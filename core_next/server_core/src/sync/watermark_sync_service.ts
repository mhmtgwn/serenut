// core_next/server_core/src/sync/watermark_sync_service.ts
import { Pool, PoolClient } from 'pg';

export interface SyncEventPayload {
  eventId: string;
  entityType: 'PRODUCT' | 'CUSTOMER' | 'SALE' | 'LEDGER_ENTRY';
  entityId: string;
  operation: 'UPSERT' | 'DELETE';
  payloadJson: string;
  clientTimestamp: number;
}

export interface SyncPushResult {
  acknowledgedEventIds: string[];
  serverRevision: number;
}

export interface SyncPullResult {
  currentRevision: number;
  events: SyncEventPayload[];
}

/**
 * Yeni Nesil Olay Tabanlı Watermark Senkronizasyon Motoru (Watermark Sync Service).
 * 
 * 409 Conflict ve sıralama çakışmalarını kalıcı olarak bitirir.
 * İstemci tarafından gönderilen olayları PostgreSQL üzerinde atomik ve idempotent
 * (ON CONFLICT DO NOTHING) olarak deftere işler ve revizyon sayacını artırır.
 */
export class WatermarkSyncService {
  constructor(private readonly pool: Pool) {}

  /**
   * İstemciden gelen olayları toplu (batch) olarak kabul eder ve işler.
   */
  async processPush(
    tenantId: string,
    deviceId: string,
    events: SyncEventPayload[]
  ): Promise<SyncPushResult> {
    const client = await this.pool.connect();
    const acknowledgedIds: string[] = [];

    try {
      await client.query('BEGIN');

      // 1. Kiracı revizyon sayacını kilitleyerek al (Row-level lock)
      const revRes = await client.query(
        `SELECT current_revision FROM tenant_sync_watermarks 
         WHERE tenant_id = $1 FOR UPDATE`,
        [tenantId]
      );

      let currentRev = 0;
      if (revRes.rows.length === 0) {
        await client.query(
          `INSERT INTO tenant_sync_watermarks (tenant_id, current_revision, updated_at) 
           VALUES ($1, 0, NOW())`,
          [tenantId]
        );
      } else {
        currentRev = revRes.rows[0].current_revision;
      }

      // 2. Her bir olayı idempotent olarak log tablosuna yaz
      for (const ev of events) {
        currentRev += 1;

        const insertRes = await client.query(
          `INSERT INTO sync_event_log 
            (event_id, tenant_id, device_id, entity_type, entity_id, operation, payload_json, client_timestamp, server_revision, created_at)
           VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, NOW())
           ON CONFLICT (event_id) DO NOTHING
           RETURNING event_id`,
          [
            ev.eventId,
            tenantId,
            deviceId,
            ev.entityType,
            ev.entityId,
            ev.operation,
            ev.payloadJson,
            ev.clientTimestamp,
            currentRev,
          ]
        );

        // İster yeni yazılmış olsun, ister önceden işlenmiş (idempotent), acknowledge listesine ekle
        acknowledgedIds.push(ev.eventId);

        // Eğer yeni yazıldıysa materyalleştirme tablosunu güncelle
        if (insertRes.rowCount && insertRes.rowCount > 0) {
          await this.materializeEntity(client, tenantId, ev);
        }
      }

      // 3. Güncellenen revizyonu kaydet
      await client.query(
        `UPDATE tenant_sync_watermarks 
         SET current_revision = $1, updated_at = NOW() 
         WHERE tenant_id = $2`,
        [currentRev, tenantId]
      );

      await client.query('COMMIT');

      return {
        acknowledgedEventIds: acknowledgedIds,
        serverRevision: currentRev,
      };
    } catch (error) {
      await client.query('ROLLBACK');
      throw error;
    } finally {
      client.release();
    }
  }

  /**
   * İstemciye son bildiği revizyondan sonraki değişiklikleri döner.
   */
  async processPull(
    tenantId: string,
    sinceRevision: number,
    limit: number = 500
  ): Promise<SyncPullResult> {
    const client = await this.pool.connect();
    try {
      // Güncel revizyonu al
      const revRes = await client.query(
        `SELECT current_revision FROM tenant_sync_watermarks WHERE tenant_id = $1`,
        [tenantId]
      );
      const currentRev = revRes.rows.length > 0 ? revRes.rows[0].current_revision : 0;

      // Delta olaylarını topla
      const eventsRes = await client.query(
        `SELECT event_id, entity_type, entity_id, operation, payload_json, client_timestamp, server_revision
         FROM sync_event_log
         WHERE tenant_id = $1 AND server_revision > $2
         ORDER BY server_revision ASC
         LIMIT $3`,
        [tenantId, sinceRevision, limit]
      );

      const events: SyncEventPayload[] = eventsRes.rows.map((row) => ({
        eventId: row.event_id,
        entityType: row.entity_type,
        entityId: row.entity_id,
        operation: row.operation,
        payloadJson: row.payload_json,
        clientTimestamp: Number(row.client_timestamp),
      }));

      return {
        currentRevision: currentRev,
        events,
      };
    } finally {
      client.release();
    }
  }

  /**
   * Gelen olayı ilişkisel ana tablolara uygular (Domain Materializer)
   */
  private async materializeEntity(
    client: PoolClient,
    tenantId: string,
    ev: SyncEventPayload
  ): Promise<void> {
    if (ev.operation === 'DELETE') {
      if (ev.entityType === 'PRODUCT') {
        await client.query(
          `UPDATE products SET is_deleted = true, updated_at = NOW() 
           WHERE id = $1 AND tenant_id = $2`,
          [ev.entityId, tenantId]
        );
      } else if (ev.entityType === 'CUSTOMER') {
        await client.query(
          `UPDATE customers SET is_deleted = true, updated_at = NOW() 
           WHERE id = $1 AND tenant_id = $2`,
          [ev.entityId, tenantId]
        );
      }
      return;
    }

    // UPSERT operasyonu
    const data = JSON.parse(ev.payloadJson);

    if (ev.entityType === 'PRODUCT') {
      await client.query(
        `INSERT INTO products 
          (id, tenant_id, barcode, name, price_cents, cost_price_cents, vat_rate, stock_quantity, is_active, is_deleted, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, NOW())
         ON CONFLICT (id) DO UPDATE SET
          barcode = EXCLUDED.barcode,
          name = EXCLUDED.name,
          price_cents = EXCLUDED.price_cents,
          cost_price_cents = EXCLUDED.cost_price_cents,
          vat_rate = EXCLUDED.vat_rate,
          stock_quantity = EXCLUDED.stock_quantity,
          is_active = EXCLUDED.is_active,
          is_deleted = EXCLUDED.is_deleted,
          updated_at = NOW()`,
        [
          data.id,
          tenantId,
          data.barcode,
          data.name,
          data.price_cents,
          data.cost_price_cents ?? null,
          data.vat_rate ?? 20,
          data.stock_quantity ?? 0,
          data.is_active ?? true,
          data.is_deleted ?? false,
        ]
      );
    } else if (ev.entityType === 'CUSTOMER') {
      await client.query(
        `INSERT INTO customers 
          (id, tenant_id, name, phone, balance_cents, credit_limit_cents, is_active, is_deleted, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8, NOW())
         ON CONFLICT (id) DO UPDATE SET
          name = EXCLUDED.name,
          phone = EXCLUDED.phone,
          balance_cents = EXCLUDED.balance_cents,
          credit_limit_cents = EXCLUDED.credit_limit_cents,
          is_active = EXCLUDED.is_active,
          is_deleted = EXCLUDED.is_deleted,
          updated_at = NOW()`,
        [
          data.id,
          tenantId,
          data.name,
          data.phone ?? null,
          data.balance_cents ?? 0,
          data.credit_limit_cents ?? 0,
          data.is_active ?? true,
          data.is_deleted ?? false,
        ]
      );
    }
  }
}
