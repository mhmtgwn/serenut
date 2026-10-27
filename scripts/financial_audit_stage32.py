#!/usr/bin/env python3
"""
scripts/financial_audit_stage32.py
Deep financial, payment, customer balance, and stock reconciliation for Stage 10.12.32.
"""

import os
import sys
import sqlite3
import json

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def audit_db(label, db_path):
    print(f"\n=======================================================")
    print(f"AUDITING: {label}")
    print(f"Path: {db_path}")
    print(f"=======================================================")
    conn = sqlite3.connect(f"file:{os.path.abspath(db_path)}?mode=ro", uri=True)
    cur = conn.cursor()

    cur.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = set(r[0] for r in cur.fetchall())

    res = {}

    # 1. Products & Stock
    if "products" in tables:
        cur.execute("PRAGMA table_info(products);")
        pcols = [c[1] for c in cur.fetchall()]
        stock_col = "stock_quantity" if "stock_quantity" in pcols else "quantity"
        price_col = "price_cents" if "price_cents" in pcols else "price"
        
        cur.execute(f"SELECT COUNT(*), SUM(CAST({stock_col} AS REAL)), SUM(CAST({stock_col} AS INTEGER)) FROM products;")
        pcnt, pstock_real, pstock_int = cur.fetchone()
        
        cur.execute(f"SELECT COUNT(*) FROM products WHERE is_deleted = 0;")
        active_cnt = cur.fetchone()[0]
        cur.execute(f"SELECT COUNT(*) FROM products WHERE is_deleted = 1;")
        deleted_cnt = cur.fetchone()[0]
        
        res["products"] = {
            "total_count": pcnt,
            "active_count": active_cnt,
            "deleted_count": deleted_cnt,
            "stock_real": round(pstock_real, 2),
            "stock_int": pstock_int
        }

    # 2. Customers & Balances
    if "customers" in tables:
        cur.execute("PRAGMA table_info(customers);")
        ccols = [c[1] for c in cur.fetchall()]
        bal_col = "balance_cents" if "balance_cents" in ccols else "balance"
        
        cur.execute(f"SELECT COUNT(*), SUM({bal_col}) FROM customers;")
        ccnt, cbal = cur.fetchone()
        
        # In Core Next, balance is in cents (integer). In legacy, balance is in TL (real).
        if "balance_cents" in ccols:
            bal_tl = cbal / 100.0 if cbal else 0.0
            bal_cents = cbal
        else:
            bal_tl = round(cbal, 2) if cbal else 0.0
            bal_cents = int(round(cbal * 100)) if cbal else 0
            
        cur.execute(f"SELECT COUNT(*) FROM customers WHERE {bal_col} < 0;")
        debtors_cnt = cur.fetchone()[0]
        cur.execute(f"SELECT COUNT(*) FROM customers WHERE {bal_col} > 0;")
        creditors_cnt = cur.fetchone()[0]
        
        res["customers"] = {
            "total_count": ccnt,
            "total_balance_tl": bal_tl,
            "total_balance_cents": bal_cents,
            "debtors_count": debtors_cnt,
            "creditors_count": creditors_cnt
        }

    # 3. Sales & Revenue
    if "sales" in tables:
        cur.execute("PRAGMA table_info(sales);")
        scols = [c[1] for c in cur.fetchall()]
        tot_col = "total_cents" if "total_cents" in scols else "total_amount"
        
        cur.execute(f"SELECT COUNT(*), SUM({tot_col}) FROM sales;")
        scnt, stot = cur.fetchone()
        stot_tl = stot / 100.0 if "total_cents" in scols else round(stot, 2)
        stot_cents = stot if "total_cents" in scols else int(round(stot * 100))
        
        # Breakdown by payment method
        by_method = {}
        if "sale_payments" in tables:
            cur.execute("SELECT payment_type, COUNT(*), SUM(amount_cents) FROM sale_payments GROUP BY payment_type;")
            for m, cnt, amt in cur.fetchall():
                by_method[m] = {
                    "count": cnt,
                    "amount_tl": amt / 100.0 if amt else 0.0,
                    "amount_cents": amt
                }
        elif "payment_method" in scols:
            cur.execute(f"SELECT payment_method, COUNT(*), SUM({tot_col}) FROM sales GROUP BY payment_method;")
            for m, cnt, amt in cur.fetchall():
                by_method[m] = {
                    "count": cnt,
                    "amount_tl": amt / 100.0 if "total_cents" in scols else round(amt, 2)
                }
                
        res["sales"] = {
            "total_sales": scnt,
            "total_revenue_tl": stot_tl,
            "total_revenue_cents": stot_cents,
            "by_payment_method": by_method
        }

    # 4. Sale Items
    if "sale_items" in tables:
        cur.execute("PRAGMA table_info(sale_items);")
        sicols = [c[1] for c in cur.fetchall()]
        tot_col = "total_cents" if "total_cents" in sicols else "subtotal"
        qty_col = "quantity"
        
        cur.execute(f"SELECT COUNT(*), SUM({qty_col}), SUM({tot_col}) FROM sale_items;")
        si_cnt, si_qty, si_tot = cur.fetchone()
        si_tot_tl = si_tot / 100.0 if "total_cents" in sicols else round(si_tot, 2)
        
        res["sale_items"] = {
            "total_items": si_cnt,
            "total_quantity": si_qty,
            "total_amount_tl": si_tot_tl
        }

    # 5. Ledger / Financial Transactions
    if "ledger_entries" in tables:
        cur.execute("SELECT COUNT(*), SUM(amount_cents) FROM ledger_entries;")
        l_cnt, l_amt = cur.fetchone()
        cur.execute("SELECT entry_type, COUNT(*), SUM(amount_cents) FROM ledger_entries GROUP BY entry_type;")
        l_types = {r[0]: {"count": r[1], "amount_cents": r[2]} for r in cur.fetchall()}
        res["ledger_entries"] = {
            "count": l_cnt,
            "total_amount_cents": l_amt,
            "by_type": l_types
        }
    elif "financial_transactions" in tables:
        cur.execute("SELECT COUNT(*), SUM(amount) FROM financial_transactions;")
        ft_cnt, ft_amt = cur.fetchone()
        cur.execute("SELECT type, COUNT(*), SUM(amount) FROM financial_transactions GROUP BY type;")
        ft_types = {r[0]: {"count": r[1], "amount": round(r[2], 2)} for r in cur.fetchall()}
        res["financial_transactions"] = {
            "count": ft_cnt,
            "total_amount_tl": round(ft_amt, 2) if ft_amt else 0.0,
            "by_type": ft_types
        }

    # 6. Orders
    if "orders" in tables:
        cur.execute("PRAGMA table_info(orders);")
        ocols = [c[1] for c in cur.fetchall()]
        otot_col = "total_amount_cents" if "total_amount_cents" in ocols else "total_amount"
        cur.execute(f"SELECT COUNT(*), SUM({otot_col}) FROM orders;")
        o_cnt, o_amt = cur.fetchone()
        res["orders"] = {
            "count": o_cnt,
            "total_amount_tl": o_amt / 100.0 if "total_amount_cents" in ocols else round(o_amt, 2) if o_amt else 0.0
        }

    conn.close()
    print(json.dumps(res, indent=2, ensure_ascii=False))
    return res

def main():
    base_roaming = r"C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS"
    onedrive_dir = r"C:\Users\notop\OneDrive\Belgeler\SerenutBackups"
    
    raw_nutopia = os.path.join(base_roaming, r"backups\raw_tenants_20261016\raw_nutopia_v60.db")
    live_backup = os.path.join(onedrive_dir, "serenut_pos_backup_20261019_161042.db")
    core_next_nutopia = os.path.join(base_roaming, r"databases\core_next\nutopia_pos.db")
    
    audit_db("1. Raw Nutopia Baseline (Oct 16)", raw_nutopia)
    audit_db("2. Core Next Target (Nutopia)", core_next_nutopia)
    audit_db("3. Live Backup (19.10.2026 16:10)", live_backup)

if __name__ == "__main__":
    main()
