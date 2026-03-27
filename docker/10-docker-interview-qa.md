# 🎯 Docker Interview Q&A

Real Docker questions asked in DevOps interviews — with complete answers.

---

## 📚 Table of Contents

- [🔥 Core Concepts](#-core-concepts)
- [📄 Dockerfile & Images](#-dockerfile--images)
- [🌐 Networking](#-networking)
- [💾 Storage](#-storage)
- [🔐 Security](#-security)
- [⚙️ Runtime & Architecture](#️-runtime--architecture)
- [🔥 Scenario-Based Questions](#-scenario-based-questions)
- [🧠 Advanced Questions](#-advanced-questions)
- [💬 Questions to Ask the Interviewer](#-questions-to-ask-the-interviewer)

---

## 🔥 Core Concepts

---

**Q: What is Docker and how does it differ from a virtual machine?**

Docker is a platform for packaging and running applications in containers. A container is an isolated process that shares the host OS kernel — unlike a VM which runs a complete OS with its own kernel via a hypervisor.

Key differences: VMs take minutes to start and use GB of RAM (full OS). Containers start in milliseconds and share the host kernel — they only contain the app and its dependencies. VMs have stronger isolation (separate kernel). Containers have process-level isolation via Linux namespaces and cgroups.

The tradeoff: containers are faster and more resource-efficient, but rely on the host kernel. A kernel vulnerability can affect all containers.

---

**Q: What is the difference between an image and a container?**

An **image** is a read-only template — a stack of filesystem layers containing everything needed to run an application. It's like a class in object-oriented programming.

A **container** is a running instance of an image — an isolated process with a writable layer added on top of the image layers. Multiple containers can run from the same image, just like multiple objects from one class.

When you stop a container, the writable layer is preserved. When you delete it, the writable layer is gone — the image remains.

---

**Q: What are image layers and why do they matter?**

Each instruction in a Dockerfile creates a new read-only filesystem layer. Docker uses overlayfs to stack these layers into a single view. Layers are identified by a SHA256 hash and shared between images — if two images use the same base, they share those layers on disk.

Layers matter because:
1. **Caching** — Docker caches each layer. If a layer's instruction and inputs haven't changed, Docker reuses the cached version — making builds fast.
2. **Storage efficiency** — shared layers between images save disk space and registry bandwidth.
3. **Ordering matters** — put frequently-changing layers at the end so earlier layers are cached.

---

**Q: What is the difference between CMD and ENTRYPOINT?**

**ENTRYPOINT** defines the executable that always runs when the container starts. It can only be overridden with `--entrypoint` at runtime.

**CMD** provides default arguments to ENTRYPOINT, or a default command if no ENTRYPOINT is set. It can be overridden by arguments to `docker run`.

The common pattern:
```dockerfile
ENTRYPOINT ["python", "app.py"]   # always runs python app.py
CMD ["--port", "8080"]            # default args, can be overridden
```
`docker run my-app --port 9090` would run `python app.py --port 9090`.

Always use exec form `["executable", "arg"]` not shell form `executable arg` — exec form makes your app PID 1 so it receives signals correctly (SIGTERM for graceful shutdown).

---

## 📄 Dockerfile & Images

---

**Q: What is a multi-stage build and why would you use it?**

A multi-stage build uses multiple `FROM` statements in one Dockerfile. Earlier stages compile or build the application. The final stage copies only what's needed from earlier stages — no build tools, source code, or compilation artifacts in the final image.

```dockerfile
FROM golang:1.21 AS builder
WORKDIR /app
COPY . .
RUN go build -o server .

FROM scratch           # empty base image
COPY --from=builder /app/server /server
ENTRYPOINT ["/server"]
```

Result: a 5-15MB image instead of a 900MB Go compiler image. Smaller images mean faster pulls, less attack surface, and lower storage costs.

---

**Q: What is .dockerignore and why is it important?**

`.dockerignore` tells Docker which files to exclude from the build context — similar to `.gitignore`. The build context is everything sent to the Docker daemon before building.

It matters for two reasons:
1. **Performance** — a large build context (including `node_modules/`, `.git/`, large test data) slows down every build even if those files aren't used.
2. **Security** — prevents accidentally including `.env` files, SSH keys, or other secrets that might be COPYed into the image.

---

**Q: How does Docker layer caching work and how do you optimize for it?**

Docker checks each layer before building it. If the instruction AND all inputs (files referenced by COPY, build args, etc.) are identical to a cached layer, Docker reuses the cache. Once any layer is invalidated, all subsequent layers must rebuild.

Optimization: order instructions from least-changing to most-changing:

```dockerfile
COPY requirements.txt .       # changes rarely → cached
RUN pip install -r requirements.txt  # expensive, cached unless requirements change
COPY . .                      # changes frequently → only this layer rebuilds
```

---

## 🌐 Networking

---

**Q: What is the difference between the default bridge and a custom bridge network?**

The **default bridge** (docker0) is created automatically. Containers on it can communicate by IP address but NOT by name — there's no DNS resolution.

A **custom bridge** network (user-defined) provides automatic DNS — containers find each other by service name. This is essential for multi-container applications.

```bash
# Default bridge — name resolution FAILS
docker run -d --name db postgres
docker run -d --name app myapp
docker exec app ping db     # FAILS — no DNS on default bridge

# Custom bridge — name resolution WORKS
docker network create mynet
docker run -d --name db --network mynet postgres
docker run -d --name app --network mynet myapp
docker exec app ping db     # WORKS — DNS resolves "db" to postgres IP
```

Always use custom networks for production. The default bridge is a legacy feature.

---

**Q: What is `--network host` and when would you use it?**

`--network host` makes the container share the host's network stack — no isolation. The container's processes see the same network interfaces as the host, no port mapping is needed.

Use cases: network monitoring tools, performance-critical apps where NAT overhead matters, legacy apps that require specific ports.

Avoid it in production for most apps — it breaks network isolation. A compromised container with host networking has direct access to the host's network.

---

## 💾 Storage

---

**Q: What is the difference between a volume and a bind mount?**

A **volume** is managed by Docker — stored at `/var/lib/docker/volumes/`. Docker handles its lifecycle. Volumes are portable (work on any host), have better performance on non-Linux (Docker Desktop), and are the recommended way to persist data.

A **bind mount** links a specific host path into the container. The host filesystem path must exist. Changes from inside the container are immediately visible on the host and vice versa.

Use volumes for production databases and persistent data. Use bind mounts for development (live code reload) and when you need the host to read/write specific files.

---

**Q: What happens to data when a container is stopped? When it's deleted?**

When **stopped**: the container's writable layer is preserved. You can restart the container and all data written to the container filesystem is still there.

When **deleted**: the writable layer is gone. All data written to the container filesystem is lost permanently.

This is why persistent data (databases, uploaded files) must be stored in volumes or bind mounts — not inside the container's writable layer.

---

## 🔐 Security

---

**Q: What are the biggest Docker security risks and how do you mitigate them?**

1. **Running as root** — most images run as root by default. Add `USER nonroot` in Dockerfile or `--user` at runtime.

2. **Image vulnerabilities** — base images and dependencies have CVEs. Scan regularly with Trivy, use minimal base images (alpine, distroless), keep images updated.

3. **Secrets in images** — secrets baked into ENV or image layers are visible in `docker history`. Use BuildKit secret mounts, runtime secrets, or external secret managers.

4. **Privileged containers** — `--privileged` gives containers nearly full host access. Never use in production.

5. **Docker socket exposure** — mounting `/var/run/docker.sock` gives container root access to the host. Avoid unless absolutely necessary.

6. **Excessive capabilities** — use `--cap-drop ALL --cap-add <only-what-you-need>`.

---

**Q: What is the difference between `--privileged` and adding capabilities?**

`--privileged` gives the container **all** Linux capabilities plus access to all host devices. It essentially removes container isolation — a process in a privileged container can do almost anything the host root can do.

Adding specific capabilities (`--cap-add NET_ADMIN`) grants only the specific permission needed. This follows the principle of least privilege — only grant what the application actually needs.

Never use `--privileged` in production. If you think you need it, you probably need a specific capability instead.

---

## ⚙️ Runtime & Architecture

---

**Q: What is containerd and how does it relate to Docker?**

containerd is a high-level container runtime that manages the full container lifecycle: pulling images, managing storage and networking, and calling low-level runtimes (like runc) to actually create containers.

Docker uses containerd internally — dockerd talks to containerd, which calls runc. Kubernetes also uses containerd directly via the CRI (Container Runtime Interface), bypassing Docker entirely.

The stack: Docker CLI → dockerd → containerd → runc → Linux kernel.

---

**Q: Why did Kubernetes deprecate Docker support?**

Kubernetes deprecated the `dockershim` (the shim that let Kubernetes talk to Docker) in 1.20 and removed it in 1.24. This doesn't mean Docker images stopped working — the OCI image format is standard.

The reason: maintaining dockershim was extra complexity. Kubernetes communicates with container runtimes via CRI (Container Runtime Interface). Docker didn't implement CRI natively, requiring the shim. containerd and CRI-O do implement CRI natively — so Kubernetes can talk to them directly, eliminating the extra layer.

Your Dockerfiles and Docker images work unchanged on Kubernetes — they use the OCI standard which containerd supports.

---

**Q: What is the OCI standard?**

OCI (Open Container Initiative) is an open standard for container images and runtimes. It has two specs:

**Image Spec** — defines how container images are structured (layers, manifest, configuration). Any OCI-compliant image works with any OCI-compliant runtime — Docker images work on containerd, CRI-O, etc.

**Runtime Spec** — defines how containers should be created from an image (what namespaces, cgroups, capabilities to apply). runc is the reference implementation.

The OCI standard is why you can build with Docker and run on Kubernetes (containerd) without any changes.

---

## 🔥 Scenario-Based Questions

---

**Scenario 1: Your Docker image is 2GB. How do you reduce its size?**

```
1. Use multi-stage builds
   Builder stage: includes compiler, build tools
   Final stage: only the compiled binary + runtime dependencies
   → Typically reduces size by 10-100x for compiled languages

2. Use a minimal base image
   ubuntu (70MB) → ubuntu:slim (30MB) → alpine (5MB) → distroless (20MB) → scratch (0MB)
   Choose based on what you need (shell, package manager, libc)

3. Combine RUN instructions and clean up in the same layer
   RUN apt-get update && apt-get install -y nginx && rm -rf /var/lib/apt/lists/*
   (cleanup in separate RUN doesn't save space — layer already committed)

4. Use .dockerignore to exclude unnecessary files
   node_modules/, .git/, tests/, docs/, *.md

5. Remove dev dependencies
   npm ci --only=production
   pip install --no-dev
   go build with -ldflags="-s -w" (strip debug info)

6. Use dive to identify large layers
   dive my-app:latest
```

---

**Scenario 2: Container starts but app crashes immediately. How do you debug?**

```
1. Check exit code and logs
   docker ps -a          # see exit code in STATUS column
   docker logs my-app    # see what the app printed before dying
   docker logs my-app --previous  # logs from the crashed instance

2. Inspect the container
   docker inspect my-app | grep -E "ExitCode|Error|OOMKilled"
   # OOMKilled: true → increase memory limit
   # ExitCode: 137 → SIGKILL (OOM or manual kill)
   # ExitCode: 1 → app error (check logs)

3. Override the command to get a shell
   docker run -it --entrypoint /bin/sh my-app
   # If image has no shell (distroless): add a debug stage
   docker build --target debug -t my-app:debug .

4. Check environment variables
   docker run --entrypoint env my-app
   # Is the app getting the config it expects?

5. Check if it needs a service to connect to
   docker run --network my-network my-app
   # Can it reach the database/redis?

6. Run with verbose logging
   docker run -e LOG_LEVEL=debug my-app
```

---

**Scenario 3: Two containers need to communicate but they're on different Docker Compose projects. How?**

```
Option 1: Create an external network
  docker network create shared-network

  # In project A's compose.yaml:
  networks:
    shared-network:
      external: true

  # In project B's compose.yaml:
  networks:
    shared-network:
      external: true

  # Services in both projects can now reach each other by name

Option 2: Connect containers manually
  docker network connect shared-network project-a-service-1
  docker network connect shared-network project-b-service-1

Option 3: Use a single compose.yaml for both
  Best for tightly coupled services — merge them into one project
```

---

**Scenario 4: Your CI builds are slow. How do you speed them up?**

```
1. Use BuildKit cache mounts
   RUN --mount=type=cache,target=/root/.cache/pip pip install -r requirements.txt
   → pip cache persists between builds without being in the image

2. Use registry cache
   docker buildx build \
     --cache-from type=registry,ref=myregistry/cache:latest \
     --cache-to type=registry,ref=myregistry/cache:latest,mode=max \
     .

3. Use GitHub Actions cache
   cache-from: type=gha
   cache-to: type=gha,mode=max

4. Optimize Dockerfile layer ordering
   → Dependency files (requirements.txt, package.json) before application code
   → Infrequently-changing layers before frequently-changing ones

5. Build only what changed
   → Use matrix builds for multiple platforms
   → Don't rebuild if Dockerfile and source didn't change

6. Use a faster build machine
   → GitHub Actions: ubuntu-latest is free but slow
   → Self-hosted runner on a larger instance
   → Use --parallel flag in compose
```

---

## 🧠 Advanced Questions

---

**Q: How does Docker networking work at the Linux level?**

When you create a custom bridge network, Docker creates a Linux bridge interface (`br-<id>`). Each container gets a veth pair — one end in the container's network namespace, one end attached to the bridge.

Traffic between containers: goes through the bridge interface, handled by the kernel's network stack. No userspace involvement — it's fast.

Port mapping: Docker creates iptables DNAT rules. Incoming traffic on host port 8080 is redirected to the container's IP:80 by iptables before the packet reaches any process.

DNS: Docker runs an embedded DNS server at 127.0.0.11 in each container's resolv.conf. It responds to container name queries with the container's IP.

---

**Q: What is BuildKit and what problems does it solve over the classic builder?**

BuildKit is Docker's next-generation build engine. It solves several problems:

**Parallel execution** — independent stages in multi-stage builds run in parallel. Classic builder is strictly sequential.

**Cache mounts** — persist package manager caches (pip, npm, apt) between builds without including them in the image. Classic builder has no concept of this.

**Secret mounts** — inject secrets at build time without including them in any layer. Classic builder would bake secrets into layers visible in `docker history`.

**Better cache** — cache is based on content hash, not just instruction text. Detects actual file changes, not just timestamps.

**Multi-platform** — native support for building for multiple architectures. Classic builder needs QEMU emulation.

---

## 💬 Questions to Ask the Interviewer

**On their Docker usage:**
- "Do you use Docker Compose for local development or do you run everything in Kubernetes?"
- "Are you using Docker's BuildKit features like cache mounts and secret mounts in your CI pipelines?"
- "What registry do you use — ECR, GHCR, or self-hosted?"

**On their practices:**
- "Do you scan Docker images for vulnerabilities in your CI pipeline? Which tool?"
- "How do you handle base image updates — manually or automated (Renovate, Dependabot)?"
- "Do your containers run as non-root? Is that enforced by policy?"

**On their challenges:**
- "What's been your biggest Docker incident in production?"
- "How do you handle secret injection into containers — environment variables, Vault, or something else?"

---

*Good luck — Docker knowledge this deep puts you ahead of most candidates. 🚀*
