import { Router } from 'express';
import { authenticateUser } from '../../../middleware/auth.middleware';
import { SyncRestController } from '../controllers/sync-rest.controller';

const router = Router();

// All Sync V2 endpoints are protected by JWT Auth
router.post('/push', authenticateUser as any, SyncRestController.pushMutations);
router.post('/delta', authenticateUser as any, SyncRestController.pullDelta);
router.get('/snapshot', authenticateUser as any, SyncRestController.getSnapshot);

export default router;
