#!/usr/bin/env bash
# generate-shopify-token.sh
# Genera (o regenera) el access token Admin API usando Client Credentials flow.
# Lee credenciales de ./.env y guarda el token de vuelta en el mismo archivo.
# Token TTL ~24h. Cuando expire, ejecutar de nuevo.

set -euo pipefail

# --- Localizar el .env ---
# Busca .env en el directorio actual primero; si no, sube hasta encontrarlo.
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
  echo "❌ No se encontró .env en el directorio actual ni en directorios padre."
  echo "   Crea un .env desde la plantilla: cp setup-cod-stack/assets/env.template .env"
  exit 1
fi

echo "📄 Usando .env: $ENV_FILE"

# --- Cargar variables ---
set -a
# shellcheck disable=SC1090
source "$ENV_FILE"
set +a

# --- Validar requisitos ---
: "${SHOPIFY_STORE_DOMAIN:?SHOPIFY_STORE_DOMAIN no está definido en .env}"
: "${SHOPIFY_CLIENT_ID:?SHOPIFY_CLIENT_ID no está definido en .env}"
: "${SHOPIFY_CLIENT_SECRET:?SHOPIFY_CLIENT_SECRET no está definido en .env}"

# Default API version si no está definida
SHOPIFY_API_VERSION="${SHOPIFY_API_VERSION:-2026-04}"

# --- Llamar al endpoint OAuth ---
echo "🔑 Solicitando access token a Shopify..."
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  "https://${SHOPIFY_STORE_DOMAIN}/admin/oauth/access_token" \
  -H "Content-Type: application/json" \
  -d "{\"client_id\":\"${SHOPIFY_CLIENT_ID}\",\"client_secret\":\"${SHOPIFY_CLIENT_SECRET}\",\"grant_type\":\"client_credentials\"}")

HTTP_CODE=$(echo "$RESPONSE" | tail -n 1)
BODY=$(echo "$RESPONSE" | sed '$d')

if [ "$HTTP_CODE" != "200" ]; then
  echo "❌ Error HTTP $HTTP_CODE"
  echo "   Respuesta: $BODY"
  echo ""
  echo "Causas comunes:"
  echo "  - 400 invalid_client: Client ID/Secret mal copiado o espacios extras"
  echo "  - 400 application_cannot_be_found: La app no está instalada en la tienda"
  echo "  - 401 unauthorized: Credenciales revocadas o app sin scopes válidos"
  exit 1
fi

# --- Parsear respuesta ---
# Sin jq, usando solo bash + sed (más portable)
ACCESS_TOKEN=$(echo "$BODY" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')
EXPIRES_IN=$(echo "$BODY" | sed -n 's/.*"expires_in":\([0-9]*\).*/\1/p')

if [ -z "$ACCESS_TOKEN" ]; then
  echo "❌ No se pudo extraer access_token de la respuesta:"
  echo "   $BODY"
  exit 1
fi

GENERATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Actualizar .env (in-place, portable Mac/Linux) ---
update_env_var() {
  local key="$1"
  local value="$2"
  local file="$3"

  if grep -q "^${key}=" "$file"; then
    # macOS sed requiere -i ''
    if [ "$(uname)" = "Darwin" ]; then
      sed -i '' "s|^${key}=.*|${key}=${value}|" "$file"
    else
      sed -i "s|^${key}=.*|${key}=${value}|" "$file"
    fi
  else
    echo "${key}=${value}" >> "$file"
  fi
}

update_env_var "SHOPIFY_ACCESS_TOKEN" "$ACCESS_TOKEN" "$ENV_FILE"
update_env_var "SHOPIFY_TOKEN_GENERATED_AT" "$GENERATED_AT" "$ENV_FILE"
update_env_var "SHOPIFY_TOKEN_EXPIRES_IN" "$EXPIRES_IN" "$ENV_FILE"
update_env_var "SHOPIFY_API_VERSION" "$SHOPIFY_API_VERSION" "$ENV_FILE"

# --- Confirmar (sin imprimir el token) ---
TOKEN_PREFIX="${ACCESS_TOKEN:0:6}"
EXPIRES_HOURS=$((EXPIRES_IN / 3600))

echo ""
echo "✅ Access token generado y guardado en $ENV_FILE"
echo "   Prefijo: ${TOKEN_PREFIX}... (oculto por seguridad)"
echo "   Generado: $GENERATED_AT"
echo "   Expira en: ~${EXPIRES_HOURS}h"
echo ""
echo "Cuando el token expire (en ~24h), corre este mismo script de nuevo."
