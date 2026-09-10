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
