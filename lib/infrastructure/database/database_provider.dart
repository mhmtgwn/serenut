// lib/infrastructure/database/database_provider.dart
// PHASE 0 Day 4 - Database Layer
// SQLite database initialization and management
// Updated: SQLCipher removed — using standard sqflite

import 'dart:io' show Platform, File, Directory;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint, kDebugMode;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';

/// ════════════════════════════════════════════════════════════
/// Database Manager
/// ════════════════════════════════════════════════════════════
///
/// Handles SQLite database initialization, schema creation,
/// and connection management (plain sqflite, no encryption).

class DatabaseManager {
  static final _instance = DatabaseManager._();
  factory DatabaseManager() => _instance;
  DatabaseManager._();

  static const String customerBalanceSql = '''
    SELECT COALESCE(SUM(
      CASE 
        WHEN type = 'sale' THEN -debt_amount
        WHEN type = 'payment' THEN paid_amount
        WHEN type = 'cancellation' THEN debt_amount
        WHEN type = 'collection' THEN paid_amount
        WHEN type = 'refund' AND paid_amount = 0 THEN amount
        ELSE 0
      END
    ), 0.0) as expected
    FROM financial_transactions
    WHERE customer_id = ?
  ''';

  static const String _databaseName = 'serenut_pos.db';
  static const int _databaseVersion = 23;

  static String? overrideDatabasePath;
  static bool isWriteLocked = false;

  Database? _database;
  Future<Database>? _databaseFuture;

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

  /// Check if the database file is a valid SQLite database
  Future<bool> _isDatabaseFile(String path) async {
    final file = File(path);
    if (!await file.exists()) return false;
    try {
      final bytes = await file.openRead(0, 16).first;
      final header = String.fromCharCodes(bytes);
      return header.startsWith('SQLite format 3');
    } catch (_) {
      return false;
    }
  }

  /// Initialize database and create schema
  Future<Database> _initializeDatabase() async {
    final String path = overrideDatabasePath ??
        ((!kIsWeb && Platform.environment.containsKey('FLUTTER_TEST'))
            ? inMemoryDatabasePath
            : join(await getDatabasesPath(), _databaseName));

    final bool isDiskDb = path != inMemoryDatabasePath;

    if (isDiskDb) {
      try {
        final dbDir = Directory(dirname(path));
        if (!await dbDir.exists()) {
          await dbDir.create(recursive: true);
        }
      } catch (_) {}
    }

    // Safe SQLCipher / Encrypted database recovery
    if (isDiskDb) {
      final dbFile = File(path);
      if (await dbFile.exists() && !await _isDatabaseFile(path)) {
        debugPrint('[DatabaseManager] ⚠️ Encrypted or corrupt database file detected.');
        
        final dbDir = dirname(path);
        final backupPath = join(dbDir, 'serenut_pos_upgrade_backup.db');
        final backupFile = File(backupPath);
        
        List<Map<String, dynamic>> pendingSales = [];
        List<Map<String, dynamic>> pendingTransactions = [];
        
        if (await backupFile.exists() && await _isDatabaseFile(backupPath)) {
          debugPrint('[DatabaseManager] 📦 Attempting recovery from plain upgrade backup...');
          try {
            final backupDb = await openDatabase(backupPath, readOnly: true, singleInstance: false);
            try {
              pendingSales = await backupDb.query('sales', where: 'is_synced = 0');
            } catch (e, st) {
              debugPrint('[DatabaseManager] ❌ Sales recovery query failed: $e');
              await TelemetryService().logError(e, st, context: 'db_recovery_sales_query');
            }
            try {
              pendingTransactions = await backupDb.query('financial_transactions', where: 'is_synced = 0');
            } catch (e, st) {
              debugPrint('[DatabaseManager] ❌ Financial transactions recovery query failed: $e');
              await TelemetryService().logError(e, st, context: 'db_recovery_tx_query');
            }
            await backupDb.close();
            debugPrint('[DatabaseManager] 📥 Recovered ${pendingSales.length} sales and ${pendingTransactions.length} pending transactions.');
          } catch (err, st) {
            debugPrint('[DatabaseManager] ❌ Recovery reading failed: $err');
            await TelemetryService().logError(err, st, context: 'db_recovery_failed');
          }
        }
        
        debugPrint('[DatabaseManager] 🗑️ Deleting encrypted/corrupted database file to recreate plain SQLite.');
        await dbFile.delete();
        
        // Recreate clean database and write back the recovered data
        try {
          final cleanDb = await openDatabase(
            path,
            version: _databaseVersion,
            onCreate: _onCreate,
          );
          if (pendingSales.isNotEmpty || pendingTransactions.isNotEmpty) {
            debugPrint('[DatabaseManager] 🔄 Replaying recovered pending queue into the new clean database...');
            await cleanDb.transaction((txn) async {
              for (final sale in pendingSales) {
                final cleanSale = Map<String, dynamic>.from(sale);
                cleanSale['is_synced'] = 0;
                await txn.insert('sales', cleanSale, conflictAlgorithm: ConflictAlgorithm.replace);
              }
              for (final tx in pendingTransactions) {
                final cleanTx = Map<String, dynamic>.from(tx);
                cleanTx['is_synced'] = 0;
                await txn.insert('financial_transactions', cleanTx, conflictAlgorithm: ConflictAlgorithm.replace);
              }
            });
            debugPrint('[DatabaseManager] ✅ Replay completed successfully.');
          }
          await cleanDb.close();
        } catch (e) {
          debugPrint('[DatabaseManager] ❌ Replay failed: $e');
        }
      }
    }

    // Create upgrade backup if schema version will change
    String? backupPath;
    if (isDiskDb) {
      final dbFile = File(path);
      if (await dbFile.exists() && await _isDatabaseFile(path)) {
        int currentVersion = 0;
        try {
          final tempDb = await openDatabase(path, readOnly: true, singleInstance: false);
          currentVersion = await tempDb.getVersion();
          await tempDb.close();
        } catch (e, st) {
          debugPrint('[DatabaseManager] ⚠️ Pre-upgrade version check failed: $e');
          TelemetryService().logError(e, st, context: 'db_pre_upgrade_version_check');
        }

        if (currentVersion > 0 && currentVersion < _databaseVersion) {
          final dbDir = dirname(path);
          backupPath = join(dbDir, 'serenut_pos_upgrade_backup.db');
          final backupFile = File(backupPath);
          if (await backupFile.exists()) await backupFile.delete();
          await dbFile.copy(backupPath);

          final walFile = File('$path-wal');
          if (await walFile.exists()) await walFile.copy('$backupPath-wal');
          final shmFile = File('$path-shm');
          if (await shmFile.exists()) await shmFile.copy('$backupPath-shm');
        }
      }
    }

    try {
      final db = await openDatabase(
        path,
        version: _databaseVersion,
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
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
          
          return await openDatabase(
            path,
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
        } catch (e, st) {
          debugPrint('[DatabaseManager] ❌ Self-heal re-open failed after decryption error: $e');
          TelemetryService().logError(e, st, context: 'db_selfheal_reopen_failed');
        }
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
  // (Kept for backward compat — delegates to openDatabase)


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
    return openDatabase(
      path,
      version: version,
      onConfigure: onConfigure,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      readOnly: readOnly,
    );
  }

  /// Get databases path using appropriate factory for tests vs production
  Future<String> getDatabasesPath() async {
    final bool isWindows = !kIsWeb && Platform.isWindows;
    if (isWindows) {
      final appSupportDir = await getApplicationSupportDirectory();
      return join(appSupportDir.path, 'databases');
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
    // Enforce app_migration_history existence before running migrations
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_migration_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        version INTEGER NOT NULL,
        migrated_at TEXT NOT NULL,
        status TEXT NOT NULL,
        error_message TEXT
      )
    ''');

    await db.transaction((txn) async {
      try {
        if (oldVersion < 4) {
          await txn.execute('CREATE INDEX IF NOT EXISTS idx_sales_created ON sales(created_at)');
          await txn.execute('CREATE INDEX IF NOT EXISTS idx_ft_created ON financial_transactions(created_at)');
          await txn.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)');
          await txn.insert('app_migration_history', {
            'version': 4,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 5) {
          await txn.execute('ALTER TABLE sales ADD COLUMN idempotency_key TEXT');
          await txn.execute('ALTER TABLE sales ADD COLUMN is_synced INTEGER DEFAULT 0');
          await txn.execute('CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_idempotency ON sales(idempotency_key)');
          await txn.insert('app_migration_history', {
            'version': 5,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 6) {
          try {
            await txn.execute('ALTER TABLE products ADD COLUMN image_url TEXT');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 6,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 7) {
          try {
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_sales_synced ON sales(is_synced)');
          } catch (_) {}
          try {
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items(product_id)');
          } catch (_) {}
          try {
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_ft_reference ON financial_transactions(reference_id)');
          } catch (_) {}
          try {
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action)');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 7,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 8) {
          try {
            await txn.execute('''
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
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_sms_logs_status ON sms_logs(status)');
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_sms_logs_created ON sms_logs(created_at)');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 8,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 9) {
          await txn.insert('app_migration_history', {
            'version': 9,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 10) {
          await txn.insert('app_migration_history', {
            'version': 10,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 11) {
          await txn.insert('app_migration_history', {
            'version': 11,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 12) {
          try {
            await txn.execute('ALTER TABLE financial_transactions ADD COLUMN logical_clock INTEGER NOT NULL DEFAULT 0');
            await txn.execute('ALTER TABLE financial_transactions ADD COLUMN device_id TEXT');
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_ft_logical ON financial_transactions(logical_clock, device_id)');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 12,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 13) {
          try {
            await txn.execute('''
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
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_audit_events_timestamp ON audit_events(timestamp)');
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_audit_events_type ON audit_events(event_type)');

            await txn.execute('ALTER TABLE products ADD COLUMN is_deleted INTEGER DEFAULT 0');
            await txn.execute('ALTER TABLE products ADD COLUMN deleted_at TEXT');
            await txn.execute('ALTER TABLE products ADD COLUMN deleted_by TEXT');

            await txn.execute('ALTER TABLE customers ADD COLUMN is_deleted INTEGER DEFAULT 0');
            await txn.execute('ALTER TABLE customers ADD COLUMN deleted_at TEXT');
            await txn.execute('ALTER TABLE customers ADD COLUMN deleted_by TEXT');

            await txn.execute('ALTER TABLE sales ADD COLUMN is_deleted INTEGER DEFAULT 0');
            await txn.execute('ALTER TABLE sales ADD COLUMN deleted_at TEXT');
            await txn.execute('ALTER TABLE sales ADD COLUMN deleted_by TEXT');

            await txn.execute('ALTER TABLE orders ADD COLUMN is_deleted INTEGER DEFAULT 0');
            await txn.execute('ALTER TABLE orders ADD COLUMN deleted_at TEXT');
            await txn.execute('ALTER TABLE orders ADD COLUMN deleted_by TEXT');

            await txn.execute('ALTER TABLE financial_transactions ADD COLUMN is_deleted INTEGER DEFAULT 0');
            await txn.execute('ALTER TABLE financial_transactions ADD COLUMN deleted_at TEXT');
            await txn.execute('ALTER TABLE financial_transactions ADD COLUMN deleted_by TEXT');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 13,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 14) {
          await txn.insert('app_migration_history', {
            'version': 14,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 15) {
          try {
            await txn.execute('''
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
            await txn.execute('''
              CREATE TABLE IF NOT EXISTS trial_anchor (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                first_launch_ms INTEGER NOT NULL,
                device_hash TEXT,
                checksum TEXT NOT NULL,
                created_at TEXT NOT NULL
              )
            ''');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 15,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 16) {
          try {
            await txn.execute('ALTER TABLE settings ADD COLUMN owner_name TEXT DEFAULT ""');
            await txn.execute('ALTER TABLE settings ADD COLUMN business_email TEXT');
            await txn.execute('ALTER TABLE settings ADD COLUMN business_city TEXT DEFAULT ""');
            await txn.execute('ALTER TABLE settings ADD COLUMN business_district TEXT DEFAULT ""');
            await txn.execute('ALTER TABLE settings ADD COLUMN business_type TEXT DEFAULT ""');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 16,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 17) {
          try {
            await txn.execute('ALTER TABLE products ADD COLUMN is_synced INTEGER DEFAULT 1');
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_products_synced ON products(is_synced)');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 17,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 18) {
          try {
            await txn.execute('ALTER TABLE users ADD COLUMN username TEXT');
            await txn.execute('ALTER TABLE users ADD COLUMN pin_hash TEXT');
            await txn.execute('ALTER TABLE users ADD COLUMN business_code TEXT');
            await txn.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users(business_code, username) WHERE username IS NOT NULL'
            );
            await txn.execute('ALTER TABLE users ADD COLUMN device_token_version INTEGER DEFAULT 1');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 18,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 19) {
          try {
            await txn.execute('ALTER TABLE financial_transactions ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 1');
          } catch (e) {
            final msg = e.toString().toLowerCase();
            // 'duplicate column'/'already exists': kolон zaten var (idempotent)
            // 'no such table': taze DB'de tablo henuz olusturulmamis, CREATE TABLE'da gelecek
            if (!msg.contains('duplicate column') &&
                !msg.contains('already exists') &&
                !msg.contains('no such table')) {
              rethrow;
            }
          }
          try {
            await txn.execute('ALTER TABLE customers ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 1');
          } catch (e) {
            final msg = e.toString().toLowerCase();
            if (!msg.contains('duplicate column') &&
                !msg.contains('already exists') &&
                !msg.contains('no such table')) {
              rethrow;
            }
          }
          try {
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_ft_customer_id ON financial_transactions(customer_id)');
          } catch (e) {
            rethrow;
          }
          await txn.insert('app_migration_history', {
            'version': 19,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 20) {
          try {
            await txn.execute('ALTER TABLE settings ADD COLUMN license_token TEXT');
            await txn.execute('ALTER TABLE settings ADD COLUMN last_system_time TEXT');
            await txn.execute('ALTER TABLE settings ADD COLUMN max_timestamp_seen TEXT');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 20,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 21) {
          try {
            await txn.execute('''
              CREATE TABLE IF NOT EXISTS print_queue (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                receipt_json TEXT NOT NULL,
                created_at TEXT NOT NULL,
                retry_count INTEGER NOT NULL DEFAULT 0,
                status TEXT NOT NULL,
                last_error TEXT
              )
            ''');
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_print_queue_status ON print_queue(status)');
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_print_queue_created ON print_queue(created_at)');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 21,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 22) {
          // Add 9 new columns to settings table (idempotent: catch duplicate column errors)
          for (final col in [
            'ALTER TABLE settings ADD COLUMN sound_notification_enabled INTEGER NOT NULL DEFAULT 0',
            'ALTER TABLE settings ADD COLUMN sms_auto_debt_reminder_enabled INTEGER NOT NULL DEFAULT 0',
            'ALTER TABLE settings ADD COLUMN sms_auto_debt_reminder_days INTEGER NOT NULL DEFAULT 15',
            'ALTER TABLE settings ADD COLUMN sms_auto_debt_reminder_min_amount REAL NOT NULL DEFAULT 100.0',
            'ALTER TABLE settings ADD COLUMN label_printer_enabled INTEGER NOT NULL DEFAULT 0',
            'ALTER TABLE settings ADD COLUMN label_printer_ip TEXT',
            'ALTER TABLE settings ADD COLUMN label_printer_port INTEGER NOT NULL DEFAULT 9100',
            'ALTER TABLE settings ADD COLUMN label_printer_copies INTEGER NOT NULL DEFAULT 1',
            'ALTER TABLE settings ADD COLUMN admin_pin_code TEXT',
          ]) {
            try {
              await txn.execute(col);
            } catch (e) {
              final msg = e.toString().toLowerCase();
              if (!msg.contains('duplicate column') && !msg.contains('already exists')) rethrow;
            }
          }
          await txn.insert('app_migration_history', {
            'version': 22,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 23) {
          try {
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id)');
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)');
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at)');
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id)');
            await txn.execute('CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id)');
          } catch (_) {}
          await txn.insert('app_migration_history', {
            'version': 23,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
      } catch (err) {
        // Log migration error to history before throwing
        try {
          await txn.insert('app_migration_history', {
            'version': newVersion,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'failed',
            'error_message': err.toString()
          });
        } catch (_) {}
        rethrow;
      }
    });

    // ── One-time SharedPreferences → SQLite migration (runs after the transaction) ──
    // This cannot run inside a transaction because SharedPreferences is async/external.
    if (oldVersion < 22) {
      await _migrateSharedPrefsToSqlite(db);
    }
  }

  /// Migrate 9 settings fields and legacy SharedPreferences audit logs to SQLite.
  /// Runs exactly once when upgrading from a version < 22.
  Future<void> _migrateSharedPrefsToSqlite(Database db) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ── 1. Migrate 9 settings values ──────────────────────────────────────────
      final settingsRows = await db.query('settings', limit: 1);
      if (settingsRows.isNotEmpty) {
        final existingId = settingsRows.first['id'];
        await db.update('settings', {
          'sound_notification_enabled': (prefs.getBool('sound_notification_enabled') ?? false) ? 1 : 0,
          'sms_auto_debt_reminder_enabled': (prefs.getBool('sms_auto_debt_reminder_enabled') ?? false) ? 1 : 0,
          'sms_auto_debt_reminder_days': prefs.getInt('sms_auto_debt_reminder_days') ?? 15,
          'sms_auto_debt_reminder_min_amount': prefs.getDouble('sms_auto_debt_reminder_min_amount') ?? 100.0,
          'label_printer_enabled': (prefs.getBool('label_printer_enabled') ?? false) ? 1 : 0,
          'label_printer_ip': prefs.getString('label_printer_ip') ?? '',
          'label_printer_port': int.tryParse(prefs.getString('label_printer_port') ?? '9100') ?? 9100,
          'label_printer_copies': prefs.getInt('label_printer_copies') ?? 1,
          'admin_pin_code': prefs.getString('admin_pin_code'),
          'updated_at': DateTime.now().toIso8601String(),
        }, where: 'id = ?', whereArgs: [existingId]);
      }

      // Clean up migrated SharedPreferences settings keys
      for (final key in [
        'sound_notification_enabled',
        'sms_auto_debt_reminder_enabled',
        'sms_auto_debt_reminder_days',
        'sms_auto_debt_reminder_min_amount',
        'label_printer_enabled',
        'label_printer_ip',
        'label_printer_port',
        'label_printer_copies',
        'admin_pin_code',
      ]) {
        await prefs.remove(key);
      }

      // ── 2. Migrate legacy SharedPreferences audit logs → SQLite audit_logs ──
      final rawLogs = prefs.getStringList('serenut_audit_logs');
      if (rawLogs != null && rawLogs.isNotEmpty) {
        for (final rawLog in rawLogs) {
          try {
            final map = jsonDecode(rawLog) as Map<String, dynamic>;
            // Each entry has: id, timestamp, action, beforeState, afterState, metadata
            final logId = map['id'] as String? ?? const Uuid().v4();
            final details = jsonEncode({
              'before': map['beforeState'] ?? '',
              'after': map['afterState'] ?? '',
              'metadata': map['metadata'] ?? {},
            });
            await db.insert('audit_logs', {
              'id': logId,
              'user_id': 'system',
              'user_name': 'Migrated (SharedPrefs)',
              'action': map['action'] ?? 'unknown',
              'details': details,
              'created_at': map['timestamp'] ?? DateTime.now().toIso8601String(),
            }, conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (_) {
            // Malformed entry — skip
          }
        }
        // Remove migrated audit log key
        await prefs.remove('serenut_audit_logs');
        debugPrint('[DB Migration v22] Migrated ${rawLogs.length} SharedPreferences audit logs to SQLite audit_logs.');
      }

      debugPrint('[DB Migration v22] SharedPreferences → SQLite migration complete.');
    } catch (e) {
      debugPrint('[DB Migration v22] Migration failed (non-fatal): $e');
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
        updated_at TEXT NOT NULL,
        username TEXT,
        pin_hash TEXT,
        business_code TEXT,
        device_token_version INTEGER DEFAULT 1
      )
    ''');
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users(business_code, username) WHERE username IS NOT NULL
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
        deleted_by TEXT,
        is_synced INTEGER NOT NULL DEFAULT 1
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
        deleted_by TEXT,
        is_synced INTEGER NOT NULL DEFAULT 1
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
        is_synced INTEGER NOT NULL DEFAULT 1,
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
    await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id)');

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
        owner_name TEXT NOT NULL DEFAULT '',
        business_email TEXT,
        business_city TEXT NOT NULL DEFAULT '',
        business_district TEXT NOT NULL DEFAULT '',
        business_type TEXT NOT NULL DEFAULT '',
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
        license_token TEXT,
        last_system_time TEXT,
        max_timestamp_seen TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT,
        sound_notification_enabled INTEGER NOT NULL DEFAULT 0,
        sms_auto_debt_reminder_enabled INTEGER NOT NULL DEFAULT 0,
        sms_auto_debt_reminder_days INTEGER NOT NULL DEFAULT 15,
        sms_auto_debt_reminder_min_amount REAL NOT NULL DEFAULT 100.0,
        label_printer_enabled INTEGER NOT NULL DEFAULT 0,
        label_printer_ip TEXT,
        label_printer_port INTEGER NOT NULL DEFAULT 9100,
        label_printer_copies INTEGER NOT NULL DEFAULT 1,
        admin_pin_code TEXT
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

    // Create print_queue table and indexes
    await db.execute('''
      CREATE TABLE IF NOT EXISTS print_queue (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        receipt_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        retry_count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL,
        last_error TEXT
      )
    ''');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_print_queue_status ON print_queue(status)');
    await db.execute('CREATE INDEX IF NOT EXISTS idx_print_queue_created ON print_queue(created_at)');

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

    await db.execute('''
      CREATE TABLE IF NOT EXISTS client_telemetry_logs (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        metric_name TEXT NOT NULL,
        metric_value REAL NOT NULL,
        timestamp TEXT NOT NULL,
        metadata TEXT
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
      } catch (e, st) {
        debugPrint('[DatabaseManager] ❌ Trigger self-healing failed: $e');
        TelemetryService().logError(e, st, context: 'db_trigger_selfheal_failed');
      }
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
      'owner_name': '',
      'business_email': '',
      'business_city': '',
      'business_district': '',
      'business_type': '',
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
      // Sprint 4 — new settings columns (default values)
      'sound_notification_enabled': 0,
      'sms_auto_debt_reminder_enabled': 0,
      'sms_auto_debt_reminder_days': 15,
      'sms_auto_debt_reminder_min_amount': 100.0,
      'label_printer_enabled': 0,
      'label_printer_ip': '',
      'label_printer_port': 9100,
      'label_printer_copies': 1,
      'admin_pin_code': null,
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
