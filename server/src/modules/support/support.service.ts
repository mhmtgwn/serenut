// server/src/modules/support/support.service.ts
// Serenut OS — Support Ticket Service + FSM
// Blueprint: state_machine_specification.md — Section 3
// FSM: open → in_progress → pending_customer → resolved → closed
// SLA: P1=2h, P2=6h, P3=24h, P4=48h

import { pgPool } from '../../config/database';
import { logger } from '../../config/logger';
import crypto from 'crypto';

// ── SLA HOURS ─────────────────────────────────────────────────────────────────
const SLA_HOURS: Record<string, number> = {
  P1: 2,
  P2: 6,
  P3: 24,
  P4: 48,
};

// ── ALLOWED TRANSITIONS ───────────────────────────────────────────────────────
const TICKET_TRANSITIONS: Record<string, string[]> = {
  open: ['in_progress', 'closed'],
  in_progress: ['pending_customer', 'resolved'],
  pending_customer: ['in_progress', 'closed'],
  resolved: ['closed', 'in_progress'],
  closed: [],
};

function assertTicketTransition(from: string, to: string, ticketId: string): void {
  const allowed = TICKET_TRANSITIONS[from] ?? [];
  if (!allowed.includes(to)) {
    throw new Error(
      `Invalid ticket FSM transition for ${ticketId}: ${from} → ${to}. Allowed: [${allowed.join(', ')}]`
    );
  }
}

function computeSlaDeadline(priority: string): Date {
  const hours = SLA_HOURS[priority] ?? 24;
  return new Date(Date.now() + hours * 60 * 60 * 1000);
}

export class SupportService {
  static async createInboundEmailRequest(params: {
    eventId: string;
    emailId: string;
    senderEmail: string;
    recipients: string[];
    subject: string;
    message: string;
    messageId?: string;
    attachments?: unknown[];
    receivedAt?: string;
  }): Promise<{ duplicate: boolean; requestId?: string; referenceCode?: string }> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const existing = await client.query(
        'SELECT guest_request_id FROM resend_inbound_events WHERE event_id=$1 OR email_id=$2 FOR UPDATE',
        [params.eventId, params.emailId],
      );
      if (existing.rows.length) {
        await client.query('COMMIT');
        return { duplicate: true, requestId: existing.rows[0].guest_request_id || undefined };
      }

      const id = `GUEST-${Date.now()}-${crypto.randomBytes(3).toString('hex').toUpperCase()}`;
      const referenceCode = `SRN-${new Date().getUTCFullYear()}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
      const senderName = params.senderEmail.split('@')[0].slice(0, 200) || 'E-posta kullanıcısı';
      await client.query(
        `INSERT INTO guest_support_requests
           (id, reference_code, name, email, customer_claim, category, subject, message, status)
         VALUES ($1,$2,$3,$4,'not_registered','other',$5,$6,'unverified')`,
        [id, referenceCode, senderName, params.senderEmail, params.subject, params.message],
      );
      await client.query(
        `INSERT INTO resend_inbound_events
           (event_id,email_id,sender_email,recipients,subject,message_id,attachment_metadata,
            guest_request_id,received_at)
         VALUES ($1,$2,$3,$4::jsonb,$5,$6,$7::jsonb,$8,$9)`,
        [params.eventId, params.emailId, params.senderEmail, JSON.stringify(params.recipients),
         params.subject, params.messageId || null, JSON.stringify(params.attachments || []), id,
         params.receivedAt || null],
      );
      await client.query('COMMIT');
      logger.info('Inbound support email persisted', { eventId: params.eventId, requestId: id });
      return { duplicate: false, requestId: id, referenceCode };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Creates a new support ticket.
   * Initial state: 'open'. SLA deadline set based on priority.
   */
  static async createTicket(params: {
    companyId: string;
    requesterUserId: string;
    requesterName?: string;
    subject: string;
    body?: string;
    priority?: string;
    category?: string;
    logsSnapshot?: string;
  }): Promise<any> {
    const {
      companyId,
      requesterUserId,
      requesterName = 'Müşteri',
      subject,
      body,
      priority = 'P3',
      category = 'technical',
      logsSnapshot,
    } = params;

    if (!['P1', 'P2', 'P3', 'P4'].includes(priority)) {
      throw new Error('Invalid priority. Must be P1, P2, P3, or P4.');
    }
    if (!['technical', 'license', 'billing', 'account', 'usage', 'other'].includes(category)) {
      throw new Error('Invalid support category.');
    }

    const id = `TK-${Date.now()}-${crypto.randomBytes(2).toString('hex').toUpperCase()}`;
    const slaDeadlineAt = computeSlaDeadline(priority);

    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const res = await client.query(
        `INSERT INTO support_tickets
           (id, company_id, requester_user_id, subject, body, priority, category,
            status, logs_snapshot, sla_deadline_at, intake_channel)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 'open', $8, $9, 'customer_portal')
         RETURNING *`,
        [id, companyId, requesterUserId, subject, body ?? null, priority, category, logsSnapshot ?? null, slaDeadlineAt]
      );
      await client.query(
        `INSERT INTO support_ticket_messages
           (id, ticket_id, sender_id, sender_name, message)
         VALUES ($1, $2, $3, $4, $5)`,
        [
          `MSG-${Date.now()}-${crypto.randomBytes(2).toString('hex').toUpperCase()}`,
          id,
          requesterUserId,
          requesterName,
          body || subject,
        ],
      );
      await client.query('COMMIT');

      logger.info(`Support ticket created: ${id} | Priority: ${priority} | Company: ${companyId}`);
      return res.rows[0];
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * Transitions a ticket to a new status.
   * Enforces FSM rules. Sets resolved_at / closed_at timestamps as needed.
   */
  static async transitionTicket(
    ticketId: string,
    toStatus: string,
    performedBy?: string
  ): Promise<any> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      const res = await client.query(
        `SELECT id, status, company_id FROM support_tickets WHERE id = $1`,
        [ticketId]
      );
      if (res.rows.length === 0) throw new Error(`Ticket ${ticketId} not found`);

      const ticket = res.rows[0];
      assertTicketTransition(ticket.status, toStatus, ticketId);

      await client.query(
        `UPDATE support_tickets
            SET status = $2,
                assigned_to = CASE
                  WHEN $2 = 'in_progress' AND status = 'open' AND $3::varchar IS NOT NULL
                    THEN $3::varchar
                  ELSE assigned_to
                END,
                resolved_at = CASE WHEN $2 = 'resolved' THEN NOW() ELSE resolved_at END,
                closed_at = CASE WHEN $2 = 'closed' THEN NOW() ELSE closed_at END,
                updated_at = NOW()
          WHERE id = $1`,
        [ticketId, toStatus, performedBy || null]
      );

      await client.query('COMMIT');

      logger.info(`Ticket ${ticketId}: ${ticket.status} → ${toStatus}`, { performedBy });
      return { ticketId, from: ticket.status, to: toStatus };
    } catch (err) {
      await client.query('ROLLBACK');
      throw err;
    } finally {
      client.release();
    }
  }

  /**
   * Lists tickets for a company (customer view) or all tickets (sysadmin).
   */
  static async listTickets(params: {
    companyId?: string;
    status?: string;
    priority?: string;
    page?: number;
    limit?: number;
  }): Promise<{ tickets: any[]; total: number }> {
    const { companyId, status, priority, page = 1, limit = 20 } = params;
    const offset = (page - 1) * limit;

    const conditions: string[] = [];
    const values: any[] = [];
    let idx = 1;

    if (companyId) {
      conditions.push(`t.company_id = $${idx++}`);
      values.push(companyId);
    }
    if (status) {
      conditions.push(`t.status = $${idx++}`);
      values.push(status);
    }
    if (priority) {
      conditions.push(`t.priority = $${idx++}`);
      values.push(priority);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const dataRes = await client.query(
          `SELECT t.id, t.company_id, t.requester_user_id, t.subject, t.category,
                  t.priority, t.status, t.assigned_to, c.name AS company_name,
                  t.sla_deadline_at, t.resolved_at, t.closed_at, t.created_at, t.updated_at
           FROM support_tickets t
           LEFT JOIN companies c ON c.id = t.company_id
           ${where}
           ORDER BY
             CASE t.priority WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END,
             t.created_at DESC
           LIMIT $${idx++} OFFSET $${idx++}`,
          [...values, limit, offset]
        );
      const countRes = await client.query(
          `SELECT COUNT(*) as total FROM support_tickets t ${where}`,
          values
        );
      await client.query('COMMIT');

      return {
        tickets: dataRes.rows,
        total: parseInt(countRes.rows[0].total, 10),
      };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  static async getTicket(
    ticketId: string,
    companyId?: string,
  ): Promise<{ ticket: any; messages: any[] }> {
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const params = companyId ? [ticketId, companyId] : [ticketId];
      const result = await client.query(
        `SELECT t.*, c.name AS company_name
           FROM support_tickets t
           LEFT JOIN companies c ON c.id = t.company_id
          WHERE t.id = $1 ${companyId ? 'AND t.company_id = $2' : ''}`,
        params,
      );
      if (result.rows.length === 0) throw new Error(`Ticket ${ticketId} not found`);
      const messages = await client.query(
        `SELECT id, ticket_id, sender_id, sender_name, message, created_at
           FROM support_ticket_messages
          WHERE ticket_id = $1
          ORDER BY created_at ASC`,
        [ticketId],
      );
      await client.query('COMMIT');
      return { ticket: result.rows[0], messages: messages.rows };
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  static async addMessage(params: {
    ticketId: string;
    companyId?: string;
    senderId: string;
    senderName: string;
    message: string;
    isSysadmin: boolean;
  }): Promise<any> {
    const message = params.message.trim();
    if (!message || message.length > 10000) throw new Error('Invalid support message');
    const client = await pgPool.connect();
    try {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const ticketResult = await client.query(
        `SELECT id, status, company_id FROM support_tickets
          WHERE id = $1 ${params.isSysadmin ? '' : 'AND company_id = $2'}
          FOR UPDATE`,
        params.isSysadmin ? [params.ticketId] : [params.ticketId, params.companyId],
      );
      if (ticketResult.rows.length === 0) throw new Error(`Ticket ${params.ticketId} not found`);
      const ticket = ticketResult.rows[0];
      if (ticket.status === 'closed') throw new Error('Ticket is closed');

      const id = `MSG-${Date.now()}-${crypto.randomBytes(2).toString('hex').toUpperCase()}`;
      const inserted = await client.query(
        `INSERT INTO support_ticket_messages
           (id, ticket_id, sender_id, sender_name, message)
         VALUES ($1, $2, $3, $4, $5)
         RETURNING id, ticket_id, sender_id, sender_name, message, created_at`,
        [id, params.ticketId, params.senderId, params.senderName, message],
      );

      let nextStatus = ticket.status;
      if (params.isSysadmin && ticket.status === 'open') nextStatus = 'in_progress';
      if (!params.isSysadmin && ['pending_customer', 'resolved'].includes(ticket.status)) {
        nextStatus = 'in_progress';
      }
      await client.query(
        `UPDATE support_tickets
            SET status = $2,
                assigned_to = CASE
                  WHEN $3::boolean AND assigned_to IS NULL THEN $4::varchar
                  ELSE assigned_to
                END,
                updated_at = NOW()
          WHERE id = $1`,
        [params.ticketId, nextStatus, params.isSysadmin, params.senderId],
      );
      await client.query('COMMIT');
      return inserted.rows[0];
    } catch (error) {
      await client.query('ROLLBACK').catch(() => {});
      throw error;
    } finally {
      client.release();
    }
  }

  static async createGuestRequest(params: {
    name: string;
    email: string;
    phone?: string;
    companyName?: string;
    customerClaim?: string;
    category?: string;
    subject: string;
    message: string;
    privacyNoticeVersion: string;
  }): Promise<{ id: string; referenceCode: string; status: string }> {
    const category = params.category ?? 'other';
    const customerClaim = params.customerClaim ?? 'not_registered';
    if (!['technical', 'license', 'billing', 'account', 'usage', 'sales', 'other'].includes(category)) {
      throw new Error('Invalid support category.');
    }
    if (!['not_registered', 'cannot_login', 'unsure'].includes(customerClaim)) {
      throw new Error('Invalid customer claim.');
    }

    const id = `GUEST-${Date.now()}-${crypto.randomBytes(3).toString('hex').toUpperCase()}`;
    const referenceCode = `SRN-${new Date().getUTCFullYear()}-${crypto.randomBytes(4).toString('hex').toUpperCase()}`;
    await pgPool.query(
      `INSERT INTO guest_support_requests
         (id, reference_code, name, email, phone, company_name, customer_claim,
          category, subject, message, status, privacy_notice_version, privacy_consent_at, intake_source)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, 'unverified', $11, NOW(), 'website_contact')`,
      [id, referenceCode, params.name, params.email, params.phone ?? null,
       params.companyName ?? null, customerClaim, category, params.subject, params.message,
       params.privacyNoticeVersion]
    );
    logger.info('Guest support request created', { id, referenceCode, category });
    return { id, referenceCode, status: 'unverified' };
  }

  static async listGuestRequests(limit = 100): Promise<any[]> {
    const result = await pgPool.query(
      `SELECT id, reference_code, name, email, phone, company_name, customer_claim,
              category, subject, status, matched_company_id, converted_ticket_id,
              created_at, updated_at
       FROM guest_support_requests
       ORDER BY CASE status WHEN 'unverified' THEN 1 WHEN 'under_review' THEN 2 ELSE 3 END,
                created_at DESC
       LIMIT $1`,
      [Math.min(Math.max(limit, 1), 100)]
    );
    return result.rows;
  }

  /**
   * Auto-closes stale tickets based on SLA rules.
   * P4: auto-close after 48h inactivity.
   * pending_customer: auto-close after 72h no response.
   * Called by billing.scheduler.ts cron.
   */
  static async autoCloseStaleTickets(): Promise<number> {
    const client = await pgPool.connect();
    try {
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      // P4 open tickets older than 48h
      const p4Res = await client.query(
        `UPDATE support_tickets
         SET status = 'closed', closed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
         WHERE status = 'open' AND priority = 'P4'
           AND created_at < CURRENT_TIMESTAMP - INTERVAL '48 hours'
         RETURNING id`
      );

      // pending_customer tickets older than 72h
      const pendingRes = await client.query(
        `UPDATE support_tickets
         SET status = 'closed', closed_at = CURRENT_TIMESTAMP, updated_at = CURRENT_TIMESTAMP
         WHERE status = 'pending_customer'
           AND updated_at < CURRENT_TIMESTAMP - INTERVAL '72 hours'
         RETURNING id`
      );

      const closed = (p4Res.rowCount ?? 0) + (pendingRes.rowCount ?? 0);
      if (closed > 0) logger.info(`Auto-closed ${closed} stale support tickets`);
      return closed;
    } finally {
      client.release();
    }
  }
}
