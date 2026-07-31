// lib/infrastructure/database/schema/db_schema.dart
import 'package:sqflite/sqflite.dart';

class DatabaseSchema {
  static Future<void> createTables(Database db) async {
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
        device_token_version INTEGER DEFAULT 1,
        failed_pin_attempts INTEGER NOT NULL DEFAULT 0,
        locked_until TEXT,
        permissions TEXT
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
        purchase_price REAL NOT NULL DEFAULT 0,
        quantity INTEGER NOT NULL,
        min_stock INTEGER NOT NULL DEFAULT 5,
        brand TEXT NOT NULL DEFAULT '',
        unit TEXT NOT NULL DEFAULT 'adet',
        shelf_code TEXT NOT NULL DEFAULT '',
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
        ,sale_type TEXT NOT NULL DEFAULT 'piece'
        ,minimum_weight_grams INTEGER NOT NULL DEFAULT 20
      )
    ''');

    // Customers table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        normalized_name TEXT,
        email TEXT,
        normalized_email TEXT,
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
        entitlement_snapshot TEXT,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    // Sale items table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        subtotal REAL NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
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
        description TEXT,
        metadata TEXT,
        payment_method TEXT,
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
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ft_logical ON financial_transactions (logical_clock, device_id)');

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
        is_synced INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      )
    ''');

    // Order items table
    await db.execute('''
      CREATE TABLE IF NOT EXISTS order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        created_at TEXT NOT NULL,
        FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
      )
    ''');

    // Sync v4 write-ahead journal and durable pull cursor. These are also
    // created here (not only in upgrades) so a brand-new local database has
    // the same crash-safety guarantees as an upgraded installation.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox_v4 (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mutation_id TEXT NOT NULL UNIQUE,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        payload TEXT NOT NULL,
        base_revision INTEGER NOT NULL DEFAULT 0,
        state TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_outbox_v4_state ON sync_outbox_v4(state, id)');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_cursor_v4 (
        key TEXT PRIMARY KEY,
        cursor INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_conflicts_v4 (
        mutation_id TEXT PRIMARY KEY,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        server_revision INTEGER NOT NULL,
        detected_at TEXT NOT NULL,
        resolved_at TEXT
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

    await createAuditLogsTable(db);

    // Create indexes
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_status ON sales(status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_category ON products(category)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_status ON customers(status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_financial_transactions_customer ON financial_transactions(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_name ON products(name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers(name)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_created ON sales(created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ft_created ON financial_transactions(created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items(sale_id)');
    await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_sales_idempotency ON sales(idempotency_key)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_created ON audit_logs(created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_synced ON sales(is_synced)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sale_items_product ON sale_items(product_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_ft_reference ON financial_transactions(reference_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON audit_logs(action)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders(customer_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_orders_status ON orders(status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_orders_created ON orders(created_at)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_order_items_product ON order_items(product_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_active_lookup ON products(is_deleted, is_active, category)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_active_lookup ON customers(is_deleted, is_active)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_active_lookup ON sales(is_deleted, status, created_at)');

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
        print_logo INTEGER NOT NULL DEFAULT 1,
        print_customer_balance INTEGER NOT NULL DEFAULT 1,
        receipt_font TEXT NOT NULL DEFAULT 'a',
        receipt_text_size TEXT NOT NULL DEFAULT 'normal',
        receipt_item_layout TEXT NOT NULL DEFAULT 'auto',
        receipt_footer_text TEXT NOT NULL DEFAULT 'Bizi tercih ettiğiniz için teşekkür ederiz!',
        receipt_feed_lines INTEGER NOT NULL DEFAULT 2,
        auto_cut_receipt INTEGER NOT NULL DEFAULT 1,
        open_cash_drawer INTEGER NOT NULL DEFAULT 1,
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
        label_printer_name TEXT,
        label_printer_ip TEXT,
        label_printer_port INTEGER NOT NULL DEFAULT 9100,
        label_printer_copies INTEGER NOT NULL DEFAULT 1,
        label_printer_language TEXT NOT NULL DEFAULT 'tspl',
        label_width_mm INTEGER NOT NULL DEFAULT 50,
        label_height_mm INTEGER NOT NULL DEFAULT 30,
        label_gap_mm INTEGER NOT NULL DEFAULT 2,
        label_dpi INTEGER NOT NULL DEFAULT 203,
        admin_pin_code TEXT,
        sms_sim_subscription_id INTEGER,
        sms_sim_slot_index INTEGER,
        sms_monthly_limit INTEGER,
        sms_sent_this_month INTEGER NOT NULL DEFAULT 0,
        sms_limit_reset_month INTEGER,
        label_show_brand INTEGER NOT NULL DEFAULT 1,
        label_show_vat INTEGER NOT NULL DEFAULT 1,
        label_font_size TEXT NOT NULL DEFAULT 'Orta',
        label_order_show_business_name INTEGER NOT NULL DEFAULT 1,
        label_order_show_customer_name INTEGER NOT NULL DEFAULT 1,
        label_order_show_order_no INTEGER NOT NULL DEFAULT 1,
        label_order_show_date INTEGER NOT NULL DEFAULT 1,
        label_order_show_total_amount INTEGER NOT NULL DEFAULT 1,
        label_order_show_items_count INTEGER NOT NULL DEFAULT 1,
        label_order_font_size TEXT NOT NULL DEFAULT 'Orta'
      )
    ''');

    // Sync failure retry queue
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
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_failed_push_resolved ON failed_push_log(resolved)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_failed_push_next_retry ON failed_push_log(next_retry_at)');

    // Sync state machine audit trail
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
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_state_session ON sync_state_log(session_id)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_state_occurred ON sync_state_log(occurred_at)');

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
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sms_logs_status ON sms_logs(status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sms_logs_created ON sms_logs(created_at)');

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
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_print_queue_status ON print_queue(status)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_print_queue_created ON print_queue(created_at)');

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
        notes TEXT,
        previous_hash TEXT,
        record_hash TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_events_timestamp ON audit_events(timestamp)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_audit_events_type ON audit_events(event_type)');

    // business_profile table
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
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    // trial_anchor
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

    // A terminal may approve a card before the local sale transaction can be
    // committed. Keep that evidence durably so an operator can reconcile it
    // after a crash instead of blindly charging the card again.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS terminal_payment_intents (
        id TEXT PRIMARY KEY,
        idempotency_key TEXT NOT NULL UNIQUE,
        terminal_transaction_id TEXT NOT NULL UNIQUE,
        amount REAL NOT NULL,
        currency TEXT NOT NULL,
        authorization_code TEXT,
        state TEXT NOT NULL,
        context_type TEXT NOT NULL,
        context_id TEXT,
        error_message TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_terminal_payment_intents_state ON terminal_payment_intents(state, updated_at)',
    );
  }

  static Future<void> createAuditLogsTable(Database db) async {
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
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_trigger_audit_customer ON trigger_audit_logs(customer_id)');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ledger_bypass_flag (
        active INTEGER NOT NULL DEFAULT 0
      )
    ''');
    final countResult =
        await db.rawQuery('SELECT COUNT(*) as cnt FROM ledger_bypass_flag');
    if (Sqflite.firstIntValue(countResult) == 0) {
      await db.rawInsert('INSERT INTO ledger_bypass_flag (active) VALUES (0)');
    }
  }
}
