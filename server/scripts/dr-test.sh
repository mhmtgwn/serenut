#!/usr/bin/env bash
# server/scripts/dr-test.sh
# Serenut OS — Automated Disaster Recovery (DR) Verification Suite
# Blueprint: Enterprise Certification (DR Automation & Restore Verification)

set -e

BACKUP_FILE=$1
if [ -z "${BACKUP_FILE}" ]; then
  echo "Usage: ./dr-test.sh <path_to_encrypted_backup.enc>"
  exit 1
fi

echo "🏁 Starting Disaster Recovery (DR) Restore Verification..."

# 1. Spin up a temporary PostgreSQL test container on port 5439
echo "🐳 Spawning temporary PostgreSQL container (dr-postgres-temp)..."
docker run --name dr-postgres-temp -e POSTGRES_PASSWORD=temp_pass_dr_123 -d -p 5439:5432 postgres:15-alpine
sleep 5

# Export environment parameters pointing to the temp database for restore.sh
export POSTGRES_HOST="127.0.0.1"
export POSTGRES_PORT="5439"
export POSTGRES_USER="postgres"
export POSTGRES_DB="postgres"
export POSTGRES_PASSWORD="temp_pass_dr_123"
export BACKUP_ENCRYPTION_KEY=${BACKUP_ENCRYPTION_KEY:-"default-backup-key-123!"}

# 2. Execute the restore utility
echo "🔓 Triggering database decryption & restore on temp port 5439..."
./restore.sh "${BACKUP_FILE}"

if [ $? -eq 0 ]; then
  echo "✅ Decryption & restore execution completed."
else
  echo "❌ Decryption & restore execution failed!"
  docker rm -f dr-postgres-temp
  exit 1
fi

# 3. Assert schema integrity and query row/table counts
echo "📊 Querying schema metadata to verify restore integrity..."
TABLE_COUNT=$(PGPASSWORD=temp_pass_dr_123 psql -U postgres -h 127.0.0.1 -p 5439 -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';")
echo "📊 Total public tables restored: ${TABLE_COUNT}"

# Basic sanity threshold check (must restore at least core schema tables)
if [ "${TABLE_COUNT}" -gt 5 ]; then
  echo "⭐ Disaster Recovery Verification PASSED: Database successfully recovered and readable!"
  docker rm -f dr-postgres-temp
  exit 0
else
  echo "❌ Disaster Recovery Verification FAILED: Recovered schema has missing or corrupted tables."
  docker rm -f dr-postgres-temp
  exit 1
fi
