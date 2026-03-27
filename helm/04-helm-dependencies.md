# 📦 Dependencies & Subcharts

Managing complex multi-chart applications — subcharts, conditions, tags, and global values.

---

## 📚 Table of Contents

- [1. Chart Dependencies Overview](#1-chart-dependencies-overview)
- [2. Declaring Dependencies](#2-declaring-dependencies)
- [3. Managing Dependencies](#3-managing-dependencies)
- [4. Subchart Values](#4-subchart-values)
- [5. Conditions & Tags](#5-conditions--tags)
- [6. Global Values](#6-global-values)
- [7. Library Charts](#7-library-charts)
- [8. Dependency Patterns](#8-dependency-patterns)
- [Cheatsheet](#cheatsheet)

---

## 1. Chart Dependencies Overview

A chart can depend on other charts (subcharts). When you install the parent chart, Helm installs all dependencies first.

```
my-app (parent chart)
├── postgresql (subchart — database)
├── redis (subchart — cache)
└── ingress-nginx (subchart — ingress controller)
```

**Why use subcharts?**
- Bundle dependencies with your chart — one `helm install` deploys everything
- Control subchart config through parent's values.yaml
- Enable/disable components per environment

---

## 2. Declaring Dependencies

```yaml
# Chart.yaml
dependencies:
  - name: postgresql           # chart name in the repo
    version: "12.5.6"          # exact version (recommended for reproducibility)
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled      # only include if this value is true
    alias: db                          # use this name instead of "postgresql"
    tags:
      - database                       # group tag for enable/disable

  - name: redis
    version: "~17.3.0"         # patch-level updates allowed (17.3.x)
    repository: https://charts.bitnami.com/bitnami
    condition: redis.enabled
    tags:
      - cache

  - name: common
    version: "^2.0.0"          # minor-level updates allowed (2.x.x)
    repository: https://charts.bitnami.com/bitnami

  # Local subchart (in charts/ directory)
  - name: my-internal-lib
    version: "1.0.0"
    repository: "file://../my-internal-lib"  # local path

  # OCI registry
  - name: my-chart
    version: "1.0.0"
    repository: "oci://registry.example.com/charts"
```

---

## 3. Managing Dependencies

```bash
# Download dependencies to charts/ directory
helm dependency update ./my-app
# Creates/updates Chart.lock

# Install from existing Chart.lock (reproducible — use in CI)
helm dependency build ./my-app

# List dependencies and their status
helm dependency list ./my-app
# NAME        VERSION  REPOSITORY                          STATUS
# postgresql  12.5.6   https://charts.bitnami.com/bitnami  ok
# redis       17.3.2   https://charts.bitnami.com/bitnami  ok

# After update, charts/ contains:
ls charts/
# postgresql-12.5.6.tgz  redis-17.3.2.tgz
```

### Chart.lock — pinning exact versions

```yaml
# Chart.lock (auto-generated, commit this!)
dependencies:
  - name: postgresql
    repository: https://charts.bitnami.com/bitnami
    version: 12.5.6           # exact version locked
  - name: redis
    repository: https://charts.bitnami.com/bitnami
    version: 17.3.2           # exact version locked
digest: sha256:abc123...      # integrity check
generated: "2024-01-15T10:00:00Z"
```

**Best practice:** Commit `Chart.lock` to Git. Use `helm dependency build` in CI to reproduce exact same versions.

---

## 4. Subchart Values

Configure subcharts through the parent chart's `values.yaml` using the subchart name as a key.

```yaml
# parent chart values.yaml

# Configure postgresql subchart (key = chart name or alias)
postgresql:
  enabled: true
  auth:
    database: myapp
    username: myapp
    password: ""              # use existingSecret instead
    existingSecret: db-secret
  primary:
    persistence:
      enabled: true
      size: 20Gi
      storageClass: fast-ssd
  metrics:
    enabled: true

# Configure redis subchart
redis:
  enabled: true
  auth:
    enabled: true
    existingSecret: redis-secret
  master:
    persistence:
      enabled: true
      size: 5Gi
  replica:
    replicaCount: 0           # no replicas in development

# Parent app config
replicaCount: 3
image:
  repository: myregistry/my-app
  tag: v1.2.3
```

### Overriding subchart values from CLI

```bash
# Use dot notation with subchart name
helm install my-app ./my-app \
  --set postgresql.auth.password=secret \
  --set postgresql.primary.persistence.size=50Gi \
  --set redis.enabled=false
```

### Accessing subchart values in parent templates

```yaml
# In parent chart templates, you CANNOT directly access subchart values
# The subchart renders its own templates independently

# But you CAN read parent values that were set for the subchart:
{{- if .Values.postgresql.enabled }}
# ... do something based on postgresql being enabled
{{- end }}
```

---

## 5. Conditions & Tags

### Conditions — enable/disable per value

```yaml
# Chart.yaml
dependencies:
  - name: postgresql
    condition: postgresql.enabled   # enable when this value is truthy
  - name: redis
    condition: redis.enabled

# values.yaml
postgresql:
  enabled: true    # postgresql subchart included
redis:
  enabled: false   # redis subchart excluded
```

```bash
# Override at install time
helm install my-app ./my-app \
  --set postgresql.enabled=false \
  --set redis.enabled=true
```

### Tags — group enable/disable

```yaml
# Chart.yaml
dependencies:
  - name: postgresql
    tags: [database, backend]
  - name: redis
    tags: [cache, backend]
  - name: elasticsearch
    tags: [search, backend]
  - name: ingress-nginx
    tags: [networking]

# values.yaml — disable all "backend" tagged charts at once
tags:
  backend: false
  networking: true
```

```bash
# Enable/disable by tag
helm install my-app ./my-app \
  --set tags.backend=false \
  --set tags.networking=true
```

**Condition takes priority over tag** if both are set.

---

## 6. Global Values

Global values are accessible in both parent and all subchart templates using `.Values.global`.

```yaml
# parent values.yaml
global:
  imageRegistry: myregistry.example.com     # subcharts can use this
  imagePullSecrets:
    - name: registry-credentials
  storageClass: fast-ssd
  postgresql:
    auth:
      postgresPassword: ""
      existingSecret: postgres-secret

# In a subchart template, access with:
{{ .Values.global.imageRegistry }}
{{ .Values.global.storageClass }}
```

### Example — shared image registry

```yaml
# parent values.yaml
global:
  imageRegistry: private-registry.example.com

# Bitnami charts respect global.imageRegistry automatically
# For your own subcharts, use it explicitly:

# subchart template
image: {{ .Values.global.imageRegistry | default "" }}/{{ .Values.image.repository }}:{{ .Values.image.tag }}
```

---

## 7. Library Charts

A **library chart** contains only reusable templates (no deployable resources). Other charts include it as a dependency.

```yaml
# Chart.yaml — library chart
apiVersion: v2
name: my-lib
type: library      # not "application"
version: 1.0.0
```

```yaml
# Library chart _helpers.tpl
{{- define "my-lib.labels" -}}
app.kubernetes.io/name: {{ .name }}
app.kubernetes.io/instance: {{ .instance }}
app.kubernetes.io/managed-by: Helm
{{- end }}

{{- define "my-lib.resources" -}}
requests:
  cpu: {{ .cpu | default "100m" }}
  memory: {{ .memory | default "128Mi" }}
limits:
  cpu: {{ mul (.cpu | default "100m" | trimSuffix "m" | int) 5 }}m
  memory: {{ .memory | default "256Mi" }}
{{- end }}
```

```yaml
# Consumer chart — Chart.yaml
dependencies:
  - name: my-lib
    version: "1.0.0"
    repository: "file://../my-lib"

# Consumer chart template
metadata:
  labels:
    {{- include "my-lib.labels" (dict "name" "my-app" "instance" .Release.Name) | nindent 4 }}
resources:
  {{- include "my-lib.resources" (dict "cpu" "200m" "memory" "256Mi") | nindent 2 }}
```

---

## 8. Dependency Patterns

### Pattern 1 — App + Database bundle

```yaml
# Complete application with database
# Chart.yaml
dependencies:
  - name: postgresql
    version: "12.x.x"
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled

# values.yaml
postgresql:
  enabled: true
  auth:
    database: myapp
    username: myapp
    existingSecret: db-credentials

config:
  database:
    # Point app to the postgresql subchart's service
    host: "{{ .Release.Name }}-postgresql"
    port: 5432
    name: myapp
```

```yaml
# Deployment template — reference subchart service name
env:
  - name: DATABASE_URL
    value: "postgresql://myapp@{{ .Release.Name }}-postgresql:5432/myapp"
```

### Pattern 2 — Umbrella chart (meta-chart)

An umbrella chart bundles multiple independent application charts:

```
platform/
├── Chart.yaml
├── values.yaml          # configure all subcharts
└── charts/              # all apps as subcharts
    ├── my-api/
    ├── my-frontend/
    ├── my-worker/
    └── postgresql/

# Deploy everything with one command:
helm install platform ./platform --values values-production.yaml
```

```yaml
# platform/Chart.yaml
dependencies:
  - name: my-api
    repository: "file://./my-api"
    version: "1.x.x"
    condition: api.enabled
  - name: my-frontend
    repository: "file://./my-frontend"
    version: "1.x.x"
    condition: frontend.enabled
  - name: postgresql
    repository: https://charts.bitnami.com/bitnami
    version: "12.x.x"
    condition: postgresql.enabled
```

### Pattern 3 — Environment-specific subchart enable/disable

```yaml
# values-development.yaml
postgresql:
  enabled: true    # use local postgres in dev

# values-production.yaml
postgresql:
  enabled: false   # use managed RDS in production
config:
  database:
    host: prod-db.us-east-1.rds.amazonaws.com
```

---

## Cheatsheet

```bash
# Dependency commands
helm dependency update ./my-chart     # download deps, update Chart.lock
helm dependency build ./my-chart      # install from Chart.lock (CI)
helm dependency list ./my-chart       # list deps and status

# Enable/disable subcharts
helm install my-app ./my-chart --set postgresql.enabled=false
helm install my-app ./my-chart --set tags.database=false

# Pull a subchart for inspection
helm pull bitnami/postgresql --untar --destination charts/

# Show all values including subchart defaults
helm install my-app ./my-chart --dry-run --debug 2>&1 | grep -A200 "COMPUTED VALUES"
```

```yaml
# Common dependency patterns in Chart.yaml
dependencies:
  - name: postgresql
    version: "12.x.x"                          # floating minor
    repository: https://charts.bitnami.com/bitnami
    condition: postgresql.enabled
    alias: db                                   # rename in values

  - name: common
    version: "^2.0.0"                          # floating major
    repository: https://charts.bitnami.com/bitnami

  - name: my-lib
    version: "1.0.0"
    repository: "file://../my-lib"             # local chart

# Global values (accessible in all subcharts)
global:
  imageRegistry: private.registry.example.com
  storageClass: fast-ssd
  imagePullSecrets:
    - name: registry-creds
```

---

*Next: [Hooks & Tests →](./05-hooks-tests.md)*
