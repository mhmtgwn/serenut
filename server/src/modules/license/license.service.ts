import { pgPool } from '../../config/database';
import { signPayload } from '../../crypto_helper';
import crypto from 'crypto';
import { logger } from '../../config/logger';
import { scheduleTrialLifecycleJobs } from '../../workers/billing.scheduler';
import { CommercialLifecycleService } from '../billing/commercial_lifecycle.service';

export interface LicenseActivationResult {
  status: string;
  license_info: {
    merchant_id: string;
    activation_id: string;
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
    let startedTrial: { start: Date; end: Date } | null = null;
    try {
      await client.query('BEGIN');

      // 1. Fetch active entitlement details with row lock
      const entRes = await client.query(
        `SELECT id, company_id, subscription_id, plan_id, device_limit, status, valid_until, token_version
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

      // The trial clock starts with the first successful device activation.
      // Subscription, entitlement, legacy compatibility row and device binding
      // are all part of this transaction, so a partial activation is impossible.
      if (entitlement.status === 'trial') {
        const trialSub = await client.query(
          `SELECT id, trial_started_at FROM subscriptions
           WHERE id = $1 AND company_id = $2 FOR UPDATE`,
          [entitlement.subscription_id, entitlement.company_id],
        );
        if (trialSub.rows[0] && !trialSub.rows[0].trial_started_at) {
          const trialEnd = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);
          await client.query(
            `UPDATE subscriptions
             SET trial_started_at=$1, trial_ends_at=$2,
                 current_period_start=$1, current_period_end=$2,
                 status='trialing', updated_at=NOW()
             WHERE id=$3`,
            [now, trialEnd, trialSub.rows[0].id],
          );
          await client.query(
            `UPDATE license_entitlements
             SET valid_from=$1, valid_until=$2, updated_at=NOW()
             WHERE id=$3`,
            [now, trialEnd, entitlement.id],
          );
          await client.query(
            `UPDATE licenses
             SET status='active', expires_at=$1, updated_at=NOW()
             WHERE company_id=$2 AND license_key=$3`,
            [trialEnd, entitlement.company_id, licenseKey],
          );
          entitlement.valid_until = trialEnd;
          startedTrial = { start: now, end: trialEnd };
        }
      }

      if (!entitlement.valid_until || new Date(entitlement.valid_until) < now) {
        await client.query("UPDATE license_entitlements SET status = 'expired', updated_at = NOW() WHERE id = $1", [entitlement.id]);
        throw new Error('license_expired');
      }

      // 2. Fetch or create device activation
      let devRes = await client.query(
        'SELECT id, status FROM device_activations WHERE device_hash = $1 AND company_id = $2',
        [deviceHash, entitlement.company_id]
      );

      // Clearing/reinstalling the app creates a new installation UUID. If the
      // stable hardware fingerprint matches an existing activation owned by
      // the same company, rebind that activation instead of consuming another
      // device seat or returning device_limit_exceeded.
      if (devRes.rows.length === 0 &&
          fingerprint?.machine_hash && fingerprint?.hardware_hash) {
        const physicalDevice = await client.query(
          `SELECT da.id, da.status
           FROM device_activations da
           JOIN device_fingerprints df ON df.device_id = da.id
           WHERE da.company_id = $1
             AND df.machine_hash = $2
             AND df.hardware_hash = $3
           ORDER BY da.activated_at DESC
           LIMIT 1
           FOR UPDATE OF da`,
          [entitlement.company_id, fingerprint.machine_hash, fingerprint.hardware_hash]
        );
        if (physicalDevice.rows.length > 0) {
          await client.query(
            `UPDATE device_activations
             SET device_hash = $1, status = 'active', last_seen_at = NOW(), updated_at = NOW()
             WHERE id = $2`,
            [deviceHash, physicalDevice.rows[0].id]
          );
          devRes = physicalDevice;
        }
      }

      // One-time migration for activations created by clients that predate
      // hardware fingerprints. If this entitlement has exactly one active
      // device and it has never stored a fingerprint, attach the first modern
      // client fingerprint to that legacy seat instead of falsely rejecting
      // the same installation after an app-data clear.
      if (devRes.rows.length === 0 &&
          fingerprint?.machine_hash && fingerprint?.hardware_hash) {
        const legacyDevice = await client.query(
          `SELECT da.id, da.status
           FROM device_activations da
           LEFT JOIN device_fingerprints df ON df.device_id = da.id
           WHERE da.entitlement_id = $1
             AND da.status = 'active'
             AND df.device_id IS NULL
             AND (SELECT COUNT(*) FROM device_activations active_da
                  WHERE active_da.entitlement_id = $1
                    AND active_da.status = 'active') = 1
           LIMIT 1
           FOR UPDATE OF da`,
          [entitlement.id]
        );
        if (legacyDevice.rows.length > 0) {
          await client.query(
            `UPDATE device_activations
             SET device_hash = $1, device_name = $2, platform = $3,
                 last_seen_at = NOW(), updated_at = NOW()
             WHERE id = $4`,
            [
              deviceHash,
              deviceName,
              fingerprint.platform || 'unknown',
              legacyDevice.rows[0].id,
            ]
          );
          devRes = legacyDevice;
        }
      }

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
        `INSERT INTO device_activations (id, entitlement_id, company_id, device_hash, device_name, platform, status, activated_at, last_seen_at, updated_at)
           VALUES ($1, $2, $3, $4, $5, $6, 'active', NOW(), NOW(), NOW())
           RETURNING id, device_token_version`,
          [newDevActId, entitlement.id, entitlement.company_id, deviceHash, deviceName, fingerprint?.platform || 'unknown']
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
          'UPDATE device_activations SET last_seen_at = NOW(), updated_at = NOW() WHERE id = $1',
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

      if (startedTrial && process.env.REDIS_URL) {
        try {
          const company = await pgPool.query(
            'SELECT name, email, phone FROM companies WHERE id=$1',
            [entitlement.company_id],
          );
          const contact = company.rows[0];
          if (contact?.email) {
            await scheduleTrialLifecycleJobs({
              companyId: entitlement.company_id,
              companyName: contact.name,
              email: contact.email,
              phone: contact.phone || undefined,
              trialStartDate: startedTrial.start,
              trialDays: 30,
            });
          }
        } catch (scheduleError) {
          // Hourly reconciliation remains the durable expiry safety net.
          logger.error('[LicenseService] Trial notification schedule failed', scheduleError);
        }
      }

      // 4. Build device-specific signed license payload (alphabetical keys for canonical json)
      const licenseInfo = {
        activation_id: deviceId,
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
  public static async heartbeat(
    licenseKey: string,
    deviceHash: string,
    activationId?: string,
    fingerprint?: any
  ): Promise<any> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      const res = await client.query(
        `SELECT le.id as entitlement_id, le.status as entitlement_status, le.valid_until as expires_at, le.company_id, le.plan_id, le.token_version,
                da.id as device_id, da.status as device_status, da.device_token_version
         FROM license_entitlements le
         JOIN device_activations da ON le.id = da.entitlement_id
         WHERE le.license_key = $1
           AND da.device_hash = $2
           AND ($3::varchar IS NULL OR da.id = $3)
         FOR UPDATE`,
        [licenseKey, deviceHash, activationId || null]
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
        'UPDATE device_activations SET last_seen_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP WHERE id = $1',
        [info.device_id]
      );

      await client.query('COMMIT');

      // Return device-specific signed license payload (matching activation format)
      const licenseInfo = {
        activation_id: info.device_id,
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

  /**
   * Lightweight online-presence endpoint. License validation remains a signed,
   * infrequent operation; presence is authenticated and only updates the
   * canonical activation and its runtime state.
   */
  public static async reportPresence(
    companyId: string,
    activationId: string,
    runtime?: { platform?: string; currentVersion?: string; channel?: string }
  ): Promise<void> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      const activation = await client.query(
        `SELECT id FROM device_activations
         WHERE id = $1 AND company_id = $2 AND status = 'active'
         FOR UPDATE`,
        [activationId, companyId]
      );
      if (activation.rows.length === 0) {
        throw new Error('invalid_device_activation');
      }

      await client.query(
        `UPDATE device_activations
         SET last_seen_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [activationId]
      );

      if (runtime?.platform && runtime.currentVersion) {
        await client.query(
          `INSERT INTO device_runtime_state (
             device_activation_id, company_id, platform, current_version, channel, last_reported_at, updated_at
           ) VALUES ($1, $2, $3, $4, $5, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
           ON CONFLICT (device_activation_id) DO UPDATE SET
             platform = EXCLUDED.platform,
             current_version = EXCLUDED.current_version,
             channel = EXCLUDED.channel,
             last_reported_at = CURRENT_TIMESTAMP,
             updated_at = CURRENT_TIMESTAMP`,
          [activationId, companyId, runtime.platform, runtime.currentVersion, runtime.channel || 'stable']
        );
      }
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK').catch(() => {});
      throw err;
    } finally {
      client.release();
    }
  }

  public static async revoke(licenseKey: string, actorId: string, reason: string): Promise<void> {
    if (!reason.trim()) throw new Error('status_reason_required');
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');

      const res = await client.query(
        'SELECT company_id FROM license_entitlements WHERE license_key = $1 FOR UPDATE',
        [licenseKey],
      );
      if (res.rows.length === 0) {
        throw new Error('invalid_license_key');
      }

      const companyId = res.rows[0].company_id;

      await CommercialLifecycleService.setEntitlementStatus(client, {
        companyId,
        status: 'revoked',
        actorId,
        reason,
      });

      // Block all linked devices activations
      await client.query(
        `UPDATE device_activations SET status = 'revoked', revoked_at = NOW(), revoked_by = 'sysadmin' WHERE company_id = $1`,
        [companyId]
      );

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
