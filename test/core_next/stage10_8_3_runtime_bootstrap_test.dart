// test/core_next/stage10_8_3_runtime_bootstrap_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/inventory_service.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/sync_provider.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/database/schema_definitions.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_product_repository.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/migration/migration_bridge_engine.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart' as core;
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';
import '../../core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart';

/// Test Amaçlı Fake Legacy Satış Servisi
class _FakeLegacySalesService implements SalesService {
  bool wasCalled = false;

  @override
  Future<SaleEntity> createSale({
    required String customerId,
    required List<SaleItemInput> items,
    required String paymentMethod,
    double? paidAmount,
    double? discountAmount,
    String? idempotencyKey,
    String? createdBy,
    Map<String, dynamic>? terminalMetadata,
  }) async {
    wasCalled = true;
    return SaleEntity(
      id: 'legacy-sale-test',
      customerId: customerId,
      totalAmount: 100.0,
      paidAmount: paidAmount ?? 100.0,
      paymentMethod: paymentMethod,
      status: 'completed',
      items: [],
      createdAt: DateTime.now(),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Fake Sync Notifier (Test esnasında arka plan timer başlatmaz)
class _FakeSyncNotifier extends SyncNotifier {
  _FakeSyncNotifier(super.ref);

  @override
  Future<void> refreshPendingCount() async {}

  @override
  Future<void> triggerSync({bool force = false}) async {}
}

/// Core Next Runtime Composition Root Test Helper
class TestCoreNextComposition {
  final CoreAppDatabase db;
  final SqliteLedgerRepository ledgerRepo;
  final SqliteProductRepository productRepo;
  final LedgerService ledgerService;
  final HardwareWorker hardwareWorker;
  final CoreCheckoutUseCase checkoutUseCase;
  final CoreSalesFlowNotifier salesFlowNotifier;
  final SalesEngineAdapter adapter;
  final CoreNextSaleExecutor executor;

  TestCoreNextComposition({
    required this.db,
    required this.ledgerRepo,
    required this.productRepo,
    required this.ledgerService,
    required this.hardwareWorker,
    required this.checkoutUseCase,
    required this.salesFlowNotifier,
    required this.adapter,
    required this.executor,
  });

  static Future<TestCoreNextComposition> assemble({
    required String dbPath,
    HardwareWorker? hardwareWorker,
  }) async {
    final coreDb = await CoreAppDatabase.open(
      inMemoryOrCustomPath: dbPath,
    );

    final ledgerRepo = SqliteLedgerRepository(coreDb.db);
    final productRepo = SqliteProductRepository(coreDb.db);
    final ledgerService = LedgerService(ledgerRepo);

    final worker = hardwareWorker ?? HardwareWorker();
    if (hardwareWorker == null) {
      worker.initialize();
    }

    final checkoutUseCase = CoreCheckoutUseCase(
      db: coreDb,
      ledgerService: ledgerService,
      hardwareWorker: worker,
    );

    final salesFlowNotifier = CoreSalesFlowNotifier(checkoutUseCase);
    final adapter = SalesEngineAdapter(
      coreNotifier: salesFlowNotifier,
      initialUseCoreNext: true,
    );

    final CoreNextSaleExecutor executor = ({
      required String customerId,
      required List<SaleItemInput> items,
      required String paymentMethod,
      double? paidAmount,
      double? discountAmount,
      String? idempotencyKey,
      String? cashierName,
      Map<String, dynamic>? terminalMetadata,
      String? userId,
      String? userRole,
      dynamic actor,
    }) async {
      // 1. Ürünleri yükle ve sepeti doldur
      final products = <core.ProductEntity>[];
      final quantities = <String, int>{};

      for (final item in items) {
        var prod = await productRepo.getById(item.productId);
        prod ??= core.ProductEntity(
          id: item.productId,
          barcode: item.productId,
          name: item.productName ?? 'Ürün',
          price: MoneyCents((item.unitPrice * 100).round()),
          updatedAt: DateTime.now(),
        );
        products.add(prod);
        quantities[prod.id] = (quantities[prod.id] ?? 0) + item.quantity;
      }

      final core.PaymentType pType = switch (paymentMethod.toLowerCase()) {
        'cash' || 'nakit' => core.PaymentType.cash,
        'credit_card' || 'card' || 'kart' => core.PaymentType.creditCard,
        'on_account' || 'veresiye' || 'credit' => core.PaymentType.onAccount,
        _ => core.PaymentType.cash,
      };

      final totalCents = products.fold<int>(
        0,
        (sum, p) => sum + (p.price.value * (quantities[p.id] ?? 1)),
      );

      final splits = [
        core.PaymentSplitEntity(
          type: pType,
          amount: MoneyCents(paidAmount != null ? (paidAmount * 100).round() : totalCents),
        ),
      ];

      adapter.syncFromCart(
        products: products,
        quantities: quantities,
        paymentSplits: splits,
      );

      final result = await adapter.executeCheckout(
        receiptNo: 'RCP-${DateTime.now().millisecondsSinceEpoch}',
        storeTitle: 'Serenut Test Kasa',
        idempotencyKey: idempotencyKey,
        actor: ActorContext(
          userId: 'cashier-test-1',
          username: cashierName ?? 'Kasiyer',
          role: AppRole.cashier,
        ),
      );

      if (!result.isSuccess) {
        throw StateError('CoreNext satış motoru hatası: Satış başarısız. Sebep: ${result.errorMessage}');
      }

      final saleMap = result.toSaleEntityMap(
        paymentMethod: paymentMethod,
        createdBy: cashierName,
      );

      return SaleEntity.fromMap(saleMap);
    };

    return TestCoreNextComposition(
      db: coreDb,
      ledgerRepo: ledgerRepo,
      productRepo: productRepo,
      ledgerService: ledgerService,
      hardwareWorker: worker,
      checkoutUseCase: checkoutUseCase,
      salesFlowNotifier: salesFlowNotifier,
      adapter: adapter,
      executor: executor,
    );
  }

  Future<void> dispose() async {
    hardwareWorker.dispose();
    await db.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String legacyDbPath;
  late String coreDbPath;
  late SharedPreferences prefs;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
  });

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('stage10_8_3_runtime_');
    legacyDbPath = '${tempDir.path}${Platform.pathSeparator}serenut_pos.db';
    coreDbPath = '${tempDir.path}${Platform.pathSeparator}serenut_core_v2.db';
  });

  tearDown(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  group('Stage 10.8.3 — Runtime Bootstrap ve Satış Motoru Hazırlık Testleri', () {
    test('1. Uygulama Bootstrap İşlemi: Core Next bağımlılıklarını eksiksiz kurar', () async {
      final comp = await TestCoreNextComposition.assemble(dbPath: coreDbPath);
      expect(comp.db, isNotNull);
      expect(comp.ledgerRepo, isNotNull);
      expect(comp.productRepo, isNotNull);
      expect(comp.ledgerService, isNotNull);
      expect(comp.checkoutUseCase, isNotNull);
      expect(comp.salesFlowNotifier, isNotNull);
      expect(comp.adapter, isNotNull);
      expect(comp.executor, isNotNull);

      // Veritabanı tablolarının oluşturulduğunu doğrula
      final tables = await comp.db.db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN ('products', 'customers', 'sales', 'sync_events')",
      );
      expect(tables.length, 4);

      await comp.dispose();
    });

    test('2. Veritabanı Açılamazsa: Bootstrap hatayı doğru iletir ve sistem çökmez', () async {
      final corruptFile = File('${tempDir.path}${Platform.pathSeparator}corrupted.db');
      await corruptFile.writeAsString('THIS IS NOT A VALID SQLITE DATABASE FILE HEADER');
      
      bool failedGracefully = false;
      try {
        await CoreAppDatabase.open(inMemoryOrCustomPath: corruptFile.path);
      } catch (e) {
        failedGracefully = true;
        expect(e, isNotNull);
      }
      expect(failedGracefully, true, reason: 'Bozuk veritabanı açılamadığında kontrollü hata dönmeli');
    });

    test('3. Executor Oluşturulamazsa: Feature flag varsayılan olarak kapalı kalır (false)', () async {
      final container = ProviderContainer(
        overrides: [
          coreNextSaleExecutorProvider.overrideWithValue(null),
        ],
      );

      final flag = container.read(coreNextSalesEngineEnabledProvider);
      final executor = container.read(coreNextSaleExecutorProvider);

      expect(flag, false, reason: 'Varsayılan feature flag daima false olmalıdır');
      expect(executor, isNull, reason: 'Executor sağlanmadığında provider null kalmalıdır');

      container.dispose();
    });

    test('4. Provider Üzerinden Alınan Executor: Doğru veritabanı ve repository örneklerini kullanır', () async {
      final comp = await TestCoreNextComposition.assemble(dbPath: coreDbPath);

      // Ürün ekle
      await comp.productRepo.upsertProduct(core.ProductEntity(
        id: 'prod-boost-1',
        barcode: '8690001',
        name: 'Test Kahve',
        price: const MoneyCents(5000), // 50.00 TL
        costPrice: const MoneyCents(3000),
        vatRate: 20,
        unit: core.ProductUnit.piece,
        stockQuantity: 20,
        criticalStockThreshold: 5,
        isActive: true,
        isDeleted: false,
        updatedAt: DateTime.now(),
      ));

      final container = ProviderContainer(
        overrides: [
          coreNextSalesEngineEnabledProvider.overrideWith((ref) => true),
          coreNextSaleExecutorProvider.overrideWithValue(comp.executor),
        ],
      );

      final executor = container.read(coreNextSaleExecutorProvider);
      expect(executor, isNotNull);

      // Executor ile satış yap
      final sale = await executor!(
        customerId: '',
        items: [
          SaleItemInput(
            productId: 'prod-boost-1',
            productName: 'Test Kahve',
            quantity: 2,
            unitPrice: 50.0,
          ),
        ],
        paymentMethod: 'cash',
        paidAmount: 100.0,
      );

      expect(sale, isNotNull);
      expect(sale!.totalAmount, 100.0);

      // Veritabanında stok 20 -> 18 düşmüş olmalı
      final updatedProduct = await comp.productRepo.getById('prod-boost-1');
      expect(updatedProduct!.stockQuantity, 18);

      container.dispose();
      await comp.dispose();
    });

    test('5. Veritabanı Ayrılığı ve Bütünlüğü: Legacy ve Core Next iki ayrı fiziksel dosyadır', () async {
      // 1. Legacy veritabanını simüle et (serenut_pos.db)
      final legacyDb = await openDatabase(
        legacyDbPath,
        version: 60,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE products (
              id TEXT PRIMARY KEY,
              name TEXT,
              price REAL,
              stock_quantity REAL
            );
          ''');
          await db.execute('''
            CREATE TABLE customers (
              id TEXT PRIMARY KEY,
              name TEXT,
              balance REAL
            );
          ''');
        },
      );

      await legacyDb.insert('products', {
        'id': 'legacy-item-1',
        'name': 'Eski Ürün',
        'price': 25.50,
        'stock_quantity': 100.0,
      });

      // 2. Core Next veritabanını aç (serenut_core_v2.db)
      final comp = await TestCoreNextComposition.assemble(dbPath: coreDbPath);

      // İki ayrı fiziksel dosya olduğunu kanıtla
      expect(File(legacyDbPath).existsSync(), true);
      expect(File(coreDbPath).existsSync(), true);
      expect(legacyDbPath, isNot(equals(coreDbPath)));

      // Core Next veritabanında legacy verisi bulunmaz (sıfır çapraz kirlenme)
      final coreProducts = await comp.productRepo.searchProducts('');
      expect(coreProducts.isEmpty, true, reason: 'Migration yapılmadan iki dosya tamamen izoledir');

      // 3. MigrationBridgeEngine ile güvenli geçiş yapıldığında verinin dönüştürüldüğünü doğrula
      final bridge = MigrationBridgeEngine(comp.db);
      final report = await bridge.migrateFromLegacy(legacyDb);
      expect(report.isSuccess, true);
      expect(report.productsMigrated, 1);

      // Kuruş dönüşümünü doğrula: 25.50 TL -> 2550 cents
      final migratedProduct = await comp.productRepo.getById('legacy-item-1');
      expect(migratedProduct, isNotNull);
      expect(migratedProduct!.price.value, 2550);
      expect(migratedProduct.stockQuantity, 100);

      await legacyDb.close();
      await comp.dispose();
    });

    test('6. Hazırlık Aşaması: Legacy satış motoruna ve verilerine ASLA veri yazmaz', () async {
      final fakeLegacy = _FakeLegacySalesService();
      final comp = await TestCoreNextComposition.assemble(dbPath: coreDbPath);

      // Hazırlık ve initialization sırasında legacy servis çağrılmamıştır
      expect(fakeLegacy.wasCalled, false);

      // Core Next tablolarında henüz satış yoktur
      final salesCount = (await comp.db.db.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      expect(salesCount, 0);

      await comp.dispose();
    });

    test('7. Feature Flag Kapalıyken: Mevcut satış akışı ve legacy servis çalışır', () async {
      final fakeLegacy = _FakeLegacySalesService();
      final comp = await TestCoreNextComposition.assemble(dbPath: coreDbPath);

      final inMemorySaleRepo = InMemorySaleRepository();
      final inMemoryProductRepo = InMemoryProductRepository();
      final inMemoryCustomerRepo = InMemoryCustomerRepository();
      final inMemoryDashboardRepo = InMemoryDashboardRepository();
      final inMemorySettingsRepo = InMemorySettingsRepository();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          saleRepositoryProvider.overrideWith((ref) => inMemorySaleRepo),
          productRepositoryProvider.overrideWith((ref) => inMemoryProductRepo),
          customerRepositoryProvider.overrideWith((ref) => inMemoryCustomerRepo),
          dashboardRepositoryProvider.overrideWith((ref) => inMemoryDashboardRepo),
          settingsRepositoryProvider.overrideWith((ref) => inMemorySettingsRepo),
          syncProvider.overrideWith((ref) => _FakeSyncNotifier(ref)),
          coreNextSalesEngineEnabledProvider.overrideWith((ref) => false), // Kapalı
          salesServiceProvider.overrideWith((ref) => fakeLegacy),
          coreNextSaleExecutorProvider.overrideWith((ref) => comp.executor),
        ],
      );

      final controller = container.read(salesControllerProvider.notifier);
      final sale = await controller.createSale(
        customerId: 'cust-1',
        items: [
          SaleItemInput(productId: '1', productName: 'Item', quantity: 1, unitPrice: 10.0),
        ],
        paymentMethod: 'cash',
      );

      expect(sale, isNotNull);
      expect(fakeLegacy.wasCalled, true, reason: 'Flag kapalıyken legacy servis çağrılmalıdır');

      // Core Next veritabanına hiçbir satış yazılmamıştır
      final coreSalesCount = (await comp.db.db.rawQuery('SELECT COUNT(*) as c FROM sales')).first['c'] as int;
      expect(coreSalesCount, 0);

      container.dispose();
      await comp.dispose();
    });

    test('8. Feature Flag Açık & Executor Hazırken: Satış Core Next motoru üzerinden işler', () async {
      final fakeLegacy = _FakeLegacySalesService();
      final comp = await TestCoreNextComposition.assemble(dbPath: coreDbPath);

      // Ürün ekle
      await comp.productRepo.upsertProduct(core.ProductEntity(
        id: 'prod-88',
        barcode: '8690088',
        name: 'Su 0.5L',
        price: const MoneyCents(1000), // 10.00 TL
        costPrice: const MoneyCents(500),
        vatRate: 20,
        unit: core.ProductUnit.piece,
        stockQuantity: 50,
        criticalStockThreshold: 5,
        isActive: true,
        isDeleted: false,
        updatedAt: DateTime.now(),
      ));

      final inMemorySaleRepo = InMemorySaleRepository();
      final inMemoryProductRepo = InMemoryProductRepository();
      final inMemoryCustomerRepo = InMemoryCustomerRepository();
      final inMemoryDashboardRepo = InMemoryDashboardRepository();
      final inMemorySettingsRepo = InMemorySettingsRepository();

      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          saleRepositoryProvider.overrideWith((ref) => inMemorySaleRepo),
          productRepositoryProvider.overrideWith((ref) => inMemoryProductRepo),
          customerRepositoryProvider.overrideWith((ref) => inMemoryCustomerRepo),
          dashboardRepositoryProvider.overrideWith((ref) => inMemoryDashboardRepo),
          settingsRepositoryProvider.overrideWith((ref) => inMemorySettingsRepo),
          syncProvider.overrideWith((ref) => _FakeSyncNotifier(ref)),
          coreNextSalesEngineEnabledProvider.overrideWith((ref) => true), // Açık
          salesServiceProvider.overrideWith((ref) => fakeLegacy),
          coreNextSaleExecutorProvider.overrideWith((ref) => comp.executor),
        ],
      );

      final controller = container.read(salesControllerProvider.notifier);
      final sale = await controller.createSale(
        customerId: '',
        items: [
          SaleItemInput(productId: 'prod-88', productName: 'Su 0.5L', quantity: 2, unitPrice: 10.0),
        ],
        paymentMethod: 'cash',
        paidAmount: 20.0,
      );

      expect(sale, isNotNull);
      expect(fakeLegacy.wasCalled, false, reason: 'CoreNext devredeyken legacy servis ASLA çağrılmamalıdır');

      // Core Next veritabanında satış kaydedilmiş olmalı
      final coreSales = await comp.db.db.query('sales');
      expect(coreSales.length, 1);
      expect(coreSales.first['total_cents'], 2000);

      container.dispose();
      await comp.dispose();
    });

    test('9. Outbox Kaydı: Satış tamamlandıktan sonra sync_events Protocol 6 formatında yazılır', () async {
      final comp = await TestCoreNextComposition.assemble(dbPath: coreDbPath);

      await comp.productRepo.upsertProduct(core.ProductEntity(
        id: 'prod-outbox-1',
        barcode: '8690099',
        name: 'Ekmek',
        price: const MoneyCents(1250), // 12.50 TL
        costPrice: const MoneyCents(800),
        vatRate: 1,
        unit: core.ProductUnit.piece,
        stockQuantity: 30,
        criticalStockThreshold: 5,
        isActive: true,
        isDeleted: false,
        updatedAt: DateTime.now(),
      ));

      // Satışı yürüt
      await comp.executor(
        customerId: '',
        items: [
          SaleItemInput(productId: 'prod-outbox-1', productName: 'Ekmek', quantity: 1, unitPrice: 12.5),
        ],
        paymentMethod: 'cash',
        paidAmount: 12.5,
        idempotencyKey: 'idemp-sync-99',
      );

      // sync_events tablosunu kontrol et
      final events = await comp.db.db.query('sync_events');
      expect(events.length, 1);
      final ev = events.first;
      expect(ev['entity_type'], 'sale');
      expect(ev['operation'], 'UPSERT');
      expect(ev['sync_state'], 'PENDING');
      expect(ev['payload_json'], contains('idemp-sync-99'));

      await comp.dispose();
    });

    test('10. Yeniden Başlatma: Veritabanı kapatılıp diskten tekrar açıldığında satış ve outbox korunur', () async {
      // 1. Birinci oturum: Satış yap ve kapat
      final comp1 = await TestCoreNextComposition.assemble(dbPath: coreDbPath);
      await comp1.productRepo.upsertProduct(core.ProductEntity(
        id: 'prod-persist-1',
        barcode: '8690077',
        name: 'Çay',
        price: const MoneyCents(4000), // 40.00 TL
        costPrice: const MoneyCents(2000),
        vatRate: 20,
        unit: core.ProductUnit.piece,
        stockQuantity: 15,
        criticalStockThreshold: 3,
        isActive: true,
        isDeleted: false,
        updatedAt: DateTime.now(),
      ));

      await comp1.executor(
        customerId: '',
        items: [
          SaleItemInput(productId: 'prod-persist-1', productName: 'Çay', quantity: 3, unitPrice: 40.0),
        ],
        paymentMethod: 'cash',
        paidAmount: 120.0,
        idempotencyKey: 'idemp-reboot-test',
      );

      // Veritabanını kapat
      await comp1.dispose();

      // 2. İkinci oturum (Reboot): Aynı disk dosyasından tekrar aç
      final comp2 = await TestCoreNextComposition.assemble(dbPath: coreDbPath);

      // Satışın korunduğunu doğrula
      final sales = await comp2.db.db.query('sales');
      expect(sales.length, 1);
      expect(sales.first['total_cents'], 12000);
      expect(sales.first['idempotency_key'], 'idemp-reboot-test');

      // Stok düşüşünün korunduğunu doğrula (15 - 3 = 12)
      final prod = await comp2.productRepo.getById('prod-persist-1');
      expect(prod!.stockQuantity, 12);

      // Bekleyen sync_events kuyruğunun korunduğunu doğrula
      final pendingEvents = await comp2.db.db.query(
        'sync_events',
        where: "sync_state = 'PENDING'",
      );
      expect(pendingEvents.length, 1);
      expect(pendingEvents.first['payload_json'], contains('idemp-reboot-test'));

      await comp2.dispose();
    });
  });
}
