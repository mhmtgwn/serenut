import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { createError } from '../../config/error-codes';
import { logger } from '../../config/logger';
import { MailService } from './mail.service';

const router = Router();
router.use(authenticateUser);
router.use((req: AuthenticatedRequest, res: Response, next) => {
  if (!req.user!.roles?.includes('sysadmin')) return res.status(403).json(createError('AUTH005'));
  next();
});

router.get('/', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const page = Math.max(Number(req.query.page) || 1, 1);
    const limit = Math.min(Math.max(Number(req.query.limit) || 50, 1), 100);
    return res.json(await MailService.list(String(req.query.folder || 'inbox'), String(req.query.search || ''), page, limit));
  } catch (error) {
    logger.error('Mailbox list failed', error);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Posta kutusu yüklenemedi.' } });
  }
});

router.get('/:id', async (req: AuthenticatedRequest, res: Response) => {
  try { return res.json(await MailService.get(req.params.id)); }
  catch (error: any) {
    if (error.message === 'mail_not_found') return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'E-posta bulunamadı.' } });
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'E-posta yüklenemedi.' } });
  }
});

router.get('/:id/attachments/:attachmentId', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const attachment = await MailService.getAttachment(req.params.id, req.params.attachmentId);
    const response = await fetch(attachment.downloadUrl);
    if (!response.ok) throw new Error(`attachment_download_failed:${response.status}`);
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length > 25 * 1024 * 1024) return res.status(413).json({ error: { code: 'TOO_LARGE', message: 'Ek 25 MB sınırını aşıyor.' } });
    res.setHeader('Content-Type', attachment.contentType);
    res.setHeader('Content-Length', String(bytes.length));
    res.setHeader('Content-Disposition', `attachment; filename="${attachment.filename}"`);
    res.setHeader('Cache-Control', 'private, no-store');
    return res.send(bytes);
  } catch (error: any) {
    if (['mail_not_found','attachment_not_found'].includes(error.message)) return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'E-posta eki bulunamadı.' } });
    if (error.message === 'attachment_too_large') return res.status(413).json({ error: { code: 'TOO_LARGE', message: 'Ek 25 MB sınırını aşıyor.' } });
    logger.error('Mail attachment download failed', error);
    return res.status(502).json({ error: { code: 'ATTACHMENT_FAILED', message: 'E-posta eki indirilemedi.' } });
  }
});

router.post('/send', async (req: AuthenticatedRequest, res: Response) => {
  try {
    const sent = await MailService.send({ to: req.body.to, cc: req.body.cc, bcc: req.body.bcc,
      subject: req.body.subject, text: req.body.text, replyToId: req.body.reply_to_id, createdBy: req.user!.id });
    return res.status(201).json({ sent });
  } catch (error: any) {
    if (['invalid_recipient','invalid_message','mail_not_found'].includes(error.message)) {
      return res.status(400).json({ error: { code: 'VALIDATION', message: 'Alıcı, konu veya mesaj geçersiz.' } });
    }
    logger.error('Admin email send failed', error);
    return res.status(502).json({ error: { code: 'MAIL_SEND_FAILED', message: 'E-posta gönderilemedi.' } });
  }
});

router.patch('/:id', async (req: AuthenticatedRequest, res: Response) => {
  try { return res.json({ message: await MailService.update(req.params.id, { isRead: req.body.is_read, isArchived: req.body.is_archived }) }); }
  catch (error: any) {
    if (error.message === 'mail_not_found') return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'E-posta bulunamadı.' } });
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Değişiklik uygulanamadı.' } });
  }
});

export default router;
