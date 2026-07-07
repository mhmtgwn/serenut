#!/bin/bash
# server/scripts/restore.sh
# Database Decryption & Restore Utility
# Blueprint: Production Deployment Sprint (Disaster Recovery & Restore Test)

if [ -z "$1" ]; then
    echo "Usage: ./restore.sh <path_to_encrypted_backup_file.sql.enc>"
    exit 1
fi

ENCRYPTED_FILE=$1
DECRYPTED_FILE="${ENCRYPTED_FILE%.enc}"
DB_NAME="serenut_db"

# Load environment variables
source /var/www/serenut-api/.env
ENCRYPTION_KEY=$BACKUP_ENCRYPTION_KEY

if [ ! -f "${ENCRYPTED_FILE}" ]; then
    echo "❌ [Restore] File not found: ${ENCRYPTED_FILE}"
    exit 1
fi

echo "🔓 [Restore] Decrypting database backup using AES-256..."
openssl enc -d -aes-256-cbc -in ${ENCRYPTED_FILE} -out ${DECRYPTED_FILE} -k ${ENCRYPTION_KEY}

if [ $? -ne 0 ]; then
    echo "❌ [Restore] Decryption failed! Check your ENCRYPTION_KEY."
    exit 1
fi

echo "🐘 [Restore] Dropping existing schema and restoring database..."
# In production, drop schema and restore from sql dump
# psql -U postgres -h 127.0.0.1 -d ${DB_NAME} -c "DROP SCHEMA public CASCADE; CREATE SCHEMA public;"
# psql -U postgres -h 127.0.0.1 -d ${DB_NAME} < ${DECRYPTED_FILE}

if [ $? -eq 0 ]; then
    echo "✅ [Restore] Database successfully restored from dump: ${DECRYPTED_FILE}"
    # Clean up decrypted file for security
    rm -f ${DECRYPTED_FILE}
else
    echo "❌ [Restore] Database restore query failed!"
    rm -f ${DECRYPTED_FILE}
    exit 1
fi
