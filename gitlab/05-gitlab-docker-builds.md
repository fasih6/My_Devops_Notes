# 🐳 Docker & Container Builds

Building images in GitLab CI — registry, caching, multi-platform, and Kaniko.

---

## 📚 Table of Contents

- [1. GitLab Container Registry](#1-gitlab-container-registry)
- [2. Building with Docker-in-Docker](#2-building-with-docker-in-docker)
- [3. Building with Docker Socket](#3-building-with-docker-socket)
- [4. Building with Kaniko (No Docker Daemon)](#4-building-with-kaniko-no-docker-daemon)
- [5. Build Caching Strategies](#5-build-caching-strategies)
- [6. Multi-Platform Builds (buildx)](#6-multi-platform-builds-buildx)
- [7. Image Scanning in CI](#7-image-scanning-in-ci)
- [8. Complete Build Pipeline](#8-complete-build-pipeline)
- [Cheatsheet](#cheatsheet)

---

## 1. GitLab Container Registry

Every GitLab project has a built-in container registry — no external registry needed.

```bash
# Registry URL format
registry.gitlab.com/<group>/<project>        # GitLab.com
registry.gitlab.example.com/<group>/<project> # self-hosted

# Predefined variables
$CI_REGISTRY              # registry.gitlab.com
$CI_REGISTRY_IMAGE        # registry.gitlab.com/mygroup/my-project
$CI_REGISTRY_USER         # gitlab-ci-token
$CI_REGISTRY_PASSWORD     # auto-generated job token

# Login in pipeline
docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY

# Tag image
docker tag my-app:latest $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
docker tag my-app:latest $CI_REGISTRY_IMAGE:latest

# Push
docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
docker push $CI_REGISTRY_IMAGE:latest

# Pull (in other jobs/projects)
docker pull $CI_REGISTRY_IMAGE:latest
```

### Cleanup policy

```
Settings → Packages & Registries → Container Registry → Cleanup policy

Configure:
  - Keep N most recent images
  - Keep images matching: tag-regex
  - Remove images older than N days
  - Run on: schedule

Regex examples:
  Keep: ^(main|staging|v\d+\.\d+\.\d+)$    (main, staging, semver tags)
  Remove: ^sha-.+$                           (SHA-tagged images)
```

---

## 2. Building with Docker-in-Docker

DinD runs a Docker daemon inside a container. Most isolated option.

```yaml
# Full DinD example
build:
  stage: build
  image: docker:24
  services:
    - name: docker:24-dind
      alias: docker
      command: ["--tls=false"]   # disable TLS for simplicity (internal only)
  variables:
    DOCKER_HOST: tcp://docker:2375
    DOCKER_DRIVER: overlay2
    DOCKER_BUILDKIT: "1"
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - |
      docker build \
        --cache-from $CI_REGISTRY_IMAGE:latest \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --build-arg VERSION=$CI_COMMIT_SHORT_SHA \
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA \
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_REF_SLUG \
        .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_REF_SLUG
    - |
      if [ "$CI_COMMIT_BRANCH" == "$CI_DEFAULT_BRANCH" ]; then
        docker tag $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA $CI_REGISTRY_IMAGE:latest
        docker push $CI_REGISTRY_IMAGE:latest
      fi
  rules:
    - if: '$CI_COMMIT_BRANCH'
    - if: '$CI_COMMIT_TAG'
```

### Runner config for DinD

```toml
# config.toml — requires privileged mode
[[runners]]
  [runners.docker]
    privileged = true    # REQUIRED for DinD
```

---

## 3. Building with Docker Socket

Shares the host Docker daemon. Faster than DinD, less isolated.

```yaml
build:
  stage: build
  image: docker:24
  variables:
    DOCKER_HOST: unix:///var/run/docker.sock
    DOCKER_BUILDKIT: "1"
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
```

```toml
# Runner config — mount Docker socket
[[runners]]
  [runners.docker]
    privileged = false    # doesn't need privileged
    volumes = ["/var/run/docker.sock:/var/run/docker.sock", "/cache"]
```

### Security note

```
Mounting /var/run/docker.sock gives container full control over the host Docker daemon.
Any job can run privileged containers, access other containers, etc.
Acceptable for: trusted teams, private runners
Avoid for: public repos, untrusted code
```

---

## 4. Building with Kaniko (No Docker Daemon)

Kaniko builds Docker images without requiring a Docker daemon or privileged mode. Best for Kubernetes runners.

```yaml
build:
  stage: build
  image:
    name: gcr.io/kaniko-project/executor:v1.19.2-debug
    entrypoint: [""]
  script:
    - |
      /kaniko/executor \
        --context "$CI_PROJECT_DIR" \
        --dockerfile "$CI_PROJECT_DIR/Dockerfile" \
        --destination "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA" \
        --destination "$CI_REGISTRY_IMAGE:latest" \
        --cache=true \
        --cache-repo "$CI_REGISTRY_IMAGE/cache" \
        --build-arg "VERSION=$CI_COMMIT_SHORT_SHA" \
        --snapshot-mode=redo \
        --use-new-run
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
    - if: '$CI_COMMIT_TAG'
```

### Kaniko authentication

```yaml
before_script:
  # Create Kaniko credentials
  - mkdir -p /kaniko/.docker
  - |
    echo "{\"auths\":{\"$CI_REGISTRY\":{\"username\":\"$CI_REGISTRY_USER\",\"password\":\"$CI_REGISTRY_PASSWORD\"}}}" \
    > /kaniko/.docker/config.json
```

### Kaniko vs DinD vs Socket

| | Kaniko | DinD | Socket |
|--|--------|------|--------|
| **Privileged needed** | No ✅ | Yes ❌ | No ✅ |
| **Docker daemon** | None ✅ | Inside container | Host |
| **Speed** | Slower | Fast | Fastest |
| **Cache** | Registry-based | Local + registry | Local + registry |
| **K8s compatible** | ✅ Perfect | ⚠️ Needs privileged pods | ⚠️ Needs socket mount |

---

## 5. Build Caching Strategies

### Registry caching (works everywhere)

```yaml
build:
  script:
    - |
      docker build \
        --cache-from $CI_REGISTRY_IMAGE:cache \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA \
        -t $CI_REGISTRY_IMAGE:cache \   # push as cache
        .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
    - docker push $CI_REGISTRY_IMAGE:cache
```

### BuildKit cache mounts in Dockerfile

```dockerfile
# These cache mounts persist between builds via registry cache
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

RUN --mount=type=cache,target=/root/.npm \
    npm ci
```

### GitLab cache for build artifacts

```yaml
build:
  cache:
    key: docker-build-$CI_COMMIT_REF_SLUG
    paths:
      - .docker-cache/
  script:
    - docker buildx build \
        --cache-from type=local,src=.docker-cache \
        --cache-to type=local,dest=.docker-cache,mode=max \
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA \
        --load .
```

---

## 6. Multi-Platform Builds (buildx)

Build images that run on both amd64 (Intel/AMD) and arm64 (Apple Silicon, AWS Graviton).

```yaml
build-multiplatform:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  variables:
    DOCKER_BUILDKIT: "1"
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    # Set up QEMU for cross-compilation
    - docker run --privileged --rm tonistiigi/binfmt --install all
    # Create a builder with multi-platform support
    - docker buildx create --name multiplatform --use
    - docker buildx inspect --bootstrap
  script:
    - |
      docker buildx build \
        --platform linux/amd64,linux/arm64 \
        --cache-from type=registry,ref=$CI_REGISTRY_IMAGE:buildcache \
        --cache-to type=registry,ref=$CI_REGISTRY_IMAGE:buildcache,mode=max \
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA \
        -t $CI_REGISTRY_IMAGE:latest \
        --push \
        .
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
```

---

## 7. Image Scanning in CI

### GitLab built-in container scanning

```yaml
include:
  - template: Security/Container-Scanning.gitlab-ci.yml

container_scanning:
  variables:
    CS_IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
    CS_SEVERITY_THRESHOLD: HIGH    # fail on HIGH or CRITICAL
```

### Trivy (standalone)

```yaml
trivy-scan:
  stage: security
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  needs: [build-image]
  script:
    # Scan for vulnerabilities
    - trivy image
        --exit-code 1
        --severity HIGH,CRITICAL
        --no-progress
        --format table
        $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

    # Generate SARIF report for GitLab Security Dashboard
    - trivy image
        --format sarif
        --output trivy-results.sarif
        $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
  artifacts:
    reports:
      sast: trivy-results.sarif
    expire_in: 1 week
  allow_failure: false
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
```

---

## 8. Complete Build Pipeline

```yaml
# .gitlab/ci/build.yml — complete Docker build pipeline

variables:
  DOCKER_DRIVER: overlay2
  DOCKER_BUILDKIT: "1"
  IMAGE_TAG: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
  IMAGE_LATEST: $CI_REGISTRY_IMAGE:latest
  IMAGE_BRANCH: $CI_REGISTRY_IMAGE:$CI_COMMIT_REF_SLUG

.docker-base:
  image: docker:24
  services:
    - docker:24-dind
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY

build:
  extends: .docker-base
  stage: build
  script:
    # Pull cache layer
    - docker pull $IMAGE_LATEST || true

    # Build with cache
    - |
      docker build \
        --cache-from $IMAGE_LATEST \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --build-arg VERSION=$CI_COMMIT_SHORT_SHA \
        --build-arg BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
        --label "org.opencontainers.image.revision=$CI_COMMIT_SHA" \
        --label "org.opencontainers.image.source=$CI_PROJECT_URL" \
        -t $IMAGE_TAG \
        -t $IMAGE_BRANCH \
        .

    # Push SHA-tagged image
    - docker push $IMAGE_TAG
    - docker push $IMAGE_BRANCH

    # Push latest on default branch
    - |
      if [ "$CI_COMMIT_BRANCH" == "$CI_DEFAULT_BRANCH" ]; then
        docker tag $IMAGE_TAG $IMAGE_LATEST
        docker push $IMAGE_LATEST
      fi
  rules:
    - if: '$CI_COMMIT_BRANCH'
    - if: '$CI_COMMIT_TAG'

scan:
  stage: security
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  needs: [build]
  before_script:
    - trivy --version
  script:
    - trivy image --exit-code 1 --severity CRITICAL $IMAGE_TAG
  rules:
    - if: '$CI_COMMIT_BRANCH'
    - if: '$CI_COMMIT_TAG'
```

---

## Cheatsheet

```yaml
# Login to GitLab registry
before_script:
  - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY

# Build and push
script:
  - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA .
  - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

# With cache
script:
  - docker pull $CI_REGISTRY_IMAGE:latest || true
  - docker build --cache-from $CI_REGISTRY_IMAGE:latest
      --build-arg BUILDKIT_INLINE_CACHE=1
      -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA .
  - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

# Kaniko (no privileged)
image:
  name: gcr.io/kaniko-project/executor:debug
  entrypoint: [""]
script:
  - /kaniko/executor --context $CI_PROJECT_DIR
      --dockerfile Dockerfile
      --destination $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
      --cache=true
      --cache-repo $CI_REGISTRY_IMAGE/cache

# Scan
script:
  - trivy image --exit-code 1 --severity HIGH,CRITICAL $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
```

---

*Next: [Deployment Patterns →](./06-deployment-patterns.md)*
