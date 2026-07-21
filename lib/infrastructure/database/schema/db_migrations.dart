// lib/infrastructure/database/schema/db_migrations.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:serenutos/config/utils.dart';

class DatabaseMigrations {
  /// Handle database upgrades
  static Future<void> onUpgrade(
      Database db, int oldVersion, int newVersion) async {
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

    try {
      await db.transaction((txn) async {
        void handleMigrationError(dynamic e, int version) {
          debugPrint('Migration warning/error at version $version: $e');
          final msg = e.toString().toLowerCase();
          if (!msg.contains('duplicate column') &&
              !msg.contains('already exists') &&
              !msg.contains('no such table') &&
              !msg.contains('no such column')) {
            throw e;
          }
        }

        if (oldVersion < 4) {
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_sales_created ON sales(created_at)');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_ft_created ON financial_transactions(created_at)');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)');
          await txn.insert('app_migration_history', {
            'version': 4,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 5) {
          await txn
              .execute('ALTER TABLE sales ADD COLUMN idempotency_key TEXT');
          await txn.execute(
              'ALTER TABLE sales ADD COLUMN is_synced INTEGER DEFAULT 0');
          await txn.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_idempotency ON sales(idempotency_key)');
          await txn.insert('app_migration_history', {
            'version': 5,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 6) {
          try {
            await txn.execute('ALTER TABLE products ADD COLUMN image_url TEXT');
          } catch (e) {
            handleMigrationError(e, 6);
          }
          await txn.insert('app_migration_history', {
            'version': 6,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 7) {
          try {
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_sales_synced ON sales(is_synced)');
          } catch (e) {
            handleMigrationError(e, 7);
          }
          try {
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items(product_id)');
          } catch (e) {
            handleMigrationError(e, 7);
          }
          try {
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_ft_reference ON financial_transactions(reference_id)');
          } catch (e) {
            handleMigrationError(e, 7);
          }
          try {
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action)');
          } catch (e) {
            handleMigrationError(e, 7);
          }
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
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_sms_logs_status ON sms_logs(status)');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_sms_logs_created ON sms_logs(created_at)');
          } catch (e) {
            handleMigrationError(e, 8);
          }
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
            await txn.execute(
                'ALTER TABLE financial_transactions ADD COLUMN logical_clock INTEGER NOT NULL DEFAULT 0');
            await txn.execute(
                'ALTER TABLE financial_transactions ADD COLUMN device_id TEXT');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_ft_logical ON financial_transactions(logical_clock, device_id)');
          } catch (e) {
            handleMigrationError(e, 12);
          }
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
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_audit_events_timestamp ON audit_events(timestamp)');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_audit_events_type ON audit_events(event_type)');

            await txn.execute(
                'ALTER TABLE products ADD COLUMN is_deleted INTEGER DEFAULT 0');
            await txn
                .execute('ALTER TABLE products ADD COLUMN deleted_at TEXT');
            await txn
                .execute('ALTER TABLE products ADD COLUMN deleted_by TEXT');

            await txn.execute(
                'ALTER TABLE customers ADD COLUMN is_deleted INTEGER DEFAULT 0');
            await txn
                .execute('ALTER TABLE customers ADD COLUMN deleted_at TEXT');
            await txn
                .execute('ALTER TABLE customers ADD COLUMN deleted_by TEXT');

            await txn.execute(
                'ALTER TABLE sales ADD COLUMN is_deleted INTEGER DEFAULT 0');
            await txn.execute('ALTER TABLE sales ADD COLUMN deleted_at TEXT');
            await txn.execute('ALTER TABLE sales ADD COLUMN deleted_by TEXT');

            await txn.execute(
                'ALTER TABLE orders ADD COLUMN is_deleted INTEGER DEFAULT 0');
            await txn.execute('ALTER TABLE orders ADD COLUMN deleted_at TEXT');
            await txn.execute('ALTER TABLE orders ADD COLUMN deleted_by TEXT');

            await txn.execute(
                'ALTER TABLE financial_transactions ADD COLUMN is_deleted INTEGER DEFAULT 0');
            await txn.execute(
                'ALTER TABLE financial_transactions ADD COLUMN deleted_at TEXT');
            await txn.execute(
                'ALTER TABLE financial_transactions ADD COLUMN deleted_by TEXT');
          } catch (e) {
            handleMigrationError(e, 13);
          }
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
          } catch (e) {
            handleMigrationError(e, 15);
          }
          await txn.insert('app_migration_history', {
            'version': 15,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 16) {
          try {
            await txn.execute(
                'ALTER TABLE settings ADD COLUMN owner_name TEXT DEFAULT ""');
            await txn
                .execute('ALTER TABLE settings ADD COLUMN business_email TEXT');
            await txn.execute(
                'ALTER TABLE settings ADD COLUMN business_city TEXT DEFAULT ""');
            await txn.execute(
                'ALTER TABLE settings ADD COLUMN business_district TEXT DEFAULT ""');
            await txn.execute(
                'ALTER TABLE settings ADD COLUMN business_type TEXT DEFAULT ""');
          } catch (e) {
            handleMigrationError(e, 16);
          }
          await txn.insert('app_migration_history', {
            'version': 16,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 17) {
          try {
            await txn.execute(
                'ALTER TABLE products ADD COLUMN is_synced INTEGER DEFAULT 1');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_products_synced ON products(is_synced)');
          } catch (e) {
            handleMigrationError(e, 17);
          }
          await txn.insert('app_migration_history', {
            'version': 17,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 18) {
          for (final col in [
            'ALTER TABLE users ADD COLUMN username TEXT',
            'ALTER TABLE users ADD COLUMN pin_hash TEXT',
            'ALTER TABLE users ADD COLUMN business_code TEXT',
            'CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username ON users(business_code, username) WHERE username IS NOT NULL',
            'ALTER TABLE users ADD COLUMN device_token_version INTEGER DEFAULT 1',
          ]) {
            try {
              await txn.execute(col);
            } catch (e) {
              handleMigrationError(e, 18);
            }
          }
          await txn.insert('app_migration_history', {
            'version': 18,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 19) {
          try {
            await txn.execute(
                'ALTER TABLE financial_transactions ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 1');
          } catch (e) {
            handleMigrationError(e, 19);
          }
          try {
            await txn.execute(
                'ALTER TABLE customers ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 1');
          } catch (e) {
            handleMigrationError(e, 19);
          }
          try {
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_ft_customer_id ON financial_transactions(customer_id)');
          } catch (e) {
            handleMigrationError(e, 19);
          }
          await txn.insert('app_migration_history', {
            'version': 19,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 20) {
          try {
            await txn
                .execute('ALTER TABLE settings ADD COLUMN license_token TEXT');
            await txn.execute(
                'ALTER TABLE settings ADD COLUMN last_system_time TEXT');
            await txn.execute(
                'ALTER TABLE settings ADD COLUMN max_timestamp_seen TEXT');
          } catch (e) {
            handleMigrationError(e, 20);
          }
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
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_print_queue_status ON print_queue(status)');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_print_queue_created ON print_queue(created_at)');
          } catch (e) {
            handleMigrationError(e, 21);
          }
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
              handleMigrationError(e, 22);
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
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id)');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at)');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id)');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id)');
          } catch (e) {
            handleMigrationError(e, 23);
          }
          await txn.insert('app_migration_history', {
            'version': 23,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 24) {
          for (final col in [
            'ALTER TABLE settings ADD COLUMN sms_sim_subscription_id INTEGER',
            'ALTER TABLE settings ADD COLUMN sms_sim_slot_index INTEGER',
            'ALTER TABLE settings ADD COLUMN sms_monthly_limit INTEGER',
            'ALTER TABLE settings ADD COLUMN sms_sent_this_month INTEGER NOT NULL DEFAULT 0',
            'ALTER TABLE settings ADD COLUMN sms_limit_reset_month INTEGER',
          ]) {
            try {
              await txn.execute(col);
            } catch (e) {
              handleMigrationError(e, 24);
            }
          }
          await txn.insert('app_migration_history', {
            'version': 24,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 25) {
          for (final col in [
            'ALTER TABLE users ADD COLUMN failed_pin_attempts INTEGER NOT NULL DEFAULT 0',
            'ALTER TABLE users ADD COLUMN locked_until TEXT',
          ]) {
            try {
              await txn.execute(col);
            } catch (e) {
              handleMigrationError(e, 25);
            }
          }
          await txn.insert('app_migration_history', {
            'version': 25,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 26) {
          try {
            await txn.execute(
                'ALTER TABLE business_profile ADD COLUMN version INTEGER NOT NULL DEFAULT 1');
          } catch (e) {
            handleMigrationError(e, 26);
          }
          await txn.insert('app_migration_history', {
            'version': 26,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 27) {
          try {
            await txn.execute('ALTER TABLE users ADD COLUMN permissions TEXT');
          } catch (e) {
            handleMigrationError(e, 27);
          }
          await txn.insert('app_migration_history', {
            'version': 27,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 28) {
          try {
            await txn.execute(
                'ALTER TABLE sales ADD COLUMN entitlement_snapshot TEXT');
          } catch (e) {
            handleMigrationError(e, 28);
          }
          await txn.insert('app_migration_history', {
            'version': 28,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 29) {
          try {
            final customers = await txn.query('customers');
            for (final cust in customers) {
              final id = cust['id'] as String;
              final name = cust['name'] as String? ?? '';
              final email = cust['email'] as String? ?? '';
              await txn.update(
                'customers',
                {
                  'normalized_name': name.normalizeTurkish,
                  'normalized_email': email.toLowerCase(),
                },
                where: 'id = ?',
                whereArgs: [id],
              );
            }
          } catch (e) {
            handleMigrationError(e, 29);
          }
          await txn.insert('app_migration_history', {
            'version': 29,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 30) {
          try {
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_customers_normalized_name ON customers(normalized_name COLLATE NOCASE)');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_customers_normalized_email ON customers(normalized_email COLLATE NOCASE)');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers(phone COLLATE NOCASE)');

            // Database-level partial unique indexes to prevent duplicate ledger transactions
            await txn.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_ft_unique_cancellation ON financial_transactions(reference_id) WHERE type = 'cancellation'");
            await txn.execute(
                "CREATE UNIQUE INDEX IF NOT EXISTS idx_ft_unique_sale ON financial_transactions(reference_id) WHERE type = 'sale'");

            // Run ANALYZE to update query planner stats for the new indexes
            await txn.execute('ANALYZE');
          } catch (e) {
            handleMigrationError(e, 30);
          }
          await txn.insert('app_migration_history', {
            'version': 30,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 31) {
          try {
            await txn.execute(
                "ALTER TABLE products ADD COLUMN sale_type TEXT NOT NULL DEFAULT 'piece'");
            await txn.execute(
                'ALTER TABLE products ADD COLUMN minimum_weight_grams INTEGER NOT NULL DEFAULT 20');
          } catch (e) {
            handleMigrationError(e, 31);
          }
          await txn.insert('app_migration_history', {
            'version': 31,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
      });
    } catch (err) {
      // Log migration error to history outside transaction before throwing
      try {
        await db.insert('app_migration_history', {
          'version': newVersion,
          'migrated_at': DateTime.now().toIso8601String(),
          'status': 'failed',
          'error_message': err.toString()
        });
      } catch (_) {}
      rethrow;
    }

    // ── One-time SharedPreferences → SQLite migration (runs after the transaction) ──
    // This cannot run inside a transaction because SharedPreferences is async/external.
    if (oldVersion < 22) {
      await _migrateSharedPrefsToSqlite(db);
    }
  }

  /// Migrate 9 settings fields and legacy SharedPreferences audit logs to SQLite.
  /// Runs exactly once when upgrading from a version < 22.
  static Future<void> _migrateSharedPrefsToSqlite(Database db) async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ── 1. Migrate 9 settings values ──────────────────────────────────────────
      final settingsRows = await db.query('settings', limit: 1);
      if (settingsRows.isNotEmpty) {
        final existingId = settingsRows.first['id'];
        await db.update(
            'settings',
            {
              'sound_notification_enabled':
                  (prefs.getBool('sound_notification_enabled') ?? false)
                      ? 1
                      : 0,
              'sms_auto_debt_reminder_enabled':
                  (prefs.getBool('sms_auto_debt_reminder_enabled') ?? false)
                      ? 1
                      : 0,
              'sms_auto_debt_reminder_days':
                  prefs.getInt('sms_auto_debt_reminder_days') ?? 15,
              'sms_auto_debt_reminder_min_amount':
                  prefs.getDouble('sms_auto_debt_reminder_min_amount') ?? 100.0,
              'label_printer_enabled':
                  (prefs.getBool('label_printer_enabled') ?? false) ? 1 : 0,
              'label_printer_ip': prefs.getString('label_printer_ip') ?? '',
              'label_printer_port': int.tryParse(
                      prefs.getString('label_printer_port') ?? '9100') ??
                  9100,
              'label_printer_copies': prefs.getInt('label_printer_copies') ?? 1,
              'admin_pin_code': prefs.getString('admin_pin_code'),
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [existingId]);
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
            await db.insert(
                'audit_logs',
                {
                  'id': logId,
                  'user_id': 'system',
                  'user_name': 'Migrated (SharedPrefs)',
                  'action': map['action'] ?? 'unknown',
                  'details': details,
                  'created_at':
                      map['timestamp'] ?? DateTime.now().toIso8601String(),
                },
                conflictAlgorithm: ConflictAlgorithm.ignore);
          } catch (_) {
            // Malformed entry — skip
          }
        }
        // Remove migrated audit log key
        await prefs.remove('serenut_audit_logs');
        debugPrint(
            '[DB Migration v22] Migrated ${rawLogs.length} SharedPreferences audit logs to SQLite audit_logs.');
      }

      debugPrint(
          '[DB Migration v22] SharedPreferences → SQLite migration complete.');
    } catch (e) {
      debugPrint('[DB Migration v22] Migration failed (non-fatal): $e');
    }
  }
}
