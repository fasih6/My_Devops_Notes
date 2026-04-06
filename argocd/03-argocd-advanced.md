# ArgoCD Advanced

## App of Apps Pattern

The App of Apps pattern uses one "root" Application to manage all other Applications. This means the entire Application catalog is itself stored in Git and managed by ArgoCD.

```
Git repo
└── apps/
    ├── root-app.yaml          ← ArgoCD Application that watches apps/
    ├── myapp.yaml             ← Application definition for myapp
    ├── database.yaml          ← Application definition for database
    └── monitoring.yaml        ← Application definition for monitoring stack
```

```yaml
# root-app.yaml — the bootstrap application
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: root
  namespace: argocd
  finalizers:
    - resources-finalizer.argocd.argoproj.io
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/gitops-repo
    targetRevision: main
    path: apps                  # watches this directory

  destination:
    server: https://kubernetes.default.svc
    namespace: argocd           # Applications land in argocd namespace

  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

```yaml
# apps/myapp.yaml — managed by root-app
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: myapp-production
  namespace: argocd
spec:
  project: team-backend
  source:
    repoURL: https://github.com/myorg/gitops-repo
    targetRevision: main
    path: environments/production/myapp
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

## ApplicationSet — Generating Applications at Scale

ApplicationSet generates multiple Applications from a single template. Essential for managing many environments, clusters, or teams without repetition.

### List Generator

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-environments
  namespace: argocd
spec:
  generators:
    - list:
        elements:
          - env: dev
            namespace: development
            replicas: "1"
          - env: staging
            namespace: staging
            replicas: "2"
          - env: production
            namespace: production
            replicas: "5"

  template:
    metadata:
      name: "myapp-{{env}}"
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/gitops-repo
        targetRevision: main
        path: "environments/{{env}}/myapp"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{namespace}}"
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
          - CreateNamespace=true
```

### Git Directory Generator

Automatically creates an Application for every directory in a Git path:

```yaml
spec:
  generators:
    - git:
        repoURL: https://github.com/myorg/gitops-repo
        revision: main
        directories:
          - path: apps/*/overlays/production    # glob — one app per match
          - path: apps/internal/*
            exclude: true                       # but exclude these

  template:
    metadata:
      name: "{{path.basename}}"               # directory name becomes app name
    spec:
      source:
        repoURL: https://github.com/myorg/gitops-repo
        targetRevision: main
        path: "{{path}}"
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{path.basename}}"
```

### Cluster Generator — Deploy to All Clusters

```yaml
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            env: production           # only clusters labelled env=production

  template:
    metadata:
      name: "monitoring-{{name}}"    # cluster name from ArgoCD cluster secret
    spec:
      source:
        repoURL: https://github.com/myorg/gitops-repo
        targetRevision: main
        path: platform/monitoring
      destination:
        server: "{{server}}"         # cluster API URL from secret
        namespace: monitoring
```

### Matrix Generator — Combine Two Generators

```yaml
spec:
  generators:
    - matrix:
        generators:
          - clusters:
              selector:
                matchLabels:
                  env: production
          - list:
              elements:
                - app: frontend
                - app: backend
                - app: worker

  template:
    metadata:
      name: "{{app}}-{{name}}"       # e.g. frontend-prod-eu-west-1
    spec:
      source:
        path: "apps/{{app}}/overlays/production"
      destination:
        server: "{{server}}"
        namespace: "{{app}}"
```

### SCM Provider Generator (GitHub/GitLab)

```yaml
spec:
  generators:
    - scmProvider:
        github:
          organization: myorg
          tokenRef:
            secretName: github-token
            key: token
        filters:
          - repositoryMatch: "^service-"    # only repos starting with service-
          - branchMatch: "^main$"

  template:
    metadata:
      name: "{{repository}}"
    spec:
      source:
        repoURL: "{{url}}"
        targetRevision: "{{branch}}"
        path: k8s/overlays/production
      destination:
        server: https://kubernetes.default.svc
        namespace: "{{repository}}"
```

## Resource Hooks

Hooks run at specific points in the sync lifecycle — useful for pre-sync migrations, post-sync tests, or cleanup.

```yaml
# Pre-sync hook — run DB migration before applying new Deployment
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  annotations:
    argocd.argoproj.io/hook: PreSync
    argocd.argoproj.io/hook-delete-policy: BeforeHookCreation  # clean up old job first
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: migration
          image: myapp:{{.Values.image.tag}}
          command: ["python", "manage.py", "migrate"]
          env:
            - name: DATABASE_URL
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: url

---
# Post-sync hook — run smoke tests after deployment
apiVersion: batch/v1
kind: Job
metadata:
  name: smoke-test
  annotations:
    argocd.argoproj.io/hook: PostSync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: test
          image: curlimages/curl:latest
          command:
            - sh
            - -c
            - |
              curl -sf https://myapp.example.com/health || exit 1
              echo "Health check passed"
```

Hook types:
- `PreSync` — before sync begins
- `Sync` — during sync (runs alongside resources)
- `PostSync` — after all resources are healthy
- `SyncFail` — if sync fails (for cleanup/alerts)
- `Skip` — skip this resource during sync

Hook delete policies:
- `HookSucceeded` — delete after success
- `HookFailed` — delete after failure
- `BeforeHookCreation` — delete before recreating (always fresh)

## Notifications

ArgoCD Notifications sends alerts when apps change state.

```yaml
# Install
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/notifications_catalog/install.yaml

# argocd-notifications-cm
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  # Templates
  template.app-sync-succeeded: |
    message: |
      Application {{.app.metadata.name}} sync succeeded.
      Revision: {{.app.status.sync.revision}}

  template.app-sync-failed: |
    message: |
      Application {{.app.metadata.name}} sync FAILED.
      Error: {{.app.status.operationState.message}}

  # Triggers — when to send
  trigger.on-sync-succeeded: |
    - description: Notify when app syncs successfully
      send: [app-sync-succeeded]
      when: app.status.operationState.phase in ['Succeeded']

  trigger.on-sync-failed: |
    - description: Notify when sync fails
      send: [app-sync-failed]
      when: app.status.operationState.phase in ['Error', 'Failed']

  # Services — where to send
  service.slack: |
    token: $slack-token
    username: ArgoCD
    icon: ":argo:"

---
# argocd-notifications-secret
apiVersion: v1
kind: Secret
metadata:
  name: argocd-notifications-secret
  namespace: argocd
stringData:
  slack-token: xoxb-your-slack-token
```

```yaml
# Subscribe an Application to notifications
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: deployments
    notifications.argoproj.io/subscribe.on-sync-failed.slack: alerts
```

## Progressive Delivery with Argo Rollouts

ArgoCD integrates with Argo Rollouts for canary and blue-green deployments.

```yaml
# Install Argo Rollouts
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f \
  https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml

# Rollout — canary deployment
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: myapp
spec:
  replicas: 10
  selector:
    matchLabels:
      app: myapp
  template:
    metadata:
      labels:
        app: myapp
    spec:
      containers:
        - name: myapp
          image: myapp:v2.0.0

  strategy:
    canary:
      steps:
        - setWeight: 10          # send 10% traffic to new version
        - pause: {duration: 5m} # wait 5 minutes
        - setWeight: 30
        - pause: {duration: 10m}
        - analysis:              # run automated analysis
            templates:
              - templateName: success-rate
        - setWeight: 100         # full rollout

      canaryService: myapp-canary
      stableService: myapp-stable

      trafficRouting:
        nginx:
          stableIngress: myapp-ingress

---
# AnalysisTemplate — automated rollout quality gate
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  metrics:
    - name: success-rate
      interval: 1m
      successCondition: result[0] >= 0.95   # 95% success rate required
      failureLimit: 3
      provider:
        prometheus:
          address: http://prometheus.monitoring.svc:9090
          query: |
            sum(rate(http_requests_total{status=~"2.*",deployment="myapp-canary"}[5m]))
            /
            sum(rate(http_requests_total{deployment="myapp-canary"}[5m]))
```

## ArgoCD Image Updater

Automatically updates image tags in Git when a new image is pushed to a registry.

```bash
# Install
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

```yaml
# Annotate your Application
metadata:
  annotations:
    # Watch this image
    argocd-image-updater.argoproj.io/image-list: myapp=registry.example.com/myapp

    # Update strategy
    argocd-image-updater.argoproj.io/myapp.update-strategy: semver  # latest semver tag
    # or: latest, name, digest

    # Only consider tags matching this pattern
    argocd-image-updater.argoproj.io/myapp.allow-tags: regexp:^v[0-9]+\.[0-9]+\.[0-9]+$

    # Write back to Git (not just cluster) — GitOps!
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/write-back-target: kustomization
    argocd-image-updater.argoproj.io/git-branch: main
```
