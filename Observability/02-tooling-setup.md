# 🛠️ Tooling Setup

Install and configure the core observability stack on Kubernetes.

> **Prerequisites:** A running Kubernetes cluster (minikube, kind, or a cloud cluster), `kubectl` configured, and `helm` installed.

---

## 📚 Table of Contents

- [The Stack at a Glance](#the-stack-at-a-glance)
- [1. Prometheus — Metrics Collection](#1-prometheus--metrics-collection)
- [2. Grafana — Dashboards & Visualization](#2-grafana--dashboards--visualization)
- [3. Loki — Log Aggregation](#3-loki--log-aggregation)
- [4. Connecting Everything](#4-connecting-everything)
- [Verify Your Setup](#verify-your-setup)

---

## The Stack at a Glance

```
Your Apps & Kubernetes
        │
        ▼
  ┌─────────────┐     ┌─────────────┐
  │  Prometheus │     │    Loki     │
  │  (metrics)  │     │   (logs)    │
  └──────┬──────┘     └──────┬──────┘
         │                   │
         └────────┬──────────┘
                  ▼
            ┌──────────┐
            │  Grafana │
            │   (UI)   │
            └──────────┘
```

Prometheus and Loki collect the data. Grafana is where you actually *see* it.

---

## 1. Prometheus — Metrics Collection

Prometheus scrapes metrics from your apps and Kubernetes itself on a schedule (e.g. every 15s). It stores them as time-series data you can query.

### Install via Helm

```bash
# Add the Helm repo
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

# Install into its own namespace
helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace
```

> 💡 `kube-prometheus-stack` is a bundle — it installs Prometheus **and** Grafana together, plus pre-built Kubernetes dashboards. It's the recommended starting point.

### Verify it's running

```bash
kubectl get pods -n monitoring
```

You should see pods for `prometheus-server`, `alertmanager`, and `grafana`.

### Access the Prometheus UI

```bash
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring
```

Open [http://localhost:9090](http://localhost:9090) — try querying `up` to see all scraped targets.

### Key concepts

| Term | What it means |
|------|--------------|
| **Scrape** | Prometheus pulling metrics from a target endpoint |
| **Target** | An app or service exposing metrics (usually at `/metrics`) |
| **PromQL** | Prometheus's query language for filtering and aggregating metrics |
| **ServiceMonitor** | A Kubernetes resource that tells Prometheus what to scrape |

---

## 2. Grafana — Dashboards & Visualization

Grafana connects to Prometheus (and Loki) as data sources and lets you build dashboards to visualize everything.

> If you used `kube-prometheus-stack` above, Grafana is already installed. Skip to **Access Grafana**.

### Install standalone (if needed)

```bash
helm repo add grafana https://grafana.github.io/helm-charts
helm repo update

helm install grafana grafana/grafana \
  --namespace monitoring \
  --create-namespace
```

### Access Grafana

```bash
kubectl port-forward svc/grafana 3000:80 -n monitoring
```

Open [http://localhost:3000](http://localhost:3000)

**Default credentials:**
- Username: `admin`
- Password: retrieve with:

```bash
kubectl get secret --namespace monitoring grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode
```

### Add Prometheus as a data source

1. Go to **Connections → Data Sources → Add data source**
2. Select **Prometheus**
3. Set URL to: `http://prometheus-kube-prometheus-prometheus:9090`
4. Click **Save & Test** — you should see a green checkmark ✅

### Import a pre-built dashboard

Instead of building from scratch, import a community dashboard:

1. Go to **Dashboards → Import**
2. Enter dashboard ID `315` (Kubernetes cluster monitoring)
3. Select your Prometheus data source
4. Click **Import**

---

## 3. Loki — Log Aggregation

Loki stores logs from all your pods. It works like Prometheus but for logs — instead of metrics, it indexes log labels (namespace, pod name, etc.) and stores the raw log lines.

Logs are shipped to Loki by **Promtail** (an agent that runs on every node).

### Install via Helm

```bash
helm install loki grafana/loki-stack \
  --namespace monitoring \
  --set promtail.enabled=true \
  --set grafana.enabled=false  # already installed above
```

> `loki-stack` installs both Loki and Promtail together.

### Verify it's running

```bash
kubectl get pods -n monitoring | grep loki
```

You should see `loki-0` and `loki-promtail-*` pods (one per node).

### How Promtail works

```
Pod writes logs → stdout/stderr
        │
        ▼
  Promtail (on the node)
  reads log files from /var/log/pods/
        │
        ▼
     Loki stores them
```

Promtail automatically adds labels like `namespace`, `pod`, `container` to every log line — so you can filter without any app-side changes.

---

## 4. Connecting Everything

### Add Loki as a data source in Grafana

1. Go to **Connections → Data Sources → Add data source**
2. Select **Loki**
3. Set URL to: `http://loki:3100`
4. Click **Save & Test** ✅

### Query logs in Grafana

Go to **Explore**, select the **Loki** data source, and try:

```logql
{namespace="default"}
```

This shows all logs from the `default` namespace. You can filter further:

```logql
{namespace="default", pod=~"my-app-.*"} |= "error"
```

This returns only lines containing "error" from pods matching `my-app-*`.

---

## Verify Your Setup

Run through this checklist to confirm everything is working:

- [ ] `kubectl get pods -n monitoring` — all pods are `Running`
- [ ] Prometheus UI at `localhost:9090` — query `up` returns results
- [ ] Grafana at `localhost:3000` — can log in
- [ ] Prometheus data source in Grafana — green checkmark
- [ ] Loki data source in Grafana — green checkmark
- [ ] Explore tab in Grafana — can see logs from your cluster
- [ ] At least one dashboard imported and showing metrics

---

## Useful Commands Cheatsheet

```bash
# Check all monitoring pods
kubectl get pods -n monitoring

# Port-forward Prometheus
kubectl port-forward svc/prometheus-kube-prometheus-prometheus 9090:9090 -n monitoring

# Port-forward Grafana
kubectl port-forward svc/grafana 3000:80 -n monitoring

# Get Grafana admin password
kubectl get secret --namespace monitoring grafana \
  -o jsonpath="{.data.admin-password}" | base64 --decode

# Check Loki logs
kubectl logs -n monitoring -l app=loki

# Check Promtail logs
kubectl logs -n monitoring -l app=promtail
```

---
