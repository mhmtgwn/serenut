// core_next/client_core/lib/infrastructure/migration/erkul_json_importer.dart
import 'dart:convert';
import 'dart:io';
import 'package:sqflite/sqflite.dart';
import '../database/app_database.dart';

/// Bilinmeyen veya desteklenmeyen finansal işlem türü istisnası (Fail-Closed).
class UnrecognizedFinancialTransactionTypeException implements Exception {
  final String transactionId;
  final String transactionType;

  const UnrecognizedFinancialTransactionTypeException({
    required this.transactionId,
    required this.transactionType,
  });

  @override
  String toString() =>
      'UnrecognizedFinancialTransactionTypeException: Bilinmeyen finansal işlem türü "$transactionType" (ID: $transactionId)! '
      'Finansal bütünlük gereği aktarım güvenli biçimde durduruldu.';
}

/// Müşteri bazında mutabakat sapma detayı.
class ErkulCustomerReconciliationRecord {
  final String customerId;
  final String customerName;
  final bool isDeleted;
  final int sourceBalanceCents;
  final int manualDebtCents;
  final int saleDebtCents;
  final int cashSalesCents;
  final int collectionCents;
  final int paymentCents;
  final int reconstructedBalanceCents;
  final int discrepancyCents;

  const ErkulCustomerReconciliationRecord({
    required this.customerId,
    required this.customerName,
    required this.isDeleted,
    required this.sourceBalanceCents,
    required this.manualDebtCents,
    required this.saleDebtCents,
    required this.cashSalesCents,
    required this.collectionCents,
    required this.paymentCents,
    required this.reconstructedBalanceCents,
    required this.discrepancyCents,
  });

  @override
  String toString() =>
      'ErkulCustomerReconciliation(ID: $customerId, $customerName, Silinmiş: $isDeleted, '
      'Kaynak: ${sourceBalanceCents / 100} TL, Rekonstrükte: ${reconstructedBalanceCents / 100} TL, '
      'Borç: ${(manualDebtCents + saleDebtCents) / 100} TL, Tahsilat: ${collectionCents / 100} TL)';
}

/// Erkul JSON İçe Aktarım Raporu
class ErkulImportReport {
  final int usersMigrated;
  final int categoriesMigrated;
  final int productsMigrated;
  final int customersMigrated;
  final int activeCustomersCount;
  final int deletedCustomersCount;
  final int salesMigrated;
  final int saleItemsMigrated;
  final int ledgerEntriesMigrated;
  final int ordersMigrated;
  final int orderItemsMigrated;
  final int manualDebtCount;
  final int manualDebtTotalCents;
  final int collectionCount;
  final int collectionTotalCents;
  final int saleTxCount;
  final int saleTxTotalCents;
  final int paymentCount;
  final int paymentTotalCents;
  final int activeCustomerReceivableCents;
  final int deletedCustomerBalanceCents;
  final int durationMs;
  final bool isSuccess;
  final String? errorMessage;
  final List<ErkulCustomerReconciliationRecord> customerRecords;

  const ErkulImportReport({
    required this.usersMigrated,
    required this.categoriesMigrated,
    required this.productsMigrated,
    required this.customersMigrated,
    required this.activeCustomersCount,
    required this.deletedCustomersCount,
    required this.salesMigrated,
    required this.saleItemsMigrated,
    required this.ledgerEntriesMigrated,
    required this.ordersMigrated,
    required this.orderItemsMigrated,
    required this.manualDebtCount,
    required this.manualDebtTotalCents,
    required this.collectionCount,
    required this.collectionTotalCents,
    required this.saleTxCount,
    required this.saleTxTotalCents,
    required this.paymentCount,
    required this.paymentTotalCents,
    required this.activeCustomerReceivableCents,
    required this.deletedCustomerBalanceCents,
    required this.durationMs,
    required this.isSuccess,
    this.errorMessage,
    this.customerRecords = const [],
  });

  @override
  String toString() =>
      'ErkulImportReport(Kullanıcı: $usersMigrated, Kategori: $categoriesMigrated, Ürün: $productsMigrated, '
      'Müşteri: $customersMigrated (Aktif: $activeCustomersCount, Silinmiş: $deletedCustomersCount), '
      'Satış: $salesMigrated, Kalem: $saleItemsMigrated, Defter: $ledgerEntriesMigrated, '
      'Sipariş: $ordersMigrated, Kalem: $orderItemsMigrated, '
      'SözleşmeBorç: $manualDebtCount (${manualDebtTotalCents / 100} TL), '
      'Tahsilat: $collectionCount (${collectionTotalCents / 100} TL), '
      'AktifAlacak: ${activeCustomerReceivableCents / 100} TL, '
      'SilinmişBakiye: ${deletedCustomerBalanceCents / 100} TL, '
      'Süre: ${durationMs}ms, Başarılı: $isSuccess)';
}

/// Erkul Çeyiz JSON Kaynağını Kuruş Hassasiyetinde Core Next SQLite Şemasına
/// Deterministik ve Tekrar Çalıştırılabilir (Idempotent) Olarak Aktaran Resmi Dart Adaptörü.
class ErkulJsonImporter {
  final CoreAppDatabase targetDb;

  const ErkulJsonImporter(this.targetDb);

  /// Dosya yolundan JSON okuyup içeri aktarır
  Future<ErkulImportReport> importFromFile(String jsonFilePath) async {
    final file = File(jsonFilePath);
    if (!await file.exists()) {
      throw ArgumentError('Erkul kaynak JSON dosyası bulunamadı: $jsonFilePath');
    }
    final content = await file.readAsString(encoding: utf8);
    final jsonMap = jsonDecode(content) as Map<String, dynamic>;
    return importFromJson(jsonMap);
  }

  /// JSON haritasını doğrudan hedef veritabanına aktarır
  Future<ErkulImportReport> importFromJson(Map<String, dynamic> jsonMap) async {
    final stopwatch = Stopwatch()..start();

    int uCount = 0;
    int catCount = 0;
    int pCount = 0;
    int cCount = 0;
    int activeCustCount = 0;
    int deletedCustCount = 0;
    int sCount = 0;
    int siCount = 0;
    int lCount = 0;
    int oCount = 0;
    int oiCount = 0;

    int mDebtCount = 0;
    int mDebtTotalCents = 0;
    int collCount = 0;
    int collTotalCents = 0;
    int saleTxCount = 0;
    int saleTxTotalCents = 0;
    int payCount = 0;
    int payTotalCents = 0;

    int activeReceivableCents = 0;
    int deletedBalanceCents = 0;

    final customerReconciliationList = <ErkulCustomerReconciliationRecord>[];

    try {
      await targetDb.transaction((txn) async {
        // ── 0. GÜVENLİK VE BİLİNMEYEN İŞLEM TÜRLERİ DENETİMİ (FAIL-CLOSED) ──
        final fts = (jsonMap['financial_transactions'] as List?) ?? [];
        for (final ft in fts) {
          final t = ft['type']?.toString().toLowerCase().trim();
          if (t != 'manual_debt' && t != 'collection' && t != 'sale' && t != 'payment') {
            throw UnrecognizedFinancialTransactionTypeException(
              transactionId: ft['id']?.toString() ?? 'unknown',
              transactionType: t ?? 'null',
            );
          }
        }

        // ── 1. ŞİRKET BİLGİSİ VE AYARLAR ────────────────────────────────────
        final companies = (jsonMap['companies'] as List?) ?? [];
        final compName = companies.isNotEmpty ? companies.first['name']?.toString() : 'ERKUL ÇEYİZ';
        final taxNo = companies.isNotEmpty ? companies.first['tax_number']?.toString() : '3630473210';
        final nowMs = DateTime.now().millisecondsSinceEpoch;

        await txn.insert(
          'app_settings',
          {'key': 'business_name', 'value': compName ?? 'ERKUL ÇEYİZ', 'updated_at': nowMs},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.insert(
          'app_settings',
          {'key': 'business_tax_id', 'value': taxNo ?? '3630473210', 'updated_at': nowMs},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.insert(
          'app_settings',
          {'key': 'tenant_id', 'value': 'erkul', 'updated_at': nowMs},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        await txn.insert(
          'app_settings',
          {'key': 'legacy_migration_completed', 'value': 'true', 'updated_at': nowMs},
          conflictAlgorithm: ConflictAlgorithm.replace,
        );

        // ── 2. KULLANICILAR ─────────────────────────────────────────────────
        final users = (jsonMap['users'] as List?) ?? [];
        for (final u in users) {
          final id = u['id']?.toString() ?? 'usr-erkul-1';
          final username = (u['email'] ?? u['name'] ?? id).toString();
          final displayName = (u['name'] ?? 'Erkul Kullanıcı').toString();
          final createdAt = DateTime.tryParse(u['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? nowMs;

          await txn.insert(
            'users',
            {
              'id': id,
              'username': username,
              'display_name': displayName,
              'role': 'owner',
              'pin_hash': u['pin_hash']?.toString(),
              'is_active': (u['is_active'] == true || u['is_active'] == 1) ? 1 : 0,
              'created_at': createdAt,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          uCount++;
        }

        // ── 3. KATEGORİLER (ÜRÜN KATEGORİLERİNDEN TÜRETİLİR) ───────────────
        final rawProducts = (jsonMap['products'] as List?) ?? [];
        final categoryMap = <String, String>{}; // categoryName -> categoryId

        // Varsayılan genel kategori
        const defaultCatId = 'cat-erkul-genel';
        await txn.insert(
          'categories',
          {
            'id': defaultCatId,
            'name': 'Genel',
            'color_hex': '#7C3AED',
            'sort_order': 0,
            'is_active': 1,
            'updated_at': nowMs,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        catCount++;

        int catSort = 1;
        for (final p in rawProducts) {
          final catName = p['category']?.toString().trim();
          if (catName != null && catName.isNotEmpty && !categoryMap.containsKey(catName)) {
            final catId = 'cat-erkul-${catName.toLowerCase().replaceAll(RegExp(r'\s+'), '_')}';
            categoryMap[catName] = catId;
            await txn.insert(
              'categories',
              {
                'id': catId,
                'name': catName,
                'color_hex': null,
                'sort_order': catSort++,
                'is_active': 1,
                'updated_at': nowMs,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            catCount++;
          }
        }

        // ── 4. ÜRÜN KATALOĞU ────────────────────────────────────────────────
        final validProductIds = <String>{};
        final productBarcodeMap = <String, String>{};
        var batch = txn.batch();

        for (final p in rawProducts) {
          final id = p['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          validProductIds.add(id);

          final rawBarcode = (p['sku'] ?? p['barcode'] ?? id).toString().trim();
          final barcode = rawBarcode.isNotEmpty ? rawBarcode : id;
          productBarcodeMap[id] = barcode;

          final rawPrice = double.tryParse(p['price']?.toString() ?? '0') ?? 0.0;
          final priceCents = (rawPrice * 100).round();
          final rawCost = p['purchase_price'] != null ? (double.tryParse(p['purchase_price'].toString()) ?? 0.0) : 0.0;
          final costPriceCents = (rawCost * 100).round();
          final stockQty = (p['quantity'] as num?)?.toDouble() ?? (p['stock_quantity'] as num?)?.toDouble() ?? 0.0;
          final unit = (p['unit']?.toString() == 'kg') ? 'kg' : 'piece';
          final vat = (p['vat'] as num?)?.toInt() ?? 20;

          final catName = p['category']?.toString().trim();
          final categoryId = (catName != null && categoryMap.containsKey(catName)) ? categoryMap[catName] : defaultCatId;

          final updatedAt = DateTime.tryParse(p['updated_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? nowMs;

          batch.insert(
            'products',
            {
              'id': id,
              'barcode': barcode,
              'name': p['name']?.toString() ?? 'Ürün',
              'category_id': categoryId,
              'price_cents': priceCents,
              'cost_price_cents': costPriceCents > 0 ? costPriceCents : null,
              'vat_rate': vat,
              'unit': unit,
              'stock_quantity': stockQty,
              'critical_threshold': (p['min_stock'] as num?)?.toDouble() ?? 5.0,
              'image_url': p['image_path']?.toString() ?? p['image_url']?.toString(),
              'is_active': (p['status'] == 'active' && p['is_deleted'] != true) ? 1 : 0,
              'is_deleted': (p['is_deleted'] == true || p['is_deleted'] == 1) ? 1 : 0,
              'updated_at': updatedAt,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          pCount++;
        }
        await batch.commit(noResult: true);

        // ── 5. MÜŞTERİ BAZINDA FİNANSAL HAREKETLER VE BAKİYE REKONSTRÜKSİYONU ─
        final rawCustomers = (jsonMap['customers'] as List?) ?? [];
        final custTxMap = <String, List<Map<String, dynamic>>>{};
        for (final ft in fts) {
          final cid = ft['customer_id']?.toString() ?? '';
          if (cid.isNotEmpty) {
            custTxMap.putIfAbsent(cid, () => []).add(ft as Map<String, dynamic>);
          }
        }

        final validCustomerIds = <String>{};
        final customerReconstructedBalances = <String, int>{};
        batch = txn.batch();

        for (final c in rawCustomers) {
          final id = c['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          validCustomerIds.add(id);

          final isDeleted = (c['is_deleted'] == true || c['status'] == 'inactive');
          if (isDeleted) {
            deletedCustCount++;
          } else {
            activeCustCount++;
          }

          final rawSourceBal = double.tryParse(c['balance']?.toString() ?? '0') ?? 0.0;
          final sourceBalCents = (rawSourceBal * 100).round();

          final txs = custTxMap[id] ?? [];
          // Kronolojik sıralama
          txs.sort((a, b) {
            final tA = a['created_at']?.toString() ?? '';
            final tB = b['created_at']?.toString() ?? '';
            return tA.compareTo(tB);
          });

          int mDebt = 0;
          int sDebt = 0;
          int cashSale = 0;
          int coll = 0;
          int pay = 0;

          for (final ft in txs) {
            final t = ft['type']?.toString().toLowerCase().trim();
            final amt = ((double.tryParse(ft['amount']?.toString() ?? '0') ?? 0.0) * 100).round();
            final debtAmt = ((double.tryParse(ft['debt_amount']?.toString() ?? '0') ?? 0.0) * 100).round();
            final paidAmt = ((double.tryParse(ft['paid_amount']?.toString() ?? '0') ?? 0.0) * 100).round();

            if (t == 'manual_debt') {
              mDebt += amt;
            } else if (t == 'sale') {
              if (debtAmt > 0) {
                sDebt += debtAmt;
              } else if (amt > paidAmt) {
                sDebt += (amt - paidAmt);
              }
              if (paidAmt > 0) {
                cashSale += paidAmt;
              }
            } else if (t == 'collection') {
              coll += amt;
            } else if (t == 'payment') {
              pay += amt;
            }
          }

          // Serenut OS Çift Taraflı Formülü:
          // Reconstructed Balance = - (manual_debt + sale_debt) + collection + payment
          final reconstructedCents = -(mDebt + sDebt) + coll + pay;
          customerReconstructedBalances[id] = reconstructedCents;

          if (isDeleted) {
            deletedBalanceCents += reconstructedCents;
          } else {
            activeReceivableCents += (-reconstructedCents);
          }

          customerReconciliationList.add(ErkulCustomerReconciliationRecord(
            customerId: id,
            customerName: c['name']?.toString() ?? 'İsimsiz Müşteri',
            isDeleted: isDeleted,
            sourceBalanceCents: sourceBalCents,
            manualDebtCents: mDebt,
            saleDebtCents: sDebt,
            cashSalesCents: cashSale,
            collectionCents: coll,
            paymentCents: pay,
            reconstructedBalanceCents: reconstructedCents,
            discrepancyCents: reconstructedCents - sourceBalCents,
          ));

          final rawCredit = double.tryParse(c['credit_limit']?.toString() ?? '0') ?? 0.0;
          final creditLimitCents = (rawCredit * 100).round();
          final updatedAt = DateTime.tryParse(c['updated_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? nowMs;

          batch.insert(
            'customers',
            {
              'id': id,
              'name': c['name']?.toString() ?? 'İsimsiz Müşteri',
              'phone': c['phone']?.toString(),
              'email': c['email']?.toString(),
              'tax_number': c['tax_number']?.toString(),
              'tax_office': c['tax_office']?.toString(),
              'balance_cents': reconstructedCents,
              'credit_limit_cents': creditLimitCents,
              'notes': c['address']?.toString(),
              'is_active': isDeleted ? 0 : 1,
              'is_deleted': isDeleted ? 1 : 0,
              'updated_at': updatedAt,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          cCount++;
        }
        await batch.commit(noResult: true);

        // ── 6. SATIŞLAR VE SATIŞ KALEMLERİ ──────────────────────────────────
        final rawSales = (jsonMap['sales'] as List?) ?? [];
        final validSalesIds = <String>{};

        for (final s in rawSales) {
          final id = s['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          validSalesIds.add(id);

          final rawTotal = double.tryParse(s['total_amount']?.toString() ?? '0') ?? 0.0;
          final totalCents = (rawTotal * 100).round();
          final rawPaid = double.tryParse(s['paid_amount']?.toString() ?? '0') ?? 0.0;
          final paidCents = (rawPaid * 100).round();
          final rawSub = double.tryParse(s['subtotal_amount']?.toString() ?? '0') ?? rawTotal;
          final subtotalCents = (rawSub * 100).round();
          final rawDisc = double.tryParse(s['discount_amount']?.toString() ?? '0') ?? 0.0;
          final discountCents = (rawDisc * 100).round();
          final createdAt = DateTime.tryParse(s['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? nowMs;

          final custId = s['customer_id']?.toString();
          final validCid = (custId != null && validCustomerIds.contains(custId)) ? custId : null;

          await txn.insert(
            'sales',
            {
              'id': id,
              'receipt_no': s['receipt_number']?.toString() ?? s['sale_number']?.toString() ?? 'REC-$id',
              'customer_id': validCid,
              'subtotal_cents': subtotalCents,
              'discount_cents': discountCents,
              'vat_total_cents': 0,
              'total_cents': totalCents,
              'paid_cents': paidCents,
              'debt_cents': totalCents > paidCents ? totalCents - paidCents : 0,
              'status': 'COMPLETED',
              'idempotency_key': 'legacy-erkul-sale-$id',
              'created_at': createdAt,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          sCount++;
        }

        final rawSaleItems = (jsonMap['sale_items'] as List?) ?? [];
        for (final si in rawSaleItems) {
          final id = si['id']?.toString() ?? '';
          final saleId = si['sale_id']?.toString() ?? '';
          var prodId = si['product_id']?.toString() ?? '';
          if (id.isEmpty || saleId.isEmpty) continue;

          final qty = (si['quantity'] as num?)?.toDouble() ?? 1.0;
          final rawPrice = double.tryParse(si['unit_price']?.toString() ?? '0') ?? 0.0;
          final unitPriceCents = (rawPrice * 100).round();
          final rawTot = double.tryParse(si['total_price']?.toString() ?? '0') ?? (qty * rawPrice);
          final totCents = (rawTot * 100).round();

          if (!validProductIds.contains(prodId)) {
            final placeholderId = prodId.isNotEmpty ? prodId : 'p-erkul-orphaned';
            await txn.insert(
              'products',
              {
                'id': placeholderId,
                'barcode': si['barcode']?.toString() ?? 'ORPHAN-$placeholderId',
                'name': si['product_name']?.toString() ?? 'Eski Bilinmeyen Ürün',
                'category_id': defaultCatId,
                'price_cents': unitPriceCents,
                'vat_rate': 20,
                'unit': 'piece',
                'stock_quantity': 0,
                'critical_threshold': 0,
                'is_active': 0,
                'is_deleted': 1,
                'updated_at': nowMs,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            validProductIds.add(placeholderId);
            prodId = placeholderId;
          }

          final barcode = si['barcode']?.toString() ?? productBarcodeMap[prodId] ?? prodId;

          await txn.insert(
            'sale_items',
            {
              'id': id,
              'sale_id': saleId,
              'product_id': prodId,
              'barcode': barcode,
              'product_name': si['product_name']?.toString() ?? 'Ürün',
              'unit_price_cents': unitPriceCents,
              'quantity': qty,
              'discount_cents': 0,
              'vat_rate': 20,
              'total_cents': totCents,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          siCount++;
        }

        // ── 7. DEFTER-İ KEBİR (LEDGER ENTRIES) VE BAKİYE TAKİBİ ─────────────
        batch = txn.batch();
        for (final cid in validCustomerIds) {
          final txs = custTxMap[cid] ?? [];
          txs.sort((a, b) {
            final tA = a['created_at']?.toString() ?? '';
            final tB = b['created_at']?.toString() ?? '';
            return tA.compareTo(tB);
          });

          int runningBal = 0;
          for (final ft in txs) {
            final id = ft['id']?.toString() ?? '';
            if (id.isEmpty) continue;

            final t = ft['type']?.toString().toLowerCase().trim();
            final amt = ((double.tryParse(ft['amount']?.toString() ?? '0') ?? 0.0) * 100).round();
            final debtAmt = ((double.tryParse(ft['debt_amount']?.toString() ?? '0') ?? 0.0) * 100).round();
            final paidAmt = ((double.tryParse(ft['paid_amount']?.toString() ?? '0') ?? 0.0) * 100).round();

            final String entryType;
            final int effectAmount;

            if (t == 'manual_debt') {
              entryType = 'MANUAL_DEBT';
              effectAmount = amt;
              runningBal -= amt;
              mDebtCount++;
              mDebtTotalCents += amt;
            } else if (t == 'collection') {
              entryType = 'COLLECTION';
              effectAmount = amt;
              runningBal += amt;
              collCount++;
              collTotalCents += amt;
            } else if (t == 'sale') {
              entryType = 'SALE';
              saleTxCount++;
              saleTxTotalCents += amt;
              if (debtAmt > 0) {
                effectAmount = debtAmt;
                runningBal -= debtAmt;
              } else if (amt > paidAmt) {
                effectAmount = amt - paidAmt;
                runningBal -= (amt - paidAmt);
              } else {
                effectAmount = amt;
                // Peşin satış cari bakiyeyi değiştirmez
              }
            } else if (t == 'payment') {
              entryType = 'PAYMENT';
              effectAmount = amt;
              runningBal += amt;
              payCount++;
              payTotalCents += amt;
            } else {
              throw UnrecognizedFinancialTransactionTypeException(
                transactionId: id,
                transactionType: t ?? 'null',
              );
            }

            final createdAt = DateTime.tryParse(ft['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? nowMs;
            final rawRef = ft['reference_id']?.toString() ?? ft['sale_id']?.toString();
            final String? refSaleId = (rawRef != null && validSalesIds.contains(rawRef)) ? rawRef : null;

            batch.insert(
              'ledger_entries',
              {
                'id': id,
                'customer_id': cid,
                'reference_sale_id': refSaleId,
                'entry_type': entryType,
                'amount_cents': effectAmount,
                'balance_after_cents': runningBal,
                'description': ft['description']?.toString() ?? 'Erkul Çeyiz Cari Hareket',
                'created_at': createdAt,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            lCount++;
          }
        }
        await batch.commit(noResult: true);

        // ── 8. MÜŞTERİ SİPARİŞLERİ VE SİPARİŞ KALEMLERİ ─────────────────────
        final rawOrders = (jsonMap['customer_orders'] as List?) ?? [];
        final validOrderIds = <String>{};

        for (final o in rawOrders) {
          final id = o['id']?.toString() ?? '';
          if (id.isEmpty) continue;
          validOrderIds.add(id);

          final rawTot = double.tryParse(o['total_amount']?.toString() ?? '0') ?? 0.0;
          final orderDate = DateTime.tryParse(o['order_date']?.toString() ?? '')?.millisecondsSinceEpoch ?? nowMs;
          final custId = o['customer_id']?.toString();
          final validCid = (custId != null && validCustomerIds.contains(custId)) ? custId : null;

          await txn.insert(
            'orders',
            {
              'id': id,
              'order_number': o['order_number']?.toString() ?? 'SP-$id',
              'customer_id': validCid,
              'status': o['status']?.toString() ?? 'pending',
              'total_amount_cents': (rawTot * 100).round(),
              'discount_amount_cents': 0,
              'order_date': orderDate,
              'notes': o['notes']?.toString(),
              'created_by': o['created_by']?.toString(),
              'is_deleted': (o['is_deleted'] == true || o['is_deleted'] == 1) ? 1 : 0,
              'created_at': orderDate,
              'updated_at': orderDate,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          oCount++;
        }

        final rawOrderItems = (jsonMap['customer_order_items'] as List?) ?? [];
        for (final oi in rawOrderItems) {
          final id = oi['id']?.toString() ?? '';
          final orderId = oi['order_id']?.toString() ?? '';
          var prodId = oi['product_id']?.toString() ?? '';
          if (id.isEmpty || orderId.isEmpty) continue;

          final qty = (oi['quantity'] as num?)?.toDouble() ?? 1.0;
          final rawPrice = double.tryParse(oi['unit_price']?.toString() ?? '0') ?? 0.0;
          final unitPriceCents = (rawPrice * 100).round();
          final rawTot = double.tryParse(oi['total_price']?.toString() ?? '0') ?? (qty * rawPrice);
          final totCents = (rawTot * 100).round();

          if (!validProductIds.contains(prodId)) {
            final placeholderId = prodId.isNotEmpty ? prodId : 'p-erkul-order-orphaned';
            await txn.insert(
              'products',
              {
                'id': placeholderId,
                'barcode': oi['barcode']?.toString() ?? 'ORPHAN-$placeholderId',
                'name': oi['product_name']?.toString() ?? 'Sipariş Kalemi',
                'category_id': defaultCatId,
                'price_cents': unitPriceCents,
                'vat_rate': 20,
                'unit': 'piece',
                'stock_quantity': 0,
                'critical_threshold': 0,
                'is_active': 0,
                'is_deleted': 1,
                'updated_at': nowMs,
              },
              conflictAlgorithm: ConflictAlgorithm.ignore,
            );
            validProductIds.add(placeholderId);
            prodId = placeholderId;
          }

          final barcode = oi['barcode']?.toString() ?? productBarcodeMap[prodId] ?? prodId;

          await txn.insert(
            'order_items',
            {
              'id': id,
              'order_id': orderId,
              'product_id': prodId,
              'barcode': barcode,
              'product_name': oi['product_name']?.toString() ?? 'Sipariş Ürünü',
              'quantity': qty,
              'unit_price_cents': unitPriceCents,
              'total_cents': totCents,
              'created_at': DateTime.tryParse(oi['created_at']?.toString() ?? '')?.millisecondsSinceEpoch ?? nowMs,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          oiCount++;
        }
      });

      // ── 9. HEDEF VERİTABANI BÜTÜNLÜK DOĞRULAMASI (INTEGRITY & FK CHECKS) ─
      final integrityResult = await targetDb.db.rawQuery('PRAGMA integrity_check;');
      final integrityStatus = integrityResult.isNotEmpty ? integrityResult.first.values.first.toString() : 'unknown';
      if (integrityStatus.toLowerCase() != 'ok') {
        throw StateError('Erkul hedef veritabanında PRAGMA integrity_check hatası: $integrityStatus');
      }

      final fkResult = await targetDb.db.rawQuery('PRAGMA foreign_key_check;');
      if (fkResult.isNotEmpty) {
        throw StateError('Erkul hedef veritabanında PRAGMA foreign_key_check ihlalleri tespit edildi: $fkResult');
      }

      stopwatch.stop();

      return ErkulImportReport(
        usersMigrated: uCount,
        categoriesMigrated: catCount,
        productsMigrated: pCount,
        customersMigrated: cCount,
        activeCustomersCount: activeCustCount,
        deletedCustomersCount: deletedCustCount,
        salesMigrated: sCount,
        saleItemsMigrated: siCount,
        ledgerEntriesMigrated: lCount,
        ordersMigrated: oCount,
        orderItemsMigrated: oiCount,
        manualDebtCount: mDebtCount,
        manualDebtTotalCents: mDebtTotalCents,
        collectionCount: collCount,
        collectionTotalCents: collTotalCents,
        saleTxCount: saleTxCount,
        saleTxTotalCents: saleTxTotalCents,
        paymentCount: payCount,
        paymentTotalCents: payTotalCents,
        activeCustomerReceivableCents: activeReceivableCents,
        deletedCustomerBalanceCents: deletedBalanceCents,
        durationMs: stopwatch.elapsedMilliseconds,
        isSuccess: true,
        customerRecords: customerReconciliationList,
      );
    } catch (e) {
      stopwatch.stop();
      return ErkulImportReport(
        usersMigrated: uCount,
        categoriesMigrated: catCount,
        productsMigrated: pCount,
        customersMigrated: cCount,
        activeCustomersCount: activeCustCount,
        deletedCustomersCount: deletedCustCount,
        salesMigrated: sCount,
        saleItemsMigrated: siCount,
        ledgerEntriesMigrated: lCount,
        ordersMigrated: oCount,
        orderItemsMigrated: oiCount,
        manualDebtCount: mDebtCount,
        manualDebtTotalCents: mDebtTotalCents,
        collectionCount: collCount,
        collectionTotalCents: collTotalCents,
        saleTxCount: saleTxCount,
        saleTxTotalCents: saleTxTotalCents,
        paymentCount: payCount,
        paymentTotalCents: payTotalCents,
        activeCustomerReceivableCents: activeReceivableCents,
        deletedCustomerBalanceCents: deletedBalanceCents,
        durationMs: stopwatch.elapsedMilliseconds,
        isSuccess: false,
        errorMessage: e.toString(),
        customerRecords: customerReconciliationList,
      );
    }
  }
}
