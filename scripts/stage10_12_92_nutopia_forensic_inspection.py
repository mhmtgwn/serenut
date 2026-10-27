#!/usr/bin/env python3
"""
scripts/stage10_12_92_nutopia_forensic_inspection.py
SERENUT OS — STAGE 10.12.92
Adli Nutopia Kaynak ve Hedef Veri Durumu Denetimi

Salt-okunur (read-only) çalışır. Canlı ve yedek dosyalarda tek bir bayt dahi değiştirilmez.
"""

import os
import sys
import json
import sqlite3
import hashlib
from datetime import datetime

# Windows cp1254 output crash prevention
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

def inspect_legacy_db(path):
    if not os.path.exists(path):
        return {"exists": False}
    
    size = os.path.getsize(path)
    sha = sha256_file(path)
    
    # Read-only URI connection
    uri = f"file:{os.path.abspath(path)}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    
    # Integrity
    cur.execute("PRAGMA integrity_check;")
    integrity = cur.fetchall()
    integrity_ok = len(integrity) > 0 and integrity[0][0] == "ok"
    
    # Tables
    cur.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [r[0] for r in cur.fetchall()]
    
    # Business name & tenant
    bname = ""
    tenant_id = ""
    if "settings" in tables:
        try:
            cur.execute("SELECT * FROM settings LIMIT 10;")
            s_rows = cur.fetchall()
            for r in s_rows:
                keys = r.keys()
                if "business_name" in keys:
                    bname = r["business_name"] or ""
                if "tenant_id" in keys:
                    tenant_id = r["tenant_id"] or ""
                if "key" in keys and "value" in keys:
                    if r["key"] == "business_name":
                        bname = r["value"] or ""
                    elif r["key"] == "tenant_id":
                        tenant_id = r["value"] or ""
        except Exception as e:
            bname = f"err: {e}"

    # Counts
    def get_count(t):
        if t in tables:
            try:
                cur.execute(f"SELECT COUNT(*) FROM {t};")
                return cur.fetchone()[0]
            except:
                return -1
        return 0

    product_count = get_count("products")
    active_products = 0
    stock_sum = 0.0
    if "products" in tables:
        try:
            cur.execute("SELECT COUNT(*), COALESCE(SUM(quantity), 0.0) FROM products WHERE is_active = 1 OR is_active IS NULL;")
            r = cur.fetchone()
            active_products = r[0]
            stock_sum = float(r[1])
        except Exception:
            pass

    customer_count = get_count("customers")
    customer_balance_sum = 0.0
    if "customers" in tables:
        try:
            cur.execute("SELECT COALESCE(SUM(balance), 0.0) FROM customers;")
            customer_balance_sum = float(cur.fetchone()[0])
        except Exception:
            pass

    sales_count = get_count("sales")
    sales_total_volume = 0.0
    if "sales" in tables:
        try:
            cur.execute("SELECT COALESCE(SUM(total_amount), 0.0) FROM sales;")
            sales_total_volume = float(cur.fetchone()[0])
        except Exception:
            pass

    sale_items_count = get_count("sale_items")
    orders_count = get_count("orders")
    order_items_count = get_count("order_items")
    
    ledger_count = get_count("ledger_entries")
    ledger_breakdown = {}
    if "ledger_entries" in tables:
        try:
            cur.execute("SELECT type, COUNT(*), COALESCE(SUM(amount), 0.0) FROM ledger_entries GROUP BY type;")
            for r in cur.fetchall():
                ledger_breakdown[r[0]] = {"count": r[1], "sum_tl": float(r[2])}
        except Exception:
            pass

    cash_tx_count = get_count("cash_transactions")
    conn.close()

    return {
        "exists": True,
        "path": path,
        "size_bytes": size,
        "sha256": sha,
        "integrity_ok": integrity_ok,
        "tables": tables,
        "business_name": bname,
        "tenant_id": tenant_id,
        "product_count": product_count,
        "active_products": active_products,
        "stock_sum": stock_sum,
        "customer_count": customer_count,
        "customer_balance_sum": customer_balance_sum,
        "sales_count": sales_count,
        "sales_total_volume": sales_total_volume,
        "sale_items_count": sale_items_count,
        "orders_count": orders_count,
        "order_items_count": order_items_count,
        "ledger_count": ledger_count,
        "ledger_breakdown": ledger_breakdown,
        "cash_tx_count": cash_tx_count,
    }

def inspect_core_next_db(path):
    if not os.path.exists(path):
        return {"exists": False}
    
    size = os.path.getsize(path)
    sha = sha256_file(path)
    
    uri = f"file:{os.path.abspath(path)}?mode=ro"
    conn = sqlite3.connect(uri, uri=True)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()
    
    cur.execute("PRAGMA integrity_check;")
    integrity = cur.fetchall()
    integrity_ok = len(integrity) > 0 and integrity[0][0] == "ok"

    cur.execute("PRAGMA foreign_key_check;")
    fk_violations = cur.fetchall()

    cur.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [r[0] for r in cur.fetchall()]

    tenant_id = ""
    bname = ""
    if "app_settings" in tables:
        try:
            cur.execute("SELECT key, value FROM app_settings WHERE key IN ('tenant_id', 'business_name');")
            for r in cur.fetchall():
                if r["key"] == "tenant_id":
                    tenant_id = r["value"]
                elif r["key"] == "business_name":
                    bname = r["value"]
        except:
            pass

    def get_count(t):
        if t in tables:
            try:
                cur.execute(f"SELECT COUNT(*) FROM {t};")
                return cur.fetchone()[0]
            except:
                return -1
        return 0

    product_count = get_count("products")
    active_products = 0
    stock_sum = 0.0
    if "products" in tables:
        try:
            cur.execute("SELECT COUNT(*), COALESCE(SUM(stock_quantity), 0.0) FROM products WHERE is_active = 1;")
            r = cur.fetchone()
            active_products = r[0]
            stock_sum = float(r[1])
        except Exception:
            pass

    customer_count = get_count("customers")
    customer_balance_cents_sum = 0
    if "customers" in tables:
        try:
            cur.execute("SELECT COALESCE(SUM(balance_cents), 0) FROM customers;")
            customer_balance_cents_sum = cur.fetchone()[0]
        except Exception:
            pass

    sales_count = get_count("sales")
    sales_total_cents = 0
    if "sales" in tables:
        try:
            cur.execute("SELECT COALESCE(SUM(final_amount_cents), 0) FROM sales;")
            sales_total_cents = cur.fetchone()[0]
        except Exception:
            pass

    sale_items_count = get_count("sale_items")
    orders_count = get_count("orders")
    order_items_count = get_count("order_items")
    
    ledger_count = get_count("ledger_entries")
    ledger_breakdown = {}
    if "ledger_entries" in tables:
        try:
            cur.execute("SELECT type, COUNT(*), COALESCE(SUM(amount_cents), 0) FROM ledger_entries GROUP BY type;")
            for r in cur.fetchall():
                ledger_breakdown[r[0]] = {"count": r[1], "sum_cents": r[2], "sum_tl": r[2] / 100.0}
        except Exception:
            pass

    payments_count = get_count("payments")
    refunds_count = get_count("refunds")
    outbox_count = get_count("outbox")

    conn.close()

    return {
        "exists": True,
        "path": path,
        "size_bytes": size,
        "sha256": sha,
        "integrity_ok": integrity_ok,
        "fk_violations_count": len(fk_violations),
        "tables": tables,
        "business_name": bname,
        "tenant_id": tenant_id,
        "product_count": product_count,
        "active_products": active_products,
        "stock_sum": stock_sum,
        "customer_count": customer_count,
        "customer_balance_cents_sum": customer_balance_cents_sum,
        "customer_balance_tl": customer_balance_cents_sum / 100.0,
        "sales_count": sales_count,
        "sales_total_cents": sales_total_cents,
        "sales_total_tl": sales_total_cents / 100.0,
        "sale_items_count": sale_items_count,
        "orders_count": orders_count,
        "order_items_count": order_items_count,
        "ledger_count": ledger_count,
        "ledger_breakdown": ledger_breakdown,
        "payments_count": payments_count,
        "refunds_count": refunds_count,
        "outbox_count": outbox_count,
    }

def main():
    log("=================================================================")
    log("STAGE 10.12.92 — NUTOPIA KAYNAK VE HEDEF ADLİ İNCELEME")
    log("=================================================================")

    roaming = os.environ.get("APPDATA", "")
    live_app_dir = os.path.join(roaming, "Serenut OS Software Technologies A.Ş", "Serenut OS")
    live_legacy_path = os.path.join(live_app_dir, "databases", "serenut_pos.db")
    live_core_path1 = os.path.join(live_app_dir, "databases", "serenut_core_v2.db")
    live_core_path2 = os.path.join(live_app_dir, "databases", "core_next", "serenut_core_v2.db")

    stage84_backup = os.path.abspath(r"backups\nutopia_pre_cutover_20261021_stage84\serenut_pos_live_backup.db")
    stage2055_backup = os.path.abspath(r"backups\nutopia_live_20261021_2055\nutopia_live_backup.db")
    raw16_nutopia = os.path.abspath(r"backups\raw_tenants_20261016\raw_nutopia_v60.db")

    stage2055_core = os.path.abspath(r"backups\nutopia_live_20261021_2055\nutopia_core_next_live.db")
    stage64_core = os.path.abspath(r"backups\stage64_isolated\nutopia\nutopia_core_next.db")

    report = {
        "timestamp": datetime.now().isoformat(),
        "sources": {
            "live_legacy": inspect_legacy_db(live_legacy_path),
            "stage84_backup": inspect_legacy_db(stage84_backup),
            "stage2055_backup": inspect_legacy_db(stage2055_backup),
            "raw16_nutopia": inspect_legacy_db(raw16_nutopia),
        },
        "targets": {
            "live_core1": inspect_core_next_db(live_core_path1),
            "live_core2": inspect_core_next_db(live_core_path2),
            "stage2055_core": inspect_core_next_db(stage2055_core),
            "stage64_core": inspect_core_next_db(stage64_core),
        }
    }

    out_file = os.path.abspath(r"outputs\stage10_12_92_nutopia_inspection.json")
    os.makedirs(os.path.dirname(out_file), exist_ok=True)
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)

    log(f"İnceleme raporu kaydedildi: {out_file}")
    
    # Print summary table
    print("\n" + "="*80)
    print("KAYNAK VERİTABANLARI KARŞILAŞTIRMASI:")
    print("="*80)
    for k, v in report["sources"].items():
        if v.get("exists"):
            print(f"[{k.upper()}] Path: {v['path']}")
            print(f"  Boyut: {v['size_bytes']:,} B | SHA256: {v['sha256']}")
            print(f"  Bütünlük: {v['integrity_ok']} | İşletme: {v['business_name']} | Tenant: {v['tenant_id']}")
            print(f"  Ürün: {v['product_count']} (Aktif: {v['active_products']}, Stok: {v['stock_sum']:.2f})")
            print(f"  Müşteri: {v['customer_count']} (Bakiye: {v['customer_balance_sum']:.2f} TL)")
            print(f"  Satış: {v['sales_count']} (Hacim: {v['sales_total_volume']:.2f} TL) | Kalem: {v['sale_items_count']}")
            print(f"  Defter (Ledger): {v['ledger_count']} | Kasa Tx: {v['cash_tx_count']}")
            print(f"  Defter Dağılım: {v['ledger_breakdown']}")
            print("-" * 60)
        else:
            print(f"[{k.upper()}] Dosya bulunamadı!")

    print("\n" + "="*80)
    print("HEDEF CORE NEXT VERİTABANLARI KARŞILAŞTIRMASI:")
    print("="*80)
    for k, v in report["targets"].items():
        if v.get("exists"):
            print(f"[{k.upper()}] Path: {v['path']}")
            print(f"  Boyut: {v['size_bytes']:,} B | SHA256: {v['sha256']}")
            print(f"  Bütünlük: {v['integrity_ok']} | FK İhlali: {v['fk_violations_count']} | Tenant: {v['tenant_id']}")
            print(f"  Ürün: {v['product_count']} (Aktif: {v['active_products']}, Stok: {v['stock_sum']:.2f})")
            print(f"  Müşteri: {v['customer_count']} (Bakiye: {v['customer_balance_tl']:.2f} TL, Kuruş: {v['customer_balance_cents_sum']})")
            print(f"  Satış: {v['sales_count']} (Hacim: {v['sales_total_tl']:.2f} TL, Kuruş: {v['sales_total_cents']}) | Kalem: {v['sale_items_count']}")
            print(f"  Defter (Ledger): {v['ledger_count']}")
            print(f"  Defter Dağılım: {v['ledger_breakdown']}")
            print("-" * 60)
        else:
            print(f"[{k.upper()}] Dosya bulunamadı!")

if __name__ == "__main__":
    main()
