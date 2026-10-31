// server/src/modules/sync_v4/sync-v4.reset.service.ts
import { pgPool } from "../../config/database";
import { RealtimeBroadcastService } from "../realtime/broadcast.service";
import { logger } from "../../config/logger";
import { randomUUID } from "crypto";
import { assertActiveSyncActivation } from "./sync-v4.common";

export class SyncV4ResetService {
  async performCatalogReset(params: {
    companyId: string;
    userId: string;
    activationId?: string;
    deviceId?: string;
    ip?: string | null;
    correlationId?: string;
  }): Promise<{ reset_revision: number; counts: any }> {
    const { companyId, userId, activationId, deviceId, ip, correlationId } = params;
    const client = await pgPool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT set_config('app.current_company_id', $1, true)", [companyId]);
      await assertActiveSyncActivation(companyId, activationId, deviceId, client);
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtext($1), hashtext('operational-reset'))",
        [companyId],
      );
      const countResult = await client.query(
        "SELECT COUNT(*) AS products FROM products WHERE company_id=$1 AND is_deleted=false",
        [companyId],
      );
      await client.query(
        `UPDATE products SET is_deleted=true,status='inactive',deleted_at=COALESCE(deleted_at,NOW()),updated_at=NOW()
          WHERE company_id=$1`,
        [companyId],
      );
      await client.query(
        "DELETE FROM sync_v4_entities WHERE tenant_id=$1 AND entity_type='product'",
        [companyId],
      );
      await client.query(
        "DELETE FROM sync_v4_conflicts WHERE tenant_id=$1 AND entity_type='product'",
        [companyId],
      );

      const mutationId = randomUUID();
      const payload = { scope: "catalog", counts: countResult.rows[0] };
      const resetChange = await client.query(
        `INSERT INTO sync_v4_changes
          (tenant_id,mutation_id,device_id,device_activation_id,entity_type,entity_id,operation,payload)
         VALUES ($1,$2::uuid,$3,$4,'system_reset',$5,'UPSERT',$6::jsonb)
         RETURNING revision`,
        [companyId, mutationId, deviceId, activationId,
          `catalog-${mutationId}`, JSON.stringify(payload)],
      );
      const resetRevision = Number(resetChange.rows[0].revision);
      await client.query(
        `INSERT INTO audit_logs
          (id,company_id,user_id,action,entity,entity_id,new_value,ip_address)
         VALUES ($1,$2,$3,'PRODUCT_CATALOG_RESET','product_catalog',$4,$5,$6)`,
        [`aud-${randomUUID()}`, companyId, userId, String(resetRevision),
          JSON.stringify(payload), ip ?? null],
      );
      await client.query("COMMIT");
      await RealtimeBroadcastService.publishEvent(
        companyId,
        "ProductCatalogReset",
        { reset_revision: resetRevision },
        correlationId,
      );
      return { reset_revision: resetRevision, counts: countResult.rows[0] };
    } catch (error: any) {
      await client.query("ROLLBACK").catch(() => undefined);
      logger.error("Product catalog reset failed", {
        error: error?.message || "catalog_reset_failed",
        company_id: companyId,
        user_id: userId,
      });
      throw error;
    } finally {
      client.release();
    }
  }

  async performOperationalReset(params: {
    companyId: string;
    userId: string;
    activationId?: string;
    deviceId?: string;
    ip?: string | null;
    correlationId?: string;
  }): Promise<{ reset_revision: number; counts: any }> {
    const { companyId, userId, activationId, deviceId, ip, correlationId } = params;
    const client = await pgPool.connect();
    try {
      await client.query("BEGIN");
      await client.query("SELECT set_config('app.current_company_id', $1, true)", [companyId]);
      await assertActiveSyncActivation(companyId, activationId, deviceId, client);
      await client.query(
        "SELECT pg_advisory_xact_lock(hashtext($1), hashtext('operational-reset'))",
        [companyId],
      );

      const counts = await client.query(
        `SELECT
          (SELECT COUNT(*) FROM products WHERE company_id=$1) AS products,
          (SELECT COUNT(*) FROM customers WHERE company_id=$1) AS customers,
          (SELECT COUNT(*) FROM sales WHERE company_id=$1) AS sales,
          (SELECT COUNT(*) FROM customer_orders WHERE company_id=$1) AS orders,
          (SELECT COUNT(*) FROM financial_transactions WHERE company_id=$1) AS financial_transactions`,
        [companyId],
      );

      await client.query(
        `DELETE FROM refund_items ri USING refunds r
          WHERE ri.refund_id=r.id AND r.company_id=$1`,
        [companyId],
      );
      await client.query("DELETE FROM inventory_movements WHERE company_id=$1", [companyId]);
      await client.query("DELETE FROM refunds WHERE company_id=$1", [companyId]);
      await client.query("DELETE FROM sale_items WHERE company_id=$1", [companyId]);
      await client.query("DELETE FROM financial_transactions WHERE company_id=$1", [companyId]);
      await client.query("DELETE FROM sales WHERE company_id=$1", [companyId]);
      await client.query("DELETE FROM customer_order_items WHERE company_id=$1", [companyId]);
      await client.query("DELETE FROM customer_orders WHERE company_id=$1", [companyId]);
      await client.query("DELETE FROM products WHERE company_id=$1", [companyId]);
      await client.query("DELETE FROM customers WHERE company_id=$1", [companyId]);
      await client.query(
        `DELETE FROM sync_v4_entities WHERE tenant_id=$1
          AND entity_type IN ('product','customer','order','sale','financial_transaction','refund')`,
        [companyId],
      );
      await client.query("DELETE FROM sync_v4_conflicts WHERE tenant_id=$1", [companyId]);

      const mutationId = randomUUID();
      const payload = { scope: "operational", counts: counts.rows[0] };
      const resetChange = await client.query(
        `INSERT INTO sync_v4_changes
          (tenant_id,mutation_id,device_id,device_activation_id,entity_type,entity_id,operation,payload)
         VALUES ($1,$2::uuid,$3,$4,'system_reset',$5,'UPSERT',$6::jsonb)
         RETURNING revision`,
        [companyId, mutationId, deviceId, activationId,
          `operational-${mutationId}`, JSON.stringify(payload)],
      );
      const resetRevision = Number(resetChange.rows[0].revision);
      await client.query(
        `INSERT INTO audit_logs
          (id,company_id,user_id,action,entity,entity_id,new_value,ip_address)
         VALUES ($1,$2,$3,'OPERATIONAL_DATA_RESET','database',$4,$5,$6)`,
        [`aud-${randomUUID()}`, companyId, userId, String(resetRevision),
          JSON.stringify(payload), ip ?? null],
      );
      await client.query("COMMIT");
      await RealtimeBroadcastService.publishEvent(
        companyId,
        "OperationalDataReset",
        { reset_revision: resetRevision },
        correlationId,
      );
      return { reset_revision: resetRevision, counts: counts.rows[0] };
    } catch (error: any) {
      await client.query("ROLLBACK").catch(() => undefined);
      logger.error("Operational reset failed", {
        error: error?.message || "operational_reset_failed",
        company_id: companyId,
        user_id: userId,
      });
      throw error;
    } finally {
      client.release();
    }
  }
}

export const syncV4ResetService = new SyncV4ResetService();
