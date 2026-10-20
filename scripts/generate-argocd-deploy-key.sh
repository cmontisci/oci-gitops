#!/usr/bin/env bash
# Genera una deploy key per Argo CD → GitHub (read-only).
set -euo pipefail

OUT_DIR="${1:-$HOME/.ssh}"
KEY="$OUT_DIR/oci-gitops-argocd"

mkdir -p "$OUT_DIR"
chmod 700 "$OUT_DIR"

if [[ -f "$KEY" ]]; then
  echo "Esiste già $KEY — non sovrascrivo." >&2
  exit 1
fi

ssh-keygen -t ed25519 -f "$KEY" -N "" -C "argocd-oci-gitops"
chmod 600 "$KEY"

echo ""
echo "1) GitHub → cmontisci/oci-gitops → Settings → Deploy keys → Add deploy key"
echo "   Title: argocd"
echo "   Key (pubblica):"
echo "---"
cat "${KEY}.pub"
echo "---"
echo "   Allow write access: NO"
echo ""
echo "2) Argo CD → Settings → Repositories → Connect repo"
echo "   Via SSH, URL: git@github.com:cmontisci/oci-gitops.git"
echo "   Private key: contenuto di $KEY"
echo ""
