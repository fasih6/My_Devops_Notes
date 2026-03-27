# 📦 OCI Registries

Storing and distributing Helm charts using container registries — the modern alternative to HTTP chart repos.

---

## 📚 Table of Contents

- [1. Why OCI for Helm Charts?](#1-why-oci-for-helm-charts)
- [2. OCI vs Traditional HTTP Repos](#2-oci-vs-traditional-http-repos)
- [3. Pushing Charts to OCI Registries](#3-pushing-charts-to-oci-registries)
- [4. Pulling & Installing from OCI](#4-pulling--installing-from-oci)
- [5. Popular OCI Registries](#5-popular-oci-registries)
- [6. OCI in CI/CD](#6-oci-in-cicd)
- [7. Chart Signing & Verification](#7-chart-signing--verification)
- [Cheatsheet](#cheatsheet)

---

## 1. Why OCI for Helm Charts?

OCI (Open Container Initiative) registries are the same infrastructure used for Docker images — but they can store any artifact, including Helm charts.

**Benefits over traditional HTTP repos:**
- **Same infrastructure** — one registry for images AND charts
- **Access control** — reuse existing registry IAM/RBAC
- **Immutability** — tags can be made immutable (critical for reproducibility)
- **Provenance** — built-in signing and verification
- **No index.yaml** — no separate repo index to maintain
- **Supported by all major registries** — ECR, GCR, ACR, GHCR, Harbor

---

## 2. OCI vs Traditional HTTP Repos

| Feature | HTTP Repo | OCI Registry |
|---------|-----------|-------------|
| **Storage** | Web server + index.yaml | Container registry |
| **Discovery** | `helm search repo` | Registry UI or API |
| **Authentication** | HTTP basic auth | Registry login (docker/helm) |
| **Versioning** | Chart package versions | Image tags |
| **Immutability** | Optional | Can be enforced |
| **Signing** | Manual | Cosign, Notary v2 |
| **Self-hosted** | Nginx, GitHub Pages | Harbor, registry:2 |
| **Setup complexity** | Low | Low (reuses existing infra) |

---

## 3. Pushing Charts to OCI Registries

### Login to the registry

```bash
# GitHub Container Registry (GHCR)
echo $GITHUB_TOKEN | helm registry login ghcr.io \
  --username $GITHUB_USER \
  --password-stdin

# AWS ECR
aws ecr get-login-password --region eu-central-1 | \
  helm registry login \
  --username AWS \
  --password-stdin \
  123456789.dkr.ecr.eu-central-1.amazonaws.com

# GCP Artifact Registry
gcloud auth print-access-token | \
  helm registry login europe-west1-docker.pkg.dev \
  --username oauth2accesstoken \
  --password-stdin

# Docker Hub
helm registry login registry-1.docker.io \
  --username myuser \
  --password mypassword

# Self-hosted Harbor
helm registry login harbor.example.com \
  --username admin \
  --password password
```

### Package and push

```bash
# Package the chart
helm package ./my-chart
# Creates: my-chart-1.0.0.tgz

# Push to OCI registry
helm push my-chart-1.0.0.tgz oci://ghcr.io/myorg/charts
# Output: Pushed: ghcr.io/myorg/charts/my-chart:1.0.0
#         Digest: sha256:abc123...

# Push with explicit tag (same as chart version)
helm push my-chart-1.0.0.tgz oci://registry.example.com/helm-charts

# Push to AWS ECR
helm push my-chart-1.0.0.tgz \
  oci://123456789.dkr.ecr.eu-central-1.amazonaws.com/helm-charts

# ECR requires the repository to exist first
aws ecr create-repository --repository-name helm-charts/my-chart --region eu-central-1
```

### Automate package + push

```bash
#!/bin/bash
set -euo pipefail

REGISTRY="ghcr.io/myorg/charts"
CHART_DIR="./my-chart"

# Get version from Chart.yaml
VERSION=$(helm show chart "$CHART_DIR" | grep ^version | awk '{print $2}')
CHART_NAME=$(helm show chart "$CHART_DIR" | grep ^name | awk '{print $2}')

# Package
helm package "$CHART_DIR" --destination /tmp/charts/

# Push
helm push "/tmp/charts/${CHART_NAME}-${VERSION}.tgz" "oci://${REGISTRY}"

echo "Pushed ${CHART_NAME}:${VERSION} to ${REGISTRY}"
```

---

## 4. Pulling & Installing from OCI

### Install directly from OCI

```bash
# Install from OCI (no need to add a repo first)
helm install my-app oci://ghcr.io/myorg/charts/my-chart \
  --version 1.0.0

# Install with values
helm install my-app oci://ghcr.io/myorg/charts/my-chart \
  --version 1.0.0 \
  --values values-production.yaml

# Upgrade
helm upgrade my-app oci://ghcr.io/myorg/charts/my-chart \
  --version 1.2.0

# upgrade --install (idempotent)
helm upgrade --install my-app oci://ghcr.io/myorg/charts/my-chart \
  --version 1.0.0 \
  --namespace production \
  --create-namespace

# From AWS ECR
helm install my-app \
  oci://123456789.dkr.ecr.eu-central-1.amazonaws.com/helm-charts/my-chart \
  --version 1.0.0
```

### Pull chart locally (for inspection)

```bash
# Pull as tarball
helm pull oci://ghcr.io/myorg/charts/my-chart --version 1.0.0

# Pull and extract
helm pull oci://ghcr.io/myorg/charts/my-chart \
  --version 1.0.0 \
  --untar \
  --untardir ./charts/

# Show chart info without downloading
helm show chart oci://ghcr.io/myorg/charts/my-chart --version 1.0.0
helm show values oci://ghcr.io/myorg/charts/my-chart --version 1.0.0
```

### OCI in Chart.yaml dependencies

```yaml
# Chart.yaml
dependencies:
  - name: my-internal-chart
    version: "1.2.3"
    repository: "oci://ghcr.io/myorg/charts"

  - name: common-lib
    version: "2.0.0"
    repository: "oci://registry.example.com/helm-libs"
```

```bash
helm dependency update ./my-chart
```

---

## 5. Popular OCI Registries

### GitHub Container Registry (GHCR)

```bash
# Login
echo $GITHUB_TOKEN | helm registry login ghcr.io -u $GITHUB_USER --password-stdin

# Push
helm push my-chart-1.0.0.tgz oci://ghcr.io/myorg/charts

# Install
helm install my-app oci://ghcr.io/myorg/charts/my-chart --version 1.0.0

# Make package public (in GitHub Settings → Packages → Change visibility)
# Or set in package: Organization → Packages → Set visibility
```

### AWS ECR

```bash
# Create ECR repository (one per chart)
aws ecr create-repository \
  --repository-name helm-charts/my-chart \
  --region eu-central-1

# Login
aws ecr get-login-password --region eu-central-1 | \
  helm registry login \
  --username AWS \
  --password-stdin \
  123456789.dkr.ecr.eu-central-1.amazonaws.com

# Push
helm push my-chart-1.0.0.tgz \
  oci://123456789.dkr.ecr.eu-central-1.amazonaws.com/helm-charts

# Install
helm install my-app \
  oci://123456789.dkr.ecr.eu-central-1.amazonaws.com/helm-charts/my-chart \
  --version 1.0.0
```

### GCP Artifact Registry

```bash
# Create repository
gcloud artifacts repositories create helm-charts \
  --repository-format=docker \
  --location=europe-west1

# Login
gcloud auth configure-docker europe-west1-docker.pkg.dev
# OR for helm:
gcloud auth print-access-token | \
  helm registry login europe-west1-docker.pkg.dev \
  --username oauth2accesstoken \
  --password-stdin

# Push
helm push my-chart-1.0.0.tgz \
  oci://europe-west1-docker.pkg.dev/my-project/helm-charts

# Install
helm install my-app \
  oci://europe-west1-docker.pkg.dev/my-project/helm-charts/my-chart \
  --version 1.0.0
```

### Harbor (self-hosted)

```bash
# Login
helm registry login harbor.example.com \
  --username admin \
  --password password

# Create project in Harbor UI first, then push:
helm push my-chart-1.0.0.tgz oci://harbor.example.com/my-project

# Install
helm install my-app oci://harbor.example.com/my-project/my-chart \
  --version 1.0.0
```

---

## 6. OCI in CI/CD

### GitHub Actions — push chart on release

```yaml
# .github/workflows/release-chart-oci.yml
name: Release Chart to OCI

on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write    # needed to push to GHCR

    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v3
        with:
          version: v3.13.0

      - name: Login to GHCR
        run: |
          echo "${{ secrets.GITHUB_TOKEN }}" | \
            helm registry login ghcr.io \
            --username ${{ github.actor }} \
            --password-stdin

      - name: Extract version from tag
        id: version
        run: echo "VERSION=${GITHUB_REF_NAME#v}" >> $GITHUB_OUTPUT

      - name: Update Chart version
        run: |
          sed -i "s/^version:.*/version: ${{ steps.version.outputs.VERSION }}/" helm/my-chart/Chart.yaml
          sed -i "s/^appVersion:.*/appVersion: \"${{ steps.version.outputs.VERSION }}\"/" helm/my-chart/Chart.yaml

      - name: Package and push chart
        run: |
          helm dependency update helm/my-chart
          helm package helm/my-chart --destination /tmp/charts/
          helm push /tmp/charts/my-chart-${{ steps.version.outputs.VERSION }}.tgz \
            oci://ghcr.io/${{ github.repository_owner }}/charts

      - name: Verify push
        run: |
          helm show chart \
            oci://ghcr.io/${{ github.repository_owner }}/charts/my-chart \
            --version ${{ steps.version.outputs.VERSION }}
```

---

## 7. Chart Signing & Verification

Sign charts to ensure integrity and authenticity.

### Cosign (modern approach)

```bash
# Install cosign
brew install cosign

# Sign the OCI artifact after pushing
cosign sign oci://ghcr.io/myorg/charts/my-chart:1.0.0

# Verify signature
cosign verify oci://ghcr.io/myorg/charts/my-chart:1.0.0 \
  --certificate-identity https://github.com/myorg/my-repo/.github/workflows/release.yml@refs/tags/v1.0.0 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

### Helm provenance (traditional approach)

```bash
# Sign during package (requires GPG key)
helm package ./my-chart --sign --key "My GPG Key" --keyring ~/.gnupg/secring.gpg

# Verify during install
helm install my-app ./my-chart-1.0.0.tgz \
  --verify \
  --keyring ~/.gnupg/pubring.gpg
```

---

## Cheatsheet

```bash
# Registry login
echo $TOKEN | helm registry login ghcr.io -u $USER --password-stdin
aws ecr get-login-password | helm registry login --username AWS --password-stdin $ECR_URL

# Package and push
helm package ./my-chart                                    # creates .tgz
helm push my-chart-1.0.0.tgz oci://ghcr.io/myorg/charts  # push

# Install from OCI
helm install my-app oci://ghcr.io/myorg/charts/my-chart --version 1.0.0
helm upgrade --install my-app oci://ghcr.io/myorg/charts/my-chart --version 1.0.0

# Inspect without installing
helm show chart oci://ghcr.io/myorg/charts/my-chart --version 1.0.0
helm show values oci://ghcr.io/myorg/charts/my-chart --version 1.0.0

# Pull locally
helm pull oci://ghcr.io/myorg/charts/my-chart --version 1.0.0 --untar

# Logout
helm registry logout ghcr.io
```

---

*Next: [Helmfile →](./09-helmfile.md)*
