import { Request, Response, NextFunction } from 'express';
import { redisClient } from '../config/database';
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
  max: 200,
  error: 'rate_limit_exceeded',
  message: 'Çok fazla istek gönderildi. Lütfen 15 dakika sonra tekrar deneyin.',
  skip: (req) => {
    return req.path === '/health' || req.path.startsWith('/api-docs');
  }
});

// ── KİMLİK DOĞRULAMA LİMİTER ─────────────────────────────────────────────────
export const authLimiter = createRedisLimiter({
  windowMs: 15 * 60 * 1000,
  max: 10,
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
