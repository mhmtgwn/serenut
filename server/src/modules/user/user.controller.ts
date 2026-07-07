import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { pgPool } from '../../config/database';

const router = Router();

router.use(authenticateUser);

// GET /users/me
router.get('/me', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const resUser = await pgPool.query(
      'SELECT id, name, email, is_active, last_login_at, created_at FROM users WHERE id = $1',
      [user.id]
    );
    if (resUser.rows.length === 0) {
      return res.status(404).json({ error: 'user_not_found' });
    }
    return res.json({
      ...resUser.rows[0],
      roles: user.roles,
      permissions: user.permissions
    });
  } catch (err) {
    console.error('Fetch me error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// GET /sessions (List active sessions)
router.get('/sessions', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  try {
    const sessionsRes = await pgPool.query(
      `SELECT id, ip_address, user_agent, created_at, expires_at, is_revoked 
       FROM sessions 
       WHERE user_id = $1 AND is_revoked = FALSE AND expires_at > CURRENT_TIMESTAMP
       ORDER BY created_at DESC`,
      [user.id]
    );
    return res.json(sessionsRes.rows);
  } catch (err) {
    console.error('Fetch sessions error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

// DELETE /sessions/:id (Terminate specific session)
router.delete('/sessions/:id', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { id } = req.params;

  try {
    const result = await pgPool.query(
      'UPDATE sessions SET is_revoked = TRUE WHERE id = $1 AND user_id = $2 AND is_revoked = FALSE',
      [id, user.id]
    );
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'session_not_found', message: 'Oturum bulunamadı veya zaten kapatılmış.' });
    }
    return res.json({ success: true, message: 'Oturum başarıyla kapatılmıştır.' });
  } catch (err) {
    console.error('Delete session error:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

export default router;
