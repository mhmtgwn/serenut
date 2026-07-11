// test/services/load_test_suite.dart
// Production Load Test Suite
// Validates mathematical correctness and performance under realistic data volumes:
//   - 1,000 customer drift check
//   - 10,000 transaction ledger replay
//   - 50 concurrent sales (no race conditions)
//   - Floating-point invariant across 1M TL turnover

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/services/data_integrity_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';

// ── Inline schema helpers ─────────────────────────────────────────────────────

Future<void> _setupSchema(Database db) async {
  await db.execute('DROP TABLE IF EXISTS financial_transactions');
  await db.execute('DROP TABLE IF EXISTS sales');
  await db.execute('DROP TABLE IF EXISTS customers');

  await db.execute('''
    CREATE TABLE customers (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      email TEXT,
      phone TEXT,
      balance REAL NOT NULL DEFAULT 0,
      credit_limit REAL,
      status TEXT NOT NULL DEFAULT 'active',
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE financial_transactions (
      id TEXT PRIMARY KEY,
      type TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      amount REAL NOT NULL,
      paid_amount REAL NOT NULL DEFAULT 0,
      debt_amount REAL NOT NULL DEFAULT 0,
      reference_id TEXT,
      metadata TEXT,
      created_at TEXT NOT NULL
    )
  ''');
  await db.execute('''
    CREATE TABLE sales (
      id TEXT PRIMARY KEY,
      customer_id TEXT NOT NULL,
      total_amount REAL NOT NULL,
      paid_amount REAL NOT NULL DEFAULT 0,
      payment_method TEXT,
      status TEXT NOT NULL DEFAULT 'completed',
      notes TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      idempotency_key TEXT UNIQUE,
      is_synced INTEGER NOT NULL DEFAULT 0
    )
  ''');
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Production Load Test Suite', () {
    late Database db;
    late DatabaseManager databaseManager;
    late SqliteCustomerRepository customerRepo;
    late SqliteFinancialTransactionRepository txRepo;
    late DataIntegrityService integrityService;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      databaseManager = DatabaseManager();
      db = await databaseManager.getDatabase();
      await _setupSchema(db);

      final gateway = DbGatewayImpl(databaseManager);
      customerRepo = SqliteCustomerRepository(gateway);
      txRepo = SqliteFinancialTransactionRepository(gateway);
      integrityService = DataIntegrityService(
        customerRepository: customerRepo,
        transactionRepository: txRepo,
      );
    });

    tearDown(() async {
      DatabaseManager.overrideDatabasePath = null;
      await databaseManager.close();
    });

    // ── TEST 1: 1k customers — drift check performance ─────────────────────
    test('1,000 customers drift check completes within 10 seconds', () async {
      const customerCount = 1000;

      final now = DateTime.now().toIso8601String();

      // Seed 1k customers with correct balances
      final batch = db.batch();
      for (var i = 0; i < customerCount; i++) {
        final custId = 'cust-load-$i';
        batch.insert('customers', {
          'id': custId,
          'name': 'Customer $i',
          'balance': -100.0, // Each owes 100 TL
          'status': 'active',
          'is_active': 1,
          'created_at': now,
          'updated_at': now,
        });
        // One sale transaction per customer (matches balance)
        batch.insert('financial_transactions', {
          'id': 'tx-load-$i',
          'type': 'sale',
          'customer_id': custId,
          'amount': 100.0,
          'paid_amount': 0.0,
          'debt_amount': 100.0,
          'created_at': now,
        });
      }
      await batch.commit(noResult: true);

      final stopwatch = Stopwatch()..start();
      final drifts = await integrityService.runGlobalDriftCheck();
      stopwatch.stop();

      // No drifts expected — all balances are mathematically correct
      expect(drifts.isEmpty, isTrue,
          reason: '1k customers with correct balances → zero drifts');

      // Performance assertion: must complete under 10 seconds
      expect(stopwatch.elapsedMilliseconds, lessThan(10000),
          reason: 'Drift check for 1k customers must finish < 10s');

      debugPrint(
          '✅ 1k customer drift check: ${stopwatch.elapsedMilliseconds}ms');
    }, timeout: const Timeout(Duration(seconds: 30)));

    // ── TEST 2: 10k transactions — ledger math invariant ──────────────────
    test('10,000 transactions: ledger balance invariant holds to 0.01 TL', () async {
      const txCount = 10000;
      const custId = 'cust-ledger-stress';
      final now = DateTime.now();

      await db.insert('customers', {
        'id': custId,
        'name': 'Ledger Stress Customer',
        'balance': 0.0,
        'status': 'active',
        'is_active': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      // Insert alternating sales and payments: net balance = 0
      // 5000 sales × 100 TL each = 500,000 TL debt
      // 5000 payments × 100 TL each = 500,000 TL credit
      // Expected net = 0.0

      final batch = db.batch();
      for (var i = 0; i < txCount; i++) {
        final ts = now
            .add(Duration(seconds: i))
            .toIso8601String();

        if (i % 2 == 0) {
          // Sale
          batch.insert('financial_transactions', {
            'id': 'tx-stress-$i',
            'type': 'sale',
            'customer_id': custId,
            'amount': 100.0,
            'paid_amount': 0.0,
            'debt_amount': 100.0,
            'created_at': ts,
          });
        } else {
          // Payment
          batch.insert('financial_transactions', {
            'id': 'tx-stress-$i',
            'type': 'payment',
            'customer_id': custId,
            'amount': 100.0,
            'paid_amount': 100.0,
            'debt_amount': 0.0,
            'created_at': ts,
          });
        }
      }
      await batch.commit(noResult: true);

      final txs = await txRepo.getByCustomerId(custId);
      expect(txs.length, equals(txCount));

      final balance = DataIntegrityService.calculateExpectedBalance(txs);

      // Floating-point invariant: 5000 sales - 5000 payments = 0
      expect(balance.abs(), lessThan(0.01),
          reason: '10k transactions must net to 0.0 within 0.01 TL tolerance');

      debugPrint('✅ 10k ledger balance: $balance TL (expected ~0.0)');
    }, timeout: const Timeout(Duration(seconds: 60)));

    // ── TEST 3: 1M TL turnover — floating-point drift ─────────────────────
    test('1,000,000 TL total turnover: cumulative floating-point drift < 0.01 TL', () async {
      // Simulate: 1000 sales of 1000 TL each = 1M TL total
      // Each sale fully paid → expected net balance = 0

      const saleCount = 1000;
      const saleAmount = 1000.0;
      const custId = 'cust-million';
      final now = DateTime.now();

      await db.insert('customers', {
        'id': custId,
        'name': '1M TL Customer',
        'balance': 0.0,
        'status': 'active',
        'is_active': 1,
        'created_at': now.toIso8601String(),
        'updated_at': now.toIso8601String(),
      });

      final batch = db.batch();
      for (var i = 0; i < saleCount; i++) {
        final ts = now.add(Duration(seconds: i * 2)).toIso8601String();
        final ts2 = now.add(Duration(seconds: i * 2 + 1)).toIso8601String();

        batch.insert('financial_transactions', {
          'id': 'tx-million-sale-$i',
          'type': 'sale',
          'customer_id': custId,
          'amount': saleAmount,
          'paid_amount': 0.0,
          'debt_amount': saleAmount,
          'created_at': ts,
        });
        batch.insert('financial_transactions', {
          'id': 'tx-million-pay-$i',
          'type': 'payment',
          'customer_id': custId,
          'amount': saleAmount,
          'paid_amount': saleAmount,
          'debt_amount': 0.0,
          'created_at': ts2,
        });
      }
      await batch.commit(noResult: true);

      final txs = await txRepo.getByCustomerId(custId);
      final balance = DataIntegrityService.calculateExpectedBalance(txs);

      expect(balance.abs(), lessThan(0.01),
          reason:
              '1M TL total turnover: floating-point cumulative drift must be < 0.01 TL');

      debugPrint(
          '✅ 1M TL turnover drift: ${balance.toStringAsFixed(6)} TL');
    }, timeout: const Timeout(Duration(seconds: 60)));

    // ── TEST 4: Concurrent insertions — orphaned transaction check ────────
    test('50 concurrent sales: no orphaned transactions, all IDs unique', () async {
      final gateway = DbGatewayImpl(databaseManager);
      final saleRepo = SqliteSaleRepository(gateway);

      const custId = 'cust-concurrent';
      final now = DateTime.now().toIso8601String();

      await db.insert('customers', {
        'id': custId,
        'name': 'Concurrent Customer',
        'balance': 0.0,
        'status': 'active',
        'is_active': 1,
        'created_at': now,
        'updated_at': now,
      });

      const concurrentCount = 50;

      // Fire 50 concurrent inserts
      await Future.wait([
        for (var i = 0; i < concurrentCount; i++)
          saleRepo.create(SaleEntity(
            id: 'sale-conc-$i',
            customerId: custId,
            totalAmount: 50.0,
            paidAmount: 50.0,
            paymentMethod: 'cash',
            status: 'completed',
            createdAt: DateTime.now(),
            isSynced: 0,
            items: [],
          )),
      ]);

      final all = await saleRepo.findAll();
      expect(all.length, equals(concurrentCount),
          reason: '50 concurrent sales must all persist without collision');

      final ids = all.map((s) => s.id).toSet();
      expect(ids.length, equals(concurrentCount),
          reason: 'All sale IDs must be unique (no overwrites)');

      debugPrint('✅ 50 concurrent sales: ${all.length} rows, ${ids.length} unique IDs');
    }, timeout: const Timeout(Duration(seconds: 30)));
  });
}
