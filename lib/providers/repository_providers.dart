// lib/providers/repository_providers.dart
// PHASE 0 Day 3 - Repository Dependency Injection
// Riverpod providers for repository access
// Generated: 21 Jun 2026
// Strategy: Mock implementation (Phase 1) → Real SQLite (Phase 6+)

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/providers/database_provider.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_report_repository.dart';
import 'package:serenutos/domain/services/report_service.dart';
import 'package:serenutos/infrastructure/repositories/dashboard_repository.dart';
import 'package:serenutos/domain/services/dashboard_service.dart';
import 'package:serenutos/infrastructure/datasources/remote_data_sources.dart';
import 'package:serenutos/infrastructure/repositories/cloud_adaptive_product_repository.dart';
import 'package:serenutos/infrastructure/repositories/cloud_adaptive_customer_repository.dart';
import 'package:serenutos/infrastructure/repositories/cloud_adaptive_sale_repository.dart';

// ── Late Sprint Imports (Sprint 7, 8, 9, 10) ──
import 'package:serenutos/infrastructure/repositories/cloud_analytics_repository.dart';
import 'package:serenutos/infrastructure/services/analytics_ws_service.dart';
import 'package:serenutos/infrastructure/repositories/billing_repository.dart';
import 'package:serenutos/infrastructure/repositories/notification_repository.dart';
import 'package:serenutos/infrastructure/repositories/portal_repository.dart';
import 'package:serenutos/infrastructure/services/dataset_loader_service.dart';
import 'package:serenutos/providers/service_providers.dart';

// ════════════════════════════════════════════════════════════
// Riverpod Providers
// ════════════════════════════════════════════════════════════

// ── Remote Data Source Providers ──
final productRemoteDataSourceProvider =
    Provider<ProductRemoteDataSource>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CloudProductRemoteDataSource(apiClient);
});

final customerRemoteDataSourceProvider =
    Provider<CustomerRemoteDataSource>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CloudCustomerRemoteDataSource(apiClient);
});

final salesRemoteDataSourceProvider = Provider<SalesRemoteDataSource>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CloudSalesRemoteDataSource(apiClient);
});

// ── Repository Providers ──
final productRepositoryProvider =
    FutureProvider<IProductRepository>((ref) async {
  final localRepo = SqliteProductRepository(
      ref.watch(dbGatewayProvider), ref.watch(datasetLoaderServiceProvider));
  final remoteDS = ref.watch(productRemoteDataSourceProvider);
  return CloudAdaptiveProductRepository(localRepo, remoteDS);
});

final customerRepositoryProvider =
    FutureProvider<ICustomerRepository>((ref) async {
  final localRepo = SqliteCustomerRepository(ref.watch(dbGatewayProvider));
  final remoteDS = ref.watch(customerRemoteDataSourceProvider);
  return CloudAdaptiveCustomerRepository(localRepo, remoteDS);
});

final saleRepositoryProvider = FutureProvider<ISaleRepository>((ref) async {
  final localRepo = SqliteSaleRepository(ref.watch(dbGatewayProvider));
  final remoteDS = ref.watch(salesRemoteDataSourceProvider);
  return CloudAdaptiveSaleRepository(localRepo, remoteDS);
});

final financialTransactionRepositoryProvider =
    FutureProvider<IFinancialTransactionRepository>((ref) async {
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

final globalSearchRepositoryProvider = Provider<IGlobalSearchRepository>((ref) {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteGlobalSearchRepository(gateway);
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
