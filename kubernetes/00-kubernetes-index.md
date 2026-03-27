# ☸️ Kubernetes

A complete Kubernetes knowledge base — from core architecture to production-grade operations.

> Kubernetes is the most in-demand skill in German DevOps job postings. Every cloud-native company runs it. Understanding it deeply — not just the YAML — is what gets you hired.

---

## 🗺️ Learning Path

```
01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10
 │     │     │     │     │     │     │     │     │     │
 │     │     │     │     │     │     │     │     │     └── Interview prep
 │     │     │     │     │     │     │     │     └──────── Debug anything
 │     │     │     │     │     │     │     └────────────── HPA, VPA, metrics
 │     │     │     │     │     │     └──────────────────── Helm & packaging
 │     │     │     │     │     └────────────────────────── RBAC & security
 │     │     │     │     └──────────────────────────────── Config & secrets
 │     │     │     └────────────────────────────────────── Storage & PVCs
 │     │     └──────────────────────────────────────────── Services & DNS
 │     └────────────────────────────────────────────────── What workload to use
 └──────────────────────────────────────────────────────── How K8s works
```

---

## 📚 Contents

| # | File | What you'll learn |
|---|------|------------------|
| 01 | [Core Concepts & Architecture](./01-k8s-core-concepts.md) | Control plane, etcd, kubelet, scheduling, control loops, kubectl |
| 02 | [Workloads](./02-k8s-workloads.md) | Deployment, StatefulSet, DaemonSet, Job, CronJob, probes, resources |
| 03 | [Networking](./03-k8s-networking.md) | Services, Ingress, DNS, CNI, Network Policies, service mesh |
| 04 | [Storage](./04-k8s-storage.md) | PV, PVC, StorageClass, CSI drivers, volume snapshots |
| 05 | [Configuration & Secrets](./05-k8s-config-secrets.md) | ConfigMaps, Secrets, env injection, External Secrets Operator |
| 06 | [RBAC & Security](./06-k8s-rbac-security.md) | Roles, ServiceAccounts, Pod Security Standards, security contexts |
| 07 | [Helm](./07-k8s-helm.md) | Charts, releases, values, hooks, Helmfile |
| 08 | [Observability](./08-k8s-observability.md) | metrics-server, HPA, VPA, Cluster Autoscaler, events, logging |
| 09 | [Troubleshooting](./09-k8s-troubleshooting.md) | Pod failures, networking issues, storage problems, debug tools |
| 10 | [Interview Q&A](./10-k8s-interview-qa.md) | Core, scenario-based, and advanced interview questions |

---

## ⚡ Quick Reference

### Most-used kubectl commands

```bash
# Get resources
kubectl get pods -A
kubectl get pods -n production -o wide
kubectl get all -n production
kubectl get events --sort-by='.lastTimestamp' -n production

# Describe
kubectl describe pod my-pod
kubectl describe node worker-1
kubectl describe deployment my-app

# Logs
kubectl logs my-pod --previous              # crashed container
kubectl logs -l app=my-app -f              # follow all pods
kubectl logs my-pod -c sidecar             # specific container

# Exec
kubectl exec -it my-pod -- bash
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash

# Rollout
kubectl rollout status deployment/my-app
kubectl rollout undo deployment/my-app
kubectl rollout restart deployment/my-app

# Scale
kubectl scale deployment my-app --replicas=5

# Port forward
kubectl port-forward svc/my-svc 8080:80
kubectl port-forward pod/my-pod 8080:8080

# Resource usage
kubectl top nodes
kubectl top pods -A --sort-by=cpu
```

### Helm quick reference

```bash
helm repo add <n> <url> && helm repo update
helm search repo <chart>
helm install <release> <chart> --namespace <ns> --create-namespace
helm upgrade --install <release> <chart> --values values.yaml
helm list -A
helm rollback <release>
helm uninstall <release>
helm template ./my-chart --values values.yaml   # render locally
```

### Troubleshooting flow

```
Pod not running?
├── Pending → describe pod, check resources/nodeSelector/taints/PVC
├── CrashLoopBackOff → logs --previous, check OOMKilled/probes/app error
├── ImagePullBackOff → check image name, imagePullSecrets
├── ContainerCreating → check volumes, secrets, configmaps
└── Terminating (stuck) → force delete with --grace-period=0

Service issues?
├── No endpoints → selector doesn't match pod labels
├── DNS fails → check CoreDNS pods, pod /etc/resolv.conf
└── Ingress 404 → check ingressClassName, backend service, path rules

Node issues?
├── NotReady → check kubelet, disk pressure, memory pressure
└── Scheduling fails → check taints, nodeSelector, resource requests
```

---

## 🧠 Key Concepts at a Glance

| Concept | One-line summary |
|---------|-----------------|
| **Pod** | Smallest deployable unit — one or more containers sharing network/storage |
| **Deployment** | Manages stateless apps — rolling updates, rollbacks, scaling |
| **StatefulSet** | Manages stateful apps — stable identity, ordered ops, own PVC per pod |
| **DaemonSet** | One pod per node — agents, log shippers, monitoring |
| **etcd** | Source of truth — all cluster state stored here |
| **Control loop** | Observe → Diff → Act — how Kubernetes self-heals |
| **Scheduler** | Assigns pods to nodes based on resources and constraints |
| **kubelet** | Node agent — makes containers run as specified |
| **ClusterIP** | Internal-only Service — stable IP for service-to-service |
| **LoadBalancer** | External Service — provisions cloud load balancer |
| **Ingress** | L7 HTTP router — one LB for many services, handles TLS |
| **PVC** | Storage request from a pod — bound to a PV |
| **StorageClass** | Defines HOW to provision storage (driver, disk type) |
| **ConfigMap** | Non-sensitive config — injected as env vars or files |
| **Secret** | Sensitive data — base64 encoded, should be encrypted at rest |
| **RBAC** | Who can do what on which resources |
| **ServiceAccount** | Identity for pods — used to authenticate to the API |
| **HPA** | Scales pod replicas based on CPU/memory/custom metrics |
| **VPA** | Scales pod resource requests — makes pods bigger/smaller |
| **Helm** | Package manager — charts bundle all K8s resources for an app |
| **Taint** | Repels pods from a node (unless tolerated) |
| **Toleration** | Allows pod to be scheduled on tainted node |
| **PodDisruptionBudget** | Minimum pods always available during voluntary disruptions |
| **CrashLoopBackOff** | Pod keeps crashing — check logs --previous |
| **OOMKilled** | Container exceeded memory limit — exit code 137 |
| **ImagePullBackOff** | Can't pull image — check name, registry credentials |

---

## 🗂️ Folder Structure

```
kubernetes/
├── 00-kubernetes-index.md          ← You are here
├── 01-k8s-core-concepts.md
├── 02-k8s-workloads.md
├── 03-k8s-networking.md
├── 04-k8s-storage.md
├── 05-k8s-config-secrets.md
├── 06-k8s-rbac-security.md
├── 07-k8s-helm.md
├── 08-k8s-observability.md
├── 09-k8s-troubleshooting.md
└── 10-k8s-interview-qa.md
```

---

## 🔗 How Kubernetes Connects to the Rest of Your Notes

| Topic | Connection |
|-------|-----------|
| **Linux** | Containers use namespaces, cgroups, overlayfs — all Linux primitives |
| **Observability** | Prometheus, Grafana, Loki all deployed via Helm on K8s |
| **Ansible** | Provision K8s nodes with Ansible, deploy apps via playbooks |
| **Networking** | CNI implements Linux networking, iptables for Services |
| **Storage** | PVCs map to Linux block devices, CSI drivers use Linux storage |

---

*Notes are living documents — updated as I learn and build.*
