# 🎯 Interview Questions & Answers

Real questions asked in DevOps and cloud engineering interviews — with full answers, not just hints.

> Read through these after finishing the other files. Everything here connects back to concepts already covered.

---

## 📚 Table of Contents

- [🔥 Core Understanding](#-core-understanding)
- [🔍 Prometheus Deep Dive](#-prometheus-deep-dive)
- [🔗 ServiceMonitor & Scraping](#-servicemonitor--scraping)
- [📦 Exporters](#-exporters)
- [🚨 Alerting](#-alerting)
- [📊 Grafana](#-grafana)
- [☸️ Kubernetes-Specific](#️-kubernetes-specific)
- [🔥 Scenario-Based Questions](#-scenario-based-questions)
- [🧠 Advanced Questions](#-advanced-questions)
- [💬 Questions to Ask the Interviewer](#-questions-to-ask-the-interviewer)

---

## 🔥 Core Understanding

---

**Q: How does Prometheus discover targets in Kubernetes?**

Prometheus uses **service discovery** — it queries the Kubernetes API to find what to scrape, rather than having a static list of IPs.

When using the Prometheus Operator, you define `ServiceMonitor` or `PodMonitor` resources. The Operator watches for these and automatically updates Prometheus's scrape config. Prometheus then queries the Kubernetes API to find all Services/Pods matching the selector, and scrapes each one.

Without the Operator, you'd configure `kubernetes_sd_configs` directly in `prometheus.yml`:

```yaml
scrape_configs:
  - job_name: 'kubernetes-pods'
    kubernetes_sd_configs:
      - role: pod
    relabel_configs:
      - source_labels: [__meta_kubernetes_pod_annotation_prometheus_io_scrape]
        action: keep
        regex: true
```

---

**Q: Difference between ServiceMonitor vs PodMonitor?**

| | ServiceMonitor | PodMonitor |
|--|---------------|-----------|
| **Targets** | Kubernetes Services | Pods directly |
| **Use when** | App has a Service (most cases) | App has no Service (DaemonSets, batch jobs) |
| **Discovery** | Finds pods via Service endpoints | Finds pods via label selector |
| **Label matching** | Matches Service labels | Matches Pod labels |

In practice, use ServiceMonitor for 90% of cases. Use PodMonitor when you're scraping something like a DaemonSet that doesn't sit behind a Service.

---

**Q: Why do we need kube-state-metrics if we already have Node Exporter?**

They answer completely different questions:

- **Node Exporter** watches the **Linux OS** — CPU cycles, memory bytes, disk I/O, network packets. It knows nothing about Kubernetes.
- **kube-state-metrics** watches the **Kubernetes API** — pod phases, deployment replica counts, node conditions, resource quotas. It knows nothing about the OS.

Example: Node Exporter can tell you a node has 85% CPU usage. kube-state-metrics can tell you a Deployment only has 1 of 3 replicas available. You need both to get the full picture.

---

**Q: What happens if the Prometheus pod restarts? Do we lose data?**

It depends on your setup:

- **Without a PersistentVolumeClaim (PVC):** Yes — all data in memory and on the ephemeral disk is lost on restart. Prometheus starts fresh.
- **With a PVC:** No — Prometheus stores its TSDB (time series database) on the mounted volume. On restart it picks up exactly where it left off.

In production, always configure Prometheus with a PVC:

```yaml
# In kube-prometheus-stack values.yaml
prometheus:
  prometheusSpec:
    storageSpec:
      volumeClaimTemplate:
        spec:
          storageClassName: standard
          accessModes: ["ReadWriteOnce"]
          resources:
            requests:
              storage: 50Gi
```

For long-term storage beyond what fits on a single PVC, use Thanos or Grafana Mimir to offload blocks to object storage (S3, GCS, etc.).

---

**Q: How does Prometheus store data? (TSDB, retention, PVC)**

Prometheus uses its own embedded database called **TSDB (Time Series Database)**:

```
/prometheus/
├── chunks_head/       ← recent data in memory (last 2 hours)
├── 01ABCD.../         ← immutable blocks (2h chunks compacted to larger blocks)
│   ├── chunks/
│   ├── index
│   └── meta.json
└── wal/               ← Write-Ahead Log (protects against data loss on crash)
```

- Data starts in **memory** and the **WAL** (write-ahead log for crash recovery)
- Every 2 hours, it's flushed to an **immutable block** on disk
- Blocks are periodically **compacted** (merged into larger blocks) for efficiency
- Default **retention** is 15 days — configurable via `--storage.tsdb.retention.time`

```yaml
prometheus:
  prometheusSpec:
    retention: 30d          # keep 30 days
    retentionSize: 50GB     # OR cap by size — whichever comes first
```

---

**Q: What is scrape interval vs evaluation interval?**

| | Scrape Interval | Evaluation Interval |
|--|----------------|---------------------|
| **What** | How often Prometheus pulls metrics from targets | How often Prometheus evaluates alert and recording rules |
| **Default** | 1 minute | 1 minute |
| **Controls** | Data resolution — smaller = more granular | Alert responsiveness — smaller = faster detection |
| **Typical prod** | 15s–30s | 15s–1m |

```yaml
global:
  scrape_interval: 15s       # scrape every 15 seconds
  evaluation_interval: 15s   # evaluate rules every 15 seconds
```

Important: your `rate()` window in PromQL should always be **at least 2x the scrape interval**. If scraping every 15s, use `rate(...[1m])` minimum, not `rate(...[15s])`.

---

## 🔍 Prometheus Deep Dive

---

**Q: How does the Prometheus pull model work vs push model?**

**Pull (Prometheus default):**
Prometheus reaches out to each target on a schedule and scrapes the `/metrics` endpoint.

```
Prometheus ──── HTTP GET /metrics ────► Target (your app)
```

✅ Prometheus controls timing, easy to detect when a target goes down (it simply disappears from targets)  
❌ Targets must be network-reachable, doesn't work for short-lived jobs

**Push:**
The app sends (pushes) metrics to a collector.

```
App ──── HTTP POST ────► Pushgateway / OTel Collector ────► Prometheus
```

✅ Works for batch jobs, cron jobs, serverless functions  
❌ Harder to detect if an app silently stops pushing

**When to use each:**
- Long-running services → Pull (ServiceMonitor)
- Short-lived batch jobs → Push (Pushgateway)
- Traces → Always push (OTel Collector)

---

**Q: What is PromQL? Give an example query.**

PromQL (Prometheus Query Language) is the query language used to retrieve and process time series data from Prometheus.

```promql
# Instant vector — current value of a metric
http_requests_total

# Range vector — values over a time window
http_requests_total[5m]

# Rate — per-second rate of increase over 5 minutes
rate(http_requests_total[5m])

# Filter by label
rate(http_requests_total{status="500"}[5m])

# Aggregate across all pods, keep service label
sum(rate(http_requests_total[5m])) by (service)

# Error rate as a percentage
sum(rate(http_requests_total{status=~"5.."}[5m])) by (service)
/ sum(rate(http_requests_total[5m])) by (service) * 100

# P99 latency
histogram_quantile(0.99,
  sum(rate(http_request_duration_seconds_bucket[5m])) by (le, service)
)
```

---

**Q: Difference between `rate()` vs `irate()`?**

| | `rate()` | `irate()` |
|--|---------|----------|
| **Calculates** | Average per-second rate over the whole window | Instantaneous rate using only the last two data points |
| **Smoothing** | Smooth — averages out spikes | Sensitive — shows every spike |
| **Use for** | Dashboards, alerts (stable signal) | Debugging sudden spikes |
| **Example** | `rate(requests[5m])` | `irate(requests[5m])` |

```promql
# rate() — stable average, good for alerts
rate(http_requests_total[5m])

# irate() — shows spikes, good for debugging
irate(http_requests_total[5m])
```

Rule of thumb: use `rate()` in production alerts and dashboards. Use `irate()` only when investigating a specific incident.

---

**Q: Difference between `sum()` vs `avg()`?**

```promql
# sum() — adds all values together
sum(rate(http_requests_total[5m]))
# Use when: you want the total across all instances
# Example: total requests per second across 10 pods = 1000 req/s

# avg() — arithmetic mean
avg(rate(http_requests_total[5m]))
# Use when: you want the typical value per instance
# Example: average requests per second per pod = 100 req/s
```

Common mistake: using `avg()` for CPU when you want total load. If 10 pods are each using 80% CPU, `avg()` gives 80% — which looks fine. `sum()` gives 800% — which shows the true load.

---

**Q: How would you reduce cardinality issues?**

Cardinality = number of unique time series. Each unique label combination is a separate series.

**Identify the problem:**
```promql
# Find metrics with the most time series
topk(10, count by (__name__)({__name__=~".+"}))
```

**Fix strategies:**

1. **Remove high-cardinality labels** — never use user IDs, request IDs, email addresses as labels
2. **Use `relabel_configs` to drop labels before they reach Prometheus:**

```yaml
relabel_configs:
  - source_labels: [__meta_kubernetes_pod_label_user_id]
    action: labeldrop
```

3. **Move high-cardinality data to logs** — if you need per-user data, log it instead
4. **Use recording rules** to pre-aggregate and reduce series count
5. **Set cardinality limits** in Prometheus:

```yaml
--storage.tsdb.max-block-chunk-segment-size  # limit per-series size
```

---

## 🔗 ServiceMonitor & Scraping

---

**Q: How does Prometheus know which ServiceMonitor to pick up?**

The Prometheus CR (custom resource) has a `serviceMonitorSelector` that filters which ServiceMonitors it watches. With `kube-prometheus-stack`, the default selector requires the label `release: prometheus`.

```yaml
# Prometheus CR looks for ServiceMonitors with this label
serviceMonitorSelector:
  matchLabels:
    release: prometheus       # ← your ServiceMonitor MUST have this label
```

```bash
# Check what your Prometheus is looking for
kubectl get prometheus -n monitoring -o yaml | grep -A5 serviceMonitorSelector
```

If your ServiceMonitor is missing this label, Prometheus simply ignores it — no error, no warning, just silence.

---

**Q: What happens if the Service label doesn't match the ServiceMonitor selector?**

Prometheus never discovers the target. The ServiceMonitor's `selector.matchLabels` must exactly match labels on the Kubernetes Service.

```yaml
# ServiceMonitor expects this label on the Service
selector:
  matchLabels:
    app: my-app     # ← Service must have this label

# Service is missing the label
metadata:
  labels:
    app: my-application   # ← doesn't match — ServiceMonitor finds nothing
```

**Debug steps:**
```bash
# Check ServiceMonitor selector
kubectl get servicemonitor my-app -o yaml | grep -A5 selector

# Check Service labels
kubectl get svc my-app --show-labels

# See if target appears in Prometheus
# localhost:9090/targets → look for your service
```

---

**Q: What happens if the port name is wrong in the ServiceMonitor?**

The target will appear in Prometheus as `DOWN` with an error like `connection refused` or `no such port`.

ServiceMonitor uses **port names**, not port numbers:

```yaml
# ServiceMonitor references port by name
endpoints:
  - port: metrics       # ← must match the name in the Service

# Service must have this port name
ports:
  - name: metrics       # ← this must match
    port: 8080
```

If the port name doesn't match, Prometheus can't resolve it to a port number and the scrape fails.

---

## 📦 Exporters

---

**Q: Difference between Node Exporter, MySQL Exporter, and Blackbox Exporter?**

| Exporter | What it monitors | How it works |
|----------|-----------------|-------------|
| **Node Exporter** | Linux OS metrics (CPU, memory, disk, network) | Reads `/proc` and `/sys` on the host |
| **MySQL Exporter** | MySQL database metrics (queries, connections, replication lag) | Connects to MySQL and runs queries |
| **Blackbox Exporter** | External endpoint health (HTTP, TCP, DNS, ICMP) | Makes a real request and reports success/failure/latency |

**Node Exporter** — runs on every node, exposes OS internals. No config needed for standard Linux metrics.

**MySQL Exporter** — runs as a sidecar or separate pod, connects to your MySQL instance:
```yaml
# Needs DB credentials
env:
  - name: DATA_SOURCE_NAME
    value: "exporter:password@tcp(mysql:3306)/"
```

**Blackbox Exporter** — probes endpoints from the outside:
```yaml
# Checks if https://my-api.com/health returns 200
modules:
  http_2xx:
    prober: http
    http:
      valid_status_codes: [200]
      method: GET
```

---

**Q: When would you use Blackbox Exporter instead of a ServiceMonitor?**

Use **Blackbox Exporter** when you want to test your service **from the outside** — as a user would experience it.

| Scenario | Use |
|----------|-----|
| Check if `/health` returns 200 | Blackbox Exporter |
| Monitor an external third-party API | Blackbox Exporter |
| Check DNS resolution | Blackbox Exporter |
| Check TLS certificate expiry | Blackbox Exporter |
| Collect app-specific metrics (request rate, error count) | ServiceMonitor |
| Monitor internal microservice performance | ServiceMonitor |

Think of it this way: ServiceMonitor tells you what's happening *inside* your app. Blackbox Exporter tells you if your app is *reachable and responding* from the outside.

```yaml
# Blackbox probe via ServiceMonitor
scrape_configs:
  - job_name: 'blackbox'
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://my-api.com/health
    relabel_configs:
      - target_label: __address__
        replacement: blackbox-exporter:9115
```

---

## 🚨 Alerting

---

**Q: How does the alert flow work end to end?**

```
1. Prometheus evaluates rules every [evaluation_interval]
           │
           │ Rule condition becomes true
           ▼
2. Alert enters PENDING state
   (waits for `for:` duration to avoid flapping)
           │
           │ Condition still true after `for:` duration
           ▼
3. Alert enters FIRING state
   Prometheus sends it to Alertmanager
           │
           ▼
4. Alertmanager receives the alert
   - Deduplicates (both Prometheus replicas fire the same alert)
   - Groups related alerts together
   - Applies inhibition rules
   - Waits group_wait (30s) for more alerts in the same group
           │
           ▼
5. Alertmanager routes based on labels
   severity=critical → PagerDuty
   severity=warning  → Slack
           │
           ▼
6. Notification sent
   - Repeats every repeat_interval if still firing
   - Sends "resolved" notification when condition clears
```

---

**Q: Difference between `for: 5m` and an instant alert?**

```yaml
# Instant alert — fires immediately when condition is true
- alert: PodDown
  expr: up == 0
  # no `for:` field

# Alert with duration — must be true for 5 minutes before firing
- alert: HighErrorRate
  expr: error_rate > 0.05
  for: 5m
```

- **Instant alert** — fires the moment the condition is true. Use for critical, unambiguous failures (pod is completely down).
- **`for: 5m`** — condition must stay true for 5 minutes before the alert fires. Use for conditions that might be transient (brief CPU spike, brief latency increase).

Without `for:`, you get noisy alerts from momentary spikes. With `for:`, you avoid false positives but accept slower detection.

---

**Q: What are inhibition rules?**

Inhibition rules silence lower-priority alerts when a higher-priority one is already firing.

**Example:** If a node goes down, you'll get dozens of alerts — one for each pod that was running on that node. Inhibition suppresses those pod-level alerts when the node-level alert is already firing.

```yaml
inhibit_rules:
  - source_match:
      alertname: NodeDown        # if THIS alert is firing...
      severity: critical
    target_match:
      severity: warning          # ...suppress THESE alerts
    equal: ['node']              # only when they share the same node label
```

Without inhibition: 1 node down → 20 alerts  
With inhibition: 1 node down → 1 alert (the NodeDown one)

---

**Q: How do you avoid alert fatigue?**

Alert fatigue happens when so many alerts fire that engineers start ignoring them.

**Strategies:**

1. **Alert on symptoms, not causes** — alert on high error rate, not on the specific pod that caused it
2. **Use `for:` duration** — require the condition to persist before firing, not just momentarily
3. **Set meaningful thresholds** — if CPU > 80% fires every day, raise the threshold or fix the underlying issue
4. **Severity routing** — critical alerts page someone at 3am, warnings go to Slack for next-day review
5. **Inhibition rules** — suppress redundant child alerts when a parent is firing
6. **Regular alert review** — monthly review: which alerts fired most? Which were acted on? Tune or remove the rest
7. **Start small** — begin with 3-5 high-quality alerts, add more only when you feel the gap

---

## 📊 Grafana

---

**Q: How does Grafana get data?**

Grafana itself stores **no metrics** — it's purely a visualization layer. It queries data sources on demand when you open a dashboard or run a query.

```
You open a Grafana dashboard
           │
           ▼
Grafana sends PromQL query to Prometheus
(or LogQL to Loki, or trace query to Jaeger)
           │
           ▼
Data source returns results
           │
           ▼
Grafana renders the panel
```

This means Grafana going down doesn't affect metric collection — Prometheus keeps scraping regardless.

---

**Q: Difference between Metrics (Prometheus) and Logs (Loki) in Grafana?**

| | Prometheus (Metrics) | Loki (Logs) |
|--|---------------------|------------|
| **Data type** | Numbers over time | Text strings with timestamp |
| **Query language** | PromQL | LogQL |
| **Good for** | Dashboards, alerting, trends | Debugging, root cause, error details |
| **Storage** | TSDB (compressed numeric) | Object storage (raw text) |
| **Example query** | `rate(http_requests_total[5m])` | `{namespace="prod"} \|= "ERROR"` |
| **Cardinality concern** | Yes — label explosion | No — labels are just metadata |

In practice: metrics tell you *something is wrong*, logs tell you *what exactly happened*.

---

**Q: How would you debug "Dashboard is empty"?**

Work through this checklist in order:

```
1. Is Prometheus running and healthy?
   → kubectl get pods -n monitoring | grep prometheus
   → localhost:9090 — can you open the UI?

2. Is the data source configured correctly in Grafana?
   → Connections → Data Sources → Test the Prometheus source
   → Green checkmark = connected, Red = URL wrong or Prometheus down

3. Is Prometheus actually scraping your target?
   → localhost:9090/targets — find your service
   → Status should be UP, not DOWN or Unknown

4. Does the metric exist in Prometheus?
   → localhost:9090 — query the metric name directly
   → If no results, the app isn't exposing it or Prometheus isn't scraping it

5. Is the Grafana query correct?
   → Edit the panel → run the query manually
   → Check for typos in metric name or label filters

6. Is the time range correct?
   → Grafana might be showing "Last 5 minutes" but metric started 1 hour ago
   → Widen the time range

7. Is the label selector in the query matching your actual labels?
   → Query might filter by {env="prod"} but your labels say {environment="production"}
```

---

## ☸️ Kubernetes-Specific

---

**Q: Why deploy monitoring in a separate namespace?**

1. **Isolation** — monitoring components don't interfere with application workloads
2. **RBAC** — easier to grant/restrict access to monitoring tools separately from apps
3. **Resource management** — apply separate ResourceQuotas and LimitRanges to monitoring
4. **Network policies** — control which namespaces can reach Prometheus/Grafana
5. **Clarity** — `kubectl get pods -n monitoring` shows only monitoring, not a mix of everything

```bash
# Standard practice
kubectl create namespace monitoring
helm install prometheus ... --namespace monitoring
```

---

**Q: How does Prometheus scrape across namespaces?**

By default, a ServiceMonitor only finds Services in its own namespace. To scrape across namespaces, use `namespaceSelector`:

```yaml
spec:
  namespaceSelector:
    any: true              # scrape from ALL namespaces

  # OR target specific namespaces:
  namespaceSelector:
    matchNames:
      - production
      - staging
```

Prometheus also needs a ClusterRole that allows it to read Services and Pods across all namespaces — `kube-prometheus-stack` sets this up automatically.

---

**Q: What is the difference between DaemonSet and Deployment for monitoring components?**

| | DaemonSet | Deployment |
|--|-----------|-----------|
| **Runs** | One pod on every node | Specified number of replicas |
| **Used for** | Node-level agents | Cluster-level services |
| **Monitoring examples** | Node Exporter, Promtail | Prometheus, Grafana, kube-state-metrics |
| **Why** | Every node needs its own agent to collect OS metrics and ship logs | One (or two for HA) central instances are enough |

**Node Exporter as DaemonSet** — must run on every node because it reads that node's `/proc` and `/sys`. A central pod can't read another node's filesystem.

**Promtail as DaemonSet** — must run on every node because container logs are stored on the node's disk at `/var/log/pods/`.

**Prometheus as Deployment** — one central instance scrapes all targets and stores all data. (Two replicas for HA.)

---

## 🔥 Scenario-Based Questions

---

**Scenario 1: App is down but no alert triggered. What do you check?**

```
Step 1 — Does the alert rule exist?
kubectl get prometheusrule -A | grep my-app
→ If missing, nobody wrote the alert rule

Step 2 — Is Prometheus scraping the app?
localhost:9090/targets → find your service
→ If DOWN: check ServiceMonitor labels and port names
→ If missing entirely: ServiceMonitor is missing the `release: prometheus` label

Step 3 — Is the ServiceMonitor correct?
kubectl get servicemonitor my-app -o yaml
→ Does selector match the Service labels?
→ Does endpoint port name match the Service port name?

Step 4 — Is the alert rule correct?
localhost:9090/rules → find the alert
→ Run the PromQL expression manually — does it return data?
→ Is the threshold realistic? Is the metric name correct?

Step 5 — Is Alertmanager routing correctly?
localhost:9093 → check active alerts
→ Alert firing in Prometheus but not in Alertmanager = routing issue
→ Alert in Alertmanager but no notification = receiver config wrong (Slack webhook?)
```

Root causes in order of likelihood: missing ServiceMonitor label → wrong port name → wrong metric name in rule → misconfigured Alertmanager receiver.

---

**Scenario 2: High CPU alert firing constantly. What could be wrong?**

**Option A — The threshold is wrong:**
The app genuinely runs at 75% CPU normally, but the alert fires at 70%.
→ Fix: Raise the threshold or investigate why baseline CPU is high.

**Option B — The query is wrong:**
```promql
# Measures CPU in a way that's always high
container_cpu_usage_seconds_total > 0.7
# Wrong — this is a counter (cumulative), not a percentage
```
→ Fix: Use `rate()` to get actual CPU percentage.

**Option C — Missing resource limits:**
Pod has no CPU limit set, so it's consuming all available CPU on the node.
→ Fix: Set `resources.limits.cpu` in the Deployment.

**Option D — Legitimate traffic spike:**
A deployment or traffic increase genuinely pushed CPU up.
→ Fix: Scale the deployment, optimize the app, or add HPA.

**Option E — No `for:` duration:**
Brief CPU spikes (GC, startup) trigger the alert even though they're transient.
→ Fix: Add `for: 5m` to require sustained high CPU before alerting.

---

**Scenario 3: No data in Grafana. What are the possible causes?**

```
Grafana → Prometheus → Scraping → App
  │            │           │         │
  │            │           │         └── App not exposing /metrics
  │            │           └──────────── ServiceMonitor missing/wrong
  │            └──────────────────────── Prometheus not running / PVC full
  └───────────────────────────────────── Wrong data source URL / time range
```

Debug in this order:
1. Test data source in Grafana (Connections → Data Sources → Test)
2. Open Prometheus UI directly — query the metric manually
3. Check Prometheus targets page — is your service being scraped?
4. Check the app itself — does `curl <pod-ip>:8080/metrics` return data?
5. Check the Grafana panel query — metric name typo? Wrong label filter? Wrong time range?

---

**Scenario 4: MySQL metrics are missing. Debug steps.**

```bash
# 1. Is the MySQL Exporter pod running?
kubectl get pods -n <namespace> | grep mysql-exporter
# If CrashLoopBackOff → check credentials in the Secret

# 2. Can the exporter connect to MySQL?
kubectl logs <mysql-exporter-pod>
# Look for "error connecting to database"

# 3. Does the exporter expose metrics?
kubectl port-forward <mysql-exporter-pod> 9104:9104
curl localhost:9104/metrics | grep mysql_up
# mysql_up 1 = connected, mysql_up 0 = can't connect to MySQL

# 4. Does the Service exist and have the right labels?
kubectl get svc mysql-exporter --show-labels

# 5. Does the ServiceMonitor exist and select the right Service?
kubectl get servicemonitor mysql-exporter -o yaml

# 6. Is the target visible in Prometheus?
# localhost:9090/targets → look for mysql-exporter
# If DOWN: port name mismatch or network policy blocking scrape

# 7. Is the ServiceMonitor in a namespace Prometheus watches?
kubectl get servicemonitor -A
# Check namespaceSelector on the Prometheus CR
```

---

**Scenario 5: Pod is in CrashLoopBackOff. How do you investigate?**

```bash
# 1. See how many times it's restarted and when
kubectl get pod <pod-name> -n <namespace>

# 2. Check the current logs
kubectl logs <pod-name> -n <namespace>

# 3. Check logs from the PREVIOUS crash (most important)
kubectl logs <pod-name> -n <namespace> --previous

# 4. Check Kubernetes events for the pod
kubectl describe pod <pod-name> -n <namespace>
# Look for: OOMKilled, Error, Liveness probe failed

# 5. Check if it's an OOMKill
kubectl describe pod <pod-name> | grep -i oom
# If OOMKilled → increase memory limit or fix memory leak

# 6. Check if liveness probe is too aggressive
kubectl get deployment <name> -o yaml | grep -A10 livenessProbe
# If initialDelaySeconds is too low, pod gets killed before it finishes starting

# 7. Check resource limits
kubectl top pod <pod-name> -n <namespace>
```

---

## 🧠 Advanced Questions

---

**Q: How would you scale Prometheus?**

Single Prometheus has limits — high cardinality, large clusters, long retention all strain it. Solutions:

**Thanos** — most common:
- Runs a sidecar next to Prometheus that uploads blocks to object storage (S3/GCS)
- `Thanos Query` provides a unified query layer across multiple Prometheus instances
- Enables unlimited retention and multi-cluster querying

**Grafana Mimir** — horizontally scalable:
- Drop-in Prometheus-compatible backend
- Separate ingester, querier, compactor components that scale independently
- Better for very high-scale (millions of series)

**Cortex** — predecessor to Mimir, still used in some environments

```
# Decision guide
Single cluster, < 1M series   → Standard Prometheus + PVC
Multi-cluster or long retention → Prometheus + Thanos
Very high scale (> 1M series) → Grafana Mimir
```

---

**Q: Where does OpenTelemetry fit in your observability setup?**

OpenTelemetry is the **instrumentation layer** — it standardizes how you generate telemetry data, regardless of which backend you use.

```
Your App (OTel SDK)
       │ generates spans, metrics, logs
       ▼
OTel Collector
       │ receives, processes, batches, exports
       ├──► Jaeger (traces)
       ├──► Prometheus (metrics via OTLP receiver)
       └──► Loki (logs)
```

**Why it matters:** Without OTel, you'd instrument your app separately for Jaeger, Prometheus, and Loki — three different libraries, three configs. With OTel, you instrument once and route to any backend by changing Collector config.

The OTel Collector also handles:
- **Tail sampling** — keep error/slow traces, drop healthy ones
- **Data transformation** — add/remove attributes, filter sensitive data
- **Batching** — reduce network overhead before exporting

---

**Q: How would you monitor an external API?**

Use **Blackbox Exporter** to probe the endpoint from inside your cluster:

```yaml
# blackbox-config.yaml
modules:
  http_2xx:
    prober: http
    timeout: 10s
    http:
      valid_status_codes: [200, 201]
      method: GET
      tls_config:
        insecure_skip_verify: false
```

```yaml
# ServiceMonitor to scrape Blackbox Exporter probes
scrape_configs:
  - job_name: external-api-check
    metrics_path: /probe
    params:
      module: [http_2xx]
    static_configs:
      - targets:
          - https://api.stripe.com/v1/charges  # external target
          - https://api.github.com/status
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - target_label: __address__
        replacement: blackbox-exporter:9115
```

Key metrics from Blackbox Exporter:
```promql
# Is the endpoint up?
probe_success{job="external-api-check"}

# How long did it take to respond?
probe_duration_seconds{job="external-api-check"}

# TLS certificate expiry (days until expiry)
(probe_ssl_earliest_cert_expiry - time()) / 86400
```

Alert when a certificate is expiring soon:
```yaml
- alert: SSLCertExpiringSoon
  expr: (probe_ssl_earliest_cert_expiry - time()) / 86400 < 30
  for: 1h
  annotations:
    summary: "SSL cert for {{ $labels.instance }} expires in less than 30 days"
```

---

**Q: Difference between Metrics, Logs, and Traces — when do you use each?**

| | Metrics | Logs | Traces |
|--|---------|------|--------|
| **Data** | Numbers over time | Text events | Request journeys |
| **Volume** | Low | High | Medium |
| **Query speed** | Very fast | Slower | Medium |
| **Best for** | Dashboards, alerting | Debugging specific events | Latency and dependency analysis |
| **Question answered** | Is something wrong? How bad? | What exactly happened? | Where did this request slow down? |

**Use metrics when:** You need to know trends, set alert thresholds, or display dashboards.  
**Use logs when:** You need to understand the exact details of a specific failure.  
**Use traces when:** You need to understand how a request flowed through microservices and where time was spent.

In a real investigation: metrics alert you → logs give you context → traces show you the exact path.

---

## 💬 Questions to Ask the Interviewer

Asking good questions signals genuine interest and seniority. Try these:

**On their current setup:**
- "What observability stack are you currently running — self-managed Prometheus or a managed service?"
- "How many clusters are you monitoring, and do you use something like Thanos for multi-cluster querying?"
- "How do you handle log aggregation — Loki, Elasticsearch, or a cloud-native solution?"

**On their challenges:**
- "What's been the biggest observability pain point you've faced recently?"
- "How mature is your alerting setup — are you still dealing with alert fatigue?"

**On their practices:**
- "Do you treat observability config as code — dashboards and alert rules in Git?"
- "How do you onboard new services — is there a standard template for ServiceMonitors and alert rules?"

**On the role:**
- "Would I be working mostly on the observability platform itself, or helping teams instrument their applications?"
- "Are there plans to adopt OpenTelemetry across the stack?"

---

*Good luck 🚀*
