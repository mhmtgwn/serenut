// server/src/modules/order/order.controller.ts
// Serenut OS — Orders API
// Blueprint: api_contract.md — Section ORDERS
// State Machine: state_machine_specification.md — Section 4
// Routes:
//   POST /api/v1/orders              — Create order (Sale FSM)
//   POST /api/v1/orders/:id/refund   — Refund order

import { Router, Response } from 'express';
import {
  authenticateUser,
  AuthenticatedRequest,
  requireActiveEntitlement,
} from '../../middleware/auth.middleware';
import { pgPool } from '../../config/database';
import { createError } from '../../config/error-codes';
import { logger } from '../../config/logger';
import crypto from 'crypto';
import { RealtimeBroadcastService } from '../realtime/broadcast.service';
import { resolvePaidAmount } from './order.policy';
import { RefundService } from './refund.service';

const router = Router();
router.use(authenticateUser);
router.use(requireActiveEntitlement);

// ── ALLOWED ORDER FSM TRANSITIONS ─────────────────────────────────────────────
// pending → completed | cancelled
// completed → refunded | partially_refunded
// partially_refunded → refunded

/**
 * @swagger
 * /orders:
 *   post:
 *     summary: Create a new order (sale)
 *     tags: [Orders]
 *     security:
 *       - BearerAuth: []
 *     requestBody:
 *       required: true
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             required: [branchId, items, paymentMethod]
 *             properties:
 *               branchId: { type: string }
 *               deviceUuid: { type: string }
 *               items:
 *                 type: array
 *                 items:
 *                   type: object
 *                   properties:
 *                     productId: { type: string }
 *                     qty: { type: integer }
 *                     unitPrice: { type: number }
 *               paymentMethod: { type: string, enum: [cash, card, credit, mixed] }
 *               customerId: { type: string, nullable: true }
 *               idempotencyKey: { type: string }
 *               discount: { type: number }
 *     responses:
 *       201:
 *         description: Order created
 *       409:
 *         description: SYNC201 — Idempotency conflict
 */
router.post('/', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const {
    branchId,
    items,
    paymentMethod,
    discount,
    customerId,
    paidAmount,
  } = req.body;
  const idempotencyKey = req.headers['idempotency-key'] as string | undefined;

  // Input validation
  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Sipariş kalemleri zorunludur.' } });
  }
  if (!paymentMethod || !['cash', 'card', 'credit', 'mixed'].includes(paymentMethod)) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Geçerli ödeme yöntemi: cash, card, credit, mixed.' } });
  }
  if (typeof branchId !== 'string' || branchId.trim().length === 0) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Şube zorunludur.' } });
  }
  if (discount != null &&
      (typeof discount !== 'number' || !Number.isFinite(discount) || discount < 0)) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'İndirim geçerli bir pozitif tutar olmalıdır.' } });
  }

  // Validate items structure
  for (const item of items) {
    if (!item.productId || typeof item.qty !== 'number' || !Number.isInteger(item.qty) || item.qty <= 0 ||
        typeof item.unitPrice !== 'number' || !Number.isFinite(item.unitPrice) || item.unitPrice < 0) {
      return res.status(400).json({ error: { code: 'VALIDATION', message: 'Geçersiz kalem verisi.' } });
    }
  }

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    const branchResult = await client.query(
      'SELECT id FROM branches WHERE id = $1 AND company_id = $2',
      [branchId, user.company_id]
    );
    if (branchResult.rows.length === 0) {
      await client.query('ROLLBACK');
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Şube bulunamadı.' } });
    }

    // Idempotency check: if same key exists for this company, return existing
    if (idempotencyKey) {
      const existing = await client.query(
        `SELECT id, total_amount as total, fsm_state as status
         FROM sales WHERE company_id = $1 AND idempotency_key = $2`,
        [user.company_id, idempotencyKey]
      );
      if (existing.rows.length > 0) {
        await client.query('ROLLBACK');
        // Return 200 with existing (not 409) — idempotent success
        return res.json({
          orderId: existing.rows[0].id,
          total: existing.rows[0].total,
          status: existing.rows[0].status,
          idempotent: true,
        });
      }
    }

    const subtotal = items.reduce((sum: number, item: any) => sum + item.qty * item.unitPrice, 0);
    const discountAmount = discount ?? 0;
    if (discountAmount > subtotal) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: { code: 'VALIDATION', message: 'İndirim ara toplamı aşamaz.' } });
    }
    const computedTotal = subtotal - discountAmount;
    
    // Security Fix: Do not trust totalAmount and status from client
    const finalTotal = computedTotal;
    if (paidAmount != null &&
        (typeof paidAmount !== 'number' || !Number.isFinite(paidAmount) || paidAmount < 0 || paidAmount > finalTotal)) {
      await client.query('ROLLBACK');
      return res.status(400).json({ error: { code: 'VALIDATION', message: 'Ödenen tutar sipariş toplamı aralığında olmalıdır.' } });
    }
    const finalPaid = resolvePaidAmount(paymentMethod, paidAmount, finalTotal);
    const finalStatus = 'completed';

    const orderId = req.body.id || `ord-${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;

    // Normalize customerId (nullify walkin or empty)
    const rawCustomerId = customerId;
    const finalCustomerId = (rawCustomerId && rawCustomerId !== 'walkin' && rawCustomerId !== '') ? rawCustomerId : null;

    if (finalCustomerId) {
      const customerResult = await client.query(
        'SELECT id FROM customers WHERE id = $1 AND company_id = $2',
        [finalCustomerId, user.company_id]
      );
      if (customerResult.rows.length === 0) {
        await client.query('ROLLBACK');
        return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Müşteri bulunamadı.' } });
      }
    }

    // Insert sale
    await client.query(
      `INSERT INTO sales
         (id, company_id, branch_id, customer_id, payment_method,
          total_amount, paid_amount, status, fsm_state, idempotency_key, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'completed', $9, COALESCE($10, CURRENT_TIMESTAMP))`,
      [
        orderId, user.company_id, branchId,
        finalCustomerId, paymentMethod, finalTotal, finalPaid,
        finalStatus, idempotencyKey ?? null, req.body.createdAt ?? null
      ]
    );

    // Insert sale items
    for (const item of items) {
      await client.query(
        `INSERT INTO sale_items (id, sale_id, product_id, quantity, unit_price, subtotal, company_id)
         VALUES ($1, $2, $3, $4, $5, $6, $7)`,
        [
          crypto.randomUUID(), orderId, item.productId,
          item.qty, item.unitPrice, item.qty * item.unitPrice, user.company_id,
        ]
      );

      // Update stock
      // Update stock with strict rollback on insufficient quantity
      const stockRes = await client.query(
        `UPDATE products SET quantity = quantity - $1, updated_at = CURRENT_TIMESTAMP
         WHERE id = $2 AND company_id = $3 AND quantity >= $1 RETURNING id`,
        [item.qty, item.productId, user.company_id]
      );
      if (stockRes.rowCount === 0) {
        await client.query('ROLLBACK');
        return res.status(400).json({ error: { code: 'INSUFFICIENT_STOCK', message: `Product ${item.productId} is out of stock or insufficient.` } });
      }
      await client.query(
        `INSERT INTO inventory_movements
           (id,company_id,product_id,movement_type,quantity_delta,reference_type,reference_id,created_by)
         VALUES($1,$2,$3,'sale',$4,'sale',$5,$6)`,
        [crypto.randomUUID(), user.company_id, item.productId, -item.qty, orderId, user.id]
      );
    }

    await client.query('COMMIT');

    RealtimeBroadcastService.publishEvent(user.company_id, 'OrderCreated', {
      sale_id: orderId,
      total_amount: finalTotal,
      payment_method: paymentMethod,
      customer_id: finalCustomerId
    }).catch(() => {});

    return res.status(201).json({
      orderId,
      total: finalTotal,
      status: finalStatus,
    });
  } catch (err: any) {
    await client.query('ROLLBACK');
    logger.error('Create order transaction failed', {
      error: err.message,
      stack: err.stack,
      code: err.code,
      constraint: err.constraint,
      companyId: user.company_id,
      body: req.body
    });

    if (err.code === '23503') {
      if (err.constraint === 'sales_customer_id_fkey') {
        return res.status(400).json({ error: { code: 'VALIDATION', message: 'Belirtilen müşteri bulunamadı.' } });
      }
      if (err.constraint === 'sale_items_product_id_fkey') {
        return res.status(400).json({ error: { code: 'VALIDATION', message: 'Belirtilen ürün bulunamadı.' } });
      }
      return res.status(400).json({ error: { code: 'VALIDATION', message: 'Geçersiz referans (ilişkili kayıt bulunamadı).' } });
    }

    if (err.code === '23505') {
      return res.status(409).json({ error: { code: 'CONFLICT', message: 'Bu sipariş veya işlem anahtarı zaten mevcut.' } });
    }

    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'Sipariş oluşturulamadı.' } });
  } finally {
    client.release();
  }
});

/**
 * @swagger
 * /orders/{id}/refund:
 *   post:
 *     summary: Refund an order
 *     tags: [Orders]
 *     security:
 *       - BearerAuth: []
 *     requestBody:
 *       content:
 *         application/json:
 *           schema:
 *             type: object
 *             properties:
 *               amount: { type: number, description: "Partial refund amount. Omit for full refund." }
 *               reason: { type: string }
 *     responses:
 *       200:
 *         description: Refund processed
 *       403:
 *         description: AUTH005 — sales.refund permission required
 */
router.post('/:id/refund', async (req: AuthenticatedRequest, res: Response) => {
  const user = req.user!;
  const isAuthorized =
    user.permissions?.includes('sales.refund') ||
    user.roles?.includes('owner') ||
    user.roles?.includes('admin') ||
    user.roles?.includes('manager');

  if (!isAuthorized) {
    return res.status(403).json(createError('AUTH005', 'sales.refund permission required'));
  }

  const { id } = req.params;
  const { items, refundMethod, externalReference, reason } = req.body;
  const idempotencyKey = req.headers['idempotency-key'] as string | undefined;
  if (!idempotencyKey) {
    return res.status(400).json({ error: { code: 'IDEMPOTENCY_REQUIRED', message: 'İade için idempotency-key zorunludur.' } });
  }

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    const result = await RefundService.create(client, {
      companyId: user.company_id,
      saleId: id,
      actorId: user.id,
      idempotencyKey,
      reason: typeof reason === 'string' ? reason : '',
      refundMethod,
      externalReference,
      items: Array.isArray(items)
        ? items.map((item: any) => ({ saleItemId: item.saleItemId, quantity: item.quantity }))
        : undefined,
    });

    await client.query('COMMIT');

    RealtimeBroadcastService.publishEvent(user.company_id, 'OrderRefunded', {
      sale_id: id,
      refund_id: result.refundId,
      amount: result.amount,
      status: result.status,
    }).catch(() => {});

    return res.json({
      refundId: result.refundId,
      orderId: id,
      refundedAmount: result.amount,
      totalRefunded: result.totalRefunded,
      status: result.status,
      idempotent: result.idempotent === true,
    });
  } catch (err: any) {
    await client.query('ROLLBACK');
    logger.error('Refund error:', err);
    const statusByError: Record<string, number> = {
      sale_not_found: 404,
      sale_not_refundable: 409,
      invalid_refund_quantity: 409,
      duplicate_refund_item: 400,
      refund_product_missing: 409,
      refund_amount_exceeds_sale: 409,
      idempotency_key_required: 400,
      refund_reason_required: 400,
      invalid_refund_method: 400,
      external_refund_reference_required: 400,
      refund_items_required: 400,
      sale_items_missing: 409,
    };
    if (statusByError[err.message]) {
      return res.status(statusByError[err.message]).json({ error: { code: err.message.toUpperCase(), message: err.message } });
    }
    if (err.code === '23505') {
      return res.status(409).json({ error: { code: 'REFUND_CONFLICT', message: 'İade eşzamanlı olarak işlendi; tekrar sorgulayın.' } });
    }
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'İade işlemi gerçekleştirilemedi.' } });
  } finally {
    client.release();
  }
});

export default router;
