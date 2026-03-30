# Bash Patterns for DevOps Automation

## Retry with Exponential Backoff

The single most reusable pattern in DevOps scripting.

```bash
# retry <attempts> <delay_seconds> <command...>
retry() {
  local attempts="$1"; shift
  local delay="$1";    shift
  local count=0

  until "$@"; do
    count=$(( count + 1 ))
    if (( count >= attempts )); then
      error "Command failed after ${attempts} attempts: $*"
      return 1
    fi
    warn "Attempt ${count}/${attempts} failed. Retrying in ${delay}s..."
    sleep "$delay"
    delay=$(( delay * 2 ))   # exponential backoff
  done
}

# Usage
retry 5 2 kubectl apply -f deployment.yaml
retry 3 5 curl -sf https://api.example.com/health
retry 10 1 aws sts get-caller-identity  # wait for AWS credentials to become available
```

## Wait for a Condition

```bash
wait_for() {
  local description="$1"; shift
  local timeout="${1}"; shift
  local interval="${1:-5}"; shift
  local elapsed=0

  info "Waiting for: ${description} (timeout: ${timeout}s)"

  while ! "$@" &>/dev/null; do
    if (( elapsed >= timeout )); then
      die "Timed out waiting for: ${description}"
    fi
    sleep "$interval"
    elapsed=$(( elapsed + interval ))
    log "  Still waiting... (${elapsed}/${timeout}s)"
  done

  info "Ready: ${description}"
}

# Wait for a pod to be ready
wait_for "myapp pod in production" 120 5 \
  kubectl get pods -n production -l app=myapp \
  --field-selector=status.phase=Running

# Wait for HTTP endpoint
wait_for "API health endpoint" 60 3 \
  curl -sf https://staging.myapp.com/health

# Wait for a file to appear (e.g. config written by another process)
wait_for "config file to appear" 30 2 \
  test -f /etc/myapp/config.json
```

## Parallel Execution with Job Control

```bash
# Run commands in parallel and collect results
run_parallel() {
  local pids=()
  local cmds=("$@")
  local exit_codes=()

  # Start all jobs
  for cmd in "${cmds[@]}"; do
    eval "$cmd" &
    pids+=($!)
  done

  # Wait for all and collect exit codes
  local failed=0
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      failed=$(( failed + 1 ))
    fi
  done

  return $failed
}

# Run a command against multiple namespaces in parallel
scan_namespaces() {
  local namespaces=("$@")
  local pids=()

  for ns in "${namespaces[@]}"; do
    trivy image --namespace "$ns" ... &
    pids+=($!)
  done

  local failed=0
  for pid in "${pids[@]}"; do
    wait "$pid" || (( failed++ ))
  done

  (( failed == 0 )) || die "${failed} namespace scans failed"
}

scan_namespaces dev staging production
```

## Locking — Prevent Concurrent Runs

```bash
LOCK_DIR="/tmp/${SCRIPT_NAME}.lock"

acquire_lock() {
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    local pid_file="${LOCK_DIR}/pid"
    if [[ -f "$pid_file" ]]; then
      local existing_pid
      existing_pid="$(cat "$pid_file")"
      if kill -0 "$existing_pid" 2>/dev/null; then
        die "Another instance is running (PID: ${existing_pid})"
      else
        warn "Stale lock found (PID ${existing_pid} is dead). Removing."
        rm -rf "$LOCK_DIR"
        mkdir "$LOCK_DIR"
      fi
    fi
  fi
  echo $$ > "${LOCK_DIR}/pid"
}

release_lock() {
  rm -rf "$LOCK_DIR"
}

# Use with trap
trap 'release_lock; cleanup' EXIT
acquire_lock
```

## Configuration File Pattern

```bash
# Load a config file safely
load_config() {
  local config_file="${1:-${HOME}/.myapp/config}"

  [[ -f "$config_file" ]] || die "Config file not found: ${config_file}"
  [[ "$(stat -c %a "$config_file")" == "600" ]] \
    || warn "Config file permissions should be 600 (has secrets)"

  # shellcheck source=/dev/null
  source "$config_file"
}

# Or use env file format (safer — no code execution)
load_env_file() {
  local env_file="$1"
  [[ -f "$env_file" ]] || return 0   # optional env file

  while IFS='=' read -r key value; do
    # Skip comments and blank lines
    [[ "$key" =~ ^#.*$ || -z "$key" ]] && continue
    # Strip quotes from value
    value="${value%\"}"
    value="${value#\"}"
    export "$key=$value"
  done < "$env_file"
}

load_env_file ".env"
load_env_file ".env.${ENVIRONMENT}"   # environment-specific overrides
```

## Output Formatting

```bash
# Progress bar
show_progress() {
  local current="$1"
  local total="$2"
  local label="${3:-Progress}"
  local width=40
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))
  local pct=$(( current * 100 / total ))

  printf "\r%s: [%s%s] %d%% (%d/%d)" \
    "$label" \
    "$(printf '#%.0s' $(seq 1 "$filled"))" \
    "$(printf ' %.0s' $(seq 1 "$empty"))" \
    "$pct" "$current" "$total"

  (( current == total )) && echo   # newline at end
}

# Table output
print_table() {
  local -a headers=("$@")
  printf "%-20s %-15s %-10s\n" "${headers[@]}"
  printf '%.0s─' {1..50}; echo
}

# Usage in a real script
echo ""; print_table "NAMESPACE" "DEPLOYMENT" "READY"
kubectl get deployments -A -o json | jq -r \
  '.items[] | [.metadata.namespace, .metadata.name,
    "\(.status.readyReplicas // 0)/\(.spec.replicas)"] | @tsv' | \
  while IFS=$'\t' read -r ns dep ready; do
    printf "%-20s %-15s %-10s\n" "$ns" "$dep" "$ready"
  done
```

## Safe File Operations

```bash
# Atomic write — never leave a partial file
atomic_write() {
  local target="$1"
  local content="$2"
  local tmpfile
  tmpfile="$(mktemp "${target}.XXXXXX")"

  echo "$content" > "$tmpfile"
  mv "$tmpfile" "$target"     # mv is atomic on same filesystem
}

# Backup before overwrite
safe_write() {
  local target="$1"
  local content="$2"

  [[ -f "$target" ]] && cp "$target" "${target}.bak.$(date +%s)"
  atomic_write "$target" "$content"
}

# Temp directory that is always cleaned up
with_tmpdir() {
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap "rm -rf '${tmpdir}'" RETURN   # cleaned up when function returns
  "$@" "$tmpdir"
}

# Usage
process_in_tmpdir() {
  local tmpdir="$1"
  cp config.yaml "$tmpdir/"
  sed -i "s/TAG_PLACEHOLDER/${IMAGE_TAG}/" "$tmpdir/config.yaml"
  kubectl apply -f "$tmpdir/config.yaml"
}

with_tmpdir process_in_tmpdir
```

## Environment Validation Pattern

```bash
# Validate all required tools and environment variables upfront
# This gives clear errors before anything runs
validate_environment() {
  local errors=0

  # Required tools
  local required_tools=("kubectl" "helm" "docker" "jq" "aws")
  for tool in "${required_tools[@]}"; do
    if ! command -v "$tool" &>/dev/null; then
      error "Required tool not found: ${tool}"
      (( errors++ ))
    fi
  done

  # Required environment variables
  local required_vars=("KUBECONFIG" "AWS_REGION" "IMAGE_TAG" "ENVIRONMENT")
  for var in "${required_vars[@]}"; do
    if [[ -z "${!var:-}" ]]; then
      error "Required environment variable not set: ${var}"
      (( errors++ ))
    fi
  done

  # Kubernetes connectivity
  if ! kubectl cluster-info &>/dev/null; then
    error "Cannot reach Kubernetes cluster (check KUBECONFIG)"
    (( errors++ ))
  fi

  # AWS credentials
  if ! aws sts get-caller-identity &>/dev/null; then
    error "AWS credentials are not valid"
    (( errors++ ))
  fi

  (( errors == 0 )) || die "Found ${errors} validation error(s). Fix them and re-run."
  info "Environment validation passed"
}
```

## Rollback Pattern

```bash
# Always have a rollback plan
deploy_with_rollback() {
  local namespace="$1"
  local deployment="$2"
  local new_tag="$3"

  # Capture current state for rollback
  local current_tag
  current_tag="$(kubectl get deployment "$deployment" -n "$namespace" \
    -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)"

  info "Deploying ${deployment}: ${current_tag} → ${new_tag}"

  # Perform deployment
  kubectl set image deployment/"$deployment" \
    "${deployment}=${REGISTRY}/${deployment}:${new_tag}" \
    -n "$namespace"

  # Wait for rollout
  if ! kubectl rollout status deployment/"$deployment" \
    -n "$namespace" --timeout=120s; then

    warn "Deployment failed — rolling back to ${current_tag}"
    kubectl rollout undo deployment/"$deployment" -n "$namespace"
    kubectl rollout status deployment/"$deployment" \
      -n "$namespace" --timeout=60s \
      || die "Rollback also failed! Manual intervention required."

    die "Deployment of ${new_tag} failed. Rolled back to ${current_tag}."
  fi

  info "Deployment successful: ${deployment}:${new_tag}"
}
```

## Multi-Environment Script Pattern

```bash
# One script handles all environments with different configs
ENVIRONMENTS=(dev staging production)

get_env_config() {
  local env="$1"
  case "$env" in
    dev)
      CLUSTER="dev-cluster"
      NAMESPACE="development"
      REPLICAS=1
      DOMAIN="dev.myapp.com"
      ;;
    staging)
      CLUSTER="staging-cluster"
      NAMESPACE="staging"
      REPLICAS=2
      DOMAIN="staging.myapp.com"
      ;;
    production)
      CLUSTER="prod-cluster"
      NAMESPACE="production"
      REPLICAS=5
      DOMAIN="myapp.com"
      ;;
    *)
      die "Unknown environment: ${env}. Must be: ${ENVIRONMENTS[*]}"
      ;;
  esac
}

get_env_config "$ENVIRONMENT"
```

## Idempotent Resource Creation

```bash
# Create only if not exists — safe to run multiple times
ensure_namespace() {
  local ns="$1"
  if kubectl get namespace "$ns" &>/dev/null; then
    info "Namespace ${ns} already exists"
  else
    info "Creating namespace ${ns}"
    kubectl create namespace "$ns"
    kubectl label namespace "$ns" \
      environment="$ENVIRONMENT" \
      managed-by=script
  fi
}

ensure_secret() {
  local name="$1"
  local namespace="$2"
  shift 2
  local literal_args=("$@")

  if kubectl get secret "$name" -n "$namespace" &>/dev/null; then
    info "Secret ${name} already exists in ${namespace}"
  else
    info "Creating secret ${name} in ${namespace}"
    kubectl create secret generic "$name" \
      -n "$namespace" \
      "${literal_args[@]}"
  fi
}

ensure_namespace "production"
ensure_secret "db-credentials" "production" \
  --from-literal=username=myapp \
  --from-literal=password="${DB_PASSWORD}"
```

## Script Versioning and Self-Update

```bash
SCRIPT_VERSION="1.4.2"
SCRIPT_URL="https://raw.githubusercontent.com/myorg/scripts/main/deploy.sh"

check_for_updates() {
  local latest_version
  latest_version="$(curl -sf "${SCRIPT_URL}" | grep 'SCRIPT_VERSION=' | cut -d'"' -f2)"

  if [[ "$latest_version" != "$SCRIPT_VERSION" ]]; then
    warn "A newer version (${latest_version}) is available."
    warn "Update with: curl -o $0 ${SCRIPT_URL} && chmod +x $0"
  fi
}

[[ "${SKIP_UPDATE_CHECK:-false}" != "true" ]] && check_for_updates &
```
