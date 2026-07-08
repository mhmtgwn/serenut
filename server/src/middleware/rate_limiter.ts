import { Request, Response, NextFunction } from 'express';
import { redisClient } from '../config/database';

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
