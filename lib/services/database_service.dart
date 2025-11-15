import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseService {
  static Database? _database;
  static const String _dbName = 'shaman_v2.db';
  static const int _version =
      3; // Payment transactions ve stock movements eklendi

  static Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  static Future<Database> _initDB() async {
    final path = join(await getDatabasesPath(), _dbName);
    return await openDatabase(
      path,
      version: _version,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  static Future<void> _onCreate(Database db, int version) async {
    // CUSTOMERS
    await db.execute('''
      CREATE TABLE customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        phone TEXT NOT NULL UNIQUE,
        address TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // PRODUCTS
    await db.execute('''
      CREATE TABLE products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        price REAL NOT NULL,
        stock INTEGER NOT NULL DEFAULT 0,
        category TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    // ORDERS
    await db.execute('''
      CREATE TABLE orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_number TEXT NOT NULL UNIQUE,
        customer_id INTEGER NOT NULL,
        customer_name TEXT NOT NULL,
        customer_phone TEXT NOT NULL,
        total REAL NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0,
        payment_status TEXT NOT NULL DEFAULT 'unpaid',
        status TEXT NOT NULL DEFAULT 'pending',
        payment_method TEXT NOT NULL,
        notes TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // ORDER_ITEMS
    await db.execute('''
      CREATE TABLE order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER NOT NULL,
        product_name TEXT NOT NULL,
        quantity INTEGER NOT NULL,
        price REAL NOT NULL,
        subtotal REAL NOT NULL
      )
    ''');

    // EXPENSES
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        amount REAL NOT NULL,
        category TEXT NOT NULL,
        note TEXT,
        date TEXT NOT NULL
      )
    ''');

    // SMS_LOG
    await db.execute('''
      CREATE TABLE sms_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        phone TEXT NOT NULL,
        message TEXT NOT NULL,
        status TEXT NOT NULL,
        order_id INTEGER,
        sent_at TEXT NOT NULL
      )
    ''');

    // PAYMENT_TRANSACTIONS
    await db.execute('''
      CREATE TABLE payment_transactions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER NOT NULL,
        order_id INTEGER,
        amount REAL NOT NULL,
        type TEXT NOT NULL,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (customer_id) REFERENCES customers(id),
        FOREIGN KEY (order_id) REFERENCES orders(id)
      )
    ''');

    // STOCK_MOVEMENTS
    await db.execute('''
      CREATE TABLE stock_movements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        product_id INTEGER NOT NULL,
        quantity INTEGER NOT NULL,
        type TEXT NOT NULL,
        reference_id INTEGER,
        note TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // CATEGORIES
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL UNIQUE,
        color TEXT,
        created_at TEXT NOT NULL
      )
    ''');

    // INDEXES
    await db.execute('CREATE INDEX idx_orders_status ON orders(status)');
    await db.execute('CREATE INDEX idx_orders_date ON orders(created_at)');
    await db.execute('CREATE INDEX idx_products_stock ON products(stock)');
    await db.execute(
        'CREATE INDEX idx_orders_payment_status ON orders(payment_status)');
    await db.execute(
        'CREATE INDEX idx_payment_transactions_customer ON payment_transactions(customer_id)');
    await db.execute(
        'CREATE INDEX idx_stock_movements_product ON stock_movements(product_id)');
  }

  static Future<void> _onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // Borç takibi için yeni sütunlar ekleniyor
      await db.execute(
          'ALTER TABLE orders ADD COLUMN paid_amount REAL NOT NULL DEFAULT 0');
      await db.execute(
          'ALTER TABLE orders ADD COLUMN payment_status TEXT NOT NULL DEFAULT "unpaid"');
      await db.execute(
          'CREATE INDEX idx_orders_payment_status ON orders(payment_status)');
    }

    if (oldVersion < 3) {
      // Payment transactions tablosu
      await db.execute('''
        CREATE TABLE payment_transactions (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          customer_id INTEGER NOT NULL,
          order_id INTEGER,
          amount REAL NOT NULL,
          type TEXT NOT NULL,
          note TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (customer_id) REFERENCES customers(id),
          FOREIGN KEY (order_id) REFERENCES orders(id)
        )
      ''');

      // Stock movements tablosu
      await db.execute('''
        CREATE TABLE stock_movements (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          product_id INTEGER NOT NULL,
          quantity INTEGER NOT NULL,
          type TEXT NOT NULL,
          reference_id INTEGER,
          note TEXT,
          created_at TEXT NOT NULL,
          FOREIGN KEY (product_id) REFERENCES products(id)
        )
      ''');

      // Categories tablosu
      await db.execute('''
        CREATE TABLE categories (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL UNIQUE,
          color TEXT,
          created_at TEXT NOT NULL
        )
      ''');

      await db.execute(
          'CREATE INDEX idx_payment_transactions_customer ON payment_transactions(customer_id)');
      await db.execute(
          'CREATE INDEX idx_stock_movements_product ON stock_movements(product_id)');
    }
  }
}
