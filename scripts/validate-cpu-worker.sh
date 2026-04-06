#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
TARGET_NODE="polecat"
NAMESPACE="default"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-180s}"
POD_IMAGE="${POD_IMAGE:-busybox:1.36}"
POD_NAME=""
KEEP_POD="false"

log() {
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${SCRIPT_NAME}" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat <<USAGE
Usage: ${SCRIPT_NAME} [--node <name>] [--namespace <ns>] [--timeout <duration>] [--image <image>] [--keep-pod]

Validate a CPU worker canary path:
  1) node is Ready
  2) expected labels are present
  3) a pod pinned to the node runs to completion

Options:
  --node <name>        Target worker node (default: polecat)
  --namespace <ns>     Namespace for canary pod (default: default)
  --timeout <duration> Wait timeout for readiness and completion (default: 180s)
  --image <image>      Canary image (default: busybox:1.36)
  --keep-pod           Keep canary pod after success/failure (debug)
  -h, --help           Show this help text

Environment:
  KUBECONFIG           Defaults to /etc/rancher/k3s/k3s.yaml when unset

Examples:
  ./scripts/validate-cpu-worker.sh
  ./scripts/validate-cpu-worker.sh --node polecat --namespace ray --timeout 300s
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --node)
        [[ $# -ge 2 ]] || die "--node requires a value"
        TARGET_NODE="$2"
        shift 2
        ;;
      --namespace)
        [[ $# -ge 2 ]] || die "--namespace requires a value"
        NAMESPACE="$2"
        shift 2
        ;;
      --timeout)
        [[ $# -ge 2 ]] || die "--timeout requires a value"
        WAIT_TIMEOUT="$2"
        shift 2
        ;;
      --image)
        [[ $# -ge 2 ]] || die "--image requires a value"
        POD_IMAGE="$2"
        shift 2
        ;;
      --keep-pod)
        KEEP_POD="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "Unknown argument: $1"
        ;;
    esac
  done
}

k() {
  kubectl --kubeconfig "${KUBECONFIG_PATH}" "$@"
}

cleanup() {
  if [[ -n "${POD_NAME}" && "${KEEP_POD}" != "true" ]]; then
    k -n "${NAMESPACE}" delete pod "${POD_NAME}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
}

get_node_label() {
  local key="$1"
  k get node "${TARGET_NODE}" -o json | jq -r --arg key "${key}" '.metadata.labels[$key] // ""'
}

assert_node_label() {
  local key="$1"
  local expected="$2"
  local actual

  actual="$(get_node_label "${key}")"
  if [[ "${actual}" != "${expected}" ]]; then
    die "Node '${TARGET_NODE}' label '${key}' mismatch: expected='${expected}' actual='${actual:-<unset>}'"
  fi

  log "label check passed: ${key}=${expected}"
}

run_canary() {
  local scheduled_node
  local node_hostname_label

  POD_NAME="cpu-worker-canary-${TARGET_NODE}-$(date +%s)-${RANDOM}"
  node_hostname_label="$(get_node_label "kubernetes.io/hostname")"
  if [[ -z "${node_hostname_label}" ]]; then
    node_hostname_label="${TARGET_NODE}"
  fi

  cat <<EOF_POD | k apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: localk8s-cpu-canary
spec:
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: "${node_hostname_label}"
    localk8s.io/worker-class: "cpu"
    localk8s.io/ray-eligible: "true"
    localk8s.io/ollama-eligible: "false"
  containers:
  - name: canary
    image: ${POD_IMAGE}
    command: ["sh", "-c", "echo cpu-canary-ok on \$(hostname)"]
EOF_POD

  scheduled_node="$(k -n "${NAMESPACE}" get pod "${POD_NAME}" -o jsonpath='{.spec.nodeName}')"
  [[ "${scheduled_node}" == "${TARGET_NODE}" ]] || die "Canary pod scheduled to '${scheduled_node}', expected '${TARGET_NODE}'"

  if ! k -n "${NAMESPACE}" wait --for=jsonpath='{.status.phase}'=Succeeded "pod/${POD_NAME}" --timeout="${WAIT_TIMEOUT}"; then
    log "canary pod did not complete successfully"
    k -n "${NAMESPACE}" get pod "${POD_NAME}" -o wide || true
    k -n "${NAMESPACE}" describe pod "${POD_NAME}" || true
    k -n "${NAMESPACE}" logs "${POD_NAME}" || true
    die "CPU canary failed"
  fi

  k -n "${NAMESPACE}" logs "${POD_NAME}" || true
  log "canary pod completed on node '${TARGET_NODE}'"
}

main() {
  require_cmd kubectl
  require_cmd jq

  parse_args "$@"
  trap cleanup EXIT INT TERM

  log "validating CPU worker '${TARGET_NODE}' using kubeconfig '${KUBECONFIG_PATH}'"
  k get node "${TARGET_NODE}" >/dev/null
  k wait --for=condition=Ready "node/${TARGET_NODE}" --timeout="${WAIT_TIMEOUT}"

  assert_node_label "localk8s.io/worker-class" "cpu"
  assert_node_label "localk8s.io/ray-eligible" "true"
  assert_node_label "localk8s.io/ollama-eligible" "false"

  run_canary
  log "CPU worker validation passed"
}

main "$@"
