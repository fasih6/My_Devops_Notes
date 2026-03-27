# 🐳 Docker Core Concepts & Architecture

How Docker works under the hood — images, containers, layers, and the container runtime.

> Docker is the reason containers became mainstream. Understanding how it works at the Linux level makes you a much better DevOps engineer — and makes Kubernetes make a lot more sense.

---

## 📚 Table of Contents

- [1. What is Docker?](#1-what-is-docker)
- [2. Docker Architecture](#2-docker-architecture)
- [3. Images](#3-images)
- [4. Containers](#4-containers)
- [5. Image Layers & Union Filesystems](#5-image-layers--union-filesystems)
- [6. How Docker Uses Linux](#6-how-docker-uses-linux)
- [7. Essential Docker Commands](#7-essential-docker-commands)
- [8. Docker Desktop vs Docker Engine](#8-docker-desktop-vs-docker-engine)
- [Key Terms Glossary](#key-terms-glossary)

---

## 1. What is Docker?

Docker is a platform for **building, shipping, and running containers**. It packages an application and all its dependencies into a standardized unit (a container) that runs consistently anywhere.

### The core problem Docker solves

```
Without Docker:
  Developer: "Works on my machine"
  Ops: "Doesn't work in production"
  Root cause: Different OS, library versions, configs

With Docker:
  Developer builds image → same image runs everywhere
  Dev laptop = CI server = staging = production
```

### What Docker provides

| Component | What it does |
|-----------|-------------|
| **Docker Engine** | Runs and manages containers |
| **Docker CLI** | Command-line interface (`docker run`, `docker build`) |
| **Docker Hub** | Public registry for sharing images |
| **Docker Compose** | Define and run multi-container applications |
| **Docker BuildKit** | Modern, fast image build engine |

---

## 2. Docker Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Docker Client (CLI)                   │
│                   docker build/run/pull                  │
└──────────────────────────┬──────────────────────────────┘
                           │ REST API (Unix socket or TCP)
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    Docker Daemon (dockerd)               │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   Images     │  │  Containers  │  │   Networks   │  │
│  │  management  │  │  lifecycle   │  │   Volumes    │  │
│  └──────────────┘  └──────────────┘  └──────────────┘  │
└──────────────────────────┬──────────────────────────────┘
                           │ OCI (containerd)
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    containerd                            │
│              (high-level container runtime)              │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    runc                                  │
│              (low-level OCI runtime)                     │
│         actually creates the container process           │
└──────────────────────────┬──────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────┐
│                    Linux Kernel                          │
│            namespaces + cgroups + overlayfs             │
└─────────────────────────────────────────────────────────┘
```

### Client-server model

```bash
# The Docker CLI sends commands to the Docker daemon
# Default: Unix socket at /var/run/docker.sock

# Check what's running
docker info
docker version

# The daemon can be on a remote machine
DOCKER_HOST=tcp://remote-server:2376 docker ps
```

---

## 3. Images

An **image** is a read-only template containing everything needed to run an application: code, runtime, libraries, environment variables, config files.

### Image naming

```
registry/repository:tag

Examples:
nginx:1.24                          # Docker Hub official image
ubuntu:22.04                        # Docker Hub official
myuser/my-app:v1.2.3               # Docker Hub user image
ghcr.io/myorg/my-app:latest        # GitHub Container Registry
123456789.dkr.ecr.eu-central-1.amazonaws.com/my-app:v1.0.0  # AWS ECR

# Default tag is "latest" if omitted
nginx == nginx:latest               # avoid latest in production!
```

### Pulling images

```bash
# Pull from Docker Hub
docker pull nginx
docker pull nginx:1.24
docker pull nginx:1.24-alpine       # Alpine variant (smaller)

# Pull from other registries
docker pull ghcr.io/myorg/my-app:v1.2.3
docker pull ubuntu:22.04

# Pull for specific platform
docker pull --platform linux/arm64 nginx:1.24

# List local images
docker images
docker image ls
docker image ls --filter dangling=true   # untagged images

# Image details
docker inspect nginx:1.24
docker history nginx:1.24              # shows layers
docker image history nginx:1.24 --no-trunc

# Remove images
docker rmi nginx:1.24
docker image rm nginx:1.24
docker image prune                     # remove unused images
docker image prune -a                  # remove ALL unused images
```

---

## 4. Containers

A **container** is a running instance of an image. It adds a writable layer on top of the read-only image layers.

```
Image (read-only)              Container (running)
┌─────────────────┐            ┌─────────────────┐
│  nginx binary   │            │  Writable layer  │ ← container-specific changes
│  config files   │  +  run  = │─────────────────│
│  libraries      │            │  nginx binary    │
│  OS files       │            │  config files    │
└─────────────────┘            │  libraries       │
                               │  OS files        │
                               └─────────────────┘
```

### Container lifecycle

```
Created → Running → Paused → Running → Stopped → Removed
                                     ↑
                              (can restart)
```

### Running containers

```bash
# Basic run
docker run nginx

# Run with name
docker run --name my-nginx nginx

# Run in background (detached)
docker run -d nginx
docker run -d --name my-nginx nginx

# Run and attach terminal
docker run -it ubuntu bash
docker run -it --rm ubuntu bash   # --rm: delete when stopped

# Run with port mapping
docker run -d -p 8080:80 nginx    # host:container
docker run -d -p 127.0.0.1:8080:80 nginx  # bind to localhost only

# Run with environment variables
docker run -d -e APP_ENV=production -e DB_HOST=localhost my-app

# Run with resource limits
docker run -d \
  --memory=256m \         # memory limit
  --cpus=0.5 \            # CPU limit (half a core)
  --memory-swap=512m \    # swap limit
  nginx

# Run with volume
docker run -d -v /host/path:/container/path nginx
docker run -d -v my-volume:/data nginx

# Run with network
docker run -d --network my-network nginx

# Auto-restart policy
docker run -d --restart=always nginx
docker run -d --restart=on-failure:3 nginx   # max 3 retries
docker run -d --restart=unless-stopped nginx

# Override entrypoint and command
docker run nginx echo "hello"
docker run --entrypoint /bin/sh nginx -c "echo hello"
```

### Managing containers

```bash
# List containers
docker ps                    # running containers
docker ps -a                 # all containers (including stopped)
docker ps -q                 # just container IDs

# Inspect container
docker inspect my-nginx
docker inspect my-nginx --format='{{.NetworkSettings.IPAddress}}'

# Container logs
docker logs my-nginx
docker logs my-nginx -f      # follow
docker logs my-nginx --tail=100
docker logs my-nginx --since=1h
docker logs my-nginx --timestamps

# Execute command in running container
docker exec -it my-nginx bash
docker exec my-nginx cat /etc/nginx/nginx.conf
docker exec -u root my-nginx bash   # run as root

# Container stats (live)
docker stats
docker stats my-nginx
docker stats --no-stream    # one snapshot, don't follow

# Stop / kill / remove
docker stop my-nginx         # SIGTERM, then SIGKILL after timeout
docker kill my-nginx         # SIGKILL immediately
docker rm my-nginx           # remove stopped container
docker rm -f my-nginx        # force remove running container

# Remove all stopped containers
docker container prune

# Copy files to/from container
docker cp ./file.txt my-nginx:/tmp/
docker cp my-nginx:/var/log/nginx/access.log ./
```

---

## 5. Image Layers & Union Filesystems

### How image layers work

Each instruction in a Dockerfile creates a new read-only layer. Layers are shared between images — this is what makes Docker storage-efficient.

```
Dockerfile:
  FROM ubuntu:22.04         → Layer 1: Ubuntu base OS files
  RUN apt-get install nginx → Layer 2: nginx binary + dependencies
  COPY ./app /app           → Layer 3: your application files
  RUN chmod +x /app/start.sh → Layer 4: permission change

Image = Stack of 4 read-only layers

When you run a container:
  + Writable layer 0 (container-specific changes)
  ─────────────────────────────────────────────
  = Layer 4 (chmod)
  = Layer 3 (app files)
  = Layer 2 (nginx)
  = Layer 1 (ubuntu)
```

### Layer caching

Docker caches each layer. If nothing changed, it reuses the cached layer — making subsequent builds very fast.

```dockerfile
# Bad ordering — cache invalidated often
FROM python:3.11
COPY . /app              # copies ALL files — any change invalidates
RUN pip install -r requirements.txt  # expensive reinstall every time

# Good ordering — cache requirements separately
FROM python:3.11
COPY requirements.txt /app/  # only changes when requirements change
RUN pip install -r /app/requirements.txt  # cached unless requirements.txt changes
COPY . /app              # copy code last — cache miss here doesn't redo pip
```

### overlayfs — the union filesystem

Docker uses `overlayfs` (overlay filesystem) to stack layers:

```bash
# See overlayfs in action
docker inspect my-nginx | grep -A5 GraphDriver

# Output shows:
# LowerDir:  read-only image layers
# UpperDir:  writable container layer
# WorkDir:   overlayfs working directory
# MergedDir: combined view (what the container sees)
```

```bash
# Layer storage location
ls /var/lib/docker/overlay2/
# Each directory = one layer
```

---

## 6. How Docker Uses Linux

Containers are Linux processes with extra isolation — not virtual machines. Docker uses three Linux kernel features:

### Namespaces — isolation

| Namespace | Isolates |
|-----------|---------|
| `pid` | Process IDs — container has its own PID 1 |
| `net` | Network interfaces, IPs, routing |
| `mnt` | Filesystem mounts |
| `uts` | Hostname and domain name |
| `ipc` | Inter-process communication (shared memory) |
| `user` | User and group IDs |

```bash
# See namespaces of a container
docker inspect my-container | grep Pid
ls -la /proc/<pid>/ns/
```

### cgroups — resource limits

```bash
# See cgroup limits for a container
cat /sys/fs/cgroup/memory/docker/<container-id>/memory.limit_in_bytes
cat /sys/fs/cgroup/cpu/docker/<container-id>/cpu.cfs_quota_us
```

### Capabilities — fine-grained root privileges

Instead of giving containers full root, Docker drops most Linux capabilities by default:

```bash
# Default capabilities a container gets
docker run --cap-add NET_ADMIN nginx    # add a capability
docker run --cap-drop ALL nginx         # drop all
docker run --privileged nginx           # give ALL capabilities (dangerous!)
```

---

## 7. Essential Docker Commands

### System commands

```bash
# System info
docker info                      # docker daemon info
docker version                   # client and server versions
docker system df                 # disk usage
docker system prune              # clean up everything unused
docker system prune -a --volumes # nuclear option — remove everything
docker system events             # live event stream

# Context (multi-host management)
docker context ls
docker context use remote-server
```

### Quick reference

```bash
# Build
docker build -t my-app:v1 .
docker build -t my-app:v1 -f Dockerfile.prod .

# Run
docker run -d --name app -p 8080:80 my-app:v1
docker run -it --rm ubuntu bash

# Manage
docker ps -a
docker logs app -f
docker exec -it app bash
docker stop app && docker rm app

# Images
docker pull nginx:1.24
docker push myregistry/my-app:v1
docker tag my-app:v1 myregistry/my-app:v1

# Cleanup
docker system prune -a
docker volume prune
docker network prune
```

---

## 8. Docker Desktop vs Docker Engine

| | Docker Desktop | Docker Engine |
|--|---------------|--------------|
| **Platform** | macOS, Windows, Linux | Linux only |
| **GUI** | Yes | No |
| **License** | Paid for large companies | Free (Apache 2.0) |
| **VM** | Runs Linux VM on Mac/Windows | Runs natively |
| **Use case** | Developer workstations | Servers, CI |
| **Alternatives** | Colima, Rancher Desktop, Podman | — |

```bash
# On Linux servers — Docker Engine
sudo apt install docker.io
sudo usermod -aG docker $USER    # run docker without sudo

# Verify
docker run hello-world
```

---

## Key Terms Glossary

| Term | Definition |
|------|-----------|
| **Image** | Read-only template for creating containers |
| **Container** | Running instance of an image — isolated process |
| **Layer** | One filesystem change in an image — stacked to form the final filesystem |
| **Registry** | Server storing and distributing images (Docker Hub, ECR, GHCR) |
| **Dockerfile** | Text file with instructions for building an image |
| **Docker daemon** | Background service managing containers (dockerd) |
| **containerd** | High-level container runtime used by Docker and Kubernetes |
| **runc** | Low-level OCI runtime — actually creates the container process |
| **overlayfs** | Union filesystem that stacks read-only layers + writable layer |
| **Namespace** | Linux kernel feature providing process isolation |
| **cgroup** | Linux kernel feature limiting CPU/memory/IO per process group |
| **Volume** | Persistent storage that survives container restarts |
| **Bind mount** | Host directory mounted into container |
| **Port mapping** | Forward traffic from host port to container port |
| **OCI** | Open Container Initiative — standard for container images and runtimes |
| **BuildKit** | Modern Docker build engine — parallel, cached, more features |
| **Multi-stage build** | Dockerfile with multiple FROM stages — smaller final images |
| **Dangling image** | Untagged image — usually old build cache |

---

*Next: [Dockerfile Deep Dive →](./02-dockerfile-deep-dive.md)*
