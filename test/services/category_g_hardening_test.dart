import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/end_of_day_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_installment_repository.dart';
import 'package:serenutos/infrastructure/network/api_client.dart';
import 'package:serenutos/infrastructure/sync_v4/sync_v4_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Category G: Financial Integrity & Synchronization Hardening', () {
    late DatabaseManager databaseManager;
    late DbGateway gateway;
    late EndOfDayRepository endOfDayRepo;
    late SqliteInstallmentRepository installmentRepo;

    setUpAll(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'test_category_g_hardening.db');
      await deleteDatabase(path);

      databaseManager = DatabaseManager();
      gateway = DbGatewayImpl(databaseManager);
      endOfDayRepo = EndOfDayRepository(gateway);
      installmentRepo = SqliteInstallmentRepository(gateway);

      // Initialize DB schema
      await databaseManager.getDatabase();
    });

    tearDownAll(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'test_category_g_hardening.db');
      await databaseManager.close();
      await deleteDatabase(path);
    });

    test('G1: EndOfDayReport prevents double discount subtraction in net revenue', () async {
      final today = DateTime.now();
      final dateStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

      // 1. Create a customer
      await gateway.insert('customers', {
        'id': 'cust-g1-test',
        'name': 'Test Müşteri G1',
        'phone': '05551112233',
        'balance': 0.0,
        'created_at': '${dateStr}T10:00:00.000Z',
        'updated_at': '${dateStr}T10:00:00.000Z',
        'is_deleted': 0,
      });

      // 2. Insert a sale: Item 100 TL, Discount 20 TL -> total_amount is 80 TL net billed
      await gateway.insert('sales', {
        'id': 'sale-g1-1',
        'customer_id': 'cust-g1-test',
        'total_amount': 80.0,
        'total_amount_minor': 8000,
        'paid_amount': 80.0,
        'paid_amount_minor': 8000,
        'discount_amount': 20.0,
        'discount_amount_minor': 2000,
        'payment_method': 'cash',
        'status': 'completed',
        'created_at': '${dateStr}T11:00:00.000Z',
        'updated_at': '${dateStr}T11:00:00.000Z',
        'is_deleted': 0,
      });

      // 3. Insert a delivered order: 150 TL
      await gateway.insert('orders', {
        'id': 'order-g1-1',
        'order_number': 'ORD-G1-1',
        'customer_id': 'cust-g1-test',
        'total_amount': 150.0,
        'status': 'delivered',
        'actual_delivery_date': dateStr,
        'created_at': '${dateStr}T12:00:00.000Z',
        'updated_at': '${dateStr}T12:00:00.000Z',
        'is_deleted': 0,
      });

      // 4. Fetch Gün Sonu report
      final report = await endOfDayRepo.getReport(today);

      // Verify gross revenue calculation:
      // directSalesRevenue = totals.revenue (80) + totals.discount (20) = 100 TL
      expect(report.directSalesRevenue, 100.0);
      expect(report.totalDiscount, 20.0);
      expect(report.deliveredOrdersRevenue, 150.0);

      // totalRevenue = 100 (direct gross) + 150 (delivered order) = 250 TL
      expect(report.totalRevenue, 250.0);

      // netRevenue = totalRevenue (250) - totalDiscount (20) - totalRefunds (0) = 230 TL
      // (Under old code, netRevenue was 80 + 150 - 20 = 210 TL, erroneously subtracting 20 TL twice!)
      expect(report.netRevenue, 230.0);
    });

    test('G4: SqliteInstallmentRepository writes kuruş (minor) currency fields to financial_transactions', () async {
      const customerId = 'cust-g4-test';
      await gateway.insert('customers', {
        'id': customerId,
        'name': 'Taksit Kuruş Test Müşterisi',
        'phone': '05553334455',
        'balance': 0.0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_deleted': 0,
      });

      // 1. Create a 3-month installment plan for 350.75 TL with 50.25 TL down payment
      final plan = await installmentRepo.createPlan(
        customerId: customerId,
        totalAmount: 350.75,
        downPayment: 50.25,
        downPaymentMethod: 'cash',
        installmentCount: 3,
        firstDueDate: DateTime.now().add(const Duration(days: 30)),
        description: 'Test Taksit Planı G4',
      );

      expect(plan.totalAmount, 350.75);
      expect(plan.downPayment, 50.25);

      // Check debt transaction minor units
      final debtRows = await gateway.query(
        'financial_transactions',
        where: "reference_id = ? AND type = 'manual_debt'",
        whereArgs: [plan.id],
      );
      expect(debtRows.isNotEmpty, isTrue);
      final debtTx = debtRows.first;
      expect(debtTx['amount'], 350.75);
      expect(debtTx['amount_minor'], 35075);
      expect(debtTx['debt_amount_minor'], 35075);
      expect(debtTx['paid_amount_minor'], 0);

      // Check down payment transaction minor units
      final downRows = await gateway.query(
        'financial_transactions',
        where: "reference_id = ? AND type = 'collection'",
        whereArgs: [plan.id],
      );
      expect(downRows.isNotEmpty, isTrue);
      final downTx = downRows.first;
      expect(downTx['amount'], 50.25);
      expect(downTx['amount_minor'], 5025);
      expect(downTx['paid_amount_minor'], 5025);
      expect(downTx['debt_amount_minor'], 0);

      // Check outbox payload minor units for debt and down payment
      final outboxDebt = await gateway.query(
        'sync_outbox_v4',
        where: 'entity_id = ?',
        whereArgs: [debtTx['id']],
      );
      expect(outboxDebt.isNotEmpty, isTrue);
      expect(outboxDebt.first['payload'].toString(), contains('"amount_minor":35075'));

      // 2. Pay an installment of 100.16 TL
      final installments = await installmentRepo.getInstallmentsForPlan(plan.id);
      expect(installments.length, 3);
      final firstInst = installments.first;

      await installmentRepo.payInstallment(
        installmentId: firstInst.id,
        amount: firstInst.amount,
        paymentMethod: 'cash',
        note: '1. Taksit Ödemesi',
      );

      final instColRows = await gateway.query(
        'financial_transactions',
        where: "reference_id = ? AND type = 'collection'",
        whereArgs: [firstInst.id],
      );
      expect(instColRows.isNotEmpty, isTrue);
      final instColTx = instColRows.first;
      expect(instColTx['amount'], firstInst.amount);
      expect(instColTx['amount_minor'], (firstInst.amount * 100).round());
      expect(instColTx['paid_amount_minor'], (firstInst.amount * 100).round());
    });

    test('G3: Plan completion & cancellation include customer_id and use operation DELETE', () async {
      const customerId = 'cust-g3-test';
      await gateway.insert('customers', {
        'id': customerId,
        'name': 'Plan Tamamlama Testi',
        'phone': '05556667788',
        'balance': 0.0,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'is_deleted': 0,
      });

      // 1. Create a 1-installment plan
      final plan1 = await installmentRepo.createPlan(
        customerId: customerId,
        totalAmount: 100.0,
        installmentCount: 1,
        firstDueDate: DateTime.now().add(const Duration(days: 15)),
        description: 'Tek Taksit Planı',
      );

      final insts1 = await installmentRepo.getInstallmentsForPlan(plan1.id);
      expect(insts1.length, 1);

      // Pay the only installment to trigger plan completion
      await installmentRepo.payInstallment(
        installmentId: insts1.first.id,
        amount: 100.0,
        paymentMethod: 'cash',
      );

      // Check plan completion outbox entry has customer_id
      final planCompletedOutbox = await gateway.query(
        'sync_outbox_v4',
        where: "entity_id = ? AND operation = 'UPSERT'",
        whereArgs: [plan1.id],
        orderBy: 'id DESC',
        limit: 1,
      );
      expect(planCompletedOutbox.isNotEmpty, isTrue);
      final payloadStr = planCompletedOutbox.first['payload'].toString();
      expect(payloadStr, contains('"status":"completed"'));
      expect(payloadStr, contains('"customer_id":"$customerId"'));

      // 2. Test cancelPlan uses operation DELETE and includes customer_id
      final plan2 = await installmentRepo.createPlan(
        customerId: customerId,
        totalAmount: 200.0,
        installmentCount: 2,
        firstDueDate: DateTime.now().add(const Duration(days: 30)),
        description: 'İptal Edilecek Plan',
      );

      await installmentRepo.cancelPlan(plan2.id);

      // Check plan cancellation outbox uses DELETE and has customer_id
      final planCancelOutbox = await gateway.query(
        'sync_outbox_v4',
        where: "entity_id = ? AND operation = 'DELETE' AND entity_type = 'customer_installment_plan'",
        whereArgs: [plan2.id],
      );
      expect(planCancelOutbox.isNotEmpty, isTrue);
      expect(planCancelOutbox.first['payload'].toString(), contains('"customer_id":"$customerId"'));
      expect(planCancelOutbox.first['payload'].toString(), contains('"status":"cancelled"'));

      // Check financial transactions are enqueued with DELETE
      final ftCancelOutbox = await gateway.query(
        'sync_outbox_v4',
        where: "operation = 'DELETE' AND entity_type = 'financial_transaction'",
      );
      expect(ftCancelOutbox.isNotEmpty, isTrue);
    });

    test('G2: SyncV4Materializer materializes cash_counts, installment entities, and executes schema-aware DELETE', () async {
      final db = await databaseManager.getDatabase();
      final syncService = SyncV4Service(
        ApiClient(),
        deviceIdResolver: () async => 'test-device-id',
        deviceActivationIdResolver: () async => 'test-activation-id',
      );

      // 1. Test cash_count materialization with count_date -> date alias mapping
      final cashCountChange = {
        'entity_type': 'cash_count',
        'entity_id': 'count_2026-10-27',
        'operation': 'UPSERT',
        'payload': {
          'id': 'count_2026-10-27',
          'count_date': '2026-10-27',
          'opening_balance': 450.0,
          'counted_cash': 1350.0,
          'expected_cash': 1300.0,
          'difference': 50.0,
          'notes': 'Sync V4 Test Sayımı',
        },
      };

      await db.transaction((txn) async {
        await syncService.applyChangeForTesting(txn, cashCountChange);
      });

      final countRows = await gateway.query(
        'cash_counts',
        where: 'id = ?',
        whereArgs: ['count_2026-10-27'],
      );
      expect(countRows.isNotEmpty, isTrue);
      expect(countRows.first['date'], '2026-10-27');
      expect(countRows.first['counted_cash'], 1350.0);
      expect(countRows.first['difference'], 50.0);

      // 2. Test customer_installment_plan materialization and customer bootstrap
      final planChange = {
        'entity_type': 'customer_installment_plan',
        'entity_id': 'plan-sync-test-1',
        'operation': 'UPSERT',
        'payload': {
          'id': 'plan-sync-test-1',
          'customer_id': 'cust-sync-auto-bootstrapped',
          'customer_name': 'Otomatik Eklenen Müşteri',
          'total_amount': 800.0,
          'down_payment': 100.0,
          'installment_count': 4,
          'description': 'Sync V4 Taksit Testi',
          'status': 'active',
        },
      };

      await db.transaction((txn) async {
        await syncService.applyChangeForTesting(txn, planChange);
      });

      // Customer should have been automatically bootstrapped
      final custRows = await gateway.query(
        'customers',
        where: 'id = ?',
        whereArgs: ['cust-sync-auto-bootstrapped'],
      );
      expect(custRows.isNotEmpty, isTrue);
      expect(custRows.first['name'], 'Otomatik Eklenen Müşteri');

      // Installment plan should be present
      final planSyncRows = await gateway.query(
        'customer_installment_plans',
        where: 'id = ?',
        whereArgs: ['plan-sync-test-1'],
      );
      expect(planSyncRows.isNotEmpty, isTrue);
      expect(planSyncRows.first['total_amount'], 800.0);

      // 3. Test customer_installment item materialization
      final instChange = {
        'entity_type': 'customer_installment',
        'entity_id': 'inst-sync-test-1',
        'operation': 'UPSERT',
        'payload': {
          'id': 'inst-sync-test-1',
          'plan_id': 'plan-sync-test-1',
          'customer_id': 'cust-sync-auto-bootstrapped',
          'installment_no': 1,
          'amount': 175.0,
          'paid_amount': 0.0,
          'due_date': '2026-11-27',
          'status': 'pending',
        },
      };

      await db.transaction((txn) async {
        await syncService.applyChangeForTesting(txn, instChange);
      });

      final instSyncRows = await gateway.query(
        'customer_installments',
        where: 'id = ?',
        whereArgs: ['inst-sync-test-1'],
      );
      expect(instSyncRows.isNotEmpty, isTrue);
      expect(instSyncRows.first['amount'], 175.0);

      // 4. Test schema-aware deletion on cash_counts (no is_deleted column -> hard delete)
      final cashDeleteChange = {
        'entity_type': 'cash_count',
        'entity_id': 'count_2026-10-27',
        'operation': 'DELETE',
        'payload': {'id': 'count_2026-10-27'},
      };

      await db.transaction((txn) async {
        await syncService.applyChangeForTesting(txn, cashDeleteChange);
      });

      final countAfterDelete = await gateway.query(
        'cash_counts',
        where: 'id = ?',
        whereArgs: ['count_2026-10-27'],
      );
      expect(countAfterDelete.isEmpty, isTrue);

      // 5. Test schema-aware deletion on customer_installment_plans (has is_deleted -> tombstone update)
      final planDeleteChange = {
        'entity_type': 'customer_installment_plan',
        'entity_id': 'plan-sync-test-1',
        'operation': 'DELETE',
        'payload': {'id': 'plan-sync-test-1'},
      };

      await db.transaction((txn) async {
        await syncService.applyChangeForTesting(txn, planDeleteChange);
      });

      final planAfterDelete = await gateway.query(
        'customer_installment_plans',
        where: 'id = ?',
        whereArgs: ['plan-sync-test-1'],
      );
      expect(planAfterDelete.isNotEmpty, isTrue);
      expect(planAfterDelete.first['is_deleted'], 1);
    });
  });
}
