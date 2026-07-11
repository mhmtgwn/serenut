# 🚀 PHASE 1 — PARALLEL UI BUILD (ENGINEER-READY)

**Status**: 🟡 PARALLEL WITH PHASE 0  
**Duration**: 3-5 days (mock data only)  
**Constraint**: ⚠️ NO real TransactionEngine calls until PHASE 0 complete  
**Purpose**: UI skeleton + routing + mock data layer  

---

## 📋 TABLE OF CONTENTS

1. [Build Strategy](#1-build-strategy)
2. [Riverpod Setup (Template)](#2-riverpod-setup-template)
3. [Project Structure](#3-project-structure)
4. [Bottom Navbar System](#4-bottom-navbar-system)
5. [Mock Data Layer](#5-mock-data-layer)
6. [Screen Skeleton with Mocks](#6-screen-skeleton-with-mocks)
7. [Router Setup](#7-router-setup)
8. [Shared Widgets (Mock)](#8-shared-widgets-mock)
9. [State Management Pattern](#9-state-management-pattern)
10. [Build Checklist](#10-build-checklist)

---

# 1. 🎯 BUILD STRATEGY

## 1.1 What to Build (THIS PHASE)

```
✅ Riverpod DI container
✅ Bottom navbar (responsive, role-based, settings toggle)
✅ 8 screen skeletons (login, dashboard, sales, orders, customers, payments, inventory, reports)
✅ Mock data layer (fake products, customers, sales)
✅ Router (go_router setup)
✅ Shared widgets (search, selector, input fields - mock versions)
✅ Theme (colors: green #2E7D32, yellow #FFD600, red, orange)
```

## 1.2 What NOT to Build (YET)

```
❌ Real TransactionEngine calls
❌ Real database queries (SQLite ← PHASE 0)
❌ Real payment processing
❌ Real stock updates
❌ Real ledger writes
❌ Real event publishing
❌ Printer integration
❌ SMS integration
```

## 1.3 Timeline

```
Day 1: Riverpod setup + Router + Mock data layer
Day 2: Bottom navbar + Login + Dashboard
Day 3: Sales screen skeleton + Cart mock
Day 4: Orders + Customers + Inventory mocks
Day 5: Payments + Reports mocks + Shared widgets
```

---

# 2. 🧩 RIVERPOD SETUP (TEMPLATE)

## 2.1 Install Dependencies

```yaml
# pubspec.yaml

dependencies:
  flutter:
    sdk: flutter
  riverpod: ^2.4.0
  flutter_riverpod: ^2.4.0
  go_router: ^12.0.0
  shared_preferences: ^2.2.0
  intl: ^0.19.0
  uuid: ^4.0.0

dev_dependencies:
  build_runner: ^2.4.0
  riverpod_generator: ^2.3.0
```

## 2.2 DI Container (Main Provider)

```dart
// lib/presentation/providers/app_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shaman_new/domain/services/auth_service.dart';
import 'package:shaman_new/data/repositories/mock_repositories.dart';

// ═══════════════════════════════════════════════════════════
// SERVICES
// ═══════════════════════════════════════════════════════════

final authServiceProvider = Provider((ref) => AuthService());

// ═══════════════════════════════════════════════════════════
// REPOSITORIES (MOCK - will swap with real repositories in PHASE 0)
// ═══════════════════════════════════════════════════════════

final mockProductRepositoryProvider = Provider((ref) => MockProductRepository());
final mockCustomerRepositoryProvider = Provider((ref) => MockCustomerRepository());
final mockSaleRepositoryProvider = Provider((ref) => MockSaleRepository());
final mockOrderRepositoryProvider = Provider((ref) => MockOrderRepository());

// ═══════════════════════════════════════════════════════════
// FUTURE PROVIDERS (for async data fetching)
// ═══════════════════════════════════════════════════════════

final productListProvider = FutureProvider.autoDispose<List<ProductDTO>>((ref) async {
  final repo = ref.watch(mockProductRepositoryProvider);
  return repo.getAllProducts(); // mock data
});

final customerListProvider = FutureProvider.autoDispose<List<CustomerDTO>>((ref) async {
  final repo = ref.watch(mockCustomerRepositoryProvider);
  return repo.getAllCustomers(); // mock data
});

final saleHistoryProvider = FutureProvider.autoDispose<List<SaleDTO>>((ref) async {
  final repo = ref.watch(mockSaleRepositoryProvider);
  return repo.getAllSales(); // mock data
});

// ═══════════════════════════════════════════════════════════
// STATE NOTIFIERS (for mutable state)
// ═══════════════════════════════════════════════════════════

final cartStateProvider = StateNotifierProvider<CartNotifier, AppState<CartState>>((ref) {
  return CartNotifier();
});

final selectedCustomerProvider = StateProvider<CustomerDTO?>((ref) => null);
final selectedProductProvider = StateProvider<ProductDTO?>((ref) => null);
```

## 2.3 AppState Wrapper Implementation

```dart
// lib/presentation/state/app_state.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

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

// ✅ USAGE IN UI:
// 
// ref.watch(productListProvider).when(
//   loading: () => CircularProgressIndicator(),
//   error: (err, stack) => Text('Error: $err'),
//   data: (products) => ListView(...),
// );
```

---

# 3. 📁 PROJECT STRUCTURE

```
lib/
├── main.dart ← ⭐ Entrypoint
├── presentation/
│   ├── providers/
│   │   ├── app_providers.dart ← DI container
│   │   ├── auth_provider.dart
│   │   ├── product_provider.dart
│   │   └── cart_provider.dart
│   ├── state/
│   │   ├── app_state.dart ← State wrapper
│   │   ├── cart_state.dart
│   │   └── auth_state.dart
│   ├── controllers/
│   │   ├── sales_controller.dart (StateNotifier)
│   │   ├── orders_controller.dart
│   │   └── customers_controller.dart
│   ├── screens/
│   │   ├── login_screen.dart
│   │   ├── dashboard_screen.dart
│   │   ├── sales_screen.dart
│   │   ├── orders_screen.dart
│   │   ├── customers_screen.dart
│   │   ├── payments_screen.dart
│   │   ├── inventory_screen.dart
│   │   ├── reports_screen.dart
│   │   └── settings_screen.dart
│   ├── widgets/
│   │   ├── bottom_navbar.dart ← Main nav
│   │   ├── product_search_dialog.dart
│   │   ├── customer_selector.dart
│   │   ├── cart_card.dart
│   │   ├── kpi_card.dart
│   │   └── loading_overlay.dart
│   ├── router/
│   │   └── router.dart ← go_router setup
│   └── theme/
│       └── app_theme.dart ← Colors + TextStyles
├── domain/
│   ├── models/ ← (Already exist from backend)
│   ├── services/ ← (Already exist: AuthService)
│   └── events/ ← (Already exist from backend)
├── data/
│   ├── models/
│   │   └── dtos/ ← (DTOs from PHASE 0)
│   ├── repositories/
│   │   ├── mock_repositories.dart ← 🟡 MOCK versions
│   │   └── (real repos will swap in PHASE 0)
│   └── local/
│       └── mock_data.dart ← Fake products/customers/sales
└── utils/
    ├── extensions.dart
    └── constants.dart
```

---

# 4. 🧭 BOTTOM NAVBAR SYSTEM

## 4.1 Bottom Navbar Widget (Cupertino-style)

```dart
// lib/presentation/widgets/bottom_navbar.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class BottomNavbar extends ConsumerWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  
  const BottomNavbar({
    required this.currentIndex,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Get current user role
    final authState = ref.watch(authProvider);
    
    final tabs = _getTabsByRole(authState.data?.role);
    
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      backgroundColor: Colors.white,
      selectedItemColor: const Color(0xFF2E7D32), // green
      unselectedItemColor: Colors.grey[400],
      items: [
        for (final tab in tabs)
          BottomNavigationBarItem(
            icon: Icon(tab.icon),
            label: tab.label,
          ),
      ],
    );
  }
  
  List<NavTab> _getTabsByRole(UserRole? role) {
    switch (role) {
      case UserRole.admin:
        return [
          NavTab(icon: Icons.dashboard, label: 'Dashboard'),
          NavTab(icon: Icons.shopping_cart, label: 'Sales'),
          NavTab(icon: Icons.assignment, label: 'Orders'),
          NavTab(icon: Icons.people, label: 'Customers'),
          NavTab(icon: Icons.inventory, label: 'Inventory'),
          NavTab(icon: Icons.payment, label: 'Payments'),
          NavTab(icon: Icons.bar_chart, label: 'Reports'),
          NavTab(icon: Icons.settings, label: 'Settings'),
        ];
      case UserRole.manager:
        return [
          NavTab(icon: Icons.dashboard, label: 'Dashboard'),
          NavTab(icon: Icons.shopping_cart, label: 'Sales'),
          NavTab(icon: Icons.assignment, label: 'Orders'),
          NavTab(icon: Icons.people, label: 'Customers'),
          NavTab(icon: Icons.inventory, label: 'Inventory'),
          NavTab(icon: Icons.payment, label: 'Payments'),
          NavTab(icon: Icons.bar_chart, label: 'Reports'),
        ];
      case UserRole.cashier:
        return [
          NavTab(icon: Icons.dashboard, label: 'Dashboard'),
          NavTab(icon: Icons.shopping_cart, label: 'Sales'),
          NavTab(icon: Icons.people, label: 'Customers'),
          NavTab(icon: Icons.payment, label: 'Payments'),
        ];
      default:
        return [];
    }
  }
}

class NavTab {
  final IconData icon;
  final String label;
  
  NavTab({required this.icon, required this.label});
}
```

## 4.2 Settings Toggle (Save Navbar Preference)

```dart
// lib/presentation/screens/settings_screen.dart (snippet)

class SettingsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final navbarHidden = ref.watch(navbarHiddenProvider);
    
    return Scaffold(
      appBar: AppBar(title: Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text('Show Navigation Bar'),
            value: !navbarHidden,
            onChanged: (value) {
              ref.read(navbarHiddenProvider.notifier).state = !value;
              // Save to SharedPreferences
              SharedPreferences.getInstance().then((prefs) {
                prefs.setBool('navbarHidden', !value);
              });
            },
          ),
        ],
      ),
    );
  }
}

final navbarHiddenProvider = StateProvider<bool>((ref) => false);
```

---

# 5. 🗂️ MOCK DATA LAYER

## 5.1 Fake Products (seed data)

```dart
// lib/data/local/mock_data.dart

class MockData {
  static final List<ProductDTO> mockProducts = [
    ProductDTO(
      id: '1',
      barcode: '8681123456780',
      name: 'Coffee',
      categoryId: 'cat_1',
      unit: 'pcs',
      costPrice: 5.0,
      sellPrice: 12.0,
      taxPercent: 18,
      stock: 100,
      minimumStock: 10,
      createdAt: DateTime.now(),
    ),
    ProductDTO(
      id: '2',
      barcode: '8681123456781',
      name: 'Tea',
      categoryId: 'cat_1',
      unit: 'pcs',
      costPrice: 3.0,
      sellPrice: 8.0,
      taxPercent: 18,
      stock: 50,
      minimumStock: 5,
      createdAt: DateTime.now(),
    ),
    ProductDTO(
      id: '3',
      barcode: '8681123456782',
      name: 'Bread',
      categoryId: 'cat_2',
      unit: 'pcs',
      costPrice: 2.0,
      sellPrice: 5.0,
      taxPercent: 8,
      stock: 30,
      minimumStock: 5,
      createdAt: DateTime.now(),
    ),
  ];
  
  static final List<CustomerDTO> mockCustomers = [
    CustomerDTO(
      id: 'cust_1',
      nameOrCompany: 'Ahmet Ağa',
      phone: '+905551234567',
      address: 'Istanbul, Turkey',
      taxNumber: '12345678901',
      balance: 100.0, // ⚠️ READONLY - for UI display only
      isActive: true,
      createdAt: DateTime.now(),
    ),
    CustomerDTO(
      id: 'cust_2',
      nameOrCompany: 'Sirkeci Market',
      phone: '+905559876543',
      address: 'Sirkeci, Istanbul',
      taxNumber: '98765432109',
      balance: 250.0,
      isActive: true,
      createdAt: DateTime.now(),
    ),
  ];
  
  static final List<FinancialTransactionDTO> mockTransactions = [
    FinancialTransactionDTO(
      id: 'tx_1',
      customerId: 'cust_1',
      type: 'sale',
      amount: 100.0,
      paidAmount: 50.0,
      debtAmount: 50.0,
      referenceId: 'sale_1',
      paymentMethods: {'CASH': 50.0},
      description: 'Coffee + Tea',
      transactionDate: DateTime.now().subtract(Duration(days: 1)),
      createdAt: DateTime.now().subtract(Duration(days: 1)),
    ),
  ];
}
```

## 5.2 Mock Repository Implementation

```dart
// lib/data/repositories/mock_repositories.dart

class MockProductRepository {
  Future<List<ProductDTO>> getAllProducts() async {
    // Simulate network delay
    await Future.delayed(Duration(milliseconds: 500));
    return MockData.mockProducts;
  }
  
  Future<ProductDTO?> getProductByBarcode(String barcode) async {
    await Future.delayed(Duration(milliseconds: 300));
    return MockData.mockProducts.firstWhere(
      (p) => p.barcode == barcode,
      orElse: () => throw Exception('Product not found'),
    );
  }
}

class MockCustomerRepository {
  Future<List<CustomerDTO>> getAllCustomers() async {
    await Future.delayed(Duration(milliseconds: 500));
    return MockData.mockCustomers;
  }
  
  Future<double> getCustomerBalance(String customerId) async {
    await Future.delayed(Duration(milliseconds: 300));
    return MockData.mockCustomers
        .firstWhere((c) => c.id == customerId)
        .balance;
  }
}

class MockSaleRepository {
  Future<List<SaleDTO>> getAllSales() async {
    await Future.delayed(Duration(milliseconds: 500));
    return []; // Empty for now (PHASE 0 will populate)
  }
}

class MockOrderRepository {
  Future<List<OrderDTO>> getAllOrders() async {
    await Future.delayed(Duration(milliseconds: 500));
    return []; // Empty for now
  }
}
```

---

# 6. 📱 SCREEN SKELETON WITH MOCKS

## 6.1 Login Screen

```dart
// lib/presentation/screens/login_screen.dart

class LoginScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('SERENUT POS')),
      body: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              decoration: InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
              ),
              controller: _usernameController,
            ),
            SizedBox(height: 16),
            TextField(
              decoration: InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
              obscureText: true,
              controller: _passwordController,
            ),
            SizedBox(height: 24),
            ElevatedButton(
              onPressed: () async {
                final authService = ref.read(authServiceProvider);
                try {
                  await authService.login(_usernameController.text, _passwordController.text);
                  context.go('/dashboard'); // ← Mock navigation
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Login failed: $e')),
                  );
                }
              },
              child: Text('Login'),
            ),
            SizedBox(height: 16),
            Text('Demo users: admin / cashier (password = username)'),
          ],
        ),
      ),
    );
  }
}

final _usernameController = TextEditingController();
final _passwordController = TextEditingController();
```

## 6.2 Dashboard Screen (Mock KPI)

```dart
// lib/presentation/screens/dashboard_screen.dart

class DashboardScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mock data (will be real in PHASE 1+)
    const todaySales = 1250.0;
    const openOrders = 5;
    const customerDebt = 3450.0;
    const lowStockAlerts = 2;
    
    return Scaffold(
      appBar: AppBar(
        title: Text('Dashboard'),
        actions: [
          IconButton(
            icon: Icon(Icons.notifications),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          children: [
            // KPI Cards
            SizedBox(
              height: 120,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  KpiCard(
                    title: 'Today Sales',
                    value: '₺${todaySales.toStringAsFixed(2)}',
                    icon: Icons.trending_up,
                    color: Colors.green,
                  ),
                  SizedBox(width: 12),
                  KpiCard(
                    title: 'Open Orders',
                    value: '$openOrders',
                    icon: Icons.assignment,
                    color: Colors.blue,
                  ),
                  SizedBox(width: 12),
                  KpiCard(
                    title: 'Customer Debt',
                    value: '₺${customerDebt.toStringAsFixed(2)}',
                    icon: Icons.warning,
                    color: Colors.red,
                  ),
                  SizedBox(width: 12),
                  KpiCard(
                    title: 'Low Stock',
                    value: '$lowStockAlerts',
                    icon: Icons.inventory,
                    color: Colors.orange,
                  ),
                ],
              ),
            ),
            SizedBox(height: 24),
            
            // Quick Actions
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              children: [
                _ActionButton(
                  icon: Icons.add_shopping_cart,
                  label: 'New Sale',
                  onTap: () => context.go('/sales'),
                ),
                _ActionButton(
                  icon: Icons.add_box,
                  label: 'New Order',
                  onTap: () => context.go('/orders'),
                ),
                _ActionButton(
                  icon: Icons.payment,
                  label: 'Record Payment',
                  onTap: () => context.go('/payments'),
                ),
                _ActionButton(
                  icon: Icons.inventory,
                  label: 'Check Inventory',
                  onTap: () => context.go('/inventory'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;
  
  const KpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 40, color: const Color(0xFF2E7D32)),
            SizedBox(height: 8),
            Text(label, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
```

## 6.3 Sales Screen (Mock Cart)

```dart
// lib/presentation/screens/sales_screen.dart

class SalesScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productList = ref.watch(productListProvider);
    final cart = ref.watch(cartStateProvider);
    
    return Scaffold(
      appBar: AppBar(title: Text('Sales')),
      body: Row(
        children: [
          // Product Grid (Left)
          Expanded(
            flex: 2,
            child: productList.when(
              loading: () => Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
              data: (products) => GridView.builder(
                padding: EdgeInsets.all(12),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 1,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  return GestureDetector(
                    onTap: () {
                      // Add to cart (mock)
                      ref.read(cartStateProvider.notifier).addItem(product);
                    },
                    child: Card(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.shopping_bag, size: 40),
                          SizedBox(height: 8),
                          Text(
                            product.name,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '₺${product.sellPrice.toStringAsFixed(2)}',
                            style: TextStyle(color: Colors.green),
                          ),
                          Text(
                            'Stock: ${product.stock}',
                            style: TextStyle(fontSize: 10, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          
          // Cart (Right)
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.grey[100],
              padding: EdgeInsets.all(12),
              child: Column(
                children: [
                  Text('Cart', style: TextStyle(fontWeight: FontWeight.bold)),
                  Divider(),
                  // Cart items (mock - will show real items later)
                  Expanded(
                    child: ListView(
                      children: [
                        _CartItem(productName: 'Coffee', qty: 2, price: 12.0),
                        _CartItem(productName: 'Tea', qty: 1, price: 8.0),
                      ],
                    ),
                  ),
                  Divider(),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Total:', fontWeight: FontWeight.bold),
                        Text('₺32.00', fontWeight: FontWeight.bold),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      // ⚠️ NOT connected to TransactionEngine yet (PHASE 0)
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('⚠️ Mock complete sale - PHASE 0 will activate this')),
                      );
                    },
                    child: Text('Complete Sale'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartItem extends StatelessWidget {
  final String productName;
  final int qty;
  final double price;
  
  const _CartItem({
    required this.productName,
    required this.qty,
    required this.price,
  });
  
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(productName),
          Text('$qty x ₺${price.toStringAsFixed(2)}'),
        ],
      ),
    );
  }
}
```

---

# 7. 🎯 ROUTER SETUP

## 7.1 Go Router Configuration

```dart
// lib/presentation/router/router.dart

import 'package:go_router/go_router.dart';

final goRouterProvider = Provider<GoRouter>((ref) {
  final authService = ref.watch(authServiceProvider);
  
  return GoRouter(
    redirect: (context, state) async {
      final user = await authService.getCurrentUser();
      final isLoggedIn = user != null;
      final isLoggingIn = state.matchedLocation == '/login';
      
      if (!isLoggedIn) return '/login';
      if (isLoggingIn) return '/dashboard';
      
      return null; // No redirect needed
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => LoginScreen(),
      ),
      GoRoute(
        path: '/dashboard',
        builder: (context, state) => MainNavigationWrapper(
          initialTab: 0,
        ),
      ),
      GoRoute(
        path: '/sales',
        builder: (context, state) => MainNavigationWrapper(
          initialTab: 1,
        ),
      ),
      GoRoute(
        path: '/orders',
        builder: (context, state) => MainNavigationWrapper(
          initialTab: 2,
        ),
      ),
      GoRoute(
        path: '/customers',
        builder: (context, state) => MainNavigationWrapper(
          initialTab: 3,
        ),
      ),
      GoRoute(
        path: '/inventory',
        builder: (context, state) => MainNavigationWrapper(
          initialTab: 4,
        ),
      ),
      GoRoute(
        path: '/payments',
        builder: (context, state) => MainNavigationWrapper(
          initialTab: 5,
        ),
      ),
      GoRoute(
        path: '/reports',
        builder: (context, state) => MainNavigationWrapper(
          initialTab: 6,
        ),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => MainNavigationWrapper(
          initialTab: 7,
        ),
      ),
    ],
  );
});

// Main navigation wrapper (with navbar)
class MainNavigationWrapper extends ConsumerStatefulWidget {
  final int initialTab;
  
  const MainNavigationWrapper({required this.initialTab});
  
  @override
  _MainNavigationWrapperState createState() => _MainNavigationWrapperState();
}

class _MainNavigationWrapperState extends ConsumerState<MainNavigationWrapper> {
  late int _currentTab;
  
  @override
  void initState() {
    super.initState();
    _currentTab = widget.initialTab;
  }
  
  @override
  Widget build(BuildContext context) {
    final screens = [
      DashboardScreen(),
      SalesScreen(),
      OrdersScreen(),
      CustomersScreen(),
      InventoryScreen(),
      PaymentsScreen(),
      ReportsScreen(),
      SettingsScreen(),
    ];
    
    return Scaffold(
      body: screens[_currentTab],
      bottomNavigationBar: BottomNavbar(
        currentIndex: _currentTab,
        onTap: (index) {
          setState(() => _currentTab = index);
        },
      ),
    );
  }
}
```

---

# 8. 🧩 SHARED WIDGETS (MOCK)

## 8.1 Product Search Dialog

```dart
// lib/presentation/widgets/product_search_dialog.dart

class ProductSearchDialog extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productList = ref.watch(productListProvider);
    
    return Dialog(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Search by name or barcode',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (query) {
                // Filter logic (mock)
              },
            ),
          ),
          Expanded(
            child: productList.when(
              loading: () => Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
              data: (products) => ListView.builder(
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  return ListTile(
                    title: Text(product.name),
                    subtitle: Text('Code: ${product.barcode}'),
                    trailing: Text(
                      '₺${product.sellPrice.toStringAsFixed(2)}',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    onTap: () {
                      Navigator.pop(context, product);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

## 8.2 Customer Selector

```dart
// lib/presentation/widgets/customer_selector.dart

class CustomerSelector extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final customerList = ref.watch(customerListProvider);
    
    return Dialog(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                labelText: 'Select customer',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person_search),
              ),
            ),
          ),
          Expanded(
            child: customerList.when(
              loading: () => Center(child: CircularProgressIndicator()),
              error: (err, stack) => Center(child: Text('Error: $err')),
              data: (customers) => ListView.builder(
                itemCount: customers.length,
                itemBuilder: (context, index) {
                  final customer = customers[index];
                  return ListTile(
                    title: Text(customer.nameOrCompany),
                    subtitle: Text('Balance: ₺${customer.balance.toStringAsFixed(2)}'),
                    trailing: Icon(
                      customer.balance > 0 ? Icons.warning : Icons.check_circle,
                      color: customer.balance > 0 ? Colors.red : Colors.green,
                    ),
                    onTap: () {
                      Navigator.pop(context, customer);
                    },
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

---

# 9. 💾 STATE MANAGEMENT PATTERN

## 9.1 Cart State (StateNotifier Example)

```dart
// lib/presentation/state/cart_state.dart

class CartState {
  final List<CartItem> items;
  final CustomerDTO? customer;
  final double taxRate;
  
  CartState({
    this.items = const [],
    this.customer,
    this.taxRate = 0.18,
  });
  
  double get subtotal => items.fold(0, (sum, item) => sum + item.lineTotal);
  double get taxAmount => subtotal * taxRate;
  double get grandTotal => subtotal + taxAmount;
  
  CartState copyWith({
    List<CartItem>? items,
    CustomerDTO? customer,
    double? taxRate,
  }) {
    return CartState(
      items: items ?? this.items,
      customer: customer ?? this.customer,
      taxRate: taxRate ?? this.taxRate,
    );
  }
}

class CartItem {
  final ProductDTO product;
  final int quantity;
  
  CartItem({required this.product, required this.quantity});
  
  double get lineTotal => product.sellPrice * quantity;
}

class CartNotifier extends StateNotifier<AppState<CartState>> {
  CartNotifier() : super(AppState(value: AsyncData(CartState())));
  
  void addItem(ProductDTO product) {
    final current = (state.value as AsyncData<CartState>).value;
    final existingItem = current.items.firstWhere(
      (item) => item.product.id == product.id,
      orElse: () => CartItem(product: product, quantity: 0),
    );
    
    final updatedItems = current.items
        .where((item) => item.product.id != product.id)
        .toList();
    
    updatedItems.add(
      CartItem(
        product: product,
        quantity: existingItem.quantity + 1,
      ),
    );
    
    state = AppState(value: AsyncData(current.copyWith(items: updatedItems)));
  }
  
  void setCustomer(CustomerDTO customer) {
    final current = (state.value as AsyncData<CartState>).value;
    state = AppState(value: AsyncData(current.copyWith(customer: customer)));
  }
  
  void clear() {
    state = AppState(value: AsyncData(CartState()));
  }
}
```

---

# 10. ✅ BUILD CHECKLIST

## Phase 1 Completion Criteria

- [ ] Riverpod DI container compiles (all providers)
- [ ] Bottom navbar renders (role-based tabs)
- [ ] 8 screens navigate correctly via go_router
- [ ] Mock data loads in product/customer lists
- [ ] Dashboard shows mock KPI cards
- [ ] Sales screen shows product grid + mock cart
- [ ] All shared widgets render
- [ ] No console errors / warnings
- [ ] Theme colors applied (#2E7D32, #FFD600, red, orange)
- [ ] Login → Dashboard flow works
- [ ] Settings toggle saves navbar visibility
- [ ] Cart adds/removes items (mock)

## Code Quality Checks

- [ ] All providers follow AppState<T> pattern
- [ ] No raw Future handling in UI (all wrapped in AsyncValue)
- [ ] Error handling: all errors caught + shown to user
- [ ] Mock repositories respond with realistic delays (300-500ms)
- [ ] ⚠️ NO TransactionEngine calls (placeholder only)
- [ ] ⚠️ NO real database writes (SQLite unused yet)
- [ ] ⚠️ NO real event publishing (events logged only)

---

# 🎯 NEXT STEPS

**Once PHASE 0 complete** (3-5 days parallel):

1. Swap mock repositories → real repositories
2. Connect UI providers → real transactionEngineProvider
3. Add real TransactionEngine calls (sales→ledger→stock)
4. Add real payment processing
5. Add receipt printing (mock print dialog for now)
6. Add SMS notifications (event subscription)

---

**Status**: 🟡 READY FOR PARALLEL BUILD  
**Duration**: 3-5 days  
**Constraint**: ⚠️ Mock data only until PHASE 0 complete  
**Owner**: Frontend Team  

**Build now, integrate later! 🚀**
