#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  . ./.env
  set +a
fi

X3UI_PANEL_PORT="${X3UI_PANEL_PORT:-2053}"
X3UI_VLESS_PORT="${X3UI_VLESS_PORT:-8443}"
X3UI_USERNAME="${X3UI_USERNAME:-admin}"
X3UI_PASSWORD="${X3UI_PASSWORD:-admin}"
X3UI_INBOUND_ID="${X3UI_INBOUND_ID:-1}"

PANEL_URL="http://127.0.0.1:${X3UI_PANEL_PORT}"
COOKIE_FILE="$(mktemp)"
HTML_FILE="$(mktemp)"
LOGIN_FILE="$(mktemp)"
INBOUNDS_FILE="$(mktemp)"
ADD_FILE="$(mktemp)"

cleanup() {
  rm -f "$COOKIE_FILE" "$HTML_FILE" "$LOGIN_FILE" "$INBOUNDS_FILE" "$ADD_FILE"
}
trap cleanup EXIT

docker compose up -d

echo "Waiting for 3x-ui panel on ${PANEL_URL}..."
for _ in $(seq 1 30); do
  if curl -fsS -c "$COOKIE_FILE" -o "$HTML_FILE" "${PANEL_URL}/"; then
    break
  fi
  sleep 2
done

if [ ! -s "$HTML_FILE" ]; then
  echo "3x-ui panel did not become ready on ${PANEL_URL}" >&2
  exit 1
fi

docker compose exec -T x3ui /app/x-ui setting \
  -username "$X3UI_USERNAME" \
  -password "$X3UI_PASSWORD" >/dev/null

docker compose restart x3ui >/dev/null

echo "Waiting for 3x-ui panel after settings update..."
for _ in $(seq 1 30); do
  if curl -fsS -c "$COOKIE_FILE" -o "$HTML_FILE" "${PANEL_URL}/"; then
    break
  fi
  sleep 2
done

CSRF_TOKEN="$(sed -n 's/.*csrf-token" content="\([^"]*\)".*/\1/p' "$HTML_FILE" | head -n 1)"
if [ -z "$CSRF_TOKEN" ]; then
  echo "Could not read CSRF token from 3x-ui login page" >&2
  exit 1
fi

curl -fsS \
  -b "$COOKIE_FILE" \
  -c "$COOKIE_FILE" \
  -o "$LOGIN_FILE" \
  -H "X-CSRF-Token: ${CSRF_TOKEN}" \
  -X POST \
  --data-urlencode "username=${X3UI_USERNAME}" \
  --data-urlencode "password=${X3UI_PASSWORD}" \
  "${PANEL_URL}/login"

if ! grep -q '"success":true' "$LOGIN_FILE"; then
  echo "3x-ui login failed:" >&2
  cat "$LOGIN_FILE" >&2
  exit 1
fi

curl -fsS \
  -b "$COOKIE_FILE" \
  -o "$INBOUNDS_FILE" \
  "${PANEL_URL}/panel/api/inbounds/list"

if grep -q "\"id\":${X3UI_INBOUND_ID}" "$INBOUNDS_FILE"; then
  echo "Inbound ${X3UI_INBOUND_ID} already exists."
  exit 0
fi

cat > "$ADD_FILE" <<JSON
{
  "up": 0,
  "down": 0,
  "total": 0,
  "remark": "miloshvpn-vless",
  "enable": true,
  "expiryTime": 0,
  "listen": "",
  "port": ${X3UI_VLESS_PORT},
  "protocol": "vless",
  "settings": "{\"clients\":[],\"decryption\":\"none\",\"fallbacks\":[]}",
  "streamSettings": "{\"network\":\"tcp\",\"security\":\"none\",\"tcpSettings\":{\"acceptProxyProtocol\":false,\"header\":{\"type\":\"none\"}}}",
  "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\"],\"metadataOnly\":false,\"routeOnly\":false}",
  "allocate": "{\"strategy\":\"always\",\"refresh\":5,\"concurrency\":3}"
}
JSON

curl -fsS \
  -b "$COOKIE_FILE" \
  -o "$INBOUNDS_FILE" \
  -H "Content-Type: application/json" \
  -H "X-CSRF-Token: ${CSRF_TOKEN}" \
  --data "@${ADD_FILE}" \
  "${PANEL_URL}/panel/api/inbounds/add"

if ! grep -q '"success":true' "$INBOUNDS_FILE"; then
  echo "Failed to create VLESS inbound:" >&2
  cat "$INBOUNDS_FILE" >&2
  exit 1
fi

echo "3x-ui is ready."
echo "Panel: ${PANEL_URL}/"
echo "VLESS inbound port: ${X3UI_VLESS_PORT}"
