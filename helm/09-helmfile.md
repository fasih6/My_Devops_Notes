# 📋 Helmfile

Declaratively manage multiple Helm releases — the GitOps way.

---

## 📚 Table of Contents

- [1. What is Helmfile?](#1-what-is-helmfile)
- [2. Installation](#2-installation)
- [3. Helmfile Structure](#3-helmfile-structure)
- [4. Releases](#4-releases)
- [5. Environments](#5-environments)
- [6. Templating in Helmfile](#6-templating-in-helmfile)
- [7. Hooks in Helmfile](#7-hooks-in-helmfile)
- [8. Helmfile in CI/CD](#8-helmfile-in-cicd)
- [9. Real-World Example](#9-real-world-example)
- [Cheatsheet](#cheatsheet)

---

## 1. What is Helmfile?

Helmfile is a declarative spec for deploying Helm charts. Instead of running multiple `helm install/upgrade` commands, you define all releases in one `helmfile.yaml` and apply them with a single command.

```
Without Helmfile:                     With Helmfile:
──────────────────────────────        ─────────────────────
helm install ingress ...              helmfile apply
helm install cert-manager ...
helm install prometheus ...
helm install grafana ...
helm install my-app ...
# 5 separate commands, easy to forget one
# No declarative state, hard to reproduce
```

**Key features:**
- Declarative — describe desired state, not imperative commands
- Environment support — different values per environment
- Diff before apply — see what changes before making them
- Dependency ordering — install charts in the right order
- Native secrets support (helm-secrets integration)

---

## 2. Installation

```bash
# macOS
brew install helmfile

# Linux
curl -L https://github.com/helmfile/helmfile/releases/latest/download/helmfile_linux_amd64.tar.gz \
  | tar xz
sudo mv helmfile /usr/local/bin/

# Verify
helmfile version

# Install required Helm plugins
helm plugin install https://github.com/databus23/helm-diff
helm plugin install https://github.com/jkroepke/helm-secrets  # if using secrets
```

---

## 3. Helmfile Structure

```
infrastructure/
├── helmfile.yaml          # main helmfile (or helmfile.d/ directory)
├── helmfile.d/            # split across multiple files
│   ├── 00-repos.yaml
│   ├── 01-infrastructure.yaml
│   ├── 02-monitoring.yaml
│   └── 03-apps.yaml
├── values/
│   ├── prometheus.yaml
│   ├── grafana.yaml
│   └── my-app.yaml
├── secrets/
│   ├── my-app.enc.yaml    # encrypted with SOPS
│   └── grafana.enc.yaml
└── environments/
    ├── staging.yaml
    └── production.yaml
```

### helmfile.d/ — split into multiple files

```bash
# helmfile reads all .yaml files in helmfile.d/ directory
helmfile --file helmfile.d/ apply
# or set default:
# HELMFILE_DIR=helmfile.d helmfile apply
```

---

## 4. Releases

### Basic helmfile.yaml

```yaml
# helmfile.yaml
repositories:
  - name: ingress-nginx
    url: https://kubernetes.github.io/ingress-nginx
  - name: prometheus-community
    url: https://prometheus-community.github.io/helm-charts
  - name: grafana
    url: https://grafana.github.io/helm-charts
  - name: jetstack
    url: https://charts.jetstack.io
  - name: bitnami
    url: https://charts.bitnami.com/bitnami

releases:
  # Infrastructure
  - name: ingress-nginx
    namespace: ingress-nginx
    createNamespace: true
    chart: ingress-nginx/ingress-nginx
    version: 4.7.1
    values:
      - values/ingress-nginx.yaml

  - name: cert-manager
    namespace: cert-manager
    createNamespace: true
    chart: jetstack/cert-manager
    version: v1.13.0
    set:
      - name: installCRDs
        value: true

  # Monitoring stack
  - name: prometheus
    namespace: monitoring
    createNamespace: true
    chart: prometheus-community/kube-prometheus-stack
    version: 51.2.0
    values:
      - values/prometheus.yaml
    secrets:
      - secrets/prometheus.enc.yaml

  - name: loki
    namespace: monitoring
    chart: grafana/loki-stack
    version: 2.9.11
    values:
      - values/loki.yaml

  # Application
  - name: my-app
    namespace: production
    createNamespace: true
    chart: ./charts/my-app       # local chart
    version: ~              # use local version
    values:
      - values/my-app.yaml
    secrets:
      - secrets/my-app.enc.yaml
    needs:
      - ingress-nginx/ingress-nginx   # install ingress-nginx first
      - cert-manager/cert-manager
```

### Release configuration options

```yaml
releases:
  - name: my-app                    # release name
    namespace: production           # target namespace
    createNamespace: true           # create namespace if missing
    chart: myrepo/my-chart          # chart to use
    version: 1.2.3                  # chart version
    installed: true                 # set to false to uninstall

    # Values
    values:
      - values/base.yaml            # values files
      - values/production.yaml
    set:
      - name: image.tag             # --set equivalent
        value: v1.2.3
      - name: replicaCount
        value: 3
    setString:
      - name: config.port           # --set-string equivalent
        value: "8080"
    secrets:
      - secrets/my-app.enc.yaml     # decrypted before use

    # Wait & atomic
    wait: true                      # wait for resources to be ready
    timeout: 600                    # timeout in seconds
    atomic: true                    # rollback on failure
    cleanupOnFail: true             # delete new resources on upgrade failure

    # Hooks
    hooks:
      - events: [presync]
        command: echo
        args: ["deploying..."]
      - events: [postsync]
        command: ./scripts/notify.sh
        args: ["{{`{{ .Release.Name }}`}}", "deployed"]

    # Needs (install order)
    needs:
      - namespace/release-name      # wait for this release first

    # Labels (for filtering)
    labels:
      tier: app
      team: backend

    # Disable diff for this release (e.g., frequently changing CRDs)
    disableValidation: false
```

---

## 5. Environments

Environments let you use different values per target environment.

```yaml
# helmfile.yaml
environments:
  staging:
    values:
      - environments/staging.yaml
    secrets:
      - environments/staging.enc.yaml

  production:
    values:
      - environments/production.yaml
    secrets:
      - environments/production.enc.yaml

---
releases:
  - name: my-app
    namespace: "{{ .Environment.Name }}"    # uses environment name
    chart: ./charts/my-app
    values:
      - values/my-app.yaml
      - "values/my-app-{{ .Environment.Name }}.yaml"   # environment-specific
    set:
      - name: replicaCount
        value: "{{ .Environment.Values.replicaCount }}"
```

```yaml
# environments/staging.yaml
replicaCount: 1
image:
  tag: latest
ingress:
  host: staging.my-app.example.com
resources:
  requests:
    cpu: 100m
    memory: 128Mi

# environments/production.yaml
replicaCount: 3
image:
  tag: v1.2.3
ingress:
  host: my-app.example.com
resources:
  requests:
    cpu: 500m
    memory: 512Mi
```

```bash
# Apply for specific environment
helmfile --environment staging apply
helmfile --environment production apply
helmfile -e production diff
```

---

## 6. Templating in Helmfile

Helmfile supports Go templating in `helmfile.yaml`:

```yaml
# Access environment values
replicas: {{ .Environment.Values.replicaCount | default 1 }}

# Conditional release
{{- if eq .Environment.Name "production" }}
  - name: monitoring-alerts
    chart: ./charts/alerts
{{- end }}

# Loop over a list
{{- range .Values.regions }}
  - name: my-app-{{ . }}
    namespace: "{{ . }}"
    chart: ./charts/my-app
{{- end }}

# Environment variable
image:
  tag: {{ requiredEnv "IMAGE_TAG" }}         # fail if not set
  repo: {{ env "IMAGE_REPO" | default "myregistry/my-app" }}

# Read from file
config: {{ readFile "config/app.conf" | toYaml | indent 2 }}

# Exec command output
clusterName: {{ exec "kubectl" (list "config" "current-context") | trim }}
```

### Defaults across all releases

```yaml
# helmfile.yaml
helmDefaults:
  wait: true
  timeout: 600
  atomic: true
  cleanupOnFail: true
  createNamespace: true
  historyMax: 5
  force: false

releases:
  # All releases inherit helmDefaults
  - name: my-app
    chart: ./charts/my-app
    # Can override per-release:
    wait: false
    timeout: 300
```

---

## 7. Hooks in Helmfile

```yaml
releases:
  - name: my-app
    chart: ./charts/my-app
    hooks:
      # Before sync — validation
      - events: [presync]
        command: "/bin/sh"
        args:
          - "-c"
          - "curl -sf https://healthcheck.example.com || exit 1"
        showlogs: true

      # After sync — notification
      - events: [postsync]
        command: "/bin/sh"
        args:
          - "-c"
          - |
            curl -X POST $SLACK_WEBHOOK \
              -H "Content-Type: application/json" \
              -d '{"text": "Deployed my-app to {{ .Environment.Name }}"}'
        showlogs: true

      # On cleanup (helmfile destroy)
      - events: [cleanup]
        command: echo
        args: ["Cleaning up my-app..."]
```

---

## 8. Helmfile in CI/CD

```yaml
# .github/workflows/helmfile-deploy.yml
name: Helmfile Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install tools
        run: |
          # Helm
          curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
          helm plugin install https://github.com/databus23/helm-diff
          helm plugin install https://github.com/jkroepke/helm-secrets

          # Helmfile
          curl -L https://github.com/helmfile/helmfile/releases/latest/download/helmfile_linux_amd64.tar.gz \
            | tar xz
          sudo mv helmfile /usr/local/bin/

      - name: Configure AWS (for SOPS KMS)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789:role/github-actions
          aws-region: eu-central-1

      - name: Configure kubectl
        uses: azure/k8s-set-context@v3
        with:
          kubeconfig: ${{ secrets.KUBE_CONFIG }}

      - name: Diff (staging)
        run: helmfile --environment staging diff

      - name: Apply (staging)
        run: helmfile --environment staging apply --suppress-diff

      - name: Test (staging)
        run: helmfile --environment staging test

      - name: Diff (production)
        run: helmfile --environment production diff

      - name: Apply (production)
        run: helmfile --environment production apply --suppress-diff
```

---

## 9. Real-World Example

### Full platform helmfile

```yaml
# helmfile.yaml — complete platform
repositories:
  - name: ingress-nginx
    url: https://kubernetes.github.io/ingress-nginx
  - name: prometheus-community
    url: https://prometheus-community.github.io/helm-charts
  - name: grafana
    url: https://grafana.github.io/helm-charts
  - name: jetstack
    url: https://charts.jetstack.io
  - name: external-secrets
    url: https://charts.external-secrets.io
  - name: argo
    url: https://argoproj.github.io/argo-helm

helmDefaults:
  wait: true
  timeout: 600
  atomic: true
  createNamespace: true

environments:
  staging:
    values:
      - environments/staging.yaml
  production:
    values:
      - environments/production.yaml
    secrets:
      - environments/production.enc.yaml

releases:
  # ── Layer 1: Core Infrastructure ────────────────────────────
  - name: cert-manager
    namespace: cert-manager
    chart: jetstack/cert-manager
    version: v1.13.0
    set:
      - name: installCRDs
        value: true
    labels:
      layer: infrastructure

  - name: external-secrets
    namespace: external-secrets
    chart: external-secrets/external-secrets
    version: 0.9.0
    needs:
      - cert-manager/cert-manager
    labels:
      layer: infrastructure

  - name: ingress-nginx
    namespace: ingress-nginx
    chart: ingress-nginx/ingress-nginx
    version: 4.7.1
    values:
      - values/ingress-nginx.yaml
      - "values/ingress-nginx-{{ .Environment.Name }}.yaml"
    labels:
      layer: infrastructure

  # ── Layer 2: Monitoring ──────────────────────────────────────
  - name: prometheus
    namespace: monitoring
    chart: prometheus-community/kube-prometheus-stack
    version: 51.2.0
    values:
      - values/prometheus.yaml
    secrets:
      - secrets/prometheus.enc.yaml
    needs:
      - cert-manager/cert-manager
    labels:
      layer: monitoring

  - name: loki
    namespace: monitoring
    chart: grafana/loki-stack
    version: 2.9.11
    values:
      - values/loki.yaml
    needs:
      - monitoring/prometheus
    labels:
      layer: monitoring

  # ── Layer 3: Applications ────────────────────────────────────
  - name: my-api
    namespace: "{{ .Environment.Name }}"
    chart: oci://ghcr.io/myorg/charts/my-api
    version: "{{ .Environment.Values.apiVersion }}"
    values:
      - values/my-api.yaml
    secrets:
      - secrets/my-api.enc.yaml
    needs:
      - ingress-nginx/ingress-nginx
      - external-secrets/external-secrets
    labels:
      layer: app
      team: backend

  - name: my-frontend
    namespace: "{{ .Environment.Name }}"
    chart: oci://ghcr.io/myorg/charts/my-frontend
    version: "{{ .Environment.Values.frontendVersion }}"
    values:
      - values/my-frontend.yaml
    needs:
      - ingress-nginx/ingress-nginx
    labels:
      layer: app
      team: frontend
```

### Selective operations

```bash
# Apply only infrastructure layer
helmfile --environment production apply --selector layer=infrastructure

# Apply only monitoring
helmfile --environment production apply --selector layer=monitoring

# Apply only a specific team's apps
helmfile --environment production apply --selector team=backend

# Diff a specific release
helmfile --environment production diff --selector name=my-api

# Apply a single release
helmfile --environment production apply --selector name=my-api
```

---

## Cheatsheet

```bash
# Core commands
helmfile apply                        # apply all releases
helmfile diff                         # show what would change
helmfile sync                         # sync (like apply but more aggressive)
helmfile destroy                      # uninstall all releases
helmfile list                         # list all releases and status
helmfile test                         # run helm tests for all releases

# Environment targeting
helmfile --environment production apply
helmfile -e staging diff

# Selective targeting (labels)
helmfile apply --selector layer=infrastructure
helmfile apply --selector name=my-app
helmfile diff --selector team=backend

# Dry run
helmfile apply --dry-run

# With debug output
helmfile --debug apply

# Suppress diff output (for CI)
helmfile apply --suppress-diff

# Check repos/dependencies
helmfile repos          # add/update all repos
helmfile deps           # update chart dependencies
```

---

*Next: [Interview Q&A →](./10-interview-qa.md)*
