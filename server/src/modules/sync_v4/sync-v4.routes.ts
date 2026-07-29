import { Router } from "express";
import { authenticateUser } from "../../middleware/auth.middleware";
import { pgPool } from "../../config/database";
import { syncLimiter } from "../../middleware/rate-limit.middleware";
import { requireActiveEntitlement } from "../../middleware/auth.middleware";
import { RealtimeBroadcastService } from "../realtime/broadcast.service";
import { logger } from "../../config/logger";
import type { PoolClient } from "pg";

const router = Router();
const entityTypes = new Set([
  "product",
  "customer",
  "order",
  "sale",
  "financial_transaction",
]);
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const syncProtocolVersion = 5;

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
): Promise<void> {
  if (typeof activationId !== "string" || typeof installationId !== "string" ||
      !activationId || !installationId) {
    throw new Error("invalid_device_activation");
  }
  const activation = await pgPool.query(
    `SELECT id FROM device_activations
     WHERE id = $1 AND company_id = $2 AND device_hash = $3 AND status = 'active'`,
    [activationId, companyId, installationId],
  );
  if (activation.rowCount === 0) throw new Error("invalid_device_activation");
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
): Promise<void> {
  const payload = mutation.payload;
  const id = mutation.entity_id;

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
        await client.query(
          "UPDATE sales SET is_deleted = true, deleted_at = NOW(), updated_at = NOW() WHERE id = $1 AND company_id = $2",
          [id, companyId],
        );
        return;
      case "financial_transaction":
        throw new Error("immutable_financial_transaction");
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
  }
}

async function upsertSale(client: PoolClient, companyId: string, id: string, payload: Record<string, unknown>) {
  const customerId = nullableId(stringValue(payload, "customer_id"));
  const paymentMethod = stringValue(payload, "payment_method", "cash");
  const items = Array.isArray(payload.items) ? payload.items : [];
  await client.query(
    `INSERT INTO sales (id, company_id, customer_id, total_amount, paid_amount, payment_method, status, fsm_state, idempotency_key, created_at, updated_at, is_deleted, created_by)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,COALESCE($10::timestamptz,NOW()),NOW(),false,$11)
     ON CONFLICT (id) DO UPDATE SET customer_id=EXCLUDED.customer_id, total_amount=EXCLUDED.total_amount,
       paid_amount=EXCLUDED.paid_amount, payment_method=EXCLUDED.payment_method, status=EXCLUDED.status,
       fsm_state=EXCLUDED.fsm_state, is_deleted=false, updated_at=NOW() WHERE sales.company_id=EXCLUDED.company_id`,
    [id, companyId, customerId, numberValue(payload, "total_amount"), numberValue(payload, "paid_amount"),
      paymentMethod, stringValue(payload, "status", "completed"), stringValue(payload, "status", "completed"),
      stringValue(payload, "idempotency_key") || null, stringValue(payload, "created_at") || null,
      stringValue(payload, "created_by") || null],
  );
  await client.query("DELETE FROM sale_items WHERE sale_id = $1 AND company_id = $2", [id, companyId]);
  for (let index = 0; index < items.length; index++) {
    const item = items[index];
    if (!item || typeof item !== "object") throw new Error("invalid_mutation");
    const row = item as Record<string, unknown>;
    const productId = stringValue(row, "product_id");
    if (!productId) throw new Error("invalid_mutation");
    const quantity = numberValue(row, "quantity");
    const unitPrice = numberValue(row, "unit_price", numberValue(row, "price"));
    await client.query(
      `INSERT INTO sale_items (id, sale_id, product_id, product_name, quantity, unit_price, subtotal, company_id, created_at)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,COALESCE($9::timestamptz,NOW()))`,
      [stringValue(row, "id", `sync-${id}-${index}`), id, productId,
        stringValue(row, "product_name") || null, quantity, unitPrice,
        numberValue(row, "subtotal", quantity * unitPrice), companyId, stringValue(row, "created_at") || null],
    );
  }
}

async function upsertOrder(client: PoolClient, companyId: string, id: string, payload: Record<string, unknown>) {
  const customerId = stringValue(payload, "customer_id");
  if (!customerId) throw new Error("invalid_mutation");
  const items = Array.isArray(payload.items) ? payload.items : [];
  await client.query(
    `INSERT INTO customer_orders (id, company_id, customer_id, status, total_amount, order_date, expected_delivery_date, actual_delivery_date, notes, created_at, updated_at, is_deleted, created_by)
     VALUES ($1,$2,$3,$4,$5,COALESCE($6::timestamptz,NOW()),$7::timestamptz,$8::timestamptz,$9,COALESCE($10::timestamptz,NOW()),NOW(),false,$11)
     ON CONFLICT (id) DO UPDATE SET customer_id=EXCLUDED.customer_id, status=EXCLUDED.status,
       total_amount=EXCLUDED.total_amount, expected_delivery_date=EXCLUDED.expected_delivery_date,
       actual_delivery_date=EXCLUDED.actual_delivery_date, notes=EXCLUDED.notes, is_deleted=false,
       updated_at=NOW() WHERE customer_orders.company_id=EXCLUDED.company_id`,
    [id, companyId, customerId, stringValue(payload, "status", "created"), numberValue(payload, "total_amount"),
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
    [id, companyId, stringValue(payload, "type", "payment"), customerId, numberValue(payload, "amount"),
      numberValue(payload, "paid_amount"), numberValue(payload, "debt_amount"),
      stringValue(payload, "date") || stringValue(payload, "created_at") || null,
      stringValue(payload, "reference_id") || null, numberValue(payload, "logical_clock"),
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
      const effectiveOperation =
        entity.rows[0]?.is_deleted === true ? "DELETE" : mutation.operation;
      const domainMutation: SyncMutation = {
        entity_type: mutation.entity_type,
        entity_id: mutation.entity_id,
        operation: effectiveOperation,
        payload: mutation.payload,
        base_revision: mutation.base_revision,
      };
      // The domain write and the durable replication record are atomic. Never
      // acknowledge a mutation that cannot be materialized for another device.
      await applyDomainMutation(client, user.company_id, domainMutation);
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
    const [products, customers, sales, saleItems, orders, orderItems, financial, revision] = await Promise.all([
      client.query("SELECT * FROM products WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM customers WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM sales WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM sale_items WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM customer_orders WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM customer_order_items WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
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
          return { id: row.id, customer_id: row.customer_id, status: row.status, total_amount: row.total_amount,
            order_date: row.order_date, expected_delivery_date: row.expected_delivery_date,
            actual_delivery_date: row.actual_delivery_date, notes: row.notes, created_at: row.created_at,
            updated_at: row.updated_at, is_deleted: deleted, deleted_at: row.deleted_at,
            deleted_by: row.deleted_by, created_by: row.created_by };
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
