import { Router, Response } from 'express';
import {
  authenticateUser,
  AuthenticatedRequest,
  requireActiveEntitlement,
  requirePortalAccess,
} from '../../middleware/auth.middleware';
import { pgPool } from '../../config/database';
import { AuthService } from '../auth/auth.service';
import fs from 'fs';
import path from 'path';
import { exec } from 'child_process';
import { logger } from '../../config/logger';
import crypto from 'crypto';
import { PasswordRecoveryService } from '../auth/password-recovery.service';

const router = Router();

// Apply auth globally
router.use(authenticateUser);
router.use(requirePortalAccess);
router.use((req, res, next) => {
  const isReadOnly = req.method === 'GET' || req.method === 'HEAD';
  const isSupportRecoveryRoute = req.path === '/tickets' ||
    req.path.startsWith('/tickets/');
  if (isReadOnly || isSupportRecoveryRoute) {
    return next();
  }
  return requireActiveEntitlement(req, res, next);
});

// Helper to run database queries setting tenant context for RLS
async function runWithTenantContext(companyId: string, sql: string, params: any[] = []) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [companyId]);
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

// Write tenant action audit log
async function writeTenantAudit(companyId: string, userId: string, action: string, entity: string, entityId: string, oldValue: any = null, newValue: any = null) {
  const auditId = `aud-${Date.now()}-${Math.floor(Math.random() * 1000)}`;
  try {
    await runWithTenantContext(
      companyId,
      `INSERT INTO audit_logs (id, company_id, user_id, action, entity, entity_id, old_value, new_value, ip_address)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [
        auditId,
        companyId,
        userId,
        action,
        entity,
        entityId,
        oldValue ? JSON.stringify(oldValue) : null,
        newValue ? JSON.stringify(newValue) : null,
        'customer_portal'
      ]
    );
  } catch (err) {
    console.error('Failed to write tenant audit log:', err);
  }
}

// ── 1. PORTAL DASHBOARD ─────────────────────────────────────────────────────
router.get('/dashboard', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const stores = await runWithTenantContext(user.company_id, 'SELECT COUNT(*) FROM branches WHERE company_id = $1 AND is_active = TRUE', [user.company_id]);
    const devices = await runWithTenantContext(user.company_id, "SELECT COUNT(*) FROM device_activations WHERE company_id = $1 AND status = 'active'", [user.company_id]);
    const licenses = await runWithTenantContext(user.company_id, 'SELECT id, plan_id as tier, status, valid_until as expires_at, license_key, device_limit as allowed_devices_count FROM license_entitlements WHERE company_id = $1 ORDER BY valid_until DESC', [user.company_id]);
    const invoices = await runWithTenantContext(user.company_id, "SELECT COUNT(*) FROM invoices WHERE status IN ('pending','unpaid') AND company_id = $1", [user.company_id]);
    const recentSales = await runWithTenantContext(user.company_id, 'SELECT SUM(total_amount) FROM sales WHERE created_at >= NOW() - INTERVAL \'30 days\' AND company_id = $1', [user.company_id]);

    return res.json({
      summary: {
        stores: parseInt(stores.rows[0].count, 10),
        devices: parseInt(devices.rows[0].count, 10),
        activeLicenseCount: licenses.rows.filter((l: any) => l.status === 'active' || l.status === 'trial').length,
        unpaidInvoices: parseInt(invoices.rows[0].count, 10),
        monthlyRevenue: parseFloat(recentSales.rows[0].sum || '0.00'),
      },
      licenses: licenses.rows
    });
  } catch (err) {
    console.error('Portal dashboard error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 2. DEVICES ──────────────────────────────────────────────────────────────
router.get('/devices', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(user.company_id, `
      SELECT da.id, da.device_name as name, da.device_hash, da.platform, da.status, da.activated_at as created_at, da.last_seen_at as last_active_at 
      FROM device_activations da 
      WHERE da.company_id = $1
      ORDER BY da.activated_at DESC
    `, [user.company_id]);
    
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

// ── 2b. COMPANY DIAGNOSTICS ────────────────────────────────────────────────
// Tenant owners need actionable evidence for support and sync investigation,
// without exposing platform-wide server logs or another company's data.
router.get('/diagnostics', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const canInspect = user.roles?.some((role) =>
    ['owner', 'admin', 'manager', 'sysadmin'].includes(role),
  );
  if (!canInspect) {
    return res.status(403).json({ error: 'forbidden', message: 'Sistem kayıtlarını görüntüleme yetkiniz yok.' });
  }

  try {
    const [devices, conflicts, crashes, audit] = await Promise.all([
      runWithTenantContext(user.company_id,
        `SELECT da.id, da.device_name AS name, da.platform, da.status,
                da.last_seen_at AS last_active_at
         FROM device_activations da WHERE da.company_id = $1
         ORDER BY da.last_seen_at DESC NULLS LAST LIMIT 50`,
        [user.company_id]),
      runWithTenantContext(user.company_id,
        `SELECT mutation_id, entity_type, entity_id, base_revision,
                server_revision, created_at
         FROM sync_v4_conflicts WHERE tenant_id = $1
         ORDER BY created_at DESC LIMIT 100`,
        [user.company_id]),
      runWithTenantContext(user.company_id,
        `SELECT id, error_message, stack_trace, app_version, device_id, created_at
         FROM crash_logs WHERE company_id = $1
         ORDER BY created_at DESC LIMIT 100`,
        [user.company_id]),
      runWithTenantContext(user.company_id,
        `SELECT id, action, entity, entity_id, ip_address, created_at
         FROM audit_logs WHERE company_id = $1
         ORDER BY created_at DESC LIMIT 100`,
        [user.company_id]),
    ]);

    return res.json({
      summary: {
        devices: devices.rows.length,
        online_devices: devices.rows.filter((row: any) => row.last_active_at &&
          Date.now() - new Date(row.last_active_at).getTime() < 5 * 60 * 1000).length,
        sync_conflicts: conflicts.rows.length,
        crashes: crashes.rows.length,
      },
      devices: devices.rows,
      sync_conflicts: conflicts.rows,
      crashes: crashes.rows,
      audit: audit.rows,
    });
  } catch (err) {
    logger.error('Portal diagnostics query failed:', err);
    return res.status(500).json({ error: 'diagnostics_unavailable' });
  }
});

// ── 3. STORES ───────────────────────────────────────────────────────────────
router.get('/stores', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(user.company_id,
      `SELECT id, store_id, name, address, phone, is_active,
              CASE WHEN is_active THEN 'active' ELSE 'inactive' END AS status,
              created_at, updated_at
       FROM branches WHERE company_id = $1 ORDER BY name ASC`,
      [user.company_id]);
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/stores', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { name, address } = req.body;
  if (!name) {
    return res.status(400).json({ error: 'missing_name' });
  }

  const storeId = `store-${crypto.randomUUID()}`;
  const branchId = `br-${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    await client.query('INSERT INTO stores (id, company_id, name, address) VALUES ($1, $2, $3, $4)',
      [storeId, user.company_id, name.trim(), address || null]);
    await client.query(
      `INSERT INTO branches (id, company_id, store_id, name, address)
       VALUES ($1, $2, $3, $4, $5)`,
      [branchId, user.company_id, storeId, name.trim(), address || null]);
    await client.query('COMMIT');

    await writeTenantAudit(user.company_id, user.id, 'CREATE_BRANCH', 'branches', branchId, null, { name });

    return res.status(201).json({ success: true, branch_id: branchId, store_id: storeId });
  } catch (err: any) {
    await client.query('ROLLBACK');
    if (err.code === '23505') return res.status(409).json({ error: 'duplicate_branch' });
    return res.status(500).json({ error: 'server_error' });
  } finally {
    client.release();
  }
});

// ── 4. USERS ────────────────────────────────────────────────────────────────
router.get('/users', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(
      user.company_id,
      `SELECT u.id, u.name, u.email, u.is_active, u.created_at,
              COALESCE(ARRAY_AGG(r.name) FILTER (WHERE r.id IS NOT NULL), '{}') AS roles,
              MIN(r.id) AS role_id, MIN(r.name) AS role_name
       FROM users u
       LEFT JOIN user_roles ur ON ur.user_id = u.id
       LEFT JOIN roles r ON r.id = ur.role_id
       WHERE u.company_id = $1
       GROUP BY u.id
       ORDER BY u.name ASC`,
      [user.company_id]
    );
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/users', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  
  // Privilege check: only owners/admins can create new users
  const isOwnerOrAdmin = user.roles?.includes('owner') || user.roles?.includes('admin');
  if (!isOwnerOrAdmin) {
    return res.status(403).json({ error: 'forbidden', message: 'Sadece yetkili yöneticiler kullanıcı oluşturabilir.' });
  }

  const { name, email, role_id } = req.body;
  if (!name || !email || !role_id) {
    return res.status(400).json({ error: 'missing_fields', message: 'Ad, e-posta ve rol zorunludur.' });
  }

  // Prevent assigning 'sysadmin' role unless the requester is also a sysadmin
  if (role_id === 'sysadmin' && !user.roles?.includes('sysadmin')) {
    return res.status(403).json({ error: 'forbidden', message: 'Sysadmin yetkisi atanamaz.' });
  }

  const assignableRole = await runWithTenantContext(
    user.company_id,
    `SELECT id FROM roles WHERE id = $1 AND name <> 'sysadmin'
     AND (company_id IS NULL OR company_id = $2)`,
    [role_id, user.company_id]
  );
  if (assignableRole.rows.length === 0) {
    return res.status(400).json({ error: 'invalid_role', message: 'Bu rol firmaya atanamaz.' });
  }

  const id = `usr-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

  try {
    const limitResult = await runWithTenantContext(
      user.company_id,
      `SELECT COALESCE(o.user_limit,p.user_limit) AS user_limit, COUNT(u.id)::int AS current_users
       FROM subscriptions s
       JOIN plans p ON p.id = s.plan_id
       LEFT JOIN subscription_overrides o ON o.company_id=s.company_id AND o.base_plan_id=s.plan_id
        AND o.is_active=TRUE AND CURRENT_TIMESTAMP BETWEEN o.valid_from AND o.valid_until
       LEFT JOIN users u ON u.company_id = s.company_id AND u.is_active = true
       WHERE s.company_id = $1
       GROUP BY COALESCE(o.user_limit,p.user_limit)
       ORDER BY MAX(s.current_period_start) DESC LIMIT 1`,
      [user.company_id]
    );
    if (limitResult.rows[0] && limitResult.rows[0].current_users >= limitResult.rows[0].user_limit) {
      return res.status(409).json({ error: 'user_limit_reached', message: 'Planınızdaki kullanıcı sınırına ulaştınız.' });
    }

    const passwordHash = await AuthService.hashPassword(crypto.randomBytes(32).toString('base64url'));
    const client = await pgPool.connect();
    let initialClaim: { requestId: string; claimCode: string };
    try {
      await client.query('BEGIN');
      await client.query("SELECT set_config('app.current_company_id',$1,true)", [user.company_id]);
      await client.query(
        'INSERT INTO users (id,company_id,name,email,password_hash,is_active) VALUES($1,$2,$3,$4,$5,TRUE)',
        [id, user.company_id, name.trim(), email.trim().toLowerCase(), passwordHash],
      );
      await client.query('INSERT INTO user_roles(user_id,role_id) VALUES($1,$2)', [id, role_id]);
      initialClaim = await PasswordRecoveryService.createInitialClaim(client, {
        targetUserId: id, companyId: user.company_id, actorId: user.id,
        reason: 'Firma yöneticisi tarafından yeni kullanıcı aktivasyonu',
        context: { ip: req.ip, userAgent: req.headers['user-agent'] },
      });
      await client.query('COMMIT');
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally { client.release(); }

    await writeTenantAudit(user.company_id, user.id, 'CREATE_USER', 'users', id, null, { name, email, role_id });

    return res.status(201).json({
      success: true, user_id: id, recovery_request_id: initialClaim.requestId,
      claim_code: initialClaim.claimCode,
    });
  } catch (err: any) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'email_exists', message: 'Bu e-posta adresi bu firmada zaten kayıtlı.' });
    }
    console.error('Create portal user error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// PATCH /portal/users/:id — Update identity, role or active status.
router.patch('/users/:id', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const isOwner = user.roles?.includes('owner') || user.roles?.includes('admin') || user.roles?.includes('sysadmin');
  if (!isOwner) {
    return res.status(403).json({ error: 'forbidden', message: 'Sadece firma sahibi kullanıcıları düzenleyebilir.' });
  }

  const { name, email, is_active, new_password, role_id } = req.body;
  if (new_password !== undefined) {
    return res.status(410).json({
      error: 'direct_password_reset_removed',
      message: 'Yönetici parola belirleyemez. Tek kullanımlık kurtarma talebi oluşturun.',
    });
  }
  const targetId = req.params.id;
  if (targetId === user.id && is_active === false) {
    return res.status(400).json({ error: 'cannot_deactivate_self', message: 'Kendi hesabınızı devre dışı bırakamazsınız.' });
  }

  // Prevent assigning 'sysadmin' role unless the requester is also a sysadmin
  if (role_id === 'sysadmin' && !user.roles?.includes('sysadmin')) {
    return res.status(403).json({ error: 'forbidden', message: 'Sysadmin yetkisi atanamaz.' });
  }

  if (role_id !== undefined) {
    const assignableRole = await runWithTenantContext(
      user.company_id,
      `SELECT id FROM roles WHERE id = $1 AND name <> 'sysadmin'
       AND (company_id IS NULL OR company_id = $2)`,
      [role_id, user.company_id]
    );
    if (assignableRole.rows.length === 0) {
      return res.status(400).json({ error: 'invalid_role', message: 'Bu rol firmaya atanamaz.' });
    }
  }

  // Verify user belongs to this company
  const check = await runWithTenantContext(
    user.company_id,
    'SELECT id FROM users WHERE id = $1 AND company_id = $2',
    [targetId, user.company_id]
  );
  if (check.rows.length === 0) {
    return res.status(404).json({ error: 'user_not_found' });
  }

  // We need to use a single connection for multiple queries inside a single transaction
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);

    const updates: string[] = [];
    const values: any[] = [];
    let idx = 1;

    if (name !== undefined) { updates.push(`name = $${idx++}`); values.push(name.trim()); }
    if (email !== undefined) { updates.push(`email = $${idx++}`); values.push(email.trim().toLowerCase()); }
    if (is_active !== undefined) { updates.push(`is_active = $${idx++}`); values.push(Boolean(is_active)); }
    if (updates.length > 0) {
      updates.push(`token_version = token_version + 1`);
      updates.push(`updated_at = CURRENT_TIMESTAMP`);
      values.push(targetId);
      await client.query(
        `UPDATE users SET ${updates.join(', ')} WHERE id = $${idx}`,
        values
      );
    } else if (role_id !== undefined) {
      await client.query(
        'UPDATE users SET token_version = token_version + 1, updated_at = CURRENT_TIMESTAMP WHERE id = $1',
        [targetId]
      );
    }

    if (role_id !== undefined) {
      await client.query('DELETE FROM user_roles WHERE user_id = $1', [targetId]);
      await client.query('INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2)', [targetId, role_id]);
    }

    await client.query('COMMIT');

    await writeTenantAudit(user.company_id, user.id, 'UPDATE_USER', 'users', targetId, null, { name, email, is_active, role_id });

    return res.json({ success: true, message: 'Kullanıcı güncellendi.' });
  } catch (err: any) {
    await client.query('ROLLBACK').catch(() => {});
    if (err.code === '23505') {
      return res.status(409).json({ error: 'email_exists', message: 'Bu e-posta adresi zaten kayıtlı.' });
    }
    console.error('Update portal user error:', err);
    return res.status(500).json({ error: 'server_error' });
  } finally {
    client.release();
  }
});

// DELETE /portal/users/:id — Remove a sub-user (owner cannot delete themselves)
router.delete('/users/:id', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const isOwner = user.roles?.includes('owner') || user.roles?.includes('admin') || user.roles?.includes('sysadmin');
  if (!isOwner) {
    return res.status(403).json({ error: 'forbidden', message: 'Sadece firma sahibi kullanıcıları silebilir.' });
  }

  const targetId = req.params.id;
  if (targetId === user.id) {
    return res.status(400).json({ error: 'cannot_delete_self', message: 'Kendi hesabınızı silemezsiniz.' });
  }

  try {
    const result = await runWithTenantContext(
      user.company_id,
      'DELETE FROM users WHERE id = $1 AND company_id = $2',
      [targetId, user.company_id]
    );

    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'user_not_found' });
    }

    await writeTenantAudit(user.company_id, user.id, 'DELETE_USER', 'users', targetId, { id: targetId }, null);

    return res.json({ success: true, message: 'Kullanıcı silindi.' });
  } catch (err) {
    console.error('Delete portal user error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// GET /portal/roles — List assignable roles (exclude sysadmin)
router.get('/roles', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const result = await runWithTenantContext(
      user.company_id,
      `SELECT r.id, r.name, r.description, r.company_id,
              COALESCE(ARRAY_AGG(p.code) FILTER (WHERE p.code IS NOT NULL), '{}') AS permissions
       FROM roles r
       LEFT JOIN role_permissions rp ON rp.role_id = r.id
       LEFT JOIN permissions p ON p.id = rp.permission_id
       WHERE r.name <> 'sysadmin' AND (r.company_id IS NULL OR r.company_id = $1)
       GROUP BY r.id ORDER BY r.company_id NULLS FIRST, r.name ASC`,
      [user.company_id]
    );
    return res.json(result.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.get('/permissions', async (_req: AuthenticatedRequest, res: Response) => {
  try {
    const result = await pgPool.query("SELECT id, code, description FROM permissions WHERE code NOT LIKE 'platform:%' ORDER BY code");
    return res.json(result.rows);
  } catch (_) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/roles', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  if (!user.roles?.includes('owner') && !user.roles?.includes('sysadmin')) {
    return res.status(403).json({ error: 'forbidden' });
  }
  const name = String(req.body.name || '').trim();
  const description = String(req.body.description || '').trim();
  const permissionCodes = Array.isArray(req.body.permissions) ? [...new Set(req.body.permissions.map(String))] : [];
  if (!name || permissionCodes.length === 0) {
    return res.status(400).json({ error: 'missing_fields', message: 'Rol adı ve en az bir yetki zorunludur.' });
  }
  const client = await pgPool.connect();
  const roleId = `role-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;
  try {
    await client.query('BEGIN');
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await client.query(
      'INSERT INTO roles (id, company_id, name, description) VALUES ($1, $2, $3, $4)',
      [roleId, user.company_id, name, description || null]
    );
    const inserted = await client.query(
      `INSERT INTO role_permissions (role_id, permission_id)
       SELECT $1, id FROM permissions WHERE code = ANY($2::varchar[])
       RETURNING permission_id`,
      [roleId, permissionCodes]
    );
    if (inserted.rowCount !== permissionCodes.length) throw new Error('invalid_permission');
    await client.query('COMMIT');
    await writeTenantAudit(user.company_id, user.id, 'CREATE_ROLE', 'roles', roleId, null, { name, permissions: permissionCodes });
    return res.status(201).json({ id: roleId, name, permissions: permissionCodes });
  } catch (err: any) {
    await client.query('ROLLBACK').catch(() => {});
    if (err.code === '23505') return res.status(409).json({ error: 'role_exists', message: 'Bu isimde bir rol zaten var.' });
    if (err.message === 'invalid_permission') return res.status(400).json({ error: 'invalid_permission' });
    return res.status(500).json({ error: 'server_error' });
  } finally {
    client.release();
  }
});

// ── 5. INVOICES ─────────────────────────────────────────────────────────────
router.get('/invoices', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(
      user.company_id,
      'SELECT * FROM invoices WHERE company_id = $1 ORDER BY due_at DESC',
      [user.company_id]
    );
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 7. BULUT YEDEKLERI (Cloud Backups) ───────────────────────────────────────
const BACKUP_DIR = process.env.NODE_ENV === 'production' ? '/var/backups/serenut' : path.join(__dirname, '../../../backups');

router.get('/backups', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  if (!user.roles?.includes('sysadmin')) {
    return res.status(403).json({ error: 'forbidden', message: 'Yedekleme yönetimi sadece sistem yöneticilerine açıktır.' });
  }

  try {
    if (!fs.existsSync(BACKUP_DIR)) {
      fs.mkdirSync(BACKUP_DIR, { recursive: true });
    }
    const files = fs.readdirSync(BACKUP_DIR);
    const backups = files
      .filter(file => file.endsWith('.enc'))
      .map(file => {
        const filePath = path.join(BACKUP_DIR, file);
        const stats = fs.statSync(filePath);
        return {
          id: file,
          filename: file,
          size: (stats.size / (1024 * 1024)).toFixed(2) + ' MB',
          created_at: stats.mtime.toISOString(),
          type: file.includes('manual') ? 'manual' : 'scheduled'
        };
      })
      .sort((a, b) => new Date(b.created_at).getTime() - new Date(a.created_at).getTime());
    return res.json(backups);
  } catch (err) {
    logger.error('Failed to list backups:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/backups', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  if (!user.roles?.includes('sysadmin')) {
    return res.status(403).json({ error: 'forbidden', message: 'Yedekleme yönetimi sadece sistem yöneticilerine açıktır.' });
  }

  try {
    const scriptPath = process.env.NODE_ENV === 'production'
      ? '/var/www/serenut-api/scripts/backup.sh'
      : path.join(__dirname, '../../../scripts/backup.sh');

    // Trigger backup.sh script asynchronously
    exec(`bash ${scriptPath}`, (error, stdout, stderr) => {
      if (error) {
        logger.error(`Backup execution failed: ${error.message}`);
        logger.error(`Stderr: ${stderr}`);
        return;
      }
      logger.info(`Backup execution succeeded: ${stdout}`);
    });

    const backupId = `bak-${user.company_id}-${Date.now()}`;
    const filename = `db_backup_manual_${new Date().toISOString().replace(/[:.]/g, '-')}.sql.enc`;

    await writeTenantAudit(user.company_id, user.id, 'CREATE_CLOUD_BACKUP', 'backups', backupId, null, { filename });

    return res.status(201).json({
      success: true,
      message: 'Yedekleme işlemi arka planda başlatıldı.',
      backup: { id: backupId, filename, size: 'Hesaplanıyor...', created_at: new Date().toISOString(), type: 'manual' }
    });
  } catch (err) {
    logger.error('Failed to trigger backup:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.get('/backups/download/:filename', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  if (!user.roles?.includes('sysadmin')) {
    return res.status(403).json({ error: 'forbidden', message: 'Yedekleme yönetimi sadece sistem yöneticilerine açıktır.' });
  }

  const { filename } = req.params;
  // Prevent directory traversal
  if (filename.includes('..') || filename.includes('/') || filename.includes('\\')) {
    return res.status(400).json({ error: 'invalid_filename' });
  }
  const filePath = path.join(BACKUP_DIR, filename);
  if (!fs.existsSync(filePath)) {
    return res.status(404).json({ error: 'file_not_found' });
  }
  logger.info(`Downloading backup file: ${filename}`);
  return res.download(filePath, filename);
});


export default router;
