#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VERSIONS_CONFIG_FILE="${PROJECT_ROOT}/config/versions.env"

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

main() {
  load_versions
  ensure_apt
  install_apt_packages
  install_ansible
  install_helm
  install_helmfile
  print_versions
  log "setup completed"
}

main "$@"
