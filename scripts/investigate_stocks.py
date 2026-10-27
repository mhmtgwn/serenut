#!/usr/bin/env python3
"""
scripts/investigate_stocks.py
Deep forensic analysis of product counts, stock quantities, and stock movements.
Investigates the origins of 5,179,601 vs 5,179,604 vs 5,179,525.85.
"""

import os
import sys
import sqlite3
import json

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def examine_db(name, path):
    if not os.path.exists(path):
        print(f"[-] {name}: File not found at {path}")
        return None

    print(f"\n=======================================================")
    print(f"[*] Examining: {name}")
    print(f"    Path: {path}")
    print(f"    Size: {os.path.getsize(path):,} bytes")
    print(f"=======================================================")

    conn = sqlite3.connect(f"file:{os.path.abspath(path)}?mode=ro", uri=True)
    cur = conn.cursor()

    # User version
    cur.execute("PRAGMA user_version;")
    uv = cur.fetchone()[0]
    print(f"    PRAGMA user_version = {uv}")

    # Tables list
    cur.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [r[0] for r in cur.fetchall()]
    print(f"    Tables found ({len(tables)}): {', '.join(sorted(tables))}")

    # Schema for products
    prod_table = "products" if "products" in tables else None
    if prod_table:
        cur.execute(f"PRAGMA table_info({prod_table});")
        cols = [c[1] for c in cur.fetchall()]
        print(f"    Products columns: {cols}")

        stock_col = "stock_quantity" if "stock_quantity" in cols else "quantity" if "quantity" in cols else None
        print(f"    Stock column identified: {stock_col}")

        # Total count
        cur.execute(f"SELECT COUNT(*) FROM {prod_table};")
        total_prods = cur.fetchone()[0]

        # Queries on stock
        cur.execute(f"SELECT SUM({stock_col}), SUM(CAST({stock_col} AS REAL)), SUM(ROUND({stock_col}, 2)), SUM(CAST({stock_col} AS INTEGER)) FROM {prod_table};")
        s_raw, s_real, s_round, s_int = cur.fetchone()
        print(f"    Total Products: {total_prods:,}")
        print(f"    SUM({stock_col}) raw: {s_raw}")
        print(f"    SUM(CAST({stock_col} AS REAL)): {s_real}")
        print(f"    SUM(ROUND({stock_col}, 2)): {s_round}")
        print(f"    SUM(CAST({stock_col} AS INTEGER)): {s_int}")

        # Breakdown by active/deleted if columns exist
        if "is_deleted" in cols:
            cur.execute(f"SELECT is_deleted, COUNT(*), SUM(CAST({stock_col} AS REAL)) FROM {prod_table} GROUP BY is_deleted;")
            print(f"    Group by is_deleted: {cur.fetchall()}")
        if "is_active" in cols:
            cur.execute(f"SELECT is_active, COUNT(*), SUM(CAST({stock_col} AS REAL)) FROM {prod_table} GROUP BY is_active;")
            print(f"    Group by is_active: {cur.fetchall()}")

        # Check negative or decimal stocks
        cur.execute(f"SELECT COUNT(*), SUM(CAST({stock_col} AS REAL)) FROM {prod_table} WHERE CAST({stock_col} AS REAL) < 0;")
        print(f"    Negative stock products: {cur.fetchall()}")

        cur.execute(f"SELECT COUNT(*) FROM {prod_table} WHERE {stock_col} != CAST({stock_col} AS INTEGER);")
        print(f"    Fractional/decimal stock products: {cur.fetchone()[0]}")

    # Check stock movements / ledger / transactions
    for sm_table in ["stock_movements", "ledger_entries", "sales", "sale_items", "orders"]:
        if sm_table in tables:
            cur.execute(f"SELECT COUNT(*) FROM {sm_table};")
            print(f"    Table {sm_table}: {cur.fetchone()[0]:,} rows")
            if sm_table == "sale_items":
                cur.execute(f"PRAGMA table_info({sm_table});")
                si_cols = [c[1] for c in cur.fetchall()]
                qty_col = "quantity" if "quantity" in si_cols else None
                if qty_col:
                    cur.execute(f"SELECT SUM({qty_col}) FROM {sm_table};")
                    print(f"      Total Sale Items Qty: {cur.fetchone()[0]}")

    conn.close()

def main():
    base_roaming = r"C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS"
    onedrive_dir = r"C:\Users\notop\OneDrive\Belgeler\SerenutBackups"

    dbs = [
        ("Raw Nutopia Archive (v60)", os.path.join(base_roaming, r"backups\raw_tenants_20261016\raw_nutopia_v60.db")),
        ("Live Backup (19.10.2026 16:10)", os.path.join(onedrive_dir, "serenut_pos_backup_20261019_161042.db")),
        ("Previous Live Backup (19.10.2026 10:57)", os.path.join(onedrive_dir, "serenut_pos_backup_20261019_105708.db")),
        ("Core Next Nutopia DB", os.path.join(base_roaming, r"databases\core_next\nutopia_pos.db")),
        ("Core Next Serenut DB", os.path.join(base_roaming, r"databases\core_next\serenut_pos.db")),
        ("Core Next Erkul DB", os.path.join(base_roaming, r"databases\core_next\erkul_pos.db")),
        ("Raw Serenut v44 Archive", os.path.join(base_roaming, r"backups\raw_tenants_20261016\raw_serenut_v44.db")),
    ]

    for name, path in dbs:
        examine_db(name, path)

if __name__ == "__main__":
    main()
