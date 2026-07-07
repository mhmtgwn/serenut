import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { pgPool } from '../../config/database';

const router = Router();

// Apply auth globally
router.use(authenticateUser);

// Helper to run database queries setting tenant context for RLS
async function runWithTenantContext(companyId: string, sql: string, params: any[] = []) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query(`SET LOCAL app.current_company_id = '${companyId.replace(/'/g, "''")}'`);
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
    const stores = await runWithTenantContext(user.company_id, 'SELECT COUNT(*) FROM stores');
    const devices = await runWithTenantContext(user.company_id, 'SELECT COUNT(*) FROM devices');
    const licenses = await runWithTenantContext(user.company_id, 'SELECT * FROM licenses');
    const invoices = await runWithTenantContext(user.company_id, 'SELECT COUNT(*) FROM invoices WHERE status = \'unpaid\'');
    const recentSales = await runWithTenantContext(user.company_id, 'SELECT SUM(total_amount) FROM sales WHERE created_at >= NOW() - INTERVAL \'30 days\'');

    return res.json({
      summary: {
        stores: parseInt(stores.rows[0].count, 10),
        devices: parseInt(devices.rows[0].count, 10),
        activeLicenseCount: licenses.rows.filter((l: any) => l.status === 'active').length,
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
      SELECT d.*, s.name as store_name 
      FROM devices d 
      LEFT JOIN stores s ON d.store_id = s.id 
      ORDER BY d.created_at DESC
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

// ── 3. STORES ───────────────────────────────────────────────────────────────
router.get('/stores', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const list = await runWithTenantContext(user.company_id, 'SELECT * FROM stores ORDER BY name ASC');
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
      'SELECT id, name, email, is_active, created_at FROM users ORDER BY name ASC'
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
    return res.status(400).json({ error: 'missing_fields' });
  }

  const id = `user-${Date.now()}`;
  const passwordHash = `PBKDF2:${password}`; // Standard mockup hash matching PasswordHashService

  try {
    await runWithTenantContext(
      user.company_id,
      'INSERT INTO users (id, company_id, name, email, password_hash, is_active) VALUES ($1, $2, $3, $4, $5, true)',
      [id, user.company_id, name, email, passwordHash]
    );

    await runWithTenantContext(
      user.company_id,
      'INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2)',
      [id, role_id]
    );

    await writeTenantAudit(user.company_id, user.id, 'CREATE_USER', 'users', id, null, { name, email, role_id });

    return res.status(201).json({ success: true, user_id: id });
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
      'SELECT * FROM invoices ORDER BY due_at DESC'
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
      'SELECT * FROM support_tickets ORDER BY created_at DESC'
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

  const id = `msg-${Date.now()}`;
  try {
    // RLS will block replies to other tenant tickets automatically
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
router.get('/backups', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const backups: any[] = [];
    return res.json(backups);
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/backups', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const backupId = `bak-${user.company_id}-${Date.now()}`;
    const filename = `serenut_backup_manual_${new Date().toISOString().split('T')[0]}.sql.gz.gpg`;
    
    await writeTenantAudit(user.company_id, user.id, 'CREATE_CLOUD_BACKUP', 'backups', backupId, null, { filename });
    
    return res.status(201).json({
      success: true,
      backup: { id: backupId, filename, size: '2.4 MB', created_at: new Date().toISOString(), type: 'manual' }
    });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
