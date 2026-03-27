# 📦 Registry & Image Management

Push, pull, tag, and manage Docker images across ECR, GHCR, GCR, Docker Hub, and private registries.

---

## 📚 Table of Contents

- [1. Registry Overview](#1-registry-overview)
- [2. Docker Hub](#2-docker-hub)
- [3. GitHub Container Registry (GHCR)](#3-github-container-registry-ghcr)
- [4. AWS ECR](#4-aws-ecr)
- [5. GCP Artifact Registry](#5-gcp-artifact-registry)
- [6. Private Registry (Harbor / registry:2)](#6-private-registry-harbor--registry2)
- [7. Image Tagging Strategies](#7-image-tagging-strategies)
- [8. Multi-Platform Images](#8-multi-platform-images)
- [9. Image Signing & Verification](#9-image-signing--verification)
- [10. Image Lifecycle & Cleanup](#10-image-lifecycle--cleanup)
- [Cheatsheet](#cheatsheet)

---

## 1. Registry Overview

A registry stores and distributes Docker images. Every `docker pull` fetches from a registry.

```
Image name breakdown:
ghcr.io / myorg / my-app : v1.2.3
   │         │       │        │
registry  namespace  repo    tag

# Default registry is Docker Hub:
nginx == docker.io/library/nginx:latest
myuser/myapp == docker.io/myuser/myapp:latest
```

### Registry comparison

| Registry | Free tier | Auth | Best for |
|----------|-----------|------|---------|
| **Docker Hub** | 1 private repo | Docker login | Public images, OSS |
| **GHCR** | Free for public, included with GitHub | GitHub token | GitHub users |
| **ECR** | 500MB/month free | AWS IAM | AWS workloads |
| **GCR/GAR** | Limited free | GCP IAM | GCP workloads |
| **Harbor** | Self-hosted | LDAP/OIDC | Enterprise self-hosted |
| **registry:2** | Self-hosted | Basic auth | Simple private registry |

---

## 2. Docker Hub

```bash
# Login
docker login
docker login -u myuser -p mypassword

# Pull
docker pull nginx:1.24
docker pull myuser/my-app:v1.0.0

# Tag and push
docker build -t my-app:v1.0.0 .
docker tag my-app:v1.0.0 myuser/my-app:v1.0.0
docker tag my-app:v1.0.0 myuser/my-app:latest
docker push myuser/my-app:v1.0.0
docker push myuser/my-app:latest

# Rate limits (unauthenticated: 100 pulls/6h, authenticated: 200/6h)
# Use authenticated pulls in CI to avoid limits
echo $DOCKER_PASSWORD | docker login -u $DOCKER_USERNAME --password-stdin
```

---

## 3. GitHub Container Registry (GHCR)

```bash
# Login with GitHub Personal Access Token (PAT)
echo $GITHUB_TOKEN | docker login ghcr.io -u $GITHUB_USER --password-stdin

# Pull
docker pull ghcr.io/myorg/my-app:v1.0.0

# Build and push
docker build -t ghcr.io/myorg/my-app:v1.0.0 .
docker push ghcr.io/myorg/my-app:v1.0.0
```

### GitHub Actions — push to GHCR

```yaml
jobs:
  push:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write       # required for GHCR

    steps:
      - uses: actions/checkout@v4

      - name: Login to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}   # no PAT needed

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ghcr.io/${{ github.repository }}:${{ github.sha }}
```

---

## 4. AWS ECR

```bash
# Authenticate (token valid for 12 hours)
aws ecr get-login-password --region eu-central-1 | \
  docker login \
  --username AWS \
  --password-stdin \
  123456789.dkr.ecr.eu-central-1.amazonaws.com

# Create repository (one per image)
aws ecr create-repository \
  --repository-name my-app \
  --region eu-central-1 \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256

# Build and push
ECR_URL=123456789.dkr.ecr.eu-central-1.amazonaws.com
docker build -t my-app:v1.0.0 .
docker tag my-app:v1.0.0 $ECR_URL/my-app:v1.0.0
docker push $ECR_URL/my-app:v1.0.0

# Pull
docker pull $ECR_URL/my-app:v1.0.0
```

### ECR lifecycle policy — auto-clean old images

```json
{
  "rules": [
    {
      "rulePriority": 1,
      "description": "Keep last 10 tagged images",
      "selection": {
        "tagStatus": "tagged",
        "tagPrefixList": ["v"],
        "countType": "imageCountMoreThan",
        "countNumber": 10
      },
      "action": { "type": "expire" }
    },
    {
      "rulePriority": 2,
      "description": "Delete untagged images older than 1 day",
      "selection": {
        "tagStatus": "untagged",
        "countType": "sinceImagePushed",
        "countUnit": "days",
        "countNumber": 1
      },
      "action": { "type": "expire" }
    }
  ]
}
```

```bash
aws ecr put-lifecycle-policy \
  --repository-name my-app \
  --lifecycle-policy-text file://lifecycle-policy.json
```

### GitHub Actions — push to ECR

```yaml
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789:role/github-actions
    aws-region: eu-central-1

- name: Login to ECR
  id: login-ecr
  uses: aws-actions/amazon-ecr-login@v2

- name: Build and push to ECR
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: ${{ steps.login-ecr.outputs.registry }}/my-app:${{ github.sha }}
```

---

## 5. GCP Artifact Registry

```bash
# Configure authentication
gcloud auth configure-docker europe-west1-docker.pkg.dev

# Create repository
gcloud artifacts repositories create docker-repo \
  --repository-format=docker \
  --location=europe-west1 \
  --description="Docker images"

# Build and push
GAR_URL=europe-west1-docker.pkg.dev/my-project/docker-repo
docker build -t $GAR_URL/my-app:v1.0.0 .
docker push $GAR_URL/my-app:v1.0.0

# Pull
docker pull $GAR_URL/my-app:v1.0.0
```

---

## 6. Private Registry (Harbor / registry:2)

### Run registry:2 (simple, no UI)

```bash
# Start a local registry
docker run -d \
  -p 5000:5000 \
  --name registry \
  --restart always \
  -v registry-data:/var/lib/registry \
  registry:2

# Push to local registry
docker tag my-app:latest localhost:5000/my-app:latest
docker push localhost:5000/my-app:latest

# Pull from local registry
docker pull localhost:5000/my-app:latest

# With authentication
docker run -d \
  -p 5000:5000 \
  -v registry-data:/var/lib/registry \
  -v $(pwd)/auth:/auth \
  -e REGISTRY_AUTH=htpasswd \
  -e REGISTRY_AUTH_HTPASSWD_REALM="Registry" \
  -e REGISTRY_AUTH_HTPASSWD_PATH=/auth/htpasswd \
  registry:2

# Generate password file
htpasswd -Bc auth/htpasswd myuser
```

### Harbor (production-grade, with UI)

```bash
# Install Harbor with docker compose
curl -L https://github.com/goharbor/harbor/releases/latest/download/harbor-online-installer.tgz \
  | tar xz

cd harbor
# Edit harbor.yml (hostname, admin password, TLS certs)
./install.sh

# Access UI at https://harbor.example.com
# Default credentials: admin / Harbor12345

# Login
docker login harbor.example.com
docker push harbor.example.com/myproject/my-app:v1.0.0
```

---

## 7. Image Tagging Strategies

### Semantic versioning

```bash
# Tag with full semver + additional tags
docker build -t my-app:2.1.3 .
docker tag my-app:2.1.3 myregistry/my-app:2.1.3   # exact version
docker tag my-app:2.1.3 myregistry/my-app:2.1      # minor
docker tag my-app:2.1.3 myregistry/my-app:2         # major
docker tag my-app:2.1.3 myregistry/my-app:latest    # latest (only for stable)

# Push all tags
docker push myregistry/my-app:2.1.3
docker push myregistry/my-app:2.1
docker push myregistry/my-app:2
docker push myregistry/my-app:latest
```

### Git-based tagging

```bash
# Tag with Git SHA (immutable, always traceable)
SHA=$(git rev-parse --short HEAD)
docker build -t myregistry/my-app:${SHA} .

# Tag with branch name
BRANCH=$(git rev-parse --abbrev-ref HEAD | sed 's/\//-/g')
docker tag myregistry/my-app:${SHA} myregistry/my-app:${BRANCH}

# Tag with Git tag
VERSION=$(git describe --tags --abbrev=0)
docker tag myregistry/my-app:${SHA} myregistry/my-app:${VERSION}
```

### Docker metadata action (GitHub Actions best practice)

```yaml
- name: Extract metadata
  id: meta
  uses: docker/metadata-action@v5
  with:
    images: ghcr.io/${{ github.repository }}
    tags: |
      type=ref,event=branch          # branch name
      type=ref,event=pr              # pr-123
      type=semver,pattern={{version}} # v1.2.3
      type=semver,pattern={{major}}.{{minor}}  # 1.2
      type=sha                       # sha-abc1234
      type=raw,value=latest,enable=${{ github.ref == 'refs/heads/main' }}

- name: Build and push
  uses: docker/build-push-action@v5
  with:
    tags: ${{ steps.meta.outputs.tags }}
    labels: ${{ steps.meta.outputs.labels }}
```

---

## 8. Multi-Platform Images

Build images that run on both amd64 (Intel/AMD) and arm64 (Apple Silicon, AWS Graviton).

```bash
# Set up buildx builder with multi-platform support
docker buildx create --name multiplatform --use
docker buildx inspect --bootstrap

# Build and push multi-platform image
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t myregistry/my-app:latest \
  --push \
  .

# The registry stores both variants — Docker pulls the right one automatically

# Build for specific platform only
docker buildx build --platform linux/arm64 -t my-app:arm64 .

# Check image platforms
docker manifest inspect myregistry/my-app:latest
docker buildx imagetools inspect myregistry/my-app:latest
```

---

## 9. Image Signing & Verification

### Cosign (modern standard)

```bash
# Install cosign
brew install cosign
# OR download from: https://github.com/sigstore/cosign/releases

# Generate key pair
cosign generate-key-pair

# Sign an image (after pushing)
cosign sign --key cosign.key myregistry/my-app:v1.0.0

# Verify signature
cosign verify \
  --key cosign.pub \
  myregistry/my-app:v1.0.0

# Keyless signing (uses OIDC — no key to manage)
cosign sign --yes myregistry/my-app:v1.0.0

# Verify keyless
cosign verify \
  --certificate-identity https://github.com/myorg/my-repo/.github/workflows/release.yml@refs/tags/v1.0.0 \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  myregistry/my-app:v1.0.0
```

### Sign in GitHub Actions

```yaml
- name: Sign image with Cosign
  run: |
    cosign sign --yes \
      ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}@${{ steps.build.outputs.digest }}
  env:
    COSIGN_EXPERIMENTAL: true    # keyless signing
```

---

## 10. Image Lifecycle & Cleanup

```bash
# Remove local images
docker rmi my-app:v1.0.0
docker image rm my-app:v1.0.0

# Remove all unused images
docker image prune                  # only dangling (untagged)
docker image prune -a               # all unused images
docker image prune -a --filter "until=24h"   # older than 24 hours

# Remove all stopped containers AND unused images/networks/volumes
docker system prune -a --volumes

# Check disk usage
docker system df
docker system df -v    # verbose — shows individual items

# ECR — delete images
aws ecr batch-delete-image \
  --repository-name my-app \
  --image-ids imageTag=v1.0.0

# List all tags in ECR repo
aws ecr list-images --repository-name my-app

# Find large images
docker images --format "{{.Size}}\t{{.Repository}}:{{.Tag}}" | sort -h
```

---

## Cheatsheet

```bash
# Login
docker login                                      # Docker Hub
echo $TOKEN | docker login ghcr.io -u user --password-stdin
aws ecr get-login-password | docker login --username AWS --password-stdin $ECR

# Tag and push
docker build -t myregistry/my-app:v1.0.0 .
docker tag my-app:latest myregistry/my-app:latest
docker push myregistry/my-app:v1.0.0

# Pull
docker pull myregistry/my-app:v1.0.0

# Inspect
docker inspect myregistry/my-app:v1.0.0
docker history myregistry/my-app:v1.0.0
docker manifest inspect myregistry/my-app:latest  # multi-platform info

# Scan
trivy image myregistry/my-app:v1.0.0

# Multi-platform build
docker buildx build --platform linux/amd64,linux/arm64 \
  -t myregistry/my-app:v1.0.0 --push .

# Cleanup
docker image prune -a
docker system prune -a --volumes
docker system df
```

---

*Next: [Container Runtime →](./08-container-runtime.md)*
