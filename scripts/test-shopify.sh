#!/usr/bin/env bash
# test-shopify.sh
# Test rápido de la conexión Admin API: GET /shop.json
# Si retorna 200 con info de la tienda, todo está conectado.

set -euo pipefail

# --- Localizar el .env ---
ENV_FILE=""
DIR="$(pwd)"
while [ "$DIR" != "/" ]; do
  if [ -f "$DIR/.env" ]; then
    ENV_FILE="$DIR/.env"
    break
  fi
  DIR="$(dirname "$DIR")"
done

if [ -z "$ENV_FILE" ]; then
  echo "❌ No se encontró .env"
  exit 1
fi

# --- Cargar variables ---
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

: "${SHOPIFY_STORE_DOMAIN:?SHOPIFY_STORE_DOMAIN no está definido}"
: "${SHOPIFY_ACCESS_TOKEN:?SHOPIFY_ACCESS_TOKEN no está definido — corre generate-shopify-token.sh primero}"

SHOPIFY_API_VERSION="${SHOPIFY_API_VERSION:-2026-04}"

# --- Test ---
echo "🔍 Test: GET /admin/api/${SHOPIFY_API_VERSION}/shop.json"
echo ""

RESPONSE=$(curl -s -w "\n%{http_code}" \
  "https://${SHOPIFY_STORE_DOMAIN}/admin/api/${SHOPIFY_API_VERSION}/shop.json" \
  -H "X-Shopify-Access-Token: ${SHOPIFY_ACCESS_TOKEN}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
  echo "❌ HTTP $HTTP_CODE"
  echo "$BODY" | head -c 500
  echo ""
  if [ "$HTTP_CODE" = "401" ]; then
    echo ""
    echo "→ Token expirado o inválido. Regenera con: bash scripts/generate-shopify-token.sh"
  fi
  exit 1
fi

# --- Extraer campos clave (sin jq) ---
SHOP_NAME=$(echo "$BODY" | sed -n 's/.*"name":"\([^"]*\)".*/\1/p' | head -1)
PLAN=$(echo "$BODY" | sed -n 's/.*"plan_display_name":"\([^"]*\)".*/\1/p')
CURRENCY=$(echo "$BODY" | sed -n 's/.*"currency":"\([^"]*\)".*/\1/p')
COUNTRY=$(echo "$BODY" | sed -n 's/.*"country_name":"\([^"]*\)".*/\1/p')

echo "✅ Conexión Admin API verificada"
echo ""
echo "   Tienda:   $SHOP_NAME"
echo "   Dominio:  $SHOPIFY_STORE_DOMAIN"
echo "   Plan:     $PLAN"
echo "   País:     $COUNTRY"
echo "   Moneda:   $CURRENCY"
echo ""
echo "Tu stack Shopify está listo. Ahora puedes hacer llamadas a la Admin API."
