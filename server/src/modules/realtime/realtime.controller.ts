import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { issueRealtimeTicket } from './realtime-ticket.service';
import { logger } from '../../config/logger';

const router = Router();
router.use(authenticateUser);

// WebSocket handshakes cannot reliably carry an Authorization header in every
// supported client. Issue a short-lived, single-use opaque ticket instead of
// placing the reusable JWT in URLs and proxy logs.
router.post('/ticket', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const user = req.user!;
    return res.status(201).json(await issueRealtimeTicket({
      id: user.id,
      name: user.name,
      email: user.email,
      company_id: user.company_id,
      roles: user.roles || [],
      permissions: user.permissions || [],
      token_version: user.token_version,
    }));
  } catch (error) {
    logger.error('Realtime ticket issue failed', {
      error: error instanceof Error ? error.message : String(error),
      company_id: req.user?.company_id,
      user_id: req.user?.id,
    });
    return res.status(503).json({
      error: 'realtime_unavailable',
      message: 'Canlı bağlantı bileti şu anda üretilemiyor.',
    });
  }
});

export default router;
