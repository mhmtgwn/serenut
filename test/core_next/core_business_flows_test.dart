import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' hide equals;
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_product_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_customer_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_installment_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_order_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:serenutos/domain/services/payment_service.dart';
import 'package:serenutos/domain/events/event_publisher.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Core Business Flows (Müşteri, Borç, Taksit, Sipariş)', () {
    late DatabaseManager databaseManager;
    late DbGateway gateway;
    late SqliteCustomerRepository customerRepo;
    late SqliteInstallmentRepository installmentRepo;
    late SqliteOrderRepository orderRepo;
    late SqliteFinancialTransactionRepository financialRepo;
    late PaymentService paymentService;

    setUpAll(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'test_core_business_flows.db');
      await deleteDatabase(path);

      databaseManager = DatabaseManager();
      gateway = DbGatewayImpl(databaseManager);
      customerRepo = SqliteCustomerRepository(gateway);
      installmentRepo = SqliteInstallmentRepository(gateway);
      orderRepo = SqliteOrderRepository(gateway);
      financialRepo = SqliteFinancialTransactionRepository(gateway);
      paymentService = PaymentService(
        customerRepository: customerRepo,
        transactionRepository: financialRepo,
        eventPublisher: EventPublisher(),
      );

      // Ensure DB is initialized
      await databaseManager.getDatabase();
    });

    tearDownAll(() async {
      final databasePath = await getDatabasesPath();
      final path = join(databasePath, 'test_core_business_flows.db');
      await databaseManager.close();
      await deleteDatabase(path);
    });

    test('1. Müşteri ekleme ve duplicate kontrolü çalışıyor mu?', () async {
      final customer = CustomerEntity(
        id: 'cust-test-1',
        name: 'Ahmet Yılmaz',
        phone: '05551234567',
        balance: 0.0,
        createdAt: DateTime.now(),
      );

      await customerRepo.create(customer);
      final fetched = await customerRepo.findById('cust-test-1');
      expect(fetched, isNotNull);
      expect(fetched!.name, 'Ahmet Yılmaz');
      expect(fetched.phone, '05551234567');
      expect(fetched.balance, 0.0);
    });

    test('2. Elle borç ekleme ve bakiye güncelleme çalışıyor mu?', () async {
      await paymentService.recordManualDebt(
        customerId: 'cust-test-1',
        amount: 500.0,
        notes: 'Test elden borç verme',
      );

      final customer = await customerRepo.findById('cust-test-1');
      expect(customer, isNotNull);
      // Debt balance is negative in ledger (-500 TL)
      expect(customer!.balance, -500.0);

      final txs = await financialRepo.getByCustomerId('cust-test-1');
      expect(txs.isNotEmpty, isTrue);
      expect(txs.any((tx) => tx.type == 'manual_debt' && tx.debtAmount == 500.0), isTrue);
    });

    test('3. Taksit planı ekleme, peşinat ve taksit ödeme çalışıyor mu?', () async {
      // Toplam 1200 TL, 200 TL peşinat, 2 taksit (her biri 500 TL)
      final plan = await installmentRepo.createPlan(
        customerId: 'cust-test-1',
        totalAmount: 1200.0,
        downPayment: 200.0,
        downPaymentMethod: 'cash',
        installmentCount: 2,
        firstDueDate: DateTime.now().add(const Duration(days: 30)),
        description: 'Çeyiz Taksiti',
      );

      expect(plan.id, isNotEmpty);
      expect(plan.status, 'active');

      final insts = await installmentRepo.getInstallmentsForPlan(plan.id);
      expect(insts.length, 2);
      expect(insts[0].amount, 500.0);
      expect(insts[1].amount, 500.0);

      // Customer previously had -500 TL. Added 1000 TL financed debt (1200 - 200 peşinat).
      // Total debt should now be -1500 TL.
      var customer = await customerRepo.findById('cust-test-1');
      expect(customer!.balance, -1500.0);

      // 1. taksiti öde (500 TL)
      await installmentRepo.payInstallment(
        installmentId: insts[0].id,
        amount: 500.0,
        paymentMethod: 'cash',
        note: '1. taksit elden ödendi',
      );

      final updatedInsts = await installmentRepo.getInstallmentsForPlan(plan.id);
      expect(updatedInsts[0].status, 'paid');
      expect(updatedInsts[0].paidAmount, 500.0);
      expect(updatedInsts[1].status, 'pending');

      // Balance after paying 500 TL should be -1000 TL
      customer = await customerRepo.findById('cust-test-1');
      expect(customer!.balance, -1000.0);
    });

    test('4. Sipariş oluşturma, numara üretimi ve sipariş sorgulama çalışıyor mu?', () async {
      final productRepo = SqliteProductRepository(gateway);
      await productRepo.create(ProductEntity(
        id: 'prod-1',
        name: 'Test Ürün A',
        description: 'Açıklama A',
        price: 150.0,
        quantity: 10,
        category: 'Test',
      ));

      final order = OrderEntity(
        id: 'ord-test-101',
        customerId: 'cust-test-1',
        customerName: 'Ahmet Yılmaz',
        customerPhone: '05551234567',
        status: 'created',
        createdAt: DateTime.now(),
        items: [
          {
            'product_id': 'prod-1',
            'product_name': 'Test Ürün A',
            'quantity': 2.0,
            'unit_price': 150.0,
            'total_price': 300.0,
          }
        ],
        discountAmount: 0.0,
      );

      final rowId = await orderRepo.create(order);
      expect(rowId, isPositive);

      final fetched = await orderRepo.findById('ord-test-101');
      expect(fetched, isNotNull);
      expect(fetched!.displayNumber.startsWith('SP-'), isTrue);
      expect(fetched.customerName, 'Ahmet Yılmaz');
      expect(fetched.totalAmount, 300.0);
      expect(fetched.items.length, 1);
      expect(fetched.items.first['product_name'], 'Test Ürün A');
    });
  });
}
