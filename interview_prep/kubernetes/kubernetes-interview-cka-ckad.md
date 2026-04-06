# Kubernetes Interview Q&A — CKA / CKAD Level

> **Level**: CKA / CKAD Exam-Style  
> **Format**: Hands-on scenarios, imperative command drills, mock exam tasks, and explanations  
> **Prerequisite**: Beginner + Intermediate + Advanced levels completed  
> **Total**: 120+ questions covering all CKA/CKAD exam domains

---

## Table of Contents

1. [CKA Exam Overview & Strategy](#1-cka-exam-overview--strategy)
2. [Core kubectl Speed Drills](#2-core-kubectl-speed-drills)
3. [Workloads Domain — CKA/CKAD Tasks](#3-workloads-domain--ckaickad-tasks)
4. [Scheduling Domain — CKA Tasks](#4-scheduling-domain--cka-tasks)
5. [Services & Networking Domain](#5-services--networking-domain)
6. [Storage Domain — CKA Tasks](#6-storage-domain--cka-tasks)
7. [Cluster Maintenance Domain — CKA Tasks](#7-cluster-maintenance-domain--cka-tasks)
8. [Security Domain — CKA/CKAD Tasks](#8-security-domain--ckaickad-tasks)
9. [Observability & Troubleshooting Domain](#9-observability--troubleshooting-domain)
10. [Full Mock Exam Scenarios](#10-full-mock-exam-scenarios)

---

## 1. CKA Exam Overview & Strategy

---

**Q1. What is the CKA exam format?**

| Attribute | Detail |
|---|---|
| Duration | 2 hours |
| Questions | 15–20 performance-based tasks |
| Format | 100% hands-on (browser-based terminal) |
| Passing score | 66% |
| Environment | Multiple pre-configured clusters |
| Open book | Yes — kubernetes.io/docs allowed |
| Proctored | Yes — webcam + screen share |

---

**Q2. What are the CKA exam domains and weights (2024)?**

| Domain | Weight |
|---|---|
| Storage | 10% |
| Troubleshooting | 30% |
| Workloads & Scheduling | 15% |
| Cluster Architecture, Installation & Configuration | 25% |
| Services & Networking | 20% |

> **Troubleshooting (30%) is the heaviest domain — prioritize it.**

---

**Q3. What is the CKAD exam format?**

| Attribute | Detail |
|---|---|
| Duration | 2 hours |
| Questions | 15–20 performance-based tasks |
| Passing score | 66% |
| Focus | Application design, build, deploy, observe |

**CKAD domains:**

| Domain | Weight |
|---|---|
| Application Design and Build | 20% |
| Application Deployment | 20% |
| Application Observability and Maintenance | 15% |
| Application Environment, Configuration and Security | 25% |
| Services and Networking | 20% |

---

**Q4. What are the top exam strategy tips?**

- **Always set the namespace** — most tasks specify a namespace; wrong namespace = 0 marks
- **Always switch context first** — the exam provides the context switch command at the top of each question
- **Use `--dry-run=client -o yaml`** — generate manifests quickly, then edit
- **Use `kubectl explain`** — faster than remembering field names
- **Use `kubectl create/run` imperatively** — much faster than writing YAML from scratch
- **Bookmark docs** — kubernetes.io/docs, especially Tasks section
- **Don't get stuck** — skip, mark, come back later
- **Verify your work** — always run `kubectl get` after applying changes

---

**Q5. What context-switching command is given at the start of each exam question?**

```bash
# Shown at the top of every question — always run it first
kubectl config use-context <cluster-name>

# Example:
kubectl config use-context k8s-cluster-prod
```

Forgetting to switch context is one of the most common costly mistakes in the exam.

---

**Q6. What are the most useful keyboard shortcuts and aliases to set up at the start of the exam?**

```bash
# Must-do aliases
alias k=kubectl
alias kn='kubectl config set-context --current --namespace'

# Enable autocomplete
source <(kubectl completion bash)
complete -F __start_kubectl k

# Short dry-run flag
export do='--dry-run=client -o yaml'
export now='--grace-period=0 --force'

# Usage examples:
k run nginx --image=nginx $do > pod.yaml
k delete pod nginx $now
kn dev   # switch to dev namespace
```

---

**Q7. What are the most-used kubectl documentation pages to bookmark?**

- `https://kubernetes.io/docs/reference/kubectl/cheatsheet/`
- `https://kubernetes.io/docs/tasks/` (all task pages)
- `https://kubernetes.io/docs/concepts/`
- `https://kubernetes.io/docs/reference/generated/kubectl/kubectl-commands`

---

## 2. Core kubectl Speed Drills

---

**Q8. Create a Pod named `web` with image `nginx:alpine` in namespace `frontend`.**

```bash
kubectl run web --image=nginx:alpine -n frontend
```

---

**Q9. Create a Deployment named `api` with image `python:3.9` and 3 replicas.**

```bash
kubectl create deployment api --image=python:3.9 --replicas=3
```

---

**Q10. Generate a Pod YAML without creating it, save to `pod.yaml`.**

```bash
kubectl run nginx --image=nginx --dry-run=client -o yaml > pod.yaml
```

---

**Q11. Generate a Deployment YAML for `myapp` with image `myapp:v1` and 2 replicas.**

```bash
kubectl create deployment myapp --image=myapp:v1 --replicas=2 \
  --dry-run=client -o yaml > deploy.yaml
```

---

**Q12. Expose a Deployment `web` on port 80 as a ClusterIP Service.**

```bash
kubectl expose deployment web --port=80 --target-port=80 --type=ClusterIP
```

---

**Q13. Expose a Deployment `web` on port 80 as a NodePort Service.**

```bash
kubectl expose deployment web --port=80 --type=NodePort
```

---

**Q14. Scale deployment `web` to 5 replicas.**

```bash
kubectl scale deployment web --replicas=5
```

---

**Q15. Update deployment `web` image to `nginx:1.26`.**

```bash
kubectl set image deployment/web nginx=nginx:1.26
```

---

**Q16. Rollback deployment `web` to previous version.**

```bash
kubectl rollout undo deployment/web
```

---

**Q17. Check rollout history of `web` and rollback to revision 2.**

```bash
kubectl rollout history deployment/web
kubectl rollout undo deployment/web --to-revision=2
```

---

**Q18. Create a ConfigMap `app-config` with key `ENV=prod` and `LOG=debug`.**

```bash
kubectl create configmap app-config \
  --from-literal=ENV=prod \
  --from-literal=LOG=debug
```

---

**Q19. Create a Secret `db-secret` with username=admin and password=pass123.**

```bash
kubectl create secret generic db-secret \
  --from-literal=username=admin \
  --from-literal=password=pass123
```

---

**Q20. Create a ServiceAccount named `app-sa` in namespace `dev`.**

```bash
kubectl create serviceaccount app-sa -n dev
```

---

**Q21. Create a Role `pod-reader` in namespace `dev` that allows get, list, watch on pods.**

```bash
kubectl create role pod-reader \
  --verb=get,list,watch \
  --resource=pods \
  -n dev
```

---

**Q22. Bind role `pod-reader` to user `alice` in namespace `dev`.**

```bash
kubectl create rolebinding pod-reader-binding \
  --role=pod-reader \
  --user=alice \
  -n dev
```

---

**Q23. Bind ClusterRole `view` to ServiceAccount `app-sa` in namespace `dev`.**

```bash
kubectl create rolebinding view-binding \
  --clusterrole=view \
  --serviceaccount=dev:app-sa \
  -n dev
```

---

**Q24. Check if user `alice` can create pods in namespace `dev`.**

```bash
kubectl auth can-i create pods --as=alice -n dev
```

---

**Q25. Create a Job named `batch` using image `busybox` that runs `echo hello`.**

```bash
kubectl create job batch --image=busybox -- echo hello
```

---

**Q26. Create a CronJob `cleanup` with image `busybox` that runs `rm -rf /tmp/*` every day at midnight.**

```bash
kubectl create cronjob cleanup \
  --image=busybox \
  --schedule="0 0 * * *" \
  -- rm -rf /tmp/*
```

---

**Q27. Get all Pods sorted by creation time.**

```bash
kubectl get pods --sort-by=.metadata.creationTimestamp
```

---

**Q28. Get Pods with a specific label and show their node.**

```bash
kubectl get pods -l app=nginx -o wide
```

---

**Q29. Delete a Pod immediately without waiting for graceful shutdown.**

```bash
kubectl delete pod nginx --grace-period=0 --force
```

---

**Q30. Run a temporary debug Pod and delete it after exit.**

```bash
kubectl run debug --image=busybox --rm -it --restart=Never -- /bin/sh
```

---

**Q31. Get the IP address of a Pod using jsonpath.**

```bash
kubectl get pod nginx -o jsonpath='{.status.podIP}'
```

---

**Q32. Get all Pods in all namespaces with their node name.**

```bash
kubectl get pods --all-namespaces -o wide
```

---

**Q33. Forward local port 8080 to Pod port 80.**

```bash
kubectl port-forward pod/nginx 8080:80
```

---

**Q34. Copy file from Pod to local machine.**

```bash
kubectl cp nginx:/etc/nginx/nginx.conf ./nginx.conf
```

---

**Q35. Label node `node1` with `disk=ssd`.**

```bash
kubectl label node node1 disk=ssd
```

---

## 3. Workloads Domain — CKA/CKAD Tasks

---

**Q36. TASK: Create a Pod with two containers — `main` (nginx) and `sidecar` (busybox that runs `sleep 3600`). Both share a volume at `/shared`.**

```yaml
# Save as multi-container-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  name: multi-pod
spec:
  containers:
  - name: main
    image: nginx
    volumeMounts:
    - name: shared-vol
      mountPath: /shared
  - name: sidecar
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: shared-vol
      mountPath: /shared
  volumes:
  - name: shared-vol
    emptyDir: {}
```

```bash
kubectl apply -f multi-container-pod.yaml
kubectl get pod multi-pod
```

---

**Q37. TASK: Create a Pod with an init container that writes `hello` to `/work/msg` and a main container (busybox, sleep 3600) that reads from `/work`.**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: init-pod
spec:
  initContainers:
  - name: init-writer
    image: busybox
    command: ["sh", "-c", "echo hello > /work/msg"]
    volumeMounts:
    - name: work-vol
      mountPath: /work
  containers:
  - name: app
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: work-vol
      mountPath: /work
  volumes:
  - name: work-vol
    emptyDir: {}
```

```bash
kubectl apply -f init-pod.yaml
kubectl exec init-pod -- cat /work/msg   # Should print: hello
```

---

**Q38. TASK: Create a Deployment `webapp` with image `nginx:1.25`, 3 replicas, and resource requests cpu=100m, memory=128Mi and limits cpu=200m, memory=256Mi.**

```bash
kubectl create deployment webapp --image=nginx:1.25 --replicas=3 \
  --dry-run=client -o yaml > webapp.yaml
```

Edit `webapp.yaml` to add resources:
```yaml
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "200m"
            memory: "256Mi"
```

```bash
kubectl apply -f webapp.yaml
```

---

**Q39. TASK: Configure the `webapp` Deployment to use a ConfigMap `webapp-config` (key: `APP_ENV=production`) as an environment variable.**

```bash
# Create ConfigMap
kubectl create configmap webapp-config --from-literal=APP_ENV=production

# Patch deployment
kubectl set env deployment/webapp --from=configmap/webapp-config
```

Or edit the deployment YAML and add:
```yaml
        envFrom:
        - configMapRef:
            name: webapp-config
```

---

**Q40. TASK: Create a Deployment with a liveness probe (HTTP GET /health on port 8080) and readiness probe (HTTP GET /ready on port 8080).**

```bash
kubectl create deployment myapp --image=myapp:latest --dry-run=client -o yaml > myapp.yaml
```

Add probes to the container spec:
```yaml
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /ready
            port: 8080
          initialDelaySeconds: 5
          periodSeconds: 5
```

```bash
kubectl apply -f myapp.yaml
```

---

**Q41. TASK: Create a StatefulSet `mysql` with 1 replica, image `mysql:8.0`, env `MYSQL_ROOT_PASSWORD=secret` and a PVC of 1Gi per Pod.**

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: mysql
spec:
  serviceName: mysql
  replicas: 1
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
          value: "secret"
        volumeMounts:
        - name: data
          mountPath: /var/lib/mysql
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
---
apiVersion: v1
kind: Service
metadata:
  name: mysql
spec:
  clusterIP: None
  selector:
    app: mysql
  ports:
  - port: 3306
```

---

**Q42. TASK: Create a CronJob that prints the current date every 5 minutes.**

```bash
kubectl create cronjob print-date \
  --image=busybox \
  --schedule="*/5 * * * *" \
  -- date
```

---

**Q43. TASK: Create a Job with `backoffLimit=2` and `completions=3` using image `busybox` that runs `echo done`.**

```bash
kubectl create job batch-job --image=busybox \
  --dry-run=client -o yaml -- echo done > job.yaml
```

Edit `job.yaml`:
```yaml
spec:
  completions: 3
  backoffLimit: 2
  template:
    ...
```

```bash
kubectl apply -f job.yaml
```

---

**Q44. TASK: Update Deployment `webapp` to use a rolling update strategy with maxSurge=1 and maxUnavailable=0.**

```bash
kubectl patch deployment webapp -p '{
  "spec": {
    "strategy": {
      "type": "RollingUpdate",
      "rollingUpdate": {
        "maxSurge": 1,
        "maxUnavailable": 0
      }
    }
  }
}'
```

---

**Q45. TASK: Annotate a Deployment `webapp` with `kubernetes.io/change-cause="Updated to nginx 1.26"`.**

```bash
kubectl annotate deployment webapp \
  kubernetes.io/change-cause="Updated to nginx 1.26"
```

---

## 4. Scheduling Domain — CKA Tasks

---

**Q46. TASK: Create a Pod that runs ONLY on nodes with label `disk=ssd`.**

```bash
kubectl run ssd-pod --image=nginx --dry-run=client -o yaml > ssd-pod.yaml
```

Add to spec:
```yaml
  nodeSelector:
    disk: ssd
```

```bash
kubectl label node node1 disk=ssd    # Make sure at least one node has the label
kubectl apply -f ssd-pod.yaml
```

---

**Q47. TASK: Create a Pod with a toleration for taint `dedicated=gpu:NoSchedule`.**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: gpu-pod
spec:
  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "gpu"
    effect: "NoSchedule"
  containers:
  - name: gpu-app
    image: nvidia/cuda:11.0-base
```

---

**Q48. TASK: Taint node `node2` so that no new Pods are scheduled on it unless they tolerate `env=test:NoSchedule`.**

```bash
kubectl taint nodes node2 env=test:NoSchedule

# Verify
kubectl describe node node2 | grep Taint
```

---

**Q49. TASK: Create a Pod with node affinity — it must run on a node with label `zone=us-east-1a`, but prefers nodes with label `ssd=true`.**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: affinity-pod
spec:
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: zone
            operator: In
            values:
            - us-east-1a
      preferredDuringSchedulingIgnoredDuringExecution:
      - weight: 1
        preference:
          matchExpressions:
          - key: ssd
            operator: In
            values:
            - "true"
  containers:
  - name: app
    image: nginx
```

---

**Q50. TASK: Create a Deployment with pod anti-affinity so that no two replicas run on the same node.**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: spread-deploy
spec:
  replicas: 3
  selector:
    matchLabels:
      app: spread
  template:
    metadata:
      labels:
        app: spread
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: spread
            topologyKey: kubernetes.io/hostname
      containers:
      - name: app
        image: nginx
```

---

**Q51. TASK: Create a PodDisruptionBudget for Deployment `webapp` allowing at most 1 unavailable Pod.**

```bash
kubectl create poddisruptionbudget webapp-pdb \
  --selector=app=webapp \
  --max-unavailable=1
```

---

**Q52. TASK: Manually assign a Pod to `node1` using `nodeName`.**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: manual-pod
spec:
  nodeName: node1
  containers:
  - name: nginx
    image: nginx
```

---

**Q53. TASK: Create a ResourceQuota in namespace `dev` limiting to 10 Pods and 4 CPU cores.**

```bash
kubectl create resourcequota dev-quota \
  --hard=pods=10,requests.cpu=4 \
  -n dev
```

---

**Q54. TASK: Create a LimitRange in namespace `dev` with default CPU request=100m and limit=500m.**

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: cpu-limits
  namespace: dev
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: "100m"
    default:
      cpu: "500m"
```

---

**Q55. TASK: Set up HPA for Deployment `webapp` — min 2, max 8 replicas, target CPU 70%.**

```bash
kubectl autoscale deployment webapp \
  --min=2 --max=8 --cpu-percent=70
```

---

## 5. Services & Networking Domain

---

**Q56. TASK: Create a Service that exposes Deployment `backend` on port 8080, mapping to container port 3000.**

```bash
kubectl expose deployment backend --port=8080 --target-port=3000
```

---

**Q57. TASK: Create a NodePort Service for `frontend` Deployment on port 80, exposed on nodePort 30080.**

```bash
kubectl expose deployment frontend --port=80 --type=NodePort \
  --dry-run=client -o yaml > svc.yaml
```

Edit `svc.yaml` to add `nodePort: 30080` under ports, then:
```bash
kubectl apply -f svc.yaml
```

---

**Q58. TASK: Create an Ingress that routes `app.example.com/api` to service `api-svc:8080` and `app.example.com/` to service `web-svc:80`.**

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: app-ingress
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
            name: api-svc
            port:
              number: 8080
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-svc
            port:
              number: 80
```

---

**Q59. TASK: Create a NetworkPolicy in namespace `prod` that denies all ingress traffic to all Pods.**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all-ingress
  namespace: prod
spec:
  podSelector: {}
  policyTypes:
  - Ingress
```

---

**Q60. TASK: Create a NetworkPolicy that allows Pods with label `role=frontend` to reach Pods with label `role=backend` on port 3000. Deny everything else.**

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-backend
  namespace: default
spec:
  podSelector:
    matchLabels:
      role: backend
  policyTypes:
  - Ingress
  ingress:
  - from:
    - podSelector:
        matchLabels:
          role: frontend
    ports:
    - protocol: TCP
      port: 3000
```

---

**Q61. TASK: Verify DNS resolution from inside a Pod.**

```bash
kubectl run dns-test --image=busybox --rm -it --restart=Never \
  -- nslookup kubernetes.default.svc.cluster.local
```

---

**Q62. TASK: Create a headless Service for StatefulSet `mysql`.**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: mysql-headless
spec:
  clusterIP: None
  selector:
    app: mysql
  ports:
  - port: 3306
```

---

**Q63. TASK: Find which Service is using selector `app=nginx` and its ClusterIP.**

```bash
kubectl get svc -o wide | grep nginx
kubectl get svc -o jsonpath='{range .items[?(@.spec.selector.app=="nginx")]}{.metadata.name}{"\t"}{.spec.clusterIP}{"\n"}'
```

---

**Q64. TASK: Verify traffic reaches a Service by testing from a debug Pod.**

```bash
kubectl run curl-test --image=curlimages/curl --rm -it --restart=Never \
  -- curl http://my-service.default.svc.cluster.local:80
```

---

**Q65. TASK: Get the endpoint IPs for a Service named `api-svc`.**

```bash
kubectl get endpoints api-svc
kubectl describe endpoints api-svc
```

---

## 6. Storage Domain — CKA Tasks

---

**Q66. TASK: Create a PersistentVolume of 1Gi using hostPath `/data/pv1` with ReadWriteOnce access mode and Retain policy.**

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-hostpath
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /data/pv1
```

---

**Q67. TASK: Create a PersistentVolumeClaim for 500Mi with ReadWriteOnce access mode.**

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
      storage: 500Mi
```

---

**Q68. TASK: Create a Pod that mounts PVC `my-pvc` at `/data`.**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: pvc-pod
spec:
  containers:
  - name: app
    image: nginx
    volumeMounts:
    - name: storage
      mountPath: /data
  volumes:
  - name: storage
    persistentVolumeClaim:
      claimName: my-pvc
```

---

**Q69. TASK: Check why a PVC is in `Pending` state.**

```bash
kubectl describe pvc my-pvc
# Look at Events:
# - "no persistent volumes available for this claim and no storage class is set"
# - "volume node affinity conflict"

kubectl get pv    # Check if matching PV exists
kubectl get storageclass  # Check available StorageClasses
```

---

**Q70. TASK: Create a StorageClass named `fast` using the `kubernetes.io/no-provisioner` provisioner with WaitForFirstConsumer binding.**

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast
provisioner: kubernetes.io/no-provisioner
volumeBindingMode: WaitForFirstConsumer
```

---

**Q71. TASK: Expand an existing PVC `my-pvc` from 1Gi to 2Gi.**

```bash
kubectl patch pvc my-pvc -p '{"spec":{"resources":{"requests":{"storage":"2Gi"}}}}'

# Verify
kubectl get pvc my-pvc
# STATUS shows: Bound, CAPACITY shows: 2Gi (after StorageClass allows resize)
```

> The StorageClass must have `allowVolumeExpansion: true`.

---

**Q72. TASK: Create a Pod that uses a ConfigMap as a mounted volume file at `/etc/config/app.conf`.**

```bash
kubectl create configmap app-conf --from-literal=app.conf="key=value"
```

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: config-pod
spec:
  containers:
  - name: app
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: config-vol
      mountPath: /etc/config
  volumes:
  - name: config-vol
    configMap:
      name: app-conf
```

---

**Q73. TASK: Mount only the `username` key from Secret `db-secret` as a file at `/secrets/user`.**

```yaml
volumes:
- name: secret-vol
  secret:
    secretName: db-secret
    items:
    - key: username
      path: user
containers:
- volumeMounts:
  - name: secret-vol
    mountPath: /secrets
    readOnly: true
```

---

## 7. Cluster Maintenance Domain — CKA Tasks

---

**Q74. TASK: Safely drain `node2` for maintenance.**

```bash
# Cordon first
kubectl cordon node2

# Drain (evict all pods)
kubectl drain node2 \
  --ignore-daemonsets \
  --delete-emptydir-data

# Verify
kubectl get nodes    # node2 should show: Ready,SchedulingDisabled

# After maintenance, restore
kubectl uncordon node2
```

---

**Q75. TASK: Backup etcd to `/backup/etcd.db`.**

```bash
ETCDCTL_API=3 etcdctl snapshot save /backup/etcd.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

# Verify
ETCDCTL_API=3 etcdctl snapshot status /backup/etcd.db --write-out=table
```

---

**Q76. TASK: Restore etcd from snapshot `/backup/etcd.db` to data directory `/var/lib/etcd-new`.**

```bash
ETCDCTL_API=3 etcdctl snapshot restore /backup/etcd.db \
  --data-dir=/var/lib/etcd-new

# Update etcd manifest to use new data dir
vi /etc/kubernetes/manifests/etcd.yaml
# Change: --data-dir=/var/lib/etcd  →  --data-dir=/var/lib/etcd-new
# Change: hostPath path for data volume accordingly

# Wait for etcd to restart
watch kubectl get nodes
```

---

**Q77. TASK: Upgrade the control plane from 1.27 to 1.28 using kubeadm.**

```bash
# 1. Upgrade kubeadm
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.28.0-00
apt-mark hold kubeadm

# 2. Check plan
kubeadm upgrade plan

# 3. Apply upgrade
kubeadm upgrade apply v1.28.0

# 4. Drain control plane
kubectl drain controlplane --ignore-daemonsets

# 5. Upgrade kubelet + kubectl
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.28.0-00 kubectl=1.28.0-00
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet

# 6. Uncordon
kubectl uncordon controlplane
kubectl get nodes    # Verify VERSION shows v1.28.0
```

---

**Q78. TASK: Upgrade worker node `node1` to 1.28.**

```bash
# === On Control Plane ===
kubectl drain node1 --ignore-daemonsets --delete-emptydir-data

# === SSH into node1 ===
apt-mark unhold kubeadm
apt-get install -y kubeadm=1.28.0-00
apt-mark hold kubeadm

kubeadm upgrade node

apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.28.0-00 kubectl=1.28.0-00
apt-mark hold kubelet kubectl
systemctl daemon-reload
systemctl restart kubelet

# === On Control Plane ===
kubectl uncordon node1
kubectl get nodes
```

---

**Q79. TASK: Check certificate expiration dates on the control plane.**

```bash
kubeadm certs check-expiration

# Manual check
openssl x509 -in /etc/kubernetes/pki/apiserver.crt -noout -dates
```

---

**Q80. TASK: Renew all Kubernetes certificates.**

```bash
kubeadm certs renew all

# Restart control plane components
# Static Pods restart automatically when their manifests are touched
# Or manually:
crictl rm $(crictl ps --name kube-apiserver -q)
crictl rm $(crictl ps --name kube-controller-manager -q)
crictl rm $(crictl ps --name kube-scheduler -q)
```

---

## 8. Security Domain — CKA/CKAD Tasks

---

**Q81. TASK: Create a ClusterRole `node-reader` that allows listing Nodes, then bind it to user `bob`.**

```bash
kubectl create clusterrole node-reader \
  --verb=get,list,watch \
  --resource=nodes

kubectl create clusterrolebinding node-reader-bob \
  --clusterrole=node-reader \
  --user=bob
```

---

**Q82. TASK: Create a ServiceAccount `deploy-sa`, bind ClusterRole `edit` to it in namespace `staging`.**

```bash
kubectl create serviceaccount deploy-sa -n staging

kubectl create rolebinding deploy-sa-edit \
  --clusterrole=edit \
  --serviceaccount=staging:deploy-sa \
  -n staging
```

---

**Q83. TASK: Create a Pod that runs as non-root user (uid 1000) with a read-only filesystem.**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: secure-pod
spec:
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  containers:
  - name: app
    image: nginx
    securityContext:
      readOnlyRootFilesystem: true
      allowPrivilegeEscalation: false
      capabilities:
        drop: ["ALL"]
```

---

**Q84. TASK: Create a Pod that uses ServiceAccount `app-sa`.**

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: sa-pod
spec:
  serviceAccountName: app-sa
  containers:
  - name: app
    image: nginx
```

---

**Q85. TASK: Get a token for ServiceAccount `app-sa` valid for 1 hour.**

```bash
kubectl create token app-sa --duration=1h
```

---

**Q86. TASK: Create a Secret `tls-secret` from TLS certificate files `tls.crt` and `tls.key`.**

```bash
kubectl create secret tls tls-secret \
  --cert=tls.crt \
  --key=tls.key
```

---

**Q87. TASK: Create a docker registry secret for pulling images from a private registry.**

```bash
kubectl create secret docker-registry registry-creds \
  --docker-server=registry.example.com \
  --docker-username=myuser \
  --docker-password=mypass \
  --docker-email=myuser@example.com
```

---

**Q88. TASK: Use `kubectl auth can-i` to verify that ServiceAccount `app-sa` in namespace `dev` can list Pods.**

```bash
kubectl auth can-i list pods \
  --as=system:serviceaccount:dev:app-sa \
  -n dev
```

---

**Q89. TASK: Apply a Pod Security Standard `baseline` enforcement to namespace `production`.**

```bash
kubectl label namespace production \
  pod-security.kubernetes.io/enforce=baseline \
  pod-security.kubernetes.io/enforce-version=latest
```

---

**Q90. TASK: Decode the value of key `password` in Secret `db-secret`.**

```bash
kubectl get secret db-secret \
  -o jsonpath='{.data.password}' | base64 --decode
```

---

## 9. Observability & Troubleshooting Domain

---

**Q91. TASK: Find all Pods that are NOT in `Running` state across all namespaces.**

```bash
kubectl get pods --all-namespaces --field-selector=status.phase!=Running
```

---

**Q92. TASK: A Pod `webapp` is crashing. Retrieve its logs from before the last crash.**

```bash
kubectl logs webapp --previous
kubectl logs webapp --previous --tail=50
```

---

**Q93. TASK: Find which node a Pod `api-pod` is running on.**

```bash
kubectl get pod api-pod -o wide
kubectl get pod api-pod -o jsonpath='{.spec.nodeName}'
```

---

**Q94. TASK: A Deployment `frontend` has 0 ready Pods. Debug it step by step.**

```bash
# Step 1: Check Deployment status
kubectl get deployment frontend
kubectl describe deployment frontend

# Step 2: Check ReplicaSet
kubectl get rs -l app=frontend

# Step 3: Check Pods
kubectl get pods -l app=frontend
kubectl describe pod <pod-name>   # Check Events

# Step 4: Check logs
kubectl logs <pod-name>
kubectl logs <pod-name> --previous  # If crashing

# Step 5: Check Service endpoints
kubectl get endpoints frontend-svc
```

---

**Q95. TASK: A node `node2` is NotReady. Investigate and fix it.**

```bash
# On control plane
kubectl describe node node2        # Check Conditions and Events
kubectl get pods -o wide | grep node2   # Which pods were on node2

# SSH to node2
ssh node2
systemctl status kubelet           # Is kubelet running?
journalctl -u kubelet -n 50       # Check kubelet logs

# Common fixes
systemctl restart kubelet          # Restart kubelet if stopped
df -h                             # Check disk (DiskPressure)
free -m                           # Check memory (MemoryPressure)
```

---

**Q96. TASK: Get events for namespace `production` sorted by time, filtered to only Warning events.**

```bash
kubectl get events -n production \
  --field-selector=type=Warning \
  --sort-by='.lastTimestamp'
```

---

**Q97. TASK: A Pod shows `OOMKilled`. What do you check and fix?**

```bash
# Confirm OOMKill
kubectl describe pod <pod-name>
# Look for: "OOMKilled" in Last State, Exit Code: 137

# Check current limits
kubectl get pod <pod-name> -o jsonpath='{.spec.containers[0].resources}'

# Fix: Increase memory limit in Deployment
kubectl set resources deployment myapp \
  --limits=memory=512Mi \
  --requests=memory=256Mi
```

---

**Q98. TASK: Use `kubectl top` to find the Pod consuming the most CPU in namespace `prod`.**

```bash
kubectl top pods -n prod --sort-by=cpu | head -5
```

---

**Q99. TASK: A Service is not routing traffic. Debug the Endpoints.**

```bash
# Check Service exists and selector
kubectl describe svc my-service

# Check if Endpoints are populated
kubectl get endpoints my-service
# If empty → no Pods match the selector

# Fix: compare service selector vs pod labels
kubectl get pods --show-labels
kubectl get svc my-service -o jsonpath='{.spec.selector}'
```

---

**Q100. TASK: Find the container that restarted the most times in namespace `kube-system`.**

```bash
kubectl get pods -n kube-system \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{range .status.containerStatuses[*]}{.restartCount}{"\n"}{end}{end}' \
  | sort -t$'\t' -k2 -rn | head -5
```

---

**Q101. TASK: Run `kubectl exec` to check environment variables inside a running Pod.**

```bash
kubectl exec <pod-name> -- env
kubectl exec <pod-name> -- env | grep APP_ENV
```

---

**Q102. TASK: View the last 100 lines of logs from all containers in a Pod.**

```bash
kubectl logs <pod-name> --all-containers=true --tail=100
```

---

**Q103. TASK: Check which kube-system components are running as static Pods.**

```bash
ls /etc/kubernetes/manifests/
# etcd.yaml  kube-apiserver.yaml  kube-controller-manager.yaml  kube-scheduler.yaml

kubectl get pods -n kube-system | grep -E "etcd|apiserver|controller|scheduler"
```

---

**Q104. TASK: Use `kubectl diff` to preview changes before applying.**

```bash
kubectl diff -f updated-deployment.yaml
# Shows what WILL change — like git diff
```

---

**Q105. TASK: Find all resources in namespace `dev` with label `env=staging`.**

```bash
kubectl get all -n dev -l env=staging
```

---

## 10. Full Mock Exam Scenarios

---

**Q106. MOCK TASK 1 — Multi-step: Create a complete application stack.**

**Requirements:**
- Namespace: `app-ns`
- Deployment: `web`, image `nginx:1.25`, 2 replicas, namespace `app-ns`
- ConfigMap: `web-config`, key `NGINX_PORT=80`
- Service: ClusterIP on port 80
- Verify: curl from inside cluster works

```bash
# Step 1: Create namespace
kubectl create namespace app-ns

# Step 2: Create ConfigMap
kubectl create configmap web-config \
  --from-literal=NGINX_PORT=80 \
  -n app-ns

# Step 3: Create Deployment
kubectl create deployment web \
  --image=nginx:1.25 \
  --replicas=2 \
  -n app-ns

# Step 4: Inject ConfigMap env
kubectl set env deployment/web \
  --from=configmap/web-config \
  -n app-ns

# Step 5: Expose as Service
kubectl expose deployment web \
  --port=80 \
  --type=ClusterIP \
  -n app-ns

# Step 6: Verify
kubectl run test --image=busybox --rm -it --restart=Never \
  -n app-ns -- wget -O- http://web.app-ns.svc.cluster.local
```

---

**Q107. MOCK TASK 2 — Storage: Create PV, PVC, and mount in Pod.**

```bash
# Step 1: Create PV
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolume
metadata:
  name: task-pv
spec:
  capacity:
    storage: 1Gi
  accessModes:
  - ReadWriteOnce
  persistentVolumeReclaimPolicy: Retain
  hostPath:
    path: /mnt/task-data
EOF

# Step 2: Create PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: task-pvc
spec:
  accessModes:
  - ReadWriteOnce
  resources:
    requests:
      storage: 500Mi
EOF

# Step 3: Create Pod using PVC
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: task-pod
spec:
  containers:
  - name: app
    image: busybox
    command: ["sleep", "3600"]
    volumeMounts:
    - name: data
      mountPath: /data
  volumes:
  - name: data
    persistentVolumeClaim:
      claimName: task-pvc
EOF

# Step 4: Verify
kubectl get pv,pvc,pod
kubectl exec task-pod -- ls /data
```

---

**Q108. MOCK TASK 3 — RBAC: Full setup for a developer user.**

**Requirements:** User `dev-user` should be able to get/list/watch Pods and Deployments in namespace `development`, but nothing else.

```bash
# Step 1: Create namespace
kubectl create namespace development

# Step 2: Create Role
kubectl create role dev-role \
  --verb=get,list,watch \
  --resource=pods,deployments \
  -n development

# Step 3: Create RoleBinding
kubectl create rolebinding dev-binding \
  --role=dev-role \
  --user=dev-user \
  -n development

# Step 4: Verify
kubectl auth can-i list pods \
  --as=dev-user -n development      # Should be: yes

kubectl auth can-i delete pods \
  --as=dev-user -n development      # Should be: no

kubectl auth can-i list pods \
  --as=dev-user -n default          # Should be: no (different namespace)
```

---

**Q109. MOCK TASK 4 — Node Maintenance: Drain, upgrade kubelet, restore.**

```bash
# Step 1: Cordon node
kubectl cordon worker-1

# Step 2: Drain node
kubectl drain worker-1 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=30

# Step 3: (On worker node) Upgrade kubelet
ssh worker-1
apt-mark unhold kubelet kubectl
apt-get install -y kubelet=1.28.0-00 kubectl=1.28.0-00
apt-mark hold kubelet kubectl
systemctl daemon-reload && systemctl restart kubelet
exit

# Step 4: Uncordon and verify
kubectl uncordon worker-1
kubectl get nodes
kubectl get pods -o wide | grep worker-1   # Pods rescheduled
```

---

**Q110. MOCK TASK 5 — Troubleshooting: Fix a broken Deployment.**

**Scenario:** Deployment `broken-app` has 0 ready pods. It should be running `nginx:1.25` in namespace `qa`.

```bash
# Step 1: Investigate
kubectl get deployment broken-app -n qa
kubectl describe deployment broken-app -n qa
kubectl get pods -n qa -l app=broken-app
kubectl describe pod <pod-name> -n qa

# Common findings and fixes:

# Fix 1: Wrong image name
kubectl set image deployment/broken-app app=nginx:1.25 -n qa

# Fix 2: Pod has wrong nodeSelector (no matching node)
kubectl edit deployment broken-app -n qa
# Remove or fix nodeSelector

# Fix 3: Missing ConfigMap/Secret referenced by pod
kubectl create configmap missing-cm --from-literal=key=val -n qa

# Fix 4: Resource quota exceeded
kubectl describe resourcequota -n qa

# Step 2: Verify after fix
kubectl rollout status deployment/broken-app -n qa
kubectl get pods -n qa
```

---

**Q111. MOCK TASK 6 — etcd Backup and Restore.**

```bash
# BACKUP
ETCDCTL_API=3 etcdctl snapshot save /opt/backup/etcd-backup.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key

ETCDCTL_API=3 etcdctl snapshot status /opt/backup/etcd-backup.db

# RESTORE
ETCDCTL_API=3 etcdctl snapshot restore /opt/backup/etcd-backup.db \
  --data-dir=/var/lib/etcd-from-backup

# Update etcd manifest
vi /etc/kubernetes/manifests/etcd.yaml
# Find and update:
#   --data-dir=/var/lib/etcd  →  --data-dir=/var/lib/etcd-from-backup
# Also update the hostPath volume path to match

# Wait for etcd + API server to restart
sleep 30
kubectl get nodes
```

---

**Q112. MOCK TASK 7 — Create a fully configured Pod with multiple features.**

**Requirements:**
- Pod name: `full-pod`, namespace: `default`
- Container: `app`, image: `nginx:alpine`
- Environment: `APP_ENV=production` from ConfigMap `app-config`
- Secret: mount `db-secret` at `/secrets` (readonly)
- Resources: requests cpu=100m mem=64Mi, limits cpu=200m mem=128Mi
- Liveness probe: HTTP GET /healthz port 80, after 10s, every 5s
- Run as user 1000, non-root

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: full-pod
spec:
  securityContext:
    runAsUser: 1000
    runAsNonRoot: true
  containers:
  - name: app
    image: nginx:alpine
    resources:
      requests:
        cpu: "100m"
        memory: "64Mi"
      limits:
        cpu: "200m"
        memory: "128Mi"
    env:
    - name: APP_ENV
      valueFrom:
        configMapKeyRef:
          name: app-config
          key: APP_ENV
    volumeMounts:
    - name: secrets-vol
      mountPath: /secrets
      readOnly: true
    livenessProbe:
      httpGet:
        path: /healthz
        port: 80
      initialDelaySeconds: 10
      periodSeconds: 5
  volumes:
  - name: secrets-vol
    secret:
      secretName: db-secret
```

---

**Q113. MOCK TASK 8 — Ingress with TLS.**

```bash
# Step 1: Create TLS secret
kubectl create secret tls ingress-tls \
  --cert=/path/to/tls.crt \
  --key=/path/to/tls.key

# Step 2: Create Ingress with TLS
cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: secure-ingress
spec:
  ingressClassName: nginx
  tls:
  - hosts:
    - secure.example.com
    secretName: ingress-tls
  rules:
  - host: secure.example.com
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: web-svc
            port:
              number: 80
EOF

# Step 3: Verify
kubectl describe ingress secure-ingress
```

---

**Q114. MOCK TASK 9 — StatefulSet with persistent storage and headless service.**

```bash
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: redis-headless
spec:
  clusterIP: None
  selector:
    app: redis
  ports:
  - port: 6379
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: redis
spec:
  serviceName: redis-headless
  replicas: 3
  selector:
    matchLabels:
      app: redis
  template:
    metadata:
      labels:
        app: redis
    spec:
      containers:
      - name: redis
        image: redis:7-alpine
        ports:
        - containerPort: 6379
        volumeMounts:
        - name: data
          mountPath: /data
  volumeClaimTemplates:
  - metadata:
      name: data
    spec:
      accessModes: ["ReadWriteOnce"]
      resources:
        requests:
          storage: 1Gi
EOF

# Verify ordered creation
kubectl get pods -w   # redis-0 → redis-1 → redis-2
```

---

**Q115. MOCK TASK 10 — Upgrade kubeadm cluster and verify.**

```bash
# Full workflow verification
kubectl get nodes    # Before: all at v1.27.x

# Control plane
apt-get install -y kubeadm=1.28.0-00
kubeadm upgrade apply v1.28.0
apt-get install -y kubelet=1.28.0-00 kubectl=1.28.0-00
systemctl daemon-reload && systemctl restart kubelet

# Worker
kubectl drain node1 --ignore-daemonsets --delete-emptydir-data
# (on node1)
apt-get install -y kubeadm=1.28.0-00 && kubeadm upgrade node
apt-get install -y kubelet=1.28.0-00 kubectl=1.28.0-00
systemctl daemon-reload && systemctl restart kubelet
# (back on CP)
kubectl uncordon node1

# Final verification
kubectl get nodes
# All nodes should show VERSION: v1.28.x
```

---

## Bonus — CKA/CKAD Quick Reference Card

---

**Q116. What are the must-know `kubectl explain` paths?**

```bash
kubectl explain pod.spec
kubectl explain pod.spec.containers
kubectl explain pod.spec.containers.resources
kubectl explain pod.spec.containers.livenessProbe
kubectl explain pod.spec.affinity
kubectl explain pod.spec.tolerations
kubectl explain pod.spec.volumes
kubectl explain deployment.spec.strategy
kubectl explain pvc.spec.accessModes
kubectl explain networkpolicy.spec
```

---

**Q117. What are the fastest ways to create common resources?**

```bash
# Pod
kubectl run mypod --image=nginx

# Deployment
kubectl create deployment myapp --image=nginx --replicas=3

# Service (from existing deployment)
kubectl expose deployment myapp --port=80

# ConfigMap
kubectl create configmap mycm --from-literal=key=val

# Secret
kubectl create secret generic mysecret --from-literal=pass=abc

# ServiceAccount
kubectl create serviceaccount mysa

# Role
kubectl create role myrole --verb=get,list --resource=pods

# RoleBinding
kubectl create rolebinding myrb --role=myrole --user=alice

# Job
kubectl create job myjob --image=busybox -- echo hello

# CronJob
kubectl create cronjob mycj --image=busybox --schedule="*/5 * * * *" -- date

# Namespace
kubectl create namespace mynamespace
```

---

**Q118. What are the most important `-o jsonpath` patterns?**

```bash
# Pod IP
kubectl get pod mypod -o jsonpath='{.status.podIP}'

# Node of a Pod
kubectl get pod mypod -o jsonpath='{.spec.nodeName}'

# All pod names in a namespace
kubectl get pods -o jsonpath='{.items[*].metadata.name}'

# Container images in a deployment
kubectl get deploy myapp -o jsonpath='{.spec.template.spec.containers[*].image}'

# Service ClusterIP
kubectl get svc mysvc -o jsonpath='{.spec.clusterIP}'

# Secret value decoded
kubectl get secret mysecret -o jsonpath='{.data.password}' | base64 -d

# PVC storage request
kubectl get pvc mypvc -o jsonpath='{.spec.resources.requests.storage}'

# Node capacity
kubectl get node node1 -o jsonpath='{.status.capacity}'
```

---

**Q119. What is the complete list of exam-day checks to do at the start?**

```bash
# 1. Set aliases
alias k=kubectl
source <(kubectl completion bash)
complete -F __start_kubectl k

# 2. Export shortcuts
export do='--dry-run=client -o yaml'
export now='--force --grace-period=0'

# 3. Check current context
kubectl config current-context
kubectl config get-contexts

# 4. Confirm cluster access
kubectl get nodes
kubectl cluster-info

# 5. For EACH question — always run:
kubectl config use-context <given-context>
```

---

**Q120. What are the top mistakes to avoid in the CKA/CKAD exam?**

| Mistake | Prevention |
|---|---|
| Wrong namespace | Always use `-n <namespace>` or `kn <namespace>` |
| Wrong context | Always run `kubectl config use-context` at question start |
| Forgot to apply YAML | Always run `kubectl apply -f file.yaml` |
| Typo in YAML indentation | Use `kubectl explain` for correct field names |
| Didn't verify work | Always run `kubectl get/describe` after task |
| Spent too long on one question | Time-box 5 min; skip and return |
| Forgot `--ignore-daemonsets` on drain | Always include it — drain will fail otherwise |
| Wrong PVC access mode | Double-check: `ReadWriteOnce`, `ReadOnlyMany`, `ReadWriteMany` |
| Forgot restartPolicy in Job | Jobs need `OnFailure` or `Never` — not `Always` |
| Edited wrong resource | Confirm name/namespace before editing |

---

*End of CKA/CKAD Level — 120 Questions*

---

## Complete Series Summary

| File | Level | Questions | Key Topics |
|---|---|---|---|
| `interview-beginner-qa.md` | 🟢 Beginner | 120 | Architecture, Pods, Services, ConfigMaps, kubectl basics |
| `interview-intermediate-qa.md` | 🟡 Intermediate | 120 | Scheduling, RBAC, StatefulSets, Ingress, NetworkPolicy, HPA |
| `interview-advanced-qa.md` | 🟠 Advanced | 120 | etcd, TLS, Operators, Webhooks, CNI, Service Mesh, Observability |
| `interview-cka-ckad-qa.md` | 🔴 CKA/CKAD | 120 | Hands-on tasks, mock exams, speed drills, troubleshooting scenarios |

**Total: 480 questions — complete Kubernetes interview and exam preparation**
