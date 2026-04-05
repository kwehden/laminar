#!/usr/bin/env bash
set -Eeuo pipefail

# Override if needed:
#   OLLAMA_MODEL_DISK_UUID=<uuid> ./scripts/mount-ollama-model-disk.sh
#   OLLAMA_MODEL_MOUNT_POINT=/mnt/ollama-models ./scripts/mount-ollama-model-disk.sh

DISK_UUID_DEFAULT="052b22cb-460f-4951-8d78-7a816f8a6895"
MOUNT_POINT="${OLLAMA_MODEL_MOUNT_POINT:-/mnt/ollama-models}"
DISK_UUID="${OLLAMA_MODEL_DISK_UUID:-${DISK_UUID_DEFAULT}}"
FSTYPE_EXPECTED="${OLLAMA_MODEL_FS_TYPE:-ext4}"

log() {
  printf '[%s] [mount-ollama-disk] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

run_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

main() {
  local device_path fstype fstab_line

  device_path="$(lsblk -rno PATH,UUID | awk -v uuid="${DISK_UUID}" '$2 == uuid { print $1; exit }' || true)"
  if [[ -z "${device_path}" ]]; then
    device_path="$(blkid -U "${DISK_UUID}" || true)"
  fi
  if [[ -z "${device_path}" && "${EUID}" -ne 0 ]]; then
    device_path="$(sudo blkid -U "${DISK_UUID}" || true)"
  fi
  [[ -n "${device_path}" ]] || {
    log "unable to resolve device for UUID=${DISK_UUID}"
    exit 1
  }

  fstype="$(lsblk -no FSTYPE "${device_path}" | head -n 1 | tr -d '[:space:]' || true)"
  if [[ -z "${fstype}" ]]; then
    fstype="$(blkid -o value -s TYPE "${device_path}" || true)"
  fi
  if [[ -z "${fstype}" && "${EUID}" -ne 0 ]]; then
    fstype="$(sudo blkid -o value -s TYPE "${device_path}" || true)"
  fi
  [[ "${fstype}" == "${FSTYPE_EXPECTED}" ]] || {
    log "unexpected filesystem on ${device_path}: got '${fstype}', expected '${FSTYPE_EXPECTED}'"
    exit 1
  }

  run_root mkdir -p "${MOUNT_POINT}"

  fstab_line="UUID=${DISK_UUID} ${MOUNT_POINT} ${FSTYPE_EXPECTED} defaults,nofail 0 2"
  if ! grep -Eqs "^[[:space:]]*UUID=${DISK_UUID}[[:space:]]+${MOUNT_POINT}[[:space:]]+${FSTYPE_EXPECTED}[[:space:]]" /etc/fstab; then
    log "adding fstab entry for ${device_path} -> ${MOUNT_POINT}"
    printf '%s\n' "${fstab_line}" | run_root tee -a /etc/fstab >/dev/null
  else
    log "fstab entry already present"
  fi

  if findmnt -n "${MOUNT_POINT}" >/dev/null 2>&1; then
    log "${MOUNT_POINT} already mounted"
  else
    log "mounting ${MOUNT_POINT}"
    run_root mount "${MOUNT_POINT}"
  fi

  run_root chmod 0775 "${MOUNT_POINT}"

  log "mount ready:"
  findmnt "${MOUNT_POINT}"
}

main "$@"
