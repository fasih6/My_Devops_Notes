# Kubernetes Interview Q&A — DevOps Roles

> Covers: Beginner → Advanced → CKA/CKAD-style  
> Format: Mix of concise answers, bullet points, and code snippets  
> Total: 100+ questions across 10 topic sections

---

## Table of Contents

1. [Core Concepts & Architecture](#1-core-concepts--architecture)
2. [Workloads: Pods, Deployments, StatefulSets](#2-workloads-pods-deployments-statefulsets)
3. [Services & Networking](#3-services--networking)
4. [Storage: Volumes, PV, PVC](#4-storage-volumes-pv-pvc)
5. [ConfigMaps & Secrets](#5-configmaps--secrets)
6. [Scheduling & Resource Management](#6-scheduling--resource-management)
7. [RBAC & Security](#7-rbac--security)
8. [Cluster Maintenance & Upgrades](#8-cluster-maintenance--upgrades)
9. [Observability: Logging & Monitoring](#9-observability-logging--monitoring)
10. [Advanced Topics & Troubleshooting](#10-advanced-topics--troubleshooting)

---

## 1. Core Concepts & Architecture

**Q1. What is Kubernetes and why is it used?**  
Kubernetes (K8s) is an open-source container orchestration platform that automates deployment, scaling, and management of containerized applications. It abstracts infrastructure and ensures applications run reliably across clusters.

---

**Q2. What are the main components of the Kubernetes control plane?**

| Component | Role |
|---|---|
| `kube-apiserver` | Front-end of the control plane; handles all REST API requests |
| `etcd` | Distributed key-value store; stores all cluster state |
| `kube-scheduler` | Assigns Pods to nodes based on resource availability |
| `kube-controller-manager` | Runs controllers (Node, Replication, Endpoints, etc.) |
| `cloud-controller-manager` | Integrates with cloud provider APIs |

---

**Q3. What are the worker node components?**

- **kubelet** — Agent on each node; ensures containers are running per PodSpec
- **kube-proxy** — Manages network rules and load balancing for Services
- **Container Runtime** — Runs containers (containerd, CRI-O, Docker)

---

**Q4. What is a Pod?**  
A Pod is the smallest deployable unit in Kubernetes. It wraps one or more containers that share the same network namespace (IP, port space) and storage volumes. Containers in a Pod communicate via `localhost`.

---

**Q5. What is the difference between a Node and a Pod?**  
A **Node** is a physical or virtual machine in the cluster. A **Pod** is a logical unit that runs containers on a node. Multiple Pods can run on a single Node.

---

**Q6. What is etcd and why is it critical?**  
`etcd` is a strongly consistent, distributed key-value store that stores the entire state of the Kubernetes cluster (all objects, configs, secrets). If etcd goes down, the control plane loses all state. It should be backed up regularly.

```bash
# Backup etcd snapshot
ETCDCTL_API=3 etcdctl snapshot save /backup/snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
```

---

**Q7. What is the role of `kube-scheduler`?**  
The scheduler watches for newly created Pods with no assigned node and selects the best node based on:
- Resource requests/limits
- Node selectors and affinity rules
- Taints and tolerations
- Pod topology spread constraints

---

**Q8. What is a Namespace?**  
Namespaces provide logical isolation within a cluster. They separate resources like Pods, Services, and ConfigMaps. Default namespaces: `default`, `kube-system`, `kube-public`, `kube-node-lease`.

```bash
kubectl get pods -n kube-system
kubectl create namespace dev
```

---

**Q9. What is the difference between `kubectl apply` and `kubectl create`?**

| `kubectl create` | `kubectl apply` |
|---|---|
| Imperative; fails if resource exists | Declarative; creates or updates resource |
| Good for one-time creation | Good for GitOps/IaC workflows |

---

**Q10. What is a ReplicaSet?**  
A ReplicaSet ensures a specified number of Pod replicas are running at all times. It replaces failed Pods automatically. Usually managed by a Deployment rather than directly.

---

## 2. Workloads: Pods, Deployments, StatefulSets

**Q11. What is a Deployment and why use it over a ReplicaSet?**  
A Deployment manages ReplicaSets and provides:
- Rolling updates and rollbacks
- Declarative updates to Pods
- History of revisions

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nginx-deploy
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

**Q12. How do you perform a rolling update and rollback?**

```bash
# Update image
kubectl set image deployment/nginx-deploy nginx=nginx:1.26

# Check rollout status
kubectl rollout status deployment/nginx-deploy

# Rollback to previous version
kubectl rollout undo deployment/nginx-deploy

# Rollback to specific revision
kubectl rollout undo deployment/nginx-deploy --to-revision=2

# View history
kubectl rollout history deployment/nginx-deploy
```

---

**Q13. What is the difference between RollingUpdate and Recreate deployment strategies?**

| Strategy | Behavior |
|---|---|
| `RollingUpdate` | Gradually replaces old Pods; zero downtime; configurable via `maxSurge` and `maxUnavailable` |
| `Recreate` | Kills all old Pods first, then starts new ones; causes downtime |

---

**Q14. What is a StatefulSet and when would you use it?**  
A StatefulSet manages stateful applications. Unlike Deployments, it provides:
- Stable, unique Pod names (e.g., `web-0`, `web-1`)
- Stable persistent storage per Pod
- Ordered, graceful deployment and scaling

Use for: databases (MySQL, Postgres), message brokers (Kafka, RabbitMQ), distributed systems (Zookeeper, Elasticsearch).

---

**Q15. What is a DaemonSet?**  
A DaemonSet ensures one Pod runs on every (or selected) node. Used for:
- Log collectors (Fluentd, Filebeat)
- Monitoring agents (Prometheus Node Exporter, Datadog)
- Network plugins (Calico, Weave)

---

**Q16. What is a Job and a CronJob?**

- **Job**: Runs Pods to completion (e.g., batch processing, database migration). Ensures a task completes successfully.
- **CronJob**: Runs Jobs on a scheduled basis (cron syntax).

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: backup-job
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: backup
            image: backup-tool:latest
          restartPolicy: OnFailure
```

---

**Q17. What are init containers?**  
Init containers run before app containers in a Pod. They must complete successfully before the main container starts. Used for:
- Waiting for a service to be ready
- Pre-populating config or data
- Setting up permissions

```yaml
initContainers:
- name: wait-for-db
  image: busybox
  command: ['sh', '-c', 'until nc -z db-service 5432; do sleep 2; done']
```

---

**Q18. What is a sidecar container?**  
A sidecar is an additional container in the same Pod that extends the main container's functionality — e.g., log shipper (Fluentd), proxy (Envoy/Istio), secrets injector (Vault agent).

---

**Q19. Explain Pod lifecycle phases.**

| Phase | Meaning |
|---|---|
| `Pending` | Pod accepted but not yet scheduled or images not pulled |
| `Running` | At least one container is running |
| `Succeeded` | All containers exited with code 0 |
| `Failed` | At least one container exited with non-zero code |
| `Unknown` | Node communication lost |

---

**Q20. What are the Pod restart policies?**

- `Always` (default) — Restart container whenever it exits
- `OnFailure` — Restart only on non-zero exit
- `Never` — Never restart

---

## 3. Services & Networking

**Q21. What is a Kubernetes Service?**  
A Service is an abstraction that exposes a set of Pods as a stable network endpoint. It provides a consistent DNS name and IP, even as Pods are replaced.

---

**Q22. What are the types of Services?**

| Type | Description |
|---|---|
| `ClusterIP` | Internal-only; default type; accessible within cluster |
| `NodePort` | Exposes service on a static port on each node (30000–32767) |
| `LoadBalancer` | Provisions a cloud load balancer; external access |
| `ExternalName` | Maps service to a DNS name (CNAME) |

---

**Q23. How does kube-proxy work?**  
`kube-proxy` runs on each node and maintains iptables (or IPVS) rules to route traffic to the correct Pod IPs based on Service definitions. It watches the API server for Service and Endpoint changes.

---

**Q24. What is an Ingress and how is it different from a Service?**

- **Service** exposes Pods at the network layer (L4 — TCP/UDP).
- **Ingress** is an API object that manages external HTTP/HTTPS access (L7 routing) based on hostnames and paths. Requires an **Ingress Controller** (Nginx, Traefik, HAProxy).

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
spec:
  rules:
  - host: app.example.com
    http:
      paths:
      - path: /api
        pathType: Prefix
        backend:
          service:
            name: api-service
            port:
              number: 80
```

---

**Q25. What is DNS in Kubernetes?**  
Kubernetes runs CoreDNS to resolve service names. A Service named `my-svc` in namespace `my-ns` is reachable at:
- `my-svc` (within same namespace)
- `my-svc.my-ns`
- `my-svc.my-ns.svc.cluster.local` (fully qualified)

---

**Q26. What is a NetworkPolicy?**  
A NetworkPolicy controls traffic flow between Pods. By default, all Pod-to-Pod traffic is allowed. A NetworkPolicy restricts ingress/egress based on namespace, pod selectors, or IP blocks.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
```

---

**Q27. What is the difference between NodePort and LoadBalancer?**

- **NodePort**: Opens a port on every cluster node. You must manage traffic externally.
- **LoadBalancer**: Automatically provisions a cloud load balancer with a public IP. More seamless for production.

---

**Q28. What are Endpoints in Kubernetes?**  
Endpoints are the actual IP:port pairs of Pods that back a Service. Kubernetes automatically creates and updates Endpoint objects as Pods start/stop.

```bash
kubectl get endpoints my-service
```

---

## 4. Storage: Volumes, PV, PVC

**Q29. What is a Volume in Kubernetes?**  
A Volume is a directory accessible to containers in a Pod. Unlike container filesystems, Volumes persist across container restarts (but not Pod deletion unless using persistent volumes).

Common volume types: `emptyDir`, `hostPath`, `configMap`, `secret`, `persistentVolumeClaim`, `nfs`.

---

**Q30. What is the difference between PersistentVolume (PV) and PersistentVolumeClaim (PVC)?**

| | PV | PVC |
|---|---|---|
| What | Actual storage resource provisioned by admin | Request for storage by a user/Pod |
| Scope | Cluster-scoped | Namespace-scoped |
| Analogy | The hard drive | The request to use a hard drive |

---

**Q31. What are the PVC access modes?**

| Mode | Description |
|---|---|
| `ReadWriteOnce (RWO)` | Mounted read-write by a single node |
| `ReadOnlyMany (ROX)` | Mounted read-only by many nodes |
| `ReadWriteMany (RWX)` | Mounted read-write by many nodes |
| `ReadWriteOncePod (RWOP)` | Mounted by a single Pod only (K8s 1.22+) |

---

**Q32. What is a StorageClass?**  
A StorageClass enables dynamic provisioning of PersistentVolumes. It defines the provisioner (e.g., AWS EBS, GCE PD, NFS) and parameters. When a PVC references a StorageClass, a PV is automatically created.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
provisioner: kubernetes.io/aws-ebs
parameters:
  type: gp3
```

---

**Q33. What is `emptyDir`?**  
`emptyDir` is a temporary volume created when a Pod is assigned to a node. It's shared between containers in the same Pod and deleted when the Pod is removed. Used for scratch space or inter-container data sharing.

---

**Q34. What happens to a PVC when a Pod is deleted?**  
The PVC persists — it is not deleted with the Pod. The Pod must explicitly claim the PVC again, or another Pod can reuse it. The PV data is preserved until the PVC is deleted (and reclaim policy kicks in).

---

**Q35. What are PV reclaim policies?**

| Policy | Behavior |
|---|---|
| `Retain` | PV kept after PVC deleted; manual cleanup needed |
| `Delete` | PV and underlying storage deleted when PVC is deleted |
| `Recycle` (deprecated) | Basic scrub (`rm -rf /volume/*`) then made available again |

---

## 5. ConfigMaps & Secrets

**Q36. What is a ConfigMap?**  
A ConfigMap stores non-sensitive configuration data as key-value pairs. It decouples environment-specific config from container images.

```bash
kubectl create configmap app-config --from-literal=ENV=production --from-file=config.properties
```

---

**Q37. How do you use a ConfigMap in a Pod?**

Three ways:
1. **Environment variables**
2. **Command-line arguments**
3. **Mounted as files (volume)**

```yaml
envFrom:
- configMapRef:
    name: app-config
```

---

**Q38. What is a Secret and how is it different from ConfigMap?**

- Secrets store sensitive data (passwords, tokens, certificates).
- Data is base64-encoded (not encrypted by default).
- Access can be restricted via RBAC.
- Can be encrypted at rest using `EncryptionConfiguration`.

```bash
kubectl create secret generic db-creds \
  --from-literal=username=admin \
  --from-literal=password=s3cr3t
```

---

**Q39. What are the types of Secrets?**

| Type | Use |
|---|---|
| `Opaque` | Default; arbitrary key-value data |
| `kubernetes.io/dockerconfigjson` | Docker registry credentials |
| `kubernetes.io/tls` | TLS certificate and key |
| `kubernetes.io/service-account-token` | Service account token |

---

**Q40. Are Secrets secure in Kubernetes by default?**  
Not fully. By default, Secrets are only base64-encoded (not encrypted). To improve security:
- Enable **encryption at rest** via `EncryptionConfiguration`
- Use **RBAC** to limit Secret access
- Use external secret managers (HashiCorp Vault, AWS Secrets Manager) with tools like External Secrets Operator

---

## 6. Scheduling & Resource Management

**Q41. How does the Kubernetes scheduler assign a Pod to a node?**

Two phases:
1. **Filtering**: Eliminates nodes that don't meet Pod requirements (resources, taints, affinity)
2. **Scoring**: Ranks remaining nodes; highest score wins

---

**Q42. What are resource requests and limits?**

- **Request**: Minimum resources a container needs; used by scheduler for placement
- **Limit**: Maximum resources a container can use; enforced by kubelet

```yaml
resources:
  requests:
    cpu: "250m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"
```

---

**Q43. What is a LimitRange?**  
A LimitRange sets default and maximum resource requests/limits for containers in a namespace, preventing resource abuse.

---

**Q44. What is a ResourceQuota?**  
A ResourceQuota limits the total amount of resources (CPU, memory, number of Pods, PVCs, etc.) consumed in a namespace.

---

**Q45. What are taints and tolerations?**

- **Taint**: Applied to a node; repels Pods that don't tolerate it
- **Toleration**: Applied to a Pod; allows it to be scheduled on tainted nodes

```bash
# Add taint to node
kubectl taint nodes node1 dedicated=gpu:NoSchedule

# Pod toleration
tolerations:
- key: "dedicated"
  operator: "Equal"
  value: "gpu"
  effect: "NoSchedule"
```

Taint effects: `NoSchedule`, `PreferNoSchedule`, `NoExecute`

---

**Q46. What is node affinity?**  
Node affinity is a more expressive replacement for `nodeSelector`. It allows rules like "this Pod should run on nodes with label `disktype=ssd`" with required or preferred rules.

```yaml
affinity:
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: disktype
          operator: In
          values:
          - ssd
```

---

**Q47. What is Pod affinity and anti-affinity?**

- **Pod affinity**: Schedule Pod near other Pods with specific labels (e.g., same zone as cache Pod)
- **Pod anti-affinity**: Spread Pods across nodes/zones to avoid single points of failure

---

**Q48. What is a PodDisruptionBudget (PDB)?**  
A PDB limits the number of simultaneously unavailable Pods during voluntary disruptions (node drains, upgrades). Ensures minimum availability.

```yaml
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: nginx
```

---

**Q49. What is the Horizontal Pod Autoscaler (HPA)?**  
HPA automatically scales the number of Pod replicas based on observed CPU/memory utilization or custom metrics.

```bash
kubectl autoscale deployment nginx --cpu-percent=70 --min=2 --max=10
```

---

**Q50. What is the Vertical Pod Autoscaler (VPA)?**  
VPA automatically adjusts CPU/memory requests and limits for containers based on historical usage. Unlike HPA, it changes resource allocation rather than replica count.

---

## 7. RBAC & Security

**Q51. What is RBAC in Kubernetes?**  
Role-Based Access Control (RBAC) is the authorization mechanism in Kubernetes. It controls who can do what on which resources.

Four key objects:
- **Role** — namespace-scoped permissions
- **ClusterRole** — cluster-wide permissions
- **RoleBinding** — binds a Role to a user/group/SA in a namespace
- **ClusterRoleBinding** — binds a ClusterRole cluster-wide

---

**Q52. Create a Role that allows reading Pods in the `dev` namespace.**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  namespace: dev
  name: pod-reader
rules:
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "watch", "list"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods-binding
  namespace: dev
subjects:
- kind: User
  name: jane
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

---

**Q53. What is a ServiceAccount?**  
A ServiceAccount provides an identity for Pods to interact with the Kubernetes API. Each namespace has a `default` ServiceAccount. Pods use it to authenticate API calls.

```bash
kubectl create serviceaccount my-app-sa -n dev
```

---

**Q54. What is Pod Security Admission (PSA)?**  
PSA (replacing PodSecurityPolicy) enforces security standards on Pods at admission time. Three levels:
- `privileged` — unrestricted
- `baseline` — prevents known privilege escalations
- `restricted` — hardened, follows security best practices

---

**Q55. What is a SecurityContext?**  
Defines security settings at Pod or container level:

```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
```

---

**Q56. How do you check permissions for a user?**

```bash
kubectl auth can-i create pods --namespace dev --as jane
kubectl auth can-i "*" "*"  # admin check
```

---

## 8. Cluster Maintenance & Upgrades

**Q57. How do you safely drain a node for maintenance?**

```bash
# Cordon node (prevent new scheduling)
kubectl cordon node1

# Drain node (evict Pods gracefully)
kubectl drain node1 --ignore-daemonsets --delete-emptydir-data

# After maintenance, uncordon
kubectl uncordon node1
```

---

**Q58. How do you upgrade a Kubernetes cluster (kubeadm)?**

```bash
# On control plane
apt-get update && apt-get install -y kubeadm=1.28.0-00
kubeadm upgrade plan
kubeadm upgrade apply v1.28.0

# Upgrade kubelet and kubectl
apt-get install -y kubelet=1.28.0-00 kubectl=1.28.0-00
systemctl daemon-reload && systemctl restart kubelet

# On each worker node (after draining)
kubeadm upgrade node
apt-get install -y kubelet=1.28.0-00 kubectl=1.28.0-00
systemctl daemon-reload && systemctl restart kubelet
```

---

**Q59. How do you back up and restore etcd?**

```bash
# Backup
ETCDCTL_API=3 etcdctl snapshot save snapshot.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Restore
ETCDCTL_API=3 etcdctl snapshot restore snapshot.db \
  --data-dir=/var/lib/etcd-restore
```

---

**Q60. What is the difference between `kubectl cordon` and `kubectl drain`?**

- `cordon`: Marks node as unschedulable; existing Pods continue running
- `drain`: Cordons node AND evicts all running Pods (except DaemonSets)

---

**Q61. How do you check cluster component health?**

```bash
kubectl get componentstatuses   # deprecated but still works
kubectl get nodes
kubectl get pods -n kube-system
kubectl cluster-info
```

---

## 9. Observability: Logging & Monitoring

**Q62. How do you view logs for a Pod?**

```bash
# Current logs
kubectl logs pod-name

# Previous container logs (after crash)
kubectl logs pod-name --previous

# Specific container in multi-container Pod
kubectl logs pod-name -c container-name

# Stream logs
kubectl logs -f pod-name
```

---

**Q63. What is the difference between cluster-level and node-level logging?**

- **Container/Pod level**: `kubectl logs` fetches logs from the kubelet on the node
- **Cluster-level**: Requires a logging agent (Fluentd, Filebeat) to ship logs to a central store (Elasticsearch, Loki, CloudWatch)

---

**Q64. What metrics does the Kubernetes Metrics Server provide?**  
Metrics Server collects CPU and memory usage from kubelets and exposes them via the Metrics API. Used by HPA and `kubectl top`.

```bash
kubectl top nodes
kubectl top pods -n production
```

---

**Q65. What is Prometheus and how does it integrate with Kubernetes?**  
Prometheus is a time-series monitoring system. In Kubernetes:
- Uses **service discovery** to automatically find scrape targets
- Scrapes `/metrics` endpoints from Pods/Services
- `kube-state-metrics` exposes cluster object metrics
- `node-exporter` exposes node-level metrics
- Often deployed via the **kube-prometheus-stack** Helm chart

---

**Q66. What are liveness, readiness, and startup probes?**

| Probe | Purpose | On Failure |
|---|---|---|
| `livenessProbe` | Is the container alive? | Restart container |
| `readinessProbe` | Is the container ready to receive traffic? | Remove from Service endpoints |
| `startupProbe` | Has the app finished starting? | Prevents liveness from killing slow-starting apps |

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

## 10. Advanced Topics & Troubleshooting

**Q67. How do you troubleshoot a Pod stuck in `Pending` state?**

```bash
kubectl describe pod <pod-name>
# Look for: Events section — "Insufficient cpu/memory", "no nodes available", taint mismatch
kubectl get nodes  # Check if nodes are Ready
kubectl describe node <node-name>  # Check node capacity
```

Common causes:
- Insufficient resources on all nodes
- No nodes match nodeSelector/affinity
- Taint not tolerated
- PVC not bound

---

**Q68. How do you troubleshoot a Pod in `CrashLoopBackOff`?**

```bash
kubectl logs <pod-name> --previous   # Check last crash logs
kubectl describe pod <pod-name>      # Check exit code and events
kubectl exec -it <pod-name> -- /bin/sh  # If it's running briefly
```

Common causes: application error, wrong command/args, missing env var, OOMKilled (memory limit exceeded).

---

**Q69. How do you troubleshoot a Pod in `ImagePullBackOff`?**

```bash
kubectl describe pod <pod-name>
# Events: "Failed to pull image", "unauthorized", "not found"
```

Common causes:
- Wrong image name or tag
- Private registry with no imagePullSecret
- Registry unreachable

---

**Q70. What is `kubectl exec` used for?**

```bash
# Open shell in running container
kubectl exec -it pod-name -- /bin/bash

# Run one-off command
kubectl exec pod-name -- env
kubectl exec pod-name -- cat /etc/config/app.conf
```

---

**Q71. What is a Custom Resource Definition (CRD)?**  
CRDs extend the Kubernetes API by defining new resource types. Once a CRD is created, you can manage custom objects via `kubectl` just like built-in resources. Used extensively by operators (Prometheus Operator, ArgoCD, cert-manager).

---

**Q72. What is a Kubernetes Operator?**  
An Operator is a Kubernetes-native application that uses CRDs and controllers to automate complex stateful application management (install, upgrade, backup, failover). Examples: etcd-operator, Prometheus Operator, PostgreSQL Operator.

---

**Q73. What is Helm?**  
Helm is the package manager for Kubernetes. It uses **charts** (templates + default values) to deploy and manage applications. Key commands:

```bash
helm install my-app ./my-chart
helm upgrade my-app ./my-chart --set image.tag=1.2
helm rollback my-app 1
helm list
helm uninstall my-app
```

---

**Q74. What is a Helm chart structure?**

```
my-chart/
├── Chart.yaml          # Metadata
├── values.yaml         # Default values
├── templates/
│   ├── deployment.yaml
│   ├── service.yaml
│   └── _helpers.tpl    # Template helpers
└── charts/             # Sub-charts (dependencies)
```

---

**Q75. What is a Kubernetes context?**  
A context is a named combination of cluster, user, and namespace in `kubeconfig`. It lets you switch between clusters easily.

```bash
kubectl config get-contexts
kubectl config use-context prod-cluster
kubectl config current-context
```

---

**Q76. What is the difference between a label and an annotation?**

| | Label | Annotation |
|---|---|---|
| Purpose | Identify and select objects | Store arbitrary metadata |
| Queryable | Yes (selectors, kubectl -l) | No |
| Size limit | Small | Large (can hold JSON, URLs) |

---

**Q77. How does Kubernetes handle rolling updates with zero downtime?**

By configuring `maxSurge` and `maxUnavailable` in the Deployment strategy:

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1          # Extra pods above desired count during update
    maxUnavailable: 0    # No pods go down during update → zero downtime
```

---

**Q78. What is a Topology Spread Constraint?**  
It controls how Pods are spread across nodes, zones, or regions to improve availability:

```yaml
topologySpreadConstraints:
- maxSkew: 1
  topologyKey: topology.kubernetes.io/zone
  whenUnsatisfiable: DoNotSchedule
  labelSelector:
    matchLabels:
      app: web
```

---

**Q79. What is Kubernetes Federation?**  
Federation allows managing multiple Kubernetes clusters as a single entity, enabling cross-cluster service discovery and workload distribution. Replaced in newer patterns by tools like **ArgoCD**, **Flux**, or **Liqo** for multi-cluster management.

---

**Q80. What is the difference between `kubectl apply` and `kubectl replace`?**

- `kubectl apply`: Merges changes (preferred for GitOps)
- `kubectl replace`: Completely replaces the resource (fails if it doesn't exist)
- `kubectl replace --force`: Deletes and recreates the resource

---

**Q81. How do you expose a Deployment as a Service quickly?**

```bash
kubectl expose deployment nginx --port=80 --type=ClusterIP
kubectl expose deployment nginx --port=80 --type=NodePort
```

---

**Q82. What is a multi-tenant Kubernetes cluster?**  
A cluster shared by multiple teams/projects. Isolation is achieved via:
- Namespaces (logical separation)
- RBAC (access control per namespace)
- ResourceQuotas and LimitRanges (resource isolation)
- NetworkPolicies (traffic isolation)
- Node taints/affinity (physical isolation)

---

**Q83. How do you force delete a stuck namespace?**

```bash
kubectl get namespace stuck-ns -o json \
  | jq '.spec.finalizers = []' \
  | kubectl replace --raw /api/v1/namespaces/stuck-ns/finalize -f -
```

---

**Q84. What is a finalizer in Kubernetes?**  
A finalizer is a key in the `metadata.finalizers` field that prevents an object from being deleted until specific cleanup is done. Controllers remove the finalizer after cleanup, allowing deletion to proceed.

---

**Q85. What is a Webhook in Kubernetes?**

Two types:
- **MutatingAdmissionWebhook**: Modifies incoming API requests (e.g., inject sidecar, set defaults)
- **ValidatingAdmissionWebhook**: Validates requests and rejects invalid ones (e.g., enforce naming conventions, require labels)

Used by tools like Istio, OPA/Gatekeeper, Kyverno.

---

**Q86. What is OPA/Gatekeeper?**  
Open Policy Agent (OPA) with Gatekeeper is a policy engine for Kubernetes. It enforces custom policies using `ConstraintTemplates` and `Constraints` (e.g., "all Pods must have resource limits", "no latest tags allowed").

---

**Q87. What is a Service Mesh and when would you use it?**  
A service mesh (Istio, Linkerd) adds a layer of infrastructure for microservice communication:
- mTLS between services
- Traffic management (canary, A/B testing)
- Observability (distributed tracing, metrics per service)
- Circuit breaking and retries

Use when you have many microservices needing advanced traffic control and security.

---

**Q88. What is `kubectl port-forward` used for?**

```bash
# Forward local port 8080 to Pod port 80
kubectl port-forward pod/nginx-pod 8080:80

# Forward to a Service
kubectl port-forward svc/my-service 9090:80
```

Useful for debugging without exposing a Service externally.

---

**Q89. Explain the Kubernetes admission control flow.**

1. Request hits `kube-apiserver`
2. **Authentication** — Who are you?
3. **Authorization** — Are you allowed to do this? (RBAC)
4. **Admission Controllers** — Should this be allowed/modified?
   - MutatingAdmissionWebhooks run first
   - ValidatingAdmissionWebhooks run second
5. Object persisted to `etcd`

---

**Q90. How do you generate a YAML manifest without applying it?**

```bash
kubectl create deployment nginx --image=nginx --dry-run=client -o yaml > nginx-deploy.yaml
kubectl run test-pod --image=busybox --dry-run=client -o yaml
```

---

## CKA/CKAD Quick-Fire Style Questions

**Q91.** Set the image of container `app` in deployment `web` to `nginx:1.26`:
```bash
kubectl set image deployment/web app=nginx:1.26
```

**Q92.** Scale deployment `web` to 5 replicas:
```bash
kubectl scale deployment web --replicas=5
```

**Q93.** Create a Pod named `test` with image `busybox` that runs `sleep 3600`:
```bash
kubectl run test --image=busybox --command -- sleep 3600
```

**Q94.** Get all Pods sorted by creation time:
```bash
kubectl get pods --sort-by=.metadata.creationTimestamp
```

**Q95.** Label node `node1` with `env=production`:
```bash
kubectl label node node1 env=production
```

**Q96.** Get all Pods with label `app=nginx`:
```bash
kubectl get pods -l app=nginx
```

**Q97.** Delete all Pods in namespace `test`:
```bash
kubectl delete pods --all -n test
```

**Q98.** Check which node a Pod is running on:
```bash
kubectl get pod <pod-name> -o wide
```

**Q99.** Output the YAML definition of an existing Pod:
```bash
kubectl get pod <pod-name> -o yaml
```

**Q100.** Create a temporary debug Pod and delete it after:
```bash
kubectl run debug --image=busybox --rm -it --restart=Never -- /bin/sh
```

**Q101.** Find all resources in a namespace:
```bash
kubectl get all -n dev
```

**Q102.** Copy a file from a Pod to local machine:
```bash
kubectl cp <pod-name>:/path/in/pod ./local-path
```

**Q103.** View events in a namespace sorted by time:
```bash
kubectl get events -n dev --sort-by='.lastTimestamp'
```

**Q104.** Force delete a stuck Pod:
```bash
kubectl delete pod <pod-name> --grace-period=0 --force
```

**Q105.** Check API resources available in the cluster:
```bash
kubectl api-resources
kubectl api-versions
```

---

## Common Interview Scenario Questions

**Q106. Your app is not receiving traffic. How do you debug?**
1. Check Pod status: `kubectl get pods` — are they Running?
2. Check readiness probe: is Pod marked as Ready?
3. Check Service: `kubectl describe svc` — does it have Endpoints?
4. Check Endpoints: `kubectl get endpoints svc-name` — is Pod IP listed?
5. Check NetworkPolicy — is traffic blocked?
6. Test from inside cluster: `kubectl exec -it debug-pod -- curl http://svc-name`

---

**Q107. A node is NotReady. What do you check?**
```bash
kubectl describe node <node-name>    # Check conditions and events
kubectl get pods -n kube-system      # Is kubelet/kube-proxy running?
ssh node1
systemctl status kubelet             # Is kubelet healthy?
journalctl -u kubelet -n 50          # Check logs
df -h                                # Disk pressure?
free -m                              # Memory pressure?
```

---

**Q108. You need to run a one-time database migration job. How?**  
Use a Kubernetes **Job** with `restartPolicy: OnFailure`. The Job will retry on failure and mark complete when successful. Use an init container or a separate Job that runs before the Deployment is started.

---

**Q109. How do you ensure your app is highly available across zones?**
- Use Deployments with `replicas >= 3`
- Set `podAntiAffinity` to spread across zones
- Use `topologySpreadConstraints`
- Use a PodDisruptionBudget to maintain minimum replicas during disruptions
- Use a LoadBalancer or Ingress with zone-aware routing

---

**Q110. How would you implement blue-green deployment in Kubernetes?**
1. Deploy new version as separate Deployment (`app: blue` → `app: green`)
2. Both Deployments run simultaneously
3. Switch Service selector from `version: blue` to `version: green`
4. If OK, delete old Deployment; if not, revert selector

---

*Happy studying! For hands-on practice, use `minikube`, `kind`, or a managed cluster. The CKA exam is entirely hands-on — practice `kubectl` commands daily.*
