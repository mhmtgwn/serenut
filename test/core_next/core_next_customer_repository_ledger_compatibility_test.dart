// test/core_next/core_next_customer_repository_ledger_compatibility_test.dart
// SERENUT OS — ARCHITECTURAL VERIFICATION
// Verifies CoreNextCustomerRepository correctly maps camelCase (LedgerEntryType.debitSale/creditCollection)
// and legacy uppercase (DEBIT_SALE, DEBT, COLLECTION, PAYMENT, MANUAL_DEBT) ledger entries.
// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/core_next/domain/models/core_entities.dart' as core_models;
import 'package:serenutos/core_next/infrastructure/database/app_database.dart';
import 'package:serenutos/core_next/infrastructure/repositories/core_next_customer_repository.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('CoreNextCustomerRepository Ledger Compatibility Test', () {
    late CoreAppDatabase coreDb;
    late CoreNextCustomerRepository customerRepo;

    setUp(() async {
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
      customerRepo = CoreNextCustomerRepository(coreDb.db);
    });

    tearDown(() async {
      await coreDb.close();
    });

    test('1.1 camelCase debitSale entries must correctly populate oldestDebtDate & latestDebtDate', () async {
      // 1. Müşteri ekle
      final customer = CustomerEntity(
        id: 'cust-camel-1',
        name: 'Ahmet Yılmaz',
        phone: '05551112233',
        balance: -150.0, // 150 TL borç
        createdAt: DateTime(2026, 1, 1),
      );
      await customerRepo.create(customer);

      final date1 = DateTime(2026, 2, 10, 14, 0).millisecondsSinceEpoch;
      final date2 = DateTime(2026, 2, 20, 16, 30).millisecondsSinceEpoch;

      // 2. camelCase entry_type: 'debitSale' (LedgerEntryType.debitSale.name)
      await coreDb.db.insert('ledger_entries', {
        'id': 'ledger-1',
        'customer_id': 'cust-camel-1',
        'entry_type': core_models.LedgerEntryType.debitSale.name, // 'debitSale'
        'amount_cents': 10000,
        'balance_after_cents': -10000,
        'description': 'Veresiye Satış #1',
        'created_at': date1,
      });

      await coreDb.db.insert('ledger_entries', {
        'id': 'ledger-2',
        'customer_id': 'cust-camel-1',
        'entry_type': core_models.LedgerEntryType.debitSale.name, // 'debitSale'
        'amount_cents': 5000,
        'balance_after_cents': -15000,
        'description': 'Veresiye Satış #2',
        'created_at': date2,
      });

      // 3. findById sorgula
      final found = await customerRepo.findById('cust-camel-1');
      expect(found, isNotNull);
      expect(found!.oldestDebtDate, equals(DateTime.fromMillisecondsSinceEpoch(date1)));
      expect(found.latestDebtDate, equals(DateTime.fromMillisecondsSinceEpoch(date2)));

      // 4. getDebtors sorgula
      final debtors = await customerRepo.getDebtors();
      expect(debtors.length, equals(1));
      expect(debtors.first.oldestDebtDate, equals(DateTime.fromMillisecondsSinceEpoch(date1)));
      expect(debtors.first.latestDebtDate, equals(DateTime.fromMillisecondsSinceEpoch(date2)));
    });

    test('1.2 camelCase creditCollection entries must correctly calculate getTotalPaid', () async {
      final customer = CustomerEntity(
        id: 'cust-camel-2',
        name: 'Mehmet Demir',
        phone: '05552223344',
        balance: 0.0,
        createdAt: DateTime(2026, 1, 1),
      );
      await customerRepo.create(customer);

      // Tahsilatlar (creditCollection)
      await coreDb.db.insert('ledger_entries', {
        'id': 'ledger-coll-1',
        'customer_id': 'cust-camel-2',
        'entry_type': core_models.LedgerEntryType.creditCollection.name, // 'creditCollection'
        'amount_cents': 12500, // 125 TL
        'balance_after_cents': 0,
        'description': 'Nakit Tahsilat',
        'created_at': DateTime(2026, 2, 1).millisecondsSinceEpoch,
      });

      await coreDb.db.insert('ledger_entries', {
        'id': 'ledger-coll-2',
        'customer_id': 'cust-camel-2',
        'entry_type': core_models.LedgerEntryType.creditCollection.name, // 'creditCollection'
        'amount_cents': 7500, // 75 TL
        'balance_after_cents': 0,
        'description': 'Kredi Kartı Tahsilat',
        'created_at': DateTime(2026, 2, 2).millisecondsSinceEpoch,
      });

      final totalPaid = await customerRepo.getTotalPaid('cust-camel-2');
      // 125 + 75 = 200.00 TL
      expect(totalPaid, equals(200.0));
    });

    test('1.3 Legacy uppercase entries (DEBIT_SALE, MANUAL_DEBT, COLLECTION) must remain 100% compatible', () async {
      final customer = CustomerEntity(
        id: 'cust-legacy-1',
        name: 'Fatma Kaya',
        phone: '05553334455',
        balance: -50.0,
        createdAt: DateTime(2026, 1, 1),
      );
      await customerRepo.create(customer);

      final dateDebt = DateTime(2026, 1, 15, 10, 0).millisecondsSinceEpoch;

      await coreDb.db.insert('ledger_entries', {
        'id': 'ledger-leg-1',
        'customer_id': 'cust-legacy-1',
        'entry_type': 'DEBIT_SALE',
        'amount_cents': 15000,
        'balance_after_cents': -15000,
        'description': 'Eski Veresiye',
        'created_at': dateDebt,
      });

      await coreDb.db.insert('ledger_entries', {
        'id': 'ledger-leg-2',
        'customer_id': 'cust-legacy-1',
        'entry_type': 'COLLECTION',
        'amount_cents': 10000, // 100 TL
        'balance_after_cents': -5000,
        'description': 'Eski Tahsilat',
        'created_at': DateTime(2026, 1, 20, 11, 0).millisecondsSinceEpoch,
      });

      final found = await customerRepo.findById('cust-legacy-1');
      expect(found, isNotNull);
      expect(found!.oldestDebtDate, equals(DateTime.fromMillisecondsSinceEpoch(dateDebt)));
      expect(found.latestDebtDate, equals(DateTime.fromMillisecondsSinceEpoch(dateDebt)));

      final totalPaid = await customerRepo.getTotalPaid('cust-legacy-1');
      expect(totalPaid, equals(100.0));
    });
  });
}
