// test/services/order_printing_productization_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/domain/services/order_math_engine.dart';
import 'package:serenutos/domain/models/label_model.dart';
import 'package:serenutos/domain/services/label_layout_engine.dart';
import 'package:serenutos/domain/services/security_gate.dart';
import 'package:serenutos/domain/services/trial_manager.dart';
import 'package:serenutos/domain/services/license_service.dart';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_order_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_payment_repository.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/services/printer_service.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  SharedPreferences.setMockInitialValues({});

  group('Order Printing & Productization Tests', () {
    late Database db;
    late DatabaseManager databaseManager;
    late SqliteOrderRepository orderRepo;
    late SqliteSaleRepository saleRepo;
    late SecurityGate securityGate;
    late LicenseService licenseService;

    setUp(() async {
      DatabaseManager.overrideDatabasePath = inMemoryDatabasePath;
      databaseManager = DatabaseManager();
      db = await databaseManager.getDatabase();

      final gateway = DbGatewayImpl(databaseManager);
      orderRepo = SqliteOrderRepository(gateway);
      saleRepo = SqliteSaleRepository(gateway);

      final prefs = await SharedPreferences.getInstance();
      licenseService = LicenseService(prefs);
      final trialManager = TrialManager(prefs);
      securityGate = SecurityGate(licenseService, trialManager);
    });

    test('OrderMathEngine - Safe decimal calculations without precision drifts', () {
      final subtotal = OrderMathEngine.calculateItemSubtotal(19.90, 1.5);
      expect(subtotal, 29.85); // 1.5 * 19.90 = 29.85

      final items = [
        {'product_id': 'cheese', 'quantity': 1.5, 'unit_price': 19.90},
        {'product_id': 'olives', 'quantity': 0.75, 'unit_price': 12.00},
      ];
      final total = OrderMathEngine.calculateTotal(items);
      expect(total, 38.85); // 29.85 + 9.00 = 38.85
    });

    test('SQLite Repositories - Decimal quantity persistence', () async {
      // Create a walk-in cash customer first to satisfy foreign key constraints
      await db.insert('customers', {
        'id': 'cust-test-1',
        'name': 'Test Müşteri',
        'email': 'test@serenut.com',
        'phone': '5551234567',
        'balance': 0.0,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      // Insert product to satisfy foreign key
      await db.insert('products', {
        'id': 'prod-test-1',
        'name': 'Test Product',
        'price': 19.90,
        'quantity': 100,
        'category': 'default',
        'sku': 'SKU123',
        'is_active': 1,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      });

      final order = OrderEntity(
        id: 'ord-test-123',
        customerId: 'cust-test-1',
        status: 'created',
        createdAt: DateTime.now(),
        items: [
          {'product_id': 'prod-test-1', 'quantity': 1.5, 'unit_price': 19.90},
        ],
      );

      // Save order
      await orderRepo.create(order);

      // Load order
      final savedOrder = await orderRepo.findById('ord-test-123');
      expect(savedOrder, isNotNull);
      expect(savedOrder!.items, hasLength(1));
      expect(savedOrder.items.first['quantity'], 1.5); // Verify double quantity is preserved!
    });

    test('PrinterService - Queue execution doesn’t break on job failures', () async {
      final printerService = PrinterService((ip, port, {timeout}) async {
        throw Exception('Connection failed');
      });

      int successJobs = 0;
      int failedJobs = 0;

      printerService.addListener(() {
        for (final job in printerService.queue) {
          if (job.status == 'success') successJobs++;
          if (job.status == 'failed') failedJobs++;
        }
      });

      // Enqueue job 1 (failing)
      printerService.enqueue('Job 1', () async {
        throw Exception('Failure 1');
      });

      // Enqueue job 2 (succeeding)
      printerService.enqueue('Job 2', () async {
        // Success
      });

      // Wait a short duration for the event loop
      await Future.delayed(const Duration(milliseconds: 100));

      expect(printerService.queue, hasLength(2));
      expect(printerService.queue[0].status, 'failed');
      expect(printerService.queue[1].status, 'success'); // Job 2 successfully ran despite Job 1 failure!
    });

    test('LabelLayoutEngine - Beautiful ESC/POS label bytes generation', () {
      final labelModel = LabelModel(
        productName: 'Eski Kaşar',
        weight: 1.5,
        price: 199.90,
        qrData: 'item|ord-1|cheese|1.5',
        timestamp: DateTime(2026, 7, 1, 12, 0),
        batchNo: 'BATCH-99',
      );

      final bytes = LabelLayoutEngine.generateLabelBytes(labelModel, width: 32);
      expect(bytes, isNotEmpty);
      expect(bytes.contains(0x1B), isTrue); // ESC init command check
      expect(bytes.contains(0x1D), isTrue); // GS QR code command check
    });

    test('SecurityGate - SaaS device limit and force update checks', () {
      // Device limits checks
      expect(
        () => securityGate.validateDeviceLimit('dev-1', 4, 3),
        throwsA(isA<LicenseException>()),
      );
      expect(
        () => securityGate.validateDeviceLimit('dev-1', 2, 3),
        returnsNormally,
      );

      // Force update checks
      expect(
        () => securityGate.checkForceUpdate(10, 12),
        throwsA(isA<UpdateRequiredException>()),
      );
      expect(
        () => securityGate.checkForceUpdate(12, 12),
        returnsNormally,
      );
    });
  });
}
