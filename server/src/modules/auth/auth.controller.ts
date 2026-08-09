import { Router, Request, Response } from 'express';
import { AuthService } from './auth.service';
import { LicenseService } from '../license/license.service';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { authLimiter, passwordResetLimiter, signupLimiter } from '../../middleware/rate-limit.middleware';
import { RealtimeBroadcastService } from '../realtime/broadcast.service';
import { createError } from '../../config/error-codes';
import { logger } from '../../config/logger';
import { pgPool } from '../../config/database';
import { enqueueNotification } from '../../workers/notification.worker';
import { emailVerificationEmail, passwordResetEmail } from '../notifications/email.templates';
import crypto from 'crypto';
import { CommercialLifecycleService } from '../billing/commercial_lifecycle.service';
import { PasswordRecoveryService } from './password-recovery.service';

const router = Router();
// Mail delivery is currently optional. Verification is enabled only when the
// deployment explicitly opts in; a missing environment variable must not lock
// newly-created accounts out.
const emailDeliveryEnabled = process.env.EMAIL_DELIVERY_ENABLED === 'true';
const emailVerificationRequired =
  emailDeliveryEnabled && process.env.REQUIRE_EMAIL_VERIFICATION === 'true';


if (process.env.REQUIRE_EMAIL_VERIFICATION === 'true' && !emailDeliveryEnabled) {
  logger.warn(
    'REQUIRE_EMAIL_VERIFICATION was requested while EMAIL_DELIVERY_ENABLED is false; verification remains disabled.'
  );
}

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
    const result = await AuthService.login(
      String(email).trim().toLowerCase(),
      password,
      ipAddress,
      userAgent
    );

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
    logger.error('Login error:', err);
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
 * */
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
    logger.error('Refresh token error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Oturum yenileme esnasında hata oluştu.' } });
  }
});

router.post('/logout', async (req: Request, res: Response) => {
  const { refresh_token } = req.body ?? {};
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

/**
 * Idempotent post-login recovery contract. A client may retry this request
 * after any interrupted register/login flow without creating another device
 * activation or changing the entitlement state.
 */
router.post('/session-bootstrap', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { device_hash, device_name, fingerprint } = req.body ?? {};
  try {
    const entitlementResult = await pgPool.query(
      `SELECT license_key FROM license_entitlements
       WHERE company_id = $1 AND status IN ('trial', 'active')
       ORDER BY valid_until DESC LIMIT 1`,
      [user.company_id]
    );
    const companyResult = await pgPool.query(
      `SELECT id, name, owner_name, phone, email, tax_number, city, district, address
       FROM companies WHERE id = $1 LIMIT 1`,
      [user.company_id]
    );

    let activation: unknown = null;
    if (device_hash) {
      if (typeof device_hash !== 'string' || device_hash.length > 255) {
        return res.status(400).json({ error: 'invalid_device_hash' });
      }
      activation = await LicenseService.autoActivate(
        user.company_id,
        device_hash,
        typeof device_name === 'string' && device_name.trim().length > 0
          ? device_name.trim()
          : `Serenut cihazı ${device_hash.slice(0, 8)}`,
        undefined,
        fingerprint
      );
    }

    // Device activation starts a new tenant's trial and writes trial_ends_at.
    // Read the subscription afterwards so the client never caches the stale
    // pre-activation `trialing + trial_ends_at: null` snapshot.
    const subscriptionResult = await pgPool.query(
      `SELECT id, status, trial_started_at, trial_ends_at, current_period_start,
              current_period_end, grace_hours_override
       FROM subscriptions
       WHERE company_id = $1
       ORDER BY current_period_start DESC, id DESC LIMIT 1`,
      [user.company_id]
    );

    return res.json({
      user: { id: user.id, company_id: user.company_id, roles: user.roles, permissions: user.permissions },
      subscription: subscriptionResult.rows[0] ?? null,
      company: companyResult.rows[0] ?? null,
      license_key: entitlementResult.rows[0]?.license_key ?? null,
      activation,
    });
  } catch (err: any) {
    const known = new Set([
      'no_license_found', 'license_expired', 'device_blocked',
      'device_limit_exceeded', 'hardware_tampered_limit_exceeded'
    ]);
    if (known.has(err.message)) {
      return res.status(409).json({ error: err.message });
    }
    logger.error('Session bootstrap error:', err);
    return res.status(500).json({ error: 'session_bootstrap_failed' });
  }
});

router.post('/change-password', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { old_password, new_password } = req.body;

  if (!old_password || !new_password) {
    return res.status(400).json({ error: 'missing_passwords', message: 'Eski ve yeni şifre belirtilmelidir.' });
  }
  if (typeof new_password !== 'string' || !PasswordRecoveryService.isStrongPassword(new_password)) {
    return res.status(400).json({ error: 'weak_password', message: 'Yeni şifre en az 10 karakter olmalı ve harf ile rakam içermelidir.' });
  }

  try {
    await AuthService.changePassword(user.id, user.company_id, old_password, new_password);
    return res.json({ success: true, message: 'Şifreniz başarıyla güncellenmiştir. Güvenliğiniz için tüm aktif oturumlar kapatılmıştır.' });
  } catch (err: any) {
    if (err.message === 'invalid_old_password') {
      return res.status(400).json({ error: 'invalid_old_password', message: 'Eski şifre hatalı.' });
    }
    if (err.message === 'password_reuse_not_allowed') {
      return res.status(400).json({ error: 'password_reuse_not_allowed', message: 'Yeni şifre mevcut şifreyle aynı olamaz.' });
    }
    logger.error('Change password error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/verify-identity', passwordResetLimiter, async (req: Request, res: Response) => {
  return res.status(410).json({
    error: 'recovery_code_required',
    message: 'Kayıt bilgileri tek başına şifre sıfırlama yetkisi vermez. Kurtarma kodu veya yönetici destekli kurtarma kullanın.',
  });
});

router.post('/forgot-password', passwordResetLimiter, async (req: Request, res: Response) => {
  const genericResponse = { message: 'Bu e-posta ile eşleşen doğrulanmış bir hesap varsa sıfırlama bağlantısı gönderildi.' };
  const email = String(req.body?.email || '').trim().toLowerCase();
  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) return res.json(genericResponse);
  try {
    const recovery = await PasswordRecoveryService.createEmailReset({
      email, context: { ip: req.ip, userAgent: req.headers['user-agent'] },
    });
    if (recovery) {
      const publicUrl = (process.env.PUBLIC_URL || 'https://serenut.com').replace(/\/$/, '');
      const message = passwordResetEmail({
        userName: recovery.userName,
        resetLink: `${publicUrl}/reset-password?token=${encodeURIComponent(recovery.resetToken)}`,
      });
      const notificationId = `notif-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
      await pgPool.query(
        `INSERT INTO notification_queue (id,company_id,channel,recipient,title,body,status,scheduled_at)
         VALUES($1,$2,'email',$3,$4,$5,'pending',NOW())`,
        [notificationId, recovery.companyId, recovery.email, message.subject, message.html],
      );
      await enqueueNotification({ notification_id: notificationId, company_id: recovery.companyId,
        channel: 'email', recipient: recovery.email, title: message.subject, body: message.html });
    }
    return res.json(genericResponse);
  } catch (error) {
    logger.error('Email password recovery request failed', error);
    return res.json(genericResponse);
  }
});

router.post('/reset-password', passwordResetLimiter, async (req: Request, res: Response) => {
  const { token, newPassword } = req.body;
  if (!token || !newPassword) {
    return res.status(400).json({ error: 'missing_fields', message: 'Token ve yeni şifre zorunludur.' });
  }
  if (newPassword.length < 10) {
    return res.status(400).json({ error: 'weak_password', message: 'Şifre en az 10 karakter olmalıdır.' });
  }

  try {
    const success = await PasswordRecoveryService.resetPassword(token, newPassword, {
      ip: req.ip, userAgent: req.headers['user-agent'],
    });
    if (!success) {
      return res.status(400).json({ error: 'invalid_token', message: 'Geçersiz veya süresi dolmuş token.' });
    }
    return res.json({ success: true, message: 'Şifreniz başarıyla güncellendi.' });
  } catch (err) {
    if ((err as Error).message === 'weak_password') {
      return res.status(400).json({ error: 'weak_password', message: 'Şifre en az 10 karakter olmalı ve harf ile rakam içermelidir.' });
    }
    if ((err as Error).message === 'password_reuse_not_allowed') {
      return res.status(400).json({ error: 'password_reuse_not_allowed', message: 'Yeni şifre mevcut şifreyle aynı olamaz.' });
    }
    logger.error('Reset password error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/recovery/authorize-code', passwordResetLimiter, async (req: Request, res: Response) => {
  const { identifier, company_name, tax_number, recovery_code } = req.body;
  if (![identifier, company_name, tax_number, recovery_code].every(value => typeof value === 'string' && value.trim())) {
    return res.status(400).json({ error: 'missing_fields', message: 'Hesap, işletme, TC/VKN ve kurtarma kodu zorunludur.' });
  }
  try {
    const authorization = await PasswordRecoveryService.recoverWithIdentityAndCode({
      identifier, companyName: company_name, taxNumber: tax_number, recoveryCode: recovery_code,
      context: { ip: req.ip, userAgent: req.headers['user-agent'] },
    });
    if (!authorization) return res.status(400).json({ error: 'recovery_verification_failed', message: 'Bilgiler veya kurtarma kodu doğrulanamadı.' });
    return res.json({ success: true, reset_token: authorization.resetToken, expires_in: authorization.expiresInSeconds });
  } catch (error) {
    logger.error('Recovery-code authorization failed', error);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/recovery/claim', passwordResetLimiter, async (req: Request, res: Response) => {
  const { request_id, claim_code } = req.body;
  if (typeof request_id !== 'string' || typeof claim_code !== 'string') return res.status(400).json({ error: 'missing_fields' });
  try {
    const authorization = await PasswordRecoveryService.claimAdminRequest(request_id, claim_code, {
      ip: req.ip, userAgent: req.headers['user-agent'],
    });
    if (!authorization) return res.status(400).json({ error: 'invalid_or_expired_claim' });
    return res.json({ success: true, reset_token: authorization.resetToken, expires_in: authorization.expiresInSeconds });
  } catch (error) {
    logger.error('Recovery claim failed', error);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/recovery/admin-assist', authenticateUser, passwordResetLimiter, async (req: AuthenticatedRequest, res: Response) => {
  const { target_user_id, reason } = req.body;
  if (typeof target_user_id !== 'string' || typeof reason !== 'string') return res.status(400).json({ error: 'missing_fields' });
  try {
    const result = await PasswordRecoveryService.createAdminAssistedRequest({
      targetUserId: target_user_id, actorId: req.user!.id, actorCompanyId: req.user!.company_id,
      actorRoles: req.user!.roles, reason, context: { ip: req.ip, userAgent: req.headers['user-agent'] },
    });
    return res.status(201).json({ success: true, request_id: result.requestId, claim_code: result.claimCode, requires_second_approval: result.requiresSecondApproval });
  } catch (error: any) {
    if (['forbidden','self_admin_recovery_forbidden'].includes(error.message)) return res.status(403).json({ error: error.message });
    if (error.message === 'user_not_found') return res.status(404).json({ error: error.message });
    if (error.message === 'recovery_reason_required') return res.status(400).json({ error: error.message });
    logger.error('Admin-assisted recovery request failed', error);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/recovery/codes/regenerate', authenticateUser, passwordResetLimiter, async (req: AuthenticatedRequest, res: Response) => {
  const currentPassword = req.body.current_password;
  if (typeof currentPassword !== 'string') return res.status(400).json({ error: 'current_password_required' });
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls='true'");
    const user = await client.query('SELECT password_hash FROM users WHERE id=$1 AND company_id=$2 FOR UPDATE', [req.user!.id, req.user!.company_id]);
    if (!user.rowCount || !(await AuthService.verifyPassword(currentPassword, user.rows[0].password_hash)).valid) {
      await client.query('ROLLBACK');
      return res.status(403).json({ error: 'invalid_current_password' });
    }
    const codes = await PasswordRecoveryService.issueRecoveryCodes(client, req.user!.id);
    await client.query(
      `INSERT INTO password_security_events(id,user_id,company_id,event_type,actor_id,ip_address,user_agent)
       VALUES($1,$2,$3,'RECOVERY_CODES_REGENERATED',$2,$4,$5)`,
      [`pse-${crypto.randomUUID()}`, req.user!.id, req.user!.company_id, req.ip || null, req.headers['user-agent'] || null],
    );
    await client.query('COMMIT');
    return res.json({ success: true, recovery_codes: codes });
  } catch (error) {
    await client.query('ROLLBACK').catch(() => {});
    logger.error('Recovery-code regeneration failed', error);
    return res.status(500).json({ error: 'server_error' });
  } finally { client.release(); }
});

// ── SELF-SERVICE REGISTRATION ────────────────────────────────────────────────
// Creates a new company tenant + owner/admin user in a single atomic transaction.
router.post('/register', signupLimiter, async (req: Request, res: Response) => {
  const { company_name, name, email, username, password, phone, tax_number, tax_office, city, district, address,
    accept_terms, accept_privacy, accept_kvkk, accept_marketing } = req.body;
  const normalizedEmail = String(email || '').trim().toLowerCase();
  const normalizedUsername = username ? String(username).trim().toLowerCase() : null;
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

  if (!PasswordRecoveryService.isStrongPassword(password)) {
    return res.status(400).json({
      error: 'weak_password',
      message: 'Şifre en az 10 karakter olmalı ve harf ile rakam içermelidir.'
    });
  }

  const crypto = require('crypto');
  const { pgPool } = require('../../config/database');

  const client = await pgPool.connect();
  let verificationToken = '';
  let registeredUserId = '';
  let registeredCompanyId = '';
  let recoveryCodes: string[] = [];
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
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'active')`,
      [companyId, company_name, name, normalizedTaxNumber, tax_office || null, phone || null, normalizedEmail,
        city || null, district || null, address || null]
    );

    const defaultStoreId = `store-${crypto.randomUUID()}`;
    const defaultBranchId = `br-${crypto.randomUUID()}`;
    await client.query(
      `INSERT INTO stores (id, company_id, name, address) VALUES ($1, $2, 'Merkez Şube', $3)`,
      [defaultStoreId, companyId, address || null]
    );
    await client.query(
      `INSERT INTO branches (id, company_id, store_id, name, address)
       VALUES ($1, $2, $3, 'Merkez Şube', $4)`,
      [defaultBranchId, companyId, defaultStoreId, address || null]
    );

    // Create owner user
    const userId = `usr-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    const passwordHash = await AuthService.hashPassword(password);
    await client.query(
      `INSERT INTO users (id, company_id, name, email, username, password_hash, is_active, email_verified_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [userId, companyId, name, normalizedEmail, normalizedUsername, passwordHash,
        !emailVerificationRequired, emailVerificationRequired ? null : new Date()]
    );
    registeredUserId = userId;
    registeredCompanyId = companyId;
    recoveryCodes = await PasswordRecoveryService.issueRecoveryCodes(client, userId);

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
      await CommercialLifecycleService.provisionPendingTrial(client, { companyId });

      if (emailVerificationRequired) {
        verificationToken = crypto.randomBytes(32).toString('hex');
        const verificationHash = crypto.createHash('sha256').update(verificationToken).digest('hex');
        await client.query(
          `INSERT INTO email_verification_tokens (id, user_id, token_hash, expires_at)
           VALUES ($1, $2, $3, NOW() + INTERVAL '30 minutes')`,
          [`evt-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`, userId, verificationHash]
        );
      }

    await client.query('COMMIT');

    if (emailVerificationRequired) try {
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

    if (!emailVerificationRequired) {
      try {
        const loginResult = await AuthService.login(
          normalizedEmail,
          password,
          req.ip || req.socket.remoteAddress || undefined,
          req.headers['user-agent'] || undefined
        );
        return res.status(201).json({
          ...loginResult,
          email_verification_required: false,
          recovery_codes: recoveryCodes,
          message: 'Hesabınız oluşturuldu ve giriş yapıldı.'
        });
      } catch (loginErr) {
        logger.error('Auto-login after registration failed:', loginErr);
      }
    }

    return res.status(201).json({
      user_id: registeredUserId,
      recovery_codes: recoveryCodes,
      email_verification_required: emailVerificationRequired,
      message: emailVerificationRequired
        ? 'Hesabınız oluşturuldu. Giriş yapabilmek için e-posta adresinizi doğrulayın.'
        : 'Hesabınız oluşturuldu. Şimdi giriş yapabilirsiniz.'
    });
  } catch (err: any) {
    await client.query('ROLLBACK').catch(() => {});
    logger.error('Register error:', err);
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
    return res.redirect(302, '/login?verified=1');
  } catch (err) {
    await client.query('ROLLBACK').catch(() => {});
    logger.error('Email verification failed', err);
    return res.status(500).send('E-posta doğrulanamadı. Lütfen yeniden deneyin.');
  } finally {
    client.release();
  }
});

router.post('/resend-verification', signupLimiter, async (req: Request, res: Response) => {
  if (!emailDeliveryEnabled) {
    return res.status(503).json({
      error: 'email_service_unavailable',
      message: 'E-posta doğrulaması henüz aktif değil.'
    });
  }
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
