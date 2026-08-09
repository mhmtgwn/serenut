#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-.env.production}"
secret="$(cat)"
case "$secret" in
  whsec_*) ;;
  *) echo "Invalid Resend webhook secret" >&2; exit 1 ;;
esac
if grep -q '^RESEND_WEBHOOK_SECRET=' "$ENV_FILE"; then
  sed -i "s|^RESEND_WEBHOOK_SECRET=.*|RESEND_WEBHOOK_SECRET=$secret|" "$ENV_FILE"
else
  printf 'RESEND_WEBHOOK_SECRET=%s\n' "$secret" >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"
echo "Resend webhook secret configured."
