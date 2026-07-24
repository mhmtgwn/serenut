// server/src/modules/branch/branch.controller.ts
// Serenut OS — Branches API
// Blueprint: api_contract.md — Section BRANCHES
// Routes:
//   GET    /api/v1/branches         — List branches
//   POST   /api/v1/branches         — Create branch
//   PATCH  /api/v1/branches/:id     — Update branch
//   DELETE /api/v1/branches/:id     — Delete branch (COMPANY401 if active devices)

import { Router, Response } from 'express';
import {
  authenticateUser,
  AuthenticatedRequest,
  requireActiveEntitlement,
} from '../../middleware/auth.middleware';
import { pgPool } from '../../config/database';
import { createError } from '../../config/error-codes';
import crypto from 'crypto';

const router = Router();
router.use(authenticateUser);
router.use(requireActiveEntitlement);

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
  const storeId = `store-${crypto.randomUUID()}`;
  const client = await pgPool.connect();

  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    await client.query(
      `INSERT INTO stores (id, company_id, name, address)
       VALUES ($1, $2, $3, $4)`,
      [storeId, user.company_id, name.trim(), address ?? null]
    );
    const result = await client.query(
      `INSERT INTO branches (id, company_id, store_id, name, address, phone)
       VALUES ($1, $2, $3, $4, $5, $6)
       RETURNING *`,
      [id, user.company_id, storeId, name.trim(), address ?? null, phone ?? null]
    );
    await client.query('COMMIT');
    return res.status(201).json(result.rows[0]);
  } catch (err: any) {
    await client.query('ROLLBACK');
    if (err.code === '23505') {
      return res.status(409).json({
        error: { code: 'DUPLICATE', message: 'Bu isimde bir şube zaten mevcut.' },
      });
    }
    console.error('Create branch error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Şube oluşturulamadı.' } });
  } finally {
    client.release();
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

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const result = await client.query(
      `UPDATE branches SET ${updates.join(', ')}
       WHERE id = $${idx++} AND company_id = $${idx}
       RETURNING *`,
      values
    );
    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Şube bulunamadı.' } });
    }
    const storeId = result.rows[0].store_id as string | null;
    if (storeId && (name !== undefined || address !== undefined)) {
      await client.query(
        `UPDATE stores
         SET name = COALESCE($1, name),
             address = COALESCE($2, address)
         WHERE id = $3 AND company_id = $4`,
        [name?.trim() ?? null, address ?? null, storeId, user.company_id]
      );
    }
    await client.query('COMMIT');
    return res.json(result.rows[0]);
  } catch (err) {
    await client.query('ROLLBACK');
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Şube güncellenemedi.' } });
  } finally {
    client.release();
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
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    // Check if branch has active devices (COMPANY401)
    const branchResult = await client.query(
      `SELECT store_id FROM branches WHERE id = $1 AND company_id = $2`,
      [id, user.company_id]
    );
    if (branchResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Şube bulunamadı.' } });
    }
    const storeId = branchResult.rows[0].store_id as string | null;

    const deviceCheck = storeId
      ? await client.query(
          `SELECT COUNT(*) as count FROM devices
           WHERE company_id = $1 AND store_id = $2 AND status = 'active'`,
          [user.company_id, storeId]
        )
      : { rows: [{ count: '0' }] };
    // Also check device_licenses for this branch's devices
    // For now, check if any device is linked to a license in this company
    const licCheck = storeId
      ? await client.query(
          `SELECT COUNT(*) as count
           FROM device_licenses dl
           JOIN devices d ON d.id = dl.device_id
           JOIN licenses l ON l.id = dl.license_id
           WHERE l.company_id = $1 AND d.store_id = $2`,
          [user.company_id, storeId]
        )
      : { rows: [{ count: '0' }] };

    if (parseInt(deviceCheck.rows[0].count, 10) > 0 ||
        parseInt(licCheck.rows[0].count, 10) > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json(createError('COMPANY401'));
    }

    const result = await client.query(
      `DELETE FROM branches WHERE id = $1 AND company_id = $2 RETURNING id`,
      [id, user.company_id]
    );

    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Şube bulunamadı.' } });
    }

    if (storeId) {
      await client.query(
        `DELETE FROM stores WHERE id = $1 AND company_id = $2`,
        [storeId, user.company_id]
      );
    }
    await client.query('COMMIT');
    return res.status(204).send();
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Delete branch error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Şube silinemedi.' } });
  } finally {
    client.release();
  }
});

export default router;
