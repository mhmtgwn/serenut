// core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';
import 'erkul_json_importer.dart';

class CustomerDiscrepancy {
  final String customerId;
  final String customerName;
  final int authoritativeBalanceCents;
  final int staleMinorCents;
  final int discrepancyCents;

  const CustomerDiscrepancy({
    required this.customerId,
    required this.customerName,
    required this.authoritativeBalanceCents,
    required this.staleMinorCents,
    required this.discrepancyCents,
  });

  @override
  String toString() =>
      'CustomerDiscrepancy(ID: $customerId, Yetkili: $authoritativeBalanceCents, BayatMinor: $staleMinorCents, Fark: $discrepancyCents)';
}

class MigrationReport {
  final int productsMigrated;
  final int customersMigrated;
  final int salesMigrated;
  final int ledgerEntriesMigrated;
  final int categoriesMigrated;
  final int saleItemsMigrated;
  final int usersMigrated;
  final int syncEventsMigrated;
  final int durationMs;
  final bool isSuccess;
  final String? errorMessage;
  final List<CustomerDiscrepancy> customerDiscrepancies;
  final int ordersMigrated;
  final int installmentsMigrated;
  final int auditEventsMigrated;
  final int cashCountsMigrated;
  final int cashTransactionsMigrated;

  const MigrationReport({
    required this.productsMigrated,
    required this.customersMigrated,
    required this.salesMigrated,
    required this.ledgerEntriesMigrated,
    this.categoriesMigrated = 0,
    this.saleItemsMigrated = 0,
    this.usersMigrated = 0,
    this.syncEventsMigrated = 0,
    this.ordersMigrated = 0,
    this.installmentsMigrated = 0,
    this.auditEventsMigrated = 0,
    this.cashCountsMigrated = 0,
    this.cashTransactionsMigrated = 0,
    required this.durationMs,
    required this.isSuccess,
    this.errorMessage,
    this.customerDiscrepancies = const [],
  });

  @override
  String toString() =>
      'MigrationReport(Ürünler: $productsMigrated, Cariler: $customersMigrated (Sapmalar: ${customerDiscrepancies.length}), Satışlar: $salesMigrated, Kalemler: $saleItemsMigrated, Defter: $ledgerEntriesMigrated, KasaHareket: $cashTransactionsMigrated, Siparişler: $ordersMigrated, Taksitler: $installmentsMigrated, Audit: $auditEventsMigrated, Kategoriler: $categoriesMigrated, Kullanıcılar: $usersMigrated, Outbox: $syncEventsMigrated, Süre: ${durationMs}ms, Başarılı: $isSuccess)';
}

class ReverseMigrationReport {
  final int salesExported;
  final int saleItemsExported;
  final int customersUpdated;
  final int productsUpdated;
  final int ledgerEntriesExported;
  final int syncEventsExported;
  final int durationMs;
  final bool isSuccess;
  final String? errorMessage;

  const ReverseMigrationReport({
    required this.salesExported,
    required this.saleItemsExported,
    required this.customersUpdated,
    required this.productsUpdated,
    required this.ledgerEntriesExported,
    required this.syncEventsExported,
    required this.durationMs,
    required this.isSuccess,
    this.errorMessage,
  });

  @override
  String toString() =>
      'ReverseMigrationReport(Satışlar: $salesExported, Kalemler: $saleItemsExported, Güncellenen Müşteriler: $customersUpdated, Güncellenen Ürünler: $productsUpdated, Defter: $ledgerEntriesExported, Outbox: $syncEventsExported, Süre: ${durationMs}ms, Başarılı: $isSuccess)';
}

Future<Set<String>> _getTableColumns(DatabaseExecutor db, String tableName) async {
  final info = await db.rawQuery('PRAGMA table_info($tableName)');
  return info.map((r) => r['name'].toString()).toSet();
}

/// Eski SQLite (v60) Verilerini Yeni Temiz Kuruş Şemasına (v3) Taşıyan Otomatik Köprü Motoru.
/// 
/// Sıfır Kesinti ve Sıfır Veri Kaybı Garantisi:
/// - Eski dosyayı asla silmez; `.backup` yedeğini alır.
/// - Double fiyat ve bakiyeleri kuruşa `(val * 100).round()` ile dönüştürür.
/// - `ConflictAlgorithm.ignore` ile ikinci çalıştırmalarda veya yeniden başlatmalarda
///   `sale_items` ve `ledger_entries` yabancı anahtar (RESTRICT) ihlallerini önler.
/// - `fullScope: true` ile tüm ilişkili tabloları (users, categories, sale_items, ledger_entries, sync_events) taşır.
/// - `fullScope: false` ile Stage 10.8.4 uyumluluğu için çekirdek katalog, müşteri ve satış başlıklarını taşır.
class MigrationBridgeEngine {
  final CoreAppDatabase targetDb;

  const MigrationBridgeEngine(this.targetDb);

  /// Geçişin daha önce yapılıp yapılmadığını kontrol eder
  Future<bool> isMigrationCompleted() async {
    final rows = await targetDb.db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: ['legacy_migration_completed'],
    );
    return rows.isNotEmpty && rows.first['value'] == 'true';
  }

  /// Tablo kolonlarını güvenle listeler (Schema v44 / v60 uyumluluğu)
  static Future<Set<String>> _getTableColumns(Database db, String table) async {
    final cols = await db.rawQuery('PRAGMA table_info($table);');
    return cols.map((c) => c['name'] as String).toSet();
  }

  /// Eski veritabanından yeni veritabanına veri aktarımını başlatır
  Future<MigrationReport> migrateFromLegacy(
    Database legacyDb, {
    String? legacyFilePath,
    bool fullScope = false,
    void Function(String stage, double progress, String? detail)? onProgress,
  }) async {
    final stopwatch = Stopwatch()..start();

    // 1. Rollback Güvencesi: Dosya yolu verilmişse fiziksel yedeğini al
    if (legacyFilePath != null) {
      final legacyFile = File(legacyFilePath);
      if (await legacyFile.exists()) {
        await legacyFile.copy('$legacyFilePath.backup');
      }
    }

    int catCount = 0;
    int pCount = 0;
    int cCount = 0;
    int sCount = 0;
    int itemCount = 0;
    int lCount = 0;
    int uCount = 0;
    int syncCount = 0;
    int orderCount = 0;
    int instCount = 0;
    int auditCount = 0;
    int cashCount = 0;
    int cashTxCount = 0;
    final discrepancies = <CustomerDiscrepancy>[];

    try {
      await targetDb.transaction((txn) async {
        // ── 1. KULLANICILAR & ROLLER (FULL SCOPE) ───────────────────────────
        if (fullScope) {
          final legacyUsersTable = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='users'",
          );
          if (legacyUsersTable.isNotEmpty) {
            final users = await legacyDb.query('users');
            for (final row in users) {
              final id = row['id']?.toString() ?? 'usr-${row['username']}';
              final rawUsername = (row['username'] ?? row['email'] ?? row['name'] ?? 'user_$id').toString().trim();
              final username = rawUsername.isNotEmpty ? rawUsername : 'user_$id';
              final displayName = (row['name'] ?? row['display_name'] ?? row['username'] ?? 'Kullanıcı').toString();
              final role = (row['role'] ?? 'cashier').toString();
              final pinHash = (row['pin_hash'] ?? row['password_hash'])?.toString();
              final isActive = (row['is_active'] as int?) ?? 1;

              final createdAtVal = row['created_at'];
              final int createdAtMs = createdAtVal is int
                  ? createdAtVal
                  : DateTime.tryParse(createdAtVal?.toString() ?? '')
                          ?.millisecondsSinceEpoch ??
                      DateTime.now().millisecondsSinceEpoch;

              await txn.insert(
                'users',
                {
                  'id': id,
                  'username': username,
                  'display_name': displayName,
                  'role': role,
                  'pin_hash': pinHash,
                  'is_active': isActive,
                  'created_at': createdAtMs,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
              uCount++;
            }
          }
        }

        // ── 2. KATEGORİLER (FULL SCOPE) ─────────────────────────────────────
        final categoryMap = <String, String>{}; // categoryName -> categoryId
        if (fullScope) {
          final legacyCategoriesTable = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='categories'",
          );

          if (legacyCategoriesTable.isNotEmpty) {
            final categories = await legacyDb.query('categories');
            for (final row in categories) {
              final id = row['id']?.toString() ?? '';
              final name = row['name']?.toString() ?? '';
              if (id.isEmpty || name.isEmpty) continue;

              categoryMap[name] = id;
              await txn.rawInsert(
                '''
                INSERT INTO categories (
                  id, name, color_hex, sort_order, is_active, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(id) DO UPDATE SET
                  name = excluded.name,
                  color_hex = excluded.color_hex,
                  sort_order = excluded.sort_order,
                  is_active = excluded.is_active,
                  updated_at = excluded.updated_at
                ''',
                [
                  id,
                  name,
                  row['color_hex'] as String?,
                  (row['sort_order'] as num? ?? 0).toInt(),
                  (row['is_active'] as int? ?? 1),
                  DateTime.now().millisecondsSinceEpoch,
                ],
              );
              catCount++;
            }
          } else {
            final legacyProductsCheck = await legacyDb.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='products'",
            );
            if (legacyProductsCheck.isNotEmpty) {
              final prodCols = await _getTableColumns(legacyDb, 'products');
              if (prodCols.contains('category')) {
                final distinctCats = await legacyDb.rawQuery(
                  "SELECT DISTINCT category FROM products WHERE category IS NOT NULL AND category != ''",
                );
                int sort = 0;
                for (final row in distinctCats) {
                  final catName = row['category']?.toString().trim() ?? '';
                  if (catName.isEmpty) continue;
                  final catId = 'cat-${catName.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';
                  categoryMap[catName] = catId;

                  await txn.insert(
                    'categories',
                    {
                      'id': catId,
                      'name': catName,
                      'color_hex': null,
                      'sort_order': sort++,
                      'is_active': 1,
                      'updated_at': DateTime.now().millisecondsSinceEpoch,
                    },
                    conflictAlgorithm: ConflictAlgorithm.ignore,
                  );
                  catCount++;
                }
              }
            }
          }
        }

        // ── 3. CARİ / MÜŞTERİ AKTARIMI ───────────────────────────────────────
        final legacyCustomers = await legacyDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='customers'",
        );
        if (legacyCustomers.isNotEmpty) {
          final hasLedgerEffect = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') AND name='v_customer_ledger_effect'",
          );
          final ledgerBalances = <String, double>{};
          if (hasLedgerEffect.isNotEmpty) {
            final lRows = await legacyDb.rawQuery(
              "SELECT customer_id, ROUND(SUM(balance_effect), 2) as ledger_bal FROM v_customer_ledger_effect WHERE customer_id IS NOT NULL AND customer_id != '' GROUP BY customer_id",
            );
            for (final lr in lRows) {
              final cid = lr['customer_id']?.toString() ?? '';
              if (cid.isNotEmpty) {
                ledgerBalances[cid] = (lr['ledger_bal'] as num?)?.toDouble() ?? 0.0;
              }
            }
          }

          final customers = await legacyDb.query('customers');
          var batch = txn.batch();

          for (final row in customers) {
            var id = row['id']?.toString() ?? '';
            if (id.trim().isEmpty) {
              id = 'customer-pesin-default';
            }
            final name = row['name']?.toString() ?? 'İsimsiz Müşteri';

            final rawBalance = (row['balance'] as num?)?.toDouble() ?? 0.0;
            final expectedAuthoritativeCents = (rawBalance * 100).round();

            if (hasLedgerEffect.isNotEmpty && id != 'customer-pesin-default') {
              final ledgerTl = ledgerBalances[id] ?? 0.0;
              final ledgerCents = (ledgerTl * 100).round();
              if (expectedAuthoritativeCents != ledgerCents) {
                throw StateError(
                  'MÜŞTERİ BAKİYE SAPMASI TESPİT EDİLDİ! '
                  'Müşteri: $id ($name) için customers.balance ($expectedAuthoritativeCents kuruş) ile '
                  'v_customer_ledger_effect defter toplamı ($ledgerCents kuruş) uyuşmuyor! '
                  'Finansal bütünlük ve adli kural gereği migrasyon güvenli biçimde durduruldu.',
                );
              }
            }

            final int balanceCents;
            if (row['balance_minor'] != null) {
              final minorCents = (row['balance_minor'] as num).toInt();
              if (minorCents != expectedAuthoritativeCents) {
                discrepancies.add(CustomerDiscrepancy(
                  customerId: id,
                  customerName: name,
                  authoritativeBalanceCents: expectedAuthoritativeCents,
                  staleMinorCents: minorCents,
                  discrepancyCents: minorCents - expectedAuthoritativeCents,
                ));
                balanceCents = expectedAuthoritativeCents;
              } else {
                balanceCents = minorCents;
              }
            } else {
              balanceCents = expectedAuthoritativeCents;
            }

            final int creditLimitCents;
            if (row['credit_limit_minor'] != null) {
              creditLimitCents = (row['credit_limit_minor'] as num).toInt();
            } else {
              final rawLimit = (row['credit_limit'] as num?)?.toDouble() ?? 0.0;
              creditLimitCents = (rawLimit * 100).round();
            }

            batch.rawInsert(
              '''
              INSERT INTO customers (
                id, name, phone, email, tax_number, tax_office,
                balance_cents, credit_limit_cents, notes, is_active,
                is_deleted, updated_at
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(id) DO UPDATE SET
                name = excluded.name,
                phone = excluded.phone,
                email = excluded.email,
                tax_number = excluded.tax_number,
                tax_office = excluded.tax_office,
                balance_cents = excluded.balance_cents,
                credit_limit_cents = excluded.credit_limit_cents,
                notes = excluded.notes,
                is_active = excluded.is_active,
                is_deleted = excluded.is_deleted,
                updated_at = excluded.updated_at
              ''',
              [
                id,
                name,
                row['phone'] as String?,
                row['email'] as String?,
                row['tax_number'] as String?,
                row['tax_office'] as String?,
                balanceCents,
                creditLimitCents,
                row['notes'] as String?,
                (row['is_active'] as int? ?? 1),
                (row['is_deleted'] as int? ?? 0),
                DateTime.now().millisecondsSinceEpoch,
              ],
            );
            cCount++;
          }
          await batch.commit(noResult: true);
        }

        // ── 4. ÜRÜN KATALOĞU AKTARIMI ────────────────────────────────────────
        final productBarcodeMap = <String, String>{}; // productId -> barcode
        final legacyProducts = await legacyDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='products'",
        );
        if (legacyProducts.isNotEmpty) {
          final products = await legacyDb.query('products');
          var batch = txn.batch();
          int batchCount = 0;

          for (final row in products) {
            final rawBarcode = (row['barcode'] ?? row['sku'] ?? row['id'])?.toString() ?? '';
            final barcode = rawBarcode.trim();
            if (barcode.isEmpty) continue;

            final int priceCents;
            if (row['price_minor'] != null) {
              priceCents = (row['price_minor'] as num).toInt();
            } else {
              final rawPrice = (row['price'] as num?)?.toDouble() ?? 0.0;
              priceCents = (rawPrice * 100).round();
            }

            final int? costPriceCents;
            if (row['purchase_price_minor'] != null) {
              costPriceCents = (row['purchase_price_minor'] as num).toInt();
            } else if (row['purchase_price'] != null) {
              costPriceCents = ((row['purchase_price'] as num).toDouble() * 100).round();
            } else if (row['cost_price'] != null) {
              costPriceCents = ((row['cost_price'] as num).toDouble() * 100).round();
            } else {
              costPriceCents = null;
            }

            final id = row['id']?.toString() ?? barcode;
            productBarcodeMap[id] = barcode;

            final name = row['name']?.toString() ?? 'İsimsiz Ürün';
            final vatRate = (row['vat_rate'] ?? row['vat'] ?? 20) as num;
            final stock = (row['stock_quantity'] ?? row['quantity'] ?? 0) as num;
            final isActive = (row['is_active'] as int? ?? 1);
            final isDeleted = (row['is_deleted'] as int? ?? 0);
            final updatedAt = DateTime.now().millisecondsSinceEpoch;

            final unit = (row['sale_type'] == 'weighed' || row['unit'] == 'kg')
                ? 'kg'
                : 'piece';

            final rawCatName = row['category']?.toString();
            final categoryId = row['category_id']?.toString() ??
                (rawCatName != null ? categoryMap[rawCatName] : null);

            batch.rawInsert(
              '''
              INSERT INTO products (
                id, barcode, name, category_id, price_cents, cost_price_cents,
                vat_rate, unit, stock_quantity, critical_threshold, image_url,
                is_active, is_deleted, updated_at
              ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(id) DO UPDATE SET
                barcode = excluded.barcode,
                name = excluded.name,
                category_id = excluded.category_id,
                price_cents = excluded.price_cents,
                cost_price_cents = excluded.cost_price_cents,
                vat_rate = excluded.vat_rate,
                unit = excluded.unit,
                stock_quantity = excluded.stock_quantity,
                critical_threshold = excluded.critical_threshold,
                image_url = excluded.image_url,
                is_active = excluded.is_active,
                is_deleted = excluded.is_deleted,
                updated_at = excluded.updated_at
              ''',
              [
                id,
                barcode,
                name,
                categoryId,
                priceCents,
                costPriceCents,
                vatRate.toInt(),
                unit,
                stock.toDouble(),
                (row['min_stock'] as num? ?? 5).toDouble(),
                row['image_url'] as String?,
                isActive,
                isDeleted,
                updatedAt,
              ],
            );
            pCount++;
            batchCount++;

            if (batchCount >= 1000) {
              await batch.commit(noResult: true);
              batch = txn.batch();
              batchCount = 0;
              await Future<void>.delayed(Duration.zero);
              if (onProgress != null && products.isNotEmpty) {
                final pct = 0.40 + (pCount / products.length) * 0.25;
                onProgress('Ürünler aktarılıyor', pct, '$pCount / ${products.length} ürün aktarıldı');
              }
            }
          }
          if (batchCount > 0) {
            await batch.commit(noResult: true);
            await Future<void>.delayed(Duration.zero);
          }
        }

        final validCustRows = await txn.query('customers', columns: ['id']);
        final validCustomerIds = validCustRows.map((r) => r['id'] as String).toSet();
        final validProdRows = await txn.query('products', columns: ['id']);
        final validProductIds = validProdRows.map((r) => r['id'] as String).toSet();
        final legacySalesTable = await legacyDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='sales'",
        );
        final validSalesSet = <String>{};

        if (legacySalesTable.isNotEmpty) {
          final legacySalePaymentsTable = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sale_payments'",
          );

          final sales = await legacyDb.query('sales');
          var batch = txn.batch();
          int batchCount = 0;

          for (final row in sales) {
            final saleId = row['id'] as String;
            validSalesSet.add(saleId);

            final int totalCents = resolveAmountCents(
              rawAmountNum: (row['total_amount'] ?? row['total']) as num?,
              rawMinorNum: row['total_amount_minor'] as num?,
            );

            final int paidCents = resolveAmountCents(
              rawAmountNum: (row['paid_amount'] ?? row['paid']) as num? ?? (totalCents / 100.0),
              rawMinorNum: row['paid_amount_minor'] as num?,
            );

            final int discountCents = resolveAmountCents(
              rawAmountNum: (row['discount_amount'] ?? row['discount']) as num?,
              rawMinorNum: row['discount_amount_minor'] as num?,
            );

            final rawStatus = row['status']?.toString() ?? 'COMPLETED';
            if (totalCents < 0 && rawStatus != 'REFUND') {
              throw StateError(
                'GEÇMİŞ SATIŞ MUTABAKAT HATASI: Satış $saleId için toplam tutar ($totalCents kuruş) negatif olamaz.',
              );
            }
            if (paidCents < 0 && rawStatus != 'REFUND') {
              throw StateError(
                'GEÇMİŞ SATIŞ MUTABAKAT HATASI: Satış $saleId için tahsilat tutarı ($paidCents kuruş) negatif olamaz.',
              );
            }
            if (paidCents > totalCents && rawStatus != 'REFUND') {
              throw StateError(
                'GEÇMİŞ SATIŞ MUTABAKAT HATASI: Satış $saleId için tahsilat tutarı ($paidCents kuruş) toplam tutarı ($totalCents kuruş) aşamaz.',
              );
            }

            final int debtCents = totalCents - paidCents;

            final createdAtVal = row['created_at'];
            final int createdAtMs = createdAtVal is int
                ? createdAtVal
                : DateTime.tryParse(createdAtVal?.toString() ?? '')
                        ?.millisecondsSinceEpoch ??
                    DateTime.now().millisecondsSinceEpoch;

            final rawCustId = row['customer_id']?.toString().trim();
            final String? customerId = (rawCustId != null && validCustomerIds.contains(rawCustId))
                ? rawCustId
                : null;
            final idempotencyKey = row['idempotency_key']?.toString() ?? row['id'].toString();

            batch.insert(
              'sales',
              {
                'id': saleId,
                'receipt_no': row['receipt_no']?.toString() ?? row['id'].toString(),
                'customer_id': customerId,
                'subtotal_cents': totalCents + discountCents,
                'discount_cents': discountCents,
                'vat_total_cents': 0,
                'total_cents': totalCents,
                'paid_cents': paidCents,
                'debt_cents': debtCents,
                'status': rawStatus,
                'idempotency_key': idempotencyKey,
                'created_at': createdAtMs,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );

            final legacyPaymentMethod = (row['payment_method'] ?? 'cash').toString().toLowerCase().trim();
            final String mappedPaymentType;
            final String paymentNote;

            if (legacyPaymentMethod.contains('mixed') ||
                legacyPaymentMethod.contains('karma') ||
                legacyPaymentMethod.contains('split') ||
                legacyPaymentMethod.contains('parcali')) {
              mappedPaymentType = 'mixed';
              paymentNote = 'Eski Karma Satış (Tarihsel Parçalı Kırılım Bilinmiyor: $legacyPaymentMethod)';
            } else if (legacyPaymentMethod.contains('card') || legacyPaymentMethod.contains('kart')) {
              mappedPaymentType = 'creditCard';
              paymentNote = 'Eski Satış Aktarımı ($legacyPaymentMethod)';
            } else if (legacyPaymentMethod.contains('bank') ||
                legacyPaymentMethod.contains('havale') ||
                legacyPaymentMethod.contains('eft')) {
              mappedPaymentType = 'bankTransfer';
              paymentNote = 'Eski Satış Aktarımı ($legacyPaymentMethod)';
            } else if (legacyPaymentMethod.contains('debt') || legacyPaymentMethod.contains('veresiye')) {
              mappedPaymentType = 'onAccount';
              paymentNote = 'Eski Satış Aktarımı ($legacyPaymentMethod)';
            } else {
              mappedPaymentType = 'cash';
              paymentNote = 'Eski Satış Aktarımı ($legacyPaymentMethod)';
            }

            bool hasStructuredPayments = false;
            if (legacySalePaymentsTable.isNotEmpty) {
              final spRows = await legacyDb.query(
                'sale_payments',
                where: 'sale_id = ?',
                whereArgs: [saleId],
              );
              if (spRows.isNotEmpty) {
                hasStructuredPayments = true;
                for (final sp in spRows) {
                  final spId = sp['id']?.toString() ?? '$saleId-pay-${sp['payment_type']}';
                  final spType = sp['payment_type']?.toString() ?? 'cash';
                  final int spCents = resolveAmountCents(
                    rawAmountNum: sp['amount'] as num?,
                    rawMinorNum: (sp['amount_minor'] ?? sp['amount_cents']) as num?,
                  );
                  batch.insert(
                    'sale_payments',
                    {
                      'id': spId,
                      'sale_id': saleId,
                      'payment_type': spType,
                      'amount_cents': spCents,
                      'reference_note': sp['reference_note']?.toString(),
                      'created_at': createdAtMs,
                    },
                    conflictAlgorithm: ConflictAlgorithm.ignore,
                  );
                }
              }
            }

            if (!hasStructuredPayments) {
              if (paidCents > 0) {
                batch.insert(
                  'sale_payments',
                  {
                    'id': '$saleId-pay-legacy-paid',
                    'sale_id': saleId,
                    'payment_type': mappedPaymentType,
                    'amount_cents': paidCents,
                    'reference_note': paymentNote,
                    'created_at': createdAtMs,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
              }

              if (debtCents > 0) {
                batch.insert(
                  'sale_payments',
                  {
                    'id': '$saleId-pay-legacy-debt',
                    'sale_id': saleId,
                    'payment_type': 'onAccount',
                    'amount_cents': debtCents,
                    'reference_note': 'Eski Satış Vadeli Borç',
                    'created_at': createdAtMs,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
              }
            }

            sCount++;
            batchCount++;

            if (batchCount >= 1000) {
              await batch.commit(noResult: true);
              batch = txn.batch();
              batchCount = 0;
            }
          }
          if (batchCount > 0) {
            await batch.commit(noResult: true);
          }
        }

        // ── 6. SATIŞ KALEMLERİ AKTARIMI (FULL SCOPE) ─────────────────────────
        if (fullScope) {
          final legacySaleItemsTable = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sale_items'",
          );
          if (legacySaleItemsTable.isNotEmpty) {
            final saleItems = await legacyDb.query('sale_items');
            var batch = txn.batch();
            int batchCount = 0;

            for (final row in saleItems) {
              final saleId = row['sale_id']?.toString() ?? '';
              if (!validSalesSet.contains(saleId)) continue;

              var productId = row['product_id']?.toString() ?? '';
              if (!validProductIds.contains(productId)) {
                final placeholderId = productId.isNotEmpty ? productId : 'p-legacy-orphaned';
                await txn.insert(
                  'products',
                  {
                    'id': placeholderId,
                    'barcode': 'ORPHAN-$placeholderId',
                    'name': (row['product_name'] ?? 'Eski Bilinmeyen Ürün').toString(),
                    'price_cents': 0,
                    'vat_rate': 20,
                    'unit': 'piece',
                    'stock_quantity': 0,
                    'critical_threshold': 0,
                    'is_active': 0,
                    'is_deleted': 1,
                    'updated_at': DateTime.now().millisecondsSinceEpoch,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
                validProductIds.add(placeholderId);
                productId = placeholderId;
              }

              final barcode = row['barcode']?.toString() ??
                  productBarcodeMap[productId] ??
                  'BC-$productId';

              final int unitPriceCents;
              if (row['unit_price_minor'] != null) {
                unitPriceCents = (row['unit_price_minor'] as num).toInt();
              } else {
                final up = (row['unit_price'] as num?)?.toDouble() ?? 0.0;
                unitPriceCents = (up * 100).round();
              }

              final int totalCents;
              if (row['subtotal_minor'] != null) {
                totalCents = (row['subtotal_minor'] as num).toInt();
              } else {
                final st = (row['subtotal'] as num?)?.toDouble() ?? (unitPriceCents / 100.0);
                totalCents = (st * 100).round();
              }

              final double quantity = (row['quantity'] as num?)?.toDouble() ?? 1.0;
              final int vatRate = ((row['vat_rate'] ?? row['vat'] ?? 20) as num).toInt();
              final int discountCents = ((row['discount_amount_minor'] ?? 0) as num).toInt();

              final itemId = row['id']?.toString() ?? '$saleId-item-$itemCount';

              batch.insert(
                'sale_items',
                {
                  'id': itemId,
                  'sale_id': saleId,
                  'product_id': productId,
                  'barcode': barcode,
                  'product_name': (row['product_name'] ?? 'Ürün').toString(),
                  'unit_price_cents': unitPriceCents,
                  'quantity': quantity,
                  'discount_cents': discountCents,
                  'vat_rate': vatRate,
                  'total_cents': totalCents,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
              itemCount++;
              batchCount++;

              if (batchCount >= 1000) {
                await batch.commit(noResult: true);
                batch = txn.batch();
                batchCount = 0;
              }
            }
            if (batchCount > 0) {
              await batch.commit(noResult: true);
            }
          }
        }

        // ── 7. MÜŞTERİ DEFTERİ / FİNANSAL HAREKETLER (FULL SCOPE) ─────────────
        if (fullScope) {
          final legacyFtTable = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='financial_transactions'",
          );
          if (legacyFtTable.isNotEmpty) {
            final validCustRows = await txn.query('customers', columns: ['id']);
            final validCustomerIds = validCustRows.map((r) => r['id'] as String).toSet();

            final ftRows = await legacyDb.query('financial_transactions');
            final customerRunningBalances = <String, int>{};
            var batch = txn.batch();
            int batchCount = 0;

            for (final row in ftRows) {
              final isDeletedVal = row['is_deleted'];
              final isDeleted = isDeletedVal == 1 ||
                  isDeletedVal == true ||
                  isDeletedVal?.toString() == '1';
              final deletedAtStr = row['deleted_at']?.toString().trim();
              if (isDeleted || (deletedAtStr != null && deletedAtStr.isNotEmpty)) {
                continue;
              }

              final cid = row['customer_id']?.toString() ?? '';
              final rawAmount = (row['amount'] as num?)?.toDouble() ?? 0.0;
              final rawMinor = (row['amount_minor'] as num?)?.toInt();
              final amountCents = resolveAmountCents(
                rawAmountNum: rawAmount,
                rawMinorNum: rawMinor,
              );

              final rawType = (row['type'] ?? 'ADJUSTMENT').toString().toLowerCase().trim();
              var entryType = rawType.toUpperCase();
              var effectiveAmountCents = amountCents;
              var rawDesc = row['description']?.toString() ?? 'Eski Finansal Hareket';
              final rawRefId = row['reference_id']?.toString();

              final hasSubAmounts = row['debt_amount'] != null ||
                  row['paid_amount'] != null ||
                  row['debt_amount_minor'] != null ||
                  row['paid_amount_minor'] != null;
              if (hasSubAmounts) {
                final paidCents = resolveAmountCents(
                  rawAmountNum: (row['paid_amount'] as num?)?.toDouble(),
                  rawMinorNum: (row['paid_amount_minor'] as num?)?.toInt(),
                );
                final debtCents = (row['debt_amount'] != null || row['debt_amount_minor'] != null)
                    ? resolveAmountCents(
                        rawAmountNum: (row['debt_amount'] as num?)?.toDouble(),
                        rawMinorNum: (row['debt_amount_minor'] as num?)?.toInt(),
                      )
                    : (amountCents - paidCents).clamp(0, amountCents);
                if (rawType == 'sale') {
                  if (debtCents == 0 && paidCents > 0) {
                    entryType = 'SALE_PAID';
                    effectiveAmountCents = amountCents;
                  } else if (paidCents > 0 && debtCents > 0) {
                    effectiveAmountCents = debtCents;
                    if (!rawDesc.contains('[ft:total=')) {
                      rawDesc = '$rawDesc [ft:total=$amountCents,paid=$paidCents,debt=$debtCents]';
                    }
                  }
                } else if (rawType == 'cancellation') {
                  if (debtCents != amountCents) {
                    effectiveAmountCents = debtCents;
                    if (!rawDesc.contains('[ft:total=')) {
                      rawDesc = '$rawDesc [ft:total=$amountCents,paid=$paidCents,debt=$debtCents]';
                    }
                  }
                } else if (rawType == 'refund') {
                  if (paidCents == amountCents && paidCents > 0) {
                    entryType = 'REFUND_CASH';
                  } else if (paidCents > 0) {
                    if (!rawDesc.contains('[ft:total=')) {
                      rawDesc = '$rawDesc [ft:total=$amountCents,paid=$paidCents,debt=$debtCents]';
                    }
                  }
                }
              }

              final createdAtVal = row['created_at'];
              final int createdAtMs = createdAtVal is int
                  ? createdAtVal
                  : DateTime.tryParse(createdAtVal?.toString() ?? '')
                          ?.millisecondsSinceEpoch ??
                      DateTime.now().millisecondsSinceEpoch;

              // ── MÜŞTERİSİZ NAKİT SATIŞLAR: cash_transactions'a aktar ──
              if (cid.trim().isEmpty || !validCustomerIds.contains(cid)) {
                if (rawType == 'sale') {
                  if (rawRefId == null || !validSalesSet.contains(rawRefId)) {
                    throw StateError(
                      'GEÇERSİZ MÜŞTERİSİZ SATIŞ REFERANSI: İşlem ${row['id']} için reference_id ($rawRefId) sales tablosunda bulunamadı!',
                    );
                  }
                  final entryId = row['id']?.toString() ?? 'ft-cash-$cashTxCount';
                  batch.insert(
                    'cash_transactions',
                    {
                      'id': entryId,
                      'type': 'INFLOW',
                      'amount_cents': amountCents,
                      'category': 'SALE',
                      'description': (row['description']?.toString().isNotEmpty == true)
                          ? row['description']!.toString()
                          : 'Nakit Satış ($rawRefId)',
                      'created_at': createdAtMs,
                    },
                    conflictAlgorithm: ConflictAlgorithm.ignore,
                  );
                  cashTxCount++;
                  batchCount++;
                  if (batchCount >= 1000) {
                    await batch.commit(noResult: true);
                    batch = txn.batch();
                    batchCount = 0;
                  }
                  continue;
                } else {
                  throw StateError(
                    'TANIMSIZ MÜŞTERİSİZ FİNANSAL HAREKET: İşlem ${row['id']} müşterisiz ancak türü "$rawType". Finansal bütünlük gereği durduruldu.',
                  );
                }
              }

              // ── MÜŞTERİLİ CARİ HAREKETLER: ledger_entries'e aktar ──
              final currentRunning = customerRunningBalances[cid] ?? 0;
              final isDebtIncrease = entryType != 'SALE_PAID' &&
                  (entryType.contains('SALE') || entryType.contains('DEBT') || entryType.contains('BORC'));
              final newRunning = (entryType == 'SALE_PAID' || entryType == 'REFUND_CASH')
                  ? currentRunning
                  : (isDebtIncrease ? currentRunning - effectiveAmountCents : currentRunning + effectiveAmountCents);
              customerRunningBalances[cid] = newRunning;

              final String? refSaleId = (rawRefId != null &&
                      (validSalesSet.contains(rawRefId) ||
                          rawRefId.startsWith('ord-') ||
                          rawRefId.startsWith('refund-')))
                  ? rawRefId
                  : null;

              final entryId = row['id']?.toString() ?? 'ft-legacy-$lCount';

              batch.insert(
                'ledger_entries',
                {
                  'id': entryId,
                  'customer_id': cid,
                  'reference_sale_id': refSaleId,
                  'entry_type': entryType,
                  'amount_cents': effectiveAmountCents,
                  'balance_after_cents': newRunning,
                  'description': rawDesc,
                  'created_at': createdAtMs,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
              lCount++;
              batchCount++;

              if (batchCount >= 1000) {
                await batch.commit(noResult: true);
                batch = txn.batch();
                batchCount = 0;
              }
            }
            if (batchCount > 0) {
              await batch.commit(noResult: true);
            }
          }
        }

        // ── 8. BEKLEYEN OFFLINE OLAYLAR (GÜVENLİ CUTOVER POLİTİKASI) ──────────
        // PENDING, IN_FLIGHT ve TRANSIENT_ERROR durumundaki unconfirmed mutasyonlar taşınır
        if (fullScope) {
          final legacyOutboxTable = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sync_outbox_v4'",
          );
          if (legacyOutboxTable.isNotEmpty) {
            final pendingRows = await legacyDb.query(
              'sync_outbox_v4',
              where: "state IN ('PENDING', 'IN_FLIGHT', 'TRANSIENT_ERROR')",
            );
            var batch = txn.batch();
            for (final row in pendingRows) {
              final eventId = (row['mutation_id'] ?? 'legacy-mutation-${row['id']}').toString();
              final entityType = (row['entity_type'] ?? 'unknown').toString();
              final entityId = (row['entity_id'] ?? '').toString();
              final operation = (row['operation'] ?? 'UPSERT').toString();
              final payloadJson = (row['payload'] ?? '{}').toString();
              final baseRevision = (row['base_revision'] as num? ?? 0).toInt();
              final attempts = (row['attempts'] as num? ?? 0).toInt();

              final createdAtVal = row['created_at'];
              final int createdAtMs = createdAtVal is int
                  ? createdAtVal
                  : DateTime.tryParse(createdAtVal?.toString() ?? '')
                          ?.millisecondsSinceEpoch ??
                      DateTime.now().millisecondsSinceEpoch;

              batch.insert(
                'sync_events',
                {
                  'event_id': eventId,
                  'entity_type': entityType,
                  'entity_id': entityId,
                  'operation': operation,
                  'payload_json': payloadJson,
                  'base_revision': baseRevision,
                  'client_timestamp': createdAtMs,
                  'sync_state': 'PENDING',
                  'attempts': attempts,
                  'causal_sequence': (row['id'] as num? ?? 0).toInt(),
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
              syncCount++;
            }
            await batch.commit(noResult: true);
          }
        }

        // ── 9. SİPARİŞLER VE SİPARİŞ KALEMLERİ (FULL SCOPE) ────────────────
        if (fullScope) {
          final legacyOrdersTable = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='orders'",
          );
          if (legacyOrdersTable.isNotEmpty) {
            final orderCols = await _getTableColumns(legacyDb, 'orders');
            final legacyOrders = await legacyDb.query('orders');
            final validOrderIds = <String>{};
            var batch = txn.batch();
            int batchCount = 0;
            for (final row in legacyOrders) {
              final id = row['id'].toString();
              validOrderIds.add(id);
              final orderNo = orderCols.contains('order_number')
                  ? (row['order_number']?.toString() ?? 'ORD-$id')
                  : 'ORD-$id';
              final customerId = row['customer_id']?.toString();
              final validCid = (customerId != null && validCustomerIds.contains(customerId))
                  ? customerId
                  : null;
              final status = row['status']?.toString() ?? 'pending';
              final rawTotal = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
              final totalAmountCents = (rawTotal * 100).round();
              final rawDiscount = orderCols.contains('discount_amount')
                  ? ((row['discount_amount'] as num?)?.toDouble() ?? 0.0)
                  : 0.0;
              final discountCents = (rawDiscount * 100).round();
              final orderDateVal = row['order_date'];
              final int orderDateMs = orderDateVal is int
                  ? orderDateVal
                  : DateTime.tryParse(orderDateVal?.toString() ?? '')?.millisecondsSinceEpoch ??
                      DateTime.now().millisecondsSinceEpoch;
              final expDeliveryVal = row['expected_delivery_date'];
              final int? expDeliveryMs = expDeliveryVal != null
                  ? (expDeliveryVal is int ? expDeliveryVal : DateTime.tryParse(expDeliveryVal.toString())?.millisecondsSinceEpoch)
                  : null;
              final actDeliveryVal = row['actual_delivery_date'];
              final int? actDeliveryMs = actDeliveryVal != null
                  ? (actDeliveryVal is int ? actDeliveryVal : DateTime.tryParse(actDeliveryVal.toString())?.millisecondsSinceEpoch)
                  : null;
              final notes = row['notes']?.toString();
              final createdBy = row['created_by']?.toString();
              final isDeleted = (row['is_deleted'] as int?) ?? 0;
              final createdAtVal = row['created_at'];
              final int createdAtMs = createdAtVal is int
                  ? createdAtVal
                  : DateTime.tryParse(createdAtVal?.toString() ?? '')?.millisecondsSinceEpoch ??
                      orderDateMs;
              final updatedAtVal = row['updated_at'];
              final int updatedAtMs = updatedAtVal is int
                  ? updatedAtVal
                  : DateTime.tryParse(updatedAtVal?.toString() ?? '')?.millisecondsSinceEpoch ??
                      createdAtMs;

              batch.insert(
                'orders',
                {
                  'id': id,
                  'order_number': orderNo,
                  'customer_id': validCid,
                  'status': status,
                  'total_amount_cents': totalAmountCents,
                  'discount_amount_cents': discountCents,
                  'order_date': orderDateMs,
                  'expected_delivery_date': expDeliveryMs,
                  'actual_delivery_date': actDeliveryMs,
                  'notes': notes,
                  'created_by': createdBy,
                  'is_deleted': isDeleted,
                  'created_at': createdAtMs,
                  'updated_at': updatedAtMs,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
              orderCount++;
              batchCount++;
              if (batchCount >= 1000) {
                await batch.commit(noResult: true);
                batch = txn.batch();
                batchCount = 0;
              }
            }
            if (batchCount > 0) {
              await batch.commit(noResult: true);
            }

            final legacyOrderItemsTable = await legacyDb.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='order_items'",
            );
            if (legacyOrderItemsTable.isNotEmpty) {
              final itemCols = await _getTableColumns(legacyDb, 'order_items');
              final legacyItems = await legacyDb.query('order_items');
              batch = txn.batch();
              batchCount = 0;
              for (final row in legacyItems) {
                final id = row['id'].toString();
                final orderId = row['order_id'].toString();
                if (!validOrderIds.contains(orderId)) continue;
                var productId = row['product_id']?.toString() ?? '';
                final productName = itemCols.contains('product_name')
                    ? (row['product_name']?.toString() ?? 'Ürün')
                    : 'Ürün';
                final barcode = itemCols.contains('barcode')
                    ? row['barcode']?.toString()
                    : null;
                final qty = (row['quantity'] as num?)?.toDouble() ?? 1.0;
                final rawPrice = (row['unit_price'] as num?)?.toDouble() ?? 0.0;
                final unitPriceCents = (rawPrice * 100).round();
                final rawTotal = itemCols.contains('total_price')
                    ? ((row['total_price'] as num?)?.toDouble() ?? (qty * rawPrice))
                    : (qty * rawPrice);
                final totalCents = (rawTotal * 100).round();
                final createdAtVal = row['created_at'];
                final int createdAtMs = createdAtVal is int
                    ? createdAtVal
                    : DateTime.tryParse(createdAtVal?.toString() ?? '')?.millisecondsSinceEpoch ??
                        DateTime.now().millisecondsSinceEpoch;

                if (!validProductIds.contains(productId)) {
                  final placeholderId = productId.isNotEmpty ? productId : 'p-order-orphaned';
                  await txn.insert(
                    'products',
                    {
                      'id': placeholderId,
                      'barcode': barcode ?? 'ORPHAN-$placeholderId',
                      'name': productName,
                      'price_cents': unitPriceCents,
                      'vat_rate': 20,
                      'unit': 'piece',
                      'stock_quantity': 0,
                      'critical_threshold': 0,
                      'is_active': 0,
                      'is_deleted': 1,
                      'updated_at': DateTime.now().millisecondsSinceEpoch,
                    },
                    conflictAlgorithm: ConflictAlgorithm.ignore,
                  );
                  validProductIds.add(placeholderId);
                  productId = placeholderId;
                }

                batch.insert(
                  'order_items',
                  {
                    'id': id,
                    'order_id': orderId,
                    'product_id': productId,
                    'barcode': barcode,
                    'product_name': productName,
                    'quantity': qty,
                    'unit_price_cents': unitPriceCents,
                    'total_cents': totalCents,
                    'created_at': createdAtMs,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
                batchCount++;
                if (batchCount >= 1000) {
                  await batch.commit(noResult: true);
                  batch = txn.batch();
                  batchCount = 0;
                }
              }
              if (batchCount > 0) {
                await batch.commit(noResult: true);
              }
            }
          }
        }

        // ── 10. MÜŞTERİ TAKSİTLERİ VE PLANLARI (FULL SCOPE) ────────────────
        if (fullScope) {
          final legacyPlansTable = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='customer_installment_plans'",
          );
          if (legacyPlansTable.isNotEmpty) {
            final plans = await legacyDb.query('customer_installment_plans');
            var batch = txn.batch();
            for (final row in plans) {
              final id = row['id'].toString();
              final cid = row['customer_id'].toString();
              if (!validCustomerIds.contains(cid)) continue;
              final rawTotal = (row['total_amount'] as num?)?.toDouble() ?? 0.0;
              final rawDown = (row['down_payment'] as num?)?.toDouble() ?? 0.0;
              final count = (row['installment_count'] as num?)?.toInt() ?? 1;
              final desc = row['description']?.toString();
              final status = row['status']?.toString() ?? 'active';
              final isDel = (row['is_deleted'] as int?) ?? 0;
              final cAt = DateTime.tryParse(row['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
              final uAt = DateTime.tryParse(row['updated_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? cAt;

              batch.insert(
                'customer_installment_plans',
                {
                  'id': id,
                  'customer_id': cid,
                  'total_amount_cents': (rawTotal * 100).round(),
                  'down_payment_cents': (rawDown * 100).round(),
                  'installment_count': count,
                  'description': desc,
                  'status': status,
                  'is_deleted': isDel,
                  'created_at': cAt,
                  'updated_at': uAt,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
            await batch.commit(noResult: true);

            final legacyInstTable = await legacyDb.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='customer_installments'",
            );
            if (legacyInstTable.isNotEmpty) {
              final insts = await legacyDb.query('customer_installments');
              batch = txn.batch();
              for (final row in insts) {
                final id = row['id'].toString();
                final planId = row['plan_id'].toString();
                final cid = row['customer_id'].toString();
                final no = (row['installment_no'] as num?)?.toInt() ?? 1;
                final rawAmt = (row['amount'] as num?)?.toDouble() ?? 0.0;
                final rawPaid = (row['paid_amount'] as num?)?.toDouble() ?? 0.0;
                final dueDateStr = row['due_date']?.toString();
                final int dueDateMs = DateTime.tryParse(dueDateStr ?? '')?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
                final status = row['status']?.toString() ?? 'pending';
                final paidAtStr = row['paid_at']?.toString();
                final int? paidAtMs = paidAtStr != null ? DateTime.tryParse(paidAtStr)?.millisecondsSinceEpoch : null;
                final txId = row['financial_transaction_id']?.toString();
                final isDel = (row['is_deleted'] as int?) ?? 0;
                final cAt = DateTime.tryParse(row['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch;
                final uAt = DateTime.tryParse(row['updated_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? cAt;

                batch.insert(
                  'customer_installments',
                  {
                    'id': id,
                    'plan_id': planId,
                    'customer_id': cid,
                    'installment_no': no,
                    'amount_cents': (rawAmt * 100).round(),
                    'paid_amount_cents': (rawPaid * 100).round(),
                    'due_date': dueDateMs,
                    'status': status,
                    'paid_at': paidAtMs,
                    'financial_transaction_id': txId,
                    'is_deleted': isDel,
                    'created_at': cAt,
                    'updated_at': uAt,
                  },
                  conflictAlgorithm: ConflictAlgorithm.ignore,
                );
                instCount++;
              }
              await batch.commit(noResult: true);
            }
          }
        }

        // ── 11. KASA SAYIMLARI VE GİDERLER (FULL SCOPE) ────────────────────
        if (fullScope) {
          final legacyCountsTable = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='cash_counts'",
          );
          if (legacyCountsTable.isNotEmpty) {
            final counts = await legacyDb.query('cash_counts');
            var batch = txn.batch();
            for (final row in counts) {
              final id = row['id'].toString();
              final dateVal = row['date'] ?? row['count_date'];
              final int dateMs = dateVal is int
                  ? dateVal
                  : DateTime.tryParse(dateVal?.toString() ?? '')?.millisecondsSinceEpoch ??
                      DateTime.now().millisecondsSinceEpoch;
              final rawExp = (row['expected_amount'] as num?)?.toDouble() ?? 0.0;
              final rawAct = (row['actual_amount'] as num?)?.toDouble() ?? 0.0;
              final rawDiff = (row['difference'] as num?)?.toDouble() ?? (rawAct - rawExp);
              final notes = row['notes']?.toString();
              final createdBy = row['created_by']?.toString();
              final createdAtVal = row['created_at'];
              final int createdAtMs = createdAtVal is int
                  ? createdAtVal
                  : DateTime.tryParse(createdAtVal?.toString() ?? '')?.millisecondsSinceEpoch ?? dateMs;

              batch.insert(
                'cash_counts',
                {
                  'id': id,
                  'count_date': dateMs,
                  'expected_amount_cents': (rawExp * 100).round(),
                  'actual_amount_cents': (rawAct * 100).round(),
                  'difference_cents': (rawDiff * 100).round(),
                  'notes': notes,
                  'created_by': createdBy,
                  'created_at': createdAtMs,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
              cashCount++;
            }
            await batch.commit(noResult: true);
          }

          final legacyExpTable = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='cash_expenses'",
          );
          if (legacyExpTable.isNotEmpty) {
            final expenses = await legacyDb.query('cash_expenses');
            var batch = txn.batch();
            for (final row in expenses) {
              final id = row['id'].toString();
              final rawAmt = (row['amount'] as num?)?.toDouble() ?? 0.0;
              final cat = row['category']?.toString() ?? 'Genel';
              final desc = row['description']?.toString();
              final dateVal = row['expense_date'] ?? row['date'];
              final int dateMs = dateVal is int
                  ? dateVal
                  : DateTime.tryParse(dateVal?.toString() ?? '')?.millisecondsSinceEpoch ??
                      DateTime.now().millisecondsSinceEpoch;
              final createdBy = row['created_by']?.toString();
              final createdAtVal = row['created_at'];
              final int createdAtMs = createdAtVal is int
                  ? createdAtVal
                  : DateTime.tryParse(createdAtVal?.toString() ?? '')?.millisecondsSinceEpoch ?? dateMs;

              batch.insert(
                'cash_expenses',
                {
                  'id': id,
                  'amount_cents': (rawAmt * 100).round(),
                  'category': cat,
                  'description': desc,
                  'expense_date': dateMs,
                  'created_by': createdBy,
                  'created_at': createdAtMs,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
            await batch.commit(noResult: true);
          }
        }

        // ── 12. ADLİ DENETİM KAYITLARI (FULL SCOPE) ─────────────────────────
        if (fullScope) {
          final legacyAuditTable = await legacyDb.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='audit_events'",
          );
          if (legacyAuditTable.isNotEmpty) {
            final auditRows = await legacyDb.query('audit_events');
            var batch = txn.batch();
            int batchCount = 0;
            for (final row in auditRows) {
              final id = row['id'].toString();
              final eventType = row['event_type']?.toString() ?? '';
              final entityType = row['entity_type']?.toString() ?? '';
              final entityId = row['entity_id']?.toString() ?? '';
              final userId = row['user_id']?.toString();
              final userName = row['user_name']?.toString();
              final oldValue = row['old_value']?.toString();
              final newValue = row['new_value']?.toString();
              final tsVal = row['timestamp'];
              final int tsMs = tsVal is int
                  ? tsVal
                  : DateTime.tryParse(tsVal?.toString() ?? '')?.millisecondsSinceEpoch ??
                      DateTime.now().millisecondsSinceEpoch;
              final deviceId = row['device_id']?.toString();
              final notes = row['notes']?.toString();
              final prevHash = row['previous_hash']?.toString();
              final recHash = row['record_hash']?.toString();

              batch.insert(
                'audit_events',
                {
                  'id': id,
                  'event_type': eventType,
                  'entity_type': entityType,
                  'entity_id': entityId,
                  'user_id': userId,
                  'user_name': userName,
                  'old_value': oldValue,
                  'new_value': newValue,
                  'timestamp': tsMs,
                  'device_id': deviceId,
                  'notes': notes,
                  'previous_hash': prevHash,
                  'record_hash': recHash,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
              auditCount++;
              batchCount++;
              if (batchCount >= 1000) {
                await batch.commit(noResult: true);
                batch = txn.batch();
                batchCount = 0;
              }
            }
            if (batchCount > 0) {
              await batch.commit(noResult: true);
            }
          }
        }

        // ── 13. MİGRASYON TAMAMLANDI BAYRAĞI & İŞLETME KİMLİĞİ ──────────────
        final legacySettingsCheck = await legacyDb.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('settings', 'business_profile')",
        );
        String? bName;
        String? bTax;
        if (legacySettingsCheck.any((r) => r['name'] == 'settings')) {
          final sRows = await legacyDb.query('settings', limit: 1);
          if (sRows.isNotEmpty) {
            bName = sRows.first['business_name']?.toString();
            bTax = sRows.first['business_tax_id']?.toString();
          }
        }
        if (bName == null && legacySettingsCheck.any((r) => r['name'] == 'business_profile')) {
          final bpRows = await legacyDb.query('business_profile', limit: 1);
          if (bpRows.isNotEmpty) {
            bName = bpRows.first['name']?.toString();
            bTax = bpRows.first['tax_number']?.toString();
          }
        }

        final tenantSlug = (bName != null && bName.toLowerCase().contains('nutopia'))
            ? 'nutopia'
            : (bName != null && bName.toLowerCase().contains('serenut'))
                ? 'serenut'
                : 'legacy_store';

        if (bName != null) {
          await txn.insert(
            'app_settings',
            {'key': 'business_name', 'value': bName, 'updated_at': DateTime.now().millisecondsSinceEpoch},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        if (bTax != null) {
          await txn.insert(
            'app_settings',
            {'key': 'business_tax_id', 'value': bTax, 'updated_at': DateTime.now().millisecondsSinceEpoch},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
        await txn.insert(
          'app_settings',
          {'key': 'tenant_id', 'value': tenantSlug, 'updated_at': DateTime.now().millisecondsSinceEpoch},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.insert(
          'app_settings',
          {
            'key': 'legacy_migration_completed',
            'value': 'true',
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      });

      stopwatch.stop();
      return MigrationReport(
        productsMigrated: pCount,
        customersMigrated: cCount,
        salesMigrated: sCount,
        ledgerEntriesMigrated: lCount,
        categoriesMigrated: catCount,
        saleItemsMigrated: itemCount,
        usersMigrated: uCount,
        syncEventsMigrated: syncCount,
        ordersMigrated: orderCount,
        installmentsMigrated: instCount,
        auditEventsMigrated: auditCount,
        cashCountsMigrated: cashCount,
        cashTransactionsMigrated: cashTxCount,
        durationMs: stopwatch.elapsedMilliseconds,
        isSuccess: true,
        customerDiscrepancies: discrepancies,
      );
    } catch (e) {
      stopwatch.stop();
      return MigrationReport(
        productsMigrated: pCount,
        customersMigrated: cCount,
        salesMigrated: sCount,
        ledgerEntriesMigrated: lCount,
        categoriesMigrated: catCount,
        saleItemsMigrated: itemCount,
        usersMigrated: uCount,
        syncEventsMigrated: syncCount,
        ordersMigrated: orderCount,
        installmentsMigrated: instCount,
        auditEventsMigrated: auditCount,
        cashCountsMigrated: cashCount,
        cashTransactionsMigrated: cashTxCount,
        durationMs: stopwatch.elapsedMilliseconds,
        isSuccess: false,
        errorMessage: e.toString(),
        customerDiscrepancies: discrepancies,
      );
    }
  }

  /// Erkul Çeyiz gibi buluttan / PostgreSQL'den JSON olarak indirilen veriyi
  /// kuruş bazlı Core Next mimarisine tam mutabakat ve sıfır kayıpla aktarır.
  /// Resmi ErkulJsonImporter adaptörüne delege eder.
  Future<MigrationReport> migrateFromErkulJson(Map<String, dynamic> jsonMap) async {
    final importer = ErkulJsonImporter(targetDb);
    final report = await importer.importFromJson(jsonMap);

    return MigrationReport(
      productsMigrated: report.productsMigrated,
      customersMigrated: report.customersMigrated,
      salesMigrated: report.salesMigrated,
      ledgerEntriesMigrated: report.ledgerEntriesMigrated,
      categoriesMigrated: report.categoriesMigrated,
      saleItemsMigrated: report.saleItemsMigrated,
      usersMigrated: report.usersMigrated,
      ordersMigrated: report.ordersMigrated,
      durationMs: report.durationMs,
      isSuccess: report.isSuccess,
      errorMessage: report.errorMessage,
    );
  }

  /// Safely resolves the transaction amount in cents from legacy floating-point and minor unit fields.
  ///
  /// Contract rules:
  /// 1. If [rawMinorNum] and [rawAmountNum] both resolve to the same cents, that value is used.
  /// 2. If [rawMinorNum] is null, [rawAmountNum] is authoritative: (rawAmount * 100).round().
  /// 3. In the legacy SQLite schema, `amount_minor` was created with `DEFAULT 0`.
  ///    Legacy repositories wrote `amount` (e.g. 5000.0) without populating `amount_minor`.
  ///    Therefore, if `minorCents == 0` while `expectedFromAmount != 0`, the 0 is an unpopulated
  ///    default and `expectedFromAmount` is authoritative.
  /// 4. If `expectedFromAmount == 0` while `minorCents != 0`, `minorCents` is authoritative.
  /// 5. If both are 0, amount is legitimate 0 cents.
  /// 6. If both are non-zero but conflict, the trigger-enforced and view-authoritative
  ///    `expectedFromAmount` is used, and a discrepancy can be documented.
  static int resolveAmountCents({
    required num? rawAmountNum,
    required num? rawMinorNum,
  }) {
    final rawAmount = rawAmountNum?.toDouble() ?? 0.0;
    final expectedFromAmount = (rawAmount * 100).round();

    if (rawMinorNum == null) {
      return expectedFromAmount;
    }

    final minorCents = rawMinorNum.toInt();
    if (minorCents == expectedFromAmount) {
      return minorCents;
    }

    // Unpopulated legacy default column (DEFAULT 0)
    if (minorCents == 0 && expectedFromAmount != 0) {
      return expectedFromAmount;
    }

    // Minor cents explicitly provided while rawAmount is 0
    if (expectedFromAmount == 0 && minorCents != 0) {
      return minorCents;
    }

    // Conflicting non-zero values: In legacy SQLite, db triggers (trg_ft_insert)
    // and official accounting view (v_customer_ledger_effect) operate exclusively on `amount`.
    return expectedFromAmount;
  }
}

/// Core Next (v3) Sisteminden Eski Legacy (v60) Sistemine Geri Dönüş (Rollback) Motoru.
/// 
/// Sıfır Veri Kaybı Prensibi:
/// 1. Karma ödemeler (`sale_payments`) legacy `payment_method = 'mixed'` ve detaylı `notes` ile korunur.
/// 2. İadeler negatif satış olarak değil, legacy `refunds` ve `refund_items` tablolarına dönüştürülür.
/// 3. PENDING, IN_FLIGHT ve TRANSIENT_ERROR durumundaki kuyruk olayları legacy outbox'a iade edilir.
class ReverseMigrationEngine {
  static Future<ReverseMigrationReport> rollbackToLegacy({
    required Database legacyDb,
    required CoreAppDatabase coreDb,
  }) async {
    final stopwatch = Stopwatch()..start();
    int sExported = 0;
    int itemsExported = 0;
    int cUpdated = 0;
    int pUpdated = 0;
    int lExported = 0;
    int syncExported = 0;

    try {
      await legacyDb.transaction((txn) async {
        // 1. Yeni Satışlar ve İadeler (İçerik Çakışması Korumalı)
        final legacySaleRows = await txn.query('sales');
        final legacySaleMap = {for (final r in legacySaleRows) r['id'].toString(): r};

        final coreSales = await coreDb.db.query('sales');
        final newSales = <Map<String, dynamic>>[];

        for (final s in coreSales) {
          final sId = s['id'].toString();
          if (legacySaleMap.containsKey(sId)) {
            // İkisi de aynı satış ID'sine sahip: Derin Çok Boyutlu İçerik Sapması (Deep Content Divergence) Kontrolü
            final legacySale = legacySaleMap[sId]!;
            final coreTotalCents = (s['total_cents'] as num).toInt();
            final legacyTotalCents = legacySale.containsKey('total_amount_minor') &&
                    legacySale['total_amount_minor'] != null &&
                    (legacySale['total_amount_minor'] as num).toInt() != 0
                ? (legacySale['total_amount_minor'] as num).toInt()
                : ((legacySale['total_amount'] as num).toDouble() * 100).round();

            // 1. Tutar Karşılaştırması
            if (legacyTotalCents != coreTotalCents) {
              throw StateError(
                'SATIŞ İÇERİK ÇAKIŞMASI TESPİT EDİLDİ! '
                'Satış [$sId] her iki sistemde mevcut ancak tutarları farklı '
                '(Legacy: $legacyTotalCents kuruş, Core Next: $coreTotalCents kuruş). '
                'Aynı ID ile içerik sapması olan işlem sessizce atlanamaz veya ezilemez.',
              );
            }

            // 2. Müşteri (Cari) Kimliği Karşılaştırması
            final legacyCustId = legacySale['customer_id']?.toString();
            final coreCustId = s['customer_id']?.toString();
            if (legacyCustId != null &&
                coreCustId != null &&
                legacyCustId != coreCustId &&
                legacyCustId != 'customer-pesin-default') {
              throw StateError(
                'SATIŞ MÜŞTERİ ÇAKIŞMASI TESPİT EDİLDİ! '
                'Satış [$sId] müşteri kimliği uyuşmuyor '
                '(Legacy: $legacyCustId, Core Next: $coreCustId).',
              );
            }

            // 3. Kalem (Items) İçerik ve Miktar Karşılaştırması
            final hasLegacyItems = await txn.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='sale_items'",
            );
            if (hasLegacyItems.isNotEmpty) {
              final legItems = await txn.query('sale_items', where: 'sale_id = ?', whereArgs: [sId]);
              final coreItems = await coreDb.db.query('sale_items', where: 'sale_id = ?', whereArgs: [sId]);

              if (legItems.isNotEmpty || coreItems.isNotEmpty) {
                if (legItems.length != coreItems.length) {
                  throw StateError(
                    'SATIŞ KALEM SAYISI ÇAKIŞMASI TESPİT EDİLDİ! '
                    'Satış [$sId] kalem sayısı uyuşmuyor '
                    '(Legacy: ${legItems.length}, Core Next: ${coreItems.length}).',
                  );
                }

                final legItemProductMap = <String, double>{};
                for (final li in legItems) {
                  final pid = li['product_id']?.toString() ?? '';
                  legItemProductMap[pid] = (legItemProductMap[pid] ?? 0.0) + (li['quantity'] as num).toDouble();
                }

                for (final ci in coreItems) {
                  final pid = ci['product_id']?.toString() ?? '';
                  final cQty = (ci['quantity'] as num).toDouble();
                  final legQty = legItemProductMap[pid] ?? 0.0;
                  if ((legQty - cQty).abs() > 0.001) {
                    throw StateError(
                      'SATIŞ KALEM DETAY ÇAKIŞMASI TESPİT EDİLDİ! '
                      'Satış [$sId] için ürün [$pid] miktarı uyuşmuyor '
                      '(Legacy: $legQty, Core Next: $cQty).',
                    );
                  }
                }
              }
            }

            // 4. Ödeme Yöntemi ve Dağılım Karşılaştırması
            final corePayments = await coreDb.db.query('sale_payments', where: 'sale_id = ?', whereArgs: [sId]);
            final hasLegacyPayments = await txn.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='sale_payments'",
            );
            if (hasLegacyPayments.isNotEmpty) {
              final legPayments = await txn.query('sale_payments', where: 'sale_id = ?', whereArgs: [sId]);
              if (legPayments.isNotEmpty && corePayments.isNotEmpty) {
                final legPaymentMap = <String, int>{};
                for (final lp in legPayments) {
                  final type = lp['payment_type']?.toString() ?? 'cash';
                  final amt = (lp['amount_minor'] as num? ?? ((lp['amount'] as num).toDouble() * 100).round()).toInt();
                  legPaymentMap[type] = (legPaymentMap[type] ?? 0) + amt;
                }

                for (final cp in corePayments) {
                  final type = cp['payment_type']?.toString() ?? 'cash';
                  final amt = (cp['amount_cents'] as num).toInt();
                  final legAmt = legPaymentMap[type] ?? 0;
                  if (legAmt != amt) {
                    throw StateError(
                      'SATIŞ ÖDEME DAĞILIM ÇAKIŞMASI TESPİT EDİLDİ! '
                      'Satış [$sId] için [$type] ödeme tutarı uyuşmuyor '
                      '(Legacy: $legAmt kuruş, Core Next: $amt kuruş).',
                    );
                  }
                }
              }
            }
            // Tüm alanlar tam uyuşuyorsa: Güvenli idempotent tekrar (tekrar aktarılmaz)
          } else {
            newSales.add(s);
          }
        }

        // 0. Eksik Kayıt Türleri Korunumu: Cari ve Ürünler öncelikli olarak aktarılır

        // C) Yeni Müşterilerin (Cari) Kayıpsız Geri Aktarımı
        final legacyCustRows = await txn.query('customers', columns: ['id']);
        final existingLegacyCustIds = legacyCustRows.map((r) => r['id'].toString()).toSet();
        final newlyInsertedCustIds = <String>{};
        final custCols = await _getTableColumns(txn, 'customers');
        final coreCustAll = await coreDb.db.query('customers');

        for (final cc in coreCustAll) {
          final cid = cc['id'].toString();
          if (!existingLegacyCustIds.contains(cid)) {
            final int balCents = (cc['balance_cents'] as num? ?? 0).toInt();
            final int creditLimitCents = (cc['credit_limit_cents'] as num? ?? 0).toInt();
            final name = cc['name']?.toString() ?? 'Yeni Müşteri ($cid)';
            final isActive = (cc['is_active'] as num?)?.toInt() ?? 1;
            final isDeleted = (cc['is_deleted'] as num?)?.toInt() ?? 0;

            final custMap = <String, dynamic>{
              'id': cid,
              'name': name,
              'balance': balCents / 100.0,
            };
            if (custCols.contains('normalized_name')) {
              custMap['normalized_name'] = name.toLowerCase().trim();
            }
            if (custCols.contains('phone')) custMap['phone'] = cc['phone']?.toString();
            if (custCols.contains('email')) {
              final em = cc['email']?.toString();
              custMap['email'] = em;
              if (custCols.contains('normalized_email') && em != null) {
                custMap['normalized_email'] = em.toLowerCase().trim();
              }
            }
            if (custCols.contains('balance_minor')) custMap['balance_minor'] = balCents;
            if (custCols.contains('credit_limit')) custMap['credit_limit'] = creditLimitCents / 100.0;
            if (custCols.contains('credit_limit_minor')) custMap['credit_limit_minor'] = creditLimitCents;
            if (custCols.contains('status')) custMap['status'] = isActive == 1 ? 'active' : 'inactive';
            if (custCols.contains('is_active')) custMap['is_active'] = isActive;
            if (custCols.contains('is_deleted')) custMap['is_deleted'] = isDeleted;
            if (custCols.contains('is_synced')) custMap['is_synced'] = 1;
            if (custCols.contains('address')) custMap['address'] = cc['tax_office']?.toString();
            if (custCols.contains('created_at')) {
              custMap['created_at'] = DateTime.fromMillisecondsSinceEpoch(
                (cc['created_at'] as num? ?? DateTime.now().millisecondsSinceEpoch).toInt(),
              ).toIso8601String();
            }
            if (custCols.contains('updated_at')) {
              custMap['updated_at'] = DateTime.now().toIso8601String();
            }
            await txn.insert('customers', custMap, conflictAlgorithm: ConflictAlgorithm.replace);
            existingLegacyCustIds.add(cid);
            newlyInsertedCustIds.add(cid);
            cUpdated++;
          }
        }

        // D) Yeni Ürünlerin (Katalog) Kayıpsız Geri Aktarımı
        final legacyProdRows = await txn.query('products', columns: ['id']);
        final existingLegacyProdIds = legacyProdRows.map((r) => r['id'].toString()).toSet();
        final newlyInsertedProductIds = <String>{};
        final prodCols = await _getTableColumns(txn, 'products');
        final coreProdAll = await coreDb.db.query('products');

        for (final cp in coreProdAll) {
          final pid = cp['id'].toString();
          if (!existingLegacyProdIds.contains(pid)) {
            final priceCents = (cp['price_cents'] as num? ?? 0).toInt();
            final costPriceCents = (cp['cost_price_cents'] as num? ?? 0).toInt();
            final stock = (cp['stock_quantity'] as num? ?? 0.0).toDouble();
            final unit = cp['unit']?.toString() ?? 'adet';
            final isWeight = (unit == 'kg' || unit == 'gram');
            final barcode = cp['barcode']?.toString() ?? pid;
            final isActive = (cp['is_active'] as num?)?.toInt() ?? 1;
            final isDeleted = (cp['is_deleted'] as num?)?.toInt() ?? 0;
            final vatRate = (cp['vat_rate'] as num?)?.toInt() ?? 20;

            final pMap = <String, dynamic>{
              'id': pid,
              'name': cp['name']?.toString() ?? 'Yeni Ürün ($pid)',
              'price': priceCents / 100.0,
              'quantity': stock,
            };
            if (prodCols.contains('sku')) pMap['sku'] = barcode;
            if (prodCols.contains('barcode')) pMap['barcode'] = barcode;
            if (prodCols.contains('price_minor')) pMap['price_minor'] = priceCents;
            if (prodCols.contains('purchase_price')) pMap['purchase_price'] = costPriceCents / 100.0;
            if (prodCols.contains('purchase_price_minor')) pMap['purchase_price_minor'] = costPriceCents;
            if (prodCols.contains('unit')) pMap['unit'] = unit;
            if (prodCols.contains('sale_type')) pMap['sale_type'] = isWeight ? 'weight' : 'piece';
            if (prodCols.contains('category')) pMap['category'] = cp['category_id']?.toString() ?? 'Genel';
            if (prodCols.contains('min_stock')) {
              pMap['min_stock'] = (cp['critical_threshold'] as num?)?.toInt() ?? 5;
            }
            if (prodCols.contains('brand')) pMap['brand'] = '';
            if (prodCols.contains('shelf_code')) pMap['shelf_code'] = '';
            if (prodCols.contains('origin')) pMap['origin'] = 'TÜRKİYE';
            if (prodCols.contains('vat')) pMap['vat'] = vatRate;
            if (prodCols.contains('is_active')) pMap['is_active'] = isActive;
            if (prodCols.contains('is_deleted')) pMap['is_deleted'] = isDeleted;
            if (prodCols.contains('is_synced')) pMap['is_synced'] = 1;
            if (prodCols.contains('created_at')) {
              pMap['created_at'] = DateTime.fromMillisecondsSinceEpoch(
                (cp['created_at'] as num? ?? DateTime.now().millisecondsSinceEpoch).toInt(),
              ).toIso8601String();
            }
            if (prodCols.contains('updated_at')) {
              pMap['updated_at'] = DateTime.now().toIso8601String();
            }
            await txn.insert('products', pMap, conflictAlgorithm: ConflictAlgorithm.replace);
            existingLegacyProdIds.add(pid);
            newlyInsertedProductIds.add(pid);
            pUpdated++;
          }
        }

        // E) Cari Kontrolü: Legacy sales.customer_id için varsayılan cari
        String defaultCustId = existingLegacyCustIds.isNotEmpty ? existingLegacyCustIds.first : 'customer-pesin-default';
        if (!existingLegacyCustIds.contains('customer-pesin-default') && !existingLegacyCustIds.contains(defaultCustId)) {
          final custMap = <String, dynamic>{
            'id': 'customer-pesin-default',
            'name': 'Genel Müşteri (Peşin)',
            'balance': 0.0,
          };
          if (custCols.contains('balance_minor')) custMap['balance_minor'] = 0;
          if (custCols.contains('created_at')) custMap['created_at'] = DateTime.now().toIso8601String();
          if (custCols.contains('updated_at')) custMap['updated_at'] = DateTime.now().toIso8601String();
          await txn.insert(
            'customers',
            custMap,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          defaultCustId = 'customer-pesin-default';
        }

        final legacySalesCols = await _getTableColumns(txn, 'sales');

        for (final sale in newSales) {
          final saleId = sale['id'].toString();
          final int totalCents = (sale['total_cents'] as num).toInt();
          final int paidCents = (sale['paid_cents'] as num).toInt();
          final int discountCents = (sale['discount_cents'] as num? ?? 0).toInt();
          final String status = sale['status']?.toString() ?? 'completed';

          final rawCustId = sale['customer_id']?.toString();
          final String custId = (rawCustId != null && existingLegacyCustIds.contains(rawCustId))
              ? rawCustId
              : defaultCustId;

          final createdAtMs = (sale['created_at'] as num).toInt();
          final createdAtIso = DateTime.fromMillisecondsSinceEpoch(createdAtMs).toIso8601String();

          // ── A) İADE (REFUND) AYRIŞMASI ─────────────────────────────────────
          if (status == 'REFUND' || totalCents < 0) {
            final hasRefundsTable = await txn.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='refunds'",
            );
            if (hasRefundsTable.isNotEmpty) {
              final rawReceipt = sale['receipt_no']?.toString() ?? '';
              String origSaleId = '';

              if (rawReceipt.startsWith('REF-')) {
                final candidate = rawReceipt.replaceFirst('REF-', '');
                final byId = await txn.query('sales', where: 'id = ?', whereArgs: [candidate], limit: 1);
                if (byId.isNotEmpty) {
                  origSaleId = candidate;
                } else if (legacySalesCols.contains('receipt_no')) {
                  final origReceipt = candidate.split('-').first;
                  final origRows = await txn.query(
                    'sales',
                    where: 'receipt_no LIKE ?',
                    whereArgs: ['$origReceipt%'],
                    limit: 1,
                  );
                  if (origRows.isNotEmpty) {
                    origSaleId = origRows.first['id'].toString();
                  }
                }
              }
              if (origSaleId.isEmpty) {
                final anySale = await txn.query('sales', limit: 1);
                origSaleId = anySale.isNotEmpty ? anySale.first['id'].toString() : saleId;
              }

              final existingRefund = await txn.query('refunds', where: 'id = ?', whereArgs: [saleId]);
              final double refundAmount = totalCents.abs() / 100.0;
              if (existingRefund.isNotEmpty) {
                final legAmtCents = (((existingRefund.first['amount'] as num).toDouble()) * 100).round();
                if (legAmtCents != totalCents.abs()) {
                  throw StateError(
                    'İADE TUTAR ÇAKIŞMASI TESPİT EDİLDİ! İade [$saleId] tutarı uyuşmuyor '
                    '(Legacy: $legAmtCents kuruş, Core: ${totalCents.abs()} kuruş).',
                  );
                }

                // 2. İlişkili Satış ID Karşılaştırması
                final legSaleId = existingRefund.first['sale_id']?.toString();
                if (legSaleId != null && legSaleId.isNotEmpty && origSaleId.isNotEmpty && legSaleId != origSaleId && origSaleId != saleId) {
                  throw StateError(
                    'İADE İLİŞKİLİ SATIŞ ÇAKIŞMASI TESPİT EDİLDİ! '
                    'İade [$saleId] ilişkili satış kimliği uyuşmuyor (Legacy: $legSaleId, Core: $origSaleId).',
                  );
                }

                // 3. İade Kalemleri (Items) Karşılaştırması
                final hasRefundItemsTable = await txn.rawQuery(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name='refund_items'",
                );
                if (hasRefundItemsTable.isNotEmpty) {
                  final legRefItems = await txn.query('refund_items', where: 'refund_id = ?', whereArgs: [saleId]);
                  final coreItems = await coreDb.db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
                  if (legRefItems.isNotEmpty || coreItems.isNotEmpty) {
                    if (legRefItems.length != coreItems.length) {
                      throw StateError(
                        'İADE KALEM SAYISI ÇAKIŞMASI TESPİT EDİLDİ! '
                        'İade [$saleId] kalem sayısı uyuşmuyor (Legacy: ${legRefItems.length}, Core: ${coreItems.length}).',
                      );
                    }
                    final legItemMap = <String, double>{};
                    for (final lri in legRefItems) {
                      final pid = lri['product_id']?.toString() ?? '';
                      legItemMap[pid] = (legItemMap[pid] ?? 0.0) + (lri['quantity'] as num).toDouble();
                    }
                    for (final ci in coreItems) {
                      final pid = ci['product_id']?.toString() ?? '';
                      final cQty = (ci['quantity'] as num).toDouble().abs();
                      final lQty = legItemMap[pid] ?? 0.0;
                      if ((lQty - cQty).abs() > 0.001) {
                        throw StateError(
                          'İADE KALEM DETAY ÇAKIŞMASI TESPİT EDİLDİ! '
                          'İade [$saleId] için ürün [$pid] miktarı uyuşmuyor (Legacy: $lQty, Core: $cQty).',
                        );
                      }
                    }
                  }
                }

                sExported++;
                continue; // Tutar, ilişkili satış ve kalemler aynıysa güvenli idempotent tekrar
              }

              await txn.insert(
                'refunds',
                {
                  'id': saleId,
                  'sale_id': origSaleId,
                  'amount': refundAmount,
                  'refund_method': 'cash',
                  'reason': 'Core Next İadesi',
                  'status': 'completed',
                  'created_at': createdAtIso,
                },
                conflictAlgorithm: ConflictAlgorithm.replace,
              );

              final hasRefundItemsTable = await txn.rawQuery(
                "SELECT name FROM sqlite_master WHERE type='table' AND name='refund_items'",
              );
              if (hasRefundItemsTable.isNotEmpty) {
                final coreItems = await coreDb.db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
                for (final item in coreItems) {
                  final qty = (item['quantity'] as num).toInt().abs();
                  final unitPrice = ((item['unit_price_cents'] as num).toInt()) / 100.0;
                  final subtotal = ((item['total_cents'] as num).toInt().abs()) / 100.0;
                  await txn.insert(
                    'refund_items',
                    {
                      'id': item['id'].toString(),
                      'refund_id': saleId,
                      'sale_item_id': item['id'].toString(),
                      'product_id': item['product_id']?.toString() ?? '',
                      'quantity': qty > 0 ? qty : 1,
                      'unit_refund_amount': unitPrice,
                      'subtotal': subtotal,
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace,
                  );
                }
              }

              if (legacySalesCols.contains('refunded_amount')) {
                await txn.rawUpdate(
                  '''
                  UPDATE sales 
                  SET refunded_amount = (
                    SELECT COALESCE(SUM(amount), 0.0) 
                    FROM refunds 
                    WHERE sale_id = ?
                  ), 
                  updated_at = ? 
                  WHERE id = ?
                  ''',
                  [origSaleId, DateTime.now().toIso8601String(), origSaleId],
                );
              }
              sExported++;
              continue; // Legacy sales tablosuna negatif satır yazılmaz
            }
          }

          // ── B) NORMAL SATIŞ VE KARMA ÖDEME AYRIŞMASI ────────────────────────
          final payments = await coreDb.db.query('sale_payments', where: 'sale_id = ?', whereArgs: [saleId]);
          String paymentMethod = 'cash';
          String? paymentNotes;

          if (payments.length > 1) {
            paymentMethod = 'mixed';
            final breakdown = payments
                .map((p) => '${p['payment_type']}: ${((p['amount_cents'] as num) / 100.0).toStringAsFixed(2)} TL')
                .join(', ');
            paymentNotes = 'Parçalı Ödeme Dağılımı: $breakdown';
          } else if (payments.isNotEmpty) {
            paymentMethod = payments.first['payment_type']?.toString() ?? 'cash';
          }

          final saleMap = <String, dynamic>{
            'id': saleId,
            'customer_id': custId,
            'total_amount': totalCents / 100.0,
            'payment_method': paymentMethod,
            'status': status,
            'created_at': createdAtIso,
          };
          if (legacySalesCols.contains('receipt_no')) {
            saleMap['receipt_no'] = sale['receipt_no']?.toString() ?? saleId;
          }
          if (legacySalesCols.contains('total_amount_minor')) {
            saleMap['total_amount_minor'] = totalCents;
          }
          if (legacySalesCols.contains('paid_amount')) {
            saleMap['paid_amount'] = paidCents / 100.0;
          }
          if (legacySalesCols.contains('paid_amount_minor')) {
            saleMap['paid_amount_minor'] = paidCents;
          }
          if (legacySalesCols.contains('discount_amount')) {
            saleMap['discount_amount'] = discountCents / 100.0;
          }
          if (legacySalesCols.contains('discount_amount_minor')) {
            saleMap['discount_amount_minor'] = discountCents;
          }
          if (legacySalesCols.contains('idempotency_key')) {
            saleMap['idempotency_key'] = sale['idempotency_key']?.toString();
          }
          if (legacySalesCols.contains('updated_at')) {
            saleMap['updated_at'] = createdAtIso;
          }
          if (legacySalesCols.contains('notes') && paymentNotes != null) {
            saleMap['notes'] = paymentNotes;
          }

          await txn.insert(
            'sales',
            saleMap,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          sExported++;

          // Satış kalemlerini aktar
          final hasItemsTable = await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='sale_items'");
          if (hasItemsTable.isNotEmpty) {
            final legacyItemCols = await _getTableColumns(txn, 'sale_items');
            final items = await coreDb.db.query('sale_items', where: 'sale_id = ?', whereArgs: [saleId]);
            for (final item in items) {
              final itemId = item['id'].toString();
              final int unitPriceCents = (item['unit_price_cents'] as num).toInt();
              final int itemTotalCents = (item['total_cents'] as num).toInt();
              final int qty = (item['quantity'] as num).toInt();

              final itemMap = <String, dynamic>{
                'id': itemId,
                'sale_id': saleId,
                'product_id': item['product_id']?.toString() ?? '',
                'quantity': qty.toDouble(),
                'unit_price': unitPriceCents / 100.0,
                'subtotal': itemTotalCents / 100.0,
              };
              if (legacyItemCols.contains('product_name')) {
                itemMap['product_name'] = item['product_name']?.toString() ?? '';
              }
              if (legacyItemCols.contains('created_at')) {
                itemMap['created_at'] = createdAtIso;
              }
              if (legacyItemCols.contains('updated_at')) {
                itemMap['updated_at'] = createdAtIso;
              }
              await txn.insert(
                'sale_items',
                itemMap,
                conflictAlgorithm: ConflictAlgorithm.replace,
              );
              itemsExported++;
            }
          }

          // ADV-03: Parçalı ve yapısal ödemeleri legacy sale_payments tablosuna aktar
          final hasLegacyPaymentsTable = await txn.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='sale_payments'",
          );
          if (hasLegacyPaymentsTable.isEmpty) {
            await txn.execute('''
              CREATE TABLE IF NOT EXISTS sale_payments (
                id TEXT PRIMARY KEY NOT NULL,
                sale_id TEXT NOT NULL,
                payment_type TEXT NOT NULL,
                amount REAL NOT NULL,
                amount_minor INTEGER NOT NULL,
                reference_note TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
              );
            ''');
          }
          for (final p in payments) {
            final pAmountCents = (p['amount_cents'] as num).toInt();
            await txn.insert(
              'sale_payments',
              {
                'id': p['id'].toString(),
                'sale_id': saleId,
                'payment_type': p['payment_type']?.toString() ?? 'cash',
                'amount': pAmountCents / 100.0,
                'amount_minor': pAmountCents,
                'reference_note': p['reference_note']?.toString(),
                'created_at': createdAtIso,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }

        // ── 1.5. YENİ SİPARİŞLER VE SİPARİŞ KALEMLERİNİN GERİ AKTARIMI ──────────
        final hasCoreOrdersTable = await coreDb.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='orders'",
        );
        final hasLegacyOrdersTable = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='orders'",
        );
        if (hasCoreOrdersTable.isNotEmpty && hasLegacyOrdersTable.isNotEmpty) {
          final legOrderRows = await txn.query('orders', columns: ['id']);
          final existingLegacyOrderIds = legOrderRows.map((r) => r['id'].toString()).toSet();
          final legOrderCols = await _getTableColumns(txn, 'orders');

          final coreOrders = await coreDb.db.query('orders');
          for (final co in coreOrders) {
            final oid = co['id'].toString();
            if (!existingLegacyOrderIds.contains(oid)) {
              final rawCid = co['customer_id']?.toString();
              final custId = (rawCid != null && existingLegacyCustIds.contains(rawCid))
                  ? rawCid
                  : defaultCustId;
              final totalCents = (co['total_amount_cents'] as num? ?? 0).toInt();
              final discountCents = (co['discount_amount_cents'] as num? ?? 0).toInt();
              final orderDateMs = (co['order_date'] as num? ?? co['created_at'] as num? ?? DateTime.now().millisecondsSinceEpoch).toInt();
              final orderDateIso = DateTime.fromMillisecondsSinceEpoch(orderDateMs).toIso8601String();

              final oMap = <String, dynamic>{
                'id': oid,
                'order_number': co['order_number']?.toString() ?? 'ORD-$oid',
                'customer_id': custId,
                'status': co['status']?.toString() ?? 'created',
                'total_amount': totalCents / 100.0,
                'order_date': orderDateIso,
                'created_at': DateTime.fromMillisecondsSinceEpoch(
                  (co['created_at'] as num? ?? orderDateMs).toInt(),
                ).toIso8601String(),
                'updated_at': DateTime.fromMillisecondsSinceEpoch(
                  (co['updated_at'] as num? ?? orderDateMs).toInt(),
                ).toIso8601String(),
                'is_deleted': (co['is_deleted'] as num?)?.toInt() ?? 0,
                'is_synced': 0,
              };
              if (legOrderCols.contains('discount_amount')) {
                oMap['discount_amount'] = discountCents / 100.0;
              }
              if (legOrderCols.contains('notes')) {
                oMap['notes'] = co['notes']?.toString();
              }
              if (legOrderCols.contains('created_by')) {
                oMap['created_by'] = co['created_by']?.toString();
              }
              if (legOrderCols.contains('expected_delivery_date') && co['expected_delivery_date'] != null) {
                oMap['expected_delivery_date'] = DateTime.fromMillisecondsSinceEpoch(
                  (co['expected_delivery_date'] as num).toInt(),
                ).toIso8601String();
              }
              if (legOrderCols.contains('actual_delivery_date') && co['actual_delivery_date'] != null) {
                oMap['actual_delivery_date'] = DateTime.fromMillisecondsSinceEpoch(
                  (co['actual_delivery_date'] as num).toInt(),
                ).toIso8601String();
              }

              await txn.insert('orders', oMap, conflictAlgorithm: ConflictAlgorithm.replace);
              existingLegacyOrderIds.add(oid);
            }
          }

          // Sipariş Kalemleri
          final hasCoreOrderItems = await coreDb.db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='order_items'",
          );
          final hasLegacyOrderItems = await txn.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='order_items'",
          );
          if (hasCoreOrderItems.isNotEmpty && hasLegacyOrderItems.isNotEmpty) {
            final legItemRows = await txn.query('order_items', columns: ['id']);
            final existingLegItemIds = legItemRows.map((r) => r['id'].toString()).toSet();
            final coreOrderItems = await coreDb.db.query('order_items');

            for (final ci in coreOrderItems) {
              final oiId = ci['id'].toString();
              if (!existingLegItemIds.contains(oiId)) {
                final parentOrderId = ci['order_id'].toString();
                if (!existingLegacyOrderIds.contains(parentOrderId)) continue;

                final rawPid = ci['product_id']?.toString() ?? '';
                final qty = (ci['quantity'] as num? ?? 1.0).toDouble();
                final unitPriceCents = (ci['unit_price_cents'] as num? ?? 0).toInt();
                final pName = ci['product_name']?.toString() ?? 'Ürün';

                final oiMap = <String, dynamic>{
                  'id': oiId,
                  'order_id': parentOrderId,
                  'product_id': rawPid,
                  'product_name': pName,
                  'quantity': qty,
                  'unit_price': unitPriceCents / 100.0,
                  'created_at': DateTime.fromMillisecondsSinceEpoch(
                    (ci['created_at'] as num? ?? DateTime.now().millisecondsSinceEpoch).toInt(),
                  ).toIso8601String(),
                };
                await txn.insert('order_items', oiMap, conflictAlgorithm: ConflictAlgorithm.replace);
                existingLegItemIds.add(oiId);
              }
            }
          }
        }

        // ── 1.6. YENİ TAKSİTLİ SENET SÖZLEŞMELERİ VE TAKSİT PLANI GERİ AKTARIMI ──
        final hasCoreInstallmentsTable = await coreDb.db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='installments'",
        );
        final hasLegacyPlansTable = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='customer_installment_plans'",
        );
        final hasLegacyInstTable = await txn.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name='customer_installments'",
        );

        if (hasCoreInstallmentsTable.isNotEmpty &&
            hasLegacyPlansTable.isNotEmpty &&
            hasLegacyInstTable.isNotEmpty) {
          final coreInstallments = await coreDb.db.query('installments');
          if (coreInstallments.isNotEmpty) {
            final legPlanRows = await txn.query('customer_installment_plans', columns: ['id']);
            final existingPlanIds = legPlanRows.map((r) => r['id'].toString()).toSet();

            final legInstRows = await txn.query('customer_installments', columns: ['id']);
            final existingInstIds = legInstRows.map((r) => r['id'].toString()).toSet();

            // Core taksitlerini sale_id (plan) bazında grupla
            final installmentsBySale = <String, List<Map<String, dynamic>>>{};
            for (final inst in coreInstallments) {
              final saleId = inst['sale_id']?.toString() ?? 'unknown_sale';
              installmentsBySale.putIfAbsent(saleId, () => []).add(inst);
            }

            for (final entry in installmentsBySale.entries) {
              final saleId = entry.key;
              final planInstallments = entry.value;
              final planId = 'plan-$saleId';

              final firstInst = planInstallments.first;
              final rawCid = firstInst['customer_id']?.toString();
              final custId = (rawCid != null && existingLegacyCustIds.contains(rawCid))
                  ? rawCid
                  : defaultCustId;

              int totalPlanCents = 0;
              for (final inst in planInstallments) {
                totalPlanCents += (inst['amount_cents'] as num? ?? 0).toInt();
              }

              // Bağlı satıştan peşinat ve sözleşme toplam tutarının tespiti (down_payment korunumu)
              final saleRows = await coreDb.db.query('sales', where: 'id = ?', whereArgs: [saleId], limit: 1);
              int downPaymentCents = 0;
              int contractTotalCents = totalPlanCents;
              if (saleRows.isNotEmpty) {
                final sRow = saleRows.first;
                final sTotal = (sRow['total_cents'] as num? ?? 0).toInt();
                final sPaid = (sRow['paid_cents'] as num? ?? 0).toInt();
                downPaymentCents = sPaid;
                contractTotalCents = sTotal > 0 ? sTotal : (totalPlanCents + downPaymentCents);
              }

              final bool allPaid = planInstallments.every(
                (i) => (i['is_paid'] as num?)?.toInt() == 1,
              );

              // 1. Plan Kaydı
              if (!existingPlanIds.contains(planId)) {
                await txn.insert(
                  'customer_installment_plans',
                  {
                    'id': planId,
                    'customer_id': custId,
                    'total_amount': contractTotalCents / 100.0,
                    'down_payment': downPaymentCents / 100.0,
                    'installment_count': planInstallments.length,
                    'description': 'Core Next Taksit/Senet Planı (Satış: $saleId)',
                    'status': allPaid ? 'completed' : 'active',
                    'created_at': DateTime.now().toIso8601String(),
                    'updated_at': DateTime.now().toIso8601String(),
                    'is_synced': 0,
                    'is_deleted': 0,
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                existingPlanIds.add(planId);
              }

              // 2. Her bir Taksit Kaydı
              for (final inst in planInstallments) {
                final instId = inst['id'].toString();
                if (!existingInstIds.contains(instId)) {
                  final amountCents = (inst['amount_cents'] as num? ?? 0).toInt();
                  final paidCents = (inst['paid_amount_cents'] as num? ?? 0).toInt();
                  final isPaid = (inst['is_paid'] as num?)?.toInt() == 1;
                  final dueMs = (inst['due_date'] as num? ?? DateTime.now().millisecondsSinceEpoch).toInt();
                  final dueDateStr = DateTime.fromMillisecondsSinceEpoch(dueMs)
                      .toIso8601String()
                      .substring(0, 10);

                  final status = isPaid
                      ? 'paid'
                      : (paidCents > 0 ? 'partially_paid' : 'pending');

                  await txn.insert(
                    'customer_installments',
                    {
                      'id': instId,
                      'plan_id': planId,
                      'customer_id': custId,
                      'installment_no': (inst['installment_no'] as num? ?? 1).toInt(),
                      'amount': amountCents / 100.0,
                      'paid_amount': paidCents / 100.0,
                      'due_date': dueDateStr,
                      'status': status,
                      'paid_at': isPaid ? DateTime.now().toIso8601String() : null,
                      'created_at': DateTime.now().toIso8601String(),
                      'updated_at': DateTime.now().toIso8601String(),
                      'is_synced': 0,
                      'is_deleted': 0,
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace,
                  );
                  existingInstIds.add(instId);
                }
              }
            }
          }

          // ── 1.7. MANUEL SENETLERİN (SATIŞA BAĞLI OLMAYAN PLANLAR) GERİ AKTARIMI ──
          final hasCoreStandalonePlans = await coreDb.db.rawQuery(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='customer_installment_plans'",
          );
          if (hasCoreStandalonePlans.isNotEmpty) {
            final corePlans = await coreDb.db.query('customer_installment_plans');
            final legPlanRows = await txn.query('customer_installment_plans', columns: ['id']);
            final existingPlanIds = legPlanRows.map((r) => r['id'].toString()).toSet();

            for (final cp in corePlans) {
              final pid = cp['id'].toString();
              if (!existingPlanIds.contains(pid)) {
                final rawCid = cp['customer_id']?.toString();
                final custId = (rawCid != null && existingLegacyCustIds.contains(rawCid))
                    ? rawCid
                    : defaultCustId;
                final totalCents = (cp['total_amount_cents'] as num? ?? 0).toInt();
                final downCents = (cp['down_payment_cents'] as num? ?? 0).toInt();
                final cAt = (cp['created_at'] as num? ?? DateTime.now().millisecondsSinceEpoch).toInt();
                final uAt = (cp['updated_at'] as num? ?? cAt).toInt();

                await txn.insert(
                  'customer_installment_plans',
                  {
                    'id': pid,
                    'customer_id': custId,
                    'total_amount': totalCents / 100.0,
                    'down_payment': downCents / 100.0,
                    'installment_count': (cp['installment_count'] as num? ?? 1).toInt(),
                    'description': cp['description']?.toString(),
                    'status': cp['status']?.toString() ?? 'active',
                    'created_at': DateTime.fromMillisecondsSinceEpoch(cAt).toIso8601String(),
                    'updated_at': DateTime.fromMillisecondsSinceEpoch(uAt).toIso8601String(),
                    'is_synced': 0,
                    'is_deleted': (cp['is_deleted'] as num?)?.toInt() ?? 0,
                  },
                  conflictAlgorithm: ConflictAlgorithm.replace,
                );
                existingPlanIds.add(pid);
              }
            }

            final hasCoreStandaloneInst = await coreDb.db.rawQuery(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='customer_installments'",
            );
            if (hasCoreStandaloneInst.isNotEmpty) {
              final coreInsts = await coreDb.db.query('customer_installments');
              final legInstRows = await txn.query('customer_installments', columns: ['id']);
              final existingInstIds = legInstRows.map((r) => r['id'].toString()).toSet();

              for (final ci in coreInsts) {
                final iid = ci['id'].toString();
                if (!existingInstIds.contains(iid)) {
                  final pid = ci['plan_id']?.toString() ?? '';
                  final rawCid = ci['customer_id']?.toString();
                  final custId = (rawCid != null && existingLegacyCustIds.contains(rawCid))
                      ? rawCid
                      : defaultCustId;
                  final amountCents = (ci['amount_cents'] as num? ?? 0).toInt();
                  final paidCents = (ci['paid_amount_cents'] as num? ?? 0).toInt();
                  final dueMs = (ci['due_date'] as num? ?? DateTime.now().millisecondsSinceEpoch).toInt();
                  final dueDateStr = DateTime.fromMillisecondsSinceEpoch(dueMs).toIso8601String().substring(0, 10);
                  final paidAtMs = ci['paid_at'] as num?;
                  final cAt = (ci['created_at'] as num? ?? DateTime.now().millisecondsSinceEpoch).toInt();
                  final uAt = (ci['updated_at'] as num? ?? cAt).toInt();

                  await txn.insert(
                    'customer_installments',
                    {
                      'id': iid,
                      'plan_id': pid,
                      'customer_id': custId,
                      'installment_no': (ci['installment_no'] as num? ?? 1).toInt(),
                      'amount': amountCents / 100.0,
                      'paid_amount': paidCents / 100.0,
                      'due_date': dueDateStr,
                      'status': ci['status']?.toString() ?? 'pending',
                      'paid_at': paidAtMs != null ? DateTime.fromMillisecondsSinceEpoch(paidAtMs.toInt()).toIso8601String() : null,
                      'financial_transaction_id': ci['financial_transaction_id']?.toString(),
                      'created_at': DateTime.fromMillisecondsSinceEpoch(cAt).toIso8601String(),
                      'updated_at': DateTime.fromMillisecondsSinceEpoch(uAt).toIso8601String(),
                      'is_synced': 0,
                      'is_deleted': (ci['is_deleted'] as num?)?.toInt() ?? 0,
                    },
                    conflictAlgorithm: ConflictAlgorithm.replace,
                  );
                  existingInstIds.add(iid);
                }
              }
            }
          }
        }

        // 2. Çakışma Güvenlikli Stok Uzlaştırması
        // Core Next'teki yeni satış/iadelerden kaynaklanan ürün stok değişimleri (deltas):
        final productDeltas = <String, double>{};
        for (final sale in newSales) {
          final sId = sale['id'].toString();
          final statusStr = sale['status']?.toString().toUpperCase() ?? 'COMPLETED';
          if (statusStr == 'CANCELLED' || statusStr == 'CANCELED') {
            // İptal edilmiş satışlar ürün stoklarını eksiltmez!
            continue;
          }
          final isRefund = (statusStr == 'REFUND') || ((sale['total_cents'] as num).toInt() < 0);
          final items = await coreDb.db.query('sale_items', where: 'sale_id = ?', whereArgs: [sId]);
          for (final it in items) {
            final pId = it['product_id']?.toString() ?? '';
            if (pId.isEmpty) continue;
            final qty = (it['quantity'] as num).toDouble().abs();
            if (isRefund) {
              productDeltas[pId] = (productDeltas[pId] ?? 0.0) + qty;
            } else {
              productDeltas[pId] = (productDeltas[pId] ?? 0.0) - qty;
            }
          }
        }

        final coreProducts = await coreDb.db.query('products');
        final coreProductMap = {for (final p in coreProducts) p['id'].toString(): p};

        for (final entry in productDeltas.entries) {
          final pid = entry.key;
          final delta = entry.value;
          final cp = coreProductMap[pid];
          if (cp == null || newlyInsertedProductIds.contains(pid)) continue;

          final coreStock = (cp['stock_quantity'] as num).toDouble();
          final legacyRows = await txn.query('products', where: 'id = ?', whereArgs: [pid]);
          if (legacyRows.isEmpty) continue;

          final legacyStock = (legacyRows.first['quantity'] as num).toDouble();
          final expectedLegacyBaseline = coreStock - delta;

          if ((legacyStock - expectedLegacyBaseline).abs() > 0.001) {
            throw StateError(
              'STOK ÇAKIŞMASI TESPİT EDİLDİ! '
              'Ürün: $pid için legacy stok ($legacyStock) ile beklenen baseline ($expectedLegacyBaseline) uyuşmuyor! '
              '(Core Next Satış Etkisi: $delta, Güncel Core Stok: $coreStock). '
              'Legacy üzerindeki bağımsız stok değişikliğini ezmemek için ters uzlaştırma güvenli biçimde durduruldu.',
            );
          }

          final updated = await txn.rawUpdate(
            'UPDATE products SET quantity = ? WHERE id = ?',
            [coreStock, pid],
          );
          if (updated > 0) {
            pUpdated++;
          }
        }

        // 3. Çakışma Güvenlikli Müşteri Bakiye Uzlaştırması
        // Yeni defter hareketlerinden kaynaklanan bakiye değişimleri (deltas):
        final customerDeltasCents = <String, int>{};
        final coreLedgers = await coreDb.db.query('ledger_entries');
        final hasFtTable = await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='financial_transactions'");
        final existingFtIds = <String>{};
        if (hasFtTable.isNotEmpty) {
          final legacyFtRows = await txn.query('financial_transactions', columns: ['id']);
          existingFtIds.addAll(legacyFtRows.map((r) => r['id'].toString()));
        }

        for (final le in coreLedgers) {
          final leId = le['id'].toString();
          if (existingFtIds.contains(leId)) continue;

          final cid = le['customer_id']?.toString() ?? '';
          if (cid.isEmpty) continue;
          final amtCents = (le['amount_cents'] as num).toInt();
          final type = le['entry_type']?.toString() ?? 'SALE';

          if (type == 'SALE' || type == 'DEBT') {
            customerDeltasCents[cid] = (customerDeltasCents[cid] ?? 0) - amtCents;
          } else {
            customerDeltasCents[cid] = (customerDeltasCents[cid] ?? 0) + amtCents;
          }
        }

        final coreCustomers = await coreDb.db.query('customers');
        final coreCustomerMap = {for (final c in coreCustomers) c['id'].toString(): c};

        for (final entry in customerDeltasCents.entries) {
          final cid = entry.key;
          final deltaCents = entry.value;
          final cc = coreCustomerMap[cid];
          if (cc == null || newlyInsertedCustIds.contains(cid)) continue;

          final coreBalCents = (cc['balance_cents'] as num).toInt();
          final legacyRows = await txn.query('customers', where: 'id = ?', whereArgs: [cid]);
          if (legacyRows.isEmpty) continue;

          final legacyCustCols = await _getTableColumns(txn, 'customers');
          final rawMinor = legacyRows.first['balance_minor'];
          final int legacyBalCents = (legacyCustCols.contains('balance_minor') && rawMinor is num && rawMinor.toInt() != 0)
              ? rawMinor.toInt()
              : (((legacyRows.first['balance'] as num?)?.toDouble() ?? 0.0) * 100).round();
          final expectedLegacyBalCents = coreBalCents - deltaCents;

          if (legacyBalCents != expectedLegacyBalCents) {
            throw StateError(
              'MÜŞTERİ BAKİYE ÇAKIŞMASI TESPİT EDİLDİ! '
              'Müşteri: $cid için legacy bakiye ($legacyBalCents kuruş) ile beklenen baseline ($expectedLegacyBalCents kuruş) uyuşmuyor! '
              '(Core Next Defter Etkisi: $deltaCents kuruş, Güncel Core Bakiye: $coreBalCents kuruş). '
              'Legacy üzerindeki bağımsız tahsilat/düzeltmeyi ezmemek için ters uzlaştırma güvenli biçimde durduruldu.',
            );
          }

          final custUpdateMap = <String, dynamic>{
            'balance': coreBalCents / 100.0,
          };
          if (legacyCustCols.contains('balance_minor')) {
            custUpdateMap['balance_minor'] = coreBalCents;
          }
          if (legacyCustCols.contains('updated_at')) {
            custUpdateMap['updated_at'] = DateTime.now().toIso8601String();
          }

          final updated = await txn.update(
            'customers',
            custUpdateMap,
            where: 'id = ?',
            whereArgs: [cid],
          );
          if (updated > 0) {
            cUpdated++;
          }
        }

        // 4. Cari Defter Hareketleri
        final hasFt = await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='financial_transactions'");
        if (hasFt.isNotEmpty) {
          final legacyFtCols = await _getTableColumns(txn, 'financial_transactions');
          final legacyFtRows = await txn.query('financial_transactions');
          final legacyFtMap = {for (final r in legacyFtRows) r['id'].toString(): r};

          final coreLedgers = await coreDb.db.query('ledger_entries');
          for (final le in coreLedgers) {
            final leId = le['id'].toString();
            final int amountCents = (le['amount_cents'] as num).toInt();
            final type = le['entry_type']?.toString() ?? 'SALE';

            if (legacyFtMap.containsKey(leId)) {
              final existingFt = legacyFtMap[leId]!;
              final existingAmt = (existingFt['amount'] as num).toDouble();
              final existingAmtCents = (existingAmt * 100).round();
              if (existingAmtCents != amountCents) {
                throw StateError(
                  'FİNANSAL HAREKET İÇERİK ÇAKIŞMASI TESPİT EDİLDİ! '
                  'Cari hareket [$leId] her iki sistemde farklı tutarlara sahip '
                  '(Legacy: $existingAmtCents kuruş, Core: $amountCents kuruş). '
                  'İşlem güvenli biçimde durduruldu.',
                );
              }
              final existingType = existingFt['type']?.toString().toLowerCase().trim();
              final coreType = type.toLowerCase().trim();
              bool typesMatch(String legType, String crType) {
                if (legType == crType) return true;
                if (legType == 'sale' && (crType == 'sale' || crType == 'sale_paid' || crType == 'sale_debt')) return true;
                if ((legType == 'payment' || legType == 'collection') && (crType == 'payment' || crType == 'collection')) return true;
                if ((legType == 'debt' || legType == 'manual_debt') && (crType == 'debt' || crType == 'manual_debt')) return true;
                if ((legType == 'refund' || legType == 'cancellation') && (crType == 'refund' || crType == 'cancellation')) return true;
                return false;
              }
              if (existingType != null && !typesMatch(existingType, coreType)) {
                throw StateError(
                  'FİNANSAL HAREKET TÜR ÇAKIŞMASI TESPİT EDİLDİ! '
                  'Cari hareket [$leId] türü uyuşmuyor (Legacy: $existingType, Core: $type).',
                );
              }
              final existingCust = existingFt['customer_id']?.toString();
              final coreCust = le['customer_id']?.toString();
              if (existingCust != null && coreCust != null && existingCust != coreCust && existingCust != defaultCustId) {
                throw StateError(
                  'FİNANSAL HAREKET MÜŞTERİ ÇAKIŞMASI TESPİT EDİLDİ! '
                  'Cari hareket [$leId] müşteri kimliği uyuşmuyor (Legacy: $existingCust, Core: $coreCust).',
                );
              }
              final existingRefId = existingFt['reference_id']?.toString();
              final coreRefId = le['reference_sale_id']?.toString();
              if (existingRefId != null && coreRefId != null && existingRefId.isNotEmpty && coreRefId.isNotEmpty && existingRefId != coreRefId) {
                throw StateError(
                  'FİNANSAL HAREKET KAYNAK SATIŞ ÇAKIŞMASI TESPİT EDİLDİ! '
                  'Cari hareket [$leId] kaynak satış kimliği uyuşmuyor (Legacy: $existingRefId, Core: $coreRefId).',
                );
              }
              continue; // Tutar, tür, müşteri ve kaynak satış aynıysa güvenli tekrar (idempotent), atla
            }

            final createdAtMs = (le['created_at'] as num).toInt();

            final ftMap = <String, dynamic>{
              'id': leId,
              'customer_id': le['customer_id']?.toString() ?? defaultCustId,
              'type': type,
              'amount': amountCents / 100.0,
              'created_at': DateTime.fromMillisecondsSinceEpoch(createdAtMs).toIso8601String(),
            };
            if (legacyFtCols.contains('paid_amount')) {
              ftMap['paid_amount'] = (type == 'PAYMENT' || type == 'COLLECTION') ? amountCents / 100.0 : 0.0;
            }
            if (legacyFtCols.contains('debt_amount')) {
              ftMap['debt_amount'] = (type == 'SALE' || type == 'DEBT') ? amountCents / 100.0 : 0.0;
            }
            if (legacyFtCols.contains('payment_method')) {
              ftMap['payment_method'] = 'onAccount';
            }
            if (legacyFtCols.contains('is_synced')) {
              ftMap['is_synced'] = 0;
            }
            await txn.insert(
              'financial_transactions',
              ftMap,
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            lExported++;
          }
        }

        // 5. Bekleyen Senkronizasyon Kuyruğu (Güvenli Reverse Cutover)
        final hasOutbox = await txn.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='sync_outbox_v4'");
        if (hasOutbox.isNotEmpty) {
          final legacyOutboxRows = await txn.query('sync_outbox_v4', columns: ['mutation_id']);
          final existingOutboxIds = legacyOutboxRows.map((r) => r['mutation_id'].toString()).toSet();

          final pendingEvents = await coreDb.db.query(
            'sync_events',
            where: "sync_state IN ('PENDING', 'IN_FLIGHT', 'TRANSIENT_ERROR')",
          );
          for (final ev in pendingEvents) {
            final evId = ev['event_id'].toString();
            if (existingOutboxIds.contains(evId)) continue;

            await txn.insert(
              'sync_outbox_v4',
              {
                'mutation_id': evId,
                'entity_type': ev['entity_type']?.toString() ?? 'unknown',
                'entity_id': ev['entity_id']?.toString() ?? '',
                'operation': ev['operation']?.toString() ?? 'UPSERT',
                'payload': ev['payload_json']?.toString() ?? '{}',
                'base_revision': (ev['base_revision'] as num? ?? 0).toInt(),
                'state': 'PENDING',
                'created_at': DateTime.now().toIso8601String(),
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
            syncExported++;
          }
        }
      });

      await coreDb.db.insert(
        'app_settings',
        {
          'key': 'legacy_migration_completed',
          'value': 'rolled_back',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      stopwatch.stop();
      return ReverseMigrationReport(
        salesExported: sExported,
        saleItemsExported: itemsExported,
        customersUpdated: cUpdated,
        productsUpdated: pUpdated,
        ledgerEntriesExported: lExported,
        syncEventsExported: syncExported,
        durationMs: stopwatch.elapsedMilliseconds,
        isSuccess: true,
      );
    } catch (e) {
      stopwatch.stop();
      return ReverseMigrationReport(
        salesExported: sExported,
        saleItemsExported: itemsExported,
        customersUpdated: cUpdated,
        productsUpdated: pUpdated,
        ledgerEntriesExported: lExported,
        syncEventsExported: syncExported,
        durationMs: stopwatch.elapsedMilliseconds,
        isSuccess: false,
        errorMessage: e.toString(),
      );
    }
  }
}
