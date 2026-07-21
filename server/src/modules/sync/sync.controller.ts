import { Router, Request, Response } from 'express';
import crypto from 'crypto';
import { pgPool } from '../../config/database';
import { RealtimeBroadcastService } from '../realtime/broadcast.service';
import { syncLimiter } from '../../middleware/rate-limit.middleware';
import { authenticateUser } from '../../middleware/auth.middleware';
import jwt from 'jsonwebtoken';

const router = Router();
router.use(syncLimiter);

router.use(authenticateUser);

router.get('/health', async (_req: Request, res: Response) => {
  try {
    await pgPool.query('SELECT 1');
    return res.json({ status: 'healthy' });
  } catch (_err) {
    return res.status(503).json({ status: 'unhealthy' });
  }
});

router.post('/push', async (req: Request, res: Response) => {
  const user = (req as any).user;
  const { items } = req.body;

  if (!items || !Array.isArray(items)) {
    return res.status(400).json({ error: 'invalid_payload', message: 'Kuyruk elemanları dizisi (items) zorunludur.' });
  }

  let syncedCount = 0;
  const errors: any[] = [];
  const processed: string[] = [];
  console.log('[DEBUG] Trying to connect to pgPool...');
  const client = await pgPool.connect();
  console.log('[DEBUG] Connected to pgPool.');

  try {
    // Determine Grace Expiry Status
    const subRes = await client.query(`
      SELECT s.status, s.trial_ends_at, s.current_period_end, s.grace_hours_override, p.offline_grace_hours
      FROM subscriptions s
      JOIN plans p ON s.plan_id = p.id
      WHERE s.company_id = $1 LIMIT 1
    `, [user.company_id]);

    let isGraceExpired = false;
    let expirationTimeUtc = new Date(0);

    if (subRes.rows.length > 0) {
      const sub = subRes.rows[0];
      if (sub.status === 'canceled' || sub.status === 'revoked') {
        return res.status(402).json({ error: 'COMPANY402', message: 'Aboneliğiniz iptal edilmiştir.' });
      }
      
      const graceHours = sub.grace_hours_override ?? sub.offline_grace_hours ?? 72;
      const baseExpiration = sub.status === 'trialing' ? sub.trial_ends_at : sub.current_period_end;
      
      if (baseExpiration) {
        expirationTimeUtc = new Date(baseExpiration.getTime() + graceHours * 3600 * 1000);
        if (new Date() > expirationTimeUtc) {
          isGraceExpired = true;
        }
      }
    } else {
         console.log('[DEBUG] No subscription found.');
    }

    console.log(`[DEBUG] Processing ${items.length} items...`);
    for (const item of items) {
      console.log(`[DEBUG] Processing item ${item.id}`);
      const { id, entity_type, entity_id, payload } = item;
      if (!id || !entity_type || !entity_id || !payload) {
        errors.push({ id, error: 'missing_fields' });
        continue;
      }
      if (!['sale', 'customer', 'product', 'financial_transaction'].includes(entity_type)) {
        errors.push({ id, error: 'unsupported_entity_type' });
        continue;
      }
      const itemTime = payload.created_at || payload.date || new Date().toISOString();
      const maxSkewMsGlobal = 60 * 60 * 1000;
      if (new Date(itemTime).getTime() > Date.now() + maxSkewMsGlobal) {
         errors.push({ id, error: 'clock_spoofed', message: 'İşlem tarihi gelecekte olamaz (clock_spoofed sunucu zamanına göre geleceğe dönük).' });
         continue;
      }
      
      // Prevent clock manipulation attacks: if grace expired, only allow valid historical sales
      if (isGraceExpired) {
        const itemTime = payload.created_at || payload.date;
        if (!itemTime || new Date(itemTime) > expirationTimeUtc) {
          errors.push({ id, error: 'grace_expired', message: 'Geçersiz işlem tarihi: Abonelik süresi dışında işlem yapılamaz.' });
          continue;
        }

        // Validate entitlement snapshot to prevent clock spoofing
        const snapshot = payload.entitlement_snapshot;
        if (!snapshot) {
          errors.push({ id, error: 'missing_entitlement_snapshot', message: 'Geçmiş işlem doğrulaması için güvenlik anahtarı eksik (clock_spoofing_prevented).' });
          continue;
        }

        try {
          // Verify JWT without checking expiration (since it was offline)
          const decoded = jwt.verify(snapshot, process.env.JWT_SECRET as string, { ignoreExpiration: true }) as any;
          
          if (!decoded.entitlement_valid_until) {
             errors.push({ id, error: 'invalid_entitlement_snapshot', message: 'Eski güvenlik anahtarı sürümü desteklenmiyor.' });
             continue;
          }

          // The item must have been created AFTER the snapshot was issued
          const iatDate = new Date(decoded.iat * 1000);
          const maxSkewMs = 60 * 60 * 1000; // 1 hour skew tolerance
          if (new Date(itemTime).getTime() < iatDate.getTime() - maxSkewMs) {
             errors.push({ id, error: 'clock_spoofed', message: 'Cihaz saati manipülasyonu tespit edildi (clock_spoofed geçmişe dönük).' });
             continue;
          }

          // The item must have been created BEFORE the entitlement expired (with 1 hour skew tolerance)
          const validUntilMs = decoded.entitlement_valid_until;
          if (new Date(itemTime).getTime() > validUntilMs + maxSkewMs) {
             errors.push({ id, error: 'clock_spoofed', message: 'İşlem tarihi, cihazın yetki süresinin (grace period) dışında (clock_spoofed geleceğe dönük).' });
             continue;
          }
        } catch (err) {
          errors.push({ id, error: 'invalid_entitlement_snapshot', message: 'Geçersiz güvenlik anahtarı.' });
          continue;
        }
      }
      await client.query('BEGIN');
      try {
        // Enforce Multi-tenant RLS context for safety
        await client.query("SELECT set_config('app.current_company_id', $1, true)", [user.company_id]);

        // 1. Insert into sync_queue log
        await client.query(
          `INSERT INTO sync_queue (id, company_id, entity_type, entity_id, payload, status)
           VALUES ($1, $2, $3, $4, $5, 'processed')
           ON CONFLICT (id) DO UPDATE SET status = 'processed'`,
          [id || crypto.randomUUID(), user.company_id, entity_type, entity_id, JSON.stringify(payload)]
        );

        // 2. Process entity updates based on type
        if (entity_type === 'sale') {
          // Idempotency: insert or ignore if exists (same sale ID)
          const saleQuery = `
            INSERT INTO sales (id, company_id, customer_id, total_amount, paid_amount, payment_method, status, created_at, updated_at, idempotency_key, created_by)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, CURRENT_TIMESTAMP, $9, $10)
            ON CONFLICT (id) DO NOTHING
          `;
          await client.query(saleQuery, [
            payload.id,
            user.company_id,
            payload.customer_id || null,
            payload.total_amount || 0.00,
            payload.paid_amount || 0.00,
            payload.payment_method || 'cash',
            payload.status || 'completed',
            payload.created_at ? new Date(payload.created_at) : new Date(),
            payload.id, // Sale ID acts as idempotency key
            user.id
          ]);

          // Insert sale items and update stock if new
          if (payload.items && Array.isArray(payload.items)) {
            for (const itemObj of payload.items) {
              const qty = parseFloat(itemObj.quantity) || 0.0;
              const price = parseFloat(itemObj.unit_price) || 0.0;
              const insertItemRes = await client.query(
                `INSERT INTO sale_items (id, sale_id, product_id, quantity, unit_price, subtotal)
                 VALUES ($1, $2, $3, $4, $5, $6)
                 ON CONFLICT (id) DO NOTHING RETURNING id`,
                [
                  itemObj.id || `item-${payload.id}-${itemObj.product_id}`,
                  payload.id,
                  itemObj.product_id,
                  qty,
                  price,
                  qty * price
                ]
              );
              
              if (insertItemRes.rows.length > 0) {
                // Deduct stock for new sale item
                await client.query(
                  `UPDATE products 
                   SET quantity = quantity - $1, updated_at = CURRENT_TIMESTAMP 
                   WHERE id = $2 AND company_id = $3`,
                  [qty, itemObj.product_id, user.company_id]
                );
              }
            }
          }
        } 
        else if (entity_type === 'customer') {
          const customerQuery = `
            INSERT INTO customers (id, company_id, name, email, phone, balance, credit_limit, status, is_deleted, created_at, updated_at)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, CURRENT_TIMESTAMP, CURRENT_TIMESTAMP)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              email = EXCLUDED.email,
              phone = EXCLUDED.phone,
              balance = EXCLUDED.balance,
              credit_limit = EXCLUDED.credit_limit,
              status = EXCLUDED.status,
              is_deleted = EXCLUDED.is_deleted,
              updated_at = CURRENT_TIMESTAMP
          `;
          await client.query(customerQuery, [
            payload.id,
            user.company_id,
            payload.name,
            payload.email || null,
            payload.phone || null,
            payload.balance || 0.00,
            payload.credit_limit || 0.00,
            payload.status || 'active',
            payload.is_deleted || false
          ]);
        } 
        else if (entity_type === 'product') {
          const productQuery = `
            INSERT INTO products (id, company_id, name, description, price, quantity, category, vat, image_path, status, is_deleted)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
            ON CONFLICT (id) DO UPDATE SET
              name = EXCLUDED.name,
              description = EXCLUDED.description,
              price = EXCLUDED.price,
              quantity = EXCLUDED.quantity,
              category = EXCLUDED.category,
              vat = EXCLUDED.vat,
              image_path = EXCLUDED.image_path,
              status = EXCLUDED.status,
              is_deleted = EXCLUDED.is_deleted,
              updated_at = CURRENT_TIMESTAMP
          `;
          await client.query(productQuery, [
            payload.id,
            user.company_id,
            payload.name,
            payload.description || null,
            payload.price || 0.00,
            payload.quantity || 0,
            payload.category || null,
            payload.vat || 0,
            payload.image_path || null,
            payload.status || 'active',
            payload.is_deleted || false
          ]);
        }
        else if (entity_type === 'financial_transaction') {
          const transQuery = `
            INSERT INTO financial_transactions (id, company_id, type, customer_id, amount, paid_amount, debt_amount, date, reference_id, is_deleted)
            VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
            ON CONFLICT (id) DO UPDATE SET
              type = EXCLUDED.type,
              customer_id = EXCLUDED.customer_id,
              amount = EXCLUDED.amount,
              paid_amount = EXCLUDED.paid_amount,
              debt_amount = EXCLUDED.debt_amount,
              date = EXCLUDED.date,
              reference_id = EXCLUDED.reference_id,
              is_deleted = EXCLUDED.is_deleted,
              updated_at = CURRENT_TIMESTAMP
          `;
          await client.query(transQuery, [
            payload.id,
            user.company_id,
            payload.type,
            payload.customer_id || null,
            payload.amount || 0.00,
            payload.paid_amount || 0.00,
            payload.debt_amount || 0.00,
            payload.date ? new Date(payload.date) : new Date(),
            payload.reference_id || null,
            payload.is_deleted || false
          ]);
        }

        await client.query('COMMIT');
        syncedCount++;
        processed.push(id);

        // Realtime Event Broadcasting
        try {
          if (entity_type === 'sale') {
            await RealtimeBroadcastService.publishEvent(user.company_id, 'OrderCreated', {
              orderId: payload.id,
              totalAmount: parseFloat(payload.total_amount || 0.00),
              paymentMethod: payload.payment_method || 'cash',
              createdAt: payload.created_at || new Date().toISOString(),
            });
            await RealtimeBroadcastService.publishEvent(user.company_id, 'InventoryUpdated', {
              reason: 'sale_sync',
              referenceId: payload.id,
            });
          } else if (entity_type === 'customer') {
            await RealtimeBroadcastService.publishEvent(user.company_id, 'CustomerUpdated', {
              customerId: payload.id,
              name: payload.name,
              balance: parseFloat(payload.balance || 0.00),
              status: payload.status,
            });
          } else if (entity_type === 'product') {
            await RealtimeBroadcastService.publishEvent(user.company_id, 'InventoryUpdated', {
              productId: payload.id,
              name: payload.name,
              quantity: parseInt(payload.quantity || 0, 10),
              price: parseFloat(payload.price || 0.00),
            });
            await RealtimeBroadcastService.publishEvent(user.company_id, 'PriceChanged', {
              productId: payload.id,
              price: parseFloat(payload.price || 0.00),
            });
          } else if (entity_type === 'financial_transaction') {
            await RealtimeBroadcastService.publishEvent(user.company_id, 'PaymentReceived', {
              transactionId: payload.id,
              type: payload.type,
              customerId: payload.customer_id,
              amount: parseFloat(payload.amount || 0.00),
            });
          }
        } catch (wsErr) {
          // Silence ws errors so they do not block standard sync flow
        }
      } catch (err: any) {
        console.log('[DEBUG] Error checking subscription:', err);
        await client.query('ROLLBACK');
        console.error(`Error syncing item ${id}:`, err);
        errors.push({ id, error: err.message || 'database_error' });
      }
    }

    console.log('[DEBUG] Finished processing. Sending response...');
    return res.json({
      synced_count: syncedCount,
      processed,
      errors
    });
  } finally {
    client.release();
  }
});

router.get('/pull', async (req: Request, res: Response) => {
  const user = (req as any).user;
  const lastTimestampStr = req.query.last_timestamp as string;
  const lastTime = lastTimestampStr ? new Date(parseInt(lastTimestampStr, 10)) : new Date(0);
  const cursorType = typeof req.query.last_type === 'string' ? req.query.last_type : '';
  const cursorId = typeof req.query.last_id === 'string' ? req.query.last_id : '';
  const requestedLimit = Number.parseInt(String(req.query.limit || '500'), 10);
  const limit = Math.min(Math.max(Number.isFinite(requestedLimit) ? requestedLimit : 500, 1), 1000);
  const timestampOperator = cursorType || cursorId ? '>=' : '>';

  try {
    const client = await pgPool.connect();
    try {
      const subRes = await client.query(`
        SELECT s.status, s.trial_ends_at, s.current_period_end, s.grace_hours_override, p.offline_grace_hours
        FROM subscriptions s
        JOIN plans p ON s.plan_id = p.id
        WHERE s.company_id = $1 LIMIT 1
      `, [user.company_id]);

      if (subRes.rows.length > 0) {
        console.log('[DEBUG] Subscription found.');
        const sub = subRes.rows[0];
        if (sub.status === 'canceled' || sub.status === 'revoked') {
          return res.status(402).json({ error: 'COMPANY402', message: 'Aboneliğiniz iptal edilmiştir.' });
        }
        
        const graceHours = sub.grace_hours_override ?? sub.offline_grace_hours ?? 72;
        const baseExpiration = sub.status === 'trialing' ? sub.trial_ends_at : sub.current_period_end;
        
        if (baseExpiration) {
          const expirationTimeUtc = new Date(baseExpiration.getTime() + graceHours * 3600 * 1000);
          if (new Date() > expirationTimeUtc) {
            return res.status(402).json({ error: 'grace_expired', message: 'Abonelik süresi dolduğu için veri senkronizasyonu durduruldu.' });
          }
        }
      }
    } finally {
      client.release();
    }

    // Gather modified products since last timestamp
    const prodRes = await pgPool.query(
      `SELECT * FROM products WHERE company_id = $1 AND updated_at ${timestampOperator} $2`,
      [user.company_id, lastTime]
    );

    // Gather modified customers since last timestamp
    const custRes = await pgPool.query(
      `SELECT * FROM customers WHERE company_id = $1 AND updated_at ${timestampOperator} $2`,
      [user.company_id, lastTime]
    );

    // Gather modified sales since last timestamp
    const salesRes = await pgPool.query(
      `SELECT * FROM sales WHERE company_id = $1 AND updated_at ${timestampOperator} $2`,
      [user.company_id, lastTime]
    );

    // Gather modified financial transactions since last timestamp
    const transRes = await pgPool.query(
      `SELECT * FROM financial_transactions WHERE company_id = $1 AND updated_at ${timestampOperator} $2`,
      [user.company_id, lastTime]
    );

    const transactions: any[] = [];

    for (const row of prodRes.rows) {
      transactions.push({
        id: row.id,
        type: 'product',
        payload: row,
        timestamp: new Date(row.updated_at).getTime()
      });
    }

    for (const row of custRes.rows) {
      transactions.push({
        id: row.id,
        type: 'customer',
        payload: row,
        timestamp: new Date(row.updated_at).getTime()
      });
    }

    for (const row of transRes.rows) {
      transactions.push({
        id: row.id,
        type: 'financial_transaction',
        payload: row,
        timestamp: new Date(row.updated_at).getTime()
      });
    }

    // FIX [AUDIT-005]: N+1 sorunu giderildi — tüm sale_items tek sorguda çekiliyor
    const saleIds = salesRes.rows.map((r: any) => r.id);
    const itemsBySaleId: Record<string, any[]> = {};
    if (saleIds.length > 0) {
      const allItemsRes = await pgPool.query(
        'SELECT * FROM sale_items WHERE sale_id = ANY($1::text[])',
        [saleIds]
      );
      for (const item of allItemsRes.rows) {
        if (!itemsBySaleId[item.sale_id]) itemsBySaleId[item.sale_id] = [];
        itemsBySaleId[item.sale_id].push(item);
      }
    }

    for (const row of salesRes.rows) {
      row.items = itemsBySaleId[row.id] || [];
      transactions.push({
        id: row.id,
        type: 'sale',
        payload: row,
        timestamp: new Date(row.updated_at).getTime()
      });
    }

    // Stable composite cursor prevents records sharing the same millisecond from
    // being skipped between pages.
    transactions.sort((a, b) =>
      a.timestamp - b.timestamp || a.type.localeCompare(b.type) || String(a.id).localeCompare(String(b.id))
    );
    const filtered = transactions.filter((item) => {
      if (item.timestamp > lastTime.getTime()) return true;
      if (item.timestamp < lastTime.getTime()) return false;
      if (!cursorType && !cursorId) return false;
      return item.type.localeCompare(cursorType) > 0 ||
        (item.type === cursorType && String(item.id).localeCompare(cursorId) > 0);
    });
    const page = filtered.slice(0, limit);
    const hasMore = filtered.length > page.length;
    const lastItem = page.length > 0 ? page[page.length - 1] : null;
    const nextTimestamp = lastItem?.timestamp ?? lastTime.getTime();

    return res.json({
      transactions: page,
      last_timestamp: nextTimestamp,
      last_type: lastItem?.type ?? cursorType,
      last_id: lastItem?.id ?? cursorId,
      has_more: hasMore
    });
  } catch (err) {
    console.error('Pull sync error:', err);
    return res.status(500).json({ error: 'server_error', message: 'Senkronizasyon çekme işleminde hata oluştu.' });
  }
});

// --- Sprint 2: Automated Bootstrap Sync Endpoint ---
router.get('/bootstrap/:module', async (req: Request, res: Response) => {
  const user = (req as any).user;
  const { module } = req.params;

  try {
    let data: any = {};
    if (module === 'company') {
      const resDb = await pgPool.query('SELECT * FROM companies WHERE id = $1', [user.company_id]);
      data = resDb.rows[0] || {};
    } 
    else if (module === 'stores') {
      const resDb = await pgPool.query('SELECT * FROM stores WHERE company_id = $1', [user.company_id]);
      data = resDb.rows;
    }
    else if (module === 'users') {
      // FIX [AUDIT-001]: users tablosunda 'role' kolonu yok — RBAC user_roles/roles tablosunda
      // Role bilgisi LEFT JOIN ile alınıyor; rol atanmamış kullanıcılar için 'cashier' varsayılan
      const resDb = await pgPool.query(
        `SELECT u.id, u.name, u.email, u.is_active,
                COALESCE(r.name, 'cashier') AS role
         FROM users u
         LEFT JOIN user_roles ur ON u.id = ur.user_id
         LEFT JOIN roles r ON ur.role_id = r.id
         WHERE u.company_id = $1`,
        [user.company_id]
      );
      data = resDb.rows;
    }
    else if (module === 'categories') {
      const resDb = await pgPool.query('SELECT DISTINCT category FROM products WHERE company_id = $1', [user.company_id]);
      data = resDb.rows.map((r: any) => r.category).filter(Boolean);
    }
    else if (module === 'products') {
      const resDb = await pgPool.query('SELECT * FROM products WHERE company_id = $1 AND is_deleted = false', [user.company_id]);
      data = resDb.rows;
    }
    else if (module === 'customers') {
      const resDb = await pgPool.query('SELECT * FROM customers WHERE company_id = $1 AND is_deleted = false', [user.company_id]);
      data = resDb.rows;
    }
    else if (module === 'payment-types') {
      data = ['cash', 'credit_card', 'gift_card', 'bank_transfer'];
    }
    else if (module === 'tax-rates') {
      data = [1, 8, 10, 18, 20];
    }
    else if (module === 'settings') {
      // FIX [AUDIT-002 extended]: system_settings tablosunda company_id kolonu yok
      // Global ayarlar key/value çiftleri olarak tutulur, tümü döndürülür
      const resDb = await pgPool.query('SELECT key, value FROM system_settings');
      const settingsMap: Record<string, string> = {};
      resDb.rows.forEach((r: any) => { settingsMap[r.key] = r.value; });
      data = settingsMap;
    }
    else if (module === 'printer-config') {
      data = { printer_type: 'thermal', paper_width: 80, auto_print: true };
    }
    else if (module === 'license-config') {
      const resDb = await pgPool.query(
        "SELECT id, plan_id as tier, status, valid_until as expires_at, license_key, device_limit as allowed_devices_count FROM license_entitlements WHERE company_id = $1 AND status IN ('trial', 'active') ORDER BY valid_until DESC LIMIT 1",
        [user.company_id]
      );
      data = resDb.rows[0] || {};
    }
    else {
      return res.status(400).json({ error: 'invalid_module', message: 'Geçersiz bootstrap modülü.' });
    }

    return res.json({ module, data });
  } catch (err: any) {
    console.error(`[SYNC] Bulk push failed: ${err.message}`);
    return res.status(500).json({ error: 'server_error', message: `Bootstrap veri yükleme hatası: ${module}` });
  }
});

export default router;
