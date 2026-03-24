# ☁️ Cloud Provider Observability

Native observability tools from AWS, GCP, and Azure — and how they fit alongside your Prometheus/Grafana stack.

> **Why this matters for DevOps roles:** Most companies run on one of these three clouds. Knowing the native tools — even at a high level — shows you can work in real-world environments, not just local clusters.

---

## 📚 Table of Contents

- [The Big Picture](#the-big-picture)
- [1. AWS — CloudWatch & Container Insights](#1-aws--cloudwatch--container-insights)
- [2. GCP — Cloud Monitoring & Google Managed Prometheus](#2-gcp--cloud-monitoring--google-managed-prometheus)
- [3. Azure — Azure Monitor & Container Insights](#3-azure--azure-monitor--container-insights)
- [4. Native vs Self-Managed: When to Use What](#4-native-vs-self-managed-when-to-use-what)
- [5. Connecting Cloud Tools to Grafana](#5-connecting-cloud-tools-to-grafana)
- [Quick Reference Cheatsheet](#quick-reference-cheatsheet)

---

## The Big Picture

Every cloud provider has its own observability suite. They all cover the same three pillars — just with different names:

| Pillar | AWS | GCP | Azure |
|--------|-----|-----|-------|
| **Metrics** | CloudWatch Metrics | Cloud Monitoring | Azure Monitor Metrics |
| **Logs** | CloudWatch Logs | Cloud Logging | Log Analytics / Azure Monitor Logs |
| **Traces** | X-Ray | Cloud Trace | Application Insights |
| **Dashboards** | CloudWatch Dashboards | Cloud Monitoring Dashboards | Azure Workbooks |
| **Alerts** | CloudWatch Alarms | Alerting Policies | Azure Alerts |
| **K8s-specific** | Container Insights (EKS) | GKE Observability | Container Insights (AKS) |

### The key tradeoff

```
Native Cloud Tools                Self-Managed (Prometheus/Grafana)
─────────────────                 ────────────────────────────────
✅ Zero setup                     ✅ Full control
✅ Deeply integrated              ✅ Vendor-neutral
✅ Managed for you                ✅ Works across clouds
❌ Vendor lock-in                 ❌ You manage it
❌ Can get expensive at scale     ❌ More initial setup
❌ Different per cloud            ✅ Same stack everywhere
```

Most real companies use **both** — native tools for quick wins and cloud-level visibility, Prometheus/Grafana for custom app metrics and cross-cloud views.

---

## 1. AWS — CloudWatch & Container Insights

### What is CloudWatch?

CloudWatch is AWS's all-in-one observability service. It collects metrics and logs from almost every AWS service automatically — EC2, RDS, Lambda, EKS, and more.

### Key CloudWatch components

| Component | What it does |
|-----------|-------------|
| **Metrics** | Time-series data from AWS services and your apps |
| **Logs** | Stores and queries log streams from any source |
| **Log Insights** | SQL-like query language for searching logs |
| **Alarms** | Triggers notifications or auto-scaling based on metrics |
| **Dashboards** | Visual panels for metrics |
| **Container Insights** | Deep EKS/ECS metrics (pods, nodes, containers) |
| **X-Ray** | Distributed tracing for AWS workloads |

### Enable Container Insights on EKS

Container Insights gives you pod-level CPU, memory, network, and disk metrics — plus cluster-level views.

```bash
# Attach the required IAM policy to your node group role first
aws iam attach-role-policy \
  --role-name <your-node-group-role> \
  --policy-arn arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy

# Deploy the CloudWatch agent as a DaemonSet
kubectl apply -f https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/cloudwatch-namespace.yaml

# Install using the quick-start script
ClusterName=<your-cluster-name>
RegionName=<your-region>
FluentBitHttpPort='2020'
FluentBitReadFromHead='Off'

curl https://raw.githubusercontent.com/aws-samples/amazon-cloudwatch-container-insights/latest/k8s-deployment-manifest-templates/deployment-mode/daemonset/container-insights-monitoring/quickstart/cwagent-fluent-bit-quickstart.yaml | \
  sed "s/{{cluster_name}}/${ClusterName}/;s/{{region_name}}/${RegionName}/;s/{{http_server_toggle}}/On/;s/{{http_server_port}}/${FluentBitHttpPort}/;s/{{read_from_head}}/${FluentBitReadFromHead}/" | \
  kubectl apply -f -
```

### Query logs with CloudWatch Log Insights

```sql
-- Find all ERROR logs in the last hour
fields @timestamp, @message
| filter @message like /ERROR/
| sort @timestamp desc
| limit 50

-- Count errors by pod
fields @timestamp, @message, kubernetes.pod_name
| filter @message like /ERROR/
| stats count(*) as error_count by kubernetes.pod_name
| sort error_count desc

-- Find slow requests (over 1 second)
fields @timestamp, @message, duration
| filter duration > 1000
| sort duration desc
```

### Set up a CloudWatch Alarm

```bash
# Alert when CPU > 80% for 5 minutes
aws cloudwatch put-metric-alarm \
  --alarm-name "High-CPU-EKS" \
  --metric-name CPUUtilization \
  --namespace ContainerInsights \
  --statistic Average \
  --period 300 \
  --threshold 80 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions arn:aws:sns:<region>:<account>:<your-sns-topic>
```

### Scrape CloudWatch metrics into Prometheus

Use the `yet-another-cloudwatch-exporter` (YACE) to pull CloudWatch metrics into Prometheus — so you can view AWS metrics alongside your app metrics in Grafana:

```bash
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm install yace prometheus-community/prometheus-cloudwatch-exporter \
  --namespace monitoring \
  --set aws.region=eu-central-1
```

---

## 2. GCP — Cloud Monitoring & Google Managed Prometheus

### What is Cloud Monitoring?

GCP's Cloud Monitoring (formerly Stackdriver) collects metrics, logs, and traces from GCP services and GKE clusters automatically.

### Key GCP components

| Component | What it does |
|-----------|-------------|
| **Cloud Monitoring** | Metrics, dashboards, uptime checks |
| **Cloud Logging** | Centralized log storage and search |
| **Cloud Trace** | Distributed tracing |
| **Error Reporting** | Groups and surfaces application errors |
| **Google Managed Prometheus (GMP)** | Fully managed Prometheus — drop-in replacement |
| **GKE Observability** | Pre-built dashboards for GKE clusters |

### Google Managed Prometheus (GMP)

This is the big one for Kubernetes on GCP. GMP is a fully managed Prometheus-compatible service — you keep your existing PromQL queries and Grafana dashboards, but Google handles the infrastructure.

```bash
# Enable on a GKE cluster
gcloud container clusters update <cluster-name> \
  --enable-managed-prometheus \
  --region <region>
```

Deploy a `PodMonitoring` resource to tell GMP what to scrape (same concept as Prometheus `ServiceMonitor`):

```yaml
apiVersion: monitoring.googleapis.com/v1
kind: PodMonitoring
metadata:
  name: my-app-monitoring
  namespace: default
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
    - port: metrics
      interval: 30s
```

```bash
kubectl apply -f pod-monitoring.yaml
```

Your app's metrics now appear in Cloud Monitoring — queryable with PromQL.

### Query logs with Log Explorer

GCP uses a structured query language called **Log Query Language (LQL)**:

```
# All ERROR logs from a GKE pod
resource.type="k8s_container"
severity=ERROR
resource.labels.cluster_name="my-cluster"

# Logs from a specific namespace
resource.type="k8s_container"
resource.labels.namespace_name="production"

# Find logs containing a specific message
resource.type="k8s_container"
textPayload:"connection refused"

# Logs in the last 30 minutes with high severity
resource.type="k8s_container"
severity>=WARNING
timestamp>="2024-01-01T00:00:00Z"
```

### Create an alerting policy (GCP)

```bash
# Via gcloud CLI — alert on high memory usage
gcloud alpha monitoring policies create \
  --notification-channels=<channel-id> \
  --display-name="High Memory Usage" \
  --condition-display-name="Memory > 80%" \
  --condition-filter='resource.type="k8s_node" AND metric.type="kubernetes.io/node/memory/used_bytes"' \
  --condition-threshold-value=0.8 \
  --condition-threshold-comparison=COMPARISON_GT \
  --condition-duration=300s
```

---

## 3. Azure — Azure Monitor & Container Insights

### What is Azure Monitor?

Azure Monitor is the umbrella service for all observability on Azure. It collects metrics and logs from Azure resources, VMs, and AKS clusters.

### Key Azure components

| Component | What it does |
|-----------|-------------|
| **Azure Monitor Metrics** | Time-series metrics from Azure resources |
| **Log Analytics Workspace** | Central store for logs — queryable with KQL |
| **Container Insights** | Deep AKS metrics (pods, nodes, deployments) |
| **Application Insights** | APM — traces, exceptions, request tracking |
| **Azure Alerts** | Metric and log-based alerting |
| **Azure Workbooks** | Rich interactive dashboards |
| **Managed Prometheus** | Fully managed Prometheus for AKS |

### Enable Container Insights on AKS

```bash
# Enable on an existing AKS cluster
az aks enable-addons \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --addons monitoring \
  --workspace-resource-id <log-analytics-workspace-id>
```

This deploys the Azure Monitor agent as a DaemonSet and starts collecting pod/node metrics automatically.

### Enable Azure Managed Prometheus

```bash
# Create an Azure Monitor workspace
az monitor account create \
  --name myMonitorWorkspace \
  --resource-group <resource-group> \
  --location germanywestcentral

# Link it to your AKS cluster
az aks update \
  --resource-group <resource-group> \
  --name <cluster-name> \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id <workspace-id>
```

### Query logs with KQL (Kusto Query Language)

Azure uses **KQL** to query logs in Log Analytics. It's more powerful than CloudWatch Log Insights:

```kusto
// All pod errors in the last hour
KubePodInventory
| where TimeGenerated > ago(1h)
| where ContainerStatus == "Error"
| project TimeGenerated, Name, Namespace, ContainerStatus

// Top 10 pods by CPU usage
Perf
| where ObjectName == "K8SContainer" and CounterName == "cpuUsageNanoCores"
| summarize avg(CounterValue) by InstanceName
| top 10 by avg_CounterValue desc

// Count of errors by namespace
ContainerLog
| where LogEntry contains "ERROR"
| summarize error_count=count() by Namespace = extractjson("$.namespace", Tags)
| order by error_count desc

// Requests per second for an app
requests
| where timestamp > ago(1h)
| summarize rps=count() by bin(timestamp, 1m)
| render timechart
```

### Create an Azure Alert

```bash
# Alert when pod restart count exceeds 5
az monitor metrics alert create \
  --name "Pod Restart Alert" \
  --resource-group <resource-group> \
  --scopes <aks-cluster-resource-id> \
  --condition "avg kube_pod_container_status_restarts_total > 5" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --action <action-group-id> \
  --severity 2
```

---

## 4. Native vs Self-Managed: When to Use What

### Use native cloud tools when:
- You're on a **single cloud** and want fast setup with zero maintenance
- You need **cloud-level visibility** (billing, quotas, managed service health)
- Your team is **small** and can't afford to maintain Prometheus infrastructure
- You're using **serverless** (Lambda, Cloud Functions, Azure Functions) — Prometheus can't scrape these

### Use self-managed Prometheus/Grafana when:
- You're **multi-cloud** or hybrid and need one unified view
- You have **custom app metrics** that need flexible instrumentation
- You want **full control** over retention, cardinality, and cost
- Your team already knows the Prometheus/Grafana ecosystem
- You're building a **portfolio** — self-managed shows more depth to interviewers

### The pragmatic hybrid approach (most companies)

```
AWS CloudWatch / GCP Monitoring / Azure Monitor
        │
        │ native metrics for managed services
        │ (RDS, S3, managed Kubernetes nodes)
        ▼
  Prometheus + Grafana
        │
        │ custom app metrics, cross-service views,
        │ unified dashboards, alerting rules as code
        ▼
     One Grafana instance
     showing everything
```

---

## 5. Connecting Cloud Tools to Grafana

You don't have to choose — Grafana supports all three clouds as data sources.

### AWS CloudWatch in Grafana

1. Go to **Connections → Data Sources → Add data source**
2. Select **CloudWatch**
3. Configure:

```yaml
Authentication Provider: AWS SDK Default  # uses IAM role if on EKS
Default Region: eu-central-1
```

Required IAM permissions for the Grafana pod:
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "cloudwatch:GetMetricData",
      "cloudwatch:ListMetrics",
      "logs:GetLogEvents",
      "logs:DescribeLogGroups"
    ],
    "Resource": "*"
  }]
}
```

### GCP Cloud Monitoring in Grafana

1. Add data source → select **Google Cloud Monitoring**
2. Upload a GCP service account JSON key with `Monitoring Viewer` role
3. Select your GCP project

### Azure Monitor in Grafana

1. Add data source → select **Azure Monitor**
2. Configure with an Azure App Registration (service principal):

```yaml
Directory (tenant) ID: <your-tenant-id>
Application (client) ID: <your-app-id>
Client Secret: <your-client-secret>
Default Subscription: <your-subscription-id>
```

The App Registration needs the **Monitoring Reader** role on your subscription.

---

## Quick Reference Cheatsheet

### Key services side by side

| Need | AWS | GCP | Azure |
|------|-----|-----|-------|
| View cluster metrics | Container Insights | GKE Observability | Container Insights |
| Query logs | CloudWatch Log Insights | Log Explorer (LQL) | Log Analytics (KQL) |
| Managed Prometheus | AMP (Amazon Managed Prometheus) | Google Managed Prometheus | Azure Managed Prometheus |
| Distributed tracing | X-Ray | Cloud Trace | Application Insights |
| Set an alert | CloudWatch Alarm | Alerting Policy | Azure Alert Rule |
| View dashboards | CloudWatch Dashboards | Cloud Monitoring Dashboards | Azure Workbooks |

### Useful CLI commands

```bash
# AWS — tail CloudWatch logs
aws logs tail /aws/containerinsights/<cluster>/performance --follow

# AWS — list CloudWatch alarms
aws cloudwatch describe-alarms --state-value ALARM

# GCP — tail GKE logs
gcloud logging read 'resource.type="k8s_container"' --limit=50 --format=json

# GCP — list alerting policies
gcloud alpha monitoring policies list

# Azure — query Log Analytics
az monitor log-analytics query \
  --workspace <workspace-id> \
  --analytics-query "KubePodInventory | where ContainerStatus == 'Error' | limit 10"

# Azure — list active alerts
az monitor metrics alert list --resource-group <resource-group>
```

---
