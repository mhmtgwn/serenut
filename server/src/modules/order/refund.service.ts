import crypto from 'crypto';
import type { PoolClient } from 'pg';

export type RefundItemInput = { saleItemId: string; quantity: number };

export class RefundService {
  static async create(client: PoolClient, params: {
    companyId: string;
    saleId: string;
    actorId: string;
    idempotencyKey: string;
    reason: string;
    refundMethod: 'cash' | 'balance' | 'card' | 'mixed';
    externalReference?: string;
    items?: RefundItemInput[];
    refundId?: string;
  }): Promise<{ refundId: string; amount: number; totalRefunded: number; status: string; idempotent?: boolean }> {
    if (!params.idempotencyKey || params.idempotencyKey.length > 100) throw new Error('idempotency_key_required');
    if (params.reason.trim().length < 3) throw new Error('refund_reason_required');
    if (!['cash','balance','card','mixed'].includes(params.refundMethod)) throw new Error('invalid_refund_method');
    if ((params.refundMethod === 'card' || params.refundMethod === 'mixed') && !params.externalReference?.trim()) {
      throw new Error('external_refund_reference_required');
    }
    const prior = await client.query(
      `SELECT r.id,r.amount,s.refunded_amount,s.fsm_state
       FROM refunds r JOIN sales s ON s.id=r.sale_id AND s.company_id=r.company_id
       WHERE r.company_id=$1 AND r.idempotency_key=$2 AND r.sale_id=$3`,
      [params.companyId, params.idempotencyKey, params.saleId],
    );
    if (prior.rowCount) return { refundId: prior.rows[0].id, amount: Number(prior.rows[0].amount),
      totalRefunded: Number(prior.rows[0].refunded_amount), status: prior.rows[0].fsm_state, idempotent: true };

    const saleResult = await client.query(
      `SELECT id,total_amount,refunded_amount,fsm_state,payment_method,customer_id
       FROM sales WHERE id=$1 AND company_id=$2 FOR UPDATE`,
      [params.saleId, params.companyId],
    );
    if (!saleResult.rowCount) throw new Error('sale_not_found');
    const sale = saleResult.rows[0];
    // A concurrent request may have committed while this request waited for the
    // sale lock. Re-read the key under the aggregate lock before any mutation.
    const committedPrior = await client.query(
      `SELECT r.id,r.amount,s.refunded_amount,s.fsm_state
       FROM refunds r JOIN sales s ON s.id=r.sale_id AND s.company_id=r.company_id
       WHERE r.company_id=$1 AND r.idempotency_key=$2 AND r.sale_id=$3`,
      [params.companyId, params.idempotencyKey, params.saleId],
    );
    if (committedPrior.rowCount) return {
      refundId: committedPrior.rows[0].id,
      amount: Number(committedPrior.rows[0].amount),
      totalRefunded: Number(committedPrior.rows[0].refunded_amount),
      status: committedPrior.rows[0].fsm_state,
      idempotent: true,
    };
    if (!['completed','partially_refunded'].includes(sale.fsm_state)) throw new Error('sale_not_refundable');

    const saleItems = await client.query(
      `SELECT si.id,si.product_id,si.quantity,si.subtotal,
              COALESCE((SELECT SUM(ri.quantity) FROM refund_items ri WHERE ri.sale_item_id=si.id),0) AS refunded_quantity
       FROM sale_items si WHERE si.sale_id=$1 AND si.company_id=$2 ORDER BY si.id FOR UPDATE`,
      [params.saleId, params.companyId],
    );
    if (!saleItems.rowCount) throw new Error('sale_items_missing');
    if (params.items?.length && new Set(params.items.map(item => item.saleItemId)).size !== params.items.length) {
      throw new Error('duplicate_refund_item');
    }
    const requested = params.items?.length
      ? new Map(params.items.map(item => [item.saleItemId, item.quantity]))
      : new Map(saleItems.rows.map(row => [row.id, Number(row.quantity)-Number(row.refunded_quantity)]));
    if (!requested.size) throw new Error('refund_items_required');
    const normalized: Array<{ saleItemId:string; productId:string; quantity:number; unit:number; subtotal:number }> = [];
    let amount = 0;
    for (const [saleItemId, quantityValue] of requested) {
      const row = saleItems.rows.find(item => item.id === saleItemId);
      const quantity = Number(quantityValue);
      if (!row || !Number.isFinite(quantity) || !Number.isInteger(quantity) || quantity <= 0 ||
          quantity > Number(row.quantity)-Number(row.refunded_quantity)+0.000001) throw new Error('invalid_refund_quantity');
      const unit = Number(row.subtotal)/Number(row.quantity);
      const subtotal = Number((unit*quantity).toFixed(2));
      amount += subtotal;
      normalized.push({ saleItemId, productId: row.product_id, quantity, unit, subtotal });
    }
    amount = Number(amount.toFixed(2));
    const remaining = Number(sale.total_amount)-Number(sale.refunded_amount || 0);
    if (amount <= 0 || amount > remaining+0.01) throw new Error('refund_amount_exceeds_sale');
    const refundId = params.refundId?.trim() || `ref-${Date.now()}-${crypto.randomBytes(8).toString('hex')}`;
    if (refundId.length > 100) throw new Error('invalid_refund_id');
    await client.query(
      `INSERT INTO refunds(id,company_id,sale_id,idempotency_key,amount,refund_method,external_reference,reason,created_by)
       VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
      [refundId,params.companyId,params.saleId,params.idempotencyKey,amount,params.refundMethod,
        params.externalReference?.trim() || null,params.reason.trim(),params.actorId],
    );
    for (const item of normalized) {
      await client.query(
        `INSERT INTO refund_items(id,refund_id,sale_item_id,product_id,quantity,unit_refund_amount,subtotal)
         VALUES($1,$2,$3,$4,$5,$6,$7)`,
        [crypto.randomUUID(),refundId,item.saleItemId,item.productId,item.quantity,item.unit,item.subtotal],
      );
      const stockUpdate = await client.query(
        `UPDATE products SET quantity=quantity+$1,updated_at=NOW() WHERE id=$2 AND company_id=$3`,
        [item.quantity,item.productId,params.companyId],
      );
      if (!stockUpdate.rowCount) throw new Error('refund_product_missing');
      await client.query(
        `INSERT INTO inventory_movements(id,company_id,product_id,movement_type,quantity_delta,reference_type,reference_id,created_by)
         VALUES($1,$2,$3,'refund',$4,'refund',$5,$6)`,
        [crypto.randomUUID(),params.companyId,item.productId,item.quantity,refundId,params.actorId],
      );
    }
    const totalRefunded = Number((Number(sale.refunded_amount || 0)+amount).toFixed(2));
    const state = totalRefunded >= Number(sale.total_amount)-0.01 ? 'refunded' : 'partially_refunded';
    await client.query(
      `UPDATE sales SET refunded_amount=$1,fsm_state=$2,refund_reason=$3,updated_at=NOW()
       WHERE id=$4 AND company_id=$5`,
      [totalRefunded,state,params.reason.trim(),params.saleId,params.companyId],
    );
    if (sale.customer_id) {
      await client.query(
        `INSERT INTO financial_transactions
         (id,company_id,type,customer_id,amount,paid_amount,debt_amount,date,reference_id,description,payment_method)
         VALUES($1,$2,'refund',$3,$4,$5,0,NOW(),$6,$7,$8)`,
        [`tx-${crypto.randomUUID()}`,params.companyId,sale.customer_id,amount,
          params.refundMethod==='balance'?0:amount,refundId,params.reason.trim(),params.refundMethod],
      );
    }
    return { refundId,amount,totalRefunded,status:state };
  }
}
