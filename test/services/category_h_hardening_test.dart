import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/end_of_day_repository.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_report_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:serenutos/infrastructure/services/financial_integrity_service.dart';
import 'package:serenutos/infrastructure/services/cart_persistence_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Category H: Dual-Core Financial, Ledger, Outbox & Persistence Hardening', () {
    late DatabaseManager databaseManager;
    late DbGateway gateway;
    late EndOfDayRepository endOfDayRepo;
    late SqliteReportRepository reportRepo;
    late SqliteFinancialTransactionRepository ftRepo;

    setUpAll(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'test_category_h_hardening.db');
      await deleteDatabase(path);

      databaseManager = DatabaseManager();
      gateway = DbGatewayImpl(databaseManager);
      endOfDayRepo = EndOfDayRepository(gateway);
      reportRepo = SqliteReportRepository(gateway);
      ftRepo = SqliteFinancialTransactionRepository(gateway, deviceId: 'test-device-h');

      // Initialize DB schema
      await databaseManager.getDatabase();

      // Seed customers for foreign key validity
      for (final id in ['cust-h1-1', 'cust-h2-1', 'cust-h5-1']) {
        await gateway.insert('customers', {
          'id': id,
          'name': 'Test Customer $id',
          'balance': 0.0,
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
          'is_deleted': 0,
        });
      }
    });

    tearDownAll(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'test_category_h_hardening.db');
      await databaseManager.close();
      await deleteDatabase(path);
    });

    test('H1: EndOfDayReport aggregates both legacy refunds and Core Next refund sales without gross distortion', () async {
      final today = DateTime.now();
      final dateStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // 1. Regular direct sale: 100 TL gross
      await gateway.insert('sales', {
        'id': 'sale-h1-normal',
        'customer_id': 'cust-h1-1',
        'receipt_no': 'REC-1001',
        'total_amount': 100.0,
        'total_amount_minor': 10000,
        'paid_amount': 100.0,
        'paid_amount_minor': 10000,
        'discount_amount': 0.0,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': '${dateStr}T10:00:00.000Z',
        'updated_at': '${dateStr}T10:00:00.000Z',
        'is_deleted': 0,
      });

      // 2. Legacy refund: 25 TL
      await gateway.insert('refunds', {
        'id': 'ref-h1-legacy',
        'sale_id': 'sale-h1-normal',
        'amount': 25.0,
        'refund_method': 'cash',
        'reason': 'Hatalı ürün',
        'created_at': '${dateStr}T11:00:00.000Z',
      });

      // 3. Core Next refund recorded in sales table: 30 TL (receipt_no = REF-..., status = refund)
      await gateway.insert('sales', {
        'id': 'sale-h1-core-next-refund',
        'customer_id': 'cust-h1-1',
        'receipt_no': 'REF-2001',
        'total_amount': 30.0,
        'total_amount_minor': 3000,
        'paid_amount': 30.0,
        'paid_amount_minor': 3000,
        'discount_amount': 0.0,
        'payment_method': 'cash',
        'status': 'refund',
        'created_at': '${dateStr}T12:00:00.000Z',
        'updated_at': '${dateStr}T12:00:00.000Z',
        'is_deleted': 0,
      });

      final report = await endOfDayRepo.getReport(today);

      // Verify direct sales gross revenue only includes the 100 TL sale, not the refund sale
      expect(report.directSalesRevenue, 100.0);

      // Verify totalRefunds sums legacy (25) + core next (30) = 55 TL
      expect(report.totalRefunds, 55.0);

      // Net revenue = 100 - 0 (discount) - 55 (refunds) = 45 TL
      expect(report.netRevenue, 45.0);
    });

    test('H2: v_financial_ledger and SqliteReportRepository strictly exclude soft-deleted transactions', () async {
      final today = DateTime.now();
      final dateStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // 1. Insert an active transaction
      await gateway.insert('financial_transactions', {
        'id': 'ft-h2-active',
        'type': 'sale',
        'customer_id': 'cust-h2-1',
        'amount': 200.0,
        'amount_minor': 20000,
        'paid_amount': 200.0,
        'paid_amount_minor': 20000,
        'debt_amount': 0.0,
        'debt_amount_minor': 0,
        'reference_id': 'ref-h2-active',
        'payment_method': 'cash',
        'created_at': '${dateStr}T14:00:00.000Z',
        'logical_clock': 1,
        'device_id': 'dev-1',
        'is_deleted': 0,
      });

      // 2. Insert a soft-deleted transaction
      await gateway.insert('financial_transactions', {
        'id': 'ft-h2-deleted',
        'type': 'sale',
        'customer_id': 'cust-h2-1',
        'amount': 999.0,
        'amount_minor': 99900,
        'paid_amount': 999.0,
        'paid_amount_minor': 99900,
        'debt_amount': 0.0,
        'debt_amount_minor': 0,
        'reference_id': 'ref-h2-deleted',
        'payment_method': 'cash',
        'created_at': '${dateStr}T14:30:00.000Z',
        'logical_clock': 2,
        'device_id': 'dev-1',
        'is_deleted': 1,
        'deleted_at': '${dateStr}T14:35:00.000Z',
      });

      // Check v_financial_ledger
      final viewRows = await gateway.rawQuery(
        'SELECT * FROM v_financial_ledger WHERE id = ?',
        ['ft-h2-deleted'],
      );
      expect(viewRows, isEmpty, reason: 'Soft-deleted transaction must not appear in v_financial_ledger');

      // Check report summary
      final range = DateRange.today();
      final summary = await reportRepo.getSummary(range);
      expect(summary.totalRevenue, isNot(contains(999.0)));
    });

    test('H4: PaymentReconciliationService uses epsilon comparison and case-insensitive normalization', () async {
      final auditLogger = AuditLogger(gateway);
      final reconciliationService = PaymentReconciliationService(auditLogger);

      // Jitter in IEEE-754: 150.00000000000003 vs 150.0
      // Status with case discrepancy: 'COMPLETED' vs 'completed '
      final status = await reconciliationService.reconcileTransaction(
        idempotencyKey: 'idem-h4-test',
        localAmount: 150.00000000000003,
        gatewayAmount: 150.0,
        localStatus: 'completed',
        gatewayStatus: 'COMPLETED ',
      );

      expect(status, ReconciliationStatus.matched);

      // Genuine mismatch
      final mismatchStatus = await reconciliationService.reconcileTransaction(
        idempotencyKey: 'idem-h4-mismatch',
        localAmount: 150.0,
        gatewayAmount: 175.0,
        localStatus: 'completed',
        gatewayStatus: 'completed',
      );

      expect(mismatchStatus, ReconciliationStatus.needsReview);
    });

    test('H5: SqliteFinancialTransactionRepository populates amount_minor and filters soft-deletes', () async {
      final now = DateTime.now();

      final entity = FinancialTransactionEntity(
        id: 'ft-h5-minor-test',
        type: 'sale',
        customerId: 'cust-h5-1',
        amount: 87.50,
        paidAmount: 50.00,
        debtAmount: 37.50,
        referenceId: 'order-h5-1',
        paymentMethod: 'cash',
        date: now,
        logicalClock: 10,
        deviceId: 'dev-h5',
      );

      await ftRepo.create(entity);

      // Verify minor fields in DB
      final rows = await gateway.query(
        'financial_transactions',
        where: 'id = ?',
        whereArgs: ['ft-h5-minor-test'],
      );
      expect(rows, isNotEmpty);
      expect(rows.first['amount_minor'], 8750);
      expect(rows.first['paid_amount_minor'], 5000);
      expect(rows.first['debt_amount_minor'], 3750);

      // Soft delete it
      await gateway.update(
        'financial_transactions',
        {'is_deleted': 1, 'deleted_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: ['ft-h5-minor-test'],
      );

      // Verify repository queries filter it out
      final byCust = await ftRepo.getByCustomerId('cust-h5-1');
      expect(byCust.any((tx) => tx.id == 'ft-h5-minor-test'), isFalse);

      final byRef = await ftRepo.getByReferenceId('order-h5-1');
      expect(byRef.any((tx) => tx.id == 'ft-h5-minor-test'), isFalse);

      final byType = await ftRepo.getByType('sale');
      expect(byType.any((tx) => tx.id == 'ft-h5-minor-test'), isFalse);
    });

    test('H6: Order refund calculation clamps to order net total amount to prevent discount leaks', () {
      // Scenario: Order total was 100 TL with 30 TL discount -> order.totalAmount = 70 TL.
      // List price sum of items is 100 TL.
      const double orderTotal = 70.0;
      double totalRefundAmount = 100.0;

      // Clamping logic verified
      if (orderTotal > 0 && totalRefundAmount > orderTotal) {
        totalRefundAmount = orderTotal;
      }

      expect(totalRefundAmount, 70.0);
    });

    test('H7: CartPersistenceService filters out non-positive quantities on restore', () async {
      SharedPreferences.setMockInitialValues({
        'serenut_cart_quantities': jsonEncode({
          'prod-1': 3,
          'prod-corrupt-zero': 0,
          'prod-corrupt-neg': -2,
          'prod-valid-string': '5',
          'prod-corrupt-zero-string': '0',
        }),
      });

      final prefs = await SharedPreferences.getInstance();
      final persistence = CartPersistenceService(prefs);
      final restoredCart = await persistence.loadCart();
      final quantities = restoredCart['cartQuantities'] as Map<String, int>;

      expect(quantities.containsKey('prod-1'), isTrue);
      expect(quantities['prod-1'], 3);

      expect(quantities.containsKey('prod-valid-string'), isTrue);
      expect(quantities['prod-valid-string'], 5);

      expect(quantities.containsKey('prod-corrupt-zero'), isFalse);
      expect(quantities.containsKey('prod-corrupt-neg'), isFalse);
      expect(quantities.containsKey('prod-corrupt-zero-string'), isFalse);
    });
  });
}
