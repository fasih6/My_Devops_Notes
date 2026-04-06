# GitOps — Index & Core Concepts

## What Is GitOps?

GitOps is an operational framework where **Git is the single source of truth** for the desired state of your infrastructure and applications. Instead of running `kubectl apply` or `helm upgrade` manually, you commit a change to Git — and a controller running inside the cluster detects the drift and reconciles the actual state to match.

The core insight: if your deployment state lives in Git, you get version history, audit trails, code review, and rollback for free.

## Push vs Pull — The Key Mental Model

```
PUSH model (traditional CI/CD):
  Developer → CI pipeline → kubectl apply → Cluster
  Problem: CI pipeline needs cluster credentials, no drift detection

PULL model (GitOps):
  Developer → Git commit → [GitOps controller watches repo]
                               ↓
                           Cluster (controller pulls and reconciles)
  Cluster credentials stay INSIDE the cluster — never in CI/CD
```

The pull model is fundamentally more secure: credentials never leave the cluster perimeter.

## The Four GitOps Principles (OpenGitOps)

| Principle | What it means |
|-----------|--------------|
| **Declarative** | System state described as desired state, not imperative commands |
| **Versioned and immutable** | State stored in Git — canonical, versioned, auditable |
| **Pulled automatically** | Software agents pull desired state from source continuously |
| **Continuously reconciled** | Agents detect drift and correct it automatically |

## The Reconciliation Loop

This is the heartbeat of every GitOps system:

```
┌─────────────────────────────────────────┐
│          GitOps Controller              │
│                                         │
│  1. OBSERVE   → What does Git say?      │
│  2. DIFF      → What is the cluster?   │
│  3. ACT       → Apply the difference   │
│  4. REPORT    → Update status/alerts   │
│                                         │
│  Repeats every N seconds (sync interval)│
└─────────────────────────────────────────┘
```

When Git and the cluster match → **synced**. When they differ → **out of sync** (drift). The controller's job is to eliminate drift.

## ArgoCD vs Flux — Quick Comparison

| Feature | ArgoCD | Flux v2 |
|---------|--------|---------|
| UI | Rich web UI built-in | CLI-first, optional UI (Weave GitOps) |
| Architecture | Server + repo-server + application-controller | Modular controllers per concern |
| Config language | YAML Applications, ApplicationSets | YAML CRDs (GitRepository, Kustomization, HelmRelease) |
| Helm support | Native, built-in | Via HelmRelease CRD |
| Multi-tenancy | Projects + RBAC | Tenants via Kustomize overlays |
| Image automation | ArgoCD Image Updater (separate) | Built-in (ImageUpdateAutomation) |
| Best for | Teams wanting a UI, centralised control | Teams wanting pure K8s-native, GitOps-all-the-way |
| CNCF status | Graduated | Graduated |

Both are excellent. The choice is usually about team preference: UI vs CLI, centralised vs distributed.

## Folder Contents

| File | Topic |
|------|-------|
| `01-core-concepts.md` | This file — principles, reconciliation, push vs pull |
| `02-argocd-core.md` | Install, Applications, sync policies, RBAC |
| `03-argocd-advanced.md` | App of Apps, ApplicationSets, hooks, notifications |
| `04-flux-core.md` | Flux v2 bootstrap, GitRepository, Kustomization, HelmRelease |
| `05-flux-advanced.md` | Multi-tenancy, notifications, Flux with Terraform |
| `06-repo-structure.md` | Mono vs poly repos, environment layouts, promotion patterns |
| `07-image-automation.md` | Auto-updating image tags in Git on new builds |
| `08-secrets-gitops.md` | Sealed Secrets, SOPS, ESO — secrets that can live in Git |
| `09-multi-cluster.md` | Managing many clusters from one control plane |
| `10-interview-qa.md` | GitOps interview questions and answers |

## Key Terms Quick Reference

| Term | Definition |
|------|-----------|
| Desired state | What Git says the cluster should look like |
| Actual state | What the cluster currently looks like |
| Drift | Difference between desired and actual state |
| Reconciliation | The act of making actual match desired |
| Sync | ArgoCD term for reconciliation |
| Source | Where the desired state lives (Git repo, Helm chart, OCI) |
| Application | ArgoCD object that links a source to a destination cluster/namespace |
| Kustomization | Flux object that applies manifests from a GitRepository |
| HelmRelease | Flux object that manages a Helm chart release |
| App of Apps | ArgoCD pattern: one Application manages many other Applications |
| Bootstrap | The initial setup that installs a GitOps controller and points it at itself |
