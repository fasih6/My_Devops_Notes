# 🚀 Docker in CI/CD

BuildKit caching, multi-stage builds, GitHub Actions, and production build pipelines.

---

## 📚 Table of Contents

- [1. BuildKit Deep Dive](#1-buildkit-deep-dive)
- [2. Build Caching Strategies](#2-build-caching-strategies)
- [3. GitHub Actions Workflows](#3-github-actions-workflows)
- [4. GitLab CI Pipelines](#4-gitlab-ci-pipelines)
- [5. Docker-in-Docker vs Kaniko](#5-docker-in-docker-vs-kaniko)
- [6. Build Best Practices](#6-build-best-practices)
- [Cheatsheet](#cheatsheet)

---

## 1. BuildKit Deep Dive

BuildKit is Docker's modern build engine — enabled by default in Docker 23+.

### Why BuildKit

```
Old builder:          BuildKit:
Sequential layers     Parallel build graph
No cache mounts       Cache mounts (pip, npm, apt)
No secrets           Secret mounts (no layer leakage)
No SSH forwarding    SSH agent forwarding
Single platform       Multi-platform (buildx)
```

```bash
# Enable BuildKit
export DOCKER_BUILDKIT=1
docker build .

# Or use docker buildx (always uses BuildKit)
docker buildx build .

# Create a builder with advanced features
docker buildx create --name mybuilder --use
docker buildx inspect --bootstrap    # starts the builder
```

### BuildKit special RUN flags

```dockerfile
# Cache mount — persist between builds, not in image
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y git

RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Secret mount — not stored in image layers
RUN --mount=type=secret,id=github_token \
    git clone https://$(cat /run/secrets/github_token)@github.com/private/repo .

# SSH mount — forward SSH agent
RUN --mount=type=ssh \
    git clone git@github.com:private/repo.git

# Bind mount — read-only access to build context
RUN --mount=type=bind,source=.,target=/src \
    cat /src/version.txt
```

---

## 2. Build Caching Strategies

### Registry cache (best for CI)

```bash
# Push cache to registry
docker buildx build \
  --cache-to type=registry,ref=myregistry/my-app:buildcache,mode=max \
  --cache-from type=registry,ref=myregistry/my-app:buildcache \
  -t myregistry/my-app:latest \
  --push \
  .

# mode=max: cache all layers (including intermediate)
# mode=min: only cache final image layers
```

### GitHub Actions cache

```bash
# Use GitHub Actions cache backend
docker buildx build \
  --cache-to type=gha,mode=max \
  --cache-from type=gha \
  -t myregistry/my-app:latest \
  --push \
  .
```

### Local cache

```bash
# Save cache to local directory
docker buildx build \
  --cache-to type=local,dest=/tmp/cache,mode=max \
  --cache-from type=local,src=/tmp/cache \
  -t my-app:latest \
  .
```

---

## 3. GitHub Actions Workflows

### Complete CI/CD workflow

```yaml
# .github/workflows/docker.yml
name: Docker Build & Push

on:
  push:
    branches: [main, develop]
    tags: ['v*']
  pull_request:
    branches: [main]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}

jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
      security-events: write    # for SARIF upload

    outputs:
      image-digest: ${{ steps.build.outputs.digest }}
      image-tags: ${{ steps.meta.outputs.tags }}

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      # Setup Docker Buildx (enables BuildKit + multi-platform)
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      # Login to GHCR
      - name: Login to GHCR
        if: github.event_name != 'pull_request'
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      # Generate tags and labels
      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha,prefix=sha-
            type=raw,value=latest,enable={{is_default_branch}}

      # Build and push with cache
      - name: Build and push
        id: build
        uses: docker/build-push-action@v5
        with:
          context: .
          push: ${{ github.event_name != 'pull_request' }}
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max
          platforms: linux/amd64,linux/arm64
          build-args: |
            VERSION=${{ github.ref_name }}
            BUILD_DATE=${{ github.event.head_commit.timestamp }}
            GIT_SHA=${{ github.sha }}

      # Scan for vulnerabilities
      - name: Run Trivy vulnerability scanner
        uses: aquasecurity/trivy-action@master
        with:
          image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ steps.meta.outputs.version }}
          format: sarif
          output: trivy-results.sarif
          severity: CRITICAL,HIGH

      - name: Upload Trivy results to GitHub Security
        uses: github/codeql-action/upload-sarif@v2
        if: always()
        with:
          sarif_file: trivy-results.sarif

  # Optional: deploy after build
  deploy:
    needs: build
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    environment: production

    steps:
      - name: Deploy to production
        run: |
          # Example: update Helm chart image tag
          helm upgrade --install my-app ./helm/my-app \
            --set image.tag=${{ github.sha }} \
            --atomic
```

### PR preview environments

```yaml
# Build on PRs but don't push (just verify it builds)
- name: Build (PR — no push)
  if: github.event_name == 'pull_request'
  uses: docker/build-push-action@v5
  with:
    context: .
    push: false        # build only, don't push
    tags: my-app:pr-${{ github.event.number }}
    cache-from: type=gha
    cache-to: type=gha,mode=max
```

---

## 4. GitLab CI Pipelines

```yaml
# .gitlab-ci.yml
stages:
  - build
  - test
  - scan
  - push

variables:
  DOCKER_BUILDKIT: "1"
  IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
  IMAGE_LATEST: $CI_REGISTRY_IMAGE:latest

# Login template
.docker-login: &docker-login
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY

# Build
build:
  stage: build
  image: docker:24
  services: [docker:24-dind]
  <<: *docker-login
  script:
    - |
      docker buildx build \
        --cache-from $CI_REGISTRY_IMAGE:buildcache \
        --cache-to type=registry,ref=$CI_REGISTRY_IMAGE:buildcache,mode=max \
        --build-arg VERSION=$CI_COMMIT_SHORT_SHA \
        -t $IMAGE \
        --push \
        .
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
    - if: $CI_PIPELINE_SOURCE == "merge_request_event"

# Security scan
trivy-scan:
  stage: scan
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  script:
    - trivy image --exit-code 1 --severity CRITICAL $IMAGE
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH

# Tag as latest on main
tag-latest:
  stage: push
  image: docker:24
  services: [docker:24-dind]
  <<: *docker-login
  script:
    - docker pull $IMAGE
    - docker tag $IMAGE $IMAGE_LATEST
    - docker push $IMAGE_LATEST
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

---

## 5. Docker-in-Docker vs Kaniko

### Docker-in-Docker (DinD)

Runs Docker inside a Docker container. Requires privileged mode.

```yaml
# GitLab CI with DinD
build:
  image: docker:24
  services:
    - docker:24-dind    # DinD service
  variables:
    DOCKER_HOST: tcp://docker:2376
    DOCKER_TLS_CERTDIR: "/certs"
  script:
    - docker build -t my-app .
```

**Problems with DinD:**
- Requires `--privileged` — security risk
- Slow (nested virtualization)
- Cache not shared between builds

### Kaniko — build without Docker daemon

Kaniko builds Docker images without requiring Docker daemon or privileged access.

```yaml
# GitHub Actions with Kaniko
- name: Build with Kaniko
  uses: aevea/action-kaniko@master
  with:
    image: my-app
    registry: ghcr.io
    registry_username: ${{ github.actor }}
    registry_password: ${{ secrets.GITHUB_TOKEN }}
    tag: ${{ github.sha }}
    cache: true
    cache_registry: ghcr.io/${{ github.repository }}/cache
```

```yaml
# Kubernetes Job with Kaniko
apiVersion: batch/v1
kind: Job
metadata:
  name: kaniko-build
spec:
  template:
    spec:
      containers:
        - name: kaniko
          image: gcr.io/kaniko-project/executor:latest
          args:
            - --dockerfile=Dockerfile
            - --context=git://github.com/myorg/my-app
            - --destination=myregistry/my-app:v1.0.0
            - --cache=true
          volumeMounts:
            - name: docker-config
              mountPath: /kaniko/.docker
      volumes:
        - name: docker-config
          secret:
            secretName: registry-credentials
      restartPolicy: Never
```

### BuildKit without DinD

Use `docker buildx` with a remote builder — no DinD needed:

```bash
# Use TCP socket (not recommended for production)
DOCKER_HOST=tcp://builder:2376 docker buildx build .

# Better: use BuildKit daemon
docker buildx create --driver docker-container --name remote-builder
docker buildx use remote-builder
docker buildx build .
```

---

## 6. Build Best Practices

### Optimize build time

```dockerfile
# 1. Order layers: rarely-changing → frequently-changing
FROM node:20-alpine
WORKDIR /app
COPY package.json package-lock.json ./   # rarely changes
RUN npm ci                                # cached until package.json changes
COPY . .                                  # changes frequently

# 2. Use cache mounts for package managers
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# 3. Use .dockerignore — exclude unnecessary files
# (see .dockerignore section in 02-dockerfile-deep-dive.md)

# 4. Multi-stage builds — keep final image small
```

### Reproducible builds

```dockerfile
# Pin all versions
FROM node:20.10.0-alpine3.19          # exact version
RUN npm ci                             # use lock file, not npm install

# In CI — always build fresh (don't rely on stale cache)
docker build --no-cache .             # when you need to verify

# But USE cache normally for speed
docker buildx build --cache-from ... .
```

### Build arguments for versioning

```dockerfile
ARG VERSION=dev
ARG BUILD_DATE
ARG GIT_SHA

LABEL org.opencontainers.image.version="${VERSION}"
LABEL org.opencontainers.image.created="${BUILD_DATE}"
LABEL org.opencontainers.image.revision="${GIT_SHA}"

ENV APP_VERSION=${VERSION}
```

```bash
docker build \
  --build-arg VERSION=$(git describe --tags) \
  --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  --build-arg GIT_SHA=$(git rev-parse HEAD) \
  -t my-app:$(git describe --tags) .
```

---

## Cheatsheet

```bash
# BuildKit
export DOCKER_BUILDKIT=1
docker buildx build .
docker buildx create --name mybuilder --use

# Build with cache (registry)
docker buildx build \
  --cache-from type=registry,ref=myregistry/cache \
  --cache-to type=registry,ref=myregistry/cache,mode=max \
  -t myregistry/my-app:latest \
  --push .

# Multi-platform
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t myregistry/my-app:latest \
  --push .

# Build args
docker build \
  --build-arg VERSION=v1.2.3 \
  --build-arg GIT_SHA=$(git rev-parse --short HEAD) \
  -t my-app:v1.2.3 .

# Scan after build
trivy image my-app:latest

# Check image
docker history my-app:latest
dive my-app:latest          # interactive layer explorer
docker inspect my-app:latest
```

---

*Next: [Interview Q&A →](./10-interview-qa.md)*
