// server/src/modules/remote-config/remote-config.controller.ts
// Serenut OS — Remote Config Express Controller (Sprint 8)

import { Router, Response } from 'express';
import { pgPool } from '../../config/database';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { logger } from '../../config/logger';

const router = Router();

/**
 * @openapi
 * /api/v1/remote-config:
 *   get:
 *     summary: Retrieve global feature flags and runtime configurations
 *     security:
 *       - BearerAuth: []
 *     responses:
 *       200:
 *         description: Success
 *       500:
 *         description: Server error
 */
router.get('/', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const queryRes = await pgPool.query(
      "SELECT value FROM remote_configs WHERE key = 'global_config' LIMIT 1"
    );

    if (queryRes.rows.length === 0) {
      return res.status(404).json({ error: 'config_not_found', message: 'Uzaktan konfigürasyon şeması bulunamadı.' });
    }

    return res.json(queryRes.rows[0].value);
  } catch (err) {
    logger.error('Failed to retrieve remote configuration:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
