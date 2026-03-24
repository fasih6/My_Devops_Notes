# 📡 Observability Notes

A personal knowledge base for learning observability — from core concepts to hands-on tooling.

---

## 📚 Table of Contents

- [1. Concepts & Theory](#1-concepts--theory)
  - [What is Observability?](#what-is-observability)
  - [Metrics](#metrics)
  - [Logs](#logs)
  - [Tracing](#tracing)
  - [Kubernetes-specific Observability](#kubernetes-specific-observability)

---

## 1. Concepts & Theory

> Start here. Understanding the *why* before the *how* makes everything else click.

### What is Observability?

Observability is the ability to understand what's happening **inside** a system just by looking at what it **outputs** — without having to dig into the code or guess.

Think of it like a car dashboard: you don't open the hood every time something's wrong — the warning lights and gauges tell you what you need to know.

It's built on **three pillars**:

| Pillar | What it answers |
|--------|----------------|
| **Metrics** | *How much? How often? How fast?* |
| **Logs** | *What exactly happened, and when?* |
| **Traces** | *Where did this request go, and where did it slow down?* |

---

### Metrics

**What they are:** Numbers collected over time that describe your system's health and performance.

**Examples:**
- CPU usage at 85%
- 1,200 HTTP requests per second
- Memory consumption growing over 6 hours

**Common tools:**

| Tool | Role |
|------|------|
| **Prometheus** | Collects and stores metrics |
| **Grafana** | Visualizes metrics as dashboards and charts |
| **Kube-state-metrics** | Exposes Kubernetes cluster state as metrics |

---

### Logs

**What they are:** Text records of events that happened in your system — errors, warnings, info messages, debug output.

**Examples:**
- `ERROR: database connection timed out`
- `INFO: user login successful for user_id=42`
- `WARN: memory usage above 80%`

**Common tools:**

| Tool | Role |
|------|------|
| **Fluentd** | Collects and ships logs from containers |
| **Loki** | Stores and queries logs (Grafana's log backend) |
| **Elasticsearch** | Stores and indexes logs for fast search |
| **Kibana** | Visualizes logs stored in Elasticsearch |

---

### Tracing

**What it is:** Following a single request as it travels through multiple services — so you can see exactly where time was spent or where something broke.

**Example:** A user clicks "Buy" → the request hits the API gateway → auth service → inventory service → payment service. A trace shows the full journey and how long each step took.

**Common tools:**

| Tool | Role |
|------|------|
| **Jaeger** | Distributed tracing backend and UI |
| **OpenTelemetry** | Vendor-neutral standard for instrumenting apps |

---

### Kubernetes-specific Observability

Kubernetes adds its own layer of things to watch. Here's what matters:

| What to observe | Examples |
|----------------|---------|
| **Pod & Node metrics** | CPU, memory, network per pod or node |
| **Cluster events** | Deployments rolling out, pods crashing, restarts |
| **Service-level metrics** | Request latency, error rates, uptime |
| **Container runtime metrics** | Stats from Docker or containerd |
| **Custom app metrics** | Business or app-specific data you instrument yourself |

> 💡 **Key idea:** In Kubernetes, things are constantly moving — pods restart, scale up, get rescheduled. Good observability is what keeps you in control of that chaos.

---

*More sections coming soon — tooling setup, hands-on labs, and real-world examples.*
