import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest, requireRole } from '../../middleware/auth.middleware';
import { pgPool, redisClient } from '../../config/database';
import os from 'os';
import crypto from 'crypto';
import { execSync } from 'child_process';
import { getNotificationQueue } from '../../workers/notification.worker';
import { getBillingQueue } from '../../workers/billing.scheduler';
import { enqueueNotification } from '../../workers/notification.worker';
import { getActiveWebSocketCount } from '../analytics/analytics.ws';
import { loadIyzicoConfig, IyzicoService } from '../billing/iyzico.service';
import { logger } from '../../config/logger';
import { CommercialLifecycleService } from '../billing/commercial_lifecycle.service';
import { encryptSecret } from '../../crypto_helper';

const router = Router();

// Apply auth and sysadmin validation globally
router.use(authenticateUser);
router.use(requireRole('sysadmin'));

// Helper to run database queries bypassing RLS for sysadmin
async function runBypassingRLS(sql: string, params: any[] = []) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const res = await client.query(sql, params);
    await client.query('COMMIT');
    return res;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

// Helper to write admin audit log
async function writeAdminAudit(userId: string, action: string, entity: string, entityId: string, oldValue: any = null, newValue: any = null, ipAddress: string = 'admin_panel') {
  const auditId = `aud-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
  try {
    await runBypassingRLS(
      `INSERT INTO audit_logs (id, company_id, user_id, action, entity, entity_id, old_value, new_value, ip_address)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [
        auditId,
        'serenut_cloud', // Admin platform indicator
        userId,
        action,
        entity,
        entityId,
        oldValue ? JSON.stringify(oldValue) : null,
        newValue ? JSON.stringify(newValue) : null,
        ipAddress
      ]
    );
  } catch (err) {
    console.error('Failed to write admin audit log:', err);
  }
}

// ── 1. DASHBOARD OVERVIEW ───────────────────────────────────────────────────
router.get('/dashboard', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const companiesCount = await runBypassingRLS('SELECT COUNT(*) FROM companies');
    const devicesCount = await runBypassingRLS('SELECT COUNT(*) FROM devices');
    const licensesCount = await runBypassingRLS('SELECT COUNT(*) FROM licenses');
    const trialCount = await runBypassingRLS("SELECT COUNT(*) FROM licenses WHERE tier = 'trial'");
    
    const expiringCount = await runBypassingRLS(
      "SELECT COUNT(*) FROM licenses WHERE expires_at BETWEEN NOW() AND NOW() + INTERVAL '7 days'"
    );
    
    const syncCount24h = await runBypassingRLS(
      "SELECT COUNT(*) FROM sync_queue WHERE created_at >= NOW() - INTERVAL '24 hours'"
    );

    // Dynamic Server Health
    let dbStatus = 'up';
    try {
      await pgPool.query('SELECT 1');
    } catch (_) {
      dbStatus = 'down';
    }

    const redisStatus = redisClient && redisClient.isOpen ? 'up' : 'down';
    const totalMem = os.totalmem();
    const freeMem = os.freemem();
    const usedMemPercentage = ((totalMem - freeMem) / totalMem) * 100;
    const cpuLoad = os.loadavg()[0];

    let diskUsage = 0;
    try {
      const dfOut = execSync("df -h / | awk 'NR==2 {print $5}' | sed 's/%//'").toString().trim();
      diskUsage = parseFloat(dfOut) || 0;
    } catch (_) {
      diskUsage = 0;
    }

    return res.json({
      metrics: {
        activeCompanies: parseInt(companiesCount.rows[0].count, 10),
        activePos: parseInt(devicesCount.rows[0].count, 10),
        activeLicenses: parseInt(licensesCount.rows[0].count, 10),
        trialUsers: parseInt(trialCount.rows[0].count, 10),
        expiringLicenses: parseInt(expiringCount.rows[0].count, 10),
        syncsLast24h: parseInt(syncCount24h.rows[0].count, 10),
      },
      system: {
        database: dbStatus,
        redis: redisStatus,
        cpuUsage: parseFloat(cpuLoad.toFixed(1)),
        ramUsage: parseFloat(usedMemPercentage.toFixed(1)),
        diskUsage: diskUsage,
      }
    });
  } catch (err) {
    console.error('Admin dashboard error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 2. COMPANIES ────────────────────────────────────────────────────────────
router.get('/companies', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const list = await runBypassingRLS(`
      SELECT c.*, 
             (SELECT COUNT(*) FROM stores s WHERE s.company_id = c.id) as store_count,
             (SELECT COUNT(*) FROM devices d WHERE d.company_id = c.id) as device_count,
             (SELECT expires_at FROM licenses l WHERE l.company_id = c.id ORDER BY expires_at DESC LIMIT 1) as license_expires_at
      FROM companies c 
      ORDER BY c.created_at DESC
    `);
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.get('/companies/:id', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const company = await runBypassingRLS('SELECT * FROM companies WHERE id = $1', [req.params.id]);
    if (company.rows.length === 0) {
      return res.status(404).json({ error: 'company_not_found' });
    }

    const stores = await runBypassingRLS('SELECT * FROM stores WHERE company_id = $1', [req.params.id]);
    const devices = await runBypassingRLS('SELECT * FROM devices WHERE company_id = $1', [req.params.id]);
    const licenses = await runBypassingRLS('SELECT * FROM licenses WHERE company_id = $1', [req.params.id]);
    const users = await runBypassingRLS('SELECT id, name, email, is_active, created_at FROM users WHERE company_id = $1', [req.params.id]);
    const invoices = await runBypassingRLS('SELECT * FROM invoices WHERE company_id = $1 ORDER BY due_at DESC', [req.params.id]);

    return res.json({
      company: company.rows[0],
      stores: stores.rows,
      devices: devices.rows,
      licenses: licenses.rows,
      users: users.rows,
      invoices: invoices.rows,
    });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/companies', async (req: AuthenticatedRequest, res: Response) => {
  const { name, tax_number, tax_office, phone, email, address } = req.body;
  if (!name || !tax_number) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  const id = `comp-${Date.now()}`;
  try {
    await runBypassingRLS(
      `INSERT INTO companies (id, name, tax_number, tax_office, phone, email, address, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, 'active')`,
      [id, name, tax_number, tax_office || null, phone || null, email || null, address || null]
    );

    // Auto generate seed plans and trial license for the new company
    const licenseId = `lic-${Date.now()}`;
    const licenseKey = `KEY-${Math.random().toString(36).substring(2, 10).toUpperCase()}-${Math.random().toString(36).substring(2, 10).toUpperCase()}`;
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30); // 30 days trial

    await runBypassingRLS(
      `INSERT INTO licenses (id, company_id, license_key, tier, allowed_devices_count, status, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [licenseId, id, licenseKey, 'trial', 2, 'active', expiresAt]
    );

    await writeAdminAudit(req.user!.id, 'CREATE_COMPANY', 'companies', id, null, { name, tax_number });

    return res.status(201).json({ success: true, company_id: id, license_key: licenseKey });
  } catch (err: any) {
    console.error('Create company error:', err);
    if (err.message?.includes('unique_tax_number') || err.message?.includes('tax_number')) {
      return res.status(400).json({ error: 'duplicate_tax_number', message: 'Bu vergi numarası zaten sistemde kayıtlı.' });
    }
    return res.status(500).json({ error: 'server_error' });
  }
});

router.put('/companies/:id', async (req: AuthenticatedRequest, res: Response) => {
  const { status, name, phone, email, address } = req.body;
  try {
    const original = await runBypassingRLS('SELECT * FROM companies WHERE id = $1', [req.params.id]);
    if (original.rows.length === 0) {
      return res.status(404).json({ error: 'company_not_found' });
    }

    await runBypassingRLS(
      `UPDATE companies 
       SET status = COALESCE($1, status),
           name = COALESCE($2, name),
           phone = COALESCE($3, phone),
           email = COALESCE($4, email),
           address = COALESCE($5, address),
           updated_at = NOW()
       WHERE id = $6`,
      [status || null, name || null, phone || null, email || null, address || null, req.params.id]
    );

    await writeAdminAudit(req.user!.id, 'UPDATE_COMPANY', 'companies', req.params.id, original.rows[0], { status, name }, req.ip);

    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 3. LICENSES ─────────────────────────────────────────────────────────────
router.get('/licenses', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const list = await runBypassingRLS(`
      SELECT l.*, c.name as company_name 
      FROM licenses l 
      JOIN companies c ON l.company_id = c.id 
      ORDER BY l.created_at DESC
    `);
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/licenses', async (req: AuthenticatedRequest, res: Response) => {
  const { company_id, tier, allowed_devices_count, expires_in_days } = req.body;
  if (!company_id || !tier) {
    return res.status(400).json({ error: 'missing_fields', message: 'company_id ve tier alanları zorunludur.' });
  }

  const days = expires_in_days ? parseInt(expires_in_days, 10) : 365;
  if (isNaN(days) || days <= 0) {
    return res.status(400).json({ error: 'invalid_expiry', message: 'Geçersiz lisans süresi gün değeri.' });
  }

  const limit = allowed_devices_count ? parseInt(allowed_devices_count, 10) : 1;
  if (isNaN(limit) || limit <= 0 || limit > 1000) {
    return res.status(400).json({ error: 'invalid_device_limit', message: 'Geçersiz cihaz limiti (1-1000 arası olmalıdır).' });
  }

  try {
    // 1. Verify company exists
    const company = await runBypassingRLS('SELECT id FROM companies WHERE id = $1', [company_id]);
    if (company.rows.length === 0) {
      return res.status(400).json({ error: 'company_not_found', message: 'Şirket bulunamadı.' });
    }

    const id = `lic-${Date.now()}`;
    const licenseKey = `KEY-${Math.random().toString(36).substring(2, 10).toUpperCase()}-${Math.random().toString(36).substring(2, 10).toUpperCase()}`;
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + days);

    // Resolve plan ID & limits
    let planId = 'plan-basic';
    let storeLimit = 1;
    if (tier === 'trial') {
      planId = 'plan-free';
      storeLimit = 1;
    } else if (tier === 'pro') {
      planId = 'plan-pro';
      storeLimit = 3;
    } else if (tier === 'pro_plus') {
      planId = 'plan-enterprise';
      storeLimit = 99;
    }

    const entitlementId = `ent-${Date.now()}-${Math.random().toString(36).substring(2, 10).toUpperCase()}`;

    // Write to both tables inside a transaction
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      // Insert legacy license
      await client.query(
        `INSERT INTO licenses (id, company_id, license_key, tier, allowed_devices_count, status, expires_at)
         VALUES ($1, $2, $3, $4, $5, 'active', $6)`,
        [id, company_id, licenseKey, tier, limit, expiresAt]
      );

      // Insert new entitlement
      await client.query(
        `INSERT INTO license_entitlements (id, company_id, plan_id, status, device_limit, store_limit, valid_from, valid_until, token_version, license_key, created_at, updated_at)
         VALUES ($1, $2, $3, 'active', $4, $5, NOW(), $6, 1, $7, NOW(), NOW())`,
        [entitlementId, company_id, planId, limit, storeLimit, expiresAt, licenseKey]
      );

      await client.query('COMMIT');
    } catch (txErr) {
      await client.query('ROLLBACK');
      throw txErr;
    } finally {
      client.release();
    }

    await writeAdminAudit(req.user!.id, 'CREATE_LICENSE', 'licenses', id, null, { licenseKey, tier, company_id }, req.ip);

    return res.status(201).json({ success: true, license_id: id, license_key: licenseKey });
  } catch (err) {
    console.error('Create manual license error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/licenses/:id/renew', async (req: AuthenticatedRequest, res: Response) => {
  const { additional_days } = req.body;
  const days = additional_days ? parseInt(additional_days, 10) : 365;
  if (isNaN(days) || days <= 0) {
    return res.status(400).json({ error: 'invalid_days', message: 'Geçersiz yenileme süresi gün değeri.' });
  }

  try {
    const license = await runBypassingRLS('SELECT * FROM licenses WHERE id = $1', [req.params.id]);
    if (license.rows.length === 0) {
      return res.status(404).json({ error: 'license_not_found' });
    }

    const licenseKey = license.rows[0].license_key;
    const currentExpiry = new Date(license.rows[0].expires_at);
    const newExpiry = new Date(Math.max(currentExpiry.getTime(), Date.now()));
    newExpiry.setDate(newExpiry.getDate() + days);

    // Update both tables inside transaction
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      await client.query(
        'UPDATE licenses SET expires_at = $1, status = \'active\' WHERE id = $2',
        [newExpiry, req.params.id]
      );

      await client.query(
        "UPDATE license_entitlements SET valid_until = $1, status = 'active', token_version = token_version + 1, updated_at = NOW() WHERE license_key = $2",
        [newExpiry, licenseKey]
      );

      await client.query('COMMIT');
    } catch (txErr) {
      await client.query('ROLLBACK');
      throw txErr;
    } finally {
      client.release();
    }

    await writeAdminAudit(req.user!.id, 'RENEW_LICENSE', 'licenses', req.params.id, license.rows[0], { new_expiry: newExpiry }, req.ip);

    return res.json({ success: true, new_expiry: newExpiry });
  } catch (err) {
    console.error('Renew license error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/licenses/:id/suspend', async (req: AuthenticatedRequest, res: Response) => {
  const { suspend } = req.body; // boolean
  const newStatus = suspend ? 'suspended' : 'active';
  try {
    const license = await runBypassingRLS('SELECT * FROM licenses WHERE id = $1', [req.params.id]);
    if (license.rows.length === 0) {
      return res.status(404).json({ error: 'license_not_found' });
    }

    const licenseKey = license.rows[0].license_key;

    // Update both tables inside transaction
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      await client.query(
        'UPDATE licenses SET status = $1 WHERE id = $2',
        [newStatus, req.params.id]
      );

      await client.query(
        "UPDATE license_entitlements SET status = $1, token_version = token_version + 1, updated_at = NOW() WHERE license_key = $2",
        [newStatus, licenseKey]
      );

      await client.query('COMMIT');
    } catch (txErr) {
      await client.query('ROLLBACK');
      throw txErr;
    } finally {
      client.release();
    }

    await writeAdminAudit(req.user!.id, suspend ? 'SUSPEND_LICENSE' : 'ACTIVATE_LICENSE', 'licenses', req.params.id, license.rows[0], { status: newStatus }, req.ip);

    return res.json({ success: true });
  } catch (err) {
    console.error('Suspend license error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/licenses/:id/revoke', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const license = await runBypassingRLS('SELECT * FROM licenses WHERE id = $1', [req.params.id]);
    if (license.rows.length === 0) {
      return res.status(404).json({ error: 'license_not_found' });
    }

    const licenseKey = license.rows[0].license_key;
    const companyId = license.rows[0].company_id;

    // Update licenses, license_entitlements, and device_activations inside transaction
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      await client.query(
        'UPDATE licenses SET status = \'revoked\' WHERE id = $1',
        [req.params.id]
      );

      await client.query(
        "UPDATE license_entitlements SET status = 'revoked', token_version = token_version + 1, updated_at = NOW() WHERE license_key = $1",
        [licenseKey]
      );

      await client.query(
        "UPDATE device_activations SET status = 'revoked', revoked_at = NOW(), revoked_by = 'sysadmin' WHERE company_id = $1",
        [companyId]
      );

      await client.query('COMMIT');
    } catch (txErr) {
      await client.query('ROLLBACK');
      throw txErr;
    } finally {
      client.release();
    }

    await writeAdminAudit(req.user!.id, 'REVOKE_LICENSE', 'licenses', req.params.id, license.rows[0], { status: 'revoked' }, req.ip);

    return res.json({ success: true });
  } catch (err) {
    console.error('Revoke license error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 4. DEVICES ──────────────────────────────────────────────────────────────
router.get('/devices', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const list = await runBypassingRLS(`
      SELECT d.*, c.name as company_name, s.name as store_name 
      FROM devices d 
      JOIN companies c ON d.company_id = c.id 
      LEFT JOIN stores s ON d.store_id = s.id 
      ORDER BY d.last_active_at DESC NULLS LAST
    `);
    
    // Add real-time online status helper (active in last 5 minutes)
    const formatted = list.rows.map(row => {
      const isOnline = row.last_active_at 
        ? (Date.now() - new Date(row.last_active_at).getTime()) < 5 * 60 * 1000
        : false;
      return { ...row, is_online: isOnline };
    });

    return res.json(formatted);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/devices/:id/toggle', async (req: AuthenticatedRequest, res: Response) => {
  const { action } = req.body; // 'activate' | 'disable' | 'block' | 'unblock'
  try {
    const device = await runBypassingRLS('SELECT * FROM devices WHERE id = $1', [req.params.id]);
    if (device.rows.length === 0) {
      return res.status(404).json({ error: 'device_not_found' });
    }

    const currentStatus = device.rows[0].status;
    let nextStatus: string;

    if (action === 'activate') {
      nextStatus = 'active';
    } else if (action === 'disable') {
      nextStatus = 'disabled';
    } else if (action === 'block') {
      nextStatus = 'blocked';
    } else if (action === 'unblock') {
      nextStatus = 'active';
    } else {
      // Legacy toggle behaviour: active ↔ disabled
      nextStatus = currentStatus === 'active' ? 'disabled' : 'active';
    }

    await runBypassingRLS(
      'UPDATE devices SET status = $1, updated_at = NOW() WHERE id = $2',
      [nextStatus, req.params.id]
    );

    await writeAdminAudit(req.user!.id, `DEVICE_${(action || 'TOGGLE').toUpperCase()}`, 'devices', req.params.id,
      { status: currentStatus }, { status: nextStatus });

    return res.json({ success: true, previousStatus: currentStatus, status: nextStatus });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// Device block by hardware hash (for Flutter heartbeat rejection)
router.post('/devices/block-by-hash', async (req: AuthenticatedRequest, res: Response) => {
  const { device_hash, reason } = req.body;
  if (!device_hash) return res.status(400).json({ error: 'missing_device_hash' });

  try {
    const result = await runBypassingRLS(
      "UPDATE devices SET status = 'blocked', updated_at = NOW() WHERE device_hash = $1 RETURNING id, name, company_id",
      [device_hash]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'device_not_found' });
    }
    const blocked = result.rows[0];
    await writeAdminAudit(req.user!.id, 'DEVICE_BLOCKED_BY_HASH', 'devices', blocked.id, null,
      { device_hash, reason: reason || 'Admin manual block' });
    return res.json({ success: true, blockedCount: result.rows.length, devices: result.rows });
  } catch (err) {
    console.error('Device block by hash error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 5. UPDATES (RELEASE CHANNEL) ───────────────────────────────────────────
router.get('/updates', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const list = await runBypassingRLS('SELECT * FROM app_versions ORDER BY created_at DESC');
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/updates', async (req: AuthenticatedRequest, res: Response) => {
  const { version_code, platform, download_url, sha256_hash, is_mandatory, release_notes } = req.body;
  if (!version_code || !platform || !download_url || !sha256_hash) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  const id = `ver-${Date.now()}`;
  try {
    await runBypassingRLS(
      `INSERT INTO app_versions (id, version_code, platform, download_url, sha256_hash, is_mandatory, release_notes)
       VALUES ($1, $2, $3, $4, $5, $6, $7)`,
      [id, version_code, platform, download_url, sha256_hash, is_mandatory || false, release_notes || null]
    );

    await writeAdminAudit(req.user!.id, 'PUBLISH_UPDATE', 'app_versions', id, null, { version_code, platform });

    return res.status(201).json({ success: true });
  } catch (err: any) {
    if (err.message?.includes('unique') || err.message?.includes('version_code')) {
      return res.status(400).json({ error: 'duplicate_version', message: 'Bu sürüm kodu zaten mevcut.' });
    }
    return res.status(500).json({ error: 'server_error' });
  }
});

router.delete('/updates/:id', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const original = await runBypassingRLS('SELECT * FROM app_versions WHERE id = $1', [req.params.id]);
    if (original.rows.length === 0) {
      return res.status(404).json({ error: 'version_not_found' });
    }

    await runBypassingRLS('DELETE FROM app_versions WHERE id = $1', [req.params.id]);

    await writeAdminAudit(req.user!.id, 'DELETE_UPDATE', 'app_versions', req.params.id, original.rows[0], null);

    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 6. SYNC MONITOR ─────────────────────────────────────────────────────────
router.get('/sync/monitor', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const pendingCount = await runBypassingRLS("SELECT COUNT(*) FROM sync_queue WHERE status = 'pending'");
    const failedCount = await runBypassingRLS("SELECT COUNT(*) FROM sync_queue WHERE status = 'failed'");
    const completedCount = await runBypassingRLS("SELECT COUNT(*) FROM sync_queue WHERE status = 'completed'");

    const failedJobs = await runBypassingRLS(`
      SELECT sq.*, c.name as company_name, d.name as device_name 
      FROM sync_queue sq
      JOIN companies c ON sq.company_id = c.id
      JOIN devices d ON sq.device_id = d.id
      WHERE sq.status = 'failed'
      ORDER BY sq.created_at DESC
      LIMIT 20
    `);

    return res.json({
      summary: {
        pending: parseInt(pendingCount.rows[0].count, 10),
        failed: parseInt(failedCount.rows[0].count, 10),
        completed: parseInt(completedCount.rows[0].count, 10),
      },
      failed_jobs: failedJobs.rows
    });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 7. CRASH & AUDIT LOGS ───────────────────────────────────────────────────
router.get('/crash-logs', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const list = await runBypassingRLS(`
      SELECT cl.*, c.name as company_name, d.name as device_name 
      FROM crash_logs cl 
      LEFT JOIN companies c ON cl.company_id = c.id 
      LEFT JOIN devices d ON cl.device_id = d.id 
      ORDER BY cl.created_at DESC 
      LIMIT 50
    `);
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.get('/audit-logs', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const list = await runBypassingRLS(`
      SELECT al.*, c.name as company_name, u.name as user_name 
      FROM audit_logs al 
      LEFT JOIN companies c ON al.company_id = c.id 
      LEFT JOIN users u ON al.user_id = u.id 
      ORDER BY al.created_at DESC 
      LIMIT 100
    `);
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 8. SMS LOGS & QUEUE ─────────────────────────────────────────────────────
router.get('/sms/stats', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const logs = await runBypassingRLS(`
      SELECT sl.*, c.name as company_name 
      FROM sms_logs sl 
      JOIN companies c ON sl.company_id = c.id 
      ORDER BY sl.created_at DESC 
      LIMIT 50
    `);
    
    // Aggregate sms stats
    const totalSent = await runBypassingRLS("SELECT COUNT(*) FROM sms_logs WHERE status = 'sent'");
    const totalFailed = await runBypassingRLS("SELECT COUNT(*) FROM sms_logs WHERE status = 'failed'");

    return res.json({
      summary: {
        sent: parseInt(totalSent.rows[0].count, 10),
        failed: parseInt(totalFailed.rows[0].count, 10),
        dailyQuotaUsed: parseInt(totalSent.rows[0].count, 10) + parseInt(totalFailed.rows[0].count, 10),
        maxDailyQuota: 5000
      },
      logs: logs.rows
    });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 9. TICKETS (SUPPORT DESK) ────────────────────────────────────────────────
router.get('/tickets', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const list = await runBypassingRLS(`
      SELECT t.*, c.name as company_name 
      FROM support_tickets t 
      JOIN companies c ON t.company_id = c.id 
      ORDER BY t.created_at DESC
    `);
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.get('/tickets/:id/messages', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const messages = await runBypassingRLS(
      'SELECT * FROM support_ticket_messages WHERE ticket_id = $1 ORDER BY created_at ASC',
      [req.params.id]
    );
    return res.json(messages.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/tickets/:id/reply', async (req: AuthenticatedRequest, res: Response) => {
  const { message } = req.body;
  if (!message) {
    return res.status(400).json({ error: 'missing_message' });
  }

  const id = `msg-${Date.now()}`;
  try {
    await runBypassingRLS(
      `INSERT INTO support_ticket_messages (id, ticket_id, sender_id, sender_name, message)
       VALUES ($1, $2, $3, $4, $5)`,
      [id, req.params.id, req.user!.id, 'Serenut Destek', message]
    );

    // Update ticket status to replied
    await runBypassingRLS(
      "UPDATE support_tickets SET status = 'replied', updated_at = NOW() WHERE id = $1",
      [req.params.id]
    );

    return res.status(201).json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 10. ANALYTICS ───────────────────────────────────────────────────────────
router.get('/analytics', async (req: AuthenticatedRequest, res: Response) => {
  try {
    // 1. Daily sales volumes over the past 30 days
    const salesVolume = await runBypassingRLS(`
      SELECT DATE_TRUNC('day', date) as day, SUM(amount) as total_amount
      FROM financial_transactions
      WHERE type = 'sale' AND date >= NOW() - INTERVAL '30 days'
      GROUP BY day
      ORDER BY day ASC
    `);

    // 2. License tiers breakdown
    const tiersBreakdown = await runBypassingRLS(`
      SELECT tier, COUNT(*) as count 
      FROM licenses 
      GROUP BY tier
    `);

    return res.json({
      salesTrend: salesVolume.rows.map(r => ({
        date: new Date(r.day).toLocaleDateString('tr-TR'),
        amount: parseFloat(r.total_amount)
      })),
      licenseDistribution: tiersBreakdown.rows
    });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 11. COMMERCIAL DASHBOARD (Sprint 12) ──────────────────────────────────────
router.get('/dashboard/commercial', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const totalCustomers = await runBypassingRLS('SELECT COUNT(*) FROM companies');
    const activeLicenses = await runBypassingRLS("SELECT COUNT(*) FROM licenses WHERE status = 'active'");
    const trialUsers = await runBypassingRLS("SELECT COUNT(*) FROM subscriptions WHERE status = 'trial'");
    
    const expiringLicenses = await runBypassingRLS(`
      SELECT COUNT(*) FROM licenses 
      WHERE expires_at BETWEEN NOW() AND NOW() + INTERVAL '7 days'
    `);

    const todaySignups = await runBypassingRLS(`
      SELECT COUNT(*) FROM companies 
      WHERE created_at >= DATE_TRUNC('day', NOW())
    `);

    // Monthly subscription revenue from invoices (using due_at since created_at doesn't exist)
    const monthlySales = await runBypassingRLS(`
      SELECT COALESCE(SUM(amount), 0) as total FROM invoices 
      WHERE status = 'paid' AND due_at >= NOW() - INTERVAL '30 days'
    `);

    const subStats = await runBypassingRLS(`
      SELECT status, COUNT(*) as count 
      FROM subscriptions 
      GROUP BY status
    `);

    const subReport: Record<string, number> = { active: 0, suspended: 0, trial: 0, cancelled: 0 };
    for (const row of subStats.rows) {
      if (row.status in subReport) {
        subReport[row.status] = parseInt(row.count, 10);
      }
    }

    return res.json({
      summary: {
        totalCustomers: parseInt(totalCustomers.rows[0].count, 10),
        activeLicenses: parseInt(activeLicenses.rows[0].count, 10),
        trialUsers: parseInt(trialUsers.rows[0].count, 10),
        expiringLicenses: parseInt(expiringLicenses.rows[0].count, 10),
        todaySignups: parseInt(todaySignups.rows[0].count, 10),
        monthlyRevenue: parseFloat(monthlySales.rows[0].total)
      },
      subscriptions: subReport
    });
  } catch (err) {
    console.error('Commercial dashboard error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 12. LICENSE MANAGEMENT ACTIONS (Sprint 12) ───────────────────────────────
router.post('/licenses/:id/manage', async (req: AuthenticatedRequest, res: Response) => {
  const { action, value } = req.body; // value can be days to extend, or new tier name
  if (!action) {
    return res.status(400).json({ error: 'missing_action' });
  }

  try {
    const licRes = await runBypassingRLS('SELECT * FROM licenses WHERE id = $1', [req.params.id]);
    if (licRes.rows.length === 0) {
      return res.status(404).json({ error: 'license_not_found' });
    }
    const currentLic = licRes.rows[0];

    let query = '';
    let params: any[] = [];
    let logMessage = '';

    if (action === 'activate') {
      query = "UPDATE licenses SET status = 'active', updated_at = NOW() WHERE id = $1";
      params = [req.params.id];
      logMessage = 'ACTIVATED';
    } else if (action === 'deactivate') {
      query = "UPDATE licenses SET status = 'inactive', updated_at = NOW() WHERE id = $1";
      params = [req.params.id];
      logMessage = 'DEACTIVATED';
    } else if (action === 'suspend') {
      query = "UPDATE licenses SET status = 'suspended', updated_at = NOW() WHERE id = $1";
      params = [req.params.id];
      logMessage = 'SUSPENDED';
    } else if (action === 'extend_duration' || action === 'extend_trial') {
      const days = parseInt(value || '30', 10);
      query = "UPDATE licenses SET expires_at = expires_at + ($2 || ' day')::interval, status = 'active', updated_at = NOW() WHERE id = $1";
      params = [req.params.id, days];
      logMessage = `EXTENDED_${days}_DAYS`;
    } else if (action === 'change_package') {
      const newTier = value || 'pro';
      query = "UPDATE licenses SET tier = $2, updated_at = NOW() WHERE id = $1";
      params = [req.params.id, newTier];
      logMessage = `CHANGED_PACKAGE_TO_${newTier.toUpperCase()}`;
    } else {
      return res.status(400).json({ error: 'invalid_action' });
    }

    await runBypassingRLS(query, params);
    
    // Write admin audit log
    await writeAdminAudit(req.user!.id, logMessage, 'licenses', req.params.id, currentLic, { ...currentLic, action });

    return res.json({ success: true });
  } catch (err) {
    console.error('License management action error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 13. SUPPORT TOOLS MULTI-CRITERIA SEARCH (Sprint 12) ──────────────────────
router.get('/support/search', async (req: AuthenticatedRequest, res: Response) => {
  const { q } = req.query;
  if (!q) {
    return res.status(400).json({ error: 'missing_query_parameter' });
  }

  const queryStr = `%${String(q).trim()}%`;
  try {
    // Search in companies (name, tax_number, email, phone) and licenses (license_key)
    const results = await runBypassingRLS(`
      SELECT DISTINCT c.*,
             (SELECT expires_at FROM licenses l WHERE l.company_id = c.id ORDER BY expires_at DESC LIMIT 1) as license_expires_at,
             (SELECT status FROM licenses l WHERE l.company_id = c.id ORDER BY expires_at DESC LIMIT 1) as license_status
      FROM companies c
      LEFT JOIN licenses l ON l.company_id = c.id
      WHERE c.name ILIKE $1
         OR c.tax_number ILIKE $1
         OR c.phone ILIKE $1
         OR c.email ILIKE $1
         OR l.license_key ILIKE $1
      ORDER BY c.created_at DESC
      LIMIT 50
    `, [queryStr]);

    return res.json(results.rows);
  } catch (err) {
    console.error('Support search failed:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 14. VERSION TRACKING & DISTRIBUTION (Sprint 12) ─────────────────────────
router.get('/releases/tracking', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const list = await runBypassingRLS(`
      SELECT 
        c.name as company_name, 
        d.device_name, 
        d.app_version, 
        d.last_active_at,
        d.last_sync_at,
        l.status as license_status
      FROM companies c
      JOIN devices d ON d.company_id = c.id
      LEFT JOIN licenses l ON l.company_id = c.id
      ORDER BY d.last_active_at DESC
    `);
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// Set specific target channels, tenants, license packages and phased percentage rollouts
router.post('/releases/distribute', async (req: AuthenticatedRequest, res: Response) => {
  const { version, channel, target_tenants, target_tiers, rollout_percentage } = req.body;
  if (!version || !channel) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  try {
    // Check if release version exists (using app_versions table)
    const relRes = await runBypassingRLS('SELECT * FROM app_versions WHERE version_code = $1', [version]);
    if (relRes.rows.length === 0) {
      return res.status(404).json({ error: 'release_version_not_found' });
    }

    // Set targeted rollout parameters on app_versions
    await runBypassingRLS(`
      UPDATE app_versions 
      SET 
        channel = $2,
        rollout_percentage = $3,
        updated_at = NOW()
      WHERE version_code = $1
    `, [
      version, 
      channel, 
      parseInt(rollout_percentage || '100', 10)
    ]);

    // Track targets inside update_targets table if specified
    if (target_tiers && Array.isArray(target_tiers)) {
      // First clear old target tiers for this version
      await runBypassingRLS('DELETE FROM update_targets WHERE release_id = $1 AND target_type = \'license_tier\'', [relRes.rows[0].id]);
      for (const tier of target_tiers) {
        const id = `tgt-${Date.now()}-${Math.floor(Math.random()*1000)}`;
        await runBypassingRLS(`
          INSERT INTO update_targets (id, release_id, target_type, target_value)
          VALUES ($1, $2, 'license_tier', $3)
        `, [id, relRes.rows[0].id, tier]);
      }
    }

    await writeAdminAudit(req.user!.id, 'DISTRIBUTED_RELEASE', 'app_versions', version, null, { version, channel, target_tenants, target_tiers, rollout_percentage });

    return res.json({ success: true });
  } catch (err) {
    console.error('Release target distribution error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 16. GELİR ZEKASI (Commercial Intelligence) ──────────────────────────────
router.get('/billing/intel', async (req: AuthenticatedRequest, res: Response) => {
  try {
    // Calculate Monthly Recurring Revenue (MRR)
    const mrrRes = await runBypassingRLS(`
      SELECT COALESCE(SUM(p.price), 0) as mrr
      FROM subscriptions s
      JOIN plans p ON s.plan_id = p.id
      WHERE s.status = 'active'
    `);
    const mrr = parseFloat(mrrRes.rows[0].mrr);

    // Active subscribers count
    const activeSubscribers = await runBypassingRLS(
      "SELECT COUNT(*) FROM subscriptions WHERE status = 'active'"
    );

    // Churn rate calculation
    const cancelledCountRes = await runBypassingRLS(`
      SELECT COUNT(*) FROM subscriptions
      WHERE status = 'cancelled' OR cancel_at_period_end = true
    `);
    const cancelledCount = parseInt(cancelledCountRes.rows[0].count, 10);
    const activeCount = parseInt(activeSubscribers.rows[0].count, 10);
    const totalBase = activeCount + cancelledCount;
    const churnRate = totalBase > 0 ? parseFloat(((cancelledCount / totalBase) * 100).toFixed(1)) : 0.0;

    // Failed payments (amount at risk)
    const failedPayments = await runBypassingRLS(`
      SELECT COALESCE(COUNT(*), 0) as count, COALESCE(SUM(amount), 0) as at_risk
      FROM invoices
      WHERE status = 'unpaid' AND due_at < NOW()
    `);

    // List of companies at risk (status = 'grace_period' or has unpaid past due invoices)
    const riskList = await runBypassingRLS(`
      SELECT c.id, c.name, c.email, s.status as subscription_status, s.grace_period_until,
             (SELECT COUNT(*) FROM invoices i WHERE i.company_id = c.id AND i.status = 'unpaid' AND i.due_at < NOW()) as unpaid_invoices_count,
             (SELECT COALESCE(SUM(i.amount), 0) FROM invoices i WHERE i.company_id = c.id AND i.status = 'unpaid' AND i.due_at < NOW()) as unpaid_amount
      FROM companies c
      JOIN subscriptions s ON c.id = s.company_id
      WHERE s.status = 'grace_period' 
         OR EXISTS (SELECT 1 FROM invoices i WHERE i.company_id = c.id AND i.status = 'unpaid' AND i.due_at < NOW())
      ORDER BY unpaid_amount DESC
    `);

    return res.json({
      mrr,
      arr: mrr * 12,
      activeSubscribers: activeCount,
      churnRate,
      failedPaymentsCount: parseInt(failedPayments.rows[0].count, 10),
      failedPaymentsAtRisk: parseFloat(failedPayments.rows[0].at_risk),
      riskList: riskList.rows
    });
  } catch (err) {
    console.error('Gelir zekasi query failed:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 17. TENANT LIFE-CYCLE MANAGEMENT ─────────────────────────────────────────
router.post('/companies/:id/suspend', async (req: AuthenticatedRequest, res: Response) => {
  const { suspend } = req.body;
  const newStatus = suspend ? 'suspended' : 'active';
  const isActive = !suspend;

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    // Update company status
    const compRes = await client.query('SELECT name FROM companies WHERE id = $1', [req.params.id]);
    if (compRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'company_not_found' });
    }

    await client.query(
      'UPDATE companies SET status = $1, updated_at = NOW() WHERE id = $2',
      [newStatus, req.params.id]
    );

    // Update license status
    await client.query(
      "UPDATE licenses SET status = $1, updated_at = NOW() WHERE company_id = $2 AND status != 'revoked'",
      [newStatus, req.params.id]
    );

    // Suspend all users of this company
    await client.query(
      'UPDATE users SET is_active = $1, updated_at = NOW() WHERE company_id = $2',
      [isActive, req.params.id]
    );

    // Revoke all sessions if suspending
    if (suspend) {
      await client.query(
        'UPDATE sessions SET is_revoked = true, updated_at = NOW() WHERE company_id = $1',
        [req.params.id]
      );
    }

    await client.query('COMMIT');

    await writeAdminAudit(req.user!.id, suspend ? 'SUSPEND_COMPANY' : 'UNSUSPEND_COMPANY', 'companies', req.params.id, null, { status: newStatus });

    return res.json({ success: true, status: newStatus });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Company suspend error:', err);
    return res.status(500).json({ error: 'server_error' });
  } finally {
    client.release();
  }
});

router.delete('/companies/:id', async (req: AuthenticatedRequest, res: Response) => {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    const compRes = await client.query('SELECT status FROM companies WHERE id = $1', [req.params.id]);
    if (compRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'company_not_found' });
    }

    // Soft delete/archive the company
    await client.query(
      "UPDATE companies SET status = 'archived', updated_at = NOW() WHERE id = $1",
      [req.params.id]
    );

    // Disable users and revoke sessions
    await client.query(
      'UPDATE users SET is_active = false, updated_at = NOW() WHERE company_id = $1',
      [req.params.id]
    );
    await client.query(
      'UPDATE sessions SET is_revoked = true, updated_at = NOW() WHERE company_id = $1',
      [req.params.id]
    );

    await client.query('COMMIT');

    await writeAdminAudit(req.user!.id, 'ARCHIVE_COMPANY', 'companies', req.params.id);

    return res.json({ success: true, message: 'Company archived successfully.' });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Company archive error:', err);
    return res.status(500).json({ error: 'server_error' });
  } finally {
    client.release();
  }
});

router.post('/companies/:id/restore', async (req: AuthenticatedRequest, res: Response) => {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    const compRes = await client.query('SELECT name FROM companies WHERE id = $1', [req.params.id]);
    if (compRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'company_not_found' });
    }

    await client.query(
      "UPDATE companies SET status = 'active', updated_at = NOW() WHERE id = $1",
      [req.params.id]
    );

    await client.query(
      "UPDATE licenses SET status = 'active', updated_at = NOW() WHERE company_id = $1 AND status = 'suspended'",
      [req.params.id]
    );

    await client.query(
      'UPDATE users SET is_active = true, updated_at = NOW() WHERE company_id = $1',
      [req.params.id]
    );

    await client.query('COMMIT');

    await writeAdminAudit(req.user!.id, 'RESTORE_COMPANY', 'companies', req.params.id);

    return res.json({ success: true, message: 'Company restored successfully.' });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Company restore error:', err);
    return res.status(500).json({ error: 'server_error' });
  } finally {
    client.release();
  }
});

// ── 18. CIHAZ DEGISTIRME (Device Swap) ────────────────────────────────────────
router.post('/devices/swap', async (req: AuthenticatedRequest, res: Response) => {
  const { company_id, old_device_id, new_device_hash, new_device_name } = req.body;

  if (!company_id || !old_device_id || !new_device_hash || !new_device_name) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    // 1. Verify old device exists and belongs to the company
    const deviceRes = await client.query(
      'SELECT * FROM devices WHERE id = $1 AND company_id = $2',
      [old_device_id, company_id]
    );
    if (deviceRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'device_not_found', message: 'Eski cihaz kaydı bulunamadı.' });
    }

    const oldDevice = deviceRes.rows[0];

    // 2. Perform the swap
    await client.query(
      `UPDATE devices 
       SET device_hash = $1, name = $2, last_active_at = NULL, last_sync_at = NULL, updated_at = NOW()
       WHERE id = $3`,
      [new_device_hash, new_device_name, old_device_id]
    );

    await client.query('COMMIT');

    // 3. Write Admin Audit Log
    await writeAdminAudit(req.user!.id, 'DEVICE_SWAP', 'devices', old_device_id, oldDevice, {
      id: old_device_id,
      company_id,
      device_hash: new_device_hash,
      name: new_device_name,
    });

    // 4. Send Email Notification to company
    const compRes = await runBypassingRLS('SELECT email, name FROM companies WHERE id = $1', [company_id]);
    if (compRes.rows.length > 0 && compRes.rows[0].email) {
      await enqueueNotification({
        notification_id: `device-swap-notify-${Date.now()}`,
        company_id,
        channel: 'email',
        recipient: compRes.rows[0].email,
        title: 'Cihaz Değişikliği Bildirimi',
        body: `Sayın Yetkili,<br/><br/>Hesabınız altındaki <strong>${oldDevice.name}</strong> cihazı, sistem yöneticisi tarafından yeni bir donanımla değiştirilmiştir.<br/>Yeni Cihaz Adı: <strong>${new_device_name}</strong><br/>Yeni Donanım Kimliği: <strong>${new_device_hash}</strong><br/><br/>Bilginiz dışında bir işlem ise lütfen acilen destek ekibimizle iletişime geçin.`,
      });
    }

    return res.json({ success: true, message: 'Cihaz başarıyla değiştirildi.' });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Device swap error:', err);
    return res.status(500).json({ error: 'server_error' });
  } finally {
    client.release();
  }
});

// ── 19. MANUEL AKTIVASYON (Offline Signature QR) ──────────────────────────────
router.post('/licenses/:id/offline-activation', async (req: AuthenticatedRequest, res: Response) => {
  const { device_hash } = req.body;

  if (!device_hash) {
    return res.status(400).json({ error: 'missing_device_hash' });
  }

  try {
    const licRes = await runBypassingRLS(
      "SELECT * FROM licenses WHERE id = $1 AND status = 'active'",
      [req.params.id]
    );

    if (licRes.rows.length === 0) {
      return res.status(404).json({ error: 'license_not_found_or_inactive' });
    }

    const license = licRes.rows[0];

    // Compute activation expiration (match license expires_at)
    const expiresAtMs = new Date(license.expires_at).getTime();

    // Create a plain token payload to sign
    const payload = {
      license_key: license.license_key,
      company_id: license.company_id,
      device_hash: device_hash,
      tier: license.tier,
      expires_at: expiresAtMs,
      allowed_devices: license.allowed_devices_count,
    };

    const secret = process.env.JWT_SECRET;
    if (!secret) {
      if (process.env.NODE_ENV === 'production') {
        logger.error('JWT_SECRET is missing in production! Blocking license activation signing.');
        return res.status(500).json({ error: 'server_error', message: 'Lisans imzalama anahtarı eksik (JWT_SECRET).' });
      }
    }
    const signSecret = secret || 'fallback-activation-secret-key-2026';
    const dataToSign = `${payload.license_key}|${payload.company_id}|${payload.device_hash}|${payload.tier}|${payload.expires_at}`;
    
    const signature = crypto
      .createHmac('sha256', signSecret)
      .update(dataToSign)
      .digest('hex');

    const qrData = JSON.stringify({
      ...payload,
      sig: signature,
    });

    // Write admin audit log
    await writeAdminAudit(req.user!.id, 'GENERATE_OFFLINE_ACTIVATION', 'licenses', license.id, null, payload);

    return res.json({
      success: true,
      license_key: license.license_key,
      qr_data: qrData,
    });
  } catch (err) {
    console.error('Offline activation generation error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 20. TOPLU LISANS URETIMI (Bulk Licenses) ──────────────────────────────────
router.post('/licenses/bulk', async (req: AuthenticatedRequest, res: Response) => {
  const { company_id, count, tier, allowed_devices_count, expires_in_days } = req.body;

  if (!company_id || !count || !tier) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  const bulkCount = parseInt(count, 10);
  if (isNaN(bulkCount) || bulkCount < 1 || bulkCount > 100) {
    return res.status(400).json({ error: 'invalid_count', message: 'Üretilecek lisans adedi 1 ile 100 arasında olmalıdır.' });
  }

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    const generatedLicenses: string[] = [];
    const days = expires_in_days ? parseInt(expires_in_days, 10) : 365;

    for (let i = 0; i < bulkCount; i++) {
      const id = `lic-bulk-${crypto.randomUUID()}`;
      const licenseKey = `KEY-${crypto.randomBytes(4).toString('hex').toUpperCase()}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
      
      const expiresAt = new Date();
      expiresAt.setDate(expiresAt.getDate() + days);

      await client.query(
        `INSERT INTO licenses (id, company_id, license_key, tier, allowed_devices_count, status, expires_at)
         VALUES ($1, $2, $3, $4, $5, 'active', $6)`,
        [id, company_id, licenseKey, tier, allowed_devices_count || 1, expiresAt]
      );

      generatedLicenses.push(licenseKey);
    }

    await client.query('COMMIT');

    await writeAdminAudit(req.user!.id, 'CREATE_BULK_LICENSES', 'licenses', company_id, null, { count: bulkCount, tier });

    return res.status(201).json({
      success: true,
      count: bulkCount,
      licenses: generatedLicenses,
    });
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Bulk license creation failed:', err);
    return res.status(500).json({ error: 'server_error' });
  } finally {
    client.release();
  }
});

// ── 21. CANLI SİSTEM MONITORING ──────────────────────────────────────────────
router.get('/monitoring/live', async (req: AuthenticatedRequest, res: Response) => {
  try {
    // 1. Dynamic Server Health
    let dbStatus = 'up';
    let pgLatency = 0;
    try {
      const start = Date.now();
      await pgPool.query('SELECT 1');
      pgLatency = Date.now() - start;
    } catch (_) {
      dbStatus = 'down';
    }

    const redisStatus = redisClient && redisClient.isOpen ? 'up' : 'down';
    
    // CPU usage & memory
    const totalMem = os.totalmem();
    const freeMem = os.freemem();
    const usedMemPercentage = ((totalMem - freeMem) / totalMem) * 100;
    const cpuLoad = os.loadavg()[0];

    // Disk usage (mock fallback)
    let diskUsage = 42.1;

    // 2. BullMQ details
    let notificationQueueJobs = { active: 0, waiting: 0, failed: 0 };
    let billingQueueJobs = { active: 0, waiting: 0, failed: 0 };

    try {
      const notifQueue = getNotificationQueue();
      const jobCounts = await notifQueue.getJobCounts('active', 'waiting', 'failed');
      notificationQueueJobs = {
        active: jobCounts.active || 0,
        waiting: jobCounts.waiting || 0,
        failed: jobCounts.failed || 0
      };

      const billQueue = getBillingQueue();
      const billCounts = await billQueue.getJobCounts('active', 'waiting', 'failed');
      billingQueueJobs = {
        active: billCounts.active || 0,
        waiting: billCounts.waiting || 0,
        failed: billCounts.failed || 0
      };
    } catch (qErr) {
      console.warn('Queue counts query failed:', qErr);
    }

    // 3. Active WebSocket Connections
    const activeWsCount = getActiveWebSocketCount();

    // 4. Incident alerts (SEV-1 & SEV-2 counts)
    const alertRes = await runBypassingRLS(`
      SELECT COUNT(*) as count 
      FROM system_incidents 
      WHERE status = 'open' AND severity IN ('SEV-1', 'SEV-2')
    `);
    const activeAlerts = parseInt(alertRes.rows[0].count || '0', 10);

    return res.json({
      timestamp: new Date().toISOString(),
      system: {
        database: dbStatus,
        databaseLatencyMs: pgLatency,
        redis: redisStatus,
        cpuUsage: parseFloat(cpuLoad.toFixed(1)),
        ramUsage: parseFloat(usedMemPercentage.toFixed(1)),
        diskUsage: diskUsage,
      },
      queues: {
        notifications: notificationQueueJobs,
        billing: billingQueueJobs,
      },
      websockets: {
        activeConnections: activeWsCount,
      },
      alerts: {
        activeAlerts,
      }
    });
  } catch (err) {
    console.error('Monitoring query error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 22. OLAY MERKEZI (Incident Manager) ───────────────────────────────────────
router.get('/incidents', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const list = await runBypassingRLS(`
      SELECT i.*, c.name as company_name 
      FROM system_incidents i
      LEFT JOIN companies c ON i.company_id = c.id
      ORDER BY i.created_at DESC
      LIMIT 100
    `);
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/incidents', async (req: AuthenticatedRequest, res: Response) => {
  const { company_id, severity, title, description } = req.body;

  if (!severity || !title || !description) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  const id = `inc-${crypto.randomUUID()}`;
  try {
    await runBypassingRLS(`
      INSERT INTO system_incidents (id, company_id, severity, title, description, status, created_at)
      VALUES ($1, $2, $3, $4, $5, 'open', NOW())`,
      [id, company_id || null, severity, title, description]
    );

    // Alert routing depending on severity
    const alertTitle = `[Incident] ${title}`;
    const alertMsg = `[${severity}] ${description}`;

    try {
      const { sendSystemAlert } = require('../../../devops/alert-manager');

      // Webhook routing (Discord/Slack) for SEV-1, SEV-2, SEV-4
      if (severity === 'SEV-1' || severity === 'SEV-2' || severity === 'SEV-4') {
        await sendSystemAlert({
          title: alertTitle,
          severity,
          message: alertMsg,
          details: { company_id, incident_id: id }
        });
      }

      // SMS routing (Netgsm) for SEV-1, SEV-2
      if (severity === 'SEV-1' || severity === 'SEV-2') {
        await enqueueNotification({
          notification_id: `notif-${crypto.randomUUID()}`,
          company_id: company_id || 'serenut_cloud',
          channel: 'sms',
          recipient: process.env.ADMIN_ALERT_PHONE || '+905555555555',
          title: alertTitle,
          body: alertMsg
        });
      }

      // Email routing (Postmark) for SEV-2, SEV-3
      if (severity === 'SEV-2' || severity === 'SEV-3') {
        await enqueueNotification({
          notification_id: `notif-${crypto.randomUUID()}`,
          company_id: company_id || 'serenut_cloud',
          channel: 'email',
          recipient: process.env.ADMIN_ALERT_EMAIL || 'admin@serenut.com',
          title: alertTitle,
          body: alertMsg
        });
      }
    } catch (alertErr) {
      console.error('Failed to dispatch alert notifications:', alertErr);
    }

    return res.status(201).json({ success: true, incident_id: id });
  } catch (err) {
    console.error('Incident create failed:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/incidents/:id/assign', async (req: AuthenticatedRequest, res: Response) => {
  const { assignee_id } = req.body;

  try {
    const inc = await runBypassingRLS('SELECT * FROM system_incidents WHERE id = $1', [req.params.id]);
    if (inc.rows.length === 0) {
      return res.status(404).json({ error: 'incident_not_found' });
    }

    await runBypassingRLS(
      "UPDATE system_incidents SET assignee = $1, status = 'assigned', updated_at = NOW() WHERE id = $2",
      [assignee_id || req.user!.id, req.params.id]
    );

    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/incidents/:id/resolve', async (req: AuthenticatedRequest, res: Response) => {
  const { notes } = req.body;

  try {
    const inc = await runBypassingRLS('SELECT * FROM system_incidents WHERE id = $1', [req.params.id]);
    if (inc.rows.length === 0) {
      return res.status(404).json({ error: 'incident_not_found' });
    }

    await runBypassingRLS(
      "UPDATE system_incidents SET status = 'resolved', resolved_at = NOW(), resolved_notes = $1, updated_at = NOW() WHERE id = $2",
      [notes || 'Çözüldü.', req.params.id]
    );

    return res.json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 23. GUVENLIK MERKEZI (Security Ban & Logouts) ─────────────────────────────
router.post('/security/ban-ip', async (req: AuthenticatedRequest, res: Response) => {
  const { ip, reason } = req.body;

  if (!ip || !reason) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  try {
    await runBypassingRLS(
      `INSERT INTO ip_blacklist (ip, reason, banned_by)
       VALUES ($1, $2, $3)
       ON CONFLICT (ip) DO UPDATE SET reason = EXCLUDED.reason`,
      [ip, reason, req.user!.id]
    );

    await writeAdminAudit(req.user!.id, 'BAN_IP', 'security', ip, null, { reason }, req.ip);

    return res.json({ success: true, message: `IP ${ip} banned.` });
  } catch (err) {
    console.error('IP ban error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.get('/security/blacklist', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const list = await runBypassingRLS('SELECT * FROM ip_blacklist ORDER BY created_at DESC');
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.delete('/security/ban-ip/:ip', async (req: AuthenticatedRequest, res: Response) => {
  try {
    await runBypassingRLS('DELETE FROM ip_blacklist WHERE ip = $1', [req.params.ip]);
    await writeAdminAudit(req.user!.id, 'UNBAN_IP', 'security', req.params.ip, null, null, req.ip);

    return res.json({ success: true, message: `IP ${req.params.ip} unbanned.` });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/security/users/:id/force-logout', async (req: AuthenticatedRequest, res: Response) => {
  try {
    await runBypassingRLS(
      'UPDATE sessions SET is_revoked = true, updated_at = NOW() WHERE user_id = $1',
      [req.params.id]
    );

    await writeAdminAudit(req.user!.id, 'FORCE_LOGOUT_USER', 'users', req.params.id);

    return res.json({ success: true, message: 'Sessions revoked successfully.' });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 24. DESTEK BILETI IC NOTLARI (Internal notes) ──────────────────────────
router.get('/tickets/:id/notes', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const notes = await runBypassingRLS(
      'SELECT * FROM ticket_internal_notes WHERE ticket_id = $1 ORDER BY created_at ASC',
      [req.params.id]
    );
    return res.json(notes.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/tickets/:id/notes', async (req: AuthenticatedRequest, res: Response) => {
  const { content } = req.body;

  if (!content) {
    return res.status(400).json({ error: 'missing_content' });
  }

  const id = `note-${crypto.randomUUID()}`;
  try {
    await runBypassingRLS(`
      INSERT INTO ticket_internal_notes (id, ticket_id, author_id, author_name, content)
      VALUES ($1, $2, $3, $4, $5)`,
      [id, req.params.id, req.user!.id, req.user!.name || 'Destek Yöneticisi', content]
    );

    return res.status(201).json({ success: true, note_id: id });
  } catch (err) {
    console.error('Failed to save ticket note:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── FAZ 3 — SPRINT 3.1: FINANCIAL KPIs & REVENUE INTELLIGENCE ──────────────

// [ADMIN-1] Revenue KPIs: MRR / ARR / Churn / Failed Payments — Redis cached 30s
router.get('/dashboard/revenue', async (req: AuthenticatedRequest, res: Response) => {
  const cacheKey = 'admin:dashboard:revenue';
  try {
    if (redisClient && redisClient.isOpen) {
      const cached = await redisClient.get(cacheKey);
      if (cached) {
        return res.json({ ...JSON.parse(cached), cached: true });
      }
    }

    // MRR = sum of active subscription plan prices
    const mrrRes = await runBypassingRLS(`
      SELECT COALESCE(SUM(p.price), 0) AS mrr
      FROM subscriptions s
      JOIN plans p ON s.plan_id = p.id
      WHERE s.status = 'active'
    `);
    const mrr = parseFloat(mrrRes.rows[0].mrr);

    // Revenue Month-to-Date from paid invoices
    const mtdRes = await runBypassingRLS(`
      SELECT COALESCE(SUM(amount), 0) AS mtd
      FROM invoices
      WHERE status = 'paid'
        AND due_at >= DATE_TRUNC('month', NOW())
    `);
    const revenueMtd = parseFloat(mtdRes.rows[0].mtd);

    // Failed payments count + amount at risk
    const failedRes = await runBypassingRLS(`
      SELECT COALESCE(COUNT(*), 0) AS count,
             COALESCE(SUM(amount), 0) AS at_risk
      FROM invoices
      WHERE status = 'unpaid' AND due_at < NOW()
    `);
    const failedPaymentsCount = parseInt(failedRes.rows[0].count, 10);
    const failedPaymentsAtRisk = parseFloat(failedRes.rows[0].at_risk);

    // Churn rate = cancelled / (active + cancelled)
    const churnRes = await runBypassingRLS(`
      SELECT
        COUNT(*) FILTER (WHERE status = 'active') AS active_count,
        COUNT(*) FILTER (WHERE status = 'cancelled' OR cancel_at_period_end = true) AS cancelled_count
      FROM subscriptions
    `);
    const activeCount = parseInt(churnRes.rows[0].active_count, 10);
    const cancelledCount = parseInt(churnRes.rows[0].cancelled_count, 10);
    const totalBase = activeCount + cancelledCount;
    const churnRate = totalBase > 0 ? parseFloat(((cancelledCount / totalBase) * 100).toFixed(2)) : 0;

    // Trial count
    const trialRes = await runBypassingRLS(`SELECT COUNT(*) FROM subscriptions WHERE status = 'trial'`);
    const trialCount = parseInt(trialRes.rows[0].count, 10);

    const payload = {
      mrr,
      arr: parseFloat((mrr * 12).toFixed(2)),
      revenueMtd,
      failedPaymentsCount,
      failedPaymentsAtRisk,
      activeSubscriptions: activeCount,
      trialSubscriptions: trialCount,
      churnRate,
      computedAt: new Date().toISOString()
    };

    if (redisClient && redisClient.isOpen) {
      await redisClient.setEx(cacheKey, 30, JSON.stringify(payload));
    }

    return res.json({ ...payload, cached: false });
  } catch (err) {
    console.error('Revenue dashboard error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// [ADMIN-2] Infrastructure metrics — CPU / RAM / Disk / DB / Redis / Uptime
router.get('/dashboard/infrastructure', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const totalMem = os.totalmem();
    const freeMem = os.freemem();
    const usedMemPercentage = parseFloat(((totalMem - freeMem) / totalMem * 100).toFixed(1));
    const cpuLoad1m = parseFloat(os.loadavg()[0].toFixed(2));
    const uptimeSeconds = Math.floor(os.uptime());

    // DB health
    let dbStatus = 'up';
    let dbLatencyMs = 0;
    try {
      const t0 = Date.now();
      await pgPool.query('SELECT 1');
      dbLatencyMs = Date.now() - t0;
    } catch (_) {
      dbStatus = 'down';
    }

    // Redis health
    const redisStatus = redisClient && redisClient.isOpen ? 'up' : 'down';

    return res.json({
      cpu: { loadAvg1m: cpuLoad1m, cores: os.cpus().length },
      memory: {
        totalMb: Math.round(totalMem / 1024 / 1024),
        freeMb: Math.round(freeMem / 1024 / 1024),
        usedPercent: usedMemPercentage
      },
      uptime: { seconds: uptimeSeconds, human: formatUptime(uptimeSeconds) },
      database: { status: dbStatus, latencyMs: dbLatencyMs },
      redis: { status: redisStatus },
      platform: { os: os.platform(), nodeVersion: process.version }
    });
  } catch (err) {
    console.error('Infrastructure metrics error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

function formatUptime(seconds: number): string {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  return `${d}d ${h}h ${m}m`;
}

// [ADMIN-3] Queue health — BullMQ bildirim + billing kuyruğu iş sayıları
router.get('/dashboard/queue-health', async (req: AuthenticatedRequest, res: Response) => {
  try {
    let notificationQueue: any = null;
    let billingQueue: any = null;
    try { notificationQueue = getNotificationQueue(); } catch (_) {}
    try { billingQueue = getBillingQueue(); } catch (_) {}

    async function getQueueCounts(q: any) {
      if (!q) return { waiting: 0, active: 0, completed: 0, failed: 0, delayed: 0 };
      try {
        const [waiting, active, completed, failed, delayed] = await Promise.all([
          q.getWaitingCount(),
          q.getActiveCount(),
          q.getCompletedCount(),
          q.getFailedCount(),
          q.getDelayedCount()
        ]);
        return { waiting, active, completed, failed, delayed };
      } catch (_) {
        return { waiting: 0, active: 0, completed: 0, failed: 0, delayed: 0, error: 'unavailable' };
      }
    }

    const [notifCounts, billCounts] = await Promise.all([
      getQueueCounts(notificationQueue),
      getQueueCounts(billingQueue)
    ]);

    const activeWsCount = (() => {
      try { return getActiveWebSocketCount(); } catch (_) { return 0; }
    })();

    return res.json({
      notification: notifCounts,
      billing: billCounts,
      activeWebSocketConnections: activeWsCount,
      checkedAt: new Date().toISOString()
    });
  } catch (err) {
    console.error('Queue health error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// [ADMIN-6] Audit log CSV export — tarih aralığı filtreli
router.get('/audit-logs/export', async (req: AuthenticatedRequest, res: Response) => {
  const { from, to } = req.query as { from?: string; to?: string };

  try {
    let sql = `
      SELECT al.id, al.company_id, c.name AS company_name,
             al.user_id, u.name AS user_name,
             al.action, al.entity, al.entity_id,
             al.old_value, al.new_value, al.ip_address, al.created_at
      FROM audit_logs al
      LEFT JOIN companies c ON al.company_id = c.id
      LEFT JOIN users u ON al.user_id = u.id
    `;
    const params: any[] = [];

    const conditions: string[] = [];
    if (from) {
      params.push(from);
      conditions.push(`al.created_at >= $${params.length}`);
    }
    if (to) {
      params.push(to);
      conditions.push(`al.created_at <= $${params.length}`);
    }
    if (conditions.length > 0) {
      sql += ` WHERE ${conditions.join(' AND ')}`;
    }
    sql += ' ORDER BY al.created_at DESC LIMIT 10000';

    const result = await runBypassingRLS(sql, params);

    // Build CSV
    const headers = ['id', 'company_id', 'company_name', 'user_id', 'user_name', 'action', 'entity', 'entity_id', 'old_value', 'new_value', 'ip_address', 'created_at'];
    const csvLines = [headers.join(',')];
    for (const row of result.rows) {
      const line = headers.map(h => {
        const val = row[h] ?? '';
        const str = String(val).replace(/"/g, '""');
        return str.includes(',') || str.includes('"') || str.includes('\n') ? `"${str}"` : str;
      }).join(',');
      csvLines.push(line);
    }

    const csvContent = csvLines.join('\n');
    res.setHeader('Content-Type', 'text/csv; charset=utf-8');
    res.setHeader('Content-Disposition', `attachment; filename="audit_logs_${Date.now()}.csv"`);
    return res.send(csvContent);
  } catch (err) {
    console.error('Audit log export error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// [ADMIN-6-retention] Manually trigger audit log archival (admin action)
router.post('/audit-logs/archive', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const result = await runBypassingRLS('SELECT archive_old_audit_logs() AS archived_count');
    const archivedCount = parseInt(result.rows[0].archived_count, 10);
    await writeAdminAudit(req.user!.id, 'AUDIT_ARCHIVE', 'audit_logs', 'retention-job', null, { archivedCount });
    return res.json({ success: true, archivedCount });
  } catch (err) {
    console.error('Audit archival error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── FAZ 3 — SPRINT 3.2: TENANT OPERATIONS & SUPPORT WORKFLOW ──────────────

// [ADMIN-7] Tenant full onboarding — firma + lisans + kullanıcı + email
router.post('/companies/:id/onboard', async (req: AuthenticatedRequest, res: Response) => {
  const { licenseKey, tier, allowedDevices, durationDays, ownerEmail, ownerName, ownerPassword } = req.body;

  if (!licenseKey || !ownerEmail || !ownerName || !ownerPassword) {
    return res.status(400).json({ error: 'missing_required_fields' });
  }

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    // Verify company exists
    const compRes = await client.query('SELECT * FROM companies WHERE id = $1', [req.params.id]);
    if (compRes.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: 'company_not_found' });
    }
    const company = compRes.rows[0];

    // Create license
    const licId = `lic-${crypto.randomUUID()}`;
    const expiresAt = new Date(Date.now() + (durationDays || 30) * 24 * 60 * 60 * 1000);
    await client.query(`
      INSERT INTO licenses (id, company_id, license_key, tier, allowed_devices_count, status, expires_at)
      VALUES ($1, $2, $3, $4, $5, 'active', $6)
    `, [licId, req.params.id, licenseKey, tier || 'pro', allowedDevices || 1, expiresAt]);

    // Create owner user
    const bcrypt = require('bcrypt');
    const passwordHash = await bcrypt.hash(ownerPassword, 10);
    const userId = `user-${crypto.randomUUID()}`;
    await client.query(`
      INSERT INTO users (id, company_id, name, email, password_hash, is_active)
      VALUES ($1, $2, $3, $4, $5, true)
    `, [userId, req.params.id, ownerName, ownerEmail, passwordHash]);

    // Assign owner role if roles table exists
    try {
      const roleRes = await client.query("SELECT id FROM roles WHERE name = 'owner' LIMIT 1");
      if (roleRes.rows.length > 0) {
        await client.query(
          'INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2) ON CONFLICT DO NOTHING',
          [userId, roleRes.rows[0].id]
        );
      }
    } catch (_) {}

    await client.query('COMMIT');

    // Enqueue welcome email notification (non-blocking)
    try {
      await enqueueNotification({
        notification_id: `notif-${crypto.randomUUID()}`,
        company_id: req.params.id,
        channel: 'email',
        recipient: ownerEmail,
        title: `${company.name} - Serenut OS Hesabınız Hazır`,
        body: `Merhaba ${ownerName}, hesabınız oluşturulmuştur. Lisans anahtarınız: ${licenseKey}. Başarılar dileriz!`
      });
    } catch (_) {}

    await writeAdminAudit(req.user!.id, 'TENANT_ONBOARDED', 'companies', req.params.id, null, {
      licenseKey, ownerEmail, tier, allowedDevices
    });

    return res.status(201).json({
      success: true,
      companyId: req.params.id,
      licenseId: licId,
      userId,
      licenseKey,
      expiresAt
    });
  } catch (err: any) {
    await client.query('ROLLBACK');
    console.error('Tenant onboarding failed:', err);
    if (err.code === '23505') return res.status(409).json({ error: 'duplicate_entry', detail: err.detail });
    return res.status(500).json({ error: 'server_error' });
  } finally {
    client.release();
  }
});

// [ADMIN-11] SLA escalation — destek bileti SLA aşımı kontrolü + eskalasyon bildirimi
router.post('/tickets/:id/sla-escalate', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const ticketRes = await runBypassingRLS(`
      SELECT t.*, c.name AS company_name, c.email AS company_email
      FROM support_tickets t
      LEFT JOIN companies c ON t.company_id = c.id
      WHERE t.id = $1
    `, [req.params.id]);

    if (ticketRes.rows.length === 0) {
      return res.status(404).json({ error: 'ticket_not_found' });
    }

    const ticket = ticketRes.rows[0];

    // SLA thresholds (hours) by priority
    const slaHours: Record<string, number> = { urgent: 4, high: 8, medium: 24, low: 72 };
    const threshold = slaHours[ticket.priority] || 24;
    const createdAt = new Date(ticket.created_at);
    const hoursElapsed = (Date.now() - createdAt.getTime()) / 3600000;
    const breached = hoursElapsed > threshold;

    if (breached && ticket.status !== 'resolved') {
      // Update ticket priority escalation marker
      await runBypassingRLS(`
        UPDATE support_tickets
        SET priority = CASE WHEN priority = 'low' THEN 'medium'
                            WHEN priority = 'medium' THEN 'high'
                            WHEN priority = 'high' THEN 'urgent'
                            ELSE priority END,
            updated_at = NOW()
        WHERE id = $1
      `, [req.params.id]);

      // Enqueue admin alert notification
      try {
        await enqueueNotification({
          notification_id: `notif-${crypto.randomUUID()}`,
          company_id: ticket.company_id,
          channel: 'email',
          recipient: ticket.company_email || 'support@serenut.com',
          title: `SLA İhlali: Destek Bileti #${req.params.id}`,
          body: `"${ticket.title}" başlıklı destek biletiniz ${Math.floor(hoursElapsed)} saattir çözümsüz kaldı. Önceliği yükseltildi.`
        });
      } catch (_) {}

      await writeAdminAudit(req.user!.id, 'SLA_ESCALATED', 'support_tickets', req.params.id, null, {
        hoursElapsed: parseFloat(hoursElapsed.toFixed(1)), threshold, previousPriority: ticket.priority
      });

      return res.json({ escalated: true, hoursElapsed: parseFloat(hoursElapsed.toFixed(1)), threshold });
    }

    return res.json({ escalated: false, hoursElapsed: parseFloat(hoursElapsed.toFixed(1)), threshold, breached });
  } catch (err) {
    console.error('SLA escalation error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// [ADMIN-10] OTA Rollout Config — GET mevcut rollout konfigürasyonları
router.get('/releases/rollout-config', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const result = await runBypassingRLS(`
      SELECT id, version, channel, rollout_percentage, is_mandatory,
             release_notes, status, created_at, updated_at
      FROM app_releases
      ORDER BY created_at DESC
      LIMIT 20
    `);
    return res.json(result.rows);
  } catch (err) {
    console.error('Rollout config fetch error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// [ADMIN-10] OTA Rollout Config — PUT rollout yüzdesi + mandatory flag güncelle
router.put('/releases/:id/rollout-config', async (req: AuthenticatedRequest, res: Response) => {
  const { rollout_percentage, is_mandatory } = req.body;

  if (rollout_percentage === undefined && is_mandatory === undefined) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  if (rollout_percentage !== undefined && (rollout_percentage < 0 || rollout_percentage > 100)) {
    return res.status(400).json({ error: 'invalid_rollout_percentage', detail: 'Must be 0–100' });
  }

  try {
    const current = await runBypassingRLS('SELECT * FROM app_releases WHERE id = $1', [req.params.id]);
    if (current.rows.length === 0) {
      return res.status(404).json({ error: 'release_not_found' });
    }

    const updates: string[] = ['updated_at = NOW()'];
    const params: any[] = [req.params.id];

    if (rollout_percentage !== undefined) {
      params.push(rollout_percentage);
      updates.push(`rollout_percentage = $${params.length}`);
    }
    if (is_mandatory !== undefined) {
      params.push(is_mandatory);
      updates.push(`is_mandatory = $${params.length}`);
    }

    await runBypassingRLS(
      `UPDATE app_releases SET ${updates.join(', ')} WHERE id = $1`,
      params
    );

    await writeAdminAudit(req.user!.id, 'ROLLOUT_CONFIG_UPDATED', 'app_releases', req.params.id,
      { rollout_percentage: current.rows[0].rollout_percentage, is_mandatory: current.rows[0].is_mandatory },
      { rollout_percentage, is_mandatory }
    );

    return res.json({ success: true });
  } catch (err) {
    console.error('Rollout config update error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// [ADMIN-10] OTA Rollback — Bir release'i önceki stable sürüme geri al
router.post('/releases/:id/rollback', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const release = await runBypassingRLS('SELECT * FROM app_releases WHERE id = $1', [req.params.id]);
    if (release.rows.length === 0) {
      return res.status(404).json({ error: 'release_not_found' });
    }
    const current = release.rows[0];

    // Mark this release as rolled back / deprecated
    await runBypassingRLS(`
      UPDATE app_releases
      SET status = 'rolled_back', rollout_percentage = 0, updated_at = NOW()
      WHERE id = $1
    `, [req.params.id]);

    // Find previous stable release to promote
    const prevRes = await runBypassingRLS(`
      SELECT id, version FROM app_releases
      WHERE channel = $1
        AND status = 'active'
        AND id != $2
      ORDER BY created_at DESC LIMIT 1
    `, [current.channel || 'stable', req.params.id]);

    let promotedVersion: string | null = null;
    if (prevRes.rows.length > 0) {
      const prevId = prevRes.rows[0].id;
      promotedVersion = prevRes.rows[0].version;
      await runBypassingRLS(`
        UPDATE app_releases SET rollout_percentage = 100, updated_at = NOW() WHERE id = $1
      `, [prevId]);
    }

    await writeAdminAudit(req.user!.id, 'RELEASE_ROLLED_BACK', 'app_releases', req.params.id,
      { status: current.status, rollout_percentage: current.rollout_percentage },
      { status: 'rolled_back', rollout_percentage: 0, promotedVersion }
    );

    return res.json({ success: true, rolledBack: current.version, promotedVersion });
  } catch (err) {
    console.error('Release rollback error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── FAZ 4 — SPRINT 4.2: MAINTENANCE & SUPPORT SLA ─────────────────────────

// [OPS-8] Toggle maintenance mode in Redis and memory
router.post('/maintenance', async (req: AuthenticatedRequest, res: Response) => {
  const { enabled } = req.body;
  if (enabled === undefined) {
    return res.status(400).json({ error: 'missing_enabled_field' });
  }

  const isEnabled = enabled === true || enabled === 'true';

  try {
    if (redisClient && redisClient.isOpen) {
      await redisClient.set('admin:maintenance_mode', isEnabled ? 'true' : 'false');
    }
    (global as any).maintenanceMode = isEnabled;

    await writeAdminAudit(req.user!.id, 'TOGGLE_MAINTENANCE_MODE', 'system', 'maintenance_mode', null, { enabled: isEnabled });

    return res.json({ success: true, maintenanceMode: isEnabled });
  } catch (err) {
    console.error('Failed to toggle maintenance mode:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// [OPS-11] GET SLA stats dashboard for support tickets
router.get('/dashboard/support-sla', async (req: AuthenticatedRequest, res: Response) => {
  try {
    // Total open tickets
    const openRes = await runBypassingRLS(`
      SELECT COUNT(*) as count FROM support_tickets WHERE status != 'resolved'
    `);
    const openTicketsCount = parseInt(openRes.rows[0].count, 10);

    // Aging counts: < 24h, 24h-72h, > 72h
    const agingRes = await runBypassingRLS(`
      SELECT 
        COUNT(*) FILTER (WHERE created_at >= NOW() - INTERVAL '24 hours') AS age_24h,
        COUNT(*) FILTER (WHERE created_at < NOW() - INTERVAL '24 hours' AND created_at >= NOW() - INTERVAL '72 hours') AS age_72h,
        COUNT(*) FILTER (WHERE created_at < NOW() - INTERVAL '72 hours') AS age_older
      FROM support_tickets
      WHERE status != 'resolved'
    `);
    const aging = {
      under24h: parseInt(agingRes.rows[0].age_24h, 10),
      between24h72h: parseInt(agingRes.rows[0].age_72h, 10),
      olderThan72h: parseInt(agingRes.rows[0].age_older, 10)
    };

    // SLA breached tickets (urgent=4h, high=8h, medium=24h, low=72h)
    const breachedRes = await runBypassingRLS(`
      SELECT t.id, t.title, t.priority, t.created_at, c.name as company_name
      FROM support_tickets t
      LEFT JOIN companies c ON t.company_id = c.id
      WHERE t.status != 'resolved'
        AND (
          (t.priority = 'urgent' AND t.created_at < NOW() - INTERVAL '4 hours') OR
          (t.priority = 'high' AND t.created_at < NOW() - INTERVAL '8 hours') OR
          (t.priority = 'medium' AND t.created_at < NOW() - INTERVAL '24 hours') OR
          (t.priority = 'low' AND t.created_at < NOW() - INTERVAL '72 hours')
        )
    `);

    return res.json({
      openTicketsCount,
      aging,
      breachedCount: breachedRes.rows.length,
      breachedTickets: breachedRes.rows
    });
  } catch (err) {
    console.error('Support SLA statistics failed:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// [ADMIN-15-settings] Get system settings
router.get('/settings', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const result = await runBypassingRLS('SELECT key, value, updated_at FROM system_settings ORDER BY key ASC');
    const settings: Record<string, string> = {};
    result.rows.forEach(row => {
      settings[row.key] = row.value;
    });
    return res.json({ success: true, settings });
  } catch (err) {
    console.error('Failed to get system settings:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// [ADMIN-16-settings] Save system settings
router.put('/settings', async (req: AuthenticatedRequest, res: Response) => {
  const { settings } = req.body;
  if (!settings || typeof settings !== 'object') {
    return res.status(400).json({ error: 'bad_request', message: 'Settings nesnesi eksik veya hatalı.' });
  }

  try {
    const keys = Object.keys(settings);
    for (const key of keys) {
      const val = String(settings[key]);
      await runBypassingRLS(
        `INSERT INTO system_settings (key, value, updated_at) 
         VALUES ($1, $2, NOW()) 
         ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = NOW()`,
        [key, val]
      );
    }

    // Reload dynamic payment configs in memory
    await loadIyzicoConfig(pgPool);

    await writeAdminAudit(req.user!.id, 'UPDATE_SYSTEM_SETTINGS', 'system_settings', 'bulk', null, settings, req.ip);
    return res.json({ success: true, message: 'Sistem ayarları başarıyla güncellendi.' });
  } catch (err) {
    console.error('Failed to save system settings:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 30. PAYMENT PROVIDERS MANAGEMENT ──────────────────────────────────────────

router.get('/payment-methods', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const result = await runBypassingRLS('SELECT * FROM payment_providers ORDER BY id ASC');
    // Mask secrets
    const masked = result.rows.map(row => {
      const secrets = typeof row.secrets === 'string' ? JSON.parse(row.secrets) : (row.secrets || {});
      const maskedSecrets: Record<string, string> = {};
      for (const key of Object.keys(secrets)) {
        maskedSecrets[key] = '********';
      }
      return { ...row, secrets: maskedSecrets };
    });
    return res.json(masked);
  } catch (err: any) {
    if (err.code === '42P01') return res.json([]);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.put('/payment-methods/:id', async (req: AuthenticatedRequest, res: Response) => {
  const { is_enabled, config, secrets } = req.body;
  try {
    const currentRes = await runBypassingRLS('SELECT * FROM payment_providers WHERE id = $1', [req.params.id]);
    if (currentRes.rows.length === 0) return res.status(404).json({ error: 'not_found' });
    
    const current = currentRes.rows[0];
    const currentSecrets = typeof current.secrets === 'string' ? JSON.parse(current.secrets) : (current.secrets || {});

    // Encrypt new secrets
    const newSecrets = { ...currentSecrets };
    if (secrets) {
      for (const [k, v] of Object.entries(secrets)) {
        if (v && v !== '********') { // Only update if value changed and not masked
          newSecrets[k] = encryptSecret(v as string);
        }
      }
    }

    // First, save the new config/secrets, but forcefully keep is_enabled = false if they requested it to be true
    // so we can test it safely.
    const requestedEnabled = is_enabled === true;
    let finalEnabled = current.is_enabled;
    if (!requestedEnabled) finalEnabled = false; // They want to disable it, allowed.

    await runBypassingRLS(`
      UPDATE payment_providers 
      SET config = $1, secrets = $2, is_configured = true, updated_at = NOW()
      WHERE id = $3
    `, [JSON.stringify(config || {}), JSON.stringify(newSecrets), req.params.id]);

    if (requestedEnabled && req.params.id === 'iyzico') {
      // Force reload config into memory to test
      await loadIyzicoConfig(pgPool);
      const testResult = await IyzicoService.testConnection();
      
      await runBypassingRLS(`
        UPDATE payment_providers SET last_test_at = NOW(), last_error = $1 WHERE id = $2
      `, [testResult.success ? null : testResult.message, req.params.id]);

      if (testResult.success) {
        finalEnabled = true;
      } else {
        return res.status(400).json({ 
          error: 'verification_failed', 
          message: 'Sağlayıcı test edilemedi. Bilgiler kaydedildi ancak aktif edilemedi: ' + testResult.message 
        });
      }
    } else if (requestedEnabled && req.params.id !== 'iyzico') {
      finalEnabled = true;
    }

    const result = await runBypassingRLS(`
      UPDATE payment_providers SET is_enabled = $1 WHERE id = $2 RETURNING *
    `, [finalEnabled, req.params.id]);

    await writeAdminAudit(req.user!.id, 'UPDATE_PAYMENT_PROVIDER', 'payment_providers', req.params.id, null, { is_enabled: finalEnabled }, req.ip);

    return res.json(result.rows[0]);
  } catch (err) {
    logger.error('Failed to update payment provider:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/payment-methods/:id/test', async (req: AuthenticatedRequest, res: Response) => {
  try {
    if (req.params.id === 'iyzico') {
      await loadIyzicoConfig(pgPool);
      const testResult = await IyzicoService.testConnection();
      await runBypassingRLS(`
        UPDATE payment_providers SET last_test_at = NOW(), last_error = $1 WHERE id = $2
      `, [testResult.success ? null : testResult.message, req.params.id]);
      
      if (!testResult.success) {
        // If test fails, forcibly disable it
        await runBypassingRLS('UPDATE payment_providers SET is_enabled = false WHERE id = $1', [req.params.id]);
      }
      return res.json(testResult);
    } else {
      await runBypassingRLS('UPDATE payment_providers SET last_test_at = NOW(), last_error = null WHERE id = $1', [req.params.id]);
      return res.json({ success: true, message: 'Test applied manually.' });
    }
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
