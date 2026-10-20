#!/usr/bin/env bash
# Crea i secret datastore e monitoring descritti nel README.
# Uso: bash scripts/setup-secrets.sh [path/to/setup-secrets.env]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="${1:-$REPO_ROOT/scripts/setup-secrets.env}"

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Manca $ENV_FILE — copia da scripts/setup-secrets.example.env e compila." >&2
  exit 1
fi

# shellcheck source=/dev/null
source "$ENV_FILE"

require() {
  local name=$1 val=$2
  if [[ -z "${val:-}" ]]; then
    echo "Variabile obbligatoria vuota: $name" >&2
    exit 1
  fi
}

require APPS_POSTGRES_PASSWORD "$APPS_POSTGRES_PASSWORD"
require APPS_VALKEY_PASSWORD "$APPS_VALKEY_PASSWORD"
require APPS_PGADMIN_EMAIL "$APPS_PGADMIN_EMAIL"
require APPS_PGADMIN_PASSWORD "$APPS_PGADMIN_PASSWORD"
require STAGING_POSTGRES_PASSWORD "$STAGING_POSTGRES_PASSWORD"
require STAGING_VALKEY_PASSWORD "$STAGING_VALKEY_PASSWORD"

if [[ -f "$SCRIPT_DIR/lib/kube.sh" ]]; then
  # shellcheck source=lib/kube.sh
  source "$SCRIPT_DIR/lib/kube.sh"
elif [[ -f "$SCRIPT_DIR/kube.sh" ]]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/kube.sh"
else
  echo "Manca scripts/lib/kube.sh" >&2
  exit 1
fi
if ! kube_init; then
  echo "Esegui sulla VM k3s oppure: bash scripts/setup-secrets-via-ssh.sh" >&2
  exit 127
fi

$KUBECTL create namespace apps --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL create namespace apps-staging --dry-run=client -o yaml | $KUBECTL apply -f -
$KUBECTL create namespace monitoring --dry-run=client -o yaml | $KUBECTL apply -f -

$KUBECTL -n apps create secret generic postgresql \
  --from-literal=POSTGRES_USER="${APPS_POSTGRES_USER:-postgres}" \
  --from-literal=POSTGRES_PASSWORD="$APPS_POSTGRES_PASSWORD" \
  --from-literal=POSTGRES_DB="${APPS_POSTGRES_DB:-postgres}" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

VALKEY_CONF=$'requirepass '"$APPS_VALKEY_PASSWORD"$'\nappendonly yes'
$KUBECTL -n apps create secret generic valkey \
  --from-literal=valkey.conf="$VALKEY_CONF" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

$KUBECTL -n apps create secret generic pgadmin \
  --from-literal=PGADMIN_DEFAULT_EMAIL="$APPS_PGADMIN_EMAIL" \
  --from-literal=PGADMIN_DEFAULT_PASSWORD="$APPS_PGADMIN_PASSWORD" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

$KUBECTL -n apps-staging create secret generic postgresql \
  --from-literal=POSTGRES_USER="${STAGING_POSTGRES_USER:-postgres}" \
  --from-literal=POSTGRES_PASSWORD="$STAGING_POSTGRES_PASSWORD" \
  --from-literal=POSTGRES_DB="${STAGING_POSTGRES_DB:-postgres}" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

STAGING_VALKEY_CONF=$'requirepass '"$STAGING_VALKEY_PASSWORD"$'\nappendonly yes'
$KUBECTL -n apps-staging create secret generic valkey \
  --from-literal=valkey.conf="$STAGING_VALKEY_CONF" \
  --dry-run=client -o yaml | $KUBECTL apply -f -

if [[ -n "${LOKI_URL:-}" && -n "${LOKI_USERNAME:-}" && -n "${LOKI_PASSWORD:-}" ]]; then
  $KUBECTL -n monitoring create secret generic grafana-cloud-loki \
    --from-literal=LOKI_URL="$LOKI_URL" \
    --from-literal=LOKI_USERNAME="$LOKI_USERNAME" \
    --from-literal=LOKI_PASSWORD="$LOKI_PASSWORD" \
    --dry-run=client -o yaml | $KUBECTL apply -f -
  echo "Secret grafana-cloud-loki creato in monitoring."
else
  echo "Loki non configurato (LOKI_* vuoti): salto grafana-cloud-loki. Alloy resterà in CrashLoop finché non lo crei."
fi

echo "Secret datastore creati. Ora sync Argo CD (datastores-production / datastores-staging)."
