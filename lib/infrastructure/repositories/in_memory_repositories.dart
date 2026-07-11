// lib/infrastructure/repositories/in_memory_repositories.dart
// Stateful In-Memory Repositories for Web fallback execution
// Generated: 21 Jun 2026

import 'package:serenutos/domain/repositories/base_repository.dart';
import 'package:serenutos/domain/models/auth_user.dart';
import 'package:serenutos/infrastructure/repositories/report_repository.dart';
import 'package:serenutos/infrastructure/repositories/dashboard_repository.dart';
import 'package:serenutos/domain/models/settings.dart';



/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
/// In-Memory Unified State
/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
class InMemoryDb {
  // Products �€” ba�Ÿlangıçta bo�Ÿ (demo veri yok)
  static final List<ProductEntity> products = [];

  // Customers �€” sadece sistem mü�Ÿterisi "Pe�Ÿin Mü�Ÿteri"
  static final List<CustomerEntity> customers = [
    CustomerEntity(
      id: '',
      name: 'Pe�Ÿin Mü�Ÿteri',
      email: '',
      phone: '',
      balance: 0.0,
      createdAt: DateTime(2024, 1, 1),
    ),
  ];

  // Sales �€” ba�Ÿlangıçta bo�Ÿ
  static final List<SaleEntity> sales = [];

  // Financial transactions �€” ba�Ÿlangıçta bo�Ÿ
  static final List<FinancialTransactionEntity> transactions = [];

  // Orders �€” ba�Ÿlangıçta bo�Ÿ
  static final List<OrderEntity> orders = [];

  // Settings �€” kurulum tamamlandıktan sonra güncellenir
  static Settings settings = Settings(
    businessName: '',
    businessPhone: '',
    businessAddress: '',
    currency: '�‚�',
    printerPort: 9100,
    paperWidth: 80,
    printReceipt: true,
    printQRCode: false,
    printProductDetails: true,
    printBarcode: false,
    printCopies: 1,
    vatCategories: '[]',
    smsEnabled: false,
    qrEnabled: false,
    qrFormat: 'type|id|timestamp|customerId|amount|hash',
    debugMode: false,
    createdAt: DateTime.now(),
  );

  // Users �€” setup sonrası doldurulur
  static final List<AuthUser> users = [];

  /// Factory Reset: tüm verileri sıfırla (sistem defaultlarına dön)
  static void reset() {
    products.clear();

    customers.clear();
    customers.add(CustomerEntity(
      id: '',
      name: 'Pe�Ÿin Mü�Ÿteri',
      email: '',
      phone: '',
      balance: 0.0,
      createdAt: DateTime(2024, 1, 1),
    ));

    sales.clear();
    transactions.clear();
    orders.clear();
    users.clear();

    settings = Settings(
      businessName: '',
      businessPhone: '',
      businessAddress: '',
      currency: '�‚�',
      printerPort: 9100,
      paperWidth: 80,
      printReceipt: true,
      printQRCode: false,
      printProductDetails: true,
      printBarcode: false,
      printCopies: 1,
      vatCategories: '[]',
      smsEnabled: false,
      qrEnabled: false,
      qrFormat: 'type|id|timestamp|customerId|amount|hash',
      debugMode: false,
      createdAt: DateTime.now(),
    );
  }
}

/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
/// Product Repository
/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
class InMemoryProductRepository implements IProductRepository {
  @override
  Future<List<ProductEntity>> findAll() async {
    return InMemoryDb.products;
  }

  @override
  Future<ProductEntity?> findById(dynamic id) async {
    try {
      return InMemoryDb.products.firstWhere((p) => p.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> create(ProductEntity entity) async {
    InMemoryDb.products.add(entity);
    return 1;
  }

  @override
  Future<int> update(ProductEntity entity, {String? oldId}) async {
    final targetId = oldId ?? entity.id;
    final idx = InMemoryDb.products.indexWhere((p) => p.id == targetId);
    if (idx != -1) {
      InMemoryDb.products[idx] = entity;
      return 1;
    }
    return 0;
  }

  @override
  Future<int> delete(dynamic id) async {
    final idx = InMemoryDb.products.indexWhere((p) => p.id == id);
    if (idx != -1) {
      InMemoryDb.products.removeAt(idx);
      return 1;
    }
    return 0;
  }

  @override
  Future<int> count() async {
    return InMemoryDb.products.length;
  }

  @override
  Future<bool> exists(dynamic id) async {
    return InMemoryDb.products.any((p) => p.id == id);
  }

  @override
  Future<List<ProductEntity>> searchByName(String query) async {
    return InMemoryDb.products
        .where((p) => p.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  @override
  Future<List<ProductEntity>> getByCategory(String category) async {
    return InMemoryDb.products.where((p) => p.category == category).toList();
  }

  @override
  Future<Map<String, List<ProductEntity>>> getGroupedByCategory() async {
    final map = <String, List<ProductEntity>>{};
    for (final p in InMemoryDb.products) {
      map.putIfAbsent(p.category, () => []).add(p);
    }
    return map;
  }

  @override
  Future<void> decreaseStock(String productId, int quantity) async {
    final idx = InMemoryDb.products.indexWhere((p) => p.id == productId);
    if (idx != -1) {
      final p = InMemoryDb.products[idx];
      InMemoryDb.products[idx] = ProductEntity(
        id: p.id,
        name: p.name,
        description: p.description,
        price: p.price,
        quantity: p.quantity - quantity,
        category: p.category,
        vat: p.vat,
      );
    }
  }

  @override
  Future<void> increaseStock(String productId, int quantity) async {
    final idx = InMemoryDb.products.indexWhere((p) => p.id == productId);
    if (idx != -1) {
      final p = InMemoryDb.products[idx];
      InMemoryDb.products[idx] = ProductEntity(
        id: p.id,
        name: p.name,
        description: p.description,
        price: p.price,
        quantity: p.quantity + quantity,
        category: p.category,
        vat: p.vat,
      );
    }
  }

  @override
  Future<List<ProductEntity>> getLowStockProducts(int threshold) async {
    return InMemoryDb.products.where((p) => p.quantity <= threshold).toList();
  }

  @override
  Future<List<ProductEntity>> findFiltered({
    String? searchQuery,
    String? category,
    int? limit,
    int? offset,
  }) async {
    Iterable<ProductEntity> results = InMemoryDb.products;
    if (category != null && category.isNotEmpty) {
      results = results.where((p) => p.category == category);
    }
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      results = results.where((p) => p.name.toLowerCase().contains(q) || p.description.toLowerCase().contains(q));
    }
    var list = results.toList();
    if (offset != null) {
      if (offset < list.length) {
        list = list.sublist(offset);
      } else {
        list = [];
      }
    }
    if (limit != null && list.length > limit) {
      list = list.sublist(0, limit);
    }
    return list;
  }

  @override
  Future<List<String>> getCategories() async {
    return InMemoryDb.products.map((p) => p.category).toSet().toList();
  }
}

/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
/// Customer Repository
/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
class InMemoryCustomerRepository implements ICustomerRepository {
  @override
  Future<List<CustomerEntity>> findAll() async {
    return InMemoryDb.customers;
  }

  @override
  Future<CustomerEntity?> findById(dynamic id) async {
    try {
      return InMemoryDb.customers.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> create(CustomerEntity entity) async {
    InMemoryDb.customers.add(entity);
    return 1;
  }

  @override
  Future<int> update(CustomerEntity entity) async {
    final idx = InMemoryDb.customers.indexWhere((c) => c.id == entity.id);
    if (idx != -1) {
      InMemoryDb.customers[idx] = entity;
      return 1;
    }
    return 0;
  }

  @override
  Future<int> delete(dynamic id) async {
    if (id == null || id == '') return 0;
    final idx = InMemoryDb.customers.indexWhere((c) => c.id == id);
    if (idx != -1) {
      InMemoryDb.customers.removeAt(idx);
      return 1;
    }
    return 0;
  }

  @override
  Future<int> count() async {
    return InMemoryDb.customers.length;
  }

  @override
  Future<bool> exists(dynamic id) async {
    return InMemoryDb.customers.any((c) => c.id == id);
  }

  @override
  Future<List<CustomerEntity>> search(String query) async {
    final q = query.toLowerCase();
    return InMemoryDb.customers
        .where((c) => c.name.toLowerCase().contains(q) || c.email.toLowerCase().contains(q))
        .toList();
  }

  @override
  Future<List<CustomerEntity>> findFiltered({
    String? searchQuery,
    int? limit,
    int? offset,
  }) async {
    Iterable<CustomerEntity> results = InMemoryDb.customers;
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final q = searchQuery.toLowerCase();
      results = results.where((c) =>
          c.name.toLowerCase().contains(q) ||
          c.phone.toLowerCase().contains(q) ||
          c.email.toLowerCase().contains(q));
    }
    var list = results.toList();
    if (offset != null) {
      if (offset < list.length) {
        list = list.sublist(offset);
      } else {
        list = [];
      }
    }
    if (limit != null && list.length > limit) {
      list = list.sublist(0, limit);
    }
    return list;
  }

  @override
  Future<List<CustomerEntity>> getDebtors() async {
    return InMemoryDb.customers.where((c) => c.balance < 0).toList();
  }

  @override
  Future<List<CustomerEntity>> getWithCredit() async {
    return InMemoryDb.customers.where((c) => c.balance > 0).toList();
  }

  @override
  Future<void> updateBalance(String customerId, double amount) async {
    // No-op: Handled automatically by in-memory triggers when transactions are created
  }

  @override
  Future<double> getBalance(String customerId) async {
    final c = await findById(customerId);
    return c?.balance ?? 0.0;
  }

  @override
  Future<double> getTotalDebt(String customerId) async {
    double debt = 0;
    for (final tx in InMemoryDb.transactions) {
      if (tx.customerId == customerId && tx.debtAmount > 0) {
        debt += tx.debtAmount;
      }
    }
    return debt;
  }

  @override
  Future<double> getTotalPaid(String customerId) async {
    double paid = 0;
    for (final tx in InMemoryDb.transactions) {
      if (tx.customerId == customerId) {
        paid += tx.paidAmount;
      }
    }
    return paid;
  }
}

/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
/// Sale Repository
/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
class InMemorySaleRepository implements ISaleRepository {
  @override
  Future<List<SaleEntity>> findAll() async {
    return InMemoryDb.sales;
  }

  @override
  Future<SaleEntity?> findByIdempotencyKey(String key) async {
    try {
      return InMemoryDb.sales.firstWhere((s) => s.idempotencyKey == key);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SaleEntity?> findById(dynamic id) async {
    try {
      return InMemoryDb.sales.firstWhere((s) => s.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> create(SaleEntity entity) async {
    InMemoryDb.sales.add(entity);
    return 1;
  }

  @override
  Future<int> update(SaleEntity entity) async {
    final idx = InMemoryDb.sales.indexWhere((s) => s.id == entity.id);
    if (idx != -1) {
      InMemoryDb.sales[idx] = entity;
      return 1;
    }
    return 0;
  }

  @override
  Future<int> delete(dynamic id) async {
    final idx = InMemoryDb.sales.indexWhere((s) => s.id == id);
    if (idx != -1) {
      InMemoryDb.sales.removeAt(idx);
      return 1;
    }
    return 0;
  }

  @override
  Future<int> count() async {
    return InMemoryDb.sales.length;
  }

  @override
  Future<bool> exists(dynamic id) async {
    return InMemoryDb.sales.any((s) => s.id == id);
  }

  @override
  Future<List<SaleEntity>> getTodaySales() async {
    final now = DateTime.now();
    return InMemoryDb.sales
        .where((s) => s.createdAt.year == now.year && s.createdAt.month == now.month && s.createdAt.day == now.day)
        .toList();
  }

  @override
  Future<List<SaleEntity>> getSalesByDateRange(DateTime from, DateTime to) async {
    return InMemoryDb.sales
        .where((s) => s.createdAt.isAfter(from) && s.createdAt.isBefore(to))
        .toList();
  }

  @override
  Future<List<SaleEntity>> getByCustomerId(String customerId) async {
    return InMemoryDb.sales.where((s) => s.customerId == customerId).toList();
  }

  @override
  Future<List<SaleEntity>> getByPaymentMethod(String method) async {
    return InMemoryDb.sales.where((s) => s.paymentMethod == method).toList();
  }

  @override
  Future<double> getTodayRevenue() async {
    final sales = await getTodaySales();
    return sales
        .where((s) => s.status == 'completed')
        .fold<double>(0.0, (sum, s) => sum + s.totalAmount);
  }

  @override
  Future<double> getRevenueByDateRange(DateTime from, DateTime to) async {
    final sales = await getSalesByDateRange(from, to);
    return sales
        .where((s) => s.status == 'completed')
        .fold<double>(0.0, (sum, s) => sum + s.totalAmount);
  }

  @override
  Future<int> getTotalItemsSold() async {
    int total = 0;
    for (final s in InMemoryDb.sales) {
      for (final item in s.items) {
        total += item['quantity'] as int? ?? 0;
      }
    }
    return total;
  }
}

/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
/// Financial Transaction Repository
/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
class InMemoryFinancialTransactionRepository implements IFinancialTransactionRepository {
  final String? deviceId;
  static final List<Map<String, dynamic>> triggerAuditLogs = [];

  InMemoryFinancialTransactionRepository({this.deviceId});

  @override
  Future<List<FinancialTransactionEntity>> findAll() async {
    final list = List<FinancialTransactionEntity>.from(InMemoryDb.transactions);
    list.sort((a, b) {
      final cmp = b.logicalClock.compareTo(a.logicalClock);
      if (cmp != 0) return cmp;
      return (b.deviceId ?? '').compareTo(a.deviceId ?? '');
    });
    return list;
  }

  @override
  Future<FinancialTransactionEntity?> findById(dynamic id) async {
    try {
      return InMemoryDb.transactions.firstWhere((t) => t.id == id);
    } catch (_) {
      return null;
    }
  }

  double _getCustomerBalance(String customerId) {
    try {
      final c = InMemoryDb.customers.firstWhere((c) => c.id == customerId);
      return c.balance;
    } catch (_) {
      return 0.0;
    }
  }

  void _logInMemoryTrigger(String triggerName, String customerId, String txId, double before, double after) {
    triggerAuditLogs.add({
      'trigger_name': triggerName,
      'customer_id': customerId,
      'transaction_id': txId,
      'before_balance': before,
      'after_balance': after,
      'timestamp': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<int> create(FinancialTransactionEntity entity) async {
    final before = _getCustomerBalance(entity.customerId);
    
    int nextClock = entity.logicalClock;
    if (nextClock == 0) {
      int maxClock = 0;
      for (final tx in InMemoryDb.transactions) {
        if (tx.logicalClock > maxClock) {
          maxClock = tx.logicalClock;
        }
      }
      nextClock = maxClock + 1;
    }
    final txDeviceId = entity.deviceId ?? deviceId ?? 'in-memory-device';

    final storedTx = FinancialTransactionEntity(
      id: entity.id,
      type: entity.type,
      customerId: entity.customerId,
      amount: entity.amount,
      paidAmount: entity.paidAmount,
      debtAmount: entity.debtAmount,
      date: entity.date,
      referenceId: entity.referenceId,
      metadata: entity.metadata,
      logicalClock: nextClock,
      deviceId: txDeviceId,
    );

    InMemoryDb.transactions.add(storedTx);
    _syncCustomerBalance(entity.customerId, storedTx, isInsert: true);
    final after = _getCustomerBalance(entity.customerId);
    _logInMemoryTrigger('trg_ft_insert', entity.customerId, entity.id, before, after);
    return 1;
  }

  @override
  Future<int> update(FinancialTransactionEntity entity) async {
    throw UnsupportedError('Kritik Hata: Finansal defter kayıtları değiştirilemez (Ledger Immutability).');
  }

  @override
  Future<int> delete(dynamic id) async {
    throw UnsupportedError('Kritik Hata: Finansal defter kayıtları silinemez (Ledger Immutability).');
  }

  void _syncCustomerBalance(String customerId, FinancialTransactionEntity tx, {required bool isInsert}) {
    double effect = 0.0;
    if (tx.type == 'sale') {
      effect = -tx.debtAmount;
    } else if (tx.type == 'payment') {
      effect = tx.paidAmount;
    } else if (tx.type == 'cancellation') {
      effect = tx.debtAmount;
    } else if (tx.type == 'collection') {
      effect = tx.paidAmount;
    } else if (tx.type == 'refund' && tx.paidAmount == 0) {
      effect = tx.amount;
    }

    if (!isInsert) {
      effect = -effect;
    }

    final custIdx = InMemoryDb.customers.indexWhere((c) => c.id == customerId);
    if (custIdx != -1) {
      final c = InMemoryDb.customers[custIdx];
      InMemoryDb.customers[custIdx] = CustomerEntity(
        id: c.id,
        name: c.name,
        email: c.email,
        phone: c.phone,
        balance: c.balance + effect,
        createdAt: c.createdAt,
      );
    }
  }

  @override
  Future<int> count() async {
    return InMemoryDb.transactions.length;
  }

  @override
  Future<bool> exists(dynamic id) async {
    return InMemoryDb.transactions.any((t) => t.id == id);
  }

  @override
  Future<List<FinancialTransactionEntity>> getByCustomerId(String customerId) async {
    final list = InMemoryDb.transactions.where((t) => t.customerId == customerId).toList();
    list.sort((a, b) {
      final cmp = b.logicalClock.compareTo(a.logicalClock);
      if (cmp != 0) return cmp;
      return (b.deviceId ?? '').compareTo(a.deviceId ?? '');
    });
    return list;
  }

  @override
  Future<List<FinancialTransactionEntity>> getByType(String type) async {
    final list = InMemoryDb.transactions.where((t) => t.type == type).toList();
    list.sort((a, b) {
      final cmp = b.logicalClock.compareTo(a.logicalClock);
      if (cmp != 0) return cmp;
      return (b.deviceId ?? '').compareTo(a.deviceId ?? '');
    });
    return list;
  }

  @override
  Future<List<FinancialTransactionEntity>> getByDateRange(DateTime from, DateTime to) async {
    final list = InMemoryDb.transactions
        .where((t) => t.date.isAfter(from) && t.date.isBefore(to))
        .toList();
    list.sort((a, b) {
      final cmp = b.logicalClock.compareTo(a.logicalClock);
      if (cmp != 0) return cmp;
      return (b.deviceId ?? '').compareTo(a.deviceId ?? '');
    });
    return list;
  }

  @override
  Future<double> getBalance(String customerId) async {
    double balance = 0;
    for (final tx in InMemoryDb.transactions) {
      if (tx.customerId == customerId) {
        balance += (tx.debtAmount - tx.paidAmount);
      }
    }
    return balance;
  }
}

/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
/// Order Repository
/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
class InMemoryOrderRepository implements IOrderRepository {
  @override
  Future<List<OrderEntity>> findAll() async {
    return InMemoryDb.orders;
  }

  @override
  Future<OrderEntity?> findById(dynamic id) async {
    try {
      return InMemoryDb.orders.firstWhere((o) => o.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> create(OrderEntity entity) async {
    InMemoryDb.orders.add(entity);
    return 1;
  }

  @override
  Future<int> update(OrderEntity entity) async {
    final idx = InMemoryDb.orders.indexWhere((o) => o.id == entity.id);
    if (idx != -1) {
      InMemoryDb.orders[idx] = entity;
      return 1;
    }
    return 0;
  }

  @override
  Future<int> delete(dynamic id) async {
    final idx = InMemoryDb.orders.indexWhere((o) => o.id == id);
    if (idx != -1) {
      InMemoryDb.orders.removeAt(idx);
      return 1;
    }
    return 0;
  }

  @override
  Future<int> count() async {
    return InMemoryDb.orders.length;
  }

  @override
  Future<bool> exists(dynamic id) async {
    return InMemoryDb.orders.any((o) => o.id == id);
  }

  @override
  Future<List<OrderEntity>> getByCustomerId(String customerId) async {
    return InMemoryDb.orders.where((o) => o.customerId == customerId).toList();
  }

  @override
  Future<List<OrderEntity>> getByStatus(String status) async {
    return InMemoryDb.orders.where((o) => o.status == status).toList();
  }

  @override
  Future<List<OrderEntity>> getPending() async {
    return InMemoryDb.orders
        .where((o) => o.status == 'created' || o.status == 'preparing' || o.status == 'ready')
        .toList();
  }

  @override
  Future<void> updateStatus(String orderId, String status) async {
    final idx = InMemoryDb.orders.indexWhere((o) => o.id == orderId);
    if (idx != -1) {
      final o = InMemoryDb.orders[idx];
      InMemoryDb.orders[idx] = OrderEntity(
        id: o.id,
        customerId: o.customerId,
        status: status,
        createdAt: o.createdAt,
        expectedDeliveryDate: o.expectedDeliveryDate,
        actualDeliveryDate: status == 'delivered' ? DateTime.now() : o.actualDeliveryDate,
        items: o.items,
      );
    }
  }

  @override
  Future<List<OrderEntity>> getOverdue() async {
    final now = DateTime.now();
    return InMemoryDb.orders
        .where((o) => o.expectedDeliveryDate != null && o.expectedDeliveryDate!.isBefore(now) && o.status != 'delivered')
        .toList();
  }
}

/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
/// Settings Repository
/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
class InMemorySettingsRepository implements ISettingsRepository {
  @override
  Future<Settings> getSettings() async {
    return InMemoryDb.settings;
  }

  @override
  Future<void> updateSettings(Settings settings) async {
    InMemoryDb.settings = settings;
  }
}

/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
/// Report Repository
/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
class InMemoryReportRepository implements IReportRepository {
  @override
  Future<List<DailyRevenue>> getDailyRevenue(DateRange range) async {
    final Map<String, Map<String, dynamic>> dailyMap = {};
    for (final s in InMemoryDb.sales) {
      if (s.createdAt.isAfter(range.from) && s.createdAt.isBefore(range.to) && s.status != 'cancelled') {
        final dayKey = s.createdAt.toIso8601String().substring(0, 10);
        final entry = dailyMap.putIfAbsent(dayKey, () => {
          'total': 0.0,
          'count': 0,
          'cash': 0.0,
          'debt': 0.0,
        });
        entry['total'] = (entry['total'] as double) + s.totalAmount;
        entry['count'] = (entry['count'] as int) + 1;
        if (s.paymentMethod == 'cash' || s.paymentMethod == 'card') {
          entry['cash'] = (entry['cash'] as double) + s.paidAmount;
        } else {
          entry['debt'] = (entry['debt'] as double) + (s.totalAmount - s.paidAmount);
        }
      }
    }

    final sortedKeys = dailyMap.keys.toList()..sort();
    return sortedKeys.map((day) {
      final m = dailyMap[day]!;
      return DailyRevenue(
        date: DateTime.parse(day),
        totalAmount: m['total'] as double,
        saleCount: m['count'] as int,
        cashAmount: m['cash'] as double,
        debtAmount: m['debt'] as double,
      );
    }).toList();
  }

  @override
  Future<List<CategoryRevenue>> getCategoryRevenue(DateRange range) async {
    final Map<String, double> categorySums = {};
    final Map<String, int> categoryCounts = {};
    double totalRevenue = 0.0;

    for (final s in InMemoryDb.sales) {
      if (s.createdAt.isAfter(range.from) && s.createdAt.isBefore(range.to) && s.status != 'cancelled') {
        for (final item in s.items) {
          final prodId = item['product_id'] as String;
          final prod = InMemoryDb.products.firstWhere(
            (p) => p.id == prodId,
            orElse: () => ProductEntity(id: '', name: 'Di�Ÿer', description: '', price: 0, quantity: 0, category: 'Di�Ÿer'),
          );
          final category = prod.category;
          final subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0.0;
          final quantity = item['quantity'] as int? ?? 1;

          categorySums[category] = (categorySums[category] ?? 0.0) + subtotal;
          categoryCounts[category] = (categoryCounts[category] ?? 0) + quantity;
          totalRevenue += subtotal;
        }
      }
    }

    return categorySums.entries.map((entry) {
      final category = entry.key;
      final sum = entry.value;
      final count = categoryCounts[category] ?? 0;
      final percentage = totalRevenue == 0 ? 0.0 : (sum / totalRevenue) * 100;
      return CategoryRevenue(
        categoryId: category,
        categoryName: category,
        totalAmount: sum,
        saleCount: count,
        percentage: percentage,
      );
    }).toList();
  }

  @override
  Future<List<ProductPerformance>> getTopProducts(DateRange range, {int limit = 10}) async {
    final Map<String, _ProductAccumulator> performanceMap = {};
    for (final s in InMemoryDb.sales) {
      if (s.createdAt.isAfter(range.from) && s.createdAt.isBefore(range.to) && s.status != 'cancelled') {
        for (final item in s.items) {
          final prodId = item['product_id'] as String;
          final qty = item['quantity'] as int? ?? 0;
          final subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0.0;

          final accum = performanceMap.putIfAbsent(prodId, () {
            final prod = InMemoryDb.products.firstWhere(
              (p) => p.id == prodId,
              orElse: () => ProductEntity(id: '', name: 'Di�Ÿer', description: '', price: 0, quantity: 0, category: 'Di�Ÿer'),
            );
            return _ProductAccumulator(prod.name, prod.category);
          });
          accum.totalSold += qty;
          accum.totalRevenue += subtotal;
        }
      }
    }

    final list = performanceMap.entries.map((entry) {
      final prodId = entry.key;
      final accum = entry.value;
      return ProductPerformance(
        productId: prodId,
        productName: accum.name,
        categoryName: accum.category,
        totalSold: accum.totalSold,
        totalRevenue: accum.totalRevenue,
        avgPrice: accum.totalSold == 0 ? 0.0 : accum.totalRevenue / accum.totalSold,
        rank: 0,
      );
    }).toList();

    list.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    final limitedList = list.take(limit).toList();
    for (int i = 0; i < limitedList.length; i++) {
      limitedList[i] = ProductPerformance(
        productId: limitedList[i].productId,
        productName: limitedList[i].productName,
        categoryName: limitedList[i].categoryName,
        totalSold: limitedList[i].totalSold,
        totalRevenue: limitedList[i].totalRevenue,
        avgPrice: limitedList[i].avgPrice,
        rank: i + 1,
      );
    }
    return limitedList;
  }

  @override
  Future<List<DebtAgingRow>> getDebtAging() async {
    final now = DateTime.now();
    final Map<String, _DebtAgingAccumulator> agingMap = {};

    for (final c in InMemoryDb.customers) {
      if (c.balance < 0) {
        agingMap.putIfAbsent(c.id, () => _DebtAgingAccumulator(c.name));
      }
    }

    for (final tx in InMemoryDb.transactions) {
      final debt = tx.debtAmount - tx.paidAmount;
      if (debt <= 0) continue;

      final customer = agingMap[tx.customerId];
      if (customer == null) continue;

      final diffDays = now.difference(tx.date).inDays;
      if (diffDays <= 30) {
        customer.current += debt;
      } else if (diffDays <= 60) {
        customer.days31to60 += debt;
      } else if (diffDays <= 90) {
        customer.days61to90 += debt;
      } else {
        customer.over90 += debt;
      }
    }

    return agingMap.entries.map((entry) {
      final customerId = entry.key;
      final accum = entry.value;
      return DebtAgingRow(
        customerId: customerId,
        customerName: accum.name,
        current: accum.current,
        days31to60: accum.days31to60,
        days61to90: accum.days61to90,
        over90: accum.over90,
      );
    }).toList();
  }

  @override
  Future<ReportSummary> getSummary(DateRange range) async {
    double totalRevenue = 0.0;
    int totalSales = 0;
    double totalDebt = 0.0;
    double totalCollected = 0.0;

    for (final s in InMemoryDb.sales) {
      if (s.createdAt.isAfter(range.from) && s.createdAt.isBefore(range.to) && s.status != 'cancelled') {
        totalRevenue += s.totalAmount;
        totalSales++;
        totalCollected += s.paidAmount;
        totalDebt += (s.totalAmount - s.paidAmount);
      }
    }

    final newCustomers = InMemoryDb.customers.where((c) => c.createdAt.isAfter(range.from) && c.createdAt.isBefore(range.to)).length;

    return ReportSummary(
      totalRevenue: totalRevenue,
      totalSales: totalSales,
      totalDebt: totalDebt,
      totalCollected: totalCollected,
      avgBasket: totalSales == 0 ? 0.0 : totalRevenue / totalSales,
      newCustomers: newCustomers,
      range: range,
    );
  }
}

/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
/// Dashboard Repository
/// �•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•��•�
class InMemoryDashboardRepository implements IDashboardRepository {
  @override
  Future<DashboardSummary> getTodaySummary() async {
    final now = DateTime.now();
    double todayRevenue = 0.0;
    double todayDebt = 0.0;
    double todayCollected = 0.0;
    int totalSalesToday = 0;

    for (final s in InMemoryDb.sales) {
      if (s.createdAt.year == now.year && s.createdAt.month == now.month && s.createdAt.day == now.day && s.status != 'cancelled') {
        totalSalesToday++;
        todayRevenue += s.totalAmount;
        todayCollected += s.paidAmount;
        todayDebt += (s.totalAmount - s.paidAmount);
      }
    }

    final pendingOrdersCount = InMemoryDb.orders
        .where((o) => o.status == 'created' || o.status == 'preparing' || o.status == 'ready')
        .length;

    final totalReceivables = InMemoryDb.customers
        .where((c) => c.balance < 0)
        .fold<double>(0.0, (sum, c) => sum + c.balance.abs());

    return DashboardSummary(
      totalSalesToday: totalSalesToday,
      todayRevenue: todayRevenue,
      todayDebt: todayDebt,
      todayCollected: todayCollected,
      pendingOrdersCount: pendingOrdersCount,
      totalReceivables: totalReceivables,
    );
  }

  @override
  Future<List<SalesTrendPoint>> getWeeklyTrend() async {
    final now = DateTime.now();
    final sevenDaysAgo = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
    
    final Map<String, double> revenueMap = {};
    final Map<String, int> countMap = {};

    for (final s in InMemoryDb.sales) {
      if (s.createdAt.isAfter(sevenDaysAgo) && s.status != 'cancelled') {
        final dayKey = s.createdAt.toIso8601String().substring(0, 10);
        revenueMap[dayKey] = (revenueMap[dayKey] ?? 0.0) + s.totalAmount;
        countMap[dayKey] = (countMap[dayKey] ?? 0) + 1;
      }
    }

    final List<SalesTrendPoint> trend = [];
    for (int i = 0; i < 7; i++) {
      final date = sevenDaysAgo.add(Duration(days: i));
      final dateKey = date.toIso8601String().substring(0, 10);
      trend.add(SalesTrendPoint(
        date: date,
        revenue: revenueMap[dateKey] ?? 0.0,
        saleCount: countMap[dateKey] ?? 0,
      ));
    }

    return trend;
  }

  @override
  Future<List<DashboardProductPerformance>> getTopProducts({int limit = 5}) async {
    final Map<String, _ProductAccumulator> performanceMap = {};
    for (final s in InMemoryDb.sales) {
      if (s.status != 'cancelled') {
        for (final item in s.items) {
          final prodId = item['product_id'] as String;
          final qty = item['quantity'] as int? ?? 0;
          final subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0.0;

          final accum = performanceMap.putIfAbsent(prodId, () {
            final prod = InMemoryDb.products.firstWhere(
              (p) => p.id == prodId,
              orElse: () => ProductEntity(id: '', name: 'Di�Ÿer', description: '', price: 0, quantity: 0, category: 'Di�Ÿer'),
            );
            return _ProductAccumulator(prod.name, prod.category);
          });
          accum.totalSold += qty;
          accum.totalRevenue += subtotal;
        }
      }
    }

    final list = performanceMap.entries.map((entry) {
      final prodId = entry.key;
      final accum = entry.value;
      return DashboardProductPerformance(
        productId: prodId,
        productName: accum.name,
        category: accum.category,
        totalSold: accum.totalSold,
        totalRevenue: accum.totalRevenue,
        rank: 0,
      );
    }).toList();

    list.sort((a, b) => b.totalRevenue.compareTo(a.totalRevenue));

    final limitedList = list.take(limit).toList();
    for (int i = 0; i < limitedList.length; i++) {
      limitedList[i] = DashboardProductPerformance(
        productId: limitedList[i].productId,
        productName: limitedList[i].productName,
        category: limitedList[i].category,
        totalSold: limitedList[i].totalSold,
        totalRevenue: limitedList[i].totalRevenue,
        rank: i + 1,
      );
    }
    return limitedList;
  }

  @override
  Future<List<DashboardCategoryShare>> getCategoryShares() async {
    final Map<String, double> categorySums = {};
    double totalRevenue = 0.0;

    for (final s in InMemoryDb.sales) {
      if (s.status != 'cancelled') {
        for (final item in s.items) {
          final prodId = item['product_id'] as String;
          final prod = InMemoryDb.products.firstWhere(
            (p) => p.id == prodId,
            orElse: () => ProductEntity(id: '', name: 'Di�Ÿer', description: '', price: 0, quantity: 0, category: 'Di�Ÿer'),
          );
          final category = prod.category;
          final subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0.0;

          categorySums[category] = (categorySums[category] ?? 0.0) + subtotal;
          totalRevenue += subtotal;
        }
      }
    }

    return categorySums.entries.map((entry) {
      final category = entry.key;
      final sum = entry.value;
      final percentage = totalRevenue == 0 ? 0.0 : (sum / totalRevenue) * 100;
      return DashboardCategoryShare(
        category: category,
        totalAmount: sum,
        percentage: percentage,
      );
    }).toList();
  }

  @override
  Future<List<SaleEntity>> getRecentSales({int limit = 5}) async {
    final list = List<SaleEntity>.from(InMemoryDb.sales);
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list.take(limit).toList();
  }

  @override
  Future<List<ProductEntity>> getLowStockProducts({int threshold = 5, int limit = 5}) async {
    final list = InMemoryDb.products.where((p) => p.quantity <= threshold).toList();
    list.sort((a, b) => a.quantity.compareTo(b.quantity));
    return list.take(limit).toList();
  }
}

/// Helper classes
class _ProductAccumulator {
  final String name;
  final String category;
  int totalSold = 0;
  double totalRevenue = 0.0;

  _ProductAccumulator(this.name, this.category);
}

class _DebtAgingAccumulator {
  final String name;
  double current = 0.0;
  double days31to60 = 0.0;
  double days61to90 = 0.0;
  double over90 = 0.0;

  _DebtAgingAccumulator(this.name);
}

/// In-Memory User Repository implementation for Web support
class InMemoryUserRepository implements IUserRepository {
  // Store password hashes keyed by userId for realistic Web behavior
  static final Map<String, String> _passwordHashes = {};

  @override
  Future<List<AuthUser>> findAll() async {
    return InMemoryDb.users;
  }

  @override
  Future<AuthUser?> findById(dynamic id) async {
    try {
      return InMemoryDb.users.firstWhere((u) => u.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AuthUser?> findByUsername(String username) async {
    try {
      return InMemoryDb.users.firstWhere((u) => u.email == username || u.name == username);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> getPasswordHash(String userId) async {
    return _passwordHashes[userId];
  }

  @override
  Future<void> updateLastLogin(String userId) async {}

  @override
  Future<void> updatePasswordHash(String userId, String passwordHash) async {
    _passwordHashes[userId] = passwordHash;
  }

  @override
  Future<void> insertUser(
    AuthUser user,
    String passwordHash, {
    String? username,
    String? pinHash,
    String? businessCode,
    int? deviceTokenVersion,
  }) async {
    InMemoryDb.users.removeWhere((u) => u.id == user.id);
    InMemoryDb.users.add(user);
    _passwordHashes[user.id] = passwordHash;
    if (pinHash != null) {
      _passwordHashes['${user.id}_pin'] = pinHash;
    }
  }

  @override
  Future<void> updateUserFields(
    AuthUser user, {
    bool? isActive,
    String? passwordHash,
    String? username,
    String? pinHash,
    String? businessCode,
    int? deviceTokenVersion,
  }) async {
    final index = InMemoryDb.users.indexWhere((u) => u.id == user.id);
    if (index != -1) {
      InMemoryDb.users[index] = user;
    }
    if (passwordHash != null) {
      _passwordHashes[user.id] = passwordHash;
    }
    if (pinHash != null) {
      _passwordHashes['${user.id}_pin'] = pinHash;
    }
  }

  @override
  Future<int> create(AuthUser user) async {
    await insertUser(user, '');
    return 1;
  }

  @override
  Future<int> update(AuthUser user) async {
    await updateUserFields(user);
    return 1;
  }

  @override
  Future<int> delete(dynamic id) async {
    InMemoryDb.users.removeWhere((u) => u.id == id);
    _passwordHashes.remove(id);
    _passwordHashes.remove('${id}_pin');
    return 1;
  }

  @override
  Future<int> count() async => InMemoryDb.users.length;

  @override
  Future<bool> exists(dynamic id) async {
    return InMemoryDb.users.any((u) => u.id == id);
  }

  @override
  Future<AuthUser?> findByBusinessCodeAndUsername(String businessCode, String username) async {
    // InMemory search
    return null;
  }

  @override
  Future<Map<String, String?>> getCredentialHashes(String userId) async {
    return {
      'password_hash': _passwordHashes[userId],
      'pin_hash': _passwordHashes['${userId}_pin'],
    };
  }
}
