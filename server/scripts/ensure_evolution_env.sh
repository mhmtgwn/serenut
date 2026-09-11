#!/usr/bin/env sh
set -eu

ENV_FILE="${ENV_FILE:-.env.production}"

if [ ! -f "$ENV_FILE" ]; then
  echo "⚠️ $ENV_FILE does not exist, skipping evolution env setup" >&2
  exit 0
fi

upsert() {
  key="$1"
  value="$2"
  if grep -q "^${key}=" "$ENV_FILE"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

# COMPOSE_PROFILES: evolution profilini ekle
if grep -q "^COMPOSE_PROFILES=" "$ENV_FILE"; then
  current_profiles="$(sed -n "s/^COMPOSE_PROFILES=//p" "$ENV_FILE" | tail -n 1)"
  case "$current_profiles" in
    *evolution*) ;;
    *) upsert COMPOSE_PROFILES "${current_profiles},evolution" ;;
  esac
else
  upsert COMPOSE_PROFILES "evolution"
fi

# EVOLUTION_API_KEY: varsa koru, yoksa 32-byte hex üret
current_key="$(sed -n "s/^EVOLUTION_API_KEY=//p" "$ENV_FILE" | tail -n 1)"
if [ -z "$current_key" ]; then
  new_key="$(head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n')"
  upsert EVOLUTION_API_KEY "$new_key"
  echo "🔑 Generated new EVOLUTION_API_KEY"
fi

# EVOLUTION_API_URL: yoksa Docker dahili ağ adresi
if ! grep -q "^EVOLUTION_API_URL=" "$ENV_FILE"; then
  upsert EVOLUTION_API_URL "http://evolution-api:8080"
fi

# EVOLUTION_DB_URL: Docker içinden 'db' servisine doğrudan erişecek PostgreSQL URL'si
if ! grep -q "^EVOLUTION_DB_URL=" "$ENV_FILE"; then
  pg_user="$(sed -n "s/^POSTGRES_USER=//p" "$ENV_FILE" | tail -n 1)"
  pg_pass="$(sed -n "s/^POSTGRES_PASSWORD=//p" "$ENV_FILE" | tail -n 1)"
  pg_db="$(sed -n "s/^POSTGRES_DB=//p" "$ENV_FILE" | tail -n 1)"
  if [ -n "$pg_user" ] && [ -n "$pg_pass" ] && [ -n "$pg_db" ]; then
    upsert EVOLUTION_DB_URL "postgresql://${pg_user}:${pg_pass}@db:5432/${pg_db}"
  fi
fi

# EVOLUTION_REDIS_URL: Docker içinden 'redis' servisine doğrudan erişecek Redis URL'si
if ! grep -q "^EVOLUTION_REDIS_URL=" "$ENV_FILE"; then
  redis_pass="$(sed -n "s/^REDIS_PASSWORD=//p" "$ENV_FILE" | tail -n 1)"
  if [ -n "$redis_pass" ]; then
    upsert EVOLUTION_REDIS_URL "redis://:${redis_pass}@redis:6379"
  else
    upsert EVOLUTION_REDIS_URL "redis://redis:6379"
  fi
fi

# WHATSAPP_GATEWAY: evolution olarak ayarla
upsert WHATSAPP_GATEWAY "evolution"

# NOTIFICATION_ENABLED_CHANNELS: whatsapp kanalını etkinleştir
if grep -q "^NOTIFICATION_ENABLED_CHANNELS=" "$ENV_FILE"; then
  current_channels="$(sed -n "s/^NOTIFICATION_ENABLED_CHANNELS=//p" "$ENV_FILE" | tail -n 1)"
  case "$current_channels" in
    *whatsapp*) ;;
    *) upsert NOTIFICATION_ENABLED_CHANNELS "${current_channels},whatsapp" ;;
  esac
else
  upsert NOTIFICATION_ENABLED_CHANNELS "sms,email,whatsapp"
fi

echo "✅ Evolution API environment variables configured in $ENV_FILE"
