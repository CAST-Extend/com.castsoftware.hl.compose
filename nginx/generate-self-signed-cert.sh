#!/usr/bin/env bash
# Generates a self-signed TLS cert/key for the nginx gateway, valid for the hostname in
# PUBLIC_HOST (read from ../.env unless passed as $1). Run once before the first
# `docker compose up`, and again if PUBLIC_HOST ever changes.
#
# Self-signed = browsers will show a trust warning. That's fine for internal/lab use; for
# anything reachable by real users, replace nginx/certs/fullchain.pem and privkey.pem with a
# CA-issued cert instead of running this script.
set -euo pipefail

cd "$(dirname "$0")"

if [ -n "${1:-}" ]; then
  HOST="$1"
  SOURCE="command line"
else
  # Strip CR (.env edited on Windows) and surrounding quotes.
  HOST="$(grep -E '^PUBLIC_HOST=' ../.env 2>/dev/null | tail -n1 | cut -d= -f2- | tr -d '\r"'"'" || true)"
  SOURCE="../.env"
fi
if [ -z "${HOST}" ]; then
  HOST=localhost
  SOURCE="default"
  echo "WARNING: no PUBLIC_HOST found (../.env missing or has no PUBLIC_HOST= line) - using 'localhost'." >&2
  echo "         Create ../.env first, or pass the hostname: $0 <hostname>" >&2
fi
echo "Generating cert for '${HOST}' (from ${SOURCE})."

mkdir -p certs

openssl req -x509 -nodes -days 825 \
  -newkey rsa:2048 \
  -keyout certs/privkey.pem \
  -out certs/fullchain.pem \
  -subj "/CN=${HOST}" \
  -addext "subjectAltName=DNS:${HOST},IP:127.0.0.1"

echo "Wrote nginx/certs/fullchain.pem + privkey.pem for host '${HOST}' (self-signed, valid 825 days)."
