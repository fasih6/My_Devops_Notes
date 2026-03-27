# ⛵ Helm Core Concepts

A deeper look at how Helm works — beyond basic install and upgrade commands.

> This file goes deeper than the Helm overview in the Kubernetes folder. If you're new to Helm, start with `kubernetes/07-k8s-helm.md` first.

---

## 📚 Table of Contents

- [1. How Helm Works Internally](#1-how-helm-works-internally)
- [2. Release Lifecycle](#2-release-lifecycle)
- [3. Helm Storage Backend](#3-helm-storage-backend)
- [4. Repository Management](#4-repository-management)
- [5. Values Hierarchy & Merging](#5-values-hierarchy--merging)
- [6. Chart Versioning](#6-chart-versioning)
- [7. Helm 3 vs Helm 2 Differences](#7-helm-3-vs-helm-2-differences)
- [8. Helm Environment Variables & Config](#8-helm-environment-variables--config)
- [Cheatsheet](#cheatsheet)

---

## 1. How Helm Works Internally

### What happens when you run `helm install`

```
helm install my-app ./my-chart --values prod.yaml
         │
         ▼
1. Helm loads the chart (Chart.yaml, templates/, values.yaml)
         │
         ▼
2. Merges values (values.yaml + user values files + --set flags)
         │
         ▼
3. Renders templates using Go template engine + Sprig functions
   (produces plain Kubernetes YAML manifests)
         │
         ▼
4. Validates rendered manifests against Kubernetes API schemas
         │
         ▼
5. Sends manifests to Kubernetes API server via kubectl-equivalent
         │
         ▼
6. Stores release metadata (name, chart, values, manifest) in a
   Kubernetes Secret in the target namespace
         │
         ▼
7. Returns success/failure to the user
```

### Helm is a client-only tool

Helm 3 has **no server-side component** (unlike Helm 2 which had Tiller). Helm talks directly to the Kubernetes API server using your kubeconfig credentials.

```bash
# Helm uses the same kubeconfig as kubectl
echo $KUBECONFIG
kubectl config current-context
helm list    # uses same context
```

---

## 2. Release Lifecycle

### Release states

| State | Meaning |
|-------|---------|
| `deployed` | Successfully installed, currently active |
| `failed` | Last operation failed |
| `pending-install` | Install in progress |
| `pending-upgrade` | Upgrade in progress |
| `pending-rollback` | Rollback in progress |
| `superseded` | Replaced by a newer revision |
| `uninstalling` | Uninstall in progress |

### Release revisions

Every install and upgrade creates a new revision. Revisions are immutable — they record exactly what was deployed.

```bash
# View release history
helm history my-app
# REVISION  UPDATED                  STATUS     CHART          APP VERSION  DESCRIPTION
# 1         Mon Jan 15 10:00:00 2024 superseded my-app-1.0.0  v1.0.0       Install complete
# 2         Mon Jan 15 11:00:00 2024 superseded my-app-1.0.1  v1.1.0       Upgrade complete
# 3         Mon Jan 15 12:00:00 2024 deployed   my-app-1.0.1  v1.1.0       Rollback to 2

# Get details of a specific revision
helm get all my-app --revision 2
helm get values my-app --revision 2
helm get manifest my-app --revision 2
```

### Atomic installs

```bash
# --atomic: rollback automatically if install/upgrade fails
helm install my-app ./my-chart --atomic --timeout 5m

# --wait: wait until all resources are ready before returning
helm install my-app ./my-chart --wait --timeout 10m

# --cleanup-on-fail: delete newly created resources on upgrade failure
helm upgrade my-app ./my-chart --cleanup-on-fail
```

---

## 3. Helm Storage Backend

Helm 3 stores all release metadata as **Kubernetes Secrets** in the release namespace.

```bash
# List release secrets
kubectl get secrets -n production | grep helm
# sh.helm.release.v1.my-app.v1     helm.sh/release.v1   1      5d
# sh.helm.release.v1.my-app.v2     helm.sh/release.v1   1      4d
# sh.helm.release.v1.my-app.v3     helm.sh/release.v1   1      1d

# Each secret contains compressed, base64-encoded release data
# (chart templates, values, rendered manifests, metadata)

# Decode a release secret to see what's inside
kubectl get secret sh.helm.release.v1.my-app.v3 -n production \
  -o jsonpath='{.data.release}' | base64 -d | base64 -d | gzip -d | jq .
```

### Why this matters

- Release history is stored in Kubernetes — survives Helm client reinstalls
- RBAC controls who can see/modify release history (Secret access)
- Deleting these secrets corrupts the release history

### Controlling history size

```bash
# Limit revisions kept (default: 10)
helm install my-app ./my-chart --history-max 5
helm upgrade my-app ./my-chart --history-max 5

# Or set globally in helm config
helm env HELM_MAX_HISTORY
```

---

## 4. Repository Management

### Working with repositories

```bash
# Add repositories
helm repo add stable         https://charts.helm.sh/stable
helm repo add bitnami        https://charts.bitnami.com/bitnami
helm repo add ingress-nginx  https://kubernetes.github.io/ingress-nginx
helm repo add prometheus     https://prometheus-community.github.io/helm-charts
helm repo add jetstack       https://charts.jetstack.io
helm repo add grafana        https://grafana.github.io/helm-charts
helm repo add argo           https://argoproj.github.io/argo-helm
helm repo add external-secrets https://charts.external-secrets.io

# Update all repos (like apt update)
helm repo update

# Update specific repo
helm repo update bitnami

# List configured repos
helm repo list

# Remove a repo
helm repo remove stable

# Repo index location
ls ~/.config/helm/repositories.yaml
ls ~/.cache/helm/repository/
```

### Searching for charts

```bash
# Search configured repos
helm search repo nginx
helm search repo nginx --versions      # all versions
helm search repo nginx --version ">=4.0.0"

# Search Artifact Hub (public index of all helm repos)
helm search hub nginx
helm search hub postgresql --max-col-width 80

# Show all versions of a specific chart
helm search repo ingress-nginx/ingress-nginx --versions | head -20

# Show chart information
helm show chart bitnami/postgresql
helm show values bitnami/postgresql          # all default values
helm show values bitnami/postgresql > postgresql-defaults.yaml
helm show readme bitnami/postgresql
helm show all bitnami/postgresql             # everything
```

### Pulling charts locally

```bash
# Pull chart tarball
helm pull bitnami/postgresql
helm pull bitnami/postgresql --version 12.5.6
helm pull bitnami/postgresql --untar          # extract immediately
helm pull bitnami/postgresql --untar --untardir ./charts/

# Useful for: inspecting before install, air-gapped environments, vendoring
```

---

## 5. Values Hierarchy & Merging

Understanding exactly how values are merged is critical for debugging unexpected behavior.

### Precedence (lowest to highest)

```
1. Chart's values.yaml (lowest — defaults)
2. Parent chart's values.yaml (if subchart)
3. values files passed with -f / --values (left to right)
4. --set-string flags
5. --set flags
6. --set-json flags (highest — always wins)
```

```bash
# Later -f files override earlier ones
helm install my-app ./chart \
  -f base-values.yaml \       # loaded first
  -f prod-values.yaml \       # overrides base
  --set image.tag=v1.2.3      # overrides both files
```

### Merging behavior

```yaml
# values.yaml (base)
config:
  database:
    host: localhost
    port: 5432
    name: myapp
  cache:
    enabled: true
    host: redis

# prod-values.yaml (override)
config:
  database:
    host: prod-db.internal    # overrides host
    # port and name are KEPT from base (deep merge)
  # cache is KEPT entirely from base (not mentioned)
```

### --set syntax reference

```bash
# Simple value
--set key=value
--set replicaCount=3

# Nested value (dot notation)
--set image.tag=v1.2.3
--set config.database.host=prod-db

# List values (index notation)
--set servers[0].host=server1
--set servers[0].port=8080

# Multiple list items
--set servers[0]=server1,servers[1]=server2

# Value with comma (use --set-string or escape)
--set "key=value1\,value2"
--set-string "key=value1,value2"

# JSON value
--set-json 'annotations={"prometheus.io/scrape":"true"}'

# Null (delete a key)
--set key=null
```

### Viewing merged values

```bash
# See what values would be used (before install)
helm install my-app ./chart -f prod.yaml --debug --dry-run 2>&1 | grep -A100 "USER-SUPPLIED VALUES"

# See values of installed release
helm get values my-app                    # user-supplied only
helm get values my-app --all             # all values including defaults
```

---

## 6. Chart Versioning

### Semantic versioning in Helm

```yaml
# Chart.yaml
version: 2.1.3        # chart version — increment when chart changes
appVersion: "v1.5.0"  # app version — what's being packaged (informational)
```

| Change | Version bump |
|--------|-------------|
| Breaking change to values interface | Major (2.0.0 → 3.0.0) |
| New feature, backward compatible | Minor (2.1.0 → 2.2.0) |
| Bug fix, no interface change | Patch (2.1.2 → 2.1.3) |

### Version constraints in requirements

```yaml
# requirements.yaml / Chart.yaml dependencies
dependencies:
  - name: postgresql
    version: ">=12.0.0 <13.0.0"   # range
    repository: https://charts.bitnami.com/bitnami

  - name: redis
    version: "~17.3.0"             # ~: patch-level changes (17.3.x)
    repository: https://charts.bitnami.com/bitnami

  - name: ingress-nginx
    version: "^4.0.0"              # ^: minor-level changes (4.x.x)
    repository: https://kubernetes.github.io/ingress-nginx
```

### Chart lock file

```bash
# Chart.lock — locks exact versions (like package-lock.json)
helm dependency update ./my-chart
# Creates Chart.lock with exact versions resolved

# Install using lock file (reproducible builds)
helm dependency build ./my-chart
```

---

## 7. Helm 3 vs Helm 2 Differences

| Feature | Helm 2 | Helm 3 |
|---------|--------|--------|
| **Server component** | Tiller (server-side) | None (client-only) |
| **Security** | Tiller had full cluster access | Uses user's RBAC permissions |
| **Release storage** | ConfigMaps in kube-system | Secrets in release namespace |
| **Namespaces** | Cluster-wide releases | Per-namespace releases |
| **CRDs** | Installed via hook | Installed from crds/ directory |
| **`helm delete`** | Keeps history by default | Purges history by default |
| **3-way merge** | No | Yes (detects out-of-band changes) |

### 3-way strategic merge (Helm 3)

Helm 3 compares three states when upgrading:
1. The **old chart** (previous desired state)
2. The **live state** (what's actually running, including manual kubectl edits)
3. The **new chart** (new desired state)

This means manual `kubectl edit` changes are preserved if the new chart doesn't touch those fields — unlike Helm 2 which would clobber them.

---

## 8. Helm Environment Variables & Config

```bash
# View all Helm environment variables
helm env

# Key variables:
HELM_CACHE_HOME       # cache directory (~/.cache/helm)
HELM_CONFIG_HOME      # config directory (~/.config/helm)
HELM_DATA_HOME        # data directory (~/.local/share/helm)
HELM_DEBUG            # enable verbose debug output (true/false)
HELM_MAX_HISTORY      # max release history (default: 10)
HELM_NAMESPACE        # default namespace
HELM_PLUGINS          # plugins directory
HELM_REGISTRY_CONFIG  # OCI registry config path
HELM_REPOSITORY_CACHE # repository cache directory
HELM_REPOSITORY_CONFIG # repositories.yaml path
KUBECONFIG            # kubeconfig file path

# Set a default namespace for all helm commands
export HELM_NAMESPACE=production
helm list    # now lists in production namespace

# Debug mode — shows raw API calls and template rendering
export HELM_DEBUG=true
helm install my-app ./chart
```

### Helm plugins

```bash
# List installed plugins
helm plugin list

# Install useful plugins
helm plugin install https://github.com/databus23/helm-diff      # show diff before upgrade
helm plugin install https://github.com/jkroepke/helm-secrets    # encrypt values with SOPS
helm plugin install https://github.com/helm/helm-mapkubeapis    # fix deprecated API versions

# Update plugins
helm plugin update diff

# Remove plugin
helm plugin remove diff
```

---

## Cheatsheet

```bash
# Release management
helm list -A
helm status my-app -n production
helm history my-app -n production
helm get values my-app --all
helm get manifest my-app

# Install with safety options
helm upgrade --install my-app ./chart \
  --namespace production \
  --create-namespace \
  --values values.yaml \
  --atomic \
  --timeout 10m \
  --cleanup-on-fail

# Debug (render without installing)
helm template my-app ./chart --values values.yaml
helm install my-app ./chart --dry-run --debug

# Repos
helm repo add <n> <url>
helm repo update
helm search repo <chart> --versions
helm pull bitnami/postgresql --untar

# Values
helm get values my-app             # user-supplied
helm get values my-app --all       # all including defaults
helm show values bitnami/postgresql > defaults.yaml
```

---

*Next: [Chart Development →](./02-chart-development.md)*
