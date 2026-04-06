# Kubernetes Interview Q&A — Beginner Level

> **Level**: Beginner  
> **Format**: Mix of concise answers, bullet points, tables, and code snippets  
> **Goal**: Build a strong foundation before moving to Intermediate → Advanced → CKA/CKAD  
> **Total**: 120+ questions across 10 beginner topic sections

---

## Table of Contents

1. [What is Kubernetes?](#1-what-is-kubernetes)
2. [Kubernetes Architecture](#2-kubernetes-architecture)
3. [Pods](#3-pods)
4. [Namespaces](#4-namespaces)
5. [Deployments & ReplicaSets](#5-deployments--replicasets)
6. [Services & Networking Basics](#6-services--networking-basics)
7. [ConfigMaps & Secrets](#7-configmaps--secrets)
8. [Volumes & Storage Basics](#8-volumes--storage-basics)
9. [kubectl Basics](#9-kubectl-basics)
10. [Labels, Selectors & Annotations](#10-labels-selectors--annotations)

---

## 1. What is Kubernetes?

---

**Q1. What is Kubernetes?**

Kubernetes (also written as K8s) is an open-source **container orchestration platform** originally developed by Google and now maintained by the CNCF (Cloud Native Computing Foundation). It automates the deployment, scaling, and management of containerized applications across a cluster of machines.

---

**Q2. Why do we need Kubernetes? What problems does it solve?**

Without Kubernetes, running containers at scale becomes very hard to manage manually. Kubernetes solves:

| Problem | Kubernetes Solution |
|---|---|
| Containers crash and need restarting | Auto-restarts failed containers |
| Traffic increases; need more instances | Horizontal auto-scaling (HPA) |
| Updating apps with zero downtime | Rolling updates & rollbacks |
| Routing traffic to healthy containers | Health checks + Service load balancing |
| Managing config and secrets | ConfigMaps & Secrets |
| Running on multiple machines | Cluster management across nodes |
| Service discovery | Built-in DNS for services |

---

**Q3. What is container orchestration?**

Container orchestration is the automated management of containerized applications across multiple hosts. It handles:
- **Scheduling** — deciding which host runs which container
- **Scaling** — adding/removing containers based on load
- **Networking** — connecting containers across hosts
- **Self-healing** — replacing failed containers automatically
- **Rolling updates** — updating apps without downtime

---

**Q4. What is the difference between Docker and Kubernetes?**

| Docker | Kubernetes |
|---|---|
| Runs and manages containers on a **single host** | Manages containers across a **cluster of hosts** |
| No built-in auto-scaling | Has Horizontal Pod Autoscaler |
| Manual container restarts | Automatic self-healing |
| Basic networking | Advanced service discovery and load balancing |
| No built-in rolling updates | Native rolling updates and rollbacks |

> **Simple analogy**: Docker is like a single ship carrying containers. Kubernetes is like the entire shipping fleet manager — coordinating many ships, rerouting cargo, and replacing broken ships automatically.

---

**Q5. What is CNCF and what is Kubernetes' relationship with it?**

The **Cloud Native Computing Foundation (CNCF)** is a vendor-neutral open-source foundation that hosts cloud-native projects. Kubernetes was donated to CNCF by Google in 2016 and is now its most prominent graduated project. CNCF also hosts Prometheus, Helm, containerd, Argo, and many others.

---

**Q6. What is a cluster in Kubernetes?**

A Kubernetes cluster is a set of machines (physical or virtual) that work together to run containerized workloads. A cluster has:
- **Control Plane nodes** — manage the cluster (brain)
- **Worker nodes** — run the actual application containers (muscles)

---

**Q7. What does "self-healing" mean in Kubernetes?**

Self-healing means Kubernetes automatically:
- Restarts containers that crash
- Replaces Pods that are killed
- Reschedules Pods from failed nodes to healthy ones
- Kills containers that don't pass health checks and replaces them

You define the **desired state** (e.g., "3 replicas of my app"), and Kubernetes continuously works to maintain it.

---

**Q8. What is the desired state vs actual state in Kubernetes?**

- **Desired state**: What you declare in your YAML manifests (e.g., 3 Pods running nginx)
- **Actual state**: What is currently running in the cluster
- Kubernetes controllers continuously **reconcile** the actual state toward the desired state

---

**Q9. What are the main Kubernetes objects (resources)?**

| Object | Purpose |
|---|---|
| Pod | Smallest deployable unit; runs containers |
| Deployment | Manages Pod replicas and rolling updates |
| Service | Exposes Pods over the network |
| ConfigMap | Stores configuration data |
| Secret | Stores sensitive data |
| Namespace | Logical grouping/isolation of resources |
| PersistentVolume | Represents storage |
| PersistentVolumeClaim | Requests storage |

---

**Q10. What is YAML and why is it used in Kubernetes?**

YAML (Yet Another Markup Language) is a human-readable data serialization format. Kubernetes uses YAML to define resource manifests declaratively — you describe what you want, and Kubernetes figures out how to achieve it.

```yaml
# Example: A simple Pod definition
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  labels:
    app: nginx
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    ports:
    - containerPort: 80
```

Every Kubernetes YAML has 4 top-level fields:
- `apiVersion` — API group and version
- `kind` — type of resource
- `metadata` — name, labels, namespace
- `spec` — desired state/configuration

---

## 2. Kubernetes Architecture

---

**Q11. What are the two main parts of a Kubernetes cluster?**

1. **Control Plane** — The "brain" that manages the cluster state, scheduling, and API
2. **Worker Nodes** — The machines where application Pods actually run

---

**Q12. What components make up the Control Plane?**

| Component | Role |
|---|---|
| `kube-apiserver` | The front door — all requests (kubectl, controllers) go through it |
| `etcd` | Cluster database — stores all cluster state |
| `kube-scheduler` | Decides which node a new Pod should run on |
| `kube-controller-manager` | Runs control loops to maintain desired state |
| `cloud-controller-manager` | Integrates with cloud provider (AWS, GCP, Azure) |

---

**Q13. What is the kube-apiserver?**

The `kube-apiserver` is the central API gateway for the Kubernetes control plane. Every action — from `kubectl` commands to internal controller communication — goes through it. It:
- Validates and processes REST API requests
- Reads/writes state to etcd
- Authenticates and authorizes all requests

---

**Q14. What is etcd?**

`etcd` is a distributed, strongly consistent key-value store that acts as Kubernetes' database. It stores:
- All cluster configuration
- All resource objects (Pods, Deployments, Services, Secrets, etc.)
- Cluster state

If etcd is lost without a backup, the entire cluster state is gone. That's why etcd backups are critical.

---

**Q15. What is the kube-scheduler?**

The `kube-scheduler` watches for newly created Pods with no assigned node and selects the best node for them based on:
- Available CPU and memory
- Node selectors and affinity rules
- Taints and tolerations

---

**Q16. What is the kube-controller-manager?**

It runs multiple **controllers** as a single binary. Each controller watches the API server and ensures the actual state matches the desired state:

- **Node Controller** — monitors node health
- **Replication Controller** — ensures correct number of Pod replicas
- **Endpoints Controller** — populates Endpoints objects for Services
- **Service Account Controller** — creates default service accounts

---

**Q17. What components run on each Worker Node?**

| Component | Role |
|---|---|
| `kubelet` | Agent that ensures containers run as specified in PodSpecs |
| `kube-proxy` | Handles network routing for Services |
| `Container Runtime` | Runs the containers (containerd, CRI-O) |

---

**Q18. What is the kubelet?**

The `kubelet` is an agent running on every worker node. It:
- Watches the API server for Pods assigned to its node
- Instructs the container runtime to start/stop containers
- Reports node and Pod status back to the control plane
- Runs liveness and readiness probes

---

**Q19. What is kube-proxy?**

`kube-proxy` runs on every node and maintains network rules (iptables or IPVS) that allow communication to Services. When a Service is created, kube-proxy ensures traffic sent to the Service IP gets routed to the correct Pod IP(s).

---

**Q20. What is a container runtime?**

A container runtime is the software that actually runs containers on a node. Kubernetes uses the **Container Runtime Interface (CRI)** to communicate with runtimes. Common runtimes:
- **containerd** (most common today)
- **CRI-O**
- Docker (deprecated in K8s 1.24+; Docker uses containerd underneath)

---

**Q21. How does kubectl communicate with the cluster?**

`kubectl` sends HTTP requests to the `kube-apiserver`. The API server authenticates the request (using the `kubeconfig` file with certificates/tokens), authorizes it (RBAC), and processes it.

```
kubectl → kube-apiserver → etcd (read/write) → controller/scheduler act
```

---

**Q22. What is a kubeconfig file?**

A `kubeconfig` file (default: `~/.kube/config`) stores connection information for Kubernetes clusters:
- **Cluster** — API server URL and CA certificate
- **User** — credentials (certificate, token)
- **Context** — a named combination of cluster + user + namespace

```bash
kubectl config view                    # View kubeconfig
kubectl config current-context        # Show active context
kubectl config use-context my-cluster # Switch context
```

---

**Q23. What is a Kubernetes context?**

A context is a named set of access parameters in kubeconfig — it combines a cluster, a user, and a namespace. Switching contexts lets you work with different clusters (dev, staging, prod) from the same terminal.

---

**Q24. What is the difference between the control plane and a worker node?**

| Control Plane | Worker Node |
|---|---|
| Manages the cluster | Runs application workloads |
| Runs API server, etcd, scheduler | Runs kubelet, kube-proxy, container runtime |
| Usually no application Pods | Hosts application Pods |
| 1–3 nodes (HA setup) | Can be hundreds of nodes |

---

**Q25. What is a master node? (older term)**

"Master node" is the older term for the **control plane node**. Modern Kubernetes documentation uses "control plane" instead. The master/control plane hosts kube-apiserver, etcd, kube-scheduler, and kube-controller-manager.

---

## 3. Pods

---

**Q26. What is a Pod in Kubernetes?**

A Pod is the **smallest and most basic deployable unit** in Kubernetes. It represents one or more containers that:
- Share the same **network namespace** (same IP address and port space)
- Share the same **storage volumes**
- Are always scheduled together on the same node

---

**Q27. Can a Pod have multiple containers?**

Yes. While most Pods have a single container, a Pod can host multiple containers that work closely together. Common patterns:
- **Sidecar**: A helper container alongside the main app (e.g., log shipper)
- **Init container**: A setup container that runs before the main app starts

All containers in a Pod share the same IP and can communicate via `localhost`.

---

**Q28. What is the lifecycle of a Pod?**

| Phase | Description |
|---|---|
| `Pending` | Pod accepted by cluster; waiting to be scheduled or image to be pulled |
| `Running` | Pod is bound to a node; at least one container is running |
| `Succeeded` | All containers exited with code 0 (success) |
| `Failed` | At least one container exited with non-zero code |
| `Unknown` | Pod state cannot be determined (usually node communication issue) |

---

**Q29. How do you create a Pod in Kubernetes?**

**Imperative (quick):**
```bash
kubectl run my-pod --image=nginx
```

**Declarative (YAML):**
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
spec:
  containers:
  - name: nginx
    image: nginx:1.25
    ports:
    - containerPort: 80
```
```bash
kubectl apply -f pod.yaml
```

---

**Q30. How do you view running Pods?**

```bash
kubectl get pods                        # Pods in default namespace
kubectl get pods -n kube-system         # Pods in kube-system namespace
kubectl get pods --all-namespaces       # All Pods in all namespaces
kubectl get pods -o wide                # With node IP and node name
kubectl get pods -w                     # Watch (live updates)
```

---

**Q31. How do you get detailed information about a Pod?**

```bash
kubectl describe pod my-pod
```

This shows: node assignment, container images, events, resource usage, probe status, volume mounts, and error messages — very useful for debugging.

---

**Q32. How do you delete a Pod?**

```bash
kubectl delete pod my-pod
kubectl delete pod my-pod --grace-period=0 --force   # Force delete
kubectl delete -f pod.yaml                            # Delete using manifest
```

> Note: If a Pod is managed by a Deployment, it will be recreated automatically after deletion.

---

**Q33. What is a Pod restart policy?**

The `restartPolicy` field controls when a container is restarted after it exits:

| Policy | Behavior |
|---|---|
| `Always` (default) | Always restart regardless of exit code |
| `OnFailure` | Restart only if exit code is non-zero |
| `Never` | Never restart |

```yaml
spec:
  restartPolicy: OnFailure
```

---

**Q34. What is the difference between a Pod and a container?**

| Container | Pod |
|---|---|
| A running process with its own filesystem | A Kubernetes wrapper around one or more containers |
| Managed by container runtime (containerd) | Managed by Kubernetes/kubelet |
| Has its own network namespace | Shares network namespace across containers in Pod |
| Docker/OCI concept | Kubernetes concept |

---

**Q35. Why doesn't Kubernetes manage containers directly (why Pods)?**

Kubernetes uses Pods as the unit of scheduling rather than individual containers because:
- Some apps need tightly coupled containers (e.g., app + log agent)
- Pods allow shared network and storage between co-located containers
- It provides a consistent abstraction layer regardless of the container runtime

---

**Q36. What happens when a Pod's node fails?**

If a Pod is part of a Deployment or ReplicaSet, the controller detects the missing Pod and schedules a replacement on a healthy node. If a Pod is standalone (not managed by any controller), it is lost permanently.

---

**Q37. Can you update a running Pod's image directly?**

No — most Pod fields are immutable once created. To update a Pod's image, you must delete and recreate it, or (better) update the parent Deployment which handles this gracefully.

---

**Q38. What is a static Pod?**

Static Pods are managed directly by the `kubelet` on a node, not by the API server. They are defined as YAML files in a directory on the node (e.g., `/etc/kubernetes/manifests/`). Control plane components (kube-apiserver, etcd) are typically run as static Pods.

---

**Q39. What is `kubectl logs` used for?**

```bash
kubectl logs my-pod                        # Current logs
kubectl logs my-pod --previous             # Logs from previous (crashed) container
kubectl logs my-pod -f                     # Stream (follow) logs
kubectl logs my-pod -c my-container        # Specific container in multi-container Pod
kubectl logs my-pod --tail=50              # Last 50 lines
```

---

**Q40. How do you run a command inside a running Pod?**

```bash
kubectl exec -it my-pod -- /bin/bash       # Interactive shell
kubectl exec my-pod -- env                 # Run a single command
kubectl exec my-pod -- cat /etc/os-release # Check OS
```

---

## 4. Namespaces

---

**Q41. What is a Namespace in Kubernetes?**

A Namespace provides a mechanism for **logically isolating** resources within a single cluster. It's like a virtual cluster inside a cluster. Resources in different namespaces are separated — a Pod named `web` in `dev` is different from `web` in `prod`.

---

**Q42. What are the default Namespaces in Kubernetes?**

| Namespace | Purpose |
|---|---|
| `default` | Where resources go if no namespace is specified |
| `kube-system` | Kubernetes system components (scheduler, CoreDNS, kube-proxy) |
| `kube-public` | Publicly readable data; used for cluster info |
| `kube-node-lease` | Node heartbeat lease objects (improves node health detection) |

---

**Q43. How do you create and use a Namespace?**

```bash
# Create
kubectl create namespace dev
kubectl apply -f namespace.yaml

# List
kubectl get namespaces

# Use namespace in commands
kubectl get pods -n dev
kubectl apply -f app.yaml -n dev

# Set default namespace for current context
kubectl config set-context --current --namespace=dev
```

---

**Q44. Are all Kubernetes resources namespace-scoped?**

No. Some resources are **cluster-scoped** (not tied to any namespace):
- Nodes
- PersistentVolumes
- ClusterRoles
- Namespaces themselves
- StorageClasses

Namespace-scoped examples: Pods, Deployments, Services, ConfigMaps, Secrets.

---

**Q45. Why would you use multiple Namespaces?**

- **Environment separation**: `dev`, `staging`, `production`
- **Team isolation**: `team-frontend`, `team-backend`
- **Resource quotas**: Limit CPU/memory per namespace
- **Access control**: Grant RBAC permissions per namespace
- **Billing/cost tracking**: Track resource usage per team/project

---

**Q46. Can two Pods in different Namespaces communicate?**

Yes. By default, Pods across namespaces can communicate using the full DNS name:
```
<service-name>.<namespace>.svc.cluster.local
```

You can restrict this with **NetworkPolicies**.

---

**Q47. How do you delete a Namespace?**

```bash
kubectl delete namespace dev
```

> ⚠️ Warning: Deleting a namespace deletes ALL resources inside it (Pods, Services, ConfigMaps, etc.). Be careful in production.

---

## 5. Deployments & ReplicaSets

---

**Q48. What is a ReplicaSet?**

A ReplicaSet ensures a specified number of Pod replicas are running at all times. If a Pod crashes, the ReplicaSet creates a new one. If there are too many, it removes extras.

---

**Q49. What is a Deployment?**

A Deployment is a higher-level resource that manages ReplicaSets. It provides:
- Declarative Pod management
- Rolling updates (update Pods with zero downtime)
- Rollback to previous versions
- Revision history

> In practice, you almost always use Deployments rather than ReplicaSets directly.

---

**Q50. How do you create a Deployment?**

**Imperative:**
```bash
kubectl create deployment nginx-deploy --image=nginx:1.25 --replicas=3
```

**Declarative YAML:**
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
  namespace: default
spec:
  replicas: 3
  selector:
    matchLabels:
      app: nginx
  template:
    metadata:
      labels:
        app: nginx
    spec:
      containers:
      - name: nginx
        image: nginx:1.25
        ports:
        - containerPort: 80
```

---

**Q51. What is the `selector` field in a Deployment?**

The `selector.matchLabels` tells the Deployment which Pods it "owns" and manages. The labels in `selector.matchLabels` must match the labels in `spec.template.metadata.labels`. This is how the Deployment knows which Pods belong to it.

---

**Q52. How do you scale a Deployment?**

```bash
kubectl scale deployment nginx-deploy --replicas=5

# Or edit the YAML and apply
kubectl edit deployment nginx-deploy   # Change replicas in-editor
```

---

**Q53. How do you update a Deployment's image?**

```bash
kubectl set image deployment/nginx-deploy nginx=nginx:1.26

# Check rollout progress
kubectl rollout status deployment/nginx-deploy
```

---

**Q54. How do you roll back a Deployment?**

```bash
# Rollback to previous version
kubectl rollout undo deployment/nginx-deploy

# View rollout history
kubectl rollout history deployment/nginx-deploy

# Rollback to specific revision
kubectl rollout undo deployment/nginx-deploy --to-revision=2
```

---

**Q55. What is a rolling update?**

A rolling update gradually replaces old Pods with new ones, ensuring the application stays available throughout. Kubernetes creates new Pods with the updated image while removing old ones incrementally.

Two key settings:
- `maxUnavailable`: How many Pods can be unavailable during the update
- `maxSurge`: How many extra Pods can be created above the desired count

---

**Q56. What is the difference between a Deployment and a ReplicaSet?**

| Feature | ReplicaSet | Deployment |
|---|---|---|
| Manages Pod replicas | ✅ | ✅ (via ReplicaSet) |
| Rolling updates | ❌ | ✅ |
| Rollback | ❌ | ✅ |
| Revision history | ❌ | ✅ |
| Recommended for use | ❌ (use Deployment) | ✅ |

---

**Q57. How do you view Deployment details?**

```bash
kubectl get deployments
kubectl describe deployment nginx-deploy
kubectl get replicasets                   # See underlying ReplicaSet
```

---

**Q58. What happens when you delete a Deployment?**

The Deployment, its ReplicaSet, and all its Pods are deleted. The application stops running.

```bash
kubectl delete deployment nginx-deploy
```

---

**Q59. What is `kubectl get all`?**

```bash
kubectl get all            # Shows Pods, Deployments, ReplicaSets, Services in default namespace
kubectl get all -n dev     # Same for dev namespace
```

---

**Q60. What is the `READY` column in `kubectl get deployments`?**

`READY` shows `<available>/<desired>` — how many Pods are currently ready vs. how many are requested. For example, `2/3` means 2 out of 3 replicas are ready.

---

## 6. Services & Networking Basics

---

**Q61. What is a Service in Kubernetes?**

A Service is a stable **network endpoint** that exposes a set of Pods. Because Pod IPs change when Pods are restarted or replaced, a Service provides a consistent IP address and DNS name that clients can use to reach Pods.

---

**Q62. Why do we need Services if Pods have their own IPs?**

Pod IPs are **ephemeral** — they change every time a Pod is replaced or restarted. A Service provides a **stable virtual IP** (ClusterIP) and DNS name that always routes to healthy Pods, even as underlying Pod IPs change.

---

**Q63. What are the types of Kubernetes Services?**

| Type | Description | When to use |
|---|---|---|
| `ClusterIP` | Internal cluster IP only; default type | Internal microservice communication |
| `NodePort` | Exposes service on each node's IP at a static port | Simple external access / testing |
| `LoadBalancer` | Provisions a cloud load balancer | Production external access on cloud |
| `ExternalName` | Maps service to an external DNS name | Accessing external services by name |

---

**Q64. What is a ClusterIP Service?**

The default Service type. It assigns a virtual IP that is only reachable **within the cluster**. Pods and other Services can reach it by name or IP, but external users cannot.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-service
spec:
  type: ClusterIP
  selector:
    app: nginx
  ports:
  - port: 80
    targetPort: 80
```

---

**Q65. What is a NodePort Service?**

NodePort exposes a Service on a **static port (30000–32767)** on every node in the cluster. External traffic can reach the Service at `<NodeIP>:<NodePort>`.

```yaml
spec:
  type: NodePort
  ports:
  - port: 80
    targetPort: 80
    nodePort: 30080
```

---

**Q66. How does a Service know which Pods to route traffic to?**

Via **label selectors**. The Service's `selector` field matches labels on Pods. Any Pod with matching labels becomes a backend endpoint for the Service.

```yaml
selector:
  app: nginx    # Routes to all Pods with label app=nginx
```

---

**Q67. What is the difference between `port`, `targetPort`, and `nodePort` in a Service?**

| Field | Meaning |
|---|---|
| `port` | The port the Service listens on (what clients connect to) |
| `targetPort` | The port on the Pod/container to forward traffic to |
| `nodePort` | The port opened on every node (NodePort Services only) |

---

**Q68. What is DNS in Kubernetes?**

Kubernetes runs **CoreDNS** as a cluster DNS service. Every Service gets a DNS name automatically:

```
<service-name>.<namespace>.svc.cluster.local
```

Pods in the same namespace can reach a service by just `<service-name>`. From other namespaces, use `<service-name>.<namespace>`.

---

**Q69. How do you create a Service imperatively?**

```bash
# Expose an existing Deployment
kubectl expose deployment nginx-deploy --port=80 --type=ClusterIP
kubectl expose deployment nginx-deploy --port=80 --type=NodePort
```

---

**Q70. How do you test connectivity to a Service from inside the cluster?**

```bash
# Spin up a temporary debug Pod
kubectl run test --image=busybox --rm -it --restart=Never -- /bin/sh

# Inside the pod:
wget -O- http://my-service
wget -O- http://my-service.default.svc.cluster.local
```

---

**Q71. What is `kubectl port-forward`?**

`port-forward` creates a temporary tunnel from your local machine to a Pod or Service. Useful for testing without exposing anything externally.

```bash
kubectl port-forward pod/nginx-pod 8080:80
# Access via: http://localhost:8080

kubectl port-forward svc/my-service 9090:80
```

---

**Q72. What is an Endpoints object?**

An Endpoints object is automatically created and updated by Kubernetes for every Service. It holds the actual IP:port pairs of the Pods that match the Service's selector.

```bash
kubectl get endpoints my-service
```

---

## 7. ConfigMaps & Secrets

---

**Q73. What is a ConfigMap?**

A ConfigMap stores **non-sensitive configuration data** as key-value pairs, separate from container images. This lets you change config without rebuilding your image.

Common uses: environment variables, config files, command-line arguments.

---

**Q74. How do you create a ConfigMap?**

```bash
# From literal values
kubectl create configmap app-config \
  --from-literal=APP_ENV=production \
  --from-literal=LOG_LEVEL=info

# From a file
kubectl create configmap app-config --from-file=config.properties

# From a directory
kubectl create configmap app-config --from-file=./config-dir/
```

**YAML:**
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
data:
  APP_ENV: "production"
  LOG_LEVEL: "info"
  DATABASE_URL: "postgres://db:5432/mydb"
```

---

**Q75. How do you use a ConfigMap in a Pod?**

**Method 1 — As environment variables:**
```yaml
env:
- name: APP_ENV
  valueFrom:
    configMapKeyRef:
      name: app-config
      key: APP_ENV
```

**Method 2 — All keys as env vars:**
```yaml
envFrom:
- configMapRef:
    name: app-config
```

**Method 3 — Mounted as a file (volume):**
```yaml
volumes:
- name: config-vol
  configMap:
    name: app-config
containers:
- volumeMounts:
  - mountPath: /etc/config
    name: config-vol
```

---

**Q76. What is a Secret?**

A Secret stores **sensitive data** such as passwords, API tokens, and certificates. Data is stored as **base64-encoded** values (not encrypted by default, but can be encrypted at rest).

---

**Q77. How do you create a Secret?**

```bash
# From literals
kubectl create secret generic db-creds \
  --from-literal=username=admin \
  --from-literal=password=S3cur3P@ss

# From file
kubectl create secret generic tls-secret --from-file=tls.crt --from-file=tls.key
```

**YAML (values must be base64-encoded):**
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: db-creds
type: Opaque
data:
  username: YWRtaW4=        # echo -n 'admin' | base64
  password: UzNjdXIzUEBzcw==
```

---

**Q78. How do you encode and decode base64 for Secrets?**

```bash
# Encode
echo -n 'mypassword' | base64
# Output: bXlwYXNzd29yZA==

# Decode
echo 'bXlwYXNzd29yZA==' | base64 --decode
# Output: mypassword
```

---

**Q79. How do you use a Secret in a Pod?**

**As environment variable:**
```yaml
env:
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: db-creds
      key: password
```

**As mounted volume (files):**
```yaml
volumes:
- name: secret-vol
  secret:
    secretName: db-creds
containers:
- volumeMounts:
  - mountPath: /etc/secrets
    name: secret-vol
    readOnly: true
```

---

**Q80. What is the difference between a ConfigMap and a Secret?**

| Feature | ConfigMap | Secret |
|---|---|---|
| Data sensitivity | Non-sensitive | Sensitive |
| Encoding | Plain text | Base64 encoded |
| Encryption at rest | No | Optional (with EncryptionConfig) |
| Use cases | App config, flags | Passwords, tokens, certs |

---

**Q81. Can you view the value of a Secret with kubectl?**

Yes, but it's base64 encoded:
```bash
kubectl get secret db-creds -o yaml

# Decode on the fly
kubectl get secret db-creds -o jsonpath='{.data.password}' | base64 --decode
```

---

**Q82. What are the Secret types in Kubernetes?**

| Type | Purpose |
|---|---|
| `Opaque` | Default; generic key-value data |
| `kubernetes.io/tls` | TLS certificate + key |
| `kubernetes.io/dockerconfigjson` | Docker registry auth |
| `kubernetes.io/service-account-token` | Service account token |
| `kubernetes.io/ssh-auth` | SSH credentials |

---

## 8. Volumes & Storage Basics

---

**Q83. Why do we need Volumes in Kubernetes?**

Container filesystems are **ephemeral** — when a container restarts, its filesystem is reset. Volumes provide persistent or shared storage that survives container restarts.

---

**Q84. What is the difference between a Volume and a PersistentVolume?**

| Volume | PersistentVolume (PV) |
|---|---|
| Tied to the Pod's lifecycle | Independent of any Pod |
| Disappears when Pod is deleted | Persists beyond Pod lifecycle |
| Defined inside Pod spec | Defined as a cluster-level resource |
| For temporary/shared storage | For durable application storage |

---

**Q85. What is `emptyDir`?**

`emptyDir` is a temporary volume created when a Pod starts and deleted when the Pod is removed. All containers in the Pod can read/write to it. Used for:
- Scratch space
- Sharing files between containers in the same Pod

```yaml
volumes:
- name: shared-data
  emptyDir: {}
containers:
- volumeMounts:
  - mountPath: /tmp/data
    name: shared-data
```

---

**Q86. What is a PersistentVolume (PV)?**

A PV is a piece of storage in the cluster that has been provisioned by an admin (or dynamically). It exists independently of any Pod and has its own lifecycle.

---

**Q87. What is a PersistentVolumeClaim (PVC)?**

A PVC is a **request for storage** by a user or application. A Pod uses a PVC to claim a PV. Kubernetes binds the PVC to a suitable PV based on size and access mode.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
```

---

**Q88. What are the PVC access modes?**

| Mode | Short | Description |
|---|---|---|
| `ReadWriteOnce` | RWO | One node can read/write |
| `ReadOnlyMany` | ROX | Many nodes can read |
| `ReadWriteMany` | RWX | Many nodes can read/write |

---

**Q89. How does a Pod use a PVC?**

```yaml
volumes:
- name: my-storage
  persistentVolumeClaim:
    claimName: my-pvc
containers:
- volumeMounts:
  - mountPath: /data
    name: my-storage
```

---

**Q90. What is a StorageClass?**

A StorageClass enables **dynamic provisioning** of PersistentVolumes. Instead of manually creating PVs, when a PVC references a StorageClass, Kubernetes automatically creates a PV using the specified provisioner (e.g., AWS EBS, GCE PD, NFS).

---

## 9. kubectl Basics

---

**Q91. What is kubectl?**

`kubectl` is the **command-line tool** for interacting with Kubernetes clusters. It communicates with the `kube-apiserver` to manage resources.

---

**Q92. What is the basic syntax of kubectl?**

```
kubectl <verb> <resource> [name] [flags]
```

Examples:
```bash
kubectl get pods
kubectl describe pod my-pod
kubectl delete deployment nginx
kubectl apply -f manifest.yaml
kubectl logs my-pod
```

---

**Q93. What are the common kubectl verbs?**

| Verb | Description |
|---|---|
| `get` | List resources |
| `describe` | Show detailed info |
| `create` | Create a resource |
| `apply` | Create or update (declarative) |
| `delete` | Delete a resource |
| `edit` | Edit resource in-place |
| `logs` | View container logs |
| `exec` | Execute command in container |
| `scale` | Change replica count |
| `rollout` | Manage rollouts |
| `expose` | Create a Service |
| `port-forward` | Forward local port to Pod |

---

**Q94. What is the difference between `kubectl create` and `kubectl apply`?**

| `kubectl create` | `kubectl apply` |
|---|---|
| Imperative — fails if resource already exists | Declarative — creates or updates |
| No update support | Supports partial updates |
| Good for one-off creation | Best practice for GitOps / IaC |

---

**Q95. How do you output resource details in different formats?**

```bash
kubectl get pod my-pod -o yaml         # Full YAML definition
kubectl get pod my-pod -o json         # JSON format
kubectl get pods -o wide               # Extra columns (node, IP)
kubectl get pods -o name               # Just names
kubectl get pod my-pod -o jsonpath='{.status.podIP}'   # Specific field
```

---

**Q96. How do you generate a YAML template without creating a resource?**

```bash
# --dry-run=client generates YAML without applying
kubectl run nginx --image=nginx --dry-run=client -o yaml > pod.yaml
kubectl create deployment web --image=nginx --dry-run=client -o yaml > deploy.yaml
kubectl create configmap my-cm --from-literal=key=val --dry-run=client -o yaml
```

This is very useful for the CKA exam and day-to-day work.

---

**Q97. How do you watch resources in real time?**

```bash
kubectl get pods -w               # Watch for changes
kubectl get pods --watch
```

---

**Q98. How do you filter resources by label?**

```bash
kubectl get pods -l app=nginx
kubectl get pods -l "env in (dev,staging)"
kubectl get pods -l app=nginx,env=prod   # Multiple labels (AND)
```

---

**Q99. How do you view all resources in a namespace?**

```bash
kubectl get all -n dev
kubectl get all --all-namespaces     # Across all namespaces
```

---

**Q100. How do you apply changes to an existing resource?**

```bash
# Method 1: Edit in-place
kubectl edit deployment nginx-deploy

# Method 2: Apply updated YAML
kubectl apply -f updated-deploy.yaml

# Method 3: Patch a specific field
kubectl patch deployment nginx-deploy -p '{"spec":{"replicas":5}}'
```

---

**Q101. How do you check Kubernetes cluster info?**

```bash
kubectl cluster-info
kubectl get nodes
kubectl get nodes -o wide
kubectl version
```

---

**Q102. How do you view events in a namespace?**

```bash
kubectl get events
kubectl get events -n dev
kubectl get events --sort-by='.lastTimestamp'
```

Events are very useful for debugging why Pods aren't starting.

---

**Q103. How do you copy files between your machine and a Pod?**

```bash
# Local → Pod
kubectl cp ./local-file.txt my-pod:/tmp/file.txt

# Pod → Local
kubectl cp my-pod:/var/log/app.log ./app.log
```

---

**Q104. How do you check API resources available in the cluster?**

```bash
kubectl api-resources           # All resource types
kubectl api-resources --namespaced=true    # Namespace-scoped only
kubectl api-versions            # All API versions
kubectl explain pod             # Docs for a resource type
kubectl explain pod.spec        # Docs for a nested field
```

---

## 10. Labels, Selectors & Annotations

---

**Q105. What are labels in Kubernetes?**

Labels are **key-value pairs** attached to Kubernetes objects (Pods, Services, Nodes, etc.). They are used to organize, identify, and select groups of objects.

```yaml
metadata:
  labels:
    app: nginx
    env: production
    version: "1.25"
```

---

**Q106. What are label selectors?**

Label selectors are used to **filter and match** objects by their labels. Services use selectors to find Pods; Deployments use them to manage Pods.

```bash
kubectl get pods -l app=nginx
kubectl get pods -l "env in (dev, staging)"
kubectl get pods -l app=nginx,env=production   # AND condition
```

---

**Q107. What is the difference between equality-based and set-based selectors?**

| Type | Syntax | Example |
|---|---|---|
| Equality-based | `key=value` or `key!=value` | `app=nginx` |
| Set-based | `key in (v1, v2)`, `key notin (v1)`, `key` (exists) | `env in (dev,staging)` |

---

**Q108. What are annotations in Kubernetes?**

Annotations are also key-value pairs, but unlike labels, they are **not used for selection**. They store arbitrary metadata — such as build info, tool configurations, or documentation links.

```yaml
metadata:
  annotations:
    kubernetes.io/change-cause: "Updated nginx to 1.26"
    prometheus.io/scrape: "true"
    prometheus.io/port: "9090"
```

---

**Q109. What is the difference between labels and annotations?**

| Feature | Labels | Annotations |
|---|---|---|
| Used for selection | ✅ Yes | ❌ No |
| Used by controllers | ✅ Yes | ❌ No (usually) |
| Size | Short, limited | Can be large |
| Purpose | Identity + grouping | Metadata + tooling config |

---

**Q110. How do you add a label to an existing resource?**

```bash
kubectl label pod my-pod env=production
kubectl label node node1 disktype=ssd

# Overwrite existing label
kubectl label pod my-pod env=staging --overwrite

# Remove a label
kubectl label pod my-pod env-
```

---

**Q111. How do you add an annotation to a resource?**

```bash
kubectl annotate pod my-pod description="This is the main web pod"
kubectl annotate deployment nginx-deploy kubernetes.io/change-cause="Updated to v1.26"
```

---

**Q112. Why are labels important for Services and Deployments?**

Services use label selectors to find which Pods to route traffic to. If a Pod's labels don't match a Service's selector, it won't receive traffic. This is how Kubernetes wires everything together without hardcoding IP addresses.

---

**Q113. What are recommended label keys by Kubernetes?**

Kubernetes recommends a set of standard labels for consistency:

| Label Key | Example Value |
|---|---|
| `app.kubernetes.io/name` | `nginx` |
| `app.kubernetes.io/version` | `1.25` |
| `app.kubernetes.io/component` | `frontend` |
| `app.kubernetes.io/part-of` | `my-application` |
| `app.kubernetes.io/managed-by` | `helm` |
| `app.kubernetes.io/env` | `production` |

---

**Q114. How do you view labels on resources?**

```bash
kubectl get pods --show-labels
kubectl get nodes --show-labels
kubectl get pods -L app,env        # Show specific labels as columns
```

---

**Q115. What is a nodeSelector?**

`nodeSelector` is the simplest way to constrain which nodes a Pod can be scheduled on — by matching node labels.

```yaml
spec:
  nodeSelector:
    disktype: ssd
```

This Pod will only be scheduled on nodes that have the label `disktype=ssd`.

---

## Bonus Beginner Questions

---

**Q116. What is the difference between imperative and declarative Kubernetes management?**

| Imperative | Declarative |
|---|---|
| Tell Kubernetes what to DO | Tell Kubernetes what you WANT |
| `kubectl run`, `kubectl create` | `kubectl apply -f file.yaml` |
| Hard to track changes | Easy to version-control in Git |
| Quick for testing | Best practice for production |

---

**Q117. What is the role of the `spec` section in a YAML manifest?**

`spec` (specification) defines the **desired state** of the resource — what you want Kubernetes to create and maintain. The `status` section (managed by Kubernetes) reflects the **actual state**.

---

**Q118. What is `kubectl explain`?**

`kubectl explain` provides built-in documentation for any Kubernetes resource or field:

```bash
kubectl explain pod
kubectl explain pod.spec
kubectl explain pod.spec.containers
kubectl explain deployment.spec.strategy
```

Very useful when you don't remember a field name or want to understand what's available.

---

**Q119. How do you check which version of Kubernetes is running?**

```bash
kubectl version
kubectl version --short
kubectl get nodes    # Shows node K8s version in the VERSION column
```

---

**Q120. What is the purpose of `readinessProbe` and `livenessProbe` at a beginner level?**

- **livenessProbe**: "Is my container still alive?" — if it fails, Kubernetes restarts the container
- **readinessProbe**: "Is my container ready to receive traffic?" — if it fails, the Pod is removed from the Service endpoints until it recovers

```yaml
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5

readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 3
```

---

*End of Beginner Level — 120 Questions*

---

## What's Next?

| Level | Topics Coming Up |
|---|---|
| 🟡 **Intermediate** | Scheduling, Taints/Tolerations, Affinity, RBAC, NetworkPolicy, Ingress deep-dive, StatefulSets, DaemonSets |
| 🟠 **Advanced** | Cluster upgrades, etcd backup/restore, Custom controllers, Operators, Service Mesh, Multi-cluster |
| 🔴 **CKA/CKAD** | Exam-style hands-on questions, speed drills, imperative command mastery |
