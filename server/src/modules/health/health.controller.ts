// server/src/modules/health/health.controller.ts
// Serenut OS — Client Health Report Controller (Sprint 11)

import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { healthRepository } from './health.repository';
import { logger } from '../../config/logger';

const router = Router();

router.get('/', (req, res) => {
  // Sync client expects /api/v1/health to return status
  // We'll redirect to the main health check or return simple json
  res.redirect('/health');
});

/**
 * @openapi
 * /api/v1/health/report:
 *   post:
 *     summary: Ingest client device health metrics diagnostic bundle
 *     security:
 *       - BearerAuth: []
 *     responses:
 *       200:
 *         description: Ingested OK
 *       500:
 *         description: Server error
 */
router.post('/report', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const user = req.user!;
    const { device_id, status, services } = req.body;

    if (!device_id || !status || !services) {
      return res.status(400).json({ error: 'missing_params', message: 'Eksik parametre gönderildi.' });
    }

    await healthRepository.insertReport(
      user.company_id,
      device_id,
      status,
      services
    );

    return res.json({ success: true });
  } catch (err) {
    logger.error('Failed to save client health report:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/health/admin/reports:
 *   get:
 *     summary: Fetch latest health statuses for system administrators
 *     security:
 *       - BearerAuth: []
 *     responses:
 *       200:
 *         description: Success
 */
router.get('/admin/reports', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const user = req.user!;
    // Secure isolation constraint: only admins can read all, normal tenants only see their company
    const isAdmin = user.roles.includes('admin') || user.roles.includes('sysadmin') || user.roles.includes('super_admin');
    
    const rows = await healthRepository.getRecentReports(isAdmin ? undefined : user.company_id);
    return res.json(rows);
  } catch (err) {
    logger.error('Failed to retrieve client health reports:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
