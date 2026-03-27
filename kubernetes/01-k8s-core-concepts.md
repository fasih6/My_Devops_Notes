# ☸️ Core Concepts & Architecture

How Kubernetes works under the hood — the control plane, data plane, and every core building block.

> Kubernetes is a container orchestration platform. It takes your containers and decides where to run them, keeps them healthy, scales them, and connects them together. Understanding the architecture is what separates someone who can follow tutorials from someone who can debug production incidents.

---

## 📚 Table of Contents

- [1. What is Kubernetes?](#1-what-is-kubernetes)
- [2. Cluster Architecture](#2-cluster-architecture)
- [3. Control Plane Components](#3-control-plane-components)
- [4. Node Components](#4-node-components)
- [5. Core Objects](#5-core-objects)
- [6. The Kubernetes API](#6-the-kubernetes-api)
- [7. Controllers & the Control Loop](#7-controllers--the-control-loop)
- [8. Scheduling](#8-scheduling)
- [9. kubectl — the CLI](#9-kubectl--the-cli)
- [10. Namespaces](#10-namespaces)
- [Key Terms Glossary](#key-terms-glossary)

---

## 1. What is Kubernetes?

Kubernetes (K8s) is an open-source container orchestration platform. It automates:

- **Scheduling** — deciding which node to run a container on
- **Self-healing** — restarting failed containers, replacing unhealthy nodes
- **Scaling** — adding/removing replicas based on load
- **Service discovery** — finding other services by name, not IP
- **Rolling updates** — deploying new versions without downtime
- **Configuration management** — injecting config and secrets into containers

The core idea: you tell Kubernetes the **desired state** ("I want 3 replicas of my app running"), and Kubernetes continuously works to make reality match that state.

---

## 2. Cluster Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                        │
│                                                                   │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │                    Control Plane                         │    │
│  │                                                          │    │
│  │  ┌──────────┐  ┌───────────┐  ┌──────────────────────┐ │    │
│  │  │   API    │  │ Controller│  │      Scheduler       │ │    │
│  │  │  Server  │  │  Manager  │  │                      │ │    │
│  │  └──────────┘  └───────────┘  └──────────────────────┘ │    │
│  │                                                          │    │
│  │  ┌──────────────────────────────────────────────────┐   │    │
│  │  │                    etcd                          │   │    │
│  │  │         (distributed key-value store)            │   │    │
│  │  └──────────────────────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────────────┘    │
│                                                                   │
│  ┌──────────────────┐  ┌──────────────────┐  ┌───────────────┐  │
│  │     Worker Node  │  │   Worker Node    │  │  Worker Node  │  │
│  │                  │  │                  │  │               │  │
│  │  ┌────────────┐  │  │  ┌────────────┐ │  │ ┌──────────┐  │  │
│  │  │  kubelet   │  │  │  │  kubelet   │ │  │ │ kubelet  │  │  │
│  │  └────────────┘  │  │  └────────────┘ │  │ └──────────┘  │  │
│  │  ┌────────────┐  │  │  ┌────────────┐ │  │ ┌──────────┐  │  │
│  │  │ kube-proxy │  │  │  │ kube-proxy │ │  │ │kube-proxy│  │  │
│  │  └────────────┘  │  │  └────────────┘ │  │ └──────────┘  │  │
│  │  ┌────────────┐  │  │  ┌────────────┐ │  │ ┌──────────┐  │  │
│  │  │  Pods      │  │  │  │  Pods      │ │  │ │  Pods    │  │  │
│  │  └────────────┘  │  │  └────────────┘ │  │ └──────────┘  │  │
│  └──────────────────┘  └──────────────────┘  └───────────────┘  │
└─────────────────────────────────────────────────────────────────┘
```

### Control plane vs data plane

| | Control Plane | Data Plane (Worker Nodes) |
|--|--------------|--------------------------|
| **Purpose** | Brain — manages cluster state | Muscle — runs your workloads |
| **Runs** | Kubernetes system components | Your application pods |
| **Key components** | API server, etcd, scheduler, controller manager | kubelet, kube-proxy, container runtime |
| **Failure impact** | Can't make changes, existing pods keep running | Applications go down |

---

## 3. Control Plane Components

### API Server (kube-apiserver)

The **front door** to Kubernetes. Every interaction — kubectl, controllers, nodes — goes through the API server.

```
kubectl apply -f pod.yaml
        │
        ▼
   API Server
   - Authenticates the request
   - Authorizes the request (RBAC)
   - Validates the object
   - Writes to etcd
   - Returns response
```

- Stateless — can run multiple replicas for HA
- All other components talk to each other through the API server (not directly)
- Exposes a RESTful API on port 6443

### etcd

The **source of truth** — a distributed key-value store that holds all cluster state.

```
etcd stores:
- All Kubernetes objects (pods, deployments, services)
- Configuration
- Secrets
- Cluster state
```

- **If etcd goes down, the entire cluster is read-only** — existing pods keep running but no changes can be made
- Must be backed up regularly in production
- Typically run as 3 or 5 nodes for HA (odd number for quorum)

```bash
# Backup etcd
ETCDCTL_API=3 etcdctl snapshot save snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Restore etcd
ETCDCTL_API=3 etcdctl snapshot restore snapshot.db
```

### Scheduler (kube-scheduler)

Watches for new pods with no assigned node and **decides which node to run them on**.

```
New Pod created (no node assigned)
           │
           ▼
      Scheduler
      1. Filter nodes (can this node run the pod?)
         - Enough CPU/memory?
         - Node selector matches?
         - Taints tolerated?
         - Affinity rules satisfied?
      2. Score nodes (which is best?)
         - Least loaded?
         - Preferred affinity?
      3. Bind pod to winning node
```

### Controller Manager (kube-controller-manager)

Runs a collection of **controllers** — each watching the cluster state and reconciling differences.

| Controller | What it does |
|-----------|-------------|
| **ReplicaSet controller** | Ensures correct number of pod replicas |
| **Deployment controller** | Manages rolling updates |
| **Node controller** | Monitors node health, marks unreachable nodes |
| **Job controller** | Ensures Jobs complete successfully |
| **Endpoints controller** | Populates Endpoints objects (for Services) |
| **Namespace controller** | Cleans up when namespaces are deleted |
| **ServiceAccount controller** | Creates default service accounts |

### Cloud Controller Manager

Integrates Kubernetes with cloud provider APIs (AWS, GCP, Azure):
- Provisions LoadBalancer Services → creates cloud load balancers
- Attaches PersistentVolumes → provisions cloud disks
- Updates node info from cloud metadata

---

## 4. Node Components

### kubelet

The **node agent** — runs on every worker node and ensures containers are running as specified.

```
Control Plane says: "Run this pod on this node"
           │
           ▼
       kubelet
       - Receives PodSpec from API server
       - Instructs container runtime to pull image and start containers
       - Monitors container health (liveness/readiness probes)
       - Reports pod status back to API server
       - Mounts volumes and injects secrets/configmaps
```

### kube-proxy

Maintains **network rules** on each node to implement Kubernetes Services.

- Watches API server for Service and Endpoints changes
- Programs iptables (or IPVS) rules to route traffic to the right pods
- Enables the Service abstraction — `my-service:80` resolves to one of the backing pods

### Container Runtime

The software that actually **runs containers**. Kubernetes supports any runtime implementing the CRI (Container Runtime Interface):

| Runtime | Used by |
|---------|---------|
| **containerd** | Most clusters (default in newer Kubernetes) |
| **CRI-O** | OpenShift, some Kubernetes distros |
| **Docker** | Removed in Kubernetes 1.24+ |

```bash
# Check container runtime on a node
kubectl get nodes -o wide    # shows container runtime in CONTAINER-RUNTIME column
crictl ps                    # list containers (containerd equivalent of docker ps)
crictl images                # list images
```

---

## 5. Core Objects

### Pod

The **smallest deployable unit** in Kubernetes. A pod contains one or more containers that share:
- Network namespace (same IP, same port space)
- Storage volumes
- Lifecycle (start and stop together)

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  namespace: default
  labels:
    app: my-app
    version: v1.2.3
spec:
  containers:
    - name: app
      image: nginx:1.24
      ports:
        - containerPort: 80
      resources:
        requests:
          cpu: "100m"      # 0.1 CPU cores
          memory: "128Mi"
        limits:
          cpu: "500m"      # 0.5 CPU cores
          memory: "256Mi"
      env:
        - name: APP_ENV
          value: production
      livenessProbe:
        httpGet:
          path: /healthz
          port: 80
        initialDelaySeconds: 10
        periodSeconds: 10
      readinessProbe:
        httpGet:
          path: /ready
          port: 80
        initialDelaySeconds: 5
        periodSeconds: 5
```

**Pods are ephemeral** — when a pod dies, it's gone. Its IP changes. That's why we use higher-level abstractions like Deployments and Services.

### Node

A worker machine (VM or physical) that runs pods. Each node has:
- kubelet
- kube-proxy
- Container runtime
- Some CPU, memory, disk

```bash
kubectl get nodes
kubectl describe node worker-1
kubectl get nodes -o wide    # shows IPs and OS
```

### Namespace

A virtual cluster within a cluster — used for multi-tenancy and organization.

```bash
# Default namespaces
default         # where resources go if you don't specify
kube-system     # Kubernetes system components (coredns, kube-proxy)
kube-public     # publicly readable, rarely used
kube-node-lease # node heartbeat objects

# Create namespace
kubectl create namespace production
kubectl create namespace staging

# Work in a namespace
kubectl get pods -n kube-system
kubectl get all -n production

# Set default namespace for your session
kubectl config set-context --current --namespace=production
```

### Label & Selector

Labels are key-value pairs attached to objects. Selectors filter objects by their labels — this is how Services find pods, how Deployments manage ReplicaSets.

```yaml
# Labels on a pod
metadata:
  labels:
    app: nginx
    environment: production
    version: "1.24"
    tier: frontend

# Selector on a Service — finds pods with these labels
spec:
  selector:
    app: nginx
    environment: production
```

```bash
# Filter by label
kubectl get pods -l app=nginx
kubectl get pods -l "app=nginx,environment=production"
kubectl get pods -l "environment in (production,staging)"
kubectl get pods -l "environment!=development"
```

### Annotation

Non-identifying metadata — not used for selection, used for tooling:

```yaml
metadata:
  annotations:
    kubernetes.io/change-cause: "Bumped nginx to 1.24"
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
```

---

## 6. The Kubernetes API

Everything in Kubernetes is an API resource. You interact with the cluster by creating, updating, and deleting API objects.

```bash
# See all available API resources
kubectl api-resources

# See API versions
kubectl api-versions

# Explain an object's fields
kubectl explain pod
kubectl explain pod.spec
kubectl explain pod.spec.containers
kubectl explain deployment.spec.strategy
```

### Object structure — every Kubernetes object has 4 top-level fields

```yaml
apiVersion: apps/v1        # API group and version
kind: Deployment           # object type
metadata:                  # name, namespace, labels, annotations
  name: my-deployment
  namespace: default
  labels:
    app: my-app
spec:                      # desired state — what YOU define
  replicas: 3
  ...
# status:                  # current state — what KUBERNETES fills in
#   readyReplicas: 3
```

---

## 7. Controllers & the Control Loop

The **control loop** (reconciliation loop) is the fundamental pattern Kubernetes uses:

```
       Observe                  Diff                   Act
         │                       │                      │
         ▼                       ▼                      ▼
┌─────────────────┐    ┌──────────────────┐   ┌─────────────────┐
│  Current state  │───►│  Desired ≠       │──►│  Take action    │
│  (from etcd)    │    │  Current?        │   │  to converge    │
└─────────────────┘    └──────────────────┘   └─────────────────┘
         ▲                                              │
         └──────────────────────────────────────────────┘
                          (repeat forever)
```

**Example — ReplicaSet controller:**
- Desired: 3 replicas
- Current: 2 pods running (one died)
- Action: Create 1 new pod
- New current: 3 pods running ✅

This is why Kubernetes is self-healing. The controller continuously watches and corrects.

---

## 8. Scheduling

### How the scheduler places pods

```
Pod needs scheduling
       │
       ▼
Filtering (eliminates nodes that can't run the pod)
  - Insufficient CPU/memory (based on requests)
  - nodeSelector doesn't match
  - Taint not tolerated
  - Pod affinity/anti-affinity rules violated
       │
       ▼
Scoring (ranks remaining nodes)
  - LeastAllocated — prefer nodes with most free resources
  - InterPodAffinity — prefer nodes matching affinity rules
  - NodeAffinity — prefer nodes matching preferred affinity
       │
       ▼
Bind pod to highest-scoring node
```

### Node selector — simple node targeting

```yaml
spec:
  nodeSelector:
    kubernetes.io/os: linux
    node-type: gpu              # custom label on node
```

### Node affinity — more expressive

```yaml
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:   # hard rule
        nodeSelectorTerms:
          - matchExpressions:
              - key: topology.kubernetes.io/zone
                operator: In
                values: [eu-central-1a, eu-central-1b]
      preferredDuringSchedulingIgnoredDuringExecution:  # soft preference
        - weight: 100
          preference:
            matchExpressions:
              - key: node-type
                operator: In
                values: [ssd]
```

### Taints & Tolerations

**Taints** repel pods from nodes. **Tolerations** allow pods to be scheduled on tainted nodes.

```bash
# Add taint to a node
kubectl taint nodes node1 gpu=true:NoSchedule
# Effect options: NoSchedule, PreferNoSchedule, NoExecute
```

```yaml
# Pod tolerates the taint
spec:
  tolerations:
    - key: gpu
      operator: Equal
      value: "true"
      effect: NoSchedule
```

### Pod affinity & anti-affinity

```yaml
spec:
  affinity:
    # Prefer to run near pods with app=cache
    podAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app: cache
            topologyKey: kubernetes.io/hostname

    # MUST NOT run on same node as another replica (HA)
    podAntiAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        - labelSelector:
            matchLabels:
              app: my-app
          topologyKey: kubernetes.io/hostname
```

---

## 9. kubectl — the CLI

### Essential kubectl commands

```bash
# Context management
kubectl config get-contexts          # list all contexts
kubectl config current-context       # show current context
kubectl config use-context prod      # switch context
kubectl config set-context --current --namespace=production

# Get resources
kubectl get pods
kubectl get pods -A                  # all namespaces
kubectl get pods -n kube-system
kubectl get pods -o wide             # show node and IP
kubectl get pods -o yaml             # full YAML output
kubectl get pods --watch             # watch for changes
kubectl get all                      # pods, services, deployments, etc.
kubectl get events --sort-by='.lastTimestamp'

# Describe (detailed info + events)
kubectl describe pod my-pod
kubectl describe node worker-1
kubectl describe deployment my-app

# Logs
kubectl logs my-pod
kubectl logs my-pod -c container-name   # specific container
kubectl logs my-pod --previous           # logs from crashed container
kubectl logs my-pod -f                   # follow
kubectl logs my-pod --since=1h          # last 1 hour
kubectl logs -l app=my-app              # logs from all pods with label

# Execute commands
kubectl exec -it my-pod -- bash
kubectl exec -it my-pod -c sidecar -- sh
kubectl exec my-pod -- env             # non-interactive

# Apply and delete
kubectl apply -f manifest.yaml
kubectl apply -f directory/            # apply all files in dir
kubectl delete -f manifest.yaml
kubectl delete pod my-pod
kubectl delete pod my-pod --force --grace-period=0   # force delete

# Edit live objects
kubectl edit deployment my-app
kubectl patch deployment my-app -p '{"spec":{"replicas":5}}'

# Rollout management
kubectl rollout status deployment/my-app
kubectl rollout history deployment/my-app
kubectl rollout undo deployment/my-app
kubectl rollout undo deployment/my-app --to-revision=2
kubectl rollout restart deployment/my-app    # rolling restart

# Scaling
kubectl scale deployment my-app --replicas=5

# Port forwarding
kubectl port-forward pod/my-pod 8080:80
kubectl port-forward svc/my-service 8080:80
kubectl port-forward deployment/my-app 8080:8080

# Copy files
kubectl cp my-pod:/var/log/app.log ./app.log
kubectl cp ./config.yaml my-pod:/etc/app/

# Resource usage
kubectl top nodes
kubectl top pods
kubectl top pods -A

# Run a debug pod
kubectl run debug --image=busybox -it --rm -- sh
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash

# Dry run (see what would be created)
kubectl apply -f manifest.yaml --dry-run=client
kubectl create deployment my-app --image=nginx --dry-run=client -o yaml
```

---

## 10. Namespaces

```bash
# List namespaces
kubectl get namespaces

# Create
kubectl create namespace my-namespace
# OR via manifest:
kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: my-namespace
  labels:
    team: platform
    environment: production
EOF

# Delete namespace (deletes ALL resources inside!)
kubectl delete namespace my-namespace

# Work across namespaces
kubectl get pods -A                          # all namespaces
kubectl get pods --all-namespaces            # same

# Set default namespace for current context
kubectl config set-context --current --namespace=my-namespace
```

### ResourceQuota — limit namespace resources

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    requests.cpu: "10"
    requests.memory: 20Gi
    limits.cpu: "20"
    limits.memory: 40Gi
    pods: "50"
    services: "20"
    persistentvolumeclaims: "10"
```

### LimitRange — default limits per pod

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: default-limits
  namespace: production
spec:
  limits:
    - type: Container
      default:            # default limits if not specified
        cpu: "500m"
        memory: "256Mi"
      defaultRequest:     # default requests if not specified
        cpu: "100m"
        memory: "128Mi"
      max:                # maximum allowed
        cpu: "2"
        memory: "2Gi"
      min:                # minimum required
        cpu: "50m"
        memory: "64Mi"
```

---

## Key Terms Glossary

| Term | Definition |
|------|-----------|
| **Pod** | Smallest deployable unit — one or more containers sharing network and storage |
| **Node** | Worker machine (VM or physical) that runs pods |
| **Control plane** | Brain of the cluster — API server, etcd, scheduler, controller manager |
| **etcd** | Distributed key-value store — source of truth for all cluster state |
| **API server** | Front door to Kubernetes — all interactions go through it |
| **kubelet** | Node agent — ensures containers run as specified |
| **kube-proxy** | Maintains network rules on nodes for Service routing |
| **Scheduler** | Assigns pods to nodes based on resources and constraints |
| **Controller** | Watches state and reconciles differences (ReplicaSet, Deployment, etc.) |
| **Control loop** | Observe → Diff → Act cycle that keeps desired = actual state |
| **Namespace** | Virtual cluster for isolation and multi-tenancy |
| **Label** | Key-value metadata used for selection and filtering |
| **Annotation** | Non-identifying metadata for tooling |
| **Selector** | Filter that matches objects by their labels |
| **Desired state** | What you declare in your manifests |
| **Current state** | What's actually running — Kubernetes tries to match desired |
| **CRI** | Container Runtime Interface — standard for container runtimes |
| **containerd** | Default container runtime in modern Kubernetes |
| **Taint** | Repels pods from a node (unless tolerated) |
| **Toleration** | Allows a pod to be scheduled on a tainted node |
| **Affinity** | Rules for attracting pods to certain nodes or other pods |
| **ResourceQuota** | Limits total resources in a namespace |
| **LimitRange** | Sets default and max resource limits per container |

---

*Next: [Workloads →](./02-workloads.md) — Deployments, StatefulSets, DaemonSets, Jobs, and CronJobs.*
