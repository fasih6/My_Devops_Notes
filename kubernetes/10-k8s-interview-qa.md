# 🎯 Kubernetes Interview Q&A

Real questions asked in DevOps and cloud engineering interviews — with complete answers.

---

## 📚 Table of Contents

- [🔥 Core Architecture](#-core-architecture)
- [🚀 Workloads](#-workloads)
- [🌐 Networking](#-networking)
- [💾 Storage](#-storage)
- [🔐 Security](#-security)
- [⛵ Helm](#-helm)
- [🔥 Scenario-Based Questions](#-scenario-based-questions)
- [🧠 Advanced Questions](#-advanced-questions)
- [💬 Questions to Ask the Interviewer](#-questions-to-ask-the-interviewer)

---

## 🔥 Core Architecture

---

**Q: What is Kubernetes and what problems does it solve?**

Kubernetes is a container orchestration platform. It solves the operational problems of running containerized applications at scale: where to run containers, how to keep them healthy, how to scale them up and down, how to roll out updates without downtime, and how to connect services together.

The key insight is the **desired state model** — you declare what you want ("3 replicas of my app running"), and Kubernetes continuously works to make reality match that declaration through its control loops.

---

**Q: Explain the Kubernetes architecture.**

A Kubernetes cluster has two parts:

The **control plane** is the brain. It contains the API server (the front door — all interactions go through it), etcd (the distributed key-value store that holds all cluster state), the scheduler (decides which node to run pods on), and the controller manager (runs controllers that watch state and reconcile differences).

The **data plane** is the worker nodes. Each node runs the kubelet (agent that ensures containers run as specified), kube-proxy (maintains network rules for Services), and a container runtime (containerd by default).

The key design principle: all components communicate through the API server, not directly with each other.

---

**Q: What is etcd and what happens if it goes down?**

etcd is a distributed key-value store that is the **single source of truth** for all Kubernetes cluster state — every object, every configuration, every status.

If etcd goes down, the control plane becomes read-only. Existing pods continue running — the kubelet keeps them alive. But no new changes can be made: you can't deploy, scale, or create services. The cluster "freezes" in its current state.

This is why etcd must be backed up regularly and run as a 3 or 5-node cluster in production (odd number for Raft consensus quorum).

---

**Q: What is the difference between a Pod, a Deployment, and a ReplicaSet?**

A **Pod** is the smallest deployable unit — one or more containers sharing a network namespace and storage. Pods are ephemeral; when they die, they're gone.

A **ReplicaSet** ensures a specified number of pod replicas are running. If a pod dies, it creates a new one. But it has no concept of rolling updates.

A **Deployment** manages ReplicaSets and adds rolling update and rollback capabilities. When you update a Deployment, it creates a new ReplicaSet and gradually shifts traffic to the new pods while keeping the old ReplicaSet around for rollback. You almost always use Deployments, not ReplicaSets directly.

---

**Q: What is the control loop (reconciliation loop)?**

The control loop is the fundamental operating pattern of Kubernetes: **observe, diff, act**.

A controller continuously observes the current state of the cluster, compares it to the desired state, and takes action to make them match. For example, the ReplicaSet controller: desired=3 replicas, current=2 running → creates 1 new pod.

This is what makes Kubernetes self-healing. When a pod dies, a node fails, or a config changes, the relevant controller detects the difference and corrects it — automatically, continuously.

---

**Q: What are taints and tolerations?**

Taints are applied to nodes to repel pods — "don't schedule regular pods here." Tolerations are applied to pods to allow them to be scheduled on tainted nodes — "I can tolerate this restriction."

Classic use case: you have GPU nodes. You taint them with `gpu=true:NoSchedule`. Only pods with a matching toleration (your ML workloads) get scheduled there. Everything else goes to regular nodes.

The `NoExecute` taint is stronger — it also evicts pods already running on the node if they don't have a toleration.

---

## 🚀 Workloads

---

**Q: When would you use a StatefulSet vs a Deployment?**

Use a **Deployment** for stateless applications — web servers, APIs, microservices — where all pods are identical and interchangeable. Any pod can handle any request.

Use a **StatefulSet** for stateful applications — databases, message queues, distributed systems — where each pod needs a stable identity, stable network hostname, and its own persistent storage.

Key differences: StatefulSet pods have predictable names (pod-0, pod-1), start in order, each gets its own PVC that persists even if the pod is deleted, and each has a stable DNS hostname via a headless Service.

---

**Q: What is the difference between liveness, readiness, and startup probes?**

All three are health checks, but they do different things:

**Liveness probe** — "Is the app alive?" If it fails, Kubernetes kills the container and restarts it. Use for detecting deadlocks or infinite loops where the app is running but stuck.

**Readiness probe** — "Is the app ready for traffic?" If it fails, Kubernetes removes the pod from Service endpoints. Traffic stops going to it but the container isn't restarted. Use for apps that need time to warm up or temporarily can't handle traffic.

**Startup probe** — "Is the app still starting?" Disables the liveness probe until this passes, preventing liveness from killing a slow-starting app. Use when your app takes longer than `initialDelaySeconds` to start.

---

**Q: What is the difference between Deployment's Recreate and RollingUpdate strategies?**

**RollingUpdate** (default) gradually replaces old pods with new ones. Controlled by `maxSurge` (how many extra pods can exist) and `maxUnavailable` (how many pods can be down). With `maxUnavailable: 0`, you get zero-downtime deployments.

**Recreate** kills all existing pods first, then creates new ones. This causes downtime between the kill and the creation. Use when old and new versions cannot run simultaneously — for example, when they use incompatible database schemas.

---

## 🌐 Networking

---

**Q: What are the different Service types and when do you use each?**

**ClusterIP** (default) — only accessible within the cluster. Use for internal service-to-service communication (backend talking to database).

**NodePort** — exposes the service on a static port on every node. Accessible from outside via `<node-ip>:<port>`. Use for development or on-prem without a load balancer.

**LoadBalancer** — creates a cloud load balancer (AWS ELB, GCP LB). Accessible from the internet. Use for production external-facing services.

**Headless** (clusterIP: None) — no load balancing, DNS returns individual pod IPs. Use with StatefulSets so each pod has a stable DNS name (postgres-0.postgres, postgres-1.postgres).

**ExternalName** — maps to an external DNS name. Use for accessing external services like RDS by a Kubernetes-native DNS name.

---

**Q: How does Service discovery work in Kubernetes?**

Kubernetes runs CoreDNS as the cluster DNS server. Every pod is configured to use it via `/etc/resolv.conf`.

When you create a Service named `my-app` in the `production` namespace, CoreDNS automatically creates a DNS record: `my-app.production.svc.cluster.local`. From within the same namespace, pods can reach it as just `my-app`. From other namespaces: `my-app.production`.

This means services find each other by name, not by IP — and the IP can change without breaking anything.

---

**Q: What is an Ingress and how does it differ from a LoadBalancer Service?**

A **LoadBalancer Service** provisions one cloud load balancer per service. For 10 services, you'd have 10 load balancers — expensive and hard to manage.

An **Ingress** is an L7 (HTTP/HTTPS) routing layer. One Ingress controller (and one load balancer) can route to many services based on hostname and path rules. `api.example.com → api-service`, `app.example.com/v1 → app-v1-service`. 

Ingress also handles TLS termination centrally, making certificate management easier (especially with cert-manager and Let's Encrypt).

---

**Q: What are Network Policies?**

By default, all pods can communicate with all other pods in a cluster. Network Policies restrict this using rules.

They work like firewall rules at the pod level: "allow traffic from pods with label `app=frontend` to pods with label `app=backend` on port 8080." Without an explicit allow rule, traffic is blocked.

Important: Network Policies only work if your CNI plugin supports them. Calico and Cilium do. Flannel doesn't.

A common production pattern: apply a default-deny policy to a namespace, then explicitly allow the communication you need.

---

## 💾 Storage

---

**Q: Explain the relationship between PV, PVC, and StorageClass.**

A **StorageClass** defines *how* to provision storage — which provisioner to use (EBS, NFS), what disk type, what reclaim policy.

A **PersistentVolume (PV)** is the actual storage resource — either manually provisioned by an admin or automatically created by a StorageClass when a PVC requests it.

A **PersistentVolumeClaim (PVC)** is a request for storage from a workload — "I need 20Gi of ReadWriteOnce storage." Kubernetes finds or creates a matching PV and binds them together.

The pod then mounts the PVC as a volume. The separation means developers don't need to know the underlying storage details.

---

**Q: What happens to a PVC when a pod is deleted? When a StatefulSet is scaled down?**

When a **pod** is deleted, the PVC is not deleted — it remains bound to the PV. The next pod that mounts the same PVC gets the same data. This is by design.

When a **StatefulSet** is scaled down, the pods are deleted but the PVCs created by `volumeClaimTemplates` are also retained — not deleted. When you scale back up, the new pods reattach to the same PVCs, preserving data. You must manually delete PVCs if you want to reclaim the storage.

---

## 🔐 Security

---

**Q: What is RBAC in Kubernetes?**

RBAC (Role-Based Access Control) controls who can do what on which resources. It has four objects:

- **Role** — defines a set of permissions within a namespace
- **ClusterRole** — same but cluster-wide
- **RoleBinding** — grants a Role to a subject (user, group, or ServiceAccount) in a namespace
- **ClusterRoleBinding** — grants a ClusterRole to a subject cluster-wide

The subject is who (a human user, a group, or a ServiceAccount for pods). The role defines what they can do. The binding connects them.

---

**Q: What is a ServiceAccount and why do pods have one?**

A ServiceAccount is the identity a pod uses to authenticate with the Kubernetes API. Every pod runs as a ServiceAccount (the `default` SA if none is specified).

The SA token is automatically mounted into the pod at `/var/run/secrets/kubernetes.io/serviceaccount/token`. Applications use this token to make authenticated API calls.

Best practices: create a dedicated ServiceAccount per application with minimal permissions (least privilege). Disable the auto-mounted token if your app doesn't need API access (`automountServiceAccountToken: false`).

---

**Q: What are Pod Security Standards?**

Pod Security Standards (PSS) are built-in security policies enforced via the Pod Security Admission (PSA) controller. There are three levels:

**Privileged** — no restrictions. For system components.
**Baseline** — prevents privilege escalation and privileged containers. For most workloads.
**Restricted** — requires running as non-root, dropping capabilities, read-only root filesystem. For high-security workloads.

You apply them as labels on namespaces. `pod-security.kubernetes.io/enforce: restricted` means Kubernetes rejects any pod that doesn't meet the restricted standard.

---

## ⛵ Helm

---

**Q: What is Helm and what problem does it solve?**

Helm is the package manager for Kubernetes. Applications often require many Kubernetes objects — Deployment, Service, Ingress, ConfigMap, HPA, ServiceAccount, RBAC rules. Managing all of these separately is complex and error-prone.

Helm packages them into a **chart** — a versioned, configurable bundle. You install a chart into a **release**. You can upgrade the release to a new version, roll it back, and track exactly what's deployed with what configuration.

---

**Q: What is the difference between `helm install` and `helm upgrade --install`?**

`helm install` fails if the release already exists. `helm upgrade --install` is idempotent — it installs if the release doesn't exist, upgrades if it does. In CI/CD pipelines, always use `helm upgrade --install` so the pipeline works for both first-time deploys and updates.

---

**Q: How do you manage environment-specific values in Helm?**

Use multiple values files. Have a base `values.yaml` with defaults and separate override files per environment: `values-staging.yaml`, `values-production.yaml`.

```bash
helm upgrade --install my-app ./my-chart \
  --values values.yaml \
  --values values-production.yaml
```

Later files override earlier ones. Only put what differs in the environment-specific file. This keeps diffs small and readable.

---

## 🔥 Scenario-Based Questions

---

**Scenario 1: A pod is in CrashLoopBackOff. Walk me through your investigation.**

```
1. kubectl get pods — confirm CrashLoopBackOff and check restart count

2. kubectl logs my-pod --previous
   Most important step — shows why the LAST crash happened

3. kubectl describe pod my-pod
   Check Events section for OOMKilled, probe failures, image errors

4. If OOMKilled → increase memory limit
   If app error → fix the application bug
   If probe timing → adjust initialDelaySeconds on livenessProbe
   If image issue → check image name, registry credentials

5. kubectl top pod my-pod (if running) — check live memory/CPU usage
```

---

**Scenario 2: A Deployment rollout is stuck. What do you do?**

```
1. kubectl rollout status deployment/my-app
   Confirms it's stuck

2. kubectl get pods -l app=my-app
   Are new pods failing? Old pods still running?

3. kubectl describe pod <new-pod>
   Check events — CrashLoopBackOff? ImagePullBackOff? Resource issue?

4. kubectl logs <new-pod> --previous
   Application error preventing startup?

5. If the new version is broken: kubectl rollout undo deployment/my-app
   This rolls back to the previous revision instantly

6. After rollback, fix the issue and redeploy
```

---

**Scenario 3: A Service has no endpoints. Why and how do you fix it?**

```
1. kubectl get endpoints my-service
   Confirms: ENDPOINTS = <none>

2. kubectl describe svc my-service
   Shows the selector: e.g., app=my-app

3. kubectl get pods --show-labels
   Do any pods have the label app=my-app?

4. If pods exist but selector doesn't match:
   - Fix the selector on the Service, OR
   - Fix the labels on the pods (via Deployment template)

5. If no pods exist:
   - Check if the Deployment exists and has running pods
   - Check if pods are in a different namespace

6. kubectl describe pod my-pod
   Is the pod Ready? (readinessProbe might be failing)
   A pod is only added to endpoints when it passes the readiness probe
```

---

**Scenario 4: A node is NotReady. What do you do?**

```
1. kubectl describe node worker-1
   Check Conditions section:
   - DiskPressure → disk full on node
   - MemoryPressure → low memory on node
   - Ready: False → kubelet not reporting

2. kubectl get events --field-selector involvedObject.name=worker-1

3. SSH to the node:
   systemctl status kubelet        # is kubelet running?
   journalctl -u kubelet -n 50    # kubelet error logs
   df -h                           # disk usage
   free -h                         # memory

4. If disk pressure: clean up images, logs, or add storage
   If kubelet crashed: systemctl restart kubelet
   If network issue: check cloud console for node state

5. kubectl cordon worker-1          # prevent new scheduling
   kubectl drain worker-1 --ignore-daemonsets  # move workloads off
   # Fix the issue, then:
   kubectl uncordon worker-1
```

---

**Scenario 5: How would you do a zero-downtime deployment?**

```
Configure the Deployment with:

spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1         # one extra pod at a time
      maxUnavailable: 0   # never reduce available pods
  minReadySeconds: 30     # wait 30s after pod ready before proceeding

Ensure:
1. readinessProbe is configured — pod only receives traffic when truly ready
2. Resources are set — scheduler can find space for the extra pod (maxSurge)
3. App handles SIGTERM — gracefully finishes in-flight requests
4. terminationGracePeriodSeconds is adequate (default 30s)

Process:
1. New pod starts, passes readiness probe
2. Old pod removed from Service endpoints
3. Old pod gets SIGTERM, finishes requests, exits
4. Repeat for each pod
```

---

## 🧠 Advanced Questions

---

**Q: How does the Kubernetes scheduler work?**

The scheduler watches for new pods with no assigned node. For each unscheduled pod, it runs two phases:

**Filtering** eliminates nodes that can't run the pod: insufficient CPU/memory (based on requests), nodeSelector doesn't match, taint not tolerated, affinity rules violated, port conflicts.

**Scoring** ranks remaining nodes: LeastAllocated (prefer nodes with most free resources), pod/node affinity preferences, spreading policies.

The pod is bound to the highest-scoring node. The scheduler doesn't actually start the pod — it just updates the pod's `spec.nodeName`, and the kubelet on that node picks it up.

---

**Q: What is the difference between HPA and VPA?**

**HPA** (Horizontal Pod Autoscaler) scales the **number of replicas** — adds or removes pods. Good for stateless apps that can scale horizontally. Requires CPU/memory requests to be set.

**VPA** (Vertical Pod Autoscaler) scales **resource requests/limits** — makes each pod bigger or smaller. Good for apps that can't scale horizontally (databases, legacy apps). Requires pod restart to apply new requests.

Don't use HPA and VPA on the same resource (e.g., both on CPU) — they conflict. Common pattern: VPA for memory, HPA for CPU, or use KEDA for event-driven scaling.

---

**Q: What is KEDA and when would you use it?**

KEDA (Kubernetes Event-Driven Autoscaling) extends HPA to scale based on external event sources — SQS queue depth, Kafka topic lag, Prometheus metrics, database record counts, and 50+ other sources.

Use it when: you want to scale to zero (HPA minimum is 1), when scaling based on business metrics (not just CPU), or when scaling based on external queues.

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
spec:
  scaleTargetRef:
    name: my-worker
  minReplicaCount: 0      # scale to zero when queue is empty
  maxReplicaCount: 50
  triggers:
    - type: aws-sqs-queue
      metadata:
        queueURL: https://sqs.eu-central-1.amazonaws.com/123/my-queue
        targetQueueLength: "10"  # 1 pod per 10 messages
```

---

**Q: What is a PodDisruptionBudget (PDB) and why is it important?**

A PDB limits how many pods of an application can be unavailable at the same time during voluntary disruptions — node drains, cluster upgrades, Cluster Autoscaler scale-down.

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: my-app-pdb
spec:
  minAvailable: 2        # always keep at least 2 pods running
  # OR
  maxUnavailable: 1      # never take down more than 1 pod at a time
  selector:
    matchLabels:
      app: my-app
```

Without a PDB, a node drain could take down all replicas at once if they happen to be on the same node. PDBs prevent this — the drain operation respects the budget and only evicts pods when it wouldn't violate it.

---

## 💬 Questions to Ask the Interviewer

**On their Kubernetes setup:**
- "What Kubernetes distribution do you use — EKS, GKE, AKS, or self-managed?"
- "How many clusters do you operate and how do you manage multi-cluster deployments?"
- "What's your CNI plugin — Calico, Cilium, or something else?"

**On their practices:**
- "How do you handle cluster upgrades — do you do in-place or blue/green cluster upgrades?"
- "Do you use GitOps? Are you on ArgoCD or Flux?"
- "How do you manage secrets — External Secrets Operator, Vault, or native K8s Secrets?"

**On their challenges:**
- "What's been your biggest Kubernetes incident and how did you handle it?"
- "How do you handle multi-tenancy — separate clusters or namespaces with RBAC?"

**On the role:**
- "Would I be working on the platform team building K8s tooling, or embedding with product teams?"
- "What does your on-call rotation look like for cluster-level issues?"

---

*Good luck — you've built a comprehensive Kubernetes knowledge base. The notes are yours. 🚀*
