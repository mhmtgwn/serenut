import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { pgPool } from '../../config/database';
import { filterNavByEntitlements, resolveLandingRoute } from '../../config/app-shell';

const router = Router();

router.use(authenticateUser);

router.get('/bootstrap', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const companyRes = await pgPool.query(
      `SELECT id, name, business_code, status, owner_name
       FROM companies
       WHERE id = $1
       LIMIT 1`,
      [user.company_id]
    );

    const company = companyRes.rows[0] || null;
    const roles = user.roles || [];
    const permissions = user.permissions || [];

    return res.json({
      user: {
        id: user.id,
        name: user.name,
        email: user.email,
        company_id: user.company_id,
        roles,
        permissions
      },
      company,
      navigation: filterNavByEntitlements(roles, permissions),
      landing_route: resolveLandingRoute(roles, permissions),
      workspaces: {
        platform: roles.includes('sysadmin'),
        company: permissions.includes('devices:view') || permissions.includes('billing:view') || roles.includes('owner') || roles.includes('manager') || roles.includes('cashier') || roles.includes('staff')
      }
    });
  } catch (err) {
    console.error('App bootstrap error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
