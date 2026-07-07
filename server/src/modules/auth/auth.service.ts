// server/src/modules/auth/auth.service.ts
// Serenut Platform — Authentication Service
// Security: bcrypt (cost 12), JWT RTR, brute-force lock, iss/aud claims
// Migration: SHA-256 → bcrypt transparent upgrade on login

import crypto from 'crypto';
import bcrypt from 'bcrypt';
import jwt from 'jsonwebtoken';
import { pgPool, redisClient } from '../../config/database';
import { logger } from '../../config/logger';

// ── STARTUP SECRETS VALIDATION ────────────────────────────────────────────────
// Fail fast on startup if JWT_SECRET is missing or dangerously weak.
const JWT_SECRET = process.env.JWT_SECRET;
const JWT_ISSUER = 'serenut.com';
const JWT_AUDIENCE = 'serenut-pos';

if (!JWT_SECRET || JWT_SECRET.length < 32) {
  logger.error(
    '🚨 FATAL: JWT_SECRET is missing or too short (min 32 chars). ' +
    'Set JWT_SECRET in your .env file. Generate with: openssl rand -hex 64'
  );
  process.exit(1);
}

const BCRYPT_ROUNDS = 12;
const ACCESS_TOKEN_EXPIRY = '15m';
const REFRESH_TOKEN_EXPIRY_DAYS = 30;
const MAX_LOGIN_ATTEMPTS = 5;
const LOCK_TIME_MS = 15 * 60 * 1000; // 15 minutes

// SHA-256 hex hash is always exactly 64 chars — used to detect legacy hashes
const SHA256_HEX_LENGTH = 64;

export interface UserPayload {
  jti?: string; // JWT unique ID claim
  id: string;
  name: string;
  email: string;
  company_id: string;
  roles: string[];
  permissions: string[];
}

export class AuthService {
  // ── PASSWORD HASHING ────────────────────────────────────────────────────────

  /** Hash a plaintext password using bcrypt (cost 12). */
  public static async hashPassword(password: string): Promise<string> {
    return bcrypt.hash(password, BCRYPT_ROUNDS);
  }

  /**
   * Verify a password against a stored hash.
   * Supports both bcrypt (new) and SHA-256 (legacy migration) hashes.
   * Returns `{ valid: boolean, needsUpgrade: boolean }`.
   */
  public static async verifyPassword(
    plain: string,
    stored: string
  ): Promise<{ valid: boolean; needsUpgrade: boolean }> {
    // Legacy SHA-256 hash: exactly 64 hex chars, no $ prefix
    if (stored.length === SHA256_HEX_LENGTH && !stored.startsWith('$')) {
      const sha256Hash = crypto.createHash('sha256').update(plain).digest('hex');
      const valid = sha256Hash === stored;
      return { valid, needsUpgrade: valid }; // upgrade on successful legacy login
    }
    // Modern bcrypt hash
    const valid = await bcrypt.compare(plain, stored);
    return { valid, needsUpgrade: false };
  }

  // ── LOGIN ───────────────────────────────────────────────────────────────────

  public static async login(
    email: string,
    passwordPlain: string,
    ipAddress?: string,
    userAgent?: string
  ): Promise<any> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      // 1. Fetch user status (lock check)
      const userRes = await client.query(
        `SELECT id, company_id, password_hash, failed_login_attempts, locked_until, is_active
         FROM users WHERE email = $1`,
        [email]
      );

      if (userRes.rows.length === 0) {
        throw new Error('invalid_credentials');
      }

      const user = userRes.rows[0];
      const now = new Date();

      if (!user.is_active) {
        throw new Error('user_suspended');
      }

      if (user.locked_until && new Date(user.locked_until) > now) {
        throw new Error('account_locked');
      }

      // 2. Verify password (bcrypt or legacy SHA-256 with auto-upgrade)
      const { valid, needsUpgrade } = await this.verifyPassword(
        passwordPlain,
        user.password_hash
      );

      if (!valid) {
        let failedAttempts = (user.failed_login_attempts || 0) + 1;
        let lockUntil: Date | null = null;

        if (failedAttempts >= MAX_LOGIN_ATTEMPTS) {
          lockUntil = new Date(Date.now() + LOCK_TIME_MS);
          logger.warn(`Brute-force block: locking ${email} until ${lockUntil}`);
        }

        await client.query(
          'UPDATE users SET failed_login_attempts = $1, locked_until = $2 WHERE id = $3',
          [failedAttempts, lockUntil, user.id]
        );
        await client.query('COMMIT');
        throw new Error('invalid_credentials');
      }

      // 3. Transparent SHA-256 → bcrypt upgrade
      if (needsUpgrade) {
        const newHash = await this.hashPassword(passwordPlain);
        await client.query(
          'UPDATE users SET password_hash = $1 WHERE id = $2',
          [newHash, user.id]
        );
        logger.info(`Password hash upgraded to bcrypt for user ${user.id}`);
      }


      // 4. Reset failed attempts + update last login
      await client.query(
        `UPDATE users
         SET failed_login_attempts = 0, locked_until = NULL, last_login_at = CURRENT_TIMESTAMP
         WHERE id = $1`,
        [user.id]
      );

      // 4b. Trial FSM: Start trial on FIRST login (AC 1.2)
      // If subscription exists with trial_started_at IS NULL → set it now.
      // trial_ends_at = trial_started_at + 30 days, status → 'trialing'
      let trialStarted = false;
      const subRes = await client.query(
        `SELECT id, status, trial_started_at
         FROM subscriptions
         WHERE company_id = $1
         ORDER BY current_period_start DESC
         LIMIT 1`,
        [userRes.rows[0].company_id]
      );

      if (subRes.rows.length > 0 && subRes.rows[0].trial_started_at === null) {
        const trialStart = new Date();
        const trialEnd = new Date(trialStart.getTime() + 30 * 24 * 60 * 60 * 1000);
        await client.query(
          `UPDATE subscriptions
           SET trial_started_at = $1,
               trial_ends_at = $2,
               status = 'trialing'
           WHERE id = $3`,
          [trialStart, trialEnd, subRes.rows[0].id]
        );
        trialStarted = true;
        logger.info(`Trial started for company ${userRes.rows[0].company_id} — ends ${trialEnd.toISOString()}`);
      }

      // 5. Fetch full user profile (roles + permissions)
      const profileRes = await client.query(
        `SELECT u.id, u.name, u.email, u.company_id,
                ARRAY_AGG(DISTINCT r.name) AS roles
         FROM users u
         LEFT JOIN user_roles ur ON u.id = ur.user_id
         LEFT JOIN roles r ON ur.role_id = r.id
         WHERE u.id = $1
         GROUP BY u.id`,
        [user.id]
      );

      const userRow = profileRes.rows[0];
      const roles: string[] = userRow.roles.filter((r: any) => r !== null);

      let permissions: string[] = [];
      if (roles.length > 0) {
        const permRes = await client.query(
          `SELECT DISTINCT p.code
           FROM permissions p
           JOIN role_permissions rp ON p.id = rp.permission_id
           JOIN roles r ON rp.role_id = r.id
           WHERE r.name = ANY($1)`,
          [roles]
        );
        permissions = permRes.rows.map((row: any) => row.code);
      }

      const payload: UserPayload = {
        jti: crypto.randomUUID(),
        id: userRow.id,
        name: userRow.name,
        email: userRow.email,
        company_id: userRow.company_id,
        roles,
        permissions,
      };

      // 6. Issue token pair
      const accessToken = jwt.sign(payload, JWT_SECRET!, {
        expiresIn: ACCESS_TOKEN_EXPIRY,
        issuer: JWT_ISSUER,
        audience: JWT_AUDIENCE,
      });
      const refreshToken = crypto.randomBytes(40).toString('hex');
      const expiresAt = new Date(
        Date.now() + REFRESH_TOKEN_EXPIRY_DAYS * 24 * 60 * 60 * 1000
      );

      const sessionId = crypto.randomUUID();
      await client.query(
        `INSERT INTO sessions (id, user_id, company_id, refresh_token, ip_address, user_agent, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [sessionId, userRow.id, userRow.company_id, refreshToken, ipAddress || null, userAgent || null, expiresAt]
      );

      await client.query('COMMIT');

      let trialStartedAt = null;
      let trialEndsAt = null;
      if (subRes.rows.length > 0) {
        trialStartedAt = subRes.rows[0].trial_started_at;
        trialEndsAt = subRes.rows[0].trial_ends_at;
      }

      return {
        access_token: accessToken,
        refresh_token: refreshToken,
        expires_in: 3600,
        trial_started: trialStarted,
        trial_started_at: trialStartedAt,
        trial_ends_at: trialEndsAt,
        user: payload,
      };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }


  // ── REFRESH TOKEN ROTATION (RTR) ────────────────────────────────────────────

  public static async refresh(
    oldRefreshToken: string,
    ipAddress?: string,
    userAgent?: string
  ): Promise<any> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      const sessRes = await client.query(
        'SELECT id, user_id, company_id, is_revoked, expires_at FROM sessions WHERE refresh_token = $1',
        [oldRefreshToken]
      );

      if (sessRes.rows.length === 0) {
        throw new Error('invalid_refresh_token');
      }

      const session = sessRes.rows[0];

      // RTR: Replay attack — revoke ALL user sessions
      if (session.is_revoked || new Date(session.expires_at) < new Date()) {
        logger.warn(`Refresh token replay detected! Revoking all sessions for user: ${session.user_id}`);
        await client.query('UPDATE sessions SET is_revoked = TRUE WHERE user_id = $1', [session.user_id]);
        await client.query('COMMIT');
        throw new Error('refresh_token_expired');
      }

      // Revoke old token
      await client.query('UPDATE sessions SET is_revoked = TRUE WHERE id = $1', [session.id]);

      // Re-fetch user
      const userRes = await client.query(
        `SELECT u.id, u.name, u.email, u.company_id, u.is_active,
                ARRAY_AGG(DISTINCT r.name) AS roles
         FROM users u
         LEFT JOIN user_roles ur ON u.id = ur.user_id
         LEFT JOIN roles r ON ur.role_id = r.id
         WHERE u.id = $1
         GROUP BY u.id`,
        [session.user_id]
      );

      if (userRes.rows.length === 0 || !userRes.rows[0].is_active) {
        await client.query('COMMIT');
        throw new Error('user_suspended');
      }

      const userRow = userRes.rows[0];
      const roles: string[] = userRow.roles.filter((r: any) => r !== null);

      let permissions: string[] = [];
      if (roles.length > 0) {
        const permRes = await client.query(
          `SELECT DISTINCT p.code
           FROM permissions p
           JOIN role_permissions rp ON p.id = rp.permission_id
           JOIN roles r ON rp.role_id = r.id
           WHERE r.name = ANY($1)`,
          [roles]
        );
        permissions = permRes.rows.map((row: any) => row.code);
      }

      const payload: UserPayload = {
        jti: crypto.randomUUID(),
        id: userRow.id,
        name: userRow.name,
        email: userRow.email,
        company_id: userRow.company_id,
        roles,
        permissions,
      };

      const newAccessToken = jwt.sign(payload, JWT_SECRET!, {
        expiresIn: ACCESS_TOKEN_EXPIRY,
        issuer: JWT_ISSUER,
        audience: JWT_AUDIENCE,
      });
      const newRefreshToken = crypto.randomBytes(40).toString('hex');
      const expiresAt = new Date(Date.now() + REFRESH_TOKEN_EXPIRY_DAYS * 24 * 60 * 60 * 1000);

      const newSessionId = crypto.randomUUID();
      await client.query(
        `INSERT INTO sessions (id, user_id, company_id, refresh_token, ip_address, user_agent, expires_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [newSessionId, session.user_id, session.company_id, newRefreshToken, ipAddress || null, userAgent || null, expiresAt]
      );

      await client.query('COMMIT');

      return {
        access_token: newAccessToken,
        refresh_token: newRefreshToken,
        expires_in: 3600,
      };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  // ── LOGOUT ──────────────────────────────────────────────────────────────────

  public static async logout(refreshToken: string, accessToken?: string): Promise<void> {
    await pgPool.query(
      'UPDATE sessions SET is_revoked = TRUE WHERE refresh_token = $1',
      [refreshToken]
    );

    if (accessToken) {
      await AuthService.blacklistToken(accessToken);
    }
  }

  // ── TOKEN BLACKLISTING (Redis SET with jti claim tracking) ───────────────────

  public static async blacklistToken(token: string): Promise<void> {
    try {
      const decoded = jwt.decode(token) as any;
      if (decoded && decoded.jti && redisClient && redisClient.isOpen) {
        // Blacklist for 15 minutes (900 seconds)
        await redisClient.setEx(`bl:${decoded.jti}`, 900, '1');
      }
    } catch (err) {
      console.error('Failed to blacklist token:', err);
    }
  }

  public static async isTokenBlacklisted(token: string): Promise<boolean> {
    try {
      const decoded = jwt.decode(token) as any;
      if (decoded && decoded.jti && redisClient && redisClient.isOpen) {
        const isBlacklisted = await redisClient.get(`bl:${decoded.jti}`);
        return isBlacklisted === '1';
      }
    } catch (_) {}
    return false;
  }

  // ── TOKEN VERIFICATION ───────────────────────────────────────────────────────

  public static verifyAccessToken(token: string): UserPayload {
    try {
      return jwt.verify(token, JWT_SECRET!, {
        issuer: JWT_ISSUER,
        audience: JWT_AUDIENCE,
      }) as UserPayload;
    } catch (err) {
      throw new Error('invalid_access_token');
    }
  }

  // ── PASSWORD MANAGEMENT ─────────────────────────────────────────────────────

  public static async changePassword(
    userId: string,
    companyId: string,
    oldPlain: string,
    newPlain: string
  ): Promise<void> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query(`SET LOCAL app.current_company_id = '${companyId.replace(/'/g, "''")}'`);

      const verifyRes = await client.query(
        'SELECT password_hash FROM users WHERE id = $1',
        [userId]
      );

      if (verifyRes.rows.length === 0) {
        throw new Error('user_not_found');
      }

      const { valid } = await this.verifyPassword(oldPlain, verifyRes.rows[0].password_hash);
      if (!valid) {
        throw new Error('invalid_old_password');
      }

      const newHash = await this.hashPassword(newPlain);
      await client.query('UPDATE users SET password_hash = $1 WHERE id = $2', [newHash, userId]);

      // Revoke all sessions on password change (security best practice)
      await client.query('UPDATE sessions SET is_revoked = TRUE WHERE user_id = $1', [userId]);

      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  public static async forgotPassword(email: string): Promise<string | null> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      
      const res = await client.query('SELECT id, name FROM users WHERE email = $1 AND is_active = TRUE', [email]);
      if (res.rows.length === 0) {
        await client.query('COMMIT');
        return null;
      }
      
      const userId = res.rows[0].id;
      const userName = res.rows[0].name;
      const resetToken = crypto.randomBytes(30).toString('hex');
      const expiresAt = new Date(Date.now() + 60 * 60 * 1000); // 1 hour
      
      await client.query(
        'UPDATE users SET reset_token = $1, reset_token_expires_at = $2 WHERE id = $3',
        [resetToken, expiresAt, userId]
      );
      
      await client.query('COMMIT');
      
      // Queue email notification
      const { getNotificationQueue } = require('../../workers/notification.worker');
      const queue = getNotificationQueue();
      await queue.add('send-email', {
        channel: 'email',
        recipient: email,
        title: 'Serenut OS — Şifre Sıfırlama Talebi',
        body: `Merhaba ${userName},\n\nŞifrenizi sıfırlamak için aşağıdaki bağlantıyı kullanabilirsiniz. Bu bağlantı 1 saat boyunca geçerlidir:\n\nhttps://portal.serenut.com/reset-password?token=${resetToken}\n\nEğer bu talebi siz yapmadıysanız lütfen bu e-postayı dikkate almayınız.`
      });
      
      logger.info(`Password reset token generated and queued for ${email}`);
      return resetToken;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  public static async resetPassword(token: string, newPlain: string): Promise<boolean> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      
      // Find user with valid token
      const res = await client.query(
        'SELECT id FROM users WHERE reset_token = $1 AND reset_token_expires_at > NOW() AND is_active = TRUE',
        [token]
      );
      
      if (res.rows.length === 0) {
        await client.query('ROLLBACK');
        return false;
      }
      
      const userId = res.rows[0].id;
      const newHash = await this.hashPassword(newPlain);
      
      // Update password and clear token
      await client.query(
        'UPDATE users SET password_hash = $1, reset_token = NULL, reset_token_expires_at = NULL WHERE id = $2',
        [newHash, userId]
      );
      
      // Revoke all existing sessions for security
      await client.query('UPDATE sessions SET is_revoked = TRUE WHERE user_id = $1', [userId]);
      
      await client.query('COMMIT');
      return true;
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  // ── ADMIN: Force Password Reset ──────────────────────────────────────────────

  /**
   * Called by admin to set a user's password directly (bypasses old-password check).
   * Revokes all sessions.
   */
  public static async adminSetPassword(userId: string, newPlain: string): Promise<void> {
    const newHash = await this.hashPassword(newPlain);
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      await client.query('UPDATE users SET password_hash = $1 WHERE id = $2', [newHash, userId]);
      await client.query('UPDATE sessions SET is_revoked = TRUE WHERE user_id = $1', [userId]);
      await client.query('COMMIT');
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }
}
