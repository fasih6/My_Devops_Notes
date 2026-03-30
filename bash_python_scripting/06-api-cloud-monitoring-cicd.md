# API Scripting

## REST API Patterns

```python
#!/usr/bin/env python3
"""Generic REST API client patterns for DevOps tooling."""
import os, time, json, logging
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

log = logging.getLogger(__name__)

class GitLabClient:
    def __init__(self, url: str, token: str):
        self.base = url.rstrip("/") + "/api/v4"
        self.s = requests.Session()
        self.s.headers["PRIVATE-TOKEN"] = token
        adapter = HTTPAdapter(max_retries=Retry(total=3, backoff_factor=1,
                              status_forcelist=[500,502,503,504]))
        self.s.mount("https://", adapter)

    def _get_all(self, path: str, params: dict = {}) -> list:
        """Paginate through all results."""
        results, page = [], 1
        while True:
            r = self.s.get(f"{self.base}{path}",
                           params={**params, "page": page, "per_page": 100})
            r.raise_for_status()
            data = r.json()
            if not data: break
            results.extend(data)
            if not r.headers.get("X-Next-Page"): break
            page += 1
        return results

    def get_pipelines(self, project_id: int, ref: str = "main") -> list:
        return self._get_all(f"/projects/{project_id}/pipelines",
                             {"ref": ref, "order_by": "id", "sort": "desc"})

    def trigger_pipeline(self, project_id: int, ref: str,
                         variables: dict = {}) -> dict:
        r = self.s.post(f"{self.base}/projects/{project_id}/pipeline",
                        json={"ref": ref, "variables": [
                            {"key": k, "value": v} for k,v in variables.items()
                        ]})
        r.raise_for_status()
        return r.json()

    def wait_for_pipeline(self, project_id: int, pipeline_id: int,
                          timeout: int = 600) -> str:
        deadline = time.time() + timeout
        while time.time() < deadline:
            r = self.s.get(f"{self.base}/projects/{project_id}/pipelines/{pipeline_id}")
            r.raise_for_status()
            status = r.json()["status"]
            if status in ("success", "failed", "canceled", "skipped"):
                return status
            log.info("Pipeline %d status: %s", pipeline_id, status)
            time.sleep(15)
        raise TimeoutError(f"Pipeline {pipeline_id} timed out after {timeout}s")

    def create_release(self, project_id: int, tag: str, notes: str) -> dict:
        r = self.s.post(f"{self.base}/projects/{project_id}/releases",
                        json={"tag_name": tag, "description": notes})
        r.raise_for_status()
        return r.json()

    def get_open_mrs(self, project_id: int) -> list:
        return self._get_all(f"/projects/{project_id}/merge_requests",
                             {"state": "opened"})


class GitHubClient:
    def __init__(self, token: str, org: str):
        self.org = org
        self.s = requests.Session()
        self.s.headers.update({
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        })

    def create_issue(self, repo: str, title: str, body: str,
                     labels: list = []) -> dict:
        r = self.s.post(
            f"https://api.github.com/repos/{self.org}/{repo}/issues",
            json={"title": title, "body": body, "labels": labels},
        )
        r.raise_for_status()
        return r.json()

    def dispatch_workflow(self, repo: str, workflow: str,
                          ref: str, inputs: dict = {}) -> None:
        r = self.s.post(
            f"https://api.github.com/repos/{self.org}/{repo}"
            f"/actions/workflows/{workflow}/dispatches",
            json={"ref": ref, "inputs": inputs},
        )
        r.raise_for_status()
```

## Webhook Server (Simple)

```python
#!/usr/bin/env python3
"""Simple webhook receiver for CI/CD triggers."""
import hmac, hashlib, json, logging
from http.server import HTTPServer, BaseHTTPRequestHandler

SECRET = os.environ["WEBHOOK_SECRET"].encode()

class WebhookHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)

        # Verify GitLab webhook signature
        token = self.headers.get("X-Gitlab-Token", "")
        if token != os.environ["WEBHOOK_SECRET"]:
            self.send_response(401)
            self.end_headers()
            return

        payload = json.loads(body)
        event = self.headers.get("X-Gitlab-Event", "")

        if event == "Push Hook":
            self.handle_push(payload)
        elif event == "Pipeline Hook":
            self.handle_pipeline(payload)

        self.send_response(200)
        self.end_headers()
        self.wfile.write(b"OK")

    def handle_push(self, payload: dict):
        ref = payload.get("ref", "")
        if ref == "refs/heads/main":
            log.info("Main branch push — triggering deployment")
            # trigger deploy logic here

    def log_message(self, fmt, *args):
        log.info(fmt, *args)

if __name__ == "__main__":
    server = HTTPServer(("0.0.0.0", 8080), WebhookHandler)
    log.info("Webhook server listening on :8080")
    server.serve_forever()
```

---

# Cloud Scripting

## AWS CLI Patterns

```bash
#!/usr/bin/env bash
set -euo pipefail

AWS="aws --region ${AWS_REGION:-eu-central-1}"

# Check caller identity (verify credentials work)
verify_aws_auth() {
  local identity
  identity="$($AWS sts get-caller-identity --query 'Arn' --output text)"
  log "AWS identity: ${identity}"
}

# Get an SSM parameter
get_param() { $AWS ssm get-parameter --name "$1" --with-decryption \
              --query 'Parameter.Value' --output text; }

# Put an SSM parameter
put_param() { $AWS ssm put-parameter --name "$1" --value "$2" \
              --type SecureString --overwrite; }

# Wait for EC2 instance to be running
wait_for_instance() {
  local instance_id="$1"
  log "Waiting for instance ${instance_id} to be running..."
  $AWS ec2 wait instance-running --instance-ids "$instance_id"
  log "Instance ${instance_id} is running"
}

# Get all running instances with a specific tag
get_tagged_instances() {
  local tag_key="$1" tag_value="$2"
  $AWS ec2 describe-instances \
    --filters "Name=tag:${tag_key},Values=${tag_value}" \
              "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' \
    --output text
}

# ECR login
ecr_login() {
  local account_id registry
  account_id="$($AWS sts get-caller-identity --query Account --output text)"
  registry="${account_id}.dkr.ecr.${AWS_REGION:-eu-central-1}.amazonaws.com"
  $AWS ecr get-login-password | docker login --username AWS --password-stdin "$registry"
  echo "$registry"
}

# Invalidate CloudFront distribution
invalidate_cdn() {
  local distribution_id="$1"
  local paths="${2:-/*}"
  $AWS cloudfront create-invalidation \
    --distribution-id "$distribution_id" \
    --paths "$paths" \
    --query 'Invalidation.Id' --output text
}

# S3 sync with checksum validation
sync_to_s3() {
  local src="$1" bucket="$2" prefix="${3:-}"
  $AWS s3 sync "$src" "s3://${bucket}/${prefix}" \
    --delete \
    --sse AES256 \
    --exact-timestamps
}
```

## Python: boto3 Common Patterns

```python
import boto3, json, time
from botocore.exceptions import ClientError

session = boto3.Session(region_name=os.environ.get("AWS_REGION", "eu-central-1"))

def wait_for_stack(stack_name: str, timeout: int = 600) -> str:
    """Wait for a CloudFormation stack operation to complete."""
    cf = session.client("cloudformation")
    deadline = time.time() + timeout
    while time.time() < deadline:
        stack = cf.describe_stacks(StackName=stack_name)["Stacks"][0]
        status = stack["StackStatus"]
        if status.endswith("_COMPLETE") or status.endswith("_FAILED"):
            return status
        log.info("Stack %s status: %s", stack_name, status)
        time.sleep(15)
    raise TimeoutError(f"Stack {stack_name} timed out")

def send_slack_alert(webhook_url: str, message: str, color: str = "good") -> None:
    """Send a formatted message to Slack."""
    import requests
    requests.post(webhook_url, json={
        "attachments": [{
            "color": color,
            "text": message,
            "footer": "deployment bot",
            "ts": int(time.time()),
        }]
    }).raise_for_status()

def rotate_secret(secret_name: str, new_value: str) -> None:
    sm = session.client("secretsmanager")
    sm.put_secret_value(SecretId=secret_name, SecretString=new_value)
    log.info("Rotated secret: %s", secret_name)
```

## Azure CLI Patterns

```bash
#!/usr/bin/env bash
set -euo pipefail

AZ="az"

# Login check
verify_az_auth() {
  $AZ account show --query "name" -o tsv || die "Not logged in to Azure"
}

# AKS credentials
get_aks_credentials() {
  local resource_group="$1" cluster_name="$2"
  $AZ aks get-credentials \
    --resource-group "$resource_group" \
    --name "$cluster_name" \
    --overwrite-existing
}

# Key Vault secret
get_kv_secret() {
  local vault="$1" name="$2"
  $AZ keyvault secret show --vault-name "$vault" --name "$name" \
    --query "value" -o tsv
}

set_kv_secret() {
  local vault="$1" name="$2" value="$3"
  $AZ keyvault secret set --vault-name "$vault" --name "$name" --value "$value"
}

# ACR login
acr_login() {
  local registry="$1"
  $AZ acr login --name "$registry"
  echo "${registry}.azurecr.io"
}
```

---

# Monitoring & Health Check Scripts

## Health Check Patterns

```bash
#!/usr/bin/env bash
set -euo pipefail

check_http() {
  local url="$1" expected="${2:-200}" timeout="${3:-10}"
  local actual
  actual="$(curl -sf -o /dev/null -w "%{http_code}" --max-time "$timeout" "$url")"
  [[ "$actual" == "$expected" ]] || { error "${url} returned ${actual} (expected ${expected})"; return 1; }
}

check_tcp() {
  local host="$1" port="$2" timeout="${3:-5}"
  timeout "$timeout" bash -c "cat < /dev/null > /dev/tcp/${host}/${port}" 2>/dev/null \
    || { error "Cannot connect to ${host}:${port}"; return 1; }
}

check_disk() {
  local path="${1:-/}" threshold="${2:-85}"
  local usage
  usage="$(df -h "$path" | awk 'NR==2{gsub(/%/,"",$5); print $5}')"
  (( usage < threshold )) \
    || { warn "Disk usage at ${usage}% on ${path} (threshold: ${threshold}%)"; return 1; }
}

check_pod_restarts() {
  local namespace="$1" threshold="${2:-10}"
  local high_restart_pods
  high_restart_pods="$(kubectl get pods -n "$namespace" -o json | jq -r \
    ".items[] | select(.status.containerStatuses[0].restartCount > ${threshold}) |
    .metadata.name")"
  [[ -z "$high_restart_pods" ]] \
    || { warn "High-restart pods:\n${high_restart_pods}"; return 1; }
}

# Full health report
health_report() {
  local namespace="${1:-production}"
  local failed=0

  echo "=== Health Report: $(date) ==="

  check_http "https://myapp.example.com/health"        || (( failed++ ))
  check_http "https://myapp.example.com/api/v1/status" || (( failed++ ))
  check_tcp  "postgres.internal" 5432                  || (( failed++ ))
  check_disk "/var/log" 80                             || (( failed++ ))
  check_pod_restarts "$namespace" 5                    || (( failed++ ))

  if (( failed == 0 )); then
    info "All checks passed"
  else
    error "${failed} health check(s) failed"
    return 1
  fi
}
```

## Log Analysis Script

```bash
#!/usr/bin/env bash
# Analyse application logs for error patterns

ERROR_PATTERNS=(
  "ERROR"
  "FATAL"
  "Exception"
  "panic:"
  "OOMKilled"
  "CrashLoopBackOff"
)

analyse_pod_logs() {
  local namespace="$1"
  local since="${2:-1h}"
  local results=()

  kubectl get pods -n "$namespace" -o name | while read -r pod; do
    for pattern in "${ERROR_PATTERNS[@]}"; do
      count="$(kubectl logs "$pod" -n "$namespace" --since="$since" 2>/dev/null \
               | grep -c "$pattern" || true)"
      if (( count > 0 )); then
        results+=("${pod}: ${count} occurrences of '${pattern}'")
      fi
    done
  done

  if (( ${#results[@]} > 0 )); then
    warn "Error patterns found in last ${since}:"
    printf '  %s\n' "${results[@]}"
  else
    info "No error patterns found in last ${since}"
  fi
}
```

---

# CI/CD Helper Scripts

## Release Script

```bash
#!/usr/bin/env bash
set -euo pipefail
# release.sh — Create a semantic version tag and push it

CURRENT_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")"
log "Current version: ${CURRENT_TAG}"

# Parse semantic version
IFS='.' read -r major minor patch <<< "${CURRENT_TAG#v}"

case "${BUMP_TYPE:-patch}" in
  major) major=$(( major + 1 )); minor=0; patch=0 ;;
  minor) minor=$(( minor + 1 )); patch=0 ;;
  patch) patch=$(( patch + 1 )) ;;
  *)     die "BUMP_TYPE must be major|minor|patch" ;;
esac

NEW_TAG="v${major}.${minor}.${patch}"
log "New version: ${NEW_TAG}"

# Generate changelog
CHANGELOG="$(git log "${CURRENT_TAG}..HEAD" --oneline --no-merges)"
[[ -n "$CHANGELOG" ]] || die "No commits since ${CURRENT_TAG}"

log "Commits in this release:"
echo "$CHANGELOG"

confirm "Tag ${NEW_TAG} and push?" || exit 0

git tag -a "$NEW_TAG" -m "Release ${NEW_TAG}

${CHANGELOG}"
git push origin "$NEW_TAG"

log "Tagged and pushed ${NEW_TAG}"
log "Pipeline triggered at: ${CI_PROJECT_URL:-<your-repo>}/-/pipelines"
```

## Pipeline Status Checker

```python
#!/usr/bin/env python3
"""Check GitLab pipeline status and notify on Slack."""
import os, sys, time, logging, requests

log = logging.getLogger(__name__)

def check_pipeline_and_notify(
    gitlab_url: str, project_id: int, pipeline_id: int,
    slack_webhook: str, timeout: int = 600,
) -> bool:
    token = os.environ["GITLAB_TOKEN"]
    headers = {"PRIVATE-TOKEN": token}
    api = f"{gitlab_url}/api/v4/projects/{project_id}/pipelines/{pipeline_id}"

    deadline = time.time() + timeout
    while time.time() < deadline:
        resp = requests.get(api, headers=headers)
        resp.raise_for_status()
        data = resp.json()
        status = data["status"]

        if status == "success":
            _notify(slack_webhook, f"Pipeline #{pipeline_id} passed", "good")
            return True
        elif status in ("failed", "canceled"):
            _notify(slack_webhook,
                    f"Pipeline #{pipeline_id} {status}: {data['web_url']}", "danger")
            return False

        log.info("Pipeline %d: %s", pipeline_id, status)
        time.sleep(20)

    _notify(slack_webhook, f"Pipeline #{pipeline_id} timed out", "warning")
    return False

def _notify(webhook: str, text: str, color: str) -> None:
    requests.post(webhook, json={"attachments": [{"color": color, "text": text}]})

if __name__ == "__main__":
    ok = check_pipeline_and_notify(
        os.environ["GITLAB_URL"],
        int(os.environ["CI_PROJECT_ID"]),
        int(os.environ["CI_PIPELINE_ID"]),
        os.environ["SLACK_WEBHOOK"],
    )
    sys.exit(0 if ok else 1)
```
