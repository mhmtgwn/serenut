// server/src/modules/license/license.fsm.ts
// Serenut OS — License State Machine
// Blueprint: state_machine_specification.md — Section 2
// FSM: unassigned → active → expired | suspended
//      active → unassigned (deactivate)

import { pgPool } from '../../config/database';
import { logger } from '../../config/logger';
import { RealtimeBroadcastService } from '../realtime/broadcast.service';
import crypto from 'crypto';

// ── ALLOWED TRANSITIONS ───────────────────────────────────────────────────────
const LICENSE_TRANSITIONS: Record<string, string[]> = {
  unassigned: ['active', 'expired'],
  active: ['unassigned', 'expired', 'suspended'],
  expired: ['active'],
  suspended: ['active'],
};

function assertLicenseTransition(from: string, to: string): void {
  const allowed = LICENSE_TRANSITIONS[from] ?? [];
  if (!allowed.includes(to)) {
    throw new Error(
      `Invalid license FSM transition: ${from} → ${to}. Allowed: [${allowed.join(', ')}]`
    );
  }
}

// Monthly swap limit (AC 5.2, LICENSE104)
const MONTHLY_SWAP_LIMIT = 2;

export class LicenseFSM {
  /**
   * Activates a license for a device.
   * FSM: unassigned → active
   * Enforces: device limit, monthly swap limit, cross-company binding check.
   */
  static async activate(
    licenseKey: string,
    deviceHash: string,
    deviceName: string,
    companyId: string
  ): Promise<{
    status: string;
    tier: string;
    slotsAvailable: number;
    licenseId: string;
  }> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      // 1. Fetch license
      const licRes = await client.query(
        `SELECT id, company_id, tier, allowed_devices_count, fsm_state, status, expires_at
         FROM licenses WHERE license_key = $1`,
        [licenseKey]
      );

      if (licRes.rows.length === 0) throw Object.assign(new Error('LICENSE101'), { code: 'LICENSE101' });

      const license = licRes.rows[0];

      if (license.status === 'suspended' || license.fsm_state === 'suspended') {
        throw Object.assign(new Error('DEVICE502'), { code: 'DEVICE502' });
      }

      if (license.status === 'expired' || license.fsm_state === 'expired') {
        throw Object.assign(new Error('LICENSE102'), { code: 'LICENSE102' });
      }

      // 2. Cross-company binding check (AC 5.1, LICENSE105)
      if (license.company_id !== companyId) {
        throw Object.assign(new Error('LICENSE105'), { code: 'LICENSE105' });
      }

      // 3. Fetch or create device
      let devRes = await client.query(
        `SELECT id, status FROM devices WHERE device_hash = $1 AND company_id = $2`,
        [deviceHash, companyId]
      );

      let deviceId: string;
      if (devRes.rows.length === 0) {
        deviceId = crypto.randomUUID();
        await client.query(
          `INSERT INTO devices (id, company_id, device_hash, name, status, last_active_at)
           VALUES ($1, $2, $3, $4, 'active', CURRENT_TIMESTAMP)`,
          [deviceId, companyId, deviceHash, deviceName]
        );
      } else {
        if (devRes.rows[0].status === 'blocked') {
          throw Object.assign(new Error('DEVICE502'), { code: 'DEVICE502' });
        }
        deviceId = devRes.rows[0].id;
        await client.query(
          `UPDATE devices SET last_active_at = CURRENT_TIMESTAMP WHERE id = $1`,
          [deviceId]
        );
      }

      // 4. Check if already linked
      const linkRes = await client.query(
        `SELECT 1 FROM device_licenses WHERE device_id = $1 AND license_id = $2`,
        [deviceId, license.id]
      );

      if (linkRes.rows.length === 0) {
        // 5. Enforce device count limit (LICENSE103)
        const countRes = await client.query(
          `SELECT COUNT(*) as count FROM device_licenses WHERE license_id = $1`,
          [license.id]
        );
        if (parseInt(countRes.rows[0].count, 10) >= license.allowed_devices_count) {
          throw Object.assign(new Error('LICENSE103'), { code: 'LICENSE103' });
        }

        // 6. Enforce monthly swap limit (LICENSE104)
        const swapRes = await client.query(
          `SELECT COUNT(*) as count FROM device_swap_log
           WHERE license_id = $1 AND action = 'activate'
             AND performed_at >= date_trunc('month', CURRENT_TIMESTAMP)`,
          [license.id]
        );
        if (parseInt(swapRes.rows[0].count, 10) >= MONTHLY_SWAP_LIMIT) {
          throw Object.assign(new Error('LICENSE104'), { code: 'LICENSE104' });
        }

        // 7. Link device
        await client.query(
          `INSERT INTO device_licenses (device_id, license_id) VALUES ($1, $2)`,
          [deviceId, license.id]
        );

        // 8. Log swap action
        await client.query(
          `INSERT INTO device_swap_log (id, license_id, device_id, action)
           VALUES ($1, $2, $3, 'activate')`,
          [crypto.randomUUID(), license.id, deviceId]
        );
      }

      // 9. FSM: unassigned/expired → active
      if (license.fsm_state !== 'active') {
        assertLicenseTransition(license.fsm_state ?? 'unassigned', 'active');
        await client.query(
          `UPDATE licenses SET fsm_state = 'active' WHERE id = $1`,
          [license.id]
        );
      }

      const slotCountRes = await client.query(
        `SELECT COUNT(*) as count FROM device_licenses WHERE license_id = $1`,
        [license.id]
      );
      const usedSlots = parseInt(slotCountRes.rows[0].count, 10);

      await client.query('COMMIT');

      logger.info(`License activated: ${licenseKey} for device ${deviceHash} (company ${companyId})`);

      return {
        status: 'active',
        tier: license.tier,
        slotsAvailable: license.allowed_devices_count - usedSlots,
        licenseId: license.id,
      };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Deactivates a device from a license.
   * FSM: active → unassigned (if no devices remain) or stays active.
   */
  static async deactivate(
    licenseKey: string,
    deviceHash: string,
    companyId: string
  ): Promise<{ slotsAvailable: number }> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      const licRes = await client.query(
        `SELECT id, company_id, allowed_devices_count FROM licenses WHERE license_key = $1`,
        [licenseKey]
      );
      if (licRes.rows.length === 0) throw Object.assign(new Error('LICENSE101'), { code: 'LICENSE101' });

      const license = licRes.rows[0];
      if (license.company_id !== companyId) throw Object.assign(new Error('LICENSE105'), { code: 'LICENSE105' });

      const devRes = await client.query(
        `SELECT id FROM devices WHERE device_hash = $1 AND company_id = $2`,
        [deviceHash, companyId]
      );
      if (devRes.rows.length === 0) throw new Error('Device not found');

      const deviceId = devRes.rows[0].id;

      await client.query(
        `DELETE FROM device_licenses WHERE device_id = $1 AND license_id = $2`,
        [deviceId, license.id]
      );

      // Log deactivation
      await client.query(
        `INSERT INTO device_swap_log (id, license_id, device_id, action)
         VALUES ($1, $2, $3, 'deactivate')`,
        [crypto.randomUUID(), license.id, deviceId]
      );

      const slotRes = await client.query(
        `SELECT COUNT(*) as count FROM device_licenses WHERE license_id = $1`,
        [license.id]
      );
      const usedSlots = parseInt(slotRes.rows[0].count, 10);

      // If no devices remain, set fsm_state to unassigned
      if (usedSlots === 0) {
        await client.query(
          `UPDATE licenses SET fsm_state = 'unassigned' WHERE id = $1`,
          [license.id]
        );
      }

      await client.query('COMMIT');

      return { slotsAvailable: license.allowed_devices_count - usedSlots };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Suspends a license (sysadmin action — abuse/chargeback).
   * FSM: active → suspended
   * Broadcasts DEVICE502 signal to all terminals.
   */
  static async suspend(
    licenseId: string,
    reason: 'abuse' | 'chargeback' | 'manual',
    performedBy: string
  ): Promise<void> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      const res = await client.query(
        `SELECT id, company_id, fsm_state FROM licenses WHERE id = $1`,
        [licenseId]
      );
      if (res.rows.length === 0) throw new Error('License not found');

      const license = res.rows[0];
      assertLicenseTransition(license.fsm_state ?? 'active', 'suspended');

      await client.query(
        `UPDATE licenses
         SET fsm_state = 'suspended', suspended_at = CURRENT_TIMESTAMP,
             suspended_reason = $1
         WHERE id = $2`,
        [reason, licenseId]
      );

      await client.query('COMMIT');

      logger.warn(`License ${licenseId} suspended. Reason: ${reason}. By: ${performedBy}`);

      // Broadcast device lock to all terminals of this company
      RealtimeBroadcastService.publishEvent(license.company_id, 'LICENSE_CHANGED', {
        licenseId,
        status: 'suspended',
        reason,
      }).catch((err) => logger.error('Failed to broadcast license suspension:', err));
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Reinstates a suspended license (sysadmin override).
   * FSM: suspended → active
   */
  static async reinstate(licenseId: string, performedBy: string): Promise<void> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      const res = await client.query(
        `SELECT id, company_id, fsm_state FROM licenses WHERE id = $1`,
        [licenseId]
      );
      if (res.rows.length === 0) throw new Error('License not found');

      const license = res.rows[0];
      assertLicenseTransition(license.fsm_state ?? 'suspended', 'active');

      await client.query(
        `UPDATE licenses
         SET fsm_state = 'active', suspended_at = NULL, suspended_reason = NULL
         WHERE id = $1`,
        [licenseId]
      );

      await client.query('COMMIT');
      logger.info(`License ${licenseId} reinstated by ${performedBy}`);

      RealtimeBroadcastService.publishEvent(license.company_id, 'LICENSE_CHANGED', {
        licenseId,
        status: 'active',
      }).catch(() => {});
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }
}
