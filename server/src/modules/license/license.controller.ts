import { Router, Request, Response } from 'express';
import { LicenseService } from './license.service';
import { authenticateUser, requireRole, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { rateLimiter } from '../../middleware/rate_limiter';
import { incrementLicenseValidation } from '../../utils/telemetry';

const router = Router();
const licenseRateLimit = rateLimiter(20, 60 * 1000); // 20 requests per minute


// Secured Activation Route (enforces authentication to lock down activation scope)
router.post('/activate', licenseRateLimit, async (req: Request, res: Response) => {
  const { license_key, device_hash, device_name, fingerprint } = req.body;
  if (!license_key || !device_hash || !device_name) {
    incrementLicenseValidation(false);
    return res.status(400).json({ error: 'missing_fields', message: 'Lisans anahtarı, cihaz imzası ve cihaz adı zorunludur.' });
  }

  try {
    const result = await LicenseService.activate(license_key, device_hash, device_name, undefined, fingerprint);
    incrementLicenseValidation(true);
    return res.json(result);
  } catch (err: any) {
    incrementLicenseValidation(false);
    if (err.message === 'company_mismatch') {
      return res.status(403).json({ error: 'company_mismatch', message: 'Bu lisans anahtarı işletmeniz ile eşleşmiyor.' });
    }
    if (err.message === 'invalid_license_key') {
      return res.status(404).json({ error: 'invalid_license_key', message: 'Geçersiz lisans anahtarı.' });
    }
    if (err.message === 'license_inactive') {
      return res.status(403).json({ error: 'license_inactive', message: 'Lisans şu anda aktif değil.' });
    }
    if (err.message === 'license_expired') {
      return res.status(403).json({ error: 'license_expired', message: 'Lisansın geçerlilik süresi dolmuştur.' });
    }
    if (err.message === 'device_blocked') {
      return res.status(403).json({ error: 'device_blocked', message: 'Cihazın erişimi engellenmiştir.' });
    }
    if (err.message === 'device_limit_exceeded') {
      return res.status(403).json({ error: 'device_limit_exceeded', message: 'Bu lisans için tanımlı maksimum cihaz sınırına ulaşıldı.' });
    }
    if (err.message === 'hardware_tampered_limit_exceeded') {
      return res.status(403).json({ error: 'hardware_tampered_limit_exceeded', message: 'Cihaz donanım değişikliği limiti aşılmıştır.' });
    }
    console.error('Activation error:', err);
    return res.status(500).json({ error: 'server_error', message: 'Lisans aktivasyonu esnasında hata oluştu.' });
  }
});

// Public Validation Route
router.post('/validate', licenseRateLimit, async (req: Request, res: Response) => {
  const { device_hash } = req.body;
  if (!device_hash) {
    incrementLicenseValidation(false);
    return res.status(400).json({ error: 'missing_device_hash', message: 'Cihaz imzası zorunludur.' });
  }

  try {
    const isValid = await LicenseService.validate(device_hash);
    incrementLicenseValidation(isValid);
    return res.json({ valid: isValid });
  } catch (err) {
    incrementLicenseValidation(false);
    console.error('Validation error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// --- Sprint 3: POS Heartbeat Route ---
router.post('/heartbeat', licenseRateLimit, async (req: Request, res: Response) => {
  const { license_key, device_hash, fingerprint } = req.body;
  if (!license_key || !device_hash) {
    incrementLicenseValidation(false);
    return res.status(400).json({ error: 'missing_fields', message: 'Lisans anahtarı ve cihaz imzası zorunludur.' });
  }

  try {
    const result = await LicenseService.heartbeat(license_key, device_hash, fingerprint);
    incrementLicenseValidation(true);
    return res.json(result);
  } catch (err: any) {
    incrementLicenseValidation(false);
    if (err.message === 'invalid_association') {
      return res.status(404).json({ error: 'invalid_association', message: 'Cihaz bu lisans ile eşleşmiyor.' });
    }
    if (err.message === 'license_suspended') {
      return res.status(403).json({ error: 'license_suspended', message: 'Lisans askıya alınmıştır veya bloke edilmiştir.' });
    }
    if (err.message === 'license_expired') {
      return res.status(403).json({ error: 'license_expired', message: 'Lisans süresi dolmuştur.' });
    }
    if (err.message === 'device_blocked') {
      return res.status(403).json({ error: 'device_blocked', message: 'Cihaz bloke edilmiştir.' });
    }
    if (err.message === 'hardware_tampered_limit_exceeded') {
      return res.status(403).json({ error: 'hardware_tampered_limit_exceeded', message: 'Cihaz donanım değişikliği limiti aşılmıştır.' });
    }
    console.error('Heartbeat error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// --- Sprint 3: Protected Admin Routes ---
router.use(authenticateUser);

// GET /licenses/status (Admin/Owner get details)
router.get('/status', async (req: AuthenticatedRequest, res: Response) => {
  const licenseKey = req.query.license_key as string;
  if (!licenseKey) {
    return res.status(400).json({ error: 'missing_license_key' });
  }

  try {
    const details = await LicenseService.getStatus(licenseKey);
    // Enforce Tenant Isolation: Check if license belongs to the authenticated user's company
    if (details.company_id !== req.user!.company_id && !req.user!.roles.includes('sysadmin')) {
      return res.status(403).json({ error: 'forbidden', message: 'Bu lisans bilgilerine erişim yetkiniz yok.' });
    }
    return res.json(details);
  } catch (err: any) {
    if (err.message === 'invalid_license_key') {
      return res.status(404).json({ error: 'invalid_license_key' });
    }
    console.error('Fetch status error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// POST /licenses/renew (Extend license)
router.post('/renew', requireRole('owner'), async (req: AuthenticatedRequest, res: Response) => {
  const { license_key, extend_days } = req.body;
  if (!license_key || !extend_days) {
    return res.status(400).json({ error: 'missing_fields' });
  }

  try {
    // Check tenant association before renewing
    const details = await LicenseService.getStatus(license_key);
    if (details.company_id !== req.user!.company_id && !req.user!.roles.includes('sysadmin')) {
      return res.status(403).json({ error: 'forbidden' });
    }

    const result = await LicenseService.renew(license_key, parseInt(extend_days, 10));

    // Broadcast LicenseUpdated event
    try {
      const { RealtimeBroadcastService } = require('../realtime/broadcast.service');
      await RealtimeBroadcastService.publishEvent(req.user!.company_id, 'LicenseUpdated', {
        licenseKey: license_key,
        status: 'renewed',
        extendDays: extend_days,
        expiresAt: result.expires_at,
      });
    } catch (_) {}

    return res.json(result);
  } catch (err: any) {
    if (err.message === 'invalid_license_key') {
      return res.status(404).json({ error: 'invalid_license_key' });
    }
    console.error('Renew error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// POST /licenses/revoke (Suspend license - global admin only)
router.post('/revoke', requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { license_key } = req.body;
  if (!license_key) {
    return res.status(400).json({ error: 'missing_license_key' });
  }

  try {
    await LicenseService.revoke(license_key);
    return res.json({ success: true, message: 'Lisans başarıyla bloke edilmiş ve tüm bağlı POS terminalleri engellenmiştir.' });
  } catch (err: any) {
    if (err.message === 'invalid_license_key') {
      return res.status(404).json({ error: 'invalid_license_key' });
    }
    console.error('Revoke error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
