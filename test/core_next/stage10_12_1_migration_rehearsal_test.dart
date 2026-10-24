import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart';
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('STAGE 10.12.1 — GÜVENLİ VERİTABANI AKTARIM PROVASI', () {
    late Directory tempDir;
    final rawNutopiaBackup = File(r'C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_nutopia_v60.db');

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('stage10_12_1_rehearsal_');
    });

    tearDownAll(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('1. Nutopia İzole Aktarım Provası ve Derin Mutabakat (Kayıt, Kimlik, Stok ve Kuruş)', () async {
      expect(rawNutopiaBackup.existsSync(), isTrue, reason: 'Nutopia ham yedeği mevcut olmalıdır');

      final isolatedSourcePath = p.join(tempDir.path, 'nutopia_isolated_src.db');
      final isolatedTargetPath = p.join(tempDir.path, 'nutopia_isolated_tgt.db');

      // 1. Ham yedekten izole kaynak oluştur (orijinal yedeğe asla dokunulmaz)
      await rawNutopiaBackup.copy(isolatedSourcePath);

      final legacyDb = await openDatabase(isolatedSourcePath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // 2. MigrationBridgeEngine ile tam kapsamlı aktarım
      final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, isTrue, reason: report.errorMessage);

      final target = coreDb.db;

      // 3. Ürün ve Stok Kontrolü
      final srcProdCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;
      final tgtProdCount = (await target.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;
      expect(tgtProdCount, equals(srcProdCount));
      expect(tgtProdCount, equals(37682));

      final srcStockSum = ((await legacyDb.rawQuery('SELECT ROUND(SUM(CAST(quantity AS REAL)), 2) as s FROM products')).first['s'] as num).toDouble();
      final tgtStockSum = ((await target.rawQuery('SELECT ROUND(SUM(stock_quantity), 2) as s FROM products')).first['s'] as num).toDouble();
      expect(tgtStockSum, equals(srcStockSum));
      expect((tgtStockSum - 5179525.85).abs() < 0.01, isTrue);

      // 4. Müşteri ve Bakiye Kontrolü
      final srcCustCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM customers')).first['c'] as int;
      final tgtCustCount = (await target.rawQuery('SELECT COUNT(*) as c FROM customers')).first['c'] as int;
      expect(tgtCustCount, equals(srcCustCount));
      expect(tgtCustCount, equals(584));

      final srcCustBal = (await legacyDb.rawQuery('SELECT SUM(balance) as s FROM customers')).first['s'] as double;
      final tgtCustBalCents = (await target.rawQuery('SELECT SUM(balance_cents) as s FROM customers')).first['s'] as int;
      expect(tgtCustBalCents, equals((srcCustBal * 100).round()));
      expect(tgtCustBalCents, equals(-13450068)); // -134.500,68 TL

      // 5. 1.403 Finansal Hareketin 1:1 Kuruşu Kuruşuna Doğrulanması
      final allSrcFt = await legacyDb.rawQuery(
        'SELECT id, customer_id, type, amount, amount_minor FROM financial_transactions WHERE customer_id IS NOT NULL AND customer_id != ""',
      );
      expect(allSrcFt.length, equals(1403));

      final targetLedgerRows = await target.query('ledger_entries');
      expect(targetLedgerRows.length, equals(1403));

      final targetLedgerMap = {for (final r in targetLedgerRows) r['id'].toString(): r};

      int matchedEntries = 0;
      for (final ft in allSrcFt) {
        final id = ft['id'] as String;
        final le = targetLedgerMap[id];
        expect(le, isNotNull, reason: 'Kayıt hedefte eksik: $id');

        final tgtCents = le!['amount_cents'] as int;
        final rawAmount = (ft['amount'] as num?)?.toDouble() ?? 0.0;
        final minor = (ft['amount_minor'] as num?)?.toInt();
        final expectedCents = (minor != null && minor > 0) ? minor : (rawAmount * 100).round();

        expect(tgtCents, equals(expectedCents), reason: 'Kuruş uyuşmazlığı kaydı: $id');
        matchedEntries++;
      }
      expect(matchedEntries, equals(1403));

      // 6. Sipariş ve Satış Kontrolleri
      final srcSaleCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      final tgtSaleCount = (await target.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      expect(tgtSaleCount, equals(srcSaleCount));
      expect(tgtSaleCount, equals(52));

      final srcOrderCount = (await legacyDb.rawQuery('SELECT COUNT(*) as c FROM orders')).first['c'] as int;
      final tgtOrderCount = (await target.rawQuery('SELECT COUNT(*) as c FROM orders')).first['c'] as int;
      expect(tgtOrderCount, equals(srcOrderCount));
      expect(tgtOrderCount, equals(792));

      // 7. Bütünlük ve PRAGMA Kontrolleri
      final integrityCheck = await target.rawQuery('PRAGMA integrity_check');
      expect(integrityCheck.first.values.first, equals('ok'));

      final fkCheck = await target.rawQuery('PRAGMA foreign_key_check');
      expect(fkCheck.isEmpty, isTrue);

      await legacyDb.close();
      await coreDb.close();

      // Yeniden açma testi
      final reopenedDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final reopenedProds = (await reopenedDb.db.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;
      expect(reopenedProds, equals(37682));
      await reopenedDb.close();
    });

    test('2. Erkul Sentetik Vadeli Satış, Kısmi Tahsilat, İkinci Satış, İade ve Kapanış Senaryoları', () async {
      final erkulDbPath = p.join(tempDir.path, 'erkul_isolated_scenario.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: erkulDbPath);
      final ledgerRepo = SqliteLedgerRepository(coreDb.db);
      final ledgerService = LedgerService(ledgerRepo);

      // Sentetik Erkul Cari Müşterisi
      const customerId = 'cust-erkul-ceyiz-101';

      await coreDb.db.insert('customers', {
        'id': customerId,
        'name': 'AYŞE YILMAZ (ERKUL CARİ TEST)',
        'phone': '05329998877',
        'balance_cents': 0,
        'credit_limit_cents': 10000000, // 100.000 TL limit
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Satış 1 ve 2 kayıtlarını ekle (FK bütünlüğü için)
      await coreDb.db.insert('sales', {
        'id': 'sale-erk-01',
        'receipt_no': 'ERK-2026-0001',
        'customer_id': customerId,
        'subtotal_cents': 1850000,
        'total_cents': 1850000,
        'paid_cents': 0,
        'debt_cents': 1850000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      await coreDb.db.insert('sales', {
        'id': 'sale-erk-02',
        'receipt_no': 'ERK-2026-0002',
        'customer_id': customerId,
        'subtotal_cents': 1850000,
        'total_cents': 1850000,
        'paid_cents': 0,
        'debt_cents': 1850000,
        'status': 'COMPLETED',
        'created_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Senaryo 2.1: 18.500,00 TL Vadeli Satış Borç Kaydı
      final debit1 = await ledgerService.postDebitSale(
        entryId: 'led-erk-01',
        customerId: customerId,
        saleId: 'sale-erk-01',
        debtAmount: const MoneyCents(1850000), // 18.500,00 TL
        receiptNo: 'ERK-2026-0001',
        timestamp: DateTime.now(),
      );
      expect(debit1.balanceAfter.value, -1850000);

      var cust = await ledgerRepo.getCustomer(customerId);
      expect(cust!.balance.value, -1850000); // 18.500 TL Borç

      // Senaryo 2.2: 8.500,00 TL Kısmi Nakit Tahsilat
      final col = await ledgerService.postCollection(
        entryId: 'led-erk-02',
        customerId: customerId,
        collectionAmount: const MoneyCents(850000), // 8.500,00 TL
        description: 'Elden Kısmi Nakit Tahsilat',
        timestamp: DateTime.now(),
      );
      expect(col.balanceAfter.value, -1000000);

      cust = await ledgerRepo.getCustomer(customerId);
      expect(cust!.balance.value, -1000000); // Kalan Borç: 10.000,00 TL

      // Senaryo 2.3: İkinci Vadeli Satış (18.500,00 TL)
      final debit2 = await ledgerService.postDebitSale(
        entryId: 'led-erk-03',
        customerId: customerId,
        saleId: 'sale-erk-02',
        debtAmount: const MoneyCents(1850000), // 18.500,00 TL
        receiptNo: 'ERK-2026-0002',
        timestamp: DateTime.now(),
      );
      expect(debit2.balanceAfter.value, -2850000);

      cust = await ledgerRepo.getCustomer(customerId);
      expect(cust!.balance.value, -2850000); // Toplam Borç: 28.500,00 TL

      // Senaryo 2.4: İkinci Satışın İptali / Ürün İadesi (18.500,00 TL Alacak)
      final ref = await ledgerService.postRefund(
        entryId: 'led-erk-04',
        customerId: customerId,
        saleId: 'sale-erk-02',
        refundAmount: const MoneyCents(1850000),
        description: 'Çeyiz Seti İadesi / Satış İptali',
        timestamp: DateTime.now(),
      );
      expect(ref.balanceAfter.value, -1000000);

      cust = await ledgerRepo.getCustomer(customerId);
      expect(cust!.balance.value, -1000000); // Bakiye tam 10.000,00 TL'ye döndü

      // Senaryo 2.5: Veritabanının Kapanması ve Yeniden Açılması
      await coreDb.close();

      final reopenedDb = await CoreAppDatabase.open(inMemoryOrCustomPath: erkulDbPath);
      final reopenedLedgerRepo = SqliteLedgerRepository(reopenedDb.db);
      final reopenedCust = await reopenedLedgerRepo.getCustomer(customerId);
      expect(reopenedCust!.balance.value, -1000000); // Kapanıp açılsa bile bakiye kuruşu kuruşuna korunur

      // Defter geçmişinin tamlığı
      final history = await reopenedLedgerRepo.getCustomerLedgerHistory(customerId);
      expect(history.length, equals(4)); // 2 borç, 1 tahsilat, 1 iade

      await reopenedDb.close();
    });

    test('3. Hata Senaryoları, Rollback ve Bütünlük İhlali Koruması', () async {
      final rollbackDbPath = p.join(tempDir.path, 'rollback_test.db');
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: rollbackDbPath);

      // Fault injection: Transaction içi yapay kesinti
      bool errorCaught = false;
      try {
        await coreDb.db.transaction((txn) async {
          await txn.insert('products', {
            'id': 'temp-p1',
            'barcode': '999',
            'name': 'Test Ürün',
            'price_cents': 5000,
            'vat_rate': 20,
            'unit': 'piece',
            'stock_quantity': 10,
            'is_active': 1,
            'is_deleted': 0,
            'updated_at': DateTime.now().millisecondsSinceEpoch,
          });
          throw Exception('Yapay Kesinti / Elektrik Kesintisi Simülasyonu');
        });
      } catch (_) {
        errorCaught = true;
      }
      expect(errorCaught, isTrue);

      // Transaction rollback sonrası tabloda hiçbir kısmi kayıt kalmadığının kanıtı
      final remainingCount = (await coreDb.db.rawQuery('SELECT COUNT(*) as c FROM products')).first['c'] as int;
      expect(remainingCount, equals(0));

      await coreDb.close();
    });
  });
}
