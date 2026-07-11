import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { pgPool } from '../../config/database';
import { AuthService } from '../auth/auth.service';
import fs from 'fs';
import path from 'path';
import { exec } from 'child_process';
import { logger } from '../../config/logger';

const router = Router();

// Apply auth globally
router.use(authenticateUser);

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
    const stores = await runWithTenantContext(user.company_id, 'SELECT COUNT(*) FROM stores WHERE company_id = $1', [user.company_id]);
    const devices = await runWithTenantContext(user.company_id, "SELECT COUNT(*) FROM device_activations WHERE company_id = $1 AND status = 'active'", [user.company_id]);
    const licenses = await runWithTenantContext(user.company_id, 'SELECT id, plan_id as tier, status, valid_until as expires_at, license_key FROM license_entitlements WHERE company_id = $1 ORDER BY valid_until DESC', [user.company_id]);
    const invoices = await runWithTenantContext(user.company_id, 'SELECT COUNT(*) FROM invoices WHERE status = \'unpaid\' AND company_id = $1', [user.company_id]);
    const recentSales = await runWithTenantContext(user.company_id, 'SELECT SUM(total_amount) FROM sales WHERE created_at >= NOW() - INTERVAL \'30 days\' AND company_id = $1', [user.company_id]);

    return res.json({
      summary: {
        stores: parseInt(stores.rows[0].count, 10),
        devices: parseInt(devices.rows[0].count, 10),
        activeLicenseCount: licenses.rows.filter((l: any) => l.status === 'active' || l.status === 'trial').length,
        unpaidInvoices: parseInt(invoices.rows[0].count, 10),
        monthlyRevenue: parseFloat(recentSales.rows[0].sum || '0.00'),
      },
      licenses: licenses.rows.map((l: any) => ({
        ...l,
        allowed_devices_count: l.tier.includes('pro') ? 5 : 2,
      }))
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

// ── 3. STORES ───────────────────────────────────────────────────────────────
router.get('/stores', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(user.company_id, 'SELECT * FROM stores WHERE company_id = $1 ORDER BY name ASC', [user.company_id]);
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

  const id = `store-${Date.now()}`;
  try {
    await runWithTenantContext(
      user.company_id,
      'INSERT INTO stores (id, company_id, name, address) VALUES ($1, $2, $3, $4)',
      [id, user.company_id, name, address || null]
    );

    await writeTenantAudit(user.company_id, user.id, 'CREATE_STORE', 'stores', id, null, { name });

    return res.status(201).json({ success: true, store_id: id });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 4. USERS ────────────────────────────────────────────────────────────────
router.get('/users', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(
      user.company_id,
      'SELECT id, name, email, is_active, created_at FROM users WHERE company_id = $1 ORDER BY name ASC',
      [user.company_id]
    );
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/users', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { name, email, password, role_id } = req.body;
  if (!name || !email || !password || !role_id) {
    return res.status(400).json({ error: 'missing_fields', message: 'Ad, e-posta, şifre ve rol zorunludur.' });
  }
  if (password.length < 8) {
    return res.status(400).json({ error: 'weak_password', message: 'Şifre en az 8 karakter olmalıdır.' });
  }

  const id = `usr-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`;

  try {
    const passwordHash = await AuthService.hashPassword(password);

    await runWithTenantContext(
      user.company_id,
      'INSERT INTO users (id, company_id, name, email, password_hash, is_active) VALUES ($1, $2, $3, $4, $5, true)',
      [id, user.company_id, name.trim(), email.trim().toLowerCase(), passwordHash]
    );

    await runWithTenantContext(
      user.company_id,
      'INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2)',
      [id, role_id]
    );

    await writeTenantAudit(user.company_id, user.id, 'CREATE_USER', 'users', id, null, { name, email, role_id });

    return res.status(201).json({ success: true, user_id: id });
  } catch (err: any) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'email_exists', message: 'Bu e-posta adresi bu firmada zaten kayıtlı.' });
    }
    console.error('Create portal user error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// PATCH /portal/users/:id — Update name, email, active status or reset password
router.patch('/users/:id', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const isOwner = user.roles?.includes('owner') || user.roles?.includes('admin') || user.roles?.includes('sysadmin');
  if (!isOwner) {
    return res.status(403).json({ error: 'forbidden', message: 'Sadece firma sahibi kullanıcıları düzenleyebilir.' });
  }

  const { name, email, is_active, new_password, role_id } = req.body;
  const targetId = req.params.id;

  // Verify user belongs to this company
  const check = await runWithTenantContext(
    user.company_id,
    'SELECT id FROM users WHERE id = $1 AND company_id = $2',
    [targetId, user.company_id]
  );
  if (check.rows.length === 0) {
    return res.status(404).json({ error: 'user_not_found' });
  }

  try {
    const updates: string[] = [];
    const values: any[] = [];
    let idx = 1;

    if (name !== undefined) { updates.push(`name = $${idx++}`); values.push(name.trim()); }
    if (email !== undefined) { updates.push(`email = $${idx++}`); values.push(email.trim().toLowerCase()); }
    if (is_active !== undefined) { updates.push(`is_active = $${idx++}`); values.push(Boolean(is_active)); }
    if (new_password !== undefined) {
      if (new_password.length < 8) {
        return res.status(400).json({ error: 'weak_password', message: 'Şifre en az 8 karakter olmalıdır.' });
      }
      const hash = await AuthService.hashPassword(new_password);
      updates.push(`password_hash = $${idx++}`);
      values.push(hash);
    }

    if (updates.length > 0) {
      updates.push(`updated_at = CURRENT_TIMESTAMP`);
      values.push(targetId);
      await runWithTenantContext(
        user.company_id,
        `UPDATE users SET ${updates.join(', ')} WHERE id = $${idx}`,
        values
      );
    }

    if (role_id !== undefined) {
      await runWithTenantContext(user.company_id, 'DELETE FROM user_roles WHERE user_id = $1', [targetId]);
      await runWithTenantContext(user.company_id, 'INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2)', [targetId, role_id]);
    }

    await writeTenantAudit(user.company_id, user.id, 'UPDATE_USER', 'users', targetId, null, { name, email, is_active, role_id });

    return res.json({ success: true, message: 'Kullanıcı güncellendi.' });
  } catch (err: any) {
    if (err.code === '23505') {
      return res.status(409).json({ error: 'email_exists', message: 'Bu e-posta adresi zaten kayıtlı.' });
    }
    console.error('Update portal user error:', err);
    return res.status(500).json({ error: 'server_error' });
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
  try {
    const result = await pgPool.query(
      "SELECT id, name, description FROM roles WHERE name NOT IN ('sysadmin') ORDER BY name ASC"
    );
    return res.json(result.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
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

// ── 6. SUPPORT TICKETS ───────────────────────────────────────────────────────
router.get('/tickets', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(
      user.company_id,
      'SELECT * FROM support_tickets WHERE company_id = $1 ORDER BY created_at DESC',
      [user.company_id]
    );
    return res.json(list.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/tickets', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { title, description, priority } = req.body;
  if (!title || !description) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  const id = `tkt-${Date.now()}`;
  try {
    await runWithTenantContext(
      user.company_id,
      `INSERT INTO support_tickets (id, company_id, title, description, priority, status)
       VALUES ($1, $2, $3, $4, $5, 'open')`,
      [id, user.company_id, title, description, priority || 'medium']
    );

    // Auto-create initial message in ticket messages thread
    const msgId = `msg-${Date.now()}`;
    await runWithTenantContext(
      user.company_id,
      `INSERT INTO support_ticket_messages (id, ticket_id, sender_id, sender_name, message)
       VALUES ($1, $2, $3, $4, $5)`,
      [msgId, id, user.id, user.name, description]
    );

    await writeTenantAudit(user.company_id, user.id, 'CREATE_TICKET', 'support_tickets', id, null, { title, priority });

    return res.status(201).json({ success: true, ticket_id: id });
  } catch (err) {
    console.error('Create support ticket error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.get('/tickets/:id/messages', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    // Validate ownership first
    const ticketCheck = await runWithTenantContext(
      user.company_id,
      'SELECT id FROM support_tickets WHERE id = $1 AND company_id = $2',
      [req.params.id, user.company_id]
    );
    if (ticketCheck.rows.length === 0) {
      return res.status(403).json({ error: 'unauthorized' });
    }

    const messages = await runWithTenantContext(
      user.company_id,
      'SELECT * FROM support_ticket_messages WHERE ticket_id = $1 ORDER BY created_at ASC',
      [req.params.id]
    );
    return res.json(messages.rows);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/tickets/:id/reply', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { message } = req.body;
  if (!message) {
    return res.status(400).json({ error: 'missing_message' });
  }

  try {
    // Validate ownership first
    const ticketCheck = await runWithTenantContext(
      user.company_id,
      'SELECT id FROM support_tickets WHERE id = $1 AND company_id = $2',
      [req.params.id, user.company_id]
    );
    if (ticketCheck.rows.length === 0) {
      return res.status(403).json({ error: 'unauthorized' });
    }

    const id = `msg-${Date.now()}`;
    await runWithTenantContext(
      user.company_id,
      `INSERT INTO support_ticket_messages (id, ticket_id, sender_id, sender_name, message)
       VALUES ($1, $2, $3, $4, $5)`,
      [id, req.params.id, user.id, user.name, message]
    );

    // Update status back to open when customer replies
    await runWithTenantContext(
      user.company_id,
      "UPDATE support_tickets SET status = 'open', updated_at = NOW() WHERE id = $1",
      [req.params.id]
    );

    return res.status(201).json({ success: true });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── 7. BULUT YEDEKLERI (Cloud Backups) ───────────────────────────────────────
const BACKUP_DIR = process.env.NODE_ENV === 'production' ? '/var/backups/serenut' : path.join(__dirname, '../../../backups');

router.get('/backups', async (req: AuthenticatedRequest, res: Response) => {
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
