import { Router } from "express";
import { authenticateUser } from "../../middleware/auth.middleware";
import { pgPool } from "../../config/database";
import { syncLimiter } from "../../middleware/rate-limit.middleware";
import { requireActiveEntitlement } from "../../middleware/auth.middleware";
import { RealtimeBroadcastService } from "../realtime/broadcast.service";

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

router.use(syncLimiter);
router.use(authenticateUser as any);
router.use(requireActiveEntitlement as any);

router.post("/push", async (req, res) => {
  const user = (req as any).user;
  const deviceId = req.header("x-device-id") || req.body?.device_id;
  const mutations = req.body?.mutations;
  if (!deviceId || !Array.isArray(mutations) || mutations.length > 100) {
    return res.status(400).json({ error: "invalid_sync_request" });
  }

  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");
    await client.query(
      "SELECT set_config('app.current_company_id', $1, true)",
      [user.company_id],
    );
    const results = [] as Array<{ mutation_id: string; revision: number }>;
    const notifications: Array<{
      type: string;
      entityId: string;
      revision: number;
    }> = [];
    for (const mutation of mutations) {
      if (
        !mutation ||
        typeof mutation.mutation_id !== "string" ||
        !uuidPattern.test(mutation.mutation_id) ||
        !entityTypes.has(mutation.entity_type) ||
        typeof mutation.entity_id !== "string" ||
        !["UPSERT", "DELETE"].includes(mutation.operation) ||
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
        `SELECT is_deleted FROM sync_v4_entities
          WHERE tenant_id = $1 AND entity_type = $2 AND entity_id = $3 FOR UPDATE`,
        [user.company_id, mutation.entity_type, mutation.entity_id],
      );
      const effectiveOperation =
        entity.rows[0]?.is_deleted === true ? "DELETE" : mutation.operation;
      const inserted = await client.query(
        `INSERT INTO sync_v4_changes (tenant_id, mutation_id, device_id, entity_type, entity_id, operation, payload)
         VALUES ($1, $2::uuid, $3, $4, $5, $6, $7::jsonb)
         ON CONFLICT (tenant_id, mutation_id) DO NOTHING
         RETURNING revision`,
        [
          user.company_id,
          mutation.mutation_id,
          deviceId,
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
    }
    await client.query("COMMIT");
    for (const notification of notifications) {
      await RealtimeBroadcastService.publishEvent(
        user.company_id,
        notification.type,
        {
          entity_id: notification.entityId,
          revision: notification.revision,
        },
      );
    }
    return res.json({ results });
  } catch (error: any) {
    await client.query("ROLLBACK");
    return res
      .status(error.message === "invalid_mutation" ? 400 : 500)
      .json({ error: error.message });
  } finally {
    client.release();
  }
});

router.get("/pull", async (req, res) => {
  const user = (req as any).user;
  const cursor = Math.max(
    0,
    Number.parseInt(String(req.query.cursor ?? "0"), 10) || 0,
  );
  const limit = Math.min(
    500,
    Math.max(1, Number.parseInt(String(req.query.limit ?? "200"), 10) || 200),
  );
  const result = await pgPool.query(
    `SELECT revision, mutation_id, device_id, entity_type, entity_id, operation, payload, created_at
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
