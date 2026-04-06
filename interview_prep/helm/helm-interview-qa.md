# Helm Interview Q&A — All Levels

> **Coverage**: Beginner → Intermediate → Advanced → Scenario-Based  
> **Format**: Mix of concise answers, bullet points, tables, and code snippets  
> **Total**: 120+ questions across 10 topic sections  
> **Relevance**: DevOps/Cloud Engineer roles, Kubernetes engineer positions, CKA/CKAD adjacent tooling

---

## Table of Contents

1. [Helm Fundamentals](#1-helm-fundamentals)
2. [Helm Charts — Structure & Basics](#2-helm-charts--structure--basics)
3. [Values & Templating](#3-values--templating)
4. [Helm CLI & Release Management](#4-helm-cli--release-management)
5. [Repositories & Chart Management](#5-repositories--chart-management)
6. [Hooks & Tests](#6-hooks--tests)
7. [Chart Dependencies](#7-chart-dependencies)
8. [Advanced Templating & Functions](#8-advanced-templating--functions)
9. [Helm in CI/CD & Best Practices](#9-helm-in-cicd--best-practices)
10. [Scenario-Based & Real-World Questions](#10-scenario-based--real-world-questions)

---

## 1. Helm Fundamentals

---

**Q1. What is Helm?**

Helm is the **package manager for Kubernetes**. It simplifies deploying and managing Kubernetes applications by packaging all required resources (Deployments, Services, ConfigMaps, etc.) into a single unit called a **chart**.

Helm provides:
- Templating engine for Kubernetes manifests
- Release management (install, upgrade, rollback, uninstall)
- Chart versioning and sharing via repositories
- Dependency management between charts

---

**Q2. What problem does Helm solve?**

Without Helm, deploying a complex application to Kubernetes requires:
- Manually writing and managing many YAML files
- No standard way to parameterize configs for different environments
- No built-in upgrade or rollback mechanism
- No versioning of the full application stack

Helm solves this by:

| Problem | Helm Solution |
|---|---|
| Many YAML files | Packaged into a single chart |
| Hardcoded values | Go templating with configurable values |
| No upgrade mechanism | `helm upgrade` with revision history |
| No rollback | `helm rollback` to any previous revision |
| No sharing mechanism | Chart repositories (public and private) |

---

**Q3. What are the three main concepts in Helm?**

| Concept | Description |
|---|---|
| **Chart** | A Helm package; a collection of files describing Kubernetes resources |
| **Repository** | A place where charts are stored and shared (like apt/yum for packages) |
| **Release** | A running instance of a chart deployed to a Kubernetes cluster |

One chart can be installed multiple times, creating multiple releases with different names and configurations.

---

**Q4. What is the difference between Helm 2 and Helm 3?**

| Feature | Helm 2 | Helm 3 |
|---|---|---|
| Server component | Tiller (runs in cluster) | No Tiller — client-only |
| Security | Tiller had cluster-admin by default | Uses Kubernetes RBAC directly |
| Release storage | ConfigMaps in `kube-system` | Secrets in release namespace |
| 3-way merge | No (2-way diff) | Yes (3-way strategic merge patch) |
| CRD handling | Basic | Improved (separate `crds/` directory) |
| Chart schema | No validation | `values.schema.json` supported |
| Namespacing | Releases shared across namespaces | Releases are namespace-scoped |
| Status | EOL | Current (use Helm 3) |

---

**Q5. What is Tiller and why was it removed in Helm 3?**

Tiller was the **server-side component** of Helm 2 that ran inside the Kubernetes cluster and had wide permissions to create resources. Problems:
- Required cluster-admin privileges by default
- Created a security attack surface (Tiller was a privilege escalation vector)
- Complicated RBAC setup
- Single point of failure

Helm 3 removed Tiller entirely — the Helm client talks directly to the Kubernetes API using the user's own credentials and kubeconfig, inheriting their RBAC permissions.

---

**Q6. What is a Helm chart?**

A Helm chart is a **collection of files** that describe a related set of Kubernetes resources. Think of it like an application package. A chart can describe anything from a simple Pod to a full multi-tier web application with databases, caches, and message queues.

---

**Q7. What is a Helm release?**

A release is a **deployed instance of a chart** in a Kubernetes cluster. Each time you install a chart, a new release is created with a unique name. Multiple releases of the same chart can exist in the same cluster (or even same namespace with different names).

```bash
# Install creates a release
helm install my-nginx bitnami/nginx     # Release name: my-nginx
helm install web-server bitnami/nginx   # Another release of same chart
```

---

**Q8. Where does Helm 3 store release information?**

Helm 3 stores release metadata as **Kubernetes Secrets** in the same namespace as the release:

```bash
# View Helm release secrets
kubectl get secrets -n production | grep helm

# Release history stored as:
# sh.helm.release.v1.<release-name>.v<revision>
kubectl get secret sh.helm.release.v1.my-app.v1 -n production -o yaml
```

Each revision gets its own Secret, enabling rollbacks.

---

**Q9. What is the difference between `helm install` and `helm upgrade`?**

| `helm install` | `helm upgrade` |
|---|---|
| Creates a new release | Updates an existing release |
| Fails if release name already exists | Fails if release doesn't exist |
| Creates revision 1 | Increments revision number |
| Use for first deployment | Use for updates |

```bash
# Combined: install if not exists, upgrade if exists
helm upgrade --install my-app ./my-chart
```

---

**Q10. What is `helm upgrade --install`?**

A combined command that:
- **Installs** the chart if the release doesn't exist
- **Upgrades** the chart if the release already exists

This is the standard command used in CI/CD pipelines — idempotent and handles both scenarios:

```bash
helm upgrade --install my-app bitnami/nginx \
  --namespace production \
  --create-namespace \
  --values values-production.yaml \
  --set image.tag=v1.2.3 \
  --atomic \
  --timeout 5m
```

---

## 2. Helm Charts — Structure & Basics

---

**Q11. What is the directory structure of a Helm chart?**

```
my-chart/
├── Chart.yaml              # Chart metadata (name, version, description)
├── values.yaml             # Default configuration values
├── values.schema.json      # JSON Schema for values validation (optional)
├── charts/                 # Chart dependencies (subcharts)
├── crds/                   # Custom Resource Definitions
├── templates/              # Kubernetes manifest templates
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── serviceaccount.yaml
│   ├── hpa.yaml
│   ├── NOTES.txt           # Post-install notes shown to user
│   ├── _helpers.tpl        # Named templates (reusable partials)
│   └── tests/
│       └── test-connection.yaml
└── README.md               # Documentation
```

---

**Q12. What is `Chart.yaml`?**

`Chart.yaml` contains **metadata about the chart**:

```yaml
apiVersion: v2                    # Helm 3 uses v2
name: my-app
description: A Helm chart for my application
type: application                 # application or library
version: 1.2.3                    # Chart version (SemVer)
appVersion: "2.0.0"               # Version of the app being packaged
keywords:
  - web
  - backend
home: https://github.com/myorg/my-app
sources:
  - https://github.com/myorg/my-app
maintainers:
  - name: Alice
    email: alice@example.com
dependencies:
  - name: postgresql
    version: "~12.0"
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled
```

---

**Q13. What is the difference between `version` and `appVersion` in `Chart.yaml`?**

| Field | Description |
|---|---|
| `version` | The **chart** version — increment when chart structure/templates change |
| `appVersion` | The **application** version being packaged — e.g., Docker image tag |

Example: chart `version: 1.5.0` packages `appVersion: "2.0.3"` of nginx. The chart can be updated to fix a template bug (`version: 1.5.1`) without changing the app (`appVersion: "2.0.3"`).

---

**Q14. What is the `templates/` directory?**

The `templates/` directory contains **Go template files** that Helm renders into Kubernetes manifests. Files ending in `.yaml` or `.json` are rendered. Files beginning with `_` (like `_helpers.tpl`) are not rendered directly but contain **named templates** that can be included in other templates.

---

**Q15. What is `_helpers.tpl`?**

`_helpers.tpl` is a conventions file for defining **reusable named templates** (partials) used across other chart templates. It is prefixed with `_` so it is not rendered as a manifest:

```yaml
{{/*
Expand the name of the chart.
*/}}
{{- define "my-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "my-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "my-app.labels" -}}
helm.sh/chart: {{ include "my-app.chart" . }}
app.kubernetes.io/name: {{ include "my-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}
```

---

**Q16. What is `NOTES.txt`?**

`NOTES.txt` is displayed to the user **after a successful `helm install` or `helm upgrade`**. It's a template file (supports Go templating) used to show:
- Access instructions
- Important configuration notes
- Next steps

```
{{- if .Values.ingress.enabled }}
Access your app at: https://{{ .Values.ingress.host }}
{{- else }}
To access your app, run:
  kubectl port-forward svc/{{ include "my-app.fullname" . }} 8080:{{ .Values.service.port }}
  Then visit: http://localhost:8080
{{- end }}

Release name: {{ .Release.Name }}
Chart version: {{ .Chart.Version }}
App version: {{ .Chart.AppVersion }}
```

---

**Q17. What is a library chart?**

A library chart (`type: library` in `Chart.yaml`) contains **only named templates** — no deployable resources. It cannot be installed directly but can be used as a dependency by application charts to share common template logic.

```yaml
# Chart.yaml
type: library   # Cannot be installed directly
```

```yaml
# In an application chart's Chart.yaml
dependencies:
  - name: common
    version: "~2.0"
    repository: https://charts.bitnami.com/bitnami
```

---

**Q18. What is `values.schema.json`?**

A JSON Schema file that **validates values** passed to the chart during install/upgrade. Helm 3 validates user-supplied values against this schema:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "type": "object",
  "required": ["replicaCount", "image"],
  "properties": {
    "replicaCount": {
      "type": "integer",
      "minimum": 1,
      "maximum": 10
    },
    "image": {
      "type": "object",
      "required": ["repository", "tag"],
      "properties": {
        "repository": { "type": "string" },
        "tag":        { "type": "string" }
      }
    }
  }
}
```

---

**Q19. What is the `crds/` directory in a Helm chart?**

The `crds/` directory contains **Custom Resource Definitions**. Helm installs CRDs from this directory **before** rendering and installing any templates. This ensures CRDs exist before their instances are created.

Important behaviors:
- CRDs in `crds/` are never templated — they are plain YAML
- CRDs are not deleted when the chart is uninstalled (by design)
- CRDs are not upgraded by Helm (to avoid data loss) — upgrade manually

---

**Q20. How do you create a new Helm chart from scratch?**

```bash
# Create chart skeleton
helm create my-app

# Generated structure:
my-app/
├── Chart.yaml
├── values.yaml
├── charts/
└── templates/
    ├── deployment.yaml
    ├── hpa.yaml
    ├── ingress.yaml
    ├── service.yaml
    ├── serviceaccount.yaml
    ├── NOTES.txt
    └── _helpers.tpl

# Package chart into .tgz archive
helm package my-app

# Lint chart for errors
helm lint my-app
```

---

## 3. Values & Templating

---

**Q21. What are Helm values?**

Values are **configuration parameters** passed to chart templates. Default values are defined in `values.yaml`. Users can override them at install/upgrade time.

```yaml
# values.yaml
replicaCount: 2

image:
  repository: nginx
  tag: "1.25"
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  host: ""

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 200m
    memory: 256Mi
```

---

**Q22. What is the order of value precedence in Helm?**

From highest to lowest priority:

```
1. --set flags          (highest — CLI overrides)
2. --set-string flags
3. --set-file flags
4. -f / --values files  (last file wins if multiple)
5. values.yaml          (chart defaults — lowest)
```

```bash
helm install my-app ./chart \
  -f values-base.yaml \        # Applied first (lower priority)
  -f values-prod.yaml \        # Applied second (overrides base)
  --set image.tag=v2.0.0       # Applied last (highest priority)
```

---

**Q23. What is the difference between `--set`, `--set-string`, and `--set-file`?**

| Flag | Behavior |
|---|---|
| `--set key=value` | Sets value with type inference (number, bool, string) |
| `--set-string key=value` | Always treats value as string (avoids `true`/`1` being parsed as bool/int) |
| `--set-file key=./file` | Reads file content and sets as string value |
| `--set-json key='{}'` | Sets value as JSON (Helm 3.12+) |

```bash
# --set parses "true" as boolean
--set enabled=true

# --set-string forces string "true"
--set-string enabled=true

# --set-file for multiline content
--set-file config=./nginx.conf
```

---

**Q24. How does Go templating work in Helm?**

Helm uses the **Go `text/template`** package with Sprig functions. Templates are enclosed in `{{ }}`:

```yaml
# templates/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}        # Named template
  namespace: {{ .Release.Namespace }}             # Built-in object
  labels:
    {{- include "my-app.labels" . | nindent 4 }} # Named template, indented
spec:
  replicas: {{ .Values.replicaCount }}            # From values.yaml
  template:
    spec:
      containers:
      - name: {{ .Chart.Name }}                   # From Chart.yaml
        image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
        {{- if .Values.resources }}
        resources:
          {{- toYaml .Values.resources | nindent 10 }}
        {{- end }}
```

---

**Q25. What are the built-in Helm template objects?**

| Object | Description |
|---|---|
| `.Release.Name` | Release name |
| `.Release.Namespace` | Namespace release is installed in |
| `.Release.IsInstall` | True if this is an install (not upgrade) |
| `.Release.IsUpgrade` | True if this is an upgrade |
| `.Release.Revision` | Current revision number |
| `.Release.Service` | Always "Helm" |
| `.Chart.Name` | Chart name from Chart.yaml |
| `.Chart.Version` | Chart version |
| `.Chart.AppVersion` | App version from Chart.yaml |
| `.Values` | All values (merged from values.yaml + user overrides) |
| `.Files` | Access non-template files in chart |
| `.Capabilities` | Info about cluster capabilities (K8s version, API groups) |
| `.Template.Name` | Current template file path |

---

**Q26. What are whitespace control characters in Helm templates?**

```yaml
# {{- removes whitespace/newline BEFORE the action
# -}} removes whitespace/newline AFTER the action

{{- if .Values.ingress.enabled }}    # No leading whitespace
  host: {{ .Values.ingress.host -}}  # No trailing whitespace
{{- end }}

# Without control:
{{ if .Values.ingress.enabled }}
  # Produces blank line before
{{ end }}
# Produces blank line after
```

---

**Q27. What is `toYaml`, `nindent`, and `indent` in Helm?**

```yaml
# toYaml - converts a value to YAML format
resources:
  {{- toYaml .Values.resources | nindent 2 }}
# nindent = indent + leading newline

# indent - indents without leading newline
annotations:
  {{ toYaml .Values.annotations | indent 2 }}

# Example:
# .Values.resources = {requests: {cpu: 100m}}
# toYaml → "requests:\n  cpu: 100m\n"
# nindent 2 → "\n  requests:\n    cpu: 100m\n"
```

---

**Q28. How do you use conditionals in Helm templates?**

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "my-app.fullname" . }}
spec:
  {{- if .Values.ingress.tls }}
  tls:
    - hosts:
        - {{ .Values.ingress.host }}
      secretName: {{ .Values.ingress.tlsSecret }}
  {{- end }}
{{- end }}

# if/else
{{- if eq .Values.service.type "LoadBalancer" }}
  loadBalancerIP: {{ .Values.service.loadBalancerIP }}
{{- else if eq .Values.service.type "NodePort" }}
  nodePort: {{ .Values.service.nodePort }}
{{- else }}
  # ClusterIP - no extra config
{{- end }}
```

---

**Q29. How do you use loops in Helm templates?**

```yaml
# range over a list
{{- range .Values.extraEnv }}
- name: {{ .name }}
  value: {{ .value | quote }}
{{- end }}

# range over a map
{{- range $key, $value := .Values.configData }}
{{ $key }}: {{ $value | quote }}
{{- end }}

# range with index
{{- range $index, $host := .Values.ingress.hosts }}
- host: {{ $host }}
{{- end }}
```

---

**Q30. What is the `with` action in Helm templates?**

`with` changes the **scope** (`.`) to a specific value, simplifying deeply nested access:

```yaml
# Without with
image: {{ .Values.image.repository }}:{{ .Values.image.tag }}
pullPolicy: {{ .Values.image.pullPolicy }}

# With 'with' — cleaner for nested values
{{- with .Values.image }}
image: {{ .repository }}:{{ .tag }}
pullPolicy: {{ .pullPolicy }}
{{- end }}

# Important: inside 'with', you lose access to root scope
# Use $ to access root
{{- with .Values.image }}
name: {{ $.Release.Name }}-{{ .repository }}
{{- end }}
```

---

## 4. Helm CLI & Release Management

---

**Q31. What are the most important Helm CLI commands?**

```bash
# Install
helm install <release-name> <chart> [flags]
helm install my-app ./my-chart
helm install my-app bitnami/nginx --version 15.0.0

# Upgrade
helm upgrade <release-name> <chart> [flags]
helm upgrade my-app ./my-chart --values values-prod.yaml

# Upgrade or Install (idempotent)
helm upgrade --install my-app ./my-chart

# List releases
helm list
helm list --all-namespaces
helm list -n production

# Get release info
helm status my-app
helm get values my-app
helm get manifest my-app
helm get all my-app
helm get notes my-app
helm get hooks my-app

# History
helm history my-app

# Rollback
helm rollback my-app [revision]
helm rollback my-app 2

# Uninstall
helm uninstall my-app
helm uninstall my-app --keep-history    # Keep history for rollback

# Dry run
helm install my-app ./chart --dry-run --debug

# Template rendering (no install)
helm template my-app ./chart > rendered.yaml
helm template my-app ./chart -f values-prod.yaml

# Lint
helm lint ./my-chart
helm lint ./my-chart --values values-prod.yaml
```

---

**Q32. What does `helm get values` show?**

```bash
# Show user-supplied values (overrides only)
helm get values my-app

# Show all values (including defaults)
helm get values my-app --all

# Show values as JSON
helm get values my-app -o json

# Show values from specific revision
helm get values my-app --revision 3
```

---

**Q33. What does `helm history` show?**

```bash
helm history my-app
# REVISION  UPDATED                  STATUS     CHART         APP VERSION  DESCRIPTION
# 1         2024-01-01 10:00:00 UTC  superseded my-app-1.0.0  2.0.0       Install complete
# 2         2024-01-02 11:00:00 UTC  superseded my-app-1.1.0  2.1.0       Upgrade complete
# 3         2024-01-03 09:00:00 UTC  deployed   my-app-1.2.0  2.2.0       Upgrade complete
```

---

**Q34. How does `helm rollback` work?**

```bash
# Rollback to previous revision
helm rollback my-app

# Rollback to specific revision
helm rollback my-app 2

# Rollback with timeout
helm rollback my-app 2 --timeout 5m

# After rollback, a new revision is created
helm history my-app
# REVISION 4: Rollback to revision 2
```

Rollback creates a **new revision** (not revert to old one) — the rollback itself is auditable.

---

**Q35. What is `--atomic` flag in Helm?**

`--atomic` ensures that if the install/upgrade fails, Helm **automatically rolls back** to the previous state:

```bash
helm upgrade --install my-app ./chart \
  --atomic \
  --timeout 5m

# If upgrade fails (e.g., new Pods don't become Ready in 5 min):
# Helm automatically rolls back to previous revision
```

Highly recommended for production deployments — prevents leaving a release in a broken intermediate state.

---

**Q36. What is `--wait` flag in Helm?**

`--wait` causes Helm to wait until all resources are **Ready** before marking the release as successful:

```bash
helm upgrade --install my-app ./chart \
  --wait \
  --timeout 10m
```

Helm waits for:
- Pods to be Running and Ready
- Services to have endpoints
- Deployments/StatefulSets to have minimum replicas ready

Without `--wait`, Helm considers the install successful as soon as the manifests are applied to the API server.

---

**Q37. What is `helm template` and when is it used?**

`helm template` renders chart templates **locally without contacting the cluster** — outputs the rendered Kubernetes YAML:

```bash
# Render to stdout
helm template my-app ./my-chart

# Render with values
helm template my-app ./my-chart \
  -f values-prod.yaml \
  --set image.tag=v2.0.0

# Save to file (for GitOps — store rendered manifests in Git)
helm template my-app ./my-chart > rendered-manifests.yaml

# Render specific template file
helm template my-app ./my-chart -s templates/deployment.yaml
```

Used for:
- Debugging templates without installing
- GitOps workflows (render → commit → ArgoCD applies)
- CI checks

---

**Q38. What is `helm lint`?**

```bash
# Check chart for errors and best-practice violations
helm lint ./my-chart

# Lint with specific values
helm lint ./my-chart -f values-prod.yaml

# Strict mode (warnings become errors)
helm lint ./my-chart --strict
```

Checks for:
- YAML syntax errors
- Missing required fields in Chart.yaml
- Template rendering errors
- Manifest schema violations

---

**Q39. What is the difference between `helm uninstall` and `helm delete`?**

They are the same command — `helm delete` is an alias for `helm uninstall` in Helm 3.

```bash
helm uninstall my-app           # Removes release + all its resources
helm uninstall my-app --keep-history  # Removes resources but keeps history

# With --keep-history, you can still rollback
helm rollback my-app 3
```

---

**Q40. What does `helm install --dry-run --debug` do?**

```bash
helm install my-app ./chart --dry-run --debug
```

- `--dry-run`: Sends rendered templates to the server for validation but does **not** create resources
- `--debug`: Shows verbose output including the fully rendered YAML manifests

Difference from `helm template`:
- `helm template` never contacts the cluster
- `--dry-run` contacts the cluster for schema validation (checks if API groups exist)

---

## 5. Repositories & Chart Management

---

**Q41. What is a Helm repository?**

A Helm repository is an **HTTP server** that hosts an `index.yaml` file and packaged chart archives (`.tgz`). The `index.yaml` is the repository index listing all available charts and versions.

---

**Q42. How do you manage Helm repositories?**

```bash
# Add a repository
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo add stable https://charts.helm.sh/stable
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx

# List repositories
helm repo list

# Update repository index (like apt-get update)
helm repo update

# Remove a repository
helm repo remove bitnami

# Search for charts in repos
helm search repo nginx
helm search repo bitnami/nginx --versions    # All versions

# Search Artifact Hub (public registry)
helm search hub nginx
```

---

**Q43. What is Artifact Hub?**

Artifact Hub (`artifacthub.io`) is the **central public registry** for Helm charts (and other cloud-native artifacts). It replaced the deprecated Helm Hub and aggregates charts from many repositories. Think of it as DockerHub for Helm charts.

---

**Q44. How do you package and distribute a Helm chart?**

```bash
# 1. Package chart into .tgz
helm package ./my-chart
# Creates: my-chart-1.2.3.tgz

# 2. Package with destination directory
helm package ./my-chart --destination ./releases

# 3. Create/update repository index
helm repo index ./releases --url https://charts.mycompany.com

# 4. Host the directory on an HTTP server
# (nginx, GitHub Pages, S3, GCS, OCI registry)

# 5. Users add and use your repo
helm repo add mycompany https://charts.mycompany.com
helm install my-app mycompany/my-chart
```

---

**Q45. What is an OCI registry and how does Helm use it?**

OCI (Open Container Initiative) registries (like Docker Hub, ECR, ACR, GCR) can store **Helm charts as OCI artifacts** alongside container images. This is the modern approach for chart distribution:

```bash
# Push chart to OCI registry (Helm 3.8+)
helm package ./my-chart
helm push my-chart-1.0.0.tgz oci://registry.example.com/charts

# Pull and install from OCI registry
helm install my-app oci://registry.example.com/charts/my-chart \
  --version 1.0.0

# Login to OCI registry
helm registry login registry.example.com \
  --username myuser \
  --password mypass

# Pull (without installing)
helm pull oci://registry.example.com/charts/my-chart --version 1.0.0
```

OCI registries are preferred over HTTP chart repos for private charts — better security and access control.

---

**Q46. How do you use a private Helm repository?**

```bash
# Add with authentication
helm repo add private-repo https://charts.mycompany.com \
  --username myuser \
  --password mypassword

# With TLS client certificate
helm repo add private-repo https://charts.mycompany.com \
  --cert-file client.crt \
  --key-file client.key \
  --ca-file ca.crt

# With insecure TLS (dev only)
helm repo add private-repo https://charts.mycompany.com \
  --insecure-skip-tls-verify
```

---

**Q47. How do you show all versions of a chart?**

```bash
# Show all versions from repo
helm search repo bitnami/postgresql --versions

# Show all versions of a specific chart
helm search repo bitnami/postgresql --versions | grep "12\."

# Show chart details
helm show chart bitnami/postgresql
helm show values bitnami/postgresql
helm show readme bitnami/postgresql
helm show all bitnami/postgresql
```

---

**Q48. What is `helm pull`?**

Downloads a chart from a repository without installing it:

```bash
# Pull and extract chart
helm pull bitnami/nginx --version 15.0.0 --untar

# Pull as .tgz archive
helm pull bitnami/nginx --version 15.0.0

# Pull from OCI registry
helm pull oci://registry.example.com/charts/my-chart --version 1.0.0 --untar
```

Used to:
- Inspect chart contents
- Modify chart before installing
- Vendor charts into your own repository

---

## 6. Hooks & Tests

---

**Q49. What are Helm hooks?**

Helm hooks are **special resources** that run at specific points in the release lifecycle. They are annotated with `helm.sh/hook`:

| Hook | When it runs |
|---|---|
| `pre-install` | After templates rendered, before any resources created |
| `post-install` | After all resources installed |
| `pre-upgrade` | Before upgrade resources created |
| `post-upgrade` | After all upgrade resources applied |
| `pre-rollback` | Before rollback |
| `post-rollback` | After rollback complete |
| `pre-delete` | Before any resources deleted |
| `post-delete` | After all resources deleted |
| `test` | Only when `helm test` is run |

---

**Q50. How do you create a Helm hook?**

```yaml
# templates/hooks/pre-install-job.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "my-app.fullname" . }}-pre-install
  annotations:
    "helm.sh/hook": pre-install
    "helm.sh/hook-weight": "-5"          # Lower = runs first (can be negative)
    "helm.sh/hook-delete-policy": hook-succeeded  # Cleanup after success
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: pre-install
        image: alpine:3.18
        command: ["sh", "-c", "echo 'Running pre-install setup'"]
```

---

**Q51. What are hook delete policies?**

| Policy | Behavior |
|---|---|
| `before-hook-creation` (default) | Delete previous hook resource before creating new one |
| `hook-succeeded` | Delete hook resource after it succeeds |
| `hook-failed` | Delete hook resource if it fails |

```yaml
annotations:
  "helm.sh/hook-delete-policy": hook-succeeded,hook-failed  # Always clean up
```

---

**Q52. What is hook weight?**

Hook weight controls **execution order** when multiple hooks of the same type exist:

```yaml
# Runs first (weight -5)
annotations:
  "helm.sh/hook": pre-install
  "helm.sh/hook-weight": "-5"

# Runs second (weight 0)
annotations:
  "helm.sh/hook": pre-install
  "helm.sh/hook-weight": "0"

# Runs last (weight 10)
annotations:
  "helm.sh/hook": pre-install
  "helm.sh/hook-weight": "10"
```

Hooks with the same weight run in alphabetical order.

---

**Q53. What is `helm test`?**

`helm test` runs **test hooks** defined in the chart to verify the release is working correctly after installation:

```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "my-app.fullname" . }}-test-connection
  annotations:
    "helm.sh/hook": test
spec:
  restartPolicy: Never
  containers:
  - name: wget
    image: busybox
    command: ["wget", "--spider", "http://{{ include "my-app.fullname" . }}:{{ .Values.service.port }}"]
```

```bash
# Run tests for a release
helm test my-app

# Show test logs
helm test my-app --logs
```

Test Pods must exit with code 0 for the test to pass.

---

**Q54. What is the difference between a hook and a regular resource?**

| Regular Resource | Hook Resource |
|---|---|
| Created/updated during sync phase | Created at specific lifecycle points |
| Managed as part of the release | Can be cleaned up independently |
| Included in `helm get manifest` | Included in `helm get hooks` |
| Part of release health | Treated separately from release health |

---

## 7. Chart Dependencies

---

**Q55. What are chart dependencies?**

Chart dependencies (subcharts) allow a chart to **depend on other charts**. For example, a web application chart might depend on a PostgreSQL chart:

```yaml
# Chart.yaml
dependencies:
  - name: postgresql
    version: "~12.5"
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled      # Only include if this value is true
    tags:
      - database
  - name: redis
    version: "~17.0"
    repository: https://charts.bitnami.com/bitnami
    condition: redis.enabled
```

---

**Q56. How do you manage chart dependencies?**

```bash
# Download dependencies (creates charts/ directory)
helm dependency update ./my-chart

# List dependencies and their status
helm dependency list ./my-chart

# Build dependencies from Chart.lock
helm dependency build ./my-chart
```

After `helm dependency update`:
- `charts/` directory contains `.tgz` files for each dependency
- `Chart.lock` is created/updated with exact versions resolved

---

**Q57. What is `Chart.lock`?**

`Chart.lock` records the **exact versions** of all dependencies resolved during `helm dependency update` — similar to `package-lock.json`:

```yaml
# Chart.lock
dependencies:
- name: postgresql
  repository: https://charts.bitnami.com/bitnami
  version: 12.5.8          # Exact version (not range)
- name: redis
  repository: https://charts.bitnami.com/bitnami
  version: 17.11.3
digest: sha256:abc123...
generated: "2024-01-01T00:00:00Z"
```

Commit `Chart.lock` to Git for reproducible builds.

---

**Q58. How do you pass values to a subchart?**

Values for subcharts are namespaced by the subchart name in the parent `values.yaml`:

```yaml
# values.yaml of parent chart
postgresql:                # Matches subchart name
  enabled: true
  auth:
    postgresPassword: secret
    database: myapp
  primary:
    persistence:
      size: 10Gi

redis:
  enabled: false           # Disable redis subchart
```

---

**Q59. What is a global value in Helm?**

Global values are accessible by both parent and all subcharts via `.Values.global`:

```yaml
# Parent values.yaml
global:
  imageRegistry: registry.mycompany.com
  storageClass: fast-ssd
  environment: production

# In parent template
image: {{ .Values.global.imageRegistry }}/myapp:latest

# In subchart template — also has access to .Values.global
image: {{ .Values.global.imageRegistry }}/postgres:15
```

---

**Q60. What is the difference between `helm dependency update` and `helm dependency build`?**

| Command | Behavior |
|---|---|
| `helm dependency update` | Resolves latest matching versions, updates `Chart.lock`, downloads |
| `helm dependency build` | Downloads exact versions from `Chart.lock` (no resolution) |

Use `helm dependency build` in CI/CD for reproducibility (uses locked versions).
Use `helm dependency update` to update dependencies to newer versions.

---

## 8. Advanced Templating & Functions

---

**Q61. What Sprig functions are commonly used in Helm?**

Helm includes the **Sprig** function library (100+ functions):

```yaml
# String functions
{{ "hello" | upper }}                    # HELLO
{{ "hello world" | title }}              # Hello World
{{ "  hello  " | trim }}                 # hello
{{ "hello" | repeat 3 }}                 # hellohellohello
{{ list "a" "b" "c" | join "-" }}        # a-b-c
{{ "hello" | b64enc }}                   # aGVsbG8=
{{ "aGVsbG8=" | b64dec }}               # hello
{{ randAlphaNum 16 }}                    # Random 16-char string

# Type conversion
{{ "42" | int }}                         # 42
{{ 42 | toString }}                      # "42"
{{ "true" | toBool }}                    # true

# Default values
{{ .Values.port | default 80 }}          # 80 if port is not set
{{ .Values.name | default "unnamed" }}

# Math
{{ add 1 2 }}                            # 3
{{ mul 2 3 }}                            # 6
{{ max 1 5 3 }}                          # 5

# Date
{{ now | date "2006-01-02" }}            # Current date

# Dict operations
{{ dict "key" "value" }}
{{ .Values.myDict | keys | sortAlpha | join "," }}

# List operations
{{ list 1 2 3 | len }}                   # 3
{{ list 1 2 3 | first }}                 # 1
{{ list 1 2 3 | last }}                  # 3
{{ list 1 2 3 | has 2 }}                # true
```

---

**Q62. What is the `required` function?**

`required` causes the template to **fail with a message** if a value is empty:

```yaml
image: {{ required "image.repository is required" .Values.image.repository }}

database:
  host: {{ required "A database host is required" .Values.db.host }}
  password: {{ required "A database password is required" .Values.db.password }}
```

If the required value is not provided, Helm fails with the error message during template rendering.

---

**Q63. What is the `default` function?**

`default` provides a **fallback value** if the given value is empty:

```yaml
replicas: {{ .Values.replicaCount | default 1 }}
port: {{ .Values.service.port | default 80 }}
name: {{ .Values.nameOverride | default .Chart.Name }}

# Default with complex value
{{- with .Values.nodeSelector | default dict }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
```

---

**Q64. What is the `include` function vs `template`?**

```yaml
# template action — cannot be piped (result goes to output directly)
{{ template "my-app.labels" . }}

# include function — can be piped to other functions
{{ include "my-app.labels" . | nindent 4 }}
{{ include "my-app.fullname" . | upper | trunc 63 }}
```

**Always prefer `include` over `template`** — it allows piping results to functions like `indent`, `nindent`, `upper`, etc.

---

**Q65. How do you define and call a named template?**

```yaml
# In _helpers.tpl — define
{{- define "my-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "my-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "my-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "my-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

# In deployment.yaml — call
spec:
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
    spec:
      serviceAccountName: {{ include "my-app.serviceAccountName" . }}
```

---

**Q66. How do you access files in a Helm chart from templates?**

```yaml
# .Files.Get — get file as string
data:
  nginx.conf: |
    {{ .Files.Get "files/nginx.conf" | nindent 4 }}

# .Files.GetBytes — get as bytes (for binary)
# .Files.Glob — get multiple files
data:
  {{- (.Files.Glob "config/*.conf").AsConfig | nindent 2 }}

# .Files.Lines — iterate over file lines
{{- range .Files.Lines "hosts.txt" }}
- {{ . }}
{{- end }}
```

Files in `templates/` are rendered as manifests. Files elsewhere can be read via `.Files`.

---

**Q67. What is `.Capabilities` in Helm?**

`.Capabilities` provides information about the **target cluster**:

```yaml
# Check Kubernetes version
{{- if semverCompare ">=1.19-0" .Capabilities.KubeVersion.GitVersion }}
apiVersion: networking.k8s.io/v1
{{- else }}
apiVersion: networking.k8s.io/v1beta1
{{- end }}

# Check if API group is available
{{- if .Capabilities.APIVersions.Has "policy/v1/PodDisruptionBudget" }}
apiVersion: policy/v1
{{- else }}
apiVersion: policy/v1beta1
{{- end }}
```

Used for **backwards compatibility** — same chart can target different Kubernetes versions.

---

**Q68. How do you generate a random password in Helm?**

```yaml
# WARNING: Generates a NEW password on every helm upgrade!
# Only use for initial install or with lookup to persist

# Generate random password (changes on every upgrade — use with caution)
password: {{ randAlphaNum 32 | b64enc | quote }}

# Better approach: use lookup to read existing secret
{{- $secret := lookup "v1" "Secret" .Release.Namespace "my-secret" }}
{{- if $secret }}
password: {{ $secret.data.password }}
{{- else }}
password: {{ randAlphaNum 32 | b64enc | quote }}
{{- end }}
```

---

**Q69. What is the `lookup` function in Helm?**

`lookup` queries the Kubernetes API for **existing resources**:

```yaml
# Syntax: lookup <apiVersion> <kind> <namespace> <name>
# Returns the resource as a dict, or empty dict if not found

{{- $existingSecret := lookup "v1" "Secret" .Release.Namespace "my-db-secret" }}
{{- if $existingSecret }}
# Secret exists — reuse existing password
password: {{ $existingSecret.data.password }}
{{- else }}
# Secret doesn't exist — generate new password
password: {{ randAlphaNum 32 | b64enc }}
{{- end }}

# Lookup all secrets in namespace
{{- $secrets := lookup "v1" "Secret" .Release.Namespace "" }}
{{- range $secrets.items }}
# Process each secret
{{- end }}
```

---

**Q70. How do you use `tpl` function in Helm?**

`tpl` renders a string as a **Go template** at runtime — allows values to contain template expressions:

```yaml
# values.yaml
ingress:
  host: "{{ .Release.Name }}.example.com"    # Template in values

# templates/ingress.yaml
host: {{ tpl .Values.ingress.host . }}
# Result: my-release.example.com
```

Powerful but use with caution — values can execute arbitrary template code.

---

## 9. Helm in CI/CD & Best Practices

---

**Q71. How do you integrate Helm into a GitLab CI/CD pipeline?**

```yaml
# .gitlab-ci.yml
variables:
  HELM_CHART: ./charts/my-app
  RELEASE_NAME: my-app
  NAMESPACE: production

stages:
  - lint
  - test
  - deploy

lint-chart:
  stage: lint
  image: alpine/helm:3.13.0
  script:
    - helm lint $HELM_CHART
    - helm lint $HELM_CHART -f values-prod.yaml

template-test:
  stage: test
  image: alpine/helm:3.13.0
  script:
    - helm template $RELEASE_NAME $HELM_CHART
        -f values-prod.yaml
        --set image.tag=$CI_COMMIT_SHORT_SHA
      | kubectl apply --dry-run=client -f -

deploy-production:
  stage: deploy
  image: alpine/helm:3.13.0
  script:
    - helm upgrade --install $RELEASE_NAME $HELM_CHART
        --namespace $NAMESPACE
        --create-namespace
        --values values-prod.yaml
        --set image.tag=$CI_COMMIT_SHORT_SHA
        --atomic
        --timeout 10m
        --wait
  environment:
    name: production
  when: manual
  only:
    - main
```

---

**Q72. How do you use Helm with ArgoCD?**

ArgoCD uses Helm as a **rendering engine only** — it renders templates and applies the resulting manifests:

```yaml
# ArgoCD Application using Helm
spec:
  source:
    repoURL: https://charts.bitnami.com/bitnami
    chart: nginx
    targetRevision: 15.0.0
    helm:
      releaseName: my-nginx
      values: |
        replicaCount: 3
      valueFiles:
        - values-production.yaml
      parameters:
        - name: service.type
          value: ClusterIP
```

ArgoCD manages state, history, and rollbacks — not Helm. Helm is just the template engine.

---

**Q73. What is Helmfile?**

Helmfile is a **declarative tool** for managing multiple Helm releases across environments:

```yaml
# helmfile.yaml
repositories:
  - name: bitnami
    url: https://charts.bitnami.com/bitnami

environments:
  production:
    values:
      - environments/production/values.yaml
  staging:
    values:
      - environments/staging/values.yaml

releases:
  - name: nginx
    namespace: web
    chart: bitnami/nginx
    version: ~15.0
    values:
      - values/nginx.yaml
    set:
      - name: replicaCount
        value: {{ .Environment.Values.nginx.replicas }}

  - name: postgresql
    namespace: data
    chart: bitnami/postgresql
    version: ~12.0
    condition: postgresql.enabled
```

```bash
helmfile sync               # Install/upgrade all releases
helmfile diff               # Preview changes
helmfile destroy            # Delete all releases
helmfile -e production sync # Use production environment
```

---

**Q74. What are Helm chart best practices?**

**Structure:**
- Use `helm create` as starting point, then clean up unused templates
- Keep `_helpers.tpl` for all named templates
- Use `NOTES.txt` to guide users after installation
- Include `values.schema.json` for validation

**Values:**
- Document every value with a comment in `values.yaml`
- Provide sensible defaults for all optional values
- Use `required` for truly mandatory values
- Namespace nested values logically (image.*, service.*, ingress.*)

**Templates:**
- Use `include` not `template` (pipeable)
- Use `nindent` not `indent` for block YAML
- Always quote string values: `{{ .Values.name | quote }}`
- Use `toYaml | nindent` for complex objects
- Test with `helm template` and `helm lint` before committing

**Versioning:**
- Follow SemVer for chart versions
- Update chart `version` on every change
- Pin dependency versions in `Chart.lock`

---

**Q75. How do you handle sensitive values in Helm?**

```bash
# Option 1: Pass secrets via --set (not stored in Git)
helm install my-app ./chart \
  --set db.password=$DB_PASSWORD \
  --set api.key=$API_KEY

# Option 2: Use Kubernetes Secrets directly (not through Helm values)
kubectl create secret generic my-secrets \
  --from-literal=db-password=$DB_PASSWORD
# Then reference in chart template via secretKeyRef

# Option 3: Helm Secrets plugin (uses SOPS/age/GPG encryption)
helm secrets install my-app ./chart \
  -f values.yaml \
  -f secrets.yaml.enc

# Option 4: External Secrets Operator — define ExternalSecret in chart,
# actual values come from Vault/AWS SM at runtime
```

Never store unencrypted secrets in `values.yaml` committed to Git.

---

**Q76. What is the Helm Secrets plugin?**

Helm Secrets is a Helm plugin that enables **encrypted values files** in your Git repository using SOPS (Secrets OPerationS):

```bash
# Install plugin
helm plugin install https://github.com/jkroepke/helm-secrets

# Encrypt a values file with age key
sops -e values-secrets.yaml > values-secrets.yaml.enc

# Use encrypted file during install
helm secrets install my-app ./chart \
  -f values.yaml \
  -f values-secrets.yaml.enc

# The plugin decrypts on-the-fly using your SOPS key
```

---

**Q77. How do you version a Helm chart in a CI pipeline?**

```bash
# Option 1: Use git tag as chart version
CHART_VERSION=$(git describe --tags --abbrev=0 | sed 's/v//')
helm package ./charts/my-app --version $CHART_VERSION --app-version $CHART_VERSION

# Option 2: Use semantic versioning with bump
# chart-releaser (cr) tool automates this for GitHub-hosted charts

# Option 3: Use commit SHA for app version, keep chart version separate
helm package ./charts/my-app \
  --version 1.2.3 \
  --app-version $(git rev-parse --short HEAD)

# Push to OCI registry
helm push my-app-1.2.3.tgz oci://registry.example.com/charts
```

---

**Q78. What is `helm plugin`?**

Helm supports plugins for extending functionality:

```bash
# List installed plugins
helm plugin list

# Install a plugin
helm plugin install https://github.com/databus23/helm-diff
helm plugin install https://github.com/jkroepke/helm-secrets

# Update plugin
helm plugin update diff

# Remove plugin
helm plugin remove diff

# Popular plugins:
# helm-diff   — shows diff before upgrade
# helm-secrets — encrypted values files
# helm-unittest — unit testing for charts
# helm-docs   — auto-generate chart documentation
```

---

**Q79. What is `helm diff`?**

The `helm-diff` plugin shows a **preview of changes** before running `helm upgrade`:

```bash
# Install plugin
helm plugin install https://github.com/databus23/helm-diff

# Show diff
helm diff upgrade my-app ./chart -f values-prod.yaml

# Output:
# default, my-app, Deployment (apps) has changed:
# - replicas: 2
# + replicas: 3
```

Highly recommended for production — lets you review exact changes before applying.

---

**Q80. How do you perform a zero-downtime upgrade with Helm?**

```yaml
# In your Deployment template
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0          # Never reduce below desired

  template:
    spec:
      containers:
      - name: app
        readinessProbe:          # Only send traffic to ready Pods
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 3
        lifecycle:
          preStop:
            exec:
              command: ["sleep", "5"]   # Drain connections
```

```bash
# Deploy with --wait to ensure all Pods are ready before success
helm upgrade my-app ./chart \
  --set image.tag=v2.0.0 \
  --wait \
  --timeout 10m \
  --atomic    # Rollback if upgrade fails
```

---

## 10. Scenario-Based & Real-World Questions

---

**Q81. SCENARIO: A Helm upgrade fails and the release is in a broken state. How do you recover?**

```bash
# Step 1: Check release status
helm status my-app
helm history my-app

# Step 2: Check what went wrong
kubectl get pods -n production | grep my-app
kubectl describe pod <pod-name> -n production
kubectl logs <pod-name> -n production

# Step 3: Rollback to last good revision
helm rollback my-app 3    # Roll back to revision 3

# Step 4: If release is stuck in pending state
helm history my-app       # Find last successful revision

# Step 5: If rollback doesn't work — force uninstall and reinstall
helm uninstall my-app --keep-history
helm install my-app ./chart -f values-prod.yaml

# Prevention: Always use --atomic flag
helm upgrade my-app ./chart --atomic --timeout 10m
```

---

**Q82. SCENARIO: You need to deploy the same chart to 5 different namespaces with slightly different values. What is the cleanest approach?**

```bash
# Method 1: Script with per-namespace values files
for NS in team-a team-b team-c team-d team-e; do
  helm upgrade --install my-app ./chart \
    --namespace $NS \
    --create-namespace \
    -f values/base.yaml \
    -f values/$NS.yaml
done

# Method 2: Helmfile with environment definitions
# releases:
# - name: my-app
#   namespace: {{ .Values.namespace }}
#   values:
#   - values/{{ .Values.namespace }}.yaml

# Method 3: ArgoCD ApplicationSet with List generator
# Creates one Application per namespace automatically

# Method 4: --set to override namespace-specific values
for NS in team-a team-b team-c; do
  helm upgrade --install my-app ./chart \
    --namespace $NS \
    --set global.namespace=$NS \
    --set ingress.host="$NS.example.com"
done
```

---

**Q83. SCENARIO: After a `helm upgrade`, Pods keep restarting because of a bad config change. How do you find what changed and fix it?**

```bash
# Step 1: Find what changed using helm-diff (if installed)
helm diff upgrade my-app ./chart -f values-prod.yaml

# Step 2: Compare values between revisions
helm get values my-app --revision 3 > values-v3.yaml
helm get values my-app --revision 4 > values-v4.yaml
diff values-v3.yaml values-v4.yaml

# Step 3: Compare manifests between revisions
helm get manifest my-app --revision 3 > manifest-v3.yaml
helm get manifest my-app --revision 4 > manifest-v4.yaml
diff manifest-v3.yaml manifest-v4.yaml

# Step 4: Rollback immediately
helm rollback my-app 3

# Step 5: Fix the values/config and redeploy
helm upgrade my-app ./chart -f values-prod.yaml --set <fixed-value>
```

---

**Q84. SCENARIO: You want to add a database password to your chart without storing it in Git. How?**

```bash
# Option 1: Inject at deploy time from CI/CD secret
helm upgrade --install my-app ./chart \
  -f values.yaml \
  --set postgresql.auth.postgresPassword=$DB_PASSWORD

# Option 2: Create Secret separately, reference in chart
kubectl create secret generic my-db-secret \
  --from-literal=password=$DB_PASSWORD \
  --namespace production

# In chart values.yaml:
# existingSecret: "my-db-secret"  ← reference pre-created secret

# Option 3: Helm Secrets plugin with SOPS
sops -e secrets.yaml > secrets.enc.yaml
git add secrets.enc.yaml
# CI/CD: helm secrets upgrade --install my-app ./chart -f secrets.enc.yaml

# Option 4: External Secrets Operator
# Chart creates an ExternalSecret resource
# ESO fetches from Vault/AWS SM and creates a K8s Secret
```

---

**Q85. SCENARIO: Your Helm chart creates a new Deployment name when you change certain values. Resources accumulate. Why and how do you fix it?**

This happens when the resource `name` in a template is computed from a value that changes:

```yaml
# Problematic — name includes a value that changes
name: {{ .Release.Name }}-{{ .Values.version }}-deploy
# When version changes: new Deployment created, old one orphaned
```

Fix:
```yaml
# Use stable name not tied to changing values
name: {{ include "my-app.fullname" . }}
# fullname only uses Release.Name + Chart.Name → stable

# Clean up orphaned resources
kubectl get deployments -n production | grep my-app
kubectl delete deployment my-app-v1-deploy -n production
```

---

**Q86. SCENARIO: How do you test a Helm chart without deploying to a real cluster?**

```bash
# 1. Lint — syntax and best practice checks
helm lint ./my-chart
helm lint ./my-chart -f values-prod.yaml --strict

# 2. Template — render and review YAML output
helm template my-app ./my-chart -f values-prod.yaml > rendered.yaml
cat rendered.yaml    # Manually review

# 3. Validate rendered YAML against cluster schema (needs cluster)
helm template my-app ./my-chart | kubectl apply --dry-run=client -f -

# 4. kubeval — validate against Kubernetes schemas offline
helm template my-app ./my-chart | kubeval

# 5. helm unittest plugin
helm plugin install https://github.com/helm-unittest/helm-unittest
helm unittest ./my-chart

# 6. --dry-run with debug (needs cluster access)
helm install my-app ./my-chart --dry-run --debug -f values-prod.yaml
```

---

**Q87. SCENARIO: How do you implement a Helm chart for a blue-green deployment?**

```yaml
# values.yaml
deployment:
  active: blue    # "blue" or "green"

blueGreen:
  blue:
    image:
      tag: v1.0.0
    enabled: true
  green:
    image:
      tag: v2.0.0
    enabled: true

service:
  selector: blue   # Which color receives traffic
```

```yaml
# templates/deployment-blue.yaml
{{- if .Values.blueGreen.blue.enabled }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}-blue
spec:
  template:
    spec:
      containers:
      - name: app
        image: "{{ .Values.image.repository }}:{{ .Values.blueGreen.blue.image.tag }}"
{{- end }}
```

```bash
# Switch traffic to green
helm upgrade my-app ./chart --set service.selector=green

# After verification, disable blue
helm upgrade my-app ./chart \
  --set service.selector=green \
  --set blueGreen.blue.enabled=false
```

---

**Q88. SCENARIO: A chart's `values.yaml` has grown to 500 lines. How do you organize it?**

```yaml
# Split into logical sections with clear comments

# ===========================================
# Global settings
# ===========================================
global:
  imageRegistry: ""
  storageClass: ""

# ===========================================
# Application settings
# ===========================================
replicaCount: 1

image:
  repository: myapp
  tag: "1.0.0"
  pullPolicy: IfNotPresent

# ===========================================
# Networking
# ===========================================
service:
  type: ClusterIP
  port: 80

ingress:
  enabled: false
  # ... ingress settings

# ===========================================
# Resources & Scaling
# ===========================================
resources: {}
autoscaling:
  enabled: false

# ===========================================
# Storage
# ===========================================
persistence:
  enabled: true
  size: 10Gi

# ===========================================
# Dependencies
# ===========================================
postgresql:
  enabled: true
  auth:
    database: myapp
```

Also consider splitting into multiple files in a `values/` directory and merging with Helmfile or multiple `-f` flags.

---

**Q89. SCENARIO: You need to render different Kubernetes API versions based on cluster version. How?**

```yaml
# Use .Capabilities to detect cluster version
{{- if semverCompare ">=1.19-0" .Capabilities.KubeVersion.GitVersion }}
apiVersion: networking.k8s.io/v1
kind: Ingress
{{- else }}
apiVersion: networking.k8s.io/v1beta1
kind: Ingress
{{- end }}
metadata:
  name: {{ include "my-app.fullname" . }}

# Check for specific API availability
{{- if .Capabilities.APIVersions.Has "autoscaling/v2" }}
apiVersion: autoscaling/v2
{{- else }}
apiVersion: autoscaling/v2beta2
{{- end }}
kind: HorizontalPodAutoscaler
```

---

**Q90. SCENARIO: How do you migrate from plain Kubernetes manifests to Helm charts?**

```bash
# Step 1: Create chart structure
helm create my-app
# Clean out generated templates

# Step 2: Copy existing manifests to templates/
cp k8s/*.yaml my-app/templates/

# Step 3: Extract hardcoded values to values.yaml
# Replace hardcoded values with template variables:
# image: nginx:1.25  →  image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"

# Step 4: Add _helpers.tpl for common labels/names

# Step 5: Lint and test
helm lint ./my-app
helm template my-release ./my-app | diff - k8s/original.yaml

# Step 6: Install (use --dry-run first)
helm install my-release ./my-app --dry-run --debug

# Step 7: If resources already exist in cluster
# Option A: Delete and reinstall (downtime)
kubectl delete -f k8s/
helm install my-release ./my-app

# Option B: Adopt existing resources
# Set correct labels and use helm install (Helm will adopt if names match)
```

---

**Q91. What is the `helm show` command family?**

```bash
# Show chart metadata (Chart.yaml)
helm show chart bitnami/postgresql

# Show default values
helm show values bitnami/postgresql

# Show chart README
helm show readme bitnami/postgresql

# Show all (chart + values + readme)
helm show all bitnami/postgresql

# Show specific version
helm show values bitnami/postgresql --version 12.5.0
```

---

**Q92. How do you pass a complex list or map via `--set`?**

```bash
# Set a list value
helm install my-app ./chart \
  --set "ingress.hosts[0]=example.com" \
  --set "ingress.hosts[1]=www.example.com"

# Set a nested map
helm install my-app ./chart \
  --set "resources.requests.cpu=100m" \
  --set "resources.requests.memory=128Mi"

# Set a list of objects
helm install my-app ./chart \
  --set "env[0].name=ENV" \
  --set "env[0].value=production" \
  --set "env[1].name=DEBUG" \
  --set "env[1].value=false"

# For complex values, prefer -f values file over --set
```

---

**Q93. What is the difference between `helm install --replace` and `helm upgrade`?**

```bash
# helm upgrade — updates existing release, increments revision
helm upgrade my-app ./chart

# helm install --replace — replaces a deleted release with same name
# Reuses the name but treats it as a fresh install
helm install --replace my-app ./chart
# Note: Only works if previous release was deleted
# In practice, almost always use upgrade --install instead
```

---

**Q94. What are chart conventions and recommended labels?**

```yaml
# Recommended labels in all resources (via _helpers.tpl)
labels:
  helm.sh/chart: {{ include "my-app.chart" . }}
  app.kubernetes.io/name: {{ include "my-app.name" . }}
  app.kubernetes.io/instance: {{ .Release.Name }}
  app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
  app.kubernetes.io/managed-by: {{ .Release.Service }}

# Selector labels (stable — used by Service to find Pods)
# Should NOT include version (to avoid selector changes on upgrade)
selectorLabels:
  app.kubernetes.io/name: {{ include "my-app.name" . }}
  app.kubernetes.io/instance: {{ .Release.Name }}
```

---

**Q95. How do you debug a Helm template rendering issue?**

```bash
# Step 1: Render template with debug output
helm template my-app ./chart --debug 2>&1 | less

# Step 2: Check specific template file
helm template my-app ./chart -s templates/deployment.yaml

# Step 3: Check with specific values
helm template my-app ./chart \
  -f values-prod.yaml \
  --set image.tag=v2.0 \
  --debug

# Step 4: Use helm console (interactive — not built-in but use --dry-run)
helm install test ./chart --dry-run --debug \
  -f values-prod.yaml 2>&1 | grep -A 5 "Error"

# Step 5: Check YAML syntax
helm template my-app ./chart | yamllint -

# Step 6: Add print statements to template
{{- printf "DEBUG: replicaCount = %v\n" .Values.replicaCount | fail }}
# This will output the value in an error message
```

---

**Q96. How do you use `helm env` and what does it show?**

```bash
helm env
# HELM_BIN="helm"
# HELM_CACHE_HOME="/home/user/.cache/helm"
# HELM_CONFIG_HOME="/home/user/.config/helm"
# HELM_DATA_HOME="/home/user/.local/share/helm"
# HELM_DEBUG="false"
# HELM_KUBEAPISERVER=""
# HELM_KUBEASGROUPS=""
# HELM_KUBEASUSER=""
# HELM_KUBECONTEXT=""
# HELM_KUBEINSECURE_SKIP_TLS_VERIFY="false"
# HELM_KUBETOKEN=""
# HELM_MAX_HISTORY="10"
# HELM_NAMESPACE="default"
# HELM_PLUGINS="/home/user/.local/share/helm/plugins"
# HELM_REGISTRY_CONFIG="/home/user/.config/helm/registry/config.json"
# HELM_REPOSITORY_CACHE="/home/user/.cache/helm/repository"
# HELM_REPOSITORY_CONFIG="/home/user/.config/helm/repositories.yaml"
```

Useful for understanding where Helm stores its configuration and cache.

---

**Q97. How does Helm handle CRD upgrades?**

Helm **does not upgrade CRDs** placed in the `crds/` directory. This is intentional — upgrading CRDs can break existing Custom Resources. To upgrade CRDs:

```bash
# Method 1: Manual kubectl apply
kubectl apply -f crds/my-crd.yaml

# Method 2: Use a pre-upgrade hook in templates/ (not crds/)
# CRD as a Job hook that applies the CRD manifest
# This allows version management but requires care

# Method 3: Separate CRD chart
# Install CRDs as a separate chart that you control upgrades for
helm install my-app-crds ./my-app-crds-chart
helm install my-app ./my-app-chart
```

---

**Q98. What is `HELM_MAX_HISTORY` and why does it matter?**

Helm stores release history as Kubernetes Secrets. By default, Helm keeps the **last 10 revisions** (controlled by `HELM_MAX_HISTORY`):

```bash
# Set max history limit
helm upgrade my-app ./chart --history-max 5

# Global setting
export HELM_MAX_HISTORY=5

# In helmfile
releases:
  - name: my-app
    historyMax: 5
```

In clusters with many releases, unlimited history can accumulate thousands of Secrets. Always set a reasonable `historyMax`.

---

**Q99. How do you verify chart provenance and integrity?**

```bash
# Sign a chart with GPG
helm package --sign \
  --key "Alice <alice@example.com>" \
  --keyring ~/.gnupg/secring.gpg \
  ./my-chart
# Creates: my-chart-1.0.0.tgz and my-chart-1.0.0.tgz.prov

# Verify chart integrity when installing
helm install my-app my-chart-1.0.0.tgz \
  --verify \
  --keyring ~/.gnupg/pubring.gpg

# Verify without installing
helm verify my-chart-1.0.0.tgz
```

For OCI registries, use **cosign** for signing and verification:
```bash
cosign sign registry.example.com/charts/my-chart:1.0.0
cosign verify registry.example.com/charts/my-chart:1.0.0
```

---

**Q100. What are the most common Helm interview questions in German DevOps roles?**

Based on DACH region DevOps hiring patterns:

1. **"What is the difference between Helm 2 and Helm 3?"** — Tiller removal, namespaced releases
2. **"What is a Helm release and how does rollback work?"** — Revision history, `helm rollback`
3. **"How do you parameterize a Helm chart for multiple environments?"** — values files, --set, --values precedence
4. **"Explain the Helm chart directory structure"** — Chart.yaml, values.yaml, templates/, _helpers.tpl
5. **"How does Helm templating work?"** — Go templates, Sprig functions, built-in objects
6. **"How do you handle secrets in Helm?"** — Helm Secrets, External Secrets, --set at runtime
7. **"What is the difference between `helm template` and `helm install --dry-run`?"** — Cluster contact
8. **"What are Helm hooks and give an example?"** — pre-install DB migration
9. **"How do you manage chart dependencies?"** — Chart.yaml dependencies, helm dependency update
10. **"How do you integrate Helm into a CI/CD pipeline?"** — upgrade --install, --atomic, --wait

---

**Q101. What is `helm install --create-namespace`?**

```bash
# Automatically create namespace if it doesn't exist
helm install my-app ./chart \
  --namespace production \
  --create-namespace

# Without --create-namespace, install fails if namespace missing:
# Error: create: failed to create: namespaces "production" not found
```

---

**Q102. How do you pass multi-line values to a Helm chart via `--set`?**

```bash
# Multi-line values via --set are difficult — use --set-file instead
echo "line1\nline2\nline3" > /tmp/multiline.txt
helm install my-app ./chart --set-file config=/tmp/multiline.txt

# Or use a values file
cat > /tmp/values-extra.yaml <<EOF
config: |
  line1
  line2
  line3
EOF
helm install my-app ./chart -f /tmp/values-extra.yaml
```

---

**Q103. What is the `helm plugin install` URL format?**

```bash
# From GitHub
helm plugin install https://github.com/databus23/helm-diff

# From specific release
helm plugin install https://github.com/databus23/helm-diff \
  --version v3.9.0

# From local directory
helm plugin install ./my-plugin

# Plugin is stored in $HELM_PLUGINS directory
ls $(helm env HELM_PLUGINS)
```

---

**Q104. What is the `post-renderer` option in Helm?**

`--post-renderer` passes rendered manifests through an **external command** before applying:

```bash
# Apply Kustomize patches on top of Helm-rendered manifests
helm install my-app ./chart \
  --post-renderer ./kustomize-wrapper.sh

# kustomize-wrapper.sh
#!/bin/bash
cat <&0 > /tmp/helm-output.yaml
kustomize build /tmp/helm-kustomize/ | cat
```

Useful for:
- Applying organizational policies on top of third-party charts
- Adding labels/annotations to all resources
- Patching resources you can't control via values

---

**Q105. How do you check if Helm is managing a specific Kubernetes resource?**

```bash
# Check labels on a resource
kubectl get deployment my-app -n production -o yaml | grep helm

# Helm-managed resources have:
# app.kubernetes.io/managed-by: Helm
# meta.helm.sh/release-name: my-app
# meta.helm.sh/release-namespace: production

# List all resources managed by a release
helm get manifest my-app -n production | grep "^  name:"
```

---

**Q106. What is the `--set-json` flag? (Helm 3.12+)**

```bash
# Set complex JSON values directly
helm install my-app ./chart \
  --set-json 'resources={"requests":{"cpu":"100m","memory":"128Mi"}}'

# Set a list
helm install my-app ./chart \
  --set-json 'ingress.hosts=["app.example.com","www.example.com"]'

# Set an object
helm install my-app ./chart \
  --set-json 'annotations={"prometheus.io/scrape":"true"}'
```

---

**Q107. How do you use Helm to manage Kubernetes Operators?**

```bash
# Many operators are installed via Helm

# Example: Install cert-manager (operator)
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true    # Install CRDs via --set (not crds/ directory)
  # Note: cert-manager uses installCRDs value to apply CRDs as templates

# After operator is running, create CRs (also managed by Helm if needed)
helm install my-app-certs ./my-certs-chart
# Where my-certs-chart contains Certificate and Issuer resources
```

---

**Q108. What is the `helm completion` command?**

```bash
# Generate shell completion scripts
helm completion bash > /etc/bash_completion.d/helm
helm completion zsh > ~/.zsh/completion/_helm

# Add to ~/.bashrc
source <(helm completion bash)
```

---

**Q109. How does Helm work with Kubernetes RBAC?**

In Helm 3 (no Tiller), Helm uses **the current user's Kubernetes credentials** for all operations. The user must have appropriate RBAC permissions:

```yaml
# Minimum RBAC for a developer to helm install in their namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: helm-deployer
  namespace: development
rules:
- apiGroups: ["", "apps", "batch", "networking.k8s.io"]
  resources: ["deployments", "services", "configmaps", "secrets", "ingresses", "jobs"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["secrets"]     # For Helm release history storage
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
```

---

**Q110. Summarize the full Helm workflow from chart development to production deployment.**

```
1. DEVELOPMENT
   helm create my-app             → Create chart skeleton
   # Edit templates, values.yaml
   helm lint ./my-app             → Check for errors
   helm template my-app ./my-app  → Review rendered YAML

2. TESTING
   helm install test-release ./my-app \
     --dry-run --debug            → Validate against cluster
   helm install test-release ./my-app \
     -n test --create-namespace   → Deploy to test namespace
   helm test test-release         → Run chart tests
   helm uninstall test-release    → Clean up

3. PACKAGING & PUBLISHING
   helm package ./my-app          → Create my-app-1.0.0.tgz
   helm push my-app-1.0.0.tgz \
     oci://registry.example.com/charts → Push to registry

4. STAGING DEPLOYMENT
   helm upgrade --install my-app \
     oci://registry.example.com/charts/my-app \
     --version 1.0.0 \
     --namespace staging \
     -f values-staging.yaml \
     --wait --atomic

5. PRODUCTION DEPLOYMENT
   helm diff upgrade my-app \
     oci://registry.example.com/charts/my-app \
     --version 1.0.0 \
     -f values-prod.yaml           → Review changes
   
   # After review approval:
   helm upgrade --install my-app \
     oci://registry.example.com/charts/my-app \
     --version 1.0.0 \
     --namespace production \
     -f values-prod.yaml \
     --atomic \
     --timeout 10m \
     --history-max 10

6. VERIFICATION
   helm status my-app -n production
   helm history my-app -n production
   kubectl get pods -n production
   helm test my-app -n production --logs
```

---

**Q111. What are the key Helm CLI commands to memorize for interviews?**

```bash
# Install/Upgrade
helm install <name> <chart>
helm upgrade --install <name> <chart>
helm uninstall <name>
helm rollback <name> [revision]

# Inspection
helm list [-n namespace]
helm status <name>
helm history <name>
helm get values/manifest/notes/hooks/all <name>

# Chart development
helm create <name>
helm lint <chart>
helm template <name> <chart>
helm package <chart>
helm dependency update/build/list

# Repository
helm repo add/list/update/remove
helm search repo/hub <term>
helm show chart/values/readme/all <chart>
helm pull <chart>
helm push <archive> <oci-url>

# Debug
helm install --dry-run --debug
helm diff upgrade (plugin)
helm test <name>
```

---

**Q112. What is the `helm env` variable `HELM_KUBECONTEXT`?**

```bash
# Use a specific kubeconfig context for Helm operations
export HELM_KUBECONTEXT=production-cluster

# Or per-command
helm install my-app ./chart --kube-context production-cluster

# Use specific namespace
export HELM_NAMESPACE=production
helm list    # Lists only in production namespace
```

---

**Q113. What is the difference between `type: application` and `type: library` in Chart.yaml?**

| `type: application` | `type: library` |
|---|---|
| Default type | Must be explicitly declared |
| Can be installed with `helm install` | Cannot be installed directly |
| Contains deployable resources | Contains only named templates |
| Can be a dependency | Can be a dependency |
| Included in rendered output | Only provides templates to other charts |

```yaml
# Library chart Chart.yaml
apiVersion: v2
name: common-templates
type: library
version: 1.0.0
```

---

**Q114. What is `helm registry` command family?**

```bash
# Login to OCI registry
helm registry login registry.example.com \
  --username myuser \
  --password mypass

# Logout
helm registry logout registry.example.com

# Check login status
cat $(helm env HELM_REGISTRY_CONFIG)
```

---

**Q115. How do you handle Helm chart upgrades that require manual intervention (e.g., immutable field changes)?**

```bash
# Problem: Changing a StatefulSet's VolumeClaimTemplate (immutable)
# Results in: "field is immutable"

# Solution 1: Delete and recreate (with downtime)
helm uninstall my-statefulset -n production
helm install my-statefulset ./chart -n production -f values.yaml

# Solution 2: Patch the resource directly, then upgrade
kubectl delete statefulset my-app -n production --cascade=orphan  # Keep PVCs
helm upgrade my-app ./chart -n production -f values.yaml

# Solution 3: For StatefulSet volume template changes
# - Scale down to 0
kubectl scale statefulset my-app --replicas=0 -n production
# - Delete StatefulSet without deleting pods/pvcs
kubectl delete statefulset my-app -n production --cascade=orphan
# - Re-apply via Helm
helm upgrade my-app ./chart -n production

# Prevention: Test upgrades in staging first; avoid changing immutable fields
```

---

**Q116. What is `helm install --replace` and when is it used?**

```bash
# Replaces a deleted (not uninstalled) release
# Reuses the same release name and slot in history

# Scenario: Release was deleted with --keep-history
helm uninstall my-app --keep-history

# Install replacement with same name
helm install --replace my-app ./chart

# Note: Rarely needed — helm upgrade --install covers most cases
```

---

**Q117. How do you manage Helm releases in multiple clusters from a single machine?**

```bash
# Method 1: --kube-context flag
helm install my-app ./chart --kube-context dev-cluster -n production
helm install my-app ./chart --kube-context prod-cluster -n production

# Method 2: KUBECONFIG environment variable
export KUBECONFIG=~/.kube/dev-config:~/.kube/prod-config
kubectl config use-context prod-cluster
helm list    # Now targets prod cluster

# Method 3: Separate KUBECONFIG files per operation
KUBECONFIG=~/.kube/prod-config helm upgrade my-app ./chart \
  -n production --atomic
```

---

**Q118. What is the `--generate-name` flag?**

```bash
# Let Helm generate a unique release name automatically
helm install --generate-name bitnami/nginx

# Output:
# NAME: nginx-1234567890
# Use this when you don't care about the release name (ephemeral envs, testing)
```

---

**Q119. How do you add notes and documentation to a Helm chart for other teams?**

```
# NOTES.txt — shown after install/upgrade
{{- if .Values.ingress.enabled }}
🌐 Your app is accessible at: https://{{ .Values.ingress.host }}
{{- else }}
📋 To access your app locally:
  kubectl port-forward svc/{{ include "my-app.fullname" . }} 8080:{{ .Values.service.port }} -n {{ .Release.Namespace }}
  Visit: http://localhost:8080
{{- end }}

📊 Monitor your deployment:
  kubectl get pods -n {{ .Release.Namespace }} -l app.kubernetes.io/instance={{ .Release.Name }}

🔄 To upgrade:
  helm upgrade {{ .Release.Name }} <chart> -n {{ .Release.Namespace }} --set image.tag=<new-tag>

📖 Documentation: https://docs.mycompany.com/my-app
```

```bash
# View notes at any time
helm get notes my-app
```

---

**Q120. What is the helm-docs tool and how does it help?**

`helm-docs` automatically generates **Markdown documentation** from a chart's `values.yaml` and `Chart.yaml`:

```bash
# Install
brew install norwoodj/tap/helm-docs

# Generate docs
helm-docs

# Creates README.md with:
# - Chart description
# - Table of all values with descriptions and defaults
# - Requirements table

# Comment style in values.yaml:
# -- Description for the value (double dash = included in docs)
replicaCount: 1
# -- Docker image configuration
image:
  # -- Image repository
  repository: nginx
  # -- Image tag
  tag: "1.25"
```

---

*End of Helm Interview Q&A — 120 Questions (All Levels)*

---

## Complete Interview Preparation Series

| Tool | File | Questions |
|---|---|---|
| Kubernetes | `interview-beginner-qa.md` | 120 |
| Kubernetes | `interview-intermediate-qa.md` | 120 |
| Kubernetes | `interview-advanced-qa.md` | 120 |
| Kubernetes | `interview-cka-ckad-qa.md` | 120 |
| ArgoCD | `argocd-interview-qa.md` | 120 |
| Terraform | `terraform-interview-qa.md` | 120 |
| Helm | `helm-interview-qa.md` | 120 |
| **Total** | | **840 questions** |

**Up Next: OpenShift EX280 prep** — say "next" to build it! 🚀
