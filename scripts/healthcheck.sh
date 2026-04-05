#!/usr/bin/env bash
set -Eeuo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

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
  curl -sS --fail --header 'Host: laminarflow' http://127.0.0.1/ray >/dev/null
  curl -sS --fail --header 'Host: laminarflow' http://127.0.0.1/k3s/ >/dev/null
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
