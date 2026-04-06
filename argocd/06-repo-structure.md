# GitOps Repository Structure

## Mono-repo vs Poly-repo

### Mono-repo (one repo for everything)
```
gitops-repo/
├── apps/                     # application manifests
│   ├── myapp/
│   ├── api/
│   └── worker/
├── platform/                 # shared platform components
│   ├── ingress-nginx/
│   └── cert-manager/
├── environments/             # per-environment overlays
│   ├── dev/
│   ├── staging/
│   └── production/
└── clusters/                 # Flux/ArgoCD bootstrap per cluster
    ├── dev/
    ├── staging/
    └── production/
```

Pros: one PR changes everything, easy cross-service visibility
Cons: all teams in one repo, access control harder, noisier history

### Poly-repo (separate repos per concern)
```
platform-gitops/              # platform team owns clusters + infra
team-a-gitops/                # team A owns their apps + overlays
team-b-gitops/                # team B owns their apps + overlays
```

Pros: clean ownership, fine-grained access, quieter histories
Cons: harder to see cross-repo dependencies

**German enterprise preference:** Poly-repo wins — clear ownership boundaries matter for compliance.

## Full Kustomize Overlay Structure

```
gitops-repo/
└── apps/
    └── myapp/
        ├── base/
        │   ├── kustomization.yaml
        │   ├── deployment.yaml
        │   ├── service.yaml
        │   ├── hpa.yaml
        │   └── ingress.yaml
        └── overlays/
            ├── dev/
            │   ├── kustomization.yaml
            │   └── patch-replicas.yaml   # replicas: 1
            ├── staging/
            │   ├── kustomization.yaml
            │   └── patch-resources.yaml
            └── production/
                ├── kustomization.yaml
                ├── patch-replicas.yaml   # replicas: 5
                └── patch-resources.yaml  # bigger limits
```

```yaml
# apps/myapp/base/deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 1
  selector:
    matchLabels:
      app: myapp
  template:
    spec:
      containers:
        - name: myapp
          image: myapp   # tag managed by image automation
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi

# apps/myapp/overlays/production/kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
bases:
  - ../../base
patches:
  - path: patch-replicas.yaml
images:
  - name: myapp
    newName: registry.example.com/myapp
    newTag: v1.2.3 # {"$imagepolicy": "flux-system:myapp:tag"}
commonLabels:
  environment: production

# apps/myapp/overlays/production/patch-replicas.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  replicas: 5
```

## Environment Promotion Flow

```
[CI] Build image → push myapp:v1.2.3
        ↓
[Image automation] Update dev/kustomization.yaml → tag: v1.2.3
        ↓ (auto-sync)
[Dev cluster] Deploys v1.2.3
        ↓ (tests pass, promotion PR created)
[PR] Update staging/kustomization.yaml → tag: v1.2.3
        ↓ (PR merged, auto-sync)
[Staging cluster] Deploys v1.2.3
        ↓ (manual approval PR)
[PR] Update production/kustomization.yaml → tag: v1.2.3
        ↓ (PR reviewed and merged)
[Production cluster] Deploys v1.2.3
```

Promotion script:
```bash
#!/usr/bin/env bash
# promote.sh — promote image tag between environments
set -euo pipefail
SOURCE_ENV="${1?Usage: $0 <from-env> <to-env> <service>}"
TARGET_ENV="${2?}"
SERVICE="${3?}"
TAG="$(grep newTag "environments/${SOURCE_ENV}/${SERVICE}/kustomization.yaml" \
       | awk '{print $2}')"

echo "Promoting ${SERVICE}:${TAG} from ${SOURCE_ENV} → ${TARGET_ENV}"

cd "environments/${TARGET_ENV}/${SERVICE}"
kustomize edit set image "${SERVICE}=registry.example.com/${SERVICE}:${TAG}"
cd -

git add "environments/${TARGET_ENV}/${SERVICE}/kustomization.yaml"
git commit -m "chore: promote ${SERVICE} ${TAG} to ${TARGET_ENV}"
git push origin main
echo "Done — ${TARGET_ENV} will sync shortly"
```

## Cluster Bootstrap Structure (Flux)

```
clusters/
└── production/
    └── flux-system/
        ├── gotk-components.yaml     # Flux controllers (auto-generated)
        ├── gotk-sync.yaml           # Flux self-managing GitRepository + Kustomization
        ├── kustomization.yaml
        └── apps.yaml                # Kustomization pointing to apps/
```

```yaml
# clusters/production/flux-system/apps.yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: flux-system
  path: ./apps/overlays/production
  prune: true
  dependsOn:
    - name: infrastructure      # apply infra before apps
```
