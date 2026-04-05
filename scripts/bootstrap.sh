#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_CONFIG_FILE="${PROJECT_ROOT}/config/versions.env"
MANAGED_CONFIG_FILE="${PROJECT_ROOT}/config/managed-assets.env"
ANSIBLE_DIR="${PROJECT_ROOT}/ansible"
HELMFILE_PATH="${PROJECT_ROOT}/helmfile.yaml"
CURRENT_STAGE=""

log() {
  local level="$1"
  shift
  printf '[%s] [%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*"
}

die() {
  log "ERROR" "$*"
  exit 1
}

load_config_file() {
  local config_file="$1"
  [[ -f "${config_file}" ]] || die "Required config file missing: ${config_file}"

  # shellcheck disable=SC1090
  source "${config_file}"
}

require_config_var() {
  local variable_name="$1"
  local variable_value="${!variable_name:-}"
  [[ -n "${variable_value}" ]] || die "Required config variable is empty: ${variable_name}"
}

run_ansible_tags() {
  local tags="$1"
  local -a ansible_cmd
  local -a runner_cmd

  ansible_cmd=(
    ansible-playbook
    site.yml
    --tags "${tags}"
    -e "k3s_version=${K3S_VERSION}"
    -e "k3s_default_runtime=${K3S_DEFAULT_RUNTIME}"
    -e "managed_host_paths_raw=${MANAGED_HOST_PATHS}"
  )
  runner_cmd=()

  if [[ "${EUID}" -ne 0 ]]; then
    log "INFO" "Running Ansible via sudo for host configuration privileges."
    runner_cmd=(sudo --preserve-env=K3S_VERSION,K3S_DEFAULT_RUNTIME,MANAGED_HOST_PATHS,ANSIBLE_CONFIG)
  fi

  (
    export K3S_VERSION
    export K3S_DEFAULT_RUNTIME
    export MANAGED_HOST_PATHS
    export ANSIBLE_CONFIG="${ANSIBLE_DIR}/ansible.cfg"
    cd "${ANSIBLE_DIR}"
    if [[ "${#runner_cmd[@]}" -gt 0 ]]; then
      "${runner_cmd[@]}" "${ansible_cmd[@]}"
    else
      "${ansible_cmd[@]}"
    fi
  )
}

run_helmfile_selector() {
  local selector="$1"
  KUBECONFIG="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}" \
    NVIDIA_DEVICE_PLUGIN_CHART_VERSION="${NVIDIA_DEVICE_PLUGIN_CHART_VERSION}" \
    KUBERAY_HELM_CHART_VERSION="${KUBERAY_HELM_CHART_VERSION}" \
    HEADLAMP_HELM_CHART_VERSION="${HEADLAMP_HELM_CHART_VERSION}" \
    helmfile -f "${HELMFILE_PATH}" -l "component=${selector}" sync
}

safe_cleanup_managed_host_paths() {
  local managed_path
  local -a runner_cmd

  runner_cmd=()
  if [[ "${EUID}" -ne 0 ]]; then
    runner_cmd=(sudo)
  fi

  for managed_path in ${MANAGED_HOST_PATHS}; do
    case "${managed_path}" in
      /var/lib/localk8s*|/var/log/localk8s*)
        if [[ "${#runner_cmd[@]}" -gt 0 ]]; then
          "${runner_cmd[@]}" mkdir -p "${managed_path}"
          "${runner_cmd[@]}" find "${managed_path}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        else
          mkdir -p "${managed_path}"
          find "${managed_path}" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
        fi
        ;;
      *)
        die "Refusing to clean unmanaged path outside allowed prefixes: ${managed_path}"
        ;;
    esac
  done
}

on_error() {
  local exit_code="$1"
  local line_no="$2"
  local command="$3"
  local stage_display="${CURRENT_STAGE:-unknown}"
  log "ERROR" "Stage '${stage_display}' failed (exit ${exit_code}) at line ${line_no}: ${command}"
  exit "${exit_code}"
}

trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

run_stage() {
  local stage_name="$1"
  CURRENT_STAGE="$stage_name"
  log "INFO" "Starting stage: ${stage_name}"
  "${stage_name}"
  log "INFO" "Completed stage: ${stage_name}"
}

stage_preflight() {
  command -v bash >/dev/null 2>&1 || die "bash is required"
  command -v date >/dev/null 2>&1 || die "date is required"
  command -v uname >/dev/null 2>&1 || die "uname is required"
  command -v ansible-playbook >/dev/null 2>&1 || die "ansible-playbook is required"
  command -v helm >/dev/null 2>&1 || die "helm is required"
  command -v helmfile >/dev/null 2>&1 || die "helmfile is required"
  command -v findmnt >/dev/null 2>&1 || die "findmnt is required"
  command -v rg >/dev/null 2>&1 || die "rg is required"

  load_config_file "${VERSIONS_CONFIG_FILE}"
  load_config_file "${MANAGED_CONFIG_FILE}"

  require_config_var "K3S_VERSION"
  require_config_var "NVIDIA_DEVICE_PLUGIN_CHART_VERSION"
  require_config_var "KUBERAY_HELM_CHART_VERSION"
  require_config_var "HEADLAMP_HELM_CHART_VERSION"
  require_config_var "RAY_IMAGE_TAG"
  require_config_var "MANAGED_RESOURCE_LABEL_KEY"
  require_config_var "MANAGED_RESOURCE_LABEL_VALUE"
  require_config_var "MANAGED_NAMESPACES"
  require_config_var "MANAGED_HOST_PATHS"
  require_config_var "MANAGED_K8S_MANIFEST_DIR"
  [[ "${MANAGED_RESOURCE_LABEL_KEY}" == "app.kubernetes.io/managed-by" ]] || die "MANAGED_RESOURCE_LABEL_KEY must remain app.kubernetes.io/managed-by"
  [[ "${MANAGED_RESOURCE_LABEL_VALUE}" == "localk8s-bootstrap" ]] || die "MANAGED_RESOURCE_LABEL_VALUE must remain localk8s-bootstrap"

  if [[ -f "${PROJECT_ROOT}/k8s/managed/ollama-storage.yaml" ]]; then
    findmnt -rn /mnt/ollama-models >/dev/null 2>&1 || die "Expected /mnt/ollama-models to be mounted before bootstrap. Run ./scripts/mount-ollama-model-disk.sh"
  fi

  log "INFO" "Loaded pinned versions: k3s=${K3S_VERSION}, nvidia-device-plugin=${NVIDIA_DEVICE_PLUGIN_CHART_VERSION}, kuberay=${KUBERAY_HELM_CHART_VERSION}, headlamp=${HEADLAMP_HELM_CHART_VERSION}, ray=${RAY_IMAGE_TAG}"
  log "INFO" "Loaded managed ownership selector: ${MANAGED_RESOURCE_LABEL_KEY}=${MANAGED_RESOURCE_LABEL_VALUE}"
  log "INFO" "Preflight checks passed"
}

stage_install_k3s() {
  run_ansible_tags "prereqs,host_paths,k3s"
}

stage_install_nvidia_stack() {
  run_ansible_tags "nvidia_runtime"
  run_helmfile_selector "nvidia"
}

stage_install_kuberay_and_ray() {
  run_helmfile_selector "kuberay"
}

stage_install_dashboards() {
  run_helmfile_selector "dashboard"
}

stage_reconcile_managed_cleanup() {
  local managed_manifest_abs="${PROJECT_ROOT}/${MANAGED_K8S_MANIFEST_DIR}"
  local managed_selector="${MANAGED_RESOURCE_LABEL_KEY}=${MANAGED_RESOURCE_LABEL_VALUE}"
  local kubeconfig_path="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"

  command -v kubectl >/dev/null 2>&1 || die "kubectl is required after k3s installation"
  [[ -d "${managed_manifest_abs}" ]] || die "Managed manifest directory not found: ${managed_manifest_abs}"

  kubectl --kubeconfig "${kubeconfig_path}" apply -f "${managed_manifest_abs}"
  kubectl --kubeconfig "${kubeconfig_path}" apply \
    --prune \
    -f "${managed_manifest_abs}" \
    -l "${managed_selector}" \
    --prune-allowlist=core/v1/Namespace \
    --prune-allowlist=core/v1/PersistentVolume \
    --prune-allowlist=core/v1/PersistentVolumeClaim \
    --prune-allowlist=core/v1/Service \
    --prune-allowlist=core/v1/LimitRange \
    --prune-allowlist=core/v1/ResourceQuota \
    --prune-allowlist=apps/v1/Deployment \
    --prune-allowlist=networking.k8s.io/v1/Ingress \
    --prune-allowlist=traefik.io/v1alpha1/Middleware \
    --prune-allowlist=ray.io/v1/RayCluster

  safe_cleanup_managed_host_paths
}

stage_emit_access_helper() {
  local kubeconfig_path="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
  log "INFO" "k3s access helper:"
  log "INFO" "  export KUBECONFIG=${kubeconfig_path}"
  log "INFO" "  kubectl --kubeconfig ${kubeconfig_path} get nodes"
}

main() {
  log "INFO" "${SCRIPT_NAME} starting"

  run_stage stage_preflight
  run_stage stage_install_k3s
  run_stage stage_install_nvidia_stack
  run_stage stage_install_kuberay_and_ray
  run_stage stage_install_dashboards
  run_stage stage_reconcile_managed_cleanup
  run_stage stage_emit_access_helper

  log "INFO" "${SCRIPT_NAME} completed"
}

main "$@"
