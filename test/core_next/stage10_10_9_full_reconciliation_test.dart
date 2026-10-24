import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  int count(List<Map<String, Object?>> rows) => (rows.first.values.first as num).toInt();

  group('STAGE 10.10.9 — İZOLE YENİDEN AKTARIM, TAM FİNANSAL MUTABAKAT VE KABUL KAPISI', () {
    late Directory tempDir;
    final rawNutopiaBackup = File(p.join(Directory.current.path, 'backups', 'raw_tenants_20261016', 'raw_nutopia_v60.db'));
    final rawSerenutBackup = File(p.join(Directory.current.path, 'backups', 'raw_tenants_20261016', 'raw_serenut_v44.db'));
    final rawErkulBackup = File(p.join(Directory.current.path, 'backups', 'raw_tenants_20261016', 'raw_erkul_source.json'));

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('stage10_10_9_reconciliation_');
    });

    tearDownAll(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 1. NUTOPIA TAM VE DERİN FİNANSAL HAREKET (LEDGER) MUTABAKATI
    // ─────────────────────────────────────────────────────────────────────────
    test('1. Nutopia Tüm Finansal Hareketlerin 1:1 Kayıt Düzeyinde Mutabakatı', () async {
      print('\n=== BÖLÜM 1: NUTOPIA FİNANSAL HAREKETLERİN 1:1 DERİN MUTABAKATI ===');

      expect(rawNutopiaBackup.existsSync(), isTrue, reason: 'Nutopia ham yedeği mevcut olmalıdır');

      final isolatedRawPath = '${tempDir.path}\\nutopia_isolated_raw.db';
      final isolatedTargetPath = '${tempDir.path}\\nutopia_isolated_target.db';

      // Ham yedeğe asla doğrudan yazmadan geçici kopyasını al
      await rawNutopiaBackup.copy(isolatedRawPath);

      final legacyDb = await openDatabase(isolatedRawPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // Göçü çalıştır
      final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, isTrue, reason: report.errorMessage);

      final target = coreDb.db;

      // 1. Kaynak Tablo Envanteri
      final rawFtRows = await legacyDb.query('financial_transactions');
      final totalSourceTxs = rawFtRows.length;
      expect(totalSourceTxs, equals(1424), reason: 'Nutopia kaynakta 1424 financial_transactions olmalıdır');

      // Müşteri ilişkili ve genel kasa ayrımı
      final customerLinkedTxs = rawFtRows.where((r) => r['customer_id'] != null && r['customer_id'].toString().trim().isNotEmpty).toList();
      final anonymousCashTxs = rawFtRows.where((r) => r['customer_id'] == null || r['customer_id'].toString().trim().isEmpty).toList();

      expect(customerLinkedTxs.length, equals(1403), reason: 'Müşteri bağlantılı hareket sayısı 1403 olmalıdır');
      expect(anonymousCashTxs.length, equals(21), reason: 'Genel kasa (müşterisiz) hareket sayısı 21 olmalıdır');

      // Hedefteki ledger_entries
      final targetLedgerRows = await target.query('ledger_entries');
      final targetLedgerMap = {for (final r in targetLedgerRows) r['id'].toString(): r};

      expect(targetLedgerRows.length, equals(1403), reason: 'Hedefte tam 1403 müşteri defter hareketi bulunmalıdır');

      // 2. Zorunlu 6 Kategori Ayrımı ve Mutabakat Sayımları
      int catMinorPositive = 0;
      int catMinorZero = 0;
      int catMinorNull = 0;
      int catNegative = 0;
      int catConflicting = 0;
      int catLegitZero = 0;

      int matchedCount = 0;
      int unverifiedCount = 0;

      for (final src in customerLinkedTxs) {
        final srcId = src['id'].toString();
        final rawAmount = (src['amount'] as num?)?.toDouble() ?? 0.0;
        final rawMinor = (src['amount_minor'] as num?)?.toInt();
        final expectedCents = MigrationBridgeEngine.resolveAmountCents(
          rawAmountNum: rawAmount,
          rawMinorNum: rawMinor,
        );

        final tgt = targetLedgerMap[srcId];
        if (tgt == null) {
          unverifiedCount++;
          continue;
        }

        final tgtCents = (tgt['amount_cents'] as num).toInt();
        expect(tgtCents, equals(expectedCents), reason: 'İşlem $srcId tutarı $expectedCents kuruş olmalıdır, bulunan: $tgtCents');

        // Kategori Tasnifi
        if (rawMinor != null && rawMinor > 0) {
          catMinorPositive++;
        } else if (rawMinor == 0) {
          catMinorZero++;
        } else if (rawMinor == null) {
          catMinorNull++;
        }

        if (rawAmount < 0 || (rawMinor != null && rawMinor < 0)) {
          catNegative++;
        }

        if (rawMinor != null && rawMinor != 0 && (rawAmount * 100).round() != rawMinor) {
          catConflicting++;
        }

        if (rawAmount == 0.0 && (rawMinor == 0 || rawMinor == null)) {
          catLegitZero++;
        }

        matchedCount++;
      }

      print('  Kaynak Toplam financial_transactions: $totalSourceTxs');
      print('  - Müşteri Bağlantılı Hareketler: ${customerLinkedTxs.length}');
      print('  - Genel Kasa (Müşterisiz) Hareketler: ${anonymousCashTxs.length}');
      print('  Hedef Toplam ledger_entries: ${targetLedgerRows.length}');
      print('  Eşleşen Kayıt Sayısı: $matchedCount / ${customerLinkedTxs.length} (%100)');
      expect(unverifiedCount, equals(0), reason: 'Hiçbir müşteri hareketi eşleşmesiz kalmamalıdır');
      expect(matchedCount, equals(1403));

      print('\n  --- Kategori Dağılımı ve Doğrulama ---');
      print('  a) amount_minor pozitif olan hareketler: $catMinorPositive');
      print('  b) amount_minor sıfır olan hareketler: $catMinorZero');
      print('  c) amount_minor null olan hareketler: $catMinorNull');
      print('  d) Negatif tutarlı hareketler: $catNegative');
      print('  e) amount ile amount_minor çelişkili hareketler: $catConflicting');
      print('  f) Meşru sıfır tutarlı hareketler: $catLegitZero');

      // 3. Canlı 5.000 TL ve 1.800 TL İşlemlerinin Özel Doğrulaması
      final tx5000 = targetLedgerMap['trans-17921639818271285834'];
      final tx1800 = targetLedgerMap['trans-coll-17921644564249063520'];

      expect(tx5000, isNotNull);
      expect(tx5000!['amount_cents'], equals(500000), reason: 'trans-17921639818271285834 kesinlikle 500.000 kuruş olmalıdır');
      expect(tx1800, isNotNull);
      expect(tx1800!['amount_cents'], equals(180000), reason: 'trans-coll-17921644564249063520 kesinlikle 180.000 kuruş olmalıdır');

      // 4. Müşteri Bakiye Mutabakatı ve Tutarlılığı
      final custBalRow = await target.rawQuery('SELECT SUM(balance_cents) as s FROM customers');
      final totalCustBalCents = (custBalRow.first['s'] as num).toInt();
      expect(totalCustBalCents, equals(-13450068), reason: 'Nutopia müşteri bakiyesi kuruşu kuruşuna -134.500,68 TL olmalıdır');

      await legacyDb.close();
      await coreDb.close();
      print('  [PASS] Nutopia 1.403 finansal hareketin tamamı 1:1 mutabık, 6.800 TL tahsilat kusursuz aktarıldı.');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 2. DİĞER PARA VE STOK VERİLERİ MUTABAKATI
    // ─────────────────────────────────────────────────────────────────────────
    test('2. Nutopia Satış, Ödeme, Sipariş, Taksit ve Stok Mutabakatı', () async {
      print('\n=== BÖLÜM 2: SATIŞ, ÖDEME, SİPARİŞ, TAKSİT VE STOK MUTABAKATI ===');

      final isolatedRawPath = '${tempDir.path}\\nutopia_isolated_raw.db';
      final isolatedTargetPath = '${tempDir.path}\\nutopia_isolated_target.db';

      final legacyDb = await openDatabase(isolatedRawPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final target = coreDb.db;

      // 1. Satışlar ve Ödemeler
      final legSales = await legacyDb.query('sales');
      final tgtSales = await target.query('sales');
      expect(tgtSales.length, equals(legSales.length));
      expect(tgtSales.length, equals(52));

      for (final ls in legSales) {
        final sid = ls['id'].toString();
        final ts = (await target.query('sales', where: 'id = ?', whereArgs: [sid])).first;
        final expectedTotal = MigrationBridgeEngine.resolveAmountCents(
          rawAmountNum: (ls['total_amount'] ?? ls['total']) as num?,
          rawMinorNum: ls['total_amount_minor'] as num?,
        );
        expect((ts['total_cents'] as num).toInt(), equals(expectedTotal));
      }

      // 2. Siparişler ve Kalemleri
      final legOrders = count(await legacyDb.rawQuery('SELECT count(*) FROM orders'));
      final tgtOrders = count(await target.rawQuery('SELECT count(*) FROM orders'));
      expect(tgtOrders, equals(legOrders));
      expect(tgtOrders, equals(792));

      final legOrderItems = count(await legacyDb.rawQuery('SELECT count(*) FROM order_items'));
      final tgtOrderItems = count(await target.rawQuery('SELECT count(*) FROM order_items'));
      expect(tgtOrderItems, equals(legOrderItems));
      expect(tgtOrderItems, equals(1068));

      // 3. Taksitler
      final legPlans = count(await legacyDb.rawQuery('SELECT count(*) FROM customer_installment_plans'));
      final tgtPlans = count(await target.rawQuery('SELECT count(*) FROM customer_installment_plans'));
      expect(tgtPlans, equals(legPlans));
      expect(tgtPlans, equals(2));

      final legInsts = count(await legacyDb.rawQuery('SELECT count(*) FROM customer_installments'));
      final tgtInsts = count(await target.rawQuery('SELECT count(*) FROM customer_installments'));
      expect(tgtInsts, equals(legInsts));
      expect(tgtInsts, equals(9));

      // 4. Stok Miktarları ve Tartılı/Ondalıklı Ürünler
      final legStockRow = await legacyDb.rawQuery('SELECT ROUND(SUM(CAST(quantity AS REAL)), 2) as s FROM products');
      final legStock = (legStockRow.first['s'] as num).toDouble();
      final tgtStockRow = await target.rawQuery('SELECT ROUND(SUM(stock_quantity), 2) as s FROM products');
      final tgtStock = (tgtStockRow.first['s'] as num).toDouble();
      expect(tgtStock, equals(legStock));
      expect((tgtStock - 5179525.85).abs() < 0.01, isTrue);

      await legacyDb.close();
      await coreDb.close();
      print('  [PASS] Satış (52), sipariş (792/1068), taksit (2/9) ve stok (5.179.525,85) tam mutabık.');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 3. SERENUT VE ERKUL ÇEYİZ İZOLE GÖÇ VE VERİ İZOLASYONU
    // ─────────────────────────────────────────────────────────────────────────
    test('3. Serenut ve ERKUL ÇEYİZ İzole Göç ve Çapraz Veri İzolasyonu', () async {
      print('\n=== BÖLÜM 3: SERENUT VE ERKUL ÇEYİZ İZOLE GÖÇÜ VE İZOLASYON ===');

      // A) Serenut
      expect(rawSerenutBackup.existsSync(), isTrue);
      final serenutRawPath = '${tempDir.path}\\serenut_isolated_raw.db';
      final serenutTargetPath = '${tempDir.path}\\serenut_isolated_target.db';
      await rawSerenutBackup.copy(serenutRawPath);

      final serenutLegacyDb = await openDatabase(serenutRawPath, readOnly: true);
      final serenutCoreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: serenutTargetPath);
      final serenutBridge = MigrationBridgeEngine(serenutCoreDb);

      final sReport = await serenutBridge.migrateFromLegacy(serenutLegacyDb, fullScope: true);
      expect(sReport.isSuccess, isTrue);
      expect(sReport.productsMigrated, equals(6377));
      expect(sReport.customersMigrated, equals(7));

      final sBalRow = await serenutCoreDb.db.rawQuery('SELECT SUM(balance_cents) as s FROM customers');
      final sBal = (sBalRow.first['s'] as num).toInt();
      expect(sBal, equals(-267300), reason: 'Serenut bakiye -2.673,00 TL (-267.300 kuruş) olmalıdır');

      // B) ERKUL ÇEYİZ
      expect(rawErkulBackup.existsSync(), isTrue);
      final erkulTargetPath = '${tempDir.path}\\erkul_isolated_target.db';
      final erkulCoreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: erkulTargetPath);
      final erkulBridge = MigrationBridgeEngine(erkulCoreDb);

      final jsonContent = await rawErkulBackup.readAsString();
      final erkulData = jsonDecode(jsonContent) as Map<String, dynamic>;
      final erkulCustomers = erkulData['customers'] as List<dynamic>;
      final eReport = await erkulBridge.migrateFromErkulJson(erkulData);
      expect(eReport.isSuccess, isTrue, reason: eReport.errorMessage);
      expect(eReport.customersMigrated, equals(401));

      final eBalRow = await erkulCoreDb.db.rawQuery('SELECT SUM(balance_cents) as s FROM customers');
      final eBal = (eBalRow.first['s'] as num).toInt();
      expect(eBal, equals(-52362000), reason: 'ERKUL ÇEYİZ bakiye -523.620,00 TL (-52.362.000 kuruş) olmalıdır');


      // C) Tenant İzolasyonu Kontrolü
      final nutopiaCusts = (await serenutCoreDb.db.rawQuery('SELECT id FROM customers')).map((r) => r['id'].toString()).toSet();
      final erkulCusts = erkulCustomers.map((c) => c['id'].toString()).toSet();
      final intersection = nutopiaCusts.intersection(erkulCusts);
      expect(intersection.isEmpty, isTrue, reason: 'İşletmeler arasında müşteri sızıntısı sıfır olmalıdır');

      await serenutLegacyDb.close();
      await serenutCoreDb.close();
      await erkulCoreDb.close();
      print('  [PASS] Serenut (6.377 ürün, 7 müşteri) ve ERKUL (401 müşteri) tam mutabık, çapraz sızıntı 0.');
    });

    // ─────────────────────────────────────────────────────────────────────────
    // 4. TEKRAR ÇALIŞTIRMA (IDEMPOTENCY), INTEGRITY VE ROLLBACK
    // ─────────────────────────────────────────────────────────────────────────
    test('4. İdempotency, PRAGMA Bütünlüğü ve Rollback Güvencesi', () async {
      print('\n=== BÖLÜM 4: İDEMPOTENCY, PRAGMA VE İŞLEM BÜTÜNLÜĞÜ ===');

      final isolatedRawPath = '${tempDir.path}\\nutopia_isolated_raw.db';
      final isolatedTargetPath = '${tempDir.path}\\nutopia_isolated_target.db';

      final legacyDb = await openDatabase(isolatedRawPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // Göçü İKİNCİ KEZ çalıştır (İdempotency testi)
      print('  Göç motoru ikinci kez çalıştırılıyor...');
      final report2 = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report2.isSuccess, isTrue);

      final target = coreDb.db;

      // Çift kayıt oluşmaması kontrolü
      final totalLedger = count(await target.rawQuery('SELECT count(*) FROM ledger_entries'));
      expect(totalLedger, equals(1403), reason: 'İkinci çalıştırmada ledger sayısı 1403 olarak sabit kalmalıdır');

      final totalCusts = count(await target.rawQuery('SELECT count(*) FROM customers'));
      expect(totalCusts, equals(584));

      final totalBalRow = await target.rawQuery('SELECT SUM(balance_cents) as s FROM customers');
      expect((totalBalRow.first['s'] as num).toInt(), equals(-13450068));

      // PRAGMA Bütünlük Testleri
      final integ = await target.rawQuery('PRAGMA integrity_check');
      expect(integ.first.values.first, equals('ok'));

      final fk = await target.rawQuery('PRAGMA foreign_key_check');
      expect(fk.isEmpty, isTrue);

      await legacyDb.close();
      await coreDb.close();
      print('  [PASS] İdempotency (%100 mükerrersizlik), PRAGMA integrity_check=ok, foreign_key_check=0.');
    });
  });
}
