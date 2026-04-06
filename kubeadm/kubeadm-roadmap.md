# Kubeadm Self-Managed Kubernetes — Learning Roadmap

> **Environment:** Hetzner Cloud VMs (1x CPX21 control plane + 2x CPX22 workers)
> **OS:** Ubuntu 22.04 LTS
> **Goal:** Learn self-managed Kubernetes from scratch — cluster setup, internals, networking, storage, and production hardening

---

## Overview

| Phase | Topic | Est. Time | Difficulty |
|---|---|---|---|
| 0 | Prerequisites | 1–2 days | Beginner |
| 1 | Provision VMs on Hetzner | 1 day | Beginner |
| 2 | OS preparation | 1 day | Beginner–Medium |
| 3 | Install container runtime + k8s packages | 1 day | Medium |
| 4 | Bootstrap the control plane | 1–2 days | Medium |
| 5 | Install CNI plugin | 1–2 days | Medium |
| 6 | Join worker nodes | 1 day | Medium |
| 7 | Understand the internals | 1–2 weeks | Medium–Hard |
| 8 | Cluster operations | 1–2 weeks | Hard |
| 9 | Networking track (Flannel → Cilium) | 2–3 weeks | Hard |
| 10 | Storage track (Longhorn → Rook/Ceph) | 2–4 weeks | Hard |
| 11 | Production hardening | 2–3 weeks | Hard |
| 12 | Advanced (Talos, GitOps, Cluster API) | Ongoing | Expert |

---

## Phase 0 — Prerequisites

**Goal:** Make sure you have the foundational knowledge and accounts ready before touching a single server.

### What you need to know
- Basic Linux command line (file system navigation, permissions, systemctl, journalctl)
- SSH key generation and usage
- Basic networking concepts (IP addresses, subnets, ports, firewalls)
- What Kubernetes is at a high level (pods, nodes, deployments, services)

### What you need to set up
- Hetzner Cloud account (https://console.hetzner.cloud)
- SSH key pair generated locally (`ssh-keygen -t ed25519 -C "k8s-lab"`)
- SSH public key uploaded to Hetzner console
- `kubectl` installed on your local machine
- `hcloud` CLI installed (optional but useful)

### Key concepts to review
- How TCP/IP works (ports, routing)
- What a container runtime is (containerd vs Docker)
- The difference between a control plane and a worker node

---

## Phase 1 — Provision VMs on Hetzner

**Goal:** Spin up 3 cloud VMs that simulate a bare metal cluster. Understand how to structure a multi-node environment.

### What you will do
- Create a Hetzner Cloud project
- Provision 3 VMs with the following specs:

| Name | Role | Type | vCPU | RAM | Disk |
|---|---|---|---|---|---|
| `cp-1` | Control Plane | CPX21 | 3 | 4 GB | 80 GB |
| `worker-1` | Worker | CPX22 | 2 | 4 GB | 80 GB |
| `worker-2` | Worker | CPX22 | 2 | 4 GB | 80 GB |

- Set up a private network in Hetzner and attach all 3 VMs to it
- Configure Hetzner firewall rules (allow SSH, k8s API port 6443, and internal cluster traffic)
- Verify SSH access to all 3 nodes

### What you will learn
- How Hetzner Cloud networking works (public vs private IPs)
- Why a private network matters for cluster internal communication
- What firewall rules a Kubernetes cluster needs

### Key ports to open
- `22` — SSH (your IP only)
- `6443` — Kubernetes API server (your IP only)
- `2379-2380` — etcd (between control plane nodes only)
- `10250` — kubelet (between all nodes)
- `30000-32767` — NodePort services (optional, for testing)

---

## Phase 2 — OS Preparation (All 3 Nodes)

**Goal:** Configure the operating system on every node so it is ready to run Kubernetes. Understand why each setting exists.

### What you will do on every node

**Disable swap** — Kubernetes requires swap to be off:
```bash
swapoff -a
sed -i '/swap/d' /etc/fstab
```

**Load required kernel modules:**
```bash
cat <<EOF | tee /etc/modules-load.d/k8s.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter
```

**Set required sysctl parameters:**
```bash
cat <<EOF | tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

sysctl --system
```

**Set hostnames** (on each respective node):
```bash
hostnamectl set-hostname cp-1        # on control plane
hostnamectl set-hostname worker-1    # on worker 1
hostnamectl set-hostname worker-2    # on worker 2
```

**Update /etc/hosts on all nodes** with private IPs of all 3 nodes.

### What you will learn
- Why swap must be disabled for kubelet to work correctly
- What `br_netfilter` does and why pod networking needs it
- Why `ip_forward` is required for traffic to flow between pods
- How Linux kernel modules relate to container networking

---

## Phase 3 — Install Container Runtime + Kubernetes Packages

**Goal:** Install `containerd`, `kubelet`, `kubeadm`, and `kubectl` on all 3 nodes. Understand what each component does.

### What you will install
- `containerd` — the container runtime (replaces Docker in modern k8s)
- `runc` — low-level container runtime used by containerd
- `kubelet` — the node agent that runs on every node
- `kubeadm` — the cluster bootstrapping tool
- `kubectl` — the CLI for interacting with the cluster

### Install containerd
```bash
apt-get update
apt-get install -y containerd
mkdir -p /etc/containerd
containerd config default | tee /etc/containerd/config.toml
# Enable systemd cgroup driver (required for kubeadm)
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
systemctl restart containerd
systemctl enable containerd
```

### Install kubeadm, kubelet, kubectl
```bash
apt-get install -y apt-transport-https ca-certificates curl gpg
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.29/deb/Release.key \
  | gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg

echo 'deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] \
  https://pkgs.k8s.io/core:/stable:/v1.29/deb/ /' \
  | tee /etc/apt/sources.list.d/kubernetes.list

apt-get update
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl   # prevent accidental upgrades
```

### What you will learn
- The difference between containerd and Docker
- What `runc` does vs what containerd does (OCI runtime vs container manager)
- Why the systemd cgroup driver must match between containerd and kubelet
- What kubelet does on every node vs what kubeadm does at bootstrap time
- Why you `apt-mark hold` these packages

---

## Phase 4 — Bootstrap the Control Plane

**Goal:** Run `kubeadm init` on the control plane node. Understand what happens during cluster bootstrapping.

### What you will do
```bash
# On cp-1 only
kubeadm init \
  --pod-network-cidr=10.244.0.0/16 \
  --apiserver-advertise-address=<cp-1-private-ip> \
  --node-name=cp-1
```

**Save the join command** that kubeadm outputs — you need it for the worker nodes.

**Set up kubeconfig:**
```bash
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config
```

**Copy kubeconfig to your local machine:**
```bash
# On your laptop
scp root@<cp-1-public-ip>:/etc/kubernetes/admin.conf ~/.kube/hetzner-config
export KUBECONFIG=~/.kube/hetzner-config
kubectl get nodes
```

### What you will learn
- What `kubeadm init` actually does step by step (preflight checks, certificates, static pods, bootstrap tokens)
- What `--pod-network-cidr` is and why it matters for CNI
- What `kubeconfig` is and how it authenticates to the API server
- Why the control plane node shows `NotReady` until a CNI is installed

### Verify the control plane
```bash
kubectl get nodes                        # cp-1 shows NotReady (no CNI yet)
kubectl get pods -n kube-system          # API server, etcd, scheduler, controller-manager all running
kubectl get componentstatuses            # all components healthy
```

---

## Phase 5 — Install CNI Plugin

**Goal:** Install a CNI plugin so pods can communicate across nodes. Understand what a CNI plugin actually does.

### Option A — Flannel (start here for simplicity)
```bash
kubectl apply -f https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml
```

### Option B — Cilium (recommended after you understand the basics)
```bash
# Install Cilium CLI
curl -L --fail --remote-name-all \
  https://github.com/cilium/cilium-cli/releases/latest/download/cilium-linux-amd64.tar.gz
tar xzvf cilium-linux-amd64.tar.gz
mv cilium /usr/local/bin

# Install Cilium into the cluster
cilium install --version 1.15.0
cilium status --wait
```

### What you will learn
- What a CNI plugin is and why Kubernetes does not ship one by default
- How pod-to-pod networking works across nodes (VXLAN overlay vs direct routing)
- What happens in the network namespace when a pod starts
- With Cilium: what eBPF is and why it replaces iptables
- With Cilium: how to use Hubble UI for network observability

### Verify networking
```bash
kubectl get nodes              # cp-1 should now show Ready
kubectl run test --image=nginx --restart=Never
kubectl get pod test -o wide   # note the pod IP
kubectl exec -it test -- curl <pod-ip>
```

---

## Phase 6 — Join Worker Nodes

**Goal:** Add both worker nodes to the cluster. Understand the join process and node registration.

### What you will do
```bash
# On worker-1 and worker-2 — use the join command from kubeadm init output
kubeadm join <cp-1-private-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --node-name=worker-1     # change to worker-2 on second node
```

**If the token expired** (tokens expire after 24 hours):
```bash
# On cp-1 — generate a new join command
kubeadm token create --print-join-command
```

### What you will learn
- How bootstrap tokens work and why they expire
- What `--discovery-token-ca-cert-hash` verifies (prevents MITM attacks)
- How kubelet registers itself with the API server
- What happens when you `kubectl drain` and `kubectl cordon` a node

### Verify the cluster
```bash
kubectl get nodes -o wide          # all 3 nodes Ready
kubectl get pods -A                # all system pods running
kubectl describe node worker-1     # check capacity, allocatable, conditions
```

---

## Phase 7 — Understand the Internals

**Goal:** Go beyond just having a working cluster. Understand every component, where it runs, and how it fits together.

### Explore static pod manifests
```bash
ls /etc/kubernetes/manifests/
# kube-apiserver.yaml
# kube-controller-manager.yaml
# kube-scheduler.yaml
# etcd.yaml
```
Read each file. Understand every flag. Know what each component does.

### Explore certificates (PKI)
```bash
ls /etc/kubernetes/pki/
kubeadm certs check-expiration   # see when certs expire
```

Understand:
- What the CA cert is and why everything trusts it
- What the API server cert covers (SANs)
- How kubelet authenticates to the API server
- How `kubectl` authenticates (client certificate in kubeconfig)

### Explore etcd
```bash
# Install etcdctl
apt-get install -y etcd-client

# List all keys in etcd
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get / --prefix --keys-only

# Read a specific object (e.g. default namespace)
ETCDCTL_API=3 etcdctl ... get /registry/namespaces/default
```

### What you will learn
- How etcd stores every Kubernetes object as a key-value pair
- What happens if etcd goes down (API server becomes read-only)
- How the API server, scheduler, and controller-manager communicate
- What a watch event is (how controllers react to object changes)
- How static pods differ from regular pods

### Experiments to try
- Delete a static pod manifest — watch kubelet not restart it vs a regular pod
- Scale a deployment to 0 — watch the controller manager respond
- Check scheduler logs while a pod is pending
- `kubectl get events --sort-by=.lastTimestamp` — watch the cluster talk to itself

---

## Phase 8 — Cluster Operations

**Goal:** Learn day-2 operations: how to upgrade, backup, restore, and maintain a self-managed cluster.

### Upgrade the cluster
```bash
# On cp-1 — upgrade kubeadm first
apt-get update
apt-get install -y kubeadm=1.30.0-*

kubeadm upgrade plan               # shows what can be upgraded
kubeadm upgrade apply v1.30.0      # upgrades control plane

# Upgrade kubelet and kubectl on cp-1
kubectl drain cp-1 --ignore-daemonsets
apt-get install -y kubelet=1.30.0-* kubectl=1.30.0-*
systemctl daemon-reload && systemctl restart kubelet
kubectl uncordon cp-1

# Repeat kubelet upgrade on each worker node
```

### Backup and restore etcd
```bash
# Backup
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify backup
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot.db

# Restore (disaster recovery)
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restore
```

### Certificate rotation
```bash
kubeadm certs renew all            # renew all certificates
kubeadm certs check-expiration     # verify new expiry dates
```

### What you will learn
- How to safely upgrade a cluster without downtime (drain → upgrade → uncordon)
- Why etcd backup is the most critical operation in self-managed k8s
- What happens during etcd restore and when you need it
- How certificate expiry breaks a cluster and how to recover
- How to add and remove nodes cleanly

---

## Phase 9 — Networking Track

**Goal:** Deep-dive into Kubernetes networking. Go from basic pod connectivity to advanced CNI features and network policy.

### Step 1 — Flannel (foundation)

Install Flannel and explore how it works:
- How VXLAN encapsulation sends pod traffic across nodes
- What a network namespace is and how pods get isolated
- How `kube-proxy` handles service traffic with iptables
- What happens when you `kubectl exec` into a pod and ping another pod

```bash
# Useful debugging commands
ip route                           # routing table on a node
iptables -t nat -L -n              # see kube-proxy rules
kubectl exec -it <pod> -- ip addr  # pod's network interface
```

### Step 2 — Rebuild with Cilium

Tear down Flannel and install Cilium:
```bash
kubectl delete -f kube-flannel.yml
cilium install
```

Explore Cilium features:
- **Hubble UI** — visual network flow observability
  ```bash
  cilium hubble enable --ui
  cilium hubble ui
  ```
- **NetworkPolicy** — restrict pod-to-pod traffic
- **eBPF** — understand why Cilium bypasses iptables entirely

### Network policy example
```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

### What you will learn
- How the CNI spec works (what kubeadm calls during pod creation)
- VXLAN overlays vs direct routing (when to use each)
- What eBPF is and why it is faster than iptables
- How NetworkPolicy is enforced at the kernel level
- How to debug network issues (pod can't reach service, DNS not resolving, etc.)
- Kubernetes DNS (CoreDNS) — how service discovery works

---

## Phase 10 — Storage Track

**Goal:** Learn persistent storage in Kubernetes — how PVCs, StorageClasses, and volume plugins work, from simple to enterprise-grade.

### Key concepts to understand first
- **PersistentVolume (PV)** — actual storage resource
- **PersistentVolumeClaim (PVC)** — request for storage by a pod
- **StorageClass** — defines how storage is dynamically provisioned
- **CSI (Container Storage Interface)** — how storage drivers plug into Kubernetes

### Step 1 — Longhorn (start here)

Install Longhorn for distributed block storage:
```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.6.0/deploy/longhorn.yaml
```

Try:
- Create a PVC and attach it to a pod
- Write data, delete the pod, recreate it — data persists
- Take a volume snapshot
- Explore the Longhorn UI (`kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80`)

### Step 2 — Rook/Ceph (advanced)

Rook runs Ceph inside Kubernetes:
```bash
git clone https://github.com/rook/rook.git
cd rook/deploy/examples
kubectl apply -f crds.yaml -f common.yaml -f operator.yaml
kubectl apply -f cluster.yaml
```

Explore:
- **RBD (block storage)** — for databases, stateful apps
- **CephFS (shared filesystem)** — for ReadWriteMany volumes
- **Object storage (S3-compatible)** — for backups, artifacts

### What you will learn
- How the CSI spec works and how storage drivers register with kubelet
- How Longhorn replicates data across nodes
- What RADOS is and how Ceph distributes data across OSDs
- How to debug PVC stuck in Pending state
- Volume lifecycle — how attach/detach/mount/unmount works

---

## Phase 11 — Production Hardening

**Goal:** Understand what it takes to run a self-managed cluster reliably in production.

### High availability control plane

Add 2 more control plane nodes (total 3) with an external load balancer:
```bash
# On additional control plane nodes
kubeadm join <lb-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key>
```

Use Hetzner Load Balancer or HAProxy to front the 3 API servers.

### MetalLB — bare metal load balancer

MetalLB gives you `LoadBalancer` type services on bare metal (normally only available in cloud):
```bash
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.3/config/manifests/metallb-native.yaml
```

### Ingress controller

Deploy NGINX ingress or Traefik to route HTTP/HTTPS traffic:
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/baremetal/deploy.yaml
```

### Monitoring stack

Deploy the kube-prometheus stack (Prometheus + Grafana + Alertmanager):
```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring --create-namespace
```

### What you will learn
- How HA etcd quorum works (why you need an odd number of control plane nodes)
- What happens during a control plane node failure and how to recover
- How MetalLB announces IP addresses via ARP/BGP
- How TLS termination works at the ingress layer
- How to alert on cluster health with Prometheus

---

## Phase 12 — Advanced Topics

**Goal:** Explore modern self-managed Kubernetes tools and GitOps practices.

### Talos Linux

A minimal, immutable, API-driven OS designed purely for Kubernetes:
- No SSH, no shell — all configuration via API
- Kubernetes runs as the init system
- Great for understanding a very different philosophy to kubeadm

```bash
# Bootstrap a Talos cluster
talosctl gen config my-cluster https://<control-plane-ip>:6443
talosctl apply-config --insecure --nodes <ip> --file controlplane.yaml
talosctl bootstrap --nodes <ip>
```

### GitOps with Flux or ArgoCD

Manage cluster state declaratively from a Git repository:
```bash
# Flux bootstrap
flux bootstrap github \
  --owner=<your-github-user> \
  --repository=k8s-cluster \
  --branch=main \
  --path=./clusters/hetzner \
  --personal
```

### Cluster API (CAPI)

Manage the lifecycle of Kubernetes clusters using Kubernetes itself:
- Provision nodes, control planes, and workers declaratively
- Supports Hetzner as an infrastructure provider (CAPH)

### What you will learn
- How immutable infrastructure differs from traditional node management
- Why GitOps improves auditability and disaster recovery
- How Cluster API abstracts infrastructure provisioning
- The difference between managing a cluster vs managing clusters (plural)

---

## Quick Reference — Most Used Commands

```bash
# Cluster status
kubectl get nodes -o wide
kubectl get pods -A
kubectl top nodes

# Debugging
kubectl describe pod <name>
kubectl logs <pod> -f
kubectl events --sort-by=.lastTimestamp

# etcd health
etcdctl endpoint health
etcdctl endpoint status --write-out=table

# kubeadm
kubeadm token list
kubeadm certs check-expiration
kubeadm upgrade plan

# Containerd
crictl ps                    # list running containers
crictl images                # list images
crictl logs <container-id>   # container logs
```

---

## Recommended Resources

- **Kubernetes the Hard Way** (Kelsey Hightower) — do this after finishing Phase 8
- **Kubernetes docs** — https://kubernetes.io/docs
- **Cilium docs** — https://docs.cilium.io
- **Longhorn docs** — https://longhorn.io/docs
- **Rook docs** — https://rook.io/docs
- **CKA exam** — this roadmap covers ~90% of the Certified Kubernetes Administrator syllabus
