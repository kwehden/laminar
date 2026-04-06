#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
VERSIONS_CONFIG_FILE="${PROJECT_ROOT}/config/versions.env"
LOCAL_ENV_FILE="${PROJECT_ROOT}/config/local.env"
KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
JOIN_READY_TIMEOUT_SECONDS="${JOIN_READY_TIMEOUT_SECONDS:-300}"

TARGET_HOST=""
K3S_SERVER_URL="${K3S_URL:-}"
K3S_SERVER_TOKEN="${K3S_JOIN_TOKEN:-${K3S_TOKEN:-}}"
INVENTORY_PATH="${PROJECT_ROOT}/packages/node-join/inventory.example.ini"
K3S_VERSION="${K3S_VERSION:-}"
GPU_MODE="skip"
NODE_PROFILE_OVERRIDE=""
NODE_PROFILE="cpu"
EXTRA_ANSIBLE_ARGS=()

log() {
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${SCRIPT_NAME}" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat <<USAGE
Usage: ${SCRIPT_NAME} --target <host> [--k3s-url <url>] [--inventory <path>] [--gpu] [-- <extra ansible args>]

Options:
  --target <host>      Inventory host to configure (required)
  --k3s-url <url>      k3s server URL (optional if K3S_URL env or inventory var localk8s_k3s_url is set)
  --inventory <path>   Ansible inventory path (default: packages/node-join/inventory.example.ini)
  --gpu                Backward-compatible shortcut: force gpu node profile and enable GPU runtime role
  -h, --help           Show this help text

Examples:
  ${SCRIPT_NAME} --target polecat --k3s-url https://<control-plane-hostname>:6443 --inventory ./packages/node-join/inventory.example.ini
  K3S_URL=https://<control-plane-hostname>:6443 K3S_JOIN_TOKEN='***' ${SCRIPT_NAME} --target standpunkt --gpu --inventory ./packages/node-join/inventory.example.ini
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target)
        [[ $# -ge 2 ]] || die "--target requires a value"
        TARGET_HOST="$2"
        shift 2
        ;;
      --k3s-url)
        [[ $# -ge 2 ]] || die "--k3s-url requires a value"
        K3S_SERVER_URL="$2"
        shift 2
        ;;
      --inventory)
        [[ $# -ge 2 ]] || die "--inventory requires a value"
        INVENTORY_PATH="$(make_absolute_path "$2")"
        shift 2
        ;;
      --gpu)
        GPU_MODE="enable"
        NODE_PROFILE_OVERRIDE="gpu"
        shift
        ;;
      --)
        shift
        EXTRA_ANSIBLE_ARGS=("$@")
        break
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

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

make_absolute_path() {
  local input_path="$1"
  if [[ "${input_path}" == /* ]]; then
    printf '%s\n' "${input_path}"
    return
  fi
  printf '%s/%s\n' "$(pwd)" "${input_path}"
}

load_versions() {
  local env_k3s_version="${K3S_VERSION:-}"
  [[ -f "${VERSIONS_CONFIG_FILE}" ]] || die "Missing versions config: ${VERSIONS_CONFIG_FILE}"

  # shellcheck disable=SC1090
  source "${VERSIONS_CONFIG_FILE}"
  if [[ -n "${env_k3s_version}" ]]; then
    K3S_VERSION="${env_k3s_version}"
  fi

  [[ -n "${K3S_VERSION:-}" ]] || die "K3S_VERSION is required (config/versions.env or env override)"
}

prompt_for_token_if_needed() {
  if [[ -n "${K3S_SERVER_TOKEN}" ]]; then
    return
  fi

  read -r -s -p "Enter k3s join token: " K3S_SERVER_TOKEN
  printf '\n'
  [[ -n "${K3S_SERVER_TOKEN}" ]] || die "k3s server token is required"
}

resolve_k3s_url_from_inventory() {
  local inventory_json
  local inventory_url=""
  inventory_json="$(ansible-inventory -i "${INVENTORY_PATH}" --list)"
  inventory_url="$(jq -r '.node_join_targets.vars.localk8s_k3s_url // empty' <<<"${inventory_json}")"
  if [[ -n "${inventory_url}" ]]; then
    printf '%s\n' "${inventory_url}"
    return
  fi

  if [[ -n "${TARGET_HOST}" ]]; then
    ansible-inventory -i "${INVENTORY_PATH}" --host "${TARGET_HOST}" 2>/dev/null \
      | jq -r '.localk8s_k3s_url // empty'
  fi
}

resolve_k3s_url_from_local_env() {
  local cp_endpoint=""
  if [[ -f "${LOCAL_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${LOCAL_ENV_FILE}"
    cp_endpoint="${LOCAL_CONTROL_PLANE_ENDPOINT:-}"
  fi
  if [[ -n "${cp_endpoint}" ]]; then
    printf 'https://%s:6443\n' "${cp_endpoint}"
  fi
}

resolve_node_profile() {
  local inventory_profile
  local inventory_gpu_enable
  local effective_profile

  inventory_profile="$(get_host_inventory_var localk8s_node_profile)"
  inventory_profile="$(trim_whitespace "${inventory_profile}")"
  inventory_gpu_enable="$(get_host_inventory_var localk8s_gpu_enable)"
  inventory_gpu_enable="${inventory_gpu_enable,,}"

  if [[ -z "${inventory_profile}" || "${inventory_profile}" == "null" ]]; then
    if [[ "${inventory_gpu_enable}" == "true" || "${inventory_gpu_enable}" == "1" || "${inventory_gpu_enable}" == "yes" ]]; then
      effective_profile="gpu"
    else
      effective_profile="cpu"
    fi
  else
    effective_profile="${inventory_profile,,}"
  fi

  if [[ -n "${NODE_PROFILE_OVERRIDE}" ]]; then
    effective_profile="${NODE_PROFILE_OVERRIDE}"
  fi

  case "${effective_profile}" in
    cpu|gpu) ;;
    *)
      die "Invalid localk8s_node_profile '${effective_profile}' for target '${TARGET_HOST}'. Allowed values: cpu, gpu."
      ;;
  esac

  printf '%s\n' "${effective_profile}"
}

is_reserved_profile_label() {
  local label="$1"
  [[ "${label}" =~ ^localk8s\.io/(worker-class|ray-eligible|ollama-eligible)= ]]
}

get_host_inventory_var() {
  local var_name="$1"
  ansible-inventory -i "${INVENTORY_PATH}" --host "${TARGET_HOST}" 2>/dev/null \
    | jq -r --arg key "${var_name}" '.[$key] // empty'
}

trim_whitespace() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "${value}"
}

assert_inventory_contract() {
  local inventory_json
  inventory_json="$(ansible-inventory -i "${INVENTORY_PATH}" --list)"

  jq -e '.node_join_targets' >/dev/null <<<"${inventory_json}" \
    || die "Inventory must define group: node_join_targets"

  jq -e --arg target "${TARGET_HOST}" '.node_join_targets.hosts // [] | index($target) != null' >/dev/null <<<"${inventory_json}" \
    || die "Target host '${TARGET_HOST}' not found under group node_join_targets in inventory ${INVENTORY_PATH}"
}

resolve_host_port_from_url() {
  local server_endpoint="$1"
  local server_host_out="$2"
  local server_port_out="$3"
  local parsed_host
  local parsed_port

  server_endpoint="${server_endpoint#*://}"
  server_endpoint="${server_endpoint%%/*}"

  if [[ "${server_endpoint}" =~ ^\[([0-9a-fA-F:]+)\](:([0-9]+))?$ ]]; then
    parsed_host="${BASH_REMATCH[1]}"
    parsed_port="${BASH_REMATCH[3]:-6443}"
  elif [[ "${server_endpoint}" == *:* ]]; then
    parsed_host="${server_endpoint%:*}"
    parsed_port="${server_endpoint##*:}"
  else
    parsed_host="${server_endpoint}"
    parsed_port="6443"
  fi

  if [[ "${parsed_host}" == *:* ]]; then
    die "IPv6 k3s API endpoints are not supported by this script preflight yet. Use an IPv4/hostname endpoint."
  fi

  printf -v "${server_host_out}" '%s' "${parsed_host}"
  printf -v "${server_port_out}" '%s' "${parsed_port}"
}

resolve_worker_host_address() {
  local host_value
  host_value="$(get_host_inventory_var ansible_host)"

  if [[ -z "${host_value}" || "${host_value}" == "null" ]]; then
    host_value="${TARGET_HOST}"
  fi

  printf '%s\n' "${host_value}"
}

run_remote_preflight() {
  local server_host="$1"
  local server_port="$2"
  local -a ansible_remote_cmd

  ansible_remote_cmd=(
    ansible
    -i "${INVENTORY_PATH}"
    "${TARGET_HOST}"
    -m shell
    -e "ansible_become=false"
    -a "timeout 3 bash -lc '>/dev/tcp/${server_host}/${server_port}'"
  )

  log "Checking worker->control-plane API reachability (${server_host}:${server_port})"
  "${ansible_remote_cmd[@]}" >/dev/null \
    || die "Remote preflight failed: worker cannot reach ${server_host}:${server_port}"

  log "Checking worker->control-plane VXLAN path (${server_host}:8472 udp best-effort)"
  if ! ansible -i "${INVENTORY_PATH}" "${TARGET_HOST}" -m shell \
    -e "ansible_become=false" \
    -a "timeout 3 bash -lc 'echo >/dev/udp/${server_host}/8472'" >/dev/null; then
    log "WARN: VXLAN UDP/8472 probe failed (best-effort check). Continuing; verify CNI path if join fails."
  fi
}

preflight() {
  local server_host
  local server_port

  require_cmd ansible
  require_cmd ansible-playbook
  require_cmd ansible-inventory
  require_cmd bash
  require_cmd jq
  require_cmd kubectl
  require_cmd timeout
  load_versions

  [[ -n "${TARGET_HOST}" ]] || die "--target is required"
  [[ -d "${ANSIBLE_DIR}" ]] || die "Ansible directory not found: ${ANSIBLE_DIR}"
  [[ -f "${INVENTORY_PATH}" ]] || die "Inventory not found: ${INVENTORY_PATH}"
  assert_inventory_contract
  NODE_PROFILE="$(resolve_node_profile)"
  if [[ "${GPU_MODE}" == "skip" && "${NODE_PROFILE}" == "gpu" ]]; then
    GPU_MODE="enable"
  fi
  if [[ -z "${K3S_SERVER_URL}" ]]; then
    K3S_SERVER_URL="$(resolve_k3s_url_from_inventory)"
  fi
  if [[ -z "${K3S_SERVER_URL}" ]]; then
    K3S_SERVER_URL="$(resolve_k3s_url_from_local_env)"
  fi
  [[ -n "${K3S_SERVER_URL}" ]] || die "k3s server URL is required (--k3s-url, K3S_URL, or inventory var localk8s_k3s_url)"
  prompt_for_token_if_needed

  resolve_host_port_from_url "${K3S_SERVER_URL}" server_host server_port

  timeout 3 bash -c ">/dev/tcp/${server_host}/${server_port}" \
    || die "Cannot reach k3s API endpoint ${server_host}:${server_port}"

  run_remote_preflight "${server_host}" "${server_port}"
}

run_join() {
  local -a ansible_cmd

  ansible_cmd=(
    ansible-playbook
    -i "${INVENTORY_PATH}"
    site.yml
    --limit "${TARGET_HOST}"
    --tags "k3s_agent,node_gpu_runtime"
    -e "node_join_target=${TARGET_HOST}"
    -e "k3s_agent_join_mode=join"
    -e "localk8s_node_profile=${NODE_PROFILE}"
    -e "node_gpu_runtime_mode=${GPU_MODE}"
  )

  if [[ ${#EXTRA_ANSIBLE_ARGS[@]} -gt 0 ]]; then
    ansible_cmd+=("${EXTRA_ANSIBLE_ARGS[@]}")
  fi

  log "Running node join for target ${TARGET_HOST} (node_profile=${NODE_PROFILE}, gpu_mode=${GPU_MODE})"
  (
    export K3S_VERSION
    export K3S_SERVER_URL
    export K3S_SERVER_TOKEN
    export NODE_JOIN_TARGET="${TARGET_HOST}"
    export NODE_GPU_RUNTIME_MODE="${GPU_MODE}"
    export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
    cd "${ANSIBLE_DIR}"
    "${ansible_cmd[@]}"
  )
}

resolve_node_name() {
  local inventory_node_name
  local discovered_node_name

  inventory_node_name="$(get_host_inventory_var localk8s_node_name)"
  if [[ -n "${inventory_node_name}" ]]; then
    printf '%s\n' "${inventory_node_name}"
    return
  fi

  discovered_node_name="$(
    ansible -i "${INVENTORY_PATH}" "${TARGET_HOST}" -m shell -e "ansible_become=false" -a "hostname -s" -o 2>/dev/null \
      | sed -E 's/^.*>>[[:space:]]*//'
  )"
  discovered_node_name="$(trim_whitespace "${discovered_node_name}")"
  [[ -n "${discovered_node_name}" ]] || die "Unable to resolve Kubernetes node name from target host ${TARGET_HOST}"
  printf '%s\n' "${discovered_node_name}"
}

wait_for_node_ready() {
  local node_name="$1"
  local waited=0

  log "Waiting for node registration: ${node_name}"
  until kubectl --kubeconfig "${KUBECONFIG_PATH}" get node "${node_name}" >/dev/null 2>&1; do
    sleep 5
    waited=$((waited + 5))
    if [[ "${waited}" -ge "${JOIN_READY_TIMEOUT_SECONDS}" ]]; then
      die "Timed out waiting for node registration: ${node_name}"
    fi
  done

  log "Waiting for node Ready condition: ${node_name}"
  kubectl --kubeconfig "${KUBECONFIG_PATH}" wait \
    --for=condition=Ready "node/${node_name}" \
    --timeout="${JOIN_READY_TIMEOUT_SECONDS}s" >/dev/null \
    || die "Timed out waiting for node Ready condition: ${node_name}"
}

apply_node_labels_and_taints() {
  local node_name="$1"
  local labels_raw taints_raw
  local label taint
  local -a labels taints

  labels_raw="$(get_host_inventory_var localk8s_node_labels)"
  taints_raw="$(get_host_inventory_var localk8s_node_taints)"

  if [[ -n "${labels_raw}" ]]; then
    IFS=',' read -r -a labels <<<"${labels_raw}"
    for label in "${labels[@]}"; do
      label="$(trim_whitespace "${label}")"
      [[ -n "${label}" ]] || continue
      if is_reserved_profile_label "${label}"; then
        die "Custom label '${label}' attempts to override reserved profile-managed labels. Use localk8s_node_profile instead."
      fi
      log "Applying node label ${label} on ${node_name}"
      kubectl --kubeconfig "${KUBECONFIG_PATH}" label node "${node_name}" "${label}" --overwrite >/dev/null
    done
  fi

  if [[ -n "${taints_raw}" ]]; then
    IFS=',' read -r -a taints <<<"${taints_raw}"
    for taint in "${taints[@]}"; do
      taint="$(trim_whitespace "${taint}")"
      [[ -n "${taint}" ]] || continue
      log "Applying node taint ${taint} on ${node_name}"
      kubectl --kubeconfig "${KUBECONFIG_PATH}" taint node "${node_name}" "${taint}" --overwrite >/dev/null
    done
  fi
}

post_join_network_check() {
  local worker_addr
  worker_addr="$(resolve_worker_host_address)"

  log "Checking control-plane->worker kubelet path (${worker_addr}:10250)"
  timeout 3 bash -c ">/dev/tcp/${worker_addr}/10250" \
    || die "Post-join network check failed: cannot reach worker kubelet at ${worker_addr}:10250"
}

main() {
  local node_name

  parse_args "$@"
  preflight
  run_join
  node_name="$(resolve_node_name)"
  wait_for_node_ready "${node_name}"
  apply_node_labels_and_taints "${node_name}"
  post_join_network_check
  log "Join workflow completed"
}

main "$@"
