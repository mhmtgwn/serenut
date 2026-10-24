// core_next/client_core/lib/presentation/di/core_providers.dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../infrastructure/database/app_database.dart';
import '../../infrastructure/repositories/sqlite_ledger_repository.dart';
import '../../infrastructure/repositories/sqlite_product_repository.dart';
import '../../domain/services/ledger_service.dart';
import '../../domain/usecases/checkout_use_case.dart';
import '../../infrastructure/hardware/hardware_worker.dart';
import '../sales/core_sales_flow_notifier.dart';
import '../sales/core_sales_flow_state.dart';
import '../../infrastructure/sync/sync_v4_pull_ingestion_service.dart';
import '../../infrastructure/sync/sync_v4_http_client.dart';
import '../../infrastructure/sync/sync_v4_pull_worker.dart';
import '../sales/sales_engine_adapter.dart';

/// ── PRE-WARMED SENKRON RIVERPOD CONTAINER ──────────────────────────────────
/// 
/// Eski sistemdeki zincirleme `FutureProvider` ve `AsyncValue.loading` krizini
/// kalıcı olarak bitirir. Veritabanı ve temel disk bağlantıları `main()` içinde
/// pre-warm edilip buraya enjekte edilir.
/// UI bileşenleri veriyi beklemez; veri her zaman anında hazırdır.

/// Veritabanı kök sağlayıcısı (Açılışta override edilir)
final coreDatabaseProvider = Provider<CoreAppDatabase>((ref) {
  throw UnimplementedError(
    'coreDatabaseProvider açılışta overrideWithValue ile beslenmelidir.',
  );
});

/// Cari & Defter Repository Sağlayıcısı (Senkron)
final coreLedgerRepositoryProvider = Provider<SqliteLedgerRepository>((ref) {
  final db = ref.watch(coreDatabaseProvider);
  return SqliteLedgerRepository(db.db);
});

/// Ürün Kataloğu Repository Sağlayıcısı (Senkron)
final coreProductRepositoryProvider = Provider<SqliteProductRepository>((ref) {
  final db = ref.watch(coreDatabaseProvider);
  return SqliteProductRepository(db.db);
});

/// Çift Taraflı Defter Motoru Sağlayıcısı (Senkron Domain Service)
final coreLedgerServiceProvider = Provider<LedgerService>((ref) {
  final ledgerRepo = ref.watch(coreLedgerRepositoryProvider);
  return LedgerService(ledgerRepo);
});

/// Donanım Isolate Yöneticisi Sağlayıcısı
final coreHardwareWorkerProvider = Provider<HardwareWorker>((ref) {
  final worker = HardwareWorker();
  worker.initialize();
  ref.onDispose(() => worker.dispose());
  return worker;
});

/// Atomik Satış Use-Case Sağlayıcısı
final coreCheckoutUseCaseProvider = Provider<CoreCheckoutUseCase>((ref) {
  final db = ref.watch(coreDatabaseProvider);
  final ledgerService = ref.watch(coreLedgerServiceProvider);
  final hardwareWorker = ref.watch(coreHardwareWorkerProvider);
  return CoreCheckoutUseCase(
    db: db,
    ledgerService: ledgerService,
    hardwareWorker: hardwareWorker,
  );
});

/// Kasa Satış ve Sepet Akışı Durum Yöneticisi (Senkron StateNotifier)
final coreSalesFlowProvider =
    StateNotifierProvider<CoreSalesFlowNotifier, CoreSalesFlowState>((ref) {
  final checkoutUseCase = ref.watch(coreCheckoutUseCaseProvider);
  return CoreSalesFlowNotifier(checkoutUseCase);
});

/// Yerel Cihaz Kimliği Sağlayıcısı (Kasa / Terminal Kimliği)
final coreDeviceIdProvider = Provider<String>((ref) {
  throw UnimplementedError(
    'coreDeviceIdProvider açılışta overrideWithValue ile beslenmelidir.',
  );
});

/// Sync V4 Pull Ingestion Servisi Sağlayıcısı (Senkron DI)
final coreSyncPullIngestionServiceProvider = Provider<SyncV4PullIngestionService>((ref) {
  final db = ref.watch(coreDatabaseProvider);
  final deviceId = ref.watch(coreDeviceIdProvider);
  return SyncV4PullIngestionService(db, localDeviceId: deviceId);
});

/// Sync V4 HTTP İstemcisi Sağlayıcısı (Açılışta lisans ve endpoint ile override edilir)
final coreSyncHttpClientProvider = Provider<SyncV4HttpClient>((ref) {
  throw UnimplementedError(
    'coreSyncHttpClientProvider açılışta overrideWithValue ile beslenmelidir.',
  );
});

/// Sync V4 Pull İşlem Yöneticisi (Worker) Sağlayıcısı
final coreSyncPullWorkerProvider = Provider<SyncV4PullWorker>((ref) {
  final httpClient = ref.watch(coreSyncHttpClientProvider);
  final ingestionService = ref.watch(coreSyncPullIngestionServiceProvider);
  return SyncV4PullWorker(
    httpClient: httpClient,
    ingestionService: ingestionService,
  );
});

/// Satış Motoru Güvenli Adaptör Sağlayıcısı (Varsayılan: useCoreNext = false)
final salesEngineAdapterProvider = Provider<SalesEngineAdapter>((ref) {
  final salesFlowNotifier = ref.watch(coreSalesFlowProvider.notifier);
  return SalesEngineAdapter(
    coreNotifier: salesFlowNotifier,
    initialUseCoreNext: false, // Güvenli varsayılan: legacy motor
  );
});


