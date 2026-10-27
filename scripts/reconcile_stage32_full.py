#!/usr/bin/env python3
"""
scripts/reconcile_stage32_full.py
Stage 10.12.32: Full Data Reconciliation & Schema Analysis
Compares Source DB (both baseline and live) with Core Next Target DB.
"""

import os
import sys
import sqlite3
import json
import hashlib

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def get_db_info(path):
    if not os.path.exists(path):
        return None
    conn = sqlite3.connect(f"file:{os.path.abspath(path)}?mode=ro", uri=True)
    cur = conn.cursor()
    
    # User version
    cur.execute("PRAGMA user_version;")
    uv = cur.fetchone()[0]
    
    # Tables and row counts
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%';")
    tables = [r[0] for r in cur.fetchall()]
    
    schema = {}
    counts = {}
    pks = {}
    
    for t in tables:
        try:
            cur.execute(f"SELECT COUNT(*) FROM {t};")
            counts[t] = cur.fetchone()[0]
        except Exception as e:
            counts[t] = f"ERROR: {e}"
            
        cur.execute(f"PRAGMA table_info({t});")
        cols = cur.fetchall()
        schema[t] = [c[1] for c in cols]
        pk_cols = [c[1] for c in cols if c[5] > 0]
        pks[t] = pk_cols
        
    conn.close()
    return {
        "path": path,
        "size_bytes": os.path.getsize(path),
        "user_version": uv,
        "tables": sorted(tables),
        "counts": counts,
        "schema": schema,
        "pks": pks
    }

def main():
    base_roaming = r"C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS"
    onedrive_dir = r"C:\Users\notop\OneDrive\Belgeler\SerenutBackups"
    
    raw_nutopia = os.path.join(base_roaming, r"backups\raw_tenants_20261016\raw_nutopia_v60.db")
    live_backup = os.path.join(onedrive_dir, "serenut_pos_backup_20261019_161042.db")
    core_next_nutopia = os.path.join(base_roaming, r"databases\core_next\nutopia_pos.db")
    
    info_raw = get_db_info(raw_nutopia)
    info_live = get_db_info(live_backup)
    info_core = get_db_info(core_next_nutopia)
    
    print("==================================================")
    print("STAGE 10.12.32: RECONCILIATION SUMMARY")
    print("==================================================")
    
    # 1. Compare tables
    print(f"\n1. TABLE INVENTORY:")
    print(f"   Raw Nutopia (v{info_raw['user_version']}): {len(info_raw['tables'])} tables")
    print(f"   Live Backup (v{info_live['user_version']}): {len(info_live['tables'])} tables")
    print(f"   Core Next Target (v{info_core['user_version']}): {len(info_core['tables'])} tables")
    
    # Common core business entities
    mapping = [
        ("products", "products"),
        ("customers", "customers"),
        ("sales", "sales"),
        ("sale_items", "sale_items"),
        ("orders", "orders"),
        ("order_items", "order_items"),
        ("customer_installment_plans", "customer_installment_plans"),
        ("customer_installments", "customer_installments"),
        ("cash_counts", "cash_counts"),
        ("cash_expenses", "cash_expenses"),
        ("users", "users"),
        ("audit_events", "audit_events"),
    ]
    
    print(f"\n2. BUSINESS ENTITY COUNT COMPARISON:")
    print(f"{'Entity':<28} | {'Raw Baseline':<12} | {'Live Backup':<12} | {'Core Next':<12} | {'Diff (Core - Baseline)'}")
    print("-" * 85)
    for src_t, tgt_t in mapping:
        raw_cnt = info_raw['counts'].get(src_t, "N/A")
        live_cnt = info_live['counts'].get(src_t, "N/A")
        core_cnt = info_core['counts'].get(tgt_t, "N/A")
        
        diff = ""
        if isinstance(raw_cnt, int) and isinstance(core_cnt, int):
            diff = str(core_cnt - raw_cnt)
        elif raw_cnt == "N/A" and core_cnt != "N/A":
            diff = f"+{core_cnt} (New)"
        print(f"{src_t:<28} | {str(raw_cnt):<12} | {str(live_cnt):<12} | {str(core_cnt):<12} | {diff}")
        
    # Extra Core Next tables
    print(f"\n3. CORE NEXT SPECIFIC TABLES:")
    core_extras = ["ledger_entries", "sale_payments", "cash_transactions", "categories", "installments", "sync_events", "sync_applied_events", "app_settings"]
    for ce in core_extras:
        print(f"   {ce:<25}: {info_core['counts'].get(ce, 'N/A')} rows")
        
    # Extra Legacy tables
    print(f"\n4. LEGACY SPECIFIC / DEPRECATED TABLES (Migrated or Replaced):")
    legacy_only = [t for t in info_raw['tables'] if t not in info_core['tables']]
    for lo in sorted(legacy_only):
        print(f"   {lo:<30}: {info_raw['counts'].get(lo, 'N/A')} rows in baseline ({info_live['counts'].get(lo, 'N/A')} live)")

if __name__ == "__main__":
    main()
