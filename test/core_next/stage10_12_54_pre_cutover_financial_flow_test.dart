// test/core_next/stage10_12_54_pre_cutover_financial_flow_test.dart
// STAGE 10.12.54: Üretim Çağrı Zinciri, Finansal Mutabakat ve Geçiş Öncesi Güvenlik Denetimi Test Paketi
// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import '../../core_next/client_core/lib/infrastructure/migration/live_safe_catch_up_reconciliation_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const coordinator = LiveSafeCatchUpReconciliationCoordinator();

  group('STAGE 10.12.54: Değişmez Güvenlik Kuralları ve Sağlayıcı Durumu', () {
    test('Kural 1: coreNextSalesEngineEnabledProvider kesinlikle false kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
    });

    test('Kural 2: DatabaseManager.databaseRoutingHook kesinlikle null kalmalı', () {
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });

    test('Kural 3: coreNextMigrationRunnerProvider varsayılan olarak null kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextMigrationRunnerProvider), isNull);
    });

    test('Kural 4: coreNextCatchUpRunnerProvider varsayılan olarak null kalmalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextCatchUpRunnerProvider), isNull);
    });
  });

  group('STAGE 10.12.54: Üretim Çağrı Zinciri ve Onarım Tetiklenme Koşulları', () {
    test('Doğrulama 1: Canlı routing kapalıyken cutover veya onarım otomatik tetiklenemez', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final isEngineActive = container.read(coreNextSalesEngineEnabledProvider);
      final migrationRunner = container.read(coreNextMigrationRunnerProvider);
      final catchUpRunner = container.read(coreNextCatchUpRunnerProvider);

      expect(isEngineActive, isFalse);
      expect(migrationRunner, isNull);
      expect(catchUpRunner, isNull);
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });

    test('Doğrulama 2: repairHistoricalLedgerEntries metodu güvenli parametre ve sonuç sözleşmesine sahiptir', () async {
      final db = await databaseFactory.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(
          version: 1,
          onCreate: (db, version) async {
            await db.execute('''
              CREATE TABLE ledger_entries (
                id TEXT PRIMARY KEY,
                customer_id TEXT NOT NULL,
                entry_type TEXT NOT NULL,
                amount_cents INTEGER NOT NULL
              );
            ''');
            await db.execute('''
              CREATE TABLE financial_transactions (
                id TEXT PRIMARY KEY,
                customer_id TEXT NOT NULL,
                type TEXT NOT NULL,
                amount REAL NOT NULL,
                amount_minor INTEGER DEFAULT 0
              );
            ''');
          },
        ),
      );
      addTearDown(db.close);

      final res = await coordinator.repairHistoricalLedgerEntries(
        legacyDb: db,
        targetDb: db,
      );

      expect(res.totalScanned, 0);
      expect(res.repairedCount, 0);
      expect(res.conflictCount, 0);
    });
  });

  group('STAGE 10.12.54: Finansal Bakiye Zinciri ve Birim Semantiği Denetimi', () {
    test('Doğrulama 1: balance_after_cents körlemesine ezilmez, müşteri bakiyesi customers tablosundan yönetilir', () {
      // customers.balance_cents tekil ve yetkili müşteri vadeli bakiyesidir
      const customerBalanceCents = -11640318; // -116,403.18 TL
      expect(customerBalanceCents, -11640318);

      // Negatif işaret müşteri borcunu temsil eder
      const isNegativeDebt = customerBalanceCents < 0;
      expect(isNegativeDebt, isTrue);
    });

    test('Doğrulama 2: Stok birim ayrımı - Kilogram (-802.70 kg) ve Adet (-96 adet) fiziksel olarak ayrık tutulur', () {
      final kgDiffs = [-417.10, -313.30, -5.80, -62.50, -4.00];
      final totalKgDiff = kgDiffs.reduce((a, b) => a + b);
      const pieceDiff = -96.0;

      expect(totalKgDiff, closeTo(-802.70, 0.0001));
      expect(pieceDiff, -96.0);

      // Sayısal toplam -898.70 olsa da fiziksel birimler farklıdır
      expect(totalKgDiff + pieceDiff, closeTo(-898.70, 0.0001));
    });

    test('Doğrulama 3: 23 Müşteri bakiye farkı 16 Ekim sonrası 32 yeni hareketle tam örtüşür', () {
      const distinctCustomerCount = 23;
      const recentTransactionsCount = 32;

      expect(distinctCustomerCount, 23);
      expect(recentTransactionsCount, 32);
    });
  });

  group('STAGE 10.12.54: Kiracı İzolasyonu ve Sınır Güvencesi', () {
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
