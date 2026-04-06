# ArgoCD Interview Q&A — All Levels

> **Coverage**: Beginner → Intermediate → Advanced → Exam/Scenario Style  
> **Format**: Mix of concise answers, bullet points, tables, and code snippets  
> **Total**: 120+ questions across 10 topic sections  
> **Relevance**: DevOps roles, GitOps engineer positions, CKA/CKAD adjacent tooling

---

## Table of Contents

1. [GitOps & ArgoCD Fundamentals](#1-gitops--argocd-fundamentals)
2. [ArgoCD Architecture & Components](#2-argocd-architecture--components)
3. [Applications & AppProjects](#3-applications--appprojects)
4. [Sync Policies & Strategies](#4-sync-policies--strategies)
5. [Helm, Kustomize & Config Management](#5-helm-kustomize--config-management)
6. [RBAC, SSO & Security](#6-rbac-sso--security)
7. [Multi-Cluster & Advanced Deployments](#7-multi-cluster--advanced-deployments)
8. [Notifications, Webhooks & Integrations](#8-notifications-webhooks--integrations)
9. [Troubleshooting & Operations](#9-troubleshooting--operations)
10. [Scenario-Based & Real-World Questions](#10-scenario-based--real-world-questions)

---

## 1. GitOps & ArgoCD Fundamentals

---

**Q1. What is GitOps?**

GitOps is an operational model where **Git is the single source of truth** for both application code and infrastructure configuration. Key principles:

| Principle | Description |
|---|---|
| **Declarative** | System state described in declarative config files |
| **Versioned** | All changes tracked in Git (audit trail, rollback) |
| **Automatic** | Approved changes applied automatically to the system |
| **Self-healing** | System continuously reconciles toward Git-defined state |

---

**Q2. What is ArgoCD?**

ArgoCD is a **declarative, GitOps-based continuous delivery tool** for Kubernetes. It:
- Watches Git repositories for changes
- Compares live cluster state against Git-defined desired state
- Automatically (or manually) syncs the cluster to match Git
- Provides a UI, CLI, and API for managing deployments

It is a CNCF graduated project and one of the most widely adopted GitOps tools.

---

**Q3. What problem does ArgoCD solve?**

Traditional CD tools (Jenkins, GitLab CI) push changes to a cluster imperatively — running `kubectl apply` in a pipeline. Problems:
- No visibility into what's actually running vs. what was deployed
- Drift goes undetected (someone runs `kubectl edit` directly)
- No automatic reconciliation
- Poor audit trail for cluster state

ArgoCD solves this by continuously **pulling and reconciling** state from Git.

---

**Q4. What is the difference between push-based and pull-based CD?**

| Feature | Push-based (Jenkins/GitLab CI) | Pull-based (ArgoCD/Flux) |
|---|---|---|
| Direction | CI pipeline pushes to cluster | Agent in cluster pulls from Git |
| Cluster credentials | Stored in CI system (risk) | Stays inside cluster |
| Drift detection | None | Continuous |
| Reconciliation | Manual re-run | Automatic |
| Security | CI has cluster access | Cluster has Git access only |
| Examples | Jenkins, GitLab CI, GitHub Actions | ArgoCD, Flux |

---

**Q5. What are the four core GitOps principles (OpenGitOps)?**

1. **Declarative** — desired state expressed declaratively
2. **Versioned and immutable** — state stored in Git with full history
3. **Pulled automatically** — software agents pull desired state from Git
4. **Continuously reconciled** — agents detect and correct drift automatically

---

**Q6. What is the difference between ArgoCD and Flux?**

| Feature | ArgoCD | Flux |
|---|---|---|
| UI | Rich built-in web UI | No built-in UI (Weave GitOps optional) |
| Architecture | Centralized server + agents | Distributed controllers |
| App definition | `Application` CRD | `Kustomization` / `HelmRelease` CRDs |
| Multi-tenancy | Via `AppProject` | Via namespace isolation |
| SSO | Built-in (Dex) | External |
| Popularity | Higher (more enterprise adoption) | Preferred in CNCF-native setups |
| Learning curve | Gentler (UI helps) | More CLI/YAML-driven |

---

**Q7. What is configuration drift and how does ArgoCD handle it?**

**Configuration drift** occurs when the live cluster state diverges from the declared desired state — e.g., someone runs `kubectl edit deployment` directly.

ArgoCD detects drift by:
1. Continuously comparing live cluster state vs. Git-defined state
2. Marking the Application as `OutOfSync` when drift is detected
3. Optionally **auto-syncing** to restore the desired state
4. Showing the diff in the UI

---

**Q8. What are the two main GitOps tools used with Kubernetes?**

- **ArgoCD** — application-centric, great UI, AppProject multi-tenancy
- **Flux** — infrastructure-centric, native Kubernetes controller model

Both are CNCF graduated projects. Many teams use both together (ArgoCD for apps, Flux for cluster infrastructure).

---

**Q9. What is the ArgoCD Application CRD?**

The `Application` is ArgoCD's core CRD. It defines:
- **Source**: Which Git repo, path, and revision to watch
- **Destination**: Which cluster and namespace to deploy to
- **Sync policy**: Manual or automatic sync behavior

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/my-app.git
    targetRevision: HEAD
    path: k8s/overlays/production
  destination:
    server: https://kubernetes.default.svc
    namespace: production
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
```

---

**Q10. What is the App of Apps pattern?**

The **App of Apps** pattern is a way to manage multiple ArgoCD Applications declaratively using ArgoCD itself:

- One "root" ArgoCD Application points to a Git directory
- That directory contains YAML manifests for multiple other `Application` objects
- ArgoCD creates and manages all child Applications automatically

```
root-app (ArgoCD Application)
    └── git/apps/
        ├── frontend-app.yaml    (Application)
        ├── backend-app.yaml     (Application)
        └── database-app.yaml   (Application)
```

This is the GitOps-native way to bootstrap an entire platform.

---

## 2. ArgoCD Architecture & Components

---

**Q11. What are the main components of ArgoCD?**

| Component | Role |
|---|---|
| **API Server** | gRPC/REST API; serves UI, CLI, and webhook events |
| **Repository Server** | Clones Git repos; generates manifests (Helm, Kustomize, plain YAML) |
| **Application Controller** | Watches Applications; compares live vs desired state; triggers sync |
| **Dex** | Built-in OIDC identity provider for SSO (optional) |
| **Redis** | Caches repo and application state |
| **ArgoCD UI** | Web interface for visualizing and managing applications |

---

**Q12. What does the ArgoCD Application Controller do?**

The Application Controller is the heart of ArgoCD. It:
- Watches Kubernetes resources and Git state continuously
- Computes the diff between live state and desired state
- Triggers sync operations when `automated` sync is enabled
- Updates Application status (`Synced`, `OutOfSync`, `Healthy`, `Degraded`)
- Runs as a `StatefulSet` (for leader election in HA mode)

---

**Q13. What does the Repository Server do?**

The Repository Server is responsible for:
- Cloning and caching Git repositories
- Generating Kubernetes manifests from source (plain YAML, Helm charts, Kustomize overlays, Jsonnet)
- Responding to manifest generation requests from the Application Controller
- It runs as a **stateless Deployment** — multiple replicas can run for HA

---

**Q14. How is ArgoCD installed?**

```bash
# Method 1: Plain manifests
kubectl create namespace argocd
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Method 2: Helm chart
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace

# Access the UI
kubectl port-forward svc/argocd-server -n argocd 8080:443

# Get initial admin password
kubectl get secret argocd-initial-admin-secret -n argocd \
  -o jsonpath='{.data.password}' | base64 -d
```

---

**Q15. How does ArgoCD store its state?**

ArgoCD stores all its state (Applications, AppProjects, repository credentials, cluster credentials) as **Kubernetes Custom Resources and Secrets** in the `argocd` namespace — not in an external database. This makes it portable and easy to back up via standard Kubernetes tools (Velero).

---

**Q16. What is the ArgoCD CLI (`argocd`) and common commands?**

```bash
# Login
argocd login argocd.example.com --username admin

# List applications
argocd app list

# Get app details
argocd app get my-app

# Sync an application
argocd app sync my-app

# Check sync status
argocd app wait my-app --health

# Rollback to previous version
argocd app rollback my-app

# Add a Git repository
argocd repo add https://github.com/myorg/repo.git \
  --username myuser --password mytoken

# Add a cluster
argocd cluster add <context-name>

# List clusters
argocd cluster list
```

---

**Q17. What is the difference between ArgoCD server and argocd-server service?**

- **ArgoCD server** is the API server Pod (Deployment)
- **argocd-server Service** exposes it — by default as `ClusterIP`; change to `LoadBalancer` or use `Ingress` for external access

```bash
# Expose via LoadBalancer
kubectl patch svc argocd-server -n argocd \
  -p '{"spec": {"type": "LoadBalancer"}}'

# Or via port-forward for local access
kubectl port-forward svc/argocd-server -n argocd 8080:443
```

---

**Q18. What is Redis used for in ArgoCD?**

Redis acts as a **cache layer** for ArgoCD:
- Caches generated manifests from the Repository Server
- Caches application state computed by the Application Controller
- Reduces load on the API server and Git repositories
- If Redis is unavailable, ArgoCD continues to function but with degraded performance

---

**Q19. How does ArgoCD authenticate to Git repositories?**

ArgoCD supports multiple authentication methods for Git:

| Method | Use case |
|---|---|
| HTTPS with username/password or token | GitHub, GitLab, Bitbucket |
| SSH private key | Any Git server |
| GitHub App | GitHub (preferred for orgs) |
| TLS client certificates | Enterprise Git servers |

```bash
# Add HTTPS repo
argocd repo add https://github.com/myorg/repo.git \
  --username myuser \
  --password ghp_mytoken

# Add SSH repo
argocd repo add git@github.com:myorg/repo.git \
  --ssh-private-key-path ~/.ssh/id_rsa
```

---

**Q20. What is the `argocd-cm` ConfigMap and what does it configure?**

`argocd-cm` is the main ArgoCD configuration ConfigMap in the `argocd` namespace. It configures:
- OIDC / SSO provider settings
- Custom health check scripts
- Custom resource actions
- Resource exclusions
- Helm value file overrides
- RBAC policy

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-cm
  namespace: argocd
data:
  url: https://argocd.example.com
  oidc.config: |
    name: Okta
    issuer: https://dev-xxx.okta.com
    clientID: myClientId
    clientSecret: $oidc.okta.clientSecret
  resource.exclusions: |
    - apiGroups: ["cilium.io"]
      kinds: ["*"]
      clusters: ["*"]
```

---

## 3. Applications & AppProjects

---

**Q21. What is an ArgoCD Application?**

An ArgoCD Application is a CRD that represents a deployed instance of an application. It links:
- A **source** (Git repo + path + revision)
- A **destination** (cluster + namespace)
- A **sync policy** (manual or automatic)

Each Application has a **sync status** (Synced/OutOfSync) and a **health status** (Healthy/Degraded/Progressing/Missing/Unknown).

---

**Q22. What are the Application health statuses?**

| Status | Meaning |
|---|---|
| `Healthy` | All resources are healthy |
| `Progressing` | Resources are being updated (rollout in progress) |
| `Degraded` | One or more resources have failed |
| `Missing` | Resource doesn't exist in the cluster yet |
| `Suspended` | Resource is intentionally paused (e.g., suspended CronJob) |
| `Unknown` | Health status cannot be determined |

---

**Q23. What are the Application sync statuses?**

| Status | Meaning |
|---|---|
| `Synced` | Live state matches desired Git state |
| `OutOfSync` | Live state differs from Git state |
| `Unknown` | Could not determine sync status |

---

**Q24. What is an AppProject?**

An `AppProject` is an ArgoCD CRD that provides **multi-tenancy and access control** for Applications. It defines:
- Which Git repositories are allowed as sources
- Which clusters and namespaces are allowed as destinations
- Which Kubernetes resources are allowed or denied
- RBAC roles within the project

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: team-frontend
  namespace: argocd
spec:
  description: "Frontend team project"
  sourceRepos:
  - https://github.com/myorg/frontend.git
  destinations:
  - namespace: frontend-*
    server: https://kubernetes.default.svc
  clusterResourceWhitelist:
  - group: ""
    kind: Namespace
  namespaceResourceBlacklist:
  - group: ""
    kind: ResourceQuota
  roles:
  - name: developer
    description: "Frontend developers"
    policies:
    - p, proj:team-frontend:developer, applications, get, team-frontend/*, allow
    - p, proj:team-frontend:developer, applications, sync, team-frontend/*, allow
    groups:
    - frontend-devs
```

---

**Q25. What is the `default` AppProject?**

Every ArgoCD installation has a built-in `default` AppProject that:
- Allows any source repository
- Allows any destination cluster and namespace
- Has no resource restrictions

Applications not assigned to a specific project use `default`. In production, create specific projects with restrictions.

---

**Q26. How do you create an Application using the CLI?**

```bash
argocd app create my-app \
  --repo https://github.com/myorg/my-app.git \
  --path k8s/overlays/prod \
  --dest-server https://kubernetes.default.svc \
  --dest-namespace production \
  --project default \
  --sync-policy automated \
  --auto-prune \
  --self-heal \
  --revision HEAD
```

---

**Q27. What is the ApplicationSet CRD?**

An `ApplicationSet` is a CRD that **automatically generates multiple ArgoCD Applications** based on a template and a generator. Used for:
- Deploying the same app to multiple clusters
- Deploying multiple apps from a monorepo
- Creating apps per Git branch or PR

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: cluster-apps
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - cluster: staging
        url: https://staging-cluster.example.com
      - cluster: production
        url: https://prod-cluster.example.com
  template:
    metadata:
      name: '{{cluster}}-my-app'
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/my-app.git
        targetRevision: HEAD
        path: 'k8s/{{cluster}}'
      destination:
        server: '{{url}}'
        namespace: my-app
```

---

**Q28. What are ApplicationSet generators?**

Generators define how Applications are created:

| Generator | Description |
|---|---|
| `List` | Fixed list of key-value pairs |
| `Cluster` | One Application per registered cluster |
| `Git` | One Application per directory or file in a Git repo |
| `Matrix` | Combines two generators (e.g., cluster × environment) |
| `Merge` | Merges values from multiple generators |
| `SCMProvider` | One Application per repo in a GitHub/GitLab org |
| `PullRequest` | One Application per open PR |
| `ClusterDecisionResource` | Uses a custom CRD to determine target clusters |

---

**Q29. What is the difference between an Application and an ApplicationSet?**

| Application | ApplicationSet |
|---|---|
| Manually defined for one app/cluster | Auto-generates multiple Applications |
| One source → one destination | One template → many destinations |
| Good for individual apps | Good for fleet management |
| Simpler | More powerful and scalable |

---

**Q30. How do you sync an application and wait for it to be healthy?**

```bash
# Sync and wait
argocd app sync my-app --timeout 120

# Wait for healthy state
argocd app wait my-app --health --timeout 120

# Sync with specific revision
argocd app sync my-app --revision v1.2.3

# Force sync (ignore cache)
argocd app sync my-app --force

# Sync only specific resources
argocd app sync my-app --resource apps:Deployment:my-deployment
```

---

## 4. Sync Policies & Strategies

---

**Q31. What is the difference between manual and automated sync?**

| Manual Sync | Automated Sync |
|---|---|
| Requires human to trigger sync (UI, CLI, API) | ArgoCD auto-syncs when Git changes detected |
| Default behavior | Enabled via `syncPolicy.automated` |
| More control | Faster delivery |
| Safer for production (with approval gates) | Best for dev/staging environments |

---

**Q32. What are `prune` and `selfHeal` in automated sync?**

```yaml
syncPolicy:
  automated:
    prune: true      # Delete resources removed from Git
    selfHeal: true   # Re-sync if live state drifts from Git
```

- **`prune: true`**: If a resource is removed from Git, ArgoCD deletes it from the cluster
- **`selfHeal: true`**: If someone manually changes a resource in the cluster, ArgoCD reverts it to match Git

> Without `prune`, removed resources become "orphaned" in the cluster.  
> Without `selfHeal`, manual cluster changes are not reverted.

---

**Q33. What sync options are available?**

```yaml
syncPolicy:
  syncOptions:
  - CreateNamespace=true          # Auto-create destination namespace
  - PrunePropagationPolicy=foreground  # Wait for dependents before deleting
  - PruneLast=true                # Prune after all other resources sync
  - ApplyOutOfSyncOnly=true       # Only sync resources that are OutOfSync
  - ServerSideApply=true          # Use server-side apply (SSA)
  - Validate=false                # Skip kubectl validation
  - RespectIgnoreDifferences=true # Apply ignoreDifferences during sync
```

---

**Q34. What is `ignoreDifferences` and when do you use it?**

`ignoreDifferences` tells ArgoCD to ignore certain fields when computing sync status — useful for fields mutated by controllers after deployment:

```yaml
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas              # Ignore replica count (managed by HPA)
  - group: ""
    kind: ConfigMap
    name: my-config
    jsonPointers:
    - /data/last-updated          # Ignore auto-updated field
  - group: admissionregistration.k8s.io
    kind: MutatingWebhookConfiguration
    jqPathExpressions:
    - .webhooks[].clientConfig.caBundle  # Injected by cert-manager
```

---

**Q35. What are sync waves and sync phases?**

ArgoCD uses **sync waves** to control the order in which resources are applied during a sync:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"   # Applied first (lower = earlier)
```

Resources with the same wave are applied together. Waves proceed in ascending order: -5, -1, 0, 1, 2, 5...

**Sync phases:**
1. `PreSync` — hooks run before sync
2. `Sync` — main resources applied (ordered by wave)
3. `PostSync` — hooks run after sync
4. `SyncFail` — hooks run only if sync fails

---

**Q36. What are sync hooks?**

Sync hooks are Kubernetes resources (Jobs, Pods) annotated to run at specific points in the sync lifecycle:

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
  annotations:
    argocd.argoproj.io/hook: PreSync          # Run before sync
    argocd.argoproj.io/hook-delete-policy: HookSucceeded  # Delete after success
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: migrate
        image: my-app:latest
        command: ["python", "manage.py", "migrate"]
```

Hook delete policies:
- `HookSucceeded` — delete after successful completion
- `HookFailed` — delete after failure
- `BeforeHookCreation` — delete before creating the hook again (default)

---

**Q37. What is a sync window?**

Sync windows allow you to **restrict when automated syncs occur** — useful for preventing deployments during peak hours or maintenance windows:

```yaml
# In AppProject
spec:
  syncWindows:
  - kind: allow
    schedule: "0 9 * * 1-5"     # Allow sync Mon-Fri 9 AM
    duration: 8h
    applications: ["*"]
  - kind: deny
    schedule: "0 0 * * 6-7"     # Deny sync on weekends
    duration: 48h
    manualSync: true             # Also block manual syncs
```

---

**Q38. What is the retry policy in ArgoCD?**

ArgoCD can automatically retry failed syncs:

```yaml
syncPolicy:
  retry:
    limit: 5                    # Max retries
    backoff:
      duration: 5s              # Initial backoff
      factor: 2                 # Exponential multiplier
      maxDuration: 3m           # Maximum backoff duration
```

Useful for syncs that fail due to transient issues (network, webhook timeouts).

---

**Q39. How does ArgoCD detect that an Application is out of sync?**

ArgoCD computes the diff between:
1. **Desired state**: Manifests generated from Git (via Helm, Kustomize, etc.)
2. **Live state**: Resources fetched from the Kubernetes API

Differences in any tracked field mark the Application as `OutOfSync`. ArgoCD uses a **3-way diff** similar to `kubectl apply` — it considers the last-applied state to avoid false positives from controller-managed fields.

---

**Q40. What is `targetRevision` in an Application?**

`targetRevision` specifies which Git revision to track:

| Value | Meaning |
|---|---|
| `HEAD` | Latest commit on default branch |
| `main` | Tip of the `main` branch |
| `v1.2.3` | Specific Git tag |
| `abc1234` | Specific commit SHA |
| A branch name | Tip of that branch |

```yaml
source:
  targetRevision: HEAD          # Always track latest
  targetRevision: release-1.5   # Track a release branch
  targetRevision: v2.0.0        # Pin to a tag
```

---

## 5. Helm, Kustomize & Config Management

---

**Q41. How does ArgoCD support Helm charts?**

ArgoCD natively supports Helm as a source type. It renders Helm charts into manifests at sync time:

```yaml
source:
  repoURL: https://charts.bitnami.com/bitnami
  chart: nginx
  targetRevision: 15.0.0
  helm:
    releaseName: my-nginx
    values: |
      replicaCount: 3
      service:
        type: ClusterIP
    valueFiles:
    - values-production.yaml
    parameters:
    - name: image.tag
      value: "1.25"
```

---

**Q42. What is the difference between ArgoCD managing Helm vs. using `helm install`?**

| `helm install` | ArgoCD with Helm |
|---|---|
| Helm manages release state in Secrets | ArgoCD manages state; Helm used for rendering only |
| `helm list` shows releases | ArgoCD UI shows applications |
| Rollback via `helm rollback` | Rollback via ArgoCD (points to previous Git commit) |
| No drift detection | Drift detection built-in |
| Push-based | Pull-based GitOps |

> ArgoCD uses Helm as a **template engine only** — it does not use Helm's release management.

---

**Q43. How does ArgoCD support Kustomize?**

ArgoCD detects a `kustomization.yaml` file and runs `kustomize build` automatically:

```yaml
source:
  repoURL: https://github.com/myorg/my-app.git
  path: k8s/overlays/production
  kustomize:
    images:
    - name: myapp
      newTag: v1.2.3             # Override image tag at sync time
    commonLabels:
      env: production
    namePrefix: prod-
```

---

**Q44. What is the typical GitOps repo structure with Kustomize?**

```
my-app/
├── base/
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   └── service.yaml
└── overlays/
    ├── dev/
    │   ├── kustomization.yaml   # Patches for dev
    │   └── replica-patch.yaml
    ├── staging/
    │   └── kustomization.yaml
    └── production/
        ├── kustomization.yaml   # Patches for prod
        └── resource-limits.yaml
```

ArgoCD Application points to `overlays/production`.

---

**Q45. How do you use multiple value files in ArgoCD with Helm?**

```yaml
source:
  helm:
    valueFiles:
    - values.yaml              # Base values (in repo)
    - values-production.yaml   # Environment-specific overrides
    - $values/secrets.yaml     # From a separate repo (using multiple sources)
```

With **multiple sources** (ArgoCD 2.6+):

```yaml
sources:
- repoURL: https://github.com/myorg/my-app.git
  targetRevision: HEAD
  ref: values                  # Reference alias for second source
- repoURL: https://charts.bitnami.com/bitnami
  chart: nginx
  targetRevision: 15.0.0
  helm:
    valueFiles:
    - $values/environments/prod/values.yaml
```

---

**Q46. What other config management tools does ArgoCD support?**

| Tool | Detection |
|---|---|
| **Helm** | `Chart.yaml` present in path |
| **Kustomize** | `kustomization.yaml` present |
| **Jsonnet** | `.jsonnet` files present |
| **Plain directory** | Any directory with YAML/JSON manifests |
| **Custom plugins (CMP)** | Via Config Management Plugin sidecar |

---

**Q47. What is a Config Management Plugin (CMP) in ArgoCD?**

A CMP allows ArgoCD to use **custom tools** for manifest generation — anything not natively supported (Cue, Dhall, Terraform, custom scripts):

```yaml
# Plugin definition in argocd-cm
data:
  configManagementPlugins: |
    - name: my-plugin
      generate:
        command: ["sh", "-c"]
        args: ["my-tool generate --env $ARGOCD_ENV_ENV"]
```

Modern CMPs run as **sidecar containers** in the repo-server Pod.

---

**Q48. How do you override Helm values in ArgoCD without modifying the chart?**

```yaml
source:
  helm:
    # Method 1: Inline values
    values: |
      replicaCount: 5
      ingress:
        enabled: true
        host: myapp.example.com

    # Method 2: Parameters (key=value)
    parameters:
    - name: replicaCount
      value: "5"
    - name: image.tag
      value: "v2.0.0"

    # Method 3: Value files in the repo
    valueFiles:
    - environments/production/values.yaml
```

---

**Q49. What is `argocd.argoproj.io/managed-by` annotation?**

When ArgoCD creates a namespace (via `CreateNamespace=true`), it adds this annotation to the namespace:

```yaml
metadata:
  annotations:
    argocd.argoproj.io/managed-by: my-argocd-app
```

This tells ArgoCD which Application "owns" the namespace, enabling proper cleanup when the Application is deleted.

---

**Q50. How do you pin a specific Helm chart version in ArgoCD?**

```yaml
source:
  repoURL: https://charts.bitnami.com/bitnami
  chart: postgresql
  targetRevision: 12.5.6    # Pin to specific chart version
```

Avoid using version ranges in production — always pin to a specific `targetRevision` for reproducibility.

---

## 6. RBAC, SSO & Security

---

**Q51. How does ArgoCD implement RBAC?**

ArgoCD uses a **built-in RBAC system** (not Kubernetes RBAC) configured in the `argocd-rbac-cm` ConfigMap. It uses a Casbin policy format:

```
p, <subject>, <resource>, <action>, <object>, <effect>
g, <user/group>, <role>
```

```yaml
# argocd-rbac-cm
data:
  policy.default: role:readonly    # Default role for all authenticated users
  policy.csv: |
    # Admin role
    p, role:admin, applications, *, */*, allow
    p, role:admin, clusters, *, *, allow
    p, role:admin, repositories, *, *, allow

    # Developer role — only sync apps in their project
    p, role:developer, applications, get, my-project/*, allow
    p, role:developer, applications, sync, my-project/*, allow
    p, role:developer, applications, action/*, my-project/*, allow

    # Bind groups to roles
    g, dev-team, role:developer
    g, ops-team, role:admin
```

---

**Q52. What are the built-in ArgoCD roles?**

| Role | Permissions |
|---|---|
| `role:readonly` | Read-only access to all resources |
| `role:admin` | Full access to all resources |

All other roles are custom-defined. The `policy.default` field sets the role for any authenticated user without an explicit binding.

---

**Q53. What resources can be controlled via ArgoCD RBAC?**

| Resource | Actions |
|---|---|
| `applications` | `get`, `create`, `update`, `delete`, `sync`, `override`, `action/*` |
| `applicationsets` | `get`, `create`, `update`, `delete` |
| `clusters` | `get`, `create`, `update`, `delete` |
| `repositories` | `get`, `create`, `update`, `delete` |
| `projects` | `get`, `create`, `update`, `delete` |
| `accounts` | `get`, `update` |
| `certificates` | `get`, `create`, `delete` |
| `logs` | `get` |
| `exec` | `create` |

---

**Q54. How does ArgoCD SSO work with an OIDC provider?**

ArgoCD uses **Dex** (a built-in OIDC identity broker) or connects directly to an external OIDC provider:

```yaml
# argocd-cm — Direct OIDC (without Dex)
data:
  oidc.config: |
    name: Google
    issuer: https://accounts.google.com
    clientID: my-client-id
    clientSecret: $oidc.google.clientSecret
    requestedScopes:
    - openid
    - profile
    - email
    - groups
```

```yaml
# argocd-cm — Via Dex (GitHub connector)
data:
  dex.config: |
    connectors:
    - type: github
      id: github
      name: GitHub
      config:
        clientID: my-github-app-id
        clientSecret: $dex.github.clientSecret
        orgs:
        - name: my-org
```

---

**Q55. How do you map OIDC groups to ArgoCD roles?**

In `argocd-rbac-cm`:
```yaml
data:
  policy.csv: |
    g, my-org:platform-team, role:admin
    g, my-org:dev-team, role:developer
    g, my-org:readonly-team, role:readonly
```

The group format depends on the connector:
- GitHub: `org:team-name`
- LDAP/AD: `CN=groupname,OU=Groups,DC=company,DC=com`
- Okta: Group name as returned in token

---

**Q56. How does ArgoCD store repository and cluster credentials securely?**

ArgoCD stores credentials as **Kubernetes Secrets** in the `argocd` namespace:

```bash
# Repository credential secrets
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=repository

# Cluster credential secrets
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster
```

Secrets can be templated using **Bitnami Sealed Secrets**, **External Secrets Operator**, or **HashiCorp Vault** for secure GitOps-native secret management.

---

**Q57. What is the ArgoCD `admin` account and how do you manage it?**

The `admin` account is the built-in local admin user. In production:

```bash
# Change admin password
argocd account update-password \
  --current-password old-pass \
  --new-password new-pass

# Disable local admin (use SSO only)
# In argocd-cm:
data:
  admin.enabled: "false"

# Create additional local users
data:
  accounts.alice: apiKey, login
  accounts.alice.enabled: "true"
```

---

**Q58. What is the ArgoCD `exec` feature?**

The `exec` feature allows users to open a **shell into Pod containers** directly from the ArgoCD UI — similar to `kubectl exec`. Must be explicitly enabled and controlled via RBAC:

```yaml
# argocd-cm
data:
  exec.enabled: "true"

# argocd-rbac-cm
data:
  policy.csv: |
    p, role:ops, exec, create, */*, allow
```

---

**Q59. What is the ArgoCD `audit` log and how do you access it?**

ArgoCD logs all API operations. Access via:

```bash
# ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server

# Application controller logs
kubectl logs -n argocd statefulset/argocd-application-controller

# Filter for audit events
kubectl logs -n argocd deployment/argocd-server | grep audit
```

For structured audit logging, ship ArgoCD logs to a centralized logging system (EFK, Loki).

---

**Q60. How do you restrict which namespaces an AppProject can deploy to?**

```yaml
spec:
  destinations:
  # Allow only specific namespaces on the default cluster
  - server: https://kubernetes.default.svc
    namespace: frontend-prod
  - server: https://kubernetes.default.svc
    namespace: frontend-staging
  # Wildcard — allow all namespaces matching pattern
  - server: https://kubernetes.default.svc
    namespace: team-alpha-*
  # Deny all other destinations by omitting them
```

---

## 7. Multi-Cluster & Advanced Deployments

---

**Q61. How does ArgoCD manage multiple clusters?**

ArgoCD can deploy to **multiple Kubernetes clusters** from a single control plane:

```bash
# Add an external cluster (uses local kubeconfig context)
argocd cluster add my-prod-cluster-context

# List registered clusters
argocd cluster list

# The cluster is stored as a Secret in argocd namespace
kubectl get secrets -n argocd -l argocd.argoproj.io/secret-type=cluster
```

Each cluster gets a unique `server` URL used in Application `destination.server`.

---

**Q62. What is the hub-and-spoke model in ArgoCD?**

ArgoCD runs on a central **hub cluster** and manages workloads on multiple **spoke clusters**:

```
Hub Cluster (ArgoCD installed)
    ├── Spoke Cluster 1 (dev)
    ├── Spoke Cluster 2 (staging)
    └── Spoke Cluster 3 (production)
```

ArgoCD uses service account tokens stored as Secrets to authenticate to each spoke cluster. The spoke clusters do not need ArgoCD installed.

---

**Q63. What is ArgoCD in HA (High Availability) mode?**

HA mode runs multiple replicas of ArgoCD components:

```yaml
# argocd-application-controller runs as StatefulSet (1 replica by default)
# For HA: use multiple shards
spec:
  replicas: 3    # 3 shards, each managing a subset of Applications

# argocd-server and argocd-repo-server scale horizontally
spec:
  replicas: 3
```

Install using the HA manifest:
```bash
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/ha/install.yaml
```

---

**Q64. What is Application sharding in ArgoCD HA?**

In HA mode, the Application Controller can distribute Applications across multiple shards (replicas) for improved scalability:

- Each shard manages a subset of clusters
- Controlled by `ARGOCD_CONTROLLER_REPLICAS` env var
- Applications are distributed via consistent hashing based on cluster name

```bash
# Check which shard manages a cluster
kubectl logs -n argocd argocd-application-controller-0 | grep shard
```

---

**Q65. What is the ArgoCD Image Updater?**

ArgoCD Image Updater is a tool that **automatically updates container image tags** in Git when new images are pushed to a registry:

```yaml
# Annotation on ArgoCD Application
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: myapp=registry.example.com/myapp
    argocd-image-updater.argoproj.io/myapp.update-strategy: semver
    argocd-image-updater.argoproj.io/myapp.allow-tags: "^v[0-9]+\.[0-9]+\.[0-9]+$"
    argocd-image-updater.argoproj.io/write-back-method: git
```

Update strategies: `semver`, `latest`, `digest`, `name`

---

**Q66. How do you implement environment promotion with ArgoCD?**

**Pattern 1 — Branch-based promotion:**
```
feature branch → dev Application (tracks dev branch)
    ↓ PR merge
main branch → staging Application (tracks main)
    ↓ Git tag
v1.2.0 tag → prod Application (tracks v1.2.0)
```

**Pattern 2 — Directory-based promotion:**
```
environments/dev/     → dev Application
environments/staging/ → staging Application
environments/prod/    → prod Application
```

Changes promoted by copying/updating files between directories via PR.

---

**Q67. How do you implement canary deployments with ArgoCD?**

ArgoCD integrates with **Argo Rollouts** for advanced deployment strategies:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
metadata:
  name: my-app
spec:
  strategy:
    canary:
      steps:
      - setWeight: 10        # 10% traffic to canary
      - pause: {duration: 5m}
      - setWeight: 50        # 50% traffic
      - pause: {duration: 10m}
      - setWeight: 100       # Full rollout
  template:
    ...
```

ArgoCD monitors Rollout health and shows progress in the UI.

---

**Q68. What is Argo Rollouts and how does it differ from a Deployment?**

| Feature | Deployment | Argo Rollouts |
|---|---|---|
| Strategies | RollingUpdate, Recreate | Canary, Blue-Green, progressive |
| Traffic splitting | None (replica-based only) | Precise % via Service Mesh or NGINX |
| Automated analysis | None | Built-in (metrics-based promotion/abort) |
| Pause/resume | Limited | Full control |
| ArgoCD integration | Standard | Native (health checks, UI visualization) |

---

**Q69. What is an AnalysisTemplate in Argo Rollouts?**

An AnalysisTemplate defines **automated analysis** (metrics checks) to determine if a canary should proceed or roll back:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AnalysisTemplate
metadata:
  name: success-rate
spec:
  metrics:
  - name: success-rate
    interval: 5m
    successCondition: result[0] >= 0.95
    failureLimit: 3
    provider:
      prometheus:
        address: http://prometheus:9090
        query: |
          sum(rate(http_requests_total{status!~"5.."}[5m]))
          /
          sum(rate(http_requests_total[5m]))
```

---

**Q70. What is the difference between ArgoCD and Argo Workflows?**

| | ArgoCD | Argo Workflows |
|---|---|---|
| Purpose | GitOps CD for Kubernetes | Workflow orchestration (DAG pipelines) |
| Use case | Deploy apps from Git | Run CI pipelines, ML pipelines, batch jobs |
| Resource type | `Application` | `Workflow`, `WorkflowTemplate` |
| Triggers | Git commits, manual | Event-based, scheduled, API |

Both are part of the **Argo Project** (Argo CD, Argo Workflows, Argo Events, Argo Rollouts).

---

## 8. Notifications, Webhooks & Integrations

---

**Q71. What is ArgoCD Notifications?**

ArgoCD Notifications is a system for **sending alerts and messages** when Application events occur:
- App synced successfully
- App health degraded
- Sync failed
- OutOfSync detected

Supports: Slack, Email, PagerDuty, OpsGenie, Telegram, Webhook, GitHub, Microsoft Teams, Grafana.

---

**Q72. How do you configure a Slack notification in ArgoCD?**

```yaml
# argocd-notifications-cm
apiVersion: v1
kind: ConfigMap
metadata:
  name: argocd-notifications-cm
  namespace: argocd
data:
  service.slack: |
    token: $slack-token
  template.app-sync-succeeded: |
    message: |
      Application {{.app.metadata.name}} has been successfully synced.
  trigger.on-sync-succeeded: |
    - when: app.status.operationState.phase in ['Succeeded']
      send: [app-sync-succeeded]
```

```yaml
# Annotation on Application
metadata:
  annotations:
    notifications.argoproj.io/subscribe.on-sync-succeeded.slack: my-channel
    notifications.argoproj.io/subscribe.on-health-degraded.slack: alerts-channel
```

---

**Q73. What is a Git webhook and how does it improve ArgoCD performance?**

By default, ArgoCD polls Git repositories every 3 minutes. Git webhooks allow Git providers to **push change notifications** to ArgoCD immediately when a commit is pushed — dramatically reducing sync latency:

```bash
# Configure webhook in GitHub:
# Settings → Webhooks → Add webhook
# Payload URL: https://argocd.example.com/api/webhook
# Content type: application/json
# Secret: same as argocd-secret webhook.github.secret

# In argocd-secret:
data:
  webhook.github.secret: <base64-encoded-secret>
```

Supported: GitHub, GitLab, Bitbucket, Gitea, Azure DevOps.

---

**Q74. How does ArgoCD integrate with CI pipelines?**

Common pattern — CI builds image, updates Git, ArgoCD deploys:

```
# In CI pipeline (GitHub Actions / GitLab CI)

# Step 1: Build and push image
docker build -t registry.example.com/myapp:$SHA .
docker push registry.example.com/myapp:$SHA

# Step 2: Update image tag in Git (GitOps repo)
cd gitops-repo
kustomize edit set image myapp=registry.example.com/myapp:$SHA
git commit -am "Update image to $SHA"
git push

# Step 3: ArgoCD detects Git change → syncs automatically
# OR: Trigger sync via API
argocd app sync my-app --auth-token $ARGOCD_TOKEN
```

---

**Q75. How do you use ArgoCD's API from CI without storing credentials?**

Use an **ArgoCD API token** scoped to specific actions:

```bash
# Create a local account in argocd-cm
data:
  accounts.ci-pipeline: apiKey

# Generate API token
argocd account generate-token --account ci-pipeline

# Use in CI
curl -H "Authorization: Bearer $ARGOCD_TOKEN" \
  https://argocd.example.com/api/v1/applications/my-app/sync \
  -d '{}' -X POST
```

---

**Q76. What is the ArgoCD metrics endpoint?**

ArgoCD exposes Prometheus metrics:

```bash
# ArgoCD server metrics
http://argocd-metrics:8082/metrics

# Application controller metrics
http://argocd-application-controller:8082/metrics

# Repo server metrics
http://argocd-repo-server:8084/metrics
```

Key metrics:
- `argocd_app_info` — App sync/health status
- `argocd_app_sync_total` — Sync count by result
- `argocd_cluster_api_resource_objects` — Managed resource count
- `argocd_git_request_duration_seconds` — Git operation latency

---

**Q77. How do you integrate ArgoCD with Vault for secret management?**

Two common approaches:

**Option 1 — Vault Agent Injector:**
Vault injects secrets as files into Pods via sidecar — ArgoCD manages the Deployment normally.

**Option 2 — ArgoCD Vault Plugin (AVP):**
A CMP that substitutes `<path:vault/path#key>` placeholders in manifests at sync time:

```yaml
# In a Secret manifest (stored in Git)
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
  annotations:
    avp.kubernetes.io/path: "secret/data/myapp/db"
type: Opaque
stringData:
  password: <password>    # AVP replaces this at sync time
```

---

**Q78. What is Sealed Secrets and how does it work with ArgoCD?**

Sealed Secrets (by Bitnami) allows storing **encrypted secrets in Git**:

1. A controller runs in the cluster with a private key
2. You encrypt secrets with the public key using `kubeseal`
3. The `SealedSecret` YAML is safe to commit to Git
4. ArgoCD syncs the `SealedSecret` to the cluster
5. The controller decrypts it into a regular `Secret`

```bash
# Encrypt a secret
kubectl create secret generic mysecret --from-literal=password=s3cr3t \
  --dry-run=client -o yaml | \
  kubeseal --controller-namespace kube-system \
  --format yaml > sealed-secret.yaml

# Commit sealed-secret.yaml to Git — ArgoCD syncs it
```

---

## 9. Troubleshooting & Operations

---

**Q79. How do you troubleshoot an Application stuck in `OutOfSync`?**

```bash
# Step 1: Check the diff
argocd app diff my-app

# Step 2: Get detailed sync status
argocd app get my-app

# Step 3: Check for ignoreDifferences — maybe a field is being mutated
# Step 4: Force refresh (re-fetch from Git)
argocd app get my-app --refresh

# Step 5: Hard refresh (discard cache)
argocd app get my-app --hard-refresh

# Step 6: Manual sync with replace
argocd app sync my-app --replace
```

Common causes:
- Field mutated by a controller (HPA changing replicas) → add `ignoreDifferences`
- Webhook not populating (e.g., cert-manager CA bundle) → add `ignoreDifferences`
- Resource exists in cluster but not in Git (orphaned) → enable `prune`

---

**Q80. How do you troubleshoot an Application stuck in `Progressing`?**

```bash
# Check what resources are progressing
argocd app get my-app

# Check the actual resource in cluster
kubectl rollout status deployment/my-app -n production
kubectl describe deployment my-app -n production

# Common causes:
# - Deployment rollout not completing (bad image, probe failing)
# - PVC not binding
# - Init container failing
```

---

**Q81. How do you troubleshoot a sync that keeps failing?**

```bash
# Check sync operation details
argocd app get my-app --show-operation

# Check ArgoCD server logs
kubectl logs -n argocd deployment/argocd-server | tail -50

# Check application controller logs
kubectl logs -n argocd statefulset/argocd-application-controller | tail -50

# Check repo server (manifest generation issues)
kubectl logs -n argocd deployment/argocd-repo-server | tail -50

# Common causes:
# - YAML validation error in manifests
# - Webhook/hook Job failing
# - RBAC preventing resource creation
# - Namespace doesn't exist (add CreateNamespace=true)
```

---

**Q82. How do you force ArgoCD to re-fetch from Git?**

```bash
# Soft refresh — clears app cache, re-fetches from Git
argocd app get my-app --refresh

# Hard refresh — clears ALL caches including repo server cache
argocd app get my-app --hard-refresh

# Via UI: Click the "Refresh" button (hard refresh = hold Shift + click)
```

---

**Q83. How do you debug manifest generation issues?**

```bash
# Generate manifests locally (same way ArgoCD does)
argocd app manifests my-app

# Generate with specific revision
argocd app manifests my-app --revision v1.2.3

# Check repo server logs for generation errors
kubectl logs -n argocd deployment/argocd-repo-server

# Test Helm rendering directly
helm template my-chart ./chart -f values-prod.yaml

# Test Kustomize directly
kustomize build k8s/overlays/production
```

---

**Q84. How do you check ArgoCD component health?**

```bash
# Check all ArgoCD pods
kubectl get pods -n argocd

# Check ArgoCD server health endpoint
curl -k https://argocd.example.com/healthz

# Check metrics
curl http://argocd-metrics:8082/metrics | grep argocd_app

# Check Redis
kubectl exec -n argocd deployment/argocd-redis -- redis-cli ping

# Check if Application Controller is running
kubectl get statefulset -n argocd argocd-application-controller
```

---

**Q85. How do you back up and restore ArgoCD?**

ArgoCD state lives in Kubernetes — back it up with standard tools:

```bash
# Export all ArgoCD CRDs and Secrets
kubectl get applications,appprojects \
  -n argocd -o yaml > argocd-apps-backup.yaml

# Export secrets (repo creds, cluster creds)
kubectl get secrets -n argocd \
  -l argocd.argoproj.io/secret-type \
  -o yaml > argocd-secrets-backup.yaml

# Full backup using Velero
velero backup create argocd-backup \
  --include-namespaces argocd

# Restore
velero restore create --from-backup argocd-backup
```

---

**Q86. How do you delete an Application without deleting its resources?**

```bash
# Delete Application object only (resources stay in cluster)
argocd app delete my-app --cascade=false

# Or via kubectl
kubectl delete application my-app -n argocd \
  --cascade=false

# Delete Application AND all its resources (default)
argocd app delete my-app
```

---

**Q87. What is the `argocd app terminate-op` command?**

Used to cancel a running sync operation (useful when a sync is stuck):

```bash
argocd app terminate-op my-app

# Or via kubectl — delete the operation from the Application status
kubectl patch application my-app -n argocd \
  --type json \
  -p '[{"op": "remove", "path": "/status/operationState"}]'
```

---

**Q88. How do you upgrade ArgoCD?**

```bash
# Via manifests
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj/argo-cd/v2.9.0/manifests/install.yaml

# Via Helm
helm repo update
helm upgrade argocd argo/argo-cd -n argocd \
  --version 5.51.0 \
  -f values.yaml

# Check version
argocd version
kubectl get deployment argocd-server -n argocd \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

**Q89. What is the `OutOfSync` operation state vs. sync status?**

| | Sync Status | Operation State |
|---|---|---|
| What it describes | Desired vs. live state comparison | Result of the last sync operation |
| Values | `Synced`, `OutOfSync`, `Unknown` | `Running`, `Succeeded`, `Failed`, `Error` |
| When shown | Always | Only during/after a sync |

An Application can be `Synced` but the last operation state `Failed` (e.g., a PostSync hook failed after successful resource sync).

---

**Q90. How do you manage ArgoCD at scale (100+ applications)?**

Best practices:
- Use **ApplicationSet** instead of individual Applications
- Enable **Application controller sharding** for HA
- Use **AppProjects** to organize and delegate ownership
- Set **resource exclusions** for noisy resources (e.g., `EndpointSlices`)
- Configure **`resource.compareoptions`** to optimize diff computation
- Use **sync windows** to stagger syncs and reduce API server load
- Enable **server-side apply** (`ServerSideApply=true`) to reduce conflict issues

```yaml
# argocd-cm — exclude high-churn resources
data:
  resource.exclusions: |
    - apiGroups: [""]
      kinds: ["Endpoints"]
      clusters: ["*"]
    - apiGroups: ["discovery.k8s.io"]
      kinds: ["EndpointSlice"]
      clusters: ["*"]
```

---

## 10. Scenario-Based & Real-World Questions

---

**Q91. SCENARIO: A developer pushes a bad image to Git. How does ArgoCD handle it and how do you recover?**

```bash
# 1. ArgoCD detects Git change → syncs automatically (if selfHeal enabled)
# 2. New Pods fail to start (ImagePullBackOff or CrashLoopBackOff)
# 3. Deployment health: Degraded
# 4. ArgoCD Application health: Degraded

# Recovery options:

# Option A: Revert in Git (correct GitOps approach)
git revert HEAD
git push
# ArgoCD detects revert → syncs back to working state

# Option B: ArgoCD rollback (points App to previous commit)
argocd app rollback my-app     # Rolls back to last synced state
# Note: selfHeal will re-sync from Git unless you also revert Git

# Option C: Pin to known-good revision temporarily
argocd app set my-app --revision v1.1.0
argocd app sync my-app
```

---

**Q92. SCENARIO: HPA is changing replica count but ArgoCD keeps reverting it. How do you fix this?**

The HPA changes `spec.replicas` on the Deployment, but ArgoCD sees this as drift and reverts to the Git-defined value.

**Fix — add `ignoreDifferences`:**
```yaml
spec:
  ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers:
    - /spec/replicas
  syncPolicy:
    syncOptions:
    - RespectIgnoreDifferences=true   # Apply ignoreDifferences during sync too
```

Also remove `replicas` from the Deployment manifest in Git (let HPA fully manage it).

---

**Q93. SCENARIO: You need to deploy the same application to 50 clusters. How do you set this up?**

Use an **ApplicationSet with Cluster generator**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: my-app-all-clusters
  namespace: argocd
spec:
  generators:
  - clusters:
      selector:
        matchLabels:
          environment: production    # Only production clusters
  template:
    metadata:
      name: '{{name}}-my-app'
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/my-app.git
        targetRevision: HEAD
        path: k8s/production
      destination:
        server: '{{server}}'
        namespace: my-app
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
```

Label clusters when registering them:
```bash
argocd cluster set https://cluster-1.example.com \
  --label environment=production
```

---

**Q94. SCENARIO: You want ArgoCD to automatically deploy on every merge to `main` but require manual approval for production. How?**

```yaml
# Staging Application — fully automated
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-staging
spec:
  source:
    targetRevision: main
  syncPolicy:
    automated:
      prune: true
      selfHeal: true

---
# Production Application — manual sync only
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app-prod
spec:
  source:
    targetRevision: main    # Watches same branch
  # No syncPolicy.automated → manual sync required
  # Use sync windows for additional protection:
  syncPolicy:
    syncOptions:
    - ApplyOutOfSyncOnly=true
```

Production team manually reviews diff in ArgoCD UI before clicking Sync.

---

**Q95. SCENARIO: A sync hook (PreSync Job) is failing. How do you debug and bypass it?**

```bash
# Step 1: Find the failed hook Job
kubectl get jobs -n production | grep argocd-hook
kubectl logs job/db-migration -n production

# Step 2: Check the Job events
kubectl describe job db-migration -n production

# Step 3: Delete failed hook (ArgoCD will recreate on next sync)
kubectl delete job db-migration -n production

# Step 4: If hook is consistently failing and you need to bypass:
# Option A — Sync with replace (skips hooks with BeforeHookCreation policy)
argocd app sync my-app --replace

# Option B — Temporarily remove hook annotation in Git
# Remove: argocd.argoproj.io/hook: PreSync
# Sync → fix underlying issue → restore annotation

# Option C — Skip specific resources
argocd app sync my-app --resource batch:Job:db-migration
```

---

**Q96. SCENARIO: You want Git branches to automatically create preview environments. How?**

Use ApplicationSet with the **PullRequest generator**:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: preview-apps
  namespace: argocd
spec:
  generators:
  - pullRequest:
      github:
        owner: myorg
        repo: my-app
        labels:
        - preview                  # Only PRs with 'preview' label
      requeueAfterSeconds: 60
  template:
    metadata:
      name: 'preview-{{number}}'
    spec:
      project: preview
      source:
        repoURL: https://github.com/myorg/my-app.git
        targetRevision: '{{head_sha}}'
        path: k8s/preview
        helm:
          parameters:
          - name: ingress.host
            value: 'pr-{{number}}.preview.example.com'
      destination:
        server: https://kubernetes.default.svc
        namespace: 'preview-{{number}}'
      syncPolicy:
        automated:
          prune: true
        syncOptions:
        - CreateNamespace=true
```

---

**Q97. SCENARIO: You need to migrate from Helm releases to ArgoCD. What is the process?**

```bash
# Step 1: Export current Helm release values
helm get values my-app -n production > current-values.yaml

# Step 2: Create GitOps repo with values and chart reference
# Commit Chart.yaml or use external chart reference in ArgoCD

# Step 3: Create ArgoCD Application pointing to the repo
argocd app create my-app \
  --repo https://github.com/myorg/gitops.git \
  --path apps/my-app \
  --dest-namespace production \
  --dest-server https://kubernetes.default.svc

# Step 4: Sync — ArgoCD adopts existing resources
# ArgoCD does NOT delete and recreate; it applies over existing resources

# Step 5: Verify
argocd app get my-app    # Should show Synced + Healthy

# Step 6: Remove Helm release history (optional — ArgoCD won't use it)
helm uninstall my-app -n production --keep-history  # Keeps resources, removes Helm Secret
```

---

**Q98. SCENARIO: How do you implement secrets management in a GitOps workflow with ArgoCD?**

**Option 1 — Sealed Secrets (simplest):**
```bash
# Encrypt and commit
kubectl create secret generic db-pass --from-literal=pass=secret \
  --dry-run=client -o yaml | kubeseal -o yaml > sealed-db-pass.yaml
git add sealed-db-pass.yaml && git commit -m "Add sealed secret"
# ArgoCD syncs SealedSecret → controller decrypts → Secret created
```

**Option 2 — External Secrets Operator:**
```yaml
# ExternalSecret in Git (safe to commit)
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-credentials
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: db-credentials
  data:
  - secretKey: password
    remoteRef:
      key: secret/myapp/db
      property: password
```

**Option 3 — ArgoCD Vault Plugin (AVP):**
Secrets are placeholders in manifests; plugin substitutes at sync time.

---

**Q99. What are ArgoCD best practices for production?**

**Security:**
- Disable local admin account; use SSO
- Use AppProjects to restrict team access
- Store repo/cluster credentials as Sealed Secrets or via ESO
- Enable RBAC — use `role:readonly` as default

**Reliability:**
- Deploy ArgoCD in HA mode for production
- Configure retry policy on Applications
- Set up Git webhooks for faster sync
- Use sync windows to prevent off-hours syncs

**Scalability:**
- Use ApplicationSet instead of individual Applications
- Exclude high-churn resources (Endpoints, EndpointSlices)
- Enable Application Controller sharding
- Use Redis cluster for large deployments

**GitOps hygiene:**
- Never run `kubectl apply` directly — all changes via Git
- Pin all `targetRevision` to specific tags in production
- Use separate repos for app code and GitOps config
- Require PR reviews before merging to the GitOps repo

---

**Q100. What is the ArgoCD `Resource Tracking` method and what options exist?**

ArgoCD needs to track which cluster resources belong to an Application. Three methods:

| Method | How | Notes |
|---|---|---|
| `label` (default) | Adds `app.kubernetes.io/instance` label | Works for most resources |
| `annotation` | Adds `argocd.argoproj.io/tracking-id` annotation | Better for immutable fields |
| `annotation+label` | Both | Maximum compatibility |

```yaml
# argocd-cm
data:
  application.resourceTrackingMethod: annotation
```

---

**Q101. What is the `selfHeal` feature and what are its risks?**

`selfHeal: true` means ArgoCD automatically reverts any manual change to the cluster back to the Git-defined state.

**Risks:**
- Emergency hotfixes applied via `kubectl` are immediately reverted
- Operators/controllers that mutate resources may cause constant sync loops
- If Git has a broken state, selfHeal continuously applies broken config

**Mitigation:**
- Use `ignoreDifferences` for controller-managed fields
- Use sync windows to temporarily pause selfHeal during incidents
- Always fix the root cause in Git, not directly in the cluster

---

**Q102. What is the difference between `argocd app sync` and `argocd app sync --force`?**

| `argocd app sync` | `argocd app sync --force` |
|---|---|
| Standard sync — applies changes | Force sync — replaces resources (`kubectl replace`) |
| Fails if resources conflict | Deletes and recreates conflicting resources |
| Safe for most cases | Use when standard sync fails due to immutable field changes |
| Default | Use with caution in production |

---

**Q103. How does ArgoCD handle CRDs and their instances?**

ArgoCD can manage both CRDs and their instances (Custom Resources). Important consideration:

- CRDs must be applied **before** their instances
- Use **sync waves**: CRDs in wave `-1`, instances in wave `0`

```yaml
# CRD
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "-1"

# Custom Resource instance
metadata:
  annotations:
    argocd.argoproj.io/sync-wave: "0"
```

ArgoCD also has built-in awareness of CRD dependencies and applies them first by default.

---

**Q104. What is the `argocd admin` command used for?**

```bash
# Export all Application manifests (for backup/migration)
argocd admin export > backup.yaml

# Import Applications
argocd admin import < backup.yaml

# Reset user password
argocd admin initial-password -n argocd

# Check cluster connectivity
argocd admin cluster stats

# Generate API token for an account
argocd admin account generate-token --account ci-user
```

---

**Q105. How do you implement a GitOps-native promotion pipeline?**

```
Developer pushes code
        ↓
CI builds & pushes image (GitHub Actions / GitLab CI)
        ↓
CI opens PR to GitOps repo updating image tag in dev/
        ↓
Auto-merge (or review) → ArgoCD syncs dev environment
        ↓
Automated tests pass → CI opens PR updating image tag in staging/
        ↓
Review → merge → ArgoCD syncs staging
        ↓
Manual approval → PR to update prod/ image tag
        ↓
Review → merge → ArgoCD syncs production
```

Each environment is a directory or branch; promotion = PR merge.

---

**Q106. What is the `orphaned resources` feature in ArgoCD?**

Orphaned resources are cluster resources that exist in the Application's destination namespace but are **not tracked by any ArgoCD Application**. ArgoCD can warn about them:

```yaml
spec:
  orphanedResources:
    warn: true        # Show warning in UI
    ignore:
    - group: ""
      kind: ConfigMap
      name: kube-root-ca.crt   # Ignore specific resources
```

Useful for detecting resources created outside of GitOps.

---

**Q107. How does ArgoCD handle namespace-scoped vs cluster-scoped resources?**

- **Namespace-scoped resources** (Pods, Deployments, Services): Deployed to `destination.namespace`
- **Cluster-scoped resources** (ClusterRoles, Namespaces, PVs): Deployed cluster-wide regardless of `destination.namespace`

By default, AppProjects can restrict which **cluster-scoped resources** Applications are allowed to create:

```yaml
spec:
  clusterResourceWhitelist:
  - group: ""
    kind: Namespace
  - group: rbac.authorization.k8s.io
    kind: ClusterRole
```

---

**Q108. What is the Application `finalizer` and what does it do?**

ArgoCD adds a finalizer to Applications to control deletion behavior:

```yaml
metadata:
  finalizers:
  - resources-finalizer.argocd.argoproj.io   # Delete all managed resources when App is deleted
```

Without this finalizer, deleting the Application leaves resources in the cluster (orphaned).

```bash
# Remove finalizer to delete Application without deleting resources
kubectl patch application my-app -n argocd \
  -p '{"metadata":{"finalizers":null}}' \
  --type merge
```

---

**Q109. What is a Repository Template in ArgoCD?**

Repository credential templates allow you to define credentials **once** for a hostname pattern, and all repos under that host inherit them automatically:

```bash
argocd repocreds add https://github.com/myorg/ \
  --username myuser \
  --password ghp_mytoken

# Now all repos under https://github.com/myorg/ use these creds
# No need to add credentials per repo
```

---

**Q110. How do you monitor ArgoCD Application sync status from the command line in CI?**

```bash
# Wait for sync to complete and app to be healthy
argocd app sync my-app
argocd app wait my-app \
  --health \
  --sync \
  --timeout 300

# Exit code 0 = success, non-zero = failure
echo "Exit code: $?"

# Check in a loop (alternative)
for i in $(seq 1 30); do
  STATUS=$(argocd app get my-app -o json | jq -r '.status.health.status')
  if [ "$STATUS" = "Healthy" ]; then
    echo "App is healthy!"
    exit 0
  fi
  echo "Status: $STATUS — waiting..."
  sleep 10
done
echo "Timeout waiting for healthy status"
exit 1
```

---

## Final Quick-Reference

---

**Q111. What are the most important ArgoCD CLI commands to know?**

```bash
# Application management
argocd app list
argocd app get <app>
argocd app create <app> ...
argocd app sync <app>
argocd app diff <app>
argocd app delete <app>
argocd app rollback <app>
argocd app wait <app> --health
argocd app manifests <app>
argocd app set <app> --revision v1.2.3
argocd app terminate-op <app>

# Repository management
argocd repo list
argocd repo add <url> --username ... --password ...

# Cluster management
argocd cluster list
argocd cluster add <context>
argocd cluster rm <server-url>

# Account management
argocd account list
argocd account update-password
argocd account generate-token

# Project management
argocd proj list
argocd proj create <project>
argocd proj get <project>
```

---

**Q112. What are the key ArgoCD CRDs?**

| CRD | API Group | Purpose |
|---|---|---|
| `Application` | `argoproj.io/v1alpha1` | Represents a deployed application |
| `AppProject` | `argoproj.io/v1alpha1` | Multi-tenancy and access control |
| `ApplicationSet` | `argoproj.io/v1alpha1` | Auto-generate multiple Applications |
| `Rollout` | `argoproj.io/v1alpha1` | Argo Rollouts canary/blue-green |
| `AnalysisTemplate` | `argoproj.io/v1alpha1` | Metrics-based rollout analysis |
| `AnalysisRun` | `argoproj.io/v1alpha1` | An instance of an AnalysisTemplate |

---

**Q113. What is the ArgoCD sync operation timeout?**

```yaml
# Per-Application timeout
spec:
  syncPolicy:
    managedNamespaceMetadata: {}

# Global default — in argocd-cm
data:
  timeout.reconciliation: 180s      # How often to check for drift
  application.sync.timeout: 300s   # Not a direct config; use --timeout in CLI
```

```bash
# Set per-sync timeout
argocd app sync my-app --timeout 600
```

---

**Q114. What are common ArgoCD interview questions asked at German companies?**

Based on common DevOps hiring patterns in Germany (DACH region):

1. **"Explain GitOps and how ArgoCD implements it"** — Core concept, always asked
2. **"How do you handle secrets in GitOps?"** — Sealed Secrets or ESO
3. **"How do you manage multi-environment deployments?"** — Kustomize overlays or Helm values
4. **"What happens if someone runs kubectl apply directly?"** — selfHeal reverts it
5. **"How do you avoid ArgoCD reverting HPA changes?"** — ignoreDifferences
6. **"How do you structure your GitOps repository?"** — mono vs. poly repo, App of Apps
7. **"How do you implement zero-downtime deployments with ArgoCD?"** — Argo Rollouts canary
8. **"How do you set up multi-cluster deployments?"** — ApplicationSet + Cluster generator
9. **"What is the difference between ArgoCD and Flux?"** — Architecture, UI, multi-tenancy
10. **"How do you integrate ArgoCD into a CI pipeline?"** — Image update + Git commit + webhook

---

**Q115. What is the GitOps repository structure — mono-repo vs. poly-repo?**

**Mono-repo** — all apps in one GitOps repo:
```
gitops-repo/
├── apps/
│   ├── frontend/
│   │   ├── base/
│   │   └── overlays/
│   ├── backend/
│   └── database/
└── infrastructure/
    ├── cert-manager/
    └── ingress-nginx/
```

**Poly-repo** — separate GitOps repo per team/service:
```
frontend-gitops-repo/    → frontend team owns
backend-gitops-repo/     → backend team owns
platform-gitops-repo/    → platform team owns (cert-manager, monitoring, etc.)
```

| | Mono-repo | Poly-repo |
|---|---|---|
| Simplicity | Higher | Lower |
| Team autonomy | Lower | Higher |
| Access control | Harder | Easier (per-repo permissions) |
| Visibility | All in one place | Scattered |

---

**Q116. What is the `argocd-image-updater` write-back method?**

How the Image Updater commits image tag changes back to Git:

| Method | Description |
|---|---|
| `git` | Commits updated image tags directly to Git |
| `argocd` | Updates ArgoCD Application `spec.source.helm.parameters` in-cluster (no Git commit) |

`git` method is the true GitOps approach — changes are traceable via Git history.

---

**Q117. How do you do a dry-run sync in ArgoCD?**

```bash
# Preview what would be applied without actually applying
argocd app sync my-app --dry-run

# Check diff without syncing
argocd app diff my-app

# Preview with specific revision
argocd app diff my-app --revision v1.2.3
```

---

**Q118. What are the most common ArgoCD annotations used in practice?**

```yaml
# Sync wave ordering
argocd.argoproj.io/sync-wave: "5"

# Hook definition
argocd.argoproj.io/hook: PreSync
argocd.argoproj.io/hook-delete-policy: HookSucceeded

# Notification subscriptions
notifications.argoproj.io/subscribe.on-sync-succeeded.slack: my-channel
notifications.argoproj.io/subscribe.on-health-degraded.slack: alerts

# Managed-by (auto-added by ArgoCD)
argocd.argoproj.io/managed-by: my-app

# Skip resource from being managed
argocd.argoproj.io/skip-reconcile: "true"

# Image updater
argocd-image-updater.argoproj.io/image-list: myapp=registry/myapp
argocd-image-updater.argoproj.io/myapp.update-strategy: semver
```

---

**Q119. What is the ArgoCD `resource.customizations` configuration?**

Allows defining **custom health checks** and **custom actions** for any Kubernetes resource type:

```yaml
# argocd-cm
data:
  resource.customizations.health.certmanager.io_Certificate: |
    hs = {}
    if obj.status ~= nil then
      if obj.status.conditions ~= nil then
        for i, condition in ipairs(obj.status.conditions) do
          if condition.type == "Ready" and condition.status == "False" then
            hs.status = "Degraded"
            hs.message = condition.message
            return hs
          end
          if condition.type == "Ready" and condition.status == "True" then
            hs.status = "Healthy"
            hs.message = condition.message
            return hs
          end
        end
      end
    end
    hs.status = "Progressing"
    hs.message = "Waiting for certificate"
    return hs
```

---

**Q120. Summarize the full ArgoCD workflow from code commit to production.**

```
Developer pushes code to feature branch
        ↓
CI pipeline triggered (GitHub Actions / GitLab CI)
    - Run tests
    - Build Docker image
    - Push to registry (registry.example.com/myapp:abc1234)
        ↓
CI updates GitOps repo
    - Opens PR: bump image tag in environments/staging/values.yaml
        ↓
PR reviewed and merged to main
        ↓
ArgoCD detects Git change (webhook or 3-min poll)
        ↓
ArgoCD generates manifests (Helm render / Kustomize build)
        ↓
ArgoCD computes diff (desired vs. live state)
        ↓
If OutOfSync + automated sync enabled:
    - Run PreSync hooks (DB migrations)
    - Apply resources (ordered by sync wave)
    - Run PostSync hooks (smoke tests)
        ↓
ArgoCD updates Application status:
    - Sync status: Synced
    - Health status: Healthy (after probes pass)
        ↓
Notification sent to Slack: "Staging deployment succeeded"
        ↓
Manual promotion: PR to update environments/prod/values.yaml
    → Reviewed → Merged → ArgoCD syncs production
```

---

*End of ArgoCD Interview Q&A — 120 Questions (All Levels)*

---

## What's Next in the Series?

| Priority | Tool | Status |
|---|---|---|
| ✅ Done | Kubernetes (480 Q) | Complete |
| ✅ Done | ArgoCD (120 Q) | Complete |
| 2️⃣ Next | Terraform | Ready to build |
| 3️⃣ After | Helm | Ready to build |
| 4️⃣ Later | OpenShift EX280 | Ready to build |
