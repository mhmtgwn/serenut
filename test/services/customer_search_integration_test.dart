import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/config/utils.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/domain/services/customer_search_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Customer Search Integration Tests (1500+ Records)', () {
    late DatabaseManager databaseManager;
    late SqliteCustomerRepository customerRepository;
    late CustomerSearchService searchService;

    setUp(() async {
      // Clear database file for tests to avoid state pollution
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'customer_search_test.db');
      await deleteDatabase(path);

      // Set path override
      DatabaseManager.overrideDatabasePath = path;

      // Initialize database manager
      databaseManager = DatabaseManager();
      final db = await databaseManager.getDatabase();
      
      final dbGateway = DbGatewayImpl(databaseManager);
      customerRepository = SqliteCustomerRepository(dbGateway);
      searchService = CustomerSearchService(customerRepository);

      // Seed 1500 customers alphabetically
      final batch = db.batch();
      for (int i = 1; i <= 1500; i++) {
        // Generate uniform names starting with A..L so M-starting names are not in first 50
        final prefixChar = String.fromCharCode(65 + (i % 12)); // A to L
        final name = '$prefixChar-Customer-$i';
        final email = 'customer$i@example.com';
        
        batch.insert('customers', {
          'id': 'cust-$i',
          'name': name,
          'normalized_name': name.normalizeTurkish,
          'email': email,
          'normalized_email': email.toLowerCase(),
          'phone': '555000${i.toString().padLeft(4, "0")}',
          'balance': 0.0,
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      // Add target test customers
      final testCustomers = [
        {
          'id': 'cust-target-1',
          'name': 'Mehmet Yılmaz',
          'email': 'mehmet@example.com',
          'phone': '5551234567',
        },
        {
          'id': 'cust-target-2',
          'name': 'İsmail Hakkı',
          'email': 'Ismail@example.com',
          'phone': '5557654321',
        },
        {
          'id': 'cust-target-3',
          'name': 'Müşerref Aksoy',
          'email': 'muserref@example.com',
          'phone': '5559998888',
        }
      ];

      for (final tc in testCustomers) {
        batch.insert('customers', {
          'id': tc['id']!,
          'name': tc['name']!,
          'normalized_name': tc['name']!.normalizeTurkish,
          'email': tc['email']!,
          'normalized_email': tc['email']!.toLowerCase(),
          'phone': tc['phone']!,
          'balance': 0.0,
          'is_active': 1,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        });
      }

      await batch.commit(noResult: true);
    });

    tearDown(() async {
      await databaseManager.close();
      DatabaseManager.overrideDatabasePath = null;
    });

    test('Verification: empty search returns first page alphabetically', () async {
      final results = await searchService.searchCustomers(
        query: '',
        page: 0,
        limit: 50,
      );

      expect(results.items.length, equals(50));
      // First items should start with 'A'
      expect(results.items.first.name.startsWith('A'), isTrue);
      // Mehmet should NOT be in the first 50 alphabetically
      expect(results.items.any((c) => c.name.startsWith('Mehmet')), isFalse);
    });

    test('Verification: search for "m" or "M" returns "Mehmet" and "Müşerref"', () async {
      // Lowercase "m" search
      final resultsLower = await searchService.searchCustomers(
        query: 'm',
        page: 0,
        limit: 50,
      );

      final namesLower = resultsLower.items.map((c) => c.name).toList();
      expect(namesLower.any((n) => n.contains('Mehmet')), isTrue);
      expect(namesLower.any((n) => n.contains('Müşerref')), isTrue);

      // Uppercase "M" search
      final resultsUpper = await searchService.searchCustomers(
        query: 'M',
        page: 0,
        limit: 50,
      );

      final namesUpper = resultsUpper.items.map((c) => c.name).toList();
      expect(namesUpper.any((n) => n.contains('Mehmet')), isTrue);
      expect(namesUpper.any((n) => n.contains('Müşerref')), isTrue);
    });

    test('Verification: search for "müş" or "MÜŞ" matches Turkish characters', () async {
      final resultsLower = await searchService.searchCustomers(
        query: 'müş',
        page: 0,
        limit: 50,
      );

      final namesLower = resultsLower.items.map((c) => c.name).toList();
      expect(namesLower.any((n) => n.contains('Müşerref')), isTrue);

      final resultsUpper = await searchService.searchCustomers(
        query: 'MÜŞ',
        page: 0,
        limit: 50,
      );

      final namesUpper = resultsUpper.items.map((c) => c.name).toList();
      expect(namesUpper.any((n) => n.contains('Müşerref')), isTrue);
    });

    test('Verification: search for Turkish letters "İsmail", "ismail", "ısmail" works correctly', () async {
      final terms = ['İsmail', 'ismail', 'ısmail'];
      for (final term in terms) {
        final results = await searchService.searchCustomers(
          query: term,
          page: 0,
          limit: 50,
        );
        final names = results.items.map((c) => c.name).toList();
        expect(names.any((n) => n.contains('İsmail')), isTrue);
      }
    });

    test('Verification: search pagination offset returns correct subsequent slices', () async {
      // Find all M-matching entries first to verify total count
      final resultsAll = await searchService.searchCustomers(
        query: 'm',
        page: 0,
        limit: 500,
      );
      final totalMatches = resultsAll.items.length;

      // Now query in page slices of 10 items
      final page0 = await searchService.searchCustomers(
        query: 'm',
        page: 0,
        limit: 10,
      );
      expect(page0.items.length, equals(min(10, totalMatches)));

      final page1 = await searchService.searchCustomers(
        query: 'm',
        page: 1,
        limit: 10,
      );
      expect(page1.items.length, equals(min(10, totalMatches - 10)));

      // Make sure first page entries are distinct from second page entries
      final page0Ids = page0.items.map((c) => c.id).toSet();
      final page1Ids = page1.items.map((c) => c.id).toSet();
      expect(page0Ids.intersection(page1Ids), isEmpty);
    });

    test('Verification: phone search matches different inputs (0532, 532, +90, last 4 digits)', () async {
      // 1. With spaces and formatting "+90 555 123 45 67"
      final results1 = await searchService.searchCustomers(
        query: '+90 555 123 45 67',
        page: 0,
        limit: 50,
      );
      expect(results1.items.length, equals(1));
      expect(results1.items.first.id, equals('cust-target-1')); // Mehmet

      // 2. Leading zero "0555 123 45 67"
      final results2 = await searchService.searchCustomers(
        query: '0555 123 45 67',
        page: 0,
        limit: 50,
      );
      expect(results2.items.length, equals(1));
      expect(results2.items.first.id, equals('cust-target-1'));

      // 3. Raw clean number "5551234567"
      final results3 = await searchService.searchCustomers(
        query: '5551234567',
        page: 0,
        limit: 50,
      );
      expect(results3.items.length, equals(1));
      expect(results3.items.first.id, equals('cust-target-1'));

      // 4. Last 4 digits "4567"
      final results4 = await searchService.searchCustomers(
        query: '4567',
        page: 0,
        limit: 50,
      );
      expect(results4.items.length, equals(1));
      expect(results4.items.first.id, equals('cust-target-1'));
    });
  });
}
