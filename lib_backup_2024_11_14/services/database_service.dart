import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter/foundation.dart';

class DatabaseService {
  static final DatabaseService instance = DatabaseService._init();
  static Database? _database;

  DatabaseService._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('shaman.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 5,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute("PRAGMA foreign_keys = ON");
    
    await db.execute('''
      CREATE TABLE customers(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        displayName TEXT NOT NULL COLLATE UNICODE,
        firstName TEXT COLLATE UNICODE,
        lastName TEXT COLLATE UNICODE,
        phone TEXT,
        email TEXT,
        company TEXT COLLATE UNICODE,
        jobTitle TEXT,
        notes TEXT,
        syncId TEXT UNIQUE,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
    
    await db.execute('''
      CREATE TABLE devices(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        status TEXT,
        connection TEXT,
        model TEXT,
        version TEXT,
        protocol TEXT,
        encoding TEXT,
        paperWidth INTEGER,
        isInternal INTEGER,
        bluetoothAddress TEXT,
        isReceiptPrinter INTEGER DEFAULT 0,
        isLabelPrinter INTEGER DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Önce sütunların var olup olmadığını kontrol et
      final tableInfo = await db.rawQuery("PRAGMA table_info(customers)");
      final columnNames = tableInfo.map((row) => row['name'] as String).toList();
      
      bool hasCreatedAt = columnNames.contains('createdAt');
      bool hasUpdatedAt = columnNames.contains('updatedAt');
      
      if (!hasCreatedAt || !hasUpdatedAt) {
        await db.execute('ALTER TABLE customers RENAME TO customers_old');
        
        await db.execute('''
          CREATE TABLE customers(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            displayName TEXT NOT NULL COLLATE UNICODE,
            firstName TEXT COLLATE UNICODE,
            lastName TEXT COLLATE UNICODE,
            phone TEXT,
            email TEXT,
            company TEXT COLLATE UNICODE,
            jobTitle TEXT,
            notes TEXT,
            syncId TEXT UNIQUE,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
        
        await db.execute('''
          INSERT INTO customers 
          (id, displayName, firstName, lastName, phone, email, company, jobTitle, notes, syncId, createdAt, updatedAt)
          SELECT 
          id, displayName, firstName, lastName, phone, email, company, jobTitle, notes, syncId, 
          COALESCE(createdAt, datetime('now')) as createdAt,
          COALESCE(updatedAt, datetime('now')) as updatedAt
          FROM customers_old
        ''');
        
        await db.execute('DROP TABLE customers_old');
      }
    }
    
    if (oldVersion < 3) {
      // Devices tablosunun var olup olmadığını kontrol et
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='devices'"
      );
      
      if (tables.isEmpty) {
        await db.execute('''
          CREATE TABLE devices(
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            type TEXT NOT NULL,
            status TEXT,
            connection TEXT,
            model TEXT,
            version TEXT,
            protocol TEXT,
            encoding TEXT,
            paperWidth INTEGER,
            isInternal INTEGER,
            bluetoothAddress TEXT,
            createdAt TEXT NOT NULL,
            updatedAt TEXT NOT NULL
          )
        ''');
      }
    }
    
    if (oldVersion < 4) {
      // Bu sürümde printer_assignments tablosu eklenmiş ama artık kullanmayacağız
    }
    
    if (oldVersion < 5) {
      // Devices tablosuna yazıcı türü için alanlar ekle (sadece yoksa)
      final deviceTableInfo = await db.rawQuery("PRAGMA table_info(devices)");
      final deviceColumnNames = deviceTableInfo.map((row) => row['name'] as String).toList();
      
      if (!deviceColumnNames.contains('isReceiptPrinter')) {
        await db.execute('ALTER TABLE devices ADD COLUMN isReceiptPrinter INTEGER DEFAULT 0');
      }
      
      if (!deviceColumnNames.contains('isLabelPrinter')) {
        await db.execute('ALTER TABLE devices ADD COLUMN isLabelPrinter INTEGER DEFAULT 0');
      }
      
      // Mevcut printer_assignments tablosu varsa, verileri yeni yapıya taşı
      try {
        final printerAssignments = await db.query('printer_assignments');
        
        for (var assignment in printerAssignments) {
          final deviceId = assignment['deviceId'] as String;
          final type = assignment['type'] as String;
          
          if (type == 'receipt') {
            await db.update(
              'devices',
              {'isReceiptPrinter': 1},
              where: 'id = ?',
              whereArgs: [deviceId]
            );
          } else if (type == 'label') {
            await db.update(
              'devices',
              {'isLabelPrinter': 1},
              where: 'id = ?',
              whereArgs: [deviceId]
            );
          }
        }
        
        // printer_assignments tablosunu kaldır
        await db.execute('DROP TABLE IF EXISTS printer_assignments');
      } catch (e) {
        // Tablo yoksa hata verebilir, bu durumda işleme devam et
        debugPrint('Migration sırasında hata: $e');
      }
    }
  }

  // Müşteri/kişi işlemleri
  Future<int> insertContact(Contact contact) async {
    final db = await database;
    final phones = contact.phones;
    final emails = contact.emails;
    final organizations = contact.organizations;

    final firstName = contact.name.first;
    final lastName = contact.name.last;
    final displayName = [firstName, lastName]
        .where((part) => part.isNotEmpty)
        .join(' ');

    final data = {
      'displayName': displayName.isNotEmpty ? displayName : 'Unnamed Contact',
      'firstName': firstName,
      'lastName': lastName,
      'phone': phones.isNotEmpty ? phones.first.number : '',
      'email': emails.isNotEmpty ? emails.first.address : '',
      'company': organizations.isNotEmpty ? organizations.first.company : '',
      'jobTitle': organizations.isNotEmpty ? organizations.first.title : '',
      'notes': contact.notes.isNotEmpty ? contact.notes.first.note : '',
      'syncId': contact.id,
      'createdAt': DateTime.now().toIso8601String(),
      'updatedAt': DateTime.now().toIso8601String(),
    };

    return await db.insert(
      'customers',
      data,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<int> addCustomer(Map<String, dynamic> customer) async {
    final db = await database;
    
    // Tarih bilgilerini ekle
    final now = DateTime.now().toIso8601String();
    customer['createdAt'] = now;
    customer['updatedAt'] = now;
    
    return await db.insert(
      'customers',
      customer,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllCustomers() async {
    final db = await database;
    return await db.query(
      'customers',
      orderBy: 'displayName COLLATE UNICODE'
    );
  }

  Future<List<Map<String, dynamic>>> getCustomerByPhone(String phone) async {
    final db = await database;
    return await db.query(
      'customers',
      where: 'phone = ?',
      whereArgs: [phone]
    );
  }

  Future<int> updateCustomer(Map<String, dynamic> customer) async {
    final db = await database;
    
    // Güncelleme zamanını ekle
    customer['updatedAt'] = DateTime.now().toIso8601String();
    
    return await db.update(
      'customers',
      customer,
      where: 'id = ?',
      whereArgs: [customer['id']]
    );
  }

  Future<void> deleteAllCustomers() async {
    final db = await database;
    await db.delete('customers');
  }

  // Cihaz işlemleri
  Future<int> saveDevice(Map<String, dynamic> device) async {
    final db = await database;
    
    // Tarih bilgilerini ekle
    final now = DateTime.now().toIso8601String();
    
    // Bluetooth adresini doğru şekilde al
    String? bluetoothAddress;
    if (device['bluetoothDevice'] != null) {
      // BluetoothDevice nesnesinden adresi al
      bluetoothAddress = device['bluetoothDevice'].address;
      debugPrint('BluetoothDevice nesnesinden adres alındı: $bluetoothAddress');
    } else if (device['bluetoothAddress'] != null && device['bluetoothAddress'].toString().isNotEmpty) {
      // Doğrudan bluetoothAddress alanından al
      bluetoothAddress = device['bluetoothAddress'];
      debugPrint('bluetoothAddress alanından adres alındı: $bluetoothAddress');
    }
    
    // Veritabanı için cihaz bilgilerini hazırla
    final deviceData = {
      'id': device['id'],
      'name': device['name'],
      'type': device['type'],
      'status': device['status'],
      'connection': device['connection'],
      'model': device['model'] ?? '',
      'version': device['version'] ?? '',
      'protocol': device['protocol'] ?? '',
      'encoding': device['encoding'] ?? 'UTF-8',
      'paperWidth': device['paperWidth'] ?? 58,
      'isInternal': device['isInternal'] == true ? 1 : 0,
      'bluetoothAddress': bluetoothAddress ?? '',
      'isReceiptPrinter': device['isReceiptPrinter'] == true ? 1 : 0,
      'isLabelPrinter': device['isLabelPrinter'] == true ? 1 : 0,
      'createdAt': device['createdAt'] ?? now,
      'updatedAt': now,
    };
    
    debugPrint('Cihaz kaydediliyor: ${deviceData['name']}, bluetoothAddress: ${deviceData['bluetoothAddress']}');
    
    return await db.insert(
      'devices',
      deviceData,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Map<String, dynamic>>> getAllDevices() async {
    final db = await database;
    try {
      final devices = await db.query('devices');
      debugPrint('Veritabanından yüklenen cihaz sayısı: ${devices.length}');
      for (var device in devices) {
        debugPrint('DB Cihaz: ${device['name']}, ID: ${device['id']}, Type: ${device['type']}');
      }
      return devices;
    } catch (e) {
      debugPrint('Veritabanından cihazlar yüklenirken hata: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> getPrinters() async {
    final db = await database;
    return await db.query(
      'devices',
      where: 'type = ?',
      whereArgs: ['printer']
    );
  }

  Future<Map<String, dynamic>?> getDeviceById(String id) async {
    final db = await database;
    final results = await db.query(
      'devices',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1
    );
    
    return results.isNotEmpty ? results.first : null;
  }

  Future<int> updateDevice(String id, Map<String, dynamic> device) async {
    final db = await database;
    
    // Güncelleme zamanını ekle
    device['updatedAt'] = DateTime.now().toIso8601String();
    
    return await db.update(
      'devices',
      device,
      where: 'id = ?',
      whereArgs: [id]
    );
  }

  Future<int> deleteDevice(String id) async {
    final db = await database;
    try {
      debugPrint('Cihaz siliniyor: $id');
      final result = await db.delete(
        'devices',
        where: 'id = ?',
        whereArgs: [id]
      );
      debugPrint('Silinen cihaz sayısı: $result');
      return result;
    } catch (e) {
      debugPrint('Cihaz silinirken hata: $e');
      // Hata durumunda 0 dön
      return 0;
    }
  }

  /// Tüm cihazları siler
  Future<void> deleteAllDevices() async {
    final db = await database;
    try {
      debugPrint('Tüm cihazlar siliniyor...');
      final result = await db.delete('devices');
      debugPrint('Tüm cihazlar silindi. Etkilenen kayıt sayısı: $result');
    } catch (e) {
      debugPrint('Tüm cihazlar silinirken hata: $e');
      rethrow;
    }
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }
  
  // Yazıcı atama işlemleri
  
  /// Yazıcıyı fiş yazıcısı olarak atar
  Future<int> assignReceiptPrinter(String deviceId) async {
    final db = await database;
    
    // Önce tüm fiş yazıcısı atamalarını kaldır
    await db.update(
      'devices',
      {'isReceiptPrinter': 0},
      where: 'isReceiptPrinter = 1'
    );
    
    // Belirtilen cihazı fiş yazıcısı olarak ata
    return await db.update(
      'devices',
      {'isReceiptPrinter': 1, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [deviceId]
    );
  }
  
  /// Yazıcıyı etiket yazıcısı olarak atar
  Future<int> assignLabelPrinter(String deviceId) async {
    final db = await database;
    
    // Önce tüm etiket yazıcısı atamalarını kaldır
    await db.update(
      'devices',
      {'isLabelPrinter': 0},
      where: 'isLabelPrinter = 1'
    );
    
    // Belirtilen cihazı etiket yazıcısı olarak ata
    return await db.update(
      'devices',
      {'isLabelPrinter': 1, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [deviceId]
    );
  }
  
  /// Fiş yazıcısı olarak atanmış cihazı getirir
  Future<Map<String, dynamic>?> getReceiptPrinter() async {
    final db = await database;
    final results = await db.query(
      'devices',
      where: 'isReceiptPrinter = 1',
      limit: 1
    );
    
    return results.isNotEmpty ? results.first : null;
  }
    
  /// Etiket yazıcısı olarak atanmış cihazı getirir
  Future<Map<String, dynamic>?> getLabelPrinter() async {
    final db = await database;
    final results = await db.query(
      'devices',
      where: 'isLabelPrinter = 1',
      limit: 1
    );
    
    return results.isNotEmpty ? results.first : null;
  }
  
  /// Fiş yazıcısı atamasını kaldırır
  Future<int> removeReceiptPrinter() async {
    final db = await database;
    return await db.update(
        'devices',
      {'isReceiptPrinter': 0, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'isReceiptPrinter = 1'
    );
  }
  
  /// Etiket yazıcısı atamasını kaldırır
  Future<int> removeLabelPrinter() async {
    final db = await database;
    return await db.update(
      'devices',
      {'isLabelPrinter': 0, 'updatedAt': DateTime.now().toIso8601String()},
      where: 'isLabelPrinter = 1'
    );
  }
  
  /// Yeni cihaz ekler
  Future<int> insertDevice(Map<String, dynamic> device) async {
    final db = await database;
    return await db.insert('devices', device);
  }
} 
