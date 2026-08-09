#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
ENV_FILE="${ENV_FILE:-.env.production}"
ENDPOINT="${RESEND_WEBHOOK_ENDPOINT:-https://api.serenut.com/api/v1/support/webhooks/resend}"

api_key="$(sed -n 's/^RESEND_API_KEY=//p' "$ENV_FILE" | tail -n 1)"
if [ -z "$api_key" ]; then
  echo "RESEND_API_KEY is missing" >&2
  exit 1
fi

existing="$(curl -fsS https://api.resend.com/webhooks -H "Authorization: Bearer $api_key")"
webhook_id="$(WEBHOOK_JSON="$existing" ENDPOINT="$ENDPOINT" node -e '
  const data=JSON.parse(process.env.WEBHOOK_JSON);
  const item=(data.data||[]).find(value=>value.endpoint===process.env.ENDPOINT);
  process.stdout.write(item?.id||"");
')"

if [ -z "$webhook_id" ]; then
  created="$(curl -fsS -X POST https://api.resend.com/webhooks \
    -H "Authorization: Bearer $api_key" \
    -H 'Content-Type: application/json' \
    --data "{\"endpoint\":\"$ENDPOINT\",\"events\":[\"email.received\",\"email.delivered\",\"email.bounced\",\"email.complained\",\"email.failed\"]}")"
  webhook_id="$(WEBHOOK_JSON="$created" node -e '
    const data=JSON.parse(process.env.WEBHOOK_JSON);
    if(!data.id||!data.signing_secret) process.exit(2);
    process.stdout.write(data.id);
  ')"
  webhook_secret="$(WEBHOOK_JSON="$created" node -e '
    process.stdout.write(JSON.parse(process.env.WEBHOOK_JSON).signing_secret||"");
  ')"
  if grep -q '^RESEND_WEBHOOK_SECRET=' "$ENV_FILE"; then
    sed -i "s|^RESEND_WEBHOOK_SECRET=.*|RESEND_WEBHOOK_SECRET=$webhook_secret|" "$ENV_FILE"
  else
    printf 'RESEND_WEBHOOK_SECRET=%s\n' "$webhook_secret" >> "$ENV_FILE"
  fi
else
  echo "Existing webhook found; checking local signing secret."
  grep -q '^RESEND_WEBHOOK_SECRET=whsec_' "$ENV_FILE"
fi

chmod 600 "$ENV_FILE"
echo "Resend webhook configured: $webhook_id"
