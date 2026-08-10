#!/usr/bin/env sh
set -eu

env_file="${1:-.env.production}"
secret="$(cat)"
case "$secret" in re_*) ;; *) echo "Invalid Resend SMTP key" >&2; exit 1;; esac

tmp="${env_file}.smtp-key.tmp"
awk -v value="$secret" '
  BEGIN { found=0 }
  /^SMTP_PASSWORD=/ { print "SMTP_PASSWORD=" value; found=1; next }
  { print }
  END { if (!found) print "SMTP_PASSWORD=" value }
' "$env_file" > "$tmp"
chmod 600 "$tmp"
mv "$tmp" "$env_file"
echo "Resend SMTP key configured."
