# 🏗️ Chart Development

Writing production-grade Helm charts from scratch — structure, patterns, and best practices.

---

## 📚 Table of Contents

- [1. Chart Scaffold](#1-chart-scaffold)
- [2. Chart.yaml Deep Dive](#2-chartyaml-deep-dive)
- [3. values.yaml Design](#3-valuesyaml-design)
- [4. Writing Templates](#4-writing-templates)
- [5. NOTES.txt](#5-notestxt)
- [6. Validating & Linting](#7-validating--linting)
- [7. Chart Best Practices](#8-chart-best-practices)
- [8. Complete Example — Production Chart](#9-complete-example--production-chart)
- [Cheatsheet](#cheatsheet)

---

## 1. Chart Scaffold

```bash
# Create new chart with standard scaffold
helm create my-app

# Structure created:
my-app/
├── Chart.yaml              # metadata
├── values.yaml             # default values
├── charts/                 # dependencies
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   ├── ingress.yaml
│   ├── serviceaccount.yaml
│   ├── hpa.yaml
│   ├── _helpers.tpl        # reusable template snippets
│   ├── NOTES.txt           # post-install message
│   └── tests/
│       └── test-connection.yaml
└── .helmignore             # files to exclude when packaging
```

### .helmignore

```
# .helmignore
.git/
.gitignore
*.md
tests/
docs/
*.bak
```

---

## 2. Chart.yaml Deep Dive

```yaml
# Chart.yaml — complete example
apiVersion: v2                    # always v2 for Helm 3

name: my-app
description: A production-ready chart for My Application
type: application                 # application or library

# Chart version — increment when chart changes
# appVersion — version of the packaged application (informational)
version: 1.3.0
appVersion: "2.1.5"

keywords:
  - web
  - api
  - microservice

home: https://github.com/myorg/my-app
sources:
  - https://github.com/myorg/my-app

maintainers:
  - name: Fasih
    email: fasih@example.com
    url: https://github.com/fasih

icon: https://example.com/icon.png

# Minimum Helm version required
kubeVersion: ">=1.24.0"

# Annotations (used by tools like Artifact Hub)
annotations:
  artifacthub.io/category: integration-delivery
  artifacthub.io/license: MIT
  artifacthub.io/prerelease: "false"
  artifacthub.io/changes: |
    - kind: added
      description: Support for PodDisruptionBudget
    - kind: fixed
      description: Fixed ingress TLS configuration

# Dependencies (subcharts)
dependencies:
  - name: postgresql
    version: "12.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled
    tags:
      - database
  - name: redis
    version: "17.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: redis.enabled
    tags:
      - cache
```

---

## 3. values.yaml Design

Good `values.yaml` design makes your chart easy to use and hard to misconfigure.

```yaml
# values.yaml — well-structured example

# ── Replica & Scaling ────────────────────────────────────────────
replicaCount: 1

autoscaling:
  enabled: false
  minReplicas: 1
  maxReplicas: 10
  targetCPUUtilizationPercentage: 80
  targetMemoryUtilizationPercentage: 80

# ── Image ────────────────────────────────────────────────────────
image:
  repository: myregistry/my-app
  pullPolicy: IfNotPresent
  # Overrides Chart.appVersion when set
  tag: ""

imagePullSecrets: []
# - name: registry-credentials

# ── Service Account ──────────────────────────────────────────────
serviceAccount:
  create: true
  automount: false
  annotations: {}
  name: ""           # generated from fullname if empty

# ── Pod Configuration ────────────────────────────────────────────
podAnnotations: {}
podLabels: {}

podSecurityContext:
  runAsNonRoot: true
  runAsUser: 1000
  fsGroup: 2000
  seccompProfile:
    type: RuntimeDefault

securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]

# ── Service ──────────────────────────────────────────────────────
service:
  type: ClusterIP
  port: 80
  targetPort: 8080
  annotations: {}

# ── Ingress ──────────────────────────────────────────────────────
ingress:
  enabled: false
  className: nginx
  annotations: {}
  # cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: my-app.example.com
      paths:
        - path: /
          pathType: Prefix
  tls: []
  # - secretName: my-app-tls
  #   hosts:
  #     - my-app.example.com

# ── Resources ────────────────────────────────────────────────────
resources:
  requests:
    cpu: 100m
    memory: 128Mi
  limits:
    cpu: 500m
    memory: 256Mi

# ── Health Probes ────────────────────────────────────────────────
livenessProbe:
  httpGet:
    path: /healthz
    port: http
  initialDelaySeconds: 15
  periodSeconds: 20
  failureThreshold: 3

readinessProbe:
  httpGet:
    path: /ready
    port: http
  initialDelaySeconds: 5
  periodSeconds: 5
  failureThreshold: 3

startupProbe:
  enabled: false
  httpGet:
    path: /healthz
    port: http
  failureThreshold: 30
  periodSeconds: 10

# ── Scheduling ───────────────────────────────────────────────────
nodeSelector: {}
tolerations: []
affinity: {}

topologySpreadConstraints: []
# - maxSkew: 1
#   topologyKey: kubernetes.io/hostname
#   whenUnsatisfiable: DoNotSchedule
#   labelSelector:
#     matchLabels:
#       app.kubernetes.io/name: my-app

# ── Application Config ───────────────────────────────────────────
config:
  logLevel: info
  port: 8080
  metricsEnabled: true
  database:
    host: ""          # required — will fail if empty
    port: 5432
    name: myapp

# ── Extra Configuration ──────────────────────────────────────────
extraEnv: []
# - name: MY_VAR
#   value: my-value

extraEnvFrom: []
# - configMapRef:
#     name: extra-config

extraVolumes: []
extraVolumeMounts: []

# ── PodDisruptionBudget ──────────────────────────────────────────
podDisruptionBudget:
  enabled: false
  minAvailable: 1
  # maxUnavailable: 1

# ── Monitoring ───────────────────────────────────────────────────
metrics:
  enabled: false
  port: 9090
  serviceMonitor:
    enabled: false
    interval: 30s
    namespace: monitoring

# ── Dependencies ─────────────────────────────────────────────────
postgresql:
  enabled: false
  auth:
    database: myapp
    username: myapp
    existingSecret: ""

redis:
  enabled: false
  auth:
    enabled: false
```

---

## 4. Writing Templates

### templates/deployment.yaml

```yaml
{{- $fullname := include "my-app.fullname" . }}
apiVersion: apps/v1
kind: Deployment
metadata:
  name: {{ $fullname }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
  {{- with .Values.deploymentAnnotations }}
  annotations:
    {{- toYaml . | nindent 4 }}
  {{- end }}
spec:
  {{- if not .Values.autoscaling.enabled }}
  replicas: {{ .Values.replicaCount }}
  {{- end }}
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
        {{- with .Values.podLabels }}
        {{- toYaml . | nindent 8 }}
        {{- end }}
      {{- with .Values.podAnnotations }}
      annotations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
    spec:
      {{- with .Values.imagePullSecrets }}
      imagePullSecrets:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      serviceAccountName: {{ include "my-app.serviceAccountName" . }}
      automountServiceAccountToken: {{ .Values.serviceAccount.automount }}
      {{- with .Values.podSecurityContext }}
      securityContext:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      containers:
        - name: {{ .Chart.Name }}
          {{- with .Values.securityContext }}
          securityContext:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          ports:
            - name: http
              containerPort: {{ .Values.config.port }}
              protocol: TCP
            {{- if .Values.metrics.enabled }}
            - name: metrics
              containerPort: {{ .Values.metrics.port }}
              protocol: TCP
            {{- end }}
          {{- with .Values.livenessProbe }}
          livenessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.readinessProbe }}
          readinessProbe:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- if .Values.startupProbe.enabled }}
          startupProbe:
            {{- omit .Values.startupProbe "enabled" | toYaml | nindent 12 }}
          {{- end }}
          {{- with .Values.resources }}
          resources:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          env:
            - name: APP_PORT
              value: {{ .Values.config.port | quote }}
            - name: LOG_LEVEL
              value: {{ .Values.config.logLevel | quote }}
            - name: DB_HOST
              value: {{ .Values.config.database.host | required "config.database.host is required" | quote }}
            {{- with .Values.extraEnv }}
            {{- toYaml . | nindent 12 }}
            {{- end }}
          {{- with .Values.extraEnvFrom }}
          envFrom:
            {{- toYaml . | nindent 12 }}
          {{- end }}
          {{- with .Values.extraVolumeMounts }}
          volumeMounts:
            {{- toYaml . | nindent 12 }}
          {{- end }}
      {{- with .Values.extraVolumes }}
      volumes:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.nodeSelector }}
      nodeSelector:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.affinity }}
      affinity:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.tolerations }}
      tolerations:
        {{- toYaml . | nindent 8 }}
      {{- end }}
      {{- with .Values.topologySpreadConstraints }}
      topologySpreadConstraints:
        {{- toYaml . | nindent 8 }}
      {{- end }}
```

### templates/hpa.yaml

```yaml
{{- if .Values.autoscaling.enabled }}
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: {{ include "my-app.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: {{ include "my-app.fullname" . }}
  minReplicas: {{ .Values.autoscaling.minReplicas }}
  maxReplicas: {{ .Values.autoscaling.maxReplicas }}
  metrics:
    {{- if .Values.autoscaling.targetCPUUtilizationPercentage }}
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetCPUUtilizationPercentage }}
    {{- end }}
    {{- if .Values.autoscaling.targetMemoryUtilizationPercentage }}
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: {{ .Values.autoscaling.targetMemoryUtilizationPercentage }}
    {{- end }}
{{- end }}
```

### templates/pdb.yaml

```yaml
{{- if .Values.podDisruptionBudget.enabled }}
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: {{ include "my-app.fullname" . }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  {{- if .Values.podDisruptionBudget.minAvailable }}
  minAvailable: {{ .Values.podDisruptionBudget.minAvailable }}
  {{- else if .Values.podDisruptionBudget.maxUnavailable }}
  maxUnavailable: {{ .Values.podDisruptionBudget.maxUnavailable }}
  {{- end }}
{{- end }}
```

### templates/servicemonitor.yaml

```yaml
{{- if and .Values.metrics.enabled .Values.metrics.serviceMonitor.enabled }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: {{ include "my-app.fullname" . }}
  namespace: {{ .Values.metrics.serviceMonitor.namespace | default .Release.Namespace }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
spec:
  selector:
    matchLabels:
      {{- include "my-app.selectorLabels" . | nindent 6 }}
  endpoints:
    - port: metrics
      interval: {{ .Values.metrics.serviceMonitor.interval }}
      path: /metrics
{{- end }}
```

---

## 5. NOTES.txt

Displayed to the user after install/upgrade — use it to show connection info and next steps.

```
{{- $fullname := include "my-app.fullname" . }}
🚀 {{ .Chart.Name }} has been deployed!

Release:   {{ .Release.Name }}
Namespace: {{ .Release.Namespace }}
Version:   {{ .Chart.AppVersion }}

{{- if .Values.ingress.enabled }}
{{- range .Values.ingress.hosts }}
Access your application at:
  {{- if $.Values.ingress.tls }}
  https://{{ .host }}
  {{- else }}
  http://{{ .host }}
  {{- end }}
{{- end }}

{{- else if contains "LoadBalancer" .Values.service.type }}
Get the external IP:
  kubectl get svc {{ $fullname }} -n {{ .Release.Namespace }} -w

{{- else }}
Forward a local port to access the application:
  kubectl port-forward svc/{{ $fullname }} 8080:{{ .Values.service.port }} -n {{ .Release.Namespace }}
  Then open: http://localhost:8080

{{- end }}

View logs:
  kubectl logs -l app.kubernetes.io/name={{ include "my-app.name" . }} -n {{ .Release.Namespace }} -f

{{- if .Values.postgresql.enabled }}

⚠️  PostgreSQL is running as a subchart.
    To connect: kubectl exec -it {{ $fullname }}-postgresql-0 -n {{ .Release.Namespace }} -- psql -U {{ .Values.postgresql.auth.username }}
{{- end }}
```

---

## 6. Validating & Linting

```bash
# Lint chart (checks YAML syntax and basic Helm best practices)
helm lint ./my-chart
helm lint ./my-chart --strict          # fail on warnings too
helm lint ./my-chart -f values-prod.yaml

# Render templates locally (no cluster needed)
helm template my-release ./my-chart
helm template my-release ./my-chart --values values-prod.yaml
helm template my-release ./my-chart --set image.tag=v1.2.3 | kubectl apply --dry-run=client -f -

# Validate against live cluster API
helm install my-app ./my-chart --dry-run --generate-name
helm upgrade my-app ./my-chart --dry-run

# Schema validation — add values.schema.json to enforce value types
```

### values.schema.json

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "properties": {
    "replicaCount": {
      "type": "integer",
      "minimum": 1
    },
    "image": {
      "type": "object",
      "properties": {
        "repository": { "type": "string" },
        "tag": { "type": "string" },
        "pullPolicy": {
          "type": "string",
          "enum": ["Always", "IfNotPresent", "Never"]
        }
      },
      "required": ["repository"]
    },
    "service": {
      "type": "object",
      "properties": {
        "type": {
          "type": "string",
          "enum": ["ClusterIP", "NodePort", "LoadBalancer"]
        },
        "port": {
          "type": "integer",
          "minimum": 1,
          "maximum": 65535
        }
      }
    }
  }
}
```

---

## 7. Chart Best Practices

### Naming conventions

```yaml
# Use app.kubernetes.io labels (standard)
labels:
  app.kubernetes.io/name: {{ include "my-app.name" . }}
  app.kubernetes.io/instance: {{ .Release.Name }}
  app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
  app.kubernetes.io/managed-by: {{ .Release.Service }}
  helm.sh/chart: {{ include "my-app.chart" . }}
```

### Always use `{{- with }}` for optional values

```yaml
# Good — skips block if tolerations is empty
{{- with .Values.tolerations }}
tolerations:
  {{- toYaml . | nindent 8 }}
{{- end }}

# Bad — renders empty tolerations: key
tolerations:
  {{ toYaml .Values.tolerations | nindent 8 }}
```

### Use `required` for mandatory values

```yaml
# Fails helm install with a clear error if not set
host: {{ .Values.config.database.host | required "config.database.host is required" }}
```

### Quote string values

```yaml
# Always quote values that could be interpreted as numbers or booleans
value: {{ .Values.someString | quote }}
# Without quote: "true" becomes true (boolean), "1" becomes 1 (int)
```

### Never hardcode namespaces in templates

```yaml
# Bad
namespace: production

# Good
namespace: {{ .Release.Namespace }}
```

---

## 8. Complete Example — Production Chart

```bash
my-app/
├── Chart.yaml
├── values.yaml
├── values.schema.json        # schema validation
├── charts/                   # dependencies (after helm dep update)
├── .helmignore
└── templates/
    ├── _helpers.tpl
    ├── deployment.yaml
    ├── service.yaml
    ├── serviceaccount.yaml
    ├── ingress.yaml
    ├── configmap.yaml
    ├── hpa.yaml
    ├── pdb.yaml
    ├── servicemonitor.yaml   # for Prometheus
    ├── NOTES.txt
    └── tests/
        └── test-connection.yaml
```

```bash
# Develop workflow
helm create my-app              # scaffold
# edit Chart.yaml, values.yaml, templates/

helm lint ./my-app              # check for errors
helm template release ./my-app  # verify rendered output
helm install my-app ./my-app --dry-run --debug  # test against cluster

# Package
helm package ./my-app           # creates my-app-1.0.0.tgz
```

---

## Cheatsheet

```bash
# Create and scaffold
helm create my-chart
helm lint ./my-chart
helm lint ./my-chart --strict

# Render templates
helm template release ./my-chart
helm template release ./my-chart --values prod.yaml > rendered.yaml

# Test
helm install test ./my-chart --dry-run --debug
helm install test ./my-chart --dry-run --debug 2>&1 | grep -A50 "MANIFEST:"

# Package
helm package ./my-chart
helm package ./my-chart --version 1.2.3

# Key template patterns
{{ include "chart.fullname" . }}
{{ .Values.key | default "fallback" }}
{{ .Values.key | required "key is required" }}
{{ .Values.key | quote }}
{{- with .Values.optional }}...{{- end }}
{{- if .Values.feature.enabled }}...{{- end }}
```

---

*Next: [Templating Deep Dive →](./03-templating-deep-dive.md)*
