#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
SELECTOR="app.kubernetes.io/managed-by=localk8s-bootstrap"
SNAP_DIR="${PROJECT_ROOT}/.tmp-idempotency"

log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    log "missing required command: $1"
    exit 1
  }
}

snapshot_managed_state() {
  local output_file="$1"
  kubectl --kubeconfig "${KUBECONFIG_PATH}" get all,rayclusters,limitranges,resourcequotas -A -l "${SELECTOR}" -o yaml >"${output_file}"
}

main() {
  require_cmd kubectl
  require_cmd diff

  mkdir -p "${SNAP_DIR}"

  log "run 1: bootstrap"
  "${PROJECT_ROOT}/scripts/bootstrap.sh"
  snapshot_managed_state "${SNAP_DIR}/state-run1.yaml"

  log "run 2: bootstrap"
  "${PROJECT_ROOT}/scripts/bootstrap.sh"
  snapshot_managed_state "${SNAP_DIR}/state-run2.yaml"

  log "compare managed state snapshots"
  if diff -u "${SNAP_DIR}/state-run1.yaml" "${SNAP_DIR}/state-run2.yaml" >/dev/null; then
    log "idempotency check passed (managed state converged)"
  else
    log "idempotency check failed: managed state changed across reruns"
    diff -u "${SNAP_DIR}/state-run1.yaml" "${SNAP_DIR}/state-run2.yaml" || true
    exit 1
  fi
}

main "$@"
