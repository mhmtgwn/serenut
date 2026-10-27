#!/usr/bin/env python3
"""
scripts/stage10_12_42_isolated_import_rehearsal.py
SERENUT OS — STAGE 10.12.42
Yedek Kimliği Tutarlılık Denetimi + İzole Core Next Import Provası

GÜVENLİK SINIRLARI:
- Canlı veritabanına yazılmaz, migration veya cutover yapılmaz.
- Yalnızca izole geçici klasörlerde çalışır.
- Kaynak dosya hash'leri öncesi ve sonrası tam olarak doğrulanır.
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

CORE_NEXT_SCHEMA = [
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
      stock_quantity REAL NOT NULL DEFAULT 0.0,
      critical_threshold REAL NOT NULL DEFAULT 5.0,
      image_url TEXT,
      is_active INTEGER NOT NULL DEFAULT 1,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      updated_at INTEGER NOT NULL,
      FOREIGN KEY (category_id) REFERENCES categories (id) ON DELETE SET NULL
    );
    ''',
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
    '''
    CREATE TABLE IF NOT EXISTS sales (
      id TEXT PRIMARY KEY NOT NULL,
      receipt_no TEXT UNIQUE NOT NULL,
      customer_id TEXT,
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
      FOREIGN KEY (customer_id) REFERENCES customers (id) ON DELETE RESTRICT,
      FOREIGN KEY (reference_sale_id) REFERENCES sales (id) ON DELETE SET NULL
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS cash_transactions (
      id TEXT PRIMARY KEY NOT NULL,
      type TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      category TEXT NOT NULL,
      description TEXT,
      created_at INTEGER NOT NULL
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS orders (
      id TEXT PRIMARY KEY NOT NULL,
      order_number TEXT UNIQUE NOT NULL,
      customer_id TEXT,
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
    '''
    CREATE TABLE IF NOT EXISTS sale_payments (
      id TEXT PRIMARY KEY NOT NULL,
      sale_id TEXT NOT NULL,
      payment_type TEXT NOT NULL,
      amount_cents INTEGER NOT NULL,
      reference_note TEXT,
      created_at INTEGER NOT NULL,
      FOREIGN KEY (sale_id) REFERENCES sales (id) ON DELETE CASCADE
    );
    ''',
    '''
    CREATE TABLE IF NOT EXISTS app_settings (
      key TEXT PRIMARY KEY NOT NULL,
      value TEXT NOT NULL,
      updated_at INTEGER NOT NULL
    );
    '''
]

def rehearse_nutopia_migration(src_path):
    log("=================================================================")
    log("NUTOPIA: EN GÜNCEL DOĞRULANMIŞ KAYNAKTAN İZOLE CORE NEXT MIGRATION")
    log(f"Kaynak: {src_path}")
    log("=================================================================")

    sha_before = sha256_file(src_path)
    size_before = os.path.getsize(src_path)
    log(f"Kaynak Dosya Boyutu: {size_before:,} bayt | SHA-256: {sha_before}")

    temp_dir = tempfile.mkdtemp(prefix="stage42_nutopia_rehearsal_")
    isolated_src = os.path.join(temp_dir, "isolated_nutopia_src.db")
    isolated_target = os.path.join(temp_dir, "nutopia_core_next_v3.db")

    try:
        shutil.copy2(src_path, isolated_src)
        log("Kaynak veritabanının izole test kopyası oluşturuldu.")

        target_conn = sqlite3.connect(isolated_target)
        target_cur = target_conn.cursor()
        target_cur.execute("PRAGMA foreign_keys = ON;")
        for q in CORE_NEXT_SCHEMA:
            target_cur.execute(q)
        target_conn.commit()
        log("Core Next v3 hedef şeması izole hedef veritabanında oluşturuldu.")

        src_conn = sqlite3.connect(isolated_src)
        src_cur = src_conn.cursor()

        # 1. Categories
        categories = src_cur.execute("SELECT DISTINCT category FROM products WHERE category IS NOT NULL AND category != '';").fetchall()
        for idx, (cat_name,) in enumerate(categories):
            cat_id = f"cat-{cat_name.lower().replace(' ', '_')}"
            target_cur.execute(
                "INSERT OR IGNORE INTO categories (id, name, sort_order, is_active, updated_at) VALUES (?, ?, ?, 1, ?)",
                (cat_id, cat_name, idx, int(datetime.now().timestamp() * 1000))
            )
        target_conn.commit()

        # 2. Products
        prods = src_cur.execute("SELECT id, name, price, purchase_price, quantity, sku, category, is_active, is_deleted, updated_at FROM products;").fetchall()
        for p in prods:
            pid, name, price, cost, qty, sku, cat, is_active, is_deleted, updated_at = p
            bc = sku or f"BC-{pid}"
            cat_id = f"cat-{cat.lower().replace(' ', '_')}" if cat else None
            price_cents = round((price or 0.0) * 100)
            cost_cents = round((cost or 0.0) * 100)
            up_ms = int(datetime.now().timestamp() * 1000)
            target_cur.execute(
                """INSERT OR IGNORE INTO products (
                    id, barcode, name, category_id, price_cents, cost_price_cents,
                    vat_rate, unit, stock_quantity, is_active, is_deleted, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, 20, 'piece', ?, ?, ?, ?)""",
                (pid, bc, name, cat_id, price_cents, cost_cents, qty or 0.0, is_active or 1, is_deleted or 0, up_ms)
            )
        target_conn.commit()

        # 3. Customers
        custs = src_cur.execute("SELECT id, name, phone, email, balance, is_active, is_deleted, updated_at FROM customers;").fetchall()
        for c in custs:
            cid, name, phone, email, bal, is_active, is_deleted, updated_at = c
            bal_cents = round((bal or 0.0) * 100)
            up_ms = int(datetime.now().timestamp() * 1000)
            target_cur.execute(
                """INSERT OR IGNORE INTO customers (
                    id, name, phone, email, balance_cents, is_active, is_deleted, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (cid, name, phone, email, bal_cents, is_active or 1, is_deleted or 0, up_ms)
            )
        target_conn.commit()

        # 4. Sales & Sale Items
        sales = src_cur.execute("SELECT id, customer_id, total_amount, paid_amount, payment_method, created_at FROM sales;").fetchall()
        for s in sales:
            sid, cid, total, paid, pmethod, c_at = s
            tot_cents = round((total or 0.0) * 100)
            paid_cents = round((paid or 0.0) * 100)
            debt_cents = max(0, tot_cents - paid_cents)
            c_ms = int(datetime.now().timestamp() * 1000)
            target_cur.execute(
                """INSERT OR IGNORE INTO sales (
                    id, receipt_no, customer_id, subtotal_cents, discount_cents,
                    vat_total_cents, total_cents, paid_cents, debt_cents, status, created_at
                ) VALUES (?, ?, ?, ?, 0, 0, ?, ?, ?, 'COMPLETED', ?)""",
                (sid, f"REC-{sid}", cid, tot_cents, tot_cents, paid_cents, debt_cents, c_ms)
            )
        target_conn.commit()

        items = src_cur.execute("SELECT id, sale_id, product_id, product_name, quantity, unit_price, subtotal FROM sale_items;").fetchall()
        for it in items:
            iid, sid, pid, pname, qty, uprice, subtot = it
            up_cents = round((uprice or 0.0) * 100)
            tot_cents = round((subtot or (qty * uprice) or 0.0) * 100)
            target_cur.execute(
                """INSERT OR IGNORE INTO sale_items (
                    id, sale_id, product_id, barcode, product_name, unit_price_cents,
                    quantity, discount_cents, vat_rate, total_cents
                ) VALUES (?, ?, ?, ?, ?, ?, ?, 0, 20, ?)""",
                (iid, sid, pid, f"BC-{pid}", pname or "Ürün", up_cents, qty or 1.0, tot_cents)
            )
        target_conn.commit()

        # 5. Orders & Order Items
        orders = src_cur.execute("SELECT id, order_number, customer_id, status, total_amount, order_date, notes, created_at FROM orders;").fetchall()
        for o in orders:
            oid, ono, cid, status, tot, odate, notes, cat = o
            tot_cents = round((tot or 0.0) * 100)
            c_ms = int(datetime.now().timestamp() * 1000)
            target_cur.execute(
                """INSERT OR IGNORE INTO orders (
                    id, order_number, customer_id, status, total_amount_cents,
                    discount_amount_cents, order_date, notes, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, 0, ?, ?, ?, ?)""",
                (oid, ono or f"ORD-{oid}", cid, status or "pending", tot_cents, c_ms, notes, c_ms, c_ms)
            )
        target_conn.commit()

        oitems = src_cur.execute("SELECT id, order_id, product_id, product_name, quantity, unit_price, created_at FROM order_items;").fetchall()
        for oi in oitems:
            oiid, oid, pid, pname, qty, uprice, cat = oi
            up_cents = round((uprice or 0.0) * 100)
            tot_cents = round(qty * up_cents)
            c_ms = int(datetime.now().timestamp() * 1000)
            target_cur.execute(
                """INSERT OR IGNORE INTO order_items (
                    id, order_id, product_id, barcode, product_name, quantity,
                    unit_price_cents, total_cents, created_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)""",
                (oiid, oid, pid, f"BC-{pid}", pname or "Ürün", qty or 1.0, up_cents, tot_cents, c_ms)
            )
        target_conn.commit()

        # 6. Financial Transactions -> Ledger / Cash Transactions
        fts = src_cur.execute("SELECT id, customer_id, reference_id, type, amount, description, created_at FROM financial_transactions;").fetchall()
        cust_set = set(r[0] for r in target_cur.execute("SELECT id FROM customers;").fetchall())
        sales_set = set(r[0] for r in target_cur.execute("SELECT id FROM sales;").fetchall())
        running_balances = {}
        for ft in fts:
            fid, cid, ref_id, ftype, amt, desc, cat = ft
            amt_cents = round((amt or 0.0) * 100)
            c_ms = int(datetime.now().timestamp() * 1000)
            if not cid or cid not in cust_set:
                target_cur.execute(
                    """INSERT OR IGNORE INTO cash_transactions (
                        id, type, amount_cents, category, description, created_at
                    ) VALUES (?, 'INFLOW', ?, 'SALE', ?, ?)""",
                    (fid, amt_cents, desc or "Nakit Kasa Hareketi", c_ms)
                )
            else:
                curr = running_balances.get(cid, 0)
                is_debt = any(k in (ftype or "").upper() for k in ["SALE", "DEBT", "BORC"])
                new_bal = curr - amt_cents if is_debt else curr + amt_cents
                running_balances[cid] = new_bal
                ref_sale_id = ref_id if (ref_id and ref_id in sales_set) else None
                target_cur.execute(
                    """INSERT OR IGNORE INTO ledger_entries (
                        id, customer_id, reference_sale_id, entry_type, amount_cents,
                        balance_after_cents, description, created_at
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                    (fid, cid, ref_sale_id, (ftype or "ADJUSTMENT").upper(), amt_cents, new_bal, desc or "Cari Hareket", c_ms)
                )
        target_conn.commit()

        # 7. Verification: Integrity & Foreign Keys
        integrity = target_cur.execute("PRAGMA integrity_check;").fetchall()
        fk_violations = target_cur.execute("PRAGMA foreign_key_check;").fetchall()

        log(f"Core Next Hedef Integrity Check: {integrity}")
        log(f"Core Next Hedef Foreign Key İhlalleri: {len(fk_violations)}")

        # Row counts
        counts = {}
        for tbl in ["products", "customers", "sales", "sale_items", "orders", "order_items", "ledger_entries", "cash_transactions"]:
            counts[tbl] = target_cur.execute(f"SELECT COUNT(*) FROM {tbl};").fetchone()[0]

        log(f"Hedef Core Next Satır Sayımları: {counts}")

        # Idempotency Test: re-inserting all customers
        initial_cust_count = counts["customers"]
        for c in custs:
            cid, name, phone, email, bal, is_active, is_deleted, updated_at = c
            bal_cents = round((bal or 0.0) * 100)
            up_ms = int(datetime.now().timestamp() * 1000)
            target_cur.execute(
                """INSERT OR IGNORE INTO customers (
                    id, name, phone, email, balance_cents, is_active, is_deleted, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?)""",
                (cid, name, phone, email, bal_cents, is_active or 1, is_deleted or 0, up_ms)
            )
        target_conn.commit()
        recheck_cust_count = target_cur.execute("SELECT COUNT(*) FROM customers;").fetchone()[0]
        log(f"İdempotens Testi (Müşteri Sayısı Değişmedi): {initial_cust_count == recheck_cust_count} ({recheck_cust_count})")

        src_conn.close()
        target_conn.close()

        sha_after = sha256_file(src_path)
        log(f"Kaynak Dosya SHA-256 (İşlem Sonrası): {sha_after}")
        log(f"Kaynak Değişmezliği Korundu: {sha_before == sha_after}")

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
        log("Geçici prova klasörü temizlendi.")

def rehearse_erkul_feasibility(json_path):
    log("=================================================================")
    log("ERKUL: JSON'DAN CORE NEXT'E İZOLE İMPORT FİZİBİLİTESİ VE ANALİZİ")
    log(f"Kaynak: {json_path}")
    log("=================================================================")

    sha_before = sha256_file(json_path)
    log(f"Kaynak JSON SHA-256: {sha_before}")

    with open(json_path, "r", encoding="utf-8") as f:
        data = json.load(f)

    customers = data.get("customers", [])
    products = data.get("products", [])
    sales = data.get("sales", [])
    sale_items = data.get("sale_items", [])
    financial_transactions = data.get("financial_transactions", [])
    orders = data.get("customer_orders", [])
    order_items = data.get("customer_order_items", [])

    log(f"JSON Varlık Sayımları: Müşteri={len(customers)}, Ürün={len(products)}, Satış={len(sales)}, Kalem={len(sale_items)}, FT={len(financial_transactions)}, Sipariş={len(orders)}, SiparişKalem={len(order_items)}")

    # Discrepancy analysis
    cust_balances = {c["id"]: c.get("balance", 0.0) for c in customers}
    diff_count = 0
    total_bal = sum(cust_balances.values())
    tot_ft_in = sum(ft.get("amount", 0.0) for ft in financial_transactions if ft.get("type") in ("collection", "payment"))
    tot_ft_out = sum(ft.get("amount", 0.0) for ft in financial_transactions if ft.get("type") in ("sale", "manual_debt"))
    net_ft = tot_ft_in - tot_ft_out

    for c in customers:
        cid = c["id"]
        bal = c.get("balance", 0.0)
        calc = 0.0
        for ft in financial_transactions:
            if ft.get("customer_id") == cid:
                ttype = ft.get("type")
                amt = ft.get("amount", 0.0)
                if ttype in ("sale", "manual_debt"):
                    calc -= amt
                elif ttype in ("collection", "payment"):
                    calc += amt
        if abs(bal - calc) > 0.01:
            diff_count += 1

    log(f"Müşteri Bakiye Toplamı: {total_bal:,.2f} TL")
    log(f"FT Giriş: {tot_ft_in:,.2f} TL | FT Çıkış: {tot_ft_out:,.2f} TL | FT Net Etki: {net_ft:,.2f} TL")
    log(f"Toplam Bakiye - FT Net Farkı: {total_bal - net_ft:,.2f} TL")
    log(f"Bakiye-Defter Uyuşmazlığı Olan Cari Sayısı: {diff_count} / {len(customers)} ({diff_count / len(customers) * 100:.1f}%)")

    # Isolated conversion to Core Next
    temp_dir = tempfile.mkdtemp(prefix="stage42_erkul_rehearsal_")
    isolated_target = os.path.join(temp_dir, "erkul_core_next_v3.db")

    try:
        target_conn = sqlite3.connect(isolated_target)
        target_cur = target_conn.cursor()
        target_cur.execute("PRAGMA foreign_keys = ON;")
        for q in CORE_NEXT_SCHEMA:
            target_cur.execute(q)
        target_conn.commit()

        # Insert products
        for p in products:
            pid = p["id"]
            name = p.get("name", "Ürün")
            bc = p.get("barcode") or p.get("sku") or f"BC-{pid}"
            price_cents = round((p.get("price") or 0.0) * 100)
            cost_cents = round((p.get("purchase_price") or 0.0) * 100)
            qty = p.get("stock") or 0.0
            target_cur.execute(
                """INSERT OR IGNORE INTO products (
                    id, barcode, name, price_cents, cost_price_cents, vat_rate,
                    unit, stock_quantity, is_active, is_deleted, updated_at
                ) VALUES (?, ?, ?, ?, ?, 20, 'piece', ?, 1, 0, ?)""",
                (pid, bc, name, price_cents, cost_cents, qty, int(datetime.now().timestamp() * 1000))
            )

        # Insert customers
        for c in customers:
            cid = c["id"]
            name = c.get("name", "Müşteri")
            bal_cents = round((c.get("balance") or 0.0) * 100)
            target_cur.execute(
                """INSERT OR IGNORE INTO customers (
                    id, name, phone, email, balance_cents, is_active, is_deleted, updated_at
                ) VALUES (?, ?, ?, ?, ?, 1, 0, ?)""",
                (cid, name, c.get("phone"), c.get("email"), bal_cents, int(datetime.now().timestamp() * 1000))
            )

        # Insert sales & sale_items
        for s in sales:
            sid = s["id"]
            rec = s.get("receipt_no") or f"REC-{sid}"
            cid = s.get("customer_id")
            tot_cents = round((s.get("total_amount") or 0.0) * 100)
            target_cur.execute(
                """INSERT OR IGNORE INTO sales (
                    id, receipt_no, customer_id, subtotal_cents, discount_cents,
                    vat_total_cents, total_cents, paid_cents, debt_cents, status, created_at
                ) VALUES (?, ?, ?, ?, 0, 0, ?, ?, 0, 'COMPLETED', ?)""",
                (sid, rec, cid, tot_cents, tot_cents, tot_cents, int(datetime.now().timestamp() * 1000))
            )

        for it in sale_items:
            iid = it["id"]
            sid = it.get("sale_id")
            pid = it.get("product_id")
            qty = it.get("quantity") or 1.0
            up_cents = round((it.get("unit_price") or 0.0) * 100)
            tot_cents = round((it.get("total_price") or 0.0) * 100)
            target_cur.execute(
                """INSERT OR IGNORE INTO sale_items (
                    id, sale_id, product_id, barcode, product_name, unit_price_cents,
                    quantity, discount_cents, vat_rate, total_cents
                ) VALUES (?, ?, ?, ?, 'Ürün', ?, ?, 0, 20, ?)""",
                (iid, sid, pid, f"BC-{pid}", up_cents, qty, tot_cents)
            )

        # Insert orders & order_items
        for o in orders:
            oid = o["id"]
            ono = o.get("order_number") or f"ORD-{oid}"
            cid = o.get("customer_id")
            tot_cents = round((o.get("total_amount") or 0.0) * 100)
            target_cur.execute(
                """INSERT OR IGNORE INTO orders (
                    id, order_number, customer_id, status, total_amount_cents,
                    discount_amount_cents, order_date, created_at, updated_at
                ) VALUES (?, ?, ?, 'pending', ?, 0, ?, ?, ?)""",
                (oid, ono, cid, tot_cents, int(datetime.now().timestamp() * 1000), int(datetime.now().timestamp() * 1000), int(datetime.now().timestamp() * 1000))
            )

        for oi in order_items:
            oiid = oi["id"]
            oid = oi.get("order_id")
            pid = oi.get("product_id")
            qty = oi.get("quantity") or 1.0
            up_cents = round((oi.get("unit_price") or 0.0) * 100)
            tot_cents = round((oi.get("total_price") or (qty * (oi.get("unit_price") or 0.0))) * 100)
            target_cur.execute(
                """INSERT OR IGNORE INTO order_items (
                    id, order_id, product_id, barcode, product_name, quantity,
                    unit_price_cents, total_cents, created_at
                ) VALUES (?, ?, ?, ?, 'Ürün', ?, ?, ?, ?)""",
                (oiid, oid, pid, f"BC-{pid}", qty, up_cents, tot_cents, int(datetime.now().timestamp() * 1000))
            )

        # Insert ledger entries
        running = {}
        for ft in financial_transactions:
            fid = ft["id"]
            cid = ft.get("customer_id")
            amt_cents = round((ft.get("amount") or 0.0) * 100)
            ftype = (ft.get("type") or "ADJUSTMENT").upper()
            curr = running.get(cid, 0)
            is_debt = any(k in ftype for k in ["SALE", "DEBT", "BORC"])
            new_bal = curr - amt_cents if is_debt else curr + amt_cents
            running[cid] = new_bal
            target_cur.execute(
                """INSERT OR IGNORE INTO ledger_entries (
                    id, customer_id, reference_sale_id, entry_type, amount_cents,
                    balance_after_cents, description, created_at
                ) VALUES (?, ?, NULL, ?, ?, ?, ?, ?)""",
                (fid, cid, ftype, amt_cents, new_bal, ft.get("description") or "Hareket", int(datetime.now().timestamp() * 1000))
            )

        target_conn.commit()

        integrity = target_cur.execute("PRAGMA integrity_check;").fetchall()
        fk_violations = target_cur.execute("PRAGMA foreign_key_check;").fetchall()

        log(f"Erkul Core Next Hedef Integrity Check: {integrity}")
        log(f"Erkul Core Next Hedef Foreign Key İhlalleri: {len(fk_violations)}")

        target_conn.close()

    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
        log("Erkul prova klasörü temizlendi.")

def main():
    onedrive_backup = r"C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db"
    erkul_json = r"C:\Users\notop\AndroidStudioProjects\shaman_new\backups\raw_tenants_20261016\raw_erkul_source.json"

    rehearse_nutopia_migration(onedrive_backup)
    print("\n")
    rehearse_erkul_feasibility(erkul_json)

if __name__ == "__main__":
    main()
