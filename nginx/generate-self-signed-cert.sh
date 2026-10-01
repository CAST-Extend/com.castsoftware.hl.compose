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

HOST="${1:-$(grep -E '^PUBLIC_HOST=' ../.env 2>/dev/null | cut -d= -f2)}"
HOST="${HOST:-localhost}"

mkdir -p certs

openssl req -x509 -nodes -days 825 \
  -newkey rsa:2048 \
  -keyout certs/privkey.pem \
  -out certs/fullchain.pem \
  -subj "/CN=${HOST}" \
  -addext "subjectAltName=DNS:${HOST},IP:127.0.0.1"

echo "Wrote nginx/certs/fullchain.pem + privkey.pem for host '${HOST}' (self-signed, valid 825 days)."
