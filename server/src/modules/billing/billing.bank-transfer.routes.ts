// server/src/modules/billing/billing.bank-transfer.routes.ts
// Serenut Platform — Bank Transfer & EFT Billing Sub-Router (Phase 5 Modularization)

import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest, requirePermission, requireRole } from '../../middleware/auth.middleware';
import { logger } from '../../config/logger';
import { CommercialLifecycleService } from './commercial_lifecycle.service';
import { RealtimeBroadcastService } from '../realtime/broadcast.service';
import { BillingDomainService } from './billing-domain.service';

const router = Router();

/**
 * @openapi
 * /api/v1/billing/bank-accounts:
 *   get:
 *     summary: List active bank accounts for bank transfer payment
 *     security:
 *       - BearerAuth: []
 */
router.get('/bank-accounts', authenticateUser, async (req, res: Response) => {
  try {
    const includeInactive = req.query.all === 'true' && (req as AuthenticatedRequest).user?.roles?.includes('sysadmin');
    const result = await BillingDomainService.runBypassingRLS(
      `SELECT id, bank_name, account_holder, iban, currency, branch_name, instructions, is_active, display_order
       FROM payment_bank_accounts ${includeInactive ? '' : 'WHERE is_active = TRUE'} ORDER BY display_order ASC`
    );
    return res.json(result.rows);
  } catch (err) {
    logger.error('Error fetching bank accounts:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/billing/notify-transfer:
 *   post:
 *     summary: Customer notifies that bank transfer has been sent
 *     security:
 *       - BearerAuth: []
 */
router.post('/notify-transfer', authenticateUser, requirePermission('billing:view'), async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const { invoice_id, sender_name, sender_bank, transfer_date, transfer_description } = req.body;
  if (!invoice_id) {
    return res.status(400).json({ error: 'missing_fields', message: 'Fatura ID zorunludur.' });
  }
  try {
    const result = await BillingDomainService.runBypassingRLS(
      `UPDATE bank_transfer_notifications
       SET sender_name=$1, sender_bank=$2, transfer_date=$3, transfer_description=$4,
           status='pending_review', updated_at=NOW()
       WHERE invoice_id=$5 AND company_id=$6 AND status='pending'
         AND EXISTS (SELECT 1 FROM invoices i WHERE i.id=$5 AND i.status='pending' AND (i.expires_at IS NULL OR i.expires_at > NOW()))
       RETURNING reference_code`,
      [sender_name || null, sender_bank || null, transfer_date || null, transfer_description || null, invoice_id, user.company_id]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: 'notification_not_found', message: 'Havale bildirimi bulunamadı veya zaten işleme alındı.' });
    }
    await BillingDomainService.runBypassingRLS('UPDATE invoices SET expires_at=NULL, updated_at=NOW() WHERE id=$1 AND company_id=$2', [invoice_id, user.company_id]);
    return res.json({ success: true, message: 'Havale bildiriminiz alındı. Yöneticilerimiz ödemeyi inceleyecektir.', reference_code: result.rows[0].reference_code });
  } catch (err) {
    logger.error('Error updating bank transfer notification:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/admin/pending-transfers:
 *   get:
 *     summary: List pending bank transfer approvals (sysadmin only)
 *     security:
 *       - BearerAuth: []
 */
router.get('/admin/pending-transfers', authenticateUser, requireRole('sysadmin'), async (req, res: Response) => {
  try {
    const result = await BillingDomainService.runBypassingRLS(`
      SELECT btn.id, btn.reference_code, btn.sender_name, btn.sender_bank,
             btn.transfer_date, btn.status, btn.created_at,
             inv.id as invoice_id, inv.amount, inv.invoice_number, inv.billing_details,
             c.id as company_id, c.name as company_name, c.email as company_email,
             pba.bank_name, pba.iban
      FROM bank_transfer_notifications btn
      JOIN invoices inv ON inv.id = btn.invoice_id
      JOIN companies c ON c.id = btn.company_id
      LEFT JOIN payment_bank_accounts pba ON pba.id = btn.bank_account_id
      WHERE btn.status = 'pending_review'
      ORDER BY btn.created_at DESC
      LIMIT 100
    `);
    return res.json(result.rows);
  } catch (err) {
    logger.error('Error fetching pending transfers:', err);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.post('/transfer-requests/:invoiceId/cancel', authenticateUser, requirePermission('billing:view'), async (req: AuthenticatedRequest, res: Response) => {
  try {
    const outcome = await BillingDomainService.withClient(async (client) => {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const result = await client.query(
        `UPDATE invoices SET status='cancelled', updated_at=NOW()
         WHERE id=$1 AND company_id=$2 AND status='pending'
         RETURNING id`, [req.params.invoiceId, req.user!.company_id]
      );
      if (!result.rows.length) {
        await client.query('ROLLBACK');
        return { notCancellable: true };
      }
      await client.query(
        `UPDATE bank_transfer_notifications SET status='cancelled', updated_at=NOW()
         WHERE invoice_id=$1 AND status='pending'`, [req.params.invoiceId]
      );
      await client.query('COMMIT');
      return { success: true };
    });
    if ('notCancellable' in outcome) {
      return res.status(409).json({ error: 'request_not_cancellable', message: 'Bu ödeme talebi artık iptal edilemez.' });
    }
    return res.json({ success: true });
  } catch (error) {
    logger.error('Transfer request cancellation failed:', error);
    return res.status(500).json({ error: 'server_error' });
  }
});

router.put('/admin/invoices/:id/reject-payment', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const note = String(req.body?.note || '').trim();
  if (note.length < 3) return res.status(400).json({ error: 'rejection_note_required', message: 'Red gerekçesi zorunludur.' });
  try {
    const outcome = await BillingDomainService.withClient(async (client) => {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");
      const invoice = await client.query(
        `UPDATE invoices SET status='rejected', updated_at=NOW()
         WHERE id=$1 AND status='pending' RETURNING company_id`, [req.params.id]
      );
      if (!invoice.rows.length) {
        await client.query('ROLLBACK');
        return { notRejectable: true };
      }
      await client.query(
        `UPDATE bank_transfer_notifications
         SET status='rejected', admin_note=$1, reviewed_by=$2, reviewed_at=NOW(), updated_at=NOW()
         WHERE invoice_id=$3 AND status='pending_review'`,
        [note, req.user!.id, req.params.id]
      );
      await client.query(
        `INSERT INTO audit_logs (id,company_id,user_id,user_name,action,entity,entity_id,new_value)
         VALUES ($1,$2,$3,'Admin','REJECTED_BANK_WIRE_PAYMENT','invoice',$4,$5)`,
        [BillingDomainService.opaqueId('al'), invoice.rows[0].company_id, req.user!.id, req.params.id, JSON.stringify({ note })]
      );
      await client.query('COMMIT');
      return { success: true };
    });
    if ('notRejectable' in outcome) {
      return res.status(409).json({ error: 'invoice_not_rejectable' });
    }
    return res.json({ success: true, message: 'Havale bildirimi reddedildi.' });
  } catch (error) {
    logger.error('Transfer rejection failed:', error);
    return res.status(500).json({ error: 'server_error' });
  }
});

/**
 * @openapi
 * /api/v1/billing/admin/invoices/{id}/approve-payment:
 *   put:
 *     summary: Approve a bank transfer payment and activate company entitlement (sysadmin only)
 *     security:
 *       - BearerAuth: []
 */
router.put('/admin/invoices/:id/approve-payment', authenticateUser, requireRole('sysadmin'), async (req: AuthenticatedRequest, res: Response) => {
  const { id } = req.params;
  const adminUserId = req.user!.id;

  try {
    const outcome = await BillingDomainService.withClient(async (client) => {
      await client.query('BEGIN');
      await client.query("SET LOCAL app.bypass_rls = 'true'");

      // 1. Lock invoice row to prevent double-approval
      const invoiceRes = await client.query(
        'SELECT * FROM invoices WHERE id = $1 FOR UPDATE',
        [id]
      );
      if (invoiceRes.rows.length === 0) {
        await client.query('ROLLBACK');
        return { status: 404, body: { error: 'invoice_not_found', message: 'Fatura bulunamadı.' } };
      }

      const invoice = invoiceRes.rows[0];
      if (invoice.status === 'paid') {
        await client.query('ROLLBACK');
        return { status: 400, body: { error: 'already_paid', message: 'Bu fatura zaten daha önce onaylandı.' } };
      }
      const transferClaim = await client.query(
        `SELECT id,reference_code FROM bank_transfer_notifications WHERE invoice_id=$1 AND status='pending_review' FOR UPDATE`,
        [id]
      );
      if (!transferClaim.rows.length) {
        await client.query('ROLLBACK');
        return { status: 409, body: { error: 'transfer_not_pending_review', message: 'Onay bekleyen havale bildirimi bulunamadı.' } };
      }

      // All payment channels finalize through the same atomic lifecycle.
      const activation = await CommercialLifecycleService.finalizeInvoicePayment(
        client, id, 'bank_transfer', adminUserId,
        { amount: Number(invoice.amount), currency: BillingDomainService.invoiceDetails(invoice).currency || 'TRY',
          referenceCode: transferClaim.rows[0].reference_code },
      );

      await client.query(`
        UPDATE bank_transfer_notifications
        SET status = 'approved', reviewed_by = $1, reviewed_at = NOW(), updated_at = NOW()
        WHERE invoice_id = $2 AND status = 'pending_review'
      `, [adminUserId, id]);

      const billingPeriod = BillingDomainService.normalizePeriod(
        BillingDomainService.invoiceDetails(invoice).billingPeriod
      );

      // 6. Write Admin Audit Log (Inside Transaction, non-blocking)
      try {
        const auditId = BillingDomainService.opaqueId('aud');
        const invoiceAfter = { ...invoice, status: 'paid', paid_at: new Date() };
        await client.query(
          `INSERT INTO audit_logs (id, company_id, user_id, action, entity, entity_id, old_value, new_value, ip_address)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
          [
            auditId,
            invoice.company_id,
            adminUserId,
            'APPROVED_BANK_WIRE_PAYMENT',
            'invoices',
            id,
            JSON.stringify(invoice),
            JSON.stringify(invoiceAfter),
            req.ip || 'admin_panel'
          ]
        );
      } catch (auditErr) {
        logger.error('Failed to write admin audit log inside transaction:', auditErr);
      }

      // 7. Send Notification (Inside Transaction, non-blocking, dynamic phone lookup)
      try {
        const companyRes = await client.query('SELECT phone FROM companies WHERE id = $1', [invoice.company_id]);
        const recipientPhone = companyRes.rows[0]?.phone;

        if (recipientPhone && recipientPhone.trim() !== '') {
          const notifId = BillingDomainService.opaqueId('notif');
          await client.query(`
            INSERT INTO notification_queue (id, company_id, channel, recipient, body, status)
            VALUES ($1, $2, 'sms', $3, 'Sayın Müşterimiz, Havale/EFT ödemeniz onaylanmış ve lisansınız aktif edilmiştir.', 'queued')
          `, [notifId, invoice.company_id, recipientPhone]);
        } else {
          logger.warn(`No phone number found for company ${invoice.company_id}. Skipping SMS notification.`);
        }
      } catch (smsErr) {
        logger.error('Failed to queue SMS notification inside transaction:', smsErr);
      }

      await client.query('COMMIT');
      return { status: 200, activation, billingPeriod, invoice };
    });

    if (outcome.status !== 200) {
      return res.status(outcome.status).json(outcome.body);
    }

    const { activation, billingPeriod, invoice } = outcome;
    // Notify open POS and portal sessions immediately. Offline clients refresh
    // their entitlement on their next connection/heartbeat.
    await RealtimeBroadcastService.publishEvent(invoice.company_id, 'LicenseUpdated', {
      subscriptionId: activation.subscriptionId,
      entitlementId: activation.entitlementId,
      invoiceId: id,
      status: 'active',
      billingPeriod,
    });

    logger.info(`Invoice ${id} bank wire approved by admin ${req.user?.email}`);
    return res.json({
      success: true,
      message: 'Ödeme başarıyla onaylandı ve abonelik aktif edildi.',
      billing_period: billingPeriod,
      subscription_id: activation.subscriptionId,
      entitlement_id: activation.entitlementId,
      license_valid_until: activation.validUntil.toISOString(),
    });
  } catch (err: any) {
    logger.error('Error approving invoice payment:', err);
    return res.status(500).json({ error: 'server_error', message: 'Ödeme onaylanırken sunucu hatası oluştu.' });
  }
});

export default router;
