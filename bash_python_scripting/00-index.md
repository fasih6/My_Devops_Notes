# Scripting for DevOps — Index

## The Philosophy

DevOps scripting is not software engineering — it's **glue code**. The goal is to connect tools, automate repetitive tasks, and build guardrails around systems. You are not building a product; you are building leverage.

The best DevOps scripts are:
- **Short** — if it's over 300 lines, ask if Terraform, Ansible, or a proper tool should do this
- **Idempotent** — running it twice produces the same result as running it once
- **Loud on failure** — explicit error handling, clear messages, non-zero exit codes
- **Self-documenting** — `--help` flag, usage examples in the header comment

## Bash vs Python — When to Use Which

```
Use BASH when:                          Use PYTHON when:
────────────────────────────────────    ────────────────────────────────────
Calling CLI tools (kubectl, aws, git)   Parsing JSON/YAML/complex data
File operations, simple transforms      Talking to REST APIs
CI/CD pipeline steps                    Complex logic (loops, classes)
One-shot automation                     Reusable libraries / modules
System administration tasks             Error handling matters a lot
Shell script already exists             You need retry logic, backoff
< 50 lines                              > 50 lines or growing
```

Practical rule: if you reach for `python3 -c` inside a bash script to parse JSON, it's time to write a Python script.

## Folder Contents

| File | What you'll learn |
|------|------------------|
| `01-bash-core.md` | Functions, error handling, flags, traps, advanced patterns |
| `02-bash-patterns.md` | Real DevOps patterns: retries, locks, logging, wait loops |
| `03-python-core.md` | Python idioms ops engineers actually use: subprocess, pathlib, argparse |
| `04-python-devops-libs.md` | boto3, kubernetes-client, requests, fabric, rich |
| `05-k8s-automation.md` | Scripting against kubectl and the K8s Python client |
| `06-api-scripting.md` | REST APIs, GitHub/GitLab APIs, pagination, auth |
| `07-cloud-scripting.md` | AWS CLI + boto3, az CLI, cloud automation patterns |
| `08-monitoring-scripts.md` | Health checks, log analysis, alert scripts |
| `09-ci-cd-scripting.md` | Pipeline helper scripts, release scripts, changelog gen |
| `10-real-world-scripts.md` | Full production-grade scripts with comments |
| `11-interview-qa.md` | Scripting questions and live-coding style answers |
| `scripts/` | Runnable `.sh` and `.py` files you can use immediately |

## Quick Reference — Patterns You'll Use Every Day

### Bash
```bash
set -euo pipefail                        # always at the top
log()  { echo "[$(date '+%H:%M:%S')] $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }
require() { command -v "$1" &>/dev/null || die "$1 is not installed"; }
```

### Python
```python
import subprocess, sys, logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger(__name__)

def run(cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw)
```

## Learning Order

1. `01-bash-core` → `02-bash-patterns` (Bash foundation + real patterns)
2. `03-python-core` → `04-python-devops-libs` (Python for ops)
3. `05` through `09` (domain-specific: K8s, cloud, APIs, CI/CD)
4. `10-real-world-scripts` (see it all come together)
5. `11-interview-qa` (before interviews)
