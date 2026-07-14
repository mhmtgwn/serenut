import { Request, Response, NextFunction } from 'express';
import { AuthService, UserPayload } from '../modules/auth/auth.service';
import { pgPool, tenantLocalStorage } from '../config/database';
import { incrementJwtFailures } from '../utils/telemetry';

export interface AuthenticatedRequest extends Request {
  user?: UserPayload;
}

export async function authenticateUser(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    incrementJwtFailures();
    return res.status(401).json({ error: 'unauthorized', message: 'Bearer token gereklidir.' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const isBlacklisted = await AuthService.isTokenBlacklisted(token);
    if (isBlacklisted) {
      incrementJwtFailures();
      return res.status(401).json({ error: 'unauthorized', message: 'Token geçersiz kılınmıştır (oturum kapatıldı).' });
    }

    const decoded = AuthService.verifyAccessToken(token);
    console.log('authenticateUser verifyAccessToken DONE');

    // Dynamic database check for active status and token version
    console.log('authenticateUser pgPool.query...');
    const resUser = await pgPool.query('SELECT is_active, token_version FROM users WHERE id = $1', [decoded.id]);
    console.log('authenticateUser pgPool.query DONE');
    if (resUser.rows.length === 0 || !resUser.rows[0].is_active) {
      incrementJwtFailures();
      return res.status(403).json({ error: 'user_suspended', message: 'Hesabınız askıya alınmıştır.' });
    }

    const dbTokenVersion = resUser.rows[0].token_version;
    if (decoded.token_version !== undefined && dbTokenVersion !== decoded.token_version) {
      incrementJwtFailures();
      return res.status(401).json({ error: 'unauthorized', message: 'Yetkileriniz veya şifreniz güncellendi. Lütfen tekrar giriş yapın.' });
    }

    req.user = decoded;
    
    // Bind context of PG RLS for asynchronous callbacks
    tenantLocalStorage.run({ companyId: decoded.company_id, bypassRls: false }, () => {
      next();
    });
  } catch (err) {
    console.error('authenticateUser Error:', err);
    incrementJwtFailures();
    return res.status(401).json({ error: 'unauthorized', message: 'Geçersiz veya süresi dolmuş token.' });
  }
}

// Checks dynamic database active status and token version to catch immediately banned users or revoked sessions
export async function verifyUserActiveStatus(req: AuthenticatedRequest, res: Response, next: NextFunction) {
  if (!req.user) return res.status(401).json({ error: 'unauthorized' });

  try {
    const resUser = await pgPool.query('SELECT is_active, token_version FROM users WHERE id = $1', [req.user.id]);
    if (resUser.rows.length === 0 || !resUser.rows[0].is_active) {
      return res.status(403).json({ error: 'user_suspended', message: 'Hesabınız askıya alınmıştır.' });
    }

    const dbTokenVersion = resUser.rows[0].token_version;
    const tokenVersion = req.user.token_version;
    if (tokenVersion !== undefined && dbTokenVersion !== tokenVersion) {
      return res.status(401).json({ error: 'unauthorized', message: 'Yetkileriniz değiştirildi, lütfen tekrar giriş yapın.' });
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

    const hasPermission = req.user.permissions.includes(permissionCode);
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

    const hasRole = req.user.roles.includes(roleName);
    if (!hasRole) {
      return res.status(403).json({
        error: 'forbidden',
        message: `Bu işlem için '${roleName}' rolüne sahip olmalısınız.`
      });
    }
    next();
  };
}
