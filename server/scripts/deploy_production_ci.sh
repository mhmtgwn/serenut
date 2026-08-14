#!/usr/bin/env sh
set -eu

VERSION="${1:-}"
if ! printf '%s' "$VERSION" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$'; then
  echo "Usage: $0 <semantic-version+build-number> (example: 1.3.10+90)" >&2
  exit 2
fi

cd "$(dirname "$0")/.."
COMPOSE="docker compose -f docker-compose.prod.yml --env-file .env.production"
SOURCE_VERSION="$(awk '/^version:/ { print $2; exit }' ../pubspec.yaml)"
if [ "$SOURCE_VERSION" != "$VERSION" ]; then
  echo "Artifact version $VERSION does not match checked-out source version $SOURCE_VERSION." >&2
  exit 1
fi

# The maintenance agent is isolated from the public network and accepts only
# allowlisted jobs authenticated with a root-owned shared token.
sh scripts/ensure_maintenance_token.sh

mkdir -p releases
# GitHub cancellation stops the runner but cannot reliably terminate an SSH
# command that is already executing on the VPS. Serialize remote publishers so
# two runs can never consume or replace one another's incoming artifacts.
exec 9>releases/.publishing.lock
if ! flock -w 1200 9; then
  echo "Timed out waiting for the production release lock." >&2
  exit 1
fi
PUBLISH_LOCK="releases/.publishing"
touch "$PUBLISH_LOCK"
INCOMING_DIR="/var/www/serenut-api/releases/_incoming/$VERSION"

rollback_available=0
if docker image inspect serenut-backend:latest >/dev/null 2>&1; then
  docker tag serenut-backend:latest serenut-backend:rollback
  rollback_available=1
fi

rollback() {
  if [ "$rollback_available" = "1" ]; then
    echo "Health check failed; restoring previous backend image."
    docker tag serenut-backend:rollback serenut-backend:latest
    $COMPOSE up -d backend
  fi
}
cleanup() {
  status=$?
  trap - EXIT HUP INT TERM
  rm -f "$PUBLISH_LOCK"
  if [ "$status" -ne 0 ]; then
    rollback
  fi
  exit "$status"
}
trap cleanup EXIT HUP INT TERM

$COMPOSE build backend maintenance-agent
# Validate the actual VPS private key against the supported-client policy
# before migrations, container replacement, or release metadata changes.
$COMPOSE run --rm backend node dist/scripts/publish-release.js verify-policy
docker ps -a -q --filter "name=serenut-maintenance-agent" | xargs -r docker rm -f 2>/dev/null || true
$COMPOSE up -d --force-recreate --remove-orphans maintenance-agent
$COMPOSE run --rm backend node dist/scripts/run-migrations.js

# SCP writes incoming artifacts as the SSH user while the API runs as the
# container's non-root node user. Normalize the shared volume before publish.
$COMPOSE run --rm --user root backend sh -c \
  "mkdir -p '$INCOMING_DIR/android' '$INCOMING_DIR/windows' /var/www/serenut-api/releases/android/stable /var/www/serenut-api/releases/windows/stable && chown -R node:node /var/www/serenut-api/releases"

$COMPOSE up -d --remove-orphans
if ! curl --fail --retry 10 --retry-delay 3 --retry-all-errors http://127.0.0.1:3000/ready; then
  exit 1
fi

$COMPOSE exec -T backend node dist/scripts/publish-release.js batch "$VERSION" \
  "$INCOMING_DIR/android/app-release.apk" \
  "$INCOMING_DIR/windows/SerenutOSSetup.exe" false
metadata=$(curl --fail --silent --show-error \
  "https://api.serenut.com/api/v1/updates/check?platform=android&current_version=0.0.0%2B0")
node -e '
  const response = JSON.parse(process.argv[1]);
  const expectedVersion = process.argv[2];
  if (response.latestVersion !== expectedVersion) throw new Error("published version mismatch");
  if (!/^[a-f0-9]{64}$/.test(response.sha256_hash || "")) throw new Error("missing/invalid SHA-256");
  if (typeof response.signature !== "string" || response.signature.length < 100) throw new Error("missing release signature");
  // PostgreSQL BIGINT values are intentionally returned by node-postgres as
  // strings to avoid precision loss. Release artifacts are well below the JS
  // safe integer limit, so normalize the API value before validating it.
  const fileSizeBytes = Number(response.file_size_bytes);
  if (!Number.isSafeInteger(fileSizeBytes) || fileSizeBytes <= 0) throw new Error("invalid file size");
' "$metadata" "$VERSION"
# Verify the bytes delivered by the public URL (not only database metadata),
# including file size, SHA-256 and the detached RSA signature for both clients.
node ../scripts/verify_published_release.js "$VERSION"
rm -f "$PUBLISH_LOCK"
trap - EXIT HUP INT TERM
