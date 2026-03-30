# Real-World Scripts — Full Production Examples

## 1. deploy.sh — Production-Grade Kubernetes Deployment

```bash
#!/usr/bin/env bash
# deploy.sh — Deploy a service to Kubernetes with safety checks
#
# Usage:
#   ./deploy.sh -e staging -t v1.2.3
#   ./deploy.sh -e prod -t v1.2.3 -n production --dry-run
#
# Required env vars: KUBECONFIG, DOCKER_REGISTRY

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="2.1.0"
readonly LOG_FILE="/tmp/deploy-$(date +%Y%m%d-%H%M%S).log"

# ─── Logging ───────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
  BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
else
  RED=''; GREEN=''; YELLOW=''; BLUE=''; CYAN=''; NC=''
fi

log()   { printf "${BLUE}[%s]${NC} %s\n" "$(date '+%H:%M:%S')" "$*" | tee -a "$LOG_FILE"; }
info()  { printf "${GREEN}[INFO]${NC}  %s\n" "$*" | tee -a "$LOG_FILE"; }
warn()  { printf "${YELLOW}[WARN]${NC}  %s\n" "$*" | tee -a "$LOG_FILE"; }
error() { printf "${RED}[ERROR]${NC} %s\n" "$*" | tee -a "$LOG_FILE" >&2; }
die()   { error "$*"; exit 1; }

# ─── Args ──────────────────────────────────────────────────────────
usage() {
  cat <<EOF
${SCRIPT_NAME} v${SCRIPT_VERSION} — Kubernetes deployment

Usage: ${SCRIPT_NAME} [OPTIONS]

Options:
  -e ENV       Environment: dev|staging|prod [required]
  -t TAG       Docker image tag [required]
  -n NS        Kubernetes namespace [default: same as ENV]
  -s SERVICE   Service name [default: myapp]
  -d           Dry run
  -h           Help

Examples:
  ${SCRIPT_NAME} -e staging -t v1.2.3
  ${SCRIPT_NAME} -e prod -t v1.2.3 -n production -s api
EOF
  exit 0
}

ENV=""; TAG=""; NAMESPACE=""; SERVICE="myapp"; DRY_RUN=false

while getopts ":e:t:n:s:dh" opt; do
  case $opt in
    e) ENV="$OPTARG" ;;
    t) TAG="$OPTARG" ;;
    n) NAMESPACE="$OPTARG" ;;
    s) SERVICE="$OPTARG" ;;
    d) DRY_RUN=true ;;
    h) usage ;;
    :) die "Option -${OPTARG} requires an argument" ;;
    \?) die "Unknown option: -${OPTARG}" ;;
  esac
done

[[ -z "$ENV" ]] && die "Environment (-e) is required"
[[ -z "$TAG" ]] && die "Image tag (-t) is required"
[[ "$ENV" =~ ^(dev|staging|prod)$ ]] || die "ENV must be dev|staging|prod"
NAMESPACE="${NAMESPACE:-$ENV}"

# ─── Config per environment ────────────────────────────────────────
case "$ENV" in
  dev)
    CLUSTER="dev-cluster"; REPLICAS=1
    DOMAIN="dev.myapp.example.com"; REGISTRY="${DOCKER_REGISTRY:-registry.example.com}"
    ;;
  staging)
    CLUSTER="staging-cluster"; REPLICAS=2
    DOMAIN="staging.myapp.example.com"; REGISTRY="${DOCKER_REGISTRY:-registry.example.com}"
    ;;
  prod)
    CLUSTER="prod-cluster"; REPLICAS=5
    DOMAIN="myapp.example.com"; REGISTRY="${DOCKER_REGISTRY:-registry.example.com}"
    ;;
esac

IMAGE="${REGISTRY}/${SERVICE}:${TAG}"

# ─── Cleanup / lock ────────────────────────────────────────────────
LOCK_DIR="/tmp/${SERVICE}-deploy.lock"

cleanup() {
  rm -rf "$LOCK_DIR"
  [[ $? -ne 0 ]] && error "Deploy failed. Logs: ${LOG_FILE}"
}

trap cleanup EXIT
mkdir "$LOCK_DIR" 2>/dev/null || die "Another deploy is running (lock: ${LOCK_DIR})"
echo $$ > "${LOCK_DIR}/pid"

# ─── Pre-flight ────────────────────────────────────────────────────
log "Pre-flight checks..."
for tool in kubectl helm docker jq; do
  command -v "$tool" &>/dev/null || die "Missing: $tool"
done

kubectl cluster-info &>/dev/null || die "Cannot reach Kubernetes cluster"

CURRENT_CONTEXT="$(kubectl config current-context)"
info "Cluster: ${CURRENT_CONTEXT}"
info "Image:   ${IMAGE}"
info "Env:     ${ENV} → namespace/${NAMESPACE}"
info "Service: ${SERVICE} (${REPLICAS} replicas)"

[[ "$ENV" == "prod" ]] && {
  warn "PRODUCTION DEPLOYMENT"
  printf "${RED}Type 'production' to confirm: ${NC}"; read -r confirm
  [[ "$confirm" == "production" ]] || die "Confirmation failed"
}

# ─── Capture rollback info ─────────────────────────────────────────
PREV_TAG=""
if kubectl get deployment "$SERVICE" -n "$NAMESPACE" &>/dev/null; then
  PREV_TAG="$(kubectl get deployment "$SERVICE" -n "$NAMESPACE" \
    -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)"
  info "Current tag: ${PREV_TAG}"
fi

# ─── Deploy ────────────────────────────────────────────────────────
if [[ "$DRY_RUN" == "true" ]]; then
  info "[DRY RUN] Would deploy ${IMAGE} to ${NAMESPACE}"
  helm upgrade --install "$SERVICE" ./charts/"$SERVICE" \
    --namespace "$NAMESPACE" --create-namespace \
    --set image.tag="$TAG" \
    --set replicaCount="$REPLICAS" \
    --dry-run
  exit 0
fi

log "Deploying ${SERVICE}:${TAG} to ${NAMESPACE}..."

helm upgrade --install "$SERVICE" ./charts/"$SERVICE" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  --set image.tag="$TAG" \
  --set image.repository="${REGISTRY}/${SERVICE}" \
  --set replicaCount="$REPLICAS" \
  --set ingress.host="$DOMAIN" \
  --wait \
  --timeout 5m \
  --atomic

# ─── Post-deploy verification ──────────────────────────────────────
log "Verifying deployment..."
sleep 5   # let pods stabilise

READY="$(kubectl get deployment "$SERVICE" -n "$NAMESPACE" \
  -o jsonpath='{.status.readyReplicas}')"
DESIRED="$(kubectl get deployment "$SERVICE" -n "$NAMESPACE" \
  -o jsonpath='{.spec.replicas}')"

[[ "$READY" == "$DESIRED" ]] \
  || die "Only ${READY}/${DESIRED} pods ready after deploy"

# Health check
if ! curl -sf --max-time 10 "https://${DOMAIN}/health" &>/dev/null; then
  warn "Health check failed at https://${DOMAIN}/health"
fi

info "Deployment complete!"
info "  Service:  ${SERVICE}"
info "  Tag:      ${TAG}"
info "  Env:      ${ENV}"
info "  URL:      https://${DOMAIN}"
[[ -n "$PREV_TAG" ]] && info "  Previous: ${PREV_TAG}"
info "  Logs:     ${LOG_FILE}"
```

## 2. cluster-health.py — Daily Health Reporter

```python
#!/usr/bin/env python3
"""
cluster-health.py — Kubernetes cluster health report
Runs as a CronJob, posts to Slack.

Usage: python cluster-health.py --namespace production --slack-webhook $WEBHOOK_URL
"""
import argparse, json, logging, os, sys, time
import subprocess, requests
from dataclasses import dataclass, field
from typing import Optional

logging.basicConfig(level=logging.INFO,
                    format="%(asctime)s [%(levelname)s] %(message)s")
log = logging.getLogger(__name__)


@dataclass
class HealthIssue:
    severity: str      # "critical" | "warning" | "info"
    component: str
    message: str


@dataclass
class ClusterHealth:
    namespace: str
    issues: list[HealthIssue] = field(default_factory=list)
    pod_total: int = 0
    pod_running: int = 0

    @property
    def is_healthy(self) -> bool:
        return not any(i.severity == "critical" for i in self.issues)

    @property
    def summary(self) -> str:
        if self.is_healthy:
            return f"Healthy — {self.pod_running}/{self.pod_total} pods running"
        critical = [i for i in self.issues if i.severity == "critical"]
        return f"DEGRADED — {len(critical)} critical issue(s)"


def run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return result.stdout


def check_pods(namespace: str) -> list[HealthIssue]:
    issues = []
    data = json.loads(run(["kubectl", "get", "pods", "-n", namespace, "-o", "json"]))
    for pod in data["items"]:
        name = pod["metadata"]["name"]
        phase = pod["status"].get("phase", "Unknown")
        container_statuses = pod["status"].get("containerStatuses", [])

        if phase not in ("Running", "Succeeded"):
            issues.append(HealthIssue("critical", f"pod/{name}",
                                      f"Phase is {phase}"))

        for cs in container_statuses:
            restarts = cs.get("restartCount", 0)
            if restarts > 10:
                issues.append(HealthIssue("critical", f"pod/{name}",
                                          f"Container {cs['name']} has {restarts} restarts"))
            elif restarts > 5:
                issues.append(HealthIssue("warning", f"pod/{name}",
                                          f"Container {cs['name']} has {restarts} restarts"))

            if not cs.get("ready") and phase == "Running":
                issues.append(HealthIssue("warning", f"pod/{name}",
                                          f"Container {cs['name']} not ready"))
    return issues


def check_deployments(namespace: str) -> list[HealthIssue]:
    issues = []
    data = json.loads(run(["kubectl", "get", "deployments", "-n", namespace, "-o", "json"]))
    for dep in data["items"]:
        name = dep["metadata"]["name"]
        desired  = dep["spec"]["replicas"]
        ready    = dep["status"].get("readyReplicas", 0)
        if ready < desired:
            sev = "critical" if ready == 0 else "warning"
            issues.append(HealthIssue(sev, f"deployment/{name}",
                                      f"Only {ready}/{desired} replicas ready"))
    return issues


def check_pvc(namespace: str) -> list[HealthIssue]:
    issues = []
    data = json.loads(run(["kubectl", "get", "pvc", "-n", namespace, "-o", "json"]))
    for pvc in data["items"]:
        name = pvc["metadata"]["name"]
        phase = pvc["status"]["phase"]
        if phase != "Bound":
            issues.append(HealthIssue("critical", f"pvc/{name}", f"Status is {phase}"))
    return issues


def build_report(namespace: str) -> ClusterHealth:
    health = ClusterHealth(namespace=namespace)

    pods_data = json.loads(run(["kubectl", "get", "pods", "-n", namespace, "-o", "json"]))
    health.pod_total   = len(pods_data["items"])
    health.pod_running = sum(1 for p in pods_data["items"]
                             if p["status"].get("phase") == "Running")

    health.issues.extend(check_pods(namespace))
    health.issues.extend(check_deployments(namespace))
    health.issues.extend(check_pvc(namespace))
    return health


def post_to_slack(webhook: str, health: ClusterHealth) -> None:
    color = "good" if health.is_healthy else "danger"
    fields = [{"title": i.component, "value": i.message, "short": False}
              for i in health.issues[:10]]  # Slack limit

    payload = {"attachments": [{
        "color": color,
        "title": f"Cluster Health: {health.namespace}",
        "text": health.summary,
        "fields": fields,
        "footer": "cluster-health.py",
        "ts": int(time.time()),
    }]}
    requests.post(webhook, json=payload).raise_for_status()


def main() -> int:
    parser = argparse.ArgumentParser(description="Kubernetes cluster health report")
    parser.add_argument("-n", "--namespace", default="production")
    parser.add_argument("--slack-webhook", envvar="SLACK_WEBHOOK")
    parser.add_argument("--fail-on-issues", action="store_true")
    args = parser.parse_args()

    health = build_report(args.namespace)

    if args.slack_webhook:
        post_to_slack(args.slack_webhook, health)
        log.info("Report posted to Slack")

    for issue in health.issues:
        level = log.error if issue.severity == "critical" else log.warning
        level("[%s] %s: %s", issue.severity.upper(), issue.component, issue.message)

    log.info(health.summary)
    return 1 if (args.fail_on_issues and not health.is_healthy) else 0


if __name__ == "__main__":
    sys.exit(main())
```

## 3. secret-rotation.py — Automated Secret Rotation

```python
#!/usr/bin/env python3
"""Rotate a database password in AWS Secrets Manager and restart K8s deployment."""
import os, sys, secrets, string, logging
import boto3, subprocess, time

log = logging.getLogger(__name__)

def generate_password(length: int = 32) -> str:
    alphabet = string.ascii_letters + string.digits + "!@#$%^&*"
    return "".join(secrets.choice(alphabet) for _ in range(length))

def rotate_rds_password(db_identifier: str, new_password: str) -> None:
    rds = boto3.client("rds")
    rds.modify_db_instance(
        DBInstanceIdentifier=db_identifier,
        MasterUserPassword=new_password,
        ApplyImmediately=True,
    )
    log.info("RDS password updated for %s", db_identifier)

    # Wait for RDS to be available again
    waiter = rds.get_waiter("db_instance_available")
    waiter.wait(DBInstanceIdentifier=db_identifier)
    log.info("RDS instance available again")

def update_secret(secret_name: str, username: str, password: str,
                  host: str) -> None:
    import json
    sm = boto3.client("secretsmanager")
    sm.put_secret_value(
        SecretId=secret_name,
        SecretString=json.dumps({
            "username": username,
            "password": password,
            "host": host,
        }),
    )
    log.info("Secrets Manager updated: %s", secret_name)

def restart_deployment(namespace: str, deployment: str) -> None:
    subprocess.run([
        "kubectl", "rollout", "restart",
        f"deployment/{deployment}", "-n", namespace,
    ], check=True)
    subprocess.run([
        "kubectl", "rollout", "status",
        f"deployment/{deployment}", "-n", namespace, "--timeout=120s",
    ], check=True)
    log.info("Deployment %s restarted in %s", deployment, namespace)

def main() -> int:
    DB_ID       = os.environ["RDS_DB_IDENTIFIER"]
    SECRET_NAME = os.environ["SECRET_NAME"]
    DB_USERNAME = os.environ["DB_USERNAME"]
    DB_HOST     = os.environ["DB_HOST"]
    NAMESPACE   = os.environ.get("K8S_NAMESPACE", "production")
    DEPLOYMENT  = os.environ.get("K8S_DEPLOYMENT", "myapp")

    new_password = generate_password(32)
    log.info("Rotating password for %s", DB_ID)

    rotate_rds_password(DB_ID, new_password)
    update_secret(SECRET_NAME, DB_USERNAME, new_password, DB_HOST)
    time.sleep(10)  # let ESO sync the new secret into K8s
    restart_deployment(NAMESPACE, DEPLOYMENT)

    log.info("Secret rotation complete")
    return 0

if __name__ == "__main__":
    logging.basicConfig(level=logging.INFO,
                        format="%(asctime)s [%(levelname)s] %(message)s")
    sys.exit(main())
```
