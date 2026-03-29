# 🏃 GitLab Runners

Registration, executor types, autoscaling, and managing your own runner fleet.

---

## 📚 Table of Contents

- [1. What is a Runner?](#1-what-is-a-runner)
- [2. Runner Types & Scope](#2-runner-types--scope)
- [3. Registering a Runner](#3-registering-a-runner)
- [4. Executor Types](#4-executor-types)
- [5. Docker Executor (Most Common)](#5-docker-executor-most-common)
- [6. Kubernetes Executor](#6-kubernetes-executor)
- [7. Autoscaling Runners](#7-autoscaling-runners)
- [8. Runner Configuration (config.toml)](#8-runner-configuration-configtoml)
- [9. Runner Tags & Selection](#9-runner-tags--selection)
- [10. Runner Best Practices](#10-runner-best-practices)
- [Cheatsheet](#cheatsheet)

---

## 1. What is a Runner?

A GitLab Runner is an agent that picks up jobs from GitLab and executes them. It's a standalone application (written in Go) that runs on any machine — your laptop, a VM, a Kubernetes cluster.

```
GitLab Server                    Runner
     │                             │
     │  "Job available"            │
     │─────────────────────────────►│
     │                             │
     │                    Picks up job
     │                    Executes commands
     │                    Sends logs back
     │                             │
     │◄─────────────────────────────│
     │  "Job complete + artifacts"  │
```

---

## 2. Runner Types & Scope

### By scope

| Type | Available to | Best for |
|------|-------------|---------|
| **Shared runners** | All projects on the GitLab instance | General workloads |
| **Group runners** | All projects in a group | Team-shared setup |
| **Project runners** | One project only | Project-specific needs |

### By host

| Host | Description |
|------|-------------|
| **GitLab.com shared** | Managed by GitLab, free tier available |
| **Self-hosted** | You manage the runner on your infrastructure |

---

## 3. Registering a Runner

### Install GitLab Runner

```bash
# Ubuntu/Debian
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
sudo apt install gitlab-runner

# RHEL/CentOS
curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.rpm.sh" | sudo bash
sudo yum install gitlab-runner

# macOS
brew install gitlab-runner
brew services start gitlab-runner

# Docker
docker run -d --name gitlab-runner --restart always \
  -v /srv/gitlab-runner/config:/etc/gitlab-runner \
  -v /var/run/docker.sock:/var/run/docker.sock \
  gitlab/gitlab-runner:latest

# Check version
gitlab-runner --version
```

### Register a runner

```bash
# Interactive registration
gitlab-runner register

# Prompts:
# GitLab instance URL: https://gitlab.com
# Registration token:  (from Settings → CI/CD → Runners)
# Runner description: my-docker-runner
# Tags:               docker,linux,eu-central
# Executor:           docker
# Default image:      ubuntu:22.04

# Non-interactive (for automation)
gitlab-runner register \
  --non-interactive \
  --url "https://gitlab.com" \
  --registration-token "TOKEN" \
  --executor docker \
  --docker-image "ubuntu:22.04" \
  --description "my-docker-runner" \
  --tag-list "docker,linux" \
  --run-untagged true \
  --locked false

# New authentication token method (GitLab 16+)
gitlab-runner register \
  --url "https://gitlab.com" \
  --token "glrt-TOKEN" \   # runner authentication token
  --executor docker \
  --docker-image "ubuntu:22.04"
```

### Where to find the registration token

```
Project runner:   Settings → CI/CD → Runners → New project runner
Group runner:     Group → Settings → CI/CD → Runners
Instance runner:  Admin area → CI/CD → Runners (admin only)
```

---

## 4. Executor Types

### Comparison

| Executor | Isolation | Speed | Best for |
|---------|-----------|-------|---------|
| `docker` | Container per job | Fast | Most workloads |
| `shell` | No isolation | Fastest | Simple scripts, legacy |
| `kubernetes` | Pod per job | Fast | Cloud-native, autoscaling |
| `docker+machine` | VM per job (auto-provisioned) | Slower | Autoscaling on cloud |
| `virtualbox` | VM per job | Slow | Cross-OS testing |
| `parallels` | VM per job | Slow | macOS testing |
| `ssh` | Remote machine | Varies | Remote deployment |
| `custom` | Your implementation | Varies | Special requirements |

---

## 5. Docker Executor (Most Common)

Each job runs in a fresh Docker container. Clean, isolated, reproducible.

### How it works

```
Job starts
    │
    ▼
Runner pulls the image specified in job's `image:`
    │
    ▼
Creates a container from the image
    │
    ▼
Mounts: repo clone, cache, artifacts
    │
    ▼
Runs before_script, script, after_script
    │
    ▼
Uploads artifacts
    │
    ▼
Container destroyed
```

### Docker executor configuration

```toml
# /etc/gitlab-runner/config.toml
[[runners]]
  name = "my-docker-runner"
  url = "https://gitlab.com"
  token = "TOKEN"
  executor = "docker"

  [runners.docker]
    image = "ubuntu:22.04"           # default image
    privileged = false               # don't allow privileged containers
    disable_entrypoint_overwrite = false
    oom_kill_disable = false
    disable_cache = false
    volumes = [
      "/cache",                       # cache volume
      "/var/run/docker.sock:/var/run/docker.sock"  # Docker-in-Docker
    ]
    shm_size = 0
    pull_policy = ["always", "if-not-present"]   # pull behavior
    allowed_images = ["*"]           # restrict allowed images
    allowed_services = ["postgres:*", "redis:*"]  # restrict services
    memory = "4g"
    memory_swap = "4g"
    cpus = "2"
```

### Docker-in-Docker (DinD) — building Docker images

```yaml
# Method 1: Docker socket binding (easier, less isolated)
build:
  image: docker:24
  variables:
    DOCKER_HOST: unix:///var/run/docker.sock   # use host Docker daemon
  script:
    - docker build -t my-image .
  # Requires: volumes = ["/var/run/docker.sock:/var/run/docker.sock"] in runner config

# Method 2: Docker-in-Docker service (more isolated)
build:
  image: docker:24
  services:
    - docker:24-dind
  variables:
    DOCKER_TLS_CERTDIR: "/certs"
    DOCKER_DRIVER: overlay2
  script:
    - docker build -t my-image .
  # Requires: privileged = true in runner config
```

---

## 6. Kubernetes Executor

Each job runs as a Kubernetes pod. Best for cloud-native environments with autoscaling.

### Install GitLab Runner on Kubernetes

```bash
helm repo add gitlab https://charts.gitlab.io
helm install gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab-runner \
  --create-namespace \
  --set gitlabUrl=https://gitlab.com \
  --set runnerToken=glrt-TOKEN \
  --set rbac.create=true \
  --set runners.privileged=true \    # for DinD
  --set runners.tags="kubernetes,docker"
```

### Kubernetes executor configuration

```toml
[[runners]]
  name = "k8s-runner"
  url = "https://gitlab.com"
  token = "TOKEN"
  executor = "kubernetes"

  [runners.kubernetes]
    host = ""                          # uses in-cluster config
    namespace = "gitlab-runners"       # namespace for job pods
    image = "ubuntu:22.04"             # default image
    privileged = false
    cpu_request = "100m"
    cpu_limit = "2"
    memory_request = "128Mi"
    memory_limit = "2Gi"
    service_cpu_request = "100m"
    service_cpu_limit = "1"
    service_memory_request = "64Mi"
    service_memory_limit = "512Mi"
    pull_policy = "if-not-present"

    [[runners.kubernetes.volumes.host_path]]
      name = "docker"
      mount_path = "/var/run/docker.sock"
      host_path = "/var/run/docker.sock"
```

### Job pod configuration from .gitlab-ci.yml

```yaml
build:
  image: docker:24
  variables:
    KUBERNETES_CPU_REQUEST: "500m"
    KUBERNETES_MEMORY_REQUEST: "512Mi"
    KUBERNETES_CPU_LIMIT: "2"
    KUBERNETES_MEMORY_LIMIT: "4Gi"
    KUBERNETES_NODE_SELECTOR: "node-type=build"
  script:
    - docker build .
```

---

## 7. Autoscaling Runners

Runners that provision new machines on demand and terminate them when idle.

### docker+machine executor (AWS)

```toml
[[runners]]
  name = "autoscale-runner"
  executor = "docker+machine"
  limit = 20                          # max concurrent jobs

  [runners.machine]
    idle_nodes = 0                    # keep 0 machines idle (cost saving)
    idle_time = 300                   # terminate after 5 min idle
    max_growth_rate = 5               # add max 5 machines/minute

    machine_driver = "amazonec2"
    machine_name = "gitlab-runner-%s"

    machine_options = [
      "amazonec2-access-key=ACCESS_KEY",
      "amazonec2-secret-key=SECRET_KEY",
      "amazonec2-region=eu-central-1",
      "amazonec2-vpc-id=vpc-abc123",
      "amazonec2-subnet-id=subnet-abc123",
      "amazonec2-instance-type=t3.large",
      "amazonec2-ami=ami-ubuntu-22.04",
      "amazonec2-root-size=50",
      "amazonec2-tags=role,gitlab-runner",
    ]

    [[runners.machine.autoscaling]]
      periods = ["* * 8-18 * * mon-fri *"]  # 8am-6pm weekdays
      idle_count = 2                         # keep 2 warm during business hours
      idle_time = 3600
```

### Kubernetes executor autoscaling (Karpenter/Cluster Autoscaler)

```
When job arrives:
  1. Runner creates a pod request
  2. Pod is unschedulable (no nodes with capacity)
  3. Cluster Autoscaler detects unschedulable pod
  4. Provisions new node
  5. Pod scheduled on new node
  6. Job runs
  7. Pod completes, node eventually scales down

This is automatic — no special runner config needed.
Just deploy the runner on Kubernetes with appropriate pod resource requests.
```

---

## 8. Runner Configuration (config.toml)

```toml
# /etc/gitlab-runner/config.toml — full example

concurrent = 4              # max jobs running simultaneously
check_interval = 3          # how often to poll for new jobs (seconds)
log_level = "info"
log_format = "json"
shutdown_timeout = 30

[session_server]
  session_timeout = 1800    # interactive web terminal session timeout

[[runners]]
  name = "production-runner"
  url = "https://gitlab.company.com"
  token = "TOKEN"
  executor = "docker"
  environment = [           # extra environment variables for all jobs
    "DOCKER_DRIVER=overlay2",
    "AWS_DEFAULT_REGION=eu-central-1",
  ]
  pre_build_script = "echo 'Starting job on $HOSTNAME'"
  post_build_script = "echo 'Job done'"
  pre_clone_script = ""
  clone_url = ""

  [runners.docker]
    image = "ubuntu:22.04"
    privileged = false
    volumes = ["/cache:/cache:rw"]
    network_mode = "bridge"
    dns = ["8.8.8.8"]
    extra_hosts = ["internal.company.com:10.0.0.5"]
    pull_policy = ["always"]
    allowed_images = ["*"]
    memory = "4g"
    cpus = "2"

  [runners.cache]
    Type = "s3"
    Shared = true          # share cache between runners
    [runners.cache.s3]
      ServerAddress = "s3.amazonaws.com"
      BucketName = "my-gitlab-runner-cache"
      BucketLocation = "eu-central-1"
      AuthenticationType = "iam"   # use EC2 instance role
```

---

## 9. Runner Tags & Selection

Tags let you route jobs to specific runners.

```yaml
# In .gitlab-ci.yml — select runner by tags
build-gpu:
  tags:
    - gpu            # runs on runner with "gpu" tag
    - linux          # AND "linux" tag

deploy-prod:
  tags:
    - production     # production-grade runner with right access

# No tags = runs on any runner (including shared)
unit-tests:
  script: pytest
```

```
Runner registration: --tag-list "docker,linux,eu-west,4cpu"
Job tags:            [docker, linux]  → matches
Job tags:            [docker, gpu]    → does NOT match (no gpu tag on runner)
```

### Run untagged jobs

```toml
# In config.toml
[[runners]]
  run_untagged = true   # picks up jobs with no tags
```

---

## 10. Runner Best Practices

```
Security:
✅ Don't use privileged mode unless needed for DinD
✅ Use specific allowed_images (don't allow all images)
✅ Use instance IAM roles (not hardcoded AWS keys)
✅ Rotate runner tokens regularly
✅ Run runners in isolated network (VPC)
✅ Use protected runners for production deployments

Performance:
✅ Set appropriate concurrent limits (CPU * 2 for I/O-bound jobs)
✅ Configure cache on S3/GCS (shared between runners)
✅ Use pull_policy: if-not-present for large images
✅ Set reasonable memory/CPU limits

Reliability:
✅ Run multiple runner instances (no single point of failure)
✅ Set retry.max for transient failures
✅ Monitor runner queue depth and wait times
✅ Use autoscaling to handle load spikes

Maintenance:
✅ Keep gitlab-runner binary updated
✅ Clean up Docker images periodically (docker system prune)
✅ Monitor disk usage (logs, images, cache)
```

---

## Cheatsheet

```bash
# Install
apt install gitlab-runner

# Register
gitlab-runner register \
  --url https://gitlab.com \
  --token glrt-TOKEN \
  --executor docker \
  --docker-image ubuntu:22.04

# Manage service
gitlab-runner start
gitlab-runner stop
gitlab-runner restart
gitlab-runner status

# List registered runners
gitlab-runner list

# Run a job locally (test without pushing)
gitlab-runner exec docker my-job-name

# View config
cat /etc/gitlab-runner/config.toml

# Unregister
gitlab-runner unregister --url https://gitlab.com --token TOKEN
gitlab-runner unregister --all-runners

# Docker runner — clean up
docker exec gitlab-runner gitlab-runner verify   # check runner connectivity
```

---

*Next: [Variables & Secrets →](./04-variables-secrets.md)*
