// lib/infrastructure/database/schema/db_triggers.dart
import 'package:sqflite/sqflite.dart';
import 'package:serenutos/domain/services/telemetry_service.dart';
import 'package:flutter/foundation.dart' show debugPrint;

class DatabaseTriggers {
  static Future<void> createTriggers(Database db) async {
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

  static Future<void> verifyAndRepairTriggers(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'trigger' AND name IN ('trg_ft_insert', 'trg_ft_block_update', 'trg_ft_block_delete')"
    );
    if (rows.length < 3) {
      try {
        await createTriggers(db);
        debugPrint('Self-Healing: Recreated missing or tampered database triggers successfully.');
      } catch (e, st) {
        debugPrint('[DatabaseManager] ❌ Trigger self-healing failed: ');
        TelemetryService().logError(e, st, context: 'db_trigger_selfheal_failed');
      }
    }
  }
}
