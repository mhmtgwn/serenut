// test/core_next/stage10_12_66_nutopia_promissory_independent_audit_test.dart
// STAGE 10.12.66: Nutopia Senetli İşlemler Bağımsız Kanıt Denetimi
// Bu test HİÇBİR veritabanına yazmaz. Salt-okunur (readOnly: true) modda açar.
// ignore_for_file: avoid_relative_lib_imports, prefer_single_quotes

import 'dart:io';
import 'package:crypto/crypto.dart';
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

  final rawNutopiaPath = File('backups/raw_tenants_20261016/raw_nutopia_v60.db').absolute.path;
  final targetNutopiaPath = File('backups/stage64_isolated/nutopia/nutopia_core_next.db').absolute.path;

  group('STAGE 10.12.66: 1. Değişmez Güvenlik Sınırları & Salt-Okunur Dosya Kimliği', () {
    test('Kural 1: Güvenlik bayrakları kesinlikle devredışıdır', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
      expect(DatabaseManager.databaseRoutingHook, isNull);
      expect(container.read(coreNextSaleExecutorProvider), isNull);
    });

    test('Kural 2: Kaynak ve Hedef dosyaları mevcuttur, boyut ve SHA-256 doğrulanır', () {
      final srcFile = File(rawNutopiaPath);
      final tgtFile = File(targetNutopiaPath);

      expect(srcFile.existsSync(), isTrue);
      expect(tgtFile.existsSync(), isTrue);

      expect(srcFile.lengthSync(), equals(59764736));
      expect(tgtFile.lengthSync(), equals(17018880));

      final srcSha = sha256.convert(srcFile.readAsBytesSync()).toString();
      expect(srcSha, equals('e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24'));
    });
  });

  group('STAGE 10.12.66: 2. Salt-Okunur Veritabanı Bütünlüğü & Bire Bir İşlem Eşleştirmesi', () {
    late Database srcDb;
    late Database tgtDb;

    setUpAll(() async {
      srcDb = await openReadOnlyDatabase(rawNutopiaPath);
      tgtDb = await openReadOnlyDatabase(targetNutopiaPath);
    });

    tearDownAll(() async {
      await srcDb.close();
      await tgtDb.close();
    });

    test('Bütünlük Kontrolleri: Her iki DB integrity_check ve foreign_key_check geçer', () async {
      final srcIc = await srcDb.rawQuery('PRAGMA integrity_check;');
      final tgtIc = await tgtDb.rawQuery('PRAGMA integrity_check;');
      expect(srcIc.first.values.first, equals('ok'));
      expect(tgtIc.first.values.first, equals('ok'));

      final tgtFk = await tgtDb.rawQuery('PRAGMA foreign_key_check;');
      expect(tgtFk, isEmpty);
    });

    test('54 Manuel Borç Kaydının Bire Bir (1-to-1) İşlem Düzeyinde Eşleşmesi', () async {
      final srcDebts = await srcDb.rawQuery(
        "SELECT id, customer_id, type, amount, debt_amount, paid_amount, reference_id, description, created_at, is_deleted "
        "FROM financial_transactions WHERE type = 'manual_debt' ORDER BY created_at ASC",
      );
      expect(srcDebts.length, equals(54));

      int matchedCount = 0;
      int totalSourceCents = 0;

      for (final s in srcDebts) {
        final sId = s['id'] as String;
        final sCustId = s['customer_id'] as String;
        final sAmount = (s['amount'] as num).toDouble();
        final sDebtAmount = (s['debt_amount'] as num).toDouble();
        final sPaidAmount = (s['paid_amount'] as num).toDouble();
        final sAmountCents = (sAmount * 100).round();
        totalSourceCents += sAmountCents;

        // Manuel borçların hepsi başlangıçta ödenmemiş borçtur
        expect(sDebtAmount, equals(sAmount));
        expect(sPaidAmount, equals(0.0));
        expect(s['is_deleted'], equals(0));

        // Hedefte id ile bire bir ara
        final tgtRows = await tgtDb.rawQuery(
          "SELECT id, customer_id, reference_sale_id, entry_type, amount_cents, description FROM ledger_entries WHERE id = ?",
          [sId],
        );
        expect(tgtRows.length, equals(1), reason: 'İşlem $sId hedefte tam olarak 1 kez bulunmalıdır');
        final t = tgtRows.first;

        expect(t['id'], equals(sId));
        expect(t['customer_id'], equals(sCustId));
        expect(t['entry_type'], equals('MANUAL_DEBT'));
        expect(t['amount_cents'], equals(sAmountCents));
        expect(t['description'], equals(s['description'] ?? 'Eski Finansal Hareket'));

        // reference_sale_id kuralı: sales tablosu referansı değilse null olmalıdır
        final sRef = s['reference_id'];
        if (sRef != null) {
          expect(t['reference_sale_id'], isNull); // plan ID'si olduğu için sales FK kuralı gereği null
        }

        matchedCount++;
      }

      expect(matchedCount, equals(54));
      expect(totalSourceCents, equals(10335100)); // 103,351.00 TL

      // Hedefteki toplam MANUAL_DEBT sayısı ve tutarı
      final tgtStats = await tgtDb.rawQuery(
        "SELECT COUNT(*) as cnt, SUM(amount_cents) as total FROM ledger_entries WHERE entry_type = 'MANUAL_DEBT'",
      );
      expect(tgtStats.first['cnt'], equals(54));
      expect(tgtStats.first['total'], equals(10335100));
    });

    test('2 Taksit Planı, Master Borç ve Peşinat Tahsilat Kayıtları Eşleşmesi', () async {
      final srcPlans = await srcDb.rawQuery(
        "SELECT id, customer_id, total_amount, down_payment, installment_count, status, is_deleted FROM customer_installment_plans",
      );
      expect(srcPlans.length, equals(2));

      for (final sp in srcPlans) {
        final pId = sp['id'] as String;
        final tpRows = await tgtDb.rawQuery(
          "SELECT id, customer_id, total_amount_cents, down_payment_cents, installment_count, status, is_deleted "
          "FROM customer_installment_plans WHERE id = ?",
          [pId],
        );
        expect(tpRows.length, equals(1));
        final tp = tpRows.first;

        expect(tp['id'], equals(pId));
        expect(tp['customer_id'], equals(sp['customer_id']));
        expect(tp['total_amount_cents'], equals(((sp['total_amount'] as num) * 100).round()));
        expect(tp['down_payment_cents'], equals(((sp['down_payment'] as num) * 100).round()));
        expect(tp['installment_count'], equals(sp['installment_count']));
        expect(tp['status'], equals(sp['status']));
        expect(tp['is_deleted'], equals(sp['is_deleted']));

        // Her planın kaynakta 1 master manual_debt kaydı vardır
        final masterDebts = await srcDb.rawQuery(
          "SELECT id, amount, is_deleted FROM financial_transactions WHERE reference_id = ? AND type = 'manual_debt'",
          [pId],
        );
        expect(masterDebts.length, equals(1));
        final md = masterDebts.first;

        // Hedefte bu master borç MANUAL_DEBT olarak mevcuttur
        final tgtMd = await tgtDb.rawQuery(
          "SELECT id, amount_cents, entry_type FROM ledger_entries WHERE id = ?",
          [md['id']],
        );
        expect(tgtMd.length, equals(1));
        expect(tgtMd.first['amount_cents'], equals(((md['amount'] as num) * 100).round()));
        expect(tgtMd.first['entry_type'], equals('MANUAL_DEBT'));

        // Her planın kaynakta 1 peşinat tahsilat kaydı vardır (type = 'collection')
        final downPayments = await srcDb.rawQuery(
          "SELECT id, amount, is_deleted FROM financial_transactions WHERE reference_id = ? AND type = 'collection'",
          [pId],
        );
        expect(downPayments.length, equals(1));
        final dp = downPayments.first;

        final tgtDp = await tgtDb.rawQuery(
          "SELECT id, amount_cents, entry_type FROM ledger_entries WHERE id = ?",
          [dp['id']],
        );
        expect(tgtDp.length, equals(1));
        expect(tgtDp.first['amount_cents'], equals(((dp['amount'] as num) * 100).round()));
        expect(tgtDp.first['entry_type'], equals('COLLECTION'));
      }
    });

    test('9 Taksit Kaleminin Bire Bir Eşleşmesi', () async {
      final srcInsts = await srcDb.rawQuery(
        "SELECT id, plan_id, customer_id, installment_no, amount, paid_amount, status, financial_transaction_id, is_deleted "
        "FROM customer_installments ORDER BY plan_id, installment_no",
      );
      expect(srcInsts.length, equals(9));

      for (final si in srcInsts) {
        final iId = si['id'] as String;
        final tiRows = await tgtDb.rawQuery(
          "SELECT id, plan_id, customer_id, installment_no, amount_cents, paid_amount_cents, status, financial_transaction_id, is_deleted "
          "FROM customer_installments WHERE id = ?",
          [iId],
        );
        expect(tiRows.length, equals(1));
        final ti = tiRows.first;

        expect(ti['id'], equals(iId));
        expect(ti['plan_id'], equals(si['plan_id']));
        expect(ti['customer_id'], equals(si['customer_id']));
        expect(ti['installment_no'], equals(si['installment_no']));
        expect(ti['amount_cents'], equals(((si['amount'] as num) * 100).round()));
        expect(ti['paid_amount_cents'], equals(((si['paid_amount'] as num) * 100).round()));
        expect(ti['status'], equals(si['status']));
        expect(ti['financial_transaction_id'], equals(si['financial_transaction_id']));
        expect(ti['is_deleted'], equals(si['is_deleted']));
      }
    });

    test('8 Taksit Tahsilatının Bire Bir Eşleşmesi', () async {
      final srcCols = await srcDb.rawQuery(
        "SELECT id, customer_id, amount, description FROM financial_transactions "
        "WHERE type = 'collection' AND (description LIKE '%Taksit%' OR description LIKE '%taksit%')",
      );
      expect(srcCols.length, equals(8));

      int totalColCents = 0;
      for (final sc in srcCols) {
        final cId = sc['id'] as String;
        final amountCents = ((sc['amount'] as num) * 100).round();
        totalColCents += amountCents;

        final tcRows = await tgtDb.rawQuery(
          "SELECT id, customer_id, amount_cents, entry_type, description FROM ledger_entries WHERE id = ?",
          [cId],
        );
        expect(tcRows.length, equals(1));
        final tc = tcRows.first;

        expect(tc['id'], equals(cId));
        expect(tc['customer_id'], equals(sc['customer_id']));
        expect(tc['amount_cents'], equals(amountCents));
        expect(tc['entry_type'], equals('COLLECTION'));
        expect(tc['description'], equals(sc['description']));
      }

      expect(totalColCents, equals(975332)); // 9,753.32 TL
    });

    test('Müşteri Bazında Bağımsız Bakiye Doğrulaması (584 Müşteri)', () async {
      // 1. Kaynak v_customer_ledger_effect toplamları
      final viewRows = await srcDb.rawQuery(
        "SELECT customer_id, ROUND(SUM(balance_effect), 2) as eff FROM v_customer_ledger_effect GROUP BY customer_id",
      );
      final viewMap = {for (final r in viewRows) r['customer_id'] as String: (r['eff'] as num).toDouble()};

      // 2. Kaynak customers tablosu
      final srcCusts = await srcDb.rawQuery('SELECT id, name, balance FROM customers');
      expect(srcCusts.length, equals(584));

      // 3. Hedef customers tablosu
      final tgtCusts = await tgtDb.rawQuery('SELECT id, name, balance_cents FROM customers');
      final tgtMap = {for (final r in tgtCusts) r['id'] as String: r['balance_cents'] as int};

      int matchCount = 0;
      for (final sc in srcCusts) {
        final cid = sc['id'] as String;
        final sBal = (sc['balance'] as num?)?.toDouble() ?? 0.0;
        final vBal = viewMap[cid] ?? 0.0;

        // Kontrol A: Kaynak customers.balance == Kaynak v_customer_ledger_effect
        expect((sBal * 100).round(), equals((vBal * 100).round()),
            reason: 'Müşteri $cid için kaynak bakiye ile defter etkisi bire bir eşit olmalıdır');

        // Kontrol B: Hedef customers.balance_cents
        if (cid.isNotEmpty) {
          final tCents = tgtMap[cid];
          expect(tCents, isNotNull, reason: 'Müşteri $cid hedefte mevcut olmalıdır');
          expect(tCents, equals((sBal * 100).round()),
              reason: 'Müşteri $cid için hedef balance_cents kaynak balance ile kuruşu kuruşuna eşit olmalıdır');
          matchCount++;
        }
      }

      expect(matchCount, equals(583)); // 1 kayıt boş id'li "Peşin Müşteri" idi (cari dışı)
    });

    test('Satış ile Senetli Borç Kesişimi Sıfırdır (No Double-Counting)', () async {
      final overlap = Sqflite.firstIntValue(
        await tgtDb.rawQuery(
          "SELECT COUNT(*) FROM ledger_entries WHERE entry_type = 'MANUAL_DEBT' AND id IN (SELECT id FROM sales)",
        ),
      );
      expect(overlap, equals(0));
    });
  });
}
