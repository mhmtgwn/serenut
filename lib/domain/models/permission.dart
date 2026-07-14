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
  adminUsers('admin:users', 'Manage users', PermissionCategory.admin),

  // Settings (9)
  settingsView('settings:view', 'Giriş Yetkisi', PermissionCategory.admin),
  settingsPrinter('settings:printer', 'Yazıcı Tercihleri', PermissionCategory.admin),
  settingsReceipt('settings:receipt', 'Fiş Şablon Yönetimi', PermissionCategory.admin),
  settingsUsers('settings:users', 'Kullanıcı Yetkilendirme', PermissionCategory.admin),
  settingsFinance('settings:finance', 'Finans & Cari Ayarlar', PermissionCategory.admin),
  settingsAudit('settings:audit', 'Log & Audit İzleme', PermissionCategory.admin),
  settingsDatabase('settings:database', 'Veritabanı Bakım & Sağlık', PermissionCategory.admin),
  settingsRecovery('settings:recovery', 'Veri Kurtarma', PermissionCategory.admin),
  settingsLicense('settings:license', 'Lisans & Abonelik', PermissionCategory.admin);

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
      UserRole.owner => Permission.values,
      UserRole.admin => Permission.values,
      // Sysadmin should not have POS permissions
      UserRole.sysadmin => [
        Permission.adminSettings,
        Permission.adminUsers,
        Permission.reportsView,
        Permission.settingsView,
      ],
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

        // Settings (base)
        Permission.settingsView,
        Permission.settingsPrinter,
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

        // Settings (base)
        Permission.settingsView,
        Permission.settingsPrinter,
      ],
      UserRole.staff => [
        // Sales (view + create only)
        Permission.salesView,
        Permission.salesCreate,

        // Customers (view only)
        Permission.customersView,

        // Settings (base)
        Permission.settingsView,
        Permission.settingsPrinter,
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
  owner('Owner'),
  admin('Admin'),
  sysadmin('Sysadmin'),
  manager('Manager'),
  cashier('Cashier'),
  staff('Staff');

  final String label;
  const UserRole(this.label);

  /// Get color for UI display (hex)
  String get colorHex => switch (this) {
    UserRole.owner => 'FF8C00',      // Dark Orange
    UserRole.admin => 'FF6B6B',      // Red
    UserRole.sysadmin => '8A2BE2',   // BlueViolet
    UserRole.manager => '4ECDC4',    // Teal
    UserRole.cashier => 'FFD93D',    // Yellow
    UserRole.staff => '95E1D3',      // Light green
  };

  /// Get icon emoji
  String get icon => switch (this) {
    UserRole.owner => '💼',
    UserRole.admin => '👑',
    UserRole.sysadmin => '⚡',
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
