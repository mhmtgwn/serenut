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
        if (oldVersion < 32) {
          try {
            await txn.execute(
                'ALTER TABLE orders ADD COLUMN is_synced INTEGER NOT NULL DEFAULT 0');
            await txn.execute(
                'CREATE INDEX IF NOT EXISTS idx_orders_is_synced ON orders(is_synced)');
          } catch (e) {
            handleMigrationError(e, 32);
          }
          await txn.insert('app_migration_history', {
            'version': 32,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 33) {
          await txn.execute('''CREATE TABLE IF NOT EXISTS sync_outbox_v4 (
            id INTEGER PRIMARY KEY AUTOINCREMENT, mutation_id TEXT NOT NULL UNIQUE,
            entity_type TEXT NOT NULL, entity_id TEXT NOT NULL, operation TEXT NOT NULL,
            payload TEXT NOT NULL, state TEXT NOT NULL, attempts INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL)''');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_sync_outbox_v4_state ON sync_outbox_v4(state, id)');
          await txn.execute(
              'CREATE TABLE IF NOT EXISTS sync_cursor_v4 (key TEXT PRIMARY KEY, cursor INTEGER NOT NULL)');
          await txn.insert('app_migration_history', {
            'version': 33,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 34) {
          await txn
              .execute('''CREATE TABLE IF NOT EXISTS terminal_payment_intents (
            id TEXT PRIMARY KEY, idempotency_key TEXT NOT NULL UNIQUE,
            terminal_transaction_id TEXT NOT NULL UNIQUE, amount REAL NOT NULL,
            currency TEXT NOT NULL, authorization_code TEXT, state TEXT NOT NULL,
            context_type TEXT NOT NULL, context_id TEXT, error_message TEXT,
            created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_terminal_payment_intents_state ON terminal_payment_intents(state, updated_at)');
          await txn.insert('app_migration_history', {
            'version': 34,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 35) {
          try {
            await txn.execute(
                'ALTER TABLE sync_outbox_v4 ADD COLUMN base_revision INTEGER NOT NULL DEFAULT 0');
          } catch (e) {
            handleMigrationError(e, 35);
          }
          await txn.insert('app_migration_history', {
            'version': 35,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 36) {
          await txn.execute('''CREATE TABLE IF NOT EXISTS sync_conflicts_v4 (
            mutation_id TEXT PRIMARY KEY, entity_type TEXT NOT NULL,
            entity_id TEXT NOT NULL, server_revision INTEGER NOT NULL,
            detected_at TEXT NOT NULL, resolved_at TEXT)''');
          await txn.insert('app_migration_history', {
            'version': 36,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 37) {
          final ledgerTable = await txn.rawQuery(
              "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'financial_transactions'");
          if (ledgerTable.isNotEmpty) {
            final ledgerColumns = (await txn
                    .rawQuery('PRAGMA table_info(financial_transactions)'))
                .map((row) => row['name']?.toString())
                .toSet();
            for (final column in const {
              'description': 'TEXT',
              'payment_method': 'TEXT',
            }.entries) {
              if (!ledgerColumns.contains(column.key)) {
                await txn.execute(
                    'ALTER TABLE financial_transactions ADD COLUMN ${column.key} ${column.value}');
              }
            }
          }
          await txn.insert('app_migration_history', {
            'version': 37,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 39) {
          final productColumns =
              (await txn.rawQuery('PRAGMA table_info(products)'))
                  .map((row) => row['name']?.toString())
                  .toSet();
          for (final table in const ['sale_items', 'order_items']) {
            final tableInfo = await txn.rawQuery('PRAGMA table_info($table)');
            if (tableInfo.isEmpty) continue;
            final columns =
                tableInfo.map((row) => row['name']?.toString()).toSet();
            if (!columns.contains('product_name')) {
              await txn
                  .execute('ALTER TABLE $table ADD COLUMN product_name TEXT');
            }
            if (productColumns.contains('name') &&
                productColumns.contains('id')) {
              await txn.execute('''
                UPDATE $table
                   SET product_name = (
                     SELECT p.name FROM products p
                      WHERE p.id = $table.product_id
                   )
                 WHERE product_name IS NULL OR product_name = ''
              ''');
            }
          }
          await txn.insert('app_migration_history', {
            'version': 39,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 40) {
          final columns = (await txn.rawQuery('PRAGMA table_info(settings)'))
              .map((row) => row['name']?.toString())
              .toSet();
          const additions = <String, String>{
            'print_logo': 'INTEGER NOT NULL DEFAULT 1',
            'print_customer_balance': 'INTEGER NOT NULL DEFAULT 1',
            'receipt_font': "TEXT NOT NULL DEFAULT 'a'",
            'receipt_text_size': "TEXT NOT NULL DEFAULT 'normal'",
            'receipt_item_layout': "TEXT NOT NULL DEFAULT 'auto'",
            'receipt_footer_text':
                "TEXT NOT NULL DEFAULT 'Bizi tercih ettiğiniz için teşekkür ederiz!'",
            'receipt_feed_lines': 'INTEGER NOT NULL DEFAULT 2',
            'auto_cut_receipt': 'INTEGER NOT NULL DEFAULT 1',
            'open_cash_drawer': 'INTEGER NOT NULL DEFAULT 1',
          };
          for (final column in additions.entries) {
            if (!columns.contains(column.key)) {
              await txn.execute(
                  'ALTER TABLE settings ADD COLUMN ${column.key} ${column.value}');
            }
          }
          await txn.insert('app_migration_history', {
            'version': 40,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 41) {
          final columns = (await txn.rawQuery('PRAGMA table_info(products)'))
              .map((row) => row['name']?.toString())
              .toSet();
          if (!columns.contains('purchase_price')) {
            await txn.execute(
                'ALTER TABLE products ADD COLUMN purchase_price REAL NOT NULL DEFAULT 0');
          }
          if (!columns.contains('min_stock')) {
            await txn.execute(
                'ALTER TABLE products ADD COLUMN min_stock INTEGER NOT NULL DEFAULT 5');
          }
          await txn.insert('app_migration_history', {
            'version': 41,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 42) {
          final columns =
              (await txn.rawQuery('PRAGMA table_info(audit_events)'))
                  .map((row) => row['name']?.toString())
                  .toSet();
          if (!columns.contains('previous_hash')) {
            await txn.execute(
                'ALTER TABLE audit_events ADD COLUMN previous_hash TEXT');
          }
          if (!columns.contains('record_hash')) {
            await txn.execute(
                'ALTER TABLE audit_events ADD COLUMN record_hash TEXT');
          }
          await txn.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_audit_events_record_hash ON audit_events(record_hash) WHERE record_hash IS NOT NULL');
          await txn.insert('app_migration_history', {
            'version': 42,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 43) {
          final columns = (await txn.rawQuery('PRAGMA table_info(products)'))
              .map((row) => row['name']?.toString())
              .toSet();
          const additions = <String, String>{
            'brand': "TEXT NOT NULL DEFAULT ''",
            'unit': "TEXT NOT NULL DEFAULT 'adet'",
            'shelf_code': "TEXT NOT NULL DEFAULT ''",
          };
          for (final addition in additions.entries) {
            if (!columns.contains(addition.key)) {
              await txn.execute(
                  'ALTER TABLE products ADD COLUMN ${addition.key} ${addition.value}');
            }
          }
          await txn.insert('app_migration_history', {
            'version': 43,
            'migrated_at': DateTime.now().toUtc().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 44) {
          for (final statement in [
            "ALTER TABLE settings ADD COLUMN label_printer_language TEXT NOT NULL DEFAULT 'tspl'",
            'ALTER TABLE settings ADD COLUMN label_printer_name TEXT',
            'ALTER TABLE settings ADD COLUMN label_width_mm INTEGER NOT NULL DEFAULT 50',
            'ALTER TABLE settings ADD COLUMN label_height_mm INTEGER NOT NULL DEFAULT 30',
            'ALTER TABLE settings ADD COLUMN label_gap_mm INTEGER NOT NULL DEFAULT 2',
            'ALTER TABLE settings ADD COLUMN label_dpi INTEGER NOT NULL DEFAULT 203',
          ]) {
            try {
              await txn.execute(statement);
            } catch (e) {
              handleMigrationError(e, 44);
            }
          }
          await txn.insert('app_migration_history', {
            'version': 44,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 45) {
          for (final statement in [
            'ALTER TABLE settings ADD COLUMN label_show_brand INTEGER NOT NULL DEFAULT 1',
            'ALTER TABLE settings ADD COLUMN label_show_vat INTEGER NOT NULL DEFAULT 1',
            "ALTER TABLE settings ADD COLUMN label_font_size TEXT NOT NULL DEFAULT 'Orta'",
            'ALTER TABLE settings ADD COLUMN label_order_show_business_name INTEGER NOT NULL DEFAULT 1',
            'ALTER TABLE settings ADD COLUMN label_order_show_customer_name INTEGER NOT NULL DEFAULT 1',
            'ALTER TABLE settings ADD COLUMN label_order_show_order_no INTEGER NOT NULL DEFAULT 1',
            'ALTER TABLE settings ADD COLUMN label_order_show_date INTEGER NOT NULL DEFAULT 1',
            'ALTER TABLE settings ADD COLUMN label_order_show_total_amount INTEGER NOT NULL DEFAULT 1',
            'ALTER TABLE settings ADD COLUMN label_order_show_items_count INTEGER NOT NULL DEFAULT 1',
            "ALTER TABLE settings ADD COLUMN label_order_font_size TEXT NOT NULL DEFAULT 'Orta'",
          ]) {
            try {
              await txn.execute(statement);
            } catch (e) {
              handleMigrationError(e, 45);
            }
          }
          await txn.insert('app_migration_history', {
            'version': 45,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 46) {
          for (final statement in [
            'ALTER TABLE settings ADD COLUMN label_show_business_name INTEGER NOT NULL DEFAULT 1',
            'ALTER TABLE settings ADD COLUMN label_show_barcode INTEGER NOT NULL DEFAULT 1',
            'ALTER TABLE settings ADD COLUMN label_show_price INTEGER NOT NULL DEFAULT 1',
            "ALTER TABLE settings ADD COLUMN active_receipt_printer_id TEXT NOT NULL DEFAULT 'receipt-printer-primary'",
            "ALTER TABLE settings ADD COLUMN active_label_printer_id TEXT NOT NULL DEFAULT 'label-printer-primary'",
            "ALTER TABLE print_queue ADD COLUMN purpose TEXT NOT NULL DEFAULT 'receipt'",
            "ALTER TABLE print_queue ADD COLUMN device_id TEXT NOT NULL DEFAULT 'receipt-printer-primary'",
          ]) {
            try {
              await txn.execute(statement);
            } catch (e) {
              handleMigrationError(e, 46);
            }
          }
          await txn.execute(
            'UPDATE settings SET label_show_business_name = print_logo, label_show_barcode = print_barcode, label_show_price = print_product_details',
          );
          await txn.insert('app_migration_history', {
            'version': 46,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 47 && newVersion >= 47) {
          await _createPrintingV2Tables(txn);
          await _seedLegacyPrintingProfiles(txn);
          await txn.insert('app_migration_history', {
            'version': 47,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 48 && newVersion >= 48) {
          for (final statement in [
            'ALTER TABLE sales ADD COLUMN refunded_amount REAL NOT NULL DEFAULT 0',
            'ALTER TABLE sales ADD COLUMN fsm_state TEXT NOT NULL DEFAULT \'completed\'',
          ]) {
            try {
              await txn.execute(statement);
            } catch (e) {
              handleMigrationError(e, 48);
            }
          }
          await txn.execute('''CREATE TABLE IF NOT EXISTS refunds (
            id TEXT PRIMARY KEY, sale_id TEXT NOT NULL, amount REAL NOT NULL CHECK(amount>0),
            refund_method TEXT NOT NULL, external_reference TEXT, reason TEXT NOT NULL,
            status TEXT NOT NULL DEFAULT 'completed', created_at TEXT NOT NULL,
            FOREIGN KEY(sale_id) REFERENCES sales(id) ON DELETE RESTRICT)''');
          await txn.execute('''CREATE TABLE IF NOT EXISTS refund_items (
            id TEXT PRIMARY KEY, refund_id TEXT NOT NULL, sale_item_id TEXT NOT NULL,
            product_id TEXT NOT NULL, quantity INTEGER NOT NULL CHECK(quantity>0),
            unit_refund_amount REAL NOT NULL, subtotal REAL NOT NULL,
            UNIQUE(refund_id,sale_item_id),
            FOREIGN KEY(refund_id) REFERENCES refunds(id) ON DELETE RESTRICT,
            FOREIGN KEY(sale_item_id) REFERENCES sale_items(id) ON DELETE RESTRICT,
            FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE RESTRICT)''');
          await txn.execute(
              'CREATE INDEX IF NOT EXISTS idx_refund_items_sale_item ON refund_items(sale_item_id)');
          await txn.insert('app_migration_history', {
            'version': 48,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 49 && newVersion >= 49) {
          try {
            await txn
                .execute('ALTER TABLE orders ADD COLUMN order_number TEXT');
          } catch (e) {
            handleMigrationError(e, 49);
          }
          final orders = await txn.query('orders',
              columns: const ['id'], orderBy: 'created_at ASC, id ASC');
          for (var index = 0; index < orders.length; index++) {
            await txn.update(
              'orders',
              {'order_number': 'SP-${(index + 1).toString().padLeft(6, '0')}'},
              where: 'id = ?',
              whereArgs: [orders[index]['id']],
            );
          }
          await txn.execute(
              'CREATE UNIQUE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number)');
          await txn
              .execute('''CREATE TABLE IF NOT EXISTS order_number_sequence (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            next_value INTEGER NOT NULL CHECK (next_value > 0)
          )''');
          await txn.insert(
            'order_number_sequence',
            {'id': 1, 'next_value': orders.length + 1},
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          await txn.insert('app_migration_history', {
            'version': 49,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 50 && newVersion >= 50) {
          try {
            await txn.execute(
                'ALTER TABLE settings ADD COLUMN label_auto_detect_gap INTEGER NOT NULL DEFAULT 0');
          } catch (e) {
            handleMigrationError(e, 50);
          }
          await txn.insert('app_migration_history', {
            'version': 50,
            'migrated_at': DateTime.now().toIso8601String(),
            'status': 'success'
          });
        }
        if (oldVersion < 51 && newVersion >= 51) {
          await _mergeLegacyReadyCatalogProducts(txn);
          await txn.insert('app_migration_history', {
            'version': 51,
            'migrated_at': DateTime.now().toIso8601String(),
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
    if (oldVersion < 47 && newVersion >= 47) {
      await _migratePrintingDevicesAndRoutes(db);
    }
  }

  /// Merges products duplicated by the August 2026 ready catalogue, whose
  /// numeric Excel barcode column dropped the leading zero from EAN-8 values.
  /// The valid eight-digit identity is retained. Historical references are
  /// repointed before the malformed seven-digit alias is tombstoned.
  static Future<void> _mergeLegacyReadyCatalogProducts(Transaction txn) async {
    const fields = <String>[
      'name',
      'description',
      'price',
      'purchase_price',
      'quantity',
      'min_stock',
      'brand',
      'unit',
      'shelf_code',
      'category',
      'vat',
      'image_url',
      'sale_type',
      'minimum_weight_grams',
      'created_at',
      'updated_at',
    ];
    final projections = fields
        .expand((field) => [
              'a.$field AS alias_$field',
              'c.$field AS canonical_$field',
            ])
        .join(',');
    final pairs = await txn.rawQuery('''
      SELECT a.id AS alias_id, c.id AS canonical_id, $projections
      FROM products a
      JOIN products c ON c.id = '0' || a.id
      WHERE length(a.id) = 7
        AND length(c.id) = 8
        AND a.id NOT GLOB '*[^0-9]*'
        AND c.id NOT GLOB '*[^0-9]*'
        AND a.is_active = 1 AND COALESCE(a.is_deleted, 0) = 0
        AND c.is_active = 1 AND COALESCE(c.is_deleted, 0) = 0
        AND lower(trim(a.name)) = lower(trim(c.name))
        AND abs(a.price - c.price) <= 0.01
      ORDER BY c.id
    ''');
    if (pairs.isEmpty) return;

    await txn
        .execute('''CREATE TEMP TABLE IF NOT EXISTS product_identity_merge (
      alias_id TEXT PRIMARY KEY,
      canonical_id TEXT NOT NULL
    )''');
    await txn.delete('product_identity_merge');
    final mapBatch = txn.batch();
    for (final pair in pairs) {
      mapBatch.insert('product_identity_merge', {
        'alias_id': pair['alias_id'],
        'canonical_id': pair['canonical_id'],
      });
    }
    await mapBatch.commit(noResult: true);

    for (final table in const ['sale_items', 'order_items', 'refund_items']) {
      await txn.rawUpdate('''
        UPDATE $table
        SET product_id = (
          SELECT canonical_id FROM product_identity_merge
          WHERE alias_id = $table.product_id
        )
        WHERE EXISTS (
          SELECT 1 FROM product_identity_merge
          WHERE alias_id = $table.product_id
        )
      ''');
    }

    final now = DateTime.now().toUtc().toIso8601String();
    final mergeBatch = txn.batch();
    for (final pair in pairs) {
      final aliasId = pair['alias_id']! as String;
      final canonicalId = pair['canonical_id']! as String;
      final aliasUpdated = pair['alias_updated_at']?.toString() ?? '';
      final canonicalUpdated = pair['canonical_updated_at']?.toString() ?? '';
      final preferAlias = aliasUpdated.compareTo(canonicalUpdated) > 0;
      Object? chosen(String field) =>
          pair['${preferAlias ? 'alias' : 'canonical'}_$field'];
      final canonicalImage =
          pair['canonical_image_url']?.toString().trim() ?? '';
      final aliasImage = pair['alias_image_url']?.toString().trim() ?? '';
      final merged = <String, Object?>{
        for (final field in fields)
          if (field != 'created_at' &&
              field != 'updated_at' &&
              field != 'image_url')
            field: chosen(field),
        'image_url': canonicalImage.isNotEmpty
            ? canonicalImage
            : (aliasImage.isNotEmpty ? aliasImage : null),
        'is_active': 1,
        'is_deleted': 0,
        'deleted_at': null,
        'deleted_by': null,
        'is_synced': 0,
        'updated_at': now,
      };
      mergeBatch.update('products', merged,
          where: 'id = ?', whereArgs: [canonicalId]);
      mergeBatch.update(
        'products',
        {
          'is_active': 0,
          'is_deleted': 1,
          'deleted_at': now,
          'deleted_by': 'migration-v51',
          'is_synced': 0,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [aliasId],
      );
    }
    await mergeBatch.commit(noResult: true);

    await txn.rawDelete('''
      DELETE FROM sync_outbox_v4
      WHERE state = 'PENDING' AND entity_type = 'product'
        AND (entity_id IN (SELECT alias_id FROM product_identity_merge)
          OR entity_id IN (SELECT canonical_id FROM product_identity_merge))
    ''');
    await txn.execute('DROP TABLE product_identity_merge');
  }

  static Future<void> _migratePrintingDevicesAndRoutes(Database db) async {
    final settingsRows = await db.query('settings', limit: 1);
    if (settingsRows.isEmpty) return;
    final settings = settingsRows.first;
    final now = DateTime.now().toIso8601String();
    final devices = <Map<String, Object?>>[];
    // Database migrations must be deterministic and platform-independent.
    // SharedPreferences hardware-registry import belongs to application
    // bootstrap (HardwareDevicesNotifier), before PrintingRuntime starts.
    final printerName = settings['printer_name'] as String? ?? '';
    final printerIp = settings['printer_ip'] as String? ?? '';
    if (printerName.isNotEmpty || printerIp.isNotEmpty) {
      devices.add(_printingDeviceRow(
        id: settings['active_receipt_printer_id'] as String? ??
            'receipt-printer-primary',
        name: printerName.isEmpty ? 'Fiş Yazıcısı' : printerName,
        isLabel: false,
        connection: printerIp.isEmpty ? 'windows' : 'tcp',
        config: {
          'printerName': printerName,
          'host': printerIp,
          'port': settings['printer_port'] ?? 9100,
          'paperWidth': settings['paper_width'] ?? 58,
        },
        enabled: true,
        now: now,
      ));
    }
    if (settings['label_printer_enabled'] == 1) {
      final printerName = settings['label_printer_name'] as String? ?? '';
      final printerIp = settings['label_printer_ip'] as String? ?? '';
      devices.add(_printingDeviceRow(
        id: settings['active_label_printer_id'] as String? ??
            'label-printer-primary',
        name: printerName.isEmpty ? 'Etiket Yazıcısı' : printerName,
        isLabel: true,
        connection: printerIp.isEmpty ? 'windows' : 'tcp',
        config: {
          'printerName': printerName,
          'host': printerIp,
          'port': settings['label_printer_port'] ?? 9100,
          'labelWidthMm': settings['label_width_mm'] ?? 50,
          'labelHeightMm': settings['label_height_mm'] ?? 30,
          'labelGapMm': settings['label_gap_mm'] ?? 2,
          'dpi': settings['label_dpi'] ?? 203,
        },
        enabled: true,
        now: now,
      ));
    }

    await db.transaction((txn) async {
      for (final device in devices) {
        await txn.insert('printer_devices', device,
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      final receiptId = settings['active_receipt_printer_id'] as String?;
      final labelId = settings['active_label_printer_id'] as String?;
      final knownIds = devices.map((row) => row['id']).toSet();
      if (receiptId != null && knownIds.contains(receiptId)) {
        await txn.insert(
          'printer_routes',
          {
            'kind': 'receipt',
            'device_id': receiptId,
            'design_profile_id': 'receipt-default-v1',
            'updated_at': now,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      if (labelId != null && knownIds.contains(labelId)) {
        for (final route in const [
          ['productLabel', 'product-label-default-v1'],
          ['orderLabel', 'order-label-default-v1'],
        ]) {
          await txn.insert(
            'printer_routes',
            {
              'kind': route[0],
              'device_id': labelId,
              'design_profile_id': route[1],
              'updated_at': now,
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
        }
      }
    });
    await _migrateLegacyPrintJobs(db);
  }

  static Future<void> _migrateLegacyPrintJobs(Database db) async {
    final table = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      ['print_queue'],
    );
    if (table.isEmpty) return;
    final legacyJobs = await db.query('print_queue', orderBy: 'created_at ASC');
    if (legacyJobs.isEmpty) return;

    await db.transaction((txn) async {
      for (final legacy in legacyJobs) {
        final rawKind = legacy['purpose'] as String? ?? 'receipt';
        final kind = switch (rawKind) {
          'productLabel' => 'productLabel',
          'orderLabel' => 'orderLabel',
          _ => 'receipt',
        };
        final designId = switch (kind) {
          'productLabel' => 'product-label-default-v1',
          'orderLabel' => 'order-label-default-v1',
          _ => 'receipt-default-v1',
        };
        final profiles = await txn.query(
          'print_design_profiles',
          where: 'id = ?',
          whereArgs: [designId],
          limit: 1,
        );
        final deviceId = legacy['device_id'] as String? ??
            (kind == 'receipt'
                ? 'receipt-printer-primary'
                : 'label-printer-primary');
        final devices = await txn.query(
          'printer_devices',
          columns: ['transport', 'transport_config_json', 'capabilities_json'],
          where: 'id = ?',
          whereArgs: [deviceId],
          limit: 1,
        );
        final legacyStatus = legacy['status'] as String? ?? 'pending';
        final retryCount = (legacy['retry_count'] as num?)?.toInt() ?? 0;
        final state = switch (legacyStatus) {
          'success' => 'delivered',
          'abandoned' => 'failed',
          'failed' when retryCount >= 5 => 'failed',
          'failed' => 'retryWait',
          // A process may have died after sending bytes. Retaining the job as
          // queued makes the ambiguity visible; the coordinator applies its
          // recovery policy instead of silently marking it successful.
          'printing' => 'queued',
          _ => 'queued',
        };
        final createdAt =
            legacy['created_at'] as String? ?? DateTime.now().toIso8601String();
        await txn.insert(
          'print_jobs',
          {
            'id': 'legacy-${legacy['id']}',
            'kind': kind,
            'payload_json': legacy['receipt_json'] as String? ?? '{}',
            'copies': 1,
            'design_profile_id': designId,
            'design_snapshot_json': profiles.isEmpty
                ? '{}'
                : profiles.first['definition_json'] as String,
            'device_id': deviceId,
            'transport_snapshot_json': devices.isEmpty
                ? '{}'
                : jsonEncode({
                    'kind': devices.first['transport'],
                    'config': jsonDecode(
                      devices.first['transport_config_json']! as String,
                    ),
                  }),
            'capability_snapshot_json': devices.isEmpty
                ? '{}'
                : devices.first['capabilities_json'] as String,
            'renderer_version': 'legacy-raw-v1',
            'state': state,
            'attempt_count': retryCount,
            'created_at': createdAt,
            'updated_at': DateTime.now().toIso8601String(),
            'next_attempt_at':
                state == 'retryWait' ? DateTime.now().toIso8601String() : null,
            'error_code': state == 'failed' ? 'legacy_abandoned' : null,
            'error_message': legacy['last_error'] as String?,
          },
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      await txn.update(
        'print_queue',
        {
          'status': 'abandoned',
          'last_error': 'Yeni yazdırma kuyruğuna taşındı (v47).',
        },
        where: 'status IN (?, ?, ?)',
        whereArgs: ['pending', 'printing', 'failed'],
      );
    });
  }

  static Map<String, Object?> _printingDeviceRow({
    required String id,
    required String name,
    required bool isLabel,
    required String connection,
    required Map<String, Object?> config,
    required bool enabled,
    required String now,
    String? lastTestedAt,
    bool? lastTestSucceeded,
    String? lastTestMessage,
  }) {
    final transport = switch (connection) {
      'embedded' => 'embedded',
      'windows' => 'windowsSpooler',
      'usb' => 'usb',
      'bluetooth' => 'bluetooth',
      _ => 'tcp',
    };
    final capabilities = isLabel
        ? {
            'dpi': config['dpi'] ?? 203,
            'mediaWidthMm': config['labelWidthMm'] ?? 50,
            'mediaHeightMm': config['labelHeightMm'] ?? 30,
            'gapMm': config['labelGapMm'] ?? 2,
            'raster': true,
          }
        : {
            'paperWidthMm': config['paperWidth'] ?? 58,
            'raster': true,
            'cutter': config['autoCut'] ?? false,
            'cashDrawer': config['openDrawer'] ?? false,
          };
    return {
      'id': id,
      'name': name,
      'language': isLabel ? 'tspl' : 'escPos',
      'transport': transport,
      'transport_config_json': jsonEncode(config),
      'capabilities_json': jsonEncode(capabilities),
      'enabled': enabled ? 1 : 0,
      'last_tested_at': lastTestedAt,
      'last_test_succeeded':
          lastTestSucceeded == null ? null : (lastTestSucceeded ? 1 : 0),
      'last_test_message': lastTestMessage,
      'created_at': now,
      'updated_at': now,
    };
  }

  static Future<void> _createPrintingV2Tables(DatabaseExecutor db) async {
    await db.execute('''CREATE TABLE IF NOT EXISTS print_design_profiles (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, kind TEXT NOT NULL,
      schema_version INTEGER NOT NULL, renderer_version TEXT NOT NULL,
      definition_json TEXT NOT NULL, is_default INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
    await db
        .execute('''CREATE UNIQUE INDEX IF NOT EXISTS idx_print_design_default
      ON print_design_profiles(kind) WHERE is_default = 1''');
    await db.execute('''CREATE TABLE IF NOT EXISTS printer_devices (
      id TEXT PRIMARY KEY, name TEXT NOT NULL, language TEXT NOT NULL,
      transport TEXT NOT NULL, transport_config_json TEXT NOT NULL,
      capabilities_json TEXT NOT NULL, enabled INTEGER NOT NULL DEFAULT 1,
      last_tested_at TEXT, last_test_succeeded INTEGER, last_test_message TEXT,
      created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS printer_routes (
      kind TEXT PRIMARY KEY, device_id TEXT NOT NULL REFERENCES printer_devices(id),
      design_profile_id TEXT NOT NULL REFERENCES print_design_profiles(id),
      updated_at TEXT NOT NULL)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS print_jobs (
      id TEXT PRIMARY KEY, kind TEXT NOT NULL, payload_json TEXT NOT NULL,
      copies INTEGER NOT NULL DEFAULT 1 CHECK(copies > 0),
      design_profile_id TEXT NOT NULL, design_snapshot_json TEXT NOT NULL,
      device_id TEXT NOT NULL, transport_snapshot_json TEXT NOT NULL,
      capability_snapshot_json TEXT NOT NULL,
      renderer_version TEXT NOT NULL, state TEXT NOT NULL,
      attempt_count INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL, next_attempt_at TEXT, error_code TEXT,
      error_message TEXT, rendered_checksum TEXT,
      delivery_observation_json TEXT)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_print_jobs_claim
      ON print_jobs(state, next_attempt_at, created_at)''');
    await db.execute('''CREATE INDEX IF NOT EXISTS idx_print_jobs_device_state
      ON print_jobs(device_id, state)''');
    await db.execute('''CREATE TABLE IF NOT EXISTS print_job_attempts (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      job_id TEXT NOT NULL REFERENCES print_jobs(id), attempt_no INTEGER NOT NULL,
      started_at TEXT NOT NULL, completed_at TEXT, outcome TEXT, error_code TEXT,
      error_message TEXT, transport_observation_json TEXT,
      UNIQUE(job_id, attempt_no))''');
  }

  static Future<void> _seedLegacyPrintingProfiles(DatabaseExecutor db) async {
    final rows = await db.query('settings', limit: 1);
    if (rows.isEmpty) return;
    final settings = rows.first;
    final now = DateTime.now().toIso8601String();
    int flag(String key, [int fallback = 1]) =>
        (settings[key] as num?)?.toInt() ?? fallback;
    int number(String key, int fallback) =>
        (settings[key] as num?)?.toInt() ?? fallback;
    String text(String key, String fallback) =>
        settings[key] as String? ?? fallback;

    final profiles = <Map<String, Object?>>[
      {
        'id': 'receipt-default-v1',
        'name': 'Varsayılan Fiş',
        'kind': 'receipt',
        'schema_version': 1,
        'renderer_version': 'escpos-v1',
        'definition_json': jsonEncode({
          'showLogo': flag('print_logo') == 1,
          'showBarcode': flag('print_barcode') == 1,
          'showProductDetails': flag('print_product_details') == 1,
          'showCustomerBalance': flag('print_customer_balance') == 1,
          'font': text('receipt_font', 'a'),
          'textSize': text('receipt_text_size', 'normal'),
          'itemLayout': text('receipt_item_layout', 'auto'),
          'footerText': text('receipt_footer_text', ''),
          'feedLines': number('receipt_feed_lines', 2),
          'autoCut': flag('auto_cut_receipt') == 1,
          'openCashDrawer': flag('open_cash_drawer') == 1,
        }),
        'is_default': 1,
        'created_at': now,
        'updated_at': now,
      },
      {
        'id': 'product-label-default-v1',
        'name': 'Varsayılan Ürün Etiketi',
        'kind': 'productLabel',
        'schema_version': 1,
        'renderer_version': 'tspl-product-v1',
        'definition_json': jsonEncode({
          'showBusinessName': flag('label_show_business_name') == 1,
          'showBrand': flag('label_show_brand') == 1,
          'showBarcode': flag('label_show_barcode') == 1,
          'showPrice': flag('label_show_price') == 1,
          'showVat': flag('label_show_vat') == 1,
          'fontSize': text('label_font_size', 'Orta'),
        }),
        'is_default': 1,
        'created_at': now,
        'updated_at': now,
      },
      {
        'id': 'order-label-default-v1',
        'name': 'Varsayılan Sipariş Etiketi',
        'kind': 'orderLabel',
        'schema_version': 1,
        'renderer_version': 'tspl-order-v1',
        'definition_json': jsonEncode({
          'showBusinessName': flag('label_order_show_business_name') == 1,
          'showCustomerName': flag('label_order_show_customer_name') == 1,
          'showOrderNo': flag('label_order_show_order_no') == 1,
          'showDate': flag('label_order_show_date') == 1,
          'showTotalAmount': flag('label_order_show_total_amount') == 1,
          'showItemsCount': flag('label_order_show_items_count') == 1,
          'fontSize': text('label_order_font_size', 'Orta'),
        }),
        'is_default': 1,
        'created_at': now,
        'updated_at': now,
      },
    ];
    for (final profile in profiles) {
      await db.insert('print_design_profiles', profile,
          conflictAlgorithm: ConflictAlgorithm.ignore);
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
