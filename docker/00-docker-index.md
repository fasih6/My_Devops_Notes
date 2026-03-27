# 🐳 Docker

A complete Docker knowledge base — from core concepts and Dockerfiles to security, CI/CD, and the container runtime.

> Docker is the foundation of modern DevOps. Everything else — Kubernetes, Helm, CI/CD — runs on containers. Understanding Docker deeply means understanding what all those other tools are actually doing.

---

## 🗺️ Learning Path

```
01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10
 │     │     │     │     │     │     │     │     │     │
 │     │     │     │     │     │     │     │     │     └── Interview prep
 │     │     │     │     │     │     │     │     └──────── Fast, cached CI builds
 │     │     │     │     │     │     │     └────────────── How containers actually run
 │     │     │     │     │     │     └──────────────────── Push/pull from registries
 │     │     │     │     │     └────────────────────────── Secure your containers
 │     │     │     │     └──────────────────────────────── Multi-container apps
 │     │     │     └────────────────────────────────────── Persist data safely
 │     │     └──────────────────────────────────────────── Container communication
 │     └────────────────────────────────────────────────── Write production Dockerfiles
 └──────────────────────────────────────────────────────── How Docker works
```

---

## 📚 Contents

| # | File | What you'll learn |
|---|------|------------------|
| 01 | [Core Concepts](./01-docker-core-concepts.md) | Architecture, images, containers, layers, overlayfs, Linux primitives |
| 02 | [Dockerfile Deep Dive](./02-docker-dockerfile.md) | Every instruction, multi-stage builds, caching, language patterns |
| 03 | [Networking](./03-docker-networking.md) | Bridge networks, DNS, port publishing, host network, troubleshooting |
| 04 | [Storage & Volumes](./04-docker-storage.md) | Volumes, bind mounts, tmpfs, backup/restore patterns |
| 05 | [Docker Compose](./05-docker-compose.md) | Multi-container apps, services, dependencies, health checks, profiles |
| 06 | [Security](./06-docker-security.md) | Non-root, capabilities, seccomp, image scanning, secrets, hardening |
| 07 | [Registry & Image Management](./07-docker-registry.md) | ECR, GHCR, GCR, Harbor, tagging strategies, multi-platform, signing |
| 08 | [Container Runtime](./08-docker-runtime.md) | containerd, runc, OCI, CRI, crictl, gVisor, Kata |
| 09 | [Docker in CI/CD](./09-docker-cicd.md) | BuildKit, registry cache, GitHub Actions, GitLab CI, Kaniko |
| 10 | [Interview Q&A](./10-docker-interview-qa.md) | Core, scenario-based, and advanced interview questions |

---

## ⚡ Quick Reference

### Most-used Docker commands

```bash
# Images
docker pull nginx:1.24
docker build -t my-app:v1 .
docker build -t my-app:v1 --no-cache .
docker images
docker rmi my-app:old
docker image prune -a

# Containers
docker run -d --name app -p 8080:80 my-app:v1
docker run -it --rm ubuntu bash          # interactive, delete on exit
docker ps && docker ps -a
docker logs app -f --tail=100
docker exec -it app bash
docker stop app && docker rm app
docker stats

# Networks
docker network create my-net
docker network ls
docker network connect my-net app

# Volumes
docker volume create my-data
docker volume ls
docker run -v my-data:/data my-app

# Registry
docker login ghcr.io -u user --password-stdin
docker tag my-app:v1 ghcr.io/myorg/my-app:v1
docker push ghcr.io/myorg/my-app:v1

# Cleanup
docker system prune -a --volumes
docker system df
```

### Docker Compose quick reference

```bash
docker compose up -d              # start all
docker compose up -d --build      # rebuild and start
docker compose down               # stop and remove
docker compose down -v            # also remove volumes
docker compose ps                 # status
docker compose logs -f api        # follow logs
docker compose exec api bash      # shell into service
docker compose run --rm api python manage.py migrate  # one-off command
docker compose --profile monitoring up -d
```

### Secure Docker run template

```bash
docker run \
  --user 1000:1000 \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \
  --security-opt no-new-privileges:true \
  --read-only \
  --tmpfs /tmp \
  --memory 256m \
  --cpus 0.5 \
  --restart unless-stopped \
  my-app
```

---

## 🧠 Key Concepts at a Glance

| Concept | One-line summary |
|---------|-----------------|
| **Image** | Read-only template — stack of filesystem layers |
| **Container** | Running instance of an image — isolated Linux process |
| **Layer** | One filesystem snapshot — stacked via overlayfs |
| **overlayfs** | Union filesystem merging read-only layers + writable container layer |
| **Namespace** | Linux isolation for PID, network, mounts, hostname |
| **cgroup** | Linux resource limits — CPU, memory, I/O per process group |
| **Dockerfile** | Instructions for building an image |
| **Multi-stage build** | Multiple FROM stages — final image has no build tools |
| **Layer cache** | Docker reuses unchanged layers — order matters (rare changes first) |
| **ENTRYPOINT** | The executable that always runs — override with `--entrypoint` |
| **CMD** | Default args to ENTRYPOINT — override with `docker run` arguments |
| **Volume** | Docker-managed persistent storage — survives container deletion |
| **Bind mount** | Host path mounted into container — great for dev, not ideal for prod |
| **tmpfs** | In-memory mount — fast, never hits disk, lost when container stops |
| **Custom bridge** | User-defined network with DNS — containers find each other by name |
| **containerd** | High-level runtime Docker and K8s use internally |
| **runc** | Low-level OCI runtime — actually creates the container process |
| **OCI** | Open Container Initiative — standard format for images and runtimes |
| **CRI** | Container Runtime Interface — how Kubernetes talks to containerd |
| **BuildKit** | Modern Docker build engine — parallel, cached, secrets, multi-platform |
| **Distroless** | Minimal base image — no shell, no package manager, tiny attack surface |
| **Trivy** | Open-source vulnerability scanner for container images |
| **crictl** | CLI for debugging containers on Kubernetes nodes |

---

## 🗂️ Folder Structure

```
docker/
├── 00-docker-index.md              ← You are here
├── 01-docker-core-concepts.md
├── 02-docker-dockerfile.md
├── 03-docker-networking.md
├── 04-docker-storage.md
├── 05-docker-compose.md
├── 06-docker-security.md
├── 07-docker-registry.md
├── 08-docker-runtime.md
├── 09-docker-cicd.md
└── 10-docker-interview-qa.md
```

---

## 🔗 How Docker Connects to the Rest of Your Notes

| Topic | Connection |
|-------|-----------|
| **Kubernetes** | K8s runs containers via containerd (same OCI images) — pods are containers with extra isolation |
| **Helm** | Helm charts deploy Docker images to Kubernetes — image.repository and image.tag in values.yaml |
| **Observability** | Prometheus, Grafana, Loki all packaged as Docker images |
| **Linux** | Containers use Linux namespaces, cgroups, overlayfs — covered in linux/ folder |
| **CI/CD** | GitHub Actions / GitLab CI build and push Docker images as part of deployment pipelines |
| **Ansible** | Ansible can build and deploy Docker containers — community.docker collection |

---

*Notes are living documents — updated as I learn and build.*
