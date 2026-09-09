import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/payment_service.dart';
import 'package:serenutos/domain/events/event_publisher.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';

void main() {
  databaseFactory = databaseFactoryFfi;
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database db;
  late SqliteCustomerRepository customerRepo;
  late SqliteFinancialTransactionRepository transactionRepo;
  late PaymentService paymentService;

  setUpAll(() async {
    DatabaseManager.overrideDatabasePath = ':memory:';
    db = await DatabaseManager().getDatabase();
    final gateway = DbGatewayImpl.raw(db);
    customerRepo = SqliteCustomerRepository(gateway);
    transactionRepo = SqliteFinancialTransactionRepository(gateway);
    paymentService = PaymentService(
      customerRepository: customerRepo,
      transactionRepository: transactionRepo,
      eventPublisher: EventPublisher(),
    );
  });

  tearDownAll(() async {
    await db.close();
    DatabaseManager.overrideDatabasePath = null;
  });

  group('Order Revision Payment & Balance Tests (Atomic Single-Row Update)', () {
    const cust1 = 'cust-rev-1';
    const cust2 = 'cust-rev-2';
    const orderId = 'order-test-revision-101';

    setUp(() async {
      await db.update('ledger_bypass_flag', {'active': 1});
      await db.delete('financial_transactions');
      await db.delete('customers');
      await db.update('ledger_bypass_flag', {'active': 0});

      await customerRepo.create(CustomerEntity(
        id: cust1,
        name: 'Müşteri 1',
        email: 'c1@test.com',
        phone: '11111',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));

      await customerRepo.create(CustomerEntity(
        id: cust2,
        name: 'Müşteri 2',
        email: 'c2@test.com',
        phone: '22222',
        balance: 0.0,
        createdAt: DateTime.now(),
      ));
    });

    test(
        'Order revisions atomically update the single sale transaction in-place with ZERO fake cancellations and ZERO phantom credit',
        () async {
      // 1. Initial Order Creation: Total = 500, Paid = 0 -> Debt = 500
      await paymentService.processSalePayment(
        saleId: orderId,
        customerId: cust1,
        totalAmount: 500.0,
        paidAmount: 0.0,
        paymentMethod: 'debt',
      );

      var b1 = await customerRepo.getBalance(cust1);
      expect(b1, -500.0, reason: 'Initial balance should be -500 (Borç)');

      var txs = await transactionRepo.getByReferenceId(orderId);
      expect(txs.length, 1, reason: 'Initially exactly 1 transaction exists');

      // 2. Revision 1: User changes order to Total = 600, Paid = 0 -> Debt = 600
      await paymentService.reviseOrderPayment(
        orderId: orderId,
        oldCustomerId: cust1,
        newCustomerId: cust1,
        totalAmount: 600.0,
        paidAmount: 0.0,
      );

      b1 = await customerRepo.getBalance(cust1);
      expect(b1, -600.0, reason: 'Balance after 1st revision should be -600');

      txs = await transactionRepo.getByReferenceId(orderId);
      expect(txs.length, 1,
          reason:
              'Root Solution Guarantee: Exactly 1 transaction remains (NO duplicate sales, NO fake cancellations)');
      expect(txs.first.amount, 600.0);
      expect(txs.first.debtAmount, 600.0);

      // 3. Revision 2: User changes order to Total = 750, Paid = 0 -> Debt = 750
      await paymentService.reviseOrderPayment(
        orderId: orderId,
        oldCustomerId: cust1,
        newCustomerId: cust1,
        totalAmount: 750.0,
        paidAmount: 0.0,
      );

      b1 = await customerRepo.getBalance(cust1);
      expect(b1, -750.0,
          reason: 'Balance after 2nd revision must be -750 (never phantom credit)');

      txs = await transactionRepo.getByReferenceId(orderId);
      expect(txs.length, 1, reason: 'Still exactly 1 transaction');
      expect(txs.first.amount, 750.0);

      // 4. Revision 3: User pays 300 TL during edit -> Total = 750, Paid = 300 -> Debt = 450
      await paymentService.reviseOrderPayment(
        orderId: orderId,
        oldCustomerId: cust1,
        newCustomerId: cust1,
        totalAmount: 750.0,
        paidAmount: 300.0,
      );

      b1 = await customerRepo.getBalance(cust1);
      expect(b1, -450.0,
          reason: 'Balance after 3rd revision (partial payment) must be -450');

      txs = await transactionRepo.getByReferenceId(orderId);
      expect(txs.length, 1, reason: 'Still exactly 1 transaction');
      expect(txs.first.paidAmount, 300.0);
      expect(txs.first.debtAmount, 450.0);

      // 5. Revision 4: Customer transfer from cust1 to cust2 with Debt = 450
      await paymentService.reviseOrderPayment(
        orderId: orderId,
        oldCustomerId: cust1,
        newCustomerId: cust2,
        totalAmount: 750.0,
        paidAmount: 300.0,
      );

      b1 = await customerRepo.getBalance(cust1);
      var b2 = await customerRepo.getBalance(cust2);
      expect(b1, 0.0,
          reason:
              'cust1 balance must be completely cleared (0.0) by trg_ft_update reversing old customer debt');
      expect(b2, -450.0,
          reason:
              'cust2 balance must now carry the 450 TL debt applied by trg_ft_update');

      // Final ledger verification:
      final allOrderTxs = await transactionRepo.getByReferenceId(orderId);
      expect(allOrderTxs.length, 1,
          reason:
              'Throughout all 4 revisions, exactly 1 transaction ever existed in financial_transactions!');
      expect(allOrderTxs.first.customerId, cust2);
      expect(allOrderTxs.first.amount, 750.0);
      expect(allOrderTxs.first.paidAmount, 300.0);
      expect(allOrderTxs.first.debtAmount, 450.0);
      expect(allOrderTxs.first.type, 'sale');

      // Cancellations count must be strictly 0
      final allCancellations =
          allOrderTxs.where((tx) => tx.type == 'cancellation').toList();
      expect(allCancellations.isEmpty, true,
          reason: 'No fake cancellation transactions were generated!');
    });
  });
}
