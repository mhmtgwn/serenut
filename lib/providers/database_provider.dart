// lib/providers/database_provider.dart
// PHASE 0 Day 4 - Database Riverpod Provider
// Provides SQLite database and repositories for Phase 6 integration
// Generated: 21 Jun 2026

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/infrastructure/database/database_provider.dart';
import 'package:serenutos/infrastructure/database/db_gateway.dart';
import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/infrastructure/repositories/sqlite_repositories.dart';
import 'package:serenutos/infrastructure/services/dataset_loader_service.dart';

/// ============================================================
/// Database Provider
/// ============================================================

/// Get SQLite database instance
/// 
/// Usage:
/// ```dart
/// final db = await ref.watch(databaseProvider.future);
/// ```
final databaseProvider = FutureProvider<Database>((ref) async {
  final dbManager = DatabaseManager();
  return dbManager.getDatabase();
});

/// Get DbGateway instance (lock-safe query suspension boundary)
final dbGatewayProvider = Provider<DbGateway>((ref) {
  final dbManager = DatabaseManager();
  return DbGatewayImpl(dbManager);
});

/// ============================================================
/// SQLite Repository Providers (Phase 6 Ready)
/// ============================================================
/// 
/// These providers are ready for Phase 6 integration.
/// Simply switch from mock providers to these SQLite versions.
/// 
/// Current Usage (Phase 1):
/// - UI uses mock providers from repository_providers.dart
/// - Mock repos return hardcoded data with 300ms delay
/// 
/// Phase 6 Usage:
/// - Override repository_providers.dart to use these SQLite versions
/// - Same provider names, same interface contracts
/// - Zero UI changes needed
/// ============================================================

/// SQLite Product Repository Provider
/// 
/// Replaces MockProductRepository on Phase 6


final sqliteProductRepositoryProvider = FutureProvider<IProductRepository>((ref) async {
  final gateway = ref.watch(dbGatewayProvider);
  final datasetLoader = ref.watch(datasetLoaderServiceProvider);
  return SqliteProductRepository(gateway, datasetLoader);
});

/// SQLite Customer Repository Provider
/// 
/// Replaces MockCustomerRepository on Phase 6
final sqliteCustomerRepositoryProvider = FutureProvider<ICustomerRepository>((ref) async {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteCustomerRepository(gateway);
});

/// SQLite Sale Repository Provider
/// 
/// Replaces MockSaleRepository on Phase 6
final sqliteSaleRepositoryProvider = FutureProvider<ISaleRepository>((ref) async {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteSaleRepository(gateway);
});

/// SQLite Financial Transaction Repository Provider
/// 
/// Replaces MockFinancialTransactionRepository on Phase 6
final sqliteFinancialTransactionRepositoryProvider = 
  FutureProvider<IFinancialTransactionRepository>((ref) async {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteFinancialTransactionRepository(gateway);
});

/// SQLite Order Repository Provider
/// 
/// Replaces MockOrderRepository on Phase 6
final sqliteOrderRepositoryProvider = FutureProvider<IOrderRepository>((ref) async {
  final gateway = ref.watch(dbGatewayProvider);
  return SqliteOrderRepository(gateway);
});

/// ============================================================
/// Phase 6 Migration Instructions
/// ============================================================
/// 
/// When ready for Phase 6 transition:
/// 
/// STEP 1: Export SQLite providers from this file
/// Already done! ^^ See above
/// 
/// STEP 2: Update repository_providers.dart
/// 
/// Change the provider implementations:
/// 
/// ```dart
/// // OLD (Phase 1):
/// final productRepositoryProvider = FutureProvider((ref) async {
///   return MockProductRepository();
/// });
/// 
/// // NEW (Phase 6):
/// final productRepositoryProvider = FutureProvider((ref) async {
///   final db = await ref.watch(databaseProvider.future);
///   return SqliteProductRepository(db);
/// });
/// ```
/// 
/// OR, import and delegate to SQLite providers:
/// 
/// ```dart
/// import 'package:serenutos/providers/database_provider.dart';
/// 
/// // Simple delegation
/// final productRepositoryProvider = ref.watch(sqliteProductRepositoryProvider);
/// ```
/// 
/// STEP 3: Run tests
/// 
/// ```bash
/// flutter test test/integration/transaction_flow_test.dart
/// flutter run  # Test app with real data
/// ```
/// 
/// STEP 4: Monitor for issues
/// 
/// - Check database initialization logs
/// - Verify schema creates successfully
/// - Ensure all mock data inserts
/// - Test each screen with real data
/// 
/// ============================================================
/// 
/// No UI code changes required!
/// Same provider names, same interfaces, same behavior
/// Only the underlying implementation changes.
/// ============================================================
