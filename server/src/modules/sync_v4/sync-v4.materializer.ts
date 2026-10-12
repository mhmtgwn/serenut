import type { PoolClient } from "pg";
import { RefundService } from "../order/refund.service";
import { logger } from "../../config/logger";

export type SyncMutation = {
  entity_type: string;
  entity_id: string;
  operation: "UPSERT" | "DELETE";
  base_revision: number;
  payload: Record<string, unknown>;
};

export const stringValue = (payload: Record<string, unknown>, key: string, fallback = ""): string =>
  typeof payload[key] === "string" ? (payload[key] as string).trim() : fallback;

export const numberValue = (payload: Record<string, unknown>, key: string, fallback = 0): number => {
  const value = Number(payload[key]);
  return Number.isFinite(value) ? value : fallback;
};

export const nullableId = (value: string): string | null => (value.length ? value : null);

/**
 * Applies a replicated aggregate to the tenant's actual business tables.
 * The replication log is written only after this function succeeds, in the
 * same PostgreSQL transaction. This prevents a false "synced" state.
 */
export async function applyDomainMutation(
  client: PoolClient,
  companyId: string,
  mutation: SyncMutation,
  actorId?: string,
): Promise<void> {
  const payload = mutation.payload;
  let id = mutation.entity_id;

  // A legacy ready catalogue encoded EAN-8 values as numbers and therefore
  // dropped their leading zero. Old clients may still replay those aliases.
  // Resolve only an exact seven/eight-digit, same-name, same-price match; an
  // arbitrary merchant-defined seven-digit code must remain untouched.
  if (mutation.entity_type === "product" && mutation.operation === "UPSERT" &&
      /^\d{7}$/.test(id)) {
    const canonical = await client.query(
      `SELECT id FROM products
       WHERE id = $1 AND company_id = $2
         AND lower(btrim(name)) = lower(btrim($3))
         AND abs(price - $4) <= 0.01
       LIMIT 1`,
      [`0${id}`, companyId, stringValue(payload, "name"), numberValue(payload, "price")],
    );
    if (canonical.rowCount) id = canonical.rows[0].id;
  }

  if (mutation.operation === "DELETE") {
    switch (mutation.entity_type) {
      case "product":
        await client.query(
          "UPDATE products SET is_deleted = true, status = 'inactive', deleted_at = NOW(), updated_at = NOW() WHERE id = $1 AND company_id = $2",
          [id, companyId],
        );
        return;
      case "customer":
        await client.query(
          "UPDATE customers SET is_deleted = true, status = 'inactive', deleted_at = NOW(), updated_at = NOW() WHERE id = $1 AND company_id = $2",
          [id, companyId],
        );
        return;
      case "order":
        await client.query(
          "UPDATE customer_orders SET is_deleted = true, deleted_at = NOW(), updated_at = NOW() WHERE id = $1 AND company_id = $2",
          [id, companyId],
        );
        return;
      case "sale":
        throw new Error("immutable_sale");
      case "financial_transaction":
        await client.query(
          "UPDATE financial_transactions SET is_deleted = true, deleted_at = NOW(), updated_at = NOW() WHERE id = $1 AND company_id = $2",
          [id, companyId],
        );
        return;
      case "refund":
        throw new Error("immutable_refund");
    }
  }

  switch (mutation.entity_type) {
    case "product": {
      const name = stringValue(payload, "name");
      if (!name) throw new Error("invalid_mutation");
      const deleted = payload.is_deleted === 1 || payload.is_deleted === true;
      await client.query(
        `INSERT INTO products (id, company_id, name, description, price, purchase_price, quantity, min_stock, brand, unit, shelf_code, category, sku, vat, image_path, status, is_deleted, created_at, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,COALESCE($18::timestamptz,NOW()),NOW())
         ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, description=EXCLUDED.description,
           price=EXCLUDED.price, purchase_price=EXCLUDED.purchase_price, quantity=EXCLUDED.quantity,
           min_stock=EXCLUDED.min_stock, brand=EXCLUDED.brand, unit=EXCLUDED.unit,
           shelf_code=EXCLUDED.shelf_code, category=EXCLUDED.category, sku=EXCLUDED.sku,
           vat=EXCLUDED.vat, image_path=EXCLUDED.image_path, status=EXCLUDED.status,
           is_deleted=EXCLUDED.is_deleted, deleted_at=CASE WHEN EXCLUDED.is_deleted THEN NOW() ELSE NULL END,
           updated_at=NOW() WHERE products.company_id=EXCLUDED.company_id`,
        [id, companyId, name, stringValue(payload, "description"), numberValue(payload, "price"),
          numberValue(payload, "purchase_price"), numberValue(payload, "quantity"),
          numberValue(payload, "min_stock", 5), stringValue(payload, "brand"),
          stringValue(payload, "unit", "adet"), stringValue(payload, "shelf_code"),
          stringValue(payload, "category", "Genel"),
          stringValue(payload, "sku", id), Number.isFinite(Number(payload.vat)) ? Number(payload.vat) : null,
          stringValue(payload, "image_url") || null, deleted ? "inactive" : stringValue(payload, "status", "active"),
          deleted, stringValue(payload, "created_at") || null],
      );
      return;
    }
    case "customer": {
      const name = stringValue(payload, "name");
      if (!name) throw new Error("invalid_mutation");
      const deleted = payload.is_deleted === 1 || payload.is_deleted === true;
      await client.query(
        `INSERT INTO customers (id, company_id, name, email, phone, address, balance, credit_limit, status, is_deleted, created_at, updated_at)
         VALUES ($1,$2,$3,$4,$5,$6,0,$7,$8,$9,COALESCE($10::timestamptz,NOW()),NOW())
         ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, email=EXCLUDED.email, phone=EXCLUDED.phone, address=EXCLUDED.address,
           credit_limit=EXCLUDED.credit_limit, status=EXCLUDED.status,
           is_deleted=EXCLUDED.is_deleted, deleted_at=CASE WHEN EXCLUDED.is_deleted THEN NOW() ELSE NULL END,
           updated_at=NOW() WHERE customers.company_id=EXCLUDED.company_id`,
        [id, companyId, name, stringValue(payload, "email") || null, stringValue(payload, "phone") || null,
          stringValue(payload, "address") || null,
          numberValue(payload, "credit_limit"),
          deleted ? "inactive" : stringValue(payload, "status", "active"), deleted,
          stringValue(payload, "created_at") || null],
      );
      return;
    }
    case "sale":
      await upsertSale(client, companyId, id, payload);
      return;
    case "order":
      await upsertOrder(client, companyId, id, payload);
      return;
    case "financial_transaction":
      await upsertFinancialTransaction(client, companyId, id, payload);
      return;
    case "refund": {
      if (!actorId) throw new Error("refund_actor_required");
      const rawItems = Array.isArray(payload.items) ? payload.items : [];
      await RefundService.create(client, {
        companyId,
        saleId: stringValue(payload, "sale_id"),
        actorId,
        idempotencyKey: id,
        refundId: id,
        reason: stringValue(payload, "reason"),
        refundMethod: stringValue(payload, "refund_method") as 'cash'|'balance'|'card'|'mixed',
        externalReference: stringValue(payload, "external_reference") || undefined,
        items: rawItems.map((item: any) => ({
          saleItemId: typeof item?.sale_item_id === 'string' ? item.sale_item_id : '',
          quantity: Number(item?.quantity),
        })),
      });
      return;
    }
  }
}

export async function upsertSale(
  client: PoolClient,
  companyId: string,
  id: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const customerId = nullableId(stringValue(payload, "customer_id"));
  const paymentMethod = stringValue(payload, "payment_method", "cash");
  const items = Array.isArray(payload.items) ? payload.items : [];
  if (!items.length || !["cash", "card", "credit", "mixed", "veresiye", "debt", "karma"].includes(paymentMethod)) {
    throw new Error("invalid_sale");
  }
  const prior = await client.query(
    "SELECT id FROM sales WHERE id = $1 AND company_id = $2 FOR UPDATE",
    [id, companyId],
  );
  // A completed sale is an immutable financial fact. Replayed materialization
  // is a no-op; later changes must be represented by a refund/reversal.
  if (prior.rowCount) return;
  if (customerId) {
    const customer = await client.query(
      "SELECT id FROM customers WHERE id = $1 AND company_id = $2 AND is_deleted = false",
      [customerId, companyId],
    );
    if (!customer.rowCount) throw new Error("invalid_customer");
  }
  let computedTotal = 0;
  const normalizedItems: Array<{ id: string; productId: string; productName: string | null; quantity: number; unitPrice: number; subtotal: number; createdAt: string | null }> = [];
  for (let index = 0; index < items.length; index++) {
    const item = items[index];
    if (!item || typeof item !== "object") throw new Error("invalid_mutation");
    const row = item as Record<string, unknown>;
    const productId = stringValue(row, "product_id");
    const quantity = numberValue(row, "quantity", Number.NaN);
    const unitPrice = numberValue(row, "unit_price", numberValue(row, "price", Number.NaN));
    if (!productId || !Number.isFinite(quantity) || quantity <= 0 ||
        !Number.isFinite(unitPrice) || unitPrice < 0) throw new Error("invalid_sale_item");
    const subtotal = quantity * unitPrice;
    computedTotal += subtotal;
    normalizedItems.push({
      id: stringValue(row, "id", `sync-${id}-${index}`),
      productId,
      productName: stringValue(row, "product_name") || null,
      quantity,
      unitPrice,
      subtotal,
      createdAt: stringValue(row, "created_at") || null,
    });
  }
  const clientTotal = numberValue(payload, "total_amount", Number.NaN);
  const paidAmount = numberValue(payload, "paid_amount", Number.NaN);
  const discountAmount = numberValue(payload, "discount_amount", 0);
  const expectedTotal = Math.max(0, Number((computedTotal - discountAmount).toFixed(2)));

  if (!Number.isFinite(clientTotal) || Math.abs(clientTotal - expectedTotal) > 0.05 ||
      !Number.isFinite(paidAmount) || paidAmount < 0) {
    throw new Error("sale_total_mismatch");
  }
  if ((paymentMethod === "credit" || paymentMethod === "veresiye" || paymentMethod === "debt") && paidAmount !== 0) {
    throw new Error("invalid_credit_payment");
  }
  if (paymentMethod === "card" && Math.abs(paidAmount - expectedTotal) > 0.05) {
    throw new Error("invalid_full_payment");
  }
  if (paymentMethod === "cash" && paidAmount < expectedTotal - 0.05) {
    throw new Error("invalid_full_payment");
  }

  const effectivePaidAmount = Math.min(paidAmount, expectedTotal);
  await client.query(
    `INSERT INTO sales (id, company_id, customer_id, total_amount, paid_amount, discount_amount, payment_method, status, fsm_state, idempotency_key, created_at, updated_at, is_deleted, created_by)
     VALUES ($1,$2,$3,$4,$5,$6,$7,'completed','completed',$8,COALESCE($9::timestamptz,NOW()),NOW(),false,$10)`,
    [id, companyId, customerId, clientTotal, effectivePaidAmount, discountAmount, paymentMethod,
      stringValue(payload, "idempotency_key") || null, stringValue(payload, "created_at") || null,
      stringValue(payload, "created_by") || null],
  );
  for (const row of normalizedItems) {
    await client.query(
      `UPDATE products SET quantity = quantity - $1, updated_at = NOW()
       WHERE id = $2 AND company_id = $3 AND is_deleted = false`,
      [row.quantity, row.productId, companyId],
    );
    await client.query(
      `INSERT INTO inventory_movements(id,company_id,product_id,movement_type,quantity_delta,reference_type,reference_id,created_by)
       VALUES($1,$2,$3,'sale',$4,'sale',$5,$6)`,
      [`mov-${id}-${row.id}`, companyId, row.productId, -row.quantity, id,
        stringValue(payload, "created_by") || null],
    );
    await client.query(
      `INSERT INTO sale_items (id, sale_id, product_id, product_name, quantity, unit_price, subtotal, company_id, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,COALESCE($9::timestamptz,NOW()))`,
      [row.id, id, row.productId, row.productName, row.quantity, row.unitPrice,
        row.subtotal, companyId, row.createdAt],
    );
  }
}

export async function upsertOrder(
  client: PoolClient,
  companyId: string,
  id: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const customerId = stringValue(payload, "customer_id");
  if (!customerId) throw new Error("invalid_mutation");
  const rawOrderNumber = stringValue(payload, "order_number");
  const orderNumber = rawOrderNumber || `SYNC-${id}`;
  const items = Array.isArray(payload.items) ? payload.items : [];
  const discountAmount = numberValue(payload, "discount_amount", 0);

  await client.query(
    `INSERT INTO customers (id, company_id, name, status, is_deleted, created_at, updated_at)
     VALUES ($1, $2, $3, 'active', false, NOW(), NOW())
     ON CONFLICT (id) DO NOTHING`,
    [customerId, companyId, stringValue(payload, "customer_name") || `Müşteri (${customerId})`],
  );

  await client.query(
    `INSERT INTO customer_orders (id, company_id, order_number, customer_id, status, total_amount, discount_amount, order_date, expected_delivery_date, actual_delivery_date, notes, created_at, updated_at, is_deleted, created_by)
     VALUES ($1,$2,$3,$4,$5,$6,$7,COALESCE($8::timestamptz,NOW()),$9::timestamptz,$10::timestamptz,$11,COALESCE($12::timestamptz,NOW()),NOW(),false,$13)
     ON CONFLICT (id) DO UPDATE SET
       order_number = CASE 
         WHEN EXCLUDED.order_number NOT LIKE 'SYNC-%' AND EXCLUDED.order_number != '' THEN EXCLUDED.order_number
         WHEN customer_orders.order_number NOT LIKE 'SYNC-%' AND customer_orders.order_number != '' THEN customer_orders.order_number
         ELSE EXCLUDED.order_number
       END,
       customer_id=EXCLUDED.customer_id, status=EXCLUDED.status,
       total_amount=EXCLUDED.total_amount, discount_amount=EXCLUDED.discount_amount,
       expected_delivery_date=EXCLUDED.expected_delivery_date,
       actual_delivery_date=EXCLUDED.actual_delivery_date, notes=EXCLUDED.notes, is_deleted=false,
       updated_at=NOW() WHERE customer_orders.company_id=EXCLUDED.company_id`,
    [id, companyId, orderNumber, customerId, stringValue(payload, "status", "created"), numberValue(payload, "total_amount"),
      discountAmount,
      stringValue(payload, "order_date") || stringValue(payload, "created_at") || null,
      stringValue(payload, "expected_delivery_date") || null, stringValue(payload, "actual_delivery_date") || null,
      stringValue(payload, "notes") || null, stringValue(payload, "created_at") || null,
      stringValue(payload, "created_by") || null],
  );

  // Ensure all distinct products exist atomically to prevent foreign key errors without N+1 queries
  const distinctProducts = new Map<string, string>();
  for (const item of items) {
    if (!item || typeof item !== "object") continue;
    const row = item as Record<string, unknown>;
    const pId = stringValue(row, "product_id");
    if (pId && !distinctProducts.has(pId)) {
      distinctProducts.set(pId, stringValue(row, "product_name") || `Ürün (${pId})`);
    }
  }
  for (const [prodId, prodName] of distinctProducts.entries()) {
    await client.query(
      `INSERT INTO products (id, company_id, name, price, quantity, status, is_deleted, created_at, updated_at)
       VALUES ($1, $2, $3, 0, 0, 'active', false, NOW(), NOW())
       ON CONFLICT (id) DO NOTHING`,
      [prodId, companyId, prodName],
    );
  }

  await client.query("DELETE FROM customer_order_items WHERE order_id = $1 AND company_id = $2", [id, companyId]);
  for (let index = 0; index < items.length; index++) {
    const item = items[index];
    if (!item || typeof item !== "object") throw new Error("invalid_mutation");
    const row = item as Record<string, unknown>;
    const productId = stringValue(row, "product_id");
    if (!productId) throw new Error("invalid_mutation");

    await client.query(
      `INSERT INTO customer_order_items (id, order_id, product_id, product_name, quantity, unit_price, company_id, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,COALESCE($8::timestamptz,NOW()))`,
      [stringValue(row, "id", `sync-${id}-${index}`), id, productId,
        stringValue(row, "product_name") || null, numberValue(row, "quantity"),
        numberValue(row, "unit_price"), companyId, stringValue(row, "created_at") || null],
    );
  }
}

export async function upsertFinancialTransaction(
  client: PoolClient,
  companyId: string,
  id: string,
  payload: Record<string, unknown>,
): Promise<void> {
  const customerId = nullableId(stringValue(payload, "customer_id"));
  const type = stringValue(payload, "type");
  const amount = numberValue(payload, "amount", Number.NaN);
  const paidAmount = numberValue(payload, "paid_amount", Number.NaN);
  const debtAmount = numberValue(payload, "debt_amount", Number.NaN);
  const referenceId = nullableId(stringValue(payload, "reference_id"));
  const requiresCustomer = ["payment", "collection", "manual_debt"].includes(type);
  if (!["sale","payment","collection","manual_debt","cancellation","refund"].includes(type) ||
      (requiresCustomer && !customerId) ||
      !Number.isFinite(amount) || !Number.isFinite(paidAmount) || !Number.isFinite(debtAmount) ||
      amount < 0 || paidAmount < 0 || debtAmount < 0) throw new Error("invalid_financial_transaction");
  const description = stringValue(payload, "description") || stringValue(payload, "notes") || null;
  const metadata = typeof payload.metadata === "object" && payload.metadata !== null ? JSON.stringify(payload.metadata) : (stringValue(payload, "metadata") || null);
  const paymentMethod = stringValue(payload, "payment_method") || null;
  const rawMetadata = typeof payload.metadata === "object" && payload.metadata !== null ? payload.metadata : null;
  const isRevision = (rawMetadata && (rawMetadata as any).reason === "order_revision") ||
                     (typeof payload.metadata === "string" && payload.metadata.includes('"order_revision"'));
  const isDeleted = payload.is_deleted === 1 || payload.is_deleted === true;
  let effectiveDebtAmount = debtAmount;
  if (!Number.isFinite(effectiveDebtAmount) || effectiveDebtAmount < 0 || Math.abs(amount - paidAmount - effectiveDebtAmount) > 0.05) {
    effectiveDebtAmount = Math.max(0, Number((amount - paidAmount).toFixed(2)));
  }

  const prior = await client.query(
    `SELECT id, amount, paid_amount, debt_amount, customer_id, type, is_deleted FROM financial_transactions WHERE id=$1 AND company_id=$2 FOR UPDATE`, [id, companyId]);
  if (prior.rowCount) {
    const prev = prior.rows[0];
    if (isDeleted && !prev.is_deleted) {
      await client.query(
        `UPDATE financial_transactions SET is_deleted = true, deleted_at = NOW(), updated_at = NOW() WHERE id = $1 AND company_id = $2`,
        [id, companyId]
      );
    }
    return;
  }
  if (customerId) {
    const customer = await client.query(
      `SELECT id FROM customers WHERE id=$1 AND company_id=$2 AND is_deleted=false`, [customerId, companyId]);
    if (!customer.rowCount) throw new Error("invalid_customer");
  }

  if (type === "sale") {
    let sale = referenceId ? await client.query(
      `SELECT total_amount,paid_amount,customer_id FROM sales WHERE id=$1 AND company_id=$2 FOR UPDATE`,
      [referenceId, companyId]) : { rowCount: 0, rows: [] };
    if (!sale.rowCount && referenceId) {
      sale = await client.query(
        `SELECT total_amount, $3::numeric as paid_amount, customer_id FROM customer_orders WHERE id=$1 AND company_id=$2 FOR UPDATE`,
        [referenceId, companyId, paidAmount]);
    }
    const saleCustId = sale.rowCount && sale.rows[0].customer_id ? String(sale.rows[0].customer_id) : null;
    const hasCustomerMismatch = customerId && saleCustId && customerId !== saleCustId;
    if (hasCustomerMismatch) {
      logger.warn("Sale ledger customer mismatch detected, logging warning but retaining financial transaction", {
        transaction_id: id, customer_id: customerId, sale_customer_id: saleCustId
      });
    }
  } else if (type === "payment") {
    if (amount <= 0) {
      throw new Error("invalid_payment_transaction");
    }
    if (referenceId) {
      let sale = await client.query(
        `SELECT total_amount,paid_amount,customer_id FROM sales WHERE id=$1 AND company_id=$2 FOR UPDATE`,
        [referenceId, companyId]);
      const isOrder = !sale.rowCount;
      if (isOrder) {
        sale = await client.query(
          `SELECT total_amount, $3::numeric as paid_amount, customer_id FROM customer_orders WHERE id=$1 AND company_id=$2 FOR UPDATE`,
          [referenceId, companyId, amount]);
      }
      if (sale.rowCount && !isOrder) {
        const newPaid = Number(sale.rows[0].paid_amount) + amount;
        await client.query(
          `UPDATE sales SET paid_amount=$1,status=$2,updated_at=NOW() WHERE id=$3 AND company_id=$4`,
          [newPaid, newPaid >= Number(sale.rows[0].total_amount) - 0.01 ? 'completed' : 'partial', referenceId, companyId]);
      }
    }
  } else if (type === "collection" &&
      (amount <= 0 || Math.abs(amount-paidAmount)>0.01)) {
    throw new Error("invalid_collection_transaction");
  } else if (type === "manual_debt" &&
      (amount <= 0 || paidAmount !== 0 || Math.abs(amount-debtAmount)>0.01)) {
    throw new Error("invalid_manual_debt_transaction");
  } else if ((type === "cancellation" || type === "refund")) {
    if (!referenceId || amount <= 0 || paidAmount > amount || debtAmount > amount) {
      throw new Error(`invalid_${type}_transaction`);
    }
    let sale = await client.query(
      `SELECT customer_id,total_amount FROM sales WHERE id=$1 AND company_id=$2`,
      [referenceId, companyId]);
    if (!sale.rowCount) {
      sale = await client.query(
        `SELECT customer_id,total_amount FROM customer_orders WHERE id=$1 AND company_id=$2`,
        [referenceId, companyId]);
    }
    const saleCustId = sale.rowCount && sale.rows[0].customer_id ? String(sale.rows[0].customer_id) : null;
    const hasCustomerMismatch = customerId && saleCustId && customerId !== saleCustId;
    if (!sale.rowCount || hasCustomerMismatch ||
        (!isRevision && amount > Number(sale.rows[0].total_amount)+0.01)) {
      throw new Error(`${type}_sale_mismatch`);
    }
  }
  await client.query(
    `INSERT INTO financial_transactions (id, company_id, type, customer_id, amount, paid_amount, debt_amount, date, reference_id, logical_clock, device_id, description, metadata, payment_method, is_deleted, updated_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,COALESCE($8::timestamptz,NOW()),$9,$10,$11,$12,$13,$14,$15,NOW())
     ON CONFLICT (id) DO UPDATE SET
       is_deleted = EXCLUDED.is_deleted,
       deleted_at = CASE WHEN EXCLUDED.is_deleted THEN NOW() ELSE NULL END,
       customer_id = COALESCE(EXCLUDED.customer_id, financial_transactions.customer_id),
       description = COALESCE(EXCLUDED.description, financial_transactions.description),
       metadata = COALESCE(EXCLUDED.metadata, financial_transactions.metadata),
       payment_method = COALESCE(EXCLUDED.payment_method, financial_transactions.payment_method),
       updated_at = NOW()`,
    [id, companyId, type, customerId, amount,
      paidAmount, effectiveDebtAmount,
      stringValue(payload, "date") || stringValue(payload, "created_at") || null,
      referenceId, numberValue(payload, "logical_clock"),
      stringValue(payload, "device_id") || null, description, metadata, paymentMethod, isDeleted],
  );
}
