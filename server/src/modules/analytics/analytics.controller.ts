import { Router, Request, Response } from 'express';
import { pgPool } from '../../config/database';
import { AuthService } from '../auth/auth.service';

const router = Router();

// Endpoint to log app crashes from clients
router.post('/crash', async (req: Request, res: Response) => {
  const { error_message, stack_trace, app_version, device_hash } = req.body;
  if (!error_message) {
    return res.status(400).json({ error: 'missing_error_message', message: 'Hata detayı belirtilmelidir.' });
  }

  try {
    // Attempt to match device_hash to retrieve company_id
    let companyId: string | null = null;
    let deviceId: string | null = null;
    
    if (device_hash) {
      const devRes = await pgPool.query(
        'SELECT id, company_id FROM devices WHERE device_hash = $1',
        [device_hash]
      );
      if (devRes.rows.length > 0) {
        deviceId = devRes.rows[0].id;
        companyId = devRes.rows[0].company_id;
      }
    }

    const incidentId = crypto.randomUUID ? crypto.randomUUID() : `inc-${Date.now()}-${Math.floor(Math.random() * 1000)}`;

    await pgPool.query(
      `INSERT INTO crash_logs (id, company_id, device_id, error_message, stack_trace, app_version)
       VALUES ($1, $2, $3, $4, $5, $6)`,
      [incidentId, companyId, deviceId, error_message, stack_trace || null, app_version || null]
    );

    return res.status(201).json({
      status: 'logged',
      incident_id: incidentId
    });
  } catch (err) {
    console.error('Failed to log crash:', err);
    return res.status(500).json({ error: 'server_error', message: 'Hata raporlama başarısız.' });
  }
});

// Endpoint to post audit logs (requires Auth)
router.post('/audit', async (req: Request, res: Response) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'unauthorized' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const isBlacklisted = await AuthService.isTokenBlacklisted(token);
    if (isBlacklisted) {
      return res.status(401).json({ error: 'unauthorized' });
    }

    const user = AuthService.verifyAccessToken(token);
    const { action, entity, entity_id, old_value, new_value } = req.body;

    if (!action) {
      return res.status(400).json({ error: 'missing_action' });
    }

    const auditId = crypto.randomUUID ? crypto.randomUUID() : `aud-${Date.now()}`;
    const ipAddress = req.ip || req.socket.remoteAddress || 'unknown';

    await pgPool.query(
      `INSERT INTO audit_logs (id, company_id, user_id, action, entity, entity_id, old_value, new_value, ip_address)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [
        auditId,
        user.company_id,
        user.id,
        action,
        entity || null,
        entity_id || null,
        old_value ? JSON.stringify(old_value) : null,
        new_value ? JSON.stringify(new_value) : null,
        ipAddress
      ]
    );

    return res.status(201).json({ success: true, audit_id: auditId });
  } catch (err) {
    return res.status(401).json({ error: 'unauthorized' });
  }
});

export default router;
