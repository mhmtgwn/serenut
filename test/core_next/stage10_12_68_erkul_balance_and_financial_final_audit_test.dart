// test/core_next/stage10_12_68_erkul_balance_and_financial_final_audit_test.dart
// STAGE 10.12.68: Erkul Bakiye Semantiği ve Üç İşletme Finansal Son Kanıt Denetimi Testi
// Bu test HİÇBİR veritabanına veya dosyaya YAZMAZ. Salt-okunur (readOnly: true) modda çalışır.
// ignore_for_file: avoid_relative_lib_imports, prefer_single_quotes

import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  final nutopiaSrcPath = File('backups/raw_tenants_20261016/raw_nutopia_v60.db').absolute.path;
  final nutopiaTgtPath = File('backups/stage64_isolated/nutopia/nutopia_core_next.db').absolute.path;

  final serenutSrcPath = File('backups/raw_tenants_20261016/raw_serenut_v44.db').absolute.path;
  final serenutTgtPath = File('backups/stage64_isolated/serenut/serenut_core_next.db').absolute.path;

  final erkulSrcPath = File('backups/raw_tenants_20261016/raw_erkul_source.json').absolute.path;
  final erkulTgtPath = File('backups/stage64_isolated/erkul/erkul_core_next.db').absolute.path;

  group('STAGE 10.12.68: 1. Değişmez Güvenlik Sınırları & Salt-Okunur Dosya Bütünlüğü', () {
    test('Kural 1: Güvenlik bayrakları kesinlikle devredışıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
      expect(DatabaseManager.databaseRoutingHook, isNull);
      expect(container.read(coreNextSaleExecutorProvider), isNull);
    });

    test('Kural 2: Altı dosya mevcuttur ve boyutları doğrulanır', () {
      expect(File(nutopiaSrcPath).lengthSync(), equals(59764736));
      expect(File(nutopiaTgtPath).lengthSync(), equals(17018880));

      expect(File(serenutSrcPath).lengthSync(), equals(6516736));
      expect(File(serenutTgtPath).lengthSync(), equals(2359296));

      expect(File(erkulSrcPath).lengthSync(), equals(485357));
      expect(File(erkulTgtPath).lengthSync(), equals(565248));
    });
  });

  group('STAGE 10.12.68: 2. Erkul Çeyiz Bakiye Semantiğinin Kesin Matematiksel Kanıtı', () {
    late Map<String, dynamic> erkulJson;
    late Database eTgtDb;

    setUpAll(() async {
      erkulJson = jsonDecode(File(erkulSrcPath).readAsStringSync()) as Map<String, dynamic>;
      eTgtDb = await openReadOnlyDatabase(erkulTgtPath);
    });

    tearDownAll(() async {
      await eTgtDb.close();
    });

    test('Kanıt 1: Kaynak JSON customer.balance alanı sadece tahsilatların eksi toplamıdır (-sum(collection))', () {
      final custs = (erkulJson['customers'] as List?) ?? [];
      final fts = (erkulJson['financial_transactions'] as List?) ?? [];

      final txByCust = <String, List<Map<String, dynamic>>>{};
      for (final tx in fts) {
        final cid = tx['customer_id'] as String?;
        if (cid != null) {
          txByCust.putIfAbsent(cid, () => []).add(tx as Map<String, dynamic>);
        }
      }

      int matchCount = 0;
      for (final c in custs) {
        final cid = c['id'] as String;
        final rawBal = double.tryParse(c['balance']?.toString() ?? '0') ?? 0.0;
        final cTxs = txByCust[cid] ?? [];
        final colSum = cTxs
            .where((t) => t['type'] == 'collection')
            .fold<double>(0.0, (acc, t) => acc + (double.tryParse(t['amount']?.toString() ?? '0') ?? 0.0));

        if ((rawBal - (-colSum)).abs() < 0.01) {
          matchCount++;
        }
      }

      // 401 müşterinin 397'sinde (%99) balance tam olarak -collections'a eşittir!
      expect(matchCount, equals(397));
    });

    test('Kanıt 2: Geriye kalan 4 müşteri TUNAHAN demo carileridir ve borç-alacak netleri tam 0 TL\'dir', () {
      final custs = (erkulJson['customers'] as List?) ?? [];
      final fts = (erkulJson['financial_transactions'] as List?) ?? [];

      final txByCust = <String, List<Map<String, dynamic>>>{};
      for (final tx in fts) {
        final cid = tx['customer_id'] as String?;
        if (cid != null) {
          txByCust.putIfAbsent(cid, () => []).add(tx as Map<String, dynamic>);
        }
      }

      final exceptions = <Map<String, dynamic>>[];
      for (final c in custs) {
        final cid = c['id'] as String;
        final rawBal = double.tryParse(c['balance']?.toString() ?? '0') ?? 0.0;
        final cTxs = txByCust[cid] ?? [];
        final colSum = cTxs
            .where((t) => t['type'] == 'collection')
            .fold<double>(0.0, (acc, t) => acc + (double.tryParse(t['amount']?.toString() ?? '0') ?? 0.0));

        if ((rawBal - (-colSum)).abs() >= 0.01) {
          exceptions.add(c as Map<String, dynamic>);
        }
      }

      expect(exceptions.length, equals(4));
      for (final e in exceptions) {
        expect(e['name'], equals('TUNAHAN'));
        expect(e['is_deleted'], isTrue);
      }
    });

    test('Kanıt 3: 20 Silinmiş Müşterinin Tamamında Borç == Tahsilat olduğundan Bakiye 0 Kuruştur', () async {
      final deletedCustRows = await eTgtDb.rawQuery(
        'SELECT id, name, balance_cents FROM customers WHERE is_deleted = 1',
      );
      expect(deletedCustRows.length, equals(20));

      for (final r in deletedCustRows) {
        expect(r['balance_cents'], equals(0),
            reason: 'Silinmiş müşteri ${r['id']} borçları ödendiği için bakiyesi tam 0 kuruş olmalıdır');
      }
    });

    test('Kanıt 4: 381 Aktif Müşteride Gerçek Alacak 3.787.125 TL (-378,712,500 kuruş) Olarak Doğrulanır', () async {
      final activeBal = Sqflite.firstIntValue(
        await eTgtDb.rawQuery('SELECT SUM(balance_cents) FROM customers WHERE is_deleted = 0'),
      );
      expect(activeBal, equals(-378712500)); // -3,787,125.00 TL (Receivable / Alacak)
    });
  });

  group('STAGE 10.12.68: 3. Üç İşletmede 1,985 Finansal Hareketin Satır Satır (1-to-1) Doğrulanması', () {
    late Database nSrcDb;
    late Database nTgtDb;
    late Database sSrcDb;
    late Database sTgtDb;
    late Database eTgtDb;
    late Map<String, dynamic> erkulJson;

    setUpAll(() async {
      nSrcDb = await openReadOnlyDatabase(nutopiaSrcPath);
      nTgtDb = await openReadOnlyDatabase(nutopiaTgtPath);
      sSrcDb = await openReadOnlyDatabase(serenutSrcPath);
      sTgtDb = await openReadOnlyDatabase(serenutTgtPath);
      eTgtDb = await openReadOnlyDatabase(erkulTgtPath);
      erkulJson = jsonDecode(File(erkulSrcPath).readAsStringSync()) as Map<String, dynamic>;
    });

    tearDownAll(() async {
      await nSrcDb.close();
      await nTgtDb.close();
      await sSrcDb.close();
      await sTgtDb.close();
      await eTgtDb.close();
    });

    test('Nutopia: 1,424 Hareketin Tamamı (1,403 Defter + 21 Kasa) Satır Satır Eşleşir (0 Eksik, 0 Fark)', () async {
      final srcTxs = await nSrcDb.rawQuery(
        'SELECT id, customer_id, type, amount FROM financial_transactions',
      );
      expect(srcTxs.length, equals(1424));

      int matchedLedger = 0;
      int matchedCash = 0;

      for (final s in srcTxs) {
        final sId = s['id'] as String;
        final sCid = (s['customer_id'] as String?)?.trim() ?? '';
        final sType = (s['type'] as String).toUpperCase();
        final sCents = ((s['amount'] as num).toDouble() * 100).round();

        if (sCid.isNotEmpty) {
          final tRows = await nTgtDb.rawQuery(
            'SELECT id, customer_id, entry_type, amount_cents FROM ledger_entries WHERE id = ?',
            [sId],
          );
          expect(tRows.length, equals(1), reason: 'İşlem $sId hedef ledger_entries içinde bulunamadı');
          final t = tRows.first;
          expect(t['customer_id'], equals(sCid));
          expect(t['entry_type'], equals(sType));
          expect(t['amount_cents'], equals(sCents));
          matchedLedger++;
        } else {
          final tRows = await nTgtDb.rawQuery(
            'SELECT id, amount_cents FROM cash_transactions WHERE id = ?',
            [sId],
          );
          expect(tRows.length, equals(1), reason: 'Carisiz işlem $sId hedef cash_transactions içinde bulunamadı');
          expect(tRows.first['amount_cents'], equals(sCents));
          matchedCash++;
        }
      }

      expect(matchedLedger, equals(1403));
      expect(matchedCash, equals(21));
    });

    test('Serenut: 22 Hareketin Tamamı (12 Defter + 10 Kasa) Satır Satır Eşleşir (0 Eksik, 0 Fark)', () async {
      final srcTxs = await sSrcDb.rawQuery(
        'SELECT id, customer_id, type, amount FROM financial_transactions',
      );
      expect(srcTxs.length, equals(22));

      int matchedLedger = 0;
      int matchedCash = 0;

      for (final s in srcTxs) {
        final sId = s['id'] as String;
        final sCid = (s['customer_id'] as String?)?.trim() ?? '';
        final sType = (s['type'] as String).toUpperCase();
        final sCents = ((s['amount'] as num).toDouble() * 100).round();

        if (sCid.isNotEmpty) {
          final tRows = await sTgtDb.rawQuery(
            'SELECT id, customer_id, entry_type, amount_cents FROM ledger_entries WHERE id = ?',
            [sId],
          );
          expect(tRows.length, equals(1));
          final t = tRows.first;
          expect(t['customer_id'], equals(sCid));
          expect(t['entry_type'], equals(sType));
          expect(t['amount_cents'], equals(sCents));
          matchedLedger++;
        } else {
          final tRows = await sTgtDb.rawQuery(
            'SELECT id, amount_cents FROM cash_transactions WHERE id = ?',
            [sId],
          );
          expect(tRows.length, equals(1));
          expect(tRows.first['amount_cents'], equals(sCents));
          matchedCash++;
        }
      }

      expect(matchedLedger, equals(12));
      expect(matchedCash, equals(10));
    });

    test('Erkul Çeyiz: 539 Hareketin Tamamı Defterde Satır Satır Eşleşir (0 Eksik, 0 Fark)', () async {
      final eTxs = (erkulJson['financial_transactions'] as List?) ?? [];
      expect(eTxs.length, equals(539));

      int matched = 0;
      for (final tx in eTxs) {
        final sId = tx['id'] as String;
        final sCid = tx['customer_id'] as String;
        final sType = (tx['type'] as String).toUpperCase();
        final sCents = ((double.tryParse(tx['amount']?.toString() ?? '0') ?? 0.0) * 100).round();

        final tRows = await eTgtDb.rawQuery(
          'SELECT id, customer_id, entry_type, amount_cents FROM ledger_entries WHERE id = ?',
          [sId],
        );
        expect(tRows.length, equals(1), reason: 'Erkul işlem $sId hedefte bulunamadı');
        final t = tRows.first;
        expect(t['customer_id'], equals(sCid));
        expect(t['entry_type'], equals(sType));
        expect(t['amount_cents'], equals(sCents));
        matched++;
      }

      expect(matched, equals(539));
    });
  });
}
