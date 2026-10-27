#!/usr/bin/env python3
"""
scripts/stage10_12_41_erkul_legacy_reconstruction_prototype.py
SERENUT OS — STAGE 10.12.41
Erkul Çeyiz: JSON Kaynağından İzole Legacy DB Üretim Prototipi ve Bütünlük Doğrulaması

UYARI: Bu betik hiçbir canlı veritabanına yazmaz. Sadece izole geçici klasörde
JSON kaynağının Legacy v60 şemasıyla uyumluluğunu test eder.
"""

import os
import sys
import json
import sqlite3
import tempfile
import hashlib
import shutil
from datetime import datetime

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)

def sha256_file(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def create_legacy_schema(conn):
    cur = conn.cursor()
    # 1. Products
    cur.execute('''
    CREATE TABLE products (
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
        is_synced INTEGER NOT NULL DEFAULT 1,
        sale_type TEXT NOT NULL DEFAULT 'piece',
        minimum_weight_grams INTEGER NOT NULL DEFAULT 20,
        origin TEXT NOT NULL DEFAULT 'TÜRKİYE',
        price_minor INTEGER DEFAULT 0,
        purchase_price_minor INTEGER DEFAULT 0
    );
    ''')

    # 2. Customers
    cur.execute('''
    CREATE TABLE customers (
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
        is_synced INTEGER NOT NULL DEFAULT 1,
        address TEXT,
        balance_minor INTEGER DEFAULT 0,
        credit_limit_minor INTEGER
    );
    ''')

    # 3. Sales
    cur.execute('''
    CREATE TABLE sales (
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
        refunded_amount REAL NOT NULL DEFAULT 0,
        fsm_state TEXT NOT NULL DEFAULT 'completed',
        discount_amount REAL NOT NULL DEFAULT 0.0,
        total_amount_minor INTEGER DEFAULT 0,
        paid_amount_minor INTEGER DEFAULT 0,
        refunded_amount_minor INTEGER DEFAULT 0,
        discount_amount_minor INTEGER DEFAULT 0,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
    );
    ''')

    # 4. Sale Items
    cur.execute('''
    CREATE TABLE sale_items (
        id TEXT PRIMARY KEY,
        sale_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        subtotal REAL NOT NULL,
        created_at TEXT NOT NULL,
        unit_price_minor INTEGER DEFAULT 0,
        subtotal_minor INTEGER DEFAULT 0,
        FOREIGN KEY (sale_id) REFERENCES sales(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
    );
    ''')

    # 5. Financial Transactions
    cur.execute('''
    CREATE TABLE financial_transactions (
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
        amount_minor INTEGER DEFAULT 0,
        paid_amount_minor INTEGER DEFAULT 0,
        debt_amount_minor INTEGER DEFAULT 0,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
    );
    ''')

    # 6. Orders and Order Items
    cur.execute('''
    CREATE TABLE orders (
        id TEXT PRIMARY KEY,
        customer_id TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        total_amount REAL NOT NULL,
        order_date TEXT NOT NULL,
        expected_delivery_date TEXT,
        actual_delivery_date TEXT,
        notes TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        is_deleted INTEGER NOT NULL DEFAULT 0,
        deleted_at TEXT,
        deleted_by TEXT,
        created_by TEXT,
        order_number TEXT UNIQUE,
        discount_amount REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
    );
    ''')

    cur.execute('''
    CREATE TABLE order_items (
        id TEXT PRIMARY KEY,
        order_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        quantity REAL NOT NULL,
        unit_price REAL NOT NULL,
        created_at TEXT NOT NULL,
        product_name TEXT,
        FOREIGN KEY (order_id) REFERENCES orders(id) ON DELETE CASCADE,
        FOREIGN KEY (product_id) REFERENCES products(id)
    );
    ''')

    # 7. Business Profile & Settings
    cur.execute('''
    CREATE TABLE business_profile (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        owner_name TEXT NOT NULL,
        type TEXT,
        phone TEXT,
        email TEXT,
        tax_number TEXT,
        city TEXT,
        district TEXT,
        currency TEXT NOT NULL DEFAULT '₺',
        tax_included INTEGER NOT NULL DEFAULT 1,
        logo_path TEXT,
        version INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
    );
    ''')

    cur.execute('''
    CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        created_at TEXT,
        updated_at TEXT
    );
    ''')
    conn.commit()

def populate_from_json(conn, json_data):
    cur = conn.cursor()

    # 1. Products
    for p in json_data.get('products', []):
        price = float(p.get('price', 0.0))
        cur.execute('''
        INSERT INTO products (
            id, name, description, price, purchase_price, quantity, min_stock,
            brand, unit, shelf_code, category, sku, vat, is_active, created_at,
            updated_at, price_minor, purchase_price_minor
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            p['id'], p['name'], p.get('description', ''), price,
            float(p.get('purchase_price', 0.0)), int(float(p.get('quantity', 0.0))),
            int(float(p.get('min_stock', 5.0))), p.get('brand', ''),
            p.get('unit', 'adet'), p.get('shelf_code', ''), p.get('category', 'Genel'),
            p.get('sku', p['id']), int(p.get('vat', 1)), 1 if p.get('status') == 'active' else 0,
            p.get('created_at', ''), p.get('updated_at', ''),
            round(price * 100), round(float(p.get('purchase_price', 0.0)) * 100)
        ))

    # 2. Customers
    for c in json_data.get('customers', []):
        bal = float(c.get('balance', 0.0))
        cur.execute('''
        INSERT INTO customers (
            id, name, email, phone, balance, credit_limit, status, is_active,
            created_at, updated_at, address, balance_minor
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            c['id'], c['name'], c.get('email'), c.get('phone'), bal,
            float(c.get('credit_limit', 0.0)), c.get('status', 'active'),
            1 if c.get('status') == 'active' else 0, c.get('created_at', ''),
            c.get('updated_at', ''), c.get('address'), round(bal * 100)
        ))

    # 3. Sales
    for s in json_data.get('sales', []):
        tot = float(s.get('total_amount', 0.0))
        paid = float(s.get('paid_amount', 0.0))
        cur.execute('''
        INSERT INTO sales (
            id, customer_id, total_amount, paid_amount, payment_method, status,
            created_at, updated_at, idempotency_key, total_amount_minor, paid_amount_minor
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            s['id'], s['customer_id'], tot, paid, s.get('payment_method', 'debt'),
            s.get('status', 'completed'), s.get('created_at', ''), s.get('updated_at', ''),
            s.get('idempotency_key'), round(tot * 100), round(paid * 100)
        ))

    # 4. Sale Items
    for si in json_data.get('sale_items', []):
        u_price = float(si.get('unit_price', 0.0))
        sub = float(si.get('subtotal', 0.0))
        cur.execute('''
        INSERT INTO sale_items (
            id, sale_id, product_id, product_name, quantity, unit_price, subtotal,
            created_at, unit_price_minor, subtotal_minor
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            si['id'], si['sale_id'], si['product_id'], si.get('product_name'),
            float(si.get('quantity', 1.0)), u_price, sub, si.get('created_at', ''),
            round(u_price * 100), round(sub * 100)
        ))

    # 5. Financial Transactions
    for ft in json_data.get('financial_transactions', []):
        amt = float(ft.get('amount', 0.0))
        paid = float(ft.get('paid_amount', 0.0))
        debt = float(ft.get('debt_amount', 0.0))
        dt = ft.get('date', ft.get('created_at', ''))
        cur.execute('''
        INSERT INTO financial_transactions (
            id, type, customer_id, amount, paid_amount, debt_amount, reference_id,
            created_at, payment_method, amount_minor, paid_amount_minor, debt_amount_minor
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            ft['id'], ft.get('type', 'sale'), ft['customer_id'], amt, paid, debt,
            ft.get('reference_id'), dt, ft.get('payment_method'),
            round(amt * 100), round(paid * 100), round(debt * 100)
        ))

    # 6. Orders and Order Items
    for o in json_data.get('customer_orders', []):
        tot = float(o.get('total_amount', 0.0))
        cur.execute('''
        INSERT INTO orders (
            id, customer_id, status, total_amount, order_date, expected_delivery_date,
            actual_delivery_date, notes, created_at, updated_at, order_number
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            o['id'], o['customer_id'], o.get('status', 'pending'), tot,
            o.get('order_date', ''), o.get('expected_delivery_date'),
            o.get('actual_delivery_date'), o.get('notes'), o.get('created_at', ''),
            o.get('updated_at', ''), o.get('order_number')
        ))

    for oi in json_data.get('customer_order_items', []):
        cur.execute('''
        INSERT INTO order_items (
            id, order_id, product_id, quantity, unit_price, created_at, product_name
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (
            oi['id'], oi['order_id'], oi['product_id'], float(oi.get('quantity', 1.0)),
            float(oi.get('unit_price', 0.0)), oi.get('created_at', ''), oi.get('product_name')
        ))

    # 7. Business Profile
    companies = json_data.get('companies', [])
    if companies:
        c0 = companies[0]
        cur.execute('''
        INSERT INTO business_profile (
            name, owner_name, tax_number, city, district, currency, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            c0.get('name', 'ERKUL ÇEYİZ'), c0.get('owner_name', ''),
            c0.get('tax_number', ''), c0.get('city', ''), c0.get('district', ''),
            c0.get('currency', '₺'), c0.get('created_at', ''), c0.get('updated_at', '')
        ))

    cur.execute("PRAGMA user_version = 60;")
    conn.commit()

def main():
    json_path = os.path.abspath(r"backups\raw_tenants_20261016\raw_erkul_source.json")
    log("=================================================================")
    log("SERENUT OS — ERKUL ÇEYİZ LEGACY RECOVERY PROTOTİPİ DENETİMİ")
    log(f"Kaynak: {json_path}")
    log("=================================================================")

    if not os.path.exists(json_path):
        log("HATA: JSON kaynak dosyası bulunamadı!")
        return

    sha_before = sha256_file(json_path)
    log(f"Kaynak JSON SHA-256 (İşlem Öncesi): {sha_before}")

    with open(json_path, 'r', encoding='utf-8') as f:
        json_data = json.load(f)

    temp_dir = tempfile.mkdtemp(prefix="stage41_erkul_proto_")
    db_path = os.path.join(temp_dir, "erkul_reconstructed_legacy_v60.db")
    log(f"İzole Prototip Veritabanı Yolu: {db_path}")

    try:
        conn = sqlite3.connect(db_path)
        cur = conn.cursor()
        cur.execute("PRAGMA foreign_keys = ON;")
        
        log("1. Adım: Legacy v60 şeması izole dosyada oluşturuluyor...")
        create_legacy_schema(conn)

        log("2. Adım: JSON verisi ilişkisel tablolara yerleştiriliyor...")
        populate_from_json(conn, json_data)

        log("3. Adım: PRAGMA bütünlük ve Foreign Key kontrolleri icra ediliyor...")
        cur.execute("PRAGMA integrity_check;")
        integrity = cur.fetchall()
        log(f"Integrity Check: {integrity}")

        cur.execute("PRAGMA foreign_key_check;")
        fk_violations = cur.fetchall()
        log(f"Foreign Key İhlalleri (Sayı): {len(fk_violations)}")
        if fk_violations:
            log(f"FK İhlalleri Detay: {fk_violations}")

        # Tablo Sayımları
        counts = {}
        for t in ['products', 'customers', 'sales', 'sale_items', 'financial_transactions', 'orders', 'order_items', 'business_profile']:
            cur.execute(f"SELECT COUNT(*) FROM {t}")
            counts[t] = cur.fetchone()[0]
        log(f"Üretilen Tablo Satır Sayımları: {counts}")

        # Finansal Bakiye ve Stok Toplamları
        cur.execute("SELECT SUM(quantity) FROM products")
        total_stock = cur.fetchone()[0]
        cur.execute("SELECT SUM(balance), SUM(balance_minor) FROM customers")
        total_bal, total_bal_minor = cur.fetchone()
        cur.execute("SELECT SUM(total_amount), SUM(total_amount_minor) FROM sales")
        total_sales, total_sales_minor = cur.fetchone()
        cur.execute("SELECT SUM(amount), SUM(amount_minor) FROM financial_transactions")
        total_ft, total_ft_minor = cur.fetchone()

        log(f"Toplam Stok: {total_stock}")
        log(f"Toplam Müşteri Bakiyesi: {total_bal:.2f} TL ({total_bal_minor} kuruş)")
        log(f"Toplam Satış Tutarı: {total_sales:.2f} TL ({total_sales_minor} kuruş)")
        log(f"Toplam Finansal Hareket Tutarı: {total_ft:.2f} TL ({total_ft_minor} kuruş)")

        conn.close()

        proto_sha = sha256_file(db_path)
        proto_size = os.path.getsize(db_path)
        log(f"Üretilen Prototip SQLite Dosya Boyutu: {proto_size:,} bayt | SHA-256: {proto_sha}")

        # JSON dosyasının değişmezliğini doğrula
        sha_after = sha256_file(json_path)
        log(f"Kaynak JSON SHA-256 (İşlem Sonrası): {sha_after}")
        log(f"Kaynak Değişmezliği Korundu: {sha_before == sha_after}")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
        log("Geçici prototip klasörü temizlendi.")

if __name__ == "__main__":
    main()
