# 🚨 Alerting & Incident Response

Know when something breaks — and know what to do about it.

> **Prerequisites:** Completed [02-tooling-setup.md](./02-tooling-setup.md) — Prometheus, Grafana, and Loki are running.

---

## 📚 Table of Contents

- [The Big Picture](#the-big-picture)
- [1. Alerting Concepts](#1-alerting-concepts)
- [2. Prometheus Alerting Rules](#2-prometheus-alerting-rules)
- [3. Alertmanager — Routing & Notifications](#3-alertmanager--routing--notifications)
- [4. Grafana Alerts](#4-grafana-alerts)
- [5. Runbooks](#5-runbooks)
- [6. Incident Response Basics](#6-incident-response-basics)
- [Alerting Cheatsheet](#alerting-cheatsheet)

---

## The Big Picture

```
Prometheus evaluates alert rules every 15s
           │
           │ rule fires (e.g. CPU > 90%)
           ▼
      Alertmanager
           │
     routes & deduplicates
           │
    ┌──────┴───────┐
    ▼              ▼
  Slack          PagerDuty
 (warning)       (critical)
```

Prometheus **detects** the problem. Alertmanager **decides who to tell and how**. You **respond** using a runbook.

---

## 1. Alerting Concepts

Before writing any rules, understand these terms:

| Term | What it means |
|------|--------------|
| **Alert rule** | A PromQL condition that, when true, fires an alert |
| **Pending** | Rule is firing but hasn't lasted long enough yet (avoids flapping) |
| **Firing** | Alert is active and sent to Alertmanager |
| **Resolved** | Condition is no longer true — alert clears |
| **Inhibition** | Suppress lower-priority alerts when a higher one is firing |
| **Silencing** | Mute an alert temporarily (e.g. during planned maintenance) |
| **Flapping** | Alert rapidly switching between firing and resolved — usually means your threshold is too tight |

### The golden rule: alert on symptoms, not causes

❌ **Bad:** Alert when a specific pod restarts  
✅ **Good:** Alert when error rate exceeds 5% for 5 minutes

Users experience symptoms (slow responses, errors). Alert on what they feel, then investigate the cause.

---

## 2. Prometheus Alerting Rules

Rules are defined in YAML and loaded by Prometheus. Each rule is a PromQL expression — when it evaluates to true for a set duration, the alert fires.

### Basic rule structure

```yaml
groups:
  - name: example-alerts
    rules:
      - alert: HighCPUUsage
        expr: avg(rate(container_cpu_usage_seconds_total[5m])) by (pod) > 0.8
        for: 5m                          # must be true for 5 min before firing
        labels:
          severity: warning
        annotations:
          summary: "High CPU on {{ $labels.pod }}"
          description: "Pod {{ $labels.pod }} is using more than 80% CPU for 5 minutes."
```

### Common useful alerts for Kubernetes

```yaml
groups:
  - name: kubernetes-alerts
    rules:

      # Pod has been crashing repeatedly
      - alert: PodCrashLooping
        expr: rate(kube_pod_container_status_restarts_total[15m]) > 0
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Pod {{ $labels.pod }} is crash looping"

      # Node is running out of memory
      - alert: NodeMemoryPressure
        expr: |
          node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes < 0.1
        for: 2m
        labels:
          severity: warning
        annotations:
          summary: "Node {{ $labels.node }} has less than 10% memory available"

      # Deployment has no available replicas
      - alert: DeploymentUnavailable
        expr: kube_deployment_status_replicas_available == 0
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Deployment {{ $labels.deployment }} has no available replicas"

      # High HTTP error rate
      - alert: HighErrorRate
        expr: |
          rate(http_requests_total{status=~"5.."}[5m])
          / rate(http_requests_total[5m]) > 0.05
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Error rate above 5% for {{ $labels.service }}"
```

### Apply rules to your cluster

Save the file as `alert-rules.yaml`, then:

```bash
# If using kube-prometheus-stack, create a PrometheusRule resource
kubectl apply -f alert-rules.yaml -n monitoring

# Verify Prometheus picked it up
# Go to localhost:9090 → Alerts tab
```

Or add them via Helm values:

```yaml
# values.yaml
additionalPrometheusRulesMap:
  custom-rules:
    groups:
      - name: my-alerts
        rules:
          - alert: ...
```

```bash
helm upgrade prometheus prometheus-community/kube-prometheus-stack \
  -f values.yaml -n monitoring
```

---

## 3. Alertmanager — Routing & Notifications

Alertmanager receives alerts from Prometheus and decides: who gets notified, through which channel, and how often.

### Key concepts

| Concept | What it does |
|---------|-------------|
| **Route** | Matches alerts by label and sends to a receiver |
| **Receiver** | A notification target (Slack, email, PagerDuty, etc.) |
| **Group by** | Bundles related alerts into one notification |
| **Repeat interval** | How often to re-notify if alert is still firing |
| **Inhibit rule** | Suppress child alerts when a parent alert fires |

### Example Alertmanager config

```yaml
# alertmanager.yaml
global:
  slack_api_url: 'https://hooks.slack.com/services/YOUR/WEBHOOK/URL'

route:
  group_by: ['alertname', 'namespace']
  group_wait: 30s          # wait before sending the first notification
  group_interval: 5m       # wait before sending updates
  repeat_interval: 4h      # re-notify if still firing
  receiver: 'slack-warnings'

  routes:
    # Critical alerts go to PagerDuty
    - match:
        severity: critical
      receiver: 'pagerduty-critical'

    # Warning alerts go to Slack
    - match:
        severity: warning
      receiver: 'slack-warnings'

receivers:
  - name: 'slack-warnings'
    slack_configs:
      - channel: '#alerts'
        title: '{{ .GroupLabels.alertname }}'
        text: '{{ range .Alerts }}{{ .Annotations.summary }}{{ end }}'

  - name: 'pagerduty-critical'
    pagerduty_configs:
      - routing_key: 'YOUR_PAGERDUTY_INTEGRATION_KEY'

inhibit_rules:
  # If a node is down, suppress pod-level alerts from that node
  - source_match:
      severity: critical
      alertname: NodeDown
    target_match:
      severity: warning
    equal: ['node']
```

### Apply the config

```bash
kubectl create secret generic alertmanager-prometheus-kube-prometheus-alertmanager \
  --from-file=alertmanager.yaml \
  -n monitoring \
  --dry-run=client -o yaml | kubectl apply -f -
```

### Access Alertmanager UI

```bash
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring
```

Open [http://localhost:9093](http://localhost:9093) to see active alerts, silences, and inhibitions.

---

## 4. Grafana Alerts

Grafana can also fire alerts directly from dashboard panels — useful for log-based alerts (since Prometheus can't alert on Loki data).

### Create an alert in Grafana

1. Open a dashboard panel → click **Edit**
2. Go to the **Alert** tab
3. Click **Create alert rule from this panel**
4. Set your condition (e.g. "Last value is above 90")
5. Set evaluation interval (e.g. every 1m for 5m)
6. Add a **notification policy** to route to Slack/email

### When to use Grafana alerts vs Prometheus alerts

| Use Grafana alerts when... | Use Prometheus alerts when... |
|---------------------------|------------------------------|
| Alerting on log patterns (Loki) | Alerting on metrics |
| You want a visual UI to manage rules | You want rules stored as code (GitOps) |
| Quick one-off alerts | Production, team-shared alerts |

---

## 5. Runbooks

A runbook is a short document that tells whoever is on-call **exactly what to do** when a specific alert fires. It removes guesswork at 3am.

### Runbook template

```markdown
## Alert: HighErrorRate

**Severity:** Critical  
**Team:** Platform  

### What is happening?
The HTTP error rate for [service] has exceeded 5% for more than 5 minutes.

### Impact
Users are experiencing failures. Requests are not completing successfully.

### Immediate steps
1. Check which pods are affected:
   kubectl get pods -n <namespace>

2. Check recent logs for errors:
   kubectl logs -n <namespace> <pod-name> --tail=100

3. Check if a recent deployment caused this:
   kubectl rollout history deployment/<name> -n <namespace>

4. If caused by a bad deploy, roll back:
   kubectl rollout undo deployment/<name> -n <namespace>

### Escalate if
- Rollback doesn't fix it within 10 minutes
- Error rate exceeds 20%
- Multiple services are affected

### Silence the alert (if planned maintenance)
Go to Alertmanager → Silences → New Silence
```

### Where to store runbooks

- In the same Git repo as your alert rules (keeps them in sync)
- Link to them from the alert annotation:

```yaml
annotations:
  summary: "High error rate on {{ $labels.service }}"
  runbook_url: "https://github.com/your-org/runbooks/blob/main/high-error-rate.md"
```

---

## 6. Incident Response Basics

When an alert fires in production, having a process prevents chaos.

### Simple incident lifecycle

```
Alert fires
    │
    ▼
Acknowledge — someone owns it (stops re-paging)
    │
    ▼
Investigate — use metrics, logs, traces to find root cause
    │
    ▼
Mitigate — stop the bleeding (rollback, restart, scale up)
    │
    ▼
Resolve — confirm the issue is gone, alert clears
    │
    ▼
Post-mortem — document what happened and how to prevent it
```

### During an incident: useful commands

```bash
# What's broken right now?
kubectl get pods -A | grep -v Running

# Recent events (crashes, scheduling issues)
kubectl get events -n <namespace> --sort-by='.lastTimestamp'

# Logs from a crashing pod
kubectl logs <pod-name> -n <namespace> --previous

# Resource usage per pod
kubectl top pods -n <namespace>

# Resource usage per node
kubectl top nodes

# Describe a pod (shows restart count, events, image)
kubectl describe pod <pod-name> -n <namespace>

# Quick rollback
kubectl rollout undo deployment/<name> -n <namespace>
```

### Post-mortem template (blameless)

```markdown
## Incident: [Short title]
**Date:** YYYY-MM-DD  
**Duration:** X hours Y minutes  
**Severity:** Critical / High / Medium  

### What happened?
[Plain English summary]

### Timeline
- HH:MM — Alert fired
- HH:MM — On-call acknowledged
- HH:MM — Root cause identified
- HH:MM — Mitigation applied
- HH:MM — Resolved

### Root cause
[What actually caused it]

### What went well?
[Honest positives]

### What can be improved?
[Honest gaps]

### Action items
| Action | Owner | Due |
|--------|-------|-----|
| Add alert for X | @person | date |
| Update runbook | @person | date |
```

> 💡 **Blameless means:** focus on fixing the system, not blaming the person. Everyone makes mistakes — the goal is to make the system resilient enough that one mistake doesn't cause an outage.

---

## Alerting Cheatsheet

```bash
# Port-forward Alertmanager
kubectl port-forward svc/prometheus-kube-prometheus-alertmanager 9093:9093 -n monitoring

# View current firing alerts
kubectl get prometheusrule -n monitoring

# Check Alertmanager config is valid
amtool check-config alertmanager.yaml

# Silence an alert for 2 hours (via CLI)
amtool silence add alertname="PodCrashLooping" --duration=2h --comment="Investigating"

# List active silences
amtool silence query

# Test Alertmanager routing (dry run)
amtool config routes test --config.file=alertmanager.yaml alertname="HighCPUUsage" severity="warning"
```

---
