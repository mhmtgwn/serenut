#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-.env.production}"

if [ ! -f "$ENV_FILE" ]; then
  echo "$ENV_FILE does not exist" >&2
  exit 1
fi

meta_app_secret="$(cat)"
case "$meta_app_secret" in
  *[!0-9a-fA-F]*|'') echo "Invalid Meta App Secret" >&2; exit 1 ;;
esac
if [ "${#meta_app_secret}" -lt 32 ]; then
  echo "Invalid Meta App Secret" >&2
  exit 1
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

secret_or_generate() {
  key="$1"
  current="$(sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n 1)"
  case "$current" in
    ''|REPLACE_*|SET_*)
      head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n'
      ;;
    *) printf '%s' "$current" ;;
  esac
}

umask 077
webhook_token="$(secret_or_generate WHATSAPP_WEBHOOK_VERIFY_TOKEN)"
encryption_key="$(secret_or_generate WHATSAPP_CREDENTIAL_ENCRYPTION_KEY)"

upsert META_APP_ID 1224880033182854
upsert META_APP_SECRET "$meta_app_secret"
upsert WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID 2051947882108806
upsert WHATSAPP_WEBHOOK_VERIFY_TOKEN "$webhook_token"
upsert WHATSAPP_CREDENTIAL_ENCRYPTION_KEY "$encryption_key"
upsert WHATSAPP_GRAPH_API_VERSION v23.0
upsert WHATSAPP_DEFAULT_COUNTRY_CODE 90

# Meta onayı ve webhook doğrulaması tamamlanana kadar kanalı açma.
if ! grep -q '^NOTIFICATION_ENABLED_CHANNELS=' "$ENV_FILE"; then
  upsert NOTIFICATION_ENABLED_CHANNELS sms,email
fi

chmod 600 "$ENV_FILE"
echo "WhatsApp production environment prepared; channel remains disabled until approval."

