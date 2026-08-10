#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-.env.production}"
api_key="$(cat)"
case "$api_key" in
  re_*) ;;
  *) echo "Invalid Resend API key" >&2; exit 1 ;;
esac
if grep -q '^RESEND_API_KEY=' "$ENV_FILE"; then
  sed -i "s|^RESEND_API_KEY=.*|RESEND_API_KEY=$api_key|" "$ENV_FILE"
else
  printf 'RESEND_API_KEY=%s\n' "$api_key" >> "$ENV_FILE"
fi
chmod 600 "$ENV_FILE"
echo "Resend API key configured."
