#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-.env.production}"
WEBHOOK_URL="${WHATSAPP_WEBHOOK_URL:-https://serenut.com/api/v1/whatsapp/webhook}"

required="META_APP_ID META_APP_SECRET WHATSAPP_EMBEDDED_SIGNUP_CONFIG_ID WHATSAPP_WEBHOOK_VERIFY_TOKEN WHATSAPP_CREDENTIAL_ENCRYPTION_KEY"
for key in $required; do
  value="$(sed -n "s/^${key}=//p" "$ENV_FILE" | tail -n 1)"
  if [ -z "$value" ]; then
    echo "$key is missing" >&2
    exit 1
  fi
done

verify_token="$(sed -n 's/^WHATSAPP_WEBHOOK_VERIFY_TOKEN=//p' "$ENV_FILE" | tail -n 1)"
challenge="serenut-whatsapp-ready"
response="$(curl -fsS --get "$WEBHOOK_URL" \
  --data-urlencode 'hub.mode=subscribe' \
  --data-urlencode "hub.verify_token=$verify_token" \
  --data-urlencode "hub.challenge=$challenge")"
if [ "$response" != "$challenge" ]; then
  echo "Public WhatsApp webhook verification failed" >&2
  exit 1
fi

channels="$(sed -n 's/^NOTIFICATION_ENABLED_CHANNELS=//p' "$ENV_FILE" | tail -n 1)"
case ",$channels," in
  *,whatsapp,*) ;;
  *)
    channels="${channels:-sms,email},whatsapp"
    sed -i "s|^NOTIFICATION_ENABLED_CHANNELS=.*|NOTIFICATION_ENABLED_CHANNELS=$channels|" "$ENV_FILE"
    ;;
esac

chmod 600 "$ENV_FILE"
echo "WhatsApp channel enabled after successful public webhook verification."

