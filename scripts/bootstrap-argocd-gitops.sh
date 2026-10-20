#!/usr/bin/env bash
# Registra il repo GitOps in Argo CD (secret SSH) e crea l'Application root oci-gitops.
# Dopo ogni reinstall di k3s/Argo CD sulla VM — la deploy key su GitHub può restare la stessa.
#
# Uso (sul PC, con SSH alla VM):
#   bash scripts/bootstrap-argocd-gitops.sh
#   GITOPS_SSH_KEY=~/.ssh/oci-gitops-argocd bash scripts/bootstrap-argocd-gitops-via-ssh.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/lib/kube.sh" ]]; then
  # Esecuzione dal clone (scripts/bootstrap-argocd-gitops.sh)
  # shellcheck source=lib/kube.sh
  source "$SCRIPT_DIR/lib/kube.sh"
  BOOTSTRAP_APP_YAML="$SCRIPT_DIR/bootstrap-argocd-root.yaml"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
elif [[ -f "$SCRIPT_DIR/kube.sh" ]]; then
  # Copia in /tmp sulla VM (via SSH)
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/kube.sh"
  BOOTSTRAP_APP_YAML="$SCRIPT_DIR/bootstrap-argocd-root.yaml"
  REPO_ROOT="$SCRIPT_DIR"
else
  echo "Manca scripts/lib/kube.sh (o /tmp/kube.sh sulla VM)." >&2
  exit 1
fi

GITOPS_REPO_URL="${GITOPS_REPO_URL:-git@github.com:cmontisci/oci-gitops.git}"
GITOPS_SSH_KEY="${GITOPS_SSH_KEY:-$HOME/.ssh/oci-gitops-argocd}"
REMOTE="${GITOPS_REMOTE:-ubuntu@129.152.30.248}"
SSH_KEY="${SSH_KEY:-$HOME/.ssh/id_ed25519}"

usage() {
  echo "Usage: bash scripts/bootstrap-argocd-gitops.sh [--via-ssh]" >&2
  echo "  GITOPS_SSH_KEY  default: ~/.ssh/oci-gitops-argocd" >&2
  echo "  GITOPS_REPO_URL default: git@github.com:cmontisci/oci-gitops.git" >&2
}

run_on_cluster() {
  if ! kube_init; then
    return 127
  fi

  if [[ ! -f "$GITOPS_SSH_KEY" ]]; then
    echo "Manca chiave privata: $GITOPS_SSH_KEY" >&2
    echo "Genera con: bash scripts/generate-argocd-deploy-key.sh" >&2
    return 1
  fi

  $KUBECTL get ns argocd >/dev/null 2>&1 || {
    echo "Namespace argocd assente. Esegui prima ansible-playbook playbooks/lab.yml" >&2
    return 1
  }

  $KUBECTL -n argocd create secret generic repo-oci-gitops \
    --from-literal=type=git \
    --from-literal=url="$GITOPS_REPO_URL" \
    --from-file=sshPrivateKey="$GITOPS_SSH_KEY" \
    --dry-run=client -o yaml | \
    $KUBECTL label --local -f - argocd.argoproj.io/secret-type=repository -o yaml | \
    $KUBECTL apply -f -

  $KUBECTL apply -f "$BOOTSTRAP_APP_YAML"

  echo ""
  echo "Repo + Application oci-gitops applicati."
  echo "Argo CD UI → Applications → sync oci-gitops se non parte da solo."
  echo "Poi: bash scripts/setup-secrets-via-ssh.sh"
}

via_ssh() {
  local ssh_opts=(-o BatchMode=yes)
  [[ -f "$SSH_KEY" ]] && ssh_opts+=(-i "$SSH_KEY")

  if [[ ! -f "$GITOPS_SSH_KEY" ]]; then
    echo "Manca chiave privata: $GITOPS_SSH_KEY" >&2
    exit 1
  fi

  scp "${ssh_opts[@]}" \
    "$REPO_ROOT/scripts/lib/kube.sh" \
    "$REPO_ROOT/scripts/bootstrap-argocd-gitops.sh" \
    "$REPO_ROOT/scripts/bootstrap-argocd-root.yaml" \
    "$GITOPS_SSH_KEY" \
    "$REMOTE:/tmp/"

  ssh "${ssh_opts[@]}" "$REMOTE" bash <<REMOTE
set -euo pipefail
export PATH="/usr/local/bin:/usr/bin:/bin:\$PATH"
export GITOPS_SSH_KEY=/tmp/$(basename "$GITOPS_SSH_KEY")
export GITOPS_REPO_URL="$GITOPS_REPO_URL"
chmod 600 "\$GITOPS_SSH_KEY"
bash /tmp/bootstrap-argocd-gitops.sh __local__
rm -f "\$GITOPS_SSH_KEY"
REMOTE
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  usage
  exit 0
fi

if [[ "${1:-}" == "__local__" ]]; then
  run_on_cluster
  exit 0
fi

if kube_init 2>/dev/null; then
  run_on_cluster
else
  via_ssh
fi
