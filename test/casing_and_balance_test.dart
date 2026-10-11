// test/casing_and_balance_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_installment_repository.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Customer Casing & Balance Calculations Regression Tests', () {
    late DatabaseManager databaseManager;
    late DbGateway gateway;
    late SqliteCustomerRepository customerRepository;

    setUpAll(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'test_casing_balance.db');
      await deleteDatabase(path);

      databaseManager = DatabaseManager();
      gateway = DbGatewayImpl(databaseManager);
      customerRepository = SqliteCustomerRepository(gateway);

      final db = await databaseManager.getDatabase();

      // Seed customers
      await db.insert('customers', {
        'id': 'cust-1',
        'name': 'Mehmet Ali',
        'email': 'mehmet@example.com',
        'phone': '1234567890',
        'balance': 0.0,
        'credit_limit': 1000.0,
        'status': 'active',
        'is_active': 1,
        'is_deleted': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      await db.insert('customers', {
        'id': 'cust-2',
        'name': 'İbrahim Çelik',
        'email': 'ibrahim@example.com',
        'phone': '9876543210',
        'balance': 0.0,
        'credit_limit': 1000.0,
        'status': 'active',
        'is_active': 1,
        'is_deleted': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      await db.insert('customers', {
        'id': 'cust-3',
        'name': 'Ömer Şerif',
        'email': 'omer@example.com',
        'phone': '5554443322',
        'balance': 0.0,
        'credit_limit': 1000.0,
        'status': 'active',
        'is_active': 1,
        'is_deleted': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });
    });

    tearDownAll(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'test_casing_balance.db');
      await deleteDatabase(path);
    });

    test(
        'findFiltered and search should handle Turkish casing normalization correctly',
        () async {
      // 1. Search 'mehmet' (lowercase, ASCII) should match 'Mehmet Ali'
      final searchMehmet =
          await customerRepository.findFiltered(searchQuery: 'mehmet');
      expect(searchMehmet.length, 1);
      expect(searchMehmet.first.name, 'Mehmet Ali');

      // 2. Search 'ibrahim' (lowercase, ASCII) should match 'İbrahim Çelik' (non-ASCII capital 'İ')
      final searchIbrahim =
          await customerRepository.findFiltered(searchQuery: 'ibrahim');
      expect(searchIbrahim.length, 1);
      expect(searchIbrahim.first.name, 'İbrahim Çelik');

      // 3. Search 'omer' (lowercase, ASCII) should match 'Ömer Şerif' (non-ASCII capital 'Ö')
      final searchOmer =
          await customerRepository.findFiltered(searchQuery: 'omer');
      expect(searchOmer.length, 1);
      expect(searchOmer.first.name, 'Ömer Şerif');

      // 4. Search 'serif' (lowercase, ASCII) should match 'Ömer Şerif' (non-ASCII capital 'Ş')
      final searchSerif =
          await customerRepository.findFiltered(searchQuery: 'serif');
      expect(searchSerif.length, 1);
      expect(searchSerif.first.name, 'Ömer Şerif');
    });

    test(
        'getTotalDebt and getTotalPaid should correctly calculate values with cancellations and partial payments',
        () async {
      final db = await databaseManager.getDatabase();
      const customerId = 'cust-1';

      // Clean existing transactions for the customer
      await db.delete('financial_transactions',
          where: 'customer_id = ?', whereArgs: [customerId]);

      // 1. Incur a sale of 100 TL, 40 TL paid, 60 TL debt
      await db.insert('financial_transactions', {
        'id': 'tx-1',
        'type': 'sale',
        'customer_id': customerId,
        'amount': 100.0,
        'paid_amount': 40.0,
        'debt_amount': 60.0,
        'reference_id': 'sale-1',
        'created_at': DateTime.now().toIso8601String(),
      });

      var totalDebt = await customerRepository.getTotalDebt(customerId);
      var totalPaid = await customerRepository.getTotalPaid(customerId);

      expect(totalDebt, 100.0);
      expect(totalPaid, 40.0);

      // 2. Make a payment transaction of 30 TL (debt remaining 30 TL)
      await db.insert('financial_transactions', {
        'id': 'tx-2',
        'type': 'payment',
        'customer_id': customerId,
        'amount': 30.0,
        'paid_amount': 30.0,
        'debt_amount': 30.0,
        'reference_id': 'sale-1',
        'created_at': DateTime.now().toIso8601String(),
      });

      totalDebt = await customerRepository.getTotalDebt(customerId);
      totalPaid = await customerRepository.getTotalPaid(customerId);

      expect(totalDebt, 100.0); // Total purchase cost remains 100
      expect(totalPaid, 70.0); // Total paid accumulates to 70

      // 3. Cancel the sale (reverses 100 TL amount and 40 TL paid)
      await db.insert('financial_transactions', {
        'id': 'tx-3',
        'type': 'cancellation',
        'customer_id': customerId,
        'amount': 100.0,
        'paid_amount': 40.0,
        'debt_amount': 60.0,
        'reference_id': 'sale-1',
        'created_at': DateTime.now().toIso8601String(),
      });

      totalDebt = await customerRepository.getTotalDebt(customerId);
      totalPaid = await customerRepository.getTotalPaid(customerId);

      expect(totalDebt, 0.0); // 100 - 100 = 0
      expect(totalPaid,
          30.0); // (40 from sale - 40 from cancellation) + 30 from payment = 30
    });

    test('manual debt is reflected in ledger totals and customer balance',
        () async {
      final db = await databaseManager.getDatabase();
      const customerId = 'cust-2';

      await db.insert('financial_transactions', {
        'id': 'tx-manual-debt-1',
        'type': 'manual_debt',
        'customer_id': customerId,
        'amount': 275.50,
        'paid_amount': 0.0,
        'debt_amount': 275.50,
        'created_at': DateTime.now().toIso8601String(),
        'is_synced': 0,
      });

      final customer = await customerRepository.findById(customerId);
      expect(customer?.balance, -275.50);
      expect(await customerRepository.getTotalDebt(customerId), 275.50);
      expect(await customerRepository.getTotalPaid(customerId), 0.0);
    });

    test(
        'installment plan with down payment zeroes customer balance upon completion without artificial credit',
        () async {
      final db = await databaseManager.getDatabase();
      const customerId = 'cust-inst-test';

      await db.insert('customers', {
        'id': customerId,
        'name': 'Taksit Test Müşteri',
        'phone': '5559998877',
        'balance': 0.0,
        'is_active': 1,
        'is_deleted': 0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final installmentRepo = SqliteInstallmentRepository(gateway);
      final plan = await installmentRepo.createPlan(
        customerId: customerId,
        totalAmount: 1000.0,
        downPayment: 200.0,
        downPaymentMethod: 'cash',
        installmentCount: 2,
        firstDueDate: DateTime.now().add(const Duration(days: 30)),
        description: 'Test Taksit',
      );

      // Total: 1000, Down payment: 200 -> financed: 800.
      // Net customer balance should be exactly -800.0 (800 TL debt)
      var customer = await customerRepository.findById(customerId);
      expect(customer?.balance, -800.0);

      // Pay all installments
      final insts = await installmentRepo.getInstallmentsForPlan(plan.id);
      expect(insts.length, 2);
      for (final inst in insts) {
        await installmentRepo.payInstallment(
          installmentId: inst.id,
          amount: inst.amount,
          paymentMethod: 'cash',
        );
      }

      // Customer should now have 0.0 balance, NEVER positive/alacaklı!
      customer = await customerRepository.findById(customerId);
      expect(customer?.balance, 0.0);

      // Confirm filter classification
      final creditors = await customerRepository.findFiltered(
        searchQuery: 'Taksit Test Müşteri',
        balanceFilter: CustomerBalanceFilter.credit,
      );
      expect(creditors, isEmpty);

      final clearCustomers = await customerRepository.findFiltered(
        searchQuery: 'Taksit Test Müşteri',
        balanceFilter: CustomerBalanceFilter.clear,
      );
      expect(clearCustomers.length, 1);
      expect(clearCustomers.first.id, customerId);
    });

    test(
        'customer sorting options (oldestDebt, newestDebt, highestDebt, name) work correctly',
        () async {
      final db = await databaseManager.getDatabase();

      // Create test customers
      await customerRepository.create(CustomerEntity(
        id: 'sort-cust-1',
        name: 'Ali Yılmaz',
        phone: '05550000001',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));
      await customerRepository.create(CustomerEntity(
        id: 'sort-cust-2',
        name: 'Berk Öztürk',
        phone: '05550000002',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));
      await customerRepository.create(CustomerEntity(
        id: 'sort-cust-3',
        name: 'Canan Demir',
        phone: '05550000003',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));

      // Customer 1: Older debt (2024-01-10), -500 TL
      await db.insert('financial_transactions', {
        'id': 'ft-sort-1',
        'type': 'manual_debt',
        'customer_id': 'sort-cust-1',
        'amount': 500.0,
        'paid_amount': 0.0,
        'debt_amount': 500.0,
        'created_at': '2024-01-10T10:00:00.000',
        'is_deleted': 0,
      });

      // Customer 2: Newer debt (2024-06-15), -1000 TL
      await db.insert('financial_transactions', {
        'id': 'ft-sort-2',
        'type': 'manual_debt',
        'customer_id': 'sort-cust-2',
        'amount': 1000.0,
        'paid_amount': 0.0,
        'debt_amount': 1000.0,
        'created_at': '2024-06-15T10:00:00.000',
        'is_deleted': 0,
      });

      // Customer 3 has no debt

      // Test 1: oldestDebt sort
      final oldestList = await customerRepository.findFiltered(
        sortOption: CustomerSortOption.oldestDebt,
      );
      final sortMatchesOldest = oldestList
          .where((c) => c.id.startsWith('sort-cust-'))
          .map((c) => c.id)
          .toList();
      expect(sortMatchesOldest.first, 'sort-cust-1'); // Ali has oldest debt (Jan 2024)
      expect(sortMatchesOldest[1], 'sort-cust-2'); // Berk has June 2024 debt
      expect(sortMatchesOldest[2], 'sort-cust-3'); // Canan has no debt

      final cust1 = oldestList.firstWhere((c) => c.id == 'sort-cust-1');
      expect(cust1.oldestDebtDate, isNotNull);
      expect(cust1.oldestDebtDate?.year, 2024);
      expect(cust1.oldestDebtDate?.month, 1);

      // Test 2: newestDebt sort
      final newestList = await customerRepository.findFiltered(
        sortOption: CustomerSortOption.newestDebt,
      );
      final sortMatchesNewest = newestList
          .where((c) => c.id.startsWith('sort-cust-'))
          .map((c) => c.id)
          .toList();
      expect(sortMatchesNewest.first, 'sort-cust-2'); // Berk has newest debt (June 2024)
      expect(sortMatchesNewest[1], 'sort-cust-1'); // Ali has Jan 2024 debt

      // Test 3: highestDebt sort
      final highestList = await customerRepository.findFiltered(
        sortOption: CustomerSortOption.highestDebt,
      );
      final sortMatchesHighest = highestList
          .where((c) => c.id.startsWith('sort-cust-'))
          .map((c) => c.id)
          .toList();
      expect(sortMatchesHighest.first, 'sort-cust-2'); // Berk owes 1000 TL
      expect(sortMatchesHighest[1], 'sort-cust-1'); // Ali owes 500 TL
    });
  });
}
