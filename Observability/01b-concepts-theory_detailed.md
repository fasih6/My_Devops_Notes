# 📖 Concepts & Theory

The fundamentals of observability — understand the *why* before the *how*.

> Everything in the later files makes more sense once these concepts are clear. Don't skip this.

---

## 📚 Table of Contents

- [1. What is Observability?](#1-what-is-observability)
- [2. Observability vs Monitoring](#2-observability-vs-monitoring)
- [3. The Three Pillars](#3-the-three-pillars)
  - [Metrics](#metrics)
  - [Logs](#logs)
  - [Traces](#traces)
- [4. How the Three Pillars Work Together](#4-how-the-three-pillars-work-together)
- [5. SLIs, SLOs, and SLAs](#5-slis-slos-and-slas)
- [6. Error Budgets](#6-error-budgets)
- [7. Kubernetes-Specific Observability](#7-kubernetes-specific-observability)
- [8. Instrumentation](#8-instrumentation)
- [9. Cardinality](#9-cardinality)
- [10. Sampling](#10-sampling)
- [11. Observability in the SDLC](#11-observability-in-the-sdlc)
- [Key Terms Glossary](#key-terms-glossary)

---

## 1. What is Observability?

Observability is the ability to understand what is happening **inside** a system just by looking at what it **outputs** — without needing to touch the code or guess.

The term comes from control theory (engineering): a system is "observable" if you can determine its internal state from its external outputs alone.

### The analogy

Think of a car dashboard. You don't open the hood every time you want to know how the engine is doing. The dashboard — speed, temperature, fuel, warning lights — tells you what you need to know. That's observability.

In software, your system's "dashboard" is made of metrics, logs, and traces.

### Why it matters

Modern systems are distributed — dozens of microservices, running across many containers, on many nodes. When something goes wrong:

- You can't SSH into every pod
- You can't reproduce every issue locally
- Problems often emerge from the *interaction* between services, not inside a single one

Observability gives you the tools to answer **"what is happening and why?"** without needing to be there when it happens.

---

## 2. Observability vs Monitoring

These terms are often used interchangeably, but they mean different things:

| | Monitoring | Observability |
|--|-----------|--------------|
| **Focus** | Known failure modes | Unknown and unexpected failures |
| **Approach** | Check predefined conditions | Explore and ask new questions |
| **Question** | "Is X broken?" | "Why is X behaving this way?" |
| **Example** | Alert when CPU > 80% | Investigate why latency spiked last Tuesday |
| **Tooling** | Dashboards, alerts | Metrics + logs + traces + querying |

### The key difference

Monitoring tells you **when** something is wrong.  
Observability helps you understand **why**.

You need both. Monitoring catches fires. Observability helps you put them out and understand what caused them.

---

## 3. The Three Pillars

### Metrics

**What they are:** Numbers collected over time that describe your system's state and performance.

Metrics are the most efficient form of telemetry — a single number can summarize the behavior of thousands of requests. They are ideal for alerting and dashboards.

**Examples:**
- CPU usage: `85%`
- Request rate: `1,200 req/s`
- Memory used: `3.2 GB`
- HTTP error rate: `2.4%`
- Pod restart count: `7`

**Structure of a metric:**

```
http_requests_total{method="GET", status="200", service="checkout"} 4521
       │                    │                                          │
   metric name           labels                                     value
```

- **Metric name** — what is being measured
- **Labels** — dimensions that describe the metric (low cardinality values only)
- **Value** — the number at this point in time
- **Timestamp** — when it was recorded (added automatically)

**Metric types:**

| Type | What it is | Example |
|------|-----------|---------|
| **Counter** | Always increases, never decreases | Total HTTP requests, total errors |
| **Gauge** | Can go up or down | Current CPU %, memory in use, active connections |
| **Histogram** | Samples observations into buckets | Request duration, response size |
| **Summary** | Like histogram but calculates quantiles client-side | P99 latency |

**When to use histogram vs summary:**
- Use **histogram** when you need to aggregate across multiple instances (most cases)
- Use **summary** only when you need accurate quantiles for a single instance

**Tools:** Prometheus, Grafana, kube-state-metrics, node-exporter, Thanos

---

### Logs

**What they are:** Timestamped, text-based records of individual events that happened in your system.

Logs are the most detailed form of telemetry — they capture exactly what happened and when. They are ideal for debugging and root cause analysis.

**Examples:**
```
2024-01-15T10:23:45Z INFO  User login successful user_id=42 ip=192.168.1.1
2024-01-15T10:23:46Z ERROR Database connection failed error="timeout after 30s"
2024-01-15T10:23:47Z WARN  Memory usage above 80% current=82% threshold=80%
```

**Log levels (in order of severity):**

| Level | When to use |
|-------|------------|
| `DEBUG` | Detailed info for development — never on in production |
| `INFO` | Normal operation — user logins, requests completed |
| `WARN` | Something unexpected but not breaking — degraded performance |
| `ERROR` | Something failed — a request couldn't be served |
| `FATAL` | System cannot continue — process will exit |

**Structured vs unstructured logs:**

```
# Unstructured — hard to query
ERROR: failed to connect to database at 10:23:46

# Structured (JSON) — easy to filter and aggregate
{"level":"error","time":"2024-01-15T10:23:46Z","msg":"failed to connect","db":"postgres","retry":3}
```

Always use **structured logging** in production. It makes log querying dramatically easier.

**Log pipeline:**

```
App writes logs to stdout/stderr
          │
          ▼
   Promtail / Fluentd         ← collects from nodes
   (log shipping agent)
          │
          ▼
       Loki / Elasticsearch   ← stores and indexes
          │
          ▼
   Grafana / Kibana           ← query and visualize
```

**Tools:** Loki, Promtail, Fluentd, Elasticsearch, Kibana, CloudWatch Logs

---

### Traces

**What they are:** A record of the full journey of a single request as it travels through multiple services.

While metrics tell you *something is slow* and logs tell you *an error happened*, traces tell you *exactly which service, in which call, at what step* the problem occurred.

**Core concepts:**

| Term | What it means |
|------|--------------|
| **Trace** | The complete end-to-end journey of one request |
| **Span** | A single unit of work — one service call, one DB query |
| **Trace ID** | A unique ID shared by all spans in a trace |
| **Span ID** | A unique ID for one specific span |
| **Parent span** | The span that triggered the current one |
| **Root span** | The first span — where the request entered the system |

**Example trace:**

```
Trace ID: 4bf92f3577b34da6
Total duration: 120ms

├── API Gateway          [root span]     0ms → 120ms
│   ├── Auth Service     [child span]    5ms → 13ms
│   └── Order Service    [child span]   15ms → 110ms
│       ├── Inventory    [child span]   20ms → 35ms
│       └── DB Query     [child span]   40ms → 108ms  ← bottleneck
```

The DB Query span took 68ms — that's your root cause.

**Context propagation:**

For a trace to work across services, each service must pass the Trace ID forward in HTTP headers:

```
HTTP Header: traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01
                               │                               │
                           trace-id                        span-id
```

Service B reads this header, creates a child span with the same trace ID, and passes it to Service C. This is how all spans end up linked under one trace.

**Tools:** OpenTelemetry, Jaeger, Zipkin, Grafana Tempo, X-Ray, Cloud Trace

---

## 4. How the Three Pillars Work Together

In practice, metrics, logs, and traces are most powerful when connected:

```
Step 1: Metric alert fires
───────────────────────────
Grafana dashboard shows P99 latency spiked to 3s at 14:32
→ Something is slow

Step 2: Correlate with logs
───────────────────────────
Query Loki for errors around 14:32 in the affected service
→ See "DB connection pool exhausted" errors

Step 3: Follow the trace
───────────────────────────
Find a trace from 14:32 — the DB Query span took 2.8s
→ Root cause: database was overloaded
```

This is called **correlating signals** — jumping between metrics, logs, and traces to tell the full story of an incident. Grafana makes this possible by linking all three in one interface.

---

## 5. SLIs, SLOs, and SLAs

These three terms define *how good* your service needs to be — and whether you're meeting that bar.

### SLI — Service Level Indicator

A specific metric that measures one aspect of your service's reliability. It's always a ratio or percentage.

```
SLI = (good events) / (total events)

Example:
  SLI = successful HTTP requests / total HTTP requests
      = 99,750 / 100,000
      = 99.75%
```

Common SLIs:
- **Availability** — % of requests that succeeded
- **Latency** — % of requests under a time threshold (e.g. under 200ms)
- **Error rate** — % of requests that returned an error
- **Throughput** — requests per second

### SLO — Service Level Objective

The target you set for an SLI. It's the internal reliability goal your team commits to.

```
SLO: 99.9% of requests succeed over a 30-day window
SLO: 95% of requests complete in under 200ms
SLO: Error rate stays below 0.1%
```

SLOs drive alert thresholds. If your SLO is 99.9% availability, you alert when you're trending toward breaking it — not after.

### SLA — Service Level Agreement

A legal or contractual commitment to a customer. It's usually less strict than your SLO (you need internal headroom).

```
SLA (customer promise): 99.5% uptime per month
SLO (internal target):  99.9% uptime per month
         │
         └── If you breach the SLO, you have buffer before breaching the SLA
```

### How they relate

```
SLA  ←  SLO  ←  SLI
 │         │        │
Legal    Internal  Actual
promise   goal   measurement
```

---

## 6. Error Budgets

An error budget is the amount of unreliability you're *allowed* to have before breaching your SLO.

```
SLO = 99.9% availability over 30 days

Total minutes in 30 days = 43,200
Allowed downtime         = 43,200 × 0.1% = 43.2 minutes

Error budget = 43.2 minutes of downtime per month
```

### Why error budgets matter

Error budgets create a shared language between developers and ops:

- **Budget is healthy** → ship features faster, take more risk
- **Budget is low** → slow down, focus on reliability, no risky deployments
- **Budget is exhausted** → freeze deployments until budget recovers

This removes the tension of "ops wants stability, devs want to ship" — the budget makes the tradeoff objective.

### Burn rate

How fast you're consuming your error budget:

```
Burn rate of 1 = consuming budget at exactly the SLO rate (sustainable)
Burn rate of 2 = consuming budget twice as fast (will breach SLO in half the window)
Burn rate of 10 = alert immediately — budget will be gone in 10% of the window
```

---

## 7. Kubernetes-Specific Observability

Kubernetes adds its own layer of things to observe — beyond just your application code.

### What to observe in a Kubernetes cluster

```
┌─────────────────────────────────────────────┐
│                  Cluster                     │
│  ┌──────────────────────────────────────┐   │
│  │               Node                   │   │
│  │  ┌─────────────────────────────┐    │   │
│  │  │            Pod              │    │   │
│  │  │  ┌──────────┐ ┌──────────┐ │    │   │
│  │  │  │Container │ │Container │ │    │   │
│  │  │  └──────────┘ └──────────┘ │    │   │
│  │  └─────────────────────────────┘    │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

Each layer has its own metrics to watch:

**Cluster level:**
- Node count and health
- API server latency and error rate
- etcd health (Kubernetes' brain)
- Scheduler and controller manager performance

**Node level:**
- CPU, memory, disk, network utilization
- Disk pressure, memory pressure conditions
- Number of pods per node

**Pod level:**
- CPU and memory requests vs limits vs actual usage
- Restart count (high restarts = crash looping)
- Pod phase (Pending, Running, Failed, Succeeded)
- Time in Pending state (scheduling issues)

**Container level:**
- CPU throttling (container hitting its CPU limit)
- OOMKill events (container killed for using too much memory)
- Image pull errors

### Key Kubernetes metrics to know

```promql
# Pod restart count (crash looping indicator)
kube_pod_container_status_restarts_total

# Pods not in Running state
kube_pod_status_phase{phase!="Running"}

# CPU throttling per container
rate(container_cpu_cfs_throttled_seconds_total[5m])

# Memory usage vs limit
container_memory_working_set_bytes / container_spec_memory_limit_bytes

# Pending pods (scheduling issues)
kube_pod_status_phase{phase="Pending"}

# Node memory available
node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes

# Deployment replicas available vs desired
kube_deployment_status_replicas_available / kube_deployment_spec_replicas
```

### Kubernetes events

Kubernetes generates events for everything — pod scheduling, image pulls, restarts, failures. Events are short-lived (1 hour by default) but critical for debugging:

```bash
# All events in a namespace, newest first
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Only warning events
kubectl get events -n <namespace> --field-selector type=Warning

# Events for a specific pod
kubectl describe pod <pod-name> -n <namespace>
```

Common events to watch for:

| Event | What it means |
|-------|--------------|
| `OOMKilled` | Container ran out of memory |
| `BackOff` | Container keeps crashing, Kubernetes is slowing retries |
| `Evicted` | Pod removed from node due to resource pressure |
| `FailedScheduling` | No node has enough resources for the pod |
| `ImagePullBackOff` | Can't pull the container image |
| `Unhealthy` | Liveness or readiness probe failing |

---

## 8. Instrumentation

Instrumentation is the code you add to your application to produce telemetry — metrics, logs, and traces.

### Types of instrumentation

**Manual instrumentation** — you write the code yourself:

```go
// Manually create a span in Go
ctx, span := tracer.Start(ctx, "processOrder")
defer span.End()

span.SetAttributes(attribute.String("order.id", orderID))
```

**Auto-instrumentation** — a library or agent patches your code automatically:

```bash
# Python — auto-instrument without changing your code
opentelemetry-instrument python app.py
```

Auto-instrumentation covers common frameworks (HTTP servers, database clients, message queues) out of the box. Manual instrumentation is needed for custom business logic.

### What to instrument

**Always instrument:**
- Incoming HTTP requests (rate, duration, status)
- Outgoing HTTP calls to other services
- Database queries (duration, errors)
- Background job execution (duration, success/failure)
- Cache operations (hit rate, latency)

**Instrument when relevant:**
- Queue depth and processing time
- Business events (orders placed, payments processed)
- Feature flag evaluations
- Authentication attempts

### The OpenTelemetry standard

OpenTelemetry (OTel) is the industry standard for instrumentation. It's vendor-neutral — you instrument once, send to any backend (Jaeger, Grafana Tempo, Datadog, etc.).

```
Your App (OTel SDK)
       │
       ▼
OTel Collector       ← receives, processes, exports
       │
  ┌────┴────┐
  ▼         ▼
Jaeger   Prometheus  ← any backend you choose
```

See [04-tracing-deep-dive.md](./04-tracing-deep-dive.md) for full OTel setup.

---

## 9. Cardinality

Cardinality is the number of unique combinations of label values in your metrics. It's one of the most important concepts to understand when working with Prometheus at scale.

### Why it matters

Every unique label combination creates a separate time series in Prometheus. Too many time series = high memory usage = slow queries = expensive storage.

```
# Low cardinality — 3 methods × 4 status codes = 12 time series
http_requests_total{method="GET", status="200"}
http_requests_total{method="GET", status="404"}
http_requests_total{method="POST", status="200"}
...

# HIGH cardinality — 1 per user = millions of time series ❌
http_requests_total{method="GET", user_id="12345"}
http_requests_total{method="GET", user_id="12346"}
...
```

### Safe vs unsafe labels

| Safe (low cardinality) | Unsafe (high cardinality) |
|-----------------------|--------------------------|
| HTTP method (GET, POST, etc.) | User ID |
| Status code (200, 404, 500) | Request ID |
| Service name | IP address |
| Namespace | Email address |
| Environment (prod, staging) | Full URL path with IDs |

### Rule of thumb

A label should have **fewer than ~100 unique values**. If it has thousands or millions, it doesn't belong in a metric label — it belongs in a log.

---

## 10. Sampling

Recording every single trace in a high-traffic system is expensive. Sampling means only keeping a fraction of traces.

### Head-based sampling

The decision to sample is made at the **start** of a request — before you know how it will turn out.

```
100 requests arrive
       │
  10% sample rate
       │
10 traces recorded (random selection)
```

**Pros:** Simple, low overhead  
**Cons:** You might drop exactly the traces you needed (errors, slow requests)

### Tail-based sampling

The decision is made **after** the trace completes — so you can keep the interesting ones.

```
100 requests complete
       │
Keep: all errors, all requests > 500ms, 5% of the rest
       │
~15 traces recorded (the ones that matter)
```

**Pros:** Always captures errors and slow requests  
**Cons:** Requires buffering traces before deciding — more memory overhead

### When to use which

| Scenario | Strategy |
|----------|---------|
| Development / low traffic | 100% — keep everything |
| Production, moderate traffic | Head sampling at 10-20% |
| Production, high traffic | Tail sampling — keep errors + slow traces |
| Critical user journeys | Always sample (100% for checkout, payments) |

---

## 11. Observability in the SDLC

Observability isn't just a production concern — it should be built in from the start.

### Shift-left observability

```
Design → Develop → Test → Deploy → Operate
  │          │        │       │        │
  │          │        │       │        └── Monitor & alert
  │          │        │       └─────────── Deploy dashboards with the service
  │          │        └─────────────────── Test instrumentation in CI
  │          └──────────────────────────── Add metrics/logs/traces while coding
  └─────────────────────────────────────── Define SLOs before writing code
```

### Observability checklist for a new service

Before shipping a new microservice to production:

- [ ] Exposes `/metrics` endpoint with RED metrics (rate, errors, duration)
- [ ] Structured logging with consistent fields (`service`, `level`, `traceID`)
- [ ] OTel instrumentation for incoming and outgoing requests
- [ ] SLO defined (e.g. 99.9% availability, P99 < 300ms)
- [ ] At least one alert rule covering error rate or availability
- [ ] A runbook linked from the alert
- [ ] A dashboard in Grafana showing RED metrics
- [ ] Health check endpoints (`/healthz`, `/readyz`)

### Health check endpoints

Kubernetes uses these to know whether to send traffic to a pod:

```
/healthz  (liveness probe)   — is the app alive? Should Kubernetes restart it?
/readyz   (readiness probe)  — is the app ready to receive traffic?
/metrics  (Prometheus scrape) — telemetry data
```

```yaml
# In your Deployment spec
livenessProbe:
  httpGet:
    path: /healthz
    port: 8080
  initialDelaySeconds: 10
  periodSeconds: 10

readinessProbe:
  httpGet:
    path: /readyz
    port: 8080
  initialDelaySeconds: 5
  periodSeconds: 5
```

---

## Key Terms Glossary

| Term | Definition |
|------|-----------|
| **Observability** | Ability to understand a system's internal state from its outputs |
| **Monitoring** | Watching for known failure conditions |
| **Telemetry** | Data emitted by a system (metrics, logs, traces) |
| **Instrumentation** | Code added to produce telemetry |
| **Metric** | A numeric measurement over time |
| **Counter** | A metric that only goes up (requests, errors) |
| **Gauge** | A metric that goes up and down (CPU %, memory) |
| **Histogram** | Samples observations into configurable buckets |
| **Log** | A timestamped record of an event |
| **Structured log** | A log in machine-readable format (JSON) |
| **Trace** | Full journey of a request across services |
| **Span** | One unit of work within a trace |
| **Trace ID** | Unique ID linking all spans in a trace |
| **Context propagation** | Passing trace context between services via headers |
| **SLI** | A metric measuring one aspect of reliability |
| **SLO** | The internal reliability target for an SLI |
| **SLA** | A contractual reliability commitment to customers |
| **Error budget** | Allowed unreliability before breaching an SLO |
| **Burn rate** | How fast you're consuming your error budget |
| **Cardinality** | Number of unique label combinations in metrics |
| **Head sampling** | Decide to sample at the start of a request |
| **Tail sampling** | Decide to sample after a request completes |
| **Scrape** | Prometheus pulling metrics from a target |
| **Exporter** | A component that exposes metrics for Prometheus to scrape |
| **Alert rule** | A condition that triggers a notification when true |
| **Alertmanager** | Routes alerts to the right team via the right channel |
| **Runbook** | A document describing what to do when an alert fires |
| **OOMKill** | A container killed by Kubernetes for exceeding memory limits |
| **CrashLoopBackOff** | A container repeatedly crashing and restarting |
| **OpenTelemetry** | Vendor-neutral standard for instrumentation |

---
