# Flux v2 Core

## What Is Flux?

Flux v2 is a set of Kubernetes controllers (the GitOps Toolkit) that continuously reconcile cluster state to match what's defined in Git. Unlike ArgoCD, Flux has no built-in UI — it is entirely CLI and Kubernetes-native, communicating through CRDs.

Flux components:
- **source-controller** — watches Git repos, Helm repos, OCI registries
- **kustomize-controller** — applies Kustomize overlays from sources
- **helm-controller** — manages Helm releases from sources
- **notification-controller** — sends alerts, receives webhooks
- **image-reflector-controller** — scans image registries for new tags
- **image-automation-controller** — writes image tag updates back to Git

## Bootstrap — The Self-Managing Install

Flux bootstrap installs Flux into the cluster AND commits its own manifests to Git. From that point, Flux manages itself through GitOps.

```bash
# Install the Flux CLI
brew install fluxcd/tap/flux                  # macOS
curl -s https://fluxcd.io/install.sh | sudo bash  # Linux

# Pre-flight check
flux check --pre

# Bootstrap with GitHub
flux bootstrap github \
  --owner=myorg \
  --repository=gitops-repo \
  --branch=main \
  --path=clusters/production \
  --personal                     # use personal token (omit for org)

# Bootstrap with GitLab
flux bootstrap gitlab \
  --owner=mygroup \
  --repository=gitops-repo \
  --branch=main \
  --path=clusters/production \
  --token-auth                   # use GITLAB_TOKEN env var

# Bootstrap with a generic Git server
flux bootstrap git \
  --url=ssh://git@gitlab.example.com/myorg/gitops-repo \
  --branch=main \
  --path=clusters/production \
  --private-key-file=~/.ssh/id_ed25519
```

After bootstrap, your repo has:
```
gitops-repo/
└── clusters/
    └── production/
        └── flux-system/
            ├── gotk-components.yaml    ← Flux controllers
            ├── gotk-sync.yaml          ← GitRepository + Kustomization for itself
            └── kustomization.yaml
```

## Core CRDs — The Building Blocks

### GitRepository — Defines the Source

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: gitops-repo
  namespace: flux-system
spec:
  interval: 1m               # how often to check for new commits
  url: https://github.com/myorg/gitops-repo
  ref:
    branch: main             # or tag, semver, commit

  secretRef:
    name: github-credentials # Secret with username/password or SSH key

  ignore: |                  # paths to ignore
    # ignore docs and tests
    /docs/
    /tests/
    *.md

---
# Secret for private repo (HTTPS)
apiVersion: v1
kind: Secret
metadata:
  name: github-credentials
  namespace: flux-system
type: Opaque
stringData:
  username: git
  password: ghp_yourpersonalaccesstoken

---
# Secret for private repo (SSH)
apiVersion: v1
kind: Secret
metadata:
  name: github-ssh-key
  namespace: flux-system
type: Opaque
stringData:
  identity: |
    -----BEGIN OPENSSH PRIVATE KEY-----
    ...
    -----END OPENSSH PRIVATE KEY-----
  identity.pub: "ssh-ed25519 AAAA..."
  known_hosts: "github.com ssh-ed25519 AAAA..."
```

### Kustomization — Applies Manifests

The Flux `Kustomization` (not the same as Kustomize's `kustomization.yaml`) tells Flux to apply a path from a GitRepository source.

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: myapp
  namespace: flux-system
spec:
  interval: 5m               # how often to reconcile (even if no git change)
  retryInterval: 1m          # retry on failure
  timeout: 2m

  sourceRef:
    kind: GitRepository
    name: gitops-repo

  path: ./apps/myapp/overlays/production   # path inside the repo

  prune: true                # delete resources removed from Git
  force: false               # use apply (not replace)
  wait: true                 # wait for resources to be ready

  targetNamespace: production   # override namespace in all manifests

  # Pass environment-specific values as post-build substitutions
  postBuild:
    substitute:
      ENVIRONMENT: production
      REPLICA_COUNT: "5"
      IMAGE_TAG: v1.2.3
    substituteFrom:
      - kind: ConfigMap
        name: cluster-vars       # substitutions from a ConfigMap
      - kind: Secret
        name: cluster-secrets    # substitutions from a Secret (for sensitive vars)

  # Health checks — only mark ready when these pass
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: myapp
      namespace: production

  # Dependency — wait for another Kustomization first
  dependsOn:
    - name: infrastructure      # apply infrastructure before apps
```

### HelmRelease — Manages Helm Charts

```yaml
# First, define where the chart comes from
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmRepository
metadata:
  name: bitnami
  namespace: flux-system
spec:
  interval: 1h
  url: https://charts.bitnami.com/bitnami

---
# Then define the release
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: postgresql
  namespace: flux-system
spec:
  interval: 5m
  releaseName: postgresql
  targetNamespace: databases
  storageNamespace: flux-system   # where HelmRelease state is stored

  chart:
    spec:
      chart: postgresql
      version: ">=14.0.0 <15.0.0"  # semver range
      sourceRef:
        kind: HelmRepository
        name: bitnami
      interval: 1h

  values:
    auth:
      postgresPassword: "${DB_PASSWORD}"   # uses postBuild substitution
    primary:
      persistence:
        size: 50Gi

  valuesFrom:
    - kind: ConfigMap
      name: postgresql-config
      valuesKey: values.yaml       # key in the ConfigMap
    - kind: Secret
      name: postgresql-secrets
      valuesKey: secret-values.yaml

  # Upgrade strategy
  upgrade:
    remediation:
      retries: 3
      remediateLastFailure: true   # roll back on failure

  rollback:
    timeout: 5m
    cleanupOnFail: true

  # Install strategy
  install:
    remediation:
      retries: 3
    createNamespace: true

  # Test after install/upgrade
  test:
    enable: true
```

### HelmChart from Git (not Helm repo)

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: HelmChart
metadata:
  name: myapp
  namespace: flux-system
spec:
  interval: 5m
  chart: ./charts/myapp          # path inside the git repo
  sourceRef:
    kind: GitRepository
    name: gitops-repo
  version: "*"                   # always use latest from git
```

## Flux CLI Operations

```bash
# Check Flux status
flux check

# List all sources
flux get sources all

# List GitRepositories
flux get sources git

# List Kustomizations
flux get kustomizations

# List HelmReleases
flux get helmreleases -A

# Force reconcile (don't wait for interval)
flux reconcile source git gitops-repo
flux reconcile kustomization myapp
flux reconcile helmrelease postgresql

# Watch reconciliation in real time
flux reconcile kustomization myapp --watch

# Suspend / resume (pause GitOps for manual intervention)
flux suspend kustomization myapp
flux resume kustomization myapp

# Show events for a resource
flux events --for Kustomization/myapp

# Diff — what would change
flux diff kustomization myapp

# Export a resource
flux export source git gitops-repo
flux export kustomization myapp

# Get logs from controllers
flux logs --follow --level=error
flux logs --kind=HelmRelease --name=postgresql
```

## Kustomize Overlays Structure

Flux's recommended way to manage multiple environments:

```
gitops-repo/
├── apps/
│   └── myapp/
│       ├── base/
│       │   ├── kustomization.yaml
│       │   ├── deployment.yaml
│       │   ├── service.yaml
│       │   └── hpa.yaml
│       └── overlays/
│           ├── dev/
│           │   ├── kustomization.yaml   # patches for dev
│           │   └── replica-patch.yaml
│           ├── staging/
│           │   └── kustomization.yaml
│           └── production/
│               ├── kustomization.yaml
│               └── resources-patch.yaml
└── clusters/
    ├── dev/
    │   └── flux-system/
    │       └── apps.yaml     ← Kustomization pointing to apps/myapp/overlays/dev
    ├── staging/
    └── production/
```

```yaml
# apps/myapp/base/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - deployment.yaml
  - service.yaml
  - hpa.yaml

# apps/myapp/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ../../base
patches:
  - path: replica-patch.yaml
  - path: resources-patch.yaml
images:
  - name: myapp
    newTag: v1.2.3           # this gets updated by image-automation-controller
```

## Post-Build Variable Substitution

Flux can substitute variables in manifests at apply-time — useful for environment-specific values without duplicating YAML.

```yaml
# In your manifest — use ${VAR} syntax
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: ${NAMESPACE}
spec:
  replicas: ${REPLICA_COUNT}
  template:
    spec:
      containers:
        - name: myapp
          image: registry.example.com/myapp:${IMAGE_TAG}
          env:
            - name: LOG_LEVEL
              value: ${LOG_LEVEL}

---
# In your Kustomization
spec:
  postBuild:
    substitute:
      NAMESPACE: production
      REPLICA_COUNT: "5"
      IMAGE_TAG: v1.2.3
      LOG_LEVEL: info
```

## OCI Artifacts as Sources

Flux can pull manifests from OCI registries (Docker Hub, ECR, ACR, GAR):

```yaml
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: myapp-manifests
  namespace: flux-system
spec:
  interval: 5m
  url: oci://registry.example.com/myapp-manifests
  ref:
    tag: latest              # or semver, digest

  secretRef:
    name: registry-credentials

---
# Use it in a Kustomization
spec:
  sourceRef:
    kind: OCIRepository
    name: myapp-manifests
  path: ./production
```

Push manifests as OCI artifact from CI:
```bash
flux push artifact oci://registry.example.com/myapp-manifests:latest \
  --path=./k8s \
  --source=https://github.com/myorg/myapp \
  --revision=main@$(git rev-parse HEAD)
```
