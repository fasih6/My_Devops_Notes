# Kubernetes Interview Q&A — Intermediate Level

> **Level**: Intermediate  
> **Format**: Mix of concise answers, bullet points, tables, and code snippets  
> **Prerequisite**: Beginner level completed  
> **Total**: 120+ questions across 10 intermediate topic sections

---

## Table of Contents

1. [Scheduling & Node Management](#1-scheduling--node-management)
2. [Taints, Tolerations & Affinity](#2-taints-tolerations--affinity)
3. [StatefulSets & DaemonSets](#3-statefulsets--daemonsets)
4. [Jobs & CronJobs](#4-jobs--cronjobs)
5. [Ingress & Ingress Controllers](#5-ingress--ingress-controllers)
6. [NetworkPolicy](#6-networkpolicy)
7. [RBAC & Security](#7-rbac--security)
8. [Resource Management & Autoscaling](#8-resource-management--autoscaling)
9. [Probes, Init Containers & Sidecar Pattern](#9-probes-init-containers--sidecar-pattern)
10. [Intermediate Troubleshooting](#10-intermediate-troubleshooting)

---

## 1. Scheduling & Node Management

---

**Q1. How does the Kubernetes scheduler decide where to place a Pod?**

The scheduler works in two phases:

1. **Filtering** — eliminates nodes that don't meet Pod requirements:
   - Insufficient CPU/memory
   - Node selector mismatch
   - Taint not tolerated
   - Volume zone constraints

2. **Scoring** — ranks remaining nodes using priority functions:
   - Least requested resources
   - Node affinity preference weight
   - Pod topology spread

The Pod is assigned to the highest-scoring node.

---

**Q2. What is a nodeSelector and how is it different from nodeAffinity?**

| Feature | `nodeSelector` | `nodeAffinity` |
|---|---|---|
| Syntax | Simple key=value | Rich expression-based rules |
| Operators | Only equality | In, NotIn, Exists, Gt, Lt |
| Required vs preferred | Required only | Both required and preferred |
| Recommended | Basic use | Preferred; more powerful |

```yaml
# nodeSelector (simple)
spec:
  nodeSelector:
    disktype: ssd

# nodeAffinity (rich)
spec:
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

**Q3. What does `requiredDuringSchedulingIgnoredDuringExecution` mean?**

This is a node affinity rule type. Breaking it down:

- `requiredDuringScheduling` — Pod **must** be placed on a matching node; if none found, Pod stays Pending
- `IgnoredDuringExecution` — if a node's labels change after the Pod is already running, the Pod is **not evicted**

The counterpart `preferredDuringSchedulingIgnoredDuringExecution` is a soft preference — scheduler tries to match but proceeds anyway if it can't.

---

**Q4. How do you manually assign a Pod to a specific node?**

Two ways:

**Method 1 — `nodeName` (bypasses scheduler):**
```yaml
spec:
  nodeName: worker-node-1
```

**Method 2 — `nodeSelector` (uses scheduler):**
```yaml
spec:
  nodeSelector:
    kubernetes.io/hostname: worker-node-1
```

---

**Q5. How do you cordon and uncordon a node?**

```bash
# Cordon: mark node as unschedulable (no new Pods)
kubectl cordon node1

# Uncordon: re-enable scheduling on the node
kubectl uncordon node1

# Check node status
kubectl get nodes
# STATUS shows: Ready,SchedulingDisabled when cordoned
```

Existing Pods continue running on a cordoned node.

---

**Q6. What is `kubectl drain` and when do you use it?**

`drain` is used to **safely evict all Pods** from a node before maintenance (OS patching, hardware replacement). It:
1. Cordons the node (no new Pods scheduled)
2. Gracefully evicts all running Pods (respecting PodDisruptionBudgets)

```bash
kubectl drain node1 \
  --ignore-daemonsets \       # DaemonSet Pods can't be evicted
  --delete-emptydir-data \    # Allow eviction of Pods with emptyDir volumes
  --grace-period=60           # Wait 60s for graceful shutdown
```

After maintenance:
```bash
kubectl uncordon node1
```

---

**Q7. What is the difference between cordoning and draining a node?**

| Action | New Pods | Running Pods |
|---|---|---|
| `cordon` | ❌ Blocked | ✅ Continue running |
| `drain` | ❌ Blocked | 🔄 Evicted gracefully |

---

**Q8. How do you label a node and use it for scheduling?**

```bash
# Add label to node
kubectl label node node1 env=production
kubectl label node node2 disktype=ssd

# Remove label
kubectl label node node1 env-

# Show node labels
kubectl get nodes --show-labels
```

Then reference in Pod spec:
```yaml
spec:
  nodeSelector:
    disktype: ssd
```

---

**Q9. What happens if no node matches a Pod's scheduling requirements?**

The Pod remains in `Pending` state. You can diagnose it with:

```bash
kubectl describe pod <pod-name>
# Look at Events section:
# "0/3 nodes are available: 3 Insufficient cpu"
# "0/3 nodes are available: 3 node(s) didn't match Pod's node affinity"
```

---

**Q10. What is the `IgnoredDuringExecution` part of affinity rules?**

It means that affinity rules are only evaluated **at scheduling time**. Once a Pod is running, if the node's labels change (violating the affinity rule), the Pod is **not automatically evicted**. A future `requiredDuringSchedulingRequiredDuringExecution` type (planned) would evict such Pods.

---

## 2. Taints, Tolerations & Affinity

---

**Q11. What is a taint in Kubernetes?**

A taint is applied to a **node** to repel Pods from being scheduled on it — unless those Pods explicitly tolerate the taint. It's used to:
- Reserve nodes for specific workloads (e.g., GPU nodes)
- Mark nodes as unschedulable for general workloads
- Indicate a problem with a node (e.g., node is not ready)

```bash
# Apply a taint
kubectl taint nodes node1 dedicated=gpu:NoSchedule

# Remove a taint (note the trailing -)
kubectl taint nodes node1 dedicated=gpu:NoSchedule-

# View taints on a node
kubectl describe node node1 | grep Taints
```

---

**Q12. What are the three taint effects?**

| Effect | Behavior |
|---|---|
| `NoSchedule` | Pods without matching toleration are **not scheduled** on this node |
| `PreferNoSchedule` | Kubernetes **tries** to avoid scheduling Pods here, but not guaranteed |
| `NoExecute` | Existing Pods without toleration are **evicted**; new ones not scheduled |

---

**Q13. What is a toleration?**

A toleration is applied to a **Pod** to allow it to be scheduled on tainted nodes. Without a toleration, a Pod will not be placed on a tainted node.

```yaml
spec:
  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "gpu"
    effect: "NoSchedule"
```

- `operator: Equal` — key and value must match exactly
- `operator: Exists` — only key must match (any value)

---

**Q14. How do taints and tolerations work together? Give a real-world example.**

**Scenario**: You have GPU nodes that should only run ML workloads.

```bash
# Taint the GPU node
kubectl taint nodes gpu-node-1 hardware=gpu:NoSchedule
```

Regular Pods won't be scheduled there. Only ML Pods with the right toleration will:

```yaml
spec:
  tolerations:
  - key: "hardware"
    operator: "Equal"
    value: "gpu"
    effect: "NoSchedule"
  nodeSelector:
    hardware: gpu
```

> Note: Tolerations allow Pods **onto** a tainted node — they don't **force** the Pod there. You still need nodeSelector or nodeAffinity to guarantee placement.

---

**Q15. What is the difference between taints/tolerations and node affinity?**

| Feature | Taints & Tolerations | Node Affinity |
|---|---|---|
| Direction | Node repels Pods | Pod attracted to nodes |
| Control | Node-side | Pod-side |
| Use case | Restrict access to nodes | Preference/requirement for nodes |
| Eviction support | Yes (NoExecute) | No |

They are **complementary** — use both together for precise scheduling control.

---

**Q16. What is Pod affinity?**

Pod affinity allows a Pod to be scheduled **near** other Pods (on the same node, zone, or rack) that match a label selector. Useful for co-locating services that communicate frequently.

```yaml
affinity:
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app: cache
      topologyKey: kubernetes.io/hostname
```

This means: "Schedule me on a node that already has a Pod with label `app=cache`."

---

**Q17. What is Pod anti-affinity?**

Pod anti-affinity does the opposite — it schedules Pods **away** from other Pods with matching labels. Used to spread replicas across nodes/zones for high availability.

```yaml
affinity:
  podAntiAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          app: web
      topologyKey: kubernetes.io/hostname
```

This means: "Don't schedule me on a node that already has a Pod with label `app=web`." — ensures one replica per node.

---

**Q18. What is `topologyKey` in affinity rules?**

`topologyKey` defines the scope of the affinity rule — which node label to use as the "topology domain." Common values:

| topologyKey | Scope |
|---|---|
| `kubernetes.io/hostname` | Per node |
| `topology.kubernetes.io/zone` | Per availability zone |
| `topology.kubernetes.io/region` | Per region |

---

**Q19. What are system-added taints in Kubernetes?**

Kubernetes automatically taints nodes under certain conditions:

| Taint | Reason |
|---|---|
| `node.kubernetes.io/not-ready` | Node is not ready |
| `node.kubernetes.io/unreachable` | Node controller can't reach node |
| `node.kubernetes.io/memory-pressure` | Node has memory pressure |
| `node.kubernetes.io/disk-pressure` | Node has disk pressure |
| `node.kubernetes.io/unschedulable` | Node is cordoned |

Pods with `NoExecute` toleration and `tolerationSeconds` can stay running temporarily during node issues.

---

**Q20. How do you tolerate all taints (run anywhere)?**

```yaml
tolerations:
- operator: "Exists"   # Tolerates all keys, values, and effects
```

This is used by DaemonSet Pods that must run on every node regardless of taints.

---

## 3. StatefulSets & DaemonSets

---

**Q21. What is a StatefulSet and when should you use it?**

A StatefulSet manages **stateful applications** where each Pod needs a stable identity. Unlike Deployments, StatefulSets provide:
- **Stable, unique Pod names** — `web-0`, `web-1`, `web-2` (not random hashes)
- **Stable persistent storage** — each Pod gets its own PVC that follows it
- **Ordered deployment/scaling** — Pods start and stop in order

Use for: MySQL, PostgreSQL, Kafka, Zookeeper, Elasticsearch, Redis Cluster.

---

**Q22. What is the difference between a Deployment and a StatefulSet?**

| Feature | Deployment | StatefulSet |
|---|---|---|
| Pod names | Random hash suffix | Stable ordinal (`web-0`, `web-1`) |
| Storage | Shared or none | Each Pod gets its own PVC |
| Scaling order | Parallel (by default) | Ordered (0 → 1 → 2) |
| Delete order | Any order | Reverse order (2 → 1 → 0) |
| Use case | Stateless apps | Stateful apps (databases) |
| Pod identity | Interchangeable | Unique and stable |

---

**Q23. Write a basic StatefulSet YAML.**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: "mysql"       # Headless service name (required)
  replicas: 3
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
      - name: mysql
        image: mysql:8.0
        env:
        - name: MYSQL_ROOT_PASSWORD
          valueFrom:
            secretKeyRef:
              name: mysql-secret
              key: password
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
  volumeClaimTemplates:       # Each Pod gets its own PVC
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 10Gi
```

---

**Q24. What is a headless Service and why does StatefulSet need it?**

A headless Service (with `clusterIP: None`) does not provide load balancing. Instead, DNS returns the IPs of **individual Pods** directly.

StatefulSets need a headless Service so each Pod gets a **stable DNS name**:
```
<pod-name>.<service-name>.<namespace>.svc.cluster.local
# e.g.:
mysql-0.mysql.default.svc.cluster.local
mysql-1.mysql.default.svc.cluster.local
```

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  clusterIP: None          # Headless
  selector:
    app: mysql
  ports:
  - port: 3306
```

---

**Q25. What happens to StatefulSet PVCs when you delete the StatefulSet?**

PVCs created by `volumeClaimTemplates` are **NOT deleted** when the StatefulSet is deleted. You must delete them manually. This is intentional — to prevent accidental data loss.

```bash
kubectl delete statefulset mysql
kubectl get pvc                     # PVCs still exist
kubectl delete pvc data-mysql-0     # Manual cleanup
```

---

**Q26. What is a DaemonSet?**

A DaemonSet ensures that **one Pod runs on every node** (or a subset of nodes) in the cluster. When a new node is added, a Pod is automatically scheduled on it. When a node is removed, the Pod is garbage collected.

Common uses:
- Log collection agents (Fluentd, Filebeat)
- Monitoring agents (Prometheus Node Exporter, Datadog Agent)
- Network plugins (Calico, Weave, Cilium)
- Storage daemons (Ceph, GlusterFS)

---

**Q27. Write a basic DaemonSet YAML.**

```yaml
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: node-exporter
  namespace: monitoring
spec:
  selector:
    matchLabels:
      app: node-exporter
  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      tolerations:
      - operator: Exists         # Run on ALL nodes including tainted ones
      containers:
      - name: node-exporter
        image: prom/node-exporter:latest
        ports:
        - containerPort: 9100
          hostPort: 9100         # Expose on the node's port directly
```

---

**Q28. How is a DaemonSet different from a Deployment?**

| Feature | Deployment | DaemonSet |
|---|---|---|
| Replicas | Fixed number you define | One per node (auto) |
| Pod placement | Scheduler decides | One per matching node |
| Use case | Stateless apps with N replicas | Node-level agents |
| Scaling | `kubectl scale` | Scales with cluster nodes |

---

**Q29. Can a DaemonSet run on only some nodes?**

Yes — using `nodeSelector` or `nodeAffinity` in the DaemonSet's Pod template:

```yaml
spec:
  template:
    spec:
      nodeSelector:
        node-role: worker      # Only on worker nodes
```

---

**Q30. How do you update a DaemonSet?**

```bash
kubectl set image daemonset/node-exporter node-exporter=prom/node-exporter:v1.7.0

# Check rollout
kubectl rollout status daemonset/node-exporter
kubectl rollout history daemonset/node-exporter
```

Update strategies: `RollingUpdate` (default) or `OnDelete` (manual control).

---

## 4. Jobs & CronJobs

---

**Q31. What is a Job in Kubernetes?**

A Job creates one or more Pods and ensures they **run to completion** successfully. If a Pod fails, the Job retries it. Once all Pods complete successfully, the Job is done.

Used for: batch processing, database migrations, report generation, data imports.

---

**Q32. Write a basic Job YAML.**

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
spec:
  completions: 1             # Number of successful Pod completions needed
  parallelism: 1             # How many Pods run in parallel
  backoffLimit: 3            # Retry up to 3 times on failure
  template:
    spec:
      restartPolicy: OnFailure   # Required for Jobs (Never or OnFailure)
      containers:
      - name: migrate
        image: my-app:latest
        command: ["python", "manage.py", "migrate"]
```

---

**Q33. What restart policies are valid for Jobs?**

Jobs only support:
- `OnFailure` — restart container on failure (within same Pod)
- `Never` — create a new Pod on failure (old Pod stays for debugging)

`Always` is NOT valid for Jobs — it would loop forever.

---

**Q34. What is a parallel Job?**

A parallel Job runs multiple Pods simultaneously:

```yaml
spec:
  completions: 10      # Need 10 successful completions total
  parallelism: 3       # Run 3 at a time
```

Kubernetes creates up to 3 Pods at once, and continues until 10 complete successfully.

---

**Q35. What is a CronJob?**

A CronJob runs Jobs on a **scheduled basis** using standard cron syntax. It creates a new Job at each scheduled time.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: nightly-backup
spec:
  schedule: "0 2 * * *"          # Run at 2:00 AM every day
  jobTemplate:
    spec:
      template:
        spec:
          restartPolicy: OnFailure
          containers:
          - name: backup
            image: backup-tool:latest
            command: ["/backup.sh"]
  successfulJobsHistoryLimit: 3  # Keep last 3 successful jobs
  failedJobsHistoryLimit: 1      # Keep last 1 failed job
```

---

**Q36. What is the cron syntax used in CronJobs?**

```
┌───────────── minute (0–59)
│ ┌───────────── hour (0–23)
│ │ ┌───────────── day of month (1–31)
│ │ │ ┌───────────── month (1–12)
│ │ │ │ ┌───────────── day of week (0–6, Sunday=0)
│ │ │ │ │
* * * * *
```

| Schedule | Meaning |
|---|---|
| `0 * * * *` | Every hour at :00 |
| `*/5 * * * *` | Every 5 minutes |
| `0 0 * * *` | Every day at midnight |
| `0 9 * * 1` | Every Monday at 9 AM |
| `0 0 1 * *` | First day of every month at midnight |

---

**Q37. What happens if a CronJob misses its schedule?**

If the cluster is down or the CronJob controller misses a schedule, `startingDeadlineSeconds` controls whether a missed job should still be triggered:

```yaml
spec:
  schedule: "0 2 * * *"
  startingDeadlineSeconds: 3600  # Trigger if missed within last 1 hour
```

If more than 100 schedules are missed, the CronJob stops scheduling new Jobs.

---

**Q38. How do you manually trigger a CronJob?**

```bash
kubectl create job manual-run --from=cronjob/nightly-backup
```

---

**Q39. How do you check Job status and logs?**

```bash
kubectl get jobs
kubectl describe job db-migration
kubectl get pods --selector=job-name=db-migration
kubectl logs <pod-name>          # View job output
```

---

**Q40. What is `concurrencyPolicy` in CronJobs?**

Controls what happens if a new Job is triggered while the previous one is still running:

| Policy | Behavior |
|---|---|
| `Allow` (default) | Multiple Jobs can run concurrently |
| `Forbid` | Skip new Job if previous is still running |
| `Replace` | Cancel previous Job, start new one |

---

## 5. Ingress & Ingress Controllers

---

**Q41. What is an Ingress in Kubernetes?**

An Ingress is a Kubernetes API object that manages **external HTTP/HTTPS access** to Services inside the cluster. It provides:
- Host-based routing (`app.example.com` → Service A)
- Path-based routing (`/api` → Service B, `/web` → Service C)
- TLS termination
- Name-based virtual hosting

> Think of Ingress as a smart reverse proxy at the cluster edge.

---

**Q42. What is an Ingress Controller?**

An Ingress object alone does nothing — it needs an **Ingress Controller** to implement the rules. The controller is a Pod (usually a reverse proxy) that watches Ingress objects and configures routing.

Popular Ingress Controllers:
- **Nginx Ingress Controller** (most common)
- **Traefik**
- **HAProxy**
- **AWS ALB Ingress Controller**
- **Kong**

---

**Q43. What is the difference between a Service and an Ingress?**

| Feature | Service | Ingress |
|---|---|---|
| OSI Layer | L4 (TCP/UDP) | L7 (HTTP/HTTPS) |
| Routing | By IP:port | By hostname and URL path |
| TLS termination | ❌ | ✅ |
| Path-based routing | ❌ | ✅ |
| Requires controller | No | Yes (Ingress Controller) |

---

**Q44. Write an Ingress manifest with host and path-based routing.**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
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
              number: 8080
      - path: /
        pathType: Prefix
        backend:
          service:
            name: frontend-service
            port:
              number: 80
  - host: admin.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: admin-service
            port:
              number: 80
```

---

**Q45. How do you add TLS to an Ingress?**

```yaml
spec:
  tls:
  - hosts:
    - app.example.com
    secretName: app-tls-secret    # Secret with tls.crt and tls.key

---
# Create TLS secret
kubectl create secret tls app-tls-secret \
  --cert=tls.crt \
  --key=tls.key
```

---

**Q46. What are Ingress path types?**

| PathType | Behavior |
|---|---|
| `Exact` | Matches the exact URL path only |
| `Prefix` | Matches paths starting with the given prefix |
| `ImplementationSpecific` | Behavior depends on the Ingress controller |

---

**Q47. What is an IngressClass?**

An IngressClass specifies which Ingress Controller should handle an Ingress object. Useful when multiple controllers are running in the same cluster.

```yaml
spec:
  ingressClassName: nginx    # Use the nginx controller

# Or set a default IngressClass
kubectl annotate ingressclass nginx \
  ingressclass.kubernetes.io/is-default-class=true
```

---

**Q48. How do you get the external IP of an Ingress?**

```bash
kubectl get ingress
# Shows: NAME, CLASS, HOSTS, ADDRESS, PORTS, AGE
# ADDRESS is the external IP assigned by the cloud load balancer
```

---

**Q49. Can you use Ingress without a domain name (by IP)?**

Yes, by omitting the `host` field — the rule applies to all incoming traffic:

```yaml
rules:
- http:
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

**Q50. What is the difference between Ingress and a LoadBalancer Service?**

| | LoadBalancer Service | Ingress |
|---|---|---|
| Protocol | TCP/UDP (L4) | HTTP/HTTPS (L7) |
| Cost | 1 cloud LB per Service | 1 cloud LB for all Services |
| Path/Host routing | ❌ | ✅ |
| TLS termination | ❌ | ✅ |
| Best for | Non-HTTP services | Multiple HTTP services |

---

## 6. NetworkPolicy

---

**Q51. What is a NetworkPolicy in Kubernetes?**

A NetworkPolicy is a Kubernetes resource that controls **traffic flow between Pods** at the IP/port level. By default, all Pods can communicate with all other Pods. NetworkPolicies let you restrict this.

> NetworkPolicies require a **CNI plugin** that supports them (Calico, Cilium, Weave). Flannel does NOT support NetworkPolicy by default.

---

**Q52. What is the default networking behavior in Kubernetes?**

By default, Kubernetes is **fully open**:
- All Pods can communicate with all other Pods (in any namespace)
- All Pods can reach external IPs

Once you create a NetworkPolicy that selects a Pod, that Pod's unmatched traffic is **denied**.

---

**Q53. How do you deny all ingress traffic to Pods in a namespace?**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: production
spec:
  podSelector: {}          # Selects ALL Pods in namespace
  policyTypes:
  - Ingress                # Only restrict ingress
  # No ingress rules = deny all ingress
```

---

**Q54. How do you allow only specific Pods to communicate?**

Allow only Pods with label `role=frontend` to reach Pods with label `role=backend` on port 8080:

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: default
spec:
  podSelector:
    matchLabels:
      role: backend          # This policy applies to backend Pods
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: frontend     # Only allow from frontend Pods
    ports:
    - protocol: TCP
      port: 8080
```

---

**Q55. How do you allow traffic from a specific namespace?**

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        kubernetes.io/metadata.name: monitoring   # Allow from monitoring namespace
```

---

**Q56. How do you allow both a specific namespace AND specific Pods (AND condition)?**

```yaml
ingress:
- from:
  - namespaceSelector:
      matchLabels:
        env: production
    podSelector:             # Same list item = AND condition
      matchLabels:
        app: prometheus
```

> **Separate list items = OR condition. Same list item = AND condition.** This is a common interview question!

---

**Q57. How do you allow egress traffic to specific IPs (external)?**

```yaml
spec:
  podSelector:
    matchLabels:
      app: my-app
  policyTypes:
  - Egress
  egress:
  - to:
    - ipBlock:
        cidr: 10.0.0.0/24
        except:
        - 10.0.0.1/32        # Exclude specific IP
    ports:
    - port: 5432
      protocol: TCP
```

---

**Q58. Does a NetworkPolicy affect the node network?**

No. NetworkPolicies only apply to **Pod-to-Pod traffic**. Node-level traffic and traffic to/from the host network are not affected.

---

**Q59. How do you allow DNS egress so Pods can resolve names?**

If you apply a default deny-all egress policy, you must explicitly allow DNS:

```yaml
egress:
- ports:
  - port: 53
    protocol: UDP
  - port: 53
    protocol: TCP
```

Without this, Pods won't be able to resolve service names.

---

**Q60. How do you verify NetworkPolicy is working?**

```bash
# Create a test Pod and try to reach the target
kubectl run test --image=busybox --rm -it --restart=Never -- wget -O- http://backend-svc:8080

# Check if CNI supports NetworkPolicy
kubectl get pods -n kube-system | grep -i calico   # or cilium, weave
```

---

## 7. RBAC & Security

---

**Q61. What is RBAC in Kubernetes?**

Role-Based Access Control (RBAC) is the authorization mechanism that controls **who can do what on which resources**. It is enabled by default in Kubernetes 1.6+.

Four key objects:
- **Role** — defines permissions within a namespace
- **ClusterRole** — defines permissions cluster-wide
- **RoleBinding** — binds a Role to subjects in a namespace
- **ClusterRoleBinding** — binds a ClusterRole cluster-wide

---

**Q62. What is the structure of a Role?**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: dev
rules:
- apiGroups: [""]            # "" = core API group (pods, services, etc.)
  resources: ["pods"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list"]
```

Common verbs: `get`, `list`, `watch`, `create`, `update`, `patch`, `delete`

---

**Q63. What is the difference between a Role and a ClusterRole?**

| Role | ClusterRole |
|---|---|
| Namespace-scoped | Cluster-scoped |
| Grants access to resources in one namespace | Grants access across all namespaces or to cluster-scoped resources |
| Used with RoleBinding | Used with ClusterRoleBinding (or RoleBinding for namespace use) |

> A ClusterRole can be bound with a **RoleBinding** to limit it to a specific namespace.

---

**Q64. How do you bind a Role to a user?**

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: pod-reader-binding
  namespace: dev
subjects:
- kind: User
  name: jane                 # Username
  apiGroup: rbac.authorization.k8s.io
- kind: Group
  name: dev-team
  apiGroup: rbac.authorization.k8s.io
- kind: ServiceAccount
  name: my-sa
  namespace: dev
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

---

**Q65. What is a ServiceAccount?**

A ServiceAccount provides an **identity for Pods** to authenticate with the Kubernetes API. Each namespace has a `default` ServiceAccount. Pods use it to make API calls.

```bash
# Create a ServiceAccount
kubectl create serviceaccount my-app-sa -n dev

# Bind a Role to the ServiceAccount
kubectl create rolebinding my-app-binding \
  --role=pod-reader \
  --serviceaccount=dev:my-app-sa \
  -n dev
```

---

**Q66. How do you check if a user/SA has permission to perform an action?**

```bash
# Check your own permissions
kubectl auth can-i create pods
kubectl auth can-i delete deployments -n production

# Check as another user
kubectl auth can-i create pods --as=jane
kubectl auth can-i create pods --as=jane -n dev

# Check as a ServiceAccount
kubectl auth can-i list secrets --as=system:serviceaccount:dev:my-app-sa

# List all permissions for current user
kubectl auth can-i --list
kubectl auth can-i --list --as=jane -n dev
```

---

**Q67. What are the default ClusterRoles in Kubernetes?**

| ClusterRole | Description |
|---|---|
| `cluster-admin` | Full access to everything |
| `admin` | Full access within a namespace |
| `edit` | Read/write access to most resources |
| `view` | Read-only access to most resources |

---

**Q68. What is a SecurityContext in Kubernetes?**

A SecurityContext defines security settings for a Pod or container:

```yaml
# Pod-level
spec:
  securityContext:
    runAsUser: 1000          # Run as non-root user
    runAsGroup: 3000
    fsGroup: 2000            # File system group for volumes

  containers:
  - name: app
    # Container-level (overrides Pod-level)
    securityContext:
      allowPrivilegeEscalation: false
      readOnlyRootFilesystem: true
      capabilities:
        drop: ["ALL"]
        add: ["NET_BIND_SERVICE"]
```

---

**Q69. What is Pod Security Admission (PSA)?**

PSA is Kubernetes' built-in mechanism to enforce security standards on Pods (replaced PodSecurityPolicy in K8s 1.25+). It operates at the namespace level with three profiles:

| Profile | Description |
|---|---|
| `privileged` | No restrictions |
| `baseline` | Prevents known privilege escalations |
| `restricted` | Heavily restricted; follows security best practices |

```bash
# Apply baseline policy to a namespace
kubectl label namespace dev pod-security.kubernetes.io/enforce=baseline
```

---

**Q70. What are RBAC best practices?**

- Use **least privilege** — only grant what's needed
- Prefer **Roles over ClusterRoles** when namespace-scoped access is sufficient
- Use **Groups** instead of individual users
- Avoid binding `cluster-admin` to service accounts
- Regularly audit permissions: `kubectl auth can-i --list`
- Use dedicated ServiceAccounts per application (don't use `default`)

---

## 8. Resource Management & Autoscaling

---

**Q71. What are resource requests and limits?**

- **Request**: The minimum amount of CPU/memory guaranteed to the container. Used by the scheduler for Pod placement.
- **Limit**: The maximum CPU/memory the container can use. Enforced by the kubelet/cgroups.

```yaml
resources:
  requests:
    cpu: "250m"        # 250 millicores = 0.25 CPU core
    memory: "128Mi"    # 128 mebibytes
  limits:
    cpu: "500m"
    memory: "256Mi"
```

---

**Q72. What happens when a container exceeds its resource limits?**

| Resource | What happens when limit is exceeded |
|---|---|
| CPU | Container is **throttled** (slowed down) — not killed |
| Memory | Container is **OOMKilled** (killed by the OOM killer) and restarted |

```bash
# Check for OOMKilled containers
kubectl describe pod <pod-name>
# Look for: "OOMKilled" in Last State
```

---

**Q73. What are CPU units in Kubernetes?**

CPU resources are measured in **millicores (m)**:
- `1000m` = 1 CPU core
- `500m` = 0.5 CPU core
- `250m` = 0.25 CPU core

You can also write `0.5` instead of `500m`.

---

**Q74. What is a LimitRange?**

A LimitRange sets default and min/max resource constraints for containers in a namespace. Prevents containers from being created without limits:

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: cpu-memory-limits
  namespace: dev
spec:
  limits:
  - type: Container
    default:              # Applied if no limit is specified
      cpu: "500m"
      memory: "256Mi"
    defaultRequest:       # Applied if no request is specified
      cpu: "100m"
      memory: "64Mi"
    max:                  # Hard ceiling
      cpu: "2"
      memory: "1Gi"
    min:                  # Hard floor
      cpu: "50m"
      memory: "32Mi"
```

---

**Q75. What is a ResourceQuota?**

A ResourceQuota limits the total resources consumed by all objects in a namespace:

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: namespace-quota
  namespace: dev
spec:
  hard:
    pods: "10"
    requests.cpu: "4"
    requests.memory: "4Gi"
    limits.cpu: "8"
    limits.memory: "8Gi"
    persistentvolumeclaims: "5"
    services: "5"
    secrets: "10"
    configmaps: "10"
```

---

**Q76. What is the difference between LimitRange and ResourceQuota?**

| LimitRange | ResourceQuota |
|---|---|
| Per-container/Pod limits | Namespace-wide totals |
| Sets defaults for individual resources | Limits total resource consumption |
| Controls individual object size | Controls aggregate usage |

---

**Q77. What is the Horizontal Pod Autoscaler (HPA)?**

HPA automatically scales the **number of Pod replicas** in a Deployment (or ReplicaSet/StatefulSet) based on observed metrics (CPU, memory, custom metrics).

```bash
# Create HPA imperatively
kubectl autoscale deployment nginx-deploy \
  --cpu-percent=70 \
  --min=2 \
  --max=10
```

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: nginx-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: nginx-deploy
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

---

**Q78. What does HPA require to work?**

HPA requires the **Metrics Server** to be installed in the cluster. Metrics Server collects CPU/memory usage from kubelets and exposes them via the `metrics.k8s.io` API.

```bash
kubectl top pods          # Requires Metrics Server
kubectl top nodes
kubectl get hpa           # Shows current/target metrics
```

---

**Q79. What is the Vertical Pod Autoscaler (VPA)?**

VPA automatically adjusts **CPU and memory requests/limits** for containers based on historical usage. Instead of changing replica count (like HPA), it changes the resource allocation per Pod.

- Modes: `Off` (recommendations only), `Initial` (set at Pod start), `Auto` (update running Pods)
- VPA and HPA should not both scale on CPU for the same Deployment (conflict)

---

**Q80. What is a QoS class in Kubernetes?**

Kubernetes assigns a **Quality of Service (QoS)** class to each Pod based on resource settings:

| QoS Class | Condition | Eviction Priority |
|---|---|---|
| `Guaranteed` | requests == limits for all containers | Last to be evicted |
| `Burstable` | requests < limits, or only some containers set limits | Middle priority |
| `BestEffort` | No requests or limits set at all | First to be evicted |

```bash
kubectl describe pod <pod-name> | grep "QoS Class"
```

---

## 9. Probes, Init Containers & Sidecar Pattern

---

**Q81. What are the three types of probes in Kubernetes?**

| Probe | Question It Answers | On Failure |
|---|---|---|
| `livenessProbe` | Is the container still alive? | Restart the container |
| `readinessProbe` | Is the container ready to serve traffic? | Remove from Service endpoints |
| `startupProbe` | Has the application finished starting up? | Restart the container |

---

**Q82. What are the probe mechanisms?**

| Mechanism | Description |
|---|---|
| `httpGet` | HTTP GET request; success if 200–399 |
| `tcpSocket` | TCP connection attempt; success if port opens |
| `exec` | Run a command in the container; success if exit code 0 |
| `grpc` | gRPC health check (K8s 1.24+) |

---

**Q83. Write a complete probe configuration example.**

```yaml
containers:
- name: app
  image: my-app:latest
  startupProbe:
    httpGet:
      path: /healthz
      port: 8080
    failureThreshold: 30      # Try 30 times
    periodSeconds: 10         # Every 10s → allows 5 min for startup
  livenessProbe:
    httpGet:
      path: /healthz
      port: 8080
    initialDelaySeconds: 0    # After startupProbe succeeds
    periodSeconds: 10
    failureThreshold: 3
    timeoutSeconds: 5
  readinessProbe:
    httpGet:
      path: /ready
      port: 8080
    initialDelaySeconds: 5
    periodSeconds: 5
    successThreshold: 1
    failureThreshold: 3
```

---

**Q84. What is `initialDelaySeconds` in a probe?**

How long to wait after the container starts before the first probe is executed. Useful for apps that take time to initialize. If set too low, the container may be killed before it finishes starting.

`startupProbe` is the modern solution to replace large `initialDelaySeconds` values.

---

**Q85. What is the difference between livenessProbe and readinessProbe failing?**

| | livenessProbe fails | readinessProbe fails |
|---|---|---|
| Effect | Container is **restarted** | Pod is **removed from Service endpoints** |
| App still running? | No (killed and restarted) | Yes (just not receiving traffic) |
| Use case | Detect deadlocks, crashes | Detect overload, not-yet-ready state |

---

**Q86. What is an init container?**

An init container runs **before** the main application container starts. It must complete successfully — if it fails, the Pod restarts. Use cases:
- Wait for a dependency (database, another service)
- Pre-populate data or config files
- Set file permissions
- Clone a git repository

```yaml
spec:
  initContainers:
  - name: wait-for-db
    image: busybox
    command:
    - sh
    - -c
    - "until nc -z postgres-service 5432; do echo waiting; sleep 2; done"
  - name: init-config
    image: alpine
    command: ["sh", "-c", "cp /mnt/config/app.conf /app/config/"]
    volumeMounts:
    - name: config
      mountPath: /mnt/config
    - name: app-config
      mountPath: /app/config
  containers:
  - name: app
    image: my-app:latest
```

---

**Q87. How are init containers different from regular containers?**

| Feature | Init Container | Regular Container |
|---|---|---|
| Run order | Sequential, before app | Parallel (start together) |
| Restart behavior | Restart Pod if fails | Based on restartPolicy |
| Resource limits | Separate from app | Counted separately |
| Access to volumes | Yes (shared with app) | Yes |
| Liveness/readiness probes | ❌ Not supported | ✅ Supported |

---

**Q88. What is the sidecar container pattern?**

A sidecar is a container in the same Pod that **augments or extends** the main application container without modifying it. Both run simultaneously.

Common sidecars:
- **Log shipper**: Fluentd/Filebeat tailing app logs → forwards to Elasticsearch
- **Proxy**: Envoy/Istio sidecar for mTLS and traffic management
- **Secrets injector**: Vault Agent syncing secrets to a shared volume
- **Metrics exporter**: Exposing app metrics in Prometheus format

```yaml
containers:
- name: app
  image: my-app:latest
  volumeMounts:
  - name: logs
    mountPath: /var/log/app
- name: log-shipper
  image: fluentd:latest
  volumeMounts:
  - name: logs
    mountPath: /var/log/app    # Reads the same log directory
volumes:
- name: logs
  emptyDir: {}
```

---

**Q89. What is the ambassador container pattern?**

An ambassador container acts as a **proxy between the app container and external services**. The app always connects to `localhost`, and the ambassador handles the complexity (connection pooling, routing, TLS).

Example: App connects to `localhost:5432` and the ambassador proxies to different database endpoints based on environment.

---

**Q90. What is the adapter container pattern?**

An adapter container **transforms the output** of the main container into a standardized format. Example: an app writes logs in a proprietary format, and the adapter container converts them to JSON before forwarding.

---

## 10. Intermediate Troubleshooting

---

**Q91. A Pod is stuck in `Pending`. How do you debug it?**

```bash
kubectl describe pod <pod-name>
# Check Events section at the bottom
```

Common causes and messages:

| Message | Cause | Fix |
|---|---|---|
| `Insufficient cpu/memory` | No node has enough resources | Scale cluster or reduce requests |
| `no nodes available to schedule pods` | All nodes cordoned or tainted | Check node status, taints |
| `didn't match Pod's node affinity/selector` | No matching node labels | Fix nodeSelector or label nodes |
| `pod has unbound immediate PersistentVolumeClaims` | PVC not bound | Check PVC status |

---

**Q92. A Pod is in `CrashLoopBackOff`. How do you debug?**

```bash
# Check recent logs
kubectl logs <pod-name>

# Check logs from previous (crashed) container
kubectl logs <pod-name> --previous

# Describe for exit code and events
kubectl describe pod <pod-name>
# Look for: "Exit Code", "OOMKilled", "Error"
```

Common causes:
- Application error (check logs)
- Wrong command/entrypoint in YAML
- Missing environment variable or config
- OOMKilled (increase memory limit)
- Missing dependency (init container might help)

---

**Q93. A Pod shows `ImagePullBackOff` or `ErrImagePull`. How do you fix it?**

```bash
kubectl describe pod <pod-name>
# Events: "Failed to pull image...", "unauthorized", "not found"
```

Common causes:

| Error | Fix |
|---|---|
| `not found` | Wrong image name or tag → correct image name |
| `unauthorized` | Private registry — add `imagePullSecret` |
| `network timeout` | DNS or network issue — check node connectivity |

```yaml
# Add imagePullSecret
spec:
  imagePullSecrets:
  - name: my-registry-secret
```

---

**Q94. A Service is not routing traffic. How do you debug?**

```bash
# 1. Check Service exists
kubectl get svc my-service

# 2. Check Endpoints — are any Pods registered?
kubectl get endpoints my-service
# If empty: selector mismatch or no ready Pods

# 3. Check Pod labels match Service selector
kubectl get pods --show-labels
kubectl describe svc my-service | grep Selector

# 4. Check readiness probe — are Pods ready?
kubectl get pods   # Ready column should show 1/1

# 5. Test from inside cluster
kubectl run test --image=busybox --rm -it --restart=Never -- wget -O- http://my-service
```

---

**Q95. How do you debug DNS resolution inside the cluster?**

```bash
# Run a debug Pod with DNS tools
kubectl run dns-test --image=busybox --rm -it --restart=Never -- /bin/sh

# Inside pod:
nslookup my-service
nslookup my-service.default.svc.cluster.local
nslookup kubernetes.default.svc.cluster.local  # Should always work

# Check CoreDNS
kubectl get pods -n kube-system | grep coredns
kubectl logs -n kube-system <coredns-pod>
```

---

**Q96. A Deployment rollout is stuck. How do you debug?**

```bash
kubectl rollout status deployment/my-deploy
# "Waiting for deployment rollout to finish: 1 out of 3 new replicas have been updated"

kubectl describe deployment my-deploy
kubectl get pods                          # Check new Pod status
kubectl logs <new-pod-name>              # Check new Pod logs

# If you need to abort, rollback
kubectl rollout undo deployment/my-deploy
```

---

**Q97. How do you debug a node in `NotReady` state?**

```bash
# Check node details
kubectl describe node <node-name>
# Look for: Conditions (MemoryPressure, DiskPressure, PIDPressure, Ready)

# SSH to node and check kubelet
ssh <node>
systemctl status kubelet
journalctl -u kubelet -n 100

# Check node resources
df -h        # Disk pressure?
free -m      # Memory pressure?
```

---

**Q98. How do you check resource usage across Pods?**

```bash
kubectl top pods                        # CPU/memory per Pod
kubectl top pods -n production
kubectl top pods --containers           # Per container breakdown
kubectl top nodes                       # Per node usage
```

---

**Q99. How do you force restart all Pods in a Deployment without changing anything?**

```bash
kubectl rollout restart deployment/my-deploy
# This performs a rolling restart — no downtime
```

---

**Q100. How do you quickly find which Pod is consuming the most memory?**

```bash
kubectl top pods --all-namespaces --sort-by=memory | head -10
kubectl top pods -n production --sort-by=cpu | head -5
```

---

## Bonus Intermediate Questions

---

**Q101. What is the difference between `kubectl apply` and `kubectl replace`?**

| `kubectl apply` | `kubectl replace` |
|---|---|
| Merges changes (3-way merge) | Full replacement of the resource |
| Works if resource doesn't exist (creates it) | Fails if resource doesn't exist |
| Preserves fields not in your YAML | Removes any fields not in your YAML |
| Best for GitOps | Use when you want exact replacement |

`kubectl replace --force` = delete + recreate (causes brief downtime).

---

**Q102. What is a Kubernetes operator?**

An operator is a **custom controller** that encodes operational knowledge about a specific application into Kubernetes. It uses:
- **CRDs** (Custom Resource Definitions) to define new resource types
- A **controller loop** to watch those resources and take action

Examples: Prometheus Operator, cert-manager, ArgoCD, PostgreSQL Operator.

---

**Q103. What is a Custom Resource Definition (CRD)?**

A CRD extends the Kubernetes API with new resource types. Once created, you can manage custom objects just like built-in resources:

```bash
kubectl get prometheusrules       # Custom resource
kubectl describe certificate my-cert   # cert-manager CRD
```

---

**Q104. What is a PodDisruptionBudget (PDB)?**

A PDB limits the number of Pods that can be **simultaneously unavailable** during voluntary disruptions (node drains, rolling updates):

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-pdb
spec:
  minAvailable: 2           # At least 2 Pods must always be available
  # OR
  # maxUnavailable: 1       # At most 1 Pod can be unavailable
  selector:
    matchLabels:
      app: web
```

---

**Q105. What is a Topology Spread Constraint?**

Controls how Pods are distributed across topology domains (nodes, zones) for better availability and utilization:

```yaml
spec:
  topologySpreadConstraints:
  - maxSkew: 1                          # Max difference in Pod count between domains
    topologyKey: topology.kubernetes.io/zone
    whenUnsatisfiable: DoNotSchedule    # Or ScheduleAnyway
    labelSelector:
      matchLabels:
        app: web
```

`maxSkew: 1` means no zone should have more than 1 extra Pod compared to the least-loaded zone.

---

**Q106. What is the difference between `kubectl logs` and checking application logs in a log aggregation system?**

| `kubectl logs` | Log Aggregation (EFK, Loki) |
|---|---|
| Shows current container logs | Stores historical logs (even after Pod deletion) |
| Limited to running/recently terminated Pods | Searchable across all Pods/namespaces |
| No persistence | Persisted storage |
| Good for quick debugging | Good for audit, analytics, alerting |
| Built-in | Requires separate setup (Fluentd, Promtail) |

---

**Q107. What is the purpose of `kubectl rollout pause` and `kubectl rollout resume`?**

```bash
# Pause a rollout (useful for canary-style manual testing)
kubectl rollout pause deployment/my-deploy

# Make changes (e.g., update image, env vars)
kubectl set image deployment/my-deploy app=my-app:v2
kubectl set env deployment/my-deploy LOG_LEVEL=debug

# Resume the rollout (applies all changes at once)
kubectl rollout resume deployment/my-deploy
```

---

**Q108. What are finalizers in Kubernetes?**

Finalizers are strings in `metadata.finalizers` that prevent object deletion until cleanup is done. Controllers remove the finalizer after completing cleanup, allowing deletion to proceed.

Common example: PVC protection finalizer prevents PVCs from being deleted while in use by a Pod:
```bash
kubectl describe pvc my-pvc | grep Finalizers
# Finalizers: kubernetes.io/pvc-protection
```

---

**Q109. How do you get events for a specific resource?**

```bash
kubectl describe pod my-pod    # Events at the bottom

# Or separately
kubectl get events --field-selector involvedObject.name=my-pod
kubectl get events -n dev --sort-by='.lastTimestamp'
```

---

**Q110. What is `imagePullPolicy` and what are the options?**

| Policy | Behavior |
|---|---|
| `Always` | Always pull from registry (even if cached) |
| `IfNotPresent` | Pull only if not already on the node |
| `Never` | Never pull; fail if not on node |

Default: `Always` if tag is `latest`, otherwise `IfNotPresent`.

```yaml
containers:
- name: app
  image: my-app:1.2.0
  imagePullPolicy: IfNotPresent
```

---

**Q111. What is the difference between `kubectl delete` and removing a resource from a GitOps repo?**

- `kubectl delete` imperatively removes the resource immediately
- Removing from a GitOps repo (ArgoCD, Flux) removes it on the next sync — depends on the sync policy and pruning settings
- In GitOps, `kubectl delete` is an anti-pattern — changes should go through Git

---

**Q112. What is `kubectl diff`?**

Shows the **difference between the current live state** and what would be applied from a file — like `git diff` for Kubernetes:

```bash
kubectl diff -f updated-deployment.yaml
# Shows: what will change if you apply this file
```

---

**Q113. How does a Pod access the Kubernetes API from inside the cluster?**

Using the **ServiceAccount token** and the internal API server address:

```bash
# Inside a Pod:
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
curl --cacert $CACERT \
     -H "Authorization: Bearer $TOKEN" \
     https://kubernetes.default.svc/api/v1/namespaces/default/pods
```

---

**Q114. What is `kubectl debug` and when is it useful?**

```bash
# Attach an ephemeral debug container to a running Pod
kubectl debug -it my-pod --image=busybox --target=app-container

# Create a copy of the Pod with a debug container
kubectl debug my-pod -it --image=ubuntu --copy-to=debug-pod

# Debug a node directly
kubectl debug node/node1 -it --image=ubuntu
```

Useful when the main container doesn't have shell tools (e.g., distroless images).

---

**Q115. What is `subPath` in a volume mount?**

`subPath` mounts a specific file or subdirectory from a volume instead of the entire volume:

```yaml
volumeMounts:
- name: config-vol
  mountPath: /etc/nginx/nginx.conf
  subPath: nginx.conf           # Mount only this file, not the whole volume
```

Useful when you want to inject a single ConfigMap key as a specific file without overwriting the whole directory.

---

**Q116. What is `hostNetwork` in a Pod spec?**

When `hostNetwork: true`, the Pod uses the node's network namespace directly (same IP as the node). Used for:
- Network monitoring tools
- High-performance networking

```yaml
spec:
  hostNetwork: true
```

> Security risk — avoid in general workloads.

---

**Q117. What is resource `fieldRef` and `resourceFieldRef`?**

Used to **expose Pod metadata as environment variables** (Downward API):

```yaml
env:
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name          # Pod name
- name: POD_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: NODE_NAME
  valueFrom:
    fieldRef:
      fieldPath: spec.nodeName
- name: CPU_LIMIT
  valueFrom:
    resourceFieldRef:
      containerName: app
      resource: limits.cpu
```

---

**Q118. What is `terminationGracePeriodSeconds`?**

When a Pod is deleted, Kubernetes sends `SIGTERM` to containers and waits `terminationGracePeriodSeconds` (default: 30) before sending `SIGKILL`. Set it higher for apps that need longer to finish in-flight requests:

```yaml
spec:
  terminationGracePeriodSeconds: 60
```

---

**Q119. What is a PreStop hook?**

A lifecycle hook that runs **just before the container receives SIGTERM**. Used to deregister from service discovery, flush buffers, or complete in-flight requests:

```yaml
lifecycle:
  preStop:
    exec:
      command: ["/bin/sh", "-c", "sleep 5"]   # Allow load balancer to deregister
  postStart:
    exec:
      command: ["/bin/sh", "-c", "echo started > /tmp/started"]
```

---

**Q120. How do you check what's using the most resources in a namespace?**

```bash
# Resource usage
kubectl top pods -n production --sort-by=memory

# Resource requests/limits defined
kubectl get pods -n production -o json | \
  jq '.items[] | {name: .metadata.name, cpu_req: .spec.containers[].resources.requests.cpu}'

# Check quota usage
kubectl describe resourcequota -n production
```

---

*End of Intermediate Level — 120 Questions*

---

## What's Next?

| Level | Topics Coming Up |
|---|---|
| 🟠 **Advanced** | etcd backup/restore, cluster upgrades, kubeadm, TLS certificates, Custom controllers, Operators, Service Mesh (Istio), Multi-cluster, Admission Webhooks, OPA/Gatekeeper |
| 🔴 **CKA/CKAD** | Exam-style hands-on scenarios, time-pressured imperative command drills, full mock questions |
