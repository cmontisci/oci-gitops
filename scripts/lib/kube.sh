# shellcheck shell=bash
# Inizializza KUBECTL e KUBECONFIG (k3s / kubectl). Source: . scripts/lib/kube.sh && kube_init
kube_init() {
  export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

  KUBECTL=""
  if command -v kubectl >/dev/null 2>&1; then
    KUBECTL=kubectl
  elif command -v k3s >/dev/null 2>&1; then
    KUBECTL="k3s kubectl"
  elif [[ -x /usr/local/bin/k3s ]]; then
    KUBECTL="/usr/local/bin/k3s kubectl"
  elif [[ -x /usr/local/bin/kubectl ]]; then
    KUBECTL=/usr/local/bin/kubectl
  fi

  if [[ -z "$KUBECTL" ]]; then
    echo "kubectl/k3s non trovato (PATH=$PATH)." >&2
    return 127
  fi

  if [[ -f "${KUBECONFIG:-}" ]]; then
    :
  elif [[ -f "$HOME/.kube/config" ]]; then
    export KUBECONFIG="$HOME/.kube/config"
  elif [[ -f /etc/rancher/k3s/k3s.yaml ]]; then
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  fi

  if ! $KUBECTL get ns default >/dev/null 2>&1; then
    if [[ -x /usr/local/bin/k3s ]] && sudo -n /usr/local/bin/k3s kubectl get ns default >/dev/null 2>&1; then
      KUBECTL="sudo -n /usr/local/bin/k3s kubectl"
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    elif sudo -n k3s kubectl get ns default >/dev/null 2>&1; then
      KUBECTL="sudo -n k3s kubectl"
      export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    else
      echo "Impossibile usare il cluster (KUBECONFIG=${KUBECONFIG:-unset})." >&2
      return 1
    fi
  fi
  return 0
}
