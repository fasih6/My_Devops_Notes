# ⚙️ Prometheus Operator Ecosystem

Everything that makes Prometheus work well in Kubernetes — exporters, custom resources, and the operator pattern explained.

> **Prerequisites:** Completed [02-tooling-setup.md](./02-tooling-setup.md) — `kube-prometheus-stack` is installed.

---

## 📚 Table of Contents

- [1. The Prometheus Operator](#1-the-prometheus-operator)
- [2. Node Exporter](#2-node-exporter)
- [3. kube-state-metrics](#3-kube-state-metrics)
- [4. ServiceMonitor](#4-servicemonitor)
- [5. PodMonitor](#5-podmonitor)
- [6. PrometheusRule](#6-prometheusrule)
- [7. Alertmanager Custom Resources](#7-alertmanager-custom-resources)
- [8. How It All Fits Together](#8-how-it-all-fits-together)
- [9. Expose Your Own App Metrics](#9-expose-your-own-app-metrics)
- [Cheatsheet](#cheatsheet)

---

## 1. The Prometheus Operator

### The problem it solves

Without the Operator, configuring Prometheus in Kubernetes is painful:
- You edit raw config files inside the Prometheus pod
- Adding a new scrape target means editing a ConfigMap and restarting Prometheus
- Alert rules live in config files disconnected from your app's code

The **Prometheus Operator** fixes this by introducing Kubernetes-native custom resources. Instead of editing config files, you `kubectl apply` YAML — just like deploying any other Kubernetes resource.

### What the Operator does

```
You apply a ServiceMonitor YAML
           │
           ▼
   Prometheus Operator watches for it
           │
           ▼
   Operator updates Prometheus config automatically
           │
           ▼
   Prometheus starts scraping the new target
   (no restart, no manual config editing)
```

### Custom Resources introduced by the Operator

| Resource | What it does |
|----------|-------------|
| `Prometheus` | Defines a Prometheus instance |
| `Alertmanager` | Defines an Alertmanager instance |
| `ServiceMonitor` | Tells Prometheus to scrape a Kubernetes Service |
| `PodMonitor` | Tells Prometheus to scrape individual Pods |
| `PrometheusRule` | Defines alert rules and recording rules |
| `AlertmanagerConfig` | Defines routing rules for Alertmanager |
| `ScrapeConfig` | Advanced scrape configuration |

### Check what's installed

```bash
# See all Operator custom resources in your cluster
kubectl get crd | grep monitoring.coreos.com

# Check the Operator is running
kubectl get pods -n monitoring | grep operator
```

---

## 2. Node Exporter

### What it is

Node Exporter is a Prometheus exporter that runs on **every node** in your cluster as a DaemonSet. It exposes hardware and OS-level metrics — the things happening below Kubernetes, at the Linux system level.

```
┌─────────────────────────────────┐
│           Node (VM)             │
│                                 │
│  ┌────────────────────────┐    │
│  │  Node Exporter (pod)   │    │
│  │  reads /proc, /sys     │    │
│  │  exposes :9100/metrics │    │
│  └────────────────────────┘    │
│                                 │
│  ┌──────┐ ┌──────┐ ┌──────┐   │
│  │ Pod  │ │ Pod  │ │ Pod  │   │
│  └──────┘ └──────┘ └──────┘   │
└─────────────────────────────────┘
```

### What it measures

| Category | Metrics |
|----------|---------|
| **CPU** | Usage per core, idle time, system/user split, iowait |
| **Memory** | Total, available, used, buffers, cache, swap |
| **Disk** | Read/write bytes, IOPS, filesystem usage, inodes |
| **Network** | Bytes in/out, packets, errors, drops per interface |
| **System** | Load average, open file descriptors, context switches |
| **Processes** | Running processes, blocked processes |

### Key Node Exporter metrics

```promql
# CPU usage per node (1 = 100%)
1 - avg(rate(node_cpu_seconds_total{mode="idle"}[5m])) by (instance)

# Memory available as a percentage
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes * 100

# Disk space remaining
node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100

# Network traffic in (bytes per second)
rate(node_network_receive_bytes_total[5m])

# Disk read throughput
rate(node_disk_read_bytes_total[5m])

# System load average (1 minute)
node_load1
```

### It's installed automatically

If you used `kube-prometheus-stack`, Node Exporter is already running as a DaemonSet:

```bash
# Verify Node Exporter is on every node
kubectl get daemonset -n monitoring | grep node-exporter

# Check metrics are being scraped
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
# Then visit localhost:9090/targets — look for node-exporter targets
```

---

## 3. kube-state-metrics

### What it is

kube-state-metrics listens to the **Kubernetes API** and exposes the *state* of Kubernetes objects as metrics. It answers questions like "how many replicas does this deployment have?" or "is this pod in a crash loop?"

### Node Exporter vs kube-state-metrics

This is a common point of confusion:

| | Node Exporter | kube-state-metrics |
|--|--------------|-------------------|
| **Watches** | Linux OS / hardware | Kubernetes API |
| **Answers** | Is this node's CPU high? | Is this deployment healthy? |
| **Examples** | CPU %, memory bytes, disk IOPS | Pod phase, replica count, resource limits |
| **Runs as** | DaemonSet (one per node) | Deployment (one per cluster) |

You need **both**. They cover different layers.

### What kube-state-metrics measures

| Object | Example metrics |
|--------|----------------|
| **Pods** | Phase (Running/Pending/Failed), restart count, ready status |
| **Deployments** | Desired vs available replicas, rollout status |
| **Nodes** | Ready condition, schedulable, disk/memory pressure |
| **Jobs** | Succeeded, failed, active count |
| **PersistentVolumes** | Phase, capacity, reclaim policy |
| **ResourceQuotas** | Used vs hard limit per namespace |
| **HorizontalPodAutoscaler** | Current vs desired replicas |

### Key kube-state-metrics queries

```promql
# Pods not in Running state
kube_pod_status_phase{phase!="Running", phase!="Succeeded"}

# Deployment rollout stuck (desired != available)
kube_deployment_spec_replicas != kube_deployment_status_replicas_available

# Pods with high restart count
kube_pod_container_status_restarts_total > 5

# Node not ready
kube_node_status_condition{condition="Ready", status="true"} == 0

# Pods close to memory limit (>80%)
container_memory_working_set_bytes
  / on(pod, container) kube_pod_container_resource_limits{resource="memory"}
  > 0.8

# Jobs that failed
kube_job_status_failed > 0

# Namespace resource quota usage
kube_resourcequota{type="used"} / kube_resourcequota{type="hard"} > 0.9
```

### Verify it's running

```bash
kubectl get deployment -n monitoring | grep kube-state-metrics
kubectl get pods -n monitoring | grep kube-state-metrics
```

---

## 4. ServiceMonitor

### What it is

A `ServiceMonitor` is a custom resource that tells Prometheus which Kubernetes **Services** to scrape for metrics, and how.

Instead of editing Prometheus's `scrape_configs` manually, you deploy a ServiceMonitor alongside your app — and the Operator automatically updates Prometheus's config.

### How it works

```
Your App Deployment
      │ exposes
      ▼
Kubernetes Service  (port: metrics, 8080)
      │
      │  ServiceMonitor selects this Service
      ▼
ServiceMonitor
      │
      │  Operator reads it and updates Prometheus config
      ▼
Prometheus scrapes Service at /metrics every 30s
```

### Basic ServiceMonitor example

```yaml
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-monitor
  namespace: default
  labels:
    release: prometheus        # must match Prometheus selector (see note below)
spec:
  selector:
    matchLabels:
      app: my-app              # selects Services with this label
  endpoints:
    - port: metrics            # the port name on the Service (not the number)
      path: /metrics           # where metrics are exposed (default: /metrics)
      interval: 30s            # how often to scrape
```

The matching Service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  labels:
    app: my-app               # matched by ServiceMonitor selector
spec:
  selector:
    app: my-app
  ports:
    - name: metrics           # must match ServiceMonitor endpoint port name
      port: 8080
      targetPort: 8080
```

> ⚠️ **Important:** The ServiceMonitor needs a label that matches the Prometheus CR's `serviceMonitorSelector`. With `kube-prometheus-stack`, that label is `release: prometheus`. Without it, Prometheus won't pick up your ServiceMonitor.

```bash
# Check what label Prometheus is looking for
kubectl get prometheus -n monitoring -o yaml | grep -A5 serviceMonitorSelector
```

### Apply and verify

```bash
kubectl apply -f service-monitor.yaml

# Check Prometheus picked it up (wait ~30s)
# Go to localhost:9090/targets — your app should appear
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
```

### ServiceMonitor with authentication

If your metrics endpoint requires authentication:

```yaml
spec:
  endpoints:
    - port: metrics
      scheme: https
      tlsConfig:
        insecureSkipVerify: true
      bearerTokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
```

---

## 5. PodMonitor

### What it is

A `PodMonitor` is like a ServiceMonitor but targets **Pods directly** — without needing a Kubernetes Service in front.

### When to use PodMonitor vs ServiceMonitor

| Use ServiceMonitor when... | Use PodMonitor when... |
|---------------------------|----------------------|
| Your app has a Kubernetes Service | Your app has no Service (e.g. a DaemonSet with no load balancer) |
| Standard web app deployment | Each pod exposes different metrics |
| You want traffic balanced | You want to scrape every pod individually |

### Basic PodMonitor example

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PodMonitor
metadata:
  name: my-daemonset-monitor
  namespace: default
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: my-daemonset         # selects Pods with this label
  podMetricsEndpoints:
    - port: metrics             # port name on the Pod spec
      path: /metrics
      interval: 30s
```

The matching Pod (from a DaemonSet):

```yaml
spec:
  template:
    metadata:
      labels:
        app: my-daemonset
    spec:
      containers:
        - name: my-app
          ports:
            - name: metrics     # must match PodMonitor port name
              containerPort: 9100
```

---

## 6. PrometheusRule

### What it is

A `PrometheusRule` is a custom resource for defining **alert rules** and **recording rules** as Kubernetes objects. Instead of editing config files, you deploy rules the same way you deploy apps — with `kubectl apply`.

### Alert rules

```yaml
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-app-alerts
  namespace: default
  labels:
    release: prometheus         # must match Prometheus ruleSelector
spec:
  groups:
    - name: my-app.rules
      rules:

        # Alert when error rate exceeds 5%
        - alert: HighErrorRate
          expr: |
            sum(rate(http_requests_total{status=~"5..", job="my-app"}[5m]))
            / sum(rate(http_requests_total{job="my-app"}[5m])) > 0.05
          for: 5m
          labels:
            severity: critical
            team: backend
          annotations:
            summary: "High error rate on my-app"
            description: "Error rate is {{ $value | humanizePercentage }} for the last 5 minutes."
            runbook_url: "https://github.com/your-org/runbooks/blob/main/high-error-rate.md"

        # Alert when pod is crash looping
        - alert: PodCrashLooping
          expr: rate(kube_pod_container_status_restarts_total{job="my-app"}[15m]) > 0
          for: 5m
          labels:
            severity: warning
          annotations:
            summary: "Pod {{ $labels.pod }} is crash looping"
```

### Recording rules

Recording rules pre-compute expensive PromQL expressions and save the result as a new metric. This makes dashboards load faster and reduces Prometheus query load.

```yaml
spec:
  groups:
    - name: my-app.recording
      interval: 1m              # evaluate every minute
      rules:

        # Pre-compute error rate per job
        - record: job:http_error_rate:ratio5m
          expr: |
            sum(rate(http_requests_total{status=~"5.."}[5m])) by (job)
            / sum(rate(http_requests_total[5m])) by (job)

        # Pre-compute P99 latency per job
        - record: job:http_request_duration_p99:5m
          expr: |
            histogram_quantile(0.99,
              sum(rate(http_request_duration_seconds_bucket[5m])) by (job, le)
            )

        # Pre-compute request rate per job
        - record: job:http_request_rate:5m
          expr: sum(rate(http_requests_total[5m])) by (job)
```

Now your Grafana dashboards query `job:http_error_rate:ratio5m` instead of the full expression — much faster at scale.

### Apply and verify

```bash
kubectl apply -f prometheus-rule.yaml

# Check Prometheus loaded the rules
# Go to localhost:9090/rules — your rules should appear
# Go to localhost:9090/alerts — check for any firing alerts
```

---

## 7. Alertmanager Custom Resources

### AlertmanagerConfig

Defines routing and receiver configuration for Alertmanager as a Kubernetes resource — scoped to a namespace.

```yaml
apiVersion: monitoring.coreos.com/v1alpha1
kind: AlertmanagerConfig
metadata:
  name: backend-team-alerts
  namespace: backend              # only routes alerts from this namespace
  labels:
    alertmanagerConfig: backend
spec:
  route:
    receiver: slack-backend
    groupBy: ['alertname', 'pod']
    groupWait: 30s
    repeatInterval: 4h
    matchers:
      - name: namespace
        value: backend

  receivers:
    - name: slack-backend
      slackConfigs:
        - apiURL:
            name: slack-webhook-secret    # reference a Kubernetes Secret
            key: url
          channel: '#backend-alerts'
          title: '{{ .GroupLabels.alertname }}'
          text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'
```

The Slack webhook URL is stored in a Secret (not hardcoded):

```bash
kubectl create secret generic slack-webhook-secret \
  --from-literal=url='https://hooks.slack.com/services/YOUR/WEBHOOK/URL' \
  -n backend
```

---

## 8. How It All Fits Together

Here's the complete picture of the Prometheus Operator ecosystem:

```
┌─────────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                        │
│                                                                   │
│  ┌─────────────┐    ┌──────────────────┐    ┌────────────────┐  │
│  │Node Exporter│    │ kube-state-metrics│    │   Your App     │  │
│  │ (DaemonSet) │    │  (Deployment)    │    │  (Deployment)  │  │
│  │ OS metrics  │    │  K8s API metrics │    │  /metrics      │  │
│  └──────┬──────┘    └────────┬─────────┘    └───────┬────────┘  │
│         │                    │                       │            │
│         │     ┌──────────────┴──────────────────┐   │            │
│         │     │         ServiceMonitors          │   │            │
│         │     │  (tell Prometheus what to scrape)│   │            │
│         │     └──────────────┬──────────────────┘   │            │
│         │                    │                       │            │
│         └────────────────────┼───────────────────────┘           │
│                              ▼                                    │
│                    ┌─────────────────┐                           │
│                    │    Prometheus   │◄── PrometheusRules         │
│                    │   (stores data) │    (alert + recording)     │
│                    └────────┬────────┘                           │
│                             │                                     │
│                    ┌────────▼────────┐                           │
│                    │  Alertmanager   │◄── AlertmanagerConfig      │
│                    │ (routes alerts) │    (routing rules)         │
│                    └────────┬────────┘                           │
│                             │                                     │
│                    ┌────────▼────────┐                           │
│                    │     Grafana     │                            │
│                    │  (dashboards)   │                            │
│                    └─────────────────┘                           │
│                                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │              Prometheus Operator                          │   │
│  │  Watches for ServiceMonitors, PodMonitors, PrometheusRules│   │
│  │  and automatically updates Prometheus + Alertmanager config│  │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### The flow in plain English

1. **Node Exporter** collects OS/hardware metrics from each node
2. **kube-state-metrics** collects Kubernetes object state from the API
3. **Your app** exposes custom metrics at `/metrics`
4. **ServiceMonitor / PodMonitor** tells Prometheus where to find each target
5. **Prometheus Operator** reads those resources and keeps Prometheus config in sync
6. **Prometheus** scrapes all targets and stores the data
7. **PrometheusRule** defines what conditions should trigger alerts
8. **Alertmanager** receives fired alerts and routes them to Slack/PagerDuty/email
9. **Grafana** queries Prometheus and displays everything as dashboards

---

## 9. Expose Your Own App Metrics

To make your app scrapeable by Prometheus, it needs to expose a `/metrics` endpoint in the Prometheus text format.

### Go — using the official Prometheus client

```go
package main

import (
    "net/http"
    "github.com/prometheus/client_golang/prometheus"
    "github.com/prometheus/client_golang/prometheus/promauto"
    "github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
    requestsTotal = promauto.NewCounterVec(
        prometheus.CounterOpts{
            Name: "http_requests_total",
            Help: "Total number of HTTP requests",
        },
        []string{"method", "status"},
    )

    requestDuration = promauto.NewHistogramVec(
        prometheus.HistogramOpts{
            Name:    "http_request_duration_seconds",
            Help:    "HTTP request duration in seconds",
            Buckets: prometheus.DefBuckets,
        },
        []string{"method"},
    )
)

func main() {
    http.Handle("/metrics", promhttp.Handler())   // expose metrics
    http.ListenAndServe(":8080", nil)
}
```

### Python — using the prometheus-client library

```python
from prometheus_client import Counter, Histogram, start_http_server

requests_total = Counter(
    'http_requests_total',
    'Total HTTP requests',
    ['method', 'status']
)

request_duration = Histogram(
    'http_request_duration_seconds',
    'HTTP request duration',
    ['method']
)

# Start metrics server on port 8080
start_http_server(8080)
```

### What the `/metrics` output looks like

```
# HELP http_requests_total Total number of HTTP requests
# TYPE http_requests_total counter
http_requests_total{method="GET",status="200"} 1234
http_requests_total{method="POST",status="500"} 7

# HELP http_request_duration_seconds HTTP request duration in seconds
# TYPE http_request_duration_seconds histogram
http_request_duration_seconds_bucket{method="GET",le="0.1"} 900
http_request_duration_seconds_bucket{method="GET",le="0.5"} 1200
http_request_duration_seconds_bucket{method="GET",le="+Inf"} 1234
http_request_duration_seconds_sum{method="GET"} 145.3
http_request_duration_seconds_count{method="GET"} 1234
```

### Full end-to-end: app → ServiceMonitor → Prometheus

```yaml
# 1. Deployment — your app
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
  namespace: default
spec:
  template:
    metadata:
      labels:
        app: my-app
    spec:
      containers:
        - name: my-app
          image: my-app:latest
          ports:
            - name: metrics        # name the port
              containerPort: 8080

---
# 2. Service — expose it
apiVersion: v1
kind: Service
metadata:
  name: my-app
  labels:
    app: my-app
spec:
  selector:
    app: my-app
  ports:
    - name: metrics              # same name as container port
      port: 8080

---
# 3. ServiceMonitor — tell Prometheus to scrape it
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app
  labels:
    release: prometheus
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s

---
# 4. PrometheusRule — alert on it
apiVersion: monitoring.coreos.com/v1
kind: PrometheusRule
metadata:
  name: my-app-alerts
  labels:
    release: prometheus
spec:
  groups:
    - name: my-app
      rules:
        - alert: HighErrorRate
          expr: |
            sum(rate(http_requests_total{status=~"5..",job="my-app"}[5m]))
            / sum(rate(http_requests_total{job="my-app"}[5m])) > 0.05
          for: 5m
          labels:
            severity: critical
          annotations:
            summary: "High error rate on my-app"
```

---

## Cheatsheet

```bash
# List all ServiceMonitors
kubectl get servicemonitor -A

# List all PodMonitors
kubectl get podmonitor -A

# List all PrometheusRules
kubectl get prometheusrule -A

# List all AlertmanagerConfigs
kubectl get alertmanagerconfig -A

# Check if Prometheus picked up a ServiceMonitor
# Go to localhost:9090/targets after port-forwarding

# Check if rules are loaded
# Go to localhost:9090/rules after port-forwarding

# Validate a PrometheusRule before applying
promtool check rules my-rule.yaml

# Debug — check Operator logs
kubectl logs -n monitoring -l app.kubernetes.io/name=prometheus-operator

# Check Prometheus config (generated by Operator)
kubectl get secret -n monitoring prometheus-prometheus-kube-prometheus-prometheus -o jsonpath='{.data.prometheus\.yaml\.gz}' | base64 -d | gunzip
```

### Common gotchas

| Problem | Cause | Fix |
|---------|-------|-----|
| ServiceMonitor not picked up | Missing `release: prometheus` label | Add the label that matches `serviceMonitorSelector` |
| Target shows as DOWN | Wrong port name | Make sure port name in ServiceMonitor matches Service port name |
| PrometheusRule not loaded | Missing `release: prometheus` label | Same as above — check `ruleSelector` on the Prometheus CR |
| Metrics endpoint 404 | App not exposing `/metrics` | Add Prometheus client library to your app |
| High cardinality warning | Too many label values | Remove high-cardinality labels (user IDs, request IDs) |

---
