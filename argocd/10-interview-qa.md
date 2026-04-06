# GitOps Interview Q&A

## Core Concepts

**Q: What is GitOps and how does it differ from traditional CI/CD?**

GitOps is an operational model where Git is the single source of truth for the desired state of infrastructure and applications. A controller running inside the cluster continuously pulls from Git and reconciles the actual state to match — this is the pull model.

Traditional CI/CD is push-based: a pipeline runs `kubectl apply` from outside the cluster, pushing state changes in. The key differences are: in GitOps, cluster credentials never leave the cluster; drift is automatically detected and corrected; rollback is `git revert`; and every change has a Git audit trail with who, what, and why.

---

**Q: Explain the GitOps reconciliation loop.**

The controller (ArgoCD or Flux) continuously: observes — reads desired state from Git; diffs — compares desired vs actual cluster state; acts — applies changes to eliminate any drift; reports — updates status and sends alerts.

This runs on an interval regardless of Git changes. If someone runs `kubectl edit` in production, the controller reverts it on the next loop — intentionally. This is self-healing.

---

**Q: What is drift and why does GitOps prevent it?**

Drift is when the actual cluster state diverges from what's in Git. It can happen via manual `kubectl` edits, partial failed deployments, or external systems modifying resources.

GitOps prevents it because the reconciliation loop continuously compares and corrects. If `selfHeal: true` is set in ArgoCD (or `prune: true` in Flux), any manual change is automatically reverted within the sync interval (typically 1–5 minutes).

---

**Q: What does `prune: true` do in ArgoCD/Flux and what are the risks?**

When `prune: true` is set, resources that exist in the cluster but are no longer present in Git are deleted. Without pruning, deleting a Deployment from Git has no effect — it stays in the cluster forever.

The risk: if you accidentally delete a file from Git, the resources are deleted from the cluster too. Always test in staging first, and consider setting `prune: false` initially when migrating existing workloads to GitOps.

---

## ArgoCD Questions

**Q: What is the App of Apps pattern?**

A "root" Application in ArgoCD points to a directory that contains other Application YAML files. ArgoCD applies those files, creating the child Applications. This means the entire application catalog is itself managed through GitOps — adding an application means committing an Application manifest, not clicking in a UI. The root App is often the only thing manually created in a new cluster.

---

**Q: What are ApplicationSets and when would you use them?**

ApplicationSet is a controller that generates multiple Applications from a single template. You'd use it when you have the same application deploying to many environments, clusters, or namespaces and don't want to repeat Application YAML for each.

Common generators: List (explicit elements), Git Directory (one app per matching directory), Cluster (one app per registered cluster), Matrix (combine two generators — e.g. all apps × all clusters).

---

**Q: How do sync waves work in ArgoCD?**

Sync waves control the order in which resources are applied during a sync. Resources with a lower wave number are applied and must be healthy before the next wave begins.

You annotate resources: `argocd.argoproj.io/sync-wave: "-1"` for CRDs (first), `"0"` for namespaces and secrets, `"1"` for database migrations, `"2"` for the main Deployment. This solves the ordering problem without needing separate Applications.

---

**Q: What is a resource hook in ArgoCD?**

Hooks are resources (usually Jobs) that run at specific sync lifecycle points: `PreSync` (before applying any resources — good for DB migrations), `PostSync` (after everything is healthy — good for smoke tests), `SyncFail` (when sync fails — good for alerting or cleanup).

Example: a PreSync Job runs `python manage.py migrate` against the database before rolling out a new Deployment that requires the migration.

---

## Flux Questions

**Q: What is Flux bootstrapping and why is it special?**

`flux bootstrap` installs the Flux controllers AND commits their own manifests to a Git repo. From that point, Flux manages itself through GitOps — if you want to upgrade Flux, you commit a new version to Git, and Flux upgrades itself. This is self-managing GitOps applied to the GitOps tool itself.

---

**Q: What is the difference between a Flux Kustomization and a Kustomize kustomization.yaml?**

They are completely separate things with the same name — a common source of confusion.

`kustomization.yaml` is Kustomize's file format listing which resources to include and how to patch them — it's processed by the `kustomize` binary.

A Flux `Kustomization` (capital K, `kind: Kustomization`) is a CRD that tells Flux which GitRepository to watch, which path to apply, and with what settings (prune, interval, health checks, etc.). It drives Flux's reconciliation — it uses Kustomize internally to apply the manifests, but they are different objects.

---

**Q: How does Flux multi-tenancy work?**

Each team gets a namespace with a dedicated ServiceAccount. The platform team creates a Flux `Kustomization` for each team's namespace, specifying `serviceAccountName: team-a-reconciler`. Flux impersonates that service account when applying resources, which means team A's reconciler only has permissions in the `team-a` namespace. Team A commits their Application manifests to their own repo — they cannot affect other namespaces.

---

## Secrets & Operations

**Q: How do you handle secrets in GitOps?**

Three main approaches, each with trade-offs:

Sealed Secrets: encrypt with the cluster's public key using `kubeseal`. The encrypted blob is safe to commit — only that cluster can decrypt. Simple to start but couples secrets to a specific cluster's key.

SOPS: encrypt YAML files with Age or KMS before committing. Flux natively decrypts SOPS-encrypted files using a key stored in the cluster. Works across clusters, key rotation is clean.

External Secrets Operator: store secrets in Vault, AWS Secrets Manager, or Azure Key Vault. Commit `ExternalSecret` manifests (which have no secret values). ESO pulls from the store and creates K8s Secrets at runtime. Best for enterprises with existing secret stores.

---

**Q: How would you roll back a deployment in a GitOps world?**

Since Git is the source of truth, rollback is `git revert`. Find the commit that introduced the bad state, revert it, push — the GitOps controller will detect the change and roll the cluster back to the previous state.

For ArgoCD: `argocd app rollback myapp <revision>` also works and writes back to Git if write-back is configured.

For speed: `kubectl rollout undo deployment/myapp` is faster but creates drift — you should follow up with a git revert to keep Git as the source of truth.

---

**Q: How do you handle a situation where someone needs to make an emergency manual change in production?**

1. Make the urgent change with `kubectl` — it works, but creates drift
2. The GitOps controller will revert it if `selfHeal: true` — so either suspend the Application/Kustomization first (`argocd app suspend` / `flux suspend kustomization`) or make the change fast and immediately follow up
3. Immediately commit the same change to Git to eliminate drift
4. Resume the Application/Kustomization
5. Post-incident: add a guard so this scenario needs less manual intervention

The key discipline: every manual change must be followed by a Git commit, or the controller will revert it.

---

**Q: Describe your GitOps promotion strategy between environments.**

I use Kustomize overlays — one base set of manifests, per-environment overlays that patch image tags, replica counts, and resource limits.

For dev: image automation commits new image tags directly to the dev overlay on every build.
For staging: either image automation also updates staging, or a promotion script copies the tag from dev to staging via a Git commit after dev tests pass.
For production: a Pull Request that updates the production overlay. Requires review + merge. The PR serves as the audit trail and approval gate — who approved, what was the image tag, when was it deployed.

No CI/CD pipeline ever has production cluster credentials. The merge to main is the only trigger needed.

---

## Scenario Questions

**Q: You join a company running Kubernetes with no GitOps. How do you introduce it without breaking production?**

Start with observability, not control. First install ArgoCD or Flux in read-only mode — no auto-sync, no self-healing. Point it at a Git repo that mirrors what's already deployed. This gives you visibility into drift without risk.

Phase 1: capture current state. `helm get values` and `kubectl get -o yaml` on everything, commit to Git. Now you have a baseline.

Phase 2: enable auto-sync on a non-critical namespace — internal tools, staging. Get the team comfortable with the pull model.

Phase 3: migrate production namespaces one-by-one. Enable auto-sync but leave `selfHeal: false` initially. Only enable self-healing after the team trusts the system.

Phase 4: migrate secrets last — introduce Sealed Secrets or ESO, stop manually creating secrets.

---

**Q: A critical hotfix is needed in production right now. The GitOps pipeline normally takes 10 minutes. How do you handle it?**

Two valid approaches depending on urgency:

If seconds matter: `kubectl apply` the fix directly — it works immediately. Then immediately commit the same change to Git. When the GitOps controller next reconciles, it will see Git and cluster already match — no disruption.

If minutes are acceptable: push directly to the production branch with an expedited PR review (or bypass policy with a break-glass procedure). Trigger an immediate reconcile via `argocd app sync myapp` or `flux reconcile kustomization apps`. This takes 1–2 minutes instead of 10.

Either way: document the incident, and if you used `kubectl` directly, ensure the Git commit lands before the next reconciliation cycle or the change gets reverted.

---

**Q: How do you structure a GitOps repo when you have 10 microservices across 3 environments?**

I'd use a mono-repo with Kustomize overlays:

```
gitops-repo/
├── apps/
│   ├── service-a/
│   │   ├── base/            # shared deployment, service, hpa
│   │   └── overlays/
│   │       ├── dev/         # patch: replicas=1, small limits
│   │       ├── staging/     # patch: replicas=2
│   │       └── production/  # patch: replicas=5, large limits
│   ├── service-b/
│   └── ...  (repeat for 10 services)
└── clusters/
    ├── dev/      → Kustomization: path=apps/*/overlays/dev
    ├── staging/  → Kustomization: path=apps/*/overlays/staging
    └── prod/     → Kustomization: path=apps/*/overlays/production
```

Each environment's Kustomization in the `clusters/` directory points to its overlay path and handles all 10 services. Image automation updates each service's overlay independently when a new image is built. Promotion means a PR changing the image tag in the next environment's overlay.

---

**Q: What is the difference between ArgoCD sync status and health status?**

They are two independent dimensions:

Sync status: does the cluster match Git? Values: `Synced` (matches), `OutOfSync` (differs), `Unknown` (can't tell).

Health status: are the resources functioning correctly? Values: `Healthy` (all resources Ready), `Progressing` (rolling update in progress), `Degraded` (some pods crashing), `Suspended` (paused), `Missing` (resource doesn't exist).

A combination you often see:
- `Synced / Progressing` — Git was applied successfully, but pods are still rolling out
- `Synced / Degraded` — Git matches cluster, but the app is crashing (wrong image, bad config)
- `OutOfSync / Healthy` — app is running fine but someone manually changed something

You want `Synced / Healthy`. `Synced / Degraded` is the worst — it means the broken state IS what Git says should exist, so the controller won't help you. You need to fix Git.

---

**Q: How do you test changes to GitOps manifests before committing?**

Several layers:

Local validation: `kustomize build environments/production/ | kubeval` — validates YAML structure without a cluster. `flux build kustomization myapp --path ./environments/production` — simulates Flux's processing locally.

PR-based preview: on every PR, run a GitHub Action that does `kustomize build` + `kubectl diff` against a dev cluster. Shows exactly what would change before merge.

Staging environment: ArgoCD/Flux syncs staging from the same repo but a different overlay. Merge to a staging branch first, verify, then PR to main.

Policy checks in CI: run `checkov -d .` and `conftest test ./environments/` on every PR to catch security misconfigurations before they reach a cluster.

---

**Q: Walk me through what happens end-to-end when a developer merges a PR that bumps the image tag.**

1. Developer merges PR — `environments/production/kustomization.yaml` now has `newTag: v1.3.0`
2. GitHub/GitLab sends a webhook to the GitOps controller (Flux Receiver / ArgoCD webhook)
3. Controller immediately fetches the latest commit from the repo (otherwise would wait for polling interval)
4. Controller computes diff: cluster still has `v1.2.9`, Git says `v1.3.0` → OutOfSync
5. Controller applies the Kustomize output to the cluster: `kubectl apply` of the Deployment with the new image tag
6. Kubernetes starts a rolling update: new pods with `v1.3.0` start alongside old pods with `v1.2.9`
7. Readiness probes pass → new pods become Ready → old pods are terminated
8. Controller detects all Deployment replicas are Ready and matching desired state
9. Status updates to: `Synced / Healthy`
10. Notification fires to Slack: "myapp v1.3.0 deployed to production ✓"

Total time: 2–5 minutes depending on image pull time and rollout speed.
