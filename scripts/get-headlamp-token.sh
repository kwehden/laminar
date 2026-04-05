#!/usr/bin/env bash
set -Eeuo pipefail

KUBECONFIG_PATH="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
NAMESPACE="k3s-dashboard"
SERVICE_ACCOUNT="headlamp"
DURATION=""

usage() {
  cat <<'EOF'
Usage:
  ./scripts/get-headlamp-token.sh [--namespace <ns>] [--service-account <name>] [--duration <duration>]

Defaults:
  namespace:       k3s-dashboard
  service-account: headlamp
  kubeconfig:      $KUBECONFIG or /etc/rancher/k3s/k3s.yaml

Examples:
  ./scripts/get-headlamp-token.sh
  ./scripts/get-headlamp-token.sh --duration 24h
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --namespace)
        [[ $# -ge 2 ]] || { echo "--namespace requires a value" >&2; exit 1; }
        NAMESPACE="$2"
        shift 2
        ;;
      --service-account)
        [[ $# -ge 2 ]] || { echo "--service-account requires a value" >&2; exit 1; }
        SERVICE_ACCOUNT="$2"
        shift 2
        ;;
      --duration)
        [[ $# -ge 2 ]] || { echo "--duration requires a value" >&2; exit 1; }
        DURATION="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
  done
}

main() {
  local -a cmd

  require_cmd kubectl
  parse_args "$@"

  cmd=(
    kubectl
    --kubeconfig "${KUBECONFIG_PATH}"
    create
    token "${SERVICE_ACCOUNT}"
    --namespace "${NAMESPACE}"
  )

  if [[ -n "${DURATION}" ]]; then
    cmd+=(--duration "${DURATION}")
  fi

  "${cmd[@]}"
}

main "$@"
