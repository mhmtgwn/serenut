// lib/infrastructure/repositories/base_repository.dart
// PHASE 0 Day 3 - Repository Pattern
// Base interfaces for data access layer
// Generated: 21 Jun 2026

import 'dart:convert';
import 'package:serenutos/domain/models/settings.dart';
import 'package:serenutos/domain/models/auth_user.dart';

/// Generic repository interface for CRUD operations
/// 
/// Implemented by:
/// - Mock repositories (Phase 1)
/// - SQLite repositories (Phase 1.5+)
/// 
/// Usage:
/// ```dart
/// final productRepo = ref.watch(productRepositoryProvider);
/// final products = await productRepo.findAll();
/// ```
abstract class BaseRepository<T> {
  /// Get all records
  Future<List<T>> findAll();

  /// Get by ID
  Future<T?> findById(dynamic id);

  /// Create new record
  Future<int> create(T entity);

  /// Update existing record (returns affected rows)
  Future<int> update(T entity);

  /// Delete by ID (soft delete with last_modified_at)
  Future<int> delete(dynamic id);

  /// Count total records
  Future<int> count();

  /// Check if exists
  Future<bool> exists(dynamic id);
}

/// Product repository
abstract class IProductRepository implements BaseRepository<ProductEntity> {
  @override
  Future<int> update(ProductEntity entity, {String? oldId});

  /// Search products by name
  Future<List<ProductEntity>> searchByName(String query);

  /// Get products by category
  Future<List<ProductEntity>> getByCategory(String category);

  /// Get products grouped by category
  Future<Map<String, List<ProductEntity>>> getGroupedByCategory();

  /// Decrease stock (for sale)
  Future<void> decreaseStock(String productId, int quantity);

  /// Increase stock (for return/adjustment)
  Future<void> increaseStock(String productId, int quantity);

  /// Get low stock products
  Future<List<ProductEntity>> getLowStockProducts(int threshold);

  /// Find products with search, category filters, and pagination
  Future<List<ProductEntity>> findFiltered({
    String? searchQuery,
    String? category,
    int? limit,
    int? offset,
  });

  /// Get distinct categories of active products
  Future<List<String>> getCategories();
}

/// Customer repository
abstract class ICustomerRepository implements BaseRepository<CustomerEntity> {
  /// Search customers by name or email
  Future<List<CustomerEntity>> search(String query);

  /// Find customers with search and pagination
  Future<List<CustomerEntity>> findFiltered({
    String? searchQuery,
    int? limit,
    int? offset,
  });

  /// Get customers with debt
  Future<List<CustomerEntity>> getDebtors();

  /// Get customers with credit
  Future<List<CustomerEntity>> getWithCredit();

  /// Update customer balance
  Future<void> updateBalance(String customerId, double amount);

  /// Get customer balance
  Future<double> getBalance(String customerId);

  /// Get total debt for customer
  Future<double> getTotalDebt(String customerId);

  /// Get total paid by customer
  Future<double> getTotalPaid(String customerId);
}

/// Sale repository
abstract class ISaleRepository implements BaseRepository<SaleEntity> {
  /// Find sale by idempotency key
  Future<SaleEntity?> findByIdempotencyKey(String key);

  /// Get sales for today
  Future<List<SaleEntity>> getTodaySales();

  /// Get sales for date range
  Future<List<SaleEntity>> getSalesByDateRange(DateTime from, DateTime to);

  /// Get sales by customer
  Future<List<SaleEntity>> getByCustomerId(String customerId);

  /// Get sales by payment method
  Future<List<SaleEntity>> getByPaymentMethod(String method);

  /// Get today's revenue
  Future<double> getTodayRevenue();

  /// Get date range revenue
  Future<double> getRevenueByDateRange(DateTime from, DateTime to);

  /// Get total items sold
  Future<int> getTotalItemsSold();

  /// İSTEK 3 DÜZELTMESİ: Sadece is_synced = 0 olan satışları döner.
  /// findAll().where() Dart-tarafı filtreleme yerine SQL WHERE kullanır (O(n) RAM → O(k) RAM).
  Future<List<SaleEntity>> findUnsynced();

  /// Paginated filtered query — used by sales history UI.
  /// [searchQuery] matches on sale id (case-insensitive).
  /// [limit] / [offset] control the page window.
  Future<List<SaleEntity>> findFiltered({
    String? searchQuery,
    int limit = 25,
    int offset = 0,
  });
}

/// Financial transaction repository
abstract class IFinancialTransactionRepository implements BaseRepository<FinancialTransactionEntity> {
  /// Get transactions by customer
  Future<List<FinancialTransactionEntity>> getByCustomerId(String customerId);

  /// Get transactions by type
  Future<List<FinancialTransactionEntity>> getByType(String type);

  /// Get transactions for date range
  Future<List<FinancialTransactionEntity>> getByDateRange(DateTime from, DateTime to);

  /// Get ledger balance for customer
  Future<double> getBalance(String customerId);

  /// YÜKSEK A DÜZELTMESİ: Get the maximum logical clock value from all local transactions.
  /// O(1) SQL query — avoids loading all transactions into memory just to find the max.
  Future<int> getMaxLogicalClock();

  /// İSTEK 3 DÜZELTMESİ: Belirtilen referenceId + type ikilisine sahip kayıt var mı?
  /// payment_service.dart'taki findAll().any() Dart filtresi yerine EXISTS SQL sorgusu kullanır.
  Future<bool> existsByReferenceId(String referenceId, String type);
}

/// Order repository
abstract class IOrderRepository implements BaseRepository<OrderEntity> {
  /// Get orders by customer
  Future<List<OrderEntity>> getByCustomerId(String customerId);

  /// Get orders by status
  Future<List<OrderEntity>> getByStatus(String status);

  /// Get pending orders
  Future<List<OrderEntity>> getPending();

  /// Update order status
  Future<void> updateStatus(String orderId, String status);

  /// Get overdue orders
  Future<List<OrderEntity>> getOverdue();

  /// Paginated filtered query — used by orders list UI.
  /// [searchQuery] matches on order id (case-insensitive).
  /// [status] filters by exact status; null or 'all' returns all statuses.
  /// [limit] / [offset] control the page window.
  Future<List<OrderEntity>> findFiltered({
    String? searchQuery,
    String? status,
    int limit = 25,
    int offset = 0,
  });

  /// Returns the count of orders per status key.
  /// Keys: 'all', 'created', 'preparing', 'ready', 'delivered', 'cancelled'.
  Future<Map<String, int>> getStatusCounts({String? searchQuery});
}

/// Settings repository interface
abstract class ISettingsRepository {
  Future<Settings> getSettings();
  Future<void> updateSettings(Settings settings);
}

/// ════════════════════════════════════════════════════════════
/// Entity Models (for data access)
/// ════════════════════════════════════════════════════════════

/// Product entity (matches database schema)
class ProductEntity {
  final String id;
  final String name;
  final String description;
  final double price;
  final int quantity;
  final String category;
  final int? vat; // VAT percentage
  final String? imageUrl;

  ProductEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.price,
    required this.quantity,
    required this.category,
    this.vat,
    this.imageUrl,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'price': price,
    'quantity': quantity,
    'category': category,
    'vat': vat,
    'image_url': imageUrl,
  };

  factory ProductEntity.fromMap(Map<String, dynamic> map) => ProductEntity(
    id: map['id'] as String,
    name: map['name'] as String,
    description: map['description'] as String,
    price: map['price'] as double,
    quantity: map['quantity'] as int,
    category: map['category'] as String,
    vat: map['vat'] as int?,
    imageUrl: map['image_url'] as String?,
  );
}

/// Customer entity
class CustomerEntity {
  final String id;
  final String name;
  final String email;
  final String phone;
  final double balance; // Positive = credit, Negative = debt
  final DateTime createdAt;

  CustomerEntity({
    required this.id,
    required this.name,
    required this.email,
    required this.phone,
    required this.balance,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'email': email,
    'phone': phone,
    'balance': balance,
    'created_at': createdAt.toIso8601String(),
  };

  factory CustomerEntity.fromMap(Map<String, dynamic> map) => CustomerEntity(
    id: map['id'] as String,
    name: map['name'] as String,
    email: map['email'] as String,
    phone: map['phone'] as String,
    balance: map['balance'] as double,
    createdAt: DateTime.parse(map['created_at'] as String),
  );
}

/// Sale entity
class SaleEntity {
  final String id;
  final String customerId;
  final double totalAmount;
  final double paidAmount;
  final String paymentMethod;
  final String status; // completed, pending, cancelled, processing, failed, reverted
  final DateTime createdAt;
  final List<Map<String, dynamic>> items; // Sale items
  final String? idempotencyKey;
  final int isSynced;
  final String? createdBy;

  SaleEntity({
    required this.id,
    required this.customerId,
    required this.totalAmount,
    required this.paidAmount,
    required this.paymentMethod,
    required this.status,
    required this.createdAt,
    required this.items,
    this.idempotencyKey,
    this.isSynced = 0,
    this.createdBy,
  });

  double get remainingAmount => totalAmount - paidAmount;

  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_id': customerId,
    'total_amount': totalAmount,
    'paid_amount': paidAmount,
    'payment_method': paymentMethod,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'idempotency_key': idempotencyKey,
    'is_synced': isSynced,
    'created_by': createdBy,
  };

  factory SaleEntity.fromMap(Map<String, dynamic> map) => SaleEntity(
    id: map['id'] as String,
    customerId: map['customer_id'] as String,
    totalAmount: map['total_amount'] as double,
    paidAmount: map['paid_amount'] as double,
    paymentMethod: map['payment_method'] as String,
    status: map['status'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
    idempotencyKey: map['idempotency_key'] as String?,
    isSynced: map['is_synced'] as int? ?? 0,
    createdBy: map['created_by'] as String?,
    items: [],
  );
}

/// Financial transaction entity
class FinancialTransactionEntity {
  final String id;
  final String type; // sale, payment, refund, etc.
  final String customerId;
  final double amount;
  final double paidAmount;
  final double debtAmount;
  final DateTime date;
  final String? referenceId; // Sale ID, Order ID, etc.
  final Map<String, dynamic>? metadata;
  final int logicalClock;
  final String? deviceId;

  FinancialTransactionEntity({
    required this.id,
    required this.type,
    required this.customerId,
    required this.amount,
    required this.paidAmount,
    required this.debtAmount,
    required this.date,
    this.referenceId,
    this.metadata,
    this.logicalClock = 0,
    this.deviceId,
  });

  Map<String, dynamic> toMap() => {
    'id': id,
    'type': type,
    'customer_id': customerId,
    'amount': amount,
    'paid_amount': paidAmount,
    'debt_amount': debtAmount,
    'date': date.toIso8601String(),
    'reference_id': referenceId,
    'metadata': metadata,
    'logical_clock': logicalClock,
    'device_id': deviceId,
  };

  factory FinancialTransactionEntity.fromMap(Map<String, dynamic> map) => FinancialTransactionEntity(
    id: map['id'] as String,
    type: map['type'] as String,
    customerId: map['customer_id'] as String,
    amount: map['amount'] as double,
    paidAmount: map['paid_amount'] as double,
    debtAmount: map['debt_amount'] as double,
    date: DateTime.parse((map['created_at'] ?? map['date'] ?? map['occurred_at'] ?? DateTime.now().toIso8601String()) as String),
    referenceId: map['reference_id'] as String?,
    metadata: map['metadata'] is String 
        ? jsonDecode(map['metadata'] as String) as Map<String, dynamic>?
        : map['metadata'] as Map<String, dynamic>?,
    logicalClock: map['logical_clock'] as int? ?? 0,
    deviceId: map['device_id'] as String?,
  );
}

/// Order entity
class OrderEntity {
  final String id;
  final String customerId;
  final String status; // created, preparing, ready, delivered, cancelled
  final DateTime createdAt;
  final DateTime? expectedDeliveryDate;
  final DateTime? actualDeliveryDate;
  final List<Map<String, dynamic>> items;
  final String? notes;
  final String? createdBy;

  OrderEntity({
    required this.id,
    required this.customerId,
    required this.status,
    required this.createdAt,
    this.expectedDeliveryDate,
    this.actualDeliveryDate,
    required this.items,
    this.notes,
    this.createdBy,
  });

  bool get isOverdue {
    if (expectedDeliveryDate == null) return false;
    return DateTime.now().isAfter(expectedDeliveryDate!) && status != 'delivered';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'customer_id': customerId,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'expected_delivery_date': expectedDeliveryDate?.toIso8601String(),
    'actual_delivery_date': actualDeliveryDate?.toIso8601String(),
    'notes': notes,
    'created_by': createdBy,
  };

  factory OrderEntity.fromMap(Map<String, dynamic> map) => OrderEntity(
    id: map['id'].toString(),
    customerId: map['customer_id'].toString(),
    status: map['status'] as String,
    createdAt: DateTime.parse(map['created_at'] as String),
    expectedDeliveryDate: map['expected_delivery_date'] != null 
      ? DateTime.parse(map['expected_delivery_date'] as String)
      : null,
    actualDeliveryDate: map['actual_delivery_date'] != null
      ? DateTime.parse(map['actual_delivery_date'] as String)
      : null,
    notes: map['notes'] as String?,
    createdBy: map['created_by'] as String?,
    items: [],
  );
}

/// Abstract contract for orchestrating database transactions from the domain layer.
abstract class IDbTransactionRunner {
  Future<T> transaction<T>(Future<T> Function() action);
}

/// User repository contract
abstract class IUserRepository implements BaseRepository<AuthUser> {
  Future<AuthUser?> findByUsername(String username);
  Future<AuthUser?> findByBusinessCodeAndUsername(String businessCode, String username);
  Future<String?> getPasswordHash(String userId);
  Future<Map<String, String?>> getCredentialHashes(String userId);
  Future<void> updateLastLogin(String userId);
  Future<void> updatePasswordHash(String userId, String passwordHash);
  Future<void> insertUser(
    AuthUser user,
    String passwordHash, {
    String? username,
    String? pinHash,
    String? businessCode,
    int? deviceTokenVersion,
  });
  Future<void> updateUserFields(
    AuthUser user, {
    bool? isActive,
    String? passwordHash,
    String? username,
    String? pinHash,
    String? businessCode,
    int? deviceTokenVersion,
  });
}

/// DTO representing the counts of database health anomalies
class DatabaseHealthReport {
  final int orphanedSaleItemsCount;
  final int orphanedOrderItemsCount;
  final int orphanedOrderPaymentsCount;
  final int orphanedTransactionsCount;
  final int negativeStockProductsCount;
  final int customerBalanceDriftsCount;
  final int duplicateUuidsCount;

  const DatabaseHealthReport({
    required this.orphanedSaleItemsCount,
    required this.orphanedOrderItemsCount,
    required this.orphanedOrderPaymentsCount,
    required this.orphanedTransactionsCount,
    required this.negativeStockProductsCount,
    required this.customerBalanceDriftsCount,
    required this.duplicateUuidsCount,
  });

  bool get isHealthy =>
      orphanedSaleItemsCount == 0 &&
      orphanedOrderItemsCount == 0 &&
      orphanedOrderPaymentsCount == 0 &&
      orphanedTransactionsCount == 0 &&
      negativeStockProductsCount == 0 &&
      customerBalanceDriftsCount == 0 &&
      duplicateUuidsCount == 0;
}

/// Interface for executing structural and logical database health checks
abstract class IDatabaseHealthRepository {
  /// Scans the database for anomalies and returns a health report
  Future<DatabaseHealthReport> checkHealth();

  /// Fixes anomalies (deletes orphans, resets negative stock, corrects balance drifts)
  Future<void> repairHealth();
}

/// DTO representing the unified results from a global search
class GlobalSearchResult {
  final List<CustomerEntity> customers;
  final List<ProductEntity> products;
  final List<SaleEntity> sales;
  final List<FinancialTransactionEntity> transactions;

  const GlobalSearchResult({
    required this.customers,
    required this.products,
    required this.sales,
    required this.transactions,
  });

  bool get isEmpty =>
      customers.isEmpty &&
      products.isEmpty &&
      sales.isEmpty &&
      transactions.isEmpty;
}

/// Interface for executing unified search queries across multiple entities
abstract class IGlobalSearchRepository {
  /// Searches all customers, products, sales, and financial transactions for a query
  Future<GlobalSearchResult> searchAll(String query);
}
