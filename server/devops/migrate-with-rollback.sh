#!/bin/bash
# migrate-with-rollback.sh — Database migration runner with automatic pg_dump rollback on failure

set -e

if [ -z "$DATABASE_URL" ]; then
  echo "❌ Error: DATABASE_URL is not set."
  exit 1
fi

BACKUP_FILE="/tmp/serenut_pre_migrate_$(date +%Y%m%d_%H%M%S).sql"

# Check if pg_dump is available on host
if command -v pg_dump &> /dev/null; then
  echo "📦 Creating pre-migration database snapshot..."
  pg_dump -Fc "$DATABASE_URL" > "$BACKUP_FILE"
  HAS_BACKUP=true
else
  echo "⚠️ Warning: pg_dump not found on host. Bypassing snapshot backup."
  HAS_BACKUP=false
fi

echo "🔄 Running database migrations..."
if npm run migrate; then
  echo "✅ Migration successful."
  if [ "$HAS_BACKUP" = true ]; then
    rm -f "$BACKUP_FILE"
  fi
  exit 0
else
  echo "❌ Migration failed!"
  if [ "$HAS_BACKUP" = true ]; then
    echo "Starting automatic rollback to pre-migration state..."
    pg_restore --clean --if-exists -d "$DATABASE_URL" "$BACKUP_FILE"
    echo "🔄 Rollback completed successfully."
    rm -f "$BACKUP_FILE"
  fi
  exit 1
fi
