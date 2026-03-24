# 📐 Architecture & Design Patterns

How to design observability for real-world microservices — not just install tools, but structure them well.

> **Why this matters:** Anyone can `helm install prometheus`. What separates a junior from a mid-level DevOps engineer is knowing *how* to design an observability system that scales, stays maintainable, and actually helps when things go wrong.

---

## 📚 Table of Contents

- [1. The Observability Stack as Architecture](#1-the-observability-stack-as-architecture)
- [2. The RED Method](#2-the-red-method)
- [3. The USE Method](#3-the-use-method)
- [4. The Four Golden Signals](#4-the-four-golden-signals)
- [5. Multi-Tenant Observability](#5-multi-tenant-observability)
- [6. The Push vs Pull Pattern](#6-the-push-vs-pull-pattern)
- [7. Observability as Code](#7-observability-as-code)
- [8. High Availability & Scalability](#8-high-availability--scalability)
- [9. Common Anti-Patterns](#9-common-anti-patterns)
- [Design Decisions Cheatsheet](#design-decisions-cheatsheet)

---

## 1. The Observability Stack as Architecture

Most tutorials show you how to install tools. But in production, you need to think about the full data flow — from your app to the screen.

### Full reference architecture

```
┌─────────────────────────────────────────────────────────┐
│                     Your Applications                    │
│         (instrumented with OTel SDK / Prometheus)        │
└───────────┬─────────────────┬───────────────────────────┘
            │ metrics          │ traces         │ logs
            ▼                  ▼                ▼
     ┌────────────┐    ┌─────────────┐   ┌───────────┐
     │ Prometheus │    │OTel Collector│   │ Promtail  │
     │  (scrape)  │    │  (receive)  │   │ (collect) │
     └─────┬──────┘    └──────┬──────┘   └─────┬─────┘
           │                  │                 │
           ▼                  ▼                 ▼
     ┌────────────┐    ┌─────────────┐   ┌───────────┐
     │ Thanos /   │    │   Jaeger    │   │   Loki    │
     │ Cortex     │    │  (storage)  │   │ (storage) │
     │ (long-term)│    └──────┬──────┘   └─────┬─────┘
     └─────┬──────┘           │                 │
           │                  │                 │
           └──────────────────┼─────────────────┘
                              ▼
                        ┌──────────┐
                        │  Grafana │
                        │ (unified │
                        │   view)  │
                        └──────────┘
                              │
                        ┌─────┴──────┐
                        │Alertmanager│
                        │ (routing)  │
                        └────────────┘
```

Each layer has a job. The architecture works because each component does **one thing well** and hands off to the next.

---

## 2. The RED Method

RED is the go-to framework for observability in **microservices**. For every service, track these three things:

| Signal | What to measure | Example metric |
|--------|----------------|----------------|
| **R**ate | How many requests per second | `rate(http_requests_total[5m])` |
| **E**rrors | How many requests are failing | `rate(http_requests_total{status=~"5.."}[5m])` |
| **D**uration | How long requests take | `histogram_quantile(0.99, rate(http_request_duration_seconds_bucket[5m]))` |

### Why RED works

If your **Rate** drops → something is blocking requests  
If your **Error** rate rises → something is broken  
If your **Duration** increases → something is slow

These three signals cover almost every user-facing problem. Start here before adding any other metrics.

### RED dashboard template (PromQL)

```promql
# Rate — requests per second
sum(rate(http_requests_total{service="my-app"}[5m]))

# Error rate — percentage of failed requests
sum(rate(http_requests_total{service="my-app", status=~"5.."}[5m]))
/ sum(rate(http_requests_total{service="my-app"}[5m])) * 100

# P99 latency — 99th percentile response time
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket{service="my-app"}[5m])) by (le)
)
```

---

## 3. The USE Method

USE is the framework for observability of **infrastructure** (nodes, disks, network). For every resource, track:

| Signal | What to measure | Example |
|--------|----------------|---------|
| **U**tilization | How busy is the resource? | CPU at 85% |
| **S**aturation | How much work is queued/waiting? | CPU run queue length |
| **E**rrors | Are there hardware or OS-level errors? | Disk read errors |

### USE vs RED — know when to use which

```
User reports slowness
        │
        ├── Is it the app?        → Use RED (check rate, errors, duration per service)
        │
        └── Is it the infra?      → Use USE (check CPU, memory, disk, network)
```

### USE dashboard PromQL

```promql
# CPU Utilization
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (node)

# CPU Saturation (run queue)
node_load1 / count(node_cpu_seconds_total{mode="idle"}) by (node)

# Memory Utilization
1 - node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# Disk Utilization
rate(node_disk_io_time_seconds_total[5m])

# Network Errors
rate(node_network_receive_errs_total[5m])
+ rate(node_network_transmit_errs_total[5m])
```

---

## 4. The Four Golden Signals

Coined by Google's SRE book. The four things that matter most for **any** system:

| Signal | What it is | When to alert |
|--------|-----------|--------------|
| **Latency** | Time to serve a request | P99 > SLO threshold |
| **Traffic** | Demand on the system | Sudden drop or spike |
| **Errors** | Rate of failed requests | Error rate > 1% |
| **Saturation** | How full your system is | CPU > 80%, disk > 85% |

### How RED, USE, and Golden Signals relate

```
Four Golden Signals (the what)
         │
    ┌────┴────┐
    │         │
   RED       USE
(services) (infra)
```

Think of the Four Golden Signals as the goal. RED and USE are the *how* — practical frameworks that help you implement them.

---

## 5. Multi-Tenant Observability

When you have **multiple teams, environments, or customers** sharing the same Kubernetes cluster, you need to think about separation and access control.

### Namespace-based separation

The simplest pattern — each team owns a namespace, and observability is scoped accordingly:

```yaml
# Prometheus only scrapes pods in team-a's namespace
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: team-a-apps
  namespace: team-a
spec:
  namespaceSelector:
    matchNames:
      - team-a
  selector:
    matchLabels:
      team: team-a
```

### Grafana multi-tenancy with Organizations

In Grafana, create a separate **Organization** per team:
- Each org has its own dashboards, data sources, and users
- Teams can't see each other's data
- One Grafana instance, many isolated views

```bash
# Create a new organization via Grafana API
curl -X POST http://admin:password@localhost:3000/api/orgs \
  -H "Content-Type: application/json" \
  -d '{"name": "Team A"}'
```

### Thanos for multi-cluster metrics

When you have **multiple clusters** (dev, staging, prod, different regions), Thanos lets you query all their Prometheus instances from one place:

```
Cluster A (eu-west)          Cluster B (us-east)
   Prometheus ──────────────── Prometheus
        │                           │
        └──────────┬────────────────┘
                   ▼
             Thanos Query
                   │
               Grafana
          (query all clusters)
```

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami

helm install thanos bitnami/thanos \
  --namespace monitoring \
  --set query.enabled=true \
  --set queryFrontend.enabled=true
```

---

## 6. The Push vs Pull Pattern

This is a fundamental design decision in observability architecture.

### Pull (Prometheus default)

Prometheus reaches out to your app and scrapes the `/metrics` endpoint on a schedule.

```
Prometheus ──── scrapes ────► App /metrics endpoint
```

**Pros:** Prometheus controls the schedule, easy to detect when a target is down  
**Cons:** Requires targets to be reachable (hard with short-lived jobs, Lambda, etc.)

### Push (Pushgateway, OTel, cloud agents)

Your app sends metrics/traces/logs to a collector.

```
App ──── pushes ────► OTel Collector / Pushgateway ────► Backend
```

**Pros:** Works for short-lived jobs, serverless, batch workloads  
**Cons:** Harder to detect if an app silently stops sending

### When to use which

| Scenario | Pattern | Reason |
|----------|---------|--------|
| Long-running services | Pull | Prometheus detects if target goes down |
| Batch jobs / cron | Push (Pushgateway) | Job ends before next scrape |
| Serverless (Lambda) | Push | No persistent endpoint to scrape |
| Traces | Push (OTel) | Traces are event-driven, not polled |
| Logs | Push (Promtail/Fluentd) | Logs stream continuously |

### Pushgateway for batch jobs

```yaml
# Job pushes its completion metric to Pushgateway
apiVersion: batch/v1
kind: Job
spec:
  template:
    spec:
      containers:
        - name: my-job
          command:
            - /bin/sh
            - -c
            - |
              # Do your work
              ./run-batch-job.sh

              # Push success metric to Pushgateway
              echo 'batch_job_last_success_timestamp $(date +%s)' | \
                curl --data-binary @- http://pushgateway:9091/metrics/job/my-batch-job
```

---

## 7. Observability as Code

Treating your observability config the same as your application code — versioned in Git, reviewed, tested, and deployed automatically.

### What to store in Git

```
observability/
├── prometheus/
│   ├── alert-rules/
│   │   ├── kubernetes.yaml
│   │   ├── applications.yaml
│   │   └── infrastructure.yaml
│   └── recording-rules/
│       └── aggregations.yaml
├── grafana/
│   ├── dashboards/
│   │   ├── service-overview.json
│   │   └── kubernetes-nodes.json
│   └── datasources/
│       └── datasources.yaml
├── alertmanager/
│   └── alertmanager.yaml
└── loki/
    └── loki-config.yaml
```

### Deploy Grafana dashboards as ConfigMaps

Instead of clicking in the UI, store dashboards as JSON in Git and load them automatically:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: grafana-dashboard-services
  namespace: monitoring
  labels:
    grafana_dashboard: "1"    # Grafana sidecar picks this up automatically
data:
  service-overview.json: |
    {
      "title": "Service Overview",
      "panels": [...]
    }
```

```bash
kubectl apply -f grafana-dashboards/
# Grafana reloads dashboards automatically — no restart needed
```

### Recording rules — pre-compute expensive queries

Instead of running complex PromQL on every dashboard load, pre-compute results as new metrics:

```yaml
# recording-rules.yaml
groups:
  - name: aggregations
    interval: 1m
    rules:
      # Pre-compute error rate per service (expensive query run once, result cached)
      - record: job:http_error_rate:ratio5m
        expr: |
          sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)
          / sum(rate(http_requests_total[5m])) by (job)

      # Pre-compute P99 latency per service
      - record: job:http_request_duration_p99:5m
        expr: |
          histogram_quantile(0.99,
            sum(rate(http_request_duration_seconds_bucket[5m])) by (job, le)
          )
```

Now dashboards query `job:http_error_rate:ratio5m` instead of the full expression — much faster.

---

## 8. High Availability & Scalability

Production observability needs to survive failures. Here's how to design for it.

### Prometheus HA — two replicas, same config

```yaml
# Run two identical Prometheus instances
# Both scrape the same targets — data is duplicated
apiVersion: monitoring.coreos.com/v1
kind: Prometheus
metadata:
  name: prometheus
spec:
  replicas: 2         # two instances scraping the same targets
  alerting:
    alertmanagers:
      - name: alertmanager
        port: web
```

Alertmanager deduplicates alerts from both replicas automatically.

### Thanos for long-term storage

By default, Prometheus only keeps data for 15 days (local disk). Thanos extends this:

```
Prometheus (15 days local)
      │
      │ Thanos Sidecar uploads blocks to
      ▼
  Object Storage (S3 / GCS / Azure Blob)
      │            (unlimited retention)
      ▼
  Thanos Store Gateway
  (serves historical data as if it were live)
      │
      ▼
  Thanos Query (unified query layer)
```

```yaml
# Add Thanos sidecar to Prometheus
spec:
  thanos:
    image: quay.io/thanos/thanos:v0.34.0
    objectStorageConfig:
      key: thanos.yaml
      name: thanos-objstore-config
```

### Loki scalability — monolith vs microservices mode

```
Small cluster (< 50 nodes):     Large cluster (100+ nodes):
  Loki monolith                   Loki microservices mode
  (single pod, simple)            (separate querier, ingester,
                                   compactor pods — scale each
                                   component independently)
```

```bash
# Small setup — monolith
helm install loki grafana/loki \
  --set loki.commonConfig.replication_factor=1 \
  --set singleBinary.replicas=1

# Large setup — distributed
helm install loki grafana/loki \
  --set deploymentMode=Distributed \
  --set ingester.replicas=3 \
  --set querier.replicas=2 \
  --set distributor.replicas=2
```

---

## 9. Common Anti-Patterns

Things that seem fine at first but cause pain at scale. Avoid these.

### ❌ Alerting on every metric

**Problem:** Alert fatigue — too many alerts, engineers start ignoring them.  
**Fix:** Alert on symptoms (user impact), not causes. Follow the RED method — if RED is healthy, users are fine.

### ❌ High cardinality labels

**Problem:** Adding labels like `user_id` or `request_id` to metrics creates millions of unique time series — Prometheus runs out of memory.

```promql
# BAD — user_id label creates one series per user
http_requests_total{method="GET", user_id="12345"}

# GOOD — keep labels low-cardinality
http_requests_total{method="GET", status="200"}
```

**Rule of thumb:** A label value should have fewer than ~100 unique values. If it has thousands, it's too high cardinality.

### ❌ Storing logs in Prometheus

**Problem:** Prometheus is for metrics (numbers). Storing log-like strings as label values causes cardinality explosion.  
**Fix:** Use Loki for logs. Use Prometheus for numbers.

### ❌ No retention policy

**Problem:** Logs and metrics accumulate forever, storage fills up, costs spiral.  
**Fix:** Define retention upfront:

```yaml
# Prometheus — keep 30 days
prometheus:
  retention: 30d
  retentionSize: 50GB   # whichever comes first

# Loki — keep 14 days
loki:
  limits_config:
    retention_period: 336h   # 14 days
```

### ❌ Dashboards nobody uses

**Problem:** Teams build 50 dashboards during setup. 48 are never opened again.  
**Fix:** Start with 3 dashboards: cluster overview, service RED metrics, active incidents. Add more only when you feel the need.

### ❌ Not testing alert rules

**Problem:** An alert rule has a typo in the PromQL — it never fires, and nobody notices until production is on fire.  
**Fix:** Test your rules:

```bash
# Validate alert rule files before applying
promtool check rules alert-rules.yaml

# Unit test your rules
promtool test rules tests/alert-rules-test.yaml
```

---

## Design Decisions Cheatsheet

| Decision | Small team / startup | Large team / enterprise |
|----------|---------------------|------------------------|
| Prometheus storage | Local (15-30 days) | Thanos + object storage |
| Log storage | Loki monolith | Loki distributed |
| Grafana access | Single org, shared | Multi-org per team |
| Alert routing | Slack only | Slack + PagerDuty by severity |
| Dashboards | 3 core dashboards | GitOps-managed per team |
| Metrics framework | RED for services | RED + USE + Golden Signals |
| Tracing | OTel + Jaeger | OTel + Grafana Tempo or cloud-native |
| Multi-cluster | Single Prometheus | Thanos Query across clusters |

---
