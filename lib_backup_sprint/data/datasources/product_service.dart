import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'dart:io';

class ProductService {
  static final ProductService instance = ProductService._init();
  static Database? _database;

  ProductService._init();

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
    
    _database = await _initDB('products.db');
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
        
        // Veritabanı dosyasının izinlerini kontrol et
        try {
          final file = File(path);
          if (await file.exists()) {
          }
        } catch (e) {
        }
      }

      return await openDatabase(
        path,
        version: 3,
        onCreate: _createDB,
        onUpgrade: _upgradeDB,
        onOpen: (db) {
        },
        readOnly: false, // Yazma izni olduğundan emin ol
        singleInstance: true, // Tek bir bağlantı kullan
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode TEXT,
        name TEXT NOT NULL COLLATE UNICODE,
        price REAL NOT NULL,
        purchasePrice REAL DEFAULT 0,
        tax REAL DEFAULT 0,
        discount REAL DEFAULT 0,
        stock REAL NOT NULL,
        criticalStock REAL DEFAULT 0,
        unit TEXT NOT NULL,
        description TEXT,
        imagePath TEXT,
        category TEXT COLLATE UNICODE,
        brand TEXT COLLATE UNICODE,
        profitMargin REAL DEFAULT 0,
        finalPrice REAL DEFAULT 0,
        createdAt TEXT NOT NULL,
        updatedAt TEXT NOT NULL
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Yeni sütunları ekle
      await db.execute('ALTER TABLE products ADD COLUMN purchasePrice REAL DEFAULT 0');
      await db.execute('ALTER TABLE products ADD COLUMN discount REAL DEFAULT 0');
      await db.execute('ALTER TABLE products ADD COLUMN criticalStock REAL DEFAULT 0');
    }
    
    if (oldVersion < 3) {
      // Kar marjı ve son fiyat sütunlarını ekle
      await db.execute('ALTER TABLE products ADD COLUMN profitMargin REAL DEFAULT 0');
      await db.execute('ALTER TABLE products ADD COLUMN finalPrice REAL DEFAULT 0');
      
      // Not: Versiyon 3'te vergi hesaplama mantığı değiştirildi
      // Önceki: Vergi satış fiyatı üzerine ekleniyor
      // Yeni: Vergi satış fiyatının içinde (KDV dahil fiyat)
    }
  }

  Future<int> addProduct(Map<String, dynamic> product) async {
    try {
      final db = await database;
      
      // Tarih bilgilerini ekle
      final now = DateTime.now().toIso8601String();
      product['createdAt'] = now;
      product['updatedAt'] = now;
      
      
      // Null değerleri kontrol et
      product.forEach((key, value) {
        if (value == null && key != 'imagePath') {
          if (key == 'unit') {
            product[key] = 'adet';
          } else if (key == 'price' || key == 'stock' || 
                    key == 'purchasePrice' || key == 'tax' || 
                    key == 'discount' || key == 'criticalStock' ||
                    key == 'profitMargin' || key == 'finalPrice') {
            product[key] = 0.0;
          } else if (key != 'imagePath') {
            product[key] = '';
          }
        }
      });
      
      final id = await db.insert('products', product);
      return id;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> getAllProducts() async {
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount < maxRetries) {
      try {
        final db = await database;
        
        // Veritabanının açık olup olmadığını kontrol et
        try {
          // Test sorgusu çalıştır
          await db.rawQuery('SELECT 1');
        } catch (testError) {
          // Bağlantıyı yeniden kur
          await reconnectDatabase();
          retryCount++;
          continue;
        }
        
        final products = await db.query('products');
        return products;
      } catch (e) {
        
        // Son deneme başarısız olduysa
        if (retryCount == maxRetries - 1) {
          // Veritabanını sıfırlamayı dene
          try {
            await resetDatabase();
            return [];
          } catch (resetError) {
            return [];
          }
        }
        
        // Yeniden bağlanmayı dene
        await reconnectDatabase();
        retryCount++;
      }
    }
    
    // Tüm denemeler başarısız olduysa boş liste döndür
    return [];
  }

  Future<Map<String, dynamic>?> getProduct(int id) async {
    try {
      final db = await database;
      final List<Map<String, dynamic>> maps = await db.query(
        'products',
        where: 'id = ?',
        whereArgs: [id],
      );
      
      if (maps.isNotEmpty) {
        return maps.first;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<int> updateProduct(Map<String, dynamic> product) async {
    try {
      final db = await database;
      
      // Güncelleme tarihini ekle
      product['updatedAt'] = DateTime.now().toIso8601String();
      
      
      // Null değerleri kontrol et
      product.forEach((key, value) {
        if (value == null && key != 'imagePath') {
          if (key == 'unit') {
            product[key] = 'adet';
          } else if (key == 'price' || key == 'stock' || 
                    key == 'purchasePrice' || key == 'tax' || 
                    key == 'discount' || key == 'criticalStock' ||
                    key == 'profitMargin' || key == 'finalPrice') {
            product[key] = 0.0;
          } else if (key != 'imagePath') {
            product[key] = '';
          }
        }
      });
      
      final rowsAffected = await db.update(
        'products',
        product,
        where: 'id = ?',
        whereArgs: [product['id']],
      );
      
      return rowsAffected;
    } catch (e) {
      rethrow;
    }
  }

  Future<int> deleteProduct(int id) async {
    final db = await database;
    return await db.delete(
      'products',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, dynamic>>> searchProducts(String query) async {
    final db = await database;
    return await db.query(
      'products',
      where: 'name LIKE ? OR barcode LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
    );
  }

  Future<List<Map<String, dynamic>>> getLowStockProducts() async {
    final db = await database;
    return await db.rawQuery(
      'SELECT * FROM products WHERE stock <= criticalStock AND criticalStock > 0'
    );
  }

  Future<void> close() async {
    final db = await database;
    db.close();
  }

  Future<void> resetDatabase() async {
    try {
      // Mevcut veritabanını kapat
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      
      // Veritabanı dosyasının yolunu al
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'products.db');
      
      // Dosya varsa sil
      if (await databaseExists(path)) {
        await deleteDatabase(path);
        
        // Dosyanın silindiğinden emin ol
        if (await databaseExists(path)) {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        }
      }
      
      // Veritabanını yeniden oluştur
      _database = await _initDB('products.db');
    } catch (e) {
      rethrow;
    }
  }

  // Veritabanı bağlantısını yeniden oluştur
  Future<void> reconnectDatabase() async {
    try {
      // Mevcut veritabanını kapat
      if (_database != null) {
        await _database!.close();
        _database = null;
      }
      
      // Veritabanını yeniden aç
      _database = await _initDB('products.db');
    } catch (e) {
      rethrow;
    }
  }
} 
