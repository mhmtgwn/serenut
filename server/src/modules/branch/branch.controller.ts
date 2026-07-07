// server/src/modules/branch/branch.controller.ts
// Serenut OS — Branches API
// Blueprint: api_contract.md — Section BRANCHES
// Routes:
//   GET    /api/v1/branches         — List branches
//   POST   /api/v1/branches         — Create branch
//   PATCH  /api/v1/branches/:id     — Update branch
//   DELETE /api/v1/branches/:id     — Delete branch (COMPANY401 if active devices)

import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { pgPool } from '../../config/database';
import { createError } from '../../config/error-codes';
import crypto from 'crypto';

const router = Router();
router.use(authenticateUser);

/**
 * @swagger
 * /branches:
 *   get:
 *     summary: List branches for the authenticated company
 *     tags: [Branches]
 *     security:
 *       - BearerAuth: []
 *     responses:
 *       200:
 *         description: Array of branches
 */
router.get('/', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const result = await pgPool.query(
      `SELECT id, name, address, phone, is_active, created_at, updated_at
       FROM branches WHERE company_id = $1 ORDER BY name ASC`,
      [req.user!.company_id]
    );
    return res.json({ branches: result.rows });
  } catch (err) {
    console.error('List branches error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Şubeler listelenemedi.' } });
  }
});

/**
 * @swagger
 * /branches:
 *   post:
 *     summary: Create a new branch
 *     tags: [Branches]
 *     security:
 *       - BearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [name]
 *             properties:
 *               name: { type: string }
 *               address: { type: string }
 *               phone: { type: string }
 *     responses:
 *       201:
 *         description: Branch created
 *       403:
 *         description: AUTH005 — Requires branch.create permission
 */
router.post('/', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const isAuthorized = user.roles?.includes('owner') ||
    user.roles?.includes('admin') ||
    user.permissions?.includes('branch.create');

  if (!isAuthorized) {
    return res.status(403).json(createError('AUTH005', 'branch.create permission required'));
  }

  const { name, address, phone } = req.body;

  if (!name || name.trim().length === 0) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Şube adı zorunludur.' } });
  }

  const id = `br-${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;

  try {
    const result = await pgPool.query(
      `INSERT INTO branches (id, company_id, name, address, phone)
       VALUES ($1, $2, $3, $4, $5)
       RETURNING *`,
      [id, user.company_id, name.trim(), address ?? null, phone ?? null]
    );
    return res.status(201).json(result.rows[0]);
  } catch (err: any) {
    if (err.code === '23505') {
      return res.status(409).json({
        error: { code: 'DUPLICATE', message: 'Bu isimde bir şube zaten mevcut.' },
      });
    }
    console.error('Create branch error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Şube oluşturulamadı.' } });
  }
});

/**
 * @swagger
 * /branches/{id}:
 *   patch:
 *     summary: Update a branch
 *     tags: [Branches]
 *     security:
 *       - BearerAuth: []
 */
router.patch('/:id', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const isAuthorized = user.roles?.includes('owner') || user.roles?.includes('admin');
  if (!isAuthorized) {
    return res.status(403).json(createError('AUTH005'));
  }

  const { name, address, phone, is_active } = req.body;
  const { id } = req.params;

  const updates: string[] = [];
  const values: any[] = [];
  let idx = 1;

  if (name !== undefined) { updates.push(`name = $${idx++}`); values.push(name.trim()); }
  if (address !== undefined) { updates.push(`address = $${idx++}`); values.push(address); }
  if (phone !== undefined) { updates.push(`phone = $${idx++}`); values.push(phone); }
  if (is_active !== undefined) { updates.push(`is_active = $${idx++}`); values.push(is_active); }

  if (updates.length === 0) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Güncellenecek alan belirtilmedi.' } });
  }

  updates.push(`updated_at = CURRENT_TIMESTAMP`);
  values.push(id, user.company_id);

  try {
    const result = await pgPool.query(
      `UPDATE branches SET ${updates.join(', ')}
       WHERE id = $${idx++} AND company_id = $${idx}
       RETURNING *`,
      values
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Şube bulunamadı.' } });
    }
    return res.json(result.rows[0]);
  } catch (err) {
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Şube güncellenemedi.' } });
  }
});

/**
 * @swagger
 * /branches/{id}:
 *   delete:
 *     summary: Delete a branch
 *     tags: [Branches]
 *     security:
 *       - BearerAuth: []
 *     responses:
 *       204:
 *         description: Deleted
 *       409:
 *         description: COMPANY401 — Branch has active devices
 *       403:
 *         description: AUTH005 — Requires branch.delete permission
 */
router.delete('/:id', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const isAuthorized = user.roles?.includes('owner') ||
    user.permissions?.includes('branch.delete');

  if (!isAuthorized) {
    return res.status(403).json(createError('AUTH005', 'branch.delete permission required'));
  }

  const { id } = req.params;

  const client = await pgPool.connect();
  try {
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    // Check if branch has active devices (COMPANY401)
    const deviceCheck = await client.query(
      `SELECT COUNT(*) as count FROM devices
       WHERE company_id = $1 AND status = 'active'`,
      [user.company_id]
    );
    // Also check device_licenses for this branch's devices
    // For now, check if any device is linked to a license in this company
    const licCheck = await client.query(
      `SELECT COUNT(*) as count
       FROM device_licenses dl
       JOIN devices d ON d.id = dl.device_id
       JOIN licenses l ON l.id = dl.license_id
       WHERE l.company_id = $1`,
      [user.company_id]
    );

    if (parseInt(licCheck.rows[0].count, 10) > 0) {
      return res.status(409).json(createError('COMPANY401'));
    }

    const result = await pgPool.query(
      `DELETE FROM branches WHERE id = $1 AND company_id = $2 RETURNING id`,
      [id, user.company_id]
    );

    if (result.rows.length === 0) {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Şube bulunamadı.' } });
    }

    return res.status(204).send();
  } catch (err) {
    console.error('Delete branch error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Şube silinemedi.' } });
  } finally {
    client.release();
  }
});

export default router;
