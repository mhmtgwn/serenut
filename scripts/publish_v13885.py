#!/usr/bin/env python3
import os
import sys
import shutil
import hashlib
import time
import psycopg2

VERSION = "1.3.8"
BUILD_NUM = 85
FULL_VER = f"{VERSION}+{BUILD_NUM}"
RELEASE_NOTES = "Nakit ödeme ekranında akıllı TL banknot yuvarlama chipleri (5, 10, 20, 50, 100, 200 TL ve katları) eklendi."

DB_NAME = os.environ.get("DB_NAME", "serenut")
DB_USER = os.environ.get("DB_USER", "postgres")
DB_PASS = os.environ.get("DB_PASS", "Meven2022")
DB_HOST = os.environ.get("DB_HOST", "localhost")
DB_PORT = os.environ.get("DB_PORT", "5432")

RELEASES_DIR = "/var/www/serenut/server/releases"
PUBLIC_DIR = "/var/www/serenut-api/releases"

def get_hash_and_size(filepath):
    sha256 = hashlib.sha256()
    size = os.path.getsize(filepath)
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            sha256.update(chunk)
    return sha256.hexdigest(), size

def publish():
    print(f"--- PUBLISHING {FULL_VER} ---")
    conn = psycopg2.connect(
        dbname=DB_NAME, user=DB_USER, password=DB_PASS, host=DB_HOST, port=DB_PORT
    )
    cursor = conn.cursor()

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

        if src_path != pub_path:
            shutil.copy2(src_path, pub_path)

        file_hash, file_size = get_hash_and_size(src_path)

        # 1. Update app_releases
        cursor.execute("""
            INSERT INTO app_releases (
                platform, version, build_number, min_required_version,
                is_force_update, download_url, sha256_hash, release_notes,
                channel, file_size_bytes, schema_version
            ) VALUES (
                %s, %s, %s, %s,
                %s, %s, %s, %s,
                %s, %s, %s
            ) ON CONFLICT (platform, version) DO UPDATE SET
                build_number = EXCLUDED.build_number,
                sha256_hash = EXCLUDED.sha256_hash,
                download_url = EXCLUDED.download_url,
                release_notes = EXCLUDED.release_notes,
                file_size_bytes = EXCLUDED.file_size_bytes,
                created_at = NOW();
        """, (
            platform, FULL_VER, BUILD_NUM, "1.0.0+1",
            False, f"/releases/{filename}", file_hash, RELEASE_NOTES,
            "stable", file_size, 36
        ))
        print(f"DB app_releases Result ({platform}): {cursor.statusmessage}")

        # 2. Update app_versions (Queried by public /api/v1/updates/check)
        release_id = f"rel-{platform}-{FULL_VER.replace('+', '-')}"
        cursor.execute("""
            INSERT INTO app_versions (
                id, version_code, platform, channel, download_url, file_path,
                sha256_hash, file_size_bytes, is_mandatory, min_required_version,
                release_notes, status, rollout_percentage, schema_version
            ) VALUES (
                %s, %s, %s, 'stable', %s, %s,
                %s, %s, false, '1.0.0+1',
                %s, 'active', 100, 36
            ) ON CONFLICT (platform, version_code) DO UPDATE SET
                sha256_hash = EXCLUDED.sha256_hash,
                download_url = EXCLUDED.download_url,
                file_path = EXCLUDED.file_path,
                file_size_bytes = EXCLUDED.file_size_bytes,
                release_notes = EXCLUDED.release_notes,
                status = 'active',
                rollout_percentage = 100,
                updated_at = NOW();
        """, (
            release_id, FULL_VER, platform, f"/releases/{filename}", src_path,
            file_hash, file_size, RELEASE_NOTES
        ))
        print(f"DB app_versions Result ({platform}): {cursor.statusmessage}")

    conn.commit()
    cursor.close()
    conn.close()
    print(f"ALL_RELEASES_{VERSION}_BUILD{BUILD_NUM}_PUBLISHED_SUCCESSFULLY")

if __name__ == "__main__":
    publish()
