// test/core_next/stage10_12_12_anonymous_cash_sales_test.dart
// STAGE 10.12.12 — 21 MÜŞTERİSİZ NAKİT SATIŞIN KAYIPSIZ VE İDEMPOTENT GÖÇÜ TESTİ

@Timeout(Duration(minutes: 3))

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('STAGE 10.12.12 — 21 Müşterisiz Nakit Satışın Kayıpsız ve İdempotent Göçü', () {
    late Directory tempDir;
    final rawNutopiaBackup = File(r'C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_nutopia_v60.db');

    setUpAll(() {
      tempDir = Directory.systemTemp.createTempSync('stage10_12_12_anon_cash_');
    });

    tearDownAll(() {
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 1: Gerçek Nutopia Kopyası Üzerinde 21 Müşterisiz Nakit Satışın
    //         cash_transactions Tablosuna 1:1 ve Eksiksiz Göçü
    // ─────────────────────────────────────────────────────────────────────────
    test('1. 21 Müşterisiz Nakit Satış cash_transactions Tablosuna 12.197 TL Olarak Aktarılmalıdır', () async {
      print('\n=== TEST 1: 21 MÜŞTERİSİZ NAKİT SATIŞIN KESİN GÖÇÜ VE MUTABAKATI ===');

      expect(rawNutopiaBackup.existsSync(), isTrue, reason: 'Nutopia ham yedeği diskte bulunmalıdır');

      final isolatedRawPath = '${tempDir.path}\\nutopia_isolated_raw.db';
      final isolatedTargetPath = '${tempDir.path}\\nutopia_isolated_target.db';

      // Ham yedeğe asla yazmadan izole test kopyası al
      await rawNutopiaBackup.copy(isolatedRawPath);

      final legacyDb = await openDatabase(isolatedRawPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // Göçü çalıştır
      final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, isTrue, reason: report.errorMessage);

      final target = coreDb.db;

      // 1. Kaynakta beklenen 21 kaydın tamamı mevcut mu?
      final srcAnonRows = await legacyDb.rawQuery(
        "SELECT * FROM financial_transactions WHERE customer_id IS NULL OR customer_id = '' ORDER BY created_at ASC",
      );
      expect(srcAnonRows.length, equals(21), reason: 'Kaynakta tam 21 adet müşterisiz hareket olmalıdır');

      // 2. 21 kaydın tamamı sales tablosunda doğru satışa bağlı mı?
      final srcSalesRows = await legacyDb.query('sales');
      final srcSalesMap = {for (final s in srcSalesRows) s['id'].toString(): s};

      int srcTotalMinor = 0;
      for (final src in srcAnonRows) {
        final refId = src['reference_id']?.toString();
        expect(refId, isNotNull, reason: 'reference_id boş olamaz');
        expect(srcSalesMap.containsKey(refId), isTrue, reason: 'Satış $refId sales tablosunda bulunmalıdır');
        
        final sale = srcSalesMap[refId]!;
        expect(sale['payment_method'], equals('cash'), reason: 'Ödeme yöntemi cash olmalıdır');
        expect(sale['status'], equals('completed'), reason: 'Satış status completed olmalıdır');

        // 3. Satış ve ödeme tutarları eşleşiyor mu?
        final ftAmount = (src['amount'] as num).toDouble();
        final saleTotal = (sale['total_amount'] as num).toDouble();
        final salePaid = (sale['paid_amount'] as num).toDouble();
        expect(ftAmount, equals(saleTotal), reason: 'FT tutarı satış toplamına eşit olmalıdır');
        expect(salePaid, equals(saleTotal), reason: 'Satış tahsilatı toplam tutara eşit olmalıdır');

        final minor = (src['amount_minor'] as num?)?.toInt() ?? (ftAmount * 100).round();
        srcTotalMinor += minor;
      }
      expect(srcTotalMinor, equals(1219700), reason: 'Kaynak 21 hareketin toplamı 1.219.700 kuruş (12.197 TL) olmalıdır');

      // 4. Hedefte 21 kaydın tamamı cash_transactions tablosunda bulunuyor mu?
      final targetCashRows = await target.query(
        'cash_transactions',
        where: "category = 'SALE'",
        orderBy: 'created_at ASC',
      );
      expect(targetCashRows.length, equals(21), reason: 'Hedef cash_transactions tablosunda tam 21 kayıt olmalıdır');

      // 5. Hedefte eksik veya mükerrer kayıt var mı?
      final targetCashMap = {for (final r in targetCashRows) r['id'].toString(): r};
      expect(targetCashMap.length, equals(21), reason: 'Tüm 21 kayıt benzersiz birincil anahtara (PK) sahip olmalıdır');

      int targetTotalCents = 0;
      for (final src in srcAnonRows) {
        final srcId = src['id'].toString();
        expect(targetCashMap.containsKey(srcId), isTrue, reason: 'İşlem $srcId hedef cash_transactions tablosunda bulunmalıdır');

        final tgt = targetCashMap[srcId]!;
        expect(tgt['type'], equals('INFLOW'), reason: 'İşlem türü INFLOW olmalıdır');
        expect(tgt['category'], equals('SALE'), reason: 'Kategori SALE olmalıdır');
        
        final tgtCents = (tgt['amount_cents'] as num).toInt();
        final rawAmount = (src['amount'] as num).toDouble();
        final rawMinor = (src['amount_minor'] as num?)?.toInt();
        final expectedCents = MigrationBridgeEngine.resolveAmountCents(rawAmountNum: rawAmount, rawMinorNum: rawMinor);
        expect(tgtCents, equals(expectedCents), reason: 'Tutar kuruşu kuruşuna eşit olmalıdır');
        targetTotalCents += tgtCents;
      }

      // 6. 21 kaydın toplamı tam olarak 12.197,00 TL mi?
      expect(targetTotalCents, equals(1219700), reason: 'Hedef toplam tam 12.197,00 TL (1.219.700 kuruş) olmalıdır');

      // 7. Müşteri defteri bakiyeleri bu nakit satışlar yüzünden değişmiyor mu?
      final targetLedgerRows = await target.query('ledger_entries');
      expect(targetLedgerRows.length, equals(1403), reason: 'ledger_entries tam 1403 müşteri hareketi içermelidir (21 anonim hareket buraya sızmamalıdır)');

      final customerRows = await target.query('customers');
      expect(customerRows.length, equals(584), reason: 'Toplam müşteri sayısı 584 olmalıdır');
      int totalBalanceCents = 0;
      for (final c in customerRows) {
        totalBalanceCents += (c['balance_cents'] as num).toInt();
      }
      expect(totalBalanceCents, equals(-13450068), reason: 'Müşteri toplam bakiyesi -134.500,68 TL olarak korunmalıdır');

      // 8. PRAGMA integrity_check ve foreign_key_check
      final integrity = await target.rawQuery('PRAGMA integrity_check;');
      expect(integrity.first.values.first, equals('ok'), reason: 'PRAGMA integrity_check ok dönmelidir');

      final fkCheck = await target.rawQuery('PRAGMA foreign_key_check;');
      expect(fkCheck.isEmpty, isTrue, reason: 'PRAGMA foreign_key_check boş olmalıdır (0 hata)');

      print('  [PASS] 21 Müşterisiz nakit satış tam 12.197,00 TL olarak cash_transactions tablosuna aktarıldı.');
      print('  [PASS] 1.403 Müşteri defteri ve -134.500,68 TL müşteri bakiyesi sıfır sapma ile korundu.');

      await legacyDb.close();
      await coreDb.close();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 2: İkinci Çalıştırma (Idempotency) — Mükerrer Kayıt Oluşmaması
    // ─────────────────────────────────────────────────────────────────────────
    test('2. İkinci Çalıştırmada cash_transactions Mükerrer Kayıt Üretmemelidir', () async {
      print('\n=== TEST 2: İKİNCİ ÇALIŞTIRMA (IDEMPOTENCY) DOĞRULAMASI ===');

      final isolatedRawPath = '${tempDir.path}\\nutopia_idempotency_raw.db';
      final isolatedTargetPath = '${tempDir.path}\\nutopia_idempotency_target.db';

      await rawNutopiaBackup.copy(isolatedRawPath);

      final legacyDb = await openDatabase(isolatedRawPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // İlk çalıştırma
      final rep1 = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep1.isSuccess, isTrue);

      final target = coreDb.db;
      final count1 = (await target.rawQuery("SELECT COUNT(*) as c FROM cash_transactions WHERE category = 'SALE'")).first['c'] as int;
      final sum1 = (await target.rawQuery("SELECT SUM(amount_cents) as s FROM cash_transactions WHERE category = 'SALE'")).first['s'] as int;
      expect(count1, equals(21));
      expect(sum1, equals(1219700));

      // İkinci çalıştırma (Aynı hedef DB üzerinde)
      final rep2 = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(rep2.isSuccess, isTrue);

      final count2 = (await target.rawQuery("SELECT COUNT(*) as c FROM cash_transactions WHERE category = 'SALE'")).first['c'] as int;
      final sum2 = (await target.rawQuery("SELECT SUM(amount_cents) as s FROM cash_transactions WHERE category = 'SALE'")).first['s'] as int;

      expect(count2, equals(21), reason: 'İkinci çalıştırmada kayıt sayısı 21 olarak sabit kalmalıdır');
      expect(sum2, equals(1219700), reason: 'İkinci çalıştırmada toplam tutar 12.197,00 TL olarak sabit kalmalıdır');

      final ledgerCount = (await target.rawQuery("SELECT COUNT(*) as c FROM ledger_entries")).first['c'] as int;
      expect(ledgerCount, equals(1403), reason: 'ledger_entries sayısı da 1403 olarak sabit kalmalıdır');

      print('  [PASS] İkinci çalıştırma %100 idempotent: Sayı 21, Tutar 12.197,00 TL mükerrersiz korundu.');

      await legacyDb.close();
      await coreDb.close();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 3: Hata Enjeksiyonu ve Atomik Rollback Davranışı
    // ─────────────────────────────────────────────────────────────────────────
    test('3. Müşterisiz Satış Sırasında Hata Alınırsa Transaction Atomik Olarak ROLLBACK Olmalıdır', () async {
      print('\n=== TEST 3: HATA ENJEKSİYONU VE ATOMİK ROLLBACK DENETİMİ ===');

      final isolatedRawPath = '${tempDir.path}\\nutopia_fault_raw.db';
      final isolatedTargetPath = '${tempDir.path}\\nutopia_fault_target.db';

      await rawNutopiaBackup.copy(isolatedRawPath);

      // Yazılabilir modda açarak 1 adet sahte geçersiz referanslı müşterisiz işlem enjekte edelim
      final faultLegacyDb = await openDatabase(isolatedRawPath);
      await faultLegacyDb.insert('financial_transactions', {
        'id': 'ft-fault-corrupted-ref',
        'type': 'sale',
        'amount': 999.0,
        'amount_minor': 99900,
        'customer_id': '', // Müşterisiz
        'reference_id': 'sale-non-existent-fake-id', // sales tablosunda OLMAYAN referans!
        'created_at': DateTime.now().toIso8601String(),
      });
      await faultLegacyDb.close();

      final legacyDb = await openDatabase(isolatedRawPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      // Göç hata fırlatmalıdır (Geçersiz satış referansı tespit edildiğinde StateError)
      final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, isFalse, reason: 'Bozuk referanslı müşterisiz işlemde migration başarısız olmalıdır');
      expect(report.errorMessage, contains('GEÇERSİZ MÜŞTERİSİZ SATIŞ REFERANSI'));

      final target = coreDb.db;
      // Atomik rollback teyidi: Hedefte hiçbir kısmi kayıt kalmamalıdır!
      final cashCount = (await target.rawQuery("SELECT COUNT(*) as c FROM cash_transactions")).first['c'] as int;
      final ledgerCount = (await target.rawQuery("SELECT COUNT(*) as c FROM ledger_entries")).first['c'] as int;
      final productsCount = (await target.rawQuery("SELECT COUNT(*) as c FROM products")).first['c'] as int;

      expect(cashCount, equals(0), reason: 'Rollback sonrası cash_transactions boş olmalıdır');
      expect(ledgerCount, equals(0), reason: 'Rollback sonrası ledger_entries boş olmalıdır');
      expect(productsCount, equals(0), reason: 'Rollback sonrası products boş olmalıdır (Atomik işlem)');

      print('  [PASS] Hata anında tüm tablolar atomik olarak ROLLBACK edildi; 0 yarım kayıt bırakıldı.');

      await legacyDb.close();
      await coreDb.close();
    });

    // ─────────────────────────────────────────────────────────────────────────
    // TEST 4: Kapsamlı Regresyon Senaryoları (Müşterili, Müşterisiz, Vadeli, Karma)
    // ─────────────────────────────────────────────────────────────────────────
    test('4. Çeşitli Ödeme ve Finansal Tiplerin Hedef Eşleşme Regresyonu', () async {
      print('\n=== TEST 4: ÖDEME VE TİP REGRESYON TESTLERİ ===');

      final isolatedRawPath = '${tempDir.path}\\nutopia_regression_raw.db';
      final isolatedTargetPath = '${tempDir.path}\\nutopia_regression_target.db';

      await rawNutopiaBackup.copy(isolatedRawPath);
      final legacyDb = await openDatabase(isolatedRawPath, readOnly: true);
      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: isolatedTargetPath);
      final bridge = MigrationBridgeEngine(coreDb);

      final report = await bridge.migrateFromLegacy(legacyDb, fullScope: true);
      expect(report.isSuccess, isTrue);

      final target = coreDb.db;

      // 1. Müşterili nakit satışlar (sales tablosunda 31 nakit satış vardı; 21'i müşterisiz, 10'u müşterili)
      final salesRows = await target.query('sales');
      final cashSales = salesRows.where((s) => s['idempotency_key'] != null).toList();
      expect(cashSales.length, equals(52));

      // 2. Satış ödemeleri (sale_payments tablosunda nakit ve vadeli kırılımlar)
      final salePayments = await target.query('sale_payments');
      expect(salePayments.isNotEmpty, isTrue);
      final cashPayments = salePayments.where((p) => p['payment_type'] == 'cash').toList();
      final onAccountPayments = salePayments.where((p) => p['payment_type'] == 'onAccount').toList();
      final mixedPayments = salePayments.where((p) => p['payment_type'] == 'mixed').toList();

      expect(cashPayments.length, greaterThanOrEqualTo(31), reason: 'En az 31 nakit satış ödemesi bulunmalıdır');
      expect(onAccountPayments.length, greaterThanOrEqualTo(19), reason: 'En az 19 vadeli satış ödemesi bulunmalıdır');
      expect(mixedPayments.length, equals(2), reason: 'Tam 2 adet karma ödeme bulunmalıdır');

      // 3. İadeler (financial_transactions -> ledger_entries)
      final refundEntries = await target.query('ledger_entries', where: "entry_type = 'REFUND'");
      expect(refundEntries.length, equals(22), reason: 'Tam 22 adet iade cari defter kaydı bulunmalıdır');
      int totalRefundCents = 0;
      for (final r in refundEntries) {
        totalRefundCents += (r['amount_cents'] as num).toInt();
      }
      expect(totalRefundCents, equals(1197700), reason: 'İadeler toplamı 11.977,00 TL (1.197.700 kuruş) olmalıdır');

      print('  [PASS] Müşterili nakit, müşterisiz nakit, vadeli borç, karma ve iade tipleri eksiksiz mutabık.');

      await legacyDb.close();
      await coreDb.close();
    });
  });
}
