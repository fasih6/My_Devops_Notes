# 🔭 Kubernetes Observability

A structured knowledge base covering observability on Kubernetes — from core concepts to production-grade architecture.

> Built while preparing for DevOps & cloud engineering roles. Notes are practical, hands-on, and written in plain English.

---

## 🗺️ Learning Path

Work through these in order — each file builds on the previous one.

```
01 → 02 → 03 → 04 → 05 → 06
 │     │     │     │     │     │
 │     │     │     │     │     └── How to design it all at scale
 │     │     │     │     └──────── Cloud-native tools (AWS/GCP/Azure)
 │     │     │     └────────────── Tracing requests across services
 │     │     └──────────────────── Know when things break
 │     └────────────────────────── Get the tools running
 └──────────────────────────────── Understand the fundamentals
```

---

## 📚 Contents

| # | File | What you'll learn |
|---|------|------------------|
| 01 | [Concepts & Theory](./01-concepts-theory.md) | What observability is, the three pillars (metrics, logs, traces), and Kubernetes-specific concepts |
| 02 | [Tooling Setup](./02-tooling-setup.md) | Install and configure Prometheus, Grafana, and Loki on a Kubernetes cluster |
| 03 | [Alerting & Incident Response](./03-alerting-incident-response.md) | Write alert rules, configure Alertmanager, build runbooks, respond to incidents |
| 04 | [Tracing Deep Dive](./04-tracing-deep-dive.md) | Set up OpenTelemetry and Jaeger, instrument apps in Go and Python, read traces |
| 05 | [Cloud Provider Observability](./05-cloud-provider-observability.md) | Native tools on AWS (CloudWatch), GCP (Cloud Monitoring), and Azure (Azure Monitor) |
| 06 | [Architecture & Design Patterns](./06-architecture-design-patterns.md) | RED/USE/Golden Signals, multi-tenancy, HA, observability as code, anti-patterns |

---

## 🧰 Tools Covered

| Category | Tools |
|----------|-------|
| **Metrics** | Prometheus, Grafana, kube-state-metrics, node-exporter, Thanos |
| **Logs** | Loki, Promtail, Fluentd, CloudWatch Logs, Cloud Logging, Log Analytics |
| **Traces** | OpenTelemetry, Jaeger, X-Ray, Cloud Trace, Application Insights |
| **Alerting** | Alertmanager, Grafana Alerts, CloudWatch Alarms, Azure Alerts |
| **Cloud** | AWS Container Insights, GCP Managed Prometheus, Azure Container Insights |

---

## ⚡ Quick Reference

### Most useful PromQL queries

```promql
# Request rate per service
sum(rate(http_requests_total[5m])) by (service)

# Error rate (%)
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
/ sum(rate(http_requests_total[5m])) by (service) * 100

# P99 latency
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service))

# CPU usage per pod
sum(rate(container_cpu_usage_seconds_total[5m])) by (pod)

# Memory usage per pod
sum(container_memory_working_set_bytes) by (pod)
```

### Most useful kubectl commands during an incident

```bash
# What's not running?
kubectl get pods -A | grep -v Running

# Recent cluster events
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Logs from a crashing pod
kubectl logs <pod> -n <namespace> --previous

# Resource usage
kubectl top pods -n <namespace>
kubectl top nodes

# Quick rollback
kubectl rollout undo deployment/<name> -n <namespace>
```

### Port-forward everything

```bash
# Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring

# Grafana
kubectl port-forward svc/grafana 3000:80 -n monitoring

# Alertmanager
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring

# Jaeger
kubectl port-forward svc/jaeger-query 16686:16686 -n monitoring
```

---

## 🧠 Key Concepts at a Glance

| Concept | One-line summary |
|---------|-----------------|
| **Observability** | Understanding a system's internal state from its outputs |
| **RED Method** | Rate, Errors, Duration — for every microservice |
| **USE Method** | Utilization, Saturation, Errors — for every resource |
| **Four Golden Signals** | Latency, Traffic, Errors, Saturation — from Google SRE |
| **Trace** | Full journey of one request across all services |
| **Span** | One unit of work within a trace |
| **Cardinality** | Number of unique label combinations — keep it low in Prometheus |
| **Tail sampling** | Record only slow/error traces, drop the rest |
| **Recording rules** | Pre-computed PromQL results stored as new metrics |
| **Alertmanager** | Routes alerts to the right team via the right channel |

---

## 🗂️ Repo Structure

```
observability_k8s/
├── 00-index.md                         ← You are here
├── 01-concepts-theory.md
├── 02-tooling-setup.md
├── 03-alerting-incident-response.md
├── 04-tracing-deep-dive.md
├── 05-cloud-provider-observability.md
└── 06-architecture-design-patterns.md
```

---

*Notes are living documents — updated as I learn and build.*
