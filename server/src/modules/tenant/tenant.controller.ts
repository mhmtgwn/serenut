// server/src/modules/tenant/tenant.controller.ts
// Serenut OS — Company (Tenant) API
// Blueprint: api_contract.md — Section COMPANY
// Routes:
//   GET    /api/v1/company         — Get company profile
//   PATCH  /api/v1/company         — Update company profile
//   GET    /api/v1/stores          — (legacy) list stores
//   GET    /api/v1/devices         — List devices

import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { pgPool } from '../../config/database';
import { createError } from '../../config/error-codes';

const router = Router();
router.use(authenticateUser);

/**
 * @swagger
 * /company:
 *   get:
 *     summary: Get company profile
 *     tags: [Company]
 *     security:
 *       - BearerAuth: []
 *     responses:
 *       200:
 *         description: Company profile
 *       404:
 *         description: Company not found
 */
router.get('/company', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const compRes = await pgPool.query(
      `SELECT id, name, tax_number, tax_office, phone, email, address, status,
              owner_name, type, city, district, currency, logo_url,
              created_at, updated_at
       FROM companies WHERE id = $1`,
      [user.company_id]
    );
    if (compRes.rows.length === 0) {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Şirket bulunamadı.' } });
    }
    return res.json(compRes.rows[0]);
  } catch (err) {
    console.error('Fetch company error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Şirket bilgisi alınamadı.' } });
  }
});

/**
 * @swagger
 * /company:
 *   patch:
 *     summary: Update company profile
 *     tags: [Company]
 *     security:
 *       - BearerAuth: []
 *     requestBody:
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               name: { type: string }
 *               address: { type: string }
 *               phone: { type: string }
 *               tax_office: { type: string }
 *               owner_name: { type: string }
 *               type: { type: string }
 *               city: { type: string }
 *               district: { type: string }
 *               currency: { type: string }
 *               logo_url: { type: string }
 *     responses:
 *       200:
 *         description: Updated company object
 *       403:
 *         description: AUTH005 — Insufficient permissions
 */
router.patch('/company', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;

  // Only owner/admin/sysadmin can update company profile
  const isOwner = user.roles?.includes('owner') || user.roles?.includes('admin') || user.roles?.includes('sysadmin');
  if (!isOwner) {
    return res.status(403).json(createError('AUTH005'));
  }

  const { expected_version, name, address, phone, tax_office, owner_name, type, city, district, currency, logo_url } = req.body;

  if (expected_version === undefined || expected_version === null) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'expected_version gereklidir.' } });
  }

  try {
    // 1. Fetch current server version
    const currentRes = await pgPool.query('SELECT version FROM companies WHERE id = $1', [user.company_id]);
    if (currentRes.rows.length === 0) {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Şirket bulunamadı.' } });
    }

    const currentServerVersion = currentRes.rows[0].version;

    // 2. Exact version equality check
    if (Number(expected_version) !== Number(currentServerVersion)) {
      return res.status(409).json({
        error: {
          code: 'CONFLICT',
          message: `Sürüm çakışması: Beklenen sürüm ${expected_version}, sunucu sürümü ${currentServerVersion}.`
        }
      });
    }

    const updates: string[] = [];
    const values: any[] = [];
    let idx = 1;

    if (name !== undefined) { updates.push(`name = $${idx++}`); values.push(name.trim()); }
    if (address !== undefined) { updates.push(`address = $${idx++}`); values.push(address); }
    if (phone !== undefined) { updates.push(`phone = $${idx++}`); values.push(phone); }
    if (tax_office !== undefined) { updates.push(`tax_office = $${idx++}`); values.push(tax_office); }
    if (owner_name !== undefined) { updates.push(`owner_name = $${idx++}`); values.push(owner_name); }
    if (type !== undefined) { updates.push(`type = $${idx++}`); values.push(type); }
    if (city !== undefined) { updates.push(`city = $${idx++}`); values.push(city); }
    if (district !== undefined) { updates.push(`district = $${idx++}`); values.push(district); }
    if (currency !== undefined) { updates.push(`currency = $${idx++}`); values.push(currency); }
    if (logo_url !== undefined) { updates.push(`logo_url = $${idx++}`); values.push(logo_url); }

    if (updates.length === 0) {
      return res.status(400).json({ error: { code: 'VALIDATION', message: 'Güncellenecek alan belirtilmedi.' } });
    }

    // Atomic version increment in same statement
    updates.push(`version = version + 1`);
    updates.push(`updated_at = CURRENT_TIMESTAMP`);

    const companyIdIdx = idx++;
    const expectedVersionIdx = idx++;
    values.push(user.company_id);
    values.push(expected_version);

    // 3. Update atomically using version filter
    const updateRes = await pgPool.query(
      `UPDATE companies SET ${updates.join(', ')} WHERE id = $${companyIdIdx} AND version = $${expectedVersionIdx} RETURNING *`,
      values
    );

    if (updateRes.rowCount === 0) {
      return res.status(409).json({
        error: {
          code: 'CONFLICT',
          message: 'Sürüm çakışması: Güncelleme sırasında veri başka bir işlem tarafından değiştirildi.'
        }
      });
    }

    return res.json(updateRes.rows[0]);
  } catch (err) {
    console.error('Update company error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Şirket güncellenemedi.' } });
  }
});

// ── LEGACY ROUTES (backward compat) ──────────────────────────────────────────

// GET /companies/current — legacy alias for GET /company
router.get('/companies/current', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const compRes = await pgPool.query(
      `SELECT id, name, tax_number, tax_office, phone, email, address, logo_url, status,
              owner_name, type, city, district, currency, created_at
       FROM companies WHERE id = $1`,
      [user.company_id]
    );
    if (compRes.rows.length === 0) {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Şirket bulunamadı.' } });
    }
    return res.json(compRes.rows[0]);
  } catch (err) {
    return res.status(500).json({ error: { code: 'SERVER_ERROR' } });
  }
});

// GET /stores — legacy store list
router.get('/stores', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const storesRes = await pgPool.query(
      'SELECT id, name, address, created_at FROM stores WHERE company_id = $1 ORDER BY name ASC',
      [user.company_id]
    );
    return res.json(storesRes.rows);
  } catch (err) {
    return res.status(500).json({ error: { code: 'SERVER_ERROR' } });
  }
});

// GET /devices — device list
router.get('/devices', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const devicesRes = await pgPool.query(
      `SELECT id, device_hash, name, status, last_active_at, created_at
       FROM devices WHERE company_id = $1 ORDER BY created_at DESC`,
      [user.company_id]
    );
    return res.json(devicesRes.rows);
  } catch (err) {
    return res.status(500).json({ error: { code: 'SERVER_ERROR' } });
  }
});

export default router;
