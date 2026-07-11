import { Router, Request, Response } from 'express';
import { pgPool } from '../../config/database';
import { AuthService } from '../auth/auth.service';
import { RealtimeBroadcastService } from '../realtime/broadcast.service';

import { syncLimiter } from '../../middleware/rate-limit.middleware';

const router = Router();
router.use(syncLimiter);

// Middleware to enforce authentication on sync endpoints
const authMiddleware = async (req: Request, res: Response, next: any) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ error: 'unauthorized', message: 'Bearer token gereklidir.' });
  }
  
  const token = authHeader.split(' ')[1];
  try {
    const isBlacklisted = await AuthService.isTokenBlacklisted(token);
    if (isBlacklisted) {
      return res.status(401).json({ error: 'unauthorized', message: 'Token geçersiz kılınmıştır.' });
    }

    const decoded = AuthService.verifyAccessToken(token);
    (req as any).user = decoded;
    next();
  } catch (err) {
    return res.status(401).json({ error: 'unauthorized', message: 'Geçersiz veya süresi dolmuş token.' });
  }
};

router.use(authMiddleware);

router.post('/push', async (req: Request, res: Response) => {
  const user = (req as any).user;
  const { items } = req.body;

  if (!items || !Array.isArray(items)) {
    return res.status(400).json({ error: 'invalid_payload', message: 'Kuyruk elemanları dizisi (items) zorunludur.' });
  }

  let syncedCount = 0;
  const errors: any[] = [];
  const client = await pgPool.connect();

  try {
    for (const item of items) {
      const { id, entity_type, entity_id, payload } = item;
      if (!entity_type || !entity_id || !payload) {
        errors.push({ id, error: 'missing_fields' });
        continue;
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

          // Insert sale items
          if (payload.items && Array.isArray(payload.items)) {
            for (const itemObj of payload.items) {
              const qty = parseFloat(itemObj.quantity) || 0.0;
              const price = parseFloat(itemObj.unit_price) || 0.0;
              await client.query(
                `INSERT INTO sale_items (id, sale_id, product_id, quantity, unit_price, subtotal)
                 VALUES ($1, $2, $3, $4, $5, $6)
                 ON CONFLICT (id) DO NOTHING`,
                [
                  itemObj.id || `item-${payload.id}-${itemObj.product_id}`,
                  payload.id,
                  itemObj.product_id,
                  qty,
                  price,
                  qty * price
                ]
              );
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
        await client.query('ROLLBACK');
        console.error(`Error syncing item ${id}:`, err);
        errors.push({ id, error: err.message || 'database_error' });
      }
    }

    return res.json({
      synced_count: syncedCount,
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

  try {
    // Gather modified products since last timestamp
    const prodRes = await pgPool.query(
      'SELECT * FROM products WHERE company_id = $1 AND updated_at > $2',
      [user.company_id, lastTime]
    );

    // Gather modified customers since last timestamp
    const custRes = await pgPool.query(
      'SELECT * FROM customers WHERE company_id = $1 AND updated_at > $2',
      [user.company_id, lastTime]
    );

    // Gather modified sales since last timestamp
    const salesRes = await pgPool.query(
      'SELECT * FROM sales WHERE company_id = $1 AND updated_at > $2',
      [user.company_id, lastTime]
    );

    // Gather modified financial transactions since last timestamp
    const transRes = await pgPool.query(
      'SELECT * FROM financial_transactions WHERE company_id = $1 AND updated_at > $2',
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

    // Sort by timestamp ascending to preserve order
    transactions.sort((a, b) => a.timestamp - b.timestamp);

    const nextTimestamp = transactions.length > 0 ? transactions[transactions.length - 1].timestamp : lastTime.getTime();

    return res.json({
      transactions,
      last_timestamp: nextTimestamp
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
    console.error(`Bootstrap sync error on ${module}:`, err);
    return res.status(500).json({ error: 'server_error', message: `Bootstrap veri yükleme hatası: ${module}` });
  }
});

export default router;
