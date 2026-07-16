import { Router, Request, Response } from 'express';
import { AuthService } from './auth.service';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { authLimiter, passwordResetLimiter, signupLimiter } from '../../middleware/rate-limit.middleware';
import { RealtimeBroadcastService } from '../realtime/broadcast.service';
import { createError } from '../../config/error-codes';
import { logger } from '../../config/logger';
import { pgPool } from '../../config/database';
import { enqueueNotification } from '../../workers/notification.worker';
import { emailVerificationEmail } from '../notifications/email.templates';
import crypto from 'crypto';

const router = Router();

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
router.post('/login', authLimiter, async (req: Request, res: Response) => {
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
    if (err.message === 'email_not_verified') {
      return res.status(403).json({
        error: { code: 'EMAIL_NOT_VERIFIED', message: 'Giriş yapmadan önce e-posta adresinizi doğrulayın.' },
        can_resend: true
      });
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
 * /auth/login/sub:
 *   post:
 *     summary: Sub-user login (cashier, manager, staff) using business_code + username + PIN
 *     tags: [Auth]
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [business_code, username, pin]
 *             properties:
 *               business_code: { type: string, example: "SRNTT-7X9K" }
 *               username: { type: string, example: "ahmet_kasiyer" }
 *               pin: { type: string, example: "1234" }
 *     responses:
 *       200:
 *         description: Login successful
 *       401:
 *         description: Invalid credentials
 *       429:
 *         description: Too many attempts
 */
router.post('/login/sub', authLimiter, async (req: Request, res: Response) => {
  const { business_code, username, pin } = req.body;
  if (!business_code || !username || !pin) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'İşletme kodu, kullanıcı adı ve PIN zorunludur.' } });
  }

  const ipAddress = req.ip || req.socket.remoteAddress || undefined;
  const userAgent = req.headers['user-agent'] || undefined;

  try {
    const result = await AuthService.loginSubUser(business_code, username, pin, ipAddress, userAgent);

    RealtimeBroadcastService.publishEvent(result.user.company_id, 'UserLoggedIn', {
      userId: result.user.id,
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
    if (err.message === 'business_code_not_found') {
      return res.status(401).json({ error: { code: 'AUTH001', message: 'İşletme kodu, kullanıcı adı veya PIN hatalı.' } });
    }
    console.error('Sub-user login error:', err);
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
          }).catch((err) => { logger.warn('Failed to publish logout event:', err); });
        } catch (err) { logger.warn('Failed to verify access token during logout:', err); }
      }
      await AuthService.logout(refresh_token, accessToken);
    } catch (err) {
      logger.error('Logout failure:', err);
    }
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

router.post('/forgot-password', passwordResetLimiter, async (req: Request, res: Response) => {
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

router.post('/reset-password', passwordResetLimiter, async (req: Request, res: Response) => {
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
router.post('/register', signupLimiter, async (req: Request, res: Response) => {
  const { company_name, name, email, password, phone, tax_number, tax_office, city, district, address,
    accept_terms, accept_privacy, accept_kvkk, accept_marketing } = req.body;
  const normalizedEmail = String(email || '').trim().toLowerCase();
  const normalizedTaxNumber = String(tax_number || '').replace(/\D/g, '');

  if (!company_name || !name || !normalizedEmail || !password || !normalizedTaxNumber) {
    return res.status(400).json({
      error: 'missing_fields',
      message: 'Firma adı, ad soyad, e-posta, şifre ve TC/VKN zorunludur.'
    });
  }

  if (![10, 11].includes(normalizedTaxNumber.length)) {
    return res.status(400).json({ error: 'invalid_tax_number', message: 'TC 11, VKN 10 haneli olmalıdır.' });
  }
  if (!accept_terms || !accept_privacy || !accept_kvkk) {
    return res.status(400).json({ error: 'legal_consent_required', message: 'Üyelik, gizlilik ve KVKK onayları zorunludur.' });
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
  let verificationToken = '';
  let registeredUserId = '';
  let registeredCompanyId = '';
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    // Check if email already exists (global uniqueness for the owner account)
    const emailCheck = await client.query(
      'SELECT id FROM users WHERE email = $1',
      [normalizedEmail]
    );
    if (emailCheck.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: 'email_taken',
        message: 'Bu e-posta adresiyle zaten bir hesap mevcut. Lütfen giriş yapın.'
      });
    }

    const taxCheck = await client.query(
      `SELECT id FROM companies WHERE REGEXP_REPLACE(tax_number, '\\D', '', 'g') = $1 LIMIT 1`,
      [normalizedTaxNumber]
    );
    if (taxCheck.rows.length > 0) {
      await client.query('ROLLBACK');
      return res.status(409).json({
        error: 'tax_number_taken',
        message: 'Bu TC/VKN ile kayıtlı bir firma var. Firma sahibinden kullanıcı hesabı isteyin.'
      });
    }

    // Create company
    const companyId = `comp-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    await client.query(
      `INSERT INTO companies (id, name, owner_name, tax_number, tax_office, phone, email, city, district, address, status)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'trial')`,
      [companyId, company_name, name, normalizedTaxNumber, tax_office || null, phone || null, normalizedEmail,
        city || null, district || null, address || null]
    );

    // Create owner user
    const userId = `usr-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    const passwordHash = await AuthService.hashPassword(password);
    await client.query(
      `INSERT INTO users (id, company_id, name, email, password_hash, is_active)
       VALUES ($1, $2, $3, $4, $5, false)`,
      [userId, companyId, name, normalizedEmail, passwordHash]
    );
    registeredUserId = userId;
    registeredCompanyId = companyId;

    const consentVersion = process.env.LEGAL_DOCUMENT_VERSION || '2026-07';
    const consentRows = [
      ['terms', true], ['privacy', true], ['kvkk', true], ['marketing', Boolean(accept_marketing)]
    ];
    for (const [consentType, accepted] of consentRows) {
      await client.query(
        `INSERT INTO user_legal_consents
          (id, user_id, consent_type, document_version, accepted, ip_address, user_agent)
         VALUES ($1,$2,$3,$4,$5,$6,$7)`,
        [`consent-${userId}-${consentType}`, userId, consentType, consentVersion, accepted,
          req.ip || null, req.headers['user-agent'] || null]
      );
    }

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

    // Registration never selects a paid plan. Every company starts with the
    // Starter trial contract; the clock begins on first device activation.
    const trialPlanId = 'plan-basic';
    const trialDeviceLimit = 1;
    const trialStoreLimit = 1;

    // Create subscription with trial_started_at = NULL (AC 1.1)
    // Trial does NOT start at registration, nor on first login.
    // It starts on FIRST POS DEVICE ACTIVATION via LicenseService.activate().
      const subId = `sub-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
      await client.query(
        `INSERT INTO subscriptions
           (id, company_id, plan_id, status, current_period_start, current_period_end,
            trial_started_at, trial_ends_at, payment_retry_count)
         VALUES ($1, $2, $3, 'trialing', CURRENT_TIMESTAMP, CURRENT_TIMESTAMP + INTERVAL '30 days',
                 NULL, NULL, 0)`,
        [subId, companyId, trialPlanId]
      );

      // Generate a canonical license key and trial entitlement during registration!
      const parts = [];
      for (let i = 0; i < 4; i++) {
        parts.push(crypto.randomBytes(2).toString('hex').toUpperCase());
      }
      const licenseKey = `SRNT-${parts.join('-')}`;

      // Insert into license_entitlements (free trial limits enforce authorization boundaries)
      const entId = `ent-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
      await client.query(`
        INSERT INTO license_entitlements (
          id, company_id, subscription_id, plan_id,
          status, device_limit, store_limit,
          valid_from, valid_until, token_version,
          license_key, created_at, updated_at
        )
        VALUES ($1, $2, $3, $4, 'trial', $5, $6, NOW(), NOW() + INTERVAL '30 days', 1, $7, NOW(), NOW())
      `, [entId, companyId, subId, trialPlanId, trialDeviceLimit, trialStoreLimit, licenseKey]);

      // Sync legacy licenses table (start on trial with 1 device)
      await client.query(`
        INSERT INTO licenses (
          id, company_id, license_key, tier,
          allowed_devices_count, status, expires_at, created_at
        )
        VALUES ($1, $2, $3, 'trial', 1, 'active', NOW() + INTERVAL '30 days', NOW())
      `, [
        `lic-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`,
        companyId,
        licenseKey
      ]);

      verificationToken = crypto.randomBytes(32).toString('hex');
      const verificationHash = crypto.createHash('sha256').update(verificationToken).digest('hex');
      await client.query(
        `INSERT INTO email_verification_tokens (id, user_id, token_hash, expires_at)
         VALUES ($1, $2, $3, NOW() + INTERVAL '30 minutes')`,
        [`evt-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`, userId, verificationHash]
      );

    await client.query('COMMIT');

    try {
    const publicUrl = (process.env.PUBLIC_URL || 'https://serenut.com').replace(/\/$/, '');
    const message = emailVerificationEmail({
      userName: name,
      verificationLink: `${publicUrl}/api/v1/auth/verify-email?token=${verificationToken}`
    });
    const notificationId = `notif-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    await pgPool.query(
      `INSERT INTO notification_queue (id, company_id, channel, recipient, title, body, status, scheduled_at)
       VALUES ($1, $2, 'email', $3, $4, $5, 'pending', NOW())`,
      [notificationId, registeredCompanyId, normalizedEmail, message.subject, message.html]
    );
    await enqueueNotification({
      notification_id: notificationId,
      company_id: registeredCompanyId,
      channel: 'email',
      recipient: normalizedEmail,
      title: message.subject,
      body: message.html
    });
    } catch (notificationError) {
      logger.error('Verification email could not be queued after registration', notificationError);
    }

    return res.status(201).json({
      user_id: registeredUserId,
      email_verification_required: true,
      message: 'Hesabınız oluşturuldu. Giriş yapabilmek için e-posta adresinizi doğrulayın.'
    });
  } catch (err: any) {
    await client.query('ROLLBACK').catch(() => {});
    console.error('Register error:', err);
    return res.status(500).json({ error: 'server_error', message: 'Kayıt işlemi sırasında bir hata oluştu.' });
  } finally {
    client.release();
  }
});

router.get('/verify-email', async (req: Request, res: Response) => {
  const token = String(req.query.token || '');
  if (!/^[a-f0-9]{64}$/i.test(token)) {
    return res.status(400).send('Geçersiz doğrulama bağlantısı.');
  }

  const tokenHash = crypto.createHash('sha256').update(token).digest('hex');
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const result = await client.query(
      `SELECT id, user_id FROM email_verification_tokens
       WHERE token_hash = $1 AND used_at IS NULL AND expires_at > NOW()
       FOR UPDATE`,
      [tokenHash]
    );
    if (result.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(400).send('Doğrulama bağlantısının süresi dolmuş veya bağlantı daha önce kullanılmış.');
    }
    await client.query(
      `UPDATE users SET email_verified_at = NOW(), is_active = true WHERE id = $1`,
      [result.rows[0].user_id]
    );
    await client.query(
      `UPDATE email_verification_tokens SET used_at = NOW()
       WHERE user_id = $1 AND used_at IS NULL`,
      [result.rows[0].user_id]
    );
    await client.query('COMMIT');
    return res.redirect(302, '/app/#login?verified=1');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    logger.error('Email verification failed', err);
    return res.status(500).send('E-posta doğrulanamadı. Lütfen yeniden deneyin.');
  } finally {
    client.release();
  }
});

router.post('/resend-verification', signupLimiter, async (req: Request, res: Response) => {
  const normalizedEmail = String(req.body.email || '').trim().toLowerCase();
  const genericResponse = {
    message: 'Doğrulanmamış bir hesap varsa yeni bağlantı gönderildi.'
  };
  if (!normalizedEmail) return res.status(200).json(genericResponse);

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const userResult = await client.query(
      `SELECT id, company_id, name FROM users
       WHERE LOWER(email) = $1 AND email_verified_at IS NULL AND is_active = false
       LIMIT 1`,
      [normalizedEmail]
    );
    if (userResult.rows.length === 0) {
      await client.query('COMMIT');
      return res.status(200).json(genericResponse);
    }
    const user = userResult.rows[0];
    const rawToken = crypto.randomBytes(32).toString('hex');
    const tokenHash = crypto.createHash('sha256').update(rawToken).digest('hex');
    await client.query(
      `UPDATE email_verification_tokens SET used_at = NOW()
       WHERE user_id = $1 AND used_at IS NULL`,
      [user.id]
    );
    await client.query(
      `INSERT INTO email_verification_tokens (id, user_id, token_hash, expires_at)
       VALUES ($1, $2, $3, NOW() + INTERVAL '30 minutes')`,
      [`evt-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`, user.id, tokenHash]
    );
    await client.query('COMMIT');

    const publicUrl = (process.env.PUBLIC_URL || 'https://serenut.com').replace(/\/$/, '');
    const emailMessage = emailVerificationEmail({
      userName: user.name,
      verificationLink: `${publicUrl}/api/v1/auth/verify-email?token=${rawToken}`
    });
    const notificationId = `notif-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    await pgPool.query(
      `INSERT INTO notification_queue (id, company_id, channel, recipient, title, body, status, scheduled_at)
       VALUES ($1, $2, 'email', $3, $4, $5, 'pending', NOW())`,
      [notificationId, user.company_id, normalizedEmail, emailMessage.subject, emailMessage.html]
    );
    await enqueueNotification({
      notification_id: notificationId,
      company_id: user.company_id,
      channel: 'email',
      recipient: normalizedEmail,
      title: emailMessage.subject,
      body: emailMessage.html
    });
    return res.status(200).json(genericResponse);
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    logger.error('Resend verification failed', err);
    return res.status(500).json({ error: 'server_error' });
  } finally {
    client.release();
  }
});

export default router;
