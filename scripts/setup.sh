#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_CONFIG_FILE="${PROJECT_ROOT}/config/versions.env"
LOCAL_ENV_FILE="${PROJECT_ROOT}/config/local.env"

log() {
  printf '[%s] [setup] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

if [[ ${EUID} -eq 0 ]]; then
  SUDO=""
else
  command -v sudo >/dev/null 2>&1 || die "sudo is required when running as non-root"
  SUDO="sudo"
fi

load_versions() {
  [[ -f "${VERSIONS_CONFIG_FILE}" ]] || die "missing ${VERSIONS_CONFIG_FILE}"
  # shellcheck disable=SC1090
  source "${VERSIONS_CONFIG_FILE}"
  [[ -n "${HELM_VERSION:-}" ]] || die "HELM_VERSION must be set"
  [[ -n "${HELMFILE_VERSION:-}" ]] || die "HELMFILE_VERSION must be set"
}

ensure_apt() {
  command -v apt-get >/dev/null 2>&1 || die "this setup script currently supports apt-based systems"
}

install_apt_packages() {
  log "installing apt prerequisites"
  ${SUDO} apt-get update
  ${SUDO} apt-get install -y \
    ca-certificates \
    curl \
    gpg \
    jq \
    ripgrep \
    tar \
    gzip
}

install_ansible() {
  if command -v ansible-playbook >/dev/null 2>&1; then
    log "ansible-playbook already installed"
    return
  fi

  log "installing ansible"
  if ! ${SUDO} apt-get install -y ansible-core; then
    ${SUDO} apt-get install -y ansible
  fi

  command -v ansible-playbook >/dev/null 2>&1 || die "failed to install ansible-playbook"
}

get_helm_version() {
  if ! command -v helm >/dev/null 2>&1; then
    echo ""
    return
  fi

  helm version --short 2>/dev/null | awk '{print $1}' | sed 's/+.*//'
}

get_helmfile_version() {
  if ! command -v helmfile >/dev/null 2>&1; then
    echo ""
    return
  fi

  helmfile version 2>/dev/null | awk '/Version/ {print $2; exit}' | sed 's/^v//'
}

install_helm() {
  local current=""
  current="$(get_helm_version)"

  if [[ "${current}" == "${HELM_VERSION}" ]]; then
    log "helm ${HELM_VERSION} already installed"
    return
  fi

  log "installing helm ${HELM_VERSION}"
  local tmpdir archive
  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/helm.tgz"

  curl -fsSL "https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz" -o "${archive}"
  tar -xzf "${archive}" -C "${tmpdir}"
  ${SUDO} install -m 0755 "${tmpdir}/linux-amd64/helm" /usr/local/bin/helm

  rm -rf "${tmpdir}"
}

install_helmfile() {
  local current=""
  current="$(get_helmfile_version)"

  if [[ "${current}" == "${HELMFILE_VERSION}" ]]; then
    log "helmfile ${HELMFILE_VERSION} already installed"
    return
  fi

  log "installing helmfile ${HELMFILE_VERSION}"
  local tmpdir archive
  tmpdir="$(mktemp -d)"
  archive="${tmpdir}/helmfile.tgz"

  curl -fsSL \
    "https://github.com/helmfile/helmfile/releases/download/v${HELMFILE_VERSION}/helmfile_${HELMFILE_VERSION}_linux_amd64.tar.gz" \
    -o "${archive}"
  tar -xzf "${archive}" -C "${tmpdir}"
  ${SUDO} install -m 0755 "${tmpdir}/helmfile" /usr/local/bin/helmfile

  rm -rf "${tmpdir}"
}

print_versions() {
  log "installed tool versions"
  ansible-playbook --version | head -n 1
  printf 'helm %s\n' "$(get_helm_version)"
  printf 'helmfile v%s\n' "$(get_helmfile_version)"
  rg --version | head -n 1
}

first_non_loopback_ipv4() {
  hostname -I | awk '{
    for (i = 1; i <= NF; i++) {
      if ($i ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ && $i !~ /^127\./) {
        print $i
        exit
      }
    }
  }'
}

register_local_env() {
  local env_local_hostname="${LOCAL_HOSTNAME:-}"
  local env_local_address_mode="${LOCAL_ADDRESS_MODE:-}"
  local env_local_control_plane_endpoint="${LOCAL_CONTROL_PLANE_ENDPOINT:-}"
  local local_hostname=""
  local local_address_mode=""
  local local_control_plane_endpoint=""
  local detected_ip=""
  local prompt=""
  local default_endpoint=""

  if [[ -f "${LOCAL_ENV_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "${LOCAL_ENV_FILE}"
  fi

  local_hostname="${env_local_hostname:-${LOCAL_HOSTNAME:-}}"
  local_address_mode="${env_local_address_mode:-${LOCAL_ADDRESS_MODE:-}}"
  local_control_plane_endpoint="${env_local_control_plane_endpoint:-${LOCAL_CONTROL_PLANE_ENDPOINT:-}}"

  if [[ -z "${local_hostname}" ]]; then
    local_hostname="$(hostname -s)"
  fi

  detected_ip="$(first_non_loopback_ipv4)"

  if [[ -z "${local_address_mode}" ]]; then
    local_address_mode="dns"
    if [[ -t 0 ]]; then
      read -r -p "Address mode for node inventory and k3s URL [dns/ip] (default: dns): " prompt
      if [[ -n "${prompt}" ]]; then
        local_address_mode="${prompt,,}"
      fi
    fi
  fi

  case "${local_address_mode}" in
    dns)
      default_endpoint="${local_hostname}"
      ;;
    ip)
      [[ -n "${detected_ip}" ]] || die "Unable to detect a non-loopback IPv4 address for LOCAL_ADDRESS_MODE=ip"
      default_endpoint="${detected_ip}"
      ;;
    *)
      die "LOCAL_ADDRESS_MODE must be 'dns' or 'ip' (got '${local_address_mode}')"
      ;;
  esac

  if [[ -z "${local_control_plane_endpoint}" ]]; then
    local_control_plane_endpoint="${default_endpoint}"
    if [[ -t 0 ]]; then
      read -r -p "Control-plane endpoint for localk8s_k3s_url [${default_endpoint}]: " prompt
      if [[ -n "${prompt}" ]]; then
        local_control_plane_endpoint="${prompt}"
      fi
    fi
  fi

  [[ -n "${local_control_plane_endpoint}" ]] || die "LOCAL_CONTROL_PLANE_ENDPOINT must not be empty"

  cat >"${LOCAL_ENV_FILE}" <<EOF
# Local host-specific overrides for Laminar scripts.
# Generated by scripts/setup.sh. Edit only when you intentionally want custom values.
LOCAL_HOSTNAME="${local_hostname}"
LOCAL_ADDRESS_MODE="${local_address_mode}"
LOCAL_CONTROL_PLANE_ENDPOINT="${local_control_plane_endpoint}"
EOF

  log "registered local config in ${LOCAL_ENV_FILE}"
  log "optional shell export for current session:"
  log "  export LOCAL_HOSTNAME=\"${local_hostname}\""
  log "  export LOCAL_ADDRESS_MODE=\"${local_address_mode}\""
  log "  export LOCAL_CONTROL_PLANE_ENDPOINT=\"${local_control_plane_endpoint}\""
  log "optional persistence in ~/.bashrc or ~/.zshrc:"
  log "  export LOCAL_HOSTNAME=\"${local_hostname}\""
  log "  export LOCAL_ADDRESS_MODE=\"${local_address_mode}\""
  log "  export LOCAL_CONTROL_PLANE_ENDPOINT=\"${local_control_plane_endpoint}\""
}

main() {
  load_versions
  ensure_apt
  install_apt_packages
  install_ansible
  install_helm
  install_helmfile
  print_versions
  register_local_env
  log "setup completed"
}

main "$@"
