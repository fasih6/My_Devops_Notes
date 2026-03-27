# ⚙️ Container Runtime

How containers actually run — containerd, runc, the OCI standard, and how Kubernetes fits in.

---

## 📚 Table of Contents

- [1. The Container Runtime Stack](#1-the-container-runtime-stack)
- [2. OCI Standard](#2-oci-standard)
- [3. runc — Low-Level Runtime](#3-runc--low-level-runtime)
- [4. containerd — High-Level Runtime](#4-containerd--high-level-runtime)
- [5. CRI — Container Runtime Interface](#5-cri--container-runtime-interface)
- [6. Docker vs containerd](#6-docker-vs-containerd)
- [7. crictl — Debugging on Kubernetes Nodes](#7-crictl--debugging-on-kubernetes-nodes)
- [8. Other Runtimes](#8-other-runtimes)
- [Cheatsheet](#cheatsheet)

---

## 1. The Container Runtime Stack

```
User
  │  docker run / kubectl apply
  ▼
Docker CLI / kubectl
  │
  ▼  REST API
dockerd / kubelet
  │
  ▼  gRPC (CRI)
containerd                 ← high-level runtime
  │  manages images, snapshots, networking setup
  ▼
containerd-shim            ← keeps container running if containerd restarts
  │
  ▼  OCI runtime spec
runc                       ← low-level runtime
  │  calls Linux kernel features
  ▼
Linux Kernel
  namespaces + cgroups + overlayfs
```

Each layer has a specific responsibility — this separation enables swapping components.

---

## 2. OCI Standard

The **Open Container Initiative (OCI)** defines two standards:

### Image Spec

Defines how a container image is structured — layers, manifest, configuration.

```json
// Image manifest (what's in the image)
{
  "schemaVersion": 2,
  "mediaType": "application/vnd.oci.image.manifest.v1+json",
  "config": {
    "mediaType": "application/vnd.oci.image.config.v1+json",
    "digest": "sha256:abc123...",
    "size": 7023
  },
  "layers": [
    {
      "mediaType": "application/vnd.oci.image.layer.v1.tar+gzip",
      "digest": "sha256:def456...",
      "size": 32654
    }
  ]
}
```

### Runtime Spec

Defines how a container should be run — what filesystem, namespaces, cgroups, capabilities.

```json
// config.json — OCI runtime bundle (what runc reads)
{
  "ociVersion": "1.0.0",
  "process": {
    "terminal": false,
    "user": { "uid": 1000, "gid": 1000 },
    "args": ["/app/server"],
    "env": ["APP_ENV=production"]
  },
  "root": { "path": "rootfs", "readonly": false },
  "namespaces": [
    { "type": "pid" },
    { "type": "network" },
    { "type": "mount" }
  ],
  "linux": {
    "resources": {
      "memory": { "limit": 268435456 },
      "cpu": { "quota": 50000, "period": 100000 }
    }
  }
}
```

---

## 3. runc — Low-Level Runtime

`runc` is the reference OCI runtime. It reads the OCI runtime spec and creates the container process.

```bash
# runc is usually not called directly — containerd calls it
# But you can use it manually for learning

# Create OCI bundle
mkdir mycontainer && cd mycontainer
mkdir rootfs

# Extract Ubuntu filesystem into rootfs
docker export $(docker create ubuntu) | tar -C rootfs -xf -

# Generate config.json
runc spec

# Run the container
sudo runc run mycontainer

# List running containers
sudo runc list

# Execute command in container
sudo runc exec mycontainer ls /

# Delete container
sudo runc delete mycontainer
```

### What runc does

```
runc receives OCI bundle (config.json + rootfs)
  │
  ▼
Creates namespaces (unshare syscall):
  - pid namespace: container gets own PID 1
  - net namespace: isolated network
  - mnt namespace: isolated filesystem
  - uts namespace: isolated hostname
  │
  ▼
Applies cgroups (limit CPU, memory)
  │
  ▼
Sets up overlayfs (layers → merged view)
  │
  ▼
Drops capabilities (only keep what's needed)
  │
  ▼
Applies seccomp profile (restrict syscalls)
  │
  ▼
exec() the container process
```

---

## 4. containerd — High-Level Runtime

containerd manages the full container lifecycle: image pulling, storage, networking setup, and calling runc.

```bash
# containerd CLI is ctr (low-level) or nerdctl (Docker-compatible)
sudo ctr version
sudo ctr images list
sudo ctr containers list
sudo ctr tasks list

# Pull an image with ctr
sudo ctr images pull docker.io/library/nginx:latest

# Run a container with ctr
sudo ctr run --rm docker.io/library/nginx:latest mynginx

# nerdctl — Docker-compatible CLI for containerd
brew install nerdctl    # macOS (for learning)
nerdctl run -d --name nginx nginx:latest
nerdctl ps
nerdctl logs nginx
nerdctl exec -it nginx bash
```

### containerd architecture

```
containerd
├── Content store        (image layers, blobs)
├── Snapshot service     (overlayfs layer management)
├── Diff service         (image unpacking)
├── Events service       (publish/subscribe events)
├── Namespaces           (isolation between clients like Docker, Kubernetes)
└── Task service         (running containers via shim → runc)
```

### containerd namespaces

containerd uses namespaces to separate workloads:

```bash
# Docker uses the "moby" namespace
sudo ctr --namespace moby containers list

# Kubernetes uses the "k8s.io" namespace
sudo ctr --namespace k8s.io containers list

# Default namespace
sudo ctr containers list   # = --namespace default
```

---

## 5. CRI — Container Runtime Interface

The CRI is a plugin interface that Kubernetes uses to communicate with container runtimes. Without it, Kubernetes would be locked to Docker.

```
kubelet
  │  gRPC calls
  ▼
CRI interface
  ├── ImageService   (pull, list, remove images)
  └── RuntimeService (create, start, stop, delete containers/pods)
        │
        ▼
  containerd (CRI plugin) / CRI-O
        │
        ▼
  runc (or other OCI runtime)
```

### CRI operations

```bash
# What kubelet does via CRI when scheduling a pod:
1. PullImage(nginx:1.24)
2. CreateContainer(podSandboxId, containerConfig)
3. StartContainer(containerId)
4. [Pod is running]
5. StopContainer(containerId, gracePeriod)
6. RemoveContainer(containerId)
```

---

## 6. Docker vs containerd

### How Docker relates to containerd

Docker is actually a wrapper around containerd:

```
Docker CLI
    ↓
dockerd (Docker daemon)
    ↓
containerd     ← Docker uses containerd internally
    ↓
runc
```

When Kubernetes dropped Docker support (1.24), it didn't drop containers — it just started talking to containerd directly via CRI, cutting out the dockerd layer.

### Feature comparison

| Feature | Docker | containerd |
|---------|--------|-----------|
| **CLI** | docker | ctr, nerdctl |
| **Compose** | docker compose | — (nerdctl compose) |
| **Image build** | docker build, BuildKit | nerdctl build |
| **Swarm** | Yes | No |
| **CRI** | Via dockershim (removed) | Native CRI plugin |
| **Kubernetes use** | No (deprecated) | Yes (default) |

---

## 7. crictl — Debugging on Kubernetes Nodes

`crictl` is the CLI for debugging containers on Kubernetes nodes — talks directly to containerd via CRI.

```bash
# Install crictl
VERSION="v1.28.0"
curl -L https://github.com/kubernetes-sigs/cri-tools/releases/download/$VERSION/crictl-$VERSION-linux-amd64.tar.gz \
  | tar xz
sudo mv crictl /usr/local/bin/

# Configure crictl to use containerd
cat > /etc/crictl.yaml <<EOF
runtime-endpoint: unix:///var/run/containerd/containerd.sock
image-endpoint: unix:///var/run/containerd/containerd.sock
timeout: 2
debug: false
EOF

# Commands (same as docker but for K8s node)
crictl ps                           # list running containers
crictl ps -a                        # all containers
crictl images                       # list images
crictl pods                         # list pod sandboxes

# Inspect
crictl inspect <container-id>
crictl inspecti <image-id>
crictl inspectp <pod-id>

# Logs
crictl logs <container-id>
crictl logs -f <container-id>

# Execute command
crictl exec -it <container-id> bash

# Pull/remove images
crictl pull nginx:latest
crictl rmi nginx:latest

# Stats
crictl stats
crictl stats <container-id>

# Cleanup (remove stopped containers)
crictl rm $(crictl ps -a -q --state exited)
```

### When to use crictl vs kubectl

```
kubectl logs, exec, describe → use for normal operations
crictl → use when:
  - kubelet is having issues
  - Container runtime problems
  - Node-level debugging
  - Can't use kubectl (cluster control plane is down)
```

---

## 8. Other Runtimes

### CRI-O

Lightweight CRI implementation designed specifically for Kubernetes. Used by OpenShift.

```bash
# CRI-O uses the same CLI as crictl
crictl --runtime-endpoint unix:///var/run/crio/crio.sock ps
```

### gVisor (runsc)

Google's sandbox runtime — runs containers in a user-space kernel for extra isolation.

```bash
# Install gVisor
(
  set -e
  ARCH=$(uname -m)
  URL=https://storage.googleapis.com/gvisor/releases/release/latest/${ARCH}
  wget ${URL}/runsc ${URL}/runsc.sha512
  sha512sum -c runsc.sha512
  sudo cp runsc /usr/local/bin
  sudo chmod a+rx /usr/local/bin/runsc
)

# Configure Docker to use gVisor
sudo runsc install
sudo systemctl restart docker

# Run container with gVisor
docker run --runtime=runsc nginx
```

### Kata Containers

Containers running inside lightweight VMs — combines VM isolation with container speed.

```bash
# Install kata-containers
sudo snap install kata-containers --classic

# Run with Kata
docker run --runtime kata-runtime nginx
```

### Runtime selection in Kubernetes

```yaml
# RuntimeClass — select runtime per pod
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc

---
# Use in pod
spec:
  runtimeClassName: gvisor
  containers:
    - name: app
      image: my-app
```

---

## Cheatsheet

```bash
# containerd (ctr)
sudo ctr images list
sudo ctr containers list
sudo ctr tasks list
sudo ctr --namespace k8s.io containers list    # K8s containers

# crictl (on Kubernetes nodes)
crictl ps
crictl images
crictl pods
crictl logs <container-id>
crictl exec -it <container-id> sh
crictl stats

# runc (low-level, rarely direct)
sudo runc list
sudo runc state <container-id>

# Check what runtime a container uses
docker inspect <container> | grep Runtime

# Check containerd socket
ls -la /var/run/containerd/containerd.sock
ls -la /var/run/docker.sock
```

---

*Next: [Docker in CI/CD →](./09-docker-cicd.md)*
