# 📊 Observability

metrics-server, HPA, VPA, resource management, and monitoring your Kubernetes workloads.

---

## 📚 Table of Contents

- [1. metrics-server](#1-metrics-server)
- [2. Horizontal Pod Autoscaler (HPA)](#2-horizontal-pod-autoscaler-hpa)
- [3. Vertical Pod Autoscaler (VPA)](#3-vertical-pod-autoscaler-vpa)
- [4. Cluster Autoscaler](#4-cluster-autoscaler)
- [5. Resource Management](#5-resource-management)
- [6. Kubernetes Events](#6-kubernetes-events)
- [7. Logging](#7-logging)
- [8. Monitoring with Prometheus](#8-monitoring-with-prometheus)
- [Cheatsheet](#cheatsheet)

---

## 1. metrics-server

metrics-server collects **real-time** CPU and memory usage from kubelets and exposes them via the Kubernetes Metrics API. It powers `kubectl top` and HPA.

```bash
# Install metrics-server
kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# Or with Helm
helm repo add metrics-server https://kubernetes-sigs.github.io/metrics-server/
helm install metrics-server metrics-server/metrics-server -n kube-system

# For local clusters (self-signed certs) — add kubelet-insecure-tls arg
helm install metrics-server metrics-server/metrics-server -n kube-system \
  --set args[0]=--kubelet-insecure-tls

# Verify
kubectl get apiservice v1beta1.metrics.k8s.io
kubectl top nodes
kubectl top pods -A
```

### kubectl top

```bash
# Node resource usage
kubectl top nodes
# NAME       CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%
# worker-1   234m         11%    1843Mi           24%

# Pod resource usage
kubectl top pods
kubectl top pods -n production
kubectl top pods -A --sort-by=cpu
kubectl top pods -A --sort-by=memory
kubectl top pods -l app=my-app -n production

# Note: metrics-server shows current usage, not requests/limits
# For requests/limits, use: kubectl describe node
```

---

## 2. Horizontal Pod Autoscaler (HPA)

HPA automatically scales the number of pod replicas based on observed metrics.

```
HPA watches metrics every 15s (default)
         │
         │  CPU usage > 80%?
         ▼
   Scale up replicas
         │
         │  CPU usage < 80% for 5 min?
         ▼
   Scale down replicas
```

### HPA based on CPU (v2)

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: my-app-hpa
  namespace: production
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app

  minReplicas: 2
  maxReplicas: 20

  metrics:
    # CPU utilization
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 70    # target 70% of CPU request

    # Memory utilization
    - type: Resource
      resource:
        name: memory
        target:
          type: Utilization
          averageUtilization: 80

  behavior:
    scaleUp:
      stabilizationWindowSeconds: 60    # wait 60s before scaling up again
      policies:
        - type: Pods
          value: 4                      # add max 4 pods per scaling event
          periodSeconds: 60
        - type: Percent
          value: 100                    # or double the replicas
          periodSeconds: 60
      selectPolicy: Max                 # use whichever adds more pods

    scaleDown:
      stabilizationWindowSeconds: 300   # wait 5 min before scaling down
      policies:
        - type: Pods
          value: 1                      # remove max 1 pod at a time
          periodSeconds: 60
```

### HPA based on custom metrics

```yaml
metrics:
  # Custom metric from Prometheus Adapter
  - type: Pods
    pods:
      metric:
        name: http_requests_per_second
      target:
        type: AverageValue
        averageValue: 100             # 100 requests/second per pod

  # External metric (e.g., SQS queue depth)
  - type: External
    external:
      metric:
        name: sqs_messages_visible
        selector:
          matchLabels:
            queue: my-queue
      target:
        type: Value
        value: "100"                  # scale when >100 messages in queue
```

```bash
# View HPA status
kubectl get hpa -A
kubectl describe hpa my-app-hpa -n production

# Watch HPA scaling
kubectl get hpa -w

# Common HPA status conditions
# AbleToScale: True — can scale
# ScalingActive: True — metrics available, scaling decisions being made
# ScalingLimited: True — at min/max boundary
```

### HPA requirements

- Deployment must have `resources.requests.cpu` set (HPA can't calculate % without it)
- metrics-server must be installed
- For custom metrics: Prometheus Adapter or KEDA

---

## 3. Vertical Pod Autoscaler (VPA)

VPA automatically adjusts CPU and memory **requests** for containers based on actual usage.

```bash
# Install VPA
git clone https://github.com/kubernetes/autoscaler.git
cd autoscaler/vertical-pod-autoscaler
./hack/vpa-install.sh
```

```yaml
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: my-app-vpa
  namespace: production
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: my-app

  updatePolicy:
    updateMode: "Auto"    # Auto, Recreate, Initial, Off

  resourcePolicy:
    containerPolicies:
      - containerName: app
        minAllowed:
          cpu: 100m
          memory: 128Mi
        maxAllowed:
          cpu: 2
          memory: 2Gi
        controlledResources: [cpu, memory]
```

### VPA update modes

| Mode | Behavior |
|------|---------|
| `Off` | Only recommend — no changes made |
| `Initial` | Set requests at pod creation only |
| `Recreate` | Evict and recreate pods to apply new requests |
| `Auto` | Currently same as Recreate |

```bash
# Check VPA recommendations
kubectl describe vpa my-app-vpa -n production
# Look for: Recommendation section with suggested CPU/memory
```

> ⚠️ **Don't use HPA and VPA on CPU at the same time** — they conflict. Use VPA for memory, HPA for CPU (or use KEDA for advanced scaling).

---

## 4. Cluster Autoscaler

Scales the **number of nodes** in the cluster based on pending pods.

```
Pod can't be scheduled (insufficient resources)
              │
              ▼
    Cluster Autoscaler detects
              │
              ▼
    Adds a new node to the cluster
              │
              ▼
    Pod gets scheduled on new node
```

```bash
# Install on AWS EKS (via Helm)
helm repo add autoscaler https://kubernetes.github.io/autoscaler
helm install cluster-autoscaler autoscaler/cluster-autoscaler \
  --namespace kube-system \
  --set autoDiscovery.clusterName=my-cluster \
  --set awsRegion=eu-central-1
```

### Node group labels for auto-discovery

```bash
# Tag your AWS Auto Scaling Groups:
k8s.io/cluster-autoscaler/enabled = true
k8s.io/cluster-autoscaler/my-cluster = owned
```

---

## 5. Resource Management

### Understanding requests vs limits

```
                requests                    limits
                   │                          │
    Scheduler ─────┘   (decides where)        │
                                              │
    CPU: throttled if exceeded ───────────────┘
    Memory: OOMKilled if exceeded ────────────┘
```

### LimitRange — namespace defaults

```yaml
apiVersion: v1
kind: LimitRange
metadata:
  name: production-limits
  namespace: production
spec:
  limits:
    - type: Container
      default:              # applied if no limit specified
        cpu: "500m"
        memory: "256Mi"
      defaultRequest:       # applied if no request specified
        cpu: "100m"
        memory: "128Mi"
      max:                  # hard maximum per container
        cpu: "4"
        memory: "4Gi"
      min:                  # minimum required per container
        cpu: "50m"
        memory: "64Mi"
    - type: PersistentVolumeClaim
      max:
        storage: 50Gi
```

### ResourceQuota — namespace totals

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: production-quota
  namespace: production
spec:
  hard:
    # Compute
    requests.cpu: "20"
    requests.memory: 40Gi
    limits.cpu: "40"
    limits.memory: 80Gi
    # Object counts
    pods: "100"
    services: "20"
    secrets: "50"
    configmaps: "50"
    persistentvolumeclaims: "20"
    # Services by type
    services.loadbalancers: "2"
    services.nodeports: "0"         # no NodePort services
```

```bash
# Check quota usage
kubectl describe resourcequota -n production
# Shows: RESOURCE, USED, HARD (limit)
```

### Right-sizing recommendations

```bash
# See actual usage vs requests (requires metrics-server)
kubectl top pods -n production
# Compare with: kubectl describe pod | grep -A2 Requests

# VPA can automate this — run in "Off" mode to just get recommendations
kubectl describe vpa -n production
```

---

## 6. Kubernetes Events

Events record what happened to resources — crucial for debugging.

```bash
# Show events in current namespace
kubectl get events
kubectl get events --sort-by='.lastTimestamp'
kubectl get events -n production

# Show only warnings
kubectl get events --field-selector type=Warning

# Show events for a specific resource
kubectl describe pod my-pod           # shows related events at bottom
kubectl get events --field-selector involvedObject.name=my-pod

# Watch events live
kubectl get events -w
kubectl get events --sort-by='.lastTimestamp' -w

# Show all events cluster-wide
kubectl get events -A --sort-by='.lastTimestamp'
```

### Common event messages

| Event Reason | What it means |
|-------------|--------------|
| `Scheduled` | Pod assigned to a node |
| `Pulled` | Image pulled successfully |
| `Created` | Container created |
| `Started` | Container started |
| `Killing` | Container being terminated |
| `BackOff` | Container keeps crashing, exponential backoff |
| `OOMKilling` | Container killed for exceeding memory limit |
| `FailedScheduling` | No node can run the pod |
| `FailedMount` | Volume couldn't be mounted |
| `Unhealthy` | Probe failed |
| `ScalingReplicaSet` | Deployment scaling up/down |

---

## 7. Logging

### Accessing pod logs

```bash
# Basic logs
kubectl logs my-pod
kubectl logs my-pod -n production

# Specific container in multi-container pod
kubectl logs my-pod -c my-container

# Previous container (if crashed)
kubectl logs my-pod --previous
kubectl logs my-pod -p                # short form

# Follow logs
kubectl logs my-pod -f

# Time-based filtering
kubectl logs my-pod --since=1h
kubectl logs my-pod --since-time="2024-01-15T10:00:00Z"

# Limit lines
kubectl logs my-pod --tail=100

# All pods with a label
kubectl logs -l app=my-app --all-containers

# Combine options
kubectl logs -n production -l app=my-app -f --tail=50
```

### Cluster-level logging architecture

```
Pod writes to stdout/stderr
        │
        ▼
Container runtime writes to /var/log/pods/
        │
        ▼
Log agent (DaemonSet: Promtail, Fluentd, Filebeat)
        │
        ▼
Log backend (Loki, Elasticsearch, CloudWatch)
        │
        ▼
Dashboard (Grafana, Kibana)
```

### Promtail DaemonSet (for Loki)

```yaml
# Already covered in observability_k8s notes
# Promtail runs as DaemonSet, reads /var/log/pods/*, ships to Loki
```

---

## 8. Monitoring with Prometheus

Kubernetes-specific Prometheus monitoring — see `observability_k8s/` folder for full setup.

### Key Kubernetes metrics to monitor

```promql
# Pods not running
kube_pod_status_phase{phase!="Running", phase!="Succeeded"} > 0

# High pod restart count
rate(kube_pod_container_status_restarts_total[15m]) * 60 > 1

# Deployment replicas mismatch
kube_deployment_status_replicas_available
  != kube_deployment_spec_replicas

# Node memory pressure
kube_node_status_condition{condition="MemoryPressure", status="true"}

# PVC not bound
kube_persistentvolumeclaim_status_phase{phase!="Bound"}

# HPA at max replicas (can't scale further)
kube_horizontalpodautoscaler_status_current_replicas
  == kube_horizontalpodautoscaler_spec_max_replicas

# CPU throttling
rate(container_cpu_cfs_throttled_seconds_total[5m])
  / rate(container_cpu_cfs_periods_total[5m]) > 0.25
```

### Useful Grafana dashboards

```bash
# Import these dashboard IDs in Grafana:
# 315  — Kubernetes cluster monitoring
# 8588 — Kubernetes Deployment Statefulset Daemonset
# 6417 — Kubernetes Pods
# 3119 — Kubernetes cluster (Prometheus)
# 13770 — CoreDNS
```

---

## Cheatsheet

```bash
# Resource usage
kubectl top nodes
kubectl top pods -A --sort-by=cpu
kubectl top pods -A --sort-by=memory

# HPA
kubectl get hpa -A
kubectl describe hpa my-app-hpa
kubectl get hpa -w                  # watch scaling events

# Events
kubectl get events --sort-by='.lastTimestamp' -n production
kubectl get events -A -w

# Logs
kubectl logs my-pod --previous      # crashed container logs
kubectl logs -l app=my-app -f       # follow all pods with label

# ResourceQuota
kubectl describe resourcequota -n production

# VPA recommendations
kubectl describe vpa my-app-vpa -n production
```

---

*Next: [Troubleshooting →](./09-troubleshooting.md) — diagnosing and fixing common Kubernetes failures.*
