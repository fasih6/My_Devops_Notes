# SRE with Kubernetes — Reliability in Practice

## Kubernetes as an SRE Platform

Kubernetes is not just an orchestrator — it's a reliability platform. It has built-in mechanisms for self-healing, traffic management, resource isolation, and controlled rollouts that map directly to SRE principles.

This file covers how SRE concepts — SLOs, error budgets, toil reduction, and reliability patterns — translate into concrete Kubernetes configurations.

---

## Health Probes — The Foundation of Self-Healing

Kubernetes uses probes to determine the health of pods. Properly configured probes are one of the highest-leverage reliability improvements you can make.

### Liveness Probe

**What it answers:** Is this container alive, or is it stuck/deadlocked?

If it fails → Kubernetes restarts the container.

```yaml
livenessProbe:
  httpGet:
    path: /healthz        # Must return 2xx when alive
    port: 8080
  initialDelaySeconds: 30  # Wait before first check (allow startup)
  periodSeconds: 10         # Check every 10 seconds
  failureThreshold: 3       # Restart after 3 consecutive failures
  timeoutSeconds: 5         # Probe times out after 5 seconds
```

**Rule:** The liveness endpoint must be simple and fast. Do NOT check dependencies (database, external services) in a liveness probe. If your DB is down, you don't want Kubernetes restarting all your pods — they'll all fail to start.

### Readiness Probe

**What it answers:** Is this container ready to receive traffic?

If it fails → Kubernetes removes the pod from the Service endpoint. Traffic stops going to it. The pod is NOT restarted.

```yaml
readinessProbe:
  httpGet:
    path: /ready
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 5
  failureThreshold: 3
  successThreshold: 1      # Must pass once to be considered ready
```

**Rule:** The readiness endpoint CAN check dependencies. If your DB connection is not established, return not-ready. Kubernetes will stop routing traffic to this pod until it's truly ready.

### Startup Probe

**What it answers:** Has the application finished starting up?

For slow-starting applications, startup probes prevent liveness probes from killing a pod that's still initializing.

```yaml
startupProbe:
  httpGet:
    path: /healthz
    port: 8080
  failureThreshold: 30     # Allow up to 30 × 10s = 5 minutes to start
  periodSeconds: 10
```

Once startup probe succeeds, liveness and readiness probes take over.

### The Three Probes — When to Use Each

```
Startup  → Is the app done initializing?
Liveness → Is the app alive (not deadlocked)?
Readiness → Is the app ready to serve traffic?

Startup:   Configure for slow-starting apps (JVM, large models)
Liveness:  Always configure — prevents stuck pods
Readiness: Always configure — prevents traffic to unready pods
```

---

## Resource Requests and Limits

Resource configuration is a major reliability lever. Misconfigured resources cause more K8s incidents than almost anything else.

### Requests vs Limits

```
Requests:
  What Kubernetes uses for scheduling
  "This pod needs at least X CPU and Y memory"
  Guaranteed to the pod

Limits:
  The maximum the pod can use
  If CPU limit exceeded → pod is throttled (slowed)
  If memory limit exceeded → pod is OOMKilled (restarted)
```

```yaml
resources:
  requests:
    memory: "256Mi"
    cpu: "250m"        # 250 millicores = 0.25 CPU
  limits:
    memory: "512Mi"
    cpu: "500m"
```

### Reliability Rules for Resource Configuration

**1. Always set requests**
Without requests, Kubernetes schedules pods without guarantees. Nodes get overcommitted, pods get evicted.

**2. Memory limit = memory request (for critical services)**
If memory limit > request, the pod can use more than scheduled. Under memory pressure, these pods get evicted first.

For critical services, set limit = request for guaranteed QoS class.

**3. CPU limits cause throttling — use with care**
CPU throttling is invisible in metrics but causes latency spikes. For latency-sensitive services, either don't set CPU limits or set them high.

**4. Use VPA (Vertical Pod Autoscaler) to right-size**
VPA observes actual resource usage and recommends (or automatically adjusts) requests. Start in recommendation mode, apply carefully.

### QoS Classes

| QoS Class | Condition | Eviction priority |
|-----------|-----------|------------------|
| **Guaranteed** | requests == limits for all containers | Last to be evicted |
| **Burstable** | requests set, limits > requests | Middle priority |
| **BestEffort** | No requests or limits set | First to be evicted |

For production SLO-bearing services: use Guaranteed QoS.

---

## Pod Disruption Budgets (PDB)

A PDB limits how many pods of a deployment can be unavailable simultaneously during voluntary disruptions (node drains, rolling updates, cluster upgrades).

### The Problem Without PDB

```
You have 3 replicas of checkout-api
Kubernetes drains a node for maintenance
Without PDB: all 3 pods could be evicted simultaneously
Result: checkout is completely down during maintenance
```

### The Solution

```yaml
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: checkout-api-pdb
  namespace: checkout
spec:
  minAvailable: 2          # At least 2 pods must always be available
  selector:
    matchLabels:
      app: checkout-api
```

Or equivalently:

```yaml
spec:
  maxUnavailable: 1        # At most 1 pod can be unavailable at a time
```

**Rule:** Set PDBs for every production service with more than 1 replica. Without a PDB, cluster maintenance can silently take down your service.

---

## Horizontal Pod Autoscaler (HPA)

HPA automatically scales the number of pod replicas based on metrics — handling load spikes without manual intervention (reducing toil).

### Basic HPA on CPU

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: checkout-api-hpa
  namespace: checkout
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: checkout-api
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70    # Scale when avg CPU > 70%
```

### HPA on Custom Metrics (for SLO-based scaling)

Scale based on request latency (p99) instead of CPU:

```yaml
metrics:
- type: Pods
  pods:
    metric:
      name: http_request_duration_p99
    target:
      type: AverageValue
      averageValue: "250m"   # Scale when p99 > 250ms
```

This requires Prometheus Adapter or KEDA.

### KEDA (Kubernetes Event-Driven Autoscaling)

KEDA extends HPA with rich scaling triggers:

```yaml
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: checkout-scaledobject
spec:
  scaleTargetRef:
    name: checkout-api
  minReplicaCount: 2
  maxReplicaCount: 20
  triggers:
  - type: prometheus
    metadata:
      serverAddress: http://prometheus.monitoring:9090
      metricName: checkout_queue_depth
      threshold: "100"           # Scale when queue depth > 100
      query: sum(checkout_queue_depth)
```

---

## Implementing SLOs on Kubernetes

### Measuring SLIs with Prometheus

**Availability SLI** (% of successful requests):
```promql
# Success rate
sum(rate(http_requests_total{namespace="checkout",code!~"5.."}[5m]))
/
sum(rate(http_requests_total{namespace="checkout"}[5m]))
```

**Latency SLI** (% of requests under 300ms):
```promql
sum(rate(http_request_duration_seconds_bucket{
  namespace="checkout", le="0.3"}[5m]))
/
sum(rate(http_request_duration_seconds_count{namespace="checkout"}[5m]))
```

### SLO Alerting with Prometheus Rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: checkout-slo-rules
  namespace: checkout
spec:
  groups:
  - name: checkout-slo
    rules:
    # Record the error rate (for efficiency)
    - record: job:checkout_error_rate:ratio_rate5m
      expr: |
        sum(rate(http_requests_total{namespace="checkout",code=~"5.."}[5m]))
        /
        sum(rate(http_requests_total{namespace="checkout"}[5m]))

    # Alert on fast burn (2% budget consumed in 1 hour)
    - alert: CheckoutSLOFastBurn
      expr: |
        job:checkout_error_rate:ratio_rate5m > (14.4 * 0.001)
      for: 2m
      labels:
        severity: critical
        team: checkout
      annotations:
        summary: "Checkout SLO fast burn rate"
        description: "Error rate {{ $value | humanizePercentage }} — burning budget 14x faster than normal"
        runbook: "https://wiki.internal/runbooks/checkout-slo-fast-burn"

    # Alert on slow burn (10% budget in 3 days)
    - alert: CheckoutSLOSlowBurn
      expr: |
        job:checkout_error_rate:ratio_rate5m > (3 * 0.001)
      for: 60m
      labels:
        severity: warning
        team: checkout
      annotations:
        summary: "Checkout SLO slow burn rate"
        description: "Error rate {{ $value | humanizePercentage }} — elevated, investigate this week"
```

---

## Deployment Reliability Patterns in Kubernetes

### Rolling Updates

Default Kubernetes strategy — gradually replaces old pods with new:

```yaml
spec:
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 0     # Never have fewer than desired replicas
      maxSurge: 1           # Allow 1 extra pod during update
```

With `maxUnavailable: 0`, there's always full capacity during the rollout. The rollout is slower but zero-downtime.

### Readiness Gates for Safe Rollouts

Use readiness gates to block pod traffic until external checks pass:

```yaml
spec:
  readinessGates:
  - conditionType: "target-health.alb.ingress.k8s.aws/my-ingress"
```

The pod won't receive traffic until the load balancer confirms it's healthy — not just when Kubernetes thinks it is.

### Argo Rollouts — Progressive Delivery

For canary and blue-green in Kubernetes (see also: `08-reliability-patterns.md`):

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Rollout
spec:
  strategy:
    canary:
      analysis:
        templates:
        - templateName: checkout-success-rate
        startingStep: 2
      steps:
      - setWeight: 5
      - pause: {duration: 5m}
      - setWeight: 20
      - pause: {duration: 10m}
      - setWeight: 50
      - pause: {duration: 10m}
```

With analysis templates, Argo Rollouts automatically rolls back if the canary's error rate exceeds your SLO threshold.

---

## Reducing Toil with Kubernetes

Kubernetes is a toil-reduction machine when used well:

| Manual toil | Kubernetes solution |
|-------------|-------------------|
| Restart crashed services | Liveness probes + automatic restart |
| Scale during load spikes | HPA / KEDA |
| Remove unhealthy instances | Readiness probes remove from LB |
| Drain nodes for maintenance | PDB ensures minimum availability |
| Deploy new versions safely | Rolling updates / Argo Rollouts |
| Certificate rotation | cert-manager automates TLS cert renewal |
| Secret rotation | External Secrets Operator syncs from Vault/Azure KV |

---

## Interview Questions — SRE with Kubernetes

**Q: What's the difference between liveness and readiness probes?**
A: Liveness determines if the container is alive — failure causes a restart. Readiness determines if it's ready to serve traffic — failure removes it from the load balancer without restarting. Liveness should check only the app itself; readiness can check dependencies.

**Q: What is a PodDisruptionBudget and why do you need one?**
A: A PDB sets a minimum number of available pods during voluntary disruptions (node drains, maintenance). Without one, a node drain can evict all replicas simultaneously, causing downtime. For any production service, set minAvailable to at least 1 less than your total replicas.

**Q: How do you implement SLO-based alerting in Kubernetes?**
A: Define PrometheusRules that compute the SLI (e.g. error rate ratio), then alert based on burn rate rather than raw SLO breach. Fast burn (e.g. 14x normal rate) pages immediately; slow burn creates a warning ticket. This catches both sudden outages and slow degradation.

**Q: What QoS class should production services use?**
A: Guaranteed QoS (requests == limits) for critical services. This ensures the pod has stable, predictable resources and is last to be evicted under node memory pressure. BestEffort pods (no requests/limits) are the first to go — never use for production workloads.
