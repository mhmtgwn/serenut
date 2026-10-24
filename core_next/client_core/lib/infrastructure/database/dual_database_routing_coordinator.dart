// core_next/client_core/lib/infrastructure/database/dual_database_routing_coordinator.dart
// SERENUT OS — STAGE 10.12.24
// Çift Veritabanı Mimarisi ve Güvenli Core Next Yönlendirme Koordinatörü

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/providers/repository_providers.dart';
import 'package:serenutos/presentation/controllers/sales_controller.dart';
import 'app_database.dart';
import 'database_routing_resolver.dart';
import '../repositories/core_next_customer_repository.dart';
import '../repositories/core_next_product_repository.dart';
import '../repositories/core_next_financial_transaction_repository.dart';
import '../repositories/core_next_sale_repository.dart';
import '../sales/core_next_sales_bridge.dart';
import '../hardware/hardware_worker.dart';
import '../../presentation/sales/core_sales_flow_notifier.dart';
import '../../presentation/sales/sales_engine_adapter.dart';
import '../../domain/usecases/checkout_use_case.dart';
import '../../domain/usecases/refund_use_case.dart';
import '../../domain/services/ledger_service.dart';
import '../repositories/sqlite_ledger_repository.dart';
import '../repositories/sqlite_product_repository.dart';

/// Çift Veritabanı Yönlendirme Karar ve Bağlantı Çıktısı
class DualDatabaseRoutingResult {
  final RoutingDecision decision;
  final String resolvedPath;
  final String reason;
  final bool isTargetSelected;
  final CoreAppDatabase? targetDatabase;

  const DualDatabaseRoutingResult({
    required this.decision,
    required this.resolvedPath,
    required this.reason,
    required this.isTargetSelected,
    this.targetDatabase,
  });

  bool get isSuccess => isTargetSelected && targetDatabase != null;

  @override
  String toString() =>
      'DualDatabaseRoutingResult(decision: $decision, path: $resolvedPath, isTargetSelected: $isTargetSelected, hasTargetDb: ${targetDatabase != null})';
}

/// Çift Veritabanı Yönlendirme Koordinatörü
/// 
/// Sorumlulukları:
/// 1. [DatabaseRoutingResolver] aracılığıyla hedef veritabanını doğrular.
/// 2. Göç tamamlanmamışsa veya güvenlik ihlali varsa hedef DB'yi ASLA açmaz.
/// 3. Yalnızca [RoutingDecision.targetSelected] durumunda hedefi [CoreAppDatabase.open] ile açar.
/// 4. Riverpod üzerinde UI controller'larının doğru Core Next repository'lerine bağlanması için
///    güvenli provider override listesi üretir.
/// 5. Satış motoru [enableSalesEngine] bayrağı `false` kaldığı sürece satış reposunu
///    asla Core Next'e geçirmez; legacy akışı %100 korur.
class DualDatabaseRoutingCoordinator {
  final DatabaseRoutingResolver _resolver;

  const DualDatabaseRoutingCoordinator({
    DatabaseRoutingResolver resolver = const DatabaseRoutingResolver(),
  }) : _resolver = resolver;

  /// Veritabanı yönlendirmesini çözümler ve yalnızca hedef onaylandığında CoreAppDatabase açar.
  Future<DualDatabaseRoutingResult> resolveAndOpen({
    required String requestedTenantId,
    required String legacyDbPath,
    String? targetDbPath,
    bool migrationStateCompleted = false,
    DatabaseFactory? dbFactory,
  }) async {
    final resolution = await _resolver.resolve(
      requestedTenantId: requestedTenantId,
      legacyDbPath: legacyDbPath,
      targetDbPath: targetDbPath,
      migrationStateCompleted: migrationStateCompleted,
      dbFactory: dbFactory,
    );

    if (resolution.decision != RoutingDecision.targetSelected) {
      return DualDatabaseRoutingResult(
        decision: resolution.decision,
        resolvedPath: resolution.resolvedPath,
        reason: resolution.reason,
        isTargetSelected: false,
        targetDatabase: null,
      );
    }

    try {
      final coreDb = await CoreAppDatabase.open(
        inMemoryOrCustomPath: resolution.resolvedPath,
      );

      return DualDatabaseRoutingResult(
        decision: resolution.decision,
        resolvedPath: resolution.resolvedPath,
        reason: resolution.reason,
        isTargetSelected: true,
        targetDatabase: coreDb,
      );
    } catch (e) {
      return DualDatabaseRoutingResult(
        decision: RoutingDecision.blockedFailClosed,
        resolvedPath: legacyDbPath,
        reason: 'Hedef CoreAppDatabase açılış hatası (fail-closed): $e',
        isTargetSelected: false,
        targetDatabase: null,
      );
    }
  }

  /// Doğrulanmış ve açılmış [CoreAppDatabase] için Riverpod repository override'larını üretir.
  static List<Override> createRepositoryOverrides({
    required CoreAppDatabase coreDb,
    bool enableSalesEngine = false,
  }) {
    return [
      coreNextCustomerRepositoryProvider.overrideWithValue(
        CoreNextCustomerRepository.fromCoreAppDatabase(coreDb),
      ),
      coreNextProductRepositoryProvider.overrideWithValue(
        CoreNextProductRepository.fromCoreAppDatabase(coreDb),
      ),
      coreNextFinancialTransactionRepositoryProvider.overrideWithValue(
        CoreNextFinancialTransactionRepository.fromCoreAppDatabase(coreDb),
      ),
      if (enableSalesEngine) ...[
        coreNextSaleRepositoryProvider.overrideWithValue(
          CoreNextSaleRepository.fromCoreAppDatabase(coreDb),
        ),
        coreNextSalesEngineEnabledProvider.overrideWith((ref) => true),
        coreNextSaleExecutorProvider.overrideWith((ref) {
          final ledgerRepo = SqliteLedgerRepository(coreDb.db);
          final productRepo = SqliteProductRepository(coreDb.db);
          final ledgerService = LedgerService(ledgerRepo);
          final hardwareWorker = HardwareWorker();
          final checkoutUseCase = CoreCheckoutUseCase(
            db: coreDb,
            ledgerService: ledgerService,
            hardwareWorker: hardwareWorker,
          );
          final salesFlowNotifier = CoreSalesFlowNotifier(checkoutUseCase);
          final adapter = SalesEngineAdapter(
            coreNotifier: salesFlowNotifier,
            initialUseCoreNext: true,
          );
          return CoreNextSalesBridge.createSaleExecutor(
            checkoutUseCase: checkoutUseCase,
            productRepo: productRepo,
            adapter: adapter,
            coreDb: coreDb,
          );
        }),
        coreNextRefundExecutorProvider.overrideWith((ref) {
          final ledgerRepo = SqliteLedgerRepository(coreDb.db);
          final ledgerService = LedgerService(ledgerRepo);
          final refundUseCase = CoreRefundUseCase(
            db: coreDb,
            ledgerService: ledgerService,
          );
          return CoreNextSalesBridge.createRefundExecutor(
            refundUseCase: refundUseCase,
          );
        }),
      ],
    ];
  }
}
