// lib/infrastructure/database/database_provider.dart
// PHASE 0 Day 4 - Database Layer
// SQLite database initialization and management
// Updated: SQLCipher removed — using standard sqflite

import 'dart:io' show Platform, File, Directory;
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:serenutos/infrastructure/database/schema/db_schema.dart';
import 'package:serenutos/infrastructure/database/schema/db_triggers.dart';
import 'package:serenutos/infrastructure/database/schema/db_migrations.dart';

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
        WHEN type = 'manual_debt' THEN -debt_amount
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
  static const int _databaseVersion = 32;

  static String? overrideDatabasePath;
  static bool isWriteLocked = false;

  Database? _database;
  Future<Database>? _databaseFuture;

  /// Reset database connection cache (used in testing)
  void reset() {
    _database = null;
    _databaseFuture = null;
  }

  /// Get database instance (lazy initialization)
  Future<Database> getDatabase() async {
    if (_database != null) {
      return _database!;
    }
    _databaseFuture ??= _initializeDatabase();
    _database = await _databaseFuture;
    await _verifyDatabaseSchemaInvariants(_database!);
    await DatabaseTriggers.verifyAndRepairTriggers(_database!);
    return _database!;
  }

  /// Verify that crucial tables and columns exist using sqlite_master and PRAGMA table_info
  Future<void> _verifyDatabaseSchemaInvariants(Database db) async {
    final Map<String, List<String>> expectedColumns = {
      'users': [
        'id',
        'name',
        'email',
        'password_hash',
        'role',
        'is_active',
        'username',
        'pin_hash',
        'business_code',
        'device_token_version',
        'failed_pin_attempts',
        'locked_until',
        'permissions'
      ],
      'settings': [
        'id',
        'business_name',
        'sound_notification_enabled',
        'label_printer_ip',
        'sms_sim_subscription_id'
      ],
      'business_profile': ['id', 'version'],
      'sms_logs': ['id', 'status', 'event_type'],
      'print_queue': ['id', 'status'],
    };

    for (final table in expectedColumns.keys) {
      // 1. Check table existence using sqlite_master
      final tableCheck = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
          [table]);
      if (tableCheck.isEmpty) {
        throw StateError(
            'Database invariant violation: Table $table is missing from database schema.');
      }

      // 2. Check column existence using PRAGMA table_info
      final List<Map<String, dynamic>> columnsInfo =
          await db.rawQuery('PRAGMA table_info($table)');
      final existingColumns =
          columnsInfo.map((c) => c['name'] as String).toList();

      for (final expectedCol in expectedColumns[table]!) {
        if (!existingColumns.contains(expectedCol)) {
          throw StateError(
              'Database invariant violation: Column $expectedCol is missing from table $table.');
        }
      }
    }
    debugPrint(
        '[DatabaseManager] 🛡️ All schema invariants verified successfully.');
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
        debugPrint(
            '[DatabaseManager] ⚠️ Encrypted or corrupt database file detected.');

        final dbDir = dirname(path);
        final backupPath = join(dbDir, 'serenut_pos_upgrade_backup.db');
        final backupFile = File(backupPath);

        List<Map<String, dynamic>> pendingSales = [];
        List<Map<String, dynamic>> pendingTransactions = [];

        if (await backupFile.exists() && await _isDatabaseFile(backupPath)) {
          debugPrint(
              '[DatabaseManager] 📦 Attempting recovery from plain upgrade backup...');
          try {
            final backupDb = await openDatabase(backupPath,
                readOnly: true, singleInstance: false);
            try {
              pendingSales =
                  await backupDb.query('sales', where: 'is_synced = 0');
            } catch (e, st) {
              debugPrint('[DatabaseManager] ❌ Sales recovery query failed: $e');
              await TelemetryService()
                  .logError(e, st, context: 'db_recovery_sales_query');
            }
            try {
              pendingTransactions = await backupDb
                  .query('financial_transactions', where: 'is_synced = 0');
            } catch (e, st) {
              debugPrint(
                  '[DatabaseManager] ❌ Financial transactions recovery query failed: $e');
              await TelemetryService()
                  .logError(e, st, context: 'db_recovery_tx_query');
            }
            await backupDb.close();
            debugPrint(
                '[DatabaseManager] 📥 Recovered ${pendingSales.length} sales and ${pendingTransactions.length} pending transactions.');
          } catch (err, st) {
            debugPrint('[DatabaseManager] ❌ Recovery reading failed: $err');
            await TelemetryService()
                .logError(err, st, context: 'db_recovery_failed');
          }
        }

        debugPrint(
            '[DatabaseManager] 🗑️ Deleting encrypted/corrupted database file to recreate plain SQLite.');
        await dbFile.delete();

        // Recreate clean database and write back the recovered data
        try {
          final cleanDb = await openDatabase(
            path,
            version: _databaseVersion,
            onCreate: _onCreate,
          );
          if (pendingSales.isNotEmpty || pendingTransactions.isNotEmpty) {
            debugPrint(
                '[DatabaseManager] 🔄 Replaying recovered pending queue into the new clean database...');
            await cleanDb.transaction((txn) async {
              for (final sale in pendingSales) {
                final cleanSale = Map<String, dynamic>.from(sale);
                cleanSale['is_synced'] = 0;
                await txn.insert('sales', cleanSale,
                    conflictAlgorithm: ConflictAlgorithm.replace);
              }
              for (final tx in pendingTransactions) {
                final cleanTx = Map<String, dynamic>.from(tx);
                cleanTx['is_synced'] = 0;
                await txn.insert('financial_transactions', cleanTx,
                    conflictAlgorithm: ConflictAlgorithm.replace);
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
          final tempDb =
              await openDatabase(path, readOnly: true, singleInstance: false);
          currentVersion = await tempDb.getVersion();
          await tempDb.close();
        } catch (e, st) {
          debugPrint(
              '[DatabaseManager] ⚠️ Pre-upgrade version check failed: $e');
          TelemetryService()
              .logError(e, st, context: 'db_pre_upgrade_version_check');
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
        onOpen: (db) async {
          // Sprint C - SQLite Corruption & Integrity Audit
          final integrity = await db.rawQuery('PRAGMA integrity_check;');
          if (integrity.first.values.first != 'ok') {
            throw Exception(
                'SQLite integrity check failed: \${integrity.first.values.first}');
          }
          final fkCheck = await db.rawQuery('PRAGMA foreign_key_check;');
          if (fkCheck.isNotEmpty) {
            throw Exception(
                'SQLite foreign key check failed for \${fkCheck.length} constraints.');
          }
        },
      );
      // Ensure default walk-in customer exists to satisfy FOREIGN KEY constraint for anonymous sales
      try {
        await db.insert(
            'customers',
            {
              'id': '',
              'name': 'Peşin Müşteri',
              'email': '',
              'phone': '',
              'balance': 0.0,
              'status': 'active',
              'created_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore);
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
              WHEN type = 'manual_debt' THEN amount
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
      final isDecryptionError =
          e.toString().contains('file is not a database') ||
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
          debugPrint(
              '[DatabaseManager] ❌ Self-heal re-open failed after decryption error: $e');
          TelemetryService()
              .logError(e, st, context: 'db_selfheal_reopen_failed');
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
    await DatabaseSchema.createTables(db);
    await DatabaseTriggers.createTriggers(db);
    await _insertDefaultData(db);
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    await DatabaseMigrations.onUpgrade(db, oldVersion, newVersion);
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
      final backupFile =
          File(join(dirname(path), 'serenut_pos_upgrade_backup.db'));
      if (await backupFile.exists()) {
        await backupFile.delete();
      }
      final backupWal =
          File(join(dirname(path), 'serenut_pos_upgrade_backup.db-wal'));
      if (await backupWal.exists()) {
        await backupWal.delete();
      }
      final backupShm =
          File(join(dirname(path), 'serenut_pos_upgrade_backup.db-shm'));
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
