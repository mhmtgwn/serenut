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
  /**
   * Creates a new support ticket.
   * Initial state: 'open'. SLA deadline set based on priority.
   */
  static async createTicket(params: {
    companyId: string;
    subject: string;
    body?: string;
    priority?: string;
    logsSnapshot?: string;
  }): Promise<any> {
    const { companyId, subject, body, priority = 'P3', logsSnapshot } = params;

    if (!['P1', 'P2', 'P3', 'P4'].includes(priority)) {
      throw new Error('Invalid priority. Must be P1, P2, P3, or P4.');
    }

    const id = `TK-${Date.now()}-${crypto.randomBytes(2).toString('hex').toUpperCase()}`;
    const slaDeadlineAt = computeSlaDeadline(priority);

    const client = await pgPool.connect();
    try {
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const res = await client.query(
        `INSERT INTO support_tickets
           (id, company_id, subject, body, priority, status, logs_snapshot, sla_deadline_at)
         VALUES ($1, $2, $3, $4, $5, 'open', $6, $7)
         RETURNING *`,
        [id, companyId, subject, body ?? null, priority, logsSnapshot ?? null, slaDeadlineAt]
      );

      logger.info(`Support ticket created: ${id} | Priority: ${priority} | Company: ${companyId}`);
      return res.rows[0];
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

      const now = new Date();
      const updates: string[] = [`status = '${toStatus}'`, `updated_at = CURRENT_TIMESTAMP`];

      if (toStatus === 'resolved') {
        updates.push(`resolved_at = '${now.toISOString()}'`);
      }
      if (toStatus === 'closed') {
        updates.push(`closed_at = '${now.toISOString()}'`);
      }
      if (toStatus === 'in_progress' && ticket.status === 'open') {
        // Assign to sysadmin if provided
        if (performedBy) {
          updates.push(`assigned_to = '${performedBy}'`);
        }
      }

      await client.query(
        `UPDATE support_tickets SET ${updates.join(', ')} WHERE id = $1`,
        [ticketId]
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
      conditions.push(`company_id = $${idx++}`);
      values.push(companyId);
    }
    if (status) {
      conditions.push(`status = $${idx++}`);
      values.push(status);
    }
    if (priority) {
      conditions.push(`priority = $${idx++}`);
      values.push(priority);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const client = await pgPool.connect();
    try {
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const [dataRes, countRes] = await Promise.all([
        client.query(
          `SELECT id, company_id, subject, priority, status, assigned_to,
                  sla_deadline_at, resolved_at, closed_at, created_at, updated_at
           FROM support_tickets
           ${where}
           ORDER BY
             CASE priority WHEN 'P1' THEN 1 WHEN 'P2' THEN 2 WHEN 'P3' THEN 3 ELSE 4 END,
             created_at DESC
           LIMIT $${idx++} OFFSET $${idx++}`,
          [...values, limit, offset]
        ),
        client.query(
          `SELECT COUNT(*) as total FROM support_tickets ${where}`,
          values
        ),
      ]);

      return {
        tickets: dataRes.rows,
        total: parseInt(countRes.rows[0].total, 10),
      };
    } finally {
      client.release();
    }
  }

  /**
   * Generates a one-time 8-digit remote support PIN for a ticket.
   * Used by sysadmin to initiate remote assistance session.
   */
  static async generateSupportPin(ticketId: string): Promise<string> {
    const pin = Math.floor(10000000 + Math.random() * 90000000).toString();

    await pgPool.query(
      `UPDATE support_tickets SET support_pin = $1, updated_at = CURRENT_TIMESTAMP WHERE id = $2`,
      [pin, ticketId]
    );

    logger.info(`Support PIN generated for ticket ${ticketId}`);
    return pin;
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
