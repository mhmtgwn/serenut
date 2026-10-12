import { Router } from "express";
import { requirePermission } from "../../middleware/auth.middleware";
import { pgPool } from "../../config/database";
import { RealtimeBroadcastService } from "../realtime/broadcast.service";
import { logger } from "../../config/logger";
import { randomUUID } from "crypto";
import {
  requireDestructiveResetRole,
  assertActiveSyncActivation,
} from "./sync-v4.common";

const router = Router();

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

export default router;
