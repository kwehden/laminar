#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
LOCAL_ENV_FILE="${PROJECT_ROOT}/config/local.env"

TARGET_NAME="${TARGET_NAME:-}"
TARGET_HOST="${TARGET_HOST:-}"
TARGET_USER="${TARGET_USER:-${USER}}"
KEY_PATH="${KEY_PATH:-}"
NODE_PROFILE="${NODE_PROFILE:-cpu}"
DO_COPY_ID="true"
DO_CONNECT_TEST="true"

log() {
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${SCRIPT_NAME}" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat <<'USAGE'
Usage: scripts/setup-node-ssh.sh [options]

Interactive SSH bootstrap helper for node-join targets.

Options:
  --target-name <name>   Inventory host alias (for example: polecat)
  --target-host <host>   SSH endpoint (DNS or IP)
  --target-user <user>   SSH user on remote host (default: current user)
  --key-path <path>      Private key path (default: ~/.ssh/<target-name>_ed25519)
  --node-profile <type>  cpu or gpu (default: cpu)
  --no-copy-id           Skip ssh-copy-id step
  --no-test              Skip SSH connectivity test
  -h, --help             Show this help text
USAGE
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing command: $1"
}

confirm() {
  local prompt="$1"
  local default="${2:-y}"
  local reply=""

  if [[ ! -t 0 ]]; then
    [[ "${default}" == "y" ]]
    return
  fi

  read -r -p "${prompt} " reply
  reply="${reply,,}"

  if [[ -z "${reply}" ]]; then
    reply="${default}"
  fi

  [[ "${reply}" == "y" || "${reply}" == "yes" ]]
}

prompt_if_empty() {
  local var_name="$1"
  local prompt="$2"
  local current_value="$3"
  local reply=""

  if [[ -n "${current_value}" ]]; then
    printf -v "${var_name}" '%s' "${current_value}"
    return
  fi

  [[ -t 0 ]] || die "${var_name} is required in non-interactive mode"

  while [[ -z "${reply}" ]]; do
    read -r -p "${prompt}: " reply
  done
  printf -v "${var_name}" '%s' "${reply}"
}

expand_home_path() {
  local path_value="$1"
  if [[ "${path_value}" == "~/"* ]]; then
    printf '%s/%s\n' "${HOME}" "${path_value#~/}"
    return
  fi
  printf '%s\n' "${path_value}"
}

load_local_env() {
  if [[ -f "${LOCAL_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${LOCAL_ENV_FILE}"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --target-name)
        [[ $# -ge 2 ]] || die "--target-name requires a value"
        TARGET_NAME="$2"
        shift 2
        ;;
      --target-host)
        [[ $# -ge 2 ]] || die "--target-host requires a value"
        TARGET_HOST="$2"
        shift 2
        ;;
      --target-user)
        [[ $# -ge 2 ]] || die "--target-user requires a value"
        TARGET_USER="$2"
        shift 2
        ;;
      --key-path)
        [[ $# -ge 2 ]] || die "--key-path requires a value"
        KEY_PATH="$2"
        shift 2
        ;;
      --node-profile)
        [[ $# -ge 2 ]] || die "--node-profile requires a value"
        NODE_PROFILE="${2,,}"
        shift 2
        ;;
      --no-copy-id)
        DO_COPY_ID="false"
        shift
        ;;
      --no-test)
        DO_CONNECT_TEST="false"
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

validate_inputs() {
  case "${NODE_PROFILE}" in
    cpu|gpu) ;;
    *) die "--node-profile must be 'cpu' or 'gpu'" ;;
  esac

  prompt_if_empty TARGET_NAME "Inventory target name (example: polecat)" "${TARGET_NAME}"
  prompt_if_empty TARGET_HOST "Worker SSH endpoint (${LOCAL_ADDRESS_MODE:-dns})" "${TARGET_HOST}"

  if [[ -z "${KEY_PATH}" ]]; then
    KEY_PATH="${HOME}/.ssh/${TARGET_NAME}_ed25519"
  fi
  KEY_PATH="$(expand_home_path "${KEY_PATH}")"
}

ensure_ssh_key() {
  local key_comment="laminar->${TARGET_NAME}"
  mkdir -p "$(dirname "${KEY_PATH}")"

  if [[ -f "${KEY_PATH}" ]]; then
    log "key exists: ${KEY_PATH}"
    return
  fi

  log "generating SSH key: ${KEY_PATH}"
  ssh-keygen -t ed25519 -f "${KEY_PATH}" -C "${key_comment}"
}

run_copy_id() {
  if [[ "${DO_COPY_ID}" != "true" ]]; then
    log "skipping ssh-copy-id"
    return
  fi

  if confirm "Run ssh-copy-id for ${TARGET_USER}@${TARGET_HOST}? [Y/n]" "y"; then
    ssh-copy-id -i "${KEY_PATH}.pub" "${TARGET_USER}@${TARGET_HOST}"
  else
    log "skipping ssh-copy-id by user choice"
  fi
}

run_connect_test() {
  if [[ "${DO_CONNECT_TEST}" != "true" ]]; then
    log "skipping SSH connectivity test"
    return
  fi

  if confirm "Run SSH connectivity test now? [Y/n]" "y"; then
    ssh -i "${KEY_PATH}" -o BatchMode=yes -o ConnectTimeout=5 "${TARGET_USER}@${TARGET_HOST}" "hostname -s"
    log "SSH test succeeded"
  else
    log "skipping connectivity test by user choice"
  fi
}

print_inventory_snippet() {
  local cp_endpoint="${LOCAL_CONTROL_PLANE_ENDPOINT:-<control-plane-endpoint>}"

  cat <<EOF

Inventory snippet for packages/node-join/inventory.local.ini:

[node_join_targets]
${TARGET_NAME} ansible_host=${TARGET_HOST} ansible_user=${TARGET_USER} ansible_ssh_private_key_file=${KEY_PATH} localk8s_node_name=${TARGET_NAME} localk8s_node_profile=${NODE_PROFILE} localk8s_node_labels=localk8s.io/workload-tier=general localk8s_node_taints=

[node_join_targets:vars]
ansible_become=true
localk8s_k3s_url=https://${cp_endpoint}:6443
localk8s_allow_control_plane_remove=false
EOF

  cat <<EOF

Optional (recommended when Ansible become prompts are unstable):

ssh -tt -i ${KEY_PATH} ${TARGET_USER}@${TARGET_HOST} 'echo "${TARGET_USER} ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/90-${TARGET_USER}-laminar >/dev/null && sudo chmod 440 /etc/sudoers.d/90-${TARGET_USER}-laminar && sudo visudo -cf /etc/sudoers.d/90-${TARGET_USER}-laminar'
EOF
}

main() {
  require_cmd ssh
  require_cmd ssh-keygen
  require_cmd ssh-copy-id

  load_local_env
  parse_args "$@"
  validate_inputs
  ensure_ssh_key
  run_copy_id
  run_connect_test
  print_inventory_snippet
}

main "$@"
