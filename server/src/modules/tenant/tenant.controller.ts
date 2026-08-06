// server/src/modules/tenant/tenant.controller.ts
// Serenut OS — Company (Tenant) API
// Blueprint: api_contract.md — Section COMPANY
// Routes:
//   GET    /api/v1/company         — Get company profile
//   PATCH  /api/v1/company         — Update company profile
//   GET    /api/v1/stores          — (legacy) list stores
//   GET    /api/v1/devices         — List devices

import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest, requireActiveEntitlementForMutations } from '../../middleware/auth.middleware';
import { pgPool } from '../../config/database';
import { createError } from '../../config/error-codes';
import multer from 'multer';
import { decodeDataImage, publicLogoUrl, storeCompanyLogo } from './company-logo.service';

const router = Router();
const logoUpload = multer({
  storage: multer.memoryStorage(),
  limits: { fileSize: 3 * 1024 * 1024, files: 1 },
  fileFilter: (_req, file, callback) => callback(
    null,
    ['image/png', 'image/jpeg', 'image/webp'].includes(file.mimetype),
  ),
});
router.use(authenticateUser);
router.use(requireActiveEntitlementForMutations);

router.post('/company/logo', logoUpload.single('logo'), async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const isOwner = user.roles?.includes('owner') || user.roles?.includes('admin') || user.roles?.includes('sysadmin');
  if (!isOwner) return res.status(403).json(createError('AUTH005'));
  if (!req.file) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Geçerli bir PNG, JPEG veya WebP logo gereklidir.' } });
  }
  try {
    const stored = await storeCompanyLogo(user.company_id, req.file.buffer);
    res.setHeader('Cache-Control', 'no-store');
    return res.status(201).json({
      hash: stored.hash,
      original_url: publicLogoUrl(stored.originalPath, `${req.protocol}://${req.get('host')}`),
      display_url: publicLogoUrl(stored.displayPath, `${req.protocol}://${req.get('host')}`),
      print_url: publicLogoUrl(stored.printPath, `${req.protocol}://${req.get('host')}`),
    });
  } catch (error) {
    console.error('Company logo upload error:', error);
    return res.status(400).json({ error: { code: 'INVALID_IMAGE', message: 'Logo dosyası işlenemedi.' } });
  }
});

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
              version, created_at, updated_at
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

  const { expected_version, name, address, phone, email, tax_number, tax_office, owner_name, type, city, district, currency, logo_url } = req.body;

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
    if (email !== undefined) { updates.push(`email = $${idx++}`); values.push(email); }
    if (tax_number !== undefined) { updates.push(`tax_number = $${idx++}`); values.push(tax_number); }
    if (tax_office !== undefined) { updates.push(`tax_office = $${idx++}`); values.push(tax_office); }
    if (owner_name !== undefined) { updates.push(`owner_name = $${idx++}`); values.push(owner_name); }
    if (type !== undefined) { updates.push(`type = $${idx++}`); values.push(type); }
    if (city !== undefined) { updates.push(`city = $${idx++}`); values.push(city); }
    if (district !== undefined) { updates.push(`district = $${idx++}`); values.push(district); }
    if (currency !== undefined) { updates.push(`currency = $${idx++}`); values.push(currency); }
    if (logo_url !== undefined) {
      let normalizedLogoUrl = logo_url;
      if (typeof logo_url === 'string' && logo_url.startsWith('data:image/')) {
        const legacyBytes = decodeDataImage(logo_url);
        if (!legacyBytes || legacyBytes.length > 3 * 1024 * 1024) {
          return res.status(400).json({ error: { code: 'INVALID_IMAGE', message: 'Logo dosyası geçersiz veya 3 MB sınırını aşıyor.' } });
        }
        const stored = await storeCompanyLogo(user.company_id, legacyBytes);
        normalizedLogoUrl = publicLogoUrl(stored.displayPath, `${req.protocol}://${req.get('host')}`);
      }
      updates.push(`logo_url = $${idx++}`);
      values.push(normalizedLogoUrl);
    }

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
      `SELECT activation.id, activation.device_hash, activation.device_name AS name,
              activation.platform, activation.status, activation.last_seen_at,
              activation.activated_at AS created_at, runtime.current_version,
              runtime.channel, runtime.last_reported_at
       FROM device_activations activation
       LEFT JOIN device_runtime_state runtime ON runtime.device_activation_id = activation.id
       WHERE activation.company_id = $1
       ORDER BY activation.last_seen_at DESC NULLS LAST, activation.activated_at DESC`,
      [user.company_id]
    );
    return res.json(devicesRes.rows);
  } catch (err) {
    return res.status(500).json({ error: { code: 'SERVER_ERROR' } });
  }
});

export default router;
