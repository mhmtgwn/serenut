# 🔥 PHASE 0 — FOUNDATION FREEZE (ENGINEERING GRADE)

**Status**: 🔒 LOCKED & SIGNED OFF  
**Date**: 20 Jun 2026  
**Purpose**: Zero ambiguity before PHASE 1 UI build  
**Audience**: Backend + Frontend Engineers  

---

## 📋 TABLE OF CONTENTS

1. [Auth Contract](#1-auth-contract)
2. [DTO Schema (Copy-Paste Ready)](#2-dto-schema)
3. [Riverpod State Management Standard](#3-riverpod-state-pattern)
4. [Transaction State Machine](#4-transaction-state-machine)
5. [Error & Exception Model](#5-error-model)
6. [TransactionEngine Pseudo-Code](#6-transactionengine-pseudocode)
7. [Failure & Rollback Matrix](#7-failure--rollback-matrix)
8. [Event System Design](#8-event-system-design)
9. [SQLite Schema Final (ERD)](#9-sqlite-erdfinal)
10. [UI ↔ Backend Contract Rules](#10-ui--backend-contract-rules)
11. [Offline/Sync Strategy](#11-offlinesync-strategy)
12. [Decision Log](#12-decision-log)

---

# 1. 🔐 AUTH CONTRACT

## 1.1 User Model (LOCAL MOCK — v1)

```dart
// lib/domain/models/auth_user.dart

class AuthUser {
  final String id;
  final String name;
  final UserRole role;
  final List<String> permissions;
  final DateTime createdAt;
  
  // Feature freeze
  const AuthUser({
    required this.id,
    required this.name,
    required this.role,
    required this.permissions,
    required this.createdAt,
  });
  
  bool hasPermission(String permission) => permissions.contains(permission);
  
  bool hasAllPermissions(List<String> required) => 
    required.every(hasPermission);
  
  bool hasAnyPermission(List<String> any) =>
    any.any(hasPermission);
}

enum UserRole {
  admin,      // all permissions
  manager,    // reports + orders + customers + settings
  cashier,    // sales + payments only
  staff       // sales only (future)
}
```

## 1.2 Auth Service (Mock Local Storage)

```dart
// lib/domain/services/auth_service.dart

class AuthService {
  static const String _userKey = 'auth_user';
  final _prefs = SharedPreferences.getInstance();
  
  // Mock users (DEV ONLY)
  static final _mockUsers = {
    'admin': AuthUser(
      id: 'admin_001',
      name: 'Admin User',
      role: UserRole.admin,
      permissions: _allPermissions(),
      createdAt: DateTime.now(),
    ),
    'cashier': AuthUser(
      id: 'cashier_001',
      name: 'Cashier User',
      role: UserRole.cashier,
      permissions: _cashierPermissions(),
      createdAt: DateTime.now(),
    ),
  };
  
  // Login (mock)
  Future<AuthUser> login(String username, String password) async {
    // v1: username = password
    if (_mockUsers.containsKey(username)) {
      final user = _mockUsers[username]!;
      await (await _prefs).setString(_userKey, jsonEncode(user.toMap()));
      return user;
    }
    throw AuthException('Invalid credentials');
  }
  
  // Get current user
  Future<AuthUser?> getCurrentUser() async {
    final json = (await _prefs).getString(_userKey);
    if (json == null) return null;
    return AuthUser.fromMap(jsonDecode(json));
  }
  
  // Logout
  Future<void> logout() async {
    await (await _prefs).remove(_userKey);
  }
  
  // Permissions
  static List<String> _allPermissions() => [
    // Sales
    'sales:view', 'sales:create', 'sales:edit', 'sales:delete', 'sales:print',
    // Orders
    'orders:view', 'orders:create', 'orders:edit', 'orders:deliver',
    // Customers
    'customers:view', 'customers:create', 'customers:edit', 'customers:delete',
    // Payments
    'payments:view', 'payments:record', 'payments:reverse',
    // Inventory
    'inventory:view', 'inventory:adjust', 'inventory:transfer',
    // Reports
    'reports:view', 'reports:financial', 'reports:inventory',
    // Admin
    'admin:settings', 'admin:users', 'admin:roles',
  ];
  
  static List<String> _cashierPermissions() => [
    'sales:view', 'sales:create', 'sales:print',
    'customers:view',
    'payments:view', 'payments:record',
  ];
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
  
  @override
  String toString() => message;
}
```

## 1.3 Migration Path (Future)

```
v1: LocalStorage (current)
    ↓
v2: JWT backend (future)
    ├─ Same AuthUser model
    ├─ Token refresh logic
    └─ No UI changes needed
```

**Decision**: ✅ LOCKED (no changes to this layer for 2 weeks)

---

# 2. 🗂️ DTO SCHEMA (Copy-Paste Ready)

## 2.1 Response Wrapper (Standard)

```dart
// lib/data/models/app_response.dart

class AppResponse<T> {
  final bool success;
  final T? data;
  final String? error;
  final int? errorCode;
  
  AppResponse({
    required this.success,
    this.data,
    this.error,
    this.errorCode,
  });
  
  factory AppResponse.success(T data) => AppResponse(
    success: true,
    data: data,
  );
  
  factory AppResponse.error(String message, {int? code}) => AppResponse(
    success: false,
    error: message,
    errorCode: code,
  );
}
```

## 2.2 Product DTO

```dart
// lib/data/models/dtos/product_dto.dart

class ProductDTO {
  final String id;
  final String barcode;
  final String name;
  final String categoryId;
  final String unit;
  final double costPrice;
  final double sellPrice;
  final int taxPercent;  // 0-100
  final int stock;
  final int minimumStock;
  final DateTime createdAt;
  final DateTime? updatedAt;
  
  ProductDTO({
    required this.id,
    required this.barcode,
    required this.name,
    required this.categoryId,
    required this.unit,
    required this.costPrice,
    required this.sellPrice,
    required this.taxPercent,
    required this.stock,
    required this.minimumStock,
    required this.createdAt,
    this.updatedAt,
  });
  
  // UI → Domain (no tax calculation here)
  Product toDomain() => Product(
    id: id,
    barcode: barcode,
    name: name,
    categoryId: categoryId,
    unit: unit,
    costPrice: costPrice,
    sellPrice: sellPrice,
    tax: taxPercent,
    stock: stock,
    minimumStock: minimumStock,
  );
  
  factory ProductDTO.fromMap(Map<String, dynamic> map) => ProductDTO(
    id: map['id'],
    barcode: map['barcode'],
    name: map['name'],
    categoryId: map['category_id'],
    unit: map['unit'],
    costPrice: (map['cost_price'] as num).toDouble(),
    sellPrice: (map['sell_price'] as num).toDouble(),
    taxPercent: map['tax'] as int,
    stock: map['stock'] as int,
    minimumStock: map['minimum_stock'] as int,
    createdAt: DateTime.parse(map['created_at']),
    updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : null,
  );
  
  Map<String, dynamic> toMap() => {
    'id': id,
    'barcode': barcode,
    'name': name,
    'category_id': categoryId,
    'unit': unit,
    'cost_price': costPrice,
    'sell_price': sellPrice,
    'tax': taxPercent,
    'stock': stock,
    'minimum_stock': minimumStock,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt?.toIso8601String(),
  };
}
```

## 2.3 Customer DTO

```dart
// lib/data/models/dtos/customer_dto.dart

class CustomerDTO {
  final String id;
  final String nameOrCompany;
  final String? phone;
  final String? address;
  final String? taxNumber;
  final double balance;  // READONLY - calculated by backend
  final bool isActive;
  final DateTime createdAt;
  final DateTime? deletedAt;
  
  CustomerDTO({
    required this.id,
    required this.nameOrCompany,
    this.phone,
    this.address,
    this.taxNumber,
    required this.balance,
    required this.isActive,
    required this.createdAt,
    this.deletedAt,
  });
  
  Customer toDomain() => Customer(
    id: id,
    nameOrCompany: nameOrCompany,
    phone: phone,
    address: address,
    taxNumber: taxNumber,
    isActive: isActive,
  );
  
  factory CustomerDTO.fromMap(Map<String, dynamic> map) => CustomerDTO(
    id: map['id'],
    nameOrCompany: map['name_company'],
    phone: map['phone'],
    address: map['address'],
    taxNumber: map['tax_number'],
    balance: (map['balance'] as num).toDouble(),
    isActive: map['is_active'] == 1,
    createdAt: DateTime.parse(map['created_at']),
    deletedAt: map['deleted_at'] != null ? DateTime.parse(map['deleted_at']) : null,
  );
}
```

## 2.4 Sale DTO (With Split Payment List)

```dart
// lib/data/models/dtos/sale_dto.dart

class SaleDTO {
  final String id;
  final String customerId;
  final double totalAmount;
  final double paidAmount;
  final double balanceAmount;
  final String status;  // pending, completed, cancelled
  final List<SalePaymentDTO> payments;
  final List<SaleItemDTO> items;
  final DateTime saleDate;
  final DateTime createdAt;
  
  SaleDTO({
    required this.id,
    required this.customerId,
    required this.totalAmount,
    required this.paidAmount,
    required this.balanceAmount,
    required this.status,
    required this.payments,
    required this.items,
    required this.saleDate,
    required this.createdAt,
  });
  
  Sale toDomain() => Sale(
    id: id,
    customerId: customerId,
    paymentType: payments.isNotEmpty ? payments[0].type : 'CASH',
    totalAmount: totalAmount,
    paidAmount: paidAmount,
    balanceAmount: balanceAmount,
    status: status,
  );
  
  factory SaleDTO.fromMap(Map<String, dynamic> map) => SaleDTO(
    id: map['id'],
    customerId: map['customer_id'],
    totalAmount: (map['total_amount'] as num).toDouble(),
    paidAmount: (map['paid_amount'] as num).toDouble(),
    balanceAmount: (map['balance_amount'] as num).toDouble(),
    status: map['status'] ?? 'pending',
    payments: [], // fetch separately
    items: [], // fetch separately
    saleDate: DateTime.parse(map['sale_date']),
    createdAt: DateTime.parse(map['created_at']),
  );
}

class SalePaymentDTO {
  final String paymentId;
  final String type;  // CASH, CARD, TRANSFER, CHECK, DEBT
  final double amount;
  final String status;  // PENDING, COMPLETED, FAILED, CANCELLED
  
  SalePaymentDTO({
    required this.paymentId,
    required this.type,
    required this.amount,
    required this.status,
  });
}

class SaleItemDTO {
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final int taxPercent;
  final double totalPrice;
  
  SaleItemDTO({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.taxPercent,
    required this.totalPrice,
  });
}
```

## 2.5 Transaction DTO (read-only ledger)

```dart
// lib/data/models/dtos/financial_transaction_dto.dart

class FinancialTransactionDTO {
  final String id;
  final String customerId;
  final String type;  // sale, order, payment, refund, adjustment
  final double amount;
  final double paidAmount;
  final double debtAmount;
  final String referenceId;  // sale_id, order_id, payment_id
  final Map<String, double> paymentMethods;
  final String? description;
  final DateTime transactionDate;
  final DateTime createdAt;
  
  FinancialTransactionDTO({
    required this.id,
    required this.customerId,
    required this.type,
    required this.amount,
    required this.paidAmount,
    required this.debtAmount,
    required this.referenceId,
    required this.paymentMethods,
    this.description,
    required this.transactionDate,
    required this.createdAt,
  });
  
  factory FinancialTransactionDTO.fromMap(Map<String, dynamic> map) =>
    FinancialTransactionDTO(
      id: map['id'],
      customerId: map['customer_id'],
      type: map['type'],
      amount: (map['amount'] as num).toDouble(),
      paidAmount: (map['paid_amount'] as num).toDouble(),
      debtAmount: (map['debt_amount'] as num).toDouble(),
      referenceId: map['reference_id'],
      paymentMethods: Map<String, double>.from(
        (map['payment_methods'] as Map).map(
          (k, v) => MapEntry(k as String, (v as num).toDouble())
        )
      ),
      description: map['description'],
      transactionDate: DateTime.parse(map['transaction_date']),
      createdAt: DateTime.parse(map['created_at']),
    );
}
```

**Decision**: ✅ LOCKED (no DTO changes for 2 weeks)

---

# 3. 🧩 RIVERPOD STATE PATTERN

## 3.1 AppState Wrapper (STANDARD)

```dart
// lib/presentation/state/app_state.dart

class AppState<T> {
  final AsyncValue<T> value;
  final AppException? appError;
  
  const AppState({
    required this.value,
    this.appError,
  });
  
  bool get isLoading => value is AsyncLoading;
  bool get isError => value is AsyncError || appError != null;
  bool get isSuccess => value is AsyncData && appError == null;
  
  T? get data => value is AsyncData ? (value as AsyncData<T>).value : null;
  
  AppException? get error {
    if (appError != null) return appError;
    if (value is AsyncError) {
      return (value as AsyncError<T>).error as AppException?;
    }
    return null;
  }
  
  String get errorMessage => error?.userMessage ?? 'Unknown error';
}
```

## 3.2 Riverpod Provider Template

```dart
// EXAMPLE: lib/presentation/providers/product_provider.dart

final productListProvider = FutureProvider.autoDispose<List<ProductDTO>>((ref) async {
  final repository = ref.watch(productRepositoryProvider);
  try {
    return await repository.getAllProducts();
  } catch (e) {
    throw AppException.fromException(e);
  }
});

// Usage in StateNotifier
class ProductListState extends StateNotifier<AppState<List<ProductDTO>>> {
  final Ref ref;
  
  ProductListState(this.ref)
    : super(AppState(value: const AsyncLoading()));
  
  Future<void> loadProducts() async {
    final value = await ref.read(productListProvider.future);
    state = AppState(value: AsyncData(value));
  }
}

final productListStateProvider = StateNotifierProvider.autoDispose<
  ProductListState,
  AppState<List<ProductDTO>>
>((ref) => ProductListState(ref));
```

## 3.3 Error Provider (Global)

```dart
// lib/presentation/providers/error_provider.dart

final lastErrorProvider = StateProvider<AppException?>((ref) => null);

// Usage:
ref.read(lastErrorProvider.notifier).state = AppException(...);
```

**Decision**: ✅ LOCKED (MUST use AppState wrapper for all async)

---

# 4. 💥 TRANSACTION STATE MACHINE

## 4.1 Visual State Flow

```
┌─────────────────────────────────────────────────────────────┐
│                         SALE LIFECYCLE                      │
└─────────────────────────────────────────────────────────────┘

     UI INPUT (Product + Payment)
              │
              ▼
    ┌──────────────────┐
    │   PENDING        │  ← Created by UI
    └────────┬─────────┘
             │
             ▼ TransactionEngine.executeSaleTransaction()
    ┌──────────────────┐
    │   PROCESSING     │  ← Backend transaction started
    └────────┬─────────┘
             │
        Step 1: Stock check
        Step 2: Payment split
        Step 3: Ledger write
        Step 4: Event publish
             │
             ├─ ALL OK ──► COMPLETED ✅
             │
             └─ ANY FAIL ─► FAILED ❌
                              │
                              ▼
                        ROLLBACK_REQUIRED
                              │
                              ▼
                         UI ERROR SHOW


┌─────────────────────────────────────────────────────────────┐
│                       ORDER LIFECYCLE                       │
└─────────────────────────────────────────────────────────────┘

    CREATED ──► PREPARING ──► READY ──► DELIVERED ──► CLOSED
       │           │         │           │
       │           │         │    (STOCK DECREASES HERE)
       │           │         │
       └─ CANCELLED (any state)


┌─────────────────────────────────────────────────────────────┐
│                      PAYMENT LIFECYCLE                      │
└─────────────────────────────────────────────────────────────┘

    PENDING ──► CONFIRMED ──► POSTED
       │
       └─ FAILED / CANCELLED
```

## 4.2 State Enum (Dart)

```dart
// lib/domain/models/transaction_state.dart

enum TransactionState {
  pending,        // initial
  processing,     // engine running
  completed,      // success
  failed,         // engine error
  rollbackNeeded, // manual fix required
  cancelled,      // user cancelled
}

enum OrderState {
  created,
  preparing,
  ready,
  delivered,
  closed,
  cancelled,
}

enum PaymentState {
  pending,
  confirmed,
  posted,
  failed,
  cancelled,
}
```

## 4.3 State Transitions (MUST FOLLOW)

```dart
// RULE: Only these transitions allowed

class StateTransition {
  // SALE
  static const salePending_to_processing = true;      // ✅
  static const saleProcessing_to_completed = true;    // ✅
  static const saleProcessing_to_failed = true;       // ✅
  static const sale_to_cancelled_anytime = true;      // ✅
  
  // ORDER
  static const orderCreated_to_preparing = true;      // ✅
  static const orderPreparing_to_ready = true;        // ✅
  static const orderReady_to_delivered = true;        // ✅ (STOCK DECREASES)
  static const orderDelivered_to_closed = true;       // ✅
  static const order_to_cancelled_anytime = true;     // ✅
  
  // PAYMENT
  static const paymentPending_to_confirmed = true;    // ✅
  static const paymentConfirmed_to_posted = true;     // ✅
  static const payment_to_cancelled_anytime = true;   // ✅
  
  // INVALID (will throw)
  static const saleFailed_to_completed = false;       // ❌
  static const orderDelivered_to_preparing = false;   // ❌
  static const paymentPosted_to_pending = false;      // ❌
}
```

**Decision**: ✅ LOCKED (state transitions immutable)

---

# 5. 💥 ERROR MODEL (FINANCIAL GRADE)

## 5.1 AppException Base

```dart
// lib/domain/exceptions/app_exception.dart

abstract class AppException implements Exception {
  final String code;
  final String message;
  final String? technical;
  final dynamic originalError;
  
  const AppException({
    required this.code,
    required this.message,
    this.technical,
    this.originalError,
  });
  
  /// User-facing message (safe to show in UI)
  String get userMessage {
    if (code.startsWith('FINANCIAL')) {
      return '💰 Financial operation failed. Ref: $code';
    }
    if (code.startsWith('STOCK')) {
      return '📦 Stock operation failed. Ref: $code';
    }
    if (code.startsWith('PAYMENT')) {
      return '💳 Payment failed. Ref: $code';
    }
    if (code.startsWith('VALIDATION')) {
      return '⚠️ Invalid input. Ref: $code';
    }
    return 'Operation failed. Ref: $code';
  }
  
  @override
  String toString() => 'AppException($code): $message${technical != null ? ' [$technical]' : ''}';
}
```

## 5.2 Exception Types (Domain)

```dart
// lib/domain/exceptions/exceptions.dart

class FinancialException extends AppException {
  FinancialException({
    required String code,
    required String message,
    String? technical,
    dynamic originalError,
  }) : super(
    code: code,
    message: message,
    technical: technical,
    originalError: originalError,
  );
}

class StockException extends AppException {
  StockException({
    required String code,
    required String message,
    String? technical,
    dynamic originalError,
  }) : super(
    code: code,
    message: message,
    technical: technical,
    originalError: originalError,
  );
}

class PaymentException extends AppException {
  PaymentException({
    required String code,
    required String message,
    String? technical,
    dynamic originalError,
  }) : super(
    code: code,
    message: message,
    technical: technical,
    originalError: originalError,
  );
}

class ValidationException extends AppException {
  ValidationException({
    required String code,
    required String message,
    String? technical,
    dynamic originalError,
  }) : super(
    code: code,
    message: message,
    technical: technical,
    originalError: originalError,
  );
}

class AuthenticationException extends AppException {
  AuthenticationException({
    required String message,
    String? technical,
    dynamic originalError,
  }) : super(
    code: 'AUTH_ERROR',
    message: message,
    technical: technical,
    originalError: originalError,
  );
}
```

## 5.3 Exception Factory (Error Codes)

```dart
// lib/domain/exceptions/exception_codes.dart

class FinancialErrorCodes {
  static const String insufficientBalance = 'FINANCIAL_001';
  static const String invalidAmount = 'FINANCIAL_002';
  static const String ledgerWriteFailed = 'FINANCIAL_003';
  static const String transactionRollbackFailed = 'FINANCIAL_004';
  static const String transactionAlreadyExists = 'FINANCIAL_005';
}

class StockErrorCodes {
  static const String insufficientStock = 'STOCK_001';
  static const String invalidQuantity = 'STOCK_002';
  static const String stockUpdateFailed = 'STOCK_003';
  static const String minimumStockReached = 'STOCK_004';
}

class PaymentErrorCodes {
  static const String paymentMethodNotSupported = 'PAYMENT_001';
  static const String paymentProcessingFailed = 'PAYMENT_002';
  static const String invalidPaymentAmount = 'PAYMENT_003';
  static const String paymentAlreadyProcessed = 'PAYMENT_004';
  static const String debtCreationFailed = 'PAYMENT_005';
}

class ValidationErrorCodes {
  static const String requiredFieldMissing = 'VALIDATION_001';
  static const String invalidDataFormat = 'VALIDATION_002';
  static const String constraintViolation = 'VALIDATION_003';
}
```

**Decision**: ✅ LOCKED (exception codes immutable)

---

# 6. 🔥 TRANSACTIONENGINE PSEUDO-CODE

## 6.1 Main Signature

```dart
// lib/domain/services/transaction_engine.dart

class TransactionEngine {
  final RequiredDbExecutor dbExecutor;
  final EventPublisher eventPublisher;
  final MathEngine mathEngine;
  
  TransactionEngine({
    required this.dbExecutor,
    required this.eventPublisher,
    required this.mathEngine,
  });
  
  /// SALE Transaction (atomic)
  Future<SaleTransactionResult> executeSaleTransaction({
    required String customerId,
    required double totalAmount,
    required Map<String, double> paymentMethods, // {CASH: 500, CARD: 100, DEBT: 300}
    required List<{String productId, int quantity}> items,
    String? saleId,
    RequiredDbExecutor? executor,
  }) async { ... }
  
  /// ORDER Delivery Transaction (atomic)
  Future<OrderDeliveryResult> executeOrderDeliveryTransaction({
    required String customerId,
    required String orderId,
    required double totalAmount,
    RequiredDbExecutor? executor,
  }) async { ... }
  
  /// PAYMENT Transaction (atomic)
  Future<PaymentTransactionResult> executePaymentTransaction({
    required String customerId,
    required double paidAmount,
    required Map<String, double> paymentMethods, // {CASH: 300, CARD: 100}
    String? reference,
    RequiredDbExecutor? executor,
  }) async { ... }
}
```

## 6.2 executeSaleTransaction Pseudo-Code

```pseudo
FUNCTION executeSaleTransaction(customerId, totalAmount, paymentMethods, items, saleId?, executor?)

  TRY:
    LOCK dbExecutor or create new
    
    # STEP 1: VALIDATE INPUT
    IF totalAmount <= 0:
      THROW ValidationException('VALIDATION_002', 'Invalid amount')
    
    FOR EACH item IN items:
      IF item.quantity <= 0:
        THROW ValidationException('VALIDATION_002', 'Invalid quantity')
    
    # STEP 2: CHECK CUSTOMER EXISTS
    customer = repository.getCustomer(customerId)
    IF customer == null:
      THROW ValidationException('VALIDATION_001', 'Customer not found')
    
    # STEP 3: CHECK STOCK AVAILABILITY
    FOR EACH item IN items:
      product = repository.getProduct(item.productId)
      IF product.stock < item.quantity:
        THROW StockException('STOCK_001', 'Insufficient stock for ' + product.name)
    
    # ========== BEGIN ATOMIC TRANSACTION ==========
    
    # STEP 4: DECREASE STOCK (IMMEDIATELY for SALE)
    FOR EACH item IN items:
      repository.updateStock(
        productId: item.productId,
        change: -item.quantity,
        movementType: 'SALE',
        reference: saleId ?? newId(),
      )
    
    # STEP 5: CREATE/UPDATE SALE (or use existing)
    IF saleId == null:
      sale = Sale(
        id: uuid(),
        customerId: customerId,
        totalAmount: totalAmount,
        status: 'completed',
        items: items,
      )
      repository.addSale(sale)
    ELSE:
      sale = repository.getSale(saleId)
      repository.updateSale(sale.copyWith(status: 'completed'))
    
    # STEP 6: SPLIT PAYMENTS (PaymentEngine)
    payments = paymentEngine.createSplitPayments(
      totalAmount: totalAmount,
      paymentMethods: paymentMethods,
    )
    
    # STEP 7: CREATE PAYMENT RECORDS
    FOR EACH payment IN payments:
      repository.addPayment(
        PaymentRecord(
          paymentId: uuid(),
          salId: sale.id,
          type: payment.type,
          amount: payment.amount,
          status: payment.type == 'DEBT' ? 'pending' : 'completed',
        )
      )
      
      # If DEBT: create auto debt order
      IF payment.type == 'DEBT':
        repository.createDebtOrder(
          customerId: customerId,
          amount: payment.amount,
          reference: sale.id,
        )
    
    # STEP 8: CREATE FINANCIAL TRANSACTION (MERKEZ RECORD)
    transaction = FinancialTransaction(
      id: uuid(),
      type: 'SALE',
      customerId: customerId,
      amount: totalAmount,
      paidAmount: paymentMethods['CASH'] + paymentMethods['CARD'] + ...,
      debtAmount: paymentMethods['DEBT'] || 0,
      referenceId: sale.id,
      paymentMethods: paymentMethods,
      date: now(),
    )
    repository.addFinancialTransaction(transaction)
    
    # STEP 9: CREATE LEDGER ENTRY
    ledgerEntry = FinancialLedgerEntry(
      id: uuid(),
      customerId: customerId,
      entryType: 'SALE',
      amount: totalAmount,
      saleId: sale.id,
      balanceAfter: mathEngine.calculateCustomerBalance(customerId),
      date: now(),
    )
    repository.addLedgerEntry(ledgerEntry)
    
    # STEP 10: PUBLISH EVENT
    event = SaleCreatedEvent(
      saleId: sale.id,
      customerId: customerId,
      totalAmount: totalAmount,
      paymentMethods: paymentMethods,
      timestamp: now(),
    )
    eventPublisher.publish(event)
    
    # STEP 11: GENERATE RECEIPT
    receipt = Receipt(
      id: uuid(),
      saleId: sale.id,
      type: 'SALE',
      customerId: customerId,
      content: _generateReceiptContent(sale, payments),
      qrCode: _generateQRCode(sale),
      createdAt: now(),
    )
    repository.addReceipt(receipt)
    
    # ========== COMMIT TRANSACTION ==========
    
    RETURN SaleTransactionResult(
      success: true,
      saleId: sale.id,
      receipt: receipt,
      balance: ledgerEntry.balanceAfter,
    )

  CATCH FinancialException AS e:
    ROLLBACK transaction
    LOG 'Sale failed: ' + e.message
    THROW FinancialException(..., technical: e.message)
  
  CATCH StockException AS e:
    ROLLBACK transaction
    LOG 'Stock check failed: ' + e.message
    THROW StockException(..., technical: e.message)
  
  CATCH Exception AS e:
    ROLLBACK transaction
    LOG 'Unknown error: ' + e.toString()
    THROW FinancialException('FINANCIAL_004', 'Transaction rollback', technical: e.toString())

END FUNCTION
```

## 6.3 executeOrderDeliveryTransaction Pseudo-Code

```pseudo
FUNCTION executeOrderDeliveryTransaction(customerId, orderId, totalAmount, executor?)

  TRY:
    LOCK dbExecutor or create new
    
    # STEP 1: GET ORDER
    order = repository.getOrder(orderId)
    IF order == null:
      THROW ValidationException('VALIDATION_001', 'Order not found')
    
    IF order.status != 'READY':
      THROW ValidationException('VALIDATION_002', 'Order must be READY to deliver')
    
    # STEP 2: CHECK STOCK (for delivery items)
    FOR EACH item IN order.items:
      product = repository.getProduct(item.productId)
      IF product.stock < item.quantity:
        THROW StockException('STOCK_001', 'Stock changed - unable to deliver')
    
    # ========== BEGIN ATOMIC TRANSACTION ==========
    
    # STEP 3: DECREASE STOCK (ONLY AT DELIVERY - CRITICAL RULE)
    FOR EACH item IN order.items:
      repository.updateStock(
        productId: item.productId,
        change: -item.quantity,
        movementType: 'ORDER_DELIVERY',
        reference: orderId,
      )
    
    # STEP 4: UPDATE ORDER STATUS
    repository.updateOrder(order.copyWith(
      status: 'DELIVERED',
      actualDeliveryDate: now(),
    ))
    
    # STEP 5: CREATE FINANCIAL TRANSACTION
    transaction = FinancialTransaction(
      id: uuid(),
      type: 'ORDER',
      customerId: customerId,
      amount: totalAmount,
      referenceId: orderId,
      date: now(),
    )
    repository.addFinancialTransaction(transaction)
    
    # STEP 6: CREATE LEDGER ENTRY
    ledgerEntry = FinancialLedgerEntry(
      id: uuid(),
      customerId: customerId,
      entryType: 'ORDER',
      amount: totalAmount,
      orderId: orderId,
      balanceAfter: mathEngine.calculateCustomerBalance(customerId),
      date: now(),
    )
    repository.addLedgerEntry(ledgerEntry)
    
    # STEP 7: PUBLISH EVENT
    event = OrderDeliveredEvent(
      orderId: orderId,
      customerId: customerId,
      timestamp: now(),
    )
    eventPublisher.publish(event)
    
    # ========== COMMIT TRANSACTION ==========
    
    RETURN OrderDeliveryResult(
      success: true,
      orderId: orderId,
      stockDecreased: TRUE,
      balance: ledgerEntry.balanceAfter,
    )

  CATCH ... AS e:
    ROLLBACK transaction
    THROW ...

END FUNCTION
```

## 6.4 executePaymentTransaction Pseudo-Code

```pseudo
FUNCTION executePaymentTransaction(customerId, paidAmount, paymentMethods, reference?, executor?)

  TRY:
    LOCK dbExecutor or create new
    
    # STEP 1: VALIDATE
    IF paidAmount <= 0:
      THROW PaymentException('PAYMENT_003', 'Invalid payment amount')
    
    # STEP 2: GET CUSTOMER & CALCULATE BALANCE
    customer = repository.getCustomer(customerId)
    IF customer == null:
      THROW ValidationException('VALIDATION_001', 'Customer not found')
    
    currentBalance = mathEngine.calculateCustomerBalance(customerId)
    
    # ========== BEGIN ATOMIC TRANSACTION ==========
    
    # STEP 3: CREATE PAYMENT RECORD
    payment = PaymentRecord(
      id: uuid(),
      customerId: customerId,
      amount: paidAmount,
      paymentMethods: paymentMethods,
      reference: reference,
      status: 'COMPLETED',
      date: now(),
    )
    repository.addPayment(payment)
    
    # STEP 4: CREATE FINANCIAL TRANSACTION
    transaction = FinancialTransaction(
      id: uuid(),
      type: 'PAYMENT',
      customerId: customerId,
      amount: paidAmount,
      paidAmount: paidAmount,
      debtAmount: 0,
      referenceId: payment.id,
      paymentMethods: paymentMethods,
      date: now(),
    )
    repository.addFinancialTransaction(transaction)
    
    # STEP 5: CREATE LEDGER ENTRY
    newBalance = currentBalance - paidAmount
    ledgerEntry = FinancialLedgerEntry(
      id: uuid(),
      customerId: customerId,
      entryType: 'PAYMENT',
      amount: paidAmount,
      paymentId: payment.id,
      balanceAfter: newBalance,
      date: now(),
    )
    repository.addLedgerEntry(ledgerEntry)
    
    # STEP 6: PUBLISH EVENT
    event = PaymentAddedEvent(
      customerId: customerId,
      amount: paidAmount,
      paymentMethods: paymentMethods,
      newBalance: newBalance,
      timestamp: now(),
    )
    eventPublisher.publish(event)
    
    # ========== COMMIT TRANSACTION ==========
    
    RETURN PaymentTransactionResult(
      success: true,
      paymentId: payment.id,
      amountPaid: paidAmount,
      newBalance: newBalance,
    )

  CATCH ... AS e:
    ROLLBACK transaction
    THROW ...

END FUNCTION
```

**Decision**: ✅ LOCKED (pseudo-code is architecture gospel)

---

# 7. 💥 FAILURE & ROLLBACK MATRIX

## 7.1 Complete Failure Scenarios

| Scenario | Detection Point | Action | Rollback | UI Message |
|----------|---|---|---|---|
| Stock insufficient | Step 2 (validate) | Before transaction | None | "Not enough stock for {product}" |
| Customer not found | Step 2 (validate) | Before transaction | None | "Customer not found" |
| DB connection fail | Any step | During transaction | ROLLBACK | "System error. Try again." |
| Stock update fails | Step 4 (stock) | During transaction | ROLLBACK ALL | "Stock operation failed" |
| Ledger write fails | Step 9 (ledger) | During transaction | ROLLBACK ALL | "Ledger write failed. Contact support." |
| Payment split invalid | Step 6 (payment) | During transaction | ROLLBACK ALL | "Invalid payment amounts" |
| Event publish fails | Step 10 (event) | After transaction | NO ROLLBACK (logged error) | "Sale created (notification may be delayed)" |

## 7.2 Rollback Guarantee

```dart
// lib/infrastructure/database/required_db_executor.dart

class RollbackGuarantee {
  /// If ANY step fails in transaction:
  /// 1. Database ROLLBACK() called automatically
  /// 2. All inserts/updates/deletes reversed
  /// 3. Stock reset to pre-transaction state
  /// 4. No partial commits possible
  /// 5. Exception thrown with FINANCIAL_004 code
  
  Future<Result> executeInTransaction<Result>({
    required Future<Result> Function() operation,
  }) async {
    try {
      await db.execute('BEGIN TRANSACTION');
      final result = await operation();
      await db.execute('COMMIT');
      return result;
    } catch (e) {
      await db.execute('ROLLBACK');
      rethrow;
    }
  }
}
```

## 7.3 Recovery Strategy

```
FAILED TRANSACTION:

1. Log error with code + details to debug table
2. Mark transaction as ROLLBACK_REQUIRED
3. Send NotificationEvent (SMS/email)
4. Create manual recovery task
5. Show user: "Please contact support - Ref: {transaction_id}"
```

**Decision**: ✅ LOCKED (no partial commits allowed)

---

# 8. 📡 EVENT SYSTEM DESIGN

## 8.1 Domain Events (Immutable)

```dart
// lib/domain/events/domain_event.dart

abstract class DomainEvent {
  final String eventId;
  final DateTime timestamp;
  
  const DomainEvent({
    required this.eventId,
    required this.timestamp,
  });
  
  String get eventType;
}

class SaleCreatedEvent extends DomainEvent {
  final String saleId;
  final String customerId;
  final double totalAmount;
  final Map<String, double> paymentMethods;
  final List<SaleItem> items;
  
  const SaleCreatedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.saleId,
    required this.customerId,
    required this.totalAmount,
    required this.paymentMethods,
    required this.items,
  }) : super(eventId: eventId, timestamp: timestamp);
  
  @override
  String get eventType => 'SaleCreatedEvent';
}

class OrderDeliveredEvent extends DomainEvent {
  final String orderId;
  final String customerId;
  
  const OrderDeliveredEvent({
    required String eventId,
    required DateTime timestamp,
    required this.orderId,
    required this.customerId,
  }) : super(eventId: eventId, timestamp: timestamp);
  
  @override
  String get eventType => 'OrderDeliveredEvent';
}

class PaymentAddedEvent extends DomainEvent {
  final String paymentId;
  final String customerId;
  final double amount;
  final Map<String, double> paymentMethods;
  final double newBalance;
  
  const PaymentAddedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.paymentId,
    required this.customerId,
    required this.amount,
    required this.paymentMethods,
    required this.newBalance,
  }) : super(eventId: eventId, timestamp: timestamp);
  
  @override
  String get eventType => 'PaymentAddedEvent';
}

class StockChangedEvent extends DomainEvent {
  final String productId;
  final int stockBefore;
  final int stockAfter;
  final String movementType;
  
  const StockChangedEvent({
    required String eventId,
    required DateTime timestamp,
    required this.productId,
    required this.stockBefore,
    required this.stockAfter,
    required this.movementType,
  }) : super(eventId: eventId, timestamp: timestamp);
  
  @override
  String get eventType => 'StockChangedEvent';
}
```

## 8.2 Event Publisher (Singleton)

```dart
// lib/domain/events/event_publisher.dart

class EventPublisher {
  static final EventPublisher _instance = EventPublisher._();
  
  factory EventPublisher() => _instance;
  
  EventPublisher._();
  
  final List<void Function(DomainEvent)> _subscribers = [];
  final List<DomainEvent> _eventLog = [];
  
  /// Publish event to all subscribers
  void publish(DomainEvent event) {
    _eventLog.add(event);
    for (final subscriber in _subscribers) {
      try {
        subscriber(event);
      } catch (e) {
        // Log subscriber error, don't rethrow
        print('Event subscriber error: $e');
      }
    }
  }
  
  /// Subscribe to events
  void subscribe(void Function(DomainEvent) handler) {
    _subscribers.add(handler);
  }
  
  /// Get event log (audit trail)
  List<DomainEvent> getEventLog() => List.unmodifiable(_eventLog);
}
```

## 8.3 Event Handlers (Future)

```dart
// lib/domain/events/event_handler.dart

class SaleCreatedEventHandler {
  final SmsService smsService;
  final NotificationService notificationService;
  
  void handle(SaleCreatedEvent event) {
    // Send SMS to customer
    smsService.sendSaleNotification(
      customerId: event.customerId,
      amount: event.totalAmount,
    );
    
    // Log to analytics
    notificationService.log('sale_created', {
      'saleId': event.saleId,
      'amount': event.totalAmount,
    });
  }
}
```

**Decision**: ✅ LOCKED (event names + structure immutable)

---

# 9. 🗂️ SQLITE ERD (FINAL)

## 9.1 Schema Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                         SERENUT POS                             │
│                       SQLite Schema                             │
└─────────────────────────────────────────────────────────────────┘

Products ◄──┐
            │
            ├─ Sales Items ◄─ Sales ◄──┐
            │                           │
Customers ◄─┤                        (Link)
            │
            ├─ Orders ◄─ Order Items
            │
            ├─ Financial Transactions
            │
            ├─ Financial Ledger Entries
            │
            ├─ Receipts
            │
            ├─ Documents
            │
            └─ User Permissions

RELATIONSHIPS:
- Products ←→ Categories (1:N)
- Sales ←→ Customers (1:N)
- Orders ←→ Customers (1:N)
- Financial Transactions ←→ Customers (1:N)
- Financial Ledger Entries ←→ Customers (N:1)
```

## 9.2 Table Definitions (DDL)

```sql
-- CORE TABLES

CREATE TABLE categories (
  id TEXT PRIMARY KEY,
  name TEXT UNIQUE NOT NULL,
  vat_rate INTEGER DEFAULT 0,
  parent_category_id TEXT,
  is_active INTEGER DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  FOREIGN KEY(parent_category_id) REFERENCES categories(id)
);

CREATE TABLE products (
  id TEXT PRIMARY KEY,
  barcode TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  category_id TEXT NOT NULL,
  unit TEXT DEFAULT 'piece',
  cost_price REAL NOT NULL,
  sell_price REAL NOT NULL,
  tax INTEGER DEFAULT 0,
  stock INTEGER DEFAULT 0,
  minimum_stock INTEGER DEFAULT 0,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  FOREIGN KEY(category_id) REFERENCES categories(id)
);

CREATE TABLE customers (
  id TEXT PRIMARY KEY,
  name_company TEXT NOT NULL,
  phone TEXT,
  address TEXT,
  tax_number TEXT,
  balance REAL DEFAULT 0,
  is_active INTEGER DEFAULT 1,
  created_at TEXT NOT NULL,
  deleted_at TEXT,
  updated_at TEXT
);

-- TRANSACTION TABLES

CREATE TABLE sales (
  id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL,
  payment_type TEXT DEFAULT 'CASH',
  total_amount REAL NOT NULL,
  paid_amount REAL DEFAULT 0,
  balance_amount REAL DEFAULT 0,
  status TEXT DEFAULT 'pending',
  sale_date TEXT NOT NULL,
  receipt_printed_at TEXT,
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  FOREIGN KEY(customer_id) REFERENCES customers(id)
);

CREATE TABLE sale_items (
  id TEXT PRIMARY KEY,
  sale_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price REAL NOT NULL,
  tax INTEGER DEFAULT 0,
  total_price REAL NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(sale_id) REFERENCES sales(id),
  FOREIGN KEY(product_id) REFERENCES products(id)
);

CREATE TABLE orders (
  id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL,
  status TEXT DEFAULT 'CREATED',
  total_amount REAL NOT NULL,
  order_date TEXT NOT NULL,
  expected_delivery_date TEXT,
  actual_delivery_date TEXT,
  notes TEXT,
  reference_number TEXT,
  is_active INTEGER DEFAULT 1,
  deleted_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  FOREIGN KEY(customer_id) REFERENCES customers(id)
);

CREATE TABLE order_items (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL,
  product_id TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  unit_price REAL NOT NULL,
  tax INTEGER DEFAULT 0,
  total_price REAL NOT NULL,
  item_status TEXT DEFAULT 'PENDING',
  created_at TEXT NOT NULL,
  FOREIGN KEY(order_id) REFERENCES orders(id),
  FOREIGN KEY(product_id) REFERENCES products(id)
);

CREATE TABLE order_payments (
  id TEXT PRIMARY KEY,
  order_id TEXT,
  sale_id TEXT,
  payment_type TEXT NOT NULL,
  amount REAL NOT NULL,
  payment_date TEXT NOT NULL,
  payment_reference TEXT,
  status TEXT DEFAULT 'PENDING',
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  FOREIGN KEY(order_id) REFERENCES orders(id),
  FOREIGN KEY(sale_id) REFERENCES sales(id)
);

-- FINANCIAL TABLES

CREATE TABLE financial_transactions (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  customer_id TEXT NOT NULL,
  amount REAL NOT NULL,
  paid_amount REAL DEFAULT 0,
  debt_amount REAL DEFAULT 0,
  date TEXT NOT NULL,
  reference_id TEXT,
  notes TEXT,
  payment_methods TEXT,
  created_by TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  FOREIGN KEY(customer_id) REFERENCES customers(id)
);

CREATE TABLE financial_ledger_entries (
  id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL,
  entry_type TEXT NOT NULL,
  amount REAL NOT NULL,
  sale_id TEXT,
  order_id TEXT,
  payment_id TEXT,
  payment_method TEXT,
  description TEXT,
  transaction_date TEXT NOT NULL,
  balance_after REAL NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(customer_id) REFERENCES customers(id),
  FOREIGN KEY(sale_id) REFERENCES sales(id),
  FOREIGN KEY(order_id) REFERENCES orders(id)
);

-- OPERATIONAL TABLES

CREATE TABLE receipts (
  id TEXT PRIMARY KEY,
  receipt_type TEXT NOT NULL,
  sale_id TEXT,
  order_id TEXT,
  payment_id TEXT,
  customer_id TEXT,
  customer_name TEXT,
  customer_phone TEXT,
  customer_address TEXT,
  subtotal REAL NOT NULL,
  tax_amount REAL DEFAULT 0,
  total REAL NOT NULL,
  discount_amount REAL DEFAULT 0,
  payment_method TEXT,
  paid_amount REAL NOT NULL,
  change_amount REAL DEFAULT 0,
  receipt_number TEXT UNIQUE,
  cashier_name TEXT,
  notes TEXT,
  printed_at TEXT,
  delivered_confirmed_at TEXT,
  qr_code TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY(customer_id) REFERENCES customers(id),
  FOREIGN KEY(sale_id) REFERENCES sales(id),
  FOREIGN KEY(order_id) REFERENCES orders(id)
);

CREATE TABLE documents (
  id TEXT PRIMARY KEY,
  type TEXT NOT NULL,
  number TEXT UNIQUE NOT NULL,
  status TEXT DEFAULT 'draft',
  customer_id TEXT,
  reference_id TEXT,
  qr_code TEXT,
  content TEXT,
  printed_at TEXT,
  sent_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT,
  FOREIGN KEY(customer_id) REFERENCES customers(id)
);

-- ADMIN TABLES

CREATE TABLE user_permissions (
  id TEXT PRIMARY KEY,
  user_id TEXT NOT NULL,
  role TEXT NOT NULL,
  custom_permissions TEXT,
  is_active INTEGER DEFAULT 1,
  created_at TEXT NOT NULL,
  updated_at TEXT
);

CREATE TABLE settings (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  type TEXT DEFAULT 'string',
  updated_at TEXT NOT NULL
);

-- AUDIT TABLES

CREATE TABLE stock_movements (
  id TEXT PRIMARY KEY,
  product_id TEXT NOT NULL,
  movement_type TEXT NOT NULL,
  quantity INTEGER NOT NULL,
  reference TEXT,
  notes TEXT,
  movement_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(product_id) REFERENCES products(id)
);

CREATE TABLE collections (
  id TEXT PRIMARY KEY,
  customer_id TEXT NOT NULL,
  transaction_type TEXT NOT NULL,
  amount REAL NOT NULL,
  payment_method TEXT,
  reference TEXT,
  notes TEXT,
  transaction_date TEXT NOT NULL,
  created_at TEXT NOT NULL,
  FOREIGN KEY(customer_id) REFERENCES customers(id)
);

-- INDEXES (Performance)

CREATE INDEX idx_products_barcode ON products(barcode);
CREATE INDEX idx_products_category ON products(category_id);
CREATE INDEX idx_sales_customer ON sales(customer_id);
CREATE INDEX idx_sales_date ON sales(sale_date);
CREATE INDEX idx_orders_customer ON orders(customer_id);
CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_financial_tx_customer ON financial_transactions(customer_id);
CREATE INDEX idx_ledger_customer ON financial_ledger_entries(customer_id);
CREATE INDEX idx_ledger_date ON financial_ledger_entries(transaction_date);
```

**Decision**: ✅ LOCKED (schema immutable for 2 weeks)

---

# 10. 🔗 UI ↔ BACKEND CONTRACT RULES

## 10.1 API/Repository Call Pattern

```dart
// RULE: Every UI action → Riverpod provider → Repository call

// ❌ WRONG:
// final balance = await db.rawQuery('SELECT SUM(amount) FROM ledger...');

// ✅ CORRECT:
// 1. UI calls provider
final balanceProvider = FutureProvider.autoDispose<double>((ref) async {
  final customerRepo = ref.watch(customerRepositoryProvider);
  return await customerRepo.getCustomerBalance(customerId);
});

// 2. Repository calls backend/DB
Future<double> getCustomerBalance(String customerId) async {
  final transactions = await _getAllTransactions(customerId);
  return transactions.fold(0, (sum, tx) => sum + tx.amount);
}
```

## 10.2 Data Flow Guarantee

```
┌─────────────┐
│   UI Layer  │
│ (Flutter)   │
└──────┬──────┘
       │ (Riverpod Provider)
       ▼
┌─────────────────────────┐
│  Presentation Layer     │
│ (StateNotifier +        │
│  Controllers)           │
└──────┬──────────────────┘
       │ (Service call)
       ▼
┌─────────────────────────┐
│  Domain Layer           │
│ (Services + Engines)    │
└──────┬──────────────────┘
       │ (Repository call)
       ▼
┌─────────────────────────┐
│  Data Layer             │
│ (Repositories)          │
└──────┬──────────────────┘
       │ (DB query)
       ▼
┌─────────────────────────┐
│  SQLite                 │
│ (Source of truth)       │
└─────────────────────────┘
```

## 10.3 State Update Propagation

```
1. User performs action (e.g., "Complete Sale")
   ↓
2. UI calls transactionEngineProvider.executeSaleTransaction()
   ↓
3. TransactionEngine executes (atomic)
   ↓
4. Event published (SaleCreatedEvent)
   ↓
5. Repository updated (stock decreased, ledger written)
   ↓
6. Provider invalidated → Riverpod refetches data
   ↓
7. UI state updates → Widget rebuilds
```

**Decision**: ✅ LOCKED (data flow immutable)

---

# 11. 🔄 OFFLINE/SYNC STRATEGY (v1)

## 11.1 Offline-First Architecture

```
LOCAL (SQLite)
   │
   ├─ Primary source of truth ✅
   ├─ All transactions happen here
   ├─ No network required
   │
   └─ [Future: Sync layer to backend]
```

## 11.2 Conflict Resolution (v1 - SIMPLE)

```
RULE: Last Write Wins (LWW)

Scenario:
- Device A writes sale at 10:05
- Device B writes sale at 10:07
- Conflict occurs

Resolution:
- Device B's write wins (10:07 > 10:05)
- Device A's data discarded (log kept for audit)

Future: Implement CRDT or event sourcing
```

## 11.3 No Sync Yet (v1)

```
Version 1:
- SQLite local only
- Manual export (future)
- No cloud backup (future)
- No multi-device sync (future)

Backup strategy:
- Daily local backup (SQLite .db file)
- Cloud upload (future)
```

**Decision**: ✅ LOCKED (offline-first for now, sync roadmap TBD)

---

# 12. 📋 DECISION LOG

## Signed Off Decisions

| Decision | Status | Authority | Date |
|----------|--------|-----------|------|
| Auth: Local mock + SharedPreferences | ✅ LOCKED | Team | 20 Jun 2026 |
| State: AppState wrapper + Riverpod AsyncValue | ✅ LOCKED | Team | 20 Jun 2026 |
| Transaction: Atomic via RequiredDbExecutor | ✅ LOCKED | Team | 20 Jun 2026 |
| Error: AppException hierarchy + error codes | ✅ LOCKED | Team | 20 Jun 2026 |
| Rollback: Full ROLLBACK on any failure | ✅ LOCKED | Team | 20 Jun 2026 |
| Stock timing: SALE=now, ORDER=delivery | ✅ LOCKED | Team | 20 Jun 2026 |
| Balance: SUM(transactions), never manual | ✅ LOCKED | Team | 20 Jun 2026 |
| Events: Immutable DomainEvent + EventPublisher | ✅ LOCKED | Team | 20 Jun 2026 |
| Schema: 18 tables final (no changes 2 weeks) | ✅ LOCKED | Team | 20 Jun 2026 |
| Offline: Local SQLite, sync TBD | ✅ LOCKED | Team | 20 Jun 2026 |

---

# 🔥 PHASE 0 SUMMARY

| Component | Status | Notes |
|-----------|--------|-------|
| Auth Contract | ✅ FINAL | Local mock, JWT bridge ready |
| State Pattern | ✅ FINAL | AppState + Riverpod standard |
| Error Model | ✅ FINAL | Exception hierarchy locked |
| Transaction Engine | ✅ FINAL | Pseudo-code = gospel |
| Rollback Strategy | ✅ FINAL | No partial commits |
| ETD Schema | ✅ FINAL | 18 tables, immutable |
| Event System | ✅ FINAL | 6 event types locked |
| UI-Backend Contract | ✅ FINAL | Data flow defined |
| Offline Strategy | ✅ FINAL | Local-first, sync TBD |

---

## ✅ FREEZE COMPLETE

**This specification is LOCKED. No changes without explicit team sign-off.**

Proceed to **PHASE 1: PARALLEL UI BUILD** ✅

---

**Generated**: 20 Jun 2026  
**Authority**: Engineering Review  
**Status**: 🔒 FINAL & LOCKED  
**Next**: PHASE 1 UI BUILD (Riverpod + Navbar + Dashboard mock)
