#!/usr/bin/env python3
"""
scripts/full_live_backup.py
Serenut OS — Full Live Multi-Database Hot Backup Engine
Takes atomic snapshots of active SQLite (with live WAL merge) and PostgreSQL databases.
"""

import os
import sys
import time
import shutil
import hashlib
import sqlite3
import subprocess
import json
from datetime import datetime

def compute_sha256(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    return h.hexdigest()

def backup_sqlite(src_path, dst_path):
    print(f"📦 [SQLite Backup] Connecting to source: {src_path}")
    # Open source in read-only URI mode to avoid write contention
    src_uri = f"file:{os.path.abspath(src_path)}?mode=ro"
    src_conn = sqlite3.connect(src_uri, uri=True, timeout=30.0)
    
    # Target file
    if os.path.exists(dst_path):
        os.remove(dst_path)
    dst_conn = sqlite3.connect(dst_path)
    
    print(f"🔄 [SQLite Backup] Executing online atomic backup into: {dst_path} ...")
    start = time.time()
    # sqlite3 backup API flushes active WAL into destination atomically
    src_conn.backup(dst_conn, pages=1000)
    dst_conn.close()
    src_conn.close()
    duration = time.time() - start
    print(f"✅ [SQLite Backup] Completed in {duration:.2f}s")
    
    # Verification
    print(f"🔍 [SQLite Backup] Verifying PRAGMA integrity_check...")
    verify_conn = sqlite3.connect(dst_path)
    cursor = verify_conn.cursor()
    cursor.execute("PRAGMA integrity_check;")
    res = cursor.fetchall()
    if not res or res[0][0] != "ok":
        verify_conn.close()
        raise RuntimeError(f"Integrity check failed: {res}")
    print(f"✨ [SQLite Backup] PRAGMA integrity_check: OK")
    
    # Collect key stats
    stats = {}
    for table in ['products', 'customers', 'sales', 'sale_items', 'ledger_entries', 'cash_transactions', 'users', 'sync_queue', 'outbox']:
        try:
            cursor.execute(f"SELECT COUNT(*) FROM {table};")
            stats[table] = cursor.fetchone()[0]
        except Exception:
            pass
    verify_conn.close()
    
    sha256 = compute_sha256(dst_path)
    size = os.path.getsize(dst_path)
    return {
        "source": src_path,
        "destination": dst_path,
        "size_bytes": size,
        "sha256": sha256,
        "stats": stats
    }

def backup_postgres(pg_dump_bin, host, port, user, password, dbname, dst_path):
    print(f"🐘 [Postgres Backup] Running pg_dump for database '{dbname}' on {host}:{port}...")
    env = os.environ.copy()
    env["PGPASSWORD"] = password
    
    cmd = [
        pg_dump_bin,
        "-U", user,
        "-h", host,
        "-p", str(port),
        "-Fc",  # custom compressed archive format
        "-d", dbname,
        "-f", dst_path
    ]
    
    start = time.time()
    proc = subprocess.run(cmd, env=env, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"pg_dump failed (exit {proc.returncode}): {proc.stderr}")
    
    duration = time.time() - start
    size = os.path.getsize(dst_path)
    sha256 = compute_sha256(dst_path)
    print(f"✅ [Postgres Backup] Completed in {duration:.2f}s. Size: {size} bytes.")
    return {
        "database": dbname,
        "destination": dst_path,
        "size_bytes": size,
        "sha256": sha256
    }

def main():
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    print(f"🚀 ========================================================")
    print(f"🚀 Serenut OS — Hot Backup Operation: {timestamp}")
    print(f"🚀 ========================================================")
    
    workspace_root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    archive_dir = os.path.join(workspace_root, "backups_archive", timestamp)
    os.makedirs(archive_dir, exist_ok=True)
    
    onedrive_backups_dir = os.path.expanduser(r"~\OneDrive\Belgeler\SerenutBackups")
    if os.path.exists(onedrive_backups_dir):
        os.makedirs(onedrive_backups_dir, exist_ok=True)
    
    manifest = {
        "timestamp": timestamp,
        "created_at": datetime.now().isoformat(),
        "archive_directory": archive_dir,
        "backups": {}
    }
    
    # ── 1. ACTIVE SERENUT POS SQLITE DATABASE ──────────────────────
    roaming_dir = os.path.expanduser(r"~\AppData\Roaming\Serenut OS Software Technologies A.Ş\Serenut OS\databases")
    active_sqlite = os.path.join(roaming_dir, "serenut_pos.db")
    
    if os.path.exists(active_sqlite):
        dst_archive = os.path.join(archive_dir, f"serenut_pos_live_{timestamp}.db")
        res = backup_sqlite(active_sqlite, dst_archive)
        manifest["backups"]["active_pos_sqlite"] = res
        
        # Also copy to OneDrive SerenutBackups folder to keep standard historical cadence
        if os.path.exists(onedrive_backups_dir):
            onedrive_target = os.path.join(onedrive_backups_dir, f"serenut_pos_backup_{timestamp}.db")
            shutil.copy2(dst_archive, onedrive_target)
            print(f"📁 [OneDrive] Copied to standard backups folder: {onedrive_target}")
            manifest["backups"]["active_pos_sqlite"]["onedrive_copy"] = onedrive_target
            
        # Also preserve raw snapshot of main db + wal + shm in raw_snapshot folder
        raw_snapshot_dir = os.path.join(archive_dir, "raw_sqlite_files")
        os.makedirs(raw_snapshot_dir, exist_ok=True)
        for ext in ["", "-wal", "-shm"]:
            fpath = active_sqlite + ext
            if os.path.exists(fpath):
                shutil.copy2(fpath, os.path.join(raw_snapshot_dir, f"serenut_pos.db{ext}"))
        print(f"📋 [Raw Snapshot] Copied raw db, wal and shm files to {raw_snapshot_dir}")
    else:
        print(f"⚠️ Active SQLite database not found at {active_sqlite}")
        
    # ── 2. CORE NEXT DATABASES ────────────────────────────────────
    core_next_dir = os.path.join(roaming_dir, "core_next")
    if os.path.exists(core_next_dir):
        manifest["backups"]["core_next"] = {}
        for fname in os.listdir(core_next_dir):
            if fname.endswith(".db"):
                core_db_path = os.path.join(core_next_dir, fname)
                core_dst = os.path.join(archive_dir, f"core_next_{fname}_{timestamp}")
                try:
                    c_res = backup_sqlite(core_db_path, core_dst)
                    manifest["backups"]["core_next"][fname] = c_res
                except Exception as e:
                    print(f"⚠️ Core Next {fname} backup error: {e}")
                    
    # ── 3. LOCAL POSTGRESQL (nutopiano) ───────────────────────────
    pg_dump_bin = r"C:\Program Files\PostgreSQL\16\bin\pg_dump.exe"
    if os.path.exists(pg_dump_bin):
        dst_pg = os.path.join(archive_dir, f"postgres_nutopiano_{timestamp}.dump")
        try:
            pg_res = backup_postgres(
                pg_dump_bin=pg_dump_bin,
                host="127.0.0.1",
                port=5432,
                user="postgres",
                password="postgrespassword" if "postgrespassword" else "postgres",
                dbname="nutopiano",
                dst_path=dst_pg
            )
            manifest["backups"]["postgres_nutopiano"] = pg_res
        except Exception as e:
            # Try with password "postgres"
            try:
                pg_res = backup_postgres(
                    pg_dump_bin=pg_dump_bin,
                    host="127.0.0.1",
                    port=5432,
                    user="postgres",
                    password="postgres",
                    dbname="nutopiano",
                    dst_path=dst_pg
                )
                manifest["backups"]["postgres_nutopiano"] = pg_res
            except Exception as e2:
                print(f"⚠️ Postgres backup attempt failed: {e2}")
                manifest["backups"]["postgres_error"] = str(e2)
    
    # ── 4. WRITE MANIFEST & SHA256SUMS ────────────────────────────
    manifest_path = os.path.join(archive_dir, "BACKUP_MANIFEST.json")
    with open(manifest_path, "w", encoding="utf-8") as f:
        json.dump(manifest, f, indent=2, ensure_ascii=False)
        
    sums_path = os.path.join(archive_dir, "SHA256SUMS.txt")
    with open(sums_path, "w", encoding="utf-8") as f:
        for root, _, files in os.walk(archive_dir):
            for file in files:
                if file in ["SHA256SUMS.txt", "BACKUP_MANIFEST.json"]:
                    continue
                full_p = os.path.join(root, file)
                rel_p = os.path.relpath(full_p, archive_dir)
                f.write(f"{compute_sha256(full_p)}  {rel_p}\n")
                
    print(f"\n🎉 ========================================================")
    print(f"🎉 Yedekleme Başarıyla Tamamlandı!")
    print(f"📁 Arşiv Dizini: {archive_dir}")
    print(f"📄 Manifest: {manifest_path}")
    print(f"📄 SHA256: {sums_path}")
    print(f"==========================================================\n")
    print(json.dumps(manifest, indent=2, ensure_ascii=False))

if __name__ == "__main__":
    main()
