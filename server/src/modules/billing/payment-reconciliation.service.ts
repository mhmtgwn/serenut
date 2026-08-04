import { pgPool } from '../../config/database';
import { BillingDomainService } from './billing-domain.service';
import { CommercialLifecycleService } from './commercial_lifecycle.service';
import { IyzicoService } from './iyzico.service';

export class PaymentReconciliationService {
  static async reconcileInvoice(invoiceId: string) {
    const lookup = await pgPool.connect();
    let invoice: any;
    try {
      await lookup.query('BEGIN');
      await lookup.query("SET LOCAL app.bypass_rls='true'");
      const result = await lookup.query(
        `SELECT * FROM invoices WHERE id=$1 AND status IN('pending','verification_pending')`,
        [invoiceId],
      );
      invoice = result.rows[0];
      await lookup.query('COMMIT');
    } catch (error) {
      await lookup.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally { lookup.release(); }
    if (!invoice) return { status: 'terminal' as const };
    const token = invoice.billing_details?.iyzicoToken;
    if (!token) throw new Error('invoice_provider_token_missing');
    const verified = await IyzicoService.retrieveCheckoutResult(token);
    const amount = Number(verified.paidPrice ?? verified.price);
    const currency = verified.currency || BillingDomainService.invoiceDetails(invoice).currency || 'TRY';
    if (verified.status === 'success' && verified.paymentId && Number.isFinite(amount) &&
        Math.abs(amount-Number(invoice.amount)) <= 0.009 &&
        currency === (BillingDomainService.invoiceDetails(invoice).currency || 'TRY')) {
      const client = await pgPool.connect();
      try {
        await client.query('BEGIN');
        await client.query("SET LOCAL app.bypass_rls='true'");
        const activation = await CommercialLifecycleService.finalizeInvoicePayment(
          client, invoice.id, 'card', undefined,
          { providerTransactionId: verified.paymentId, amount, currency },
        );
        await client.query('COMMIT');
        return { status: 'paid' as const, invoice, activation };
      } catch (error) {
        await client.query('ROLLBACK').catch(() => undefined);
        throw error;
      } finally { client.release(); }
    }
    const retry = await pgPool.connect();
    try {
      await retry.query('BEGIN');
      await retry.query("SET LOCAL app.bypass_rls='true'");
      const expired = invoice.expires_at && new Date(invoice.expires_at) <= new Date();
      await retry.query(
        `UPDATE invoices SET status=$1,verification_attempts=verification_attempts+1,
           verification_error=$2,next_verification_at=CASE WHEN $1='verification_pending'
             THEN NOW()+INTERVAL '15 minutes' ELSE NULL END,updated_at=NOW()
         WHERE id=$3 AND status IN('pending','verification_pending')`,
        [expired ? 'failed' : 'verification_pending', verified.errorMessage || 'provider_verification_pending', invoice.id],
      );
      await retry.query('COMMIT');
      return { status: expired ? 'failed' as const : 'pending' as const, invoice };
    } catch (error) {
      await retry.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally { retry.release(); }
  }

  static async reconcileBatch(limit=50) {
    const due = await pgPool.connect();
    let ids: string[] = [];
    try {
      await due.query('BEGIN');
      await due.query("SET LOCAL app.bypass_rls='true'");
      const rows = await due.query(
        `SELECT id FROM invoices WHERE status='verification_pending'
         AND (next_verification_at IS NULL OR next_verification_at<=NOW())
         ORDER BY updated_at LIMIT $1`, [limit]);
      ids = rows.rows.map(row => row.id);
      await due.query('COMMIT');
    } catch (error) {
      await due.query('ROLLBACK').catch(() => undefined);
      throw error;
    } finally { due.release(); }
    for (const id of ids) await this.reconcileInvoice(id);
    return ids.length;
  }
}
