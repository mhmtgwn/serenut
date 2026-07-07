// lib/infrastructure/database/database_provider.dart
// PHASE 0 Day 4 - Database Layer
// SQLite database initialization and management
// Generated: 21 Jun 2026 — Security Hardened: 24 Jun 2026

import 'dart:convert';
import 'dart:io' show Platform, File;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, kDebugMode;
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:serenutos/infrastructure/services/password_hash_service.dart';

import 'package:serenutos/infrastructure/database/sqlcipher_stub.dart'
    if (dart.library.io) 'package:serenutos/infrastructure/database/sqlcipher_native.dart' as sqlc;

/// ════════════════════════════════════════════════════════════
/// Database Manager
/// ════════════════════════════════════════════════════════════
/// 
/// Handles SQLite database initialization, schema creation,
/// and connection management.

class DatabaseManager {
  static bool isSqlCipherAvailableOnWindows() {
    if (kIsWeb) return true;
    return sqlc.isSqlCipherAvailableOnWindows();
  }

  static final _instance = DatabaseManager._();
  factory DatabaseManager() => _instance;
  DatabaseManager._() {
    if (!kIsWeb) {
      sqlc.initSqfliteFfiForTest();
      sqlc.initWindowsSqlCipherSync();
    }
  }

  static const String _databaseName = 'serenut_pos.db';
  static const int _databaseVersion = 15;

  static String? overrideDatabasePath;
  static bool isWriteLocked = false;

  Database? _database;
  Future<Database>? _databaseFuture;
  String? _encryptionKey;

  /// Exposes the derived database encryption key (for verification of backups/restores)
  String? get encryptionKey => _encryptionKey;

  /// Get database instance (lazy initialization)
  Future<Database> getDatabase() async {
    if (_database != null) {
      await _verifyAndRepairTriggers(_database!);
      return _database!;
    }
    _databaseFuture ??= _initializeDatabase();
    _database = await _databaseFuture;
    await _verifyAndRepairTriggers(_database!);
    return _database!;
  }

  /// Check if the database file is an unencrypted (plaintext) SQLite database
  Future<bool> _isPlaintextDatabase(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return false;
    }
    try {
      final bytes = await file.openRead(0, 16).first;
      final header = String.fromCharCodes(bytes);
      return header.startsWith('SQLite format 3');
    } catch (_) {
      return false;
    }
  }

  /// Migrate plaintext database to SQLCipher encrypted database
  Future<void> _migratePlaintextToSQLCipher(String databasePath, String encryptionKey) async {
    final tempPlaintextPath = '$databasePath.temp';
    final encryptedPath = '$databasePath.encrypted';
    final dbFile = File(databasePath);

    if (!await dbFile.exists()) {
      return; // No database to migrate
    }

    // Step 1: Create a backup of the plaintext database
    final backupFile = await dbFile.copy(tempPlaintextPath);

    try {
      // Step 2: Ensure any leftover encrypted temp file is deleted
      final encryptedFile = File(encryptedPath);
      if (await encryptedFile.exists()) {
        await encryptedFile.delete();
      }

      // Step 3: Open an empty encrypted database
      final Database encryptedDb = await _openDb(
        encryptedPath,
        password: encryptionKey,
        version: _databaseVersion,
        singleInstance: false,
      );

      // Step 4: Attach the plaintext database and export data
      await encryptedDb.rawQuery(
        "ATTACH DATABASE ? AS plaintext KEY ''",
        [tempPlaintextPath],
      );
      await encryptedDb.rawQuery("SELECT sqlcipher_export('main', 'plaintext')");
      await encryptedDb.rawQuery('DETACH DATABASE plaintext');
      await encryptedDb.close();

      // Step 5: Verify the encrypted database can be opened
      final Database verifyDb = await _openDb(
        encryptedPath,
        password: encryptionKey,
        readOnly: true,
        singleInstance: false,
      );
      final tables = await verifyDb.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table'",
      );
      // Verify basic table count or schema existence
      if (tables.isEmpty) {
        throw Exception('Verification failed: Migrated database contains no tables.');
      }
      await verifyDb.close();

      // Step 6: Clean up and replace the database file
      // Close any active write-locks or journals by deleting them physically
      final walFile = File('$databasePath-wal');
      if (await walFile.exists()) await walFile.delete();
      final shmFile = File('$databasePath-shm');
      if (await shmFile.exists()) await shmFile.delete();

      await dbFile.delete();
      await encryptedFile.copy(databasePath);

      // Clean up temporary files
      await encryptedFile.delete();
      await backupFile.delete();

    } catch (e) {
      // Step 7: Rollback on failure
      final encryptedFile = File(encryptedPath);
      if (await encryptedFile.exists()) {
        try {
          await encryptedFile.delete();
        } catch (_) {}
      }

      final tempBackupFile = File(tempPlaintextPath);
      if (await tempBackupFile.exists()) {
        try {
          // Re-copy the original plaintext backup to base path
          final targetDbFile = File(databasePath);
          if (await targetDbFile.exists()) {
            await targetDbFile.delete();
          }
          await tempBackupFile.copy(databasePath);
          await tempBackupFile.delete();
        } catch (_) {}
      }
      throw Exception('SQLCipher migration failed: $e. Rolled back to plaintext database.');
    }
  }

  /// Initialize database and create schema
  Future<Database> _initializeDatabase() async {
    final String path = overrideDatabasePath ??
        ((!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'))
            ? inMemoryDatabasePath
            : join(await getDatabasesPath(), _databaseName));

    final bool isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    final bool isDiskDb = path != inMemoryDatabasePath;

    // Enforce SQLCipher on Windows: fallback to read-only if missing, throw if database is new (bypass in debug mode)
    if (isDiskDb && !isTest && !kDebugMode && !kIsWeb && Platform.isWindows && !isSqlCipherAvailableOnWindows()) {
      isWriteLocked = true; // Lock all writes permanently
      final dbFile = File(path);
      if (await dbFile.exists()) {
        return await _openDb(
          path,
          readOnly: true,
          version: _databaseVersion,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
          onConfigure: (db) async {
            await db.execute('PRAGMA foreign_keys = ON');
          },
        );
      } else {
        throw StateError('Kritik Güvenlik Hatası: SQLCipher şifreleme motoru Windows üzerinde yüklü değil. Veritabanı oluşturulamıyor.');
      }
    }

    final bool isEncryptedDb = isDiskDb && !isTest && (Platform.isAndroid || Platform.isIOS || (Platform.isWindows && isSqlCipherAvailableOnWindows()));
    
    // Derive password if on disk and not in test, otherwise null
    String? encryptionKey;
    if (isEncryptedDb) {
      final prefs = await SharedPreferences.getInstance();
      String? recoveryKey = prefs.getString('database_recovery_key');
      if (recoveryKey == null || recoveryKey.isEmpty) {
        recoveryKey = 'serenut_default_recovery_key_v1';
        await prefs.setString('database_recovery_key', recoveryKey);
      }
      
      final staticSalt = Uint8List.fromList([
        0x53, 0x65, 0x72, 0x65, 0x6e, 0x75, 0x74, 0x50,
        0x4f, 0x53, 0x5f, 0x53, 0x65, 0x63, 0x75, 0x72
      ]);

      final derivedKeyBytes = PasswordHashService.deriveKey(
        password: recoveryKey,
        salt: staticSalt,
        iterations: 10000,
        keyLength: 32,
      );
      encryptionKey = base64.encode(derivedKeyBytes);
      _encryptionKey = encryptionKey;
    }

    // Step 1: Detect if migration is needed (only if database file exists and is plaintext)
    if (isEncryptedDb) {
      final dbFile = File(path);
      if (await dbFile.exists() && await _isPlaintextDatabase(path)) {
        // Perform safe dry-run migration with fallback rollback
        await _migratePlaintextToSQLCipher(path, encryptionKey!);
      }
    }

    String? backupPath;
    if (isDiskDb) {
      final dbFile = File(path);
      if (await dbFile.exists()) {
        int currentVersion = 0;
        try {
          // Open with key to verify version
          final tempDb = await _openDb(path, password: encryptionKey, readOnly: true, singleInstance: false);
          currentVersion = await tempDb.getVersion();
          await tempDb.close();
        } catch (_) {}

        if (currentVersion > 0 && currentVersion < _databaseVersion) {
          final dbDir = dirname(path);
          backupPath = join(dbDir, 'serenut_pos_upgrade_backup.db');
          final backupFile = File(backupPath);
          if (await backupFile.exists()) await backupFile.delete();
          await dbFile.copy(backupPath);

          final walFile = File('$path-wal');
          if (await walFile.exists()) {
            await walFile.copy('$backupPath-wal');
          }
          final shmFile = File('$path-shm');
          if (await shmFile.exists()) {
            await shmFile.copy('$backupPath-shm');
          }
        }
      }
    }

    try {
      final db = await _openDb(
        path,
        password: encryptionKey,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
          // WAL mode: use rawQuery to avoid 'execute not allowed in onConfigure'
          // on certain Android OEM builds (e.g. Sunmi V2s, EMUI)
          try {
            await db.rawQuery('PRAGMA journal_mode = WAL');
            await db.execute('PRAGMA synchronous = NORMAL');
          } catch (_) {
            // Device doesn't support WAL — fall back silently
          }
        },
      );
      // Ensure default walk-in customer exists to satisfy FOREIGN KEY constraint for anonymous sales
      try {
        await db.insert('customers', {
          'id': '',
          'name': 'Peşin Müşteri',
          'email': '',
          'phone': '',
          'balance': 0.0,
          'status': 'active',
          'created_at': DateTime.now().toIso8601String(),
          'updated_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {
        // Table might not exist yet in certain test configurations (e.g. backup/restore tests)
      }

      // Recreate views to make sure they are up-to-date with any schema changes/fixes
      try {
        await db.execute('DROP VIEW IF EXISTS v_financial_ledger');
        await db.execute('''
          CREATE VIEW v_financial_ledger AS
          SELECT 
            id,
            type,
            customer_id,
            amount,
            paid_amount,
            debt_amount,
            reference_id,
            created_at,
            CASE 
              WHEN type = 'sale' THEN amount
              WHEN type = 'cancellation' THEN -amount
              ELSE 0
            END AS debit,
            CASE 
              WHEN type = 'sale' THEN paid_amount
              WHEN type = 'payment' THEN amount
              WHEN type = 'collection' THEN amount
              WHEN type = 'refund' THEN amount
              WHEN type = 'cancellation' THEN -paid_amount
              ELSE 0
            END AS credit
          FROM financial_transactions
        ''');
      } catch (_) {
        // View might fail if table does not exist in initial configuration
      }

      return db;
    } catch (e) {
      // Self-healing: if database decryption fails (wrong key / corrupted DB on re-installation),
      // delete the database file and re-open it to start clean.
      final isDecryptionError = e.toString().contains('file is not a database') || 
                                e.toString().contains('code 26') || 
                                e.toString().contains('open_failed');
      if (isDiskDb && isDecryptionError) {
        try {
          await deleteDatabase(path);
          final walFile = File('$path-wal');
          if (await walFile.exists()) await walFile.delete();
          final shmFile = File('$path-shm');
          if (await shmFile.exists()) await shmFile.delete();
          
          return await _openDb(
            path,
            password: encryptionKey,
            version: _databaseVersion,
            onCreate: _onCreate,
            onUpgrade: _onUpgrade,
            onConfigure: (db) async {
              await db.execute('PRAGMA foreign_keys = ON');
              try {
                await db.rawQuery('PRAGMA journal_mode = WAL');
                await db.execute('PRAGMA synchronous = NORMAL');
              } catch (_) {}
            },
          );
        } catch (_) {}
      }

      if (isDiskDb && backupPath != null) {
        final backupFile = File(backupPath);
        if (await backupFile.exists()) {
          final dbFile = File(path);
          if (await dbFile.exists()) await dbFile.delete();
          await backupFile.copy(path);

          final backupWal = File('$backupPath-wal');
          final dbWal = File('$path-wal');
          if (await dbWal.exists()) await dbWal.delete();
          if (await backupWal.exists()) await backupWal.copy('$path-wal');

          final backupShm = File('$backupPath-shm');
          final dbShm = File('$path-shm');
          if (await dbShm.exists()) await dbShm.delete();
          if (await backupShm.exists()) await backupShm.copy('$path-shm');
        }
      }
      rethrow;
    }
  }

  /// Open database connection using appropriate factory for tests vs production
  Future<Database> _openDb(
    String path, {
    String? password,
    int? version,
    OnDatabaseConfigureFn? onConfigure,
    OnDatabaseCreateFn? onCreate,
    OnDatabaseVersionChangeFn? onUpgrade,
    bool readOnly = false,
    bool singleInstance = true,
  }) async {
    final bool isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    final bool isWindows = !kIsWeb && Platform.isWindows;
    if (isTest || isWindows) {
      return sqlc.openFfiDb(
        path,
        password: password,
        version: version,
        onConfigure: onConfigure,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        readOnly: readOnly,
        singleInstance: singleInstance,
      );
    } else {
      return openDatabase(
        path,
        password: password,
        version: version,
        onConfigure: onConfigure,
        onCreate: onCreate,
        onUpgrade: onUpgrade,
        readOnly: readOnly,
        singleInstance: singleInstance,
      );
    }
  }

  /// Derive encryption key using recovery key and static salt
  String deriveEncryptionKey(String recoveryKey) {
    final staticSalt = Uint8List.fromList([
      0x53, 0x65, 0x72, 0x65, 0x6e, 0x75, 0x74, 0x50,
      0x4f, 0x53, 0x5f, 0x53, 0x65, 0x63, 0x75, 0x72
    ]);
    final derivedKeyBytes = PasswordHashService.deriveKey(
      password: recoveryKey,
      salt: staticSalt,
      iterations: 10000,
      keyLength: 32,
    );
    return base64.encode(derivedKeyBytes);
  }

  /// Change active SQLite encryption key using SQLCipher PRAGMA rekey
  Future<void> changeDatabaseKey(String newRecoveryKey) async {
    final db = await getDatabase();
    final newEncryptionKey = deriveEncryptionKey(newRecoveryKey);
    
    // Temporarily switch back to DELETE journal mode before rekeying.
    // PRAGMA rekey in SQLCipher has known compatibility issues / corruption risks when run in WAL mode.
    try {
      await db.rawQuery('PRAGMA journal_mode = DELETE');
    } catch (_) {}
    
    await db.rawQuery("PRAGMA rekey = '$newEncryptionKey'");
    
    // Switch back to WAL mode after rekeying
    try {
      await db.rawQuery('PRAGMA journal_mode = WAL');
    } catch (_) {}
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('database_recovery_key', newRecoveryKey);
    _encryptionKey = newEncryptionKey;
  }

  /// Open database connection using appropriate factory for tests vs production
  Future<Database> openDatabaseConnection(
    String path, {
    String? password,
    int? version,
    OnDatabaseConfigureFn? onConfigure,
    OnDatabaseCreateFn? onCreate,
    OnDatabaseVersionChangeFn? onUpgrade,
    bool readOnly = false,
  }) async {
    return _openDb(
      path,
      password: password,
      version: version,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      readOnly: readOnly,
    );
  }

  /// Get databases path using appropriate factory for tests vs production
  Future<String> getDatabasesPath() async {
    final bool isTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');
    final bool isWindows = !kIsWeb && Platform.isWindows;
    if (isTest || isWindows) {
      return sqlc.getFfiDatabasesPath();
    } else {
      return databaseFactory.getDatabasesPath();
    }
  }


  /// Create database schema
  Future<void> _onCreate(Database db, int version) async {
    await _createTables(db);
    await _insertDefaultData(db);
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 4) {
      // Non-destructive upgrade: add new performance scaling indexes
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_created ON sales(created_at)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_ft_created ON financial_transactions(created_at)');
      await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)');
    }
    if (oldVersion < 5) {
      // Non-destructive upgrade for version 5: idempotency key and sync status
      await db.execute('ALTER TABLE sales ADD COLUMN idempotency_key TEXT');
      await db.execute('ALTER TABLE sales ADD COLUMN is_synced INTEGER DEFAULT 0');
      await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_idempotency ON sales(idempotency_key)');
    }
    if (oldVersion < 6) {
      // Non-destructive upgrade for version 6: add image_url to products
      try {
        await db.execute('ALTER TABLE products ADD COLUMN image_url TEXT');
      } catch (_) {}
    }
    if (oldVersion < 7) {
      // Non-destructive upgrade for version 7: missing indexes for bulk operations
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_synced ON sales(is_synced)');
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items(product_id)');
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ft_reference ON financial_transactions(reference_id)');
      } catch (_) {}
      try {
        await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action)');
      } catch (_) {}
    }
    if (oldVersion < 8) {
      // Non-destructive upgrade for version 8: sms_logs table and indexes
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS sms_logs (
            id TEXT PRIMARY KEY,
            phone TEXT NOT NULL,
            event_type TEXT NOT NULL,
            message TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'pending',
            created_at TEXT NOT NULL,
            sent_at TEXT,
            error_message TEXT,
            retry_count INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sms_logs_status ON sms_logs(status)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sms_logs_created ON sms_logs(created_at)');
      } catch (_) {}
    }
    if (oldVersion < 9) {
      try {
        await _createTriggers(db);
      } catch (_) {}
    }
    if (oldVersion < 10) {
      try {
        await _createAuditLogsTable(db);
        await _createTriggers(db);
      } catch (_) {}
    }
    if (oldVersion < 11) {
      try {
        await _createTriggers(db);
      } catch (_) {}
    }
    if (oldVersion < 12) {
      try {
        await db.execute('ALTER TABLE financial_transactions ADD COLUMN logical_clock INTEGER NOT NULL DEFAULT 0');
        await db.execute('ALTER TABLE financial_transactions ADD COLUMN device_id TEXT');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ft_logical ON financial_transactions(logical_clock, device_id)');
      } catch (_) {}
    }
    if (oldVersion < 13) {
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS audit_events (
            id TEXT PRIMARY KEY,
            event_type TEXT NOT NULL,
            entity_type TEXT NOT NULL,
            entity_id TEXT,
            user_id TEXT,
            user_name TEXT,
            old_value TEXT,
            new_value TEXT,
            timestamp TEXT NOT NULL,
            device_id TEXT,
            notes TEXT
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_events_timestamp ON audit_events(timestamp)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_events_type ON audit_events(event_type)');

        await db.execute('ALTER TABLE products ADD COLUMN is_deleted INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE products ADD COLUMN deleted_at TEXT');
        await db.execute('ALTER TABLE products ADD COLUMN deleted_by TEXT');

        await db.execute('ALTER TABLE customers ADD COLUMN is_deleted INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE customers ADD COLUMN deleted_at TEXT');
        await db.execute('ALTER TABLE customers ADD COLUMN deleted_by TEXT');

        await db.execute('ALTER TABLE sales ADD COLUMN is_deleted INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE sales ADD COLUMN deleted_at TEXT');
        await db.execute('ALTER TABLE sales ADD COLUMN deleted_by TEXT');

        await db.execute('ALTER TABLE orders ADD COLUMN is_deleted INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE orders ADD COLUMN deleted_at TEXT');
        await db.execute('ALTER TABLE orders ADD COLUMN deleted_by TEXT');

        await db.execute('ALTER TABLE financial_transactions ADD COLUMN is_deleted INTEGER DEFAULT 0');
        await db.execute('ALTER TABLE financial_transactions ADD COLUMN deleted_at TEXT');
        await db.execute('ALTER TABLE financial_transactions ADD COLUMN deleted_by TEXT');
      } catch (_) {}
    }
    if (oldVersion < 14) {
      // Version 14 upgrade: quantity in sale_items and order_items are natively treated as REAL/float.
      // SQLite handles double type automatically for INTEGER columns, so no structure alteration is required.
    }
    if (oldVersion < 15) {
      // Version 15 upgrade: business_profile table for onboarding wizard permanent storage
      try {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS business_profile (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            owner_name TEXT NOT NULL,
            type TEXT NOT NULL DEFAULT '',
            phone TEXT NOT NULL,
            email TEXT,
            tax_number TEXT,
            city TEXT NOT NULL DEFAULT '',
            district TEXT NOT NULL DEFAULT '',
            currency TEXT NOT NULL DEFAULT '₺',
            tax_included INTEGER NOT NULL DEFAULT 1,
            logo_path TEXT,
            created_at TEXT NOT NULL,
            updated_at TEXT
          )
        ''');
        // trial_anchor: üçlü doğrulama için DB tarafı kayıt
        await db.execute('''
          CREATE TABLE IF NOT EXISTS trial_anchor (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            first_launch_ms INTEGER NOT NULL,
            device_hash TEXT,
            checksum TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
      } catch (_) {}
    }
  }

  /// Create all tables
  Future<void> _createTables(Database db) async {
    // Users table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password_hash TEXT NOT NULL,
        role TEXT NOT NULL,
        is_active INTEGER NOT NULL DEFAULT 1,
        last_login TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');

    // Products table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        price REAL NOT NULL,
        quantity INTEGER NOT NULL,
        category TEXT NOT NULL,
        sku TEXT UNIQUE,
        vat INTEGER,
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        image_url TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        deleted_by TEXT
      )
    ''');

    // Customers table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT,
        phone TEXT,
        balance REAL NOT NULL DEFAULT 0,
        credit_limit REAL,
        status TEXT NOT NULL DEFAULT 'active',
        is_active INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        deleted_by TEXT
      )
    ''');

    // Sales table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sales (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        total_amount REAL NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0,
        payment_method TEXT,
        status TEXT NOT NULL DEFAULT 'completed',
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        idempotency_key TEXT UNIQUE,
        is_synced INTEGER NOT NULL DEFAULT 0,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        deleted_by TEXT,
        created_by TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    // Sale items table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        subtotal REAL NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id),
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // Financial transactions table (ledger)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS financial_transactions (
        id TEXT PRIMARY KEY,
        type TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        amount REAL NOT NULL,
        paid_amount REAL NOT NULL DEFAULT 0,
        debt_amount REAL NOT NULL DEFAULT 0,
        reference_id TEXT,
        metadata TEXT,
        created_at TEXT NOT NULL,
        logical_clock INTEGER NOT NULL DEFAULT 0,
        device_id TEXT,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        deleted_by TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ft_logical ON financial_transactions (logical_clock, device_id)');

    // Orders table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'created',
        total_amount REAL,
        order_date TEXT,
        expected_delivery_date TEXT,
        actual_delivery_date TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        deleted_by TEXT,
        created_by TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    // Order items table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders(id),
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // Create audit logs table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_logs (
        id TEXT PRIMARY KEY,
        user_id TEXT NOT NULL,
        user_name TEXT NOT NULL,
        action TEXT NOT NULL,
        details TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await _createAuditLogsTable(db);

    // Create indexes
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_status ON sales(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_category ON products(category)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_status ON customers(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_financial_transactions_customer ON financial_transactions(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_created ON sales(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ft_created ON financial_transactions(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)');
    await db.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_idempotency ON sales(idempotency_key)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_synced ON sales(is_synced)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items(product_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_ft_reference ON financial_transactions(reference_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action)');

    // Create financial ledger view
    await db.execute('''
      CREATE VIEW IF NOT EXISTS v_financial_ledger AS
      SELECT 
        id,
        type,
        customer_id,
        amount,
        paid_amount,
        debt_amount,
        reference_id,
        created_at,
        CASE 
          WHEN type = 'sale' THEN amount
          WHEN type = 'cancellation' THEN -amount
          ELSE 0
        END AS debit,
        CASE 
          WHEN type = 'sale' THEN paid_amount
          WHEN type = 'payment' THEN amount
          WHEN type = 'collection' THEN amount
          WHEN type = 'refund' THEN amount
          WHEN type = 'cancellation' THEN -paid_amount
          ELSE 0
        END AS credit
      FROM financial_transactions
    ''');

    // Create settings table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS settings (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        business_name TEXT NOT NULL,
        business_phone TEXT NOT NULL,
        business_address TEXT NOT NULL,
        business_tax_id TEXT,
        business_logo TEXT,
        currency TEXT NOT NULL DEFAULT '₺',
        printer_name TEXT,
        printer_ip TEXT,
        printer_port INTEGER NOT NULL DEFAULT 9100,
        paper_width INTEGER NOT NULL DEFAULT 80,
        print_receipt INTEGER NOT NULL DEFAULT 1,
        print_qr_code INTEGER NOT NULL DEFAULT 1,
        print_product_details INTEGER NOT NULL DEFAULT 1,
        print_barcode INTEGER NOT NULL DEFAULT 1,
        print_copies INTEGER NOT NULL DEFAULT 1,
        vat_categories TEXT NOT NULL DEFAULT '[]',
        sms_enabled INTEGER NOT NULL DEFAULT 0,
        sms_provider TEXT,
        sms_api_key TEXT,
        sms_template TEXT,
        qr_enabled INTEGER NOT NULL DEFAULT 1,
        qr_format TEXT NOT NULL DEFAULT 'type|id|timestamp|customerId|amount|hash',
        debug_mode INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    // Sync failure retry queue — stores push attempts that failed for later replay
    await db.execute('''
      CREATE TABLE IF NOT EXISTS failed_push_log (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        error_message TEXT NOT NULL,
        attempt_count INTEGER NOT NULL DEFAULT 1,
        last_attempt_at TEXT NOT NULL,
        next_retry_at TEXT NOT NULL,
        resolved INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_failed_push_resolved ON failed_push_log(resolved)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_failed_push_next_retry ON failed_push_log(next_retry_at)');

    // Sync state machine audit trail — persists every state transition for
    // crash recovery and post-incident replay.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_state_log (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        session_id TEXT NOT NULL,
        from_state TEXT NOT NULL,
        to_state TEXT NOT NULL,
        trigger_event TEXT NOT NULL,
        sale_id TEXT,
        device_id TEXT,
        metadata TEXT,
        occurred_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_state_session ON sync_state_log(session_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sync_state_occurred ON sync_state_log(occurred_at)');

    // Create sms_logs table and indexes
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sms_logs (
        id TEXT PRIMARY KEY,
        phone TEXT NOT NULL,
        event_type TEXT NOT NULL,
        message TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        created_at TEXT NOT NULL,
        sent_at TEXT,
        error_message TEXT,
        retry_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sms_logs_status ON sms_logs(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_sms_logs_created ON sms_logs(created_at)');

    // Audit Events table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS audit_events (
        id TEXT PRIMARY KEY,
        event_type TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        user_id TEXT,
        user_name TEXT,
        old_value TEXT,
        new_value TEXT,
        timestamp TEXT NOT NULL,
        device_id TEXT,
        notes TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_events_timestamp ON audit_events(timestamp)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_audit_events_type ON audit_events(event_type)');

    // business_profile table: İşletme kalıcı bilgileri
    await db.execute('''
      CREATE TABLE IF NOT EXISTS business_profile (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        owner_name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL,
        email TEXT,
        tax_number TEXT,
        city TEXT NOT NULL DEFAULT '',
        district TEXT NOT NULL DEFAULT '',
        currency TEXT NOT NULL DEFAULT '₺',
        tax_included INTEGER NOT NULL DEFAULT 1,
        logo_path TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    // trial_anchor: Deneme süresi üçlü doğrulama (SharedPrefs + DB + checksum)
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trial_anchor (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_launch_ms INTEGER NOT NULL,
        device_hash TEXT,
        checksum TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');

    await _createTriggers(db);
  }

  Future<void> _createAuditLogsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS trigger_audit_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        trigger_name TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        transaction_id TEXT NOT NULL,
        before_balance REAL NOT NULL,
        after_balance REAL NOT NULL,
        timestamp TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_trigger_audit_customer ON trigger_audit_logs(customer_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ledger_bypass_flag (
        active INTEGER NOT NULL DEFAULT 0
      )
    ''');
    final countResult = await db.rawQuery('SELECT COUNT(*) as cnt FROM ledger_bypass_flag');
    if (Sqflite.firstIntValue(countResult) == 0) {
      await db.rawInsert('INSERT INTO ledger_bypass_flag (active) VALUES (0)');
    }
  }

  Future<void> _verifyAndRepairTriggers(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name IN ('trg_ft_insert', 'trg_ft_block_update', 'trg_ft_block_delete')"
    );
    if (rows.length < 3) {
      try {
        await _createAuditLogsTable(db);
        await _createTriggers(db);
        debugPrint('Self-Healing: Recreated missing or tampered database triggers successfully.');
      } catch (_) {}
    }
  }

  /// Create financial transaction DB triggers for audit freeze bakiye calculations
  Future<void> _createTriggers(Database db) async {
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_insert');
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_update');
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_delete');
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_block_update');
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_block_delete');

    // Block updates to ensure ledger immutability
    await db.execute('''
      CREATE TRIGGER trg_ft_block_update BEFORE UPDATE ON financial_transactions
      WHEN (SELECT active FROM ledger_bypass_flag LIMIT 1) = 0
      BEGIN
        SELECT RAISE(ABORT, 'Kritik Hata: Finansal defter kayıtları değiştirilemez (Ledger Immutability).');
      END;
    ''');

    // Block deletions to ensure ledger immutability
    await db.execute('''
      CREATE TRIGGER trg_ft_block_delete BEFORE DELETE ON financial_transactions
      WHEN (SELECT active FROM ledger_bypass_flag LIMIT 1) = 0
      BEGIN
        SELECT RAISE(ABORT, 'Kritik Hata: Finansal defter kayıtları silinemez (Ledger Immutability).');
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER trg_ft_insert AFTER INSERT ON financial_transactions
      BEGIN
        -- Insert trigger audit log before updating customer balance
        INSERT INTO trigger_audit_logs (trigger_name, customer_id, transaction_id, before_balance, after_balance, timestamp)
        SELECT 
          'trg_ft_insert',
          NEW.customer_id,
          NEW.id,
          c.balance,
          c.balance + CASE 
            WHEN NEW.type = 'sale' THEN -NEW.debt_amount
            WHEN NEW.type = 'payment' THEN NEW.paid_amount
            WHEN NEW.type = 'cancellation' THEN NEW.debt_amount
            WHEN NEW.type = 'collection' THEN NEW.paid_amount
            WHEN NEW.type = 'refund' AND NEW.paid_amount = 0 THEN NEW.amount
            ELSE 0
          END,
          DATETIME('now')
        FROM customers c
        WHERE c.id = NEW.customer_id;

        UPDATE customers
        SET balance = balance + CASE 
          WHEN NEW.type = 'sale' THEN -NEW.debt_amount
          WHEN NEW.type = 'payment' THEN NEW.paid_amount
          WHEN NEW.type = 'cancellation' THEN NEW.debt_amount
          WHEN NEW.type = 'collection' THEN NEW.paid_amount
          WHEN NEW.type = 'refund' AND NEW.paid_amount = 0 THEN NEW.amount
          ELSE 0
        END
        WHERE id = NEW.customer_id;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER trg_ft_update AFTER UPDATE ON financial_transactions
      BEGIN
        -- Reverse the OLD transaction effect
        UPDATE customers
        SET balance = balance - CASE 
          WHEN OLD.type = 'sale' THEN -OLD.debt_amount
          WHEN OLD.type = 'payment' THEN OLD.paid_amount
          WHEN OLD.type = 'cancellation' THEN OLD.debt_amount
          WHEN OLD.type = 'collection' THEN OLD.paid_amount
          WHEN OLD.type = 'refund' AND OLD.paid_amount = 0 THEN OLD.amount
          ELSE 0
        END
        WHERE id = OLD.customer_id;

        -- Apply the NEW transaction effect
        UPDATE customers
        SET balance = balance + CASE 
          WHEN NEW.type = 'sale' THEN -NEW.debt_amount
          WHEN NEW.type = 'payment' THEN NEW.paid_amount
          WHEN NEW.type = 'cancellation' THEN NEW.debt_amount
          WHEN NEW.type = 'collection' THEN NEW.paid_amount
          WHEN NEW.type = 'refund' AND NEW.paid_amount = 0 THEN NEW.amount
          ELSE 0
        END
        WHERE id = NEW.customer_id;
      END;
    ''');

    await db.execute('''
      CREATE TRIGGER trg_ft_delete AFTER DELETE ON financial_transactions
      BEGIN
        -- Reverse the OLD transaction effect
        UPDATE customers
        SET balance = balance - CASE 
          WHEN OLD.type = 'sale' THEN -OLD.debt_amount
          WHEN OLD.type = 'payment' THEN OLD.paid_amount
          WHEN OLD.type = 'cancellation' THEN OLD.debt_amount
          WHEN OLD.type = 'collection' THEN OLD.paid_amount
          WHEN OLD.type = 'refund' AND OLD.paid_amount = 0 THEN OLD.amount
          ELSE 0
        END
        WHERE id = OLD.customer_id;
      END;
    ''');
  }

  /// Drop all tables (for testing/migration)
  Future<void> _dropTables(Database db) async {
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_insert');
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_block_update');
    await db.execute('DROP TRIGGER IF EXISTS trg_ft_block_delete');
    await db.execute('DROP TABLE IF EXISTS sms_logs');
    await db.execute('DROP TABLE IF EXISTS sync_state_log');
    await db.execute('DROP TABLE IF EXISTS failed_push_log');
    await db.execute('DROP TABLE IF EXISTS audit_logs');
    await db.execute('DROP TABLE IF EXISTS settings');
    await db.execute('DROP VIEW IF EXISTS v_financial_ledger');
    await db.execute('DROP TABLE IF EXISTS order_items');
    await db.execute('DROP TABLE IF EXISTS orders');
    await db.execute('DROP TABLE IF EXISTS financial_transactions');
    await db.execute('DROP TABLE IF EXISTS sale_items');
    await db.execute('DROP TABLE IF EXISTS sales');
    await db.execute('DROP TABLE IF EXISTS customers');
    await db.execute('DROP TABLE IF EXISTS products');
    await db.execute('DROP TABLE IF EXISTS users');
  }

  /// Insert default/seed data (first install only)
  Future<void> _insertDefaultData(Database db) async {
    // ── Users seeding is omitted (configured via First Setup) ──

    // ── Default Settings (production-ready, blank business info) ──────────
    await db.insert('settings', {
      'business_name': '',
      'business_phone': '',
      'business_address': '',
      'currency': '₺',
      'printer_port': 9100,
      'paper_width': 80,
      'print_receipt': 1,
      'print_qr_code': 0,
      'print_product_details': 1,
      'print_barcode': 0,
      'print_copies': 1,
      'vat_categories': '[]',
      'sms_enabled': 0,
      'qr_enabled': 0,
      'qr_format': 'type|id|timestamp|customerId|amount|hash',
      'debug_mode': 0,
      'created_at': DateTime.now().toIso8601String(),
    });

    // ── "Peşin Müşteri" — reserved walk-in cash customer ─────────────────
    // Required by the sales flow as the default anonymous customer.
    await db.insert('customers', {
      'id': '',
      'name': 'Peşin Müşteri',
      'email': '',
      'phone': '',
      'balance': 0.0,
      'credit_limit': 0.0,
      'status': 'active',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });
  }

  /// Close database connection
  Future<void> close() async {
    await _database?.close();
    _database = null;
    _databaseFuture = null;
  }

  /// Factory Reset: Closes database connection and deletes all local database files
  Future<void> resetDatabase() async {
    await close();
    final String path = overrideDatabasePath ??
        ((!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'))
            ? inMemoryDatabasePath
            : join(await getDatabasesPath(), _databaseName));
    if (path != inMemoryDatabasePath) {
      final dbFile = File(path);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      final walFile = File('$path-wal');
      if (await walFile.exists()) {
        await walFile.delete();
      }
      final shmFile = File('$path-shm');
      if (await shmFile.exists()) {
        await shmFile.delete();
      }
      final backupFile = File(join(dirname(path), 'serenut_pos_upgrade_backup.db'));
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      final backupWal = File(join(dirname(path), 'serenut_pos_upgrade_backup.db-wal'));
      if (await backupWal.exists()) {
        await backupWal.delete();
      }
      final backupShm = File(join(dirname(path), 'serenut_pos_upgrade_backup.db-shm'));
      if (await backupShm.exists()) {
        await backupShm.delete();
      }
      final bakFile = File('$path.bak');
      if (await bakFile.exists()) {
        await bakFile.delete();
      }
      final bakWalFile = File('$path-wal.bak');
      if (await bakWalFile.exists()) {
        await bakWalFile.delete();
      }
      final bakShmFile = File('$path-shm.bak');
      if (await bakShmFile.exists()) {
        await bakShmFile.delete();
      }
    }
  }

  // ── Log Retention (SQLite audit_logs table) ─────────────────────────────────

  /// Deletes `audit_logs` rows older than [retentionDays] days.
  ///
  /// Recommended schedule: call once per day (e.g. on app start).
  /// Default: 90-day retention.
  ///
  /// ```dart
  /// await DatabaseManager().purgeOldAuditLogs();
  /// ```
  Future<int> purgeOldAuditLogs({int retentionDays = 90}) async {
    final db = await getDatabase();
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .toIso8601String();
    final deleted = await db.delete(
      'audit_logs',
      where: 'created_at < ?',
      whereArgs: [cutoff],
    );
    return deleted;
  }

  /// Deletes resolved `failed_push_log` rows older than [retentionDays] days.
  ///
  /// Unresolved rows (resolved = 0) are never purged — they stay for replay.
  Future<int> purgeOldFailedPushLogs({int retentionDays = 30}) async {
    final db = await getDatabase();
    final cutoff = DateTime.now()
        .subtract(Duration(days: retentionDays))
        .toIso8601String();
    final deleted = await db.delete(
      'failed_push_log',
      where: 'resolved = 1 AND last_attempt_at < ?',
      whereArgs: [cutoff],
    );
    return deleted;
  }
}

class DatabaseLockedException implements Exception {
  final String message;
  DatabaseLockedException(this.message);

  @override
  String toString() => message;
}
