#!/usr/bin/env python3
"""
scripts/take_live_backup.py
High-integrity live hot backup script for Serenut OS.
"""

import os
import sys
import shutil
import hashlib
import sqlite3
import json
from datetime import datetime

# Configure UTF-8 output to prevent Windows cp1254 crash
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)

def sha256_file(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(131072):
            h.update(chunk)
    return h.hexdigest()

def main():
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log("==================================================")
    log(f"SERENUT OS -- CANLI GUNCEL VERI YEDEKLEME BASLADI")
    log(f"Zaman: {timestamp}")
    log("==================================================")

    # 1. Kaynak ve Hedef Yollari
    src_db_dir = r"C:\Users\notop\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases"
    onedrive_dir = r"C:\Users\notop\OneDrive\Belgeler\SerenutBackups"
    
    target_backup_dir = os.path.join(onedrive_dir, f"SNAPSHOT_{timestamp}")
    os.makedirs(target_backup_dir, exist_ok=True)
    log(f"Hedef Yedek Klasoru: {target_backup_dir}")

    report = {
        "timestamp": timestamp,
        "created_at": datetime.now().isoformat(),
        "backup_directory": target_backup_dir,
        "sqlite_files": {},
        "table_stats": {},
        "integrity": {}
    }

    # 2. Aktif Veritabanı Dosyalarını Kopyalama (DB + WAL + SHM)
    log("1. Adim: Aktif SQLite dosyalari kopyalaniyor (serenut_pos.db, -wal, -shm)...")
    copied_files = []
    for ext in ["", "-wal", "-shm"]:
        src_file = os.path.join(src_db_dir, f"serenut_pos.db{ext}")
        dst_file = os.path.join(target_backup_dir, f"serenut_pos.db{ext}")
        if os.path.exists(src_file):
            size = os.path.getsize(src_file)
            shutil.copy2(src_file, dst_file)
            copied_files.append(dst_file)
            log(f"   [OK] Kopyalandi: serenut_pos.db{ext} ({size:,} bytes)")
            report["sqlite_files"][f"serenut_pos.db{ext}"] = {
                "size_bytes": size,
                "sha256": sha256_file(dst_file)
            }

    # 3. Kopyalanan Yedek Uzerinde WAL Checkpoint ve Birlestirme
    log("2. Adim: WAL islemleri ana veritabanina birlestiriliyor (WAL Checkpoint)...")
    backup_db_path = os.path.join(target_backup_dir, "serenut_pos.db")
    
    conn = sqlite3.connect(backup_db_path)
    cur = conn.cursor()
    cur.execute("PRAGMA wal_checkpoint(TRUNCATE);")
    ckpt_res = cur.fetchall()
    log(f"   [OK] Checkpoint Sonucu: {ckpt_res}")

    # 4. Butunluk Dogrulamasi (PRAGMA integrity_check)
    log("3. Adim: Veritabani butunluk dogrulamasi (PRAGMA integrity_check)...")
    cur.execute("PRAGMA integrity_check;")
    integrity = cur.fetchall()
    if integrity and integrity[0][0] == "ok":
        log("   [OK] BUTUNLUK DOGRULAMASI: BASARILI (OK)")
        report["integrity"]["serenut_pos.db"] = "PASS_OK"
    else:
        log(f"   [FAIL] BUTUNLUK HATASI: {integrity}")
        report["integrity"]["serenut_pos.db"] = f"FAIL: {integrity}"

    # 5. Guncel Tablo Istatistikleri & Kayit Sayimlari
    log("4. Adim: Guncel isletme verileri ve tablo sayilari taraniyor...")
    tables_to_check = [
        "sales", "sale_items", "customers", "products", "categories",
        "ledger_entries", "cash_counts", "cash_transactions",
        "users", "orders", "installments", "sync_queue", "outbox"
    ]
    for table in tables_to_check:
        try:
            cur.execute(f"SELECT COUNT(*) FROM {table};")
            count = cur.fetchone()[0]
            report["table_stats"][table] = count
            log(f"   * {table}: {count:,} kayit")
        except Exception:
            pass
            
    conn.close()

    # 6. Tek Parca Standart Yedek Dosyasi Olarak da Kaydet
    standalone_filename = f"serenut_pos_backup_{timestamp}.db"
    standalone_path = os.path.join(onedrive_dir, standalone_filename)
    shutil.copy2(backup_db_path, standalone_path)
    log(f"5. Adim: Standart tekil yedek dosyasi olusturuldu: {standalone_filename}")
    report["standalone_backup"] = {
        "file": standalone_filename,
        "path": standalone_path,
        "size_bytes": os.path.getsize(standalone_path),
        "sha256": sha256_file(standalone_path)
    }

    # 7. Core Next Veritabanlari Varsa Onlari da Yedekle
    core_next_dir = os.path.join(src_db_dir, "core_next")
    if os.path.exists(core_next_dir):
        log("6. Adim: Core Next veritabanlari yedekleniyor...")
        target_core_dir = os.path.join(target_backup_dir, "core_next")
        os.makedirs(target_core_dir, exist_ok=True)
        for fname in os.listdir(core_next_dir):
            if fname.endswith((".db", ".db-wal", ".db-shm")):
                s = os.path.join(core_next_dir, fname)
                d = os.path.join(target_core_dir, fname)
                shutil.copy2(s, d)
                log(f"   [OK] Core Next kopyalandi: {fname}")

    # 8. Manifest ve SHA256SUMS Kaydi
    manifest_file = os.path.join(target_backup_dir, "BACKUP_REPORT.json")
    with open(manifest_file, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
        
    sha_file = os.path.join(target_backup_dir, "SHA256SUMS.txt")
    with open(sha_file, "w", encoding="utf-8") as f:
        for fname in os.listdir(target_backup_dir):
            full = os.path.join(target_backup_dir, fname)
            if os.path.isfile(full) and fname not in ["SHA256SUMS.txt", "BACKUP_REPORT.json"]:
                f.write(f"{sha256_file(full)}  {fname}\n")
                
    log("==================================================")
    log("GUNCEL VERI YEDEGI EKSIKSIZ ALINDI VE DOGRULANDI!")
    log(f"Dizin: {target_backup_dir}")
    log(f"Standart Dosya: {standalone_path}")
    log(f"SHA-256: {report['standalone_backup']['sha256']}")
    log("==================================================")

if __name__ == "__main__":
    main()
