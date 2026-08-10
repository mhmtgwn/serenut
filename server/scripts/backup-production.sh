#!/bin/sh
set -eu

BACKUP_DIR="${BACKUP_DIR:-/var/backups/serenut}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
DB_CONTAINER="${POSTGRES_CONTAINER:-serenut-db}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FINAL_FILE="$BACKUP_DIR/serenut-$STAMP.dump"
TEMP_FILE="$FINAL_FILE.partial"

umask 077
mkdir -p "$BACKUP_DIR"
trap 'rm -f "$TEMP_FILE"' EXIT HUP INT TERM

DB_USER="$(docker exec "$DB_CONTAINER" printenv POSTGRES_USER)"
DB_NAME="$(docker exec "$DB_CONTAINER" printenv POSTGRES_DB)"
test -n "$DB_USER"
test -n "$DB_NAME"

docker exec "$DB_CONTAINER" pg_dump -Fc -U "$DB_USER" -d "$DB_NAME" > "$TEMP_FILE"
test -s "$TEMP_FILE"
docker exec -i "$DB_CONTAINER" pg_restore -l < "$TEMP_FILE" >/dev/null

mv "$TEMP_FILE" "$FINAL_FILE"
trap - EXIT HUP INT TERM
find "$BACKUP_DIR" -maxdepth 1 -type f -name 'serenut-*.dump' -mtime "+$RETENTION_DAYS" -delete

printf 'Verified backup created: %s\n' "$FINAL_FILE"
