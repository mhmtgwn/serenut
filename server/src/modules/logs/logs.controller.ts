// server/src/modules/logs/logs.controller.ts
// Serenut OS — Encrypted Log Upload Controller (Sprint 10)

import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { logger } from '../../config/logger';
import fs from 'fs';
import path from 'path';

const router = Router();

// Create destination folder
const uploadDir = path.join(process.cwd(), 'uploads/logs');
if (!fs.existsSync(uploadDir)) {
  fs.mkdirSync(uploadDir, { recursive: true });
}

/**
 * @openapi
 * /api/v1/logs/upload:
 *   post:
 *     summary: Upload encrypted diagnostic zip files from client POS
 *     security:
 *       - BearerAuth: []
 *     responses:
 *       200:
 *         description: Success
 *       500:
 *         description: Server error
 */
router.post('/upload', authenticateUser, async (req: AuthenticatedRequest, res: Response) => {
  try {
    const user = req.user!;
    const deviceId = req.query.device_id as string || 'unknown';

    // We can handle raw binary body or multi-part
    const fileData = req.body;
    if (!fileData) {
      return res.status(400).json({ error: 'empty_payload', message: 'Boş dosya yüklenemez.' });
    }

    const filename = `logs_${user.company_id}_${deviceId}_${Date.now()}.zip.enc`;
    const targetPath = path.join(uploadDir, filename);

    // Save encrypted package to disk
    fs.writeFileSync(targetPath, JSON.stringify(fileData));

    logger.info(`Diagnostic logs uploaded successfully for company ${user.company_id} (Device: ${deviceId}).`);
    return res.json({ success: true, filename });
  } catch (err) {
    logger.error('Failed to handle logs upload:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
