import { pgPool } from '../../config/database';
import { signPayload } from '../../crypto_helper';
import crypto from 'crypto';

export interface LicenseActivationResult {
  status: string;
  license_info: {
    merchant_id: string;
    allowed_devices: string[];
    expiry_date: string;
    tier: string;
    features: string[];
  };
  signature: string;
}

export class LicenseService {
  public static async activate(licenseKey: string, deviceHash: string, deviceName: string): Promise<LicenseActivationResult> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');

      // 1. Fetch license details
      const licRes = await client.query(
        'SELECT id, company_id, tier, allowed_devices_count, status, expires_at FROM licenses WHERE license_key = $1',
        [licenseKey]
      );
      if (licRes.rows.length === 0) {
        throw new Error('invalid_license_key');
      }

      const license = licRes.rows[0];
      const now = new Date();

      if (license.status !== 'active') {
        throw new Error('license_inactive');
      }

      if (new Date(license.expires_at) < now) {
        await client.query('UPDATE licenses SET status = \'expired\' WHERE id = $1', [license.id]);
        throw new Error('license_expired');
      }

      // 2. Fetch or create device
      let devRes = await client.query(
        'SELECT id, status FROM devices WHERE device_hash = $1 AND company_id = $2',
        [deviceHash, license.company_id]
      );

      let deviceId: string;
      if (devRes.rows.length === 0) {
        const newDevId = crypto.randomUUID ? crypto.randomUUID() : `dev-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
        await client.query(
          'INSERT INTO devices (id, company_id, device_hash, name, status, last_active_at) VALUES ($1, $2, $3, $4, \'active\', CURRENT_TIMESTAMP)',
          [newDevId, license.company_id, deviceHash, deviceName]
        );
        deviceId = newDevId;
      } else {
        if (devRes.rows[0].status !== 'active') {
          throw new Error('device_blocked');
        }
        deviceId = devRes.rows[0].id;
        await client.query(
          'UPDATE devices SET last_active_at = CURRENT_TIMESTAMP WHERE id = $1',
          [deviceId]
        );
      }

      // 3. Check if device is already linked to this license
      const linkRes = await client.query(
        'SELECT 1 FROM device_licenses WHERE device_id = $1 AND license_id = $2',
        [deviceId, license.id]
      );

      if (linkRes.rows.length === 0) {
        // Verify device limit count
        const countRes = await client.query(
          'SELECT COUNT(*) as count FROM device_licenses WHERE license_id = $1',
          [license.id]
        );
        const currentDevicesCount = parseInt(countRes.rows[0].count, 10);

        if (currentDevicesCount >= license.allowed_devices_count) {
          throw new Error('device_limit_exceeded');
        }

        // Link device
        await client.query(
          'INSERT INTO device_licenses (device_id, license_id) VALUES ($1, $2)',
          [deviceId, license.id]
        );
      }

      await client.query('COMMIT');

      // 4. Build signed license payload
      const licenseInfo = {
        merchant_id: license.company_id,
        allowed_devices: ['*'],
        expiry_date: new Date(license.expires_at).toISOString(),
        tier: license.tier,
        features: license.tier === 'pro_plus' ? ['cloud_sync', 'sms_reports', 'multi_store'] : ['cloud_sync']
      };

      const payloadString = JSON.stringify(licenseInfo);
      const signature = signPayload(payloadString);

      return {
        status: 'activated',
        license_info: licenseInfo,
        signature
      };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  public static async validate(deviceHash: string): Promise<boolean> {
    const res = await pgPool.query(
      'SELECT status FROM devices WHERE device_hash = $1',
      [deviceHash]
    );
    if (res.rows.length === 0) return false;
    return res.rows[0].status === 'active';
  }

  // --- Sprint 3: Heartbeat Verification ---
  public static async heartbeat(licenseKey: string, deviceHash: string): Promise<any> {
    const res = await pgPool.query(
      `SELECT l.id as license_id, l.status as license_status, l.expires_at, l.company_id, l.tier,
              d.id as device_id, d.status as device_status
       FROM licenses l
       JOIN device_licenses dl ON l.id = dl.license_id
       JOIN devices d ON dl.device_id = d.id
       WHERE l.license_key = $1 AND d.device_hash = $2`,
      [licenseKey, deviceHash]
    );

    if (res.rows.length === 0) {
      throw new Error('invalid_association');
    }

    const info = res.rows[0];
    const now = new Date();

    if (info.license_status !== 'active') {
      throw new Error('license_suspended');
    }

    if (new Date(info.expires_at) < now) {
      throw new Error('license_expired');
    }

    if (info.device_status !== 'active') {
      throw new Error('device_blocked');
    }

    // Update last active timestamp
    await pgPool.query(
      'UPDATE devices SET last_active_at = CURRENT_TIMESTAMP WHERE id = $1',
      [info.device_id]
    );

    const licenseInfo = {
      merchant_id: info.company_id,
      allowed_devices: ['*'],
      expiry_date: new Date(info.expires_at).toISOString(),
      tier: info.tier,
      features: info.tier === 'pro_plus' ? ['cloud_sync', 'sms_reports', 'multi_store'] : ['cloud_sync']
    };

    const signature = signPayload(JSON.stringify(licenseInfo));

    return {
      status: 'valid',
      license_info: licenseInfo,
      signature
    };
  }

  // --- Sprint 3: License Renewal ---
  public static async renew(licenseKey: string, extendDays: number): Promise<any> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');

      const res = await client.query(
        'SELECT id, expires_at, status, company_id, tier FROM licenses WHERE license_key = $1',
        [licenseKey]
      );
      if (res.rows.length === 0) {
        throw new Error('invalid_license_key');
      }

      const license = res.rows[0];
      let currentExpiry = new Date(license.expires_at);
      if (currentExpiry < new Date()) {
        currentExpiry = new Date(); // If expired, start from now
      }

      const newExpiry = new Date(currentExpiry.getTime() + extendDays * 24 * 60 * 60 * 1000);

      await client.query(
        'UPDATE licenses SET expires_at = $1, status = \'active\' WHERE id = $2',
        [newExpiry, license.id]
      );

      await client.query('COMMIT');

      const licenseInfo = {
        merchant_id: license.company_id,
        allowed_devices: ['*'],
        expiry_date: newExpiry.toISOString(),
        tier: license.tier,
        features: license.tier === 'pro_plus' ? ['cloud_sync', 'sms_reports', 'multi_store'] : ['cloud_sync']
      };

      const signature = signPayload(JSON.stringify(licenseInfo));

      return {
        status: 'renewed',
        license_info: licenseInfo,
        signature
      };
    } catch (err) {
      await client.query('ROLLBACK');
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

      const res = await client.query('SELECT id FROM licenses WHERE license_key = $1', [licenseKey]);
      if (res.rows.length === 0) {
        throw new Error('invalid_license_key');
      }

      const licenseId = res.rows[0].id;

      // Block license
      await client.query('UPDATE licenses SET status = \'suspended\' WHERE id = $1', [licenseId]);

      // Block all linked devices
      await client.query(
        `UPDATE devices SET status = 'blocked' WHERE id IN (
          SELECT device_id FROM device_licenses WHERE license_id = $1
        )`,
        [licenseId]
      );

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  // --- Sprint 3: Status Details ---
  public static async getStatus(licenseKey: string): Promise<any> {
    const res = await pgPool.query(
      `SELECT id, company_id, tier, allowed_devices_count, status, expires_at, created_at 
       FROM licenses WHERE license_key = $1`,
      [licenseKey]
    );

    if (res.rows.length === 0) {
      throw new Error('invalid_license_key');
    }

    const license = res.rows[0];

    // Fetch bound devices
    const devicesRes = await pgPool.query(
      `SELECT d.id, d.name, d.device_hash, d.status, d.last_active_at
       FROM devices d
       JOIN device_licenses dl ON d.id = dl.device_id
       WHERE dl.license_id = $1`,
      [license.id]
    );

    return {
      ...license,
      bound_devices: devicesRes.rows
    };
  }
}
