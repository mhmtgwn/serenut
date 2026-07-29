#!/usr/bin/env sh
set -eu

cd "$(dirname "$0")/.."

# Docker creates a directory for a missing bind-mount source. Replace only an
# empty directory left by that behavior; any unexpected content stops deploy.
if [ -d .maintenance-token ]; then
  rmdir .maintenance-token
fi

if [ ! -s .maintenance-token ]; then
  umask 077
  token_tmp=".maintenance-token.tmp.$$"
  trap 'rm -f "$token_tmp"' EXIT HUP INT TERM
  head -c 32 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$token_tmp"
  mv "$token_tmp" .maintenance-token
  trap - EXIT HUP INT TERM
fi

# Backend image runs as UID 1000. The hardened agent has no DAC override
# capability, so it reads through its root group. No other user gets access.
chown 1000:0 .maintenance-token
chmod 640 .maintenance-token
test -f .maintenance-token
test -s .maintenance-token
