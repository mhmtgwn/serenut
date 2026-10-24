// test/core_next/stage10_12_74_nutopia_target_smoke_test.dart
// STAGE 10.12.74: Smoke Test for nutopia_core_next_live.db
// ignore_for_file: avoid_relative_lib_imports

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  const targetPath = 'backups/nutopia_live_20261021_2055/nutopia_core_next_live.db';
  final targetFile = File(targetPath).absolute;

  group('STAGE 10.12.74: nutopia_core_next_live.db Açılış ve Smoke Testi', () {
    test('1. Güvenlik Sınırları: Routing ve Satış Motoru Kesinlikle Kapalı', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
      expect(DatabaseManager.databaseRoutingHook, isNull);
    });

    test('2. Hedef Dosyanın CoreAppDatabase Olarak Açılması ve Temel Smoke Sorguları', () async {
      expect(targetFile.existsSync(), isTrue);

      final coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetFile.path);

      try {
        // Integrity & FK
        final integrity = await coreDb.db.rawQuery('PRAGMA integrity_check;');
        expect(integrity.first.values.first, equals('ok'));

        final fkCheck = await coreDb.db.rawQuery('PRAGMA foreign_key_check;');
        expect(fkCheck, isEmpty);

        // Basic read queries
        final activeProducts = Sqflite.firstIntValue(
          await coreDb.db.rawQuery('SELECT COUNT(*) FROM products WHERE is_active = 1'),
        );
        expect(activeProducts, greaterThan(0));

        final sampleProducts = await coreDb.db.rawQuery(
          'SELECT id, barcode, name, price_cents, stock_quantity FROM products LIMIT 3',
        );
        expect(sampleProducts.length, equals(3));
        for (final p in sampleProducts) {
          print('PRODUCT SMOKE: ${p['name']} | ${p['barcode']} | ${p['price_cents']} cents');
        }

        final activeCustomers = Sqflite.firstIntValue(
          await coreDb.db.rawQuery('SELECT COUNT(*) FROM customers WHERE is_active = 1'),
        );
        expect(activeCustomers, greaterThan(0));

        final sampleCustomers = await coreDb.db.rawQuery(
          'SELECT id, name, balance_cents FROM customers LIMIT 3',
        );
        expect(sampleCustomers.length, equals(3));
        for (final c in sampleCustomers) {
          print('CUSTOMER SMOKE: ${c['name']} | Balance: ${c['balance_cents']} cents');
        }

        final salesCount = Sqflite.firstIntValue(
          await coreDb.db.rawQuery('SELECT COUNT(*) FROM sales'),
        );
        expect(salesCount, equals(52));

        final ledgerCount = Sqflite.firstIntValue(
          await coreDb.db.rawQuery('SELECT COUNT(*) FROM ledger_entries'),
        );
        expect(ledgerCount, equals(1505));

        final cashCount = Sqflite.firstIntValue(
          await coreDb.db.rawQuery('SELECT COUNT(*) FROM cash_transactions'),
        );
        expect(cashCount, equals(21));
      } finally {
        await coreDb.close();
      }
    });
  });
}
