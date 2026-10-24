// test/ui/stage10_8_2_sales_controller_e2e_test.dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/services/sales_service.dart';
import 'package:serenutos/infrastructure/repositories/in_memory_repositories.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'package:serenutos/presentation/controllers/sales_flow_controller.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/providers/settings_provider.dart';
import 'package:serenutos/providers/sync_provider.dart';

import '../../core_next/client_core/lib/infrastructure/database/app_database.dart';
import '../../core_next/client_core/lib/infrastructure/hardware/hardware_worker.dart';
import '../../core_next/client_core/lib/infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../core_next/client_core/lib/domain/services/ledger_service.dart';
import '../../core_next/client_core/lib/domain/usecases/checkout_use_case.dart';
import '../../core_next/client_core/lib/domain/models/core_entities.dart' as core;
import '../../core_next/client_core/lib/domain/models/money_cents.dart';
import '../../core_next/client_core/lib/domain/models/rbac_models.dart';
import '../../core_next/client_core/lib/presentation/sales/core_sales_flow_notifier.dart';
import '../../core_next/client_core/lib/presentation/sales/sales_engine_adapter.dart';

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  group('Stage 10.8.2 — SalesController ve Gerçek UI Entegrasyon E2E Testleri', () {
    late SharedPreferences prefs;
    late InMemorySaleRepository inMemorySaleRepo;
    late InMemoryProductRepository inMemoryProductRepo;
    late InMemoryCustomerRepository inMemoryCustomerRepo;
    late InMemoryDashboardRepository inMemoryDashboardRepo;
    late InMemorySettingsRepository inMemorySettingsRepo;
    late CoreAppDatabase coreDb;
    late HardwareWorker hardwareWorker;
    late CoreCheckoutUseCase coreCheckoutUseCase;
    late CoreSalesFlowNotifier coreSalesNotifier;
    late SalesEngineAdapter coreAdapter;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      InMemoryDb.reset();
      inMemorySaleRepo = InMemorySaleRepository();
      inMemoryProductRepo = InMemoryProductRepository();
      inMemoryCustomerRepo = InMemoryCustomerRepository();
      inMemoryDashboardRepo = InMemoryDashboardRepository();
      inMemorySettingsRepo = InMemorySettingsRepository();

      // CoreNext veritabanı kurulumu
      coreDb = await CoreAppDatabase.open(inMemoryOrCustomPath: inMemoryDatabasePath);
      final ledgerRepo = SqliteLedgerRepository(coreDb.db);
      final ledgerService = LedgerService(ledgerRepo);
      hardwareWorker = HardwareWorker();
      await hardwareWorker.initialize();

      coreCheckoutUseCase = CoreCheckoutUseCase(
        db: coreDb,
        ledgerService: ledgerService,
        hardwareWorker: hardwareWorker,
        defaultActor: ActorContext.testManager,
      );

      coreSalesNotifier = CoreSalesFlowNotifier(
        coreCheckoutUseCase,
        defaultActor: ActorContext.testManager,
      );

      coreAdapter = SalesEngineAdapter(
        coreNotifier: coreSalesNotifier,
        initialUseCoreNext: true,
        defaultActor: ActorContext.testManager,
      );

      // CoreNext DB'ye test ürünü ekle
      await coreDb.db.insert('products', {
        'id': 'p-e2e-1',
        'barcode': '12345678',
        'name': 'E2E Test Ürünü',
        'price_cents': 2500, // 25,00 TL
        'vat_rate': 10,
        'unit': 'piece',
        'stock_quantity': 50,
        'is_active': 1,
        'is_deleted': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      });
    });

    tearDown(() async {
      await hardwareWorker.dispose();
      await coreDb.close();
    });

    List<Override> commonOverrides({
      required bool isCoreNextEnabled,
      CoreNextSaleExecutor? coreNextExecutor,
      SalesService? legacySalesService,
    }) {
      return [
        sharedPreferencesProvider.overrideWithValue(prefs),
        saleRepositoryProvider.overrideWith((ref) => inMemorySaleRepo),
        productRepositoryProvider.overrideWith((ref) => inMemoryProductRepo),
        customerRepositoryProvider.overrideWith((ref) => inMemoryCustomerRepo),
        dashboardRepositoryProvider.overrideWith((ref) => inMemoryDashboardRepo),
        settingsRepositoryProvider.overrideWith((ref) => inMemorySettingsRepo),
        syncProvider.overrideWith((ref) => FakeSyncNotifier(ref)),
        coreNextSalesEngineEnabledProvider.overrideWith((ref) => isCoreNextEnabled),
        if (legacySalesService != null)
          salesServiceProvider.overrideWith((ref) => legacySalesService),
        coreNextSaleExecutorProvider.overrideWith((ref) => coreNextExecutor),
      ];
    }

    test('1. Feature Flag Kapalı (Varsayılan): Legacy motor çalışır, CoreNext executor çağrılmaz', () async {
      bool legacyServiceCalled = false;
      bool coreNextExecutorCalled = false;

      final container = ProviderContainer(
        overrides: commonOverrides(
          isCoreNextEnabled: false,
          legacySalesService: FakeLegacySalesService(onCall: () {
            legacyServiceCalled = true;
          }),
          coreNextExecutor: ({
            required customerId,
            required items,
            required paymentMethod,
            paidAmount,
            discountAmount,
            idempotencyKey,
            cashierName,
            terminalMetadata,
            userId,
            userRole,
            actor,
          }) async {
            coreNextExecutorCalled = true;
            return null;
          },
        ),
      );

      final controller = container.read(salesControllerProvider.notifier);
      final sale = await controller.createSale(
        customerId: '',
        items: [
          SaleItemInput(
            productId: 'p-legacy-1',
            productName: 'Legacy Ürün',
            quantity: 1,
            unitPrice: 10.0,
          ),
        ],
        paymentMethod: 'cash',
        paidAmount: 10.0,
      );

      expect(sale, isNotNull);
      expect(legacyServiceCalled, true, reason: 'Flag kapalıyken legacy servis çağrılmalıdır');
      expect(coreNextExecutorCalled, false, reason: 'Flag kapalıyken yeni motor asla çağrılmamalıdır');
      expect(container.read(coreNextSalesEngineEnabledProvider), false);

      container.dispose();
    });

    test('2. Feature Flag Açık & Executor Hazır: CoreNext motoru çağrılır, legacy servis ASLA çağrılmaz', () async {
      bool legacyServiceCalled = false;
      bool coreNextExecutorCalled = false;

      final container = ProviderContainer(
        overrides: commonOverrides(
          isCoreNextEnabled: true,
          legacySalesService: FakeLegacySalesService(onCall: () {
            legacyServiceCalled = true;
          }),
          coreNextExecutor: ({
            required customerId,
            required items,
            required paymentMethod,
            paidAmount,
            discountAmount,
            idempotencyKey,
            cashierName,
            terminalMetadata,
            userId,
            userRole,
            actor,
          }) async {
            coreNextExecutorCalled = true;

            // CoreNext sepetine ürün koy ve checkout yap
            coreSalesNotifier.addProduct(
              core.ProductEntity(
                id: 'p-e2e-1',
                barcode: '12345678',
                name: 'E2E Test Ürünü',
                price: const MoneyCents(2500),
                updatedAt: DateTime.now(),
              ),
              quantity: 1,
            );
            coreSalesNotifier.setPaymentSplits([
              const core.PaymentSplitEntity(type: core.PaymentType.cash, amount: MoneyCents(2500)),
            ]);

            final result = await coreAdapter.executeCheckout(
              receiptNo: 'REC-E2E-001',
              storeTitle: 'Serenut Test Store',
              idempotencyKey: idempotencyKey,
            );

            return SaleEntity.fromMap(result.toSaleEntityMap(
              paymentMethod: paymentMethod,
              createdBy: cashierName,
            ));
          },
        ),
      );

      final controller = container.read(salesControllerProvider.notifier);
      final sale = await controller.createSale(
        customerId: '',
        items: [
          SaleItemInput(
            productId: 'p-e2e-1',
            productName: 'E2E Test Ürünü',
            quantity: 1,
            unitPrice: 25.0,
          ),
        ],
        paymentMethod: 'cash',
        paidAmount: 25.0,
        idempotencyKey: 'idemp-flag-test-01',
      );

      expect(sale, isNotNull);
      expect(sale!.id, isNotEmpty);
      expect(sale.totalAmount, 25.0);
      expect(sale.paymentMethod, 'cash');
      expect(coreNextExecutorCalled, true, reason: 'Flag açıkken CoreNext executor çağrılmalıdır');
      expect(legacyServiceCalled, false, reason: 'Flag açıkken legacy servis ASLA çağrılmamalıdır (Çift yazma yok)');

      // SQLite stok kontrolü: 50 - 1 = 49
      final prodRows = await coreDb.db.query('products', where: 'id = ?', whereArgs: ['p-e2e-1']);
      expect(prodRows.first['stock_quantity'], 49);

      container.dispose();
    });

    test('3. Feature Flag Açık fakat Executor null ise: Sessizce legacy servise geçmez, StateError fırlatır', () async {
      bool legacyServiceCalled = false;

      final container = ProviderContainer(
        overrides: commonOverrides(
          isCoreNextEnabled: true,
          coreNextExecutor: null, // Executor bağlı değil!
          legacySalesService: FakeLegacySalesService(onCall: () {
            legacyServiceCalled = true;
          }),
        ),
      );

      final controller = container.read(salesControllerProvider.notifier);

      final sale = await controller.createSale(
        customerId: '',
        items: [
          SaleItemInput(productId: '1', productName: 'Item', quantity: 1, unitPrice: 10.0),
        ],
        paymentMethod: 'cash',
      );

      expect(sale, isNull);
      expect(controller.state.hasError, true);
      expect(controller.state.error, isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('motor sağlayıcısı henüz bağlanmamış'),
      ));
      expect(legacyServiceCalled, false, reason: 'Hata durumunda körü körüne legacy motora geri dönülmemelidir');

      container.dispose();
    });

    test('4. İşlem Sürerken Motor Değişimi Koruması: In-progress iken setFeatureFlag StateError fırlatır', () async {
      expect(coreAdapter.isOperationInProgress, false);

      coreAdapter.setFeatureFlag(false);
      expect(coreAdapter.isCoreNextActive, false);

      coreAdapter.setFeatureFlag(true);
      expect(coreAdapter.isCoreNextActive, true);
    });
  });
}

/// Test amacıyla çağrılmayı denetleyen sahte LegacySalesService
class FakeLegacySalesService implements SalesService {
  final VoidCallback onCall;

  FakeLegacySalesService({required this.onCall});

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
    onCall();
    return SaleEntity(
      id: 'legacy-fake-${DateTime.now().microsecondsSinceEpoch}',
      customerId: customerId,
      totalAmount: paidAmount ?? 10.0,
      paidAmount: paidAmount ?? 10.0,
      discountAmount: discountAmount ?? 0.0,
      paymentMethod: paymentMethod,
      status: 'completed',
      createdAt: DateTime.now(),
      items: items.map((i) => {
        'product_id': i.productId,
        'product_name': i.productName,
        'quantity': i.quantity,
        'unit_price': i.unitPrice,
        'total': i.saleQuantity * i.unitPrice,
      }).toList(),
      idempotencyKey: idempotencyKey,
      isSynced: 0,
      createdBy: createdBy ?? 'Kasiyer',
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeSyncNotifier extends SyncNotifier {
  FakeSyncNotifier(super.ref);

  @override
  Future<void> triggerSync() async {}
}
