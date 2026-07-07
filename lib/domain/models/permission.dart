// lib/domain/models/permission.dart
// PHASE 0 - Permission Model (Day 2)
// Type-safe permission definitions
// Generated: 21 Jun 2026

/// Type-safe permission enum (mirrors string-based permissions)
/// 
/// Purpose: Use for compile-time checking, prevents typos
/// Design: Each permission has category + action (e.g., sales:view)
/// 
/// Usage:
/// ```dart
/// if (user.hasPermission(Permission.salesView.value)) {
///   // show sales view
/// }
/// 
/// // Or prefer this (compile-time safe):
/// if (user.hasPermission('sales:view')) {
///   // same thing
/// }
/// ```
enum Permission {
  // Sales (4)
  salesView('sales:view', 'View sales', PermissionCategory.sales),
  salesCreate('sales:create', 'Create sale', PermissionCategory.sales),
  salesEdit('sales:edit', 'Edit sale', PermissionCategory.sales),
  salesPrint('sales:print', 'Print receipt', PermissionCategory.sales),

  // Orders (4)
  ordersView('orders:view', 'View orders', PermissionCategory.orders),
  ordersCreate('orders:create', 'Create order', PermissionCategory.orders),
  ordersEdit('orders:edit', 'Edit order', PermissionCategory.orders),
  ordersDeliver('orders:deliver', 'Deliver order', PermissionCategory.orders),

  // Customers (4)
  customersView('customers:view', 'View customers', PermissionCategory.customers),
  customersCreate('customers:create', 'Create customer', PermissionCategory.customers),
  customersEdit('customers:edit', 'Edit customer', PermissionCategory.customers),
  customersDelete('customers:delete', 'Delete customer', PermissionCategory.customers),

  // Payments (3)
  paymentsView('payments:view', 'View payments', PermissionCategory.payments),
  paymentsRecord('payments:record', 'Record payment', PermissionCategory.payments),
  paymentsReverse('payments:reverse', 'Reverse payment', PermissionCategory.payments),

  // Inventory (3)
  inventoryView('inventory:view', 'View inventory', PermissionCategory.inventory),
  inventoryAdjust('inventory:adjust', 'Adjust stock', PermissionCategory.inventory),
  inventoryTransfer('inventory:transfer', 'Transfer stock', PermissionCategory.inventory),

  // Reports (3)
  reportsView('reports:view', 'View reports', PermissionCategory.reports),
  reportsFinancial('reports:financial', 'Financial reports', PermissionCategory.reports),
  reportsInventory('reports:inventory', 'Inventory reports', PermissionCategory.reports),

  // Admin (2)
  adminSettings('admin:settings', 'Manage settings', PermissionCategory.admin),
  adminUsers('admin:users', 'Manage users', PermissionCategory.admin);

  final String value;      // e.g., 'sales:view'
  final String label;      // e.g., 'View sales'
  final PermissionCategory category;

  const Permission(this.value, this.label, this.category);

  /// Check if this permission is in a list of string permissions
  bool isIn(List<String> permissions) => permissions.contains(value);

  /// Get all permissions in this category
  static List<Permission> inCategory(PermissionCategory category) {
    return Permission.values.where((p) => p.category == category).toList();
  }

  /// Get all permissions for a specific role
  static List<Permission> forRole(UserRole userRole) {
    return switch (userRole) {
      UserRole.admin => Permission.values,
      UserRole.manager => [
        // Sales (view + print only, no create/edit)
        Permission.salesView,
        Permission.salesPrint,

        // Orders (all)
        Permission.ordersView,
        Permission.ordersCreate,
        Permission.ordersEdit,
        Permission.ordersDeliver,

        // Customers (view + create + edit, no delete)
        Permission.customersView,
        Permission.customersCreate,
        Permission.customersEdit,

        // Payments (view + record only)
        Permission.paymentsView,
        Permission.paymentsRecord,

        // Inventory (all)
        Permission.inventoryView,
        Permission.inventoryAdjust,
        Permission.inventoryTransfer,

        // Reports (all)
        Permission.reportsView,
        Permission.reportsFinancial,
        Permission.reportsInventory,
      ],
      UserRole.cashier => [
        // Sales (view + create + print)
        Permission.salesView,
        Permission.salesCreate,
        Permission.salesPrint,

        // Customers (view only)
        Permission.customersView,

        // Payments (record only)
        Permission.paymentsRecord,
      ],
      UserRole.staff => [
        // Sales (view + create only)
        Permission.salesView,
        Permission.salesCreate,

        // Customers (view only)
        Permission.customersView,
      ],
    };
  }
}

/// Permission categories for UI organization
enum PermissionCategory {
  sales('Sales'),
  orders('Orders'),
  customers('Customers'),
  payments('Payments'),
  inventory('Inventory'),
  reports('Reports'),
  admin('Administration');

  final String label;
  const PermissionCategory(this.label);

  /// Get icon emoji for UI display
  String get icon => switch (this) {
    PermissionCategory.sales => '💳',
    PermissionCategory.orders => '📦',
    PermissionCategory.customers => '👥',
    PermissionCategory.payments => '💰',
    PermissionCategory.inventory => '📊',
    PermissionCategory.reports => '📈',
    PermissionCategory.admin => '⚙️',
  };
}

/// User role enum (from AuthUser)
enum UserRole {
  admin('Admin'),
  manager('Manager'),
  cashier('Cashier'),
  staff('Staff');

  final String label;
  const UserRole(this.label);

  /// Get color for UI display (hex)
  String get colorHex => switch (this) {
    UserRole.admin => 'FF6B6B',      // Red
    UserRole.manager => '4ECDC4',    // Teal
    UserRole.cashier => 'FFD93D',    // Yellow
    UserRole.staff => '95E1D3',      // Light green
  };

  /// Get icon emoji
  String get icon => switch (this) {
    UserRole.admin => '👑',
    UserRole.manager => '📋',
    UserRole.cashier => '💵',
    UserRole.staff => '👤',
  };
}

/// Permission assignment matrix (reference)
/// 
/// | Permission | Admin | Manager | Cashier | Staff |
/// |------------|-------|---------|---------|-------|
/// | sales:view | ✅ | ✅ | ✅ | ✅ |
/// | sales:create | ✅ | ❌ | ✅ | ✅ |
/// | sales:edit | ✅ | ❌ | ❌ | ❌ |
/// | sales:print | ✅ | ✅ | ✅ | ❌ |
/// | orders:* (all 4) | ✅ | ✅ | ❌ | ❌ |
/// | customers:view | ✅ | ✅ | ✅ | ✅ |
/// | customers:create | ✅ | ✅ | ❌ | ❌ |
/// | customers:edit | ✅ | ✅ | ❌ | ❌ |
/// | customers:delete | ✅ | ❌ | ❌ | ❌ |
/// | payments:* (all 3) | ✅ | ✅ | ✅ | ❌ |
/// | inventory:* (all 3) | ✅ | ✅ | ❌ | ❌ |
/// | reports:* (all 3) | ✅ | ✅ | ❌ | ❌ |
/// | admin:* (all 2) | ✅ | ❌ | ❌ | ❌ |
class PermissionMatrix {
  static const String _matrix = '''
  Permission Matrix (27 total)
  ═══════════════════════════════════════════════════════════
  
  ADMIN (All 27 permissions)
  MANAGER (15 permissions)
    - Sales: view, print
    - Orders: all 4
    - Customers: view, create, edit
    - Payments: view, record
    - Inventory: all 3
    - Reports: all 3
  
  CASHIER (5 permissions)
    - Sales: view, create, print
    - Customers: view
    - Payments: record
  
  STAFF (3 permissions)
    - Sales: view, create
    - Customers: view
  ''';
}
