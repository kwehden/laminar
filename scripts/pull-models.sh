#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CONFIG_FILE="${PROJECT_ROOT}/config/models.txt"
OLLAMA_ENDPOINT="${OLLAMA_ENDPOINT:-http://127.0.0.1:11434}"
VERIFY_ONLY="false"

log() {
  printf '[%s] [pull-models] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

die() {
  log "ERROR: $*"
  exit 1
}

usage() {
  cat <<'EOF'
Usage:
  ./scripts/pull-models.sh [--config <path>] [--endpoint <url>] [--verify-only]

Options:
  --config <path>    Model list file (default: config/models.txt)
  --endpoint <url>   Ollama API endpoint (default: http://127.0.0.1:11434)
  --verify-only      Skip pulls; verify all configured models exist via /api/show
  -h, --help         Show this help
EOF
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --config)
        [[ $# -ge 2 ]] || die "--config requires a value"
        CONFIG_FILE="$2"
        shift 2
        ;;
      --endpoint)
        [[ $# -ge 2 ]] || die "--endpoint requires a value"
        OLLAMA_ENDPOINT="$2"
        shift 2
        ;;
      --verify-only)
        VERIFY_ONLY="true"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
  done
}

load_models() {
  local line
  local trimmed

  MODELS=()
  while IFS= read -r line || [[ -n "${line}" ]]; do
    trimmed="$(printf '%s' "${line}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    [[ -n "${trimmed}" ]] || continue
    [[ "${trimmed}" =~ ^# ]] && continue
    MODELS+=("${trimmed}")
  done <"${CONFIG_FILE}"

  [[ "${#MODELS[@]}" -gt 0 ]] || die "no models found in ${CONFIG_FILE}"
}

check_endpoint() {
  curl -sS --fail "${OLLAMA_ENDPOINT}/api/version" >/dev/null
}

pull_model() {
  local model="$1"
  local status

  status="$(
    curl -sS --fail "${OLLAMA_ENDPOINT}/api/pull" \
      -H 'Content-Type: application/json' \
      -d "{\"model\":\"${model}\",\"stream\":false}" | jq -r '.status // empty'
  )"

  [[ -n "${status}" ]] || die "pull returned no status for ${model}"
  log "pull ${model}: ${status}"
}

verify_model() {
  local model="$1"
  curl -sS --fail "${OLLAMA_ENDPOINT}/api/show" \
    -H 'Content-Type: application/json' \
    -d "{\"model\":\"${model}\"}" >/dev/null
  log "verify ${model}: ok"
}

print_tags() {
  log "installed tags:"
  curl -sS --fail "${OLLAMA_ENDPOINT}/api/tags" | jq -r '.models[].name' | sort
}

main() {
  local model

  require_cmd curl
  require_cmd jq

  parse_args "$@"
  [[ -f "${CONFIG_FILE}" ]] || die "config file not found: ${CONFIG_FILE}"

  load_models
  check_endpoint

  log "endpoint=${OLLAMA_ENDPOINT}"
  log "config=${CONFIG_FILE}"
  log "models=${#MODELS[@]}"

  if [[ "${VERIFY_ONLY}" == "false" ]]; then
    for model in "${MODELS[@]}"; do
      pull_model "${model}"
    done
  else
    log "verify-only mode enabled; skipping pulls"
  fi

  for model in "${MODELS[@]}"; do
    verify_model "${model}"
  done

  print_tags
  log "completed"
}

main "$@"
