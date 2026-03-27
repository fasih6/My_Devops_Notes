# 🚀 Workloads

Deployments, StatefulSets, DaemonSets, Jobs, and CronJobs — when to use each and how to configure them.

---

## 📚 Table of Contents

- [1. Workload Overview](#1-workload-overview)
- [2. Deployment](#2-deployment)
- [3. ReplicaSet](#3-replicaset)
- [4. StatefulSet](#4-statefulset)
- [5. DaemonSet](#5-daemonset)
- [6. Job](#6-job)
- [7. CronJob](#7-cronjob)
- [8. Pod Lifecycle & Probes](#8-pod-lifecycle--probes)
- [9. Resource Requests & Limits](#9-resource-requests--limits)
- [10. Init Containers & Sidecars](#10-init-containers--sidecars)
- [Cheatsheet](#cheatsheet)

---

## 1. Workload Overview

| Workload | Use when | Pods | Storage | Identity |
|---------|---------|------|---------|---------|
| **Deployment** | Stateless apps (web, API) | Identical, interchangeable | Shared or none | No stable identity |
| **StatefulSet** | Stateful apps (databases, queues) | Each has unique identity | Own PVC per pod | Stable hostname + PVC |
| **DaemonSet** | One pod per node (agents, log shippers) | One per node | Usually node-local | No stable identity |
| **Job** | One-time batch task | Runs to completion | Ephemeral | No stable identity |
| **CronJob** | Scheduled recurring tasks | Runs to completion on schedule | Ephemeral | No stable identity |

---

## 2. Deployment

The most common workload. Manages stateless applications — keeps N replicas running, handles rolling updates and rollbacks.

### Full Deployment manifest

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: production
  labels:
    app: my-app
  annotations:
    kubernetes.io/change-cause: "Bumped to v1.2.3"    # shows in rollout history
spec:
  replicas: 3

  selector:
    matchLabels:
      app: my-app           # must match pod template labels

  strategy:
    type: RollingUpdate     # or Recreate
    rollingUpdate:
      maxSurge: 1           # how many extra pods during update
      maxUnavailable: 0     # how many pods can be down during update
      # maxSurge: 25% / maxUnavailable: 25% — percentage also works

  minReadySeconds: 10       # wait 10s after pod is ready before moving on

  revisionHistoryLimit: 5   # how many old ReplicaSets to keep (for rollback)

  template:
    metadata:
      labels:
        app: my-app         # must match selector.matchLabels
        version: v1.2.3
    spec:
      terminationGracePeriodSeconds: 30    # time to handle SIGTERM before SIGKILL

      containers:
        - name: app
          image: myregistry/my-app:v1.2.3
          imagePullPolicy: Always          # Always, IfNotPresent, Never

          ports:
            - name: http
              containerPort: 8080
            - name: metrics
              containerPort: 9090

          resources:
            requests:
              cpu: "100m"
              memory: "128Mi"
            limits:
              cpu: "500m"
              memory: "256Mi"

          env:
            - name: APP_ENV
              value: production
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: password

          livenessProbe:
            httpGet:
              path: /healthz
              port: 8080
            initialDelaySeconds: 15
            periodSeconds: 20
            failureThreshold: 3

          readinessProbe:
            httpGet:
              path: /ready
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
            failureThreshold: 3

      imagePullSecrets:
        - name: registry-credentials    # for private registries
```

### Deployment strategies

#### RollingUpdate (default)

```
Before: [v1] [v1] [v1]

Step 1: maxSurge=1, maxUnavailable=0
        [v1] [v1] [v1] [v2]   ← new pod added

Step 2: old pod removed after new one is Ready
        [v1] [v1] [v2]

Step 3: [v1] [v2] [v2]

Step 4: [v2] [v2] [v2]  ← done
```

Best for: zero downtime updates, gradual rollout.

#### Recreate

```
Before: [v1] [v1] [v1]
Step 1: Kill all  →  [] [] []   ← downtime here
Step 2: Create new → [v2] [v2] [v2]
```

Best for: when old and new versions cannot run simultaneously.

### Rollout commands

```bash
# Deploy
kubectl apply -f deployment.yaml

# Watch rollout progress
kubectl rollout status deployment/my-app

# View rollout history
kubectl rollout history deployment/my-app
kubectl rollout history deployment/my-app --revision=2

# Rollback to previous version
kubectl rollout undo deployment/my-app

# Rollback to specific revision
kubectl rollout undo deployment/my-app --to-revision=2

# Pause/resume rollout (for canary/staged rollouts)
kubectl rollout pause deployment/my-app
kubectl rollout resume deployment/my-app

# Force rolling restart (re-pulls images, picks up config changes)
kubectl rollout restart deployment/my-app
```

---

## 3. ReplicaSet

A ReplicaSet ensures a specified number of pod replicas are running. **You almost never create ReplicaSets directly** — Deployments manage them for you.

```yaml
apiVersion: apps/v1
kind: ReplicaSet
metadata:
  name: my-app-abc123
spec:
  replicas: 3
  selector:
    matchLabels:
      app: my-app
  template:
    ...
```

```bash
# See ReplicaSets managed by a Deployment
kubectl get replicasets
kubectl get rs -l app=my-app
# Old RS stays (0 replicas) for rollback — controlled by revisionHistoryLimit
```

---

## 4. StatefulSet

Used for stateful applications that need **stable network identity** and **persistent storage per pod**.

### What makes StatefulSet different

```
Deployment pods:           StatefulSet pods:
web-deployment-abc123      web-0
web-deployment-def456      web-1
web-deployment-ghi789      web-2

- Random names            - Predictable names (ordinal index)
- Any order               - Start in order: 0, 1, 2
- Any node                - Stable hostname per pod
- Shared or no PVC        - Own PVC per pod (not deleted on scale-down)
```

### StatefulSet manifest

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: production
spec:
  serviceName: postgres          # must match a Headless Service name
  replicas: 3
  selector:
    matchLabels:
      app: postgres

  updateStrategy:
    type: RollingUpdate          # or OnDelete
    rollingUpdate:
      partition: 0               # update pods with index >= partition

  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data

  # Each pod gets its own PVC from this template
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: fast-ssd
        resources:
          requests:
            storage: 20Gi
```

### Headless Service for StatefulSet

#### 🔹 What makes it different?
```
Normal Service (ClusterIP):               Headless Service: 
- Has a virtual IP (ClusterIP)            - No virtual IP
- Load-balances traffic across Pods       - No load balancing
- Client talks to the service IP          - DNS returns Pod IPs directly
                                          - Client talks directly to Pods
```
StatefulSets need a **headless Service** (clusterIP: None) to give each pod a stable DNS name:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres          # must match StatefulSet's serviceName
spec:
  clusterIP: None         # headless — no load balancing, direct pod DNS
  selector:
    app: postgres
  ports:
    - port: 5432
```

```
DNS names created:
postgres-0.postgres.production.svc.cluster.local
postgres-1.postgres.production.svc.cluster.local
postgres-2.postgres.production.svc.cluster.local
```

### StatefulSet scaling behavior

```bash
# Scale up — creates in order: 3, then 4, then 5
kubectl scale statefulset postgres --replicas=5

# Scale down — deletes in reverse order: 5, then 4, then 3
kubectl scale statefulset postgres --replicas=3
# PVCs are NOT deleted on scale-down — data is preserved
```

---

## 5. DaemonSet

Ensures **one pod runs on every node** (or a subset of nodes). Used for cluster-wide agents.

### Common DaemonSet use cases

- **Log collection** — Promtail, Fluentd, Filebeat
- **Monitoring** — Node Exporter, Datadog agent
- **Networking** — CNI plugins (Calico, Flannel)
- **Security** — Falco, vulnerability scanners
- **Storage** — Rook/Ceph storage agents

### DaemonSet manifest

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

  updateStrategy:
    type: RollingUpdate    # or OnDelete
    rollingUpdate:
      maxUnavailable: 1

  template:
    metadata:
      labels:
        app: node-exporter
    spec:
      # Access host network and filesystem
      hostNetwork: true
      hostPID: true

      tolerations:
        # Run on control plane nodes too
        - key: node-role.kubernetes.io/control-plane
          effect: NoSchedule

      containers:
        - name: node-exporter
          image: prom/node-exporter:latest
          ports:
            - containerPort: 9100
          volumeMounts:
            - name: proc
              mountPath: /host/proc
              readOnly: true
            - name: sys
              mountPath: /host/sys
              readOnly: true

      volumes:
        - name: proc
          hostPath:
            path: /proc
        - name: sys
          hostPath:
            path: /sys
```

### Run DaemonSet on subset of nodes

```yaml
spec:
  template:
    spec:
      nodeSelector:
        node-type: gpu         # only on GPU nodes
      # OR use affinity for more control
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
              - matchExpressions:
                  - key: kubernetes.io/os
                    operator: In
                    values: [linux]
```

---

## 6. Job

Runs a pod to **completion** — not continuously like a Deployment. Useful for batch processing, database migrations, data imports.

```yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: db-migration
spec:
  completions: 1          # number of successful completions required
  parallelism: 1          # how many pods run at once
  backoffLimit: 3         # max retries on failure
  activeDeadlineSeconds: 300   # kill job after 5 minutes

  template:
    spec:
      restartPolicy: OnFailure   # Never or OnFailure (not Always)
      containers:
        - name: migrate
          image: myapp:v1.2.3
          command: ["/bin/sh", "-c", "/app/migrate.sh"]
          env:
            - name: DB_URL
              valueFrom:
                secretKeyRef:
                  name: db-secret
                  key: url
```

### Parallel jobs

```yaml
spec:
  completions: 10      # need 10 successful completions
  parallelism: 3       # run 3 at a time
  # Kubernetes runs batches of 3 until 10 complete
```

```bash
# Watch job progress
kubectl get jobs
kubectl describe job db-migration
kubectl logs job/db-migration

# Delete job and its pods
kubectl delete job db-migration
```

---

## 7. CronJob

Runs Jobs on a **schedule** — like Linux cron but for Kubernetes.

```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: daily-backup
spec:
  schedule: "0 2 * * *"          # cron syntax: 2am every day
  timeZone: "Europe/Berlin"       # timezone (Kubernetes 1.27+)

  concurrencyPolicy: Forbid       # Allow, Forbid, Replace
  successfulJobsHistoryLimit: 3   # keep last 3 successful jobs
  failedJobsHistoryLimit: 1       # keep last 1 failed job
  startingDeadlineSeconds: 300    # deadline to start if missed schedule

  jobTemplate:
    spec:
      backoffLimit: 2
      template:
        spec:
          restartPolicy: OnFailure
          containers:
            - name: backup
              image: backup-tool:latest
              command: ["/bin/sh", "-c", "/scripts/backup.sh"]
```

```
# Cron schedule format
┌───────────── minute (0-59)
│ ┌─────────── hour (0-23)
│ │ ┌───────── day of month (1-31)
│ │ │ ┌─────── month (1-12)
│ │ │ │ ┌───── day of week (0=Sun)
│ │ │ │ │
* * * * *

0 2 * * *       daily at 2am
*/15 * * * *    every 15 minutes
0 9 * * 1-5     weekdays at 9am
0 0 1 * *       first of every month
```

```bash
# Manually trigger a CronJob
kubectl create job --from=cronjob/daily-backup manual-backup-$(date +%Y%m%d)

# View jobs created by CronJob
kubectl get jobs -l job-name=daily-backup
```

---

## 8. Pod Lifecycle & Probes

### Pod phases

| Phase | Meaning |
|-------|---------|
| `Pending` | Pod accepted, waiting for scheduling or image pull |
| `Running` | At least one container is running |
| `Succeeded` | All containers exited with code 0 |
| `Failed` | At least one container exited with non-zero code |
| `Unknown` | Pod state can't be determined (node issue) |

### Container states

| State | Meaning |
|-------|---------|
| `Waiting` | Not yet running — pulling image, waiting for secret |
| `Running` | Executing normally |
| `Terminated` | Finished (exited) |

### Probes — health checking

```yaml
containers:
  - name: app
    # Liveness — is the app alive? Kill and restart if fails.
    livenessProbe:
      httpGet:
        path: /healthz
        port: 8080
      initialDelaySeconds: 15    # wait before first check
      periodSeconds: 20           # check every 20s
      timeoutSeconds: 5           # timeout per check
      failureThreshold: 3         # fail 3 times before restart
      successThreshold: 1         # succeed once to be considered alive

    # Readiness — is the app ready for traffic? Remove from Service if fails.
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
      failureThreshold: 3

    # Startup — is the app still starting? Disable liveness until this passes.
    startupProbe:
      httpGet:
        path: /healthz
        port: 8080
      failureThreshold: 30       # allow 30 * 10s = 5 minutes to start
      periodSeconds: 10
```

### Probe types

```yaml
# HTTP GET — success if status code 200-399
livenessProbe:
  httpGet:
    path: /health
    port: 8080
    httpHeaders:
      - name: Custom-Header
        value: Awesome

# TCP socket — success if connection opens
livenessProbe:
  tcpSocket:
    port: 5432

# Exec — success if command exits 0
livenessProbe:
  exec:
    command:
      - /bin/sh
      - -c
      - "redis-cli ping | grep PONG"

# gRPC (Kubernetes 1.24+)
livenessProbe:
  grpc:
    port: 50051
```

### Liveness vs Readiness vs Startup

| Probe | Failure action | Use for |
|-------|---------------|---------|
| **Liveness** | Kill container and restart | Detecting deadlocks, infinite loops |
| **Readiness** | Remove from Service endpoints (stop traffic) | App warming up, temp unavailable |
| **Startup** | Kill container if never succeeds | Slow-starting apps (prevents liveness from killing during startup) |

### Graceful shutdown

```yaml
spec:
  terminationGracePeriodSeconds: 30   # default

  containers:
    lifecycle:
      preStop:
        exec:
          command: ["/bin/sh", "-c", "sleep 5"]   # drain connections before SIGTERM
```

```
Pod termination flow:
1. Pod marked Terminating
2. Removed from Service endpoints (traffic stops)
3. preStop hook executes
4. SIGTERM sent to containers
5. Wait up to terminationGracePeriodSeconds
6. SIGKILL if still running
```

---

## 9. Resource Requests & Limits

### Requests vs Limits

```yaml
resources:
  requests:          # minimum guaranteed resources (used for scheduling)
    cpu: "100m"      # 0.1 CPU core
    memory: "128Mi"
  limits:            # maximum allowed resources
    cpu: "500m"      # 0.5 CPU core
    memory: "256Mi"
```

| | Requests | Limits |
|--|---------|--------|
| **Purpose** | Scheduling guarantee | Maximum cap |
| **CPU exceeded** | — (no limit) | Throttled (slowed down) |
| **Memory exceeded** | — (no limit) | OOMKilled (container dies) |
| **Scheduler uses** | Yes | No |

### Quality of Service (QoS) classes

| Class | Condition | What happens under pressure |
|-------|-----------|---------------------------|
| **Guaranteed** | requests == limits for all containers | Last to be evicted |
| **Burstable** | requests < limits, or only one set | Middle priority |
| **BestEffort** | No requests or limits set | First to be evicted |

```yaml
# Guaranteed QoS (best for critical workloads)
resources:
  requests:
    cpu: "500m"
    memory: "256Mi"
  limits:
    cpu: "500m"      # same as request
    memory: "256Mi"  # same as request

# BestEffort QoS (avoid in production)
# no resources section at all
```

### CPU units

```
1 CPU = 1000m (millicores)
500m = 0.5 CPU = half a core
100m = 0.1 CPU = one tenth of a core
```

### Memory units

```
128Mi = 128 mebibytes (1Mi = 1024 * 1024 bytes)
1Gi   = 1 gibibyte
128M  = 128 megabytes (1M = 1000 * 1000 bytes)
```

---

## 10. Init Containers & Sidecars

### Init containers

Run **before** the main container. They must complete successfully before the main container starts.

```yaml
spec:
  initContainers:
    # Wait for database to be ready
    - name: wait-for-db
      image: busybox
      command: ['sh', '-c', 'until nc -z postgres 5432; do sleep 2; done']

    # Run database migration
    - name: run-migrations
      image: myapp:v1.2.3
      command: ["/app/migrate"]
      env:
        - name: DB_URL
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: url

  containers:
    - name: app
      image: myapp:v1.2.3
      # Starts only after all init containers succeed
```

### Sidecar containers

Run **alongside** the main container to add functionality:

```yaml
spec:
  containers:
    # Main application
    - name: app
      image: myapp:v1.2.3
      ports:
        - containerPort: 8080

    # Sidecar: log shipper
    - name: log-shipper
      image: fluent-bit:latest
      volumeMounts:
        - name: logs
          mountPath: /var/log/app

    # Sidecar: metrics exporter
    - name: metrics
      image: prom/statsd-exporter
      ports:
        - containerPort: 9102

  volumes:
    - name: logs
      emptyDir: {}
```

Common sidecar patterns:
- **Log shipping** — read logs from shared volume, forward to Loki/Elasticsearch
- **Service mesh proxy** — Envoy/Istio sidecar for traffic management
- **Metrics** — StatsD exporter alongside app
- **Secrets sync** — Vault agent syncing secrets to shared volume

---

## Cheatsheet

```bash
# Deployment
kubectl apply -f deployment.yaml
kubectl rollout status deployment/my-app
kubectl rollout undo deployment/my-app
kubectl rollout restart deployment/my-app
kubectl scale deployment my-app --replicas=5

# StatefulSet
kubectl get statefulsets
kubectl scale statefulset postgres --replicas=3
# PVCs are NOT deleted on scale-down

# DaemonSet
kubectl get daemonsets -A
kubectl rollout status daemonset/node-exporter -n monitoring

# Jobs
kubectl get jobs
kubectl logs job/my-job
kubectl delete job my-job

# CronJob
kubectl get cronjobs
kubectl create job --from=cronjob/daily-backup manual-run

# Pod health
kubectl describe pod my-pod    # shows probe failures in Events
kubectl get pod my-pod -o yaml # shows full spec including probes

# Resource usage
kubectl top pods
kubectl top nodes
kubectl describe node worker-1 | grep -A5 "Allocated resources"
```

---

*Next: [Networking →](./03-networking.md) — Services, Ingress, DNS, and Network Policies.*
