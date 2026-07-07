import { Request, Response, NextFunction } from 'express';
import { AuthService, UserPayload } from '../modules/auth/auth.service';
import { pgPool } from '../config/database';

export interface AuthenticatedRequest extends Request {
  user?: UserPayload;
}

export async function authenticateUser(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'unauthorized', message: 'Bearer token gereklidir.' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const isBlacklisted = await AuthService.isTokenBlacklisted(token);
    if (isBlacklisted) {
      return res.status(401).json({ error: 'unauthorized', message: 'Token geçersiz kılınmıştır (oturum kapatıldı).' });
    }

    const decoded = AuthService.verifyAccessToken(token);
    req.user = decoded;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'unauthorized', message: 'Geçersiz veya süresi dolmuş token.' });
  }
}

// Checks dynamic database active status to catch immediately banned users
export async function verifyUserActiveStatus(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  if (!req.user) return res.status(401).json({ error: 'unauthorized' });

  try {
    const resUser = await pgPool.query('SELECT is_active FROM users WHERE id = $1', [req.user.id]);
    if (resUser.rows.length === 0 || !resUser.rows[0].is_active) {
      return res.status(403).json({ error: 'user_suspended', message: 'Hesabınız askıya alınmıştır.' });
    }
    next();
  } catch (err) {
    return res.status(500).json({ error: 'server_error' });
  }
}

export function requirePermission(permissionCode: string) {
  return (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    if (!req.user) {
      return res.status(401).json({ error: 'unauthorized' });
    }

    const hasPermission = req.user.permissions.includes(permissionCode) || req.user.roles.includes('sysadmin');
    if (!hasPermission) {
      return res.status(403).json({
        error: 'forbidden',
        message: `Bu işlem için '${permissionCode}' yetkisine sahip olmalısınız.`
      });
    }
    next();
  };
}

export function requireRole(roleName: string) {
  return (req: AuthenticatedRequest, res: Response, next: NextFunction) => {
    if (!req.user) {
      return res.status(401).json({ error: 'unauthorized' });
    }

    const hasRole = req.user.roles.includes(roleName) || req.user.roles.includes('sysadmin');
    if (!hasRole) {
      return res.status(403).json({
        error: 'forbidden',
        message: `Bu işlem için '${roleName}' rolüne sahip olmalısınız.`
      });
    }
    next();
  };
}
