# Kubernetes Automation Scripting

## kubectl One-Liners (Building Blocks)

These short commands are the atoms of K8s automation scripts.

```bash
# Get resource names only
kubectl get pods -n prod -o name
kubectl get deployments -A -o jsonpath='{.items[*].metadata.name}'

# Watch a rollout live
kubectl rollout status deployment/myapp -n prod --timeout=120s

# Get image tag from a deployment
kubectl get deployment myapp -n prod \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Restart a deployment (rolling restart)
kubectl rollout restart deployment/myapp -n prod

# Get all pods NOT in Running state (stuck/crashlooping)
kubectl get pods -A --field-selector=status.phase!=Running

# Get pods with high restart count
kubectl get pods -A -o json | jq -r '
  .items[]
  | select(.status.containerStatuses[0].restartCount > 5)
  | "\(.metadata.namespace)/\(.metadata.name): \(.status.containerStatuses[0].restartCount) restarts"
'

# Get resource usage (requires metrics-server)
kubectl top pods -n prod --sort-by=memory

# Get events for a specific namespace, sorted by time
kubectl get events -n prod --sort-by='.lastTimestamp'

# Exec into a pod
kubectl exec -it $(kubectl get pod -l app=myapp -n prod -o name | head -1) \
  -n prod -- /bin/sh

# Port-forward in background
kubectl port-forward svc/myapp 8080:80 -n prod &
PF_PID=$!
trap "kill $PF_PID" EXIT

# Copy files from/to pod
kubectl cp prod/myapp-abc123:/var/log/app.log ./app.log
kubectl cp ./config.json prod/myapp-abc123:/tmp/config.json
```

## Bash: kubectl Automation Patterns

```bash
#!/usr/bin/env bash
set -euo pipefail

# Wait until all pods in a deployment are ready
wait_for_deployment() {
  local deployment="$1"
  local namespace="${2:-default}"
  local timeout="${3:-300}"

  log "Waiting for ${deployment} in ${namespace}..."
  kubectl rollout status deployment/"$deployment" \
    -n "$namespace" \
    --timeout="${timeout}s"
}

# Get the first ready pod matching a label
get_ready_pod() {
  local label="$1"
  local namespace="${2:-default}"

  kubectl get pods -n "$namespace" -l "$label" \
    --field-selector=status.phase=Running \
    -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Apply manifests from a directory with dry-run support
apply_manifests() {
  local dir="$1"
  local namespace="$2"
  local dry_run="${3:-false}"

  local dry_run_flag=""
  [[ "$dry_run" == "true" ]] && dry_run_flag="--dry-run=client"

  for manifest in "${dir}"/*.yaml; do
    log "Applying: $(basename "$manifest")"
    kubectl apply -f "$manifest" \
      -n "$namespace" \
      $dry_run_flag
  done
}

# Check if a CRD exists
crd_exists() {
  kubectl get crd "$1" &>/dev/null
}

# Drain a node safely before maintenance
drain_node() {
  local node="$1"
  local grace_period="${2:-60}"

  warn "Draining node: ${node}"
  kubectl drain "$node" \
    --ignore-daemonsets \
    --delete-emptydir-data \
    --grace-period="$grace_period" \
    --timeout=300s

  log "Node ${node} drained. Uncordon with: kubectl uncordon ${node}"
}

# Rolling restart of all deployments in a namespace
rolling_restart_namespace() {
  local namespace="$1"

  kubectl get deployments -n "$namespace" -o name | while read -r dep; do
    log "Restarting ${dep}..."
    kubectl rollout restart "$dep" -n "$namespace"
    kubectl rollout status "$dep" -n "$namespace" --timeout=120s
  done
}
```

## Python: Full K8s Automation Class

```python
#!/usr/bin/env python3
"""
k8s_manager.py — Kubernetes automation utilities
"""
import json
import logging
import time
from dataclasses import dataclass
from kubernetes import client, config, watch
from kubernetes.client.rest import ApiException

log = logging.getLogger(__name__)


class K8sManager:
    """High-level Kubernetes automation interface."""

    def __init__(self, namespace: str = "default", context: str = ""):
        if context:
            config.load_kube_config(context=context)
        else:
            try:
                config.load_incluster_config()
            except config.ConfigException:
                config.load_kube_config()

        self.namespace = namespace
        self.v1    = client.CoreV1Api()
        self.apps  = client.AppsV1Api()
        self.batch = client.BatchV1Api()

    # ─── Deployments ────────────────────────────────────────────

    def get_deployment_image(self, name: str) -> str:
        dep = self.apps.read_namespaced_deployment(name, self.namespace)
        return dep.spec.template.spec.containers[0].image

    def set_deployment_image(self, name: str, image: str) -> None:
        """Update container image and trigger rolling update."""
        patch = {"spec": {"template": {"spec": {
            "containers": [{"name": name, "image": image}]
        }}}}
        self.apps.patch_namespaced_deployment(name, self.namespace, patch)
        log.info("Updated %s image to %s", name, image)

    def scale(self, name: str, replicas: int) -> None:
        body = {"spec": {"replicas": replicas}}
        self.apps.patch_namespaced_deployment_scale(name, self.namespace, body)
        log.info("Scaled %s to %d replicas", name, replicas)

    def rollout_restart(self, name: str) -> None:
        from datetime import datetime, timezone
        patch = {"spec": {"template": {"metadata": {"annotations": {
            "kubectl.kubernetes.io/restartedAt":
                datetime.now(timezone.utc).isoformat()
        }}}}}
        self.apps.patch_namespaced_deployment(name, self.namespace, patch)
        log.info("Triggered rolling restart for %s", name)

    def wait_for_rollout(self, name: str, timeout: int = 120) -> bool:
        """Wait until deployment rollout is complete. Returns True on success."""
        deadline = time.time() + timeout
        while time.time() < deadline:
            dep = self.apps.read_namespaced_deployment(name, self.namespace)
            status = dep.status
            desired  = dep.spec.replicas or 1
            ready    = status.ready_replicas or 0
            updated  = status.updated_replicas or 0
            available = status.available_replicas or 0

            log.debug("%s: desired=%d ready=%d updated=%d available=%d",
                      name, desired, ready, updated, available)

            if (ready == desired and updated == desired
                    and available == desired):
                log.info("Rollout complete: %s", name)
                return True

            time.sleep(5)

        log.error("Rollout timed out after %ds: %s", timeout, name)
        return False

    def rollback(self, name: str) -> None:
        """Roll back to previous deployment revision."""
        import subprocess
        subprocess.run(
            ["kubectl", "rollout", "undo", f"deployment/{name}",
             "-n", self.namespace],
            check=True,
        )
        log.info("Rolled back %s", name)

    # ─── Pods ────────────────────────────────────────────────────

    def list_pods(self, label_selector: str = "") -> list:
        return self.v1.list_namespaced_pod(
            self.namespace,
            label_selector=label_selector,
        ).items

    def get_pod_logs(self, pod_name: str, container: str = "",
                     tail: int = 100) -> str:
        return self.v1.read_namespaced_pod_log(
            pod_name, self.namespace,
            container=container or None,
            tail_lines=tail,
        )

    def get_crashlooping_pods(self) -> list:
        pods = self.list_pods()
        return [
            p for p in pods
            if any(
                cs.restart_count > 5
                for cs in (p.status.container_statuses or [])
            )
        ]

    # ─── Secrets ─────────────────────────────────────────────────

    def get_secret(self, name: str) -> dict[str, str]:
        import base64
        secret = self.v1.read_namespaced_secret(name, self.namespace)
        return {
            k: base64.b64decode(v).decode()
            for k, v in (secret.data or {}).items()
        }

    def upsert_secret(self, name: str, data: dict[str, str]) -> None:
        import base64
        b64_data = {
            k: base64.b64encode(v.encode()).decode()
            for k, v in data.items()
        }
        body = client.V1Secret(
            metadata=client.V1ObjectMeta(name=name, namespace=self.namespace),
            data=b64_data,
        )
        try:
            self.v1.create_namespaced_secret(self.namespace, body)
            log.info("Created secret %s", name)
        except ApiException as e:
            if e.status == 409:
                self.v1.replace_namespaced_secret(name, self.namespace, body)
                log.info("Updated secret %s", name)
            else:
                raise

    # ─── ConfigMaps ──────────────────────────────────────────────

    def upsert_configmap(self, name: str, data: dict[str, str]) -> None:
        body = client.V1ConfigMap(
            metadata=client.V1ObjectMeta(name=name, namespace=self.namespace),
            data=data,
        )
        try:
            self.v1.create_namespaced_config_map(self.namespace, body)
        except ApiException as e:
            if e.status == 409:
                self.v1.replace_namespaced_config_map(name, self.namespace, body)
            else:
                raise


# ─── Usage example ───────────────────────────────────────────────

def main():
    k8s = K8sManager(namespace="production")

    # Deploy new image
    new_image = f"registry.example.com/myapp:{os.environ['IMAGE_TAG']}"
    k8s.set_deployment_image("myapp", new_image)

    # Wait for rollout
    if not k8s.wait_for_rollout("myapp", timeout=180):
        log.error("Rollout failed — rolling back")
        k8s.rollback("myapp")
        sys.exit(1)

    # Check for crashlooping pods post-deploy
    crashers = k8s.get_crashlooping_pods()
    if crashers:
        for pod in crashers:
            log.error("Crashlooping pod: %s", pod.metadata.name)
            log.error(k8s.get_pod_logs(pod.metadata.name, tail=50))
        sys.exit(1)

    log.info("Deployment complete and healthy")
```

## Helm Scripting

```bash
#!/usr/bin/env bash
set -euo pipefail

# Install or upgrade (idempotent)
helm_deploy() {
  local release="$1"
  local chart="$2"
  local namespace="$3"
  local values_file="${4:-values.yaml}"
  shift 4
  local extra_args=("$@")

  if helm status "$release" -n "$namespace" &>/dev/null; then
    ACTION="upgrade"
  else
    ACTION="install"
  fi

  log "Helm ${ACTION}: ${release} (chart: ${chart}, ns: ${namespace})"
  helm "$ACTION" "$release" "$chart" \
    --namespace "$namespace" \
    --create-namespace \
    --values "$values_file" \
    --wait \
    --timeout 5m \
    --atomic \          # roll back automatically on failure
    "${extra_args[@]}"
}

# Diff before applying (requires helm-diff plugin)
helm_diff() {
  local release="$1"
  local chart="$2"
  local namespace="$3"
  local values_file="${4:-values.yaml}"

  helm diff upgrade "$release" "$chart" \
    --namespace "$namespace" \
    --values "$values_file" \
    --allow-unreleased
}

# Usage
helm_deploy myapp ./charts/myapp production values-prod.yaml \
  --set image.tag="$IMAGE_TAG" \
  --set replicaCount=3
```

## Multi-Cluster Automation

```bash
#!/usr/bin/env bash
set -euo pipefail

CLUSTERS=(
  "prod-eu-central-1:eu-central-1:production"
  "prod-eu-west-1:eu-west-1:production"
  "staging:eu-central-1:staging"
)

deploy_to_cluster() {
  local cluster_name="$1"
  local region="$2"
  local namespace="$3"

  log "Deploying to cluster: ${cluster_name}"

  # Switch context
  aws eks update-kubeconfig \
    --name "$cluster_name" \
    --region "$region" \
    --alias "$cluster_name" \
    &>/dev/null

  kubectl config use-context "$cluster_name"

  # Deploy
  helm upgrade --install myapp ./charts/myapp \
    --namespace "$namespace" \
    --set image.tag="$IMAGE_TAG" \
    --wait --timeout 5m

  log "Cluster ${cluster_name}: deployment complete"
}

# Deploy to all clusters
for entry in "${CLUSTERS[@]}"; do
  IFS=':' read -r cluster region namespace <<< "$entry"
  deploy_to_cluster "$cluster" "$region" "$namespace"
done
```
