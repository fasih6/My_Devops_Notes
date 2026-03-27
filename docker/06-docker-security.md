# 🔐 Docker Security

Rootless containers, capabilities, seccomp, image scanning, and hardening your Docker setup.

---

## 📚 Table of Contents

- [1. Container Security Model](#1-container-security-model)
- [2. Running as Non-Root](#2-running-as-non-root)
- [3. Linux Capabilities](#3-linux-capabilities)
- [4. Seccomp Profiles](#4-seccomp-profiles)
- [5. Read-Only Filesystems](#5-read-only-filesystems)
- [6. Rootless Docker](#6-rootless-docker)
- [7. Image Security & Scanning](#7-image-security--scanning)
- [8. Secrets Management](#8-secrets-management)
- [9. Docker Daemon Security](#9-docker-daemon-security)
- [10. Security Checklist](#10-security-checklist)
- [Cheatsheet](#cheatsheet)

---

## 1. Container Security Model

Containers are NOT VMs — they share the host kernel. A container escape can compromise the host.

```
VM isolation:                Container isolation:
┌─────────────────┐          ┌─────────────────┐
│  App            │          │  App            │
│  OS (full)      │          │  Container libs │
│  Hypervisor     │          ├─────────────────┤
│  Hardware       │          │  Shared kernel  │ ← same kernel as host
└─────────────────┘          │  Host hardware  │
                             └─────────────────┘
```

### Attack surface

1. **Container escape** — breaking out of the container to the host
2. **Image vulnerabilities** — CVEs in base image or dependencies
3. **Secrets leakage** — secrets baked into images or logs
4. **Privilege escalation** — container gaining more host access
5. **Resource abuse** — container consuming all host resources

---

## 2. Running as Non-Root

The most important security practice. Containers run as root by default — that's dangerous.

```dockerfile
# In Dockerfile — create and use non-root user
FROM ubuntu:22.04

# Create system user (no home, no login shell)
RUN groupadd -r appgroup && \
    useradd -r -g appgroup -d /app -s /sbin/nologin app

WORKDIR /app
COPY --chown=app:appgroup . .

# Switch to non-root user
USER app

CMD ["./server"]
```

```dockerfile
# Alpine
RUN addgroup -S appgroup && adduser -S app -G appgroup
USER app
```

```bash
# Override at runtime (if image runs as root)
docker run --user 1000:1000 my-app
docker run --user nobody my-app

# Check what user a container runs as
docker inspect my-container | grep User
docker exec my-container whoami
docker exec my-container id
```

### Why root in containers is dangerous

```bash
# If container runs as root and mounts host files:
docker run --rm -v /etc:/host-etc alpine cat /host-etc/shadow
# Can read host's /etc/shadow!

# With non-root user:
docker run --rm --user 1000 -v /etc:/host-etc alpine cat /host-etc/shadow
# Permission denied — protected
```

---

## 3. Linux Capabilities

Instead of all-or-nothing root, Linux has ~40 capabilities. Docker drops most by default.

### Default capabilities Docker keeps

```
AUDIT_WRITE, CHOWN, DAC_OVERRIDE, FOWNER, FSETID,
KILL, MKNOD, NET_BIND_SERVICE, NET_RAW, SETFCAP,
SETGID, SETPCAP, SETUID, SYS_CHROOT
```

### Drop all, add only what's needed

```bash
# Drop ALL capabilities (most secure)
docker run --cap-drop ALL my-app

# Add back only what you need
docker run --cap-drop ALL \
           --cap-add NET_BIND_SERVICE \   # bind to port < 1024
           my-app

# Never use --privileged in production
docker run --privileged my-app    # gives ALL capabilities + access to all devices — DANGEROUS
```

```yaml
# In docker compose
services:
  api:
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true   # can't gain more capabilities via setuid binaries
```

### Common capabilities and when you need them

| Capability | When needed |
|-----------|------------|
| `NET_BIND_SERVICE` | Bind to ports < 1024 (better: use port > 1024 and map) |
| `NET_ADMIN` | Configure network interfaces, iptables |
| `SYS_PTRACE` | Debugging tools (strace, gdb) — only in dev |
| `SYS_ADMIN` | Many syscalls — very powerful, avoid |
| `CHOWN` | Change file ownership |
| `DAC_OVERRIDE` | Override file permissions |

---

## 4. Seccomp Profiles

Seccomp (Secure Computing Mode) restricts which system calls a container can make. Docker applies a default seccomp profile that blocks ~44 dangerous syscalls.

```bash
# Check if seccomp is enabled
docker info | grep seccomp

# Run without default seccomp (dangerous — only for debugging)
docker run --security-opt seccomp=unconfined my-app

# Apply custom seccomp profile
docker run --security-opt seccomp=/path/to/profile.json my-app
```

### Custom seccomp profile

```json
{
  "defaultAction": "SCMP_ACT_ERRNO",
  "syscalls": [
    {
      "names": [
        "read", "write", "open", "close",
        "stat", "fstat", "lstat",
        "poll", "lseek", "mmap", "mprotect",
        "munmap", "brk", "rt_sigaction",
        "rt_sigprocmask", "rt_sigreturn",
        "ioctl", "access", "pipe",
        "select", "sched_yield", "mremap",
        "socket", "connect", "accept",
        "sendto", "recvfrom", "sendmsg",
        "recvmsg", "bind", "listen",
        "getsockname", "getpeername",
        "exit", "wait4", "kill",
        "getpid", "getuid", "getgid",
        "clone", "fork", "execve",
        "exit_group", "epoll_wait",
        "epoll_ctl", "tgkill", "openat",
        "getdents64", "set_robust_list",
        "futex", "set_tid_address",
        "clock_gettime", "clock_nanosleep"
      ],
      "action": "SCMP_ACT_ALLOW"
    }
  ]
}
```

---

## 5. Read-Only Filesystems

Making the root filesystem read-only prevents malware from writing files to the container.

```bash
# Read-only root filesystem
docker run --read-only \
  --tmpfs /tmp \            # writable /tmp in memory
  --tmpfs /var/run \        # writable /var/run for sockets/PIDs
  -v app-logs:/var/log/app \ # writable log volume
  my-app
```

```yaml
# In docker compose
services:
  api:
    read_only: true
    tmpfs:
      - /tmp:rw,noexec,nosuid,size=100m
      - /var/run
    volumes:
      - app-logs:/var/log/app
```

```dockerfile
# In Dockerfile — make app code read-only
COPY --chmod=444 . /app    # read-only by all
```

---

## 6. Rootless Docker

Run the Docker daemon itself as a non-root user — if the daemon is compromised, it can't affect the host's root files.

```bash
# Install rootless Docker (Ubuntu)
dockerd-rootless-setuptool.sh install

# Start rootless daemon
systemctl --user start docker

# Use rootless docker
export DOCKER_HOST=unix://$XDG_RUNTIME_DIR/docker.sock
docker run hello-world

# Check it's rootless
docker info | grep "rootless"
```

### Rootless limitations

- No binding to ports < 1024 without workaround
- Some networking features limited
- Performance slightly lower
- Better: use rootless containers with rootful daemon (USER in Dockerfile)

---

## 7. Image Security & Scanning

### Scan with Trivy (most popular, open source)

```bash
# Install Trivy
brew install aquasecurity/trivy/trivy     # macOS
apt install trivy                          # Ubuntu

# Scan image for vulnerabilities
trivy image nginx:1.24
trivy image --severity HIGH,CRITICAL nginx:1.24

# Scan before pushing
trivy image --exit-code 1 --severity CRITICAL my-app:latest
# Exit code 1 if CRITICAL vulnerabilities found — fails CI

# Scan local filesystem
trivy fs .

# Scan Dockerfile
trivy config Dockerfile

# Output formats
trivy image --format json my-app > report.json
trivy image --format sarif my-app > results.sarif  # GitHub SARIF format
```

### Scan in CI/CD (GitHub Actions)

```yaml
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: my-app:${{ github.sha }}
    format: sarif
    output: trivy-results.sarif
    severity: CRITICAL,HIGH
    exit-code: 1     # fail if vulnerabilities found

- name: Upload Trivy results to GitHub Security
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: trivy-results.sarif
```

### Other scanning tools

```bash
# Docker Scout (built into Docker Desktop)
docker scout cves my-app:latest
docker scout recommendations my-app:latest

# Grype
grype my-app:latest

# Snyk
snyk container test my-app:latest
```

### Keep images small = smaller attack surface

```bash
# Check image layers and size contributors
docker history my-app --no-trunc
dive my-app                     # interactive layer explorer (brew install dive)

# Minimize dependencies
# Use slim/alpine base images
# Remove build tools in final stage (multi-stage builds)
```

---

## 8. Secrets Management

### Never bake secrets into images

```dockerfile
# BAD — secret in build arg (visible in docker history)
ARG API_KEY
ENV API_KEY=${API_KEY}

# BAD — secret in COPY
COPY .env /app/.env

# GOOD — use BuildKit secrets (not in layers)
RUN --mount=type=secret,id=api_key \
    export API_KEY=$(cat /run/secrets/api_key) && \
    ./configure.sh

# Build with:
docker build --secret id=api_key,src=./api_key.txt .
```

### Runtime secrets

```bash
# Pass secrets as environment variables (acceptable for non-sensitive)
docker run -e DB_PASSWORD=$DB_PASSWORD my-app

# Use Docker secrets (Swarm mode)
echo "my-secret" | docker secret create db_password -
docker service create \
  --secret db_password \
  my-app
# Available at: /run/secrets/db_password

# Use external secrets (production best practice)
# → AWS Secrets Manager via environment injection
# → HashiCorp Vault via sidecar
# → Kubernetes Secrets (when on K8s)
```

### Check for secrets in images

```bash
# Scan for secrets accidentally left in images
trivy image --scanners secret my-app:latest

# Or use dedicated tools
docker run --rm -v /var/lib/docker:/var/lib/docker:ro \
  trufflesecurity/trufflehog:latest docker --image my-app:latest
```

---

## 9. Docker Daemon Security

```json
// /etc/docker/daemon.json — secure daemon config
{
  "live-restore": true,         // containers survive daemon restart
  "userland-proxy": false,      // use iptables instead of userland proxy
  "no-new-privileges": true,    // global default for all containers
  "seccomp-profile": "/etc/docker/seccomp.json",
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "5"
  },
  "storage-driver": "overlay2",
  "icc": false                  // disable inter-container communication by default
}
```

```bash
# Restrict Docker socket access
# Docker socket (/var/run/docker.sock) = root access to the host
# Never mount it in containers unless absolutely necessary

# If you must use Docker-in-Docker:
# Use rootless Docker or dedicated DIND images
```

---

## 10. Security Checklist

```
Image:
✅ Pin base image to specific version (not latest)
✅ Use minimal base image (distroless, alpine, slim)
✅ Multi-stage builds — no build tools in final image
✅ Scan for vulnerabilities (Trivy) in CI/CD
✅ No secrets in Dockerfile, ENV, or build args
✅ Remove unnecessary packages and files

Runtime:
✅ Run as non-root user (USER in Dockerfile or --user flag)
✅ Drop ALL capabilities, add only what's needed
✅ Add --no-new-privileges
✅ Use read-only root filesystem (--read-only)
✅ Set resource limits (--memory, --cpus)
✅ Don't use --privileged
✅ Don't mount Docker socket

Networking:
✅ Use custom bridge networks (not default bridge)
✅ Expose only required ports
✅ Use internal: true for backend networks
✅ Don't use --network host in production

Data:
✅ Use volumes, not bind mounts to sensitive host directories
✅ Use tmpfs for sensitive in-memory data
✅ Never store secrets in volumes without encryption

Daemon:
✅ Restrict Docker socket access
✅ Enable live-restore
✅ Configure logging with size limits
✅ Use TLS for remote Docker API (if needed)
```

---

## Cheatsheet

```bash
# Run securely
docker run \
  --user 1000:1000 \
  --cap-drop ALL \
  --cap-add NET_BIND_SERVICE \
  --security-opt no-new-privileges:true \
  --read-only \
  --tmpfs /tmp \
  --memory 256m \
  --cpus 0.5 \
  my-app

# Scan image
trivy image my-app:latest
trivy image --severity HIGH,CRITICAL my-app:latest
trivy image --exit-code 1 --severity CRITICAL my-app:latest

# Check container security
docker inspect my-container | grep -E "User|Privileged|Cap"
docker exec my-container whoami
docker exec my-container cat /proc/1/status | grep Cap

# BuildKit secrets
docker build --secret id=mykey,src=./secret.txt .
```

---

*Next: [Registry & Image Management →](./07-registry-image-management.md)*
