#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
TARGET_NODE="standpunkt"
NAMESPACE="ray"
WAIT_TIMEOUT="${WAIT_TIMEOUT:-300s}"
POD_IMAGE="${POD_IMAGE:-nvidia/cuda:12.5.0-base-ubuntu22.04}"
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

Validate a GPU worker path:
  1) node exists and is Ready
  2) expected GPU profile labels are present
  3) an ephemeral CUDA pod scheduled to the node can run nvidia-smi

Options:
  --node <name>        Target GPU worker node (default: standpunkt)
  --namespace <ns>      Namespace for the validation pod (default: ray)
  --timeout <duration>  Wait timeout for node readiness and pod completion (default: 300s)
  --image <image>      CUDA validation image (default: nvidia/cuda:12.5.0-base-ubuntu22.04)
  --keep-pod           Keep the validation pod after success/failure for debugging
  -h, --help           Show this help text

Environment:
  KUBECONFIG           Defaults to /etc/rancher/k3s/k3s.yaml when unset

Examples:
  ./scripts/validate-gpu-worker.sh
  ./scripts/validate-gpu-worker.sh --node standpunkt --namespace ray --timeout 300s
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

duration_to_seconds() {
  local duration="$1"
  local value unit

  if [[ "${duration}" =~ ^([0-9]+)([smh]?)$ ]]; then
    value="${BASH_REMATCH[1]}"
    unit="${BASH_REMATCH[2]}"
    case "${unit}" in
      ""|s) printf '%s\n' "${value}" ;;
      m) printf '%s\n' "$((value * 60))" ;;
      h) printf '%s\n' "$((value * 3600))" ;;
      *)
        die "Unsupported timeout suffix in '${duration}'"
        ;;
    esac
    return
  fi

  die "Invalid timeout duration '${duration}'. Use values like 300s, 5m, or 1h."
}

cleanup() {
  if [[ -n "${POD_NAME}" && "${KEEP_POD}" != "true" ]]; then
    k -n "${NAMESPACE}" delete pod "${POD_NAME}" --ignore-not-found --wait=false >/dev/null 2>&1 || true
  fi
}

collect_diagnostics() {
  if [[ -z "${POD_NAME}" ]]; then
    return
  fi

  log "collecting diagnostics for ${POD_NAME}"
  k -n "${NAMESPACE}" get pod "${POD_NAME}" -o wide || true
  k -n "${NAMESPACE}" describe pod "${POD_NAME}" || true
  k -n "${NAMESPACE}" logs "${POD_NAME}" --all-containers=true || true
}

on_exit() {
  local status="$?"

  if [[ "${status}" -ne 0 ]]; then
    collect_diagnostics
  fi

  cleanup
}

assert_node_label() {
  local key="$1"
  local expected="$2"
  local actual

  actual="$(
    k get node "${TARGET_NODE}" -o json \
      | jq -r --arg key "${key}" '.metadata.labels[$key] // ""'
  )"

  if [[ "${actual}" != "${expected}" ]]; then
    die "Node '${TARGET_NODE}' label '${key}' mismatch: expected='${expected}' actual='${actual:-<unset>}'"
  fi

  log "label check passed: ${key}=${expected}"
}

wait_for_node_ready() {
  log "waiting for node Ready: ${TARGET_NODE}"
  if ! k wait --for=condition=Ready "node/${TARGET_NODE}" --timeout="${WAIT_TIMEOUT}" >/dev/null; then
    die "Timed out waiting for node '${TARGET_NODE}' to become Ready"
  fi
}

run_gpu_canary() {
  local pod_yaml
  local pod_phase
  local pod_node_name
  local wait_seconds
  local deadline_seconds

  k get namespace "${NAMESPACE}" >/dev/null \
    || die "Namespace '${NAMESPACE}' does not exist"

  POD_NAME="gpu-worker-canary-${TARGET_NODE}-$(date +%s)-${RANDOM}"
  wait_seconds="$(duration_to_seconds "${WAIT_TIMEOUT}")"
  deadline_seconds=$((SECONDS + wait_seconds))

  pod_yaml="$(
    cat <<EOF_POD
apiVersion: v1
kind: Pod
metadata:
  name: ${POD_NAME}
  namespace: ${NAMESPACE}
  labels:
    app.kubernetes.io/name: localk8s-gpu-canary
spec:
  restartPolicy: Never
  nodeSelector:
    kubernetes.io/hostname: "${TARGET_NODE}"
  containers:
  - name: cuda
    image: ${POD_IMAGE}
    imagePullPolicy: IfNotPresent
    command:
    - /bin/bash
    - -lc
    - nvidia-smi
    resources:
      requests:
        cpu: 100m
        memory: 128Mi
        nvidia.com/gpu: 1
      limits:
        cpu: 100m
        memory: 128Mi
        nvidia.com/gpu: 1
EOF_POD
  )"

  log "creating GPU canary pod ${POD_NAME} in namespace ${NAMESPACE}"
  printf '%s\n' "${pod_yaml}" | k apply -f - >/dev/null

  log "waiting for GPU canary completion on ${TARGET_NODE}"
  while true; do
    pod_phase="$(k -n "${NAMESPACE}" get pod "${POD_NAME}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    pod_node_name="$(k -n "${NAMESPACE}" get pod "${POD_NAME}" -o jsonpath='{.spec.nodeName}' 2>/dev/null || true)"

    if [[ -n "${pod_node_name}" && "${pod_node_name}" != "${TARGET_NODE}" ]]; then
      die "GPU canary pod scheduled to '${pod_node_name}', expected '${TARGET_NODE}'"
    fi

    case "${pod_phase}" in
      Succeeded)
        break
        ;;
      Failed)
        die "GPU canary pod entered Failed phase"
        ;;
    esac

    if (( SECONDS >= deadline_seconds )); then
      die "Timed out waiting for GPU canary pod '${POD_NAME}' to complete"
    fi

    sleep 2
  done

  k -n "${NAMESPACE}" logs "${POD_NAME}" --all-containers=true
  log "GPU canary pod completed on node '${TARGET_NODE}'"
}

main() {
  require_cmd kubectl
  require_cmd jq

  parse_args "$@"
  trap on_exit EXIT INT TERM

  log "validating GPU worker '${TARGET_NODE}' using kubeconfig '${KUBECONFIG_PATH}'"
  k get node "${TARGET_NODE}" >/dev/null || die "Node not found: ${TARGET_NODE}"
  wait_for_node_ready

  assert_node_label "localk8s.io/worker-class" "gpu"
  assert_node_label "localk8s.io/ray-eligible" "true"
  assert_node_label "localk8s.io/ollama-eligible" "true"

  run_gpu_canary
  log "GPU worker validation passed"
}

main "$@"
