import { Request, Response, NextFunction } from 'express';
import { redisClient, pgPool } from '../config/database';
import { AuthenticatedRequest } from './auth.middleware';
import { logger } from '../config/logger';

interface LimiterOptions {
  windowMs: number;
  max: number;
  error: string;
  message: string;
  skip?: (req: Request) => boolean;
}

// Custom Redis-based rate limiter middleware
export function createRedisLimiter(options: LimiterOptions) {
  return async (req: Request, res: Response, next: NextFunction) => {
    if (options.skip && options.skip(req)) {
      return next();
    }

    // [SEC-A] Redis down → 503 (güvenli hata, fallback yok)
    if (!redisClient || !redisClient.isOpen) {
      if (process.env.NODE_ENV !== 'production') {
        logger.warn(`Rate Limiter: Redis is down/inactive. Bypassing check in development mode.`);
        return next();
      }
      logger.error(`Rate Limiter blocked request: Redis is down/inactive. Route: ${req.originalUrl}`);
      return res.status(503).json({
        error: 'service_unavailable',
        message: 'Güvenlik sistemi geçici olarak servis dışı. Lütfen daha sonra tekrar deneyin.'
      });
    }

    const ip = req.ip || req.socket.remoteAddress || 'unknown';
    const key = `rl:${req.baseUrl || req.path}:${ip}`;

    try {
      const current = await redisClient.incr(key);
      if (current === 1) {
        await redisClient.expire(key, Math.ceil(options.windowMs / 1000));
      }

      if (current > options.max) {
        logger.warn(`Rate limit exceeded: ${ip} → ${req.originalUrl} (${current}/${options.max})`);
        return res.status(429).json({
          error: options.error,
          message: options.message
        });
      }

      next();
    } catch (err: any) {
      logger.error(`Rate Limiter error processing Redis incr: ${err.message}`);
      return res.status(503).json({
        error: 'service_unavailable',
        message: 'Güvenlik doğrulaması başarısız oldu.'
      });
    }
  };
}

// ── GENEL API RATE LİMİTER ────────────────────────────────────────────────────
export const generalApiLimiter = createRedisLimiter({
  windowMs: 15 * 60 * 1000, // 15 minutes
  max: 5000,
  error: 'rate_limit_exceeded',
  message: 'Çok fazla istek gönderildi. Lütfen 15 dakika sonra tekrar deneyin.',
  skip: (req) => {
    return req.path === '/health' || req.path.startsWith('/api-docs');
  }
});

// ── KİMLİK DOĞRULAMA LİMİTER ─────────────────────────────────────────────────
export const authLimiter = createRedisLimiter({
  windowMs: 15 * 60 * 1000,
  max: process.env.NODE_ENV === 'production' ? 10 : 200, // Üretimde daha sıkı, testte esnek
  error: 'too_many_auth_attempts',
  message: 'Çok fazla giriş denemesi yapıldı. 15 dakika bekleyin.'
});

// ── LİSANS AKTİVASYON LİMİTER ────────────────────────────────────────────────
export const licenseLimiter = createRedisLimiter({
  windowMs: 60 * 60 * 1000,
  max: 20,
  error: 'license_rate_limit_exceeded',
  message: 'Çok fazla lisans aktivasyon denemesi yapıldı. 1 saat bekleyin.'
});

// ── PORTAL KAYIT LİMİTER ─────────────────────────────────────────────────────
export const signupLimiter = createRedisLimiter({
  windowMs: 60 * 60 * 1000,
  max: 5,
  error: 'signup_rate_limit_exceeded',
  message: 'Bu IP adresinden çok fazla kayıt denemesi yapıldı.'
});

// ── BİLDİRİM / SMS LİMİTER ───────────────────────────────────────────────────
export const smsLimiter = createRedisLimiter({
  windowMs: 60 * 1000,
  max: 3,
  error: 'sms_rate_limit_exceeded',
  message: 'SMS gönderim sınırına ulaşıldı. 1 dakika bekleyin.'
});

// ── ŞİFRE SIFIRLAMA LİMİTER ──────────────────────────────────────────────────
export const passwordResetLimiter = createRedisLimiter({
  windowMs: 15 * 60 * 1000,
  max: 5,
  error: 'too_many_reset_attempts',
  message: 'Çok fazla şifre sıfırlama denemesi yapıldı. 15 dakika bekleyin.'
});

// ── SENKRONİZASYON (SYNC) LİMİTER ────────────────────────────────────────────
export const syncLimiter = createRedisLimiter({
  windowMs: 60 * 1000,
  max: 100,
  error: 'sync_rate_limit_exceeded',
  message: 'Çok fazla senkronizasyon isteği gönderildi. Lütfen 1 dakika bekleyin.'
});

// ── WEBHOOK LİMİTER ──────────────────────────────────────────────────────────
export const webhookLimiter = createRedisLimiter({
  windowMs: 60 * 1000,
  max: 60,
  error: 'webhook_rate_limit_exceeded',
  message: 'Çok fazla webhook isteği gönderildi.'
});


// --- MIGRATED FROM rate_limit.middleware.ts ---
// server/src/middleware/rate_limit.middleware.ts
// Serenut Platform — Tenant Rate Limiting & Abuse Detection Middleware (Sprint 11)
// Enforces credit limits and safeguards gateway channels from spam.
// Created: 04 Jul 2026






// In-Memory cache tracker for campaign limits per company
const campaignTracker = new Map<string, { count: number; windowStart: number }>();

async function runBypassingRLS(sql: string, params: any[] = []) {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
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

/**
 * Limit: A company is restricted to 100 notification messages (queued/sent/failed) per rolling hour
 * to prevent gateway credit drain or script loop errors.
 */
export async function enforceNotificationRateLimit(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  const user = req.user;
  if (!user) return res.status(401).json({ error: 'unauthorized' });

  try {
    // Count messages queued in the last 1 hour for this tenant
    const countRes = await runBypassingRLS(`
      SELECT COUNT(*) FROM notification_queue
      WHERE company_id = $1 AND created_at >= NOW() - INTERVAL '1 hour'
    `, [user.company_id]);

    const oneHourCount = parseInt(countRes.rows[0].count, 10);
    const hourlyLimit = 100;

    if (oneHourCount >= hourlyLimit) {
      logger.warn(`Rate limit triggered for company ${user.company_id}. Messages in last hour: ${oneHourCount}/${hourlyLimit}`);
      return res.status(429).json({
        error: 'rate_limit_exceeded',
        message: 'Saatlik maksimum mesaj gönderim limitine (100) ulaştınız. Lütfen daha sonra tekrar deneyin.'
      });
    }

    next();
  } catch (err) {
    logger.error('Rate limit evaluation error:', err);
    next();
  }
}

/**
 * Abuse Protection: Restricts campaign creation actions to 5 times per 1 minute window.
 */
export function enforceCampaignAbuseLimit(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  const user = req.user;
  if (!user) return res.status(401).json({ error: 'unauthorized' });

  const companyId = user.company_id;
  const now = Date.now();
  const windowMs = 60 * 1000; // 1 minute
  const maxCampaigns = 5;

  const tracker = campaignTracker.get(companyId) || { count: 0, windowStart: now };

  if (now - tracker.windowStart > windowMs) {
    // Reset window
    tracker.count = 1;
    tracker.windowStart = now;
  } else {
    tracker.count++;
  }

  campaignTracker.set(companyId, tracker);

  if (tracker.count > maxCampaigns) {
    logger.error(`Abuse/spam detected for company ${companyId} - triggered ${tracker.count} campaigns in 1 minute.`);
    return res.status(429).json({
      error: 'abuse_detected',
      message: 'Çok fazla kampanya isteği tespit edildi. 1 dakikada en fazla 5 kampanya başlatılabilir.'
    });
  }

  next();
}

// --- MIGRATED FROM rate_limiter.ts ---
export function rateLimiter(limitCount: number, windowMs: number) {
  return async (req: Request, res: Response, next: NextFunction) => {
    // [SEC-A] Redis down → 503 (güvenli hata, fallback yok)
    if (!redisClient || !redisClient.isOpen) {
      if (process.env.NODE_ENV !== 'production') {
        return next();
      }
      return res.status(503).json({
        error: 'service_unavailable',
        message: 'Güvenlik sistemi geçici olarak servis dışı. Lütfen daha sonra tekrar deneyin.'
      });
    }

    const ip = req.ip || req.socket.remoteAddress || 'unknown';
    const key = `rate:${ip}:${req.path}`;

    try {
      const count = await redisClient.incr(key);
      if (count === 1) {
        await redisClient.expire(key, Math.ceil(windowMs / 1000));
      }
      if (count > limitCount) {
        return res.status(429).json({
          error: 'too_many_requests',
          message: 'Çok fazla istek gönderdiniz. Lütfen bir süre sonra tekrar deneyin.'
        });
      }
      return next();
    } catch (err) {
      console.error('Redis rate limiter error:', err);
      return res.status(503).json({
        error: 'service_unavailable',
        message: 'Güvenlik doğrulaması başarısız oldu.'
      });
    }
  };
}