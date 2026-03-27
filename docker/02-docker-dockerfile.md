# 📄 Dockerfile Deep Dive

Writing efficient, secure, production-ready Dockerfiles — every instruction explained with real examples.

---

## 📚 Table of Contents

- [1. Dockerfile Instructions Reference](#1-dockerfile-instructions-reference)
- [2. Multi-Stage Builds](#2-multi-stage-builds)
- [3. Layer Caching Optimization](#3-layer-caching-optimization)
- [4. Base Image Selection](#4-base-image-selection)
- [5. Language-Specific Patterns](#5-language-specific-patterns)
- [6. Production Dockerfile Checklist](#6-production-dockerfile-checklist)
- [7. .dockerignore](#7-dockerignore)
- [8. BuildKit Features](#8-buildkit-features)
- [Cheatsheet](#cheatsheet)

---

## 1. Dockerfile Instructions Reference

### FROM — base image

```dockerfile
# Always pin to a specific version — never use latest in production
FROM ubuntu:22.04
FROM python:3.11-slim
FROM node:20-alpine
FROM scratch                    # empty image — for statically compiled binaries

# Multi-platform
FROM --platform=linux/amd64 nginx:1.24

# Named stage (for multi-stage builds)
FROM python:3.11-slim AS builder
```

### RUN — execute commands

```dockerfile
# Shell form (runs in /bin/sh -c)
RUN apt-get update && apt-get install -y nginx

# Exec form (no shell — safer, no shell interpretation)
RUN ["apt-get", "install", "-y", "nginx"]

# Best practices
RUN apt-get update && \
    apt-get install -y \
      nginx \
      curl \
      ca-certificates && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*    # clean up in SAME layer to reduce size

# Avoid creating extra layers
# Bad:
RUN apt-get update
RUN apt-get install nginx
RUN apt-get clean

# Good: one layer
RUN apt-get update && apt-get install -y nginx && apt-get clean
```

### COPY vs ADD

```dockerfile
# COPY — copy files/directories from build context
COPY ./app /app
COPY requirements.txt /app/
COPY --chown=app:app ./app /app    # set ownership
COPY --chmod=755 ./script.sh /usr/local/bin/

# ADD — like COPY but also:
#   - Extracts tar archives automatically
#   - Fetches remote URLs (bad practice — use RUN curl instead)
ADD app.tar.gz /app/              # extracts the archive
ADD https://example.com/file /tmp/ # BAD — unpredictable, no cache

# Rule: use COPY for everything. Use ADD only for auto-extraction of local tars.
```

### ENV — environment variables

```dockerfile
# Set at build time — persists into the container
ENV APP_ENV=production
ENV DB_PORT=5432

# Multiple in one layer
ENV APP_ENV=production \
    DB_PORT=5432 \
    LOG_LEVEL=info

# Available in subsequent RUN, CMD, ENTRYPOINT instructions
# Also available at runtime in the container

# Override at runtime:
# docker run -e APP_ENV=staging my-app
```

### ARG — build arguments

```dockerfile
# ARG — only available at build time (not in running container)
ARG NODE_VERSION=20
FROM node:${NODE_VERSION}-alpine

ARG APP_VERSION=dev
RUN echo "Building version ${APP_VERSION}"

# Build with args:
# docker build --build-arg NODE_VERSION=18 --build-arg APP_VERSION=v1.2.3 .

# Difference: ARG vs ENV
# ARG: build-time only, not in final image layers (except after ENV)
# ENV: build + runtime, visible in container

# Combine for versioning:
ARG VERSION=dev
ENV APP_VERSION=${VERSION}    # now available at runtime too
```

### WORKDIR — set working directory

```dockerfile
WORKDIR /app              # creates directory if it doesn't exist

# All subsequent RUN, COPY, CMD use this as CWD
COPY . .                  # copies into /app
RUN ls                    # lists /app contents

# Use absolute paths — avoid relative paths that depend on context
# Bad:
RUN cd /app && npm install
# Good:
WORKDIR /app
RUN npm install
```

### USER — set running user

```dockerfile
# Create a non-root user
RUN groupadd -r app && useradd -r -g app app

# Switch to non-root user
USER app

# All subsequent instructions run as this user
# Container process runs as this user

# On Alpine:
RUN addgroup -S app && adduser -S app -G app
USER app
```

### EXPOSE — document ports

```dockerfile
# Documents which ports the container listens on
# Does NOT actually publish the port — that's done at runtime
EXPOSE 8080
EXPOSE 8080/tcp
EXPOSE 53/udp

# This is documentation only — for docker run -P (publish all)
# and for humans reading the Dockerfile
```

### CMD vs ENTRYPOINT

```dockerfile
# CMD — default command when container starts
# Can be overridden by docker run arguments
CMD ["nginx", "-g", "daemon off;"]
CMD ["python", "app.py"]
CMD ["node", "server.js"]

# Shell form (bad — PID 1 is sh, not your app — signals don't work properly)
CMD python app.py        # BAD

# Exec form (good — your app IS PID 1)
CMD ["python", "app.py"] # GOOD

# ────────────────────────────────────────────────────────
# ENTRYPOINT — the executable that always runs
# Cannot be overridden by docker run arguments (use --entrypoint to override)
ENTRYPOINT ["nginx"]
CMD ["-g", "daemon off;"]    # default args to ENTRYPOINT
# docker run nginx — runs: nginx -g daemon off;
# docker run nginx -v — runs: nginx -v (overrides CMD)

# Common pattern: ENTRYPOINT = your app, CMD = default args
ENTRYPOINT ["python", "app.py"]
CMD ["--port", "8080"]    # default port, can be overridden

# Entrypoint script pattern
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh
ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
```

### HEALTHCHECK

```dockerfile
HEALTHCHECK --interval=30s \
            --timeout=10s \
            --start-period=15s \
            --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Exit codes:
# 0 = healthy
# 1 = unhealthy
# 2 = reserved (don't use)

# For non-HTTP services:
HEALTHCHECK CMD pg_isready -U postgres || exit 1
HEALTHCHECK CMD redis-cli ping || exit 1

# Disable inherited healthcheck:
HEALTHCHECK NONE
```

### VOLUME — declare mount points

```dockerfile
# Declares that this path will be a volume
VOLUME /data
VOLUME ["/data", "/logs"]    # multiple volumes

# Creates an anonymous volume at this path
# Better to manage volumes explicitly at runtime
# docker run -v my-volume:/data my-app
```

### LABEL — metadata

```dockerfile
LABEL maintainer="fasih@example.com"
LABEL version="1.2.3"
LABEL description="My production application"

# OCI standard labels
LABEL org.opencontainers.image.title="My App"
LABEL org.opencontainers.image.version="1.2.3"
LABEL org.opencontainers.image.source="https://github.com/myorg/my-app"
LABEL org.opencontainers.image.created="2024-01-15T10:00:00Z"
LABEL org.opencontainers.image.revision="abc123"
```

### ONBUILD

```dockerfile
# Instructions that run when this image is used AS a base image
ONBUILD COPY . /app
ONBUILD RUN npm install

# Used for base images that downstream Dockerfiles build on
```

---

## 2. Multi-Stage Builds

Multi-stage builds use multiple FROM statements. Earlier stages can be used as sources for later stages. The final image only contains what's in the last stage.

### Why multi-stage?

```
Without multi-stage:
  Final image includes: compiler, build tools, source code, test files
  Size: 800MB+

With multi-stage:
  Final image includes: only the compiled binary + runtime deps
  Size: 15MB
```

### Go binary (smallest possible image)

```dockerfile
# Stage 1: Build
FROM golang:1.21-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download                          # cache dependencies
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build \
    -ldflags="-s -w" \                       # strip debug info
    -o server ./cmd/server/

# Stage 2: Final — FROM scratch for static binaries
FROM scratch
COPY --from=builder /app/server /server
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
EXPOSE 8080
ENTRYPOINT ["/server"]
# Final image: ~5-15MB (just the binary!)
```

### Python application

```dockerfile
# Stage 1: Build dependencies
FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: Production image
FROM python:3.11-slim
WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /root/.local /root/.local

# Copy application code
COPY . .

# Security: run as non-root
RUN groupadd -r app && useradd -r -g app app
USER app

ENV PATH=/root/.local/bin:$PATH
EXPOSE 8000
CMD ["gunicorn", "app:app", "--bind", "0.0.0.0:8000"]
```

### Node.js application

```dockerfile
# Stage 1: Install dependencies
FROM node:20-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --only=production

# Stage 2: Build (if TypeScript or bundling needed)
FROM node:20-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 3: Production image
FROM node:20-alpine AS production
WORKDIR /app
RUN addgroup -S app && adduser -S app -G app

COPY --from=deps /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY package.json .

USER app
EXPOSE 3000
CMD ["node", "dist/server.js"]
```

### Referencing specific stages

```bash
# Build only up to a specific stage (useful for testing)
docker build --target builder -t my-app:builder .

# Use a stage as a test runner
docker build --target test -t my-app:test .
docker run --rm my-app:test
```

---

## 3. Layer Caching Optimization

### Cache invalidation rules

A layer is rebuilt if:
- Its instruction changes
- Any file it COPYs changes
- Any previous layer was rebuilt (cache invalidated for all subsequent layers)

```dockerfile
# WRONG — cache busted whenever ANY file changes
COPY . /app
RUN pip install -r /app/requirements.txt

# RIGHT — dependencies cached separately from code
COPY requirements.txt /app/
RUN pip install -r /app/requirements.txt    # only re-runs when requirements.txt changes
COPY . /app                                  # code changes don't invalidate pip install
```

### Ordering for maximum cache hits

```dockerfile
# Order: least-changing → most-changing

FROM python:3.11-slim                    # 1. Base image (changes rarely)
RUN apt-get update && apt-get install -y \
    libpq-dev                            # 2. System deps (changes rarely)
COPY requirements.txt .                  # 3. Dependencies list
RUN pip install -r requirements.txt      # 4. Install deps (only when requirements change)
COPY . .                                 # 5. Application code (changes frequently)
```

### Cache mounts (BuildKit)

```dockerfile
# Persist cache between builds — not in final image
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

RUN --mount=type=cache,target=/var/cache/apt \
    apt-get update && apt-get install -y nginx

RUN --mount=type=cache,target=/root/.npm \
    npm ci
```

---

## 4. Base Image Selection

### Image variants comparison

| Variant | Size | Use case |
|---------|------|---------|
| `python:3.11` | ~900MB | Full Debian — maximum compatibility |
| `python:3.11-slim` | ~150MB | Slim Debian — most common choice |
| `python:3.11-alpine` | ~50MB | Minimal — can have compatibility issues |
| `python:3.11-bookworm` | ~900MB | Specific Debian version |
| `scratch` | 0MB | Empty — for static binaries only |
| `distroless` | ~20MB | No shell/package manager — most secure |

### Distroless images

```dockerfile
# Distroless — no shell, no package manager, minimal attack surface
FROM golang:1.21 AS builder
WORKDIR /app
COPY . .
RUN CGO_ENABLED=0 go build -o server .

FROM gcr.io/distroless/static-debian11
COPY --from=builder /app/server /server
ENTRYPOINT ["/server"]

# Can't exec into distroless container (no shell)
# For debugging: use :debug variant
FROM gcr.io/distroless/static-debian11:debug
```

### Choosing the right base image

```
Need maximum compatibility?     → debian/ubuntu full
General application?            → -slim variant
Small image, pure Go/Rust?      → scratch or distroless
Security-critical?              → distroless
Script-heavy, need shell tools? → alpine
```

---

## 5. Language-Specific Patterns

### Go — production Dockerfile

```dockerfile
FROM golang:1.21-alpine AS builder
WORKDIR /app
RUN apk add --no-cache git ca-certificates tzdata
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
    go build -ldflags="-s -w -X main.version=${VERSION}" \
    -o /app/server ./cmd/server

FROM scratch
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/
COPY --from=builder /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=builder /app/server /server
EXPOSE 8080
ENTRYPOINT ["/server"]
```

### Python — production Dockerfile

```dockerfile
FROM python:3.11-slim AS base
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

FROM base AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user -r requirements.txt

FROM base AS production
WORKDIR /app
RUN groupadd -r app && useradd -r -g app --home /app app
COPY --from=builder --chown=app:app /root/.local /home/app/.local
COPY --chown=app:app . .
USER app
ENV PATH=/home/app/.local/bin:$PATH
EXPOSE 8000
HEALTHCHECK CMD curl -f http://localhost:8000/health || exit 1
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "4", "app:app"]
```

### Node.js — production Dockerfile

```dockerfile
FROM node:20-alpine AS base
RUN apk add --no-cache libc6-compat
WORKDIR /app

FROM base AS deps
COPY package.json package-lock.json ./
RUN npm ci --only=production && npm cache clean --force

FROM base AS builder
COPY package.json package-lock.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM base AS production
ENV NODE_ENV=production
RUN addgroup -S nodejs && adduser -S nextjs -G nodejs
COPY --from=deps --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/dist ./dist
COPY --chown=nextjs:nodejs package.json .
USER nextjs
EXPOSE 3000
HEALTHCHECK CMD wget -qO- http://localhost:3000/health || exit 1
CMD ["node", "dist/server.js"]
```

---

## 6. Production Dockerfile Checklist

```dockerfile
# ✅ Pin base image version
FROM python:3.11.7-slim

# ✅ Single layer for apt installs with cleanup
RUN apt-get update && apt-get install -y \
    curl \
    && rm -rf /var/lib/apt/lists/*

# ✅ Use WORKDIR instead of cd
WORKDIR /app

# ✅ Copy dependency files before application code (caching)
COPY requirements.txt .
RUN pip install -r requirements.txt

# ✅ Copy application code last
COPY . .

# ✅ Run as non-root user
RUN useradd -r -u 1001 app
USER app

# ✅ Use exec form for CMD/ENTRYPOINT (signal handling)
CMD ["gunicorn", "app:app"]

# ✅ Add HEALTHCHECK
HEALTHCHECK CMD curl -f http://localhost:8000/health || exit 1

# ✅ Add metadata labels
LABEL org.opencontainers.image.version="1.0.0"

# ✅ Use multi-stage builds to minimize final image size

# ❌ Don't store secrets in ENV or ARG
# ❌ Don't use latest tag for base image
# ❌ Don't run as root
# ❌ Don't COPY everything before installing dependencies
# ❌ Don't use shell form for CMD (signals don't work)
# ❌ Don't install unnecessary packages
```

---

## 7. .dockerignore

Like `.gitignore` — tells Docker what to exclude from the build context.

```
# .dockerignore
.git/
.gitignore
.github/
node_modules/
npm-debug.log
.env
.env.*
*.md
docs/
tests/
*.test.js
*.spec.py
__pycache__/
*.pyc
*.pyo
.pytest_cache/
.coverage
htmlcov/
dist/
build/
*.egg-info/
.DS_Store
Thumbs.db
docker-compose*.yml
Dockerfile*
.dockerignore
```

**Why it matters:**
- Smaller build context → faster builds
- Prevents accidentally including secrets (`.env` files)
- Prevents cache invalidation from files that don't affect the build

---

## 8. BuildKit Features

BuildKit is Docker's modern build engine — faster, more features, better caching.

```bash
# Enable BuildKit
DOCKER_BUILDKIT=1 docker build .
# Or set permanently in /etc/docker/daemon.json:
# { "features": { "buildkit": true } }

# Build with BuildKit (docker buildx)
docker buildx build .
docker buildx build --platform linux/amd64,linux/arm64 -t my-app:latest --push .
```

### Secret mounts — don't bake secrets into layers

```dockerfile
# Mount a secret at build time (NOT stored in the image)
RUN --mount=type=secret,id=github_token \
    git clone https://$(cat /run/secrets/github_token)@github.com/private/repo.git

# Build:
docker build --secret id=github_token,src=$HOME/.github_token .
```

### SSH mounts — SSH agent forwarding

```dockerfile
RUN --mount=type=ssh \
    git clone git@github.com:myorg/private-repo.git
```

```bash
docker build --ssh default .
```

### Bind mounts in RUN

```dockerfile
# Mount source without COPY — useful for build-time access
RUN --mount=type=bind,source=.,target=/src \
    ls /src
```

---

## Cheatsheet

```bash
# Build
docker build -t my-app:v1 .
docker build -t my-app:v1 --no-cache .      # ignore cache
docker build -t my-app:v1 --target builder . # build to specific stage
DOCKER_BUILDKIT=1 docker build -t my-app:v1 .

# Multi-platform
docker buildx build --platform linux/amd64,linux/arm64 -t my-app:v1 --push .
```

```dockerfile
# Dockerfile skeleton
FROM base:version AS stagename
WORKDIR /app
COPY --chown=user:group requirements.txt .
RUN command && cleanup
COPY --chown=user:group . .
USER user
EXPOSE 8080
HEALTHCHECK CMD curl -f http://localhost:8080/health || exit 1
CMD ["executable", "arg1"]
```

---

*Next: [Networking →](./03-networking.md)*
