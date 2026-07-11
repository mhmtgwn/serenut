# 🚀 SERENUT POS — DEVELOPMENT ROADMAP

**Current Status:** June 20, 2026  
**Completed:** Phase 1.2 (Backend %100 locked)  
**Next:** Phase 2 (UI Implementation)

---

## 📊 ARCHITECTURE (COMPLETE)

```
┌────────────────────────────────────┐
│ PRESENTATION (UI - Flutter)        │  ← Phase 2: Build NOW
├────────────────────────────────────┤
│ APPLICATION SERVICES               │  ← ✅ Phase 1.2: DONE
│ • SaleService (atomic)             │    (Transaction-safe, rollback-safe)
│ • StockService (with movements)    │
│ • CustomerService                  │
│ • PrinterService                   │
├────────────────────────────────────┤
│ DOMAIN (Business Logic)            │  ← ✅ Phase 1: DONE
│ • Models (nullable id pattern)     │    (Sale, Product, Customer, etc)
│ • Exceptions (SaleException, etc)  │    (RequiredDbExecutor enforcement)
├────────────────────────────────────┤
│ DATA (Repositories + DB)           │  ← ✅ Phase 1.1: DONE
│ • All repos with executor params   │    (Transaction-aware, all CRUD)
│ • SQLite with 8 tables             │
├────────────────────────────────────┤
│ INFRASTRUCTURE (Devices/Network)   │  ← ✅ Ready
│ • Transaction layer (compile-time) │    (RequiredDbExecutor enforcement)
│ • Database executor abstraction    │
└────────────────────────────────────┘
```

---

## ✅ COMPLETED — Phase 1.2 (Backend Hardening)

### Infrastructure
- ✅ RequiredDbExecutor (compile-time transaction enforcement)
- ✅ SqliteTransaction wrapper
- ✅ AppTransaction interface
- ✅ Full state tracking (isCommitted, isRolledBack, isActive)
- ✅ 4-repo transaction binding

### Core Services
- ✅ SaleService.createSale() — atomic multi-repo operation
- ✅ SaleService.cancelSale() — rollback-safe reversal
- ✅ Complete validation (stock, customer, items)
- ✅ StockMovement recording (type: 1=in, 2=out, 3=count, 4=correction, 5=waste)

### Models
- ✅ Nullable id pattern (DB owns ID generation)
- ✅ Sale with status (1=pending, 2=completed, 3=cancelled)
- ✅ toMap(includeId) for UPDATE operations
- ✅ Null-safe fromMap() factories
- ✅ copyWith() for all models

### Exception Hierarchy
- ✅ SaleException (sale-specific)
- ✅ StockException (stock-specific, with productId)
- ✅ TransactionException (low-level)
- ✅ All exceptions with code + message for UI

### Repository Updates
- ✅ All 6 repos accept optional [DbExecutor?] parameter
- ✅ ProductRepository.updateStock(productId, quantity, [executor])
- ✅ SaleRepository.updateSale()
- ✅ StockRepository fully transaction-safe
- ✅ CustomerRepository fully transaction-safe
- ✅ Backward compatible (optional executor)

### Quality
- ✅ Zero compilation errors
- ✅ Type-safe transaction enforcement
- ✅ All-or-nothing atomicity
- ✅ No partial commits possible
- ✅ Rollback on any failure

---

## 🎨 PHASE 2 — UI IMPLEMENTATION (4–6 days)

### Goals
1. Create user-facing screens
2. Connect UI to services
3. Handle errors gracefully
4. Provide feedback (loading, success, errors)
5. Make POS **work end-to-end**

### Architecture Pattern: Riverpod + Controller + StateNotifier

```
UI Layer (Pages)
    ↓
Controllers (StateNotifier + CRUD logic)
    ↓
Services (Business logic)
    ↓
Repositories (Data access)
    ↓
Database (SQLite)
```

Key: **UI never calls services directly. Always through controller.**

---

## 📋 PHASE 2 BREAKDOWN

### 2.1 Setup & Infrastructure (0.5 day)

**Create:**
- `lib/presentation/` (directory structure)
- `lib/presentation/controllers/` (state management)
- `lib/presentation/pages/` (screens)
- `lib/presentation/widgets/` (reusable components)

**Riverpod providers for services:**
```dart
// lib/providers/service_providers.dart

final saleServiceProvider = Provider((ref) {
  final database = ref.watch(databaseServiceProvider);
  return SaleService(
    database: database,
    saleRepository: ref.watch(saleRepositoryProvider),
    productRepository: ref.watch(productRepositoryProvider),
    customerRepository: ref.watch(customerRepositoryProvider),
    stockRepository: ref.watch(stockRepositoryProvider),
  );
});

final customerServiceProvider = Provider((ref) {
  return CustomerService(
    customerRepository: ref.watch(customerRepositoryProvider),
    saleRepository: ref.watch(saleRepositoryProvider),
  );
});

final stockServiceProvider = Provider((ref) {
  return StockService(
    stockRepository: ref.watch(stockRepositoryProvider),
    productRepository: ref.watch(productRepositoryProvider),
  );
});
```

---

### 2.2 Core Screens (1.5 days)

#### Screen 1: Dashboard (Home)
- Display: today's sales total, pending transactions, critical stock items
- Actions: New Sale, View Reports, Settings
- **File:** `lib/presentation/pages/dashboard_page.dart`

```dart
@override
Widget build(BuildContext context, WidgetRef ref) {
  final todaysSales = ref.watch(todaysSalesProvider);
  
  return Scaffold(
    appBar: AppBar(title: Text('SERENUT POS')),
    body: Column(
      children: [
        // KPI Cards
        SalesKpiCard(total: todaysSales),
        PendingTransactionsCard(),
        CriticalStockCard(),
        
        // Action Buttons
        Row(
          children: [
            ElevatedButton(
              onPressed: () => Navigator.push(...NewSalePage),
              child: Text('YENİ SATIŞ'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.push(...ReportsPage),
              child: Text('RAPORLAR'),
            ),
          ],
        ),
      ],
    ),
  );
}
```

#### Screen 2: Sales (Core Transaction)
- **File:** `lib/presentation/pages/sales_page.dart`
- **Controller:** `lib/presentation/controllers/sales_controller.dart`

Main UI:
```
┌─────────────────────────────┐
│ Customer: [Dropdown]        │
├─────────────────────────────┤
│ Product Search/Barcode      │
│ ┌─────────────────────────┐ │
│ │ Product | Qty | Price   │ │
│ │ Widget  |  2  | 50.00   │ │
│ │ Pencil  |  5  | 2.50    │ │
│ └─────────────────────────┘ │
├─────────────────────────────┤
│ Subtotal:    100.00         │
│ Tax (%18):    18.00         │
│ Total:       118.00         │
├─────────────────────────────┤
│ Payment: [Cash] [Card] [Cr] │
├─────────────────────────────┤
│ [ Clear ] [ Save ] [ Done ] │
└─────────────────────────────┘
```

**Workflow:**
```dart
// User scans/selects product
salesController.addItem(productId: 123, quantity: 2)

// UI updates with item

// User selects customer + payment type

// User presses "Satış Tamamla"
await salesController.finalizeSale()

// Shows success or error
if (state.isSuccess) {
  show receipt preview
} else if (state.isError) {
  show error message + retry
}
```

#### Screen 3: Products (Stock Management)
- **File:** `lib/presentation/pages/products_page.dart`
- **Controller:** `lib/presentation/controllers/products_controller.dart`

- Display: all products with current stock
- Actions: Add product, edit, delete, adjust stock
- Search/filter by barcode or name

#### Screen 4: Customers (Credit Management)
- **File:** `lib/presentation/pages/customers_page.dart`
- **Controller:** `lib/presentation/controllers/customers_controller.dart`

- Display: customers with current balance
- Actions: Add customer, edit, view history, collect payment

#### Screen 5: Reports (Analytics)
- **File:** `lib/presentation/pages/reports_page.dart`

- Daily sales by category, product, customer
- Stock movements (in/out/correction)
- Customer debt tracking

---

### 2.3 Controllers & State Management (1 day)

**Pattern for each screen:**

```dart
// lib/presentation/controllers/sales_controller.dart

class SaleState {
  final List<SaleItem> items;
  final int? customerId;
  final int paymentType;
  final bool isLoading;
  final Sale? completedSale;
  final String? error;
  
  SaleState({
    required this.items,
    this.customerId,
    this.paymentType = 1,
    this.isLoading = false,
    this.completedSale,
    this.error,
  });
  
  SaleState copyWith({
    List<SaleItem>? items,
    int? customerId,
    int? paymentType,
    bool? isLoading,
    Sale? completedSale,
    String? error,
  }) {
    return SaleState(
      items: items ?? this.items,
      customerId: customerId ?? this.customerId,
      paymentType: paymentType ?? this.paymentType,
      isLoading: isLoading ?? this.isLoading,
      completedSale: completedSale,
      error: error,
    );
  }
}

class SalesController extends StateNotifier<SaleState> {
  final SaleService saleService;
  final ProductRepository productRepository;
  
  SalesController({
    required this.saleService,
    required this.productRepository,
  }) : super(SaleState(items: []));
  
  Future<void> addItem(int productId, int quantity) async {
    final product = await productRepository.getProductById(productId);
    if (product == null) return;
    
    final item = SaleItem(
      productId: productId,
      quantity: quantity,
      unitPrice: product.sellPrice,
      tax: product.tax,
      totalPrice: quantity * product.sellPrice,
      createdAt: DateTime.now(),
    );
    
    state = state.copyWith(
      items: [...state.items, item],
    );
  }
  
  Future<void> removeItem(int index) async {
    final items = [...state.items];
    items.removeAt(index);
    state = state.copyWith(items: items);
  }
  
  Future<void> finalizeSale() async {
    if (state.items.isEmpty) {
      state = state.copyWith(error: 'Satış öğesi ekleyin');
      return;
    }
    if (state.customerId == null) {
      state = state.copyWith(error: 'Müşteri seçin');
      return;
    }
    
    state = state.copyWith(isLoading: true);
    
    try {
      final totalAmount = state.items.fold<double>(
        0,
        (sum, item) => sum + item.totalPrice,
      );
      
      final sale = Sale(
        customerId: state.customerId!,
        totalAmount: totalAmount,
        paidAmount: totalAmount,
        balanceAmount: state.paymentType == 3 ? totalAmount : 0,
        paymentType: state.paymentType,
        status: 1, // pending
        saleDate: DateTime.now(),
        createdAt: DateTime.now(),
      );
      
      final result = await saleService.createSale(
        sale: sale,
        items: state.items,
      );
      
      state = state.copyWith(
        isLoading: false,
        completedSale: result.saleWithId,
        items: [],
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }
}

// Riverpod provider
final salesControllerProvider =
    StateNotifierProvider<SalesController, SaleState>((ref) {
  return SalesController(
    saleService: ref.watch(saleServiceProvider),
    productRepository: ref.watch(productRepositoryProvider),
  );
});
```

---

### 2.4 Shared Widgets (0.5 day)

Create reusable components:
- **ProductListItem** — product card with stock indicator
- **SaleItemRow** — line item in sale
- **CustomerSelector** — dropdown for customer selection
- **PaymentTypeSelector** — cash/card/credit radio buttons
- **ErrorDialog** — show error messages
- **SuccessSnackBar** — transaction success feedback
- **LoadingOverlay** — semi-transparent loading spinner

**File:** `lib/presentation/widgets/`
```
widgets/
  ├─ product_list_item.dart
  ├─ sale_item_row.dart
  ├─ customer_selector.dart
  ├─ payment_selector.dart
  ├─ error_dialog.dart
  ├─ success_snackbar.dart
  └─ loading_overlay.dart
```

---

### 2.5 Error Handling & User Feedback (0.5 day)

**Error scenarios:**

1. **Insufficient Stock**
   ```
   ❌ Stok yok: Widget (mevcut: 5, istenen: 10)
   → Show in RED in cart
   → Block checkout
   ```

2. **Network Error (Printer)**
   ```
   ❌ Yazıcıyla bağlantı yok
   → Sale still completes (receipt = optional)
   → Show: "Satış tamamlandı, alındı yazılamadı"
   ```

3. **Transaction Timeout**
   ```
   ❌ İşlem zaman aşımına uğradı
   → Automatic rollback by DB
   → Show: "Lütfen tekrar deneyin"
   ```

4. **Customer Not Found**
   ```
   ❌ Müşteri bulunamadı
   → Clear error, allow selection
   ```

**All exceptions map to user messages:**
```dart
String exceptionToMessage(Exception e) {
  if (e is SaleException) {
    return switch(e.code) {
      'EMPTY_SALE' => 'Satış öğesi ekleyin',
      'INSUFFICIENT_STOCK' => 'Stok yetersiz: ${e.productId}',
      'CUSTOMER_NOT_FOUND' => 'Müşteri bulunamadı',
      'INVALID_QUANTITY' => 'Miktar 0\'dan büyük olmalı',
      _ => e.message,
    };
  }
  // ... handle other exception types
}
```

---

## 📅 TIMELINE (Phase 2)

| Day | Task | Files |
|-----|------|-------|
| Day 1 | 2.1 (Setup) + 2.2 Dashboard | dashboard_page.dart, providers |
| Day 2 | 2.2 Sales page + controller | sales_page.dart, sales_controller.dart |
| Day 3 | 2.2 Products + Customers | products_page.dart, customers_page.dart |
| Day 4 | 2.3 All controllers | *_controller.dart |
| Day 5 | 2.4 Shared widgets | widgets/* |
| Day 6 | 2.5 Error handling + testing | exception mapping |

**Checkpoint:** End of Day 6 = **Fully working POS MVP**

---

## 🧪 TESTING PHASE 2

### Manual Testing
1. Create sale (happy path): Product → Customer → Cash → Print ✓
2. Insufficient stock: Try to sell more than available → error ✓
3. Credit sale: Select customer → Payment type = Credit → Balance updated ✓
4. Cancel sale: Complete → Cancel → Stock increases, balance reverses ✓
5. Multiple customers: Same products, verify each customer isolated ✓

### Edge Cases
- Duplicate barcode scan
- Zero-price product
- Negative quantity input
- Printer offline during sale
- App crash mid-transaction (verify rollback on restart)

---

## 🎯 SUCCESS CRITERIA

After Phase 2, system must:

✅ **Functional**
- User can create complete sales end-to-end
- Receipts print correctly
- Inventory accurate after sale

✅ **Safe**
- Stock never goes negative
- No orphan records
- Transaction rollback on failure

✅ **Usable**
- Dashboard shows today's sales
- Product search by barcode or name works
- Customer credit tracking visible
- Error messages clear

✅ **Ready for Android**
- No platform-specific code in business logic
- Services are platform-agnostic
- Ready to add platform-specific UI layers

---

## 🚀 AFTER PHASE 2 (Phase 3+)

Once MVP works:

1. **Receipt Reports** — X/Z reports from PrinterService
2. **Cloud Backup** — Sync to cloud (optional, enterprise)
3. **Android UI** — Same backend, mobile UI
4. **Analytics** — Dashboard, trending products, customer lifetime value
5. **Multi-printer** — Support multiple thermal printers
6. **Advanced Inventory** — Stock counts, waste tracking, corrections
