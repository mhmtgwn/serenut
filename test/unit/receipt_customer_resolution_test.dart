// test/unit/receipt_customer_resolution_test.dart
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/printing/printing_models.dart';
import 'package:serenutos/domain/printing/printing_repository.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/printing/printing_runtime.dart';
import 'package:serenutos/infrastructure/printing/sqlite_printing_application_service.dart';

class _FakePrintingRepository implements PrintingRepository {
  PrintJobRecord? lastJob;

  @override
  Future<PrinterRoute?> getRoute(PrintDocumentKind kind) async => null;

  @override
  Future<PrinterDeviceProfile?> getDevice(String id) async => null;

  @override
  Future<PrintJobRecord> enqueue({
    required PrintDocumentKind kind,
    required String payloadJson,
    int copies = 1,
  }) async {
    final now = DateTime.now();
    final job = PrintJobRecord(
      id: 'job-1',
      kind: kind,
      payloadJson: payloadJson,
      copies: copies,
      designProfileId: 'profile-1',
      designSnapshotJson: '{}',
      deviceId: 'device-1',
      transportSnapshotJson: '{}',
      capabilitySnapshotJson: '{}',
      rendererVersion: '1.0',
      state: PrintJobState.queued,
      attemptCount: 0,
      createdAt: now,
      updatedAt: now,
    );
    lastJob = job;
    return job;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakePrintingRuntime implements PrintingRuntime {
  @override
  bool get isRunning => false;

  @override
  Future<void> processNow() async {}

  @override
  Future<PrintRecoverySummary> start() async =>
      const PrintRecoverySummary(safelyRequeued: 0, awaitingUserCheck: 0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('Receipt Customer Resolution Tests', () {
    late _FakePrintingRepository fakeRepo;
    late _FakePrintingRuntime fakeRuntime;
    late Settings testSettings;

    setUp(() {
      fakeRepo = _FakePrintingRepository();
      fakeRuntime = _FakePrintingRuntime();
      testSettings = Settings(
        businessName: 'Nutopia',
        businessPhone: '05550000000',
        businessAddress: 'İstanbul',
        currency: 'TL',
        paperWidth: 80,
      );
    });

    test('queueSaleReceipt resolves customer via customerLookup when customer argument is null', () async {
      final service = SqlitePrintingApplicationService(
        repository: fakeRepo,
        runtime: fakeRuntime,
        customerLookup: (customerId) async {
          if (customerId == 'cust-real-1') {
            return CustomerEntity(
              id: 'cust-real-1',
              name: 'Ayşe Kaya',
              email: 'ayse@example.com',
              phone: '05559998877',
              balance: -250.0,
              createdAt: DateTime.now(),
            );
          }
          return null;
        },
      );

      final sale = SaleEntity(
        id: 'sale-12345678',
        customerId: 'cust-real-1',
        totalAmount: 100.0,
        paidAmount: 100.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now(),
        items: [],
      );

      await service.queueSaleReceipt(sale, [], null, testSettings);

      expect(fakeRepo.lastJob, isNotNull);
      final decoded = jsonDecode(fakeRepo.lastJob!.payloadJson) as Map<String, dynamic>;
      final doc = decoded['document'] as Map<String, dynamic>;
      expect(doc['customerName'], equals('Ayşe Kaya'));
      expect(doc['customerPhone'], equals('05559998877'));
      expect(doc['customerBalance'], equals(-250.0));
    });

    test('queueSaleReceipt defaults to Genel Müşteri when customerId is empty', () async {
      final service = SqlitePrintingApplicationService(
        repository: fakeRepo,
        runtime: fakeRuntime,
      );

      final sale = SaleEntity(
        id: 'sale-12345678',
        customerId: '',
        totalAmount: 50.0,
        paidAmount: 50.0,
        paymentMethod: 'cash',
        status: 'completed',
        createdAt: DateTime.now(),
        items: [],
      );

      await service.queueSaleReceipt(sale, [], null, testSettings);

      expect(fakeRepo.lastJob, isNotNull);
      final decoded = jsonDecode(fakeRepo.lastJob!.payloadJson) as Map<String, dynamic>;
      final doc = decoded['document'] as Map<String, dynamic>;
      expect(doc['customerName'], equals('Genel Müşteri'));
    });

    test('queueOrderReceipt resolves customer via customerLookup and falls back to order.customerName', () async {
      final service = SqlitePrintingApplicationService(
        repository: fakeRepo,
        runtime: fakeRuntime,
        customerLookup: (customerId) async {
          if (customerId == 'cust-order-1') {
            return CustomerEntity(
              id: 'cust-order-1',
              name: 'Ali Veli',
              email: '',
              phone: '05441234567',
              balance: 0,
              createdAt: DateTime.now(),
            );
          }
          return null;
        },
      );

      final orderWithLookup = OrderEntity(
        id: 'ord-123',
        orderNumber: 'SP-000001',
        customerId: 'cust-order-1',
        status: 'created',
        createdAt: DateTime.now(),
        items: [],
      );

      await service.queueOrderReceipt(orderWithLookup, [], null, testSettings);
      expect(fakeRepo.lastJob, isNotNull);
      var decoded = jsonDecode(fakeRepo.lastJob!.payloadJson) as Map<String, dynamic>;
      var doc = decoded['document'] as Map<String, dynamic>;
      expect(doc['customerName'], equals('Ali Veli'));
      expect(doc['customerPhone'], equals('05441234567'));

      // Test fallback to order.customerName if customerLookup returns null
      final orderWithEntityName = OrderEntity(
        id: 'ord-124',
        orderNumber: 'SP-000002',
        customerId: 'cust-unknown-id',
        customerName: 'Fatma Şahin',
        customerPhone: '05331112233',
        status: 'created',
        createdAt: DateTime.now(),
        items: [],
      );

      await service.queueOrderReceipt(orderWithEntityName, [], null, testSettings);
      decoded = jsonDecode(fakeRepo.lastJob!.payloadJson) as Map<String, dynamic>;
      doc = decoded['document'] as Map<String, dynamic>;
      expect(doc['customerName'], equals('Fatma Şahin'));
    });
  });
}
