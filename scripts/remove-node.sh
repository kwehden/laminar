#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

TARGET_NODE=""
TARGET_HOST=""
INVENTORY_PATH="${PROJECT_ROOT}/ansible/inventory/localhost.yml"
ALLOW_CONTROL_PLANE_REMOVE="false"
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
Usage: ${SCRIPT_NAME} --node <k8s-node-name> --target <inventory-host> [--inventory <path>] [--allow-control-plane-remove] [-- <extra ansible args>]

Options:
  --node <name>                   Kubernetes node name to remove (required)
  --target <host>                 Inventory host/group used for host-side uninstall (required)
  --inventory <path>              Ansible inventory path (default: ansible/inventory/localhost.yml)
  --allow-control-plane-remove    Explicitly allow targeting control-plane node (dangerous)
  -h, --help                      Show this help text
USAGE
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --node)
        [[ $# -ge 2 ]] || die "--node requires a value"
        TARGET_NODE="$2"
        shift 2
        ;;
      --target)
        [[ $# -ge 2 ]] || die "--target requires a value"
        TARGET_HOST="$2"
        shift 2
        ;;
      --inventory)
        [[ $# -ge 2 ]] || die "--inventory requires a value"
        INVENTORY_PATH="$2"
        shift 2
        ;;
      --allow-control-plane-remove)
        ALLOW_CONTROL_PLANE_REMOVE="true"
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

preflight() {
  require_cmd kubectl
  require_cmd ansible-playbook
  require_cmd bash

  [[ -n "${TARGET_NODE}" ]] || die "--node is required"
  [[ -n "${TARGET_HOST}" ]] || die "--target is required"
  [[ -f "${INVENTORY_PATH}" ]] || die "Inventory not found: ${INVENTORY_PATH}"

  kubectl --kubeconfig "${KUBECONFIG_PATH}" get node "${TARGET_NODE}" >/dev/null 2>&1 || die "Node not found: ${TARGET_NODE}"
}

enforce_control_plane_safety() {
  local roles
  roles="$(kubectl --kubeconfig "${KUBECONFIG_PATH}" get node "${TARGET_NODE}" -o jsonpath='{.metadata.labels}' | tr -d '\n')"

  if [[ "${ALLOW_CONTROL_PLANE_REMOVE}" != "true" ]]; then
    if [[ "${roles}" == *"node-role.kubernetes.io/control-plane"* ]] || [[ "${roles}" == *"node-role.kubernetes.io/master"* ]]; then
      die "Refusing control-plane node removal for ${TARGET_NODE}. Re-run with --allow-control-plane-remove to override."
    fi
  fi
}

run_kubectl_removal() {
  log "Cordoning ${TARGET_NODE}"
  kubectl --kubeconfig "${KUBECONFIG_PATH}" cordon "${TARGET_NODE}" || true

  log "Draining ${TARGET_NODE}"
  kubectl --kubeconfig "${KUBECONFIG_PATH}" drain "${TARGET_NODE}" \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --grace-period=30 \
    --timeout=180s

  log "Deleting node object ${TARGET_NODE}"
  kubectl --kubeconfig "${KUBECONFIG_PATH}" delete node "${TARGET_NODE}"
}

run_ansible_uninstall() {
  local -a ansible_cmd
  local -a sudo_wrapper

  ansible_cmd=(
    ansible-playbook
    -i "${INVENTORY_PATH}"
    site.yml
    --limit "${TARGET_HOST}"
    --tags "k3s_agent,node_gpu_runtime"
    -e "node_join_target=${TARGET_HOST}"
    -e "k3s_agent_join_mode=uninstall"
    -e "node_gpu_runtime_mode=uninstall"
  )

  if [[ ${#EXTRA_ANSIBLE_ARGS[@]} -gt 0 ]]; then
    ansible_cmd+=("${EXTRA_ANSIBLE_ARGS[@]}")
  fi

  sudo_wrapper=()
  if [[ ${EUID} -ne 0 ]]; then
    require_cmd sudo
    sudo_wrapper=(sudo --preserve-env=NODE_JOIN_TARGET,ANSIBLE_CONFIG)
  fi

  log "Running host-side uninstall placeholder for ${TARGET_HOST}"
  (
    export NODE_JOIN_TARGET="${TARGET_HOST}"
    export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
    cd "${ANSIBLE_DIR}"
    if [[ ${#sudo_wrapper[@]} -gt 0 ]]; then
      "${sudo_wrapper[@]}" "${ansible_cmd[@]}"
    else
      "${ansible_cmd[@]}"
    fi
  )
}

main() {
  parse_args "$@"
  preflight
  enforce_control_plane_safety
  run_kubectl_removal
  run_ansible_uninstall
  log "Remove workflow completed"
}

main "$@"
