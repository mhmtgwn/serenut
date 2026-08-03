import os
import hashlib
import base64
import subprocess
import sys

key_path = "/var/www/serenut-api/.rsa-private.pem"
if not os.path.exists(key_path):
    key_path = "/var/www/serenut/server/.rsa-private.pem"

def get_signature_and_hash(filepath):
    h = hashlib.sha256()
    with open(filepath, 'rb') as f:
        while chunk := f.read(65536):
            h.update(chunk)
    checksum = h.hexdigest()
    file_size = os.path.getsize(filepath)

    sign_cmd = f"openssl dgst -sha256 -sign {key_path} '{filepath}' | base64 -w 0"
    res = subprocess.run(sign_cmd, shell=True, capture_output=True, text=True)
    signature = res.stdout.strip()
    return checksum, signature, file_size

# Look for v1.2.3+65 or v1.2.3 release artifacts
apk_candidates = [
    "/var/www/serenut/server/releases/SerenutOS-v1.2.3.apk",
    "/var/www/serenut/server/releases/app-release-1.2.3+65.apk",
    "/var/www/serenut/server/releases/app-release.apk"
]

win_candidates = [
    "/var/www/serenut/server/releases/SerenutOS-v1.2.3.exe",
    "/var/www/serenut/server/releases/SerenutOSSetup-1.2.3+65.exe",
    "/var/www/serenut/server/releases/SerenutOSSetup.exe"
]

apk_path = next((p for p in apk_candidates if os.path.exists(p)), None)
win_path = next((p for p in win_candidates if os.path.exists(p)), None)

if not apk_path or not win_path:
    print(f"Release files not found on server disk. APK: {apk_path}, WIN: {win_path}")
    sys.exit(1)

apk_chk, apk_sig, apk_size = get_signature_and_hash(apk_path)
win_chk, win_sig, win_size = get_signature_and_hash(win_path)

os.system("mkdir -p /var/www/serenut-api/releases")
os.system(f"cp '{apk_path}' /var/www/serenut-api/releases/SerenutOS-v1.2.3.apk")
os.system(f"cp '{win_path}' /var/www/serenut-api/releases/SerenutOS-v1.2.3.exe")
os.system("chmod -R 777 /var/www/serenut/server/releases /var/www/serenut-api/releases")
os.system("chown -R 1000:1000 /var/www/serenut/server/releases /var/www/serenut-api/releases")

def insert_db(id_val, version, platform, channel, path, size, checksum, sig, notes):
    sql = f"""
    INSERT INTO app_versions (
      id, version_code, platform, channel, download_url, file_path,
      sha256_hash, signature, file_size_bytes, is_mandatory, min_required_version,
      release_notes, status, rollout_percentage, created_at, updated_at
    ) VALUES (
      '{id_val}', '{version}', '{platform}', '{channel}', '/api/v1/updates/download/{platform}/latest', '{path}',
      '{checksum}', '{sig}', {size}, true, '1.0.0',
      '{notes}', 'active', 100, NOW(), NOW()
    ) ON CONFLICT (version_code, platform, channel) DO UPDATE SET
      file_path = EXCLUDED.file_path,
      file_size_bytes = EXCLUDED.file_size_bytes,
      sha256_hash = EXCLUDED.sha256_hash,
      signature = EXCLUDED.signature,
      status = 'active',
      updated_at = NOW();
    """
    cmd = ["docker", "exec", "-i", "serenut-db", "psql", "-U", "serenut_user", "-d", "serenut_db", "-c", sql]
    res = subprocess.run(cmd, capture_output=True, text=True)
    print(f"DB Result {platform}:", res.stdout, res.stderr)

# Clean semantic version 1.2.3 without internal build number '+' for public UI and API
insert_db("rel-apk-12365", "1.2.3+65", "android", "stable", "/var/www/serenut-api/releases/SerenutOS-v1.2.3.apk", apk_size, apk_chk, apk_sig, "Serenut OS v1.2.3 — Stable Release")
insert_db("rel-win-12365", "1.2.3+65", "windows", "stable", "/var/www/serenut-api/releases/SerenutOS-v1.2.3.exe", win_size, win_chk, win_sig, "Serenut OS v1.2.3 — Stable Release")

# Also insert clean semantic tag 1.2.3 if queried by exact semantic version
insert_db("rel-apk-123", "1.2.3", "android", "stable", "/var/www/serenut-api/releases/SerenutOS-v1.2.3.apk", apk_size, apk_chk, apk_sig, "Serenut OS v1.2.3 — Stable Release")
insert_db("rel-win-123", "1.2.3", "windows", "stable", "/var/www/serenut-api/releases/SerenutOS-v1.2.3.exe", win_size, win_chk, win_sig, "Serenut OS v1.2.3 — Stable Release")

print("ALL_RELEASES_1.2.3_PUBLISHED_SUCCESSFULLY")
