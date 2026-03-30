# Bash Core — Beyond the Basics

## The Non-Negotiable Header

Every bash script starts with this:

```bash
#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'
```

What each does:
- `set -e` — exit immediately if any command fails (non-zero exit code)
- `set -u` — treat unset variables as errors (catches typos like `$ENVIROMENT`)
- `set -o pipefail` — a pipeline fails if *any* command in it fails, not just the last
- `IFS=$'\n\t'` — prevents word-splitting on spaces (safer for filenames with spaces)

Without `set -euo pipefail`, bash silently swallows errors. This is the #1 cause of "my script ran but nothing happened" bugs.

## Logging That's Actually Useful

```bash
#!/usr/bin/env bash
set -euo pipefail

# Colours — only if terminal supports it
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; NC=''
fi

readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="${LOG_FILE:-/tmp/${SCRIPT_NAME%.sh}.log}"

log()   { echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $*" | tee -a "$LOG_FILE"; }
info()  { echo -e "${GREEN}[INFO]${NC}  $*" | tee -a "$LOG_FILE"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*" | tee -a "$LOG_FILE"; }
error() { echo -e "${RED}[ERROR]${NC} $*" | tee -a "$LOG_FILE" >&2; }
die()   { error "$*"; exit 1; }
```

Usage:
```bash
info "Starting deployment of ${APP_NAME}"
warn "Staging environment — not production"
die "KUBECONFIG is not set"  # exits immediately
```

## Strict Argument Parsing with `getopts`

```bash
#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Deploy an application to Kubernetes.

Options:
  -e ENV        Target environment (dev|staging|prod) [required]
  -t TAG        Docker image tag [required]
  -n NAMESPACE  Kubernetes namespace [default: same as ENV]
  -d            Dry run — print but do not apply
  -h            Show this help

Examples:
  $(basename "$0") -e staging -t v1.2.3
  $(basename "$0") -e prod -t v1.2.3 -n production
EOF
  exit 0
}

# Defaults
ENV=""
TAG=""
NAMESPACE=""
DRY_RUN=false

while getopts ":e:t:n:dh" opt; do
  case $opt in
    e) ENV="$OPTARG" ;;
    t) TAG="$OPTARG" ;;
    n) NAMESPACE="$OPTARG" ;;
    d) DRY_RUN=true ;;
    h) usage ;;
    :) die "Option -${OPTARG} requires an argument" ;;
    \?) die "Unknown option: -${OPTARG}" ;;
  esac
done
shift $((OPTIND - 1))

# Validate required args
[[ -z "$ENV"  ]] && die "Environment (-e) is required"
[[ -z "$TAG"  ]] && die "Image tag (-t) is required"
[[ "$ENV" =~ ^(dev|staging|prod)$ ]] || die "ENV must be dev, staging, or prod"

# Default namespace from ENV if not provided
NAMESPACE="${NAMESPACE:-$ENV}"
```

## Functions Done Right

```bash
# Functions should:
# 1. Return 0 on success, non-zero on failure
# 2. Use local variables
# 3. Print errors to stderr
# 4. Be testable in isolation

check_kubectl_context() {
  local expected_context="$1"
  local current_context

  current_context="$(kubectl config current-context 2>/dev/null)" \
    || die "kubectl is not configured or not in PATH"

  if [[ "$current_context" != "$expected_context" ]]; then
    error "Wrong kubectl context!"
    error "  Expected: ${expected_context}"
    error "  Current:  ${current_context}"
    return 1
  fi

  info "kubectl context verified: ${current_context}"
}

wait_for_deployment() {
  local namespace="$1"
  local deployment="$2"
  local timeout="${3:-120}"

  info "Waiting for deployment/${deployment} in ${namespace} (timeout: ${timeout}s)..."
  kubectl rollout status deployment/"$deployment" \
    -n "$namespace" \
    --timeout="${timeout}s" \
    || die "Deployment ${deployment} did not become ready within ${timeout}s"

  info "Deployment ${deployment} is ready"
}

get_pod_count() {
  local namespace="$1"
  local label="$2"

  kubectl get pods -n "$namespace" -l "$label" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[*].metadata.name}' \
    | wc -w
}
```

## Trap — Cleanup on Exit

```bash
#!/usr/bin/env bash
set -euo pipefail

TMPDIR=""
LOCK_FILE="/tmp/deploy.lock"

cleanup() {
  local exit_code=$?
  [[ -n "$TMPDIR" && -d "$TMPDIR" ]] && rm -rf "$TMPDIR"
  [[ -f "$LOCK_FILE" ]] && rm -f "$LOCK_FILE"

  if [[ $exit_code -ne 0 ]]; then
    error "Script failed with exit code ${exit_code}"
    error "Check logs at: ${LOG_FILE}"
  fi
}

# Run cleanup on EXIT (covers success, failure, and Ctrl+C)
trap cleanup EXIT

# Also handle signals explicitly
trap 'die "Interrupted"' INT TERM

# Now safe to create temp files — they'll be cleaned up
TMPDIR="$(mktemp -d)"
LOCK_FILE="/tmp/deploy.lock"

# Acquire lock (prevent concurrent runs)
if ! mkdir "$LOCK_FILE" 2>/dev/null; then
  die "Another instance is running (lock: ${LOCK_FILE})"
fi
```

## Variable Best Practices

```bash
# UPPERCASE for globals and exported vars
readonly APP_NAME="myapp"
readonly NAMESPACE="production"

# lowercase for local function vars
process_file() {
  local input_file="$1"
  local output_file="${2:-/tmp/output.txt}"
  local line_count

  line_count="$(wc -l < "$input_file")"
  info "Processing ${line_count} lines from ${input_file}"
}

# Default values
PORT="${PORT:-8080}"                          # use env var or default
LOG_LEVEL="${LOG_LEVEL:-info}"
RETRY_COUNT="${RETRY_COUNT:-3}"

# Brace everything — prevents subtle bugs
echo "${APP_NAME}_deployment"                # not $APP_NAME_deployment (different var)

# Arrays
REQUIRED_TOOLS=("kubectl" "helm" "docker" "aws")
NAMESPACES=("development" "staging" "production")

# Check array membership
in_array() {
  local needle="$1"; shift
  local element
  for element in "$@"; do [[ "$element" == "$needle" ]] && return 0; done
  return 1
}

in_array "staging" "${NAMESPACES[@]}" || die "Invalid namespace"
```

## String Operations

```bash
# Substitution
filename="deploy-v1.2.3.tar.gz"
name="${filename%.tar.gz}"         # → deploy-v1.2.3  (strip suffix)
version="${name##*-}"              # → v1.2.3          (strip longest prefix up to last -)
ext="${filename#*.}"               # → tar.gz          (strip up to first .)

# Replace
path="/var/log/app/error.log"
echo "${path/log/logs}"            # → /var/logs/app/error.log (first occurrence)
echo "${path//log/logs}"           # → /var/logs/app/error.logs (all occurrences)

# Case
env="PRODUCTION"
echo "${env,,}"                    # → production (lowercase)
echo "${env^}"                     # → pRODUCTION (uppercase first char)

# Substrings
tag="v1.2.3"
echo "${tag:1}"                    # → 1.2.3   (skip first char)
echo "${tag:1:3}"                  # → 1.2     (skip 1, take 3)

# Length
echo "${#tag}"                     # → 6

# Check if variable is set and non-empty
[[ -n "${MY_VAR:-}" ]] || die "MY_VAR is not set"

# Check if variable contains a substring
[[ "$ENV" == *"prod"* ]] && warn "Running against production!"
```

## Here Documents and Here Strings

```bash
# Heredoc — multi-line string, variables expanded
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NAMESPACE}
spec:
  replicas: ${REPLICAS:-2}
  selector:
    matchLabels:
      app: ${APP_NAME}
EOF

# Heredoc — no variable expansion (single-quote the delimiter)
cat <<'EOF' > /tmp/script.py
import os
print(f"Home: {os.environ.get('HOME')}")  # $ not interpreted by bash
EOF

# Heredoc into a function
generate_values_yaml() {
  local image_tag="$1"
  cat <<EOF
image:
  tag: "${image_tag}"
  pullPolicy: Always

resources:
  limits:
    cpu: 500m
    memory: 512Mi
EOF
}

values="$(generate_values_yaml "v1.2.3")"
echo "$values" | helm upgrade myapp ./chart -f -

# Here string — single line to stdin
base64_decode() { base64 -d <<< "$1"; }
```

## Process Substitution

```bash
# Compare two commands' output without temp files
diff <(kubectl get pods -n staging) <(kubectl get pods -n production)

# Read lines from a command into a loop
while IFS= read -r pod; do
  echo "Processing pod: $pod"
  kubectl logs "$pod" -n production --tail=10
done < <(kubectl get pods -n production -o name)

# Feed multiple inputs to a command
paste <(echo "col1") <(echo "col2")
```

## Conditional Patterns

```bash
# File tests
[[ -f "$FILE" ]] || die "File not found: $FILE"
[[ -d "$DIR"  ]] || mkdir -p "$DIR"
[[ -x "$BIN"  ]] || die "Not executable: $BIN"
[[ -s "$FILE" ]] || die "File is empty: $FILE"

# Command existence check
require() {
  command -v "$1" &>/dev/null || die "Required tool not found: $1"
}
require kubectl
require helm
require jq

# Numeric comparison
pods="$(get_pod_count "$NS" "$LABEL")"
(( pods >= 1 )) || die "No pods running for ${LABEL} in ${NS}"
(( pods < 5 )) && warn "Low pod count: ${pods}"

# One-liners
kubectl get ns "$NAMESPACE" &>/dev/null || kubectl create ns "$NAMESPACE"
[[ "$ENV" == "prod" ]] && { confirm_production || exit 1; }
```

## Reading User Input Safely

```bash
confirm() {
  local prompt="${1:-Are you sure?}"
  local response
  read -r -p "${prompt} [y/N] " response
  [[ "${response,,}" == "y" ]] || return 1
}

confirm_production() {
  warn "You are about to deploy to PRODUCTION"
  warn "Current context: $(kubectl config current-context)"

  local env_check
  read -r -p "Type 'production' to confirm: " env_check
  [[ "$env_check" == "production" ]] \
    || die "Confirmation failed — aborting"
}

read_secret() {
  local prompt="$1"
  local secret
  read -r -s -p "${prompt}: " secret   # -s = silent (no echo)
  echo                                  # newline after hidden input
  echo "$secret"
}
```

## jq — JSON Processing in Bash

jq is essential for any modern DevOps scripting. Treat it as part of bash.

```bash
# Get a value
aws ec2 describe-instances | jq '.Reservations[0].Instances[0].InstanceId'

# Filter and extract
kubectl get pods -o json | jq '.items[].metadata.name'

# Filter with condition
kubectl get pods -o json | \
  jq '.items[] | select(.status.phase != "Running") | .metadata.name'

# Transform to a new shape
kubectl get pods -o json | jq '
  .items[] |
  {
    name: .metadata.name,
    status: .status.phase,
    node: .spec.nodeName,
    restarts: (.status.containerStatuses[0].restartCount // 0)
  }
'

# Build an object from a command
jq -n \
  --arg tag "$IMAGE_TAG" \
  --arg env "$ENVIRONMENT" \
  --argjson replicas "$REPLICA_COUNT" \
  '{tag: $tag, environment: $env, replicas: $replicas}'

# Compact JSON (one line)
jq -c '.' input.json

# Raw string output (no quotes)
jq -r '.items[].metadata.name' pods.json

# Count items
jq '.items | length' pods.json

# Null safety
jq '.items[].metadata.labels.app // "no-label"' pods.json
```

## yq — YAML Processing

```bash
# Install: pip install yq  or  brew install yq

# Read a value
yq '.metadata.name' deployment.yaml

# Update a value in-place
yq -i '.spec.replicas = 3' deployment.yaml
yq -i ".spec.template.spec.containers[0].image = \"myapp:${TAG}\"" deployment.yaml

# Merge two YAML files
yq merge base.yaml overrides.yaml

# Convert YAML to JSON (for jq processing)
yq -o json deployment.yaml | jq '.metadata.name'
```
