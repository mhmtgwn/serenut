import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';

class CustomerService {
  static final CustomerService instance = CustomerService._init();
  static Database? _database;

  CustomerService._init();

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

    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'customers.db');

    // Veritabanı dosyasının var olup olmadığını kontrol et
    final dbExists = await databaseExists(path);

    // Veritabanı yoksa oluştur, varsa mevcut veritabanını kullan
    if (!dbExists) {
      // Veritabanı klasörünün var olduğundan emin ol
      try {
        await Directory(dirname(path)).create(recursive: true);
      } catch (e) {}
    } else {}

    return await openDatabase(
      path,
      version: 4,
      onCreate: _createDb,
      onUpgrade: _upgradeDb,
      onOpen: (db) {
        // Database opened successfully
      },
      readOnly: false,
      singleInstance: true,
    );
  }

  Future<void> _createDb(Database db, int version) async {
    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        displayName TEXT,
        phone TEXT,
        address TEXT,
        email TEXT,
        company TEXT,
        notes TEXT,
        credit_balance REAL DEFAULT 0.0,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  // Veritabanı yükseltme işlemi
  Future<void> _upgradeDb(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Versiyon 1'den 2'ye yükseltme: credit_balance sütunu ekle
      await db.execute(
          'ALTER TABLE customers ADD COLUMN credit_balance REAL DEFAULT 0.0');
    }

    if (oldVersion < 3) {
      // Versiyon 2'den 3'e yükseltme: created_at ve updated_at sütunları ekle (sadece yoksa)
      try {
        final tableInfo = await db.rawQuery("PRAGMA table_info(customers)");
        final columnNames =
            tableInfo.map((row) => row['name'] as String).toList();

        if (!columnNames.contains('created_at')) {
          await db.execute('ALTER TABLE customers ADD COLUMN created_at TEXT');
        }

        if (!columnNames.contains('updated_at')) {
          await db.execute('ALTER TABLE customers ADD COLUMN updated_at TEXT');
        }

        // Mevcut kayıtlar için varsayılan tarih değerleri ata
        final now = DateTime.now().toIso8601String();
        await db.execute(
            'UPDATE customers SET created_at = ?, updated_at = ? WHERE created_at IS NULL OR updated_at IS NULL',
            [now, now]);
      } catch (e) {
        print('Migration hatası: $e');
      }
    }

    if (oldVersion < 4) {
      // Versiyon 3'ten 4'e yükseltme: displayName ve company sütunları ekle (sadece yoksa)
      try {
        final tableInfo = await db.rawQuery("PRAGMA table_info(customers)");
        final columnNames =
            tableInfo.map((row) => row['name'] as String).toList();

        if (!columnNames.contains('displayName')) {
          await db.execute('ALTER TABLE customers ADD COLUMN displayName TEXT');
          // Mevcut kayıtlar için displayName'i name'den kopyala
          await db.execute(
              'UPDATE customers SET displayName = name WHERE displayName IS NULL');
        }

        if (!columnNames.contains('company')) {
          await db.execute('ALTER TABLE customers ADD COLUMN company TEXT');
        }
      } catch (e) {
        print('Migration hatası: $e');
      }
    }
  }

  Future<int> addCustomer(Map<String, dynamic> customer) async {
    try {
      final db = await database;

      // Tarih bilgilerini ekle
      final now = DateTime.now().toIso8601String();
      customer['created_at'] = now;
      customer['updated_at'] = now;

      // displayName yoksa name'den kopyala
      if (customer['displayName'] == null ||
          customer['displayName'].toString().isEmpty) {
        customer['displayName'] = customer['name'] ?? '';
      }

      // Null değerleri kontrol et
      customer.forEach((key, value) {
        if (value == null) {
          customer[key] = '';
        }
      });

      final id = await db.insert('customers', customer);
      return id;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    try {
      final db = await database;

      final customers = await db.query('customers', orderBy: 'name');

      return customers;
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> getCustomer(int id) async {
    final db = await database;

    final List<Map<String, dynamic>> results = await db.query(
      'customers',
      where: 'id = ?',
      whereArgs: [id],
    );

    if (results.isNotEmpty) {
      return results.first;
    }

    return null;
  }

  Future<int> updateCustomer(Map<String, dynamic> customer) async {
    try {
      final db = await database;

      // Güncelleme tarihini ekle
      customer['updated_at'] = DateTime.now().toIso8601String();

      // Null değerleri kontrol et
      customer.forEach((key, value) {
        if (value == null) {
          customer[key] = '';
        }
      });

      final rowsAffected = await db.update(
        'customers',
        customer,
        where: 'id = ?',
        whereArgs: [customer['id']],
      );

      return rowsAffected;
    } catch (e) {
      rethrow;
    }
  }

  Future<int> deleteCustomer(int id) async {
    try {
      final db = await database;

      final rowsAffected = await db.delete(
        'customers',
        where: 'id = ?',
        whereArgs: [id],
      );

      return rowsAffected;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> searchCustomers(String query) async {
    try {
      final db = await database;

      final customers = await db.query(
        'customers',
        where: 'name LIKE ? OR phone LIKE ?',
        whereArgs: ['%$query%', '%$query%'],
        orderBy: 'name',
      );

      return customers;
    } catch (e) {
      rethrow;
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }

  // Müşterinin toplam borcunu hesapla
  Future<double> getCustomerTotalDebt(int customerId) async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'orders.db');

      // Sipariş veritabanını aç
      final orderDb = await openDatabase(path, readOnly: true);

      // Müşterinin tüm siparişlerini al
      final List<Map<String, dynamic>> orders = await orderDb.query(
        'orders',
        where: 'customerId = ?',
        whereArgs: [customerId],
      );

      double totalDebt = 0.0;

      // Her sipariş için toplam tutarı ve ödenen tutarı hesapla
      for (var order in orders) {
        final totalAmount = order['totalAmount'] as double? ?? 0.0;
        final paidAmount = order['paidAmount'] as double? ?? 0.0;

        // Kalan borcu toplam borca ekle
        totalDebt += (totalAmount - paidAmount);
      }

      // Müşterinin alacak bakiyesini kontrol et
      final customerDb = await database;
      final List<Map<String, dynamic>> customerData = await customerDb.query(
        'customers',
        columns: ['credit_balance'],
        where: 'id = ?',
        whereArgs: [customerId],
      );

      if (customerData.isNotEmpty &&
          customerData.first['credit_balance'] != null) {
        final creditBalance =
            customerData.first['credit_balance'] as double? ?? 0.0;
        totalDebt -= creditBalance; // Alacak bakiyesini borçtan düş
      }

      await orderDb.close();
      return totalDebt;
    } catch (e) {
      return 0.0;
    }
  }

  // Müşterinin genel borcundan düş
  Future<bool> reduceCustomerDebt(int customerId, double amount) async {
    try {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'orders.db');

      // Sipariş veritabanını aç
      final orderDb = await openDatabase(path);

      // Müşterinin ödenmemiş siparişlerini al (ödenmemiş veya kısmi ödemeli)
      final List<Map<String, dynamic>> orders = await orderDb.query(
        'orders',
        where: 'customerId = ? AND paymentStatus != ?',
        whereArgs: [customerId, 'Ödendi'],
        orderBy: 'orderDate ASC', // En eski siparişten başla
      );

      if (orders.isEmpty) {
        // Müşterinin alacak bakiyesini güncelle
        final customerDb = await database;

        // Önce mevcut alacak bakiyesini al
        final List<Map<String, dynamic>> customerData = await customerDb.query(
          'customers',
          columns: ['credit_balance'],
          where: 'id = ?',
          whereArgs: [customerId],
        );

        double currentCreditBalance = 0.0;
        if (customerData.isNotEmpty &&
            customerData.first['credit_balance'] != null) {
          currentCreditBalance =
              customerData.first['credit_balance'] as double? ?? 0.0;
        }

        // Alacak bakiyesini güncelle
        final newCreditBalance = currentCreditBalance + amount;

        final updateResult = await customerDb.update(
          'customers',
          {'credit_balance': newCreditBalance},
          where: 'id = ?',
          whereArgs: [customerId],
        );

        await orderDb.close();
        return updateResult > 0;
      }

      double remainingAmount = amount;

      // Her sipariş için ödeme yap
      for (var order in orders) {
        if (remainingAmount <= 0) break;

        final orderId = order['id'] as int;
        final totalAmount = order['totalAmount'] as double? ?? 0.0;
        final currentPaidAmount = order['paidAmount'] as double? ?? 0.0;
        final orderDebt = totalAmount - currentPaidAmount;

        if (orderDebt <= 0) continue; // Bu sipariş zaten ödenmiş

        // Bu siparişe yapılacak ödeme miktarını hesapla
        double paymentForThisOrder =
            orderDebt <= remainingAmount ? orderDebt : remainingAmount;

        // Yeni ödenen tutarı hesapla
        final newPaidAmount = currentPaidAmount + paymentForThisOrder;

        // Ödeme durumunu belirle
        String paymentStatus = 'Kısmi Ödeme';
        if (newPaidAmount >= totalAmount) {
          paymentStatus = 'Ödendi';
        }

        // Siparişi güncelle
        await orderDb.update(
          'orders',
          {
            'paidAmount': newPaidAmount,
            'paymentStatus': paymentStatus,
            'updatedAt': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [orderId],
        );

        // Kalan ödeme miktarını güncelle
        remainingAmount -= paymentForThisOrder;
      }

      // Eğer hala kalan ödeme varsa, müşterinin alacak bakiyesine ekle
      if (remainingAmount > 0) {
        final customerDb = await database;

        // Önce mevcut alacak bakiyesini al
        final List<Map<String, dynamic>> customerData = await customerDb.query(
          'customers',
          columns: ['credit_balance'],
          where: 'id = ?',
          whereArgs: [customerId],
        );

        double currentCreditBalance = 0.0;
        if (customerData.isNotEmpty &&
            customerData.first['credit_balance'] != null) {
          currentCreditBalance =
              customerData.first['credit_balance'] as double? ?? 0.0;
        }

        // Alacak bakiyesini güncelle
        final newCreditBalance = currentCreditBalance + remainingAmount;

        await customerDb.update(
          'customers',
          {'credit_balance': newCreditBalance},
          where: 'id = ?',
          whereArgs: [customerId],
        );
      }

      await orderDb.close();
      return true;
    } catch (e) {
      return false;
    }
  }

  // Müşteri telefon numarası kontrolü için yardımcı metot
  Future<bool> validateCustomerPhone(int customerId) async {
    final customer = await getCustomer(customerId);

    if (customer == null) {
      return false;
    }

    final phone = customer['phone'];
    if (phone == null || phone.toString().trim().isEmpty) {
      return false;
    }

    return true;
  }

  // Tüm müşterilerin telefon numaralarını kontrol et
  Future<List<Map<String, dynamic>>> checkAllCustomerPhones() async {
    final customers = await getAllCustomers();
    final List<Map<String, dynamic>> results = [];

    for (var customer in customers) {
      final id = customer['id'];
      final name = customer['displayName'] ?? 'İsimsiz';
      final phone = customer['phone'];

      results.add({
        'id': id,
        'name': name,
        'phone': phone,
        'isValid': phone != null && phone.toString().trim().isNotEmpty,
      });
    }

    // Kullanılmayan for döngüsünü kaldırıyorum

    return results;
  }
}
