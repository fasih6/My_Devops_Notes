# Python DevOps Libraries

## boto3 — AWS Automation

```python
import boto3
import json
from botocore.exceptions import ClientError

# Session with explicit profile/region
session = boto3.Session(
    region_name="eu-central-1",
    profile_name=os.environ.get("AWS_PROFILE", "default"),
)

# EC2
ec2 = session.client("ec2")

def get_instances_by_tag(tag_key: str, tag_value: str) -> list[dict]:
    resp = ec2.describe_instances(Filters=[
        {"Name": f"tag:{tag_key}", "Values": [tag_value]},
        {"Name": "instance-state-name", "Values": ["running"]},
    ])
    instances = []
    for reservation in resp["Reservations"]:
        instances.extend(reservation["Instances"])
    return instances

# Paginator — handle AWS pagination automatically
def list_all_buckets() -> list[str]:
    s3 = session.client("s3")
    return [b["Name"] for b in s3.list_buckets()["Buckets"]]

def list_all_objects(bucket: str, prefix: str = "") -> list[str]:
    s3 = session.client("s3")
    paginator = s3.get_paginator("list_objects_v2")
    keys = []
    for page in paginator.paginate(Bucket=bucket, Prefix=prefix):
        keys.extend(obj["Key"] for obj in page.get("Contents", []))
    return keys

# SSM Parameter Store
def get_parameter(name: str, decrypt: bool = True) -> str:
    ssm = session.client("ssm")
    resp = ssm.get_parameter(Name=name, WithDecryption=decrypt)
    return resp["Parameter"]["Value"]

def put_parameter(name: str, value: str, param_type: str = "SecureString") -> None:
    ssm = session.client("ssm")
    ssm.put_parameter(
        Name=name, Value=value, Type=param_type, Overwrite=True
    )

# ECR — Docker image registry
def get_ecr_login_token() -> tuple[str, str]:
    ecr = session.client("ecr")
    token = ecr.get_authorization_token()["authorizationData"][0]
    import base64
    user, password = base64.b64decode(token["authorizationToken"]).decode().split(":")
    endpoint = token["proxyEndpoint"]
    return endpoint, password

# Secrets Manager
def get_secret(name: str) -> dict:
    sm = session.client("secretsmanager")
    try:
        resp = sm.get_secret_value(SecretId=name)
        return json.loads(resp["SecretString"])
    except ClientError as e:
        if e.response["Error"]["Code"] == "ResourceNotFoundException":
            raise KeyError(f"Secret not found: {name}") from e
        raise

# EKS — update kubeconfig
def update_kubeconfig(cluster_name: str) -> None:
    run(["aws", "eks", "update-kubeconfig",
         "--name", cluster_name,
         "--region", "eu-central-1"])
```

## kubernetes (Python client)

```python
from kubernetes import client, config, watch
from kubernetes.client.rest import ApiException

# Load config from kubeconfig or in-cluster
try:
    config.load_incluster_config()   # when running inside a pod
except config.ConfigException:
    config.load_kube_config()        # local development

v1     = client.CoreV1Api()
apps   = client.AppsV1Api()
batch  = client.BatchV1Api()
custom = client.CustomObjectsApi()

# List pods
def list_pods(namespace: str, label_selector: str = "") -> list:
    return v1.list_namespaced_pod(
        namespace=namespace,
        label_selector=label_selector,
    ).items

# Get deployment
def get_deployment(name: str, namespace: str):
    return apps.read_namespaced_deployment(name=name, namespace=namespace)

# Scale deployment
def scale_deployment(name: str, namespace: str, replicas: int) -> None:
    body = {"spec": {"replicas": replicas}}
    apps.patch_namespaced_deployment_scale(name=name, namespace=namespace, body=body)
    log.info("Scaled %s to %d replicas", name, replicas)

# Watch pod events in real time
def watch_pods(namespace: str, label_selector: str) -> None:
    w = watch.Watch()
    for event in w.stream(
        v1.list_namespaced_pod,
        namespace=namespace,
        label_selector=label_selector,
        timeout_seconds=120,
    ):
        pod = event["object"]
        log.info("[%s] %s → %s",
                 event["type"],
                 pod.metadata.name,
                 pod.status.phase)
        if pod.status.phase == "Running":
            w.stop()

# Create a secret
def create_or_update_secret(name: str, namespace: str, data: dict[str, str]) -> None:
    import base64
    b64_data = {k: base64.b64encode(v.encode()).decode() for k, v in data.items()}
    body = client.V1Secret(
        metadata=client.V1ObjectMeta(name=name, namespace=namespace),
        data=b64_data,
    )
    try:
        v1.create_namespaced_secret(namespace=namespace, body=body)
        log.info("Created secret %s", name)
    except ApiException as e:
        if e.status == 409:   # Already Exists
            v1.replace_namespaced_secret(name=name, namespace=namespace, body=body)
            log.info("Updated secret %s", name)
        else:
            raise

# Execute command in a pod
from kubernetes.stream import stream

def exec_in_pod(pod_name: str, namespace: str, command: list[str]) -> str:
    resp = stream(
        v1.connect_get_namespaced_pod_exec,
        pod_name,
        namespace,
        command=command,
        stderr=True, stdin=False, stdout=True, tty=False,
    )
    return resp
```

## requests — REST API Calls

```python
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry

def make_session(
    retries: int = 3,
    backoff: float = 0.5,
    base_url: str = "",
    token: str = "",
) -> requests.Session:
    """Create a requests session with retry logic and auth."""
    session = requests.Session()

    # Retry on connection errors and 5xx responses
    retry_strategy = Retry(
        total=retries,
        backoff_factor=backoff,
        status_forcelist=[500, 502, 503, 504],
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("https://", adapter)
    session.mount("http://", adapter)

    if token:
        session.headers["Authorization"] = f"Bearer {token}"
    session.headers["Content-Type"] = "application/json"

    return session


# Usage with GitLab API
gitlab = make_session(
    base_url="https://gitlab.example.com/api/v4",
    token=os.environ["GITLAB_TOKEN"],
)

def trigger_pipeline(project_id: int, ref: str, variables: dict = {}) -> dict:
    resp = gitlab.post(
        f"https://gitlab.example.com/api/v4/projects/{project_id}/pipeline",
        json={"ref": ref, "variables": [
            {"key": k, "value": v} for k, v in variables.items()
        ]},
    )
    resp.raise_for_status()
    return resp.json()

# Pagination helper
def get_all_pages(session: requests.Session, url: str, params: dict = {}) -> list:
    items = []
    page = 1
    while True:
        resp = session.get(url, params={**params, "page": page, "per_page": 100})
        resp.raise_for_status()
        data = resp.json()
        if not data:
            break
        items.extend(data)
        # GitLab-style: check X-Next-Page header
        if not resp.headers.get("X-Next-Page"):
            break
        page += 1
    return items
```

## fabric — SSH Automation

```python
from fabric import Connection, Config

# Connect to a remote server
conn = Connection(
    host="bastion.example.com",
    user="ubuntu",
    connect_kwargs={"key_filename": str(Path.home() / ".ssh" / "id_ed25519")},
)

# Run a command
result = conn.run("df -h /", hide=True)
print(result.stdout)

# Upload a file
conn.put("local-script.sh", "/tmp/script.sh")

# Download a file
conn.get("/var/log/app/error.log", "error.log")

# Sudo
conn.sudo("systemctl restart myapp")

# Chain of commands
def deploy_to_server(host: str, image_tag: str) -> None:
    with Connection(host=host, user="ubuntu") as c:
        c.run(f"docker pull registry.example.com/myapp:{image_tag}")
        c.run(f"docker stop myapp || true")
        c.run(f"docker rm myapp || true")
        c.run(
            f"docker run -d --name myapp "
            f"-p 8080:8080 "
            f"--env-file /etc/myapp/env "
            f"registry.example.com/myapp:{image_tag}"
        )
        c.run("docker ps | grep myapp")

# Run against multiple hosts
from fabric import ThreadingGroup
hosts = ["web1.example.com", "web2.example.com", "web3.example.com"]
group = ThreadingGroup(*hosts, user="ubuntu")
group.run("sudo systemctl reload nginx")
```

## rich — Beautiful Terminal Output

```python
from rich.console import Console
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TimeElapsedColumn
from rich.panel import Panel
from rich import print as rprint

console = Console()

# Coloured output
console.print("[green]Deployment successful[/green]")
console.print("[red]ERROR:[/red] Pod failed to start")
console.print("[yellow]WARNING:[/yellow] Low replica count")

# Table
def print_pod_table(pods: list) -> None:
    table = Table(title="Pod Status", show_header=True, header_style="bold blue")
    table.add_column("Name", style="cyan", no_wrap=True)
    table.add_column("Namespace")
    table.add_column("Status")
    table.add_column("Restarts", justify="right")
    table.add_column("Node")

    for pod in pods:
        status_style = "green" if pod.phase == "Running" else "red"
        table.add_row(
            pod.name,
            pod.namespace,
            f"[{status_style}]{pod.phase}[/{status_style}]",
            str(pod.restarts),
            pod.node,
        )
    console.print(table)

# Progress bar
def deploy_all_services(services: list[str]) -> None:
    with Progress(
        SpinnerColumn(),
        "[progress.description]{task.description}",
        TimeElapsedColumn(),
    ) as progress:
        task = progress.add_task("Deploying...", total=len(services))
        for service in services:
            progress.update(task, description=f"Deploying {service}...")
            deploy_service(service)
            progress.advance(task)

# Panel for important messages
console.print(Panel.fit(
    "[bold red]PRODUCTION DEPLOYMENT[/bold red]\n"
    f"Service: myapp\n"
    f"Tag: v1.2.3\n"
    f"Namespace: production",
    border_style="red",
))
```

## tenacity — Retry Library

More powerful than a hand-rolled retry decorator:

```python
from tenacity import (
    retry, stop_after_attempt, wait_exponential,
    retry_if_exception_type, before_sleep_log
)
import logging

@retry(
    stop=stop_after_attempt(5),
    wait=wait_exponential(multiplier=1, min=2, max=30),
    retry=retry_if_exception_type(subprocess.CalledProcessError),
    before_sleep=before_sleep_log(log, logging.WARNING),
)
def deploy_with_retry(namespace: str, manifest: Path) -> None:
    run(["kubectl", "apply", "-f", str(manifest)])
    run(["kubectl", "rollout", "status",
         f"deployment/{manifest.stem}",
         "-n", namespace, "--timeout=60s"])
```

## click — Better CLI Than argparse

```python
import click

@click.group()
@click.option("--verbose", is_flag=True, help="Verbose output")
@click.pass_context
def cli(ctx: click.Context, verbose: bool) -> None:
    ctx.ensure_object(dict)
    ctx.obj["verbose"] = verbose
    if verbose:
        logging.getLogger().setLevel(logging.DEBUG)

@cli.command()
@click.option("-e", "--env", required=True,
              type=click.Choice(["dev", "staging", "prod"]))
@click.option("-t", "--tag", required=True)
@click.option("--dry-run", is_flag=True)
@click.pass_context
def deploy(ctx: click.Context, env: str, tag: str, dry_run: bool) -> None:
    """Deploy a service to Kubernetes."""
    click.echo(f"Deploying {tag} to {env}")
    if dry_run:
        click.secho("[DRY RUN] Would deploy", fg="yellow")
        return
    # ... deployment logic ...

@cli.command()
@click.argument("deployment")
@click.option("-n", "--namespace", default="default")
def rollback(deployment: str, namespace: str) -> None:
    """Roll back a deployment."""
    if not click.confirm(f"Roll back {deployment} in {namespace}?"):
        raise click.Abort()
    run(["kubectl", "rollout", "undo", f"deployment/{deployment}", "-n", namespace])

if __name__ == "__main__":
    cli()
```
