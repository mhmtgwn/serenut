import { Router, Request, Response } from 'express';
import { AuthService } from './auth.service';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { rateLimiter } from '../../middleware/rate_limiter';
import { RealtimeBroadcastService } from '../realtime/broadcast.service';
import { createError } from '../../config/error-codes';

const router = Router();

// Apply strict rate limiting on Auth/Login/Forgot-Password
const authRateLimit = rateLimiter(5, 15 * 60 * 1000); // 5 attempts per 15 minutes

/**
 * @swagger
 * /auth/login:
 *   post:
 *     summary: User login
 *     tags: [Auth]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [email, password]
 *             properties:
 *               email: { type: string }
 *               password: { type: string }
 *     responses:
 *       200:
 *         description: Login successful — returns accessToken, refreshToken, trialStarted flag
 *       401:
 *         description: AUTH001 — Invalid credentials
 *       403:
 *         description: AUTH003 — Account suspended
 *       429:
 *         description: AUTH004 — Too many attempts
 */
router.post('/login', authRateLimit, async (req: Request, res: Response) => {
  const { email, password } = req.body;
  if (!email || !password) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'E-posta ve şifre zorunludur.' } });
  }

  const ipAddress = req.ip || req.socket.remoteAddress || undefined;
  const userAgent = req.headers['user-agent'] || undefined;

  try {
    const result = await AuthService.login(email, password, ipAddress, userAgent);

    // Publish UserLoggedIn event via WebSocket
    RealtimeBroadcastService.publishEvent(result.user.company_id, 'UserLoggedIn', {
      userId: result.user.id,
      email: result.user.email,
      name: result.user.name,
    }).catch(() => {});

    return res.json(result);
  } catch (err: any) {
    if (err.message === 'invalid_credentials') {
      return res.status(401).json(createError('AUTH001'));
    }
    if (err.message === 'user_suspended') {
      return res.status(403).json(createError('AUTH003'));
    }
    if (err.message === 'account_locked') {
      return res.status(429).json(createError('AUTH004'));
    }
    console.error('Login error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Giriş işlemi esnasında bir hata oluştu.' } });
  }
});

/**
 * @swagger
 * /auth/refresh:
 *   post:
 *     summary: Refresh access token
 *     tags: [Auth]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [refresh_token]
 *             properties:
 *               refresh_token: { type: string }
 *     responses:
 *       200:
 *         description: New accessToken issued
 *       401:
 *         description: AUTH002 — Invalid or expired refresh token
 */
router.post('/refresh', async (req: Request, res: Response) => {
  const { refresh_token } = req.body;
  if (!refresh_token) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Refresh token belirtilmelidir.' } });
  }

  const ipAddress = req.ip || req.socket.remoteAddress || undefined;
  const userAgent = req.headers['user-agent'] || undefined;

  try {
    const result = await AuthService.refresh(refresh_token, ipAddress, userAgent);
    return res.json(result);
  } catch (err: any) {
    if (err.message === 'invalid_refresh_token' || err.message === 'refresh_token_expired') {
      return res.status(401).json(createError('AUTH002'));
    }
    console.error('Refresh token error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Oturum yenileme esnasında hata oluştu.' } });
  }
});

router.post('/logout', async (req: Request, res: Response) => {
  const { refresh_token } = req.body;
  const authHeader = req.headers.authorization;
  const accessToken = authHeader && authHeader.startsWith('Bearer ') ? authHeader.split(' ')[1] : undefined;

  if (refresh_token) {
    try {
      if (accessToken) {
        try {
          const decoded = AuthService.verifyAccessToken(accessToken);
          RealtimeBroadcastService.publishEvent(decoded.company_id, 'UserLoggedOut', {
            userId: decoded.id,
            email: decoded.email,
          }).catch(() => {});
        } catch (_) {}
      }
      await AuthService.logout(refresh_token, accessToken);
    } catch (_) {}
  }
  return res.json({ success: true });
});

router.post('/change-password', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { old_password, new_password } = req.body;

  if (!old_password || !new_password) {
    return res.status(400).json({ error: 'missing_passwords', message: 'Eski ve yeni şifre belirtilmelidir.' });
  }

  try {
    await AuthService.changePassword(user.id, user.company_id, old_password, new_password);
    return res.json({ success: true, message: 'Şifreniz başarıyla güncellenmiştir. Güvenliğiniz için tüm aktif oturumlar kapatılmıştır.' });
  } catch (err: any) {
    if (err.message === 'invalid_old_password') {
      return res.status(400).json({ error: 'invalid_old_password', message: 'Eski şifre hatalı.' });
    }
    console.error('Change password error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/forgot-password', authRateLimit, async (req: Request, res: Response) => {
  const { email } = req.body;
  if (!email) {
    return res.status(400).json({ error: 'missing_email' });
  }

  try {
    await AuthService.forgotPassword(email);
    // Return standard success to avoid email enum attacks
    return res.json({ success: true, message: 'Eğer e-posta adresi kayıtlı ise sıfırlama linki gönderilecektir.' });
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/reset-password', authRateLimit, async (req: Request, res: Response) => {
  const { token, newPassword } = req.body;
  if (!token || !newPassword) {
    return res.status(400).json({ error: 'missing_fields', message: 'Token ve yeni şifre zorunludur.' });
  }
  if (newPassword.length < 8) {
    return res.status(400).json({ error: 'weak_password', message: 'Şifre en az 8 karakter olmalıdır.' });
  }

  try {
    const success = await AuthService.resetPassword(token, newPassword);
    if (!success) {
      return res.status(400).json({ error: 'invalid_token', message: 'Geçersiz veya süresi dolmuş token.' });
    }
    return res.json({ success: true, message: 'Şifreniz başarıyla güncellendi.' });
  } catch (err) {
    console.error('Reset password error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// ── SELF-SERVICE REGISTRATION ────────────────────────────────────────────────
// Creates a new company tenant + owner/admin user in a single atomic transaction.
router.post('/register', authRateLimit, async (req: Request, res: Response) => {
  const { company_name, name, email, password, phone, tax_number } = req.body;

  if (!company_name || !name || !email || !password) {
    return res.status(400).json({
      error: 'missing_fields',
      message: 'Firma adı, ad soyad, e-posta ve şifre zorunludur.'
    });
  }

  if (password.length < 8) {
    return res.status(400).json({
      error: 'weak_password',
      message: 'Şifre en az 8 karakter olmalıdır.'
    });
  }

  const crypto = require('crypto');
  const { pgPool } = require('../../config/database');

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    // Check if email already exists (global uniqueness for the owner account)
    const emailCheck = await client.query(
      'SELECT id FROM users WHERE email = $1',
      [email]
    );
    if (emailCheck.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: 'email_taken',
        message: 'Bu e-posta adresiyle zaten bir hesap mevcut. Lütfen giriş yapın.'
      });
    }

    // Create company
    const companyId = `comp-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    await client.query(
      `INSERT INTO companies (id, name, tax_number, phone, email, status)
       VALUES ($1, $2, $3, $4, $5, 'trial')`,
      [companyId, company_name, tax_number || `TEMP-${Date.now()}`, phone || null, email]
    );

    // Create owner user
    const userId = `usr-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    const passwordHash = await AuthService.hashPassword(password);
    await client.query(
      `INSERT INTO users (id, company_id, name, email, password_hash, is_active)
       VALUES ($1, $2, $3, $4, $5, true)`,
      [userId, companyId, name, email, passwordHash]
    );

    // Assign 'owner' role if it exists
    const ownerRoleRes = await client.query(
      `SELECT id FROM roles WHERE name = 'owner' LIMIT 1`
    );
    if (ownerRoleRes.rows.length > 0) {
      await client.query(
        `INSERT INTO user_roles (user_id, role_id) VALUES ($1, $2)`,
        [userId, ownerRoleRes.rows[0].id]
      );
    }

    // Create subscription with trial_started_at = NULL (AC 1.1)
    // Trial does NOT start at registration — it starts on FIRST LOGIN.
    // auth.service.ts login() checks trial_started_at IS NULL and sets it.
    try {
      const subId = `sub-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
      await client.query(
        `INSERT INTO subscriptions
           (id, company_id, plan_id, status, current_period_start, current_period_end,
            trial_started_at, trial_ends_at, payment_retry_count)
         VALUES ($1, $2, 'plan-free', 'trialing', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '30 days',
                 NULL, NULL, 0)`,
        [subId, companyId]
      );
    } catch (e) {
      console.error('Failed to create subscription:', e);
    }

    await client.query('COMMIT');

    // Auto-login: issue token pair
    const ipAddress = req.ip || req.socket.remoteAddress || undefined;
    const userAgent = req.headers['user-agent'] || undefined;
    const loginResult = await AuthService.login(email, password, ipAddress, userAgent);

    return res.status(201).json({
      ...loginResult,
      message: 'Hesabınız oluşturuldu. 30 günlük ücretsiz deneme başladı!'
    });
  } catch (err: any) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Register error:', err);
    return res.status(500).json({ error: 'server_error', message: 'Kayıt işlemi sırasında bir hata oluştu.' });
  } finally {
    client.release();
  }
});

export default router;
