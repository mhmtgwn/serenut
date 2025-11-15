import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'customer_service.dart';
import 'package:flutter/foundation.dart';

class OrderService {
  static final OrderService instance = OrderService._init();
  static Database? _database;
  
  // Bekleyen ödemeleri tutacak map
  final Map<int, List<Map<String, dynamic>>> _pendingPayments = {};

  OrderService._init();

  Future<Database> get database async {
    if (_database != null) {
      // Veritabanının açık olup olmadığını kontrol et
      try {
        // Test sorgusu çalıştır
        await _database!.rawQuery('SELECT 1');
        return _database!;
      } catch (e) {
        // Bağlantı kapalıysa _database'i null yap ki yeniden açılsın
        _database = null;
      }
    }
    
    _database = await _initDB('orders.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, filePath);
      
      
      // Veritabanı dosyasının var olup olmadığını kontrol et
      final dbExists = await databaseExists(path);
      
      // Veritabanı yoksa oluştur, varsa mevcut veritabanını kullan
      if (!dbExists) {
        // Veritabanı klasörünün var olduğundan emin ol
        try {
          await Directory(dirname(path)).create(recursive: true);
        } catch (e) {
        }
      } else {
      }

      return await openDatabase(
        path,
        version: 3,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
        onOpen: (db) {
        },
        readOnly: false,
        singleInstance: true,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _createDB(Database db, int version) async {
    // Siparişler tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customerId INTEGER NOT NULL,
        customerName TEXT NOT NULL,
        customerPhone TEXT,
        customerAddress TEXT,
        orderDate TEXT NOT NULL,
        totalAmount REAL NOT NULL,
        paidAmount REAL DEFAULT 0,
        remainingAmount REAL DEFAULT 0,
        orderStatus TEXT NOT NULL,
        paymentStatus TEXT NOT NULL,
        paymentMethod TEXT NOT NULL,
        notes TEXT,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    
    // Sipariş detayları tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_items(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderId INTEGER NOT NULL,
        productId INTEGER NOT NULL,
        productName TEXT NOT NULL,
        quantity REAL NOT NULL,
        unitPrice REAL NOT NULL,
        subtotal REAL NOT NULL,
        FOREIGN KEY (orderId) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');
    
    // Ödeme geçmişi tablosu
    await db.execute('''
      CREATE TABLE IF NOT EXISTS payment_history(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        orderId INTEGER NOT NULL,
        amount REAL NOT NULL,
        method TEXT NOT NULL,
        paymentDate TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        FOREIGN KEY (orderId) REFERENCES orders (id) ON DELETE CASCADE
      )
    ''');
    
  }

  Future<int> addOrder(Map<String, dynamic> order, List<Map<String, dynamic>> orderItems) async {
    try {
      final db = await database;
      
      // Tarih bilgilerini ekle
      final now = DateTime.now().toIso8601String();
      order['createdAt'] = now;
      order['updatedAt'] = now;
      
      // Müşteri telefon ve adres bilgilerini ekle (eğer varsa)
      if (order['customerPhone'] == null && order['customerId'] != null) {
        try {
          final dbPath = await getDatabasesPath();
          final path = join(dbPath, 'customers.db');
          final customerDb = await openDatabase(path, readOnly: true);
          
          final List<Map<String, dynamic>> customers = await customerDb.query(
            'customers',
            where: 'id = ?',
            whereArgs: [order['customerId']],
          );
          
          if (customers.isNotEmpty) {
            order['customerPhone'] = customers.first['phone'];
            order['customerAddress'] = customers.first['address'];
          }
          
          await customerDb.close();
        } catch (e) {
        }
      }
      
      
      // Siparişi ekle
      final orderId = await db.insert('orders', order);
      
      // Sipariş detaylarını ekle
      for (var item in orderItems) {
        item['orderId'] = orderId;
        await db.insert('order_items', item);
      }
      
      
      return orderId;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAllOrders() async {
    try {
      final db = await database;
      
      // Siparişleri al
      final orders = await db.query('orders', orderBy: 'orderDate DESC');
      
      return orders;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getOrder(int id) async {
    final db = await database;
    
    
    try {
      // Siparişi sorgula
      final List<Map<String, dynamic>> orders = await db.query(
        'orders',
        where: 'id = ?',
        whereArgs: [id],
      );
      
      if (orders.isEmpty) {
        return null;
      }
      
      final order = orders.first;
      
      // Sipariş ürünlerini sorgula
      final List<Map<String, dynamic>> items = await db.query(
        'order_items',
        where: 'orderId = ?',
        whereArgs: [id],
      );
      
      // Sipariş ve ürünleri birleştir
      final result = {
        ...order,
        'items': items,
      };
      
      
      return result;
    } catch (e) {
      return null;
    }
  }

  Future<void> updateOrder(Map<String, dynamic> order, List<Map<String, dynamic>> orderItems) async {
    try {
      final db = await database;
      
      // Müşteri telefon ve adres bilgilerini ekle (eğer varsa)
      if (order['customerPhone'] == null && order['customerId'] != null) {
        try {
          final dbPath = await getDatabasesPath();
          final path = join(dbPath, 'customers.db');
          final customerDb = await openDatabase(path, readOnly: true);
          
          final List<Map<String, dynamic>> customers = await customerDb.query(
            'customers',
            where: 'id = ?',
            whereArgs: [order['customerId']],
          );
          
          if (customers.isNotEmpty) {
            order['customerPhone'] = customers.first['phone'];
            order['customerAddress'] = customers.first['address'];
          }
          
          await customerDb.close();
        } catch (e) {
        }
      }
      
      // Veritabanı işlemlerini bir transaction içinde gerçekleştir
      await db.transaction((txn) async {
        
        // Sipariş tablosunu güncelle
        await txn.update(
          'orders',
          {
            'customerId': order['customerId'],
            'customerName': order['customerName'],
            'customerPhone': order['customerPhone'], // Telefon bilgisini ekle
            'customerAddress': order['customerAddress'], // Adres bilgisini ekle
            'orderDate': order['orderDate'],
            'orderStatus': order['orderStatus'],
            'paymentStatus': order['paymentStatus'],
            'totalAmount': order['totalAmount'],
            'paidAmount': order['paidAmount'] ?? 0, // Ödenen tutarı ekle
            'notes': order['notes'],
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [order['id']],
        );
        
        
        // Mevcut sipariş ürünlerini sil
        await txn.delete(
          'order_items',
          where: 'orderId = ?',
          whereArgs: [order['id']],
        );
        
        
        // Yeni sipariş ürünlerini ekle
        for (var item in orderItems) {
          await txn.insert(
            'order_items',
            {
              'orderId': order['id'],
              'productId': item['productId'],
              'productName': item['productName'],
              'quantity': item['quantity'],
              'unitPrice': item['unitPrice'],
              'subtotal': item['subtotal'],
            },
          );
        }
        
      });
    } catch (e) {
      rethrow;
    }
  }

  // Sadece sipariş durumunu güncelleyen metod
  Future<void> updateOrderStatus(int orderId, String newStatus) async {
    try {
      final db = await database;
      
      
      // Sipariş tablosunu güncelle
      final rowsAffected = await db.update(
        'orders',
        {
          'orderStatus': newStatus,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
      
      if (rowsAffected > 0) {
      } else {
        throw Exception('Sipariş bulunamadı');
      }
    } catch (e) {
      rethrow;
    }
  }

  Future<int> deleteOrder(int id) async {
    try {
      final db = await database;
      
      // Önce siparişi ve finansal bilgilerini al
      final order = await getOrder(id);
      if (order == null) {
        throw Exception('Sipariş bulunamadı');
      }
      
      // Sipariş için yapılan ödemeleri al
      final payments = await getPaymentHistory(id);
      final double paidAmount = order['paidAmount'] ?? 0.0;
      final int? customerId = order['customerId'] as int?;
      
      // Eğer müşteri varsa ve ödemeler yapılmışsa müşteri bakiyesini güncelle
      if (customerId != null && customerId > 0 && paidAmount > 0) {
        try {
          // Müşterinin alacak bakiyesini güncelle (ödenen tutarı geri ekle, çünkü sipariş siliniyor)
          final customerDb = await openDatabase(join(await getDatabasesPath(), 'customers.db'));
          
          // Önce mevcut alacak bakiyesini al
          final List<Map<String, dynamic>> customerData = await customerDb.query(
            'customers',
            columns: ['credit_balance'],
            where: 'id = ?',
            whereArgs: [customerId],
          );
          
          double currentCreditBalance = 0.0;
          if (customerData.isNotEmpty && customerData.first['credit_balance'] != null) {
            currentCreditBalance = customerData.first['credit_balance'] as double? ?? 0.0;
          }
          
          // Alacak bakiyesini güncelle (ödenen tutarı düş)
          final newCreditBalance = currentCreditBalance - paidAmount;
          
          await customerDb.update(
            'customers',
            {'credit_balance': newCreditBalance > 0 ? newCreditBalance : 0},
            where: 'id = ?',
            whereArgs: [customerId],
          );
          
          await customerDb.close();
        } catch (e) {
          debugPrint('Müşteri bakiyesi güncellenirken hata: $e');
          // Hata olsa bile işleme devam et
        }
      }
      
      // Ödeme geçmişini sil
      await db.delete(
        'payment_history',
        where: 'orderId = ?',
        whereArgs: [id],
      );
      
      // Sipariş detaylarını sil
      await db.delete(
        'order_items',
        where: 'orderId = ?',
        whereArgs: [id],
      );
      
      // Siparişi sil
      final rowsAffected = await db.delete(
        'orders',
        where: 'id = ?',
        whereArgs: [id],
      );
      
      return rowsAffected;
    } catch (e) {
      debugPrint('Sipariş silinirken hata: $e');
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> searchOrders(String query) async {
    try {
      final db = await database;
      
      // Siparişleri ara
      final orders = await db.query(
        'orders',
        where: 'customerName LIKE ?',
        whereArgs: ['%$query%'],
        orderBy: 'orderDate DESC',
      );
      
      return orders;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getOrdersByStatus(String status) async {
    try {
      final db = await database;
      
      // Duruma göre siparişleri al
      final orders = await db.query(
        'orders',
        where: 'orderStatus = ?',
        whereArgs: [status],
        orderBy: 'orderDate DESC',
      );
      
      return orders;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getOrderItems(int orderId) async {
    try {
      final db = await database;
      
      // Sipariş detaylarını al
      final List<Map<String, dynamic>> items = await db.query(
        'order_items',
        where: 'orderId = ?',
        whereArgs: [orderId],
      );
      
      return items;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }

  // Siparişe ödeme ekle
  Future<bool> addPaymentToOrder(int orderId, double paymentAmount, String paymentMethod) async {
    try {
      final db = await database;
      
      // Siparişi al
      final order = await getOrder(orderId);
      if (order == null) {
        return false;
      }
      
      
      final customerId = order['customerId'] as int?;
      if (customerId == null) {
        return false;
      }
      
      final totalAmount = order['totalAmount'] as double? ?? 0.0;
      final currentPaidAmount = order['paidAmount'] as double? ?? 0.0;
      
      // Yeni ödenen tutarı hesapla
      final newPaidAmount = currentPaidAmount + paymentAmount;
      
      // Ödeme durumunu belirle
      String paymentStatus = 'Kısmi Ödeme';
      if (newPaidAmount >= totalAmount) {
        paymentStatus = 'Ödendi';
      }
      
      
      // Ödeme geçmişine ekle
      final now = DateTime.now().toIso8601String();
      await db.insert('payment_history', {
        'orderId': orderId,
        'amount': paymentAmount,
        'method': paymentMethod,
        'paymentDate': now,
        'createdAt': now,
      });
      
      // Siparişi güncelle
      await db.update(
        'orders',
        {
          'paidAmount': newPaidAmount,
          'remainingAmount': totalAmount - newPaidAmount, // Kalan tutarı hesapla ve güncelle
          'paymentStatus': paymentStatus,
          'paymentMethod': paymentMethod,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [orderId],
      );
      
      
      // Güncellenmiş siparişi al
      
      
      // Fazla ödeme durumunu kontrol et
      if (newPaidAmount > totalAmount) {
        final excessPayment = newPaidAmount - totalAmount;
        
        // Müşterinin diğer borçlarından düş
        final bool debtReduced = await CustomerService.instance.reduceCustomerDebt(customerId, excessPayment);
        
        if (debtReduced) {
          
          // Fazla ödemeyi bu siparişten çıkar (toplam tutara eşitle)
          
          
          // Son durumu kontrol et
        } else {
        }
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }

  // Sipariş-müşteri ilişkisini kontrol et
  Future<List<Map<String, dynamic>>> checkOrderCustomerRelations() async {
    final List<Map<String, dynamic>> results = [];
    
    try {
      // Tüm siparişleri al
      final orders = await getAllOrders();
      
      for (var order in orders) {
        final orderId = order['id'];
        final customerId = order['customerId'];
        final customerName = order['customerName'];
        final customerPhone = order['customerPhone'];
        
        // Müşteri bilgilerini kontrol et
        Map<String, dynamic>? customer;
        if (customerId != null) {
          customer = await CustomerService.instance.getCustomer(customerId);
        }
        
        results.add({
          'orderId': orderId,
          'customerId': customerId,
          'orderCustomerName': customerName,
          'orderCustomerPhone': customerPhone,
          'customerExists': customer != null,
          'customerName': customer?['displayName'],
          'customerPhone': customer?['phone'],
          'phoneMatch': customerPhone == customer?['phone'],
        });
      }
      
      // ignore: unused_local_variable
      for (var result in results.where((r) => r['customerExists'] == true && r['phoneMatch'] == false)) {
      }
      
      // ignore: unused_local_variable
      for (var result in results.where((r) => r['customerExists'] == false)) {
      }
      
      return results;
    } catch (e) {
      return [];
    }
  }

  // Sipariş oluşturma işlemini iyileştir
  Future<int> addOrderWithValidation(Map<String, dynamic> order, List<Map<String, dynamic>> items) async {
    final db = await database;
    
    try {
      
      // Müşteri bilgilerini kontrol et
      final customerId = order['customerId'];
      if (customerId != null) {
        final customer = await CustomerService.instance.getCustomer(customerId);
        
        if (customer != null) {
          // Müşteri telefon numarasını kontrol et ve güncelle
          if (customer['phone'] != null && customer['phone'].toString().trim().isNotEmpty) {
            order['customerPhone'] = customer['phone'];
          } else {
          }
          
          // Müşteri adresini kontrol et ve güncelle
          if (customer['address'] != null && customer['address'].toString().trim().isNotEmpty) {
            order['customerAddress'] = customer['address'];
          }
        } else {
        }
      }
      
      // Sipariş verilerini hazırla
      final orderData = {
        ...order,
        'createdAt': DateTime.now().toIso8601String(),
        'updatedAt': DateTime.now().toIso8601String(),
      };
      
      
      // Siparişi ekle
      final orderId = await db.insert('orders', orderData);
      
      // Sipariş ürünlerini ekle
      for (var item in items) {
        item['orderId'] = orderId;
        await db.insert('order_items', item);
      }
      
      // Satış durumunda payment_history tablosuna da kayıt ekle
      if (order['orderStatus'] == 'Satış' && order['totalAmount'] > 0) {
        final now = DateTime.now().toIso8601String();
        await db.insert('payment_history', {
          'orderId': orderId,
          'amount': order['totalAmount'],
          'method': order['paymentMethod'] ?? 'Nakit',
          'paymentDate': now,
          'createdAt': now,
        });
      }
      
      return orderId;
    } catch (e) {
      rethrow;
    }
  }

  // Veritabanı şemasını güncelleme metodu
  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    
    if (oldVersion < 2) {
      // Versiyon 1'den 2'ye geçerken ödeme geçmişi tablosunu ekle
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS payment_history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            orderId INTEGER NOT NULL,
            amount REAL NOT NULL,
            method TEXT NOT NULL,
            paymentDate TEXT NOT NULL,
            createdAt TEXT NOT NULL,
            FOREIGN KEY (orderId) REFERENCES orders (id) ON DELETE CASCADE
          )
        ''');
        
        // Müşteri telefon ve adres sütunlarını ekle
        await db.execute('ALTER TABLE orders ADD COLUMN customerPhone TEXT;');
        
        await db.execute('ALTER TABLE orders ADD COLUMN customerAddress TEXT;');
      } catch (e) {
        // Hata olsa bile devam et
      }
    }
    
    if (oldVersion < 3) {
      // Versiyon 2'den 3'e geçerken remainingAmount sütununu ekle
      try {
        await db.execute('ALTER TABLE orders ADD COLUMN remainingAmount REAL DEFAULT 0;');
      } catch (e) {
        // Hata olsa bile devam et
      }
    }
  }

  // Ödeme geçmişini getir
  Future<List<Map<String, dynamic>>> getPaymentHistory(int orderId) async {
    try {
      final db = await database;
      
      // Ödeme geçmişini sorgula
      final List<Map<String, dynamic>> payments = await db.query(
        'payment_history',
        where: 'orderId = ?',
        whereArgs: [orderId],
        orderBy: 'paymentDate DESC',
      );
      
      return payments;
    } catch (e) {
      return [];
    }
  }

  // Bekleyen ödeme ekle
  void addPendingPayment(int orderId, double amount, String method) {
    if (!_pendingPayments.containsKey(orderId)) {
      _pendingPayments[orderId] = [];
    }
    
    _pendingPayments[orderId]!.add({
      'amount': amount,
      'method': method,
      'date': DateTime.now().toIso8601String(),
    });
    
  }
  
  // Bekleyen ödemeleri getir
  List<Map<String, dynamic>> getPendingPayments(int orderId) {
    return _pendingPayments[orderId] ?? [];
  }
  
  // Bekleyen ödemelerin toplam tutarını hesapla
  double getPendingPaymentsTotal(int orderId) {
    final payments = _pendingPayments[orderId] ?? [];
    return payments.fold(0.0, (sum, payment) => sum + (payment['amount'] as double));
  }
  
  // Bekleyen ödemeleri temizle
  void clearPendingPayments(int orderId) {
    _pendingPayments.remove(orderId);
  }
  
  // Bekleyen ödemeleri onayla ve veritabanına kaydet
  Future<bool> confirmPendingPayments(int orderId) async {
    final payments = _pendingPayments[orderId] ?? [];
    if (payments.isEmpty) {
      return true;
    }
    
    
    bool allSuccess = true;
    for (var i = 0; i < payments.length; i++) {
      final payment = payments[i];
      
      final success = await addPaymentToOrder(
        orderId, 
        payment['amount'], 
        payment['method']
      );
      
      if (!success) {
        allSuccess = false;
        break;
      }
      
    }
    
    if (allSuccess) {
      // Başarılı olduysa bekleyen ödemeleri temizle
      clearPendingPayments(orderId);
    }
    
    return allSuccess;
  }
  
  // Ödeme kaydını sil
  Future<bool> deletePayment(int paymentId) async {
    try {
      final db = await database;
      
      // Önce ödeme kaydını al
      final List<Map<String, dynamic>> payments = await db.query(
        'payment_history',
        where: 'id = ?',
        whereArgs: [paymentId],
      );
      
      if (payments.isEmpty) {
        return false;
      }
      
      final payment = payments.first;
      final int orderId = payment['orderId'];
      final double paymentAmount = payment['amount'];
      
      
      // Siparişi al
      final order = await getOrder(orderId);
      if (order == null) {
        return false;
      }
      
      final double totalAmount = order['totalAmount'] ?? 0.0;
      final double currentPaidAmount = order['paidAmount'] ?? 0.0;
      
      // Yeni ödenen tutarı hesapla
      final double newPaidAmount = currentPaidAmount - paymentAmount;
      
      // Ödeme durumunu belirle
      if (newPaidAmount > 0) {
      }
      if (newPaidAmount >= totalAmount) {
      }
      
      
      // Ödeme kaydını sil
      final deleteResult = await db.delete(
        'payment_history',
        where: 'id = ?',
        whereArgs: [paymentId],
      );
      
      if (deleteResult == 0) {
        return false;
      }
      
      
      // Siparişi güncelle
      
      
      // Güncellenmiş siparişi al
      
      return true;
    } catch (e) {
      return false;
    }
  }
} 
