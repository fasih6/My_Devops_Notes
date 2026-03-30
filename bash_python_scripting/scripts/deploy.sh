#!/usr/bin/env bash
# deploy.sh — Kubernetes deployment with safety checks
# Usage: ./deploy.sh -e staging -t v1.2.3
set -euo pipefail
IFS=$'\n\t'

[[ -t 1 ]] && { RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'; } \
           || { RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''; }

log()  { printf "${BLUE}[%s]${NC} %s\n" "$(date '+%H:%M:%S')" "$*"; }
info() { printf "${GREEN}[INFO]${NC}  %s\n" "$*"; }
warn() { printf "${YELLOW}[WARN]${NC}  %s\n" "$*"; }
die()  { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; exit 1; }

usage() { echo "Usage: $0 -e <env> -t <tag> [-n <namespace>] [-s <service>] [-d]"; exit 0; }

ENV=""; TAG=""; NAMESPACE=""; SERVICE="${SERVICE:-myapp}"; DRY_RUN=false

while getopts ":e:t:n:s:dh" opt; do
  case $opt in
    e) ENV="$OPTARG" ;;   t) TAG="$OPTARG" ;;
    n) NAMESPACE="$OPTARG" ;; s) SERVICE="$OPTARG" ;;
    d) DRY_RUN=true ;;    h) usage ;;
    :) die "Option -${OPTARG} needs an argument" ;;
    \?) die "Unknown: -${OPTARG}" ;;
  esac
done

[[ -z "$ENV" ]] && die "ENV (-e) required"
[[ -z "$TAG" ]] && die "TAG (-t) required"
[[ "$ENV" =~ ^(dev|staging|prod)$ ]] || die "ENV must be dev|staging|prod"
NAMESPACE="${NAMESPACE:-$ENV}"

for tool in kubectl helm jq; do
  command -v "$tool" &>/dev/null || die "Missing required tool: $tool"
done

LOCK="/tmp/${SERVICE}-deploy.lock"
trap 'rm -rf "$LOCK"' EXIT
mkdir "$LOCK" 2>/dev/null || die "Deploy already running (lock: $LOCK)"

info "Deploying ${SERVICE}:${TAG} → ${ENV}/${NAMESPACE}"

[[ "$ENV" == "prod" ]] && {
  warn "PRODUCTION DEPLOYMENT — type 'production' to confirm:"
  read -r confirm
  [[ "$confirm" == "production" ]] || die "Cancelled"
}

if [[ "$DRY_RUN" == "true" ]]; then
  info "[DRY RUN] Would run: helm upgrade --install ${SERVICE} ./charts/${SERVICE} --set image.tag=${TAG} -n ${NAMESPACE}"
  exit 0
fi

helm upgrade --install "$SERVICE" "./charts/${SERVICE}" \
  --namespace "$NAMESPACE" --create-namespace \
  --set "image.tag=${TAG}" \
  --wait --timeout 5m --atomic

READY="$(kubectl get deployment "$SERVICE" -n "$NAMESPACE" \
  -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)"
DESIRED="$(kubectl get deployment "$SERVICE" -n "$NAMESPACE" \
  -o jsonpath='{.spec.replicas}' 2>/dev/null || echo 1)"

[[ "$READY" == "$DESIRED" ]] || die "Only ${READY}/${DESIRED} pods ready"
info "Deployment complete: ${SERVICE}:${TAG} in ${NAMESPACE}"
