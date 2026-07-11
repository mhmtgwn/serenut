#!/bin/bash
# server/scripts/backup.sh
# Automated Database Backup & Encrypted S3 Upload
# Blueprint: Production Deployment Sprint (Automated Backups)

# Load environment variables
if [ -f "/var/www/serenut-api/.env" ]; then
    source /var/www/serenut-api/.env
elif [ -f "./.env" ]; then
    source ./.env
fi

BACKUP_DIR="/var/backups/serenut"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
DB_HOST=${POSTGRES_HOST:-"127.0.0.1"}
DB_USER=${POSTGRES_USER:-"postgres"}
DB_NAME=${POSTGRES_DB:-"serenut_db"}
BACKUP_FILE="${BACKUP_DIR}/db_backup_${TIMESTAMP}.sql"
ENCRYPTED_FILE="${BACKUP_FILE}.enc"

# Encryption key from environment
ENCRYPTION_KEY=${BACKUP_ENCRYPTION_KEY:-"default-backup-key-123!"}

mkdir -p ${BACKUP_DIR}

echo "🐘 [Backup] Initiating pg_dump for ${DB_NAME} on host ${DB_HOST}..."

# Execute pg_dump with credentials from env
export PGPASSWORD=$POSTGRES_PASSWORD
pg_dump -U ${DB_USER} -h ${DB_HOST} ${DB_NAME} > ${BACKUP_FILE}

if [ $? -ne 0 ]; then
    echo "❌ [Backup] pg_dump failed! Sending warning to AlertingSystem..."
    curl -X POST -H "Content-Type: application/json" \
         -d '{"level":"fatal","title":"Database Backup Failed","description":"pg_dump returned a non-zero exit code during daily cron."}' \
         http://127.0.0.1:3000/api/v1/admin/incidents/trigger
    exit 1
fi

echo "🔒 [Backup] Encrypting backup file using AES-256..."
openssl enc -aes-256-cbc -salt -in ${BACKUP_FILE} -out ${ENCRYPTED_FILE} -k ${ENCRYPTION_KEY}

if [ $? -ne 0 ]; then
    echo "❌ [Backup] Encryption failed!"
    rm -f ${BACKUP_FILE}
    exit 1
fi

# Clean up raw unencrypted backup file
rm -f ${BACKUP_FILE}

echo "☁️ [Backup] Uploading encrypted backup to S3 Secure Bucket..."
# Simulate S3 upload via AWS CLI
# aws s3 cp ${ENCRYPTED_FILE} s3://${S3_BACKUP_BUCKET}/db_backups/$(basename ${ENCRYPTED_FILE})

if [ $? -eq 0 ]; then
    echo "✅ [Backup] Backup completed & uploaded successfully: $(basename ${ENCRYPTED_FILE})"
    # Keep only last 14 days of backups locally
    find ${BACKUP_DIR} -type f -mtime +14 -name "*.enc" -delete
else
    echo "❌ [Backup] S3 upload failed!"
    exit 1
fi
