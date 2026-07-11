#!/bin/bash
# deploy.sh — Atomic deployment & rollback script for Serenut OS SaaS Backend

set -e

APP_DIR="/var/www/serenut_new/server"
BACKUP_DIR="/var/www/serenut_new/backups"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROLLBACK_VERSION=""

echo "🌀 Starting atomic deployment for Serenut OS..."

# Step 1: Backup current working directory in case of failure
if [ -d "$APP_DIR" ]; then
  echo "📦 Creating current version backup..."
  mkdir -p "$BACKUP_DIR"
  tar -czf "$BACKUP_DIR/backup_before_deploy_$TIMESTAMP.tar.gz" -C "$APP_DIR" .
  ROLLBACK_VERSION="$BACKUP_DIR/backup_before_deploy_$TIMESTAMP.tar.gz"
fi

# Step 2: Graceful deployment pipeline
rollback() {
  echo "⚠️ Deployment failed! Rolling back to previous state..."
  if [ -n "$ROLLBACK_VERSION" ]; then
    rm -rf "$APP_DIR/*"
    tar -xzf "$ROLLBACK_VERSION" -C "$APP_DIR"
    echo "🔄 Previous state restored. Gracefully restarting service..."
    pm2 reload serenut-server || docker-compose restart server
  fi
  exit 1
}

trap rollback ERR

echo "📥 Fetching latest code from main branch..."
git pull origin main

echo "📦 Installing production dependencies..."
npm ci --only=production

echo "🔨 Building TypeScript server application..."
npm run build

echo "🗄️ Running database schema migrations..."
npm run migrate

echo "🟢 Graceful reload application process..."
if command -v pm2 &> /dev/null; then
  pm2 reload serenut-server --update-env
elif command -v docker-compose &> /dev/null; then
  docker-compose exec -T server npm run migrate
  docker-compose restart server
fi

# Step 3: Self Health-Check Verification
echo "🔬 Running self-diagnostic health check..."
sleep 3
HEALTH=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000/health || echo "500")

if [ "$HEALTH" -ne 200 ]; then
  echo "❌ Health check failed with status $HEALTH!"
  false # Triggers rollback trap
fi

echo "✅ Serenut OS deployed successfully to production. System is healthy!"
