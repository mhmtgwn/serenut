#!/usr/bin/env python3
"""
scripts/stage10_12_40_restore_rehearsal.py
SERENUT OS — STAGE 10.12.40
Yedek Doğrulama, Geri Yükleme Provası ve İşletme Bazlı Mutabakat Hazırlığı
"""

import os
import sys
import shutil
import hashlib
import sqlite3
import tempfile
import json
from datetime import datetime

if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
if hasattr(sys.stderr, 'reconfigure'):
    sys.stderr.reconfigure(encoding='utf-8', errors='replace')

def log(msg):
    print(f"[{datetime.now().strftime('%H:%M:%S')}] {msg}", flush=True)

def sha256_file(filepath):
    if not os.path.isfile(filepath):
        return None
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(1024 * 1024):
            h.update(chunk)
    return h.hexdigest()

def get_db_stats(db_path):
    conn = sqlite3.connect(f"file:{db_path}?mode=ro", uri=True)
    cur = conn.cursor()
    
    cur.execute("PRAGMA integrity_check;")
    integrity = cur.fetchall()
    
    cur.execute("PRAGMA foreign_key_check;")
    fk_violations = cur.fetchall()
    
    cur.execute("PRAGMA user_version;")
    user_version = cur.fetchone()[0]
    
    cur.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
    tables = [r[0] for r in cur.fetchall()]
    
    table_counts = {}
    for t in tables:
        if t.startswith('sqlite_') or t.startswith('product_search_fts_'):
            continue
        try:
            cur.execute(f"SELECT COUNT(*) FROM \"{t}\";")
            table_counts[t] = cur.fetchone()[0]
        except Exception as e:
            table_counts[t] = f"ERR: {e}"
            
    conn.close()
    return {
        "integrity_check": integrity,
        "foreign_key_violations": len(fk_violations),
        "user_version": user_version,
        "total_tables": len(tables),
        "table_names": tables,
        "table_counts": table_counts
    }

def main():
    log("=================================================================")
    log("SERENUT OS — STAGE 10.12.40 YEDEK DOĞRULAMA VE GERİ YÜKLEME PROVASI")
    log("=================================================================")
    
    backups = [
        {
            "id": "known_onedrive_nutopia",
            "name": "OneDrive Live Backup (Nutopia v60)",
            "tenant": "tenant-nutopia",
            "path": r"C:\Users\notop\OneDrive\Belgeler\SerenutBackups\serenut_pos_backup_20261019_161042.db",
            "expected_sha": "da2bab7ac7cf8017290c2c37961acf9f4ca69fc4c05338db5bb24bf51c04ce89"
        },
        {
            "id": "raw_nutopia_v60",
            "name": "Workspace Raw Nutopia (v60 Arşiv)",
            "tenant": "tenant-nutopia",
            "path": r"backups\raw_tenants_20261016\raw_nutopia_v60.db",
            "expected_sha": "e70aa44a43c53f47f61c7b82a0a8c290d82e9f849aec68486782bc2917430d24"
        },
        {
            "id": "raw_serenut_v44",
            "name": "Workspace Raw Serenut (v44 Arşiv)",
            "tenant": "tenant-serenut",
            "path": r"backups\raw_tenants_20261016\raw_serenut_v44.db",
            "expected_sha": "9145443f2c94a03dea7478605de974a1214b548523da0406c18501918da7d77d"
        },
        {
            "id": "core_next_nutopia",
            "name": "Core Next Nutopia POS (v3)",
            "tenant": "tenant-nutopia",
            "path": r"C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\nutopia_pos.db",
            "expected_sha": "c976b4d243800c763525078b9c8e9931375a1bf88fe6afca727461c230c61753"
        },
        {
            "id": "core_next_serenut",
            "name": "Core Next Serenut POS (v3)",
            "tenant": "tenant-serenut",
            "path": r"C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\serenut_pos.db",
            "expected_sha": "a7cc9d22e2d4489789a9536b6c3f3018c699a5ca5daecbe2be04b32a7c7e2273"
        },
        {
            "id": "core_next_erkul",
            "name": "Core Next Erkul Çeyiz POS (v3)",
            "tenant": "tenant-erkul",
            "path": r"C:\Users\notop\OneDrive\Belgeler\SerenutBackups\SNAPSHOT_20261019_161042\core_next\erkul_pos.db",
            "expected_sha": "ad744fcf4aa5c4af0e0628b58fc7b15db1695d21173bdf5087655da5f1067860"
        }
    ]
    
    results = {}
    temp_dir = tempfile.mkdtemp(prefix="stage40_restore_")
    log(f"Geçici Geri Yükleme Klasörü: {temp_dir}")
    
    try:
        for b in backups:
            log(f"\nİNCELENİYOR: {b['name']} ({b['id']})")
            src_path = os.path.abspath(b['path'])
            if not os.path.exists(src_path):
                log(f"HATA: Dosya mevcut değil: {src_path}")
                results[b['id']] = {"status": "MISSING", "path": src_path}
                continue
                
            file_size = os.path.getsize(src_path)
            mtime = datetime.fromtimestamp(os.path.getmtime(src_path)).isoformat()
            
            # 1. Başlangıç SHA-256
            initial_sha = sha256_file(src_path)
            log(f"Boyut: {file_size:,} bayt | Tarih: {mtime}")
            log(f"Hesaplanan SHA-256: {initial_sha}")
            sha_matches = (initial_sha.lower() == b['expected_sha'].lower())
            log(f"Beklenen SHA-256 ile Eşleşme: {sha_matches}")
            
            # 2. Kaynak Bütünlük Kontrolü
            src_stats = get_db_stats(src_path)
            log(f"Kaynak Integrity: {src_stats['integrity_check']} | FK İhlali: {src_stats['foreign_key_violations']} | Tablo Sayısı: {src_stats['total_tables']}")
            
            # 3. İzole Hedefe Geri Yükleme Provası
            dst_filename = f"{b['id']}_restored.db"
            dst_path = os.path.join(temp_dir, dst_filename)
            shutil.copy2(src_path, dst_path)
            
            restored_size = os.path.getsize(dst_path)
            restored_sha = sha256_file(dst_path)
            log(f"Hedefe Kopyalandı -> Boyut: {restored_size:,} bayt | SHA-256 Eşit: {restored_sha == initial_sha}")
            
            # 4. Geri Yüklenen Dosyada Bütünlük ve Sayım Kontrolleri
            restored_stats = get_db_stats(dst_path)
            log(f"Geri Yüklenen Integrity: {restored_stats['integrity_check']} | FK İhlali: {restored_stats['foreign_key_violations']}")
            
            # Tablo sayıları ve kayıt sayıları karşılaştırması
            counts_match = (src_stats['table_counts'] == restored_stats['table_counts'])
            tables_match = (src_stats['table_names'] == restored_stats['table_names'])
            log(f"Tablo ve Kayıt Sayısı Uyumu: {counts_match and tables_match}")
            
            # 5. Kaynak Yedeğin Değişmezlik Doğrulaması (Post-rehearsal immutability)
            post_sha = sha256_file(src_path)
            immutability_preserved = (initial_sha == post_sha)
            log(f"Kaynak Yedek Değişmezliği (İmmutability): {immutability_preserved}")
            
            results[b['id']] = {
                "name": b['name'],
                "tenant": b['tenant'],
                "src_path": src_path,
                "file_size": file_size,
                "mtime": mtime,
                "initial_sha": initial_sha,
                "expected_sha": b['expected_sha'],
                "sha_matches": sha_matches,
                "post_sha": post_sha,
                "immutability_preserved": immutability_preserved,
                "integrity_ok": (src_stats['integrity_check'] == [('ok',)]),
                "fk_violations": src_stats['foreign_key_violations'],
                "user_version": src_stats['user_version'],
                "total_tables": src_stats['total_tables'],
                "key_counts": {k: src_stats['table_counts'].get(k, 0) for k in ['products', 'customers', 'sales', 'sale_items', 'refunds', 'financial_transactions', 'ledger_entries', 'sync_events', 'sync_outbox_v4'] if k in src_stats['table_counts']}
            }
            
        # Erkul JSON kaynağını da incele
        erkul_json_path = os.path.abspath(r"backups\raw_tenants_20261016\raw_erkul_source.json")
        if os.path.exists(erkul_json_path):
            e_sha = sha256_file(erkul_json_path)
            e_size = os.path.getsize(erkul_json_path)
            e_mtime = datetime.fromtimestamp(os.path.getmtime(erkul_json_path)).isoformat()
            with open(erkul_json_path, 'r', encoding='utf-8') as f:
                e_data = json.load(f)
            e_counts = {k: len(v) for k, v in e_data.items() if isinstance(v, list)}
            results["raw_erkul_json"] = {
                "name": "Workspace Raw Erkul JSON",
                "tenant": "tenant-erkul",
                "src_path": erkul_json_path,
                "file_size": e_size,
                "mtime": e_mtime,
                "sha256": e_sha,
                "key_counts": e_counts,
                "note": "Erkul Çeyiz için Legacy .db dosyası mevcut değil, kaynak veri JSON formatındadır."
            }
            log(f"\nERKUL JSON KAYNAĞI: Boyut: {e_size} bayt | SHA: {e_sha}")
            
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
        log(f"\nGeçici klasör silindi: {temp_dir}")
        
    out_file = "stage10_12_40_rehearsal_results.json"
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(results, f, ensure_ascii=False, indent=2)
    log(f"Sonuçlar kaydedildi: {out_file}")

if __name__ == "__main__":
    main()
