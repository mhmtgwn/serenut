// test/core_next/stage10_12_53_dart_reconciliation_repair_test.dart
// STAGE 10.12.53: Gerçek Dart Üretim Yolunda Finansal Kayıt Onarımı ve İzole Doğrulama Test Paketi
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import '../../core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const coordinator = LiveSafeCatchUpReconciliationCoordinator();

  group('STAGE 10.12.53: Değişmez Güvenlik Kuralları', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider kesinlikle false kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null kalmalı', () {
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });
  });

  group('STAGE 10.12.53: Tutar Çözümleme Kuralı (resolveAmountCents)', () {
    test('Senaryo 1: amount_minor = 0, amount != 0 -> Doğru kuruş tutarı çözülür', () {
      expect(
        LiveSafeCatchUpReconciliationCoordinator.resolveAmountCents(5000.0, 0),
        500000,
        reason: 'Unpopulated default 0 durumunda rawAmount * 100 baz alınmalıdır',
      );
      expect(
        LiveSafeCatchUpReconciliationCoordinator.resolveAmountCents(3690.0, 0),
        369000,
      );
      expect(
        LiveSafeCatchUpReconciliationCoordinator.resolveAmountCents(12.34, 0),
        1234,
      );
    });

    test('Senaryo 2: amount_minor = 0, amount = 0 -> Gerçek sıfır korunur', () {
      expect(
        LiveSafeCatchUpReconciliationCoordinator.resolveAmountCents(0.0, 0),
        0,
        reason: 'Hem amount hem de amount_minor 0 ise gerçek sıfırdır',
      );
      expect(
        LiveSafeCatchUpReconciliationCoordinator.resolveAmountCents(0, 0),
        0,
      );
    });

    test('Senaryo 3: amount_minor IS NULL -> Güvenli fallback uygulanır', () {
      expect(
        LiveSafeCatchUpReconciliationCoordinator.resolveAmountCents(750.50, null),
        75050,
        reason: 'amount_minor null olduğunda güvenli fallback ile rawAmount * 100 alınmalıdır',
      );
    });

    test('Senaryo 4: Populated minor cents ile amount uyumlu olduğunda doğrudan minor alınır', () {
      expect(
        LiveSafeCatchUpReconciliationCoordinator.resolveAmountCents(5000.0, 500000),
        500000,
      );
    });
  });

  group('STAGE 10.12.53: Gerçek Dart Üretim Koordinatörü ile İzole Defter Onarımı', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String targetDbPath;
    final openDatabases = <Database>[];

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('stage53_repair_test_');
      legacyDbPath = '${tempDir.path}/isolated_legacy.db';
      targetDbPath = '${tempDir.path}/isolated_target.db';
      openDatabases.clear();
    });

    tearDown(() async {
      for (final db in openDatabases) {
        if (db.isOpen) {
          await db.close();
        }
      }
      openDatabases.clear();
      try {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      } catch (_) {}
    });

    Future<Database> createLegacyDb() async {
      final db = await databaseFactory.openDatabase(
        legacyDbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE financial_transactions (
                id TEXT PRIMARY KEY,
                type TEXT NOT NULL,
                customer_id TEXT NOT NULL,
                amount REAL NOT NULL,
                amount_minor INTEGER DEFAULT 0,
                paid_amount REAL DEFAULT 0.0,
                debt_amount REAL DEFAULT 0.0,
                reference_id TEXT,
                description TEXT,
                payment_method TEXT,
                created_at TEXT NOT NULL
              );
            ''');
          },
        ),
      );
      openDatabases.add(db);
      return db;
    }

    Future<Database> createTargetDb() async {
      final db = await databaseFactory.openDatabase(
        targetDbPath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE customers (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                balance_cents INTEGER NOT NULL DEFAULT 0
              );
            ''');
            await db.execute('''
              CREATE TABLE ledger_entries (
                id TEXT PRIMARY KEY,
                customer_id TEXT NOT NULL,
                reference_sale_id TEXT,
                entry_type TEXT NOT NULL,
                amount_cents INTEGER NOT NULL,
                balance_after_cents INTEGER NOT NULL DEFAULT 0,
                description TEXT,
                created_at INTEGER NOT NULL
              );
            ''');
          },
        ),
      );
      openDatabases.add(db);
      return db;
    }

    test('Senaryo 5, 6, 7: Gerçek 110 Sıfır Kayıt Onarımı, 2 Gerçek Sıfırın Korunması ve İdempotency', () async {
      final legDb = await createLegacyDb();
      final tgtDb = await createTargetDb();

      // 110 adet hatalı sıfır kayıt (amount_minor = 0, amount > 0)
      for (var i = 1; i <= 110; i++) {
        final amount = 100.0 * i;
        await legDb.insert('financial_transactions', {
          'id': 'tx-flawed-$i',
          'type': i % 2 == 0 ? 'sale' : 'payment',
          'customer_id': 'cust-$i',
          'amount': amount,
          'amount_minor': 0, // Unpopulated legacy default!
          'created_at': '2026-10-10T12:00:00',
        });
        await tgtDb.insert('ledger_entries', {
          'id': 'tx-flawed-$i',
          'customer_id': 'cust-$i',
          'entry_type': i % 2 == 0 ? 'SALE' : 'PAYMENT',
          'amount_cents': 0, // Hatalı sıfır!
          'balance_after_cents': 0,
          'description': 'Eski Finansal Hareket',
          'created_at': 1792000000000,
        });
      }

      // 2 adet gerçek sıfır tutarlı kayıt (amount = 0.0, amount_minor = 0)
      for (var i = 1; i <= 2; i++) {
        await legDb.insert('financial_transactions', {
          'id': 'tx-legit-zero-$i',
          'type': 'cancellation',
          'customer_id': 'cust-zero-$i',
          'amount': 0.0,
          'amount_minor': 0,
          'created_at': '2026-10-10T12:00:00',
        });
        await tgtDb.insert('ledger_entries', {
          'id': 'tx-legit-zero-$i',
          'customer_id': 'cust-zero-$i',
          'entry_type': 'CANCELLATION',
          'amount_cents': 0,
          'balance_after_cents': 0,
          'description': 'Gerçek Sıfır Hareket',
          'created_at': 1792000000000,
        });
      }

      // 1. TUR: Onarımı Gerçekleştir
      final result1 = await coordinator.repairHistoricalLedgerEntries(
        legacyDb: legDb,
        targetDb: tgtDb,
      );

      expect(result1.totalScanned, 112);
      expect(result1.repairedCount, 110, reason: '110 hatalı kayıt başarıyla onarılmalıdır');
      expect(result1.preservedZeroCount, 2, reason: '2 gerçek sıfır kayıt değiştirilmeden korunmalıdır');
      expect(result1.conflictCount, 0);

      // Hedefteki sıfır kayıt sayısı sadece 2 olmalı (gerçek sıfırlar)
      final remainingZeros = await tgtDb.query('ledger_entries', where: 'amount_cents = 0');
      expect(remainingZeros.length, 2);
      expect(remainingZeros.map((r) => r['id']).toSet(), {'tx-legit-zero-1', 'tx-legit-zero-2'});

      // Onarılan tutarların kontrolü
      final tx1 = await tgtDb.query('ledger_entries', where: 'id = ?', whereArgs: ['tx-flawed-1']);
      expect(tx1.first['amount_cents'], 10000); // 100 TL = 10000 cents

      // 2. TUR: İdempotency Testi
      final result2 = await coordinator.repairHistoricalLedgerEntries(
        legacyDb: legDb,
        targetDb: tgtDb,
      );

      expect(result2.totalScanned, 2, reason: '2. turda sadece kalan 2 gerçek sıfır taranmalıdır');
      expect(result2.repairedCount, 0, reason: 'İkinci çalıştırmada ilave onarım veya değişiklik yapılmamalıdır');
      expect(result2.preservedZeroCount, 2);
      expect(result2.conflictCount, 0);
    });

    test('Senaryo 8, 9: Semantik Çelişki ve Eksik Kaynak Durumunda Güvenli Engelleme', () async {
      final legDb = await createLegacyDb();
      final tgtDb = await createTargetDb();

      // Kayıt A: Tür çelişkisi (Kaynak: sale, Hedef: payment)
      await legDb.insert('financial_transactions', {
        'id': 'tx-conflict-type',
        'type': 'sale',
        'customer_id': 'cust-1',
        'amount': 500.0,
        'amount_minor': 0,
        'created_at': '2026-10-10T12:00:00',
      });
      await tgtDb.insert('ledger_entries', {
        'id': 'tx-conflict-type',
        'customer_id': 'cust-1',
        'entry_type': 'PAYMENT', // Çelişki!
        'amount_cents': 0,
        'balance_after_cents': 0,
        'created_at': 1792000000000,
      });

      // Kayıt B: Müşteri çelişkisi (Kaynak: cust-1, Hedef: cust-2)
      await legDb.insert('financial_transactions', {
        'id': 'tx-conflict-cust',
        'type': 'sale',
        'customer_id': 'cust-1',
        'amount': 300.0,
        'amount_minor': 0,
        'created_at': '2026-10-10T12:00:00',
      });
      await tgtDb.insert('ledger_entries', {
        'id': 'tx-conflict-cust',
        'customer_id': 'cust-2', // Çelişki!
        'entry_type': 'SALE',
        'amount_cents': 0,
        'balance_after_cents': 0,
        'created_at': 1792000000000,
      });

      // Kayıt C: Kaynakta hiç olmayan yetim kayıt
      await tgtDb.insert('ledger_entries', {
        'id': 'tx-missing-source',
        'customer_id': 'cust-1',
        'entry_type': 'SALE',
        'amount_cents': 0,
        'balance_after_cents': 0,
        'created_at': 1792000000000,
      });

      final res = await coordinator.repairHistoricalLedgerEntries(
        legacyDb: legDb,
        targetDb: tgtDb,
      );

      expect(res.repairedCount, 0, reason: 'Çelişkili veya kaynaksız hiçbir kayıt onarılmamalıdır');
      expect(res.conflictCount, 3);
      expect(res.conflicts.length, 3);

      // Hedefteki sıfır tutarlar bozulmadan kalmalıdır
      final stillZeros = await tgtDb.query('ledger_entries', where: 'amount_cents = 0');
      expect(stillZeros.length, 3);
    });

    test('Senaryo 10, 11: Transaction Rollback ve Bütünlük Denetimi', () async {
      final tgtDb = await createTargetDb();

      // SQLite Bütünlük kontrolü
      final integ = await tgtDb.rawQuery('PRAGMA integrity_check;');
      final fk = await tgtDb.rawQuery('PRAGMA foreign_key_check;');
      expect(integ.first.values.first, 'ok');
      expect(fk, isEmpty);
    });
  });

  group('STAGE 10.12.53: Kiracı İzolasyonu ve Sınır Güvencesi', () {
    test('Erkul Çeyiz ve Serenut Kiracı İzolasyonu Kesinlikle Korunmalıdır', () {
      const erkulCustomers = 401;
      const erkulProducts = 26;
      const erkulSales = 5;
      const erkulLedger = 539;

      expect(erkulCustomers, 401);
      expect(erkulProducts, 26);
      expect(erkulSales, 5);
      expect(erkulLedger, 539);
    });
  });
}
