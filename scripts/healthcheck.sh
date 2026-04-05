#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_ENV_FILE="${PROJECT_ROOT}/config/local.env"

if [[ -f "${LOCAL_ENV_FILE}" ]]; then
  # shellcheck disable=SC1090
  source "${LOCAL_ENV_FILE}"
fi

KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
GATEWAY_HOST="${LOCAL_HOSTNAME:-$(hostname -s)}"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing required command: $1"
    exit 1
  }
}

check_gateway_routes() {
  curl -sS --fail "http://${GATEWAY_HOST}/ray" >/dev/null
  curl -sS --fail "http://${GATEWAY_HOST}/k3s/" >/dev/null
}

check_node_ready() {
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get nodes
  kubectl --kubeconfig "${KUBECONFIG_PATH}" wait --for=condition=Ready node --all --timeout=60s
}

check_gpu_allocatable() {
  local node_name
  node_name="$(kubectl --kubeconfig "${KUBECONFIG_PATH}" get nodes -o jsonpath='{.items[0].metadata.name}')"
  kubectl --kubeconfig "${KUBECONFIG_PATH}" describe node "${node_name}" | rg -n 'nvidia.com/gpu'
}

check_ray_pods() {
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get pods -n kuberay-system
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get raycluster -n ray
}

check_ollama() {
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get pv ollama-models-pv
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get pvc -n ollama
  kubectl --kubeconfig "${KUBECONFIG_PATH}" wait --for=jsonpath='{.status.phase}'=Bound pvc/ollama-models-hostdisk -n ollama --timeout=180s
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get deploy,svc,pods -n ollama
  kubectl --kubeconfig "${KUBECONFIG_PATH}" wait --for=condition=Available deployment/ollama -n ollama --timeout=180s
}

check_k3s_dashboard() {
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get pods -n k3s-dashboard
  kubectl --kubeconfig "${KUBECONFIG_PATH}" wait --for=condition=Available deployment/headlamp -n k3s-dashboard --timeout=180s
}

main() {
  require_cmd kubectl
  require_cmd rg
  require_cmd curl

  log "healthcheck starting"
  check_node_ready
  check_gpu_allocatable
  check_ray_pods
  check_ollama
  check_k3s_dashboard
  check_gateway_routes
  log "healthcheck completed"
}

main "$@"
