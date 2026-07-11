#!/bin/bash
# devops/backup.sh — PostgreSQL automated backup with GPG encryption and S3 upload

set -e

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="${BACKUP_DIR:-/tmp}"
BACKUP_FILE="serenut_db_${TIMESTAMP}.dump"
GPG_PASS="${BACKUP_PASSPHRASE:-fallback_passphrase}"
S3_BUCKET_NAME="${S3_BUCKET:-serenut-backups}"

echo "🐘 Starting database backup..."

if [ -z "$DATABASE_URL" ]; then
  echo "❌ Error: DATABASE_URL is not set"
  exit 1
fi

# Run pg_dump
pg_dump -Fc "$DATABASE_URL" > "${BACKUP_DIR}/${BACKUP_FILE}"

# Encrypt dump via GPG
echo "🔐 Encrypting backup with GPG..."
gpg --symmetric --cipher-algo AES256 \
  --passphrase "$GPG_PASS" \
  --batch --yes \
  -o "${BACKUP_DIR}/${BACKUP_FILE}.gpg" \
  "${BACKUP_DIR}/${BACKUP_FILE}"

# Remove unencrypted local dump
rm -f "${BACKUP_DIR}/${BACKUP_FILE}"

# Upload to S3 if aws client is installed, else save locally
if command -v aws &> /dev/null && [ -n "$S3_BUCKET" ]; then
  echo "☁️ Uploading to S3: s3://${S3_BUCKET_NAME}/backups/${BACKUP_FILE}.gpg"
  aws s3 cp "${BACKUP_DIR}/${BACKUP_FILE}.gpg" "s3://${S3_BUCKET_NAME}/backups/${BACKUP_FILE}.gpg"
  rm -f "${BACKUP_DIR}/${BACKUP_FILE}.gpg"
  echo "✅ Backup uploaded successfully to S3."
else
  echo "⚠️ AWS CLI or S3_BUCKET not found/configured. Storing backup locally in backups/ directory."
  mkdir -p backups
  mv "${BACKUP_DIR}/${BACKUP_FILE}.gpg" backups/
  echo "✅ Backup stored locally in backups/${BACKUP_FILE}.gpg"
fi
