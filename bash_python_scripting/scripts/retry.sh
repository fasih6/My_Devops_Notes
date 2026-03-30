#!/usr/bin/env bash
# retry.sh — Retry any command with exponential backoff
#
# Usage:
#   ./retry.sh [OPTIONS] -- COMMAND [ARGS...]
#
# Options:
#   -a ATTEMPTS   Max attempts (default: 5)
#   -d DELAY      Initial delay in seconds (default: 2)
#   -b BACKOFF    Backoff multiplier (default: 2)
#   -t TIMEOUT    Max total time in seconds (default: 60)
#
# Examples:
#   ./retry.sh -- curl -sf https://api.example.com/health
#   ./retry.sh -a 10 -d 1 -- kubectl apply -f deploy.yaml
#   ./retry.sh -t 120 -- helm upgrade --install myapp ./charts/myapp --wait

set -euo pipefail

ATTEMPTS=5; DELAY=2; BACKOFF=2; TIMEOUT=60

while getopts ":a:d:b:t:" opt; do
  case $opt in
    a) ATTEMPTS="$OPTARG" ;;  d) DELAY="$OPTARG" ;;
    b) BACKOFF="$OPTARG" ;;   t) TIMEOUT="$OPTARG" ;;
    :) echo "Option -${OPTARG} requires an argument" >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))
[[ "${1:-}" == "--" ]] && shift

[[ $# -eq 0 ]] && { echo "Usage: $0 [OPTIONS] -- COMMAND [ARGS...]" >&2; exit 1; }

CMD=("$@")
count=0
current_delay="$DELAY"
start_time="$(date +%s)"

echo "[retry] Command: ${CMD[*]}"
echo "[retry] Max attempts: ${ATTEMPTS}, Initial delay: ${DELAY}s, Timeout: ${TIMEOUT}s"

until "${CMD[@]}"; do
  count=$(( count + 1 ))
  elapsed=$(( $(date +%s) - start_time ))

  if (( count >= ATTEMPTS )); then
    echo "[retry] FAILED after ${count} attempts (${elapsed}s elapsed)" >&2
    exit 1
  fi

  if (( elapsed + current_delay > TIMEOUT )); then
    echo "[retry] TIMEOUT would be exceeded — giving up" >&2
    exit 1
  fi

  echo "[retry] Attempt ${count}/${ATTEMPTS} failed. Retrying in ${current_delay}s... (${elapsed}s elapsed)"
  sleep "$current_delay"
  current_delay=$(echo "$current_delay * $BACKOFF" | bc | cut -d. -f1)
done

elapsed=$(( $(date +%s) - start_time ))
echo "[retry] Succeeded after $((count + 1)) attempt(s) (${elapsed}s)"
