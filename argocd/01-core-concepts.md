# GitOps Core Concepts

## Why GitOps Exists — The Problem It Solves

Before GitOps, a typical deployment looked like this:

```
Developer → merge to main → CI pipeline runs
→ pipeline SSHs into servers OR runs kubectl with a stored kubeconfig
→ no record of who deployed what, when, or why
→ if someone manually edits production, nobody knows
→ "works on staging, broken in prod" — nobody knows what differs
```

The problems this created:
- Cluster credentials stored in CI/CD systems — a breach there = full cluster access
- No automatic drift detection — production silently diverges from what's in Git
- Rollback means re-running a pipeline, not just reverting a commit
- Audit trail lives in CI logs, not in the system itself

GitOps solves all of these by making Git the control plane.

## The Four OpenGitOps Principles

### 1. Declarative

The entire system state is described declaratively — not "run these commands" but "this is what should exist." Kubernetes YAML, Helm values, Kustomize overlays — all declarative.

```yaml
# Declarative: this is the desired state
spec:
  replicas: 3
  image: myapp:v1.2.3

# NOT: "scale to 3, then update the image"
# kubectl scale ... && kubectl set image ...
```

### 2. Versioned and Immutable

The desired state lives in Git. Every change is a commit — versioned, auditable, reversible. The history of what was deployed, by whom, and why is the Git log.

```bash
# Full deployment history
git log --oneline environments/production/

# 4a8f3c2 chore: promote myapp v1.2.4 to production (Alice, 2024-01-15)
# 9b1e7d8 fix: rollback myapp to v1.2.3 after memory spike (Bob, 2024-01-14)
# c3f9a1e feat: increase replicas to 5 for Black Friday (Alice, 2024-01-10)
```

### 3. Pulled Automatically

A software agent inside the cluster pulls the desired state from Git and applies it. The cluster credentials never leave the cluster — CI/CD cannot push into the cluster.

```
Push model (traditional):
  CI/CD → kubectl apply → Cluster
  ↑ CI/CD has cluster credentials = risk

Pull model (GitOps):
  GitOps agent (inside cluster) → pulls from Git → applies
  ↑ cluster credentials stay inside the cluster = safe
```

### 4. Continuously Reconciled

The agent doesn't just apply once — it continuously monitors both Git and the cluster. If they diverge (drift), it corrects automatically.

```
Every N minutes:
  1. What does Git say should exist?
  2. What does the cluster actually have?
  3. Apply the diff to eliminate drift
  4. Report status (synced / out-of-sync / error)
```

## The Reconciliation Loop in Detail

```
┌──────────────────────────────────────────────────────────────┐
│                    GitOps Controller                          │
│                                                               │
│   ┌─────────┐    ┌─────────┐    ┌─────────┐    ┌─────────┐  │
│   │ OBSERVE │ →  │  DIFF   │ →  │   ACT   │ →  │ REPORT  │  │
│   │         │    │         │    │         │    │         │  │
│   │ Fetch   │    │ Desired │    │ kubectl │    │ Status  │  │
│   │ from    │    │   vs    │    │  apply  │    │ alerts  │  │
│   │   Git   │    │ Actual  │    │ / delete│    │  events │  │
│   └─────────┘    └─────────┘    └─────────┘    └─────────┘  │
│        ↑                                             │        │
│        └──────────── repeat every N seconds ────────┘        │
└──────────────────────────────────────────────────────────────┘
```

Typical sync intervals:
- Git polling: 1 minute (Flux) / 3 minutes (ArgoCD default)
- Cluster reconciliation: every 5–10 minutes even without Git changes
- Webhook-triggered: immediate (when GitHub/GitLab notifies on push)

## Desired State vs Actual State

| Concept | Definition | Where it lives |
|---------|-----------|---------------|
| Desired state | What should exist | Git repository |
| Actual state | What currently exists | Kubernetes cluster |
| Drift | Difference between the two | Detected by controller |
| Synced | Desired = Actual, no drift | Target state |
| Out-of-sync | Desired ≠ Actual | Triggers reconciliation |

### What Causes Drift

- `kubectl edit` / `kubectl patch` on a live resource
- HPA scaling replicas (allowed — needs `ignoreDifferences`)
- cert-manager injecting CA bundles into webhooks
- Operators modifying resources they manage
- Partial failed deployments leaving stale state
- Infrastructure changes (node failure, PVC resize)

## GitOps vs Traditional CI/CD — Detailed Comparison

| Aspect | Push-based CI/CD | GitOps (pull) |
|--------|-----------------|--------------|
| Cluster access from CI | Yes — credentials in CI | No — controller inside cluster |
| Drift detection | None | Continuous |
| Rollback | Re-run pipeline with old tag | `git revert` + auto-deploy |
| Audit trail | CI job logs | Git commit history |
| Environment parity | Manual effort | Guaranteed by Git |
| Disaster recovery | Re-run pipeline | `flux bootstrap` / ArgoCD sync |
| Secret exposure | Pipeline env vars | Sealed/ESO/SOPS |
| Multi-cluster | N pipelines with N credentials | 1 Git source, N controllers |

## Convergence and Eventual Consistency

GitOps controllers are eventually consistent — they converge to the desired state over time, not instantly.

```
Git commit (desired state updated)
        ↓ ~1 minute (polling interval)
Controller detects change
        ↓ ~seconds
Controller applies change to cluster
        ↓ ~30s–2min (K8s rolling update)
Pods become Ready
        ↓
Status: Synced + Healthy
```

Total time from `git push` to fully deployed: typically 2–5 minutes for a simple change.

To speed this up: configure webhooks so Git pushes trigger immediate reconciliation — reduces latency to ~30 seconds.

## Immutable Infrastructure and GitOps

GitOps pairs naturally with immutable infrastructure — the idea that you never patch running instances, you replace them.

```
Mutable: ssh into server, edit config, restart service
         → server state diverges from what Git says
         → "works on Bob's server, broken on Alice's"

Immutable + GitOps:
  Edit config file → commit to Git → GitOps deploys new pod with new config
  → all environments have exactly what Git says
  → no snowflake servers
```

## Self-Healing in Practice

With `selfHeal: true` (ArgoCD) or `prune: true` (Flux):

```bash
# Developer manually scales down pods in production
kubectl scale deployment myapp --replicas=0 -n production

# 3 minutes later...
# GitOps controller detects replicas=5 in Git, replicas=0 in cluster
# Controller applies: kubectl scale deployment myapp --replicas=5
# Pods come back up

# Audit trail shows: deployment was "repaired" at 14:32:05
```

This is a feature, not a bug. It enforces the discipline: if you want to change something in production, change Git first.

## When NOT to Use GitOps

GitOps is not always the right tool:

- **Stateful data migrations** — database schema changes need ordered, one-time execution, not continuous reconciliation
- **One-off debugging** — `kubectl exec` into a pod to diagnose a live issue is fine; it doesn't affect desired state
- **Secrets with frequent rotation** — use ESO or Vault directly; don't commit re-encrypted secrets every hour
- **Very fast iteration in dev** — a developer iterating locally might not want every code change going through Git; use Skaffold or Tilt for inner-loop development

## GitOps Maturity Model

```
Level 0: Manual — kubectl apply, helm upgrade by hand
Level 1: CI Push — pipeline applies manifests (push model)
Level 2: GitOps basics — pull model, Git is source of truth, auto-sync
Level 3: GitOps + drift detection + self-healing + audit trail
Level 4: Full GitOps — secrets, image automation, multi-cluster, policy-as-code all in Git
```

Most teams aim for Level 3. Level 4 requires significant investment but delivers the highest reliability and compliance posture — particularly important for ISO 27001 / SOC2 audits in German enterprise environments.

## Key Concepts Cheat Sheet

```
Desired state     = what Git says should exist
Actual state      = what the cluster has right now
Drift             = gap between desired and actual
Reconciliation    = process of closing that gap
Sync              = ArgoCD term for reconciliation
Synced            = no drift (desired == actual)
OutOfSync         = drift exists
Self-healing      = controller auto-corrects drift
Pruning           = deleting resources removed from Git
Source            = where desired state lives (Git, Helm, OCI)
Application       = ArgoCD object: source + destination + sync policy
Kustomization     = Flux object: same concept as ArgoCD Application
HelmRelease       = Flux object: manages a Helm chart release
App of Apps       = ArgoCD pattern: one app manages all apps
ApplicationSet    = ArgoCD: generate many apps from one template
Bootstrap         = initial install of GitOps controller + self-management
```
