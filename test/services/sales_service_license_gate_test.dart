// test/services/sales_service_license_gate_test.dart
// Serenut POS — Sales Service License Gate Tests

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:serenutos/domain/services/security_gate.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/services/trial_manager.dart';
import 'package:serenutos/domain/services/inventory_service.dart';
import 'package:serenutos/domain/services/payment_service.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/events/event_publisher.dart';

class MockLicenseService extends LicenseService {
  String statusResult = 'valid';
  MockLicenseService(super.prefs);

  @override
  String checkLicenseStatus() => statusResult;
}

class MockTrialManager extends TrialManager {
  bool trialActive = false;
  MockTrialManager(super.prefs);

  @override
  bool isTrialActive() => trialActive;
}

class FakeSaleRepository implements ISaleRepository {
  final Map<String, SaleEntity> sales = {};

  @override
  Future<SaleEntity?> findById(dynamic id) async => sales[id.toString()];

  @override
  Future<int> update(SaleEntity sale) async {
    sales[sale.id] = sale;
    return 1;
  }

  @override
  Future<SaleEntity?> findByIdempotencyKey(String key) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeProductRepository implements IProductRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeCustomerRepository implements ICustomerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeFinancialTransactionRepository implements IFinancialTransactionRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeInventoryService extends InventoryService {
  FakeInventoryService() : super(
    productRepository: FakeProductRepository(),
    eventPublisher: FakeEventPublisher(),
  );

  @override
  Future<void> restoreStock(List<SaleItemInput> items) async {}
}

class FakePaymentService extends PaymentService {
  FakePaymentService() : super(
    customerRepository: FakeCustomerRepository(),
    transactionRepository: FakeFinancialTransactionRepository(),
    eventPublisher: FakeEventPublisher(),
  );

  @override
  Future<void> recordPartialPayment({
    required String saleId,
    required String customerId,
    required double amount,
    required String method,
    required double currentPaidAmount,
    required double totalAmount,
  }) async {
    // No-op
  }

  @override
  Future<void> processSaleCancellation({
    required String saleId,
    required String customerId,
    required double totalAmount,
    required double paidAmount,
  }) async {
    // No-op
  }
}

class FakeEventPublisher implements EventPublisher {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SalesService License Gate Tests', () {
    late SharedPreferences prefs;
    late MockLicenseService licenseService;
    late MockTrialManager trialManager;
    late SecurityGate securityGate;
    late FakeSaleRepository saleRepository;
    late SalesService salesService;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      licenseService = MockLicenseService(prefs);
      trialManager = MockTrialManager(prefs);
      securityGate = SecurityGate(licenseService, trialManager);
      saleRepository = FakeSaleRepository();

      salesService = SalesService.noDb(
        saleRepository: saleRepository,
        inventoryService: FakeInventoryService(),
        paymentService: FakePaymentService(),
        eventPublisher: FakeEventPublisher(),
        securityGate: securityGate,
      );

      // Seed a test sale
      saleRepository.sales['sale-1'] = SaleEntity(
        id: 'sale-1',
        customerId: 'cust-1',
        totalAmount: 100.0,
        paidAmount: 50.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now(),
        items: [],
      );
    });

    test('Allowed to record payment when license is valid', () async {
      licenseService.statusResult = 'valid';
      await expectLater(
        salesService.recordPayment(saleId: 'sale-1', amount: 10.0, method: 'cash'),
        completes,
      );
    });

    test('Fails to record payment when license is expired', () async {
      licenseService.statusResult = 'expired';
      expect(
        () => salesService.recordPayment(saleId: 'sale-1', amount: 10.0, method: 'cash'),
        throwsA(isA<LicenseException>()),
      );
    });

    test('Fails to record payment when license is suspended', () async {
      licenseService.statusResult = 'suspended';
      expect(
        () => salesService.recordPayment(saleId: 'sale-1', amount: 10.0, method: 'cash'),
        throwsA(isA<LicenseException>()),
      );
    });

    test('Allowed to cancel sale when license is valid', () async {
      licenseService.statusResult = 'valid';
      await expectLater(
        salesService.cancelSale('sale-1'),
        completes,
      );
    });

    test('Fails to cancel sale when license is revoked', () async {
      licenseService.statusResult = 'revoked';
      expect(
        () => salesService.cancelSale('sale-1'),
        throwsA(isA<LicenseException>()),
      );
    });

    test('Fails to cancel sale when license is tampered', () async {
      licenseService.statusResult = 'tampered';
      expect(
        () => salesService.cancelSale('sale-1'),
        throwsA(isA<LicenseException>()),
      );
    });
  });
}
