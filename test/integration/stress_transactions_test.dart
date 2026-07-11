// test/integration/stress_transactions_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

void main() {
  // Initialize database factory for ffi
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Automated Stress and Concurrency Tests', () {
    late DatabaseManager databaseManager;
    late Database db;
    late SqliteSaleRepository saleRepository;
    late SqliteProductRepository productRepository;

    setUpAll(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'serenut_pos_stress.db');
      await deleteDatabase(path);

      // Create a specific database for stress testing
      databaseManager = DatabaseManager();
      db = await databaseManager.getDatabase();

      // Insert a mock customer to satisfy the sales foreign key constraint
      await db.insert('customers', {
        'id': 'cust-1',
        'name': 'Stress Customer',
        'email': 'stress@customer.com',
        'phone': '123456789',
        'balance': 0.0,
        'credit_limit': 1000.0,
        'status': 'active',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final gateway = DbGatewayImpl(databaseManager);
      saleRepository = SqliteSaleRepository(gateway);
      productRepository = SqliteProductRepository(gateway);
    });

    tearDownAll(() async {
      await databaseManager.close();
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'serenut_pos_stress.db');
      await deleteDatabase(path);
    });

    test('Simulate 1000 rapid parallel transactions and reads', () async {
      final futures = <Future<void>>[];
      
      // Perform 500 parallel writes and 500 parallel reads
      for (int i = 0; i < 500; i++) {
        // Asynchronous write
        futures.add(saleRepository.create(SaleEntity(
          id: 'stress-sale-$i',
          customerId: 'cust-1',
          totalAmount: 100.0 + i,
          paidAmount: 50.0,
          paymentMethod: 'cash',
          status: 'completed',
          createdAt: DateTime.now(),
          items: const [],
        )));

        // Asynchronous read
        futures.add(productRepository.findAll().then((_) {}));
      }

      final stopwatch = Stopwatch()..start();
      await Future.wait(futures);
      stopwatch.stop();

      print('Executed 1000 operations in ${stopwatch.elapsedMilliseconds} ms');
      
      // Verify count
      final count = await db.rawQuery('SELECT COUNT(*) as count FROM sales WHERE id LIKE ?', ['stress-sale-%']);
      expect(count.first['count'] as int, equals(500));
    });
  });
}
