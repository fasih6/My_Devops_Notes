# ⛵ Helm

Kubernetes package manager — install, upgrade, and manage complex applications with charts.

---

## 📚 Table of Contents

- [1. What is Helm?](#1-what-is-helm)
- [2. Core Concepts](#2-core-concepts)
- [3. Using Helm Charts](#3-using-helm-charts)
- [4. Chart Structure](#4-chart-structure)
- [5. Writing Charts](#5-writing-charts)
- [6. Values & Customization](#6-values--customization)
- [7. Helm Hooks](#7-helm-hooks)
- [8. Chart Repositories](#8-chart-repositories)
- [9. Helmfile](#9-helmfile)
- [Cheatsheet](#cheatsheet)

---

## 1. What is Helm?

Helm is the **package manager for Kubernetes**. Instead of managing dozens of individual YAML files, you use **charts** — pre-packaged, versioned, configurable application bundles.

```
Without Helm:                    With Helm:
───────────────                  ────────────
kubectl apply -f deployment.yaml helm install my-nginx nginx/nginx
kubectl apply -f service.yaml
kubectl apply -f ingress.yaml
kubectl apply -f configmap.yaml
kubectl apply -f hpa.yaml
```

Helm also tracks **releases** — what's installed, which version, what values were used — making upgrades and rollbacks straightforward.

---

## 2. Core Concepts

| Concept | What it is |
|---------|-----------|
| **Chart** | Package of Kubernetes manifests + templates + metadata |
| **Release** | A running instance of a chart in the cluster |
| **Repository** | Collection of charts (like apt repos) |
| **Values** | Configuration for a chart (like arguments) |
| **Revision** | A version of a release (increments on each upgrade) |

```bash
# Install Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Verify
helm version
```

---

## 3. Using Helm Charts

### Repository management

```bash
# Add a repository
helm repo add stable https://charts.helm.sh/stable
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add jetstack https://charts.jetstack.io
helm repo add bitnami https://charts.bitnami.com/bitnami

# Update repos (like apt update)
helm repo update

# List repos
helm repo list

# Search for charts
helm search repo nginx
helm search repo postgres
helm search hub nginx           # search Artifact Hub (public charts)

# Show chart details
helm show chart ingress-nginx/ingress-nginx
helm show values ingress-nginx/ingress-nginx  # default values
helm show readme ingress-nginx/ingress-nginx
```

### Installing charts

```bash
# Basic install
helm install my-nginx ingress-nginx/ingress-nginx

# Install in specific namespace (create if needed)
helm install my-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

# Install specific version
helm install my-nginx ingress-nginx/ingress-nginx \
  --version 4.7.1

# Override values inline
helm install my-nginx ingress-nginx/ingress-nginx \
  --set controller.replicaCount=2 \
  --set controller.service.type=LoadBalancer

# Override values with file
helm install my-nginx ingress-nginx/ingress-nginx \
  --values custom-values.yaml

# Dry run (see what would be deployed)
helm install my-nginx ingress-nginx/ingress-nginx \
  --dry-run --debug

# Install or upgrade (idempotent)
helm upgrade --install my-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values values.yaml
```

### Managing releases

```bash
# List releases
helm list
helm list -A                    # all namespaces
helm list -n monitoring

# Upgrade a release
helm upgrade my-nginx ingress-nginx/ingress-nginx \
  --values custom-values.yaml

# Rollback
helm rollback my-nginx          # rollback to previous revision
helm rollback my-nginx 2        # rollback to specific revision

# View release history
helm history my-nginx

# Get release values
helm get values my-nginx
helm get values my-nginx --all  # include default values

# Get rendered manifests
helm get manifest my-nginx

# Uninstall
helm uninstall my-nginx
helm uninstall my-nginx --keep-history   # keep release record
```

### Helm diff (great for seeing changes before upgrade)

```bash
# Install helm-diff plugin
helm plugin install https://github.com/databus23/helm-diff

# Show what would change
helm diff upgrade my-nginx ingress-nginx/ingress-nginx --values values.yaml
```

---

## 4. Chart Structure

```
my-chart/
├── Chart.yaml          # chart metadata (name, version, description)
├── values.yaml         # default configuration values
├── charts/             # chart dependencies (subcharts)
├── templates/          # Kubernetes manifest templates
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── configmap.yaml
│   ├── _helpers.tpl    # reusable template snippets
│   ├── NOTES.txt       # shown to user after install
│   └── tests/
│       └── test-connection.yaml
├── crds/               # Custom Resource Definitions (installed first)
└── README.md
```

### Chart.yaml

```yaml
apiVersion: v2            # Helm 3 uses v2
name: my-app
description: A Helm chart for My Application
type: application         # application or library

version: 1.2.3            # chart version (semver)
appVersion: "2.0.1"       # version of the app being packaged

keywords:
  - web
  - api

maintainers:
  - name: fasih
    email: fasih@example.com

dependencies:
  - name: postgresql
    version: "12.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled    # only include if this value is true
```

---

## 5. Writing Charts

### templates/deployment.yaml

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ include "my-app.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  replicas: {{ .Values.replicaCount }}
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      containers:
        - name: {{ .Chart.Name }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - containerPort: {{ .Values.service.targetPort }}
          {{- if .Values.resources }}
          resources:
            {{- toYaml .Values.resources | nindent 12 }}
          {{- end }}
          env:
            - name: APP_ENV
              value: {{ .Values.appEnv | quote }}
            {{- range .Values.extraEnv }}
            - name: {{ .name }}
              value: {{ .value | quote }}
            {{- end }}
```

### templates/_helpers.tpl

```
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
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "my-app.labels" -}}
helm.sh/chart: {{ include "my-app.chart" . }}
{{ include "my-app.selectorLabels" . }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "my-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "my-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
```

### Built-in Helm objects

| Object | Description |
|--------|-------------|
| `.Release.Name` | Name of the release |
| `.Release.Namespace` | Namespace of the release |
| `.Release.IsUpgrade` | True if this is an upgrade |
| `.Release.IsInstall` | True if this is a fresh install |
| `.Chart.Name` | Chart name from Chart.yaml |
| `.Chart.Version` | Chart version |
| `.Chart.AppVersion` | App version |
| `.Values` | Values from values.yaml and --set |
| `.Files` | Access non-template files |
| `.Capabilities.KubeVersion` | Kubernetes version |

---

## 6. Values & Customization

### values.yaml — default values

```yaml
# values.yaml
replicaCount: 1

image:
  repository: myregistry/my-app
  tag: ""                        # defaults to appVersion if empty
  pullPolicy: IfNotPresent

service:
  type: ClusterIP
  port: 80
  targetPort: 8080

ingress:
  enabled: false
  className: nginx
  hosts:
    - host: my-app.example.com
      paths:
        - path: /
          pathType: Prefix

resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80

appEnv: production
extraEnv: []
podAnnotations: {}

postgresql:
  enabled: true          # subchart toggle
  auth:
    database: myapp
    username: myapp
```

### Overriding values

```bash
# Inline (simple values)
helm install my-app ./my-chart \
  --set replicaCount=3 \
  --set image.tag=v1.2.3 \
  --set ingress.enabled=true

# Nested values with dot notation
helm install my-app ./my-chart \
  --set postgresql.auth.password=secret

# Lists with index
helm install my-app ./my-chart \
  --set extraEnv[0].name=DEBUG \
  --set extraEnv[0].value=true

# Values file (preferred for complex overrides)
helm install my-app ./my-chart \
  --values production-values.yaml

# Multiple values files (merged in order)
helm install my-app ./my-chart \
  --values base-values.yaml \
  --values production-values.yaml   # overrides base
```

### Environment-specific values files

```
my-chart/
├── values.yaml              # defaults
├── values-staging.yaml      # staging overrides
└── values-production.yaml   # production overrides
```

```yaml
# values-production.yaml
replicaCount: 3

resources:
  requests:
    cpu: 500m
    memory: 512Mi
  limits:
    cpu: 2
    memory: 1Gi

autoscaling:
  enabled: true
  minReplicas: 3
  maxReplicas: 20
```

```bash
helm upgrade --install my-app ./my-chart \
  --values values.yaml \
  --values values-production.yaml
```

---

## 7. Helm Hooks

Hooks let you run Jobs at specific points in the release lifecycle.

#### Purpose of Helm Hooks

Hooks are used for tasks that must happen at the right time, for example:
- Run database migrations before app starts
- Create or validate resources before deployment
- Run cleanup jobs before deleting a release
- Initialize data after installation

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "my-app.fullname" . }}-db-migrate
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install    # when to run
    "helm.sh/hook-weight": "-5"                # order (lower = earlier)
    "helm.sh/hook-delete-policy": hook-succeeded  # clean up after success
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag }}"
          command: ["/bin/sh", "-c", "/app/migrate"]
```

### Hook types

| Hook | When it runs |
|------|-------------|
| `pre-install` | Before any resources are created |
| `post-install` | After all resources are created |
| `pre-upgrade` | Before upgrade starts |
| `post-upgrade` | After upgrade completes |
| `pre-rollback` | Before rollback starts |
| `post-rollback` | After rollback completes |
| `pre-delete` | Before uninstall |
| `post-delete` | After uninstall |
| `test` | When `helm test` is run |

---

## 8. Chart Repositories

```bash
# Create your own chart
helm create my-chart

# Package chart into tarball
helm package ./my-chart
# Creates: my-chart-1.0.0.tgz

# Create repo index
helm repo index .

# Publish to GitHub Pages (common pattern)
# Push .tgz and index.yaml to gh-pages branch

# Use OCI registry (modern approach)
helm push my-chart-1.0.0.tgz oci://registry.example.com/charts
helm install my-app oci://registry.example.com/charts/my-chart --version 1.0.0

# Artifact Hub — public chart discovery
# https://artifacthub.io
```

### Chart dependencies

```yaml
# Chart.yaml
dependencies:
  - name: postgresql
    version: "12.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled

  - name: redis
    version: "17.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: redis.enabled
```

```bash
# Download dependencies
helm dependency update ./my-chart
# Downloads to charts/ directory

# Build dependencies (from lock file)
helm dependency build ./my-chart
```

---

## 9. Helmfile

Helmfile manages multiple Helm releases declaratively — like a Helm orchestrator.

```yaml
# helmfile.yaml
repositories:
  - name: ingress-nginx
    url: https://kubernetes.github.io/ingress-nginx
  - name: prometheus-community
    url: https://prometheus-community.github.io/helm-charts

releases:
  - name: ingress-nginx
    namespace: ingress-nginx
    createNamespace: true
    chart: ingress-nginx/ingress-nginx
    version: 4.7.1
    values:
      - values/ingress-nginx.yaml

  - name: prometheus
    namespace: monitoring
    createNamespace: true
    chart: prometheus-community/kube-prometheus-stack
    version: 51.2.0
    values:
      - values/prometheus.yaml

  - name: my-app
    namespace: production
    chart: ./charts/my-app
    values:
      - values/my-app-base.yaml
      - values/my-app-production.yaml
    secrets:
      - secrets/my-app-secrets.yaml    # encrypted with helm-secrets
```

```bash
# Install helmfile
brew install helmfile

# Apply all releases
helmfile apply

# Sync (install/upgrade)
helmfile sync

# Diff (see changes)
helmfile diff

# Destroy all releases
helmfile destroy
```

---

## Cheatsheet

```bash
# Repos
helm repo add <name> <url>
helm repo update
helm search repo <keyword>

# Install
helm install <release> <chart> --namespace <ns> --create-namespace
helm install <release> <chart> --values values.yaml --set key=value
helm upgrade --install <release> <chart> --values values.yaml   # idempotent

# Manage releases
helm list -A
helm status <release>
helm history <release>
helm rollback <release>
helm uninstall <release>

# Inspect
helm get values <release>
helm get manifest <release>
helm show values <chart>

# Develop
helm create my-chart
helm lint ./my-chart
helm template ./my-chart --values values.yaml    # render templates locally
helm package ./my-chart

# Debug
helm install <release> <chart> --dry-run --debug
```

---

*Next: [Observability →](./08-observability.md) — metrics-server, HPA, VPA, and resource management.*
