# Flux Advanced — Multi-tenancy, Notifications & Operations

## Multi-tenancy with Flux

Flux multi-tenancy lets different teams manage their own namespaces independently without cluster-admin. The platform team owns the management layer; each tenant gets a locked-down namespace.

```
flux-system (platform team)
  ├── GitRepository: platform-repo
  └── Kustomization: tenants  ← bootstraps all team namespaces

team-a (team A's space)
  ├── GitRepository: team-a-repo  ← team A's own repo
  └── Kustomization: team-a-apps  ← reconciled with restricted SA

team-b (team B's space)
  └── ...
```

```yaml
# clusters/production/tenants/team-a.yaml  (committed in platform repo)
apiVersion: v1
kind: Namespace
metadata:
  name: team-a
  labels:
    team: team-a
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: team-a-reconciler
  namespace: team-a
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: team-a-reconciler
  namespace: team-a
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin         # admin of their namespace only
subjects:
  - kind: ServiceAccount
    name: team-a-reconciler
    namespace: team-a
---
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: team-a-repo
  namespace: team-a
spec:
  interval: 1m
  url: https://github.com/myorg/team-a-gitops
  ref:
    branch: main
  secretRef:
    name: team-a-github-token
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: team-a-apps
  namespace: team-a
spec:
  serviceAccountName: team-a-reconciler  # ← impersonate restricted SA
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: team-a-repo
  path: ./production
  prune: true
  targetNamespace: team-a    # ← all resources locked to this namespace
```

## Flux Notifications

```yaml
# Provider — where to send alerts
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Provider
metadata:
  name: slack-provider
  namespace: flux-system
spec:
  type: slack
  channel: "#deployments"
  secretRef:
    name: slack-webhook        # Secret with key "address" = webhook URL

---
# Alert — when to send
apiVersion: notification.toolkit.fluxcd.io/v1beta3
kind: Alert
metadata:
  name: helm-failures
  namespace: flux-system
spec:
  providerRef:
    name: slack-provider
  eventSeverity: error         # info | warning | error
  eventSources:
    - kind: HelmRelease
      namespace: "*"
    - kind: Kustomization
      namespace: "*"
  summary: "Flux sync failure in production"

---
# Receiver — receive webhooks to trigger immediate reconcile
apiVersion: notification.toolkit.fluxcd.io/v1
kind: Receiver
metadata:
  name: github-receiver
  namespace: flux-system
spec:
  type: github
  events: ["ping", "push"]
  secretRef:
    name: webhook-token        # Secret with key "token"
  resources:
    - kind: GitRepository
      name: gitops-repo
```

Get the receiver webhook URL to register with GitHub:
```bash
kubectl get receiver github-receiver -n flux-system \
  -o jsonpath='{.status.webhookPath}'
# → /hook/abc123...
# Full URL: https://flux.example.com/hook/abc123...
```

## Flux with Terraform (tf-controller)

Weave tf-controller lets Flux manage Terraform — full GitOps for infrastructure too.

```yaml
apiVersion: infra.contrib.fluxcd.io/v1alpha2
kind: Terraform
metadata:
  name: vpc
  namespace: flux-system
spec:
  interval: 1h
  approvePlan: auto            # auto-approve or "manual" for human review
  path: ./terraform/vpc
  sourceRef:
    kind: GitRepository
    name: gitops-repo
  vars:
    - name: region
      value: eu-central-1
  writeOutputsToSecret:
    name: vpc-outputs          # Terraform outputs become a K8s Secret
```

## Flux Dependency Management

Control the order in which Kustomizations are applied:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  dependsOn:
    - name: infrastructure     # wait for infra before apps
    - name: crds               # wait for CRDs before using them
  interval: 5m
  path: ./apps/overlays/production
  sourceRef:
    kind: GitRepository
    name: gitops-repo
```

## Flux Health Checks and Wait Conditions

```yaml
spec:
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: myapp
      namespace: production
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: ingress-nginx
      namespace: ingress-nginx
  timeout: 5m                  # fail if health checks don't pass in 5m
```

## Useful Flux Debug Commands

```bash
# See what Flux is doing right now
flux get all -A

# Watch reconciliation live
flux reconcile kustomization apps --watch

# Get detailed status
flux get kustomization apps -n flux-system --with-conditions

# Suspend everything (emergency stop)
flux suspend kustomization --all -n flux-system

# Resume everything
flux resume kustomization --all -n flux-system

# Show recent events (errors first)
flux events -A --for Kustomization

# Show Helm controller logs
flux logs --kind=HelmRelease --level=error

# Export all Flux resources as YAML
flux export source git --all > sources.yaml
flux export kustomization --all > kustomizations.yaml
flux export helmrelease --all -A > helmreleases.yaml

# Validate Flux objects (offline, without a cluster)
flux build kustomization myapp --path ./environments/production
```

## Flux with Terraform (tf-controller)

Weave tf-controller extends Flux to manage Terraform — full GitOps for infrastructure.

```bash
# Install tf-controller
helm repo add tf-controller https://weaveworks.github.io/tf-controller
helm install tf-controller tf-controller/tf-controller \
  --namespace flux-system
```

```yaml
apiVersion: infra.contrib.fluxcd.io/v1alpha2
kind: Terraform
metadata:
  name: vpc
  namespace: flux-system
spec:
  interval: 1h
  approvePlan: auto            # auto-approve or "manual" for human gate
  path: ./terraform/vpc
  sourceRef:
    kind: GitRepository
    name: gitops-repo
  vars:
    - name: region
      value: eu-central-1
  writeOutputsToSecret:
    name: vpc-outputs          # Terraform outputs become a K8s Secret
    labels:
      environment: production
```

## Dependency Management

Control apply order between Kustomizations:

```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  dependsOn:
    - name: infrastructure     # wait for this to be Healthy first
    - name: crds               # CRDs must exist before using them
  interval: 5m
  path: ./apps/overlays/production
  sourceRef:
    kind: GitRepository
    name: gitops-repo
  healthChecks:
    - apiVersion: apps/v1
      kind: Deployment
      name: myapp
      namespace: production
  timeout: 5m
```

## Flux with OCI Artifacts

Store manifests as OCI artifacts in any container registry:

```bash
# Push manifests as OCI artifact from CI
flux push artifact oci://registry.example.com/myapp-manifests:latest \
  --path=./k8s \
  --source=https://github.com/myorg/myapp \
  --revision=main@$(git rev-parse HEAD)

# Tag for production promotion
flux tag artifact oci://registry.example.com/myapp-manifests:latest \
  --tag production
```

```yaml
# Use OCI artifact as source
apiVersion: source.toolkit.fluxcd.io/v1beta2
kind: OCIRepository
metadata:
  name: myapp-manifests
  namespace: flux-system
spec:
  interval: 5m
  url: oci://registry.example.com/myapp-manifests
  ref:
    tag: production
  secretRef:
    name: registry-credentials
  verify:
    provider: cosign            # verify cosign signature
    secretRef:
      name: cosign-public-key
```

## Flux Upgrade

Because Flux manages itself via GitOps, upgrades are Git commits:

```bash
# Check current and latest versions
flux check

# Update Flux components in your Git repo
flux install \
  --version=v2.3.0 \
  --export > clusters/production/flux-system/gotk-components.yaml

# Commit and push — Flux upgrades itself
git add clusters/production/flux-system/gotk-components.yaml
git commit -m "chore: upgrade Flux to v2.3.0"
git push
```

## Useful Flux Debug Commands

```bash
# Full status overview
flux get all -A

# Watch reconciliation live
flux reconcile kustomization apps --watch

# Detailed status with conditions
flux get kustomization apps -n flux-system --with-conditions

# Emergency: suspend all reconciliation
flux suspend kustomization --all -n flux-system
# Resume:
flux resume kustomization --all -n flux-system

# Show recent error events
flux events -A --for Kustomization

# Controller logs
flux logs --kind=HelmRelease --level=error --follow
flux logs --kind=Kustomization --level=error --follow

# Validate kustomization output locally (no cluster needed)
flux build kustomization myapp \
  --path ./environments/production \
  --kustomization-file ./environments/production/kustomization.yaml

# Export all Flux resources
flux export source git --all > sources.yaml
flux export kustomization --all > kustomizations.yaml
flux export helmrelease --all -A > helmreleases.yaml

# Diff — what would a reconcile change?
flux diff kustomization myapp
```

## Common Flux Troubleshooting

```bash
# HelmRelease stuck in "reconciling"
kubectl describe helmrelease myapp -n flux-system
# Check: spec.chart.spec.version — is the version range valid?
# Check: status.conditions — what is the error message?

# Kustomization not picking up changes
flux reconcile source git gitops-repo    # force git fetch
flux reconcile kustomization myapp       # force apply

# Secret decryption failing (SOPS)
kubectl logs -n flux-system \
  -l app=kustomize-controller \
  | grep -i "decrypt\|sops"

# HelmRelease upgrade failing — check values
flux get helmrelease myapp -A
kubectl describe helmrelease myapp -n production

# Image automation not committing
flux get image update flux-system
kubectl logs -n flux-system \
  -l app=image-automation-controller \
  | grep -i "error\|push"
# Common cause: bot account lacks write permission to repo
```
