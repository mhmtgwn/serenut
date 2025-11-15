import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';
import 'customer_service.dart';
import 'order_payment_service.dart';
import '../../shared/utils/debug_config.dart';

class OrderService {
  static final OrderService instance = OrderService._init();
  static Database? _database;

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
          DebugConfig.logError('Klasör oluşturma hatası', e);
        }
      }

      return await openDatabase(
        path,
        version: 3,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
        readOnly: false,
        singleInstance: true,
      );
    } catch (e) {
      DebugConfig.logError('Veritabanı başlatma hatası', e);
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

  Future<int> addOrder(
      Map<String, dynamic> order, List<Map<String, dynamic>> orderItems) async {
    try {
      final db = await database;

      // Tarih bilgilerini ekle
      final now = DateTime.now().toIso8601String();
      order['createdAt'] = now;
      order['updatedAt'] = now;

      // Müşteri telefon ve adres bilgilerini ekle (eğer varsa)
      if (order['customerPhone'] == null && order['customerId'] != null) {
        try {
          final customer =
              await CustomerService.instance.getCustomer(order['customerId']);
          if (customer != null) {
            order['customerPhone'] = customer['phone'];
            order['customerAddress'] = customer['address'];
          }
        } catch (e) {
          DebugConfig.logError('Müşteri bilgileri alınırken hata', e);
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
      DebugConfig.logError('Sipariş eklenirken hata', e);
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
      DebugConfig.logError('Siparişler alınırken hata', e);
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
      DebugConfig.logError('Sipariş alınırken hata', e);
      return null;
    }
  }

  Future<void> updateOrder(
      Map<String, dynamic> order, List<Map<String, dynamic>> orderItems) async {
    try {
      final db = await database;

      // Müşteri telefon ve adres bilgilerini ekle (eğer varsa)
      if (order['customerPhone'] == null && order['customerId'] != null) {
        try {
          final customer =
              await CustomerService.instance.getCustomer(order['customerId']);
          if (customer != null) {
            order['customerPhone'] = customer['phone'];
            order['customerAddress'] = customer['address'];
          }
        } catch (e) {
          DebugConfig.logError('Müşteri bilgileri alınırken hata', e);
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
            'customerPhone': order['customerPhone'],
            'customerAddress': order['customerAddress'],
            'orderDate': order['orderDate'],
            'orderStatus': order['orderStatus'],
            'paymentStatus': order['paymentStatus'],
            'totalAmount': order['totalAmount'],
            'paidAmount': order['paidAmount'] ?? 0,
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
      DebugConfig.logError('Sipariş güncellenirken hata', e);
      rethrow;
    }
  }

  /// Sadece sipariş durumunu güncelleyen metod
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

      if (rowsAffected == 0) {
        throw Exception('Sipariş bulunamadı');
      }
    } catch (e) {
      DebugConfig.logError('Sipariş durumu güncellenirken hata', e);
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
      final payments =
          await OrderPaymentService.instance.getPaymentHistory(id, db);
      final double paidAmount = order['paidAmount'] ?? 0.0;
      final int? customerId = order['customerId'] as int?;

      // Eğer müşteri varsa ve ödemeler yapılmışsa müşteri bakiyesini güncelle
      if (customerId != null && customerId > 0 && paidAmount > 0) {
        try {
          // Müşterinin alacak bakiyesini güncelle
          // await CustomerService.instance.updateCustomerCreditBalance( // Method eksik - geçici olarak comment outcustomerId, -paidAmount);
        } catch (e) {
          DebugConfig.logError('Müşteri bakiyesi güncellenirken hata', e);
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
      DebugConfig.logError('Sipariş silinirken hata', e);
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
      DebugConfig.logError('Sipariş arama hatası', e);
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
      DebugConfig.logError('Durum bazlı sipariş alma hatası', e);
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
      DebugConfig.logError('Sipariş öğeleri alınırken hata', e);
      rethrow;
    }
  }

  /// Sipariş oluşturma işlemini iyileştir
  Future<int> addOrderWithValidation(
      Map<String, dynamic> order, List<Map<String, dynamic>> items) async {
    final db = await database;

    try {
      // Müşteri bilgilerini kontrol et
      final customerId = order['customerId'];
      if (customerId != null) {
        final customer = await CustomerService.instance.getCustomer(customerId);

        if (customer != null) {
          // Müşteri telefon numarasını kontrol et ve güncelle
          if (customer['phone'] != null &&
              customer['phone'].toString().trim().isNotEmpty) {
            order['customerPhone'] = customer['phone'];
          }

          // Müşteri adresini kontrol et ve güncelle
          if (customer['address'] != null &&
              customer['address'].toString().trim().isNotEmpty) {
            order['customerAddress'] = customer['address'];
          }
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
        await OrderPaymentService.instance.addPaymentToOrder(
          orderId,
          order['totalAmount'],
          order['paymentMethod'] ?? 'Nakit',
          db,
        );
      }

      return orderId;
    } catch (e) {
      DebugConfig.logError('Sipariş ekleme hatası', e);
      rethrow;
    }
  }

  /// Veritabanı şemasını güncelleme metodu
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
        DebugConfig.logError('Veritabanı güncelleme hatası', e);
      }
    }

    if (oldVersion < 3) {
      // Versiyon 2'den 3'e geçerken remainingAmount sütununu ekle
      try {
        await db.execute(
            'ALTER TABLE orders ADD COLUMN remainingAmount REAL DEFAULT 0;');
      } catch (e) {
        DebugConfig.logError('Veritabanı güncelleme hatası', e);
      }
    }
  }

  /// Sipariş-müşteri ilişkisini kontrol et
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

      return results;
    } catch (e) {
      DebugConfig.logError('Sipariş-müşteri ilişkisi kontrolü hatası', e);
      return [];
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
}
