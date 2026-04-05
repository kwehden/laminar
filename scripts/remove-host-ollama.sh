#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '[%s] [remove-host-ollama] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

run_root() {
  if [[ "${EUID}" -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

main() {
  log "stopping and disabling systemd service if present"
  if systemctl list-unit-files | awk '{print $1}' | rg -q '^ollama\.service$'; then
    run_root systemctl disable --now ollama || true
  fi

  log "removing systemd unit files"
  run_root rm -f /etc/systemd/system/ollama.service
  run_root rm -rf /etc/systemd/system/ollama.service.d
  run_root systemctl daemon-reload

  log "removing package installs when present"
  if command -v dpkg >/dev/null 2>&1 && dpkg -s ollama >/dev/null 2>&1; then
    run_root apt-get remove -y ollama
  fi

  if command -v snap >/dev/null 2>&1 && snap list ollama >/dev/null 2>&1; then
    run_root snap remove ollama
  fi

  log "removing binary and data paths"
  run_root rm -f /usr/local/bin/ollama
  run_root rm -rf /usr/share/ollama /var/lib/ollama /var/log/ollama

  log "removing dedicated user/group if present"
  if id -u ollama >/dev/null 2>&1; then
    run_root userdel ollama || true
  fi
  if getent group ollama >/dev/null 2>&1; then
    run_root groupdel ollama || true
  fi

  if command -v ss >/dev/null 2>&1 && ss -ltn | rg -q ':11434\b'; then
    log "port 11434 is still in use; verify no other process is bound to it"
    ss -ltnp | rg ':11434\b' || true
    exit 1
  fi

  if command -v ollama >/dev/null 2>&1; then
    log "ollama binary still resolvable on PATH: $(command -v ollama)"
    exit 1
  fi

  log "host-level Ollama uninstall complete"
}

main "$@"
