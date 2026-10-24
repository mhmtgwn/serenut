// lib/providers/repository_providers.dart
// PHASE 0 Day 3 - Repository Dependency Injection
// Riverpod providers for repository access
// Generated: 21 Jun 2026
// Production repositories are SQLite-first. Cross-device replication is owned
// exclusively by Sync V4's transactional outbox and cursor pull loop.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_report_repository.dart';
import 'package:serenutos/domain/services/report_service.dart';
import 'package:serenutos/infrastructure/repositories/dashboard_repository.dart';
import 'package:serenutos/domain/services/dashboard_service.dart';
import 'package:serenutos/domain/services/customer_search_service.dart';
import 'package:serenutos/domain/repositories/i_business_profile_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_business_profile_repository.dart';

// ── Late Sprint Imports (Sprint 7, 8, 9, 10) ──
import 'package:serenutos/infrastructure/repositories/cloud_analytics_repository.dart';
import 'package:serenutos/infrastructure/services/analytics_ws_service.dart';
import 'package:serenutos/infrastructure/repositories/billing_repository.dart';
import 'package:serenutos/infrastructure/repositories/notification_repository.dart';
import 'package:serenutos/infrastructure/repositories/portal_repository.dart';
import 'package:serenutos/infrastructure/services/dataset_loader_service.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_installment_repository.dart';
import 'package:serenutos/providers/service_providers.dart';

// ════════════════════════════════════════════════════════════
// Riverpod Providers
// ════════════════════════════════════════════════════════════

// ── Repository Providers ──
/// Core Next Ürün Deposu Sağlayıcısı (Varsayılan: null)
/// Core Next aktif olduğunda CoreNextProductRepository buraya atanır.
final coreNextProductRepositoryProvider =
    Provider<IProductRepository?>((ref) => null, name: 'coreNextProductRepositoryProvider');

final productRepositoryProvider =
    FutureProvider<IProductRepository>((ref) async {
  final coreRepo = ref.watch(coreNextProductRepositoryProvider);
  if (coreRepo != null) {
    return coreRepo;
  }
  return SqliteProductRepository(
      ref.watch(dbGatewayProvider), ref.watch(datasetLoaderServiceProvider));
});

/// Core Next Müşteri Deposu Sağlayıcısı (Varsayılan: null)
/// Core Next aktif olduğunda CoreNextCustomerRepository buraya atanır.
final coreNextCustomerRepositoryProvider =
    Provider<ICustomerRepository?>((ref) => null, name: 'coreNextCustomerRepositoryProvider');

final customerRepositoryProvider =
    FutureProvider<ICustomerRepository>((ref) async {
  final coreRepo = ref.watch(coreNextCustomerRepositoryProvider);
  if (coreRepo != null) {
    return coreRepo;
  }
  return SqliteCustomerRepository(ref.watch(dbGatewayProvider));
});

final customerSearchServiceProvider =
    FutureProvider<CustomerSearchService>((ref) async {
  final repo = await ref.watch(customerRepositoryProvider.future);
  return CustomerSearchService(repo);
});

/// Core Next Satış Deposu Sağlayıcısı (Varsayılan: null)
/// Core Next satış motoru aktif olduğunda CoreNextSaleRepository buraya atanır.
final coreNextSaleRepositoryProvider =
    Provider<ISaleRepository?>((ref) => null, name: 'coreNextSaleRepositoryProvider');

final saleRepositoryProvider = FutureProvider<ISaleRepository>((ref) async {
  final coreRepo = ref.watch(coreNextSaleRepositoryProvider);
  if (coreRepo != null) {
    return coreRepo;
  }
  return SqliteSaleRepository(ref.watch(dbGatewayProvider));
});

/// Core Next Finansal Hareket Deposu Sağlayıcısı (Varsayılan: null)
/// Core Next aktif olduğunda CoreNextFinancialTransactionRepository buraya atanır.
final coreNextFinancialTransactionRepositoryProvider =
    Provider<IFinancialTransactionRepository?>((ref) => null,
        name: 'coreNextFinancialTransactionRepositoryProvider');

final financialTransactionRepositoryProvider =
    FutureProvider<IFinancialTransactionRepository>((ref) async {
  final coreRepo = ref.watch(coreNextFinancialTransactionRepositoryProvider);
  if (coreRepo != null) {
    return coreRepo;
  }
  final gateway = ref.watch(dbGatewayProvider);
  final licenseService = ref.watch(licenseServiceProvider);
  final deviceId = licenseService.getDeviceUuid();
  return SqliteFinancialTransactionRepository(gateway, deviceId: deviceId);
});

final orderRepositoryProvider = FutureProvider<IOrderRepository>((ref) async {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteOrderRepository(gateway);
});

// ════════════════════════════════════════════════════════════
// Convenience Providers
// ════════════════════════════════════════════════════════════

final allProductsProvider = FutureProvider<List<ProductEntity>>((ref) async {
  final repo = await ref.watch(productRepositoryProvider.future);
  return repo.findAll();
});

final allCustomersProvider = FutureProvider<List<CustomerEntity>>((ref) async {
  final repo = await ref.watch(customerRepositoryProvider.future);
  return repo.findAll();
});

final allSalesProvider = FutureProvider<List<SaleEntity>>((ref) async {
  final repo = await ref.watch(saleRepositoryProvider.future);
  return repo.findAll();
});

final todayRevenueProvider = FutureProvider<double>((ref) async {
  final repo = await ref.watch(saleRepositoryProvider.future);
  return repo.getTodayRevenue();
});

final lowStockProductsProvider =
    FutureProvider<List<ProductEntity>>((ref) async {
  final repo = await ref.watch(productRepositoryProvider.future);
  return repo.getLowStockProducts(5);
});

final debtorsProvider = FutureProvider<List<CustomerEntity>>((ref) async {
  final repo = await ref.watch(customerRepositoryProvider.future);
  return repo.getDebtors();
});

/// ════════════════════════════════════════════════════════════
/// Phase 2.3 — Report Providers
/// ════════════════════════════════════════════════════════════

final reportRepositoryProvider = FutureProvider<IReportRepository>((ref) async {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteReportRepository(gateway);
});

final reportServiceProvider = FutureProvider<ReportService>((ref) async {
  final repo = await ref.watch(reportRepositoryProvider.future);
  return ReportService(repo);
});

/// ════════════════════════════════════════════════════════════
/// Phase 3 — Dashboard Providers
/// ════════════════════════════════════════════════════════════

final dashboardRepositoryProvider =
    FutureProvider<IDashboardRepository>((ref) async {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteDashboardRepository(gateway);
});

final userRepositoryProvider = Provider<IUserRepository>((ref) {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteUserRepository(gateway);
});

final dashboardServiceProvider = FutureProvider<DashboardService>((ref) async {
  final repo = await ref.watch(dashboardRepositoryProvider.future);
  return DashboardService(repo);
});

final databaseHealthRepositoryProvider =
    Provider<IDatabaseHealthRepository>((ref) {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteDatabaseHealthRepository(gateway);
});

// ── Cloud BI Analytics Providers (Sprint 7) ──
final cloudAnalyticsRepositoryProvider =
    Provider<CloudAnalyticsRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CloudAnalyticsRepository(apiClient: apiClient);
});

final analyticsWsServiceProvider = Provider<AnalyticsWsService>((ref) {
  return AnalyticsWsService();
});

// ── Billing Platform Providers (Sprint 8) ──
final billingRepositoryProvider = Provider<BillingRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return BillingRepository(apiClient: apiClient);
});

// ── Notification Platform Providers (Sprint 9) ──
final notificationRepositoryProvider = Provider<NotificationRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return NotificationRepository(apiClient: apiClient);
});

// ── Mobile Admin Portal Providers (Sprint 10) ──
final portalRepositoryProvider = Provider<PortalRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return PortalRepository(apiClient: apiClient);
});

// ── Installment Repository Provider ──
final installmentRepositoryProvider = Provider<IInstallmentRepository>((ref) {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteInstallmentRepository(gateway);
});

// ── Business Profile Repository Provider ──
final businessProfileRepositoryProvider =
    Provider<IBusinessProfileRepository>((ref) {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteBusinessProfileRepository(gateway);
});
