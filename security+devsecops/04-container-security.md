# Container Security

## The Container Security Problem

Containers feel isolated but share the host kernel. A container escape, a root process, or a vulnerable image layer can compromise the entire host or cluster.

Container security has four layers:
```
1. Image Security      — what's in the image before it runs
2. Registry Security   — how images are stored and distributed
3. Runtime Security    — what containers do when running
4. Host Security       — the container engine and OS
```

## Image Scanning with Trivy

Trivy is the most widely used open-source container security scanner. It scans OS packages, language dependencies, IaC files, and Kubernetes manifests.

```bash
# Install
brew install aquasecurity/trivy/trivy    # macOS
apt-get install trivy                     # Debian/Ubuntu

# Scan a Docker image
trivy image nginx:latest

# Scan only for specific severities
trivy image --severity HIGH,CRITICAL nginx:latest

# Exit with error code if critical vulns found (for CI)
trivy image --exit-code 1 --severity CRITICAL nginx:latest

# JSON output
trivy image --format json --output trivy-report.json nginx:latest

# Scan a local image (built but not pushed)
trivy image myapp:local

# Scan a tar archive
trivy image --input myimage.tar

# Ignore unfixed vulnerabilities (ones with no patch yet)
trivy image --ignore-unfixed nginx:latest

# Scan filesystem (for CI — scan before building image)
trivy fs .

# Generate SBOM from image
trivy image --format cyclonedx --output sbom.json nginx:latest
```

Trivy `.trivyignore` — suppress known false positives:
```
# .trivyignore
CVE-2023-12345   # false positive, we don't use the affected feature
CVE-2022-67890   # accepted risk, no fix available, mitigated by WAF
```

## Grype — Alternative Scanner

```bash
# Install
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh

# Scan image
grype nginx:latest

# Fail on high+ severity
grype nginx:latest --fail-on high

# Scan only OS packages
grype nginx:latest --scope squashed

# Compare against SBOM
grype sbom:./sbom.json
```

## Dockerfile Security Hardening

### Use Specific, Minimal Base Images

```dockerfile
# Bad — latest tag, unpredictable, large surface area
FROM ubuntu:latest

# Bad — full OS, many unnecessary packages
FROM python:3.11

# Good — specific version pinned
FROM python:3.11.9-slim-bookworm

# Best — distroless (no shell, no package manager, minimal attack surface)
FROM gcr.io/distroless/python3-debian12
```

Distroless images (Google):
- No shell (`/bin/sh`)
- No package manager
- Only runtime and your app
- Drastically reduced attack surface (fewer CVEs, nothing to exploit interactively)

```dockerfile
# Multi-stage build with distroless final image
FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt

FROM gcr.io/distroless/python3-debian12
COPY --from=builder /root/.local /root/.local
COPY . .
CMD ["app.py"]
```

### Run as Non-Root User

```dockerfile
# Bad — runs as root by default
FROM node:20-alpine
WORKDIR /app
COPY . .
CMD ["node", "server.js"]

# Good — create a dedicated user
FROM node:20-alpine
WORKDIR /app

# Create a non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

COPY --chown=appuser:appgroup . .

# Switch to non-root
USER appuser

CMD ["node", "server.js"]
```

### Read-Only Filesystem

```dockerfile
# Dockerfile — mark what needs to be writable
FROM node:20-alpine
WORKDIR /app
COPY . .
USER node

# In docker-compose or K8s, add:
# read_only: true
# then mount writable tmpfs for /tmp
```

```yaml
# docker-compose.yml
services:
  app:
    image: myapp:latest
    read_only: true
    tmpfs:
      - /tmp
      - /var/run
```

### Drop Capabilities

```dockerfile
# In docker run:
# --cap-drop=ALL --cap-add=NET_BIND_SERVICE

# In docker-compose:
services:
  app:
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE  # only if binding to port < 1024
```

### Full Hardened Dockerfile Example

```dockerfile
# syntax=docker/dockerfile:1.5

# Stage 1: Build
FROM golang:1.22-alpine AS builder

# Don't run build as root
RUN adduser -D -u 10001 appuser

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download

COPY . .
# Build a statically linked binary, no CGO
RUN CGO_ENABLED=0 GOOS=linux go build -a -installsuffix cgo -o app .

# Stage 2: Final — scratch image (nothing at all)
FROM scratch

# Copy only the binary and certs
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /etc/passwd /etc/passwd
COPY --from=builder /build/app /app

# Run as non-root user
USER appuser

# Drop everything
# No shell, no package manager, no OS utilities

EXPOSE 8080
ENTRYPOINT ["/app"]
```

## Image Signing with Cosign

Image signing ensures that the image you pull is exactly what was built and pushed — not tampered with in the registry.

```bash
# Install cosign
brew install sigstore/tap/cosign

# Generate a key pair
cosign generate-key-pair

# Sign an image (keyless, using OIDC — recommended for CI/CD)
cosign sign --yes registry.example.com/myapp:v1.0.0

# Sign with explicit key
cosign sign --key cosign.key registry.example.com/myapp:v1.0.0

# Verify an image
cosign verify registry.example.com/myapp:v1.0.0

# Verify with specific key
cosign verify --key cosign.pub registry.example.com/myapp:v1.0.0

# Attach an SBOM as attestation
cosign attest \
  --predicate sbom.cyclonedx.json \
  --type cyclonedx \
  registry.example.com/myapp:v1.0.0
```

Keyless signing in GitLab CI (using OIDC):
```yaml
sign-image:
  stage: sign
  image: cgr.dev/chainguard/cosign:latest
  script:
    - cosign sign --yes ${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}
  id_tokens:
    SIGSTORE_ID_TOKEN:
      aud: sigstore
```

## Docker Bench for Security

Docker Bench runs the CIS Docker Benchmark checks against your Docker host configuration.

```bash
# Run Docker Bench
docker run --rm --net host --pid host --userns host --cap-add audit_control \
  -e DOCKER_CONTENT_TRUST=$DOCKER_CONTENT_TRUST \
  -v /etc:/etc:ro \
  -v /lib/systemd/system:/lib/systemd/system:ro \
  -v /usr/bin/containerd:/usr/bin/containerd:ro \
  -v /usr/bin/runc:/usr/bin/runc:ro \
  -v /usr/lib/systemd:/usr/lib/systemd:ro \
  -v /var/lib:/var/lib:ro \
  -v /var/run/docker.sock:/var/run/docker.sock:ro \
  --label docker_bench_security \
  docker/docker-bench-security
```

CIS Docker Benchmark checks (key areas):
- Docker daemon configuration
- Docker daemon files permissions
- Container images and build files
- Container runtime
- Docker security operations
- Docker Swarm configuration

## Registry Security

### Registry Access Control

```bash
# Docker Hub — use access tokens, not passwords
docker login --username myuser --password-stdin < token_file

# Azure Container Registry
az acr login --name myregistry
az acr repository show-tags --name myregistry --repository myapp

# Enable Azure Defender for Container Registries
az security pricing create \
  --name ContainerRegistry \
  --tier Standard
```

### Image Pull Policies in Kubernetes

```yaml
# Always re-pull — never use cached potentially-stale image
spec:
  containers:
  - name: app
    image: registry.example.com/myapp:v1.0.0
    imagePullPolicy: Always  # Always for production

# Use digest (SHA) not just tag — tags are mutable, digests are not
spec:
  containers:
  - name: app
    image: registry.example.com/myapp@sha256:abc123def456...
```

### Enforce Image Signing in Kubernetes (Kyverno)

```yaml
# Only allow signed images from our registry
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: verify-image-signature
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-image-signature
    match:
      any:
      - resources:
          kinds: [Pod]
    verifyImages:
    - imageReferences:
      - "registry.example.com/*"
      attestors:
      - count: 1
        entries:
        - keyless:
            subject: "https://github.com/myorg/*"
            issuer: "https://token.actions.githubusercontent.com"
```

## Container Security in CI/CD Pipeline

```yaml
# GitLab CI — full container security pipeline
stages:
  - build
  - scan
  - sign
  - deploy

build-image:
  stage: build
  script:
    - docker build -t ${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA} .
    - docker push ${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}

trivy-scan:
  stage: scan
  image: aquasec/trivy:latest
  script:
    # Scan for vulnerabilities — fail on critical
    - trivy image
        --exit-code 1
        --severity CRITICAL
        --no-progress
        ${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}

    # Generate full report
    - trivy image
        --format json
        --output trivy-report.json
        ${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}

    # Generate SBOM
    - trivy image
        --format cyclonedx
        --output sbom.json
        ${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}
  artifacts:
    when: always
    paths:
      - trivy-report.json
      - sbom.json

sign-image:
  stage: sign
  image: cgr.dev/chainguard/cosign:latest
  script:
    - cosign sign --yes ${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}
  only:
    - main
```

## Common Container Security Misconfigurations

| Misconfiguration | Risk | Fix |
|-----------------|------|-----|
| Running as root | Container escape escalates to root on host | `USER nonroot` in Dockerfile |
| Privileged container | Full host access | Never use `--privileged` in prod |
| Mounting `/var/run/docker.sock` | Container can control Docker daemon | Remove this mount |
| Using `latest` tag | Unpredictable image contents | Pin to digest or specific version |
| Writable root filesystem | Malware can persist | `readOnlyRootFilesystem: true` |
| All Linux capabilities | Unnecessary kernel access | `drop: [ALL]`, add back only what's needed |
| No resource limits | DoS via resource exhaustion | Always set `limits.cpu` and `limits.memory` |
| Sensitive env vars in image | Secrets in image layers | Use runtime injection (Vault, K8s secrets) |

## Runtime Security (brief intro — detailed in 07-dast-runtime.md)

Even with a secure image, runtime threats exist. Key tools:

- **Falco** — Kubernetes runtime security, detects anomalous syscalls
- **Sysdig** — Commercial, wraps Falco with enterprise features  
- **Aqua Security** — Full container security platform
- **eBPF-based tools** (Cilium Tetragon) — kernel-level visibility without overhead
