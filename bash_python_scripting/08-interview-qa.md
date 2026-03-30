# Scripting Interview Q&A

## Live Coding — What to Expect

Many DevOps interviews include a "write a script" task. Common formats:
- Write a bash script to check pod health across namespaces
- Write a Python script to automate an AWS/Kubernetes task
- Debug a broken script (find the bug)
- "How would you automate X?" — talk through an approach

The interviewer is testing: problem decomposition, error handling habits, code clarity, and whether you know the tools.

---

## Bash Questions

**Q: What does `set -euo pipefail` do and why is it important?**

- `-e`: Exit immediately when any command returns non-zero. Without this, bash silently continues after errors.
- `-u`: Treat unset variables as errors — catches typos like `$ENVIROMENT` (missing letter).
- `-o pipefail`: A pipeline like `cmd1 | cmd2` fails if *any* component fails, not just the last one. Without this, `false | true` succeeds.

Together they make bash behave like a strict language rather than a lenient shell that keeps going through failures. I put this at the top of every script.

---

**Q: Write a function to retry a command with exponential backoff.**

```bash
retry() {
  local attempts="$1"; shift
  local delay="$1";    shift
  local count=0

  until "$@"; do
    count=$(( count + 1 ))
    if (( count >= attempts )); then
      echo "ERROR: Failed after ${attempts} attempts: $*" >&2
      return 1
    fi
    echo "Attempt ${count}/${attempts} failed. Retrying in ${delay}s..."
    sleep "$delay"
    delay=$(( delay * 2 ))
  done
}

# Usage
retry 5 2 kubectl apply -f deployment.yaml
retry 3 5 curl -sf https://api.example.com/health
```

---

**Q: How do you safely handle a script that should only run one instance at a time?**

Use a lock directory — `mkdir` is atomic, unlike file creation:

```bash
LOCK_DIR="/tmp/my-script.lock"

cleanup() { rm -rf "$LOCK_DIR"; }
trap cleanup EXIT

if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "Another instance is running" >&2
  exit 1
fi
echo $$ > "${LOCK_DIR}/pid"
```

Why `mkdir` not `touch`? Creating a directory is atomic on POSIX filesystems. Two processes cannot both succeed in `mkdir` for the same path simultaneously.

---

**Q: What's wrong with this script?**

```bash
#!/bin/bash
FILES=$(ls /var/log/app/*.log)
for FILE in $FILES; do
  cat $FILE | grep ERROR | wc -l
done
```

Three problems:
1. No `set -euo pipefail` — errors silently ignored
2. Parsing `ls` output is unsafe — breaks on filenames with spaces or newlines
3. Useless use of `cat` — `grep ERROR "$FILE" | wc -l` or `grep -c ERROR "$FILE"`

Fixed version:
```bash
#!/usr/bin/env bash
set -euo pipefail

while IFS= read -r -d '' file; do
  count="$(grep -c ERROR "$file" || true)"
  echo "${file}: ${count} errors"
done < <(find /var/log/app -name '*.log' -print0)
```

---

**Q: How do you process a large file line by line without loading it into memory?**

```bash
while IFS= read -r line; do
  echo "Processing: $line"
done < /var/log/app/large.log

# Or from a command
while IFS= read -r pod; do
  kubectl logs "$pod" -n production --tail=10
done < <(kubectl get pods -n production -o name)
```

The `< <(...)` is process substitution — it lets you `while read` from a command's output without a subshell, which matters because variables set inside a `while` loop in a pipeline would otherwise be lost.

---

## Python Questions

**Q: How do you run external commands from Python safely?**

Use `subprocess.run` with `check=True` — never `os.system()`:

```python
import subprocess

# Good — raises on failure, captures output
result = subprocess.run(
    ["kubectl", "get", "pods", "-n", "production"],
    check=True,
    text=True,
    capture_output=True,
)
print(result.stdout)

# Never do this — no error handling, shell injection risk
os.system(f"kubectl get pods -n {namespace}")  # WRONG
```

The `shell=True` flag should almost never be used with untrusted input — it opens shell injection vulnerabilities.

---

**Q: Write a Python function to poll a URL until it returns 200, with a timeout.**

```python
import time, urllib.request, urllib.error

def wait_for_url(url: str, timeout: int = 60, interval: int = 5) -> bool:
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=3) as resp:
                if resp.status == 200:
                    return True
        except (urllib.error.URLError, OSError):
            pass
        time.sleep(interval)
    return False

if not wait_for_url("https://staging.myapp.com/health", timeout=120):
    print("Service did not become healthy in time")
    sys.exit(1)
```

---

**Q: How do you parse JSON output from kubectl in Python?**

```python
import json, subprocess

result = subprocess.run(
    ["kubectl", "get", "pods", "-n", "production", "-o", "json"],
    check=True, text=True, capture_output=True,
)
data = json.loads(result.stdout)

# Extract what you need
pod_names = [pod["metadata"]["name"] for pod in data["items"]]
crashlooping = [
    pod["metadata"]["name"]
    for pod in data["items"]
    if any(
        cs.get("restartCount", 0) > 5
        for cs in (pod.get("status", {}).get("containerStatuses") or [])
    )
]
```

---

**Q: What is the difference between `os.environ.get("KEY")` and `os.environ["KEY"]`?**

- `os.environ["KEY"]` raises `KeyError` if the variable is not set.
- `os.environ.get("KEY")` returns `None` (or a default).
- `os.environ.get("KEY", "default")` returns `"default"` if not set.

For required variables, I prefer to raise explicitly with a useful message:

```python
def require_env(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise SystemExit(f"ERROR: Required environment variable not set: {name}")
    return value

GITLAB_TOKEN = require_env("GITLAB_TOKEN")
```

---

**Q: How do you write an idempotent script?**

An idempotent script produces the same result whether run once or ten times.

Techniques:
1. Check before creating: `kubectl get ns X || kubectl create ns X`
2. Use `--dry-run=client` for preview
3. Use declarative tools (kubectl apply, helm upgrade --install) not imperative ones (kubectl create — fails if exists)
4. Write state to a file and skip if already done
5. Use `helm upgrade --install` — installs if not present, upgrades if present

Example:
```python
def ensure_namespace(name: str) -> None:
    result = subprocess.run(
        ["kubectl", "get", "namespace", name],
        capture_output=True,
    )
    if result.returncode == 0:
        log.info("Namespace %s already exists", name)
    else:
        subprocess.run(["kubectl", "create", "namespace", name], check=True)
        log.info("Created namespace %s", name)
```

---

**Q: Live coding — Write a script that checks all deployments in a namespace and reports which are not fully ready.**

```python
#!/usr/bin/env python3
import json, subprocess, sys

def check_deployments(namespace: str) -> int:
    result = subprocess.run(
        ["kubectl", "get", "deployments", "-n", namespace, "-o", "json"],
        check=True, capture_output=True, text=True,
    )
    data = json.loads(result.stdout)
    
    issues = []
    for dep in data["items"]:
        name    = dep["metadata"]["name"]
        desired = dep["spec"].get("replicas", 1)
        ready   = dep["status"].get("readyReplicas", 0)
        
        if ready < desired:
            issues.append(f"{name}: {ready}/{desired} ready")
    
    if issues:
        print(f"Degraded deployments in {namespace}:")
        for issue in issues:
            print(f"  {issue}")
        return 1
    else:
        print(f"All deployments healthy in {namespace}")
        return 0

if __name__ == "__main__":
    namespace = sys.argv[1] if len(sys.argv) > 1 else "default"
    sys.exit(check_deployments(namespace))
```

---

**Q: How do you handle secrets securely in a Python script?**

Never hardcode. Never print. Read from environment or a secrets manager:

```python
import os

# From environment (injected by CI/CD or Vault agent)
db_password = os.environ.get("DB_PASSWORD")
if not db_password:
    raise SystemExit("DB_PASSWORD not set")

# From AWS Secrets Manager
import boto3, json
def get_secret(name: str) -> dict:
    sm = boto3.client("secretsmanager")
    resp = sm.get_secret_value(SecretId=name)
    return json.loads(resp["SecretString"])

creds = get_secret("production/myapp/db")
db_password = creds["password"]

# NEVER do:
# print(f"Using password: {db_password}")   ← leaks to logs
# log.debug("Config: %s", vars())           ← dumps everything
```

---

## Architecture / Design Questions

**Q: When would you use Bash vs Python for a DevOps task?**

Bash when:
- Calling CLI tools (kubectl, helm, aws, git) — no parsing needed
- Simple file operations, text transforms
- CI/CD pipeline steps that chain tools together
- The script is under ~50 lines

Python when:
- Parsing structured data (JSON, YAML from APIs)
- Complex logic with many conditionals
- Error handling and retry logic matter
- The script will be reused or maintained by a team
- You need libraries (boto3, kubernetes-client, requests)
- The script is growing beyond ~50 lines

The hybrid is also valid: a bash script that calls a Python helper for the complex parts.

---

**Q: How do you test scripts before running in production?**

1. **Dry run mode** — `--dry-run` flag that prints actions without executing
2. **Test in lower environment** — always run against dev/staging first
3. **shellcheck** — static analysis for bash scripts (`shellcheck script.sh`)
4. **pytest** — unit test Python utility functions in isolation
5. **Docker** — run scripts in a container to test without affecting your machine
6. **bats** — bash test framework for testing bash scripts
7. **Review exit codes** — test that failures produce non-zero exits

```bash
# shellcheck catches common bash bugs
shellcheck -S warning deploy.sh

# Test in dry-run mode
DRY_RUN=true ./deploy.sh -e staging -t v1.2.3

# Unit test Python utilities
pytest tests/test_k8s_utils.py -v
```
