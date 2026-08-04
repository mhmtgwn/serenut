import crypto from 'crypto';
import { PoolClient, QueryResultRow } from 'pg';

export type BillingPeriod = 'monthly' | 'yearly';

export interface BillingQuote {
  planId: string;
  planName: string;
  period: BillingPeriod;
  amount: number;
  currency: string;
  deviceLimit: number;
  storeLimit: number;
  userLimit: number;
}

export class BillingDomainService {
  static normalizePeriod(value: unknown): BillingPeriod {
    return value === 'yearly' ? 'yearly' : 'monthly';
  }

  static addPeriod(base: Date, period: BillingPeriod): Date {
    const end = new Date(base);
    if (period === 'yearly') end.setFullYear(end.getFullYear() + 1);
    else end.setMonth(end.getMonth() + 1);
    return end;
  }

  static async quotePlan(
    client: PoolClient,
    companyId: string,
    planId: string,
    requestedPeriod: unknown
  ): Promise<BillingQuote> {
    const result = await client.query(`
      SELECT p.id, p.name, p.price, p.currency,
             COALESCE(o.custom_price, p.price) AS effective_price,
             o.custom_price, o.billing_interval AS override_billing_interval,
             COALESCE(o.device_limit, p.device_limit) AS device_limit,
             COALESCE(o.store_limit, p.store_limit) AS store_limit,
             COALESCE(o.user_limit, p.user_limit) AS user_limit
      FROM plans p
      LEFT JOIN subscription_overrides o ON o.company_id = $2
       AND o.base_plan_id = p.id AND o.is_active = TRUE
       AND CURRENT_TIMESTAMP BETWEEN o.valid_from AND o.valid_until
      WHERE p.id = $1 AND COALESCE(p.is_active, TRUE) = TRUE
    `, [planId, companyId]);
    if (!result.rows.length) throw new Error('plan_not_found');
    const plan = result.rows[0];
    const period = plan.override_billing_interval
      ? this.normalizePeriod(plan.override_billing_interval)
      : this.normalizePeriod(requestedPeriod);
    let amount = Number(plan.effective_price);
    // A custom price is the full price for its explicitly configured interval.
    if (period === 'yearly' && plan.custom_price == null) amount *= 12 * 0.85;
    return {
      planId: plan.id,
      planName: plan.name,
      period,
      amount: Number(amount.toFixed(2)),
      currency: plan.currency || 'TRY',
      deviceLimit: Number(plan.device_limit),
      storeLimit: Number(plan.store_limit),
      userLimit: Number(plan.user_limit),
    };
  }

  static async createQuote(
    client: PoolClient,
    companyId: string,
    planId: string,
    requestedPeriod: unknown,
  ): Promise<BillingQuote & { quoteId: string; expiresAt: Date }> {
    const quote = await this.quotePlan(client, companyId, planId, requestedPeriod);
    const quoteId = this.opaqueId('quote');
    const expiresAt = new Date(Date.now() + 15 * 60 * 1000);
    await client.query(
      `INSERT INTO billing_quotes
       (id,company_id,plan_id,billing_period,amount,currency,snapshot,expires_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7::jsonb,$8)`,
      [quoteId, companyId, quote.planId, quote.period, quote.amount, quote.currency,
        JSON.stringify(quote), expiresAt],
    );
    return { ...quote, quoteId, expiresAt };
  }

  static async lockQuote(
    client: PoolClient,
    companyId: string,
    quoteId: unknown,
  ): Promise<BillingQuote & { quoteId: string }> {
    if (typeof quoteId !== 'string' || !quoteId) throw new Error('quote_required');
    const result = await client.query(
      `SELECT * FROM billing_quotes
       WHERE id=$1 AND company_id=$2 AND expires_at>NOW() AND consumed_by_invoice_id IS NULL
       FOR UPDATE`,
      [quoteId, companyId],
    );
    if (!result.rowCount) throw new Error('quote_invalid_or_expired');
    const row = result.rows[0];
    const snapshot = typeof row.snapshot === 'string' ? JSON.parse(row.snapshot) : row.snapshot;
    return { ...snapshot, quoteId: row.id, amount: Number(row.amount), period: row.billing_period,
      currency: row.currency, planId: row.plan_id };
  }

  static async consumeQuote(client: PoolClient, quoteId: string, invoiceId: string): Promise<void> {
    const result = await client.query(
      `UPDATE billing_quotes SET consumed_by_invoice_id=$1
       WHERE id=$2 AND consumed_by_invoice_id IS NULL`,
      [invoiceId, quoteId],
    );
    if (!result.rowCount) throw new Error('quote_already_consumed');
  }

  static opaqueId(prefix: string): string {
    return `${prefix}-${Date.now()}-${crypto.randomBytes(8).toString('hex')}`;
  }

  static async nextInvoiceNumber(client: PoolClient): Promise<string> {
    const year = new Date().getFullYear();
    await client.query('SELECT pg_advisory_xact_lock($1)', [year * 1009 + 73]);
    const result = await client.query(
      `SELECT COALESCE(MAX(NULLIF(regexp_replace(invoice_number, '^INV-[0-9]{4}-', ''), '')::BIGINT), 0) + 1 AS sequence
       FROM invoices WHERE invoice_number LIKE $1`,
      [`INV-${year}-%`]
    );
    return `INV-${year}-${String(result.rows[0].sequence).padStart(8, '0')}`;
  }

  static invoiceDetails(row: QueryResultRow): Record<string, any> {
    if (!row.billing_details) return {};
    return typeof row.billing_details === 'string'
      ? JSON.parse(row.billing_details)
      : row.billing_details;
  }
}
