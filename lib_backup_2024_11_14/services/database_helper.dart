import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';

// Order sınıfı
class Order {
  final int id;
  final int customerId;
  final String customerName;
  final String customerPhone;
  final DateTime orderDate;
  final String status;
  final double totalAmount;
  final double paidAmount;
  final List<OrderItem> items;

  const Order({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.orderDate,
    required this.status,
    required this.totalAmount,
    required this.paidAmount,
    required this.items,
  });
}

// OrderItem sınıfı
class OrderItem {
  final int id;
  final int orderId;
  final int productId;
  final String productName;
  final double price;
  final int quantity;
  final double totalPrice;

  const OrderItem({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    required this.totalPrice,
  });

  factory OrderItem.fromMap(Map<String, dynamic> map) {
    return OrderItem(
      id: map['id'] as int,
      orderId: map['orderId'] as int,
      productId: map['productId'] as int,
      productName: map['productName'] as String,
      price: map['price'] as double,
      quantity: map['quantity'] as int,
      totalPrice: (map['price'] as double) * (map['quantity'] as int),
    );
  }
}

// Payment sınıfı
class Payment {
  final int id;
  final int orderId;
  final double amount;
  final String paymentMethod;
  final DateTime date;
  final String note;

  const Payment({
    required this.id,
    required this.orderId,
    required this.amount,
    required this.paymentMethod,
    required this.date,
    required this.note,
  });

  factory Payment.fromMap(Map<String, dynamic> map) {
    return Payment(
      id: map['id'] as int,
      orderId: map['orderId'] as int,
      amount: map['amount'] as double,
      paymentMethod: map['paymentMethod'] as String,
      date: DateTime.parse(map['date'] as String),
      note: map['note'] as String,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'orderId': orderId,
      'amount': amount,
      'paymentMethod': paymentMethod,
      'date': date.toIso8601String(),
      'note': note,
    };
  }
}

// Expense sınıfı
class Expense {
  final int id;
  final String title;
  final double amount;
  final DateTime date;
  final String category;
  final String note;
  final String paymentMethod;

  const Expense({
    required this.id,
    required this.title,
    required this.amount,
    required this.date,
    required this.category,
    required this.note,
    required this.paymentMethod,
  });

  factory Expense.fromMap(Map<String, dynamic> map) {
    return Expense(
      id: map['id'] as int,
      title: map['title'] as String,
      amount: map['amount'] as double,
      date: DateTime.parse(map['date'] as String),
      category: map['category'] as String,
      note: map['notes'] as String? ?? '', // Veritabanında 'notes' olarak kayıtlı
      paymentMethod: 'Nakit', // Varsayılan değer
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'amount': amount,
      'date': date.toIso8601String(),
      'category': category,
      'note': note,
      'paymentMethod': paymentMethod,
    };
  }
}

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  static Database? _database;
  static Database? _ordersDatabase;
  static Database? _customersDatabase;
  static Database? _productsDatabase;

  factory DatabaseHelper() {
    return _instance;
  }

  DatabaseHelper._internal();

  // Ana veritabanı
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase('shaman_database.db');
    return _database!;
  }

  // Siparişler veritabanı
  Future<Database> get ordersDatabase async {
    if (_ordersDatabase != null) {
      return _ordersDatabase!;
    }
    
    _ordersDatabase = await _initDatabase('orders.db');
    return _ordersDatabase!;
  }

  // Müşteriler veritabanı
  Future<Database> get customersDatabase async {
    if (_customersDatabase != null) return _customersDatabase!;
    _customersDatabase = await _initDatabase('customers.db');
    return _customersDatabase!;
  }

  // Ürünler veritabanı
  Future<Database> get productsDatabase async {
    if (_productsDatabase != null) return _productsDatabase!;
    _productsDatabase = await _initDatabase('products.db');
    return _productsDatabase!;
  }

  Future<Database> _initDatabase(String dbName) async {
    try {
      // Uygulama belgeleri dizinini al (daha güvenli erişim için)
      Directory documentsDirectory = await getApplicationDocumentsDirectory();
      String path = join(documentsDirectory.path, dbName);
      
      print('Veritabanı yolu: $path');
      
      // Veritabanı dosyasının varlığını kontrol et
      bool exists = await File(path).exists();
      print('Veritabanı mevcut: $exists');
      
      // Veritabanını aç
      var db = await openDatabase(
        path,
        version: 1,
        onCreate: (db, version) async {
          print('Veritabanı oluşturuluyor: $dbName');
          if (dbName == 'shaman_database.db') {
            await _createDatabase(db, version);
          } else if (dbName == 'orders.db') {
            await _createOrdersDatabase(db, version);
          }
        },
        onOpen: (db) {
          print('Veritabanı açıldı: $dbName');
        },
        singleInstance: true,
        readOnly: false,
      );
      
      // Veritabanı yazılabilirliğini test et
      try {
        await db.execute('PRAGMA journal_mode=WAL');
        print('Veritabanı yazılabilir: $dbName');
      } catch (e) {
        print('Veritabanı yazılabilir değil: $e');
        // Veritabanını kapat
        await db.close();
        
        // Dosyayı sil ve yeniden oluştur
        try {
          await File(path).delete();
          print('Sorunlu veritabanı silindi, yeniden oluşturulacak');
          
          db = await openDatabase(
            path,
            version: 1,
            onCreate: (db, version) async {
              print('Veritabanı yeniden oluşturuluyor: $dbName');
              if (dbName == 'shaman_database.db') {
                await _createDatabase(db, version);
              } else if (dbName == 'orders.db') {
                await _createOrdersDatabase(db, version);
              }
            },
            singleInstance: true,
            readOnly: false,
          );
        } catch (deleteError) {
          print('Veritabanı silinemedi: $deleteError');
        }
      }
      
      return db;
    } catch (e) {
      print('Veritabanı açılırken hata: $e');
      rethrow;
    }
  }

  Future<void> _createOrdersDatabase(Database db, int version) async {
    // Siparişler tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerId INTEGER,
        customerName TEXT,
        customerPhone TEXT,
        orderDate TEXT,
        status TEXT,
        totalAmount REAL,
        paidAmount REAL
      )
    ''');
    
    // Sipariş öğeleri tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderId INTEGER,
        productId INTEGER,
        productName TEXT,
        price REAL,
        quantity INTEGER,
        FOREIGN KEY (orderId) REFERENCES orders (id)
      )
    ''');
    
    // Ödemeler tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderId INTEGER,
        amount REAL,
        paymentDate TEXT,
        notes TEXT,
        method TEXT,
        FOREIGN KEY (orderId) REFERENCES orders (id)
      )
    ''');
    
    // Giderler tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        amount REAL,
        date TEXT,
        category TEXT,
        notes TEXT
      )
    ''');
    
    // Database initialized successfully
  }

  Future<void> _createDatabase(Database db, int version) async {
    // Müşteri tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        phone TEXT,
        email TEXT,
        address TEXT,
        notes TEXT
      )
    ''');

    // Ürün tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT,
        price REAL,
        description TEXT,
        category TEXT,
        imageUrl TEXT
      )
    ''');

    // Sipariş tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerId INTEGER,
        customerName TEXT,
        customerPhone TEXT,
        orderDate TEXT,
        status TEXT,
        totalAmount REAL,
        paidAmount REAL,
        FOREIGN KEY (customerId) REFERENCES customers (id)
      )
    ''');

    // Sipariş öğeleri tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderId INTEGER,
        productId INTEGER,
        productName TEXT,
        price REAL,
        quantity INTEGER,
        FOREIGN KEY (orderId) REFERENCES orders (id),
        FOREIGN KEY (productId) REFERENCES products (id)
      )
    ''');

    // Ödeme tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payments(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderId INTEGER,
        amount REAL,
        paymentDate TEXT,
        notes TEXT,
        method TEXT,
        FOREIGN KEY (orderId) REFERENCES orders (id)
      )
    ''');

    // Giderler tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT,
        amount REAL,
        date TEXT,
        category TEXT,
        notes TEXT
      )
    ''');
    
    // İşletme ayarları tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS business_profile(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        company_name TEXT,
        phone TEXT,
        address TEXT,
        email TEXT,
        store_name TEXT,
        note TEXT,
        tax_number TEXT,
        currency TEXT,
        logo_path TEXT
      )
    ''');
    
    // Varsayılan işletme bilgilerini ekle
    await db.insert(
      'business_profile',
      {
        'company_name': 'Şirket Adı',
        'phone': '+90 555 123 4567',
        'address': 'İstanbul, Türkiye',
        'email': 'işletme@email.com',
        'store_name': 'Shaman Market',
        'note': 'Bizi tercih ettiğiniz için teşekkür ederiz!',
        'tax_number': '1234567890',
        'currency': '₺ TL',
        'logo_path': null
      },
      conflictAlgorithm: ConflictAlgorithm.ignore
    );
  }

  // Sipariş işlemleri
  Future<List<Order>> getOrders() async {
    try {
      final db = await ordersDatabase;
      
      final List<Map<String, dynamic>> orderMaps = await db.query('orders');
      
      List<Order> orders = [];
      
      for (var orderMap in orderMaps) {
        final List<Map<String, dynamic>> itemMaps = await db.query(
          'order_items',
          where: 'orderId = ?',
          whereArgs: [orderMap['id']],
        );
        
        List<OrderItem> items = itemMaps.map((itemMap) => OrderItem.fromMap(itemMap)).toList();
        
        Order order = Order(
          id: orderMap['id'] as int,
          customerId: orderMap['customerId'] as int,
          customerName: orderMap['customerName'] as String,
          customerPhone: orderMap['customerPhone'] as String,
          orderDate: DateTime.parse(orderMap['orderDate'] as String),
          status: orderMap['status'] as String,
          totalAmount: (orderMap['totalAmount'] as num).toDouble(),
          paidAmount: (orderMap['paidAmount'] as num).toDouble(),
          items: items,
        );
        
        orders.add(order);
      }
      
      return orders;
    } catch (e) {
      if (e.toString().contains('database_closed')) {
        _ordersDatabase = null;
        return getOrders();
      }
      return [];
    }
  }

  // Tüm ödemeleri getir
  Future<List<Payment>> getAllPayments() async {
    try {
      final db = await ordersDatabase;
      
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='payments'");
      if (tables.isEmpty) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS payments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            orderId INTEGER,
            amount REAL,
            paymentDate TEXT,
            notes TEXT,
            method TEXT,
            FOREIGN KEY (orderId) REFERENCES orders (id)
          )
        ''');
        
        // Database upgrade completed
      }
      
      final List<Map<String, dynamic>> paymentMaps = await db.query('payments');
      
      return paymentMaps.map((map) => Payment.fromMap(map)).toList();
    } catch (e) {
      if (e.toString().contains('database_closed')) {
        _ordersDatabase = null;
        return getAllPayments();
      }
      return [];
    }
  }
  
  // Sample payment data insertion removed
  Future<void> _insertSamplePayments(Database db) async {
    final List<Map<String, dynamic>> orders = await db.query('orders');
    if (orders.isEmpty) return;
    
    for (var order in orders) {
      final int orderId = order['id'] as int;
      final double paidAmount = (order['paidAmount'] as num).toDouble();
      
      if (paidAmount > 0) {
        await db.insert('payments', {
          'orderId': orderId,
          'amount': paidAmount,
          'paymentDate': order['orderDate'],
          'notes': 'Otomatik oluşturulan ödeme',
          'method': 'Nakit',
        });
      }
    }
  }
  
  // Belirli bir siparişin ödemelerini getir
  Future<List<Payment>> getPaymentsByOrderId(int orderId) async {
    try {
      final db = await ordersDatabase;
      final List<Map<String, dynamic>> paymentMaps = await db.query(
        'payments',
        where: 'orderId = ?',
        whereArgs: [orderId],
      );
      
      return paymentMaps.map((map) => Payment.fromMap(map)).toList();
    } catch (e) {
      return [];
    }
  }
  
  // Ödeme ekleme
  Future<int> addPayment(int orderId, double amount, String notes, String method) async {
    try {
      final db = await ordersDatabase;
      
      final paymentId = await db.insert('payments', {
        'orderId': orderId,
        'amount': amount,
        'paymentDate': DateTime.now().toIso8601String(),
        'notes': notes,
        'method': method,
      });
      
      final orderMap = (await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [orderId],
      )).first;
      
      final double currentPaidAmount = (orderMap['paidAmount'] as num).toDouble();
      final double newPaidAmount = currentPaidAmount + amount;
      
      await db.update(
        'orders',
        {'paidAmount': newPaidAmount},
        where: 'id = ?',
        whereArgs: [orderId],
      );
      
      if (newPaidAmount >= (orderMap['totalAmount'] as num).toDouble()) {
        await db.update(
          'orders',
          {'status': 'Tamamlandı'},
          where: 'id = ?',
          whereArgs: [orderId],
        );
      }
      
      return paymentId;
    } catch (e) {
      throw Exception('Ödeme eklenirken bir hata oluştu: $e');
    }
  }
  
  // Ödeme silme
  Future<int> deletePayment(int paymentId) async {
    try {
      final db = await ordersDatabase;
      
      final paymentMap = (await db.query(
        'payments',
        where: 'id = ?',
        whereArgs: [paymentId],
      )).first;
      
      final int orderId = paymentMap['orderId'] as int;
      final double amount = (paymentMap['amount'] as num).toDouble();
      
      await db.delete(
        'payments',
        where: 'id = ?',
        whereArgs: [paymentId],
      );
      
      final orderMap = (await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [orderId],
      )).first;
      
      final double currentPaidAmount = (orderMap['paidAmount'] as num).toDouble();
      final double newPaidAmount = currentPaidAmount - amount;
      
      await db.update(
        'orders',
        {'paidAmount': newPaidAmount},
        where: 'id = ?',
        whereArgs: [orderId],
      );
      
      if (newPaidAmount < (orderMap['totalAmount'] as num).toDouble()) {
        await db.update(
          'orders',
          {'status': 'Hazırlanıyor'},
          where: 'id = ?',
          whereArgs: [orderId],
        );
      }
      
      return orderId;
    } catch (e) {
      throw Exception('Ödeme silinirken bir hata oluştu: $e');
    }
  }
  
  // Finansal özet bilgilerini getir
  Future<Map<String, double>> getFinancialSummary() async {
    try {
      _ordersDatabase = null;
      final db = await ordersDatabase;
      
      // Tüm siparişleri kontrol et
      final allOrders = await db.query('orders');
      print('DatabaseHelper - Toplam sipariş sayısı: ${allOrders.length}');
      
      final totalSalesResult = await db.rawQuery(
        'SELECT SUM(totalAmount) as total FROM orders'
      );
      final double totalSales = totalSalesResult.first['total'] != null 
        ? (totalSalesResult.first['total'] as num).toDouble()
        : 0.0;
      print('DatabaseHelper - Toplam satış: $totalSales');
      
      final totalPaidResult = await db.rawQuery(
        'SELECT SUM(paidAmount) as total FROM orders'
      );
      final double totalPaid = totalPaidResult.first['total'] != null 
        ? (totalPaidResult.first['total'] as num).toDouble()
        : 0.0;
      print('DatabaseHelper - Toplam ödenen: $totalPaid');
      
      final double totalDebt = totalSales - totalPaid;
      print('DatabaseHelper - Toplam borç: $totalDebt');
      
      // Expenses tablosunu kontrol et
      final expensesTable = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='expenses'");
      print('DatabaseHelper - Expenses tablosu var mı: ${expensesTable.isNotEmpty}');
      
      double totalExpenses = 0.0;
      if (expensesTable.isNotEmpty) {
        final totalExpensesResult = await db.rawQuery(
          'SELECT SUM(amount) as total FROM expenses'
        );
        totalExpenses = totalExpensesResult.first['total'] != null 
          ? (totalExpensesResult.first['total'] as num).toDouble()
          : 0.0;
        print('DatabaseHelper - Toplam gider: $totalExpenses');
      }
      
      final result = {
        'totalSales': totalSales,
        'totalPaid': totalPaid,
        'totalDebt': totalDebt,
        'totalExpenses': totalExpenses,
      };
      
      print('DatabaseHelper - Finansal özet sonucu: $result');
      return result;
    } catch (e) {
      print('DatabaseHelper - Finansal özet hatası: $e');
      return {
        'totalSales': 0.0,
        'totalPaid': 0.0,
        'totalDebt': 0.0,
        'totalExpenses': 0.0,
      };
    }
  }
  
  // payment_history tablosundan ödemeleri getir
  Future<List<Map<String, dynamic>>> getPaymentHistory([int? orderId]) async {
    try {
      _ordersDatabase = null;
      final db = await ordersDatabase;
      
      final historyTables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='payment_history'");
      if (historyTables.isEmpty) {
        return [];
      }
      
      // Payment history table structure checked
      
      final List<Map<String, dynamic>> payments;
      if (orderId != null) {
        payments = await db.query(
          'payment_history',
          where: 'orderId = ?',
          whereArgs: [orderId],
        );
      } else {
        payments = await db.query('payment_history');
      }
      
      if (payments.isNotEmpty) {
      }
      
      final List<Map<String, dynamic>> result = [];
      
      for (var payment in payments) {
        try {
          final orderId = payment['orderId'] as int;
          
          final orderInfo = await db.query(
            'orders',
            where: 'id = ?',
            whereArgs: [orderId],
          );
          
          if (orderInfo.isNotEmpty) {
            final customerName = orderInfo.first['customerName'] as String? ?? 'Bilinmeyen Müşteri';
            
            double amount = 0.0;
            if (payment.containsKey('amount')) {
              amount = (payment['amount'] as num).toDouble();
            }
            
            String paymentDate = DateTime.now().toIso8601String();
            if (payment.containsKey('paymentDate')) {
              paymentDate = payment['paymentDate'] as String;
            }
            
            String method = 'Nakit';
            if (payment.containsKey('method')) {
              method = payment['method'] as String? ?? 'Nakit';
            }
            
            result.add({
              'id': payment['id'] as int,
              'orderId': orderId,
              'customerName': customerName,
              'amount': amount,
              'date': DateTime.parse(paymentDate),
              'method': method,
            });
          }
        } catch (e) {
        }
      }
      
      return result;
    } catch (e) {
      return [];
    }
  }

  // Son ödemeleri getir
  Future<List<Map<String, dynamic>>> getRecentPayments({int limit = 10}) async {
    try {
      _ordersDatabase = null;
      final db = await ordersDatabase;
      
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='payments'");
      if (tables.isEmpty) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS payments(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            orderId INTEGER,
            amount REAL,
            paymentDate TEXT,
            notes TEXT,
            method TEXT,
            FOREIGN KEY (orderId) REFERENCES orders (id)
          )
        ''');
        
        // Database upgrade completed
      }
      
      final historyTables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='payment_history'");
      
      if (historyTables.isNotEmpty) {
        // Payment history tablosu mevcut
      }
      
      List<Map<String, dynamic>> paymentMaps = [];
      
      try {
        final List<Map<String, dynamic>> regularPayments = await db.rawQuery('''
          SELECT 
            p.id, 
            p.orderId, 
            p.amount, 
            p.paymentDate, 
            p.notes, 
            p.method,
            o.customerName
          FROM payments p
          JOIN orders o ON p.orderId = o.id
          ORDER BY p.paymentDate DESC
        ''');
        
        paymentMaps.addAll(regularPayments);
      } catch (e) {
      }
      
      if (historyTables.isNotEmpty) {
        try {
          final historyPayments = await getPaymentHistory();
          paymentMaps.addAll(historyPayments);
        } catch (e) {
        }
      }
      
      if (paymentMaps.isNotEmpty) {
        paymentMaps.sort((a, b) {
          try {
            final dateA = a['date'] as DateTime;
            final dateB = b['date'] as DateTime;
            return dateB.compareTo(dateA);
          } catch (e) {
            return 0;
          }
        });
        
        if (paymentMaps.length > limit) {
          paymentMaps = paymentMaps.sublist(0, limit);
        }
      }
      
      return paymentMaps;
    } catch (e) {
      return [];
    }
  }
  
  // Borçlu müşterileri getir
  Future<List<Map<String, dynamic>>> getCustomersWithDebt() async {
    try {
      _ordersDatabase = null;
      final db = await ordersDatabase;
      
      final List<Map<String, dynamic>> results = await db.rawQuery('''
        SELECT 
          o.customerId,
          o.customerName,
          SUM(o.totalAmount - o.paidAmount) as totalDebt,
          MAX(o.orderDate) as lastOrderDate
        FROM orders o
        WHERE o.totalAmount > o.paidAmount
        GROUP BY o.customerId
        HAVING totalDebt > 0
        ORDER BY totalDebt DESC
      ''');
      
      return results.map((result) {
        return {
          'id': result['customerId'] as int,
          'customerId': result['customerId'] as int,
          'customerName': result['customerName'] as String,
          'totalDebt': (result['totalDebt'] as num).toDouble(),
          'lastOrderDate': DateTime.parse(result['lastOrderDate'] as String),
        };
      }).toList();
    } catch (e) {
      return [];
    }
  }

  // Gider ekle
  Future<int> addExpense(String title, double amount, String category, String notes) async {
    try {
      final db = await ordersDatabase;
      
      final id = await db.insert(
        'expenses',
        {
          'title': title,
          'amount': amount,
          'date': DateTime.now().toIso8601String(),
          'category': category,
          'notes': notes,
        },
      );
      
      return id;
    } catch (e) {
      throw Exception('Gider eklenirken bir hata oluştu: $e');
    }
  }
  
  // Gider sil
  Future<int> deleteExpense(int expenseId) async {
    try {
      final db = await ordersDatabase;
      
      return await db.delete(
        'expenses',
        where: 'id = ?',
        whereArgs: [expenseId],
      );
    } catch (e) {
      throw Exception('Gider silinirken bir hata oluştu: $e');
    }
  }
  
  // Tüm giderleri getir
  Future<List<Expense>> getAllExpenses() async {
    try {
      final db = await ordersDatabase;
      
      // Expenses tablosunu kontrol et
      final expensesTable = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='expenses'");
      print('DatabaseHelper - getAllExpenses - Expenses tablosu var mı: ${expensesTable.isNotEmpty}');
      
      if (expensesTable.isEmpty) {
        print('DatabaseHelper - getAllExpenses - Expenses tablosu bulunamadı');
        return [];
      }
      
      final List<Map<String, dynamic>> maps = await db.query(
        'expenses',
        orderBy: 'date DESC',
      );
      
      print('DatabaseHelper - getAllExpenses - Toplam gider sayısı: ${maps.length}');
      
      return List.generate(maps.length, (i) {
        return Expense.fromMap(maps[i]);
      });
    } catch (e) {
      print('DatabaseHelper - getAllExpenses hatası: $e');
      return [];
    }
  }
  
  // Giderleri kategoriye göre getir
  Future<List<Expense>> getExpensesByCategory(String category) async {
    try {
      final db = await ordersDatabase;
      
      final List<Map<String, dynamic>> maps = await db.query(
        'expenses',
        where: 'category = ?',
        whereArgs: [category],
        orderBy: 'date DESC',
      );
      
      return List.generate(maps.length, (i) {
        return Expense.fromMap(maps[i]);
      });
    } catch (e) {
      return [];
    }
  }

  // Sample expense data insertion removed
  Future<void> _insertSampleExpenses(Database db) async {
    final now = DateTime.now();
    
    await db.insert('expenses', {
      'title': 'Kira Ödemesi',
      'amount': 5000.0,
      'date': now.subtract(const Duration(days: 5)).toIso8601String(),
      'category': 'Kira',
      'notes': 'Aylık kira ödemesi',
    });
    
    await db.insert('expenses', {
      'title': 'Elektrik Faturası',
      'amount': 750.0,
      'date': now.subtract(const Duration(days: 10)).toIso8601String(),
      'category': 'Fatura',
      'notes': 'Mart ayı elektrik faturası',
    });
    
    await db.insert('expenses', {
      'title': 'İnternet Faturası',
      'amount': 300.0,
      'date': now.subtract(const Duration(days: 15)).toIso8601String(),
      'category': 'Fatura',
      'notes': 'Mart ayı internet faturası',
    });
    
    await db.insert('expenses', {
      'title': 'Personel Maaşı',
      'amount': 8500.0,
      'date': now.subtract(const Duration(days: 2)).toIso8601String(),
      'category': 'Personel',
      'notes': 'Mart ayı personel maaşı',
    });
    
    await db.insert('expenses', {
      'title': 'Malzeme Alımı',
      'amount': 1200.0,
      'date': now.subtract(const Duration(days: 8)).toIso8601String(),
      'category': 'Malzeme',
      'notes': 'Ofis malzemeleri',
    });
  }

  // Sample data insertion removed
  Future<void> _insertSampleData(Database db) async {
    final orderId = await db.insert(
      'orders',
      {
        'customerId': 1,
        'customerName': 'Sample Customer',
        'customerPhone': '5551234567',
        'orderDate': DateTime.now().toIso8601String(),
        'status': 'Hazırlanıyor',
        'totalAmount': 100.0,
        'paidAmount': 50.0,
      },
    );
    
    await db.insert(
      'order_items',
      {
        'orderId': orderId,
        'productId': 1,
        'productName': 'Sample Product',
        'price': 50.0,
        'quantity': 2,
      },
    );
    
    await db.insert(
      'payments',
      {
        'orderId': orderId,
        'amount': 50.0,
        'paymentDate': DateTime.now().toIso8601String(),
        'notes': 'İlk ödeme',
        'method': 'Nakit',
      },
    );
    
    await _insertSampleExpenses(db);
  }

  // İşletme bilgilerini güncelle
  Future<int> updateBusinessProfile(Map<String, dynamic> profile) async {
    try {
      final db = await database;
      
      // İşletme profilini güncelle
      int result;
      
      // Veritabanı tablosunun varlığını kontrol et
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='business_profile'");
      if (tables.isEmpty) {
        // Tablo yoksa oluştur
        await db.execute('''
          CREATE TABLE IF NOT EXISTS business_profile(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_name TEXT,
            phone TEXT,
            address TEXT,
            email TEXT,
            store_name TEXT,
            note TEXT,
            tax_number TEXT,
            currency TEXT,
            logo_path TEXT
          )
        ''');
      }
      
      // Önce mevcut kayıtları sayalım
      final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM business_profile');
      final count = countResult.first['count'] as int? ?? 0;
      
      if (count == 0) {
        // Hiç kayıt yoksa yeni ekle
        print('Hiç kayıt yok, yeni ekleniyor');
        result = await db.insert(
          'business_profile',
          profile,
          conflictAlgorithm: ConflictAlgorithm.replace
        );
      } else if (profile.containsKey('id')) {
        // Mevcut kaydı güncelle
        print('Mevcut kayıt güncelleniyor: ${profile['id']}');
        result = await db.rawUpdate(
          'UPDATE business_profile SET company_name = ?, phone = ?, address = ?, email = ?, store_name = ?, note = ?, tax_number = ?, currency = ?, logo_path = ? WHERE id = ?',
          [
            profile['company_name'],
            profile['phone'],
            profile['address'],
            profile['email'],
            profile['store_name'],
            profile['note'],
            profile['tax_number'],
            profile['currency'],
            profile['logo_path'],
            profile['id']
          ]
        );
        
        if (result == 0) {
          // Güncelleme başarısız olduysa (kayıt bulunamadı), yeni kayıt ekle
          profile.remove('id');
          print('Güncelleme başarısız oldu, yeni kayıt ekleniyor');
          result = await db.insert(
            'business_profile',
            profile,
            conflictAlgorithm: ConflictAlgorithm.replace
          );
        }
      } else {
        // Yeni kayıt ekle
        print('Yeni kayıt ekleniyor');
        result = await db.insert(
          'business_profile',
          profile,
          conflictAlgorithm: ConflictAlgorithm.replace
        );
      }
      
      print('İşlem sonucu: $result');
      return result;
    } catch (e) {
      print('İşletme bilgileri güncellenirken hata: $e');
      print('Hata stack trace: ${StackTrace.current}');
      throw Exception('İşletme bilgileri güncellenirken bir hata oluştu: $e');
    }
  }
  
  // İşletme bilgilerini getir
  Future<Map<String, dynamic>> getBusinessProfile() async {
    try {
      final db = await database;
      
      // business_profile tablosunun varlığını kontrol et
      final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table' AND name='business_profile'");
      if (tables.isEmpty) {
        // Tablo yoksa oluştur
        await db.execute('''
          CREATE TABLE IF NOT EXISTS business_profile(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            company_name TEXT,
            phone TEXT,
            address TEXT,
            email TEXT,
            store_name TEXT,
            note TEXT,
            tax_number TEXT,
            currency TEXT,
            logo_path TEXT
          )
        ''');
        
        // Varsayılan işletme bilgilerini ekle
        final id = await db.insert(
          'business_profile',
          {
            'company_name': 'Şirket Adı',
            'phone': '+90 555 123 4567',
            'address': 'İstanbul, Türkiye',
            'email': 'işletme@email.com',
            'store_name': 'Shaman Market',
            'note': 'Bizi tercih ettiğiniz için teşekkür ederiz!',
            'tax_number': '1234567890',
            'currency': '₺ TL',
            'logo_path': null
          }
        );
        
        // Yeni eklenen kaydı al
        final profiles = await db.query('business_profile', where: 'id = ?', whereArgs: [id]);
        if (profiles.isNotEmpty) {
          return profiles.first;
        }
      } else {
        // İşletme bilgilerini çek
        final List<Map<String, dynamic>> profiles = await db.query('business_profile');
        
        if (profiles.isNotEmpty) {
          return profiles.first;
        }
      }
      
      // Eğer hala kayıt yoksa varsayılan değerleri döndür
      return {
        'id': 1,
        'company_name': 'Şirket Adı',
        'phone': '+90 555 123 4567',
        'address': 'İstanbul, Türkiye',
        'email': 'işletme@email.com',
        'store_name': 'Shaman Market',
        'note': 'Bizi tercih ettiğiniz için teşekkür ederiz!',
        'tax_number': '1234567890',
        'currency': '₺ TL',
        'logo_path': null
      };
    } catch (e) {
      print('İşletme bilgileri alınırken hata: $e');
      print('Hata stack trace: ${StackTrace.current}');
      
      return {
        'id': 1,
        'company_name': 'Şirket Adı',
        'phone': '+90 555 123 4567',
        'address': 'İstanbul, Türkiye',
        'email': 'işletme@email.com',
        'store_name': 'Shaman Market',
        'note': 'Bizi tercih ettiğiniz için teşekkür ederiz!',
        'tax_number': '1234567890',
        'currency': '₺ TL',
        'logo_path': null
      };
    }
  }
  
  // İşletme profilini resetle (varsayılan değerlere döndür)
  Future<int> resetBusinessProfile() async {
    try {
      final db = await database;
      
      await db.delete('business_profile');
      
      return await db.insert(
        'business_profile',
        {
          'company_name': 'Şirket Adı',
          'phone': '+90 555 123 4567',
          'address': 'İstanbul, Türkiye',
          'email': 'işletme@email.com',
          'store_name': 'Shaman Market',
          'note': 'Bizi tercih ettiğiniz için teşekkür ederiz!',
          'tax_number': '1234567890',
          'currency': '₺ TL',
          'logo_path': null
        }
      );
    } catch (e) {
      throw Exception('İşletme bilgileri sıfırlanırken bir hata oluştu: $e');
    }
  }
} 
