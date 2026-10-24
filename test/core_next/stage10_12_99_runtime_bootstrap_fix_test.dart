// test/core_next/stage10_12_99_runtime_bootstrap_fix_test.dart
// SERENUT OS — STAGE 10.12.99
// Gerçek Bootstrap Bağlantısı ve Güvenli Çalışma Zamanı Test Paketi
// ignore_for_file: avoid_relative_lib_imports

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/inventory_service.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:serenutos/infrastructure/bootstrap/core_next_bootstrap_coordinator.dart';
import 'package:serenutos/infrastructure/bootstrap/pilot_cutover_gate.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';

import '../../core_next/client_core/lib/domain/models/core_entities.dart' as core;
import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/database_routing_resolver.dart';
import '../../core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_customer_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_financial_transaction_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_product_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/core_next_sale_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('STAGE 10.12.99 — Gerçek Bootstrap ve Runtime Bağlantı Testleri', () {
    late Directory tempDir;
    late String legacyDbPath;
    late String targetDbPath;
    late String backupPath;
    late CoreAppDatabase coreDb;

    const nutopiaTenantId = 'comp-nutopia-01';
    const erkulTenantId = 'comp-1791194455402-bdc6d8d1';
    const testProductId = 'prod-stage99-01';

    setUp(() async {
      tempDir = Directory.systemTemp.createTempSync('stage10_12_99_test_');
      legacyDbPath = p.join(tempDir.path, 'serenut_pos_legacy.db');
      targetDbPath = p.join(tempDir.path, 'serenut_core_v2_target.db');
      backupPath = p.join(tempDir.path, 'test_backup.db');

      // 1. Sahte Yedek Dosyası (En az 512 bayt olmalı)
      final bFile = File(backupPath);
      await bFile.writeAsString('BACKUP_MOCK'.padRight(600, '0'));

      // 2. Legacy Veritabanı Oluştur
      final legDb = await openDatabase(legacyDbPath, version: 60);
      await legDb.execute('CREATE TABLE IF NOT EXISTS settings (id TEXT PRIMARY KEY, business_name TEXT);');
      await legDb.execute('CREATE TABLE IF NOT EXISTS sales (id TEXT PRIMARY KEY, total_amount REAL);');
      await legDb.close();

      // 3. Hedef Core Next Veritabanı Oluştur (Şema v3)
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: targetDbPath);
      await coreDb.db.rawQuery('PRAGMA user_version = 3;');

      // app_settings tenant ID kaydet
      await coreDb.db.insert('app_settings', {
        'key': 'tenant_id',
        'value': nutopiaTenantId,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });

      // Test Ürünü Ekle (Fındık Ezmesi 100 TL = 10.000 kuruş, Stok: 20)
      await coreDb.db.insert('products', {
        'id': testProductId,
        'barcode': '8690009901',
        'name': 'Fındık Ezmesi Stage 99',
        'price_cents': 10000,
        'vat_rate': 1,
        'unit': 'piece',
        'stock_quantity': 20,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await coreDb.close();
      if (tempDir.existsSync()) {
        try {
          tempDir.deleteSync(recursive: true);
        } catch (_) {}
      }
    });

    test('1. Motor kapalıyken legacy satış akışı ve sağlayıcıları değişmeden korunur', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        CoreNextBootstrapCoordinator.prefKeyBackupPath: backupPath,
        PilotCutoverGate.prefKeySalesEngineEnabled: false, // Satış motoru kapalı
      });
      final prefs = await SharedPreferences.getInstance();

      final gate = PilotCutoverGate(
        overrideGenerator: ({
          required String requestedTenantId,
          required String legacyDbPath,
          required String targetDbPath,
          required bool enableSalesEngine,
          DatabaseFactory? dbFactory,
        }) async {
          return DualDatabaseRoutingCoordinator.createRepositoryOverrides(
            coreDb: coreDb,
            enableSalesEngine: enableSalesEngine,
          );
        },
      );

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: nutopiaTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
      );

      expect(result.isPilotActive, isTrue);
      expect(result.isSalesEngineActive, isFalse);

      final container = ProviderContainer(overrides: result.overrides);
      addTearDown(container.dispose);

      // Satış motoru bayrağı false olmalıdır
      expect(container.read(coreNextSalesEngineEnabledProvider), isFalse);
      // Executor'lar enjekte edilmemiş (null) olmalıdır
      expect(container.read(coreNextSaleExecutorProvider), isNull);
      expect(container.read(coreNextRefundExecutorProvider), isNull);
      expect(container.read(coreNextSaleRepositoryProvider), isNull);

      // Okuma ve yazma deposu legacy SQLite repo olmalıdır
      final saleRepo = await container.read(saleRepositoryProvider.future);
      expect(saleRepo, isA<SqliteSaleRepository>());
    });

    test('2. Motor açık olarak test ortamında hazırlandığında tüm executor sağlayıcıları başarıyla bağlanır', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        CoreNextBootstrapCoordinator.prefKeyBackupPath: backupPath,
        PilotCutoverGate.prefKeySalesEngineEnabled: true, // Satış motoru açık
      });
      final prefs = await SharedPreferences.getInstance();

      final gate = PilotCutoverGate(
        overrideGenerator: ({
          required String requestedTenantId,
          required String legacyDbPath,
          required String targetDbPath,
          required bool enableSalesEngine,
          DatabaseFactory? dbFactory,
        }) async {
          return DualDatabaseRoutingCoordinator.createRepositoryOverrides(
            coreDb: coreDb,
            enableSalesEngine: enableSalesEngine,
          );
        },
      );

      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: nutopiaTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
      );

      expect(result.isPilotActive, isTrue);
      expect(result.isSalesEngineActive, isTrue);
      expect(result.status, equals(PilotGateStatus.pilotActiveApproved));

      final container = ProviderContainer(overrides: result.overrides);
      addTearDown(container.dispose);

      // Tüm sağlayıcılar başarıyla bağlanmış olmalıdır
      expect(container.read(coreNextSalesEngineEnabledProvider), isTrue);
      expect(container.read(coreNextSaleExecutorProvider), isNotNull);
      expect(container.read(coreNextRefundExecutorProvider), isNotNull);
      expect(container.read(coreNextSaleRepositoryProvider), isNotNull);
      expect(container.read(coreNextSaleRepositoryProvider), isA<CoreNextSaleRepository>());

      // saleRepositoryProvider da otomatik olarak CoreNextSaleRepository dönmelidir
      final saleRepo = await container.read(saleRepositoryProvider.future);
      expect(saleRepo, isA<CoreNextSaleRepository>());
    });

    test('3. Executor bağımlılığı eksik olduğunda satış işlemi fail-closed olarak güvenle durur', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          saleRepositoryProvider.overrideWith(
            (ref) => Future.value(CoreNextSaleRepository.fromCoreAppDatabase(coreDb)),
          ),
          salesServiceProvider.overrideWith(
            (ref) => Future.value(_FakeSalesService()),
          ),
          coreNextSalesEngineEnabledProvider.overrideWith((ref) => true),
          coreNextSaleExecutorProvider.overrideWithValue(null), // Eksik executor
        ],
      );
      addTearDown(container.dispose);

      final controller = container.read(salesControllerProvider.notifier);
      await expectLater(
        controller.createSale(
          customerId: '',
          items: [
            SaleItemInput(productId: testProductId, quantity: 1, unitPrice: 100.0),
          ],
          paymentMethod: 'cash',
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('4. Tenant uyuşmazlığında (Erkul Çeyiz) Core Next satış motoru açılamaz ve fail-closed kalır', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: true,
        CoreNextBootstrapCoordinator.prefKeyMigrationState: 'completed',
        CoreNextBootstrapCoordinator.prefKeyBackupPath: backupPath,
        PilotCutoverGate.prefKeySalesEngineEnabled: true, // Motor açık istense bile
      });
      final prefs = await SharedPreferences.getInstance();

      final gate = PilotCutoverGate(
        overrideGenerator: ({
          required String requestedTenantId,
          required String legacyDbPath,
          required String targetDbPath,
          required bool enableSalesEngine,
          DatabaseFactory? dbFactory,
        }) async {
          return DualDatabaseRoutingCoordinator.createRepositoryOverrides(
            coreDb: coreDb,
            enableSalesEngine: enableSalesEngine,
          );
        },
      );

      // Erkul Çeyiz tenant'ı ile sorgula
      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: erkulTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.isSalesEngineActive, isFalse);
      expect(result.status, equals(PilotGateStatus.blockedTenantMismatch));
      expect(result.overrides, isEmpty);
    });

    test('5. Pilot onayı olmadan (migration eksik veya bayrak kapalı) satış motoru açılamaz', () async {
      SharedPreferences.setMockInitialValues({
        PilotCutoverGate.prefKeyPilotEnabled: false, // Pilot kapalı
        PilotCutoverGate.prefKeySalesEngineEnabled: true, // Satış motoru açık istense bile
      });
      final prefs = await SharedPreferences.getInstance();

      const gate = PilotCutoverGate();
      final result = await gate.evaluate(
        prefs: prefs,
        requestedTenantId: nutopiaTenantId,
        legacyDbPath: legacyDbPath,
        targetDbPath: targetDbPath,
      );

      expect(result.isPilotActive, isFalse);
      expect(result.isSalesEngineActive, isFalse);
      expect(result.status, equals(PilotGateStatus.disabledByDefault));
      expect(result.overrides, isEmpty);
    });

    test('6. Satış motoru devredeyken satış, stok, ödeme ve müşteri defteri tek ve aynı Core Next DB kullanır', () async {
      final overrides = DualDatabaseRoutingCoordinator.createRepositoryOverrides(
        coreDb: coreDb,
        enableSalesEngine: true,
      );
      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);

      final saleRepo = await container.read(saleRepositoryProvider.future);
      final customerRepo = await container.read(customerRepositoryProvider.future);
      final productRepo = await container.read(productRepositoryProvider.future);
      final financialRepo = await container.read(financialTransactionRepositoryProvider.future);

      expect(saleRepo, isA<CoreNextSaleRepository>());
      expect(customerRepo, isA<CoreNextCustomerRepository>());
      expect(productRepo, isA<CoreNextProductRepository>());
      expect(financialRepo, isA<CoreNextFinancialTransactionRepository>());
    });

    test('7. Bağlanan gerçek runtime executor üzerinden satış yapılır, stok ve tablolar doğru güncellenir', () async {
      final overrides = DualDatabaseRoutingCoordinator.createRepositoryOverrides(
        coreDb: coreDb,
        enableSalesEngine: true,
      );
      final container = ProviderContainer(overrides: overrides);
      addTearDown(container.dispose);

      final executor = container.read(coreNextSaleExecutorProvider);
      expect(executor, isNotNull);

      // Satış icra et: 2 adet Fındık Ezmesi (200 TL = 20.000 kuruş)
      final sale = await executor!(
        customerId: '',
        items: [
          SaleItemInput(
            productId: testProductId,
            productName: 'Fındık Ezmesi Stage 99',
            quantity: 2,
            unitPrice: 100.0,
          ),
        ],
        paymentMethod: 'cash',
        paidAmount: 200.0,
        cashierName: 'Ahmet Kasiyer',
        userId: 'usr-ahmet-99',
        userRole: 'cashier',
      );

      expect(sale, isNotNull);
      expect(sale!.totalAmount, equals(200.0));

      // Stok 20 - 2 = 18 olmalı
      final prodRows = await coreDb.query('products', where: 'id = ?', whereArgs: [testProductId]);
      expect(prodRows.first['stock_quantity'], equals(18));

      // Satış ve ödeme tabloları Core Next içinde kayıtlı olmalı
      final salesRows = await coreDb.query('sales');
      expect(salesRows.length, equals(1));
      expect(salesRows.first['total_cents'], equals(20000));
      expect(salesRows.first['status'], equals('COMPLETED'));

      final payRows = await coreDb.query('sale_payments');
      expect(payRows.length, equals(1));
      expect(payRows.first['payment_type'], equals('cash'));
      expect(payRows.first['amount_cents'], equals(20000));
    });
  });
}

class _FakeSalesService extends Fake implements SalesService {}
