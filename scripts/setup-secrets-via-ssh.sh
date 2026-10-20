#!/usr/bin/env bash
# Dal PC (senza kubectl locale): copia setup-secrets.env sulla VM ed esegue lo script lì.
# Uso: bash scripts/setup-secrets-via-ssh.sh [ubuntu@129.152.30.248]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="$ROOT/scripts/setup-secrets.env"
REMOTE="${1:-ubuntu@129.152.30.248}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"
SSH_OPTS=(-o BatchMode=yes)
[[ -f "$SSH_KEY" ]] && SSH_OPTS+=(-i "$SSH_KEY")

if [[ ! -f "$ENV_FILE" ]]; then
  echo "Manca $ENV_FILE" >&2
  exit 1
fi

scp "${SSH_OPTS[@]}" \
  "$ENV_FILE" \
  "$ROOT/scripts/setup-secrets.sh" \
  "$ROOT/scripts/lib/kube.sh" \
  "$REMOTE:/tmp/"

ssh "${SSH_OPTS[@]}" "$REMOTE" 'export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"; bash /tmp/setup-secrets.sh /tmp/setup-secrets.env; rm -f /tmp/setup-secrets.env'

echo "Fatto. Refresh + Sync datastores in Argo CD."
