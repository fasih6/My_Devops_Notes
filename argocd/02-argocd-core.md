# ArgoCD Core

## What ArgoCD Is

ArgoCD is a declarative, GitOps continuous delivery tool for Kubernetes. It runs as a set of controllers inside your cluster, watches Git repositories, and automatically applies changes when the desired state drifts from the actual state.

```
Git repo (desired state)
        ↓  ArgoCD watches this
ArgoCD controller
        ↓  reconciles
Kubernetes cluster (actual state)
```

## Installation

```bash
# Install ArgoCD
kubectl create namespace argocd
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=argocd-server \
  -n argocd --timeout=120s

# Install ArgoCD CLI
brew install argocd                          # macOS
curl -sSL -o argocd https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64
chmod +x argocd && mv argocd /usr/local/bin/

# Get initial admin password
argocd admin initial-password -n argocd

# Port-forward to access UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Login
argocd login localhost:8080 \
  --username admin \
  --password <password> \
  --insecure

# Change password immediately
argocd account update-password
```

### Production Installation with Helm

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --version 6.7.0 \
  --values argocd-values.yaml
```

```yaml
# argocd-values.yaml — production config
global:
  domain: argocd.example.com

configs:
  params:
    server.insecure: false          # always TLS in prod

  cm:
    # Git repos that need credentials
    repositories: |
      - url: https://github.com/myorg/gitops-repo
        passwordSecret:
          name: github-credentials
          key: password
        usernameSecret:
          name: github-credentials
          key: username

    # Resource customisations (e.g. ignore diff on certain fields)
    resource.customizations: |
      apps/Deployment:
        ignoreDifferences: |
          jsonPointers:
          - /spec/replicas

  rbac:
    policy.default: role:readonly   # least privilege default

server:
  ingress:
    enabled: true
    ingressClassName: nginx
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    tls: true

redis-ha:
  enabled: true                     # HA Redis for production

controller:
  replicas: 1

repoServer:
  replicas: 2                       # scale repo server for many apps

applicationSet:
  replicas: 2
```

## The Application CRD

An `Application` is the core ArgoCD object. It tells ArgoCD: "watch this Git path, and apply it to this cluster/namespace."

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp
  namespace: argocd          # always in argocd namespace
  finalizers:
    - resources-finalizer.argocd.argoproj.io   # cascade delete
spec:
  project: default           # ArgoCD project (for RBAC)

  source:
    repoURL: https://github.com/myorg/gitops-repo
    targetRevision: main     # branch, tag, or commit SHA
    path: apps/myapp/overlays/production   # path inside repo

  destination:
    server: https://kubernetes.default.svc  # in-cluster
    namespace: production

  syncPolicy:
    automated:
      prune: true            # delete resources removed from Git
      selfHeal: true         # revert manual kubectl edits
      allowEmpty: false      # never sync to empty state

    syncOptions:
      - CreateNamespace=true         # auto-create ns if missing
      - PrunePropagationPolicy=foreground
      - ApplyOutOfSyncOnly=true      # only apply changed resources

    retry:
      limit: 5
      backoff:
        duration: 5s
        factor: 2
        maxDuration: 3m
```

### Helm Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-helm
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://charts.example.com
    chart: myapp
    targetRevision: 1.2.3         # chart version

    helm:
      releaseName: myapp
      valueFiles:
        - values-production.yaml  # relative to repo root
      values: |
        replicaCount: 3
        image:
          tag: v2.1.0
      parameters:
        - name: image.tag
          value: v2.1.0

  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

### Multi-source Application (ArgoCD 2.6+)

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-multisource
  namespace: argocd
spec:
  sources:
    - repoURL: https://charts.example.com
      chart: myapp
      targetRevision: 1.2.3
      helm:
        valueFiles:
          - $values/environments/production/values.yaml   # $values refs second source

    - repoURL: https://github.com/myorg/gitops-repo       # values repo
      targetRevision: main
      ref: values                                         # reference name used above

  destination:
    server: https://kubernetes.default.svc
    namespace: production
```

## Sync Policies and Strategies

```yaml
syncPolicy:
  automated:
    prune: true       # IMPORTANT: without this, deleted resources stay
    selfHeal: true    # revert manual changes in cluster
  
  syncOptions:
    - Validate=false               # skip kubectl validation (for CRDs)
    - CreateNamespace=true
    - PrunePropagationPolicy=foreground   # wait for deletion
    - Replace=true                 # use kubectl replace instead of apply (for large resources)
    - ServerSideApply=true         # use server-side apply (handles conflicts better)
    - ApplyOutOfSyncOnly=true      # only touch resources that are out of sync
```

### Sync Waves — Ordering Resources

```yaml
# Apply CRDs before Deployments, Deployments before Jobs
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  annotations:
    argocd.argoproj.io/sync-wave: "2"   # higher = later
---
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  annotations:
    argocd.argoproj.io/sync-wave: "1"   # runs before deployment
---
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: mycrds.example.com
  annotations:
    argocd.argoproj.io/sync-wave: "-1"  # negative = very first
```

## ArgoCD Projects

Projects provide RBAC and restrict what Applications can do.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-backend
  namespace: argocd
spec:
  description: Backend team applications

  # Which repos this project's apps can use
  sourceRepos:
    - https://github.com/myorg/gitops-repo
    - https://charts.example.com

  # Which clusters and namespaces apps can deploy to
  destinations:
    - server: https://kubernetes.default.svc
      namespace: production
    - server: https://kubernetes.default.svc
      namespace: staging

  # Which resource kinds can be created
  clusterResourceWhitelist:
    - group: ''
      kind: Namespace
  namespaceResourceWhitelist:
    - group: apps
      kind: Deployment
    - group: ''
      kind: Service

  # RBAC for this project
  roles:
    - name: developer
      description: Can sync but not delete
      policies:
        - p, proj:team-backend:developer, applications, get, team-backend/*, allow
        - p, proj:team-backend:developer, applications, sync, team-backend/*, allow
      groups:
        - backend-team          # SSO group

    - name: operator
      policies:
        - p, proj:team-backend:operator, applications, *, team-backend/*, allow
      groups:
        - platform-team
```

## ArgoCD RBAC

```yaml
# argocd-rbac-cm ConfigMap
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-rbac-cm
  namespace: argocd
data:
  policy.default: role:readonly     # everyone gets read-only
  policy.csv: |
    # Platform team gets admin
    g, platform-team, role:admin

    # Backend team can sync their project
    p, role:backend-dev, applications, sync, team-backend/*, allow
    p, role:backend-dev, applications, get, team-backend/*, allow
    g, backend-team, role:backend-dev
```

## CLI Operations

```bash
# List all applications
argocd app list

# Get app details
argocd app get myapp

# Manual sync (when auto-sync is off)
argocd app sync myapp

# Sync specific resources only
argocd app sync myapp --resource apps:Deployment:myapp

# Sync with dry run
argocd app sync myapp --dry-run

# Rollback to previous revision
argocd app rollback myapp 3    # revision number

# Diff — what would change on next sync
argocd app diff myapp

# Hard refresh — bypass cache, re-fetch from git
argocd app get myapp --hard-refresh

# Set image (triggers git-write-back if using image updater)
argocd app set myapp --helm-set image.tag=v1.2.3

# Delete app (with cascade — deletes K8s resources too)
argocd app delete myapp --cascade

# Watch sync in real time
argocd app wait myapp --sync

# List repos
argocd repo list

# Add a private repo
argocd repo add https://github.com/myorg/private-repo \
  --username git \
  --password ghp_xxxx

# Add SSH repo
argocd repo add git@github.com:myorg/gitops.git \
  --ssh-private-key-path ~/.ssh/id_ed25519
```

## Ignore Differences

Sometimes you want ArgoCD to ignore certain fields that change outside Git (e.g. HPA-managed replica counts):

```yaml
# In Application spec
spec:
  ignoreDifferences:
    - group: apps
      kind: Deployment
      jsonPointers:
        - /spec/replicas             # HPA manages this
    - group: ""
      kind: Secret
      jsonPointers:
        - /data                      # don't diff secret data
    - group: admissionregistration.k8s.io
      kind: MutatingWebhookConfiguration
      jqPathExpressions:
        - .webhooks[]?.clientConfig.caBundle  # injected by cert-manager
```

## Health Checks

ArgoCD has built-in health checks for standard resources. Custom resources need custom checks:

```yaml
# argocd-cm ConfigMap — custom health check
data:
  resource.customizations.health.argoproj.io_Rollout: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.phase == "Degraded" then
        hs.status = "Degraded"
        hs.message = obj.status.message
      elseif obj.status.phase == "Paused" then
        hs.status = "Suspended"
        hs.message = "Rollout is paused"
      elseif obj.status.phase == "Healthy" then
        hs.status = "Healthy"
      else
        hs.status = "Progressing"
      end
    end
    return hs
```

## SSO Integration

```yaml
# argocd-cm — Dex connector for GitHub SSO
data:
  dex.config: |
    connectors:
    - type: github
      id: github
      name: GitHub
      config:
        clientID: $dex.github.clientID
        clientSecret: $dex.github.clientSecret
        redirectURI: https://argocd.example.com/api/dex/callback
        orgs:
        - name: myorg
          teams:
          - platform-team
          - backend-team
```
