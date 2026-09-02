import { Router } from "express";
import { authenticateUser, requirePermission } from "../../middleware/auth.middleware";
import { pgPool } from "../../config/database";
import { syncLimiter } from "../../middleware/rate-limit.middleware";
import { requireActiveEntitlement } from "../../middleware/auth.middleware";
import { RealtimeBroadcastService } from "../realtime/broadcast.service";
import { logger } from "../../config/logger";
import type { PoolClient } from "pg";
import { RefundService } from "../order/refund.service";
import { randomUUID } from "crypto";

const router = Router();
const entityTypes = new Set([
  "product",
  "customer",
  "order",
  "sale",
  "financial_transaction",
  "refund",
]);
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const syncProtocolVersion = 6;
const requireDestructiveResetRole = (req: any, res: any, next: any) => {
  const roles = Array.isArray(req.user?.roles) ? req.user.roles : [];
  if (!roles.includes("owner") && !roles.includes("sysadmin")) {
    return res.status(403).json({
      error: "forbidden",
      message: "Bu işlem yalnızca işletme sahibi tarafından yapılabilir.",
    });
  }
  return next();
};

type SyncMutation = {
  entity_type: string;
  entity_id: string;
  operation: "UPSERT" | "DELETE";
  base_revision: number;
  payload: Record<string, unknown>;
};

const stringValue = (payload: Record<string, unknown>, key: string, fallback = "") =>
  typeof payload[key] === "string" ? payload[key].trim() : fallback;
const numberValue = (payload: Record<string, unknown>, key: string, fallback = 0) => {
  const value = Number(payload[key]);
  return Number.isFinite(value) ? value : fallback;
};
const nullableId = (value: string) => value.length ? value : null;

async function assertActiveSyncActivation(
  companyId: string,
  activationId: unknown,
  installationId: unknown,
  executor: Pick<PoolClient, "query"> = pgPool,
): Promise<void> {
  if (typeof installationId !== "string" || !installationId) {
    throw new Error("invalid_device_activation");
  }
  // activationId is optional for trial users who haven't completed license activation yet.
  if (typeof activationId === "string" && activationId) {
    const activation = await executor.query(
      `SELECT id FROM device_activations
       WHERE id = $1 AND company_id = $2 AND device_hash = $3 AND status = 'active'`,
      [activationId, companyId, installationId],
    );
    if (activation.rowCount === 0) throw new Error("invalid_device_activation");
  } else {
    const activation = await executor.query(
      `SELECT id FROM device_activations
       WHERE company_id = $1 AND device_hash = $2 AND status = 'active'
       LIMIT 1`,
      [companyId, installationId],
    );
    if (activation.rowCount === 0) throw new Error("invalid_device_activation");
  }
}

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
        throw new Error("immutable_financial_transaction");
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
        `INSERT INTO customers (id, company_id, name, email, phone, balance, credit_limit, status, is_deleted, created_at, updated_at)
         VALUES ($1,$2,$3,$4,$5,0,$6,$7,$8,COALESCE($9::timestamptz,NOW()),NOW())
         ON CONFLICT (id) DO UPDATE SET name=EXCLUDED.name, email=EXCLUDED.email, phone=EXCLUDED.phone,
           credit_limit=EXCLUDED.credit_limit, status=EXCLUDED.status,
           is_deleted=EXCLUDED.is_deleted, deleted_at=CASE WHEN EXCLUDED.is_deleted THEN NOW() ELSE NULL END,
           updated_at=NOW() WHERE customers.company_id=EXCLUDED.company_id`,
        [id, companyId, name, stringValue(payload, "email") || null, stringValue(payload, "phone") || null,
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

async function upsertSale(client: PoolClient, companyId: string, id: string, payload: Record<string, unknown>) {
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
  if (!Number.isFinite(clientTotal) || Math.abs(clientTotal - computedTotal) > 0.01 ||
      !Number.isFinite(paidAmount) || paidAmount < 0 || paidAmount > computedTotal) {
    throw new Error("sale_total_mismatch");
  }
  if ((paymentMethod === "credit" || paymentMethod === "veresiye" || paymentMethod === "debt") && paidAmount !== 0) {
    throw new Error("invalid_credit_payment");
  }
  if ((paymentMethod === "cash" || paymentMethod === "card") &&
      Math.abs(paidAmount-computedTotal)>0.01) {
    throw new Error("invalid_full_payment");
  }
  await client.query(
    `INSERT INTO sales (id, company_id, customer_id, total_amount, paid_amount, payment_method, status, fsm_state, idempotency_key, created_at, updated_at, is_deleted, created_by)
     VALUES ($1,$2,$3,$4,$5,$6,'completed','completed',$7,COALESCE($8::timestamptz,NOW()),NOW(),false,$9)`,
    [id, companyId, customerId, computedTotal, paidAmount, paymentMethod,
      stringValue(payload, "idempotency_key") || null, stringValue(payload, "created_at") || null,
      stringValue(payload, "created_by") || null],
  );
  for (const row of normalizedItems) {
    const stock = await client.query(
      `UPDATE products SET quantity = quantity - $1, updated_at = NOW()
       WHERE id = $2 AND company_id = $3 AND is_deleted = false AND quantity >= $1
       RETURNING id`,
      [row.quantity, row.productId, companyId],
    );
    if (!stock.rowCount) throw new Error("insufficient_stock");
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

async function upsertOrder(client: PoolClient, companyId: string, id: string, payload: Record<string, unknown>) {
  const customerId = stringValue(payload, "customer_id");
  if (!customerId) throw new Error("invalid_mutation");
  const orderNumber = stringValue(payload, "order_number", `SYNC-${id}`);
  const items = Array.isArray(payload.items) ? payload.items : [];
  await client.query(
    `INSERT INTO customer_orders (id, company_id, order_number, customer_id, status, total_amount, order_date, expected_delivery_date, actual_delivery_date, notes, created_at, updated_at, is_deleted, created_by)
     VALUES ($1,$2,$3,$4,$5,$6,COALESCE($7::timestamptz,NOW()),$8::timestamptz,$9::timestamptz,$10,COALESCE($11::timestamptz,NOW()),NOW(),false,$12)
     ON CONFLICT (id) DO UPDATE SET order_number=EXCLUDED.order_number,
       customer_id=EXCLUDED.customer_id, status=EXCLUDED.status,
       total_amount=EXCLUDED.total_amount, expected_delivery_date=EXCLUDED.expected_delivery_date,
       actual_delivery_date=EXCLUDED.actual_delivery_date, notes=EXCLUDED.notes, is_deleted=false,
       updated_at=NOW() WHERE customer_orders.company_id=EXCLUDED.company_id`,
    [id, companyId, orderNumber, customerId, stringValue(payload, "status", "created"), numberValue(payload, "total_amount"),
      stringValue(payload, "order_date") || stringValue(payload, "created_at") || null,
      stringValue(payload, "expected_delivery_date") || null, stringValue(payload, "actual_delivery_date") || null,
      stringValue(payload, "notes") || null, stringValue(payload, "created_at") || null,
      stringValue(payload, "created_by") || null],
  );
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

async function upsertFinancialTransaction(client: PoolClient, companyId: string, id: string, payload: Record<string, unknown>) {
  const customerId = nullableId(stringValue(payload, "customer_id"));
  const type = stringValue(payload, "type");
  const amount = numberValue(payload, "amount", Number.NaN);
  const paidAmount = numberValue(payload, "paid_amount", Number.NaN);
  const debtAmount = numberValue(payload, "debt_amount", Number.NaN);
  const referenceId = nullableId(stringValue(payload, "reference_id"));
  if (!["sale","payment","collection","manual_debt","cancellation","refund"].includes(type) || !customerId ||
      !Number.isFinite(amount) || !Number.isFinite(paidAmount) || !Number.isFinite(debtAmount) ||
      amount < 0 || paidAmount < 0 || debtAmount < 0) throw new Error("invalid_financial_transaction");
  const prior = await client.query(
    `SELECT id FROM financial_transactions WHERE id=$1 AND company_id=$2 FOR UPDATE`, [id, companyId]);
  if (prior.rowCount) return;
  const customer = await client.query(
    `SELECT id FROM customers WHERE id=$1 AND company_id=$2 AND is_deleted=false`, [customerId, companyId]);
  if (!customer.rowCount) throw new Error("invalid_customer");
  if (type === "sale") {
    let sale = await client.query(
      `SELECT total_amount,paid_amount,customer_id FROM sales WHERE id=$1 AND company_id=$2 FOR UPDATE`,
      [referenceId, companyId]);
    if (!sale.rowCount) {
      sale = await client.query(
        `SELECT total_amount, $3::numeric as paid_amount, customer_id FROM customer_orders WHERE id=$1 AND company_id=$2 FOR UPDATE`,
        [referenceId, companyId, paidAmount]);
    }
    // The canonical sale or order may already include later partial payments when an
    // older device uploads its initial ledger snapshot. Validate the immutable
    // original fact instead of requiring the current paid projection to match.
    if (!sale.rowCount || sale.rows[0].customer_id !== customerId ||
        Math.abs(Number(sale.rows[0].total_amount)-amount)>0.01 ||
        Number(sale.rows[0].paid_amount)+0.01 < paidAmount ||
        Math.abs(amount-paidAmount-debtAmount)>0.01) throw new Error("sale_ledger_mismatch");
  } else if (type === "payment") {
    if (!referenceId || amount <= 0 || Math.abs(amount-paidAmount)>0.01) {
      throw new Error("invalid_payment_transaction");
    }
    let sale = await client.query(
      `SELECT total_amount,paid_amount,customer_id FROM sales WHERE id=$1 AND company_id=$2 FOR UPDATE`,
      [referenceId, companyId]);
    const isOrder = !sale.rowCount;
    if (isOrder) {
      sale = await client.query(
        `SELECT total_amount, $3::numeric as paid_amount, customer_id FROM customer_orders WHERE id=$1 AND company_id=$2 FOR UPDATE`,
        [referenceId, companyId, amount]);
    }
    if (!sale.rowCount || sale.rows[0].customer_id !== customerId) {
      throw new Error("payment_exceeds_sale");
    }
    if (!isOrder) {
      if (Number(sale.rows[0].paid_amount)+amount > Number(sale.rows[0].total_amount)+0.01) {
        throw new Error("payment_exceeds_sale");
      }
      const newPaid = Number(sale.rows[0].paid_amount)+amount;
      await client.query(
        `UPDATE sales SET paid_amount=$1,status=$2,updated_at=NOW() WHERE id=$3 AND company_id=$4`,
        [newPaid, newPaid >= Number(sale.rows[0].total_amount)-0.01 ? 'completed' : 'partial', referenceId, companyId]);
    }
  } else if (type === "collection" &&
      (amount <= 0 || Math.abs(amount-paidAmount)>0.01 || referenceId)) {
    throw new Error("invalid_collection_transaction");
  } else if (type === "manual_debt" &&
      (amount <= 0 || paidAmount !== 0 || Math.abs(amount-debtAmount)>0.01 || referenceId)) {
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
    if (!sale.rowCount || sale.rows[0].customer_id !== customerId ||
        amount > Number(sale.rows[0].total_amount)+0.01) {
      throw new Error(`${type}_sale_mismatch`);
    }
  }
  const description = stringValue(payload, "description") || stringValue(payload, "notes") || null;
  const metadata = typeof payload.metadata === "object" && payload.metadata !== null ? JSON.stringify(payload.metadata) : (stringValue(payload, "metadata") || null);
  const paymentMethod = stringValue(payload, "payment_method") || null;
  await client.query(
    `INSERT INTO financial_transactions (id, company_id, type, customer_id, amount, paid_amount, debt_amount, date, reference_id, logical_clock, device_id, description, metadata, payment_method, is_deleted, updated_at)
     VALUES ($1,$2,$3,$4,$5,$6,$7,COALESCE($8::timestamptz,NOW()),$9,$10,$11,$12,$13,$14,false,NOW())
     ON CONFLICT (id) DO UPDATE SET
       description = COALESCE(EXCLUDED.description, financial_transactions.description),
       metadata = COALESCE(EXCLUDED.metadata, financial_transactions.metadata),
       payment_method = COALESCE(EXCLUDED.payment_method, financial_transactions.payment_method)`,
    [id, companyId, type, customerId, amount,
      paidAmount, debtAmount,
      stringValue(payload, "date") || stringValue(payload, "created_at") || null,
      referenceId, numberValue(payload, "logical_clock"),
      stringValue(payload, "device_id") || null, description, metadata, paymentMethod],
  );
}

router.use(authenticateUser as any);
router.use(requireActiveEntitlement as any);
router.use((req, res, next) => {
  if (req.header("x-sync-protocol-version") !== String(syncProtocolVersion)) {
    return res.status(426).json({
      error: "sync_protocol_upgrade_required",
      required_version: syncProtocolVersion,
      message: "Senkronizasyon protokolü güncel değil. Lütfen uygulamayı güncelleyin.",
    });
  }
  next();
});
router.use(syncLimiter);

router.post("/device-hardware-profile/restore", async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const result = await client.query(
      `SELECT profile, updated_at FROM device_hardware_profiles
       WHERE device_activation_id = $1 AND company_id = $2`,
      [activationId, user.company_id],
    );
    await client.query("COMMIT");
    return res.json({
      profile: result.rows[0]?.profile ?? [],
      updated_at: result.rows[0]?.updated_at ?? null,
    });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "profile_restore_failed";
    return res.status(message === "invalid_device_activation" ? 403 : 500)
      .json({ error: message });
  } finally {
    client.release();
  }
});

router.put("/device-hardware-profile", async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const profile = req.body?.profile;
  if (!Array.isArray(profile) || profile.length > 20) {
    return res.status(400).json({ error: "invalid_hardware_profile" });
  }
  const encoded = JSON.stringify(profile);
  if (encoded.length > 64_000 || /password|secret|api[_-]?key|pin/i.test(encoded)) {
    return res.status(400).json({ error: "unsafe_hardware_profile" });
  }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    await client.query(
      `INSERT INTO device_hardware_profiles
         (device_activation_id, company_id, profile, updated_at)
       VALUES ($1, $2, $3::jsonb, NOW())
       ON CONFLICT (device_activation_id) DO UPDATE
       SET profile = EXCLUDED.profile, updated_at = NOW()
       WHERE device_hardware_profiles.company_id = EXCLUDED.company_id`,
      [activationId, user.company_id, encoded],
    );
    await client.query("COMMIT");
    return res.json({ success: true });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "profile_save_failed";
    return res.status(message === "invalid_device_activation" ? 403 : 500)
      .json({ error: message });
  } finally {
    client.release();
  }
});

const sharedHardwareTypes = new Set([
  "receiptPrinter", "labelPrinter", "scale", "paymentTerminal",
  "barcodeScanner", "customerDisplay",
]);
const sharedPrintOperations = new Set([
  "printReceipt", "printProductLabel", "printOrderLabel", "testPrint",
]);

const requireSharedHardwareEnabled = async (_req: any, res: any, next: any) => {
  try {
    const result = await pgPool.query(
      `SELECT COALESCE((value->>'shared_hardware_enabled')::boolean,true) AS enabled
       FROM remote_configs WHERE key='global_config' LIMIT 1`,
    );
    if (result.rows[0]?.enabled === false) {
      return res.status(503).json({ error: "shared_hardware_temporarily_disabled" });
    }
    next();
  } catch (error) {
    next(error);
  }
};

router.use("/shared-hardware", requireSharedHardwareEnabled);
router.use("/hardware-jobs", requireSharedHardwareEnabled);

function safeHardwareObject(value: unknown): Record<string, unknown> {
  if (!value || typeof value !== "object" || Array.isArray(value)) return {};
  const source = value as Record<string, unknown>;
  const result: Record<string, unknown> = {};
  for (const [key, item] of Object.entries(source)) {
    if (/password|secret|api[_-]?key|pin|token/i.test(key)) continue;
    if (["string", "number", "boolean"].includes(typeof item) || item === null) {
      result[key] = item;
    }
  }
  return result;
}

// Registers only hardware physically owned by this activated installation.
// The cloud id is namespaced so legacy local ids cannot collide across tenants.
router.put("/shared-hardware/presence", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const hardware = req.body?.hardware;
  if (!Array.isArray(hardware) || hardware.length > 50) {
    return res.status(400).json({ error: "invalid_shared_hardware" });
  }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const retainedIds: string[] = [];
    for (const raw of hardware) {
      if (!raw || typeof raw !== "object") throw new Error("invalid_shared_hardware");
      const item = raw as Record<string, unknown>;
      const localId = stringValue(item, "id");
      const name = stringValue(item, "name");
      const hardwareType = stringValue(item, "type");
      const connectionType = stringValue(item, "connection_type");
      if (!localId || localId.length > 180 || !name || name.length > 160 ||
          !sharedHardwareTypes.has(hardwareType) || !connectionType) {
        throw new Error("invalid_shared_hardware");
      }
      const cloudId = `${activationId}:${localId}`;
      retainedIds.push(cloudId);
      const configuration = safeHardwareObject(item.configuration);
      const capabilities = safeHardwareObject(item.capabilities);
      await client.query(
        `INSERT INTO shared_hardware
          (id,company_id,owner_activation_id,owner_device_id,name,hardware_type,
           connection_type,language,configuration,capabilities,sharing_scope,enabled,online,last_seen_at,updated_at)
         VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9::jsonb,$10::jsonb,$11,$12,true,NOW(),NOW())
         ON CONFLICT(id) DO UPDATE SET name=EXCLUDED.name, hardware_type=EXCLUDED.hardware_type,
           connection_type=EXCLUDED.connection_type, language=EXCLUDED.language,
           configuration=EXCLUDED.configuration, capabilities=EXCLUDED.capabilities,
           sharing_scope=EXCLUDED.sharing_scope, enabled=EXCLUDED.enabled,
           online=true,last_seen_at=NOW(),updated_at=NOW()
         WHERE shared_hardware.company_id=EXCLUDED.company_id
           AND shared_hardware.owner_activation_id=EXCLUDED.owner_activation_id`,
        [cloudId,user.company_id,activationId,deviceId,name,hardwareType,connectionType,
          stringValue(item,"language") || null,JSON.stringify(configuration),JSON.stringify(capabilities),
          ["owner","branch","company"].includes(stringValue(item,"sharing_scope"))
            ? stringValue(item,"sharing_scope") : "company",
          item.enabled !== false],
      );
    }
    await client.query(
      `UPDATE shared_hardware SET online=false,updated_at=NOW()
       WHERE company_id=$1 AND owner_activation_id=$2
         AND NOT (id = ANY($3::text[]))`,
      [user.company_id, activationId, retainedIds],
    );
    await client.query("COMMIT");
    return res.json({ success: true, registered: retainedIds.length });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "shared_hardware_presence_failed";
    return res.status(message === "invalid_device_activation" ? 403 : message === "invalid_shared_hardware" ? 400 : 500)
      .json({ error: message });
  } finally { client.release(); }
});

router.post("/shared-hardware/list", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const result = await client.query(
      `SELECT h.id,h.name,h.hardware_type AS type,h.connection_type,h.language,h.capabilities,
              h.sharing_scope,h.enabled,
              (h.online=true AND a.status='active' AND
               a.last_seen_at > NOW()-INTERVAL '5 minutes') AS online,
              COALESCE(a.last_seen_at,h.last_seen_at) AS last_seen_at,
              h.owner_activation_id,h.owner_device_id,(h.owner_activation_id=$2) AS is_local
       FROM shared_hardware h
       JOIN device_activations a ON a.id=h.owner_activation_id AND a.company_id=h.company_id
       WHERE h.company_id=$1 AND h.enabled=true
         AND (h.sharing_scope='company' OR h.owner_activation_id=$2)
       ORDER BY online DESC,h.name ASC`,
      [user.company_id, activationId],
    );
    await client.query("COMMIT");
    return res.json({ hardware: result.rows });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "shared_hardware_list_failed";
    return res.status(message === "invalid_device_activation" ? 403 : 500).json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const hardwareId = req.body?.hardware_id;
  const operation = req.body?.operation;
  const payload = req.body?.payload;
  const idempotencyKey = req.header("idempotency-key") || req.body?.idempotency_key;
  const encodedPayload = JSON.stringify(payload ?? null);
  if (typeof hardwareId !== "string" || typeof operation !== "string" ||
      !sharedPrintOperations.has(operation) || typeof idempotencyKey !== "string" ||
      !payload || typeof payload !== "object" || encodedPayload.length > 512_000) {
    return res.status(400).json({ error: "invalid_hardware_job" });
  }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const target = await client.query(
      `SELECT owner_activation_id,hardware_type,enabled,sharing_scope FROM shared_hardware
       WHERE id=$1 AND company_id=$2 FOR SHARE`, [hardwareId,user.company_id]);
    if (!target.rowCount || !target.rows[0].enabled || target.rows[0].sharing_scope === "owner") {
      throw new Error("hardware_not_available");
    }
    const expectedType = operation === "printReceipt" ? "receiptPrinter" : "labelPrinter";
    if (operation !== "testPrint" && target.rows[0].hardware_type !== expectedType) {
      throw new Error("hardware_incompatible");
    }
    const result = await client.query(
      `INSERT INTO hardware_jobs
        (id,company_id,hardware_id,owner_activation_id,requested_by_activation_id,
         requested_by_user_id,operation,payload,idempotency_key)
       VALUES(gen_random_uuid(),$1,$2,$3,$4,$5,$6,$7::jsonb,$8)
       ON CONFLICT(company_id,idempotency_key) DO UPDATE SET updated_at=hardware_jobs.updated_at
       RETURNING id,state,created_at`,
      [user.company_id,hardwareId,target.rows[0].owner_activation_id,activationId,user.id,
        operation,encodedPayload,idempotencyKey.substring(0,180)],
    );
    await client.query("COMMIT");
    return res.status(202).json({ job: result.rows[0] });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_create_failed";
    const status = message === "invalid_device_activation" ? 403 :
      ["hardware_not_available","hardware_incompatible"].includes(message) ? 409 : 500;
    return res.status(status).json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs/claim", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    await client.query(
      `UPDATE hardware_jobs SET state='requires_confirmation',lease_owner=NULL,
         lease_expires_at=NULL,error_code='owner_interrupted_during_delivery',
         error_message='Sahip cihaz yazdırma sırasında kapandı; çift baskıyı önlemek için otomatik tekrar durduruldu.',
         updated_at=NOW(),completed_at=NOW()
       WHERE company_id=$1 AND owner_activation_id=$2 AND state='executing'
         AND lease_expires_at<NOW()`,
      [user.company_id, activationId],
    );
    const result = await client.query(
      `WITH candidate AS (
         SELECT id FROM hardware_jobs
         WHERE company_id=$1 AND owner_activation_id=$2
           AND (state='queued' OR (state='retry_wait' AND next_attempt_at<=NOW())
                OR (state='claimed' AND lease_expires_at<NOW()))
           AND attempt_count<5
         ORDER BY created_at ASC FOR UPDATE SKIP LOCKED LIMIT 1
       )
       UPDATE hardware_jobs j SET state='claimed',attempt_count=attempt_count+1,
         lease_owner=$3,lease_expires_at=NOW()+INTERVAL '45 seconds',updated_at=NOW()
       FROM candidate WHERE j.id=candidate.id
       RETURNING j.id,j.hardware_id,j.operation,j.payload,j.attempt_count,j.lease_expires_at`,
      [user.company_id,activationId,deviceId],
    );
    await client.query("COMMIT");
    return res.json({ job: result.rows[0] ?? null });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_claim_failed";
    return res.status(message === "invalid_device_activation" ? 403 : 500).json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs/:id/start", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const result = await client.query(
      `UPDATE hardware_jobs SET state='executing',updated_at=NOW(),
         lease_expires_at=NOW()+INTERVAL '45 seconds'
       WHERE id=$1 AND company_id=$2 AND owner_activation_id=$3
         AND lease_owner=$4 AND state='claimed' AND lease_expires_at>NOW()
       RETURNING id,state`,
      [req.params.id,user.company_id,activationId,deviceId],
    );
    if (!result.rowCount) throw new Error("hardware_job_lease_lost");
    await client.query("COMMIT");
    return res.json({ job: result.rows[0] });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_start_failed";
    return res.status(message === "invalid_device_activation" ? 403 : message === "hardware_job_lease_lost" ? 409 : 500)
      .json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs/list", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const result = await client.query(
      `SELECT j.id,j.hardware_id,h.name AS hardware_name,j.operation,j.state,
              j.attempt_count,j.error_code,j.error_message,j.created_at,j.updated_at,
              j.completed_at,(j.requested_by_activation_id=$2) AS requested_here,
              (j.owner_activation_id=$2) AS executed_here
       FROM hardware_jobs j JOIN shared_hardware h ON h.id=j.hardware_id
       WHERE j.company_id=$1 AND
         (j.requested_by_activation_id=$2 OR j.owner_activation_id=$2)
       ORDER BY j.created_at DESC LIMIT 200`,
      [user.company_id, activationId],
    );
    await client.query("COMMIT");
    return res.json({ jobs: result.rows });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_list_failed";
    return res.status(message === "invalid_device_activation" ? 403 : 500).json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs/:id/action", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const action = req.body?.action;
  if (!["retry","cancel","confirmPrinted","confirmNotPrinted"].includes(action)) {
    return res.status(400).json({ error: "invalid_hardware_job_action" });
  }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const current = await client.query(
      `SELECT state FROM hardware_jobs WHERE id=$1 AND company_id=$2
         AND (requested_by_activation_id=$3 OR owner_activation_id=$3) FOR UPDATE`,
      [req.params.id,user.company_id,activationId],
    );
    if (!current.rowCount) throw new Error("hardware_job_not_found");
    const state = current.rows[0].state as string;
    let nextState: string;
    if (action === "retry" && ["failed"].includes(state)) nextState = "queued";
    else if (action === "cancel" && ["queued","retry_wait","failed"].includes(state)) nextState = "cancelled";
    else if (action === "confirmPrinted" && state === "requires_confirmation") nextState = "succeeded";
    else if (action === "confirmNotPrinted" && state === "requires_confirmation") nextState = "queued";
    else throw new Error("invalid_hardware_job_transition");
    const result = await client.query(
      `UPDATE hardware_jobs SET state=$1::varchar,attempt_count=CASE WHEN $1::varchar='queued' THEN 0 ELSE attempt_count END,
         lease_owner=NULL,lease_expires_at=NULL,next_attempt_at=NULL,
         error_code=NULL,error_message=NULL,updated_at=NOW(),
         completed_at=CASE WHEN $1::varchar IN ('succeeded','cancelled') THEN NOW() ELSE NULL END
       WHERE id=$2 AND company_id=$3 RETURNING id,state`,
      [nextState,req.params.id,user.company_id],
    );
    await client.query("COMMIT");
    return res.json({ job: result.rows[0] });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_action_failed";
    const status = message === "invalid_device_activation" ? 403 :
      message === "hardware_job_not_found" ? 404 :
      message === "invalid_hardware_job_transition" ? 409 : 500;
    return res.status(status).json({ error: message });
  } finally { client.release(); }
});

router.post("/hardware-jobs/:id/result", requirePermission("settings:printer") as any, async (req, res) => {
  const user = (req as any).user;
  const activationId = req.body?.device_activation_id;
  const deviceId = req.body?.device_id;
  const state = req.body?.state;
  if (!["succeeded","failed","requires_confirmation","retry_wait"].includes(state)) {
    return res.status(400).json({ error: "invalid_hardware_job_result" });
  }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
    const result = await client.query(
      `UPDATE hardware_jobs SET state=$1::varchar,result=$2::jsonb,error_code=$3,error_message=$4,
         next_attempt_at=CASE WHEN $1::varchar='retry_wait' THEN NOW()+INTERVAL '10 seconds' ELSE NULL END,
         lease_owner=NULL,lease_expires_at=NULL,updated_at=NOW(),
         completed_at=CASE WHEN $1::varchar IN ('succeeded','failed','requires_confirmation') THEN NOW() ELSE NULL END
       WHERE id=$5 AND company_id=$6 AND owner_activation_id=$7 AND lease_owner=$8
       RETURNING id,state`,
      [state,JSON.stringify(req.body?.result ?? {}),req.body?.error_code ?? null,
        String(req.body?.error_message ?? "").substring(0,500) || null,req.params.id,
        user.company_id,activationId,deviceId],
    );
    if (!result.rowCount) throw new Error("hardware_job_lease_lost");
    await client.query("COMMIT");
    return res.json({ job: result.rows[0] });
  } catch (error) {
    await client.query("ROLLBACK").catch(() => undefined);
    const message = error instanceof Error ? error.message : "hardware_job_result_failed";
    return res.status(message === "invalid_device_activation" ? 403 : message === "hardware_job_lease_lost" ? 409 : 500)
      .json({ error: message });
  } finally { client.release(); }
});

router.post(
  "/catalog-reset",
  requirePermission("settings:recovery") as any,
  requireDestructiveResetRole as any,
  async (req, res) => {
    const user = (req as any).user;
    const activationId = req.header("x-device-activation-id") || req.body?.device_activation_id;
    const deviceId = req.header("x-device-id") || req.body?.device_id;
    const client = await pgPool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
      await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtext($1), hashtext('operational-reset'))",
        [user.company_id],
      );
      const countResult = await client.query(
        "SELECT COUNT(*) AS products FROM products WHERE company_id=$1 AND is_deleted=false",
        [user.company_id],
      );
      await client.query(
        `UPDATE products SET is_deleted=true,status='inactive',deleted_at=COALESCE(deleted_at,NOW()),updated_at=NOW()
          WHERE company_id=$1`,
        [user.company_id],
      );
      await client.query(
        "DELETE FROM sync_v4_entities WHERE tenant_id=$1 AND entity_type='product'",
        [user.company_id],
      );
      await client.query(
        "DELETE FROM sync_v4_conflicts WHERE tenant_id=$1 AND entity_type='product'",
        [user.company_id],
      );

      const mutationId = randomUUID();
      const payload = { scope: "catalog", counts: countResult.rows[0] };
      const resetChange = await client.query(
        `INSERT INTO sync_v4_changes
          (tenant_id,mutation_id,device_id,device_activation_id,entity_type,entity_id,operation,payload)
         VALUES ($1,$2::uuid,$3,$4,'system_reset',$5,'UPSERT',$6::jsonb)
         RETURNING revision`,
        [user.company_id, mutationId, deviceId, activationId,
          `catalog-${mutationId}`, JSON.stringify(payload)],
      );
      const resetRevision = Number(resetChange.rows[0].revision);
      await client.query(
        `INSERT INTO audit_logs
          (id,company_id,user_id,action,entity,entity_id,new_value,ip_address)
         VALUES ($1,$2,$3,'PRODUCT_CATALOG_RESET','product_catalog',$4,$5,$6)`,
        [`aud-${randomUUID()}`, user.company_id, user.id, String(resetRevision),
          JSON.stringify(payload), req.ip ?? null],
      );
      await client.query("COMMIT");
      await RealtimeBroadcastService.publishEvent(
        user.company_id,
        "ProductCatalogReset",
        { reset_revision: resetRevision },
        req.headers["x-correlation-id"] as string | undefined,
      );
      return res.json({ success: true, reset_revision: resetRevision, counts: countResult.rows[0] });
    } catch (error: any) {
      await client.query("ROLLBACK").catch(() => undefined);
      logger.error("Product catalog reset failed", {
        error: error?.message || "catalog_reset_failed",
        company_id: user.company_id,
        user_id: user.id,
      });
      const status = error?.message === "invalid_device_activation" ? 403 : 500;
      return res.status(status).json({ error: error?.message || "catalog_reset_failed" });
    } finally {
      client.release();
    }
  },
);

router.post(
  "/operational-reset",
  requirePermission("settings:recovery") as any,
  requireDestructiveResetRole as any,
  async (req, res) => {
    const user = (req as any).user;
    const activationId = req.header("x-device-activation-id") || req.body?.device_activation_id;
    const deviceId = req.header("x-device-id") || req.body?.device_id;
    const client = await pgPool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
      await assertActiveSyncActivation(user.company_id, activationId, deviceId, client);
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtext($1), hashtext('operational-reset'))",
        [user.company_id],
      );

      const counts = await client.query(
        `SELECT
          (SELECT COUNT(*) FROM products WHERE company_id=$1) AS products,
          (SELECT COUNT(*) FROM customers WHERE company_id=$1) AS customers,
          (SELECT COUNT(*) FROM sales WHERE company_id=$1) AS sales,
          (SELECT COUNT(*) FROM customer_orders WHERE company_id=$1) AS orders,
          (SELECT COUNT(*) FROM financial_transactions WHERE company_id=$1) AS financial_transactions`,
        [user.company_id],
      );

      // Reverse dependency order. This is the explicitly authorized tenant
      // reset path; ordinary Sync V4 mutations remain immutable.
      await client.query(
        `DELETE FROM refund_items ri USING refunds r
          WHERE ri.refund_id=r.id AND r.company_id=$1`,
        [user.company_id],
      );
      await client.query("DELETE FROM inventory_movements WHERE company_id=$1", [user.company_id]);
      await client.query("DELETE FROM refunds WHERE company_id=$1", [user.company_id]);
      await client.query("DELETE FROM sale_items WHERE company_id=$1", [user.company_id]);
      await client.query("DELETE FROM financial_transactions WHERE company_id=$1", [user.company_id]);
      await client.query("DELETE FROM sales WHERE company_id=$1", [user.company_id]);
      await client.query("DELETE FROM customer_order_items WHERE company_id=$1", [user.company_id]);
      await client.query("DELETE FROM customer_orders WHERE company_id=$1", [user.company_id]);
      await client.query("DELETE FROM products WHERE company_id=$1", [user.company_id]);
      await client.query("DELETE FROM customers WHERE company_id=$1", [user.company_id]);
      await client.query(
        `DELETE FROM sync_v4_entities WHERE tenant_id=$1
          AND entity_type IN ('product','customer','order','sale','financial_transaction','refund')`,
        [user.company_id],
      );
      await client.query("DELETE FROM sync_v4_conflicts WHERE tenant_id=$1", [user.company_id]);

      const mutationId = randomUUID();
      const payload = { scope: "operational", counts: counts.rows[0] };
      const resetChange = await client.query(
        `INSERT INTO sync_v4_changes
          (tenant_id,mutation_id,device_id,device_activation_id,entity_type,entity_id,operation,payload)
         VALUES ($1,$2::uuid,$3,$4,'system_reset',$5,'UPSERT',$6::jsonb)
         RETURNING revision`,
        [user.company_id, mutationId, deviceId, activationId,
          `operational-${mutationId}`, JSON.stringify(payload)],
      );
      const resetRevision = Number(resetChange.rows[0].revision);
      await client.query(
        `INSERT INTO audit_logs
          (id,company_id,user_id,action,entity,entity_id,new_value,ip_address)
         VALUES ($1,$2,$3,'OPERATIONAL_DATA_RESET','database',$4,$5,$6)`,
        [`aud-${randomUUID()}`, user.company_id, user.id, String(resetRevision),
          JSON.stringify(payload), req.ip ?? null],
      );
      await client.query("COMMIT");
      await RealtimeBroadcastService.publishEvent(
        user.company_id,
        "OperationalDataReset",
        { reset_revision: resetRevision },
        req.headers["x-correlation-id"] as string | undefined,
      );
      return res.json({ success: true, reset_revision: resetRevision, counts: counts.rows[0] });
    } catch (error: any) {
      await client.query("ROLLBACK").catch(() => undefined);
      logger.error("Operational reset failed", {
        error: error?.message || "operational_reset_failed",
        company_id: user.company_id,
        user_id: user.id,
      });
      const status = error?.message === "invalid_device_activation" ? 403 : 500;
      return res.status(status).json({ error: error?.message || "operational_reset_failed" });
    } finally {
      client.release();
    }
  },
);

router.post("/push", async (req, res) => {
  const user = (req as any).user;
  const deviceActivationId = req.header("x-device-activation-id") || req.body?.device_activation_id;
  const deviceInstallationId = req.header("x-device-id") || req.body?.device_id;
  const mutations = req.body?.mutations;
  if (!deviceActivationId || !deviceInstallationId || !Array.isArray(mutations) || mutations.length > 100) {
    return res.status(400).json({ error: "invalid_sync_request" });
  }

  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      "SELECT set_config('app.current_company_id', $1, true)",
      [user.company_id],
    );
    const activation = await client.query(
      `SELECT id FROM device_activations
       WHERE id = $1 AND company_id = $2 AND device_hash = $3 AND status = 'active'
       FOR UPDATE`,
      [deviceActivationId, user.company_id, deviceInstallationId],
    );
    if (activation.rowCount === 0) {
      throw new Error("invalid_device_activation");
    }
    // Serialize ordinary pushes with the destructive reset transaction. A
    // mutation can therefore be wholly before or wholly after the reset
    // barrier, never interleaved with its deletes.
    await client.query(
      "SELECT pg_advisory_xact_lock(hashtext($1), hashtext('operational-reset'))",
      [user.company_id],
    );
    await client.query(
      "UPDATE device_activations SET last_seen_at = NOW(), updated_at = NOW() WHERE id = $1",
      [deviceActivationId],
    );
    const results = [] as Array<{ mutation_id: string; revision: number }>;
    const conflicts: Array<{ mutation_id: string; entity_type: string; entity_id: string; server_revision: number }> = [];
    const rejected: Array<{ mutation_id: string | null; error: string }> = [];
    const notifications: Array<{
      type: string;
      entityId: string;
      revision: number;
    }> = [];
    const resetBarrierResult = await client.query(
      `SELECT
         COALESCE(MAX(revision) FILTER (WHERE payload->>'scope'='operational'),0) AS operational_revision,
         COALESCE(MAX(revision) FILTER (WHERE payload->>'scope'='catalog'),0) AS catalog_revision
       FROM sync_v4_changes
       WHERE tenant_id=$1 AND entity_type='system_reset'`,
      [user.company_id],
    );
    const operationalResetRevision = Number(resetBarrierResult.rows[0].operational_revision);
    const catalogResetRevision = Number(resetBarrierResult.rows[0].catalog_revision);
    for (const mutation of mutations) {
      await client.query("SAVEPOINT sync_mutation");
      try {
      if (
        !mutation ||
        typeof mutation.mutation_id !== "string" ||
        !uuidPattern.test(mutation.mutation_id) ||
        !entityTypes.has(mutation.entity_type) ||
        typeof mutation.entity_id !== "string" ||
        !["UPSERT", "DELETE"].includes(mutation.operation) ||
        !Number.isSafeInteger(mutation.base_revision) || mutation.base_revision < 0 ||
        typeof mutation.payload !== "object" ||
        mutation.payload === null ||
        mutation.entity_id.length > 128 ||
        JSON.stringify(mutation.payload).length > 256 * 1024
      ) {
        throw new Error("invalid_mutation");
      }
      const resetBarrierRevision = mutation.entity_type === "product"
        ? Math.max(operationalResetRevision, catalogResetRevision)
        : operationalResetRevision;
      if (mutation.base_revision < resetBarrierRevision) {
        throw new Error("stale_before_operational_reset");
      }
      const prior = await client.query(
        "SELECT revision FROM sync_v4_changes WHERE tenant_id = $1 AND mutation_id = $2::uuid",
        [user.company_id, mutation.mutation_id],
      );
      if (prior.rowCount) {
        results.push({
          mutation_id: mutation.mutation_id,
          revision: Number(prior.rows[0].revision),
        });
        continue;
      }
      // Serialize changes for one aggregate. A durable tombstone prevents a
      // delayed offline update from resurrecting an entity another device deleted.
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtext($1), hashtext($2))",
        [user.company_id, `${mutation.entity_type}:${mutation.entity_id}`],
      );
      const entity = await client.query(
        `SELECT is_deleted, updated_revision FROM sync_v4_entities
          WHERE tenant_id = $1 AND entity_type = $2 AND entity_id = $3 FOR UPDATE`,
        [user.company_id, mutation.entity_type, mutation.entity_id],
      );
      const currentRevision = Number(entity.rows[0]?.updated_revision ?? 0);
      if (currentRevision > mutation.base_revision) {
        const source = await client.query(
          `SELECT device_id FROM sync_v4_changes
           WHERE tenant_id = $1 AND revision = $2 LIMIT 1`,
          [user.company_id, currentRevision],
        );
        // Multiple queued edits from one device are causally ordered by the
        // outbox. A different device editing after this mutation's base cursor
        // is a true concurrent write and must never be silently overwritten.
        if (source.rows[0]?.device_id !== deviceInstallationId) {
          await client.query(
            `INSERT INTO sync_v4_conflicts
             (tenant_id, mutation_id, entity_type, entity_id, base_revision, server_revision, device_id, payload)
             VALUES ($1,$2::uuid,$3,$4,$5,$6,$7,$8::jsonb)
             ON CONFLICT (tenant_id, mutation_id) DO NOTHING`,
            [user.company_id, mutation.mutation_id, mutation.entity_type,
              mutation.entity_id, mutation.base_revision, currentRevision,
              deviceInstallationId, JSON.stringify(mutation.payload)],
          );
          conflicts.push({ mutation_id: mutation.mutation_id, entity_type: mutation.entity_type,
            entity_id: mutation.entity_id, server_revision: currentRevision });
          continue;
        }
      }
      const explicitlyReactivatesDeletedProduct =
        mutation.entity_type === "product" &&
        mutation.operation === "UPSERT" &&
        mutation.payload.reactivate_deleted === true &&
        mutation.payload.is_deleted !== true &&
        mutation.payload.is_deleted !== 1;
      const effectiveOperation =
        entity.rows[0]?.is_deleted === true && !explicitlyReactivatesDeletedProduct
          ? "DELETE"
          : mutation.operation;
      const domainMutation: SyncMutation = {
        entity_type: mutation.entity_type,
        entity_id: mutation.entity_id,
        operation: effectiveOperation,
        payload: mutation.payload,
        base_revision: mutation.base_revision,
      };
      // The domain write and the durable replication record are atomic. Never
      // acknowledge a mutation that cannot be materialized for another device.
      await applyDomainMutation(client, user.company_id, domainMutation, user.id);
      const inserted = await client.query(
        `INSERT INTO sync_v4_changes (tenant_id, mutation_id, device_id, device_activation_id, entity_type, entity_id, operation, payload)
         VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8::jsonb)
         ON CONFLICT (tenant_id, mutation_id) DO NOTHING
         RETURNING revision`,
        [
          user.company_id,
          mutation.mutation_id,
          deviceInstallationId,
          deviceActivationId,
          mutation.entity_type,
          mutation.entity_id,
          effectiveOperation,
          JSON.stringify(mutation.payload),
        ],
      );
      if (inserted.rowCount) {
        const revision = Number(inserted.rows[0].revision);
        await client.query(
          `INSERT INTO sync_v4_entities
             (tenant_id, entity_type, entity_id, is_deleted, payload, updated_revision)
           VALUES ($1, $2, $3, $4, $5::jsonb, $6)
           ON CONFLICT (tenant_id, entity_type, entity_id) DO UPDATE SET
             is_deleted = EXCLUDED.is_deleted, payload = EXCLUDED.payload,
             updated_revision = EXCLUDED.updated_revision, updated_at = CURRENT_TIMESTAMP`,
          [
            user.company_id,
            mutation.entity_type,
            mutation.entity_id,
            effectiveOperation === "DELETE",
            JSON.stringify(mutation.payload),
            revision,
          ],
        );
        results.push({ mutation_id: mutation.mutation_id, revision });
        notifications.push({
          type:
            mutation.entity_type === "product"
              ? "InventoryUpdated"
              : mutation.entity_type === "customer" ||
                  mutation.entity_type === "financial_transaction"
                ? "CustomerUpdated"
                : "OrderUpdated",
          entityId: mutation.entity_id,
          revision,
        });
      } else {
        const previous = await client.query(
          "SELECT revision FROM sync_v4_changes WHERE tenant_id = $1 AND mutation_id = $2::uuid",
          [user.company_id, mutation.mutation_id],
        );
        results.push({
          mutation_id: mutation.mutation_id,
          revision: Number(previous.rows[0].revision),
        });
      }
        await client.query("RELEASE SAVEPOINT sync_mutation");
      } catch (mutationError: any) {
        await client.query("ROLLBACK TO SAVEPOINT sync_mutation");
        await client.query("RELEASE SAVEPOINT sync_mutation");
        logger.error("Sync mutation rejected", {
          error: mutationError?.message || "mutation_failed",
          correlation_id: req.headers["x-correlation-id"],
          company_id: user.company_id,
          device_id: deviceInstallationId,
          device_activation_id: deviceActivationId,
          mutation_id:
            mutation && typeof mutation.mutation_id === "string"
              ? mutation.mutation_id
              : null,
          entity_type: mutation?.entity_type,
          entity_id: mutation?.entity_id,
        });
        rejected.push({
          mutation_id:
            mutation && typeof mutation.mutation_id === "string"
              ? mutation.mutation_id
              : null,
          error: mutationError?.message || "mutation_failed",
        });
      }
    }
    await client.query("COMMIT");
    for (const notification of notifications) {
      try {
        await RealtimeBroadcastService.publishEvent(
          user.company_id,
          notification.type,
          {
            entity_id: notification.entityId,
            revision: notification.revision,
          },
        );
      } catch (broadcastError: any) {
        logger.error("Sync committed but realtime notification failed", {
          error: broadcastError?.message || "realtime_publish_failed",
          correlation_id: req.headers["x-correlation-id"],
          company_id: user.company_id,
          device_id: deviceInstallationId,
          entity_id: notification.entityId,
          event_type: notification.type,
          revision: notification.revision,
        });
      }
    }
    return res.json({ results, conflicts, rejected });
  } catch (error: any) {
    await client.query("ROLLBACK");
    logger.error("Sync push failed", {
      error: error?.message || "sync_push_failed",
      stack: error?.stack,
      correlation_id: req.headers["x-correlation-id"],
      company_id: user.company_id,
      device_id: req.body?.device_id,
      device_activation_id: req.body?.device_activation_id,
    });
    return res
      .status(error.message === "invalid_mutation" ? 400 : error.message === "invalid_device_activation" ? 403 : 500)
      .json({ error: error.message });
  } finally {
    client.release();
  }
});

router.get("/pull", async (req, res) => {
  const user = (req as any).user;
  try {
    await assertActiveSyncActivation(
      user.company_id,
      req.query.device_activation_id,
      req.query.device_id,
    );
  } catch (error: any) {
    logger.warn("Sync pull rejected: inactive or mismatched device", {
      error: error?.message,
      correlation_id: req.headers["x-correlation-id"],
      company_id: user.company_id,
      device_id: req.query.device_id,
      device_activation_id: req.query.device_activation_id,
    });
    return res.status(403).json({ error: error.message });
  }
  const cursor = Math.max(
    0,
    Number.parseInt(String(req.query.cursor ?? "0"), 10) || 0,
  );
  const limit = Math.min(
    500,
    Math.max(1, Number.parseInt(String(req.query.limit ?? "200"), 10) || 200),
  );
  const result = await pgPool.query(
    `SELECT revision, mutation_id, COALESCE(device_activation_id, device_id) AS device_id,
            entity_type, entity_id, operation, payload, created_at
       FROM sync_v4_changes WHERE tenant_id = $1 AND revision > $2 ORDER BY revision ASC LIMIT $3`,
    [user.company_id, cursor, limit],
  );
  return res.json({
    changes: result.rows,
    next_cursor: result.rows.length
      ? Number(result.rows.at(-1).revision)
      : cursor,
  });
});

/**
 * Initial hydration for a newly installed device. It reads the canonical
 * business tables, rather than relying on a historical change log that may
 * predate Sync V4. The cursor is advanced to the current journal revision so
 * the next pull receives only subsequent changes.
 */
router.get("/bootstrap", async (req, res) => {
  const user = (req as any).user;
  try {
    await assertActiveSyncActivation(
      user.company_id,
      req.query.device_activation_id,
      req.query.device_id,
    );
  } catch (error: any) {
    logger.warn("Sync bootstrap rejected: inactive or mismatched device", {
      error: error?.message,
      correlation_id: req.headers["x-correlation-id"],
      company_id: user.company_id,
      device_id: req.query.device_id,
      device_activation_id: req.query.device_activation_id,
    });
    return res.status(403).json({ error: error.message });
  }
  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);
    const [products, customers, sales, saleItems, orders, orderItems, refunds, refundItems, financial, revision] = await Promise.all([
      client.query("SELECT * FROM products WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM customers WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM sales WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM sale_items WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM customer_orders WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM customer_order_items WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM refunds WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query(`SELECT ri.* FROM refund_items ri JOIN refunds r ON r.id=ri.refund_id
        WHERE r.company_id=$1 ORDER BY r.created_at,ri.id`, [user.company_id]),
      client.query("SELECT * FROM financial_transactions WHERE company_id = $1 ORDER BY date", [user.company_id]),
      client.query("SELECT COALESCE(MAX(revision), 0) AS cursor FROM sync_v4_changes WHERE tenant_id = $1", [user.company_id]),
    ]);
    await client.query("COMMIT");

    const itemsFor = (rows: Array<Record<string, unknown>>, key: string) => {
      const grouped = new Map<string, Array<Record<string, unknown>>>();
      for (const row of rows) {
        const parent = String(row[key] ?? "");
        const current = grouped.get(parent) ?? [];
        current.push(row);
        grouped.set(parent, current);
      }
      return grouped;
    };
    const localItem = (row: Record<string, unknown>) => ({
      id: row.id,
      sale_id: row.sale_id,
      order_id: row.order_id,
      product_id: row.product_id,
      product_name: row.product_name,
      quantity: row.quantity,
      unit_price: row.unit_price,
      subtotal: row.subtotal,
      created_at: row.created_at,
    });
    const saleItemsBySale = itemsFor(saleItems.rows.map(localItem), "sale_id");
    const orderItemsByOrder = itemsFor(orderItems.rows.map(localItem), "order_id");
    const refundItemsByRefund = itemsFor(refundItems.rows, "refund_id");
    const localPayload = (entityType: string, row: Record<string, unknown>) => {
      const deleted = row.is_deleted === true ? 1 : 0;
      switch (entityType) {
        case "product":
          return { id: row.id, name: row.name, description: row.description ?? "", price: row.price,
            purchase_price: row.purchase_price ?? 0, quantity: row.quantity, min_stock: row.min_stock ?? 5,
            brand: row.brand ?? "", unit: row.unit ?? "adet", shelf_code: row.shelf_code ?? "",
            category: row.category ?? "Genel", sku: row.sku ?? row.id, vat: row.vat,
            is_active: row.status === "active" && !deleted ? 1 : 0, is_deleted: deleted,
            deleted_at: row.deleted_at, deleted_by: row.deleted_by, created_at: row.created_at,
            updated_at: row.updated_at, image_url: row.image_path ?? "" };
        case "customer":
          return { id: row.id, name: row.name, email: row.email ?? "", phone: row.phone ?? "",
            balance: row.balance, credit_limit: row.credit_limit, status: row.status ?? "active",
            is_active: row.status === "active" && !deleted ? 1 : 0, is_deleted: deleted,
            deleted_at: row.deleted_at, deleted_by: row.deleted_by, created_at: row.created_at,
            updated_at: row.updated_at };
        case "sale":
          return { id: row.id, customer_id: row.customer_id ?? "", total_amount: row.total_amount,
            paid_amount: row.paid_amount, payment_method: row.payment_method, status: row.status ?? "completed",
            created_at: row.created_at, updated_at: row.updated_at, idempotency_key: row.idempotency_key,
            is_deleted: deleted, deleted_at: row.deleted_at, deleted_by: row.deleted_by,
            created_by: row.created_by };
        case "order":
          return { id: row.id, order_number: row.order_number ?? `SYNC-${row.id}`,
            customer_id: row.customer_id, status: row.status, total_amount: row.total_amount,
            order_date: row.order_date, expected_delivery_date: row.expected_delivery_date,
            actual_delivery_date: row.actual_delivery_date, notes: row.notes, created_at: row.created_at,
            updated_at: row.updated_at, is_deleted: deleted, deleted_at: row.deleted_at,
            deleted_by: row.deleted_by, created_by: row.created_by };
        case "refund":
          return { id: row.id, sale_id: row.sale_id, amount: row.amount,
            refund_method: row.refund_method, external_reference: row.external_reference,
            reason: row.reason, status: row.status, created_at: row.created_at,
            _snapshot_projection: true };
        default:
          return { id: row.id, type: row.type, customer_id: row.customer_id ?? "", amount: row.amount,
            paid_amount: row.paid_amount, debt_amount: row.debt_amount, reference_id: row.reference_id,
            description: row.description ?? "", metadata: row.metadata ?? null, payment_method: row.payment_method ?? null,
            created_at: row.date, logical_clock: row.logical_clock ?? 0,
            device_id: row.device_id, is_deleted: deleted, deleted_at: row.deleted_at,
            deleted_by: row.deleted_by };
      }
    };
    const change = (entity_type: string, row: Record<string, unknown>, items?: Array<Record<string, unknown>>) => ({
      entity_type,
      entity_id: String(row.id),
      // Bootstrap is a complete snapshot, not an incremental event stream.
      // Soft-deleted parents must be materialized locally so historical order
      // and sale items can still satisfy their foreign-key references.
      operation: "UPSERT",
      payload: items ? { ...localPayload(entity_type, row), items } : localPayload(entity_type, row),
    });
    const changes = [
      ...products.rows.map((row) => change("product", row)),
      ...customers.rows.map((row) => change("customer", row)),
      ...orders.rows.map((row) => change("order", row, orderItemsByOrder.get(String(row.id)) ?? [])),
      ...sales.rows.map((row) => change("sale", row, saleItemsBySale.get(String(row.id)) ?? [])),
      ...refunds.rows.map((row) => change("refund", row, refundItemsByRefund.get(String(row.id)) ?? [])),
      ...financial.rows.map((row) => change("financial_transaction", row)),
    ];
    return res.json({ changes, next_cursor: Number(revision.rows[0].cursor) });
  } catch (error: any) {
    await client.query("ROLLBACK");
    logger.error("Sync bootstrap failed", {
      error: error?.message || "sync_bootstrap_failed",
      stack: error?.stack,
      correlation_id: req.headers["x-correlation-id"],
      company_id: user.company_id,
      device_id: req.query.device_id,
      device_activation_id: req.query.device_activation_id,
    });
    return res.status(500).json({ error: "sync_bootstrap_failed" });
  } finally {
    client.release();
  }
});

router.get("/bootstrap/license-config", async (req, res) => {
  const user = (req as any).user;
  const result = await pgPool.query(
    `SELECT id, plan_id AS tier, status, valid_until AS expires_at, license_key,
            device_limit AS allowed_devices_count
       FROM license_entitlements
      WHERE company_id = $1 AND status IN ('trial', 'active')
      ORDER BY valid_until DESC LIMIT 1`,
    [user.company_id],
  );
  return res.json({ module: "license-config", data: result.rows[0] ?? {} });
});

export default router;
