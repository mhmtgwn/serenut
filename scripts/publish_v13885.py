#!/usr/bin/env python3
import os
import sys
import shutil
import hashlib
import subprocess

VERSION = "1.3.8"
BUILD_NUM = 85
FULL_VER = f"{VERSION}+{BUILD_NUM}"
RELEASE_NOTES = "Nakit ödeme ekranında akıllı TL banknot yuvarlama chipleri (5, 10, 20, 50, 100, 200 TL ve katları) eklendi."

RELEASES_DIR = "/var/www/serenut/server/releases"
PUBLIC_DIR = "/var/www/serenut-api/releases"

def get_hash_and_size(filepath):
    sha256 = hashlib.sha256()
    size = os.path.getsize(filepath)
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            sha256.update(chunk)
    return sha256.hexdigest(), size

def run_sql(sql_query):
    cmd = [
        "docker", "exec", "-i", "serenut-db",
        "psql", "-U", "serenut_user", "-d", "serenut_db", "-c", sql_query
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"SQL Error: {res.stderr}")
    else:
        print(f"SQL Output: {res.stdout.strip()}")

def publish():
    print(f"--- PUBLISHING {FULL_VER} ---")

    os.makedirs(RELEASES_DIR, exist_ok=True)
    os.makedirs(PUBLIC_DIR, exist_ok=True)

    platforms = {
        "android": f"SerenutOS-v{VERSION}.apk",
        "windows": f"SerenutOS-v{VERSION}.exe"
    }

    for platform, filename in platforms.items():
        src_path = os.path.join(RELEASES_DIR, filename)
        pub_path = os.path.join(PUBLIC_DIR, filename)

        if not os.path.exists(src_path):
            print(f"Error: {src_path} not found!")
            sys.exit(1)

        try:
            if src_path != pub_path and not (os.path.exists(pub_path) and os.path.samefile(src_path, pub_path)):
                shutil.copy2(src_path, pub_path)
        except shutil.SameFileError:
            pass

        file_hash, file_size = get_hash_and_size(src_path)
        release_id = f"rel-{platform}-{FULL_VER.replace('+', '-')}"
        api_download_url = f"/api/v1/updates/download/{platform}/latest"

        # 1. Update app_versions (Queried by public /api/v1/updates/check API)
        sql_versions = f"""
            INSERT INTO app_versions (
                id, version_code, platform, channel, download_url, file_path,
                sha256_hash, file_size_bytes, is_mandatory, min_required_version,
                release_notes, status, rollout_percentage
            ) VALUES (
                '{release_id}', '{FULL_VER}', '{platform}', 'stable', '{api_download_url}', '{src_path}',
                '{file_hash}', {file_size}, false, '1.0.0+1',
                '{RELEASE_NOTES}', 'active', 100
            ) ON CONFLICT (version_code, platform, channel) DO UPDATE SET
                sha256_hash = EXCLUDED.sha256_hash,
                download_url = EXCLUDED.download_url,
                file_path = EXCLUDED.file_path,
                file_size_bytes = EXCLUDED.file_size_bytes,
                release_notes = EXCLUDED.release_notes,
                status = 'active',
                rollout_percentage = 100,
                updated_at = NOW();
        """
        print(f"Updating app_versions ({platform})...")
        run_sql(sql_versions)

        # 2. Update app_releases
        sql_releases = f"""
            INSERT INTO app_releases (
                id, version, platform, channel, download_url,
                sha256_hash, release_notes, rollout_percentage, is_mandatory, status
            ) VALUES (
                '{release_id}', '{FULL_VER}', '{platform}', 'stable', '{api_download_url}',
                '{file_hash}', '{RELEASE_NOTES}', 100, false, 'active'
            ) ON CONFLICT (id) DO UPDATE SET
                sha256_hash = EXCLUDED.sha256_hash,
                download_url = EXCLUDED.download_url,
                release_notes = EXCLUDED.release_notes,
                status = 'active',
                rollout_percentage = 100,
                updated_at = NOW();
        """
        print(f"Updating app_releases ({platform})...")
        run_sql(sql_releases)

    print(f"ALL_RELEASES_{VERSION}_BUILD{BUILD_NUM}_PUBLISHED_SUCCESSFULLY")

if __name__ == "__main__":
    publish()
