// core_next/client_core/lib/infrastructure/database/schema_definitions.dart
import 'package:sqflite/sqflite.dart';

/// Serenut OS Yeni Nesil Temiz Şema Tanımları (Version 2).
/// 
/// 60 sürüm birikmiş eski migrasyonların ve karmaşık trigger'ların yerine;
/// kuruş bazlı tamsayı (INTEGER cents), tek tip foreign key ve doğru indekslerle
/// sıfırdan oluşturulmuş saf ve güvenli veritabanı şeması.
class CoreSchemaDefinitions {
  static const int schemaVersion = 7;

  static const List<String> createTablesQueries = [
    // 1. KULLANICILAR & ROLLER
    '''
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY NOT NULL,
      username TEXT UNIQUE NOT NULL,
      display_name TEXT NOT NULL,
      role TEXT NOT NULL DEFAULT 'cashier',
      pin_hash TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL
    );
    ''',

    // 2. KATEGORİLER
    '''
    CREATE TABLE IF NOT EXISTS categories (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      color_hex TEXT,
      sort_order INTEGER NOT NULL DEFAULT 0,
      is_active INTEGER NOT NULL DEFAULT 1,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 3. ÜRÜN KATALOĞU (Kuruş Bazlı)
    '''
    CREATE TABLE IF NOT EXISTS products (
      id TEXT PRIMARY KEY NOT NULL,
      barcode TEXT UNIQUE NOT NULL,
      name TEXT NOT NULL,
      category_id TEXT,
      price_cents INTEGER NOT NULL,
      cost_price_cents INTEGER,
      vat_rate INTEGER NOT NULL DEFAULT 20,
      unit TEXT NOT NULL DEFAULT 'piece',
      sale_type TEXT NOT NULL DEFAULT 'piece',
      minimum_weight_grams INTEGER NOT NULL DEFAULT 20,
      stock_quantity REAL NOT NULL DEFAULT 0.0,
      critical_threshold REAL NOT NULL DEFAULT 5.0,
      image_url TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL
    );
    ''',

    // 4. MÜŞTERİ / CARİ HESAPLAR (Kuruş Bazlı Bakiye)
    '''
    CREATE TABLE IF NOT EXISTS customers (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      phone TEXT,
      email TEXT,
      tax_number TEXT,
      tax_office TEXT,
      balance_cents INTEGER NOT NULL DEFAULT 0,
      credit_limit_cents INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 5. SATIŞ VE FİŞLER (Kuruş Bazlı)
    '''
    CREATE TABLE IF NOT EXISTS sales (
      id TEXT PRIMARY KEY NOT NULL,
      receipt_no TEXT UNIQUE NOT NULL,
      customer_id TEXT,
      branch_id TEXT,
      subtotal_cents INTEGER NOT NULL,
      discount_cents INTEGER NOT NULL DEFAULT 0,
      vat_total_cents INTEGER NOT NULL DEFAULT 0,
      total_cents INTEGER NOT NULL,
      paid_cents INTEGER NOT NULL,
      debt_cents INTEGER NOT NULL DEFAULT 0,
      status TEXT NOT NULL DEFAULT 'COMPLETED',
      idempotency_key TEXT UNIQUE,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL
    );
    ''',

    // 6. SATIŞ KALEMLERİ
    '''
    CREATE TABLE IF NOT EXISTS sale_items (
      id TEXT PRIMARY KEY NOT NULL,
      sale_id TEXT NOT NULL,
      product_id TEXT NOT NULL,
      barcode TEXT NOT NULL,
      product_name TEXT NOT NULL,
      unit_price_cents INTEGER NOT NULL,
      quantity REAL NOT NULL DEFAULT 1.0,
      discount_cents INTEGER NOT NULL DEFAULT 0,
      vat_rate INTEGER NOT NULL,
      total_cents INTEGER NOT NULL,
      FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE,
      FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
    );
    ''',

    // 7. ÇİFT TARAFLI CARİ VE KASA DEFTERİ (TRIGGER'SIZ IMMUTABLE LEDGER)
    '''
    CREATE TABLE IF NOT EXISTS ledger_entries (
      id TEXT PRIMARY KEY NOT NULL,
      customer_id TEXT NOT NULL,
      reference_sale_id TEXT,
      entry_type TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      balance_after_cents INTEGER NOT NULL,
      description TEXT NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE RESTRICT
    );
    ''',

    // 8. TAKSİTLİ SATIŞ PLANI
    '''
    CREATE TABLE IF NOT EXISTS installments (
      id TEXT PRIMARY KEY NOT NULL,
      customer_id TEXT NOT NULL,
      sale_id TEXT NOT NULL,
      installment_no INTEGER NOT NULL,
      total_installments INTEGER NOT NULL,
      due_date INTEGER NOT NULL,
      amount_cents INTEGER NOT NULL,
      paid_amount_cents INTEGER NOT NULL DEFAULT 0,
      is_paid INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE CASCADE,
      FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
    );
    ''',

    // 9. KASA HAREKETLERİ VE GİDERLER (Nakit Akışı)
    '''
    CREATE TABLE IF NOT EXISTS cash_transactions (
      id TEXT PRIMARY KEY NOT NULL,
      branch_id TEXT,
      type TEXT NOT NULL, -- 'INFLOW', 'OUTFLOW', 'EXPENSE'
      amount_cents INTEGER NOT NULL,
      category TEXT NOT NULL, -- 'SALE', 'EXPENSE', 'OPENING_BALANCE'
      description TEXT,
      created_at INTEGER NOT NULL
    );
    ''',

    // 10. ÇAKIŞMASIZ SU DAMGASI (WATERMARK) SENKRONİZASYON KUYRUĞU
    '''
    CREATE TABLE IF NOT EXISTS sync_events (
      event_id TEXT PRIMARY KEY NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      operation TEXT NOT NULL, -- 'UPSERT', 'DELETE'
      payload_json TEXT NOT NULL,
      base_revision INTEGER NOT NULL DEFAULT 0,
      client_timestamp INTEGER NOT NULL,
      sync_state TEXT NOT NULL DEFAULT 'PENDING', -- 'PENDING', 'IN_FLIGHT', 'SYNCED', 'TRANSIENT_ERROR', 'REJECTED', 'CONFLICT'
      attempts INTEGER NOT NULL DEFAULT 0,
      last_error TEXT,
      group_id TEXT,
      causal_sequence INTEGER NOT NULL DEFAULT 0
    );
    ''',

    // 11. SİSTEM VE YAZICI AYARLARI
    '''
    CREATE TABLE IF NOT EXISTS app_settings (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 12. PARÇALI / KARMA ÖDEMELER (Kalıcı ve İdempotent)
    '''
    CREATE TABLE IF NOT EXISTS sale_payments (
      id TEXT PRIMARY KEY NOT NULL,
      sale_id TEXT NOT NULL,
      payment_type TEXT NOT NULL, -- 'cash', 'creditCard', 'onAccount', 'bankTransfer'
      amount_cents INTEGER NOT NULL,
      reference_note TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
    );
    ''',

    // 13. ÇOK KASALI UYGULANMIŞ SENKRONİZASYON HAREKETLERİ (IDEMPOTENT EVENT REPLICATION)
    '''
    CREATE TABLE IF NOT EXISTS sync_applied_events (
      id TEXT PRIMARY KEY NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      revision INTEGER NOT NULL DEFAULT 0,
      device_id TEXT,
      product_id TEXT,
      quantity_delta INTEGER NOT NULL DEFAULT 0,
      applied_at INTEGER NOT NULL
    );
    ''',

    // 14. SİPARİŞLER (Orders & Delivery)
    '''
    CREATE TABLE IF NOT EXISTS orders (
      id TEXT PRIMARY KEY NOT NULL,
      order_number TEXT UNIQUE NOT NULL,
      customer_id TEXT,
      branch_id TEXT,
      status TEXT NOT NULL DEFAULT 'pending',
      total_amount_cents INTEGER NOT NULL,
      discount_amount_cents INTEGER NOT NULL DEFAULT 0,
      order_date INTEGER NOT NULL,
      expected_delivery_date INTEGER,
      actual_delivery_date INTEGER,
      notes TEXT,
      created_by TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE SET NULL
    );
    ''',

    // 15. SİPARİŞ KALEMLERİ
    '''
    CREATE TABLE IF NOT EXISTS order_items (
      id TEXT PRIMARY KEY NOT NULL,
      order_id TEXT NOT NULL,
      product_id TEXT NOT NULL,
      barcode TEXT,
      product_name TEXT NOT NULL,
      quantity REAL NOT NULL DEFAULT 1.0,
      unit_price_cents INTEGER NOT NULL,
      total_cents INTEGER NOT NULL,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (order_id) REFERENCES orders (id) ON DELETE CASCADE,
      FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
    );
    ''',

    // 16. SİPARİŞ NUMARASI SIRASI
    '''
    CREATE TABLE IF NOT EXISTS order_number_sequence (
      prefix TEXT PRIMARY KEY NOT NULL,
      last_number INTEGER NOT NULL DEFAULT 0
    );
    ''',

    // 17. MÜŞTERİ TAKSİT PLANLARI
    '''
    CREATE TABLE IF NOT EXISTS customer_installment_plans (
      id TEXT PRIMARY KEY NOT NULL,
      customer_id TEXT NOT NULL,
      total_amount_cents INTEGER NOT NULL,
      down_payment_cents INTEGER NOT NULL DEFAULT 0,
      installment_count INTEGER NOT NULL,
      description TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      is_deleted INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE RESTRICT
    );
    ''',

    // 18. MÜŞTERİ TAKSİTLERİ (Detaylı Ödeme Planı)
    '''
    CREATE TABLE IF NOT EXISTS customer_installments (
      id TEXT PRIMARY KEY NOT NULL,
      plan_id TEXT NOT NULL,
      customer_id TEXT NOT NULL,
      installment_no INTEGER NOT NULL,
      amount_cents INTEGER NOT NULL,
      paid_amount_cents INTEGER NOT NULL DEFAULT 0,
      due_date INTEGER NOT NULL,
      status TEXT NOT NULL DEFAULT 'pending',
      paid_at INTEGER,
      financial_transaction_id TEXT,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (plan_id) REFERENCES customer_installment_plans (id) ON DELETE CASCADE,
      FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE RESTRICT
    );
    ''',

    // 19. GÜN SONU / KASA SAYIMLARI
    '''
    CREATE TABLE IF NOT EXISTS cash_counts (
      id TEXT PRIMARY KEY NOT NULL,
      count_date INTEGER NOT NULL,
      expected_amount_cents INTEGER NOT NULL DEFAULT 0,
      actual_amount_cents INTEGER NOT NULL DEFAULT 0,
      difference_cents INTEGER NOT NULL DEFAULT 0,
      notes TEXT,
      created_by TEXT,
      created_at INTEGER NOT NULL
    );
    ''',

    // 20. KASA GİDERLERİ
    '''
    CREATE TABLE IF NOT EXISTS cash_expenses (
      id TEXT PRIMARY KEY NOT NULL,
      amount_cents INTEGER NOT NULL,
      category TEXT NOT NULL,
      description TEXT,
      expense_date INTEGER NOT NULL,
      created_by TEXT,
      created_at INTEGER NOT NULL
    );
    ''',

    // 21. ADLİ DENETİM KAYITLARI (Audit Events)
    '''
    CREATE TABLE IF NOT EXISTS audit_events (
      id TEXT PRIMARY KEY NOT NULL,
      event_type TEXT NOT NULL,
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      user_id TEXT,
      user_name TEXT,
      old_value TEXT,
      new_value TEXT,
      timestamp INTEGER NOT NULL,
      device_id TEXT,
      notes TEXT,
      previous_hash TEXT,
      record_hash TEXT
    );
    ''',

    // 22. IMMUTABLE STOK DEFTERİ (APPEND-ONLY STOCK MOVEMENTS)
    '''
    CREATE TABLE IF NOT EXISTS stock_movements (
      id TEXT PRIMARY KEY NOT NULL,
      product_id TEXT NOT NULL,
      branch_id TEXT,
      reference_id TEXT,
      reference_type TEXT NOT NULL, -- 'SALE', 'REFUND', 'PURCHASE', 'WASTE', 'COUNT_ADJUSTMENT', 'SYNC_REMOTE'
      quantity_delta REAL NOT NULL,
      previous_stock REAL NOT NULL,
      new_stock REAL NOT NULL,
      reason TEXT,
      created_by TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
    );
    ''',

    // 23. ÇOKLU ŞUBE TANIMLARI (Multi-Branch Support)
    '''
    CREATE TABLE IF NOT EXISTS branches (
      id TEXT PRIMARY KEY NOT NULL,
      name TEXT NOT NULL,
      address TEXT,
      phone TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',

    // 24. BANKA / EFT-POS ÖDEME NİYETLERİ (Terminal Two-Phase Commit)
    '''
    CREATE TABLE IF NOT EXISTS terminal_payment_intents (
      id TEXT PRIMARY KEY NOT NULL,
      idempotency_key TEXT NOT NULL UNIQUE,
      terminal_transaction_id TEXT NOT NULL UNIQUE,
      amount_cents INTEGER NOT NULL,
      currency TEXT NOT NULL DEFAULT 'TRY',
      authorization_code TEXT,
      state TEXT NOT NULL,
      context_type TEXT NOT NULL,
      context_id TEXT,
      error_message TEXT,
      created_at INTEGER NOT NULL,
      updated_at INTEGER NOT NULL
    );
    ''',
  ];

  static const List<String> createIndexesQueries = [
    // Ürün indeksleri
    'CREATE INDEX IF NOT EXISTS idx_products_barcode ON products (barcode);',
    'CREATE INDEX IF NOT EXISTS idx_products_name ON products (name);',
    'CREATE INDEX IF NOT EXISTS idx_products_category ON products (category_id);',
    'CREATE INDEX IF NOT EXISTS idx_products_updated ON products (updated_at);',
    
    // Cari hesap indeksleri
    'CREATE INDEX IF NOT EXISTS idx_customers_name ON customers (name);',
    'CREATE INDEX IF NOT EXISTS idx_customers_phone ON customers (phone);',
    'CREATE INDEX IF NOT EXISTS idx_customers_balance ON customers (balance_cents);',

    // Satış indeksleri
    'CREATE INDEX IF NOT EXISTS idx_sales_receipt ON sales (receipt_no);',
    'CREATE INDEX IF NOT EXISTS idx_sales_customer ON sales (customer_id);',
    'CREATE INDEX IF NOT EXISTS idx_sales_created ON sales (created_at);',
    'CREATE INDEX IF NOT EXISTS idx_sale_items_sale ON sale_items (sale_id);',

    // Satış ödeme indeksleri
    'CREATE INDEX IF NOT EXISTS idx_sale_payments_sale ON sale_payments (sale_id);',
    'CREATE INDEX IF NOT EXISTS idx_sale_payments_type ON sale_payments (payment_type);',
    'CREATE INDEX IF NOT EXISTS idx_sale_payments_created ON sale_payments (created_at);',

    // Defter indeksleri
    'CREATE INDEX IF NOT EXISTS idx_ledger_customer ON ledger_entries (customer_id);',
    'CREATE INDEX IF NOT EXISTS idx_ledger_sale ON ledger_entries (reference_sale_id);',
    'CREATE INDEX IF NOT EXISTS idx_ledger_created ON ledger_entries (created_at);',

    // Taksit indeksleri
    'CREATE INDEX IF NOT EXISTS idx_installments_due ON installments (due_date, is_paid);',

    // Senkronizasyon indeksleri
    'CREATE INDEX IF NOT EXISTS idx_sync_events_state ON sync_events (sync_state, client_timestamp);',
    'CREATE INDEX IF NOT EXISTS idx_sync_events_queue ON sync_events (sync_state, causal_sequence, client_timestamp);',
    'CREATE INDEX IF NOT EXISTS idx_sync_events_group ON sync_events (group_id);',

    // Uygulanmış senkronizasyon hareketleri indeksleri
    'CREATE INDEX IF NOT EXISTS idx_sync_applied_entity ON sync_applied_events (entity_type, entity_id);',
    'CREATE INDEX IF NOT EXISTS idx_sync_applied_product_rev ON sync_applied_events (product_id, revision);',

    // Sipariş indeksleri
    'CREATE INDEX IF NOT EXISTS idx_orders_number ON orders (order_number);',
    'CREATE INDEX IF NOT EXISTS idx_orders_customer ON orders (customer_id);',
    'CREATE INDEX IF NOT EXISTS idx_orders_date ON orders (order_date);',
    'CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items (order_id);',

    // Taksit plan indeksleri
    'CREATE INDEX IF NOT EXISTS idx_installment_plans_customer ON customer_installment_plans (customer_id);',
    'CREATE INDEX IF NOT EXISTS idx_customer_installments_plan ON customer_installments (plan_id);',
    'CREATE INDEX IF NOT EXISTS idx_customer_installments_due ON customer_installments (due_date, status);',

    // Kasa ve adli denetim indeksleri
    'CREATE INDEX IF NOT EXISTS idx_cash_counts_date ON cash_counts (count_date);',
    'CREATE INDEX IF NOT EXISTS idx_cash_expenses_date ON cash_expenses (expense_date);',
    'CREATE INDEX IF NOT EXISTS idx_audit_events_entity ON audit_events (entity_type, entity_id);',
    'CREATE INDEX IF NOT EXISTS idx_audit_events_timestamp ON audit_events (timestamp);',

    // Stok hareketleri indeksleri
    'CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements (product_id);',
    'CREATE INDEX IF NOT EXISTS idx_stock_movements_ref ON stock_movements (reference_type, reference_id);',
    'CREATE INDEX IF NOT EXISTS idx_stock_movements_created ON stock_movements (created_at);',

    // Çoklu şube indeksleri
    'CREATE INDEX IF NOT EXISTS idx_branches_active ON branches (is_active);',
    'CREATE INDEX IF NOT EXISTS idx_sales_branch ON sales (branch_id);',
    'CREATE INDEX IF NOT EXISTS idx_orders_branch ON orders (branch_id);',
    'CREATE INDEX IF NOT EXISTS idx_stock_movements_branch ON stock_movements (branch_id);',

    // Banka / EFT-POS ödeme niyeti indeksi
    'CREATE INDEX IF NOT EXISTS idx_terminal_payment_intents_state ON terminal_payment_intents(state, updated_at);',
  ];

  /// Geriye uyumlu otomatik şema migrasyonu (v1 -> v2 -> v3)
  static Future<void> migrate(DatabaseExecutor db, int oldVersion, int newVersion) async {
    if (oldVersion < 2 && newVersion >= 2) {
      // 1. Kolonların varlığını kontrol et ve eksikleri ekle
      if (await _tableExists(db, 'sync_events')) {
        final tableInfo = await db.rawQuery('PRAGMA table_info(sync_events);');
        final existingColumns = tableInfo.map((row) => row['name'] as String).toSet();

        if (!existingColumns.contains('base_revision')) {
          await db.execute('ALTER TABLE sync_events ADD COLUMN base_revision INTEGER NOT NULL DEFAULT 0;');
        }
        if (!existingColumns.contains('attempts')) {
          await db.execute('ALTER TABLE sync_events ADD COLUMN attempts INTEGER NOT NULL DEFAULT 0;');
        }
        if (!existingColumns.contains('last_error')) {
          await db.execute('ALTER TABLE sync_events ADD COLUMN last_error TEXT;');
        }
        if (!existingColumns.contains('group_id')) {
          await db.execute('ALTER TABLE sync_events ADD COLUMN group_id TEXT;');
        }
        if (!existingColumns.contains('causal_sequence')) {
          await db.execute('ALTER TABLE sync_events ADD COLUMN causal_sequence INTEGER NOT NULL DEFAULT 0;');
        }

        // 2. Varsa eski büyük harfli entity türlerini küçük harfe normalize et
        await db.execute(
          "UPDATE sync_events SET entity_type = LOWER(entity_type) WHERE entity_type IN ('SALE', 'PRODUCT', 'CUSTOMER');",
        );

        // 3. Yeni indeksleri oluştur
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sync_events_queue ON sync_events (sync_state, causal_sequence, client_timestamp);',
        );
        await db.execute(
          'CREATE INDEX IF NOT EXISTS idx_sync_events_group ON sync_events (group_id);',
        );
      }
    }

    if (oldVersion < 3 && newVersion >= 3) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS sync_applied_events (
          id TEXT PRIMARY KEY NOT NULL,
          entity_type TEXT NOT NULL,
          entity_id TEXT NOT NULL,
          revision INTEGER NOT NULL DEFAULT 0,
          device_id TEXT,
          product_id TEXT,
          quantity_delta INTEGER NOT NULL DEFAULT 0,
          applied_at INTEGER NOT NULL
        );
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_applied_entity ON sync_applied_events (entity_type, entity_id);',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sync_applied_product_rev ON sync_applied_events (product_id, revision);',
      );
    }

    if (oldVersion < 4 && newVersion >= 4) {
      if (await _tableExists(db, 'ledger_entries')) {
        await db.execute('''
          CREATE TABLE IF NOT EXISTS ledger_entries_new (
            id TEXT PRIMARY KEY NOT NULL,
            customer_id TEXT NOT NULL,
            reference_sale_id TEXT,
            entry_type TEXT NOT NULL,
            amount_cents INTEGER NOT NULL,
            balance_after_cents INTEGER NOT NULL,
            description TEXT NOT NULL,
            created_at INTEGER NOT NULL,
            FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE RESTRICT
          );
        ''');

        final colsInfo = await db.rawQuery('PRAGMA table_info(ledger_entries);');
        final existingCols = colsInfo.map((c) => c['name'].toString()).toSet();

        final refSaleExpr = existingCols.contains('reference_sale_id') ? 'reference_sale_id' : 'NULL';
        final balAfterExpr = existingCols.contains('balance_after_cents') ? 'balance_after_cents' : '0';
        final descExpr = existingCols.contains('description') ? 'description' : "''";

        await db.execute('''
          INSERT OR IGNORE INTO ledger_entries_new (id, customer_id, reference_sale_id, entry_type, amount_cents, balance_after_cents, description, created_at)
          SELECT id, customer_id, $refSaleExpr, entry_type, amount_cents, $balAfterExpr, $descExpr, created_at FROM ledger_entries;
        ''');
        await db.execute('DROP TABLE IF EXISTS ledger_entries;');
        await db.execute('ALTER TABLE ledger_entries_new RENAME TO ledger_entries;');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ledger_customer ON ledger_entries (customer_id);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ledger_sale ON ledger_entries (reference_sale_id);');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_ledger_created ON ledger_entries (created_at);');
      }
    }

    if (oldVersion < 5 && newVersion >= 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS stock_movements (
          id TEXT PRIMARY KEY NOT NULL,
          product_id TEXT NOT NULL,
          reference_id TEXT,
          reference_type TEXT NOT NULL,
          quantity_delta REAL NOT NULL,
          previous_stock REAL NOT NULL,
          new_stock REAL NOT NULL,
          reason TEXT,
          created_by TEXT,
          created_at INTEGER NOT NULL,
          FOREIGN KEY (product_id) REFERENCES products (id) ON DELETE RESTRICT
        );
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_product ON stock_movements (product_id);',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_ref ON stock_movements (reference_type, reference_id);',
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_movements_created ON stock_movements (created_at);',
      );
    }

    if (oldVersion < 6 && newVersion >= 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS branches (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL,
          address TEXT,
          phone TEXT,
          is_active INTEGER NOT NULL DEFAULT 1,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      await _safeAddColumn(db, 'sales', 'branch_id TEXT');
      await _safeAddColumn(db, 'orders', 'branch_id TEXT');
      await _safeAddColumn(db, 'stock_movements', 'branch_id TEXT');
      await _safeAddColumn(db, 'cash_transactions', 'branch_id TEXT');
      await _safeCreateIndex(db, 'idx_branches_active', 'branches', 'is_active');
      await _safeCreateIndex(db, 'idx_sales_branch', 'sales', 'branch_id');
      await _safeCreateIndex(db, 'idx_orders_branch', 'orders', 'branch_id');
      await _safeCreateIndex(db, 'idx_stock_movements_branch', 'stock_movements', 'branch_id');
    }

    if (oldVersion < 7 && newVersion >= 7) {
      await _safeAddColumn(db, 'products', "sale_type TEXT NOT NULL DEFAULT 'piece'");
      await _safeAddColumn(db, 'products', 'minimum_weight_grams INTEGER NOT NULL DEFAULT 20');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS terminal_payment_intents (
          id TEXT PRIMARY KEY NOT NULL,
          idempotency_key TEXT NOT NULL UNIQUE,
          terminal_transaction_id TEXT NOT NULL UNIQUE,
          amount_cents INTEGER NOT NULL,
          currency TEXT NOT NULL DEFAULT 'TRY',
          authorization_code TEXT,
          state TEXT NOT NULL,
          context_type TEXT NOT NULL,
          context_id TEXT,
          error_message TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
      ''');
      await _safeCreateIndex(
        db,
        'idx_terminal_payment_intents_state',
        'terminal_payment_intents',
        'state, updated_at',
      );
    }
  }

  static Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final res = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?",
      [table],
    );
    return res.isNotEmpty;
  }

  static Future<void> _safeAddColumn(
    DatabaseExecutor db,
    String table,
    String columnDef,
  ) async {
    if (!await _tableExists(db, table)) return;
    final colName = columnDef.split(' ').first.trim();
    final info = await db.rawQuery('PRAGMA table_info($table);');
    final exists = info.any((row) => row['name']?.toString() == colName);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $columnDef;');
    }
  }

  static Future<void> _safeCreateIndex(
    DatabaseExecutor db,
    String indexName,
    String table,
    String column,
  ) async {
    if (!await _tableExists(db, table)) return;
    await db.execute('CREATE INDEX IF NOT EXISTS $indexName ON $table ($column);');
  }
}
