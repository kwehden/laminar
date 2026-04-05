#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"

TARGET_HOST=""
K3S_SERVER_URL="${K3S_URL:-}"
K3S_SERVER_TOKEN="${K3S_JOIN_TOKEN:-${K3S_TOKEN:-}}"
INVENTORY_PATH="${PROJECT_ROOT}/ansible/inventory/localhost.yml"
GPU_MODE="skip"
EXTRA_ANSIBLE_ARGS=()
SUDO_WRAPPER=()

log() {
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${SCRIPT_NAME}" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat <<USAGE
Usage: ${SCRIPT_NAME} --target <host> --k3s-url <url> [--k3s-token <token>] [--inventory <path>] [--gpu] [-- <extra ansible args>]

Options:
  --target <host>      Inventory host to configure (required)
  --k3s-url <url>      k3s server URL (required; may use K3S_URL env)
  --k3s-token <token>  k3s server token (optional if K3S_JOIN_TOKEN/K3S_TOKEN is set; prompt fallback is available)
  --inventory <path>   Ansible inventory path (default: ansible/inventory/localhost.yml)
  --gpu                Enable node GPU runtime role for target host
  -h, --help           Show this help text

Examples:
  ${SCRIPT_NAME} --target worker-a --k3s-url https://laminarflow:6443 --inventory ./packages/node-join/inventory.example.ini
  K3S_URL=https://laminarflow:6443 K3S_JOIN_TOKEN='***' ${SCRIPT_NAME} --target worker-a --gpu --inventory ./packages/node-join/inventory.example.ini
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
      --k3s-token)
        [[ $# -ge 2 ]] || die "--k3s-token requires a value"
        K3S_SERVER_TOKEN="$2"
        shift 2
        ;;
      --inventory)
        [[ $# -ge 2 ]] || die "--inventory requires a value"
        INVENTORY_PATH="$2"
        shift 2
        ;;
      --gpu)
        GPU_MODE="enable"
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

prompt_for_token_if_needed() {
  if [[ -n "${K3S_SERVER_TOKEN}" ]]; then
    return
  fi

  read -r -s -p "Enter k3s join token: " K3S_SERVER_TOKEN
  printf '\n'
  [[ -n "${K3S_SERVER_TOKEN}" ]] || die "k3s server token is required"
}

resolve_host_port_from_url() {
  local server_endpoint="$1"
  local server_host_out="$2"
  local server_port_out="$3"
  local server_host
  local server_port

  server_endpoint="${server_endpoint#*://}"
  server_endpoint="${server_endpoint%%/*}"
  server_host="${server_endpoint%:*}"
  server_port="${server_endpoint##*:}"
  if [[ "${server_host}" == "${server_port}" ]]; then
    server_port="6443"
  fi

  printf -v "${server_host_out}" '%s' "${server_host}"
  printf -v "${server_port_out}" '%s' "${server_port}"
}

resolve_worker_host_address() {
  local host_value
  host_value="$(
    ansible-inventory -i "${INVENTORY_PATH}" --host "${TARGET_HOST}" 2>/dev/null \
      | jq -r '.ansible_host // empty'
  )"

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
    -a "timeout 3 bash -lc '>/dev/tcp/${server_host}/${server_port}'"
  )

  log "Checking worker->control-plane API reachability (${server_host}:${server_port})"
  "${ansible_remote_cmd[@]}" >/dev/null \
    || die "Remote preflight failed: worker cannot reach ${server_host}:${server_port}"

  log "Checking worker->control-plane VXLAN path (${server_host}:8472 udp best-effort)"
  ansible -i "${INVENTORY_PATH}" "${TARGET_HOST}" -m shell \
    -a "timeout 3 bash -lc 'echo >/dev/udp/${server_host}/8472'" >/dev/null \
    || die "Remote preflight failed: worker cannot reach ${server_host}:8472/udp"
}

preflight() {
  local server_host
  local server_port

  prompt_for_token_if_needed

  require_cmd ansible
  require_cmd ansible-playbook
  require_cmd ansible-inventory
  require_cmd bash
  require_cmd jq
  require_cmd timeout

  [[ -n "${TARGET_HOST}" ]] || die "--target is required"
  [[ -n "${K3S_SERVER_URL}" ]] || die "k3s server URL is required (--k3s-url or K3S_URL)"
  [[ -d "${ANSIBLE_DIR}" ]] || die "Ansible directory not found: ${ANSIBLE_DIR}"
  [[ -f "${INVENTORY_PATH}" ]] || die "Inventory not found: ${INVENTORY_PATH}"

  resolve_host_port_from_url "${K3S_SERVER_URL}" server_host server_port

  timeout 3 bash -c ">/dev/tcp/${server_host}/${server_port}" \
    || die "Cannot reach k3s API endpoint ${server_host}:${server_port}"

  run_remote_preflight "${server_host}" "${server_port}"

  if [[ ${EUID} -eq 0 ]]; then
    SUDO_WRAPPER=()
  else
    require_cmd sudo
    SUDO_WRAPPER=(sudo --preserve-env=K3S_SERVER_URL,K3S_SERVER_TOKEN,NODE_JOIN_TARGET,NODE_GPU_RUNTIME_MODE,ANSIBLE_CONFIG)
  fi
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
    -e "node_gpu_runtime_mode=${GPU_MODE}"
  )

  if [[ ${#EXTRA_ANSIBLE_ARGS[@]} -gt 0 ]]; then
    ansible_cmd+=("${EXTRA_ANSIBLE_ARGS[@]}")
  fi

  log "Running node join for target ${TARGET_HOST} (gpu_mode=${GPU_MODE})"
  (
    export K3S_SERVER_URL
    export K3S_SERVER_TOKEN
    export NODE_JOIN_TARGET="${TARGET_HOST}"
    export NODE_GPU_RUNTIME_MODE="${GPU_MODE}"
    export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
    cd "${ANSIBLE_DIR}"
    if [[ ${#SUDO_WRAPPER[@]} -gt 0 ]]; then
      "${SUDO_WRAPPER[@]}" "${ansible_cmd[@]}"
    else
      "${ansible_cmd[@]}"
    fi
  )
}

post_join_network_check() {
  local worker_addr
  worker_addr="$(resolve_worker_host_address)"

  log "Checking control-plane->worker kubelet path (${worker_addr}:10250)"
  timeout 3 bash -c ">/dev/tcp/${worker_addr}/10250" \
    || die "Post-join network check failed: cannot reach worker kubelet at ${worker_addr}:10250"
}

main() {
  parse_args "$@"
  preflight
  run_join
  post_join_network_check
  log "Join workflow completed"
}

main "$@"
