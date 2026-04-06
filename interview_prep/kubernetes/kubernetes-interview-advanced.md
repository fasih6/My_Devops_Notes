# Kubernetes Interview Q&A — Advanced Level

> **Level**: Advanced  
> **Format**: Mix of concise answers, bullet points, tables, and code snippets  
> **Prerequisite**: Beginner + Intermediate levels completed  
> **Total**: 120+ questions across 10 advanced topic sections

---

## Table of Contents

1. [Cluster Setup & kubeadm](#1-cluster-setup--kubeadm)
2. [etcd — Backup, Restore & Internals](#2-etcd--backup-restore--internals)
3. [TLS, Certificates & PKI](#3-tls-certificates--pki)
4. [Cluster Upgrades & Maintenance](#4-cluster-upgrades--maintenance)
5. [Custom Resources, Controllers & Operators](#5-custom-resources-controllers--operators)
6. [Admission Controllers & Webhooks](#6-admission-controllers--webhooks)
7. [Advanced Networking & CNI](#7-advanced-networking--cni)
8. [Observability — Logging, Metrics & Tracing](#8-observability--logging-metrics--tracing)
9. [Service Mesh & Istio Basics](#9-service-mesh--istio-basics)
10. [Advanced Troubleshooting & Internals](#10-advanced-troubleshooting--internals)

---

## 1. Cluster Setup & kubeadm

---

**Q1. What is kubeadm and what is it used for?**

`kubeadm` is the official tool for bootstrapping a production-grade Kubernetes cluster. It handles:
- Initializing the control plane
- Generating TLS certificates
- Configuring etcd
- Setting up kubeconfig files
- Joining worker nodes to the cluster

It does **not** install a CNI plugin or cloud integrations — those must be set up separately.

---

**Q2. What are the steps to set up a Kubernetes cluster with kubeadm?**

```bash
# === On ALL nodes ===
# 1. Install container runtime (containerd)
apt-get install -y containerd
systemctl enable --now containerd

# 2. Install kubeadm, kubelet, kubectl
apt-get install -y kubelet kubeadm kubectl
apt-mark hold kubelet kubeadm kubectl   # Prevent auto-upgrade

# 3. Disable swap (required by kubelet)
swapoff -a
sed -i '/swap/d' /etc/fstab

# 4. Enable required kernel modules
modprobe br_netfilter
echo "net.bridge.bridge-nf-call-iptables=1" >> /etc/sysctl.conf
sysctl --system

# === On Control Plane node only ===
# 5. Initialize the cluster
kubeadm init \
  --pod-network-cidr=192.168.0.0/16 \   # Required by Calico
  --apiserver-advertise-address=<control-plane-ip>

# 6. Configure kubectl for current user
mkdir -p $HOME/.kube
cp /etc/kubernetes/admin.conf $HOME/.kube/config
chown $(id -u):$(id -g) $HOME/.kube/config

# 7. Install CNI plugin (e.g., Calico)
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml

# === On Worker nodes ===
# 8. Join workers (use token from kubeadm init output)
kubeadm join <control-plane-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash>
```

---

**Q3. What is the kubeadm config file and why use it?**

The kubeadm config file provides declarative, repeatable cluster initialization — better than long CLI flags:

```yaml
apiVersion: kubeadm.k8s.io/v1beta3
kind: ClusterConfiguration
kubernetesVersion: v1.28.0
controlPlaneEndpoint: "k8s-lb.example.com:6443"   # For HA setups
networking:
  podSubnet: "192.168.0.0/16"
  serviceSubnet: "10.96.0.0/12"
apiServer:
  extraArgs:
    audit-log-path: "/var/log/audit.log"
    audit-policy-file: "/etc/kubernetes/audit-policy.yaml"
etcd:
  local:
    dataDir: "/var/lib/etcd"
---
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
cgroupDriver: systemd
```

```bash
kubeadm init --config kubeadm-config.yaml
```

---

**Q4. How do you generate a new join token for adding worker nodes?**

```bash
# List existing tokens
kubeadm token list

# Create a new token
kubeadm token create --print-join-command

# Create token with TTL
kubeadm token create --ttl 2h --print-join-command
```

---

**Q5. What is a highly available (HA) Kubernetes control plane?**

An HA control plane runs **multiple control plane nodes** (typically 3 or 5) to eliminate a single point of failure. Requirements:
- Odd number of control plane nodes (for etcd quorum)
- A **load balancer** in front of all API server nodes
- etcd can be **stacked** (on control plane nodes) or **external** (separate cluster)

```bash
# Add additional control plane node
kubeadm join <lb-ip>:6443 \
  --token <token> \
  --discovery-token-ca-cert-hash sha256:<hash> \
  --control-plane \
  --certificate-key <cert-key>
```

---

**Q6. What is stacked etcd vs external etcd topology?**

| Topology | Description | Pros | Cons |
|---|---|---|---|
| **Stacked etcd** | etcd runs on same nodes as control plane | Simpler setup, fewer nodes | Control plane failure = etcd failure |
| **External etcd** | etcd runs on dedicated separate nodes | Full isolation | More nodes, more complexity |

For production with strict HA requirements, external etcd is preferred.

---

**Q7. What files does kubeadm generate during `kubeadm init`?**

| Path | Purpose |
|---|---|
| `/etc/kubernetes/admin.conf` | Admin kubeconfig |
| `/etc/kubernetes/controller-manager.conf` | Controller manager kubeconfig |
| `/etc/kubernetes/scheduler.conf` | Scheduler kubeconfig |
| `/etc/kubernetes/kubelet.conf` | Kubelet kubeconfig |
| `/etc/kubernetes/pki/` | All TLS certificates and keys |
| `/etc/kubernetes/manifests/` | Static Pod manifests (apiserver, etcd, etc.) |

---

**Q8. How does kubeadm store and distribute control plane certificates for HA?**

```bash
# Upload certs to the cluster (stored as a Secret in kube-system)
kubeadm init phase upload-certs --upload-certs
# Returns a --certificate-key for other control plane nodes to download certs

# On second control plane node
kubeadm join <lb>:6443 \
  --control-plane \
  --certificate-key <key>
```

The certificate key expires after 2 hours by default.

---

**Q9. What is `kubeadm reset` and when do you use it?**

`kubeadm reset` undoes what `kubeadm init` or `kubeadm join` did — removes Kubernetes components, clears state. Used when you want to rebuild a node or fix a broken initialization:

```bash
kubeadm reset
# Then clean up manually:
rm -rf /etc/kubernetes/ /var/lib/etcd/ $HOME/.kube/
iptables -F && iptables -t nat -F
ipvsadm --clear      # If using IPVS mode
```

---

**Q10. What is the CRI (Container Runtime Interface)?**

CRI is a plugin interface that allows the kubelet to use different container runtimes without needing to recompile. The kubelet communicates with any CRI-compliant runtime via gRPC.

```bash
# Check the container runtime on a node
kubectl get node node1 -o jsonpath='{.status.nodeInfo.containerRuntimeVersion}'
# Output: containerd://1.7.0

# Interact with containerd directly
crictl ps                    # List running containers
crictl images                # List images
crictl logs <container-id>   # View container logs
```

---

## 2. etcd — Backup, Restore & Internals

---

**Q11. Why is etcd so critical to Kubernetes?**

etcd is the **single source of truth** for all cluster state. Every object — Pods, Services, Deployments, Secrets, RBAC rules — is stored in etcd. If etcd is lost with no backup:
- The cluster cannot be recovered
- All workloads continue running on nodes but can't be managed
- After a node restart, Pods won't come back

This is why regular etcd backups are non-negotiable in production.

---

**Q12. How do you take an etcd snapshot backup?**

```bash
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd-snapshot-$(date +%Y%m%d).db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify the snapshot
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd-snapshot.db \
  --write-out=table
```

Output of status:
```
+----------+----------+------------+------------+
|   HASH   | REVISION | TOTAL KEYS | TOTAL SIZE |
+----------+----------+------------+------------+
| abc12345 |    12345 |       1523 |    4.2 MB  |
+----------+----------+------------+------------+
```

---

**Q13. How do you restore an etcd snapshot?**

```bash
# 1. Stop the API server (static Pod — move manifest out)
mv /etc/kubernetes/manifests/kube-apiserver.yaml /tmp/

# 2. Restore the snapshot to a new data directory
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd-snapshot.db \
  --data-dir=/var/lib/etcd-restored \
  --initial-cluster=default=https://127.0.0.1:2380 \
  --initial-cluster-token=etcd-cluster-1 \
  --initial-advertise-peer-urls=https://127.0.0.1:2380 \
  --name=default

# 3. Update etcd static Pod manifest to use new data dir
# Edit /etc/kubernetes/manifests/etcd.yaml
# Change: --data-dir=/var/lib/etcd  →  --data-dir=/var/lib/etcd-restored
# Change: hostPath for volumes accordingly

# 4. Restore API server manifest
mv /tmp/kube-apiserver.yaml /etc/kubernetes/manifests/

# 5. Verify
kubectl get nodes
```

---

**Q14. Where is the etcd data directory by default?**

```bash
# Default location
/var/lib/etcd

# Check the etcd static pod manifest
cat /etc/kubernetes/manifests/etcd.yaml | grep data-dir
# --data-dir=/var/lib/etcd
```

---

**Q15. How do you connect to etcd and query it directly?**

```bash
# List all keys
ETCDCTL_API=3 etcdctl get / --prefix --keys-only \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Get a specific key (e.g., a Pod)
ETCDCTL_API=3 etcdctl get /registry/pods/default/my-pod \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

---

**Q16. What is etcd's consensus algorithm?**

etcd uses the **Raft consensus algorithm** to ensure data consistency across its cluster members. Key properties:
- One leader elected; all writes go to the leader
- Writes are committed only when a **majority (quorum)** of members acknowledge
- Quorum = `(n/2) + 1` where n = number of etcd members

| Members | Quorum | Tolerated Failures |
|---|---|---|
| 1 | 1 | 0 |
| 3 | 2 | 1 |
| 5 | 3 | 2 |
| 7 | 4 | 3 |

---

**Q17. What is etcd compaction and defragmentation?**

- **Compaction**: etcd keeps a history of all revisions. Compaction removes old revisions to free memory:
  ```bash
  ETCDCTL_API=3 etcdctl compact <revision>
  ```

- **Defragmentation**: Compaction frees logical space but not physical disk space. Defrag reclaims it:
  ```bash
  ETCDCTL_API=3 etcdctl defrag --endpoints=https://127.0.0.1:2379 ...
  ```

In production, set `--auto-compaction-retention` on etcd to automate compaction.

---

**Q18. How do you check etcd member health?**

```bash
ETCDCTL_API=3 etcdctl member list \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

ETCDCTL_API=3 etcdctl endpoint health \
  --endpoints=https://127.0.0.1:2379 ...

ETCDCTL_API=3 etcdctl endpoint status \
  --write-out=table \
  --endpoints=https://127.0.0.1:2379 ...
```

---

**Q19. What is the etcd encryption at rest feature?**

By default, Secrets in etcd are stored in **plaintext** (only base64-encoded in the API). You can enable encryption at rest using an `EncryptionConfiguration`:

```yaml
# /etc/kubernetes/enc/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
- resources:
  - secrets
  providers:
  - aescbc:
      keys:
      - name: key1
        secret: <base64-encoded-32-byte-key>
  - identity: {}    # Fallback for reading unencrypted secrets
```

```bash
# Add to kube-apiserver static pod:
--encryption-provider-config=/etc/kubernetes/enc/encryption-config.yaml

# Re-encrypt all existing secrets
kubectl get secrets --all-namespaces -o json | kubectl replace -f -
```

---

**Q20. What is the role of etcd's WAL (Write-Ahead Log)?**

The WAL (Write-Ahead Log) is etcd's durability mechanism. Before committing any change, etcd writes it to the WAL on disk. This ensures that if etcd crashes mid-write, it can replay the WAL on restart to recover to a consistent state — similar to database transaction logs.

---

## 3. TLS, Certificates & PKI

---

**Q21. What is the Kubernetes PKI and where are certificates stored?**

Kubernetes uses a PKI (Public Key Infrastructure) for secure communication between all components. All certificates are stored at:

```
/etc/kubernetes/pki/
├── ca.crt / ca.key                    # Cluster CA
├── apiserver.crt / apiserver.key      # API server cert
├── apiserver-kubelet-client.crt/key   # API server → kubelet
├── front-proxy-ca.crt/key             # Front proxy CA
├── front-proxy-client.crt/key         # Front proxy client
├── sa.pub / sa.key                    # Service Account signing keys
└── etcd/
    ├── ca.crt / ca.key                # etcd CA
    ├── server.crt / server.key        # etcd server
    ├── peer.crt / peer.key            # etcd peer communication
    └── healthcheck-client.crt/key     # etcd health check client
```

---

**Q22. How do you check the expiry of Kubernetes certificates?**

```bash
# Check all certificate expiry at once (kubeadm clusters)
kubeadm certs check-expiration

# Manual check for a specific cert
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates

# Check via kubectl (if API server is running)
kubectl get csr
```

---

**Q23. How do you renew Kubernetes certificates?**

```bash
# Renew all certificates (kubeadm)
kubeadm certs renew all

# Renew individual certificate
kubeadm certs renew apiserver
kubeadm certs renew etcd-server
kubeadm certs renew scheduler.conf

# After renewal, restart control plane components (static Pods)
# Move and restore manifests, or:
crictl rm $(crictl ps -q)     # Force restart of all containers (kubelet restarts them)
```

Certificates expire after **1 year** by default. `kubeadm upgrade` auto-renews certs.

---

**Q24. How does TLS work between kubectl and the API server?**

```
kubectl → (TLS) → kube-apiserver
                     ↑
       Client cert signed by cluster CA
       API server presents its cert
       kubectl verifies against CA cert in kubeconfig
```

The `kubeconfig` file contains:
- `certificate-authority-data`: CA cert to verify the API server
- `client-certificate-data` + `client-key-data`: Client identity

---

**Q25. What is a CertificateSigningRequest (CSR) in Kubernetes?**

The Kubernetes API provides a CSR resource that allows components to request certificates signed by the cluster CA — used to provision client certificates for new users or components:

```bash
# Generate private key and CSR
openssl genrsa -out jane.key 2048
openssl req -new -key jane.key -out jane.csr -subj "/CN=jane/O=dev-team"

# Create K8s CSR object
cat <<EOF | kubectl apply -f -
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: jane-csr
spec:
  request: $(cat jane.csr | base64 | tr -d '\n')
  signerName: kubernetes.io/kube-apiserver-client
  usages: ["client auth"]
EOF

# Approve the CSR
kubectl certificate approve jane-csr

# Retrieve the signed certificate
kubectl get csr jane-csr -o jsonpath='{.status.certificate}' | base64 -d > jane.crt
```

---

**Q26. What is the difference between the cluster CA and the etcd CA?**

Kubernetes uses **separate CAs** for different communication paths:

| CA | Protects |
|---|---|
| Cluster CA (`pki/ca.crt`) | API server, kubelet, controller-manager, scheduler |
| etcd CA (`pki/etcd/ca.crt`) | etcd peer and client communications |
| Front-proxy CA | API aggregation layer |

This limits blast radius — a compromised etcd CA doesn't automatically compromise the entire cluster.

---

**Q27. How does the kubelet authenticate to the API server?**

The kubelet uses a **client certificate** signed by the cluster CA. The CN of the cert is `system:node:<node-name>` and the Organization is `system:nodes`. This maps to the `system:nodes` RBAC group.

Kubelet certificate rotation is enabled by default in modern Kubernetes — the kubelet auto-renews its own certificate.

---

**Q28. What is `kubelet` TLS bootstrapping?**

When new nodes join the cluster, they don't yet have a signed certificate. TLS bootstrapping allows the kubelet to:
1. Use a bootstrap token to authenticate initially
2. Submit a CSR to the API server
3. The controller-manager auto-approves and signs the CSR
4. The kubelet stores its new signed certificate

```bash
# Bootstrap tokens are created by kubeadm join
kubeadm token create --description "bootstrap token for node join"
```

---

## 4. Cluster Upgrades & Maintenance

---

**Q29. What is the supported upgrade path for Kubernetes?**

Kubernetes supports **skewing by at most one minor version** during upgrades. You must upgrade one minor version at a time:

```
1.26 → 1.27 → 1.28    ✅ (one step at a time)
1.26 → 1.28            ❌ (skipping a version)
```

Control plane components can be at most **one minor version ahead** of worker nodes.

---

**Q30. What is the correct order for upgrading a kubeadm cluster?**

```
1. Upgrade kubeadm on control plane
2. Upgrade control plane components (kubeadm upgrade apply)
3. Upgrade kubelet + kubectl on control plane
4. For each worker node:
   a. Drain the node
   b. Upgrade kubeadm on worker
   c. Upgrade node (kubeadm upgrade node)
   d. Upgrade kubelet + kubectl
   e. Uncordon the node
```

---

**Q31. Walk through a complete control plane upgrade from 1.27 to 1.28.**

```bash
# === Control Plane ===

# 1. Upgrade kubeadm
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.28.0-00
apt-mark hold kubeadm

# 2. Verify upgrade plan
kubeadm upgrade plan

# 3. Apply the upgrade
kubeadm upgrade apply v1.28.0

# 4. Drain control plane node
kubectl drain controlplane --ignore-daemonsets

# 5. Upgrade kubelet and kubectl
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.28.0-00 kubectl=1.28.0-00
apt-mark hold kubelet kubectl

# 6. Restart kubelet
systemctl daemon-reload
systemctl restart kubelet

# 7. Uncordon
kubectl uncordon controlplane

# Verify
kubectl get nodes
```

---

**Q32. Walk through upgrading a worker node.**

```bash
# === On Control Plane — drain the worker ===
kubectl drain worker-node-1 --ignore-daemonsets --delete-emptydir-data

# === On Worker Node ===
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.28.0-00
apt-mark hold kubeadm

kubeadm upgrade node   # Upgrades kubelet config (no apply needed on workers)

apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.28.0-00 kubectl=1.28.0-00
apt-mark hold kubelet kubectl

systemctl daemon-reload
systemctl restart kubelet

# === Back on Control Plane ===
kubectl uncordon worker-node-1
kubectl get nodes    # Verify version updated
```

---

**Q33. What does `kubeadm upgrade plan` output?**

It shows:
- Current cluster version
- Latest stable version available
- Which components will be upgraded
- Any API deprecation warnings
- Whether etcd will be upgraded

Always run this before `kubeadm upgrade apply` to understand what will change.

---

**Q34. How do you handle API deprecations during upgrades?**

```bash
# Check for deprecated API usage before upgrading
kubectl deprecations   # Requires pluto or similar tool

# Or use kubent (Kubernetes Node Triage)
kubent

# Check API versions in use
kubectl api-versions
kubectl get <resource> --show-api-group

# Convert manifests to newer API versions
kubectl convert -f old-deployment.yaml --output-version apps/v1
```

---

**Q35. What is the version skew policy between Kubernetes components?**

| Component | Max version skew vs API server |
|---|---|
| `kube-controller-manager` | N-1 (one minor version behind) |
| `kube-scheduler` | N-1 |
| `kubelet` | N-2 (two minor versions behind) |
| `kubectl` | N+1 to N-1 (one ahead or behind) |

This policy allows safe rolling upgrades — upgrade the API server first.

---

## 5. Custom Resources, Controllers & Operators

---

**Q36. What is a Custom Resource Definition (CRD)?**

A CRD extends the Kubernetes API with new resource types. Once created, you can manage instances of that resource (`CustomResource`) using standard `kubectl` commands, just like built-in resources.

```yaml
apiVersion: apiextensions.k8s.io/v1
kind: CustomResourceDefinition
metadata:
  name: databases.myapp.io
spec:
  group: myapp.io
  versions:
  - name: v1
    served: true
    storage: true
    schema:
      openAPIV3Schema:
        type: object
        properties:
          spec:
            type: object
            properties:
              engine:
                type: string
                enum: [postgres, mysql]
              storage:
                type: string
  scope: Namespaced
  names:
    plural: databases
    singular: database
    kind: Database
    shortNames: ["db"]
```

```bash
# After creating the CRD:
kubectl get databases
kubectl apply -f my-database.yaml
kubectl describe database my-postgres
```

---

**Q37. What is a Kubernetes controller and how does it work?**

A controller implements a **reconciliation loop**:
1. **Watch** the API server for changes to specific resources
2. **Compare** current state to desired state
3. **Act** to reconcile the difference

```
Watch API → Detect drift → Take action → Update status → Repeat
```

The control loop is idempotent — running it multiple times produces the same result. Built-in controllers: Deployment controller, ReplicaSet controller, Node controller.

---

**Q38. What is a Kubernetes Operator?**

An Operator is a **custom controller + CRD** that encodes the operational knowledge of a specific application (Day 1 and Day 2 operations):

- Deploy the application
- Handle upgrades
- Perform backups and restores
- Scale and tune
- React to failures

Popular Operators: Prometheus Operator, cert-manager, Strimzi (Kafka), CloudNativePG (Postgres), ArgoCD.

---

**Q39. What are the Operator maturity levels?**

The Operator Framework defines 5 capability levels:

| Level | Capabilities |
|---|---|
| 1 — Basic Install | Automated installation and configuration |
| 2 — Seamless Upgrades | Patch and minor version upgrades |
| 3 — Full Lifecycle | App lifecycle, storage lifecycle, backup |
| 4 — Deep Insights | Metrics, alerts, log processing, workload analysis |
| 5 — Auto Pilot | Horizontal/vertical scaling, auto config tuning, anomaly detection |

---

**Q40. What frameworks exist for building Operators?**

| Framework | Language | Description |
|---|---|---|
| **Operator SDK** | Go, Ansible, Helm | Official framework; most popular |
| **Kubebuilder** | Go | Lower-level; used by Operator SDK |
| **KUDO** | YAML | Declarative Operator framework |
| **Metacontroller** | Any (webhook-based) | Lightweight; uses JSON/webhooks |
| **Kopf** | Python | Kubernetes Operator Pythonic Framework |

---

**Q41. What is the controller-runtime library?**

`controller-runtime` is the Go library used by Kubebuilder and Operator SDK to build controllers. Key concepts:
- **Manager**: Runs multiple controllers and shared caches
- **Reconciler**: Implements the reconcile loop
- **Client**: Reads/writes Kubernetes objects
- **Informer/Cache**: Watches API server efficiently via list-watch

---

**Q42. What is the difference between a controller and an operator?**

| Controller | Operator |
|---|---|
| Manages built-in Kubernetes resources | Manages custom resources (CRDs) |
| Ships with Kubernetes | Deployed separately |
| General-purpose | Application-specific |
| Example: Deployment controller | Example: Prometheus Operator |

All Operators are controllers, but not all controllers are Operators.

---

**Q43. What is server-side apply and how does it differ from client-side apply?**

| Feature | Client-side apply | Server-side apply |
|---|---|---|
| Merge tracking | Stored as annotation on object | Tracked by API server (field manager) |
| Conflict detection | Limited | Explicit conflict detection per field |
| Multi-owner support | Poor | Excellent — each field has an owner |
| Command | `kubectl apply` (default) | `kubectl apply --server-side` |

Server-side apply (SSA) is the modern approach, used by GitOps tools like Flux.

---

**Q44. What is a field manager in server-side apply?**

Each `kubectl apply --server-side` call specifies a `--field-manager` (e.g., `kubectl`, `argocd`, `helm`). The API server tracks which manager owns which fields. Conflicts arise when two managers try to own the same field.

```bash
kubectl apply --server-side --field-manager=my-controller -f deployment.yaml
```

---

## 6. Admission Controllers & Webhooks

---

**Q45. What is an admission controller?**

An admission controller is a piece of code that **intercepts API server requests** after authentication/authorization but before the object is persisted to etcd. It can:
- **Mutate** the object (add defaults, inject sidecars)
- **Validate** the object (reject non-compliant objects)
- **Both**

---

**Q46. What is the request flow through the API server?**

```
Client Request
    ↓
Authentication (Who are you?)
    ↓
Authorization (Are you allowed?)
    ↓
Mutating Admission Webhooks (modify object)
    ↓
Schema Validation (OpenAPI schema check)
    ↓
Validating Admission Webhooks (accept/reject)
    ↓
Persist to etcd
```

---

**Q47. What is a MutatingAdmissionWebhook?**

A webhook that can **modify** (mutate) incoming API requests before they are persisted. Common uses:
- Auto-inject sidecar containers (Istio, Vault Agent)
- Set default labels or annotations
- Add resource limits if not specified
- Inject environment variables

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: MutatingWebhookConfiguration
metadata:
  name: sidecar-injector
webhooks:
- name: inject.istio.io
  admissionReviewVersions: ["v1"]
  clientConfig:
    service:
      name: istiod
      namespace: istio-system
      path: "/inject"
    caBundle: <base64-ca-cert>
  rules:
  - apiGroups: [""]
    apiVersions: ["v1"]
    operations: ["CREATE"]
    resources: ["pods"]
  namespaceSelector:
    matchLabels:
      istio-injection: enabled
  sideEffects: None
```

---

**Q48. What is a ValidatingAdmissionWebhook?**

A webhook that can **accept or reject** API requests based on custom logic. Common uses:
- Enforce naming conventions
- Require specific labels on all resources
- Reject images from untrusted registries
- Block `latest` image tags in production

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: policy-enforcer
webhooks:
- name: validate.mycompany.io
  admissionReviewVersions: ["v1"]
  clientConfig:
    service:
      name: policy-server
      namespace: policy-system
      path: "/validate"
    caBundle: <base64-ca-cert>
  rules:
  - apiGroups: ["apps"]
    apiVersions: ["v1"]
    operations: ["CREATE", "UPDATE"]
    resources: ["deployments"]
  failurePolicy: Fail    # Reject if webhook is unreachable
  sideEffects: None
```

---

**Q49. What is `failurePolicy` in a webhook configuration?**

Controls what happens if the webhook server is unreachable or returns an error:

| Value | Behavior |
|---|---|
| `Fail` (default) | Reject the request if webhook fails — strict but safer |
| `Ignore` | Allow the request to proceed if webhook fails — more lenient |

Production webhooks for security enforcement should use `Fail`. Webhooks for non-critical mutation can use `Ignore`.

---

**Q50. What is OPA Gatekeeper?**

OPA (Open Policy Agent) Gatekeeper is a policy engine for Kubernetes that uses admission webhooks. It allows you to write custom policies in **Rego** language using CRDs:

- `ConstraintTemplate` — defines the policy logic (Rego code)
- `Constraint` — an instance of a policy applied to specific resources

```yaml
# ConstraintTemplate: Require labels
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: requirelabels
spec:
  crd:
    spec:
      names:
        kind: RequireLabels
  targets:
  - target: admission.k8s.gatekeeper.sh
    rego: |
      package requirelabels
      violation[{"msg": msg}] {
        required := input.parameters.labels[_]
        not input.review.object.metadata.labels[required]
        msg := sprintf("Missing required label: %v", [required])
      }
---
# Constraint: Apply to all Pods
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: RequireLabels
metadata:
  name: require-team-label
spec:
  match:
    kinds:
    - apiGroups: [""]
      kinds: ["Pod"]
  parameters:
    labels: ["team", "app"]
```

---

**Q51. What is Kyverno?**

Kyverno is an alternative to OPA Gatekeeper. Policies are written in **YAML** (not Rego), making it more accessible. It supports:
- Validation policies
- Mutation policies
- Generation policies (auto-create NetworkPolicy when namespace is created)

```yaml
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: enforce
  rules:
  - name: check-image-tag
    match:
      resources:
        kinds: ["Pod"]
    validate:
      message: "Using 'latest' tag is not allowed"
      pattern:
        spec:
          containers:
          - image: "!*:latest"
```

---

**Q52. What built-in admission controllers are important to know?**

| Controller | Function |
|---|---|
| `NamespaceLifecycle` | Prevents creating resources in terminating namespaces |
| `LimitRanger` | Enforces LimitRange constraints |
| `ResourceQuota` | Enforces ResourceQuota limits |
| `PodSecurity` | Enforces Pod Security Standards (PSA) |
| `DefaultStorageClass` | Assigns default StorageClass to PVCs |
| `NodeRestriction` | Limits what kubelet can modify |
| `ServiceAccount` | Auto-mounts service account tokens |
| `MutatingAdmissionWebhook` | Runs external mutation webhooks |
| `ValidatingAdmissionWebhook` | Runs external validation webhooks |

---

## 7. Advanced Networking & CNI

---

**Q53. What is CNI (Container Network Interface)?**

CNI is a specification and set of libraries for configuring network interfaces in Linux containers. The kubelet calls CNI plugins when Pods are created/deleted to:
- Assign IP addresses to Pods
- Set up network interfaces and routes
- Configure inter-node networking

---

**Q54. What are the popular CNI plugins and their differences?**

| CNI Plugin | Networking Model | NetworkPolicy | Performance | Notes |
|---|---|---|---|---|
| **Calico** | BGP routing or overlay | ✅ Full support | High | Most popular for enterprise |
| **Cilium** | eBPF-based | ✅ Full + L7 | Very High | Modern; replaces kube-proxy |
| **Flannel** | VXLAN overlay | ❌ None | Medium | Simple; no NetworkPolicy |
| **Weave Net** | Mesh overlay | ✅ | Medium | Simpler than Calico |
| **Antrea** | OVS-based | ✅ | High | VMware-backed |

---

**Q55. What is the difference between overlay and underlay networking in Kubernetes?**

| Overlay | Underlay |
|---|---|
| Pods get virtual IPs; traffic encapsulated (VXLAN/IPIP) | Pods get real IPs routable in the physical network |
| Works on any infrastructure | Requires network-level support (BGP peering) |
| Higher overhead (encapsulation) | Lower overhead, better performance |
| Examples: Flannel VXLAN, Weave | Examples: Calico BGP, AWS VPC CNI |

---

**Q56. How does Pod-to-Pod communication work across nodes?**

With Calico in BGP mode:
1. Each node advertises its Pod CIDR to the network via BGP
2. Pod sends packet to another Pod's IP
3. Node's routing table knows: "Pod CIDR X is on Node Y"
4. Packet routed directly to Node Y (no encapsulation)
5. Node Y delivers to destination Pod

With overlay (VXLAN):
1. Pod sends packet to destination Pod IP
2. Source node encapsulates packet in VXLAN UDP packet
3. Sends to destination node's physical IP
4. Destination node decapsulates and delivers to Pod

---

**Q57. What is IPVS mode in kube-proxy and how does it differ from iptables?**

| Feature | iptables mode | IPVS mode |
|---|---|---|
| Data structure | Linear rule list | Hash table |
| Performance at scale | Degrades with many Services | O(1) constant regardless |
| Load balancing algorithms | Round-robin only | RR, Least Conn, Source Hash, etc. |
| Suitable for | Small/medium clusters | Large clusters (1000+ Services) |

```bash
# Check kube-proxy mode
kubectl get configmap kube-proxy -n kube-system -o yaml | grep mode
```

---

**Q58. What is Cilium and why is it gaining popularity?**

Cilium uses **eBPF** (extended Berkeley Packet Filter) to implement networking and security at the Linux kernel level:
- Replaces kube-proxy entirely (no iptables)
- L7-aware NetworkPolicies (HTTP method, path-based)
- Native support for Kubernetes services without iptables
- Higher performance and lower latency than traditional CNI
- Built-in Hubble observability for network flows

---

**Q59. What is a LoadBalancer Service implementation in bare-metal clusters?**

Cloud providers automatically provision load balancers for `type: LoadBalancer` Services. On bare-metal:
- **MetalLB**: Assigns real IPs from a configured pool and announces them via ARP or BGP
- **kube-vip**: VIP (virtual IP) for both control plane HA and Services
- **Porter/OpenELB**: BGP-based LB for bare-metal

```yaml
# MetalLB IP pool
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: first-pool
  namespace: metallb-system
spec:
  addresses:
  - 192.168.1.200-192.168.1.250
```

---

**Q60. What is the Kubernetes network model (requirements)?**

Kubernetes mandates a flat network model:
1. Every Pod gets a **unique cluster-wide IP**
2. Pods on different nodes can communicate **without NAT**
3. Nodes can communicate with all Pods **without NAT**
4. The IP a Pod sees for itself = the IP others use to reach it

CNI plugins must satisfy these requirements.

---

## 8. Observability — Logging, Metrics & Tracing

---

**Q61. What are the three pillars of observability?**

| Pillar | Description | Tools |
|---|---|---|
| **Logs** | Timestamped records of discrete events | EFK stack, Loki + Grafana |
| **Metrics** | Numeric measurements over time | Prometheus + Grafana |
| **Traces** | Request flow across services | Jaeger, Zipkin, Tempo |

---

**Q62. What is the EFK stack?**

EFK = **Elasticsearch + Fluentd + Kibana** — a popular log aggregation stack for Kubernetes:

- **Fluentd / Fluent Bit**: DaemonSet on every node; tails container logs and ships to Elasticsearch
- **Elasticsearch**: Stores and indexes logs
- **Kibana**: Web UI for searching and visualizing logs

Fluent Bit is preferred over Fluentd for lower resource usage.

---

**Q63. What is the Loki + Grafana stack and how does it differ from EFK?**

| Feature | EFK | Loki + Grafana |
|---|---|---|
| Storage | Full-text indexed (expensive) | Only indexes labels (cheap) |
| Query language | KQL | LogQL |
| Cost | Higher | Lower |
| Integration | Separate UIs | Unified in Grafana |
| Best for | Full-text search | Label-based filtering |

Loki (by Grafana Labs) is often called "Prometheus for logs."

---

**Q64. What is Prometheus and how does it work with Kubernetes?**

Prometheus is a **pull-based** time-series monitoring system:

1. Prometheus **scrapes** `/metrics` HTTP endpoints at regular intervals
2. Uses **service discovery** to find targets (Kubernetes SD)
3. Stores metrics in a local TSDB
4. Exposes a **PromQL** query API for Grafana dashboards and alerts

```yaml
# Prometheus scrape config for Kubernetes Pods
scrape_configs:
- job_name: 'kubernetes-pods'
  kubernetes_sd_configs:
  - role: pod
  relabel_configs:
  - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
    action: keep
    regex: true
```

---

**Q65. What is kube-state-metrics?**

`kube-state-metrics` is a service that listens to the Kubernetes API and generates Prometheus metrics about the **state of Kubernetes objects** — not about resource usage (that's Metrics Server), but about object health:

- `kube_deployment_status_replicas_available`
- `kube_pod_status_phase`
- `kube_node_status_condition`
- `kube_persistentvolumeclaim_status_phase`

---

**Q66. What is the Prometheus Operator and kube-prometheus-stack?**

The **Prometheus Operator** manages Prometheus, Alertmanager, and related components using CRDs:
- `Prometheus` — defines a Prometheus instance
- `ServiceMonitor` — defines what to scrape (replaces manual scrape configs)
- `AlertmanagerConfig` — defines alerting rules and receivers

`kube-prometheus-stack` (Helm chart) bundles:
- Prometheus Operator
- Prometheus
- Grafana
- kube-state-metrics
- node-exporter
- Alertmanager
- Pre-built dashboards

---

**Q67. What is a ServiceMonitor?**

A CRD from the Prometheus Operator that declaratively defines how to scrape a Service:

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-monitor
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: my-app
  namespaceSelector:
    matchNames:
    - production
  endpoints:
  - port: metrics
    interval: 30s
    path: /metrics
```

---

**Q68. What is distributed tracing and when is it needed?**

Distributed tracing tracks a **request's journey across multiple microservices**. Each service adds a "span" to the trace — recording latency, errors, and context. Essential for:
- Debugging latency issues in microservice architectures
- Understanding service dependencies
- Identifying bottlenecks

Tools: **Jaeger**, **Zipkin**, **Grafana Tempo** (with OpenTelemetry instrumentation).

---

**Q69. What is OpenTelemetry?**

OpenTelemetry (OTel) is a CNCF project providing a **vendor-neutral SDK and protocol** (OTLP) for collecting logs, metrics, and traces. It replaces disparate SDKs (Jaeger client, Prometheus client, etc.) with a unified API.

The **OpenTelemetry Collector** can receive, process, and export telemetry to any backend (Jaeger, Prometheus, Loki, Datadog, etc.).

---

**Q70. What is the difference between Metrics Server and Prometheus?**

| Feature | Metrics Server | Prometheus |
|---|---|---|
| Purpose | Real-time resource metrics for HPA and `kubectl top` | Long-term metrics storage and alerting |
| Retention | No historical data | Configurable (days/weeks) |
| Persistence | In-memory only | TSDB on disk |
| Query API | `metrics.k8s.io` API | PromQL |
| Alerting | None | Via Alertmanager |
| Scraped data | CPU/memory only | Any `/metrics` endpoint |

---

## 9. Service Mesh & Istio Basics

---

**Q71. What is a service mesh?**

A service mesh is an **infrastructure layer** that handles service-to-service communication in a microservices architecture. It provides:
- **mTLS** — mutual TLS encryption between all services automatically
- **Traffic management** — canary, A/B testing, circuit breaking, retries
- **Observability** — automatic metrics, traces, and logs per service pair
- **Policy enforcement** — authorization policies at L7

The mesh works by **injecting a sidecar proxy** (Envoy) into every Pod.

---

**Q72. What is Istio and its main components?**

Istio is the most popular service mesh. Components:

| Component | Role |
|---|---|
| **Envoy proxy** | Sidecar in every Pod; handles all traffic |
| **Istiod** | Control plane: configures Envoy proxies, manages certs, service discovery |
| **Pilot** (part of Istiod) | Pushes routing rules to Envoy |
| **Citadel** (part of Istiod) | Certificate authority for mTLS |
| **Galley** (part of Istiod) | Config validation |

---

**Q73. How does Istio sidecar injection work?**

Istio uses a **MutatingAdmissionWebhook** to automatically inject the Envoy sidecar container into Pods:

```bash
# Enable auto-injection for a namespace
kubectl label namespace production istio-injection=enabled

# Or manually inject
istioctl kube-inject -f deployment.yaml | kubectl apply -f -
```

The injected Envoy proxy intercepts all inbound and outbound traffic using iptables rules.

---

**Q74. What is mTLS in a service mesh?**

Mutual TLS (mTLS) means **both sides** of a connection present certificates:
- Without mTLS: Server presents cert, client does not
- With mTLS: Both server and client present certs

In Istio, mTLS is managed automatically — Istiod acts as a CA, issuing and rotating certificates for every service identity (SPIFFE/X.509).

```yaml
# Enforce strict mTLS in a namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT
```

---

**Q75. What is a VirtualService in Istio?**

A VirtualService defines **traffic routing rules** for services in the mesh — applied at the Envoy proxy level:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
spec:
  hosts:
  - my-app
  http:
  - match:
    - headers:
        x-user-type:
          exact: beta-tester
    route:
    - destination:
        host: my-app
        subset: v2
  - route:
    - destination:
        host: my-app
        subset: v1
        weight: 90
    - destination:
        host: my-app
        subset: v2
        weight: 10          # 10% canary traffic to v2
```

---

**Q76. What is a DestinationRule in Istio?**

A DestinationRule defines **traffic policies** applied after routing — such as load balancing, connection pool settings, outlier detection, and TLS settings:

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-app
spec:
  host: my-app
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
    outlierDetection:        # Circuit breaker
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
  subsets:
  - name: v1
    labels:
      version: v1
  - name: v2
    labels:
      version: v2
```

---

**Q77. What is circuit breaking in Istio?**

Circuit breaking prevents cascading failures by **temporarily stopping requests** to a struggling service:
1. Normal state: Requests flow through
2. Trip condition: Too many errors/timeouts → circuit opens
3. Open state: Requests fail fast (no waiting for timeout)
4. Half-open: After `baseEjectionTime`, try again
5. If successful → circuit closes; if not → extends ejection

Configured via `outlierDetection` in `DestinationRule`.

---

**Q78. What is the difference between Istio and Linkerd?**

| Feature | Istio | Linkerd |
|---|---|---|
| Proxy | Envoy (C++) | Linkerd2-proxy (Rust) |
| Resource usage | Higher | Lighter |
| Configuration | Complex (many CRDs) | Simpler |
| Features | Very rich (L7 traffic mgmt, extensible) | Core mesh features |
| Learning curve | Steep | Gentler |
| Best for | Complex traffic mgmt, multi-cluster | Simplicity, performance |

---

## 10. Advanced Troubleshooting & Internals

---

**Q79. How do you debug the API server when it's down?**

```bash
# Check static pod manifest
cat /etc/kubernetes/manifests/kube-apiserver.yaml

# Check container runtime
crictl ps -a | grep apiserver
crictl logs <container-id>

# Check kubelet (which manages static pods)
systemctl status kubelet
journalctl -u kubelet | tail -50

# Check if port is listening
ss -tlnp | grep 6443
curl -k https://localhost:6443/healthz
```

---

**Q80. How do you debug a node that has stopped accepting Pods?**

```bash
# Check node conditions
kubectl describe node <node-name>
# Look for: MemoryPressure, DiskPressure, PIDPressure, Ready=False

# Check kubelet
ssh <node>
systemctl status kubelet
journalctl -u kubelet -n 100 --no-pager

# Common fixes
df -h                         # Check disk space (/var/lib/docker or /var/lib/containerd)
docker system prune           # Or: crictl rmi --prune
free -m                       # Memory
cat /proc/sys/kernel/pid_max  # PID pressure
```

---

**Q81. How do you audit API server requests?**

Enable audit logging via API server flags:

```yaml
# /etc/kubernetes/manifests/kube-apiserver.yaml
- --audit-policy-file=/etc/kubernetes/audit-policy.yaml
- --audit-log-path=/var/log/kubernetes/audit.log
- --audit-log-maxage=30
- --audit-log-maxbackup=10
- --audit-log-maxsize=100
```

```yaml
# audit-policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: RequestResponse    # Log full request and response
  resources:
  - group: ""
    resources: ["secrets"]
- level: Metadata           # Log only metadata (no body)
  resources:
  - group: ""
    resources: ["pods"]
- level: None               # Don't log
  users: ["system:kube-proxy"]
```

Levels: `None`, `Metadata`, `Request`, `RequestResponse`

---

**Q82. How do you find which controller is managing a Pod?**

```bash
kubectl get pod <pod-name> -o jsonpath='{.metadata.ownerReferences}'

# Or describe
kubectl describe pod <pod-name> | grep "Controlled By"
# Controlled By:  ReplicaSet/nginx-deploy-7d9b8c
```

Ownership chain: Pod → ReplicaSet → Deployment

---

**Q83. What is a watch in Kubernetes and how do informers use it?**

`kubectl get -w` and controllers use the **watch API** — a long-lived HTTP connection that streams change events:
- `ADDED` — new object created
- `MODIFIED` — object updated
- `DELETED` — object deleted

**Informers** are efficient watch wrappers with:
- **Local cache**: Avoids repeated API calls
- **Event handlers**: Trigger reconcile loops
- **Resync**: Periodically re-lists to catch missed events

---

**Q84. What is the reconciliation loop and why must it be idempotent?**

The reconciliation loop:
```
Desired State (spec) ──┐
                        ├→ Diff → Action → Update Status
Actual State (status) ──┘
```

Idempotency is critical because:
- The loop runs continuously
- Network failures may cause retries
- Events may be delivered multiple times
- The controller must handle "already in desired state" gracefully without side effects

---

**Q85. How does kubectl apply implement a 3-way merge?**

When you run `kubectl apply`:
1. **Last applied config**: Stored as annotation `kubectl.kubernetes.io/last-applied-configuration`
2. **Current live config**: Fetched from API server
3. **New desired config**: Your YAML file

The 3-way merge:
- Fields in new config → apply them
- Fields in last-applied but not new config → delete them
- Fields in live config but not in last-applied → leave them (set by other controllers)

---

**Q86. What is the difference between `kubectl get` and `kubectl describe`?**

| `kubectl get` | `kubectl describe` |
|---|---|
| Shows fields from the object's JSON/status | Shows a human-friendly summary + Events |
| Useful with `-o yaml/json` for full spec | Includes related Events (crucial for debugging) |
| Fast, scriptable | Verbose, human-readable |
| No events shown | Events shown (last 1 hour) |

---

**Q87. How does Kubernetes handle leader election for control plane components?**

In HA control planes, only one instance of `kube-controller-manager` and `kube-scheduler` should be active at a time. They use **leader election** via Kubernetes Lease objects:

```bash
# Check current leader
kubectl get lease -n kube-system
kubectl describe lease kube-controller-manager -n kube-system
```

The leader periodically renews its lease. If it fails to renew within `leaseDuration`, another instance takes over.

---

**Q88. What is garbage collection in Kubernetes?**

Kubernetes automatically cleans up **orphaned objects** via the garbage collector controller. When a parent object (e.g., Deployment) is deleted:
- `Foreground deletion`: Owner is deleted after all dependents are deleted
- `Background deletion` (default): Owner deleted immediately; dependents deleted asynchronously
- `Orphan`: Dependents are kept (their owner reference is removed)

```bash
kubectl delete deployment nginx --cascade=foreground   # Wait for all Pods to be gone
kubectl delete deployment nginx --cascade=orphan       # Keep Pods running
```

---

**Q89. What is the Kubernetes Event object and how long do events persist?**

Events record what happened to a resource (image pull, scheduling decision, probe failures). By default:
- Events are retained for **1 hour** (controlled by `--event-ttl` on API server, default: 1h)
- Events are stored in etcd (can increase etcd load at scale)

For long-term event storage, use tools like **Event Exporter** to ship events to Elasticsearch or a time-series DB.

---

**Q90. How do you profile performance issues in Kubernetes components?**

```bash
# API server profiling (pprof)
kubectl proxy &
curl http://localhost:8001/debug/pprof/

# Get goroutine dump
curl http://localhost:8001/debug/pprof/goroutine?debug=2

# Heap profile
go tool pprof http://localhost:8001/debug/pprof/heap

# Check API server metrics
kubectl get --raw /metrics | grep apiserver_request_duration
```

---

## Bonus Advanced Questions

---

**Q91. What is the Cluster Autoscaler?**

The Cluster Autoscaler (CA) automatically adjusts the number of **nodes** in the cluster:
- **Scale up**: Triggered when Pods are in `Pending` state due to insufficient resources
- **Scale down**: Triggered when nodes are underutilized for a sustained period

Works with cloud providers (AWS Auto Scaling Groups, GCP MIGs, Azure VMSS).

```bash
# Check CA status
kubectl describe configmap cluster-autoscaler-status -n kube-system
```

---

**Q92. What is Velero and what is it used for?**

Velero is a tool for **Kubernetes cluster backup and disaster recovery**:
- Backup entire namespaces or specific resources to object storage (S3, GCS, Azure Blob)
- Schedule regular backups
- Restore to a different cluster (migration)
- Supports volume snapshots

```bash
velero backup create my-backup --include-namespaces production
velero restore create --from-backup my-backup
velero schedule create daily-backup --schedule="0 1 * * *"
```

---

**Q93. What is the difference between a soft and hard pod eviction?**

| Type | Trigger | Behavior |
|---|---|---|
| **Soft eviction** | Threshold exceeded for `eviction-soft-grace-period` | Pods evicted gracefully after grace period |
| **Hard eviction** | Threshold exceeded immediately | Pods evicted immediately, no grace period |

Kubelet eviction thresholds:
```
--eviction-hard=memory.available<100Mi,nodefs.available<10%
--eviction-soft=memory.available<200Mi,nodefs.available<15%
--eviction-soft-grace-period=memory.available=1m30s
```

---

**Q94. What is SPIFFE/SPIRE and how does it relate to Kubernetes?**

**SPIFFE** (Secure Production Identity Framework for Everyone) is a standard for **workload identity** using X.509 certificates. Each workload gets a SPIFFE ID (a URI like `spiffe://cluster.local/ns/default/sa/my-app`).

**SPIRE** is the reference SPIFFE implementation. Istio uses SPIFFE identities for mTLS — each Pod's Envoy sidecar gets a SPIFFE cert from Istiod.

---

**Q95. What is the Kubernetes Gateway API?**

The Gateway API is the next generation of Ingress in Kubernetes, offering more expressive and extensible traffic routing:

| Resource | Role |
|---|---|
| `GatewayClass` | Defines the controller (like IngressClass) |
| `Gateway` | Defines a load balancer / listener |
| `HTTPRoute` | Defines HTTP routing rules |
| `TCPRoute` | Defines TCP routing rules |

More powerful than Ingress: native support for traffic splitting, header matching, and multi-team ownership.

---

**Q96. What is `kubectl top` and what does it require?**

```bash
kubectl top nodes          # Node CPU/memory usage
kubectl top pods           # Pod CPU/memory usage
kubectl top pods --containers  # Per-container breakdown
```

Requires **Metrics Server** to be installed. Metrics Server collects resource usage from the kubelet's `/stats/summary` endpoint.

---

**Q97. What is the containerd image cache and how do you manage it?**

```bash
# List images on a node (using crictl)
crictl images

# Remove unused images
crictl rmi --prune

# Pull an image manually
crictl pull nginx:latest

# Check containerd storage
du -sh /var/lib/containerd/

# Clean up via containerd
ctr image ls
ctr image rm nginx:latest
```

---

**Q98. What is a multi-cluster Kubernetes architecture?**

Running multiple Kubernetes clusters for:
- **Geographic distribution**: Clusters per region
- **Environment isolation**: Separate prod/staging clusters
- **Blast radius reduction**: Failure in one cluster doesn't affect others
- **Regulatory compliance**: Data residency requirements

Tools for multi-cluster management:
- **ArgoCD** — GitOps across multiple clusters
- **Flux** — GitOps multi-cluster
- **Liqo** — workload offloading across clusters
- **Submariner** — cross-cluster networking
- **Admiral** — Istio multi-cluster service mesh

---

**Q99. How does Kubernetes handle graceful shutdown of a Pod?**

```
1. kubectl delete pod (or Deployment scaling down)
     ↓
2. Pod status → Terminating
     ↓
3. kube-proxy removes Pod from Service endpoints
     ↓
4. preStop hook executes (if configured)
     ↓
5. SIGTERM sent to main container process
     ↓
6. terminationGracePeriodSeconds countdown begins (default: 30s)
     ↓
7. If process exits → Pod deleted cleanly
   If timeout → SIGKILL sent → forceful termination
```

---

**Q100. What is the API aggregation layer?**

The API aggregation layer allows extending the Kubernetes API with **additional API servers** (APIServices). When you hit `/apis/metrics.k8s.io/v1beta1`, the request is proxied to the Metrics Server, not handled by the main API server.

```bash
kubectl get apiservice
# Shows: v1beta1.metrics.k8s.io → Local (or a service endpoint)
```

Used by: Metrics Server, custom API servers built with `apiserver-builder`.

---

**Q101. What is KEDA (Kubernetes Event-Driven Autoscaling)?**

KEDA extends HPA to scale Pods based on **external event sources** — not just CPU/memory:
- Kafka topic lag
- RabbitMQ queue depth
- AWS SQS queue length
- HTTP request rate
- Cron schedule

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: kafka-consumer-scaler
spec:
  scaleTargetRef:
    name: kafka-consumer
  minReplicaCount: 0           # Scale to zero when idle
  maxReplicaCount: 20
  triggers:
  - type: kafka
    metadata:
      topic: orders
      bootstrapServers: kafka:9092
      consumerGroup: order-processor
      lagThreshold: "100"
```

---

**Q102. What is the `projected` volume type?**

A `projected` volume maps multiple volume sources into a single directory:

```yaml
volumes:
- name: combined
  projected:
    sources:
    - configMap:
        name: app-config
    - secret:
        name: app-secret
    - serviceAccountToken:
        path: token
        expirationSeconds: 3600
    - downwardAPI:
        items:
        - path: "labels"
          fieldRef:
            fieldPath: metadata.labels
```

---

**Q103. What is the TokenRequest API and how does it improve secret security?**

The TokenRequest API generates **short-lived, audience-bound, pod-bound** service account tokens — replacing the old long-lived tokens stored as Secrets.

- Tokens expire (default: 1 hour)
- Bound to a specific Pod — invalid if Pod is deleted
- Bound to a specific audience
- Auto-rotated by the kubelet

```bash
# Request a token manually
kubectl create token my-sa --duration=1h --audience=my-service
```

---

**Q104. What is Pod Priority and Preemption?**

Pod Priority allows higher-priority Pods to **preempt** (evict) lower-priority Pods when resources are scarce:

```yaml
# Define a PriorityClass
apiVersion: scheduling.k8s.io/v1
kind: PriorityClass
metadata:
  name: high-priority
value: 1000000
globalDefault: false
preemptionPolicy: PreemptLowerPriority

---
# Use in Pod
spec:
  priorityClassName: high-priority
```

System Pods (kube-system) use `system-cluster-critical` and `system-node-critical` priority classes.

---

**Q105. What is a Lease object in Kubernetes?**

A Lease is a lightweight object (in the `coordination.k8s.io` API group) used for:
- **Leader election**: Controller-manager and scheduler use Leases to coordinate leadership
- **Node heartbeats**: Each node has a Lease in `kube-node-lease` namespace; kubelet updates it every 10s — much lighter than updating the full Node object

```bash
kubectl get leases -n kube-node-lease
kubectl get leases -n kube-system    # Controller-manager, scheduler leader election
```

---

**Q106. What is the difference between `kubectl port-forward` and a Service?**

| `port-forward` | Service |
|---|---|
| Temporary tunnel via API server | Permanent network endpoint |
| Only accessible from your machine | Accessible cluster-wide (or externally) |
| Goes through API server (slower) | Direct kube-proxy routing |
| Great for debugging/testing | Production traffic |
| No changes to cluster config | Creates a stable endpoint |

---

**Q107. How does Kubernetes handle secret rotation?**

Kubernetes does not auto-rotate secrets. Common approaches:
- **Vault Agent Injector**: Rotates secrets as files; app must handle file reload
- **External Secrets Operator**: Syncs from Vault/AWS SM; triggers Pod restarts
- **Reloader**: Watches ConfigMaps/Secrets; rolls Deployments when they change
- **Secret annotation + rolling restart**: Update secret value, then `kubectl rollout restart`

---

**Q108. What is a ResourceSlice and DynamicResourceAllocation (DRA)?**

DRA (alpha in 1.26, evolving) is a new Kubernetes framework for managing specialized hardware resources (GPUs, FPGAs, network cards) with more flexibility than device plugins. `ResourceSlice` represents available hardware, and `ResourceClaim` requests specific hardware — similar to PV/PVC but for devices.

---

**Q109. What is the difference between NodeLocal DNSCache and CoreDNS?**

| Feature | CoreDNS | NodeLocal DNSCache |
|---|---|---|
| Deployment | DaemonSet or Deployment in kube-system | DaemonSet on every node |
| Latency | Involves network hop to CoreDNS Pod | Local cache on the node — no hop |
| Scalability | Can be bottleneck at scale | Offloads CoreDNS significantly |
| How it works | Standard DNS | Local cache using link-local IP (169.254.x.x) |

NodeLocal DNSCache is recommended for large clusters to reduce DNS latency and CoreDNS load.

---

**Q110. What is ephemeral container and when is it used?**

Ephemeral containers are **temporary debugging containers** added to a running Pod without restarting it. Used when the main container doesn't have shell tools (e.g., distroless images):

```bash
kubectl debug -it <pod-name> \
  --image=busybox \
  --target=<container-name>

# The ephemeral container shares the target container's process namespace
# Useful for inspecting /proc, network, files
```

Ephemeral containers cannot be removed once added — they terminate when done.

---

**Q111. What is `kubectl wait` and when is it useful?**

```bash
# Wait for a Deployment rollout to complete
kubectl wait deployment/nginx --for=condition=Available --timeout=60s

# Wait for a Pod to be running
kubectl wait pod/my-pod --for=condition=Ready --timeout=30s

# Wait for a Job to complete
kubectl wait job/my-job --for=condition=Complete --timeout=120s

# Wait for a node to be ready
kubectl wait node/node1 --for=condition=Ready --timeout=60s
```

Useful in CI/CD pipelines to synchronize deployment steps.

---

**Q112. How do you implement blue-green deployment in Kubernetes?**

```bash
# 1. Deploy green version alongside existing blue
kubectl apply -f deployment-green.yaml

# 2. Wait for green to be ready
kubectl wait deployment/app-green --for=condition=Available

# 3. Switch Service selector to green
kubectl patch service app-service \
  -p '{"spec":{"selector":{"version":"green"}}}'

# 4. Monitor; if issues, switch back instantly
kubectl patch service app-service \
  -p '{"spec":{"selector":{"version":"blue"}}}'

# 5. When confident, delete blue
kubectl delete deployment app-blue
```

---

**Q113. How do you implement canary deployment in Kubernetes?**

**Manual approach** — leverage replica ratio:
```bash
# 99% traffic to stable (99 replicas), 1% to canary (1 replica)
kubectl scale deployment app-stable --replicas=99
kubectl scale deployment app-canary --replicas=1
# Both Deployments have same label, same Service selector
```

**Istio approach** — precise traffic splitting by percentage:
```yaml
http:
- route:
  - destination:
      host: app
      subset: stable
    weight: 95
  - destination:
      host: app
      subset: canary
    weight: 5
```

---

**Q114. What is a ValidatingAdmissionPolicy (VAP)?**

Introduced in Kubernetes 1.26 (GA in 1.30), VAP allows writing in-cluster validation policies using **CEL (Common Expression Language)** without deploying an external webhook server:

```yaml
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingAdmissionPolicy
metadata:
  name: "no-latest-tag"
spec:
  matchConstraints:
    resourceRules:
    - apiGroups: ["apps"]
      apiVersions: ["v1"]
      operations: ["CREATE","UPDATE"]
      resources: ["deployments"]
  validations:
  - expression: >
      object.spec.template.spec.containers.all(
        c, !c.image.endsWith(':latest')
      )
    message: "Using :latest tag is not allowed"
```

---

**Q115. What is the Watch Bookmark feature in Kubernetes?**

Watch Bookmarks are a reliability improvement for the watch API. The API server periodically sends `BOOKMARK` events containing the current `resourceVersion`. Clients can use this to resume a watch from a specific point, avoiding a full re-list after a reconnect — reducing API server load.

---

**Q116. How does horizontal vs vertical scaling work together in Kubernetes?**

| | HPA | VPA | Cluster Autoscaler |
|---|---|---|---|
| What scales | Replica count | Resource requests/limits | Node count |
| Trigger | CPU/memory/custom metrics | Historical resource usage | Pending Pods |
| Downtime | No (rolling) | Yes (Pod restart) | No (gradual) |
| Combine? | HPA + CA recommended | VPA + CA recommended | With both |

**HPA + VPA conflict**: Don't use both on CPU/memory for the same Deployment. Use VPA in `Off` mode for recommendations, HPA for scaling.

---

**Q117. What is the pod topology spread constraint `whenUnsatisfiable` option?**

| Value | Behavior |
|---|---|
| `DoNotSchedule` | Block Pod scheduling if constraint can't be satisfied |
| `ScheduleAnyway` | Schedule Pod anyway but prefer satisfying the constraint |

`DoNotSchedule` is strict and ensures even distribution but may cause Pods to be stuck `Pending`. `ScheduleAnyway` is a best-effort approach.

---

**Q118. How do you manage Helm releases across multiple environments?**

```bash
# Using different values files per environment
helm install my-app ./chart -f values-prod.yaml
helm install my-app ./chart -f values-staging.yaml

# Using --set for overrides
helm upgrade my-app ./chart \
  -f values-base.yaml \
  -f values-prod.yaml \
  --set image.tag=v1.2.3

# List all releases
helm list --all-namespaces

# Check release status
helm status my-app -n production
```

---

**Q119. What is Flux and how does it differ from ArgoCD?**

| Feature | ArgoCD | Flux |
|---|---|---|
| UI | Rich web UI | No built-in UI (optional Weave GitOps UI) |
| Architecture | Centralized server | Distributed controllers |
| Multi-tenancy | Via Projects | Via separate namespaces/controllers |
| Reconciliation | Pull-based + webhook | Pull-based + webhook |
| OCI support | Yes | Yes |
| SOPS/Sealed Secrets | Via plugins | Native |
| Learning curve | Gentler (UI helps) | CLI-focused |

Both are CNCF graduated GitOps tools — choice often depends on team preference and UI requirements.

---

**Q120. What are the key considerations for running Kubernetes in production?**

**Cluster Design:**
- HA control plane (3+ control plane nodes)
- External etcd for critical workloads
- Multi-AZ node groups

**Security:**
- Enable audit logging
- Use PSA or OPA/Gatekeeper for policy enforcement
- Encrypt secrets at rest
- Use dedicated ServiceAccounts per app (least privilege)
- Regularly rotate certificates

**Reliability:**
- PodDisruptionBudgets for all critical workloads
- Resource requests and limits on all containers
- Liveness, readiness, and startup probes
- Anti-affinity for replica spreading

**Observability:**
- Centralized logging (EFK or Loki)
- Prometheus + Grafana + Alertmanager
- Distributed tracing for microservices

**Operational:**
- GitOps (ArgoCD or Flux) for all deployments
- Regular etcd backups (Velero or manual)
- Documented runbooks for common failure scenarios
- Regular certificate rotation checks

---

*End of Advanced Level — 120 Questions*

---

## What's Next?

| Level | Topics Coming Up |
|---|---|
| 🔴 **CKA/CKAD** | Exam-style hands-on scenarios, time-pressured imperative command drills, full mock questions covering all exam domains — just say "next"! |
