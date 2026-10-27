// core_next/client_core/lib/infrastructure/sync/sync_v4_pull_ingestion_service.dart

import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import '../../domain/models/sync_dtos.dart';
import '../database/app_database.dart';

/// Pull Ingestion Sonuç Özeti
class PullIngestionResult {
  final int totalChanges;
  final int productsApplied;
  final int customersApplied;
  final int salesApplied;
  final int refundsApplied;
  final int otherApplied;
  final int skippedDueToPendingLocal;
  final int newCursor;
  final bool isSuccess;
  final String? error;

  const PullIngestionResult({
    required this.totalChanges,
    this.productsApplied = 0,
    this.customersApplied = 0,
    this.salesApplied = 0,
    this.refundsApplied = 0,
    this.otherApplied = 0,
    this.skippedDueToPendingLocal = 0,
    required this.newCursor,
    this.isSuccess = true,
    this.error,
  });
}

/// Sunucudan indirilen Sync V4 değişikliklerini yerel SQLite veritabanına uygulayan servis.
/// 
/// KRİTİK GÜVENLİK VE BÜTÜNLÜK KURALLARI:
/// 1. Atomik Cursor İlerlemesi: Cursor, yalnızca tüm değişiklikler yerel veritabanına
///    başarıyla yazıldıktan sonra TEK BİR ACID transaction içinde güncellenir.
/// 2. Yerel Değişiklik Korunması: Yerelde henüz push edilmemiş (`PENDING` / `TRANSIENT_ERROR`)
///    mutasyonu olan varlıkların üzerine sessizce yazılmaz (LWW koruması).
/// 3. İdempotency: Aynı sayfa tekrar indirildiğinde mükerrer stok/bakiye değişimi olmaz.
/// 4. Tombstone Yönetimi: Silinen kayıtlar `is_deleted = 1` olarak işaretlenir.
/// 5. Çok Kasalı Stok Yakınsaması: Başka kasaların yaptığı satış ve iadeler atomik olarak
///    yerel SQLite stoklarına yansıtılır; yerel kasanın kendi satışları mükerrer düşülmez.
class SyncV4PullIngestionService {
  final CoreAppDatabase db;
  final String? localDeviceId;

  const SyncV4PullIngestionService(this.db, {this.localDeviceId});

  /// Son kaydedilmiş pull cursor'ını okur
  Future<int> getSavedCursor([DatabaseExecutor? executor]) async {
    final exec = executor ?? db.db;
    final rows = await exec.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['sync_pull_cursor'],
    );
    if (rows.isEmpty) return 0;
    return int.tryParse(rows.first['value']?.toString() ?? '0') ?? 0;
  }

  /// Bootstrap anlık görüntüsünü yerel veritabanına uygular
  Future<PullIngestionResult> ingestBootstrap(SyncBootstrapResponseDto dto) {
    return _applyChanges(
      changes: dto.changes,
      nextCursor: dto.nextCursor,
      isBootstrap: true,
    );
  }

  /// Artımlı Pull değişikliklerini yerel veritabanına uygular
  Future<PullIngestionResult> ingestPull(SyncPullResponseDto dto) {
    return _applyChanges(
      changes: dto.changes,
      nextCursor: dto.nextCursor,
      isBootstrap: false,
    );
  }

  Future<PullIngestionResult> _applyChanges({
    required List<SyncPullChange> changes,
    required int nextCursor,
    required bool isBootstrap,
  }) async {
    if (changes.isEmpty) {
      final currentCursor = await getSavedCursor();
      final effectiveCursor = (!isBootstrap && nextCursor < currentCursor) ? currentCursor : nextCursor;
      // Değişiklik yoksa sadece cursor'ı kaydet
      await db.transaction((txn) async {
        await _saveCursor(txn, effectiveCursor);
      });
      return PullIngestionResult(
        totalChanges: 0,
        newCursor: effectiveCursor,
      );
    }

    // Kimliğin null, boş veya geçersiz olduğu durumda yabancı cihaz varsayımına düşülmesini engelle.
    final effectiveDeviceId = localDeviceId?.trim();
    final hasDeviceOriginDependentChanges = changes.any((c) {
      final t = c.entityType.toLowerCase();
      return t == 'sale' || t == 'refund';
    });

    if (hasDeviceOriginDependentChanges && (effectiveDeviceId == null || effectiveDeviceId.isEmpty)) {
      throw StateError(
        'SyncV4PullIngestionService: Cihaz kimliği (localDeviceId) eksik veya geçersiz. '
        'Satış ve iade olayları yabancı cihaz varsayımıyla güvenli olmayan biçimde işlenemez (unidentified_local_device).',
      );
    }

    // 1. Yerelde henüz senkronize edilmemiş (PENDING/TRANSIENT) varlıkların kimliklerini bul
    final pendingLocalRows = await db.query(
      'sync_events',
      columns: ['entity_type', 'entity_id'],
      where: "sync_state IN ('PENDING', 'TRANSIENT_ERROR')",
    );
    final pendingSet = pendingLocalRows
        .map((r) => '${r['entity_type']}:${r['entity_id']}'.toLowerCase())
        .toSet();

    return await db.transaction<PullIngestionResult>((txn) async {
      // Çok kasalı idempotency ve hareket tablosunun varlığını garanti et
      await txn.execute('''
        CREATE TABLE IF NOT EXISTS sync_applied_events (
          id TEXT PRIMARY KEY NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          revision INTEGER NOT NULL DEFAULT 0,
          device_id TEXT,
          product_id TEXT,
          quantity_delta INTEGER NOT NULL DEFAULT 0,
          applied_at INTEGER NOT NULL
        );
      ''');
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_applied_entity ON sync_applied_events (entity_type, entity_id);',
      );
      await txn.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_applied_product_rev ON sync_applied_events (product_id, revision);',
      );

      int prodCount = 0;
      int custCount = 0;
      int salesCount = 0;
      int refundsCount = 0;
      int otherCount = 0;
      int skippedCount = 0;

      for (final change in changes) {
        final key = '${change.entityType}:${change.entityId}'.toLowerCase();

        // Kural: Doğrudan aynı varlık tipinde yerel bekleyen değişiklik varsa üzerine yazma
        if (pendingSet.contains(key)) {
          skippedCount++;
          continue;
        }

        final isDeleted = change.operation == 'DELETE' ||
            change.payload['is_deleted'] == true ||
            change.payload['is_deleted'] == 1;

        final entityType = change.entityType.toLowerCase();
        if (entityType == 'product') {
          await _ingestProduct(txn, change, isDeleted);
          prodCount++;
        } else if (entityType == 'customer') {
          await _ingestCustomer(txn, change, isDeleted);
          custCount++;
        } else if (entityType == 'sale') {
          await _ingestSale(txn, change);
          salesCount++;
        } else if (entityType == 'refund') {
          await _ingestRefund(txn, change);
          refundsCount++;
        } else {
          otherCount++;
        }

        // Çakışma Masası Rebase Garantisi (B5): Eğer bu varlık için bekleyen bir CONFLICT kaydı varsa,
        // sunucunun güncel revizyonu ile rebase edilerek kuyruğa (PENDING) geri kazandırılır.
        await txn.update(
          'sync_events',
          {
            'sync_state': 'PENDING',
            'base_revision': change.revision,
            'attempts': 0,
            'last_error': null,
          },
          where: "entity_type = ? AND entity_id = ? AND sync_state = 'CONFLICT'",
          whereArgs: [change.entityType, change.entityId],
        );
      }

      final currentCursor = await getSavedCursor(txn);
      final effectiveCursor = (!isBootstrap && nextCursor < currentCursor) ? currentCursor : nextCursor;

      // Kural: Cursor yalnızca tüm veriler kalıcılaştırıldıktan sonra aynı transaction'da kaydedilir!
      await _saveCursor(txn, effectiveCursor);

      return PullIngestionResult(
        totalChanges: changes.length,
        productsApplied: prodCount,
        customersApplied: custCount,
        salesApplied: salesCount,
        refundsApplied: refundsCount,
        otherApplied: otherCount,
        skippedDueToPendingLocal: skippedCount,
        newCursor: effectiveCursor,
      );
    });
  }

  Future<void> _ingestProduct(
    Transaction txn,
    SyncPullChange change,
    bool isDeleted,
  ) async {
    final payload = change.payload;
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await txn.query(
      'products',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [change.entityId],
      limit: 1,
    );

    if (isDeleted) {
      if (existing.isNotEmpty) {
        await txn.update(
          'products',
          {
            'is_deleted': 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [change.entityId],
        );
      }
      return;
    }

    final int priceCents;
    if (payload['price_cents'] != null) {
      priceCents = (payload['price_cents'] as num).toInt();
    } else if (payload['price'] != null) {
      priceCents = ((payload['price'] as num).toDouble() * 100).round();
    } else {
      priceCents = 0;
    }

    final int? costPriceCents;
    if (payload['cost_price_cents'] != null) {
      costPriceCents = (payload['cost_price_cents'] as num).toInt();
    } else if (payload['cost_price'] != null) {
      costPriceCents = ((payload['cost_price'] as num).toDouble() * 100).round();
    } else {
      costPriceCents = null;
    }

    final barcode = payload['barcode']?.toString() ?? change.entityId;
    final name = payload['name']?.toString() ?? 'Ürün ${change.entityId}';
    final vatRate = (payload['vat_rate'] as num?)?.toInt() ?? 20;
    final unit = payload['unit']?.toString() ?? 'piece';
    final saleType = payload['sale_type']?.toString() ?? ((unit == 'kg' || unit == 'gram') ? 'weighed' : 'piece');
    final minimumWeightGrams = (payload['minimum_weight_grams'] as num?)?.toInt() ?? 20;
    final rawRemoteStock = (payload['stock_quantity'] as num?)?.toDouble() ?? ((payload['quantity'] as num?)?.toDouble() ?? 0.0);
    final isActive = (payload['is_active'] == false || payload['is_active'] == 0) ? 0 : 1;

    // Çevrimdışı ve henüz bu snapshot'a yansımamış satışların miktarını hesapla
    final unreflectedSold = await _calculateUnreflectedSoldQty(
      txn,
      change.entityId,
      change.revision,
      change.createdAt,
    );
    final effectiveStock = rawRemoteStock - unreflectedSold;

    final productMap = {
      'barcode': barcode,
      'name': name,
      'category_id': payload['category_id']?.toString(),
      'price_cents': priceCents,
      'cost_price_cents': costPriceCents,
      'vat_rate': vatRate,
      'unit': unit,
      'sale_type': saleType,
      'minimum_weight_grams': minimumWeightGrams,
      'stock_quantity': effectiveStock,
      'critical_threshold': (payload['critical_threshold'] as num?)?.toDouble() ?? 5.0,
      'image_url': payload['image_url']?.toString(),
      'is_active': isActive,
      'is_deleted': 0,
      'updated_at': now,
    };

    if (existing.isNotEmpty) {
      // ON DELETE RESTRICT FK ihlalini önlemek için REPLACE yerine UPDATE kullanılır
      await txn.update(
        'products',
        productMap,
        where: 'id = ?',
        whereArgs: [change.entityId],
      );
    } else {
      await txn.insert(
        'products',
        {
          'id': change.entityId,
          ...productMap,
        },
      );
    }
  }

  Future<double> _calculateUnreflectedSoldQty(
    Transaction txn,
    String productId,
    int changeRevision,
    String changeCreatedAt,
  ) async {
    final saleItemRows = await txn.rawQuery('''
      SELECT si.quantity, p.sale_type, p.unit, se.sync_state, se.base_revision, se.client_timestamp
      FROM sale_items si
      JOIN products p ON p.id = si.product_id
      JOIN sync_events se ON se.entity_id = si.sale_id AND se.entity_type = 'sale'
      WHERE si.product_id = ?
    ''', [productId]);

    double unreflectedQty = 0.0;
    final changeTs = DateTime.tryParse(changeCreatedAt)?.millisecondsSinceEpoch ?? 0;

    for (final row in saleItemRows) {
      final state = row['sync_state'] as String;
      final rawQty = (row['quantity'] as num).toDouble();
      final isWeighed = (row['sale_type'] == 'weighed') || (row['unit'] == 'kg' || row['unit'] == 'gram');
      final qty = isWeighed ? (rawQty / 1000.0) : rawQty;
      final baseRev = (row['base_revision'] as num?)?.toInt() ?? 0;
      final clientTs = (row['client_timestamp'] as num?)?.toInt() ?? 0;

      if (state == 'PENDING' || state == 'TRANSIENT_ERROR') {
        unreflectedQty += qty;
      } else if (state == 'SYNCED' || state == 'COMPLETED') {
        final isRevOlder = changeRevision > 0 && baseRev > 0 && changeRevision < baseRev;
        final isTsOlder = (changeRevision == 0 || baseRev == 0) && changeTs > 0 && clientTs > 0 && changeTs < clientTs;
        if (isRevOlder || isTsOlder) {
          unreflectedQty += qty;
        }
      }
    }

    // Bu snapshot revizyonundan SONRA uygulanmış olan diğer kasaların hareket delta'ları
    // (Test H: Eski snapshot'ın yeni hareketleri ezmesini engeller!)
    if (changeRevision > 0) {
      final postSnapApplied = await txn.rawQuery('''
        SELECT COALESCE(SUM(quantity_delta), 0) AS post_delta
        FROM sync_applied_events
        WHERE product_id = ? AND revision > ?
      ''', [productId, changeRevision]);

      if (postSnapApplied.isNotEmpty) {
        final postDelta = (postSnapApplied.first['post_delta'] as num?)?.toDouble() ?? 0.0;
        unreflectedQty -= postDelta;
      }
    }

    return unreflectedQty;
  }

  Future<void> _ingestSale(Transaction txn, SyncPullChange change) async {
    final eventKey = 'sale:${change.entityId}';
    final alreadyApplied = await txn.query(
      'sync_applied_events',
      where: 'id = ?',
      whereArgs: [eventKey],
      limit: 1,
    );
    if (alreadyApplied.isNotEmpty) {
      // Zaten uygulandı (Idempotent no-op)
      return;
    }

    final effectiveDeviceId = localDeviceId?.trim();
    final isDeviceLocal = effectiveDeviceId != null &&
        effectiveDeviceId.isNotEmpty &&
        change.deviceId.isNotEmpty &&
        change.deviceId == effectiveDeviceId;

    final payload = change.payload;
    final payloadReceiptNo = payload['receipt_no']?.toString();
    final payloadIdempKey = payload['idempotency_key']?.toString();

    // İkincil savunma hattı: Cihaz kimliği belirsiz veya farklı olsa dahi,
    // bu satış yerel sales tablosunda kayıtlı ise yerel kökenlidir (çift stok düşümü engellenir).
    // Güvenlik kuralı (Stage 10.7.2): receipt_no kasalar arasında bağımsız bir sayaçtır;
    // sunucu şemasında tutulmaz ve küresel tekillik taşımaz. Yalnızca receipt_no eşleşmesine dayanarak
    // yabancı bir satış yerel kabul edilemez (false positive / yabancı stok atlama riski).
    // Eşleşme değişmez satış UUID'si (id = change.entityId) veya fiş numarasından farklı,
    // açıkça atanmış tekil bir idempotency_key üzerinden yapılmalıdır.
    final bool isIdempKeyDistinguishable = payloadIdempKey != null &&
        payloadIdempKey.trim().isNotEmpty &&
        payloadIdempKey != payloadReceiptNo;

    final existingLocalSales = await txn.rawQuery('''
      SELECT id FROM sales 
      WHERE id = ? 
         OR (? = 1 AND idempotency_key IS NOT NULL AND idempotency_key = ?)
      LIMIT 1
    ''', [
      change.entityId,
      isIdempKeyDistinguishable ? 1 : 0,
      payloadIdempKey ?? '',
    ]);

    final isLocalOrigin = isDeviceLocal || existingLocalSales.isNotEmpty;

    final now = DateTime.now().millisecondsSinceEpoch;
    final rawItems = payload['items'];
    final items = rawItems is List ? rawItems : const [];

    if (!isLocalOrigin) {
      // Başka kasanın satışı: yerel SQLite stoklarını atomik olarak düşür
      for (int i = 0; i < items.length; i++) {
        final rawItem = items[i];
        if (rawItem is! Map) continue;
        final productId = rawItem['product_id']?.toString();
        var qty = (rawItem['quantity'] as num?)?.toDouble() ?? 0.0;
        if (productId == null || qty <= 0.0001) continue;

        final prod = await txn.query(
          'products',
          columns: ['id', 'unit', 'sale_type'],
          where: 'id = ?',
          whereArgs: [productId],
          limit: 1,
        );
        if (prod.isNotEmpty) {
          final isWeighed = (prod.first['sale_type'] == 'weighed') ||
              (prod.first['unit'] == 'kg' || prod.first['unit'] == 'gram');
          if (isWeighed && qty >= 10 && rawItem['is_weighed'] != true) {
            final unitPrice = (rawItem['unit_price'] as num?)?.toDouble() ?? 0.0;
            final subtotal = (rawItem['subtotal'] as num?)?.toDouble() ?? 0.0;
            if (subtotal > 0 && ((qty * unitPrice / 1000.0) - subtotal).abs() <= 0.05) {
              qty = qty / 1000.0;
            }
          }

          await txn.rawUpdate(
            'UPDATE products SET stock_quantity = stock_quantity - ?, updated_at = ? WHERE id = ?',
            [qty, now, productId],
          );
        }

        // Stok hareketi kaydı
        await txn.insert('sync_applied_events', {
          'id': '$eventKey:$productId:$i',
          'entity_type': 'sale',
          'entity_id': change.entityId,
          'revision': change.revision,
          'device_id': change.deviceId,
          'product_id': productId,
          'quantity_delta': -qty,
          'applied_at': now,
        });
      }
    }

    // Ana olay idempotency kaydı
    await txn.insert('sync_applied_events', {
      'id': eventKey,
      'entity_type': 'sale',
      'entity_id': change.entityId,
      'revision': change.revision,
      'device_id': change.deviceId,
      'product_id': null,
      'quantity_delta': 0,
      'applied_at': now,
    });
  }

  Future<void> _ingestRefund(Transaction txn, SyncPullChange change) async {
    final eventKey = 'refund:${change.entityId}';
    final alreadyApplied = await txn.query(
      'sync_applied_events',
      where: 'id = ?',
      whereArgs: [eventKey],
      limit: 1,
    );
    if (alreadyApplied.isNotEmpty) {
      // Zaten uygulandı (Idempotent no-op)
      return;
    }

    final effectiveDeviceId = localDeviceId?.trim();
    final isDeviceLocal = effectiveDeviceId != null &&
        effectiveDeviceId.isNotEmpty &&
        change.deviceId.isNotEmpty &&
        change.deviceId == effectiveDeviceId;

    final payload = change.payload;
    final payloadReceiptNo = payload['receipt_no']?.toString();
    final payloadIdempKey = payload['idempotency_key']?.toString();

    // İkincil savunma hattı: Bu iade yerel veritabanında zaten kayıtlı ise yerel kökenlidir
    // Güvenlik kuralı (Stage 10.7.2): receipt_no kasalar arasında çakışabilir;
    // eşleşme yalnızca değişmez UUID veya ayırt edilebilir idempotency_key ile aranır.
    final bool isIdempKeyDistinguishable = payloadIdempKey != null &&
        payloadIdempKey.trim().isNotEmpty &&
        payloadIdempKey != payloadReceiptNo;

    final existingLocalRefunds = await txn.rawQuery('''
      SELECT id FROM sales 
      WHERE status = 'REFUND' AND (
        id = ? 
        OR (? = 1 AND idempotency_key IS NOT NULL AND idempotency_key = ?)
      )
      LIMIT 1
    ''', [
      change.entityId,
      isIdempKeyDistinguishable ? 1 : 0,
      payloadIdempKey ?? '',
    ]);

    final isLocalOrigin = isDeviceLocal || existingLocalRefunds.isNotEmpty;

    final now = DateTime.now().millisecondsSinceEpoch;
    final rawItems = payload['items'];
    final items = rawItems is List ? rawItems : const [];

    if (!isLocalOrigin) {
      // Başka kasanın iadesi: yerel SQLite stoklarını atomik olarak artır
      for (int i = 0; i < items.length; i++) {
        final rawItem = items[i];
        if (rawItem is! Map) continue;
        String? productId = rawItem['product_id']?.toString();
        var qty = (rawItem['quantity'] as num?)?.toDouble() ?? 0.0;
        if (qty <= 0.0001) continue;

        if (productId == null || productId.isEmpty) {
          final saleItemId = rawItem['sale_item_id']?.toString();
          if (saleItemId != null && saleItemId.isNotEmpty) {
            final si = await txn.query(
              'sale_items',
              columns: ['product_id'],
              where: 'id = ?',
              whereArgs: [saleItemId],
              limit: 1,
            );
            if (si.isNotEmpty) {
              productId = si.first['product_id']?.toString();
            }
          }
        }

        if (productId != null && productId.isNotEmpty) {
          final prod = await txn.query(
            'products',
            columns: ['id', 'unit', 'sale_type'],
            where: 'id = ?',
            whereArgs: [productId],
            limit: 1,
          );
          if (prod.isNotEmpty) {
            final isWeighed = (prod.first['sale_type'] == 'weighed') ||
                (prod.first['unit'] == 'kg' || prod.first['unit'] == 'gram');
            if (isWeighed && qty >= 10 && rawItem['is_weighed'] != true) {
              final unitPrice = (rawItem['unit_price'] as num?)?.toDouble() ?? 0.0;
              final subtotal = (rawItem['subtotal'] as num?)?.toDouble() ?? 0.0;
              if (subtotal > 0 && ((qty * unitPrice / 1000.0) - subtotal).abs() <= 0.05) {
                qty = qty / 1000.0;
              }
            }

            await txn.rawUpdate(
              'UPDATE products SET stock_quantity = stock_quantity + ?, updated_at = ? WHERE id = ?',
              [qty, now, productId],
            );
          }

          // Stok hareketi kaydı
          await txn.insert('sync_applied_events', {
            'id': '$eventKey:$productId:$i',
            'entity_type': 'refund',
            'entity_id': change.entityId,
            'revision': change.revision,
            'device_id': change.deviceId,
            'product_id': productId,
            'quantity_delta': qty,
            'applied_at': now,
          });
        }
      }
    }

    // Ana olay idempotency kaydı
    await txn.insert('sync_applied_events', {
      'id': eventKey,
      'entity_type': 'refund',
      'entity_id': change.entityId,
      'revision': change.revision,
      'device_id': change.deviceId,
      'product_id': null,
      'quantity_delta': 0,
      'applied_at': now,
    });
  }

  Future<void> _ingestCustomer(
    Transaction txn,
    SyncPullChange change,
    bool isDeleted,
  ) async {
    final payload = change.payload;
    final now = DateTime.now().millisecondsSinceEpoch;

    final existing = await txn.query(
      'customers',
      columns: ['id', 'balance_cents'],
      where: 'id = ?',
      whereArgs: [change.entityId],
      limit: 1,
    );

    if (isDeleted) {
      if (existing.isNotEmpty) {
        await txn.update(
          'customers',
          {
            'is_deleted': 1,
            'updated_at': now,
          },
          where: 'id = ?',
          whereArgs: [change.entityId],
        );
      }
      return;
    }

    final int remoteBalanceCents;
    if (payload['balance_cents'] != null) {
      remoteBalanceCents = (payload['balance_cents'] as num).toInt();
    } else if (payload['balance'] != null) {
      // Sunucu (PostgreSQL schema_v72.sql) alacak perspektifiyle müşteri borcunu pozitif (+debt) tutar.
      // İstemci (Core Next & Flutter UI) ise müşteri cari perspektifiyle borcu negatif (-debt) tutar.
      // Bu nedenle sunucudan gelen pozitif Lira borç bakiyesi istemcide ters işaretle (-balance * 100) kuruşa dönüştürülür.
      remoteBalanceCents = -((payload['balance'] as num).toDouble() * 100).round();
    } else {
      remoteBalanceCents = 0;
    }

    final int creditLimitCents;
    if (payload['credit_limit_cents'] != null) {
      creditLimitCents = (payload['credit_limit_cents'] as num).toInt();
    } else if (payload['credit_limit'] != null) {
      creditLimitCents = ((payload['credit_limit'] as num).toDouble() * 100).round();
    } else {
      creditLimitCents = 0;
    }

    final name = payload['name']?.toString() ?? 'Müşteri ${change.entityId}';
    final phone = payload['phone']?.toString();
    final email = payload['email']?.toString();
    final isActive = (payload['is_active'] == false || payload['is_active'] == 0) ? 0 : 1;

    // Yerel bekleyen veya bu snapshot'a henüz yansımamış finansal hareketlerin delta toplamı
    final unreflectedDeltaCents = await _calculateUnreflectedCustomerDelta(
      txn,
      change.entityId,
      change.revision,
      change.createdAt,
    );
    final effectiveBalanceCents = remoteBalanceCents + unreflectedDeltaCents;

    final customerMap = {
      'name': name,
      'phone': phone,
      'email': email,
      'balance_cents': effectiveBalanceCents,
      'credit_limit_cents': creditLimitCents,
      'is_active': isActive,
      'is_deleted': 0,
      'updated_at': now,
    };

    if (existing.isNotEmpty) {
      // ON DELETE RESTRICT FK ihlalini önlemek için UPDATE
      await txn.update(
        'customers',
        customerMap,
        where: 'id = ?',
        whereArgs: [change.entityId],
      );
    } else {
      await txn.insert(
        'customers',
        {
          'id': change.entityId,
          ...customerMap,
        },
      );
    }
  }

  Future<int> _calculateUnreflectedCustomerDelta(
    Transaction txn,
    String customerId,
    int changeRevision,
    String changeCreatedAt,
  ) async {
    final finEventRows = await txn.rawQuery('''
      SELECT se.entity_type, se.payload_json, se.sync_state, se.base_revision, se.client_timestamp
      FROM sync_events se
      WHERE se.entity_type IN ('financial_transaction', 'sale')
    ''');

    int unreflectedDeltaCents = 0;
    final changeTs = DateTime.tryParse(changeCreatedAt)?.millisecondsSinceEpoch ?? 0;

    for (final row in finEventRows) {
      final jsonStr = row['payload_json'] as String?;
      if (jsonStr == null) continue;
      Map<String, dynamic> map;
      try {
        map = jsonDecode(jsonStr) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      if (map['customer_id'] != customerId) continue;

      final state = row['sync_state'] as String;
      final baseRev = (row['base_revision'] as num?)?.toInt() ?? 0;
      final clientTs = (row['client_timestamp'] as num?)?.toInt() ?? 0;

      bool isUnreflected = false;
      if (state == 'PENDING' || state == 'TRANSIENT_ERROR') {
        // Eğer sunucu snapshot'ının revizyonu bu mutasyonun temel aldığı revizyondan kesin olarak
        // büyükse ve snapshot sunucu zaman damgası mutasyonun oluşturulma zamanından sonraysa;
        // bu durum mutasyonun sunucuya ulaşıp işlendiğini ancak istemci ACK yanıtını henüz almadan
        // pull snapshot'ının geldiğini (in-flight overlap) gösterir.
        // Bu durumda mükerrer borç/tahsilat (double-counting) eklenmesini önleriz.
        final isSnapshotStrictlyNewer =
            (changeRevision > 0 && baseRev > 0 && changeRevision > baseRev) &&
                (changeTs > 0 && clientTs > 0 && changeTs > clientTs);
        if (!isSnapshotStrictlyNewer) {
          isUnreflected = true;
        }
      } else if (state == 'SYNCED' || state == 'COMPLETED') {
        final isRevOlder = changeRevision > 0 && baseRev > 0 && changeRevision < baseRev;
        final isTsOlder = (changeRevision == 0 || baseRev == 0) && changeTs > 0 && clientTs > 0 && changeTs < clientTs;
        if (isRevOlder || isTsOlder) {
          isUnreflected = true;
        }
      }

      if (isUnreflected) {
        final entityType = row['entity_type'] as String? ?? 'financial_transaction';
        if (entityType == 'sale') {
          // Vadeli / açık hesap satış müşterinin bakiyesini borç yönünde eksiltir (-debtCents)
          final debtLira = (map['debt_amount'] as num?)?.toDouble() ??
              (((map['total_amount'] as num?)?.toDouble() ?? 0.0) - ((map['paid_amount'] as num?)?.toDouble() ?? 0.0));
          final debtCents = (debtLira * 100).round();
          if (debtCents > 0) {
            unreflectedDeltaCents -= debtCents;
          }
        } else {
          // Vadeli işlem borcu ise balance'ı negatif yönde artırır (-debtCents)
          final debtLira = (map['debt_amount'] as num?)?.toDouble() ?? 0.0;
          final debtCents = (debtLira * 100).round();
          if (debtCents > 0) {
            unreflectedDeltaCents -= debtCents;
          }
          // Eğer tahsilat ise (paid_amount), balance'ı pozitif yönde artırır (+paidCents)
          if (map['type'] == 'collection' || map['type'] == 'payment') {
            final paidLira = (map['paid_amount'] as num?)?.toDouble() ?? (map['amount'] as num?)?.toDouble() ?? 0.0;
            final paidCents = (paidLira * 100).round();
            if (paidCents > 0) {
              unreflectedDeltaCents += paidCents;
            }
          } else if (map['type'] == 'cancellation') {
            // Vadeli satış iptali borcu düşürür (bakiyeyi pozitif yönde düzeltir)
            final cancelLira = (map['debt_amount'] as num?)?.toDouble() ?? (map['amount'] as num?)?.toDouble() ?? 0.0;
            final cancelCents = (cancelLira * 100).round();
            if (cancelCents > 0) {
              unreflectedDeltaCents += cancelCents;
            }
          } else if (map['type'] == 'refund') {
            // Cari hesaba yapılan iade (nakit ödenmeyen) borcu düşürür
            final paidLira = (map['paid_amount'] as num?)?.toDouble() ?? 0.0;
            if (paidLira == 0) {
              final refundLira = (map['amount'] as num?)?.toDouble() ?? 0.0;
              final refundCents = (refundLira * 100).round();
              if (refundCents > 0) {
                unreflectedDeltaCents += refundCents;
              }
            }
          }
        }
      }
    }
    return unreflectedDeltaCents;
  }

  Future<void> _saveCursor(Transaction txn, int cursor) async {
    await txn.insert(
      'app_settings',
      {
        'key': 'sync_pull_cursor',
        'value': '$cursor',
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
