import crypto from 'crypto';
import { pgPool } from '../../config/database';
import { logger } from '../../config/logger';
import type { PoolClient } from 'pg';

const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

async function withAdminDb<T>(work: (client: PoolClient) => Promise<T>): Promise<T> {
  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");
    const result = await work(client);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    await client.query('ROLLBACK').catch(() => undefined);
    throw error;
  } finally { client.release(); }
}

function normalizeAddresses(value: unknown): string[] {
  const values = Array.isArray(value) ? value : [value];
  const addresses = values.map(v => String(v || '').trim().toLowerCase()).filter(Boolean);
  if (!addresses.length || addresses.length > 50 || addresses.some(v => !EMAIL_RE.test(v))) {
    throw new Error('invalid_recipient');
  }
  return [...new Set(addresses)];
}

export class MailService {
  static async getAttachment(messageId: string, attachmentId: string): Promise<{
    downloadUrl: string; filename: string; contentType: string; size: number;
  }> {
    const apiKey = process.env.RESEND_API_KEY;
    if (!apiKey) throw new Error('mail_not_configured');
    const mail = await withAdminDb(client => client.query(
      `SELECT resend_email_id,attachment_metadata FROM admin_mail_messages
       WHERE id=$1 AND direction='inbound'`, [messageId],
    ));
    if (!mail.rows.length) throw new Error('mail_not_found');
    const metadata = Array.isArray(mail.rows[0].attachment_metadata) ? mail.rows[0].attachment_metadata : [];
    const expected = metadata.find((item: any) => String(item.id) === attachmentId);
    if (!expected) throw new Error('attachment_not_found');
    if (Number(expected.size || 0) > 25 * 1024 * 1024) throw new Error('attachment_too_large');
    const response = await fetch(
      `https://api.resend.com/emails/receiving/${encodeURIComponent(mail.rows[0].resend_email_id)}/attachments/${encodeURIComponent(attachmentId)}`,
      { headers: { Authorization: `Bearer ${apiKey}` } },
    );
    if (!response.ok) throw new Error(`attachment_retrieve_failed:${response.status}`);
    const attachment: any = await response.json();
    if (!attachment.download_url) throw new Error('attachment_download_unavailable');
    return {
      downloadUrl: String(attachment.download_url),
      filename: String(attachment.filename || expected.filename || 'ek').replace(/[\r\n"\\/]/g, '_').slice(0, 255),
      contentType: String(attachment.content_type || expected.content_type || 'application/octet-stream'),
      size: Number(attachment.size || expected.size || 0),
    };
  }

  static async updateDeliveryStatus(resendEmailId: string, status: string): Promise<void> {
    if (!resendEmailId) return;
    const allowed: Record<string, string> = {
      'email.sent': 'sent', 'email.delivered': 'delivered', 'email.delivery_delayed': 'delayed',
      'email.bounced': 'bounced', 'email.failed': 'failed', 'email.complained': 'complained',
    };
    const normalized = allowed[status];
    if (!normalized) return;
    await withAdminDb(client => client.query(
      'UPDATE admin_mail_messages SET delivery_status=$2,updated_at=NOW() WHERE resend_email_id=$1 AND direction=\'outbound\'',
      [resendEmailId, normalized],
    ).then(() => undefined));
  }

  static async persistInbound(params: {
    emailId: string; senderEmail: string; senderName?: string; recipients: string[];
    subject: string; textBody: string; htmlBody?: string; messageId?: string;
    inReplyTo?: string; attachments?: unknown[]; guestRequestId?: string; receivedAt?: string;
  }): Promise<void> {
    const id = `MAIL-${Date.now()}-${crypto.randomBytes(3).toString('hex').toUpperCase()}`;
    const threadKey = params.inReplyTo || params.messageId || params.emailId;
    await withAdminDb(client => client.query(
      `INSERT INTO admin_mail_messages
         (id,resend_email_id,direction,mailbox,sender_email,sender_name,recipients,subject,
          text_body,html_body,message_id,in_reply_to,thread_key,attachment_metadata,
          delivery_status,is_read,guest_request_id,received_at)
       VALUES ($1,$2,'inbound',$3,$4,$5,$6::jsonb,$7,$8,$9,$10,$11,$12,$13::jsonb,
               'received',FALSE,$14,$15)
       ON CONFLICT (resend_email_id) DO NOTHING`,
      [id, params.emailId, params.recipients[0] || 'destek@serenut.com', params.senderEmail,
       params.senderName || null, JSON.stringify(params.recipients), params.subject,
       params.textBody, params.htmlBody || null, params.messageId || null, params.inReplyTo || null,
       threadKey, JSON.stringify(params.attachments || []), params.guestRequestId || null,
       params.receivedAt || null],
    ).then(() => undefined));
  }

  static async list(folder: string, search: string, page: number, limit: number) {
    const safeFolder = ['inbox', 'sent', 'archive', 'trash'].includes(folder) ? folder : 'inbox';
    const conditions: string[] = [];
    const values: unknown[] = [];
    if (safeFolder === 'inbox') conditions.push("direction='inbound' AND is_archived=FALSE AND deleted_at IS NULL");
    if (safeFolder === 'sent') conditions.push("direction='outbound' AND is_archived=FALSE AND deleted_at IS NULL");
    if (safeFolder === 'archive') conditions.push('is_archived=TRUE AND deleted_at IS NULL');
    if (safeFolder === 'trash') conditions.push('deleted_at IS NOT NULL');
    if (search.trim()) {
      values.push(`%${search.trim().slice(0, 200)}%`);
      conditions.push(`(subject ILIKE $${values.length} OR sender_email ILIKE $${values.length} OR text_body ILIKE $${values.length})`);
    }
    const offset = (page - 1) * limit;
    values.push(limit, offset);
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const where = conditions.length ? `WHERE ${conditions.join(' AND ')}` : '';
      const rows = await client.query(
        `SELECT id,direction,mailbox,sender_email,sender_name,recipients,subject,
                LEFT(text_body,240) AS preview,delivery_status,is_read,is_archived,deleted_at,
                attachment_metadata,sent_at,received_at,created_at
           FROM admin_mail_messages ${where}
          ORDER BY COALESCE(received_at,sent_at,created_at) DESC
          LIMIT $${values.length - 1} OFFSET $${values.length}`,
        values,
      );
      const unread = await client.query("SELECT COUNT(*)::int AS count FROM admin_mail_messages WHERE direction='inbound' AND is_read=FALSE AND is_archived=FALSE AND deleted_at IS NULL");
      await client.query('COMMIT');
      return { messages: rows.rows, unread: unread.rows[0].count, page, limit };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally { client.release(); }
  }

  static async get(id: string) {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const result = await client.query('SELECT * FROM admin_mail_messages WHERE id=$1', [id]);
      if (!result.rows.length) throw new Error('mail_not_found');
      await client.query("UPDATE admin_mail_messages SET is_read=TRUE,updated_at=NOW() WHERE id=$1 AND direction='inbound'", [id]);
      const message = { ...result.rows[0], is_read: true };
      const thread = message.thread_key ? await client.query(
        'SELECT id,direction,sender_email,sender_name,recipients,subject,text_body,html_body,created_at,sent_at,received_at FROM admin_mail_messages WHERE thread_key=$1 ORDER BY created_at ASC',
        [message.thread_key],
      ) : { rows: [message] };
      await client.query('COMMIT');
      return { message, thread: thread.rows };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally { client.release(); }
  }

  static async send(params: { to: unknown; cc?: unknown; bcc?: unknown; subject: string; text: string; replyToId?: string; createdBy: string; }) {
    const apiKey = process.env.RESEND_API_KEY;
    if (!apiKey) throw new Error('mail_not_configured');
    const to = normalizeAddresses(params.to);
    const cc = params.cc ? normalizeAddresses(params.cc) : [];
    const bcc = params.bcc ? normalizeAddresses(params.bcc) : [];
    const subject = String(params.subject || '').trim().slice(0, 500);
    const text = String(params.text || '').trim().slice(0, 50000);
    if (!subject || !text) throw new Error('invalid_message');
    let inReplyTo: string | null = null;
    let threadKey: string | null = null;
    if (params.replyToId) {
      const original = await withAdminDb(client => client.query('SELECT message_id,thread_key FROM admin_mail_messages WHERE id=$1', [params.replyToId!]));
      if (!original.rows.length) throw new Error('mail_not_found');
      inReplyTo = original.rows[0].message_id || null;
      threadKey = original.rows[0].thread_key || inReplyTo;
    }
    const payload: any = { from: 'Serenut Destek <destek@serenut.com>', to, subject, text, reply_to: 'destek@serenut.com' };
    if (cc.length) payload.cc = cc;
    if (bcc.length) payload.bcc = bcc;
    if (inReplyTo) payload.headers = { 'In-Reply-To': inReplyTo, References: inReplyTo };
    const response = await fetch('https://api.resend.com/emails', {
      method: 'POST', headers: { Authorization: `Bearer ${apiKey}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
    const result: any = await response.json().catch(() => ({}));
    if (!response.ok || !result.id) throw new Error(`mail_send_failed:${response.status}`);
    const id = `MAIL-${Date.now()}-${crypto.randomBytes(3).toString('hex').toUpperCase()}`;
    await withAdminDb(client => client.query(
      `INSERT INTO admin_mail_messages
         (id,resend_email_id,direction,mailbox,sender_email,sender_name,recipients,cc,bcc,
          subject,text_body,in_reply_to,thread_key,delivery_status,is_read,created_by,sent_at)
       VALUES ($1,$2,'outbound','destek@serenut.com','destek@serenut.com','Serenut Destek',
               $3::jsonb,$4::jsonb,$5::jsonb,$6,$7,$8,$9,'sent',TRUE,$10,NOW())`,
      [id, result.id, JSON.stringify(to), JSON.stringify(cc), JSON.stringify(bcc), subject, text,
       inReplyTo, threadKey || result.id, params.createdBy],
    ).then(() => undefined));
    logger.info('Admin email sent', { id, resendEmailId: result.id, recipientCount: to.length, createdBy: params.createdBy });
    return { id, resendEmailId: result.id };
  }

  static async routeToSupport(id: string) {
    return withAdminDb(async client => {
      const mailResult = await client.query(
        `SELECT id, direction, sender_email, sender_name, subject, text_body, guest_request_id
           FROM admin_mail_messages WHERE id=$1 FOR UPDATE`,
        [id],
      );
      if (!mailResult.rows.length) throw new Error('mail_not_found');
      const mail = mailResult.rows[0];
      if (mail.direction !== 'inbound') throw new Error('inbound_mail_required');
      if (mail.guest_request_id) {
        const existing = await client.query(
          'SELECT id, reference_code, status FROM guest_support_requests WHERE id=$1',
          [mail.guest_request_id],
        );
        if (existing.rows.length) return existing.rows[0];
      }

      const requestId = `GUEST-${Date.now()}-${crypto.randomBytes(3).toString('hex').toUpperCase()}`;
      const referenceCode = `SRN-${new Date().getUTCFullYear()}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
      await client.query(
        `INSERT INTO guest_support_requests
           (id, reference_code, name, email, customer_claim, category, subject, message,
            status, intake_source)
         VALUES ($1,$2,$3,$4,'unsure','other',$5,$6,'under_review','inbound_email')`,
        [requestId, referenceCode, mail.sender_name || mail.sender_email.split('@')[0],
         mail.sender_email, mail.subject, mail.text_body],
      );
      await client.query(
        'UPDATE admin_mail_messages SET guest_request_id=$2, updated_at=NOW() WHERE id=$1',
        [id, requestId],
      );
      return { id: requestId, reference_code: referenceCode, status: 'under_review' };
    });
  }

  static async update(id: string, patch: { isRead?: boolean; isArchived?: boolean; restore?: boolean }) {
    const values: unknown[] = [id]; const sets: string[] = [];
    if (typeof patch.isRead === 'boolean') { values.push(patch.isRead); sets.push(`is_read=$${values.length}`); }
    if (typeof patch.isArchived === 'boolean') { values.push(patch.isArchived); sets.push(`is_archived=$${values.length}`); }
    if (patch.restore === true) sets.push('deleted_at=NULL');
    if (!sets.length) throw new Error('invalid_patch');
    const result = await withAdminDb(client => client.query(`UPDATE admin_mail_messages SET ${sets.join(',')},updated_at=NOW() WHERE id=$1 RETURNING id,is_read,is_archived,deleted_at`, values));
    if (!result.rows.length) throw new Error('mail_not_found');
    return result.rows[0];
  }

  static async moveToTrash(id: string) {
    const result = await withAdminDb(client => client.query(
      'UPDATE admin_mail_messages SET deleted_at=NOW(),updated_at=NOW() WHERE id=$1 RETURNING id,deleted_at',
      [id],
    ));
    if (!result.rows.length) throw new Error('mail_not_found');
    return result.rows[0];
  }
}
