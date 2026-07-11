#!/bin/bash
# dr-restore-test.sh — Disaster Recovery automated restore integrity test script

set -e

BACKUP_FILE=$1
GPG_PASS="${GPG_PASSPHRASE:-fallback_passphrase}"
TEMP_CONTAINER="serenut_dr_verify_postgres"
DB_USER="postgres"
DB_NAME="serenut_dr_verify"

if [ -z "$BACKUP_FILE" ]; then
  echo "❌ Error: Please specify the path of the GPG encrypted backup file (.sql.gz.gpg)"
  echo "Usage: ./dr-restore-test.sh /path/to/backup.sql.gz.gpg"
  exit 1
fi

echo "🧪 Starting Disaster Recovery (DR) verification test..."
echo "📂 Backup File: $BACKUP_FILE"

# Step 1: Decrypt and decompress dump
echo "🔓 Decrypting database dump..."
gpg --batch --yes --passphrase "$GPG_PASS" --decrypt "$BACKUP_FILE" > temp_backup.sql.gz
gunzip -f temp_backup.sql.gz

# Step 2: Spin up temporary Postgres Container
echo "🐘 Spinning up temporary isolated Postgres instance..."
docker run --name "$TEMP_CONTAINER" -e POSTGRES_PASSWORD=verify_secret -d -p 54321:5432 postgres:15

# Wait for postgres to be ready
echo "⏳ Waiting for PostgreSQL to bootstrap..."
until docker exec "$TEMP_CONTAINER" pg_isready -U "$DB_USER" >/dev/null 2>&1; do
  sleep 1
done

# Step 3: Create verify database and restore schema/data
echo "⚙️ Restoring database dump..."
docker exec "$TEMP_CONTAINER" psql -U "$DB_USER" -c "CREATE DATABASE $DB_NAME;"
docker exec -i "$TEMP_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" < temp_backup.sql

# Step 4: Run diagnostic integrity checks
echo "🔬 Verifying database table structures and row counts..."
CHECK_COMPANIES=$(docker exec -t "$TEMP_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM companies;" | tr -d '[:space:]')
CHECK_LICENSES=$(docker exec -t "$TEMP_CONTAINER" psql -U "$DB_USER" -d "$DB_NAME" -t -c "SELECT COUNT(*) FROM licenses;" | tr -d '[:space:]')

echo "📊 Companies count in backup: $CHECK_COMPANIES"
echo "📊 Licenses count in backup: $CHECK_LICENSES"

# Step 5: Clean up
echo "🧹 Cleaning up temp containers and decrypted files..."
docker stop "$TEMP_CONTAINER"
docker rm "$TEMP_CONTAINER"
rm -f temp_backup.sql

if [ "$CHECK_COMPANIES" -gt 0 ] && [ "$CHECK_LICENSES" -gt 0 ]; then
  echo "✅ DISASTER RECOVERY RESTORE TEST PASSED! Backup file is valid and integral."
  exit 0
else
  echo "❌ DISASTER RECOVERY RESTORE TEST FAILED! Empty database tables detected."
  exit 1
fi
