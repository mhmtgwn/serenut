// server/src/modules/order/order.controller.ts
// Serenut OS — Orders API
// Blueprint: api_contract.md — Section ORDERS
// State Machine: state_machine_specification.md — Section 4
// Routes:
//   POST /api/v1/orders              — Create order (Sale FSM)
//   POST /api/v1/orders/:id/refund   — Refund order

import { Router, Response } from 'express';
import { authenticateUser, AuthenticatedRequest } from '../../middleware/auth.middleware';
import { pgPool } from '../../config/database';
import { createError } from '../../config/error-codes';
import { logger } from '../../config/logger';
import crypto from 'crypto';

const router = Router();
router.use(authenticateUser);

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
 *               paymentMethod: { type: string, enum: [cash, card, credit] }
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
    deviceUuid,
    items,
    paymentMethod,
    customerId,
    idempotencyKey,
    discount,
    note,
  } = req.body;

  // Input validation
  if (!items || !Array.isArray(items) || items.length === 0) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Sipariş kalemleri zorunludur.' } });
  }
  if (!paymentMethod || !['cash', 'card', 'credit', 'debt', 'mixed'].includes(paymentMethod)) {
    return res.status(400).json({ error: { code: 'VALIDATION', message: 'Geçerli ödeme yöntemi: cash, card, credit, debt, mixed.' } });
  }

  // Validate items structure
  for (const item of items) {
    if (!item.productId || typeof item.qty !== 'number' || item.qty <= 0 || typeof item.unitPrice !== 'number') {
      return res.status(400).json({ error: { code: 'VALIDATION', message: 'Geçersiz kalem verisi.' } });
    }
  }

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

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
    const computedTotal = Math.max(0, subtotal - discountAmount);
    
    const finalTotal = req.body.totalAmount ?? computedTotal;
    const finalPaid = req.body.paidAmount ?? finalTotal;
    const finalStatus = req.body.status ?? 'completed';

    const orderId = req.body.id || `ord-${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;

    // Normalize customerId (nullify walkin or empty)
    const rawCustomerId = req.body.customerId;
    const finalCustomerId = (rawCustomerId && rawCustomerId !== 'walkin' && rawCustomerId !== '') ? rawCustomerId : null;

    // Insert sale
    await client.query(
      `INSERT INTO sales
         (id, company_id, branch_id, customer_id, payment_method,
          total_amount, paid_amount, status, fsm_state, idempotency_key, created_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'completed', $9, COALESCE($10, CURRENT_TIMESTAMP))`,
      [
        orderId, user.company_id, req.body.branchId ?? null,
        finalCustomerId, paymentMethod, finalTotal, finalPaid,
        finalStatus, req.body.idempotencyKey ?? null, req.body.createdAt ?? null
      ]
    );

    // Insert sale items
    for (const item of items) {
      await client.query(
        `INSERT INTO sale_items (id, sale_id, product_id, quantity, unit_price, subtotal)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [
          crypto.randomUUID(), orderId, item.productId,
          item.qty, item.unitPrice, item.qty * item.unitPrice,
        ]
      );

      // Update stock
      await client.query(
        `UPDATE products SET quantity = GREATEST(0, quantity - $1), updated_at = CURRENT_TIMESTAMP
         WHERE id = $2 AND company_id = $3`,
        [item.qty, item.productId, user.company_id]
      );
    }

    await client.query('COMMIT');

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
  const { amount, reason } = req.body;

  const client = await pgPool.connect();
  try {
    await client.query('BEGIN');
    await client.query("SET LOCAL app.bypass_rls = 'true'");

    const saleRes = await client.query(
      `SELECT id, total_amount, refunded_amount, fsm_state FROM sales
       WHERE id = $1 AND company_id = $2`,
      [id, user.company_id]
    );

    if (saleRes.rows.length === 0) {
      return res.status(404).json({ error: { code: 'NOT_FOUND', message: 'Sipariş bulunamadı.' } });
    }

    const sale = saleRes.rows[0];

    if (!['completed', 'partially_refunded'].includes(sale.fsm_state)) {
      return res.status(409).json({
        error: { code: 'INVALID_STATE', message: `${sale.fsm_state} durumundaki sipariş iade edilemez.` },
      });
    }

    const maxRefundable = parseFloat(sale.total_amount) - parseFloat(sale.refunded_amount ?? 0);
    const refundAmount = amount ?? maxRefundable;

    if (refundAmount <= 0 || refundAmount > maxRefundable) {
      return res.status(400).json({
        error: { code: 'VALIDATION', message: `İade tutarı 0 ile ${maxRefundable} arasında olmalıdır.` },
      });
    }

    const newRefunded = parseFloat(sale.refunded_amount ?? 0) + refundAmount;
    const isFullRefund = newRefunded >= parseFloat(sale.total_amount);
    const newState = isFullRefund ? 'refunded' : 'partially_refunded';

    const refundId = `ref-${Date.now()}-${crypto.randomBytes(3).toString('hex')}`;

    await client.query(
      `UPDATE sales
       SET fsm_state = $1, refunded_amount = $2, refund_reason = $3, updated_at = CURRENT_TIMESTAMP
       WHERE id = $4`,
      [newState, newRefunded, reason ?? null, id]
    );

    await client.query('COMMIT');

    return res.json({
      refundId,
      orderId: id,
      refundedAmount: refundAmount,
      totalRefunded: newRefunded,
      status: newState,
    });
  } catch (err: any) {
    await client.query('ROLLBACK');
    console.error('Refund error:', err);
    return res.status(500).json({ error: { code: 'SERVER_ERROR', message: 'İade işlemi gerçekleştirilemedi.' } });
  } finally {
    client.release();
  }
});

export default router;
