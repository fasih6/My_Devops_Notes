# Python Core for DevOps Engineers

## The Ops Engineer's Python Mindset

You're not writing Django apps. You're writing tools. Key differences:
- Scripts run once and exit — no long-running state to manage
- Errors should be loud and descriptive — not silently swallowed
- The CLI is the interface — argparse is your framework
- External commands are called constantly — subprocess is your friend

## Script Template

```python
#!/usr/bin/env python3
"""
deploy.py — Deploy a service to Kubernetes

Usage:
    deploy.py -e staging -t v1.2.3
    deploy.py -e prod -t v1.2.3 --dry-run
"""

import argparse
import logging
import sys
from pathlib import Path

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%H:%M:%S",
)
log = logging.getLogger(__name__)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Deploy a service to Kubernetes",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument("-e", "--env", required=True,
                        choices=["dev", "staging", "prod"],
                        help="Target environment")
    parser.add_argument("-t", "--tag", required=True,
                        help="Docker image tag")
    parser.add_argument("-n", "--namespace",
                        help="Kubernetes namespace (default: same as env)")
    parser.add_argument("--dry-run", action="store_true",
                        help="Print actions without executing")
    parser.add_argument("-v", "--verbose", action="store_true",
                        help="Verbose output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()

    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)

    namespace = args.namespace or args.env
    log.info("Deploying to %s (namespace: %s, tag: %s)", args.env, namespace, args.tag)

    if args.dry_run:
        log.info("[DRY RUN] Would deploy %s to %s", args.tag, namespace)
        return 0

    # ... actual deployment logic ...
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

## subprocess — Running External Commands

```python
import subprocess
import shlex

def run(cmd: list[str] | str, **kwargs) -> subprocess.CompletedProcess:
    """Run a command, raise on failure, return CompletedProcess."""
    if isinstance(cmd, str):
        cmd = shlex.split(cmd)  # safe split — handles quoted args

    log.debug("Running: %s", " ".join(cmd))
    return subprocess.run(
        cmd,
        check=True,         # raises CalledProcessError on non-zero exit
        text=True,          # decode stdout/stderr as str (not bytes)
        capture_output=True,
    )


def run_stream(cmd: list[str]) -> int:
    """Run a command streaming output to terminal in real time."""
    log.debug("Running (streaming): %s", " ".join(cmd))
    proc = subprocess.Popen(cmd, text=True)
    proc.wait()
    return proc.returncode


def get_output(cmd: list[str] | str) -> str:
    """Run a command and return stdout as a stripped string."""
    result = run(cmd)
    return result.stdout.strip()


# Usage
try:
    result = run(["kubectl", "get", "pods", "-n", "production"])
    print(result.stdout)

except subprocess.CalledProcessError as e:
    log.error("Command failed (exit %d): %s", e.returncode, e.cmd)
    log.error("stderr: %s", e.stderr)
    sys.exit(1)

# Get a single value
current_context = get_output("kubectl config current-context")
image_tag = get_output(["docker", "inspect", "--format={{.Id}}", "myapp:latest"])
```

## pathlib — File Operations Done Right

```python
from pathlib import Path
import shutil

# Paths are objects, not strings
config_dir = Path.home() / ".myapp"
config_file = config_dir / "config.yaml"

# Create directories
config_dir.mkdir(parents=True, exist_ok=True)

# Read / write
text = config_file.read_text()
config_file.write_text("new content")

# Read lines
lines = config_file.read_text().splitlines()

# Check existence
if not config_file.exists():
    raise FileNotFoundError(f"Config not found: {config_file}")

# Glob patterns
manifests = list(Path("k8s/").glob("**/*.yaml"))
python_files = list(Path(".").rglob("*.py"))

# Atomic write (never leave partial file)
def atomic_write(path: Path, content: str) -> None:
    tmp = path.with_suffix(".tmp")
    tmp.write_text(content)
    tmp.rename(path)      # atomic on same filesystem

# Walk a directory tree
for yaml_file in Path("charts/").rglob("*.yaml"):
    log.info("Processing: %s", yaml_file)
    content = yaml_file.read_text()
    content = content.replace("TAG_PLACEHOLDER", image_tag)
    atomic_write(yaml_file, content)

# Copy with metadata
shutil.copy2(src, dst)       # copy file + metadata
shutil.copytree(src, dst)    # copy entire directory tree

# Temp directory (auto-cleaned)
import tempfile
with tempfile.TemporaryDirectory() as tmpdir:
    work = Path(tmpdir)
    shutil.copy(config_file, work / "config.yaml")
    run(["kubectl", "apply", "-f", str(work / "config.yaml")])
# tmpdir deleted automatically here
```

## json and yaml — Parsing Config Files

```python
import json
import yaml         # pip install pyyaml
from typing import Any

# JSON
def load_json(path: Path) -> Any:
    return json.loads(path.read_text())

def save_json(path: Path, data: Any, indent: int = 2) -> None:
    path.write_text(json.dumps(data, indent=indent))

# Pretty-print JSON to stdout
print(json.dumps(data, indent=2, default=str))  # default=str handles datetimes

# Parse JSON from a command
result = run(["kubectl", "get", "pods", "-o", "json"])
pods = json.loads(result.stdout)
pod_names = [p["metadata"]["name"] for p in pods["items"]]

# YAML
def load_yaml(path: Path) -> Any:
    return yaml.safe_load(path.read_text())   # safe_load prevents code execution

def load_yaml_all(path: Path) -> list[Any]:
    return list(yaml.safe_load_all(path.read_text()))  # multi-document YAML

def save_yaml(path: Path, data: Any) -> None:
    path.write_text(yaml.dump(data, default_flow_style=False))

# Manipulate a Helm values file
values = load_yaml(Path("values.yaml"))
values["image"]["tag"] = image_tag
values["replicaCount"] = 3
save_yaml(Path("values-modified.yaml"), values)
```

## argparse — Professional CLIs

```python
import argparse

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="k8s-helper",
        description="Kubernetes automation helper",
    )
    # Subcommands
    sub = parser.add_subparsers(dest="command", required=True)

    # deploy subcommand
    deploy = sub.add_parser("deploy", help="Deploy a service")
    deploy.add_argument("-e", "--env", required=True)
    deploy.add_argument("-t", "--tag", required=True)
    deploy.add_argument("--replicas", type=int, default=2)
    deploy.add_argument("--dry-run", action="store_true")

    # rollback subcommand
    rollback = sub.add_parser("rollback", help="Roll back a deployment")
    rollback.add_argument("deployment", help="Deployment name")
    rollback.add_argument("-n", "--namespace", default="default")

    # scale subcommand
    scale = sub.add_parser("scale", help="Scale a deployment")
    scale.add_argument("deployment")
    scale.add_argument("replicas", type=int)
    scale.add_argument("-n", "--namespace", default="default")

    # Global options
    parser.add_argument("--context", help="kubectl context override")
    parser.add_argument("-v", "--verbose", action="store_true")

    return parser

args = build_parser().parse_args()

match args.command:
    case "deploy":
        deploy_service(args.env, args.tag, args.replicas, args.dry_run)
    case "rollback":
        rollback_deployment(args.deployment, args.namespace)
    case "scale":
        scale_deployment(args.deployment, args.replicas, args.namespace)
```

## Error Handling Patterns

```python
import sys
from typing import NoReturn

class DeployError(Exception):
    """Deployment-specific error with optional exit code."""
    def __init__(self, message: str, exit_code: int = 1):
        super().__init__(message)
        self.exit_code = exit_code


def die(message: str, exit_code: int = 1) -> NoReturn:
    log.error(message)
    sys.exit(exit_code)


def require_env(name: str) -> str:
    """Get required environment variable or exit."""
    import os
    value = os.environ.get(name)
    if not value:
        die(f"Required environment variable not set: {name}")
    return value


# Context manager for cleanup
from contextlib import contextmanager

@contextmanager
def deployment_lock(name: str):
    lock_file = Path(f"/tmp/{name}.lock")
    if lock_file.exists():
        die(f"Deployment lock exists: {lock_file}. Is another deploy running?")
    try:
        lock_file.write_text(str(os.getpid()))
        yield
    finally:
        lock_file.unlink(missing_ok=True)

# Usage
with deployment_lock("myapp"):
    deploy_to_kubernetes(...)
```

## Retry Decorator

```python
import time
import functools
from typing import Callable, TypeVar

T = TypeVar("T")

def retry(
    attempts: int = 3,
    delay: float = 1.0,
    backoff: float = 2.0,
    exceptions: tuple = (Exception,),
):
    """Decorator: retry a function with exponential backoff."""
    def decorator(func: Callable[..., T]) -> Callable[..., T]:
        @functools.wraps(func)
        def wrapper(*args, **kwargs) -> T:
            current_delay = delay
            for attempt in range(1, attempts + 1):
                try:
                    return func(*args, **kwargs)
                except exceptions as e:
                    if attempt == attempts:
                        raise
                    log.warning(
                        "Attempt %d/%d failed: %s. Retrying in %.1fs...",
                        attempt, attempts, e, current_delay
                    )
                    time.sleep(current_delay)
                    current_delay *= backoff
        return wrapper
    return decorator


@retry(attempts=5, delay=2.0, exceptions=(subprocess.CalledProcessError,))
def apply_manifest(path: Path) -> None:
    run(["kubectl", "apply", "-f", str(path)])


@retry(attempts=10, delay=3.0)
def wait_for_endpoint(url: str) -> None:
    import urllib.request
    urllib.request.urlopen(url, timeout=5)
```

## Environment and Config Management

```python
import os
from dataclasses import dataclass, field
from typing import Optional

@dataclass
class Config:
    environment:  str
    image_tag:    str
    namespace:    str          = field(default="")
    registry:     str          = field(default="")
    replica_count: int         = field(default=2)
    dry_run:      bool         = field(default=False)

    def __post_init__(self):
        if not self.namespace:
            self.namespace = self.environment
        if not self.registry:
            self.registry = os.environ.get("DOCKER_REGISTRY", "registry.example.com")

    @classmethod
    def from_env(cls) -> "Config":
        """Load config from environment variables."""
        return cls(
            environment=require_env("ENVIRONMENT"),
            image_tag=require_env("IMAGE_TAG"),
            namespace=os.environ.get("NAMESPACE", ""),
            registry=os.environ.get("DOCKER_REGISTRY", ""),
            replica_count=int(os.environ.get("REPLICAS", "2")),
            dry_run=os.environ.get("DRY_RUN", "false").lower() == "true",
        )

# Usage
cfg = Config.from_env()
log.info("Config: %s", cfg)
```

## Structured Output with dataclasses

```python
from dataclasses import dataclass
from datetime import datetime
import json

@dataclass
class PodStatus:
    name:      str
    namespace: str
    phase:     str
    restarts:  int
    node:      str

    @property
    def is_healthy(self) -> bool:
        return self.phase == "Running" and self.restarts < 5

    def to_dict(self) -> dict:
        return {
            "name": self.name,
            "namespace": self.namespace,
            "phase": self.phase,
            "restarts": self.restarts,
            "node": self.node,
            "healthy": self.is_healthy,
        }


def get_pod_statuses(namespace: str) -> list[PodStatus]:
    result = run(["kubectl", "get", "pods", "-n", namespace, "-o", "json"])
    data = json.loads(result.stdout)

    statuses = []
    for item in data["items"]:
        containers = item.get("status", {}).get("containerStatuses", [{}])
        restarts = sum(c.get("restartCount", 0) for c in containers)
        statuses.append(PodStatus(
            name=item["metadata"]["name"],
            namespace=namespace,
            phase=item["status"].get("phase", "Unknown"),
            restarts=restarts,
            node=item["spec"].get("nodeName", "unknown"),
        ))
    return statuses


# Check health
pods = get_pod_statuses("production")
unhealthy = [p for p in pods if not p.is_healthy]
if unhealthy:
    log.error("Unhealthy pods found:")
    for pod in unhealthy:
        log.error("  %s (phase=%s, restarts=%d)", pod.name, pod.phase, pod.restarts)
    sys.exit(1)
```
