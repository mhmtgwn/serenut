#!/usr/bin/env python3
"""
scripts/stage10_12_93_inspect_pilot_gate_preconditions.py
SERENUT OS — STAGE 10.12.93
Pilot Gate Önkoşulları ve Canlı Durum İncelemesi (Salt Okunur)
"""

import os
import sys
import json
import sqlite3
import hashlib
from datetime import datetime

# Windows encoding safety
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

def main():
    log("=================================================================")
    log("STAGE 10.12.93 — PILOT GATE VE CANLI DURUM İNCELEMESİ")
    log("=================================================================")

    roaming = os.environ.get("APPDATA", "")
    live_dir = os.path.join(roaming, "Serenut OS Software Technologies A.Ş", "Serenut OS")
    live_prefs_path = os.path.join(live_dir, "shared_preferences.json")
    live_legacy_path = os.path.join(live_dir, "databases", "serenut_pos.db")
    live_core_path = os.path.join(live_dir, "databases", "serenut_core_v2.db")
    live_core_sub_path = os.path.join(live_dir, "databases", "core_next", "serenut_core_v2.db")

    stage84_backup = os.path.abspath(r"backups\nutopia_pre_cutover_20261021_stage84\serenut_pos_live_backup.db")
    stage2055_core = os.path.abspath(r"backups\nutopia_live_20261021_2055\nutopia_core_next_live.db")

    installed_exe = r"C:\Program Files\Serenut OS\serenutos.exe"
    release_exe = os.path.abspath(r"build\windows\x64\runner\Release\serenutos.exe")
    release_app_so = os.path.abspath(r"build\windows\x64\runner\Release\data\app.so")

    report = {
        "timestamp": datetime.now().isoformat(),
        "live_preferences": {},
        "databases": {},
        "executables": {},
    }

    # 1. SharedPreferences İncelemesi
    log("\n--- 1. CANLI SHARED_PREFERENCES.JSON İNCELEMESİ ---")
    if os.path.exists(live_prefs_path):
        size = os.path.getsize(live_prefs_path)
        sha = sha256_file(live_prefs_path)
        with open(live_prefs_path, 'r', encoding='utf-8') as f:
            prefs_data = json.load(f)
        
        relevant_keys = {}
        for k, v in prefs_data.items():
            if any(term in k.lower() for term in ['core_next', 'pilot', 'backup', 'migration', 'kill_switch', 'tenant', 'rollback']):
                relevant_keys[k] = v
        
        report["live_preferences"] = {
            "path": live_prefs_path,
            "size_bytes": size,
            "sha256": sha,
            "total_keys": len(prefs_data),
            "relevant_keys": relevant_keys
        }
        log(f"Dosya Yolu: {live_prefs_path} ({size:,} B, SHA256: {sha})")
        log("İlgili Anahtarlar:")
        for k, v in relevant_keys.items():
            log(f"  {k}: {v}")
    else:
        log("HATA: Canlı shared_preferences.json bulunamadı!")
        report["live_preferences"]["exists"] = False

    # 2. Veritabanı ve app_settings İncelemesi
    log("\n--- 2. VERİTABANI VE APP_SETTINGS İNCELEMESİ ---")
    dbs_to_check = {
        "live_core": live_core_path,
        "live_core_sub": live_core_sub_path,
        "stage2055_core": stage2055_core,
        "live_legacy": live_legacy_path,
        "stage84_backup": stage84_backup,
    }

    for name, p in dbs_to_check.items():
        if os.path.exists(p):
            size = os.path.getsize(p)
            sha = sha256_file(p)
            uri = f"file:{os.path.abspath(p)}?mode=ro"
            conn = sqlite3.connect(uri, uri=True)
            conn.row_factory = sqlite3.Row
            cur = conn.cursor()

            cur.execute("PRAGMA integrity_check;")
            integrity = cur.fetchone()[0]

            cur.execute("PRAGMA user_version;")
            user_ver = cur.fetchone()[0]

            cur.execute("SELECT name FROM sqlite_master WHERE type='table';")
            tables = [r[0] for r in cur.fetchall()]

            app_settings = {}
            if "app_settings" in tables:
                cur.execute("SELECT key, value FROM app_settings;")
                for r in cur.fetchall():
                    app_settings[r["key"]] = r["value"]

            conn.close()

            report["databases"][name] = {
                "path": p,
                "size_bytes": size,
                "sha256": sha,
                "integrity": integrity,
                "user_version": user_ver,
                "tables_count": len(tables),
                "app_settings": app_settings
            }
            log(f"[{name.upper()}] {p}")
            log(f"  Boyut: {size:,} B | SHA-256: {sha}")
            log(f"  Integrity: {integrity} | user_version: {user_ver} | Tablolar: {len(tables)}")
            if app_settings:
                log("  app_settings kayıtları:")
                for k, v in app_settings.items():
                    log(f"    {k} = {v}")
        else:
            log(f"[{name.upper()}] Dosya mevcut değil: {p}")
            report["databases"][name] = {"exists": False}

    # 3. Executable İncelemesi
    log("\n--- 3. EXECUTABLE VE APP.SO İNCELEMESİ ---")
    exes_to_check = {
        "installed_exe": installed_exe,
        "stage91_release_exe": release_exe,
        "stage91_release_app_so": release_app_so,
    }
    for name, p in exes_to_check.items():
        if os.path.exists(p):
            size = os.path.getsize(p)
            sha = sha256_file(p)
            mtime = datetime.fromtimestamp(os.path.getmtime(p)).isoformat()
            report["executables"][name] = {
                "path": p,
                "size_bytes": size,
                "sha256": sha,
                "modified": mtime
            }
            log(f"[{name.upper()}] {p}")
            log(f"  Boyut: {size:,} B | SHA-256: {sha} | Değiştirilme: {mtime}")
        else:
            log(f"[{name.upper()}] Dosya mevcut değil: {p}")
            report["executables"][name] = {"exists": False}

    # JSON Çıktısı
    out_file = os.path.abspath(r"outputs\stage10_12_93_pilot_preconditions.json")
    os.makedirs(os.path.dirname(out_file), exist_ok=True)
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
    log(f"\nRapor kaydedildi: {out_file}")

if __name__ == "__main__":
    main()
