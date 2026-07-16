import { pgPool } from '../../config/database';
import { signPayload } from '../../crypto_helper';
import crypto from 'crypto';

export interface LicenseActivationResult {
  status: string;
  license_info: {
    merchant_id: string;
    device_id: string;
    device_token_version: number;
    expiry_date: string;
    tier: string;
    features: string[];
    token_version: number;
  };
  signature: string;
}

export class LicenseService {
  public static async saveOrVerifyFingerprint(
    client: any, 
    deviceId: string, 
    fp: any
  ): Promise<void> {
    if (!fp) return;

    // Fetch existing fingerprint
    const fpRes = await client.query(
      'SELECT machine_hash, hardware_hash, hardware_change_count FROM device_fingerprints WHERE device_id = $1',
      [deviceId]
    );

    if (fpRes.rows.length === 0) {
      // Insert new fingerprint
      await client.query(
        `INSERT INTO device_fingerprints (
          device_id, installation_id, machine_hash, hardware_hash, 
          cpu_architecture, os_version, app_version, device_name, 
          platform, install_date, last_seen
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, CURRENT_TIMESTAMP)`,
        [
          deviceId, fp.installation_id, fp.machine_hash, fp.hardware_hash,
          fp.cpu_architecture || null, fp.os_version || null, fp.app_version || null,
          fp.device_name || null, fp.platform || null, new Date(fp.install_date)
        ]
      );
    } else {
      const existing = fpRes.rows[0];
      
      const machineChanged = existing.machine_hash !== fp.machine_hash;
      const hardwareChanged = existing.hardware_hash !== fp.hardware_hash;

      if (machineChanged || hardwareChanged) {
        const newChangeCount = (existing.hardware_change_count || 0) + 1;
        const maxAllowedChanges = Number(process.env.MAX_HARDWARE_CHANGES_TOLERANCE || 3);
        
        if (newChangeCount > maxAllowedChanges) {
          throw new Error('hardware_tampered_limit_exceeded');
        }

        // Update with new fingerprint parameters and increment count
        await client.query(
          `UPDATE device_fingerprints SET 
            machine_hash = $1, 
            hardware_hash = $2, 
            hardware_change_count = $3,
            last_seen = CURRENT_TIMESTAMP 
           WHERE device_id = $4`,
          [fp.machine_hash, fp.hardware_hash, newChangeCount, deviceId]
        );
      } else {
        // Just update last seen
        await client.query(
          'UPDATE device_fingerprints SET last_seen = CURRENT_TIMESTAMP WHERE device_id = $1',
          [deviceId]
        );
      }
    }
  }

  public static async activate(
    licenseKey: string, 
    deviceHash: string, 
    deviceName: string, 
    companyId?: string, 
    fingerprint?: any
  ): Promise<LicenseActivationResult> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');

      // 1. Fetch active entitlement details with row lock
      const entRes = await client.query(
        `SELECT id, company_id, plan_id, device_limit, status, valid_until, token_version 
         FROM license_entitlements 
         WHERE license_key = $1 AND status IN ('trial', 'active') 
         ORDER BY valid_until DESC LIMIT 1 FOR UPDATE`,
        [licenseKey]
      );
      if (entRes.rows.length === 0) {
        throw new Error('invalid_license_key');
      }

      const entitlement = entRes.rows[0];

      // Enforce company scope to prevent cross-tenant activation if companyId is provided
      if (companyId && entitlement.company_id !== companyId) {
        throw new Error('company_mismatch');
      }

      const now = new Date();

      if (new Date(entitlement.valid_until) < now) {
        await client.query("UPDATE license_entitlements SET status = 'expired', updated_at = NOW() WHERE id = $1", [entitlement.id]);
        throw new Error('license_expired');
      }

      // 2. Fetch or create device activation
      let devRes = await client.query(
        'SELECT id, status FROM device_activations WHERE device_hash = $1 AND company_id = $2',
        [deviceHash, entitlement.company_id]
      );

      let deviceId: string;
      let deviceTokenVersion = 1;
      if (devRes.rows.length === 0) {
        // Verify device limit count for this entitlement
        const countRes = await client.query(
          "SELECT COUNT(*) as count FROM device_activations WHERE entitlement_id = $1 AND status = 'active'",
          [entitlement.id]
        );
        const currentDevicesCount = parseInt(countRes.rows[0].count, 10);

        if (currentDevicesCount >= entitlement.device_limit) {
          throw new Error('device_limit_exceeded');
        }

        const newDevActId = `dact-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
        const insertRes = await client.query(
          `INSERT INTO device_activations (id, entitlement_id, company_id, device_hash, device_name, status, activated_at, last_seen_at) 
           VALUES ($1, $2, $3, $4, $5, 'active', NOW(), NOW())
           RETURNING id, device_token_version`,
          [newDevActId, entitlement.id, entitlement.company_id, deviceHash, deviceName]
        );
        deviceId = insertRes.rows[0].id;
        deviceTokenVersion = insertRes.rows[0].device_token_version;
      } else {
        if (devRes.rows[0].status !== 'active') {
          throw new Error('device_blocked');
        }
        deviceId = devRes.rows[0].id;
        // Update last seen
        await client.query(
          'UPDATE device_activations SET last_seen_at = NOW() WHERE id = $1',
          [deviceId]
        );
        
        // Retrieve current device activation record versions
        const actRes = await client.query(
          'SELECT device_token_version FROM device_activations WHERE id = $1',
          [deviceId]
        );
        deviceTokenVersion = actRes.rows[0].device_token_version;
      }

      // Save and verify fingerprint
      if (fingerprint) {
        await this.saveOrVerifyFingerprint(client, deviceId, fingerprint);
      }

      await client.query('COMMIT');

      // 3. Trigger trial start on first activation if trial_started_at is NULL
      try {
        const trialClient = await pgPool.connect();
        try {
          await trialClient.query('BEGIN');
          const subCheck = await trialClient.query(
            `SELECT id FROM subscriptions WHERE company_id = $1 AND trial_started_at IS NULL LIMIT 1`,
            [entitlement.company_id]
          );
          if (subCheck.rows.length > 0) {
            const trialStart = new Date();
            const trialEnd = new Date(trialStart.getTime() + 30 * 24 * 60 * 60 * 1000);
            await trialClient.query(
              `UPDATE subscriptions
               SET trial_started_at = $1,
                   trial_ends_at = $2,
                   current_period_start = $1,
                   current_period_end = $2,
                   status = 'trialing'
               WHERE id = $3`,
              [trialStart, trialEnd, subCheck.rows[0].id]
            );
            await trialClient.query(
              `UPDATE license_entitlements
               SET valid_from = $1, valid_until = $2, updated_at = NOW()
               WHERE id = $3 AND status = 'trial'`,
              [trialStart, trialEnd, entitlement.id]
            );
            // The response below is built from the row fetched before this update.
            // Keep it aligned so the client receives the actual 30-day trial end.
            entitlement.valid_until = trialEnd;
          }
          await trialClient.query('COMMIT');
        } catch (trialErr) {
          await trialClient.query('ROLLBACK');
          console.error('[LicenseService] Trial start update failed:', trialErr);
        } finally {
          trialClient.release();
        }
      } catch (trialConnErr) {
        console.error('[LicenseService] Trial connection error:', trialConnErr);
      }

      // 4. Build device-specific signed license payload (alphabetical keys for canonical json)
      const licenseInfo = {
        device_id: deviceHash,
        device_token_version: deviceTokenVersion,
        expiry_date: new Date(entitlement.valid_until).toISOString(),
        features: entitlement.plan_id.includes('pro') ? ['cloud_sync', 'sms_reports', 'multi_store'] : ['cloud_sync'],
        merchant_id: entitlement.company_id,
        tier: entitlement.plan_id.includes('pro') ? 'pro_plus' : 'basic',
        token_version: entitlement.token_version
      };

      const sortedPayload = Object.fromEntries(Object.entries(licenseInfo).sort());
      const canonicalPayload = JSON.stringify(sortedPayload);
      const signature = signPayload(canonicalPayload);

      return {
        status: 'activated',
        license_info: licenseInfo,
        signature
      };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }

  public static async autoActivate(
    companyId: string,
    deviceHash: string,
    deviceName: string,
    enforceAuthUser?: any,
    fingerprint?: any
  ): Promise<any> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      const keyRes = await client.query(
        `SELECT license_key FROM license_entitlements WHERE company_id = $1 AND status IN ('active', 'trial') ORDER BY valid_until DESC LIMIT 1`,
        [companyId]
      );
      if (keyRes.rows.length === 0) {
        throw new Error('no_license_found');
      }
      await client.query('COMMIT');
      return this.activate(keyRes.rows[0].license_key, deviceHash, deviceName, enforceAuthUser, fingerprint);
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }

  public static async validate(licenseKey: string, deviceHash: string): Promise<boolean> {
    const res = await pgPool.query(
      `SELECT da.status FROM device_activations da
       JOIN license_entitlements le ON da.entitlement_id = le.id
       WHERE le.license_key = $1 AND da.device_hash = $2 AND da.status = 'active' AND le.status = 'active'`,
      [licenseKey, deviceHash]
    );
    return res.rows.length > 0;
  }

  // --- Sprint 3: POS Heartbeat Route ---
  public static async heartbeat(licenseKey: string, deviceHash: string, fingerprint?: any): Promise<any> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      const res = await client.query(
        `SELECT le.id as entitlement_id, le.status as entitlement_status, le.valid_until as expires_at, le.company_id, le.plan_id, le.token_version,
                da.id as device_id, da.status as device_status, da.device_token_version
         FROM license_entitlements le
         JOIN device_activations da ON le.id = da.entitlement_id
         WHERE le.license_key = $1 AND da.device_hash = $2 FOR UPDATE`,
        [licenseKey, deviceHash]
      );

      if (res.rows.length === 0) {
        throw new Error('invalid_association');
      }

      const info = res.rows[0];
      const now = new Date();

      if (info.entitlement_status !== 'active' && info.entitlement_status !== 'trial') {
        throw new Error('license_suspended');
      }

      if (new Date(info.expires_at) < now) {
        throw new Error('license_expired');
      }

      if (info.device_status !== 'active') {
        throw new Error('device_blocked');
      }

      if (fingerprint) {
        await this.saveOrVerifyFingerprint(client, info.device_id, fingerprint);
      }

      // Update last active timestamp
      await client.query(
        'UPDATE device_activations SET last_seen_at = CURRENT_TIMESTAMP WHERE id = $1',
        [info.device_id]
      );

      await client.query('COMMIT');

      // Return device-specific signed license payload (matching activation format)
      const licenseInfo = {
        device_id: deviceHash,
        device_token_version: info.device_token_version,
        expiry_date: new Date(info.expires_at).toISOString(),
        features: info.plan_id.includes('pro') ? ['cloud_sync', 'sms_reports', 'multi_store'] : ['cloud_sync'],
        merchant_id: info.company_id,
        tier: info.plan_id.includes('pro') ? 'pro_plus' : 'basic',
        token_version: info.token_version
      };

      const sortedPayload = Object.fromEntries(Object.entries(licenseInfo).sort());
      const signature = signPayload(JSON.stringify(sortedPayload));

      return {
        status: 'valid',
        license_info: licenseInfo,
        signature
      };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }

  // --- Sprint 3: License Renewal ---
  public static async renew(licenseKey: string, extendDays: number): Promise<any> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');

      const res = await client.query(
        `SELECT id, valid_until as expires_at, status, company_id, plan_id, token_version 
         FROM license_entitlements WHERE license_key = $1 AND status IN ('trial', 'active') 
         ORDER BY valid_until DESC LIMIT 1 FOR UPDATE`,
        [licenseKey]
      );
      if (res.rows.length === 0) {
        throw new Error('invalid_license_key');
      }

      const entitlement = res.rows[0];
      let currentExpiry = new Date(entitlement.expires_at);
      if (currentExpiry < new Date()) {
        currentExpiry = new Date();
      }

      const newExpiry = new Date(currentExpiry.getTime() + extendDays * 24 * 60 * 60 * 1000);

      await client.query(
        "UPDATE license_entitlements SET valid_until = $1, status = 'active', updated_at = NOW() WHERE id = $2",
        [newExpiry, entitlement.id]
      );

      // Increment token version to force refresh
      await client.query(
        "UPDATE license_entitlements SET token_version = token_version + 1 WHERE id = $1",
        [entitlement.id]
      );

      // Sync legacy licenses table
      await client.query(
        "UPDATE licenses SET expires_at = $1, status = 'active', updated_at = NOW() WHERE company_id = $2",
        [newExpiry, entitlement.company_id]
      );

      await client.query('COMMIT');

      const licenseInfo = {
        device_id: '',
        device_token_version: 1,
        expiry_date: newExpiry.toISOString(),
        tier: entitlement.plan_id.includes('pro') ? 'pro_plus' : 'basic',
        features: entitlement.plan_id.includes('pro') ? ['cloud_sync', 'sms_reports', 'multi_store'] : ['cloud_sync'],
        merchant_id: entitlement.company_id,
        token_version: entitlement.token_version + 1
      };

      const sortedPayload = Object.fromEntries(Object.entries(licenseInfo).sort());
      const signature = signPayload(JSON.stringify(sortedPayload));

      return {
        status: 'renewed',
        license_info: licenseInfo,
        signature
      };
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }

  // --- Sprint 3: License Revocation ---
  public static async revoke(licenseKey: string): Promise<void> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');

      const res = await client.query('SELECT id, company_id FROM license_entitlements WHERE license_key = $1', [licenseKey]);
      if (res.rows.length === 0) {
        throw new Error('invalid_license_key');
      }

      const companyId = res.rows[0].company_id;

      // Block license entitlements
      await client.query("UPDATE license_entitlements SET status = 'revoked', updated_at = NOW() WHERE company_id = $1", [companyId]);

      // Block all linked devices activations
      await client.query(
        `UPDATE device_activations SET status = 'revoked', revoked_at = NOW(), revoked_by = 'sysadmin' WHERE company_id = $1`,
        [companyId]
      );

      // Sync legacy licenses table
      await client.query("UPDATE licenses SET status = 'suspended', updated_at = NOW() WHERE company_id = $1", [companyId]);

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }

  // --- Sprint 3: Status Details ---
  public static async getStatus(licenseKey: string): Promise<any> {
    const res = await pgPool.query(
      `SELECT id, company_id, plan_id as tier, device_limit as allowed_devices_count, status, valid_until as expires_at, created_at 
       FROM license_entitlements WHERE license_key = $1 ORDER BY valid_until DESC LIMIT 1`,
      [licenseKey]
    );

    if (res.rows.length === 0) {
      throw new Error('invalid_license_key');
    }

    const entitlement = res.rows[0];

    // Fetch bound devices activations
    const devicesRes = await pgPool.query(
      `SELECT da.id, da.device_name as name, da.device_hash, da.status, da.last_seen_at as last_active_at
       FROM device_activations da
       WHERE da.entitlement_id = $1`,
      [entitlement.id]
    );

    return {
      id: entitlement.id,
      company_id: entitlement.company_id,
      tier: entitlement.tier.includes('pro') ? 'pro_plus' : 'basic',
      allowed_devices_count: entitlement.allowed_devices_count,
      status: entitlement.status,
      expires_at: entitlement.expires_at,
      created_at: entitlement.created_at,
      bound_devices: devicesRes.rows
    };
  }
}
