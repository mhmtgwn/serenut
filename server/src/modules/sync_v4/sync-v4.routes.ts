import { Router } from "express";
import crypto from "crypto";
import { authenticateUser, requireActiveEntitlement } from "../../middleware/auth.middleware";
import { pgPool } from "../../config/database";
import { syncLimiter } from "../../middleware/rate-limit.middleware";
import { RealtimeBroadcastService } from "../realtime/broadcast.service";
import { logger } from "../../config/logger";
export {
  applyDomainMutation,
  SyncMutation,
  stringValue,
} from "./sync-v4.materializer";
import {
  applyDomainMutation,
  SyncMutation,
} from "./sync-v4.materializer";
import hardwareRouter from "./sync-v4.hardware.routes";
import resetRouter from "./sync-v4.reset.routes";
import {
  assertActiveSyncActivation,
  requireDestructiveResetRole,
} from "./sync-v4.common";
export { assertActiveSyncActivation, requireDestructiveResetRole };

const router = Router();
const entityTypes = new Set([
  "product",
  "customer",
  "order",
  "sale",
  "financial_transaction",
  "refund",
  "cash_count",
  "cash_expense",
  "gib_invoice",
  "customer_installment_plan",
  "customer_installment",
  "warehouse",
  "customer_hazelnut_escrow",
  "warehouse_hazelnut_movement",
  "hazelnut_price_cut",
]);
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const syncProtocolVersion = 6;
const deterministicMutationPrefixPattern = /^(evt-|mut-|ev-|legacy-mutation-)[A-Za-z0-9._:-]{1,120}$/;
function resolveMutationUuid(rawId: string): string | null {
  if (uuidPattern.test(rawId)) return rawId;
  if (!deterministicMutationPrefixPattern.test(rawId)) return null;
  const h = crypto.createHash("sha256").update(`serenut-sync-v4:${rawId}`).digest("hex");
  return `${h.slice(0, 8)}-${h.slice(8, 12)}-5${h.slice(13, 16)}-8${h.slice(17, 20)}-${h.slice(20, 32)}`;
}

function payloadDeepEqual(a: any, b: any): boolean {
  if (a === b) return true;
  if (a == null || b == null) return a === b;
  if (typeof a !== "object" || typeof b !== "object") {
    if (typeof a === "number" && typeof b === "number") return Math.abs(a - b) < 1e-9;
    return a === b;
  }
  if (Array.isArray(a) !== Array.isArray(b)) return false;
  if (Array.isArray(a) && Array.isArray(b)) {
    if (a.length !== b.length) return false;
    for (let i = 0; i < a.length; i++) {
      if (!payloadDeepEqual(a[i], b[i])) return false;
    }
    return true;
  }
  const keysA = Object.keys(a);
  const keysB = Object.keys(b);
  if (keysA.length !== keysB.length) return false;
  for (const key of keysA) {
    if (!Object.prototype.hasOwnProperty.call(b, key)) return false;
    if (!payloadDeepEqual(a[key], b[key])) return false;
  }
  return true;
}

router.use(authenticateUser as any);
// /push rotası, çevrimdışı birikmiş yerel mutasyonların (satış, iade, kasa sayımı)
// lisans süresi dolsa dahi veri kaybı olmadan buluta aktarılabilmesi için açık tutulur.
router.use((req, res, next) => {
  if (req.path === "/push") {
    return next();
  }
  return (requireActiveEntitlement as any)(req, res, next);
});
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

router.use(hardwareRouter);
router.use(resetRouter);

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
    // Serialize all concurrent pushes within the same tenant to guarantee that
    // revisions commit in strictly monotonic sequential order with zero commit gaps.
    await client.query(
      "SELECT pg_advisory_xact_lock(hashtext($1), hashtext('tenant-push-order'))",
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
        !resolveMutationUuid(mutation.mutation_id) ||
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
        "SELECT revision, payload FROM sync_v4_changes WHERE tenant_id = $1 AND mutation_id = $2::uuid",
        [user.company_id, resolveMutationUuid(mutation.mutation_id)],
      );
      if (prior.rowCount) {
        const rawPayload = prior.rows[0].payload;
        const prevPayload = typeof rawPayload === "string" ? JSON.parse(rawPayload) : rawPayload;
        if (prevPayload && !payloadDeepEqual(prevPayload, mutation.payload)) {
          throw new Error("mutation_payload_conflict");
        }
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
        `SELECT is_deleted, updated_revision, payload FROM sync_v4_entities
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
            [user.company_id, resolveMutationUuid(mutation.mutation_id), mutation.entity_type,
              mutation.entity_id, mutation.base_revision, currentRevision,
              deviceInstallationId, JSON.stringify(mutation.payload)],
          );
          conflicts.push({ mutation_id: mutation.mutation_id, entity_type: mutation.entity_type,
            entity_id: mutation.entity_id, server_revision: currentRevision });
          continue;
        }
      }
      if (
        mutation.operation === "UPSERT" &&
        entity.rowCount &&
        currentRevision > 0 &&
        !entity.rows[0].is_deleted
      ) {
        const rawExisting = entity.rows[0].payload;
        const existingPayload = typeof rawExisting === "string" ? JSON.parse(rawExisting) : rawExisting;
        const isIdentical =
          existingPayload != null &&
          (payloadDeepEqual(existingPayload, mutation.payload) ||
            (mutation.entity_type === "financial_transaction" &&
              Number(existingPayload.amount) === Number(mutation.payload.amount) &&
              Number(existingPayload.paid_amount) === Number(mutation.payload.paid_amount) &&
              Number(existingPayload.debt_amount) === Number(mutation.payload.debt_amount) &&
              String(existingPayload.customer_id ?? "") === String(mutation.payload.customer_id ?? "")));

        if (isIdentical) {
          results.push({ mutation_id: mutation.mutation_id, revision: currentRevision });
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
      // The domain write and the durable replication record are atomic. Never
      // acknowledge a mutation that cannot be materialized for another device.
      const sanitizedPayload = (typeof mutation.payload === 'object' && mutation.payload !== null)
        ? { ...mutation.payload }
        : {};
      if (
        (mutation.entity_type === 'financial_transaction' ||
         mutation.entity_type === 'sale' ||
         mutation.entity_type === 'order') &&
        (sanitizedPayload.customer_id === null || sanitizedPayload.customer_id === undefined)
      ) {
        sanitizedPayload.customer_id = '';
      }
      const domainMutation: SyncMutation = {
        entity_type: mutation.entity_type,
        entity_id: mutation.entity_id,
        operation: effectiveOperation,
        payload: sanitizedPayload,
        base_revision: mutation.base_revision,
      };

      await applyDomainMutation(client, user.company_id, domainMutation, user.id);
      const inserted = await client.query(
        `INSERT INTO sync_v4_changes (tenant_id, mutation_id, device_id, device_activation_id, entity_type, entity_id, operation, payload)
         VALUES ($1, $2::uuid, $3, $4, $5, $6, $7, $8::jsonb)
         ON CONFLICT (tenant_id, mutation_id) DO NOTHING
         RETURNING revision`,
        [
          user.company_id,
          resolveMutationUuid(mutation.mutation_id),
          deviceInstallationId,
          deviceActivationId,
          mutation.entity_type,
          mutation.entity_id,
          effectiveOperation,
          JSON.stringify(sanitizedPayload),
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
            JSON.stringify(sanitizedPayload),
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
                : mutation.entity_type === "sale"
                  ? "SaleCompleted"
                  : mutation.entity_type === "refund"
                    ? "RefundCreated"
                    : "OrderUpdated",
          entityId: mutation.entity_id,
          revision,
        });
      } else {
        const previous = await client.query(
          "SELECT revision FROM sync_v4_changes WHERE tenant_id = $1 AND mutation_id = $2::uuid",
          [user.company_id, resolveMutationUuid(mutation.mutation_id)],
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
  const client = await pgPool.connect();
  try {
    const result = await client.query(
      `SELECT revision, mutation_id, COALESCE(device_activation_id, device_id) AS device_id,
              entity_type, entity_id, operation, payload, created_at
         FROM sync_v4_changes WHERE tenant_id = $1 AND revision > $2 ORDER BY revision ASC LIMIT $3`,
      [user.company_id, cursor, limit],
    );
    const changes = result.rows.map((row: any) => {
      if (
        (row.entity_type === 'financial_transaction' ||
         row.entity_type === 'sale' ||
         row.entity_type === 'order') &&
        row.payload &&
        (row.payload.customer_id === null || row.payload.customer_id === undefined)
      ) {
        return {
          ...row,
          payload: {
            ...row.payload,
            customer_id: '',
          },
        };
      }
      return row;
    });
    return res.json({
      changes,
      next_cursor: changes.length
        ? Number(changes.at(-1).revision)
        : cursor,
    });
  } finally {
    client.release();
  }
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
    const [products, customers, sales, saleItems, orders, orderItems, refunds, refundItems, financial, revision, warehouses, escrows, movements, priceCuts] = await Promise.all([
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
      client.query("SELECT * FROM warehouses WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM customer_hazelnut_escrow WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM warehouse_hazelnut_movements WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
      client.query("SELECT * FROM hazelnut_price_cuts WHERE company_id = $1 ORDER BY created_at", [user.company_id]),
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
            address: row.address ?? "",
            balance: row.balance, credit_limit: row.credit_limit, status: row.status ?? "active",
            is_active: row.status === "active" && !deleted ? 1 : 0, is_deleted: deleted,
            deleted_at: row.deleted_at, deleted_by: row.deleted_by, created_at: row.created_at,
            updated_at: row.updated_at };
        case "sale":
          return { id: row.id, customer_id: row.customer_id ?? "", total_amount: row.total_amount,
            paid_amount: row.paid_amount, discount_amount: Number(row.discount_amount ?? 0), payment_method: row.payment_method, status: row.status ?? "completed",
            created_at: row.created_at, updated_at: row.updated_at, idempotency_key: row.idempotency_key,
            is_deleted: deleted, deleted_at: row.deleted_at, deleted_by: row.deleted_by,
            created_by: row.created_by };
        case "order":
          return { id: row.id, order_number: row.order_number ?? `SYNC-${row.id}`,
            customer_id: row.customer_id, status: row.status, total_amount: row.total_amount,
            discount_amount: Number(row.discount_amount ?? 0),
            order_date: row.order_date, expected_delivery_date: row.expected_delivery_date,
            actual_delivery_date: row.actual_delivery_date, notes: row.notes, created_at: row.created_at,
            updated_at: row.updated_at, is_deleted: deleted, deleted_at: row.deleted_at,
            deleted_by: row.deleted_by, created_by: row.created_by };
        case "refund":
          return { id: row.id, sale_id: row.sale_id, amount: row.amount,
            refund_method: row.refund_method, external_reference: row.external_reference,
            reason: row.reason, status: row.status, created_at: row.created_at,
            _snapshot_projection: true };
        case "warehouse":
          return {
            id: row.id,
            name: row.name,
            location: row.location ?? "",
            capacity_kg: row.capacity_kg,
            current_stock_kg: row.current_stock_kg,
            average_rendiment: row.average_rendiment,
            is_active: row.is_active ? 1 : 0,
            is_deleted: deleted,
            deleted_at: row.deleted_at,
            created_at: row.created_at,
            updated_at: row.updated_at,
          };
        case "customer_hazelnut_escrow":
          return {
            id: row.id,
            customer_id: row.customer_id,
            warehouse_id: row.warehouse_id,
            receipt_no: row.receipt_no ?? "",
            gross_kg: row.gross_kg,
            sack_count: row.sack_count,
            tare_kg: row.tare_kg,
            net_kg: row.net_kg,
            rendiment: row.rendiment,
            remaining_kg: row.remaining_kg,
            status: row.status ?? "active",
            notes: row.notes ?? "",
            created_by: row.created_by,
            is_deleted: deleted,
            deleted_at: row.deleted_at,
            created_at: row.created_at,
            updated_at: row.updated_at,
          };
        case "warehouse_hazelnut_movement":
          return {
            id: row.id,
            warehouse_id: row.warehouse_id,
            movement_type: row.movement_type,
            quantity_kg: row.quantity_kg,
            rendiment: row.rendiment,
            balance_kg_after: row.balance_kg_after,
            average_rendiment_after: row.average_rendiment_after,
            reference_id: row.reference_id,
            description: row.description ?? "",
            created_by: row.created_by,
            created_at: row.created_at,
          };
        case "hazelnut_price_cut":
          return {
            id: row.id,
            escrow_id: row.escrow_id,
            customer_id: row.customer_id,
            cut_kg: row.cut_kg,
            rendiment: row.rendiment,
            base_price_50: row.base_price_50,
            effective_price: row.effective_price,
            total_amount: row.total_amount,
            settlement_type: row.settlement_type ?? "ACCOUNT_CREDIT",
            financial_transaction_id: row.financial_transaction_id,
            notes: row.notes ?? "",
            created_by: row.created_by,
            created_at: row.created_at,
          };
        default:
          return { id: row.id, type: row.type, customer_id: row.customer_id ?? "", amount: row.amount,
            paid_amount: row.paid_amount, debt_amount: row.debt_amount, reference_id: row.reference_id,
            description: row.description ?? "",
            metadata: row.metadata
              ? (typeof row.metadata === "string" ? row.metadata : JSON.stringify(row.metadata))
              : null,
            payment_method: row.payment_method ?? null,
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
      ...warehouses.rows.map((row) => change("warehouse", row)),
      ...escrows.rows.map((row) => change("customer_hazelnut_escrow", row)),
      ...movements.rows.map((row) => change("warehouse_hazelnut_movement", row)),
      ...priceCuts.rows.map((row) => change("hazelnut_price_cut", row)),
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
  const client = await pgPool.connect();
  try {
    const result = await client.query(
      `SELECT id, plan_id AS tier, status, valid_until AS expires_at, license_key,
              device_limit AS allowed_devices_count
         FROM license_entitlements
        WHERE company_id = $1 AND status IN ('trial', 'active')
        ORDER BY valid_until DESC LIMIT 1`,
      [user.company_id],
    );
    return res.json({ module: 'license-config', data: result.rows[0] ?? {} });
  } finally {
    client.release();
  }
});

export default router;
