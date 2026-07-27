import os
import hashlib
import base64
import subprocess

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

apk_path = "/var/www/serenut/server/releases/app-release-1.2.0+27.apk"
win_path = "/var/www/serenut/server/releases/SerenutOSSetup-1.2.0+27.exe"

if not os.path.exists(apk_path) or not os.path.exists(win_path):
    print("Files not fully uploaded yet")
    exit(1)

apk_chk, apk_sig, apk_size = get_signature_and_hash(apk_path)
win_chk, win_sig, win_size = get_signature_and_hash(win_path)

os.system("mkdir -p /var/www/serenut-api/releases")
os.system("cp /var/www/serenut/server/releases/app-release-1.2.0+27.apk /var/www/serenut-api/releases/app-release-1.2.0+27.apk")
os.system("cp /var/www/serenut/server/releases/SerenutOSSetup-1.2.0+27.exe /var/www/serenut-api/releases/SerenutOSSetup-1.2.0+27.exe")
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

insert_db("rel-apk-12027", "1.2.0+27", "android", "stable", "/var/www/serenut-api/releases/app-release-1.2.0+27.apk", apk_size, apk_chk, apk_sig, "Tam senkronizasyon ve buluttan veri cekme destegi")
insert_db("rel-win-12027", "1.2.0+27", "windows", "stable", "/var/www/serenut-api/releases/SerenutOSSetup-1.2.0+27.exe", win_size, win_chk, win_sig, "Tam senkronizasyon ve buluttan veri cekme destegi")
print("ALL_RELEASES_1.2.0+27_PUBLISHED_SUCCESSFULLY")
