# Image Automation in GitOps

## The Problem

GitOps requires Git to be the source of truth, but CI pushes new images to a registry. Something must update the image tag in Git after each build. Image automation tools do this automatically — closing the loop between CI and GitOps.

```
CI builds myapp:v1.2.4 → registry
         ↓
Image automation detects v1.2.4 in registry
         ↓
Commits "newTag: v1.2.4" to Git
         ↓
GitOps controller detects Git change → deploys
```

## Flux Image Automation — 4-Step Setup

Enable at bootstrap:
```bash
flux bootstrap github ... \
  --components-extra=image-reflector-controller,image-automation-controller
```

### Step 1: ImageRepository — Scan the Registry

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImageRepository
metadata:
  name: myapp
  namespace: flux-system
spec:
  image: registry.example.com/myapp
  interval: 1m
  secretRef:
    name: registry-credentials
```

### Step 2: ImagePolicy — Which Tag to Use

```yaml
# Semver — latest stable version in a range
apiVersion: image.toolkit.fluxcd.io/v1beta2
kind: ImagePolicy
metadata:
  name: myapp
  namespace: flux-system
spec:
  imageRepositoryRef:
    name: myapp
  policy:
    semver:
      range: ">=1.0.0 <2.0.0"

---
# Non-semver — filter by pattern, sort by extracted group
spec:
  policy:
    alphabetical:
      order: asc
  filterTags:
    pattern: "^main-[a-f0-9]+-(?P<ts>[0-9]+)$"
    extract: "$ts"             # sort by timestamp
```

### Step 3: ImageUpdateAutomation — Write to Git

```yaml
apiVersion: image.toolkit.fluxcd.io/v1beta1
kind: ImageUpdateAutomation
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: gitops-repo
  git:
    checkout:
      ref:
        branch: main
    commit:
      author:
        email: fluxbot@example.com
        name: Flux Image Updater
      messageTemplate: |
        chore: update {{range .Updated.Images}}{{.Name}} to {{.Identifier}}{{end}}
    push:
      branch: main
  update:
    path: ./environments
    strategy: Setters
```

### Step 4: Mark Fields in Manifests

```yaml
# environments/production/kustomization.yaml
images:
  - name: myapp
    newName: registry.example.com/myapp
    newTag: v1.2.3 # {"$imagepolicy": "flux-system:myapp:tag"}
#                    ↑ automation updates the value above this comment
```

```bash
# Check status
flux get image repository myapp     # what tags exist?
flux get image policy myapp         # which tag was selected?
flux get image update flux-system   # has it committed to Git?

# Force check
flux reconcile image repository myapp
flux reconcile image update flux-system
```

## ArgoCD Image Updater

```bash
kubectl apply -n argocd -f \
  https://raw.githubusercontent.com/argoproj-labs/argocd-image-updater/stable/manifests/install.yaml
```

```yaml
# Annotate your Application
metadata:
  annotations:
    argocd-image-updater.argoproj.io/image-list: myapp=registry.example.com/myapp
    argocd-image-updater.argoproj.io/myapp.update-strategy: semver
    argocd-image-updater.argoproj.io/myapp.allow-tags: regexp:^v[0-9]+\.[0-9]+\.[0-9]+$
    argocd-image-updater.argoproj.io/write-back-method: git
    argocd-image-updater.argoproj.io/write-back-target: kustomization
    argocd-image-updater.argoproj.io/git-branch: main
```

## Update Strategy Comparison

| Strategy | Use case | Example tags |
|----------|---------|-------------|
| `semver` | Stable versioned releases | v1.2.3, v2.0.0 |
| `alphabetical` | Non-semver, sort by name/timestamp | main-20240115 |
| `digest` | Pinned exact SHA | sha256:abc... |
| `latest` | Dev only — always latest | latest |

## Security Notes

- Use a dedicated Git bot account with minimal write permissions (gitops repo only)
- Prefer pushing to a PR branch (not directly to main) for production — forces review
- Tighten tag filter regex — don't match `latest` or dev tags in production policies
- Consider signing images with cosign and verifying before automation trusts new tags
