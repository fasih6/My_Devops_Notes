# Azure Monitor 📊

> Part of my DevOps journey — azure folder
> Ties into: observability/ folder

---

## Azure Monitor Overview

Azure Monitor is the **unified observability platform** for Azure — collects metrics, logs, traces, and events from every layer of your stack.

```
Azure Resources (VMs, AKS, Functions, SQL, etc.)
        ↓ automatically sends
Azure Monitor
├── Metrics          → numerical time-series (CPU %, request rate)
├── Logs             → structured/unstructured text (Log Analytics)
├── Traces           → distributed request tracing (Application Insights)
├── Alerts           → notify on conditions
└── Dashboards       → visualise everything

Data Flows:
  Resource → Diagnostic Settings → Log Analytics Workspace
  App code → Application Insights SDK → Log Analytics Workspace
  Prometheus metrics → Azure Monitor Managed Prometheus → Grafana
```

---

## Log Analytics Workspace

The central store for all logs in Azure Monitor. Everything feeds into it.

```bash
# Create workspace
az monitor log-analytics workspace create \
  --workspace-name myapp-logs \
  --resource-group myapp-prod-rg \
  --location germanywestcentral \
  --sku PerGB2018 \
  --retention-time 90

# Get workspace ID
az monitor log-analytics workspace show \
  --workspace-name myapp-logs \
  --resource-group myapp-prod-rg \
  --query customerId -o tsv

# Send diagnostic logs from a resource to workspace
az monitor diagnostic-settings create \
  --name myapp-diag \
  --resource $(az vm show -g myapp-prod-rg -n my-vm --query id -o tsv) \
  --workspace $(az monitor log-analytics workspace show \
    --workspace-name myapp-logs -g myapp-prod-rg --query id -o tsv) \
  --metrics '[{"category": "AllMetrics", "enabled": true}]' \
  --logs '[{"category": "Administrative", "enabled": true}]'
```

---

## KQL — Kusto Query Language

KQL is the query language for Log Analytics — similar to SQL but optimised for time-series and logs.

```kusto
// Basic structure
TableName
| where TimeGenerated > ago(1h)
| where column == "value"
| project column1, column2, TimeGenerated
| summarize count() by bin(TimeGenerated, 5m)
| order by TimeGenerated desc

// Common tables
AzureActivity          // Azure control plane operations (who did what)
AzureMetrics           // resource metrics
ContainerLog           // AKS container logs
KubePodInventory       // AKS pod state
KubeNodeInventory      // AKS node state
AppRequests            // Application Insights HTTP requests
AppExceptions          // Application Insights exceptions
AppDependencies        // Application Insights downstream calls
AppTraces              // Application Insights traces
Heartbeat              // agent heartbeat
Syslog                 // Linux syslog
Event                  // Windows event logs
SecurityEvent          // Windows security events
```

### Essential KQL Queries

```kusto
// Failed AKS pods in last hour
KubePodInventory
| where TimeGenerated > ago(1h)
| where PodStatus != "Running" and PodStatus != "Succeeded"
| project TimeGenerated, Namespace, PodName=Name, PodStatus, ContainerStatus
| order by TimeGenerated desc

// AKS container logs for a specific pod
ContainerLog
| where TimeGenerated > ago(1h)
| where PodName contains "myapp"
| where LogEntry contains "ERROR"
| project TimeGenerated, PodName, LogEntry
| order by TimeGenerated desc

// HTTP request rate and latency (Application Insights)
AppRequests
| where TimeGenerated > ago(1h)
| summarize
    RequestCount = count(),
    AvgDuration = avg(DurationMs),
    P95Duration = percentile(DurationMs, 95),
    FailureCount = countif(Success == false)
    by bin(TimeGenerated, 5m), Name
| order by TimeGenerated desc

// Error rate by endpoint
AppRequests
| where TimeGenerated > ago(24h)
| summarize Total=count(), Failures=countif(Success==false) by Name
| extend ErrorRate = round(100.0 * Failures / Total, 2)
| where ErrorRate > 5
| order by ErrorRate desc

// Who deleted resources (Activity Log)
AzureActivity
| where TimeGenerated > ago(24h)
| where OperationNameValue endswith "delete"
| where ActivityStatusValue == "Success"
| project TimeGenerated, Caller, OperationNameValue, ResourceGroup, Resource=_ResourceId
| order by TimeGenerated desc

// VM CPU over 80% in last hour
AzureMetrics
| where TimeGenerated > ago(1h)
| where MetricName == "Percentage CPU"
| where Maximum > 80
| summarize MaxCPU = max(Maximum) by Resource, bin(TimeGenerated, 5m)
| order by MaxCPU desc

// Node resource pressure
KubeNodeInventory
| where TimeGenerated > ago(5m)
| project Computer, Status, KubeletVersion
| where Status contains "Pressure"
```

---

## Metrics

Azure Monitor collects platform metrics automatically — CPU, memory, disk, network for every resource.

```bash
# Query metrics via CLI
az monitor metrics list \
  --resource $(az vm show -g myapp-prod-rg -n my-vm --query id -o tsv) \
  --metric "Percentage CPU" \
  --start-time 2024-01-01T00:00:00Z \
  --end-time 2024-01-01T01:00:00Z \
  --interval PT5M \
  --aggregation Average Maximum \
  --output table

# List available metrics for a resource
az monitor metrics list-definitions \
  --resource $(az vm show -g myapp-prod-rg -n my-vm --query id -o tsv) \
  --output table
```

### Azure Monitor Managed Prometheus + Grafana

For AKS clusters — collect Prometheus metrics without managing a Prometheus server.

```bash
# Enable Managed Prometheus on AKS
az aks update \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --enable-azure-monitor-metrics

# Create Managed Grafana
az grafana create \
  --name myapp-grafana \
  --resource-group myapp-prod-rg \
  --location germanywestcentral

# Link Grafana to Azure Monitor workspace
az aks update \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --enable-azure-monitor-metrics \
  --azure-monitor-workspace-resource-id <workspace-id> \
  --grafana-resource-id $(az grafana show -n myapp-grafana -g myapp-prod-rg --query id -o tsv)
```

---

## Application Insights

**Application Performance Management (APM)** for your application — traces, exceptions, dependencies, user analytics.

```bash
# Create Application Insights
az monitor app-insights component create \
  --app myapp-insights \
  --resource-group myapp-prod-rg \
  --location germanywestcentral \
  --workspace $(az monitor log-analytics workspace show \
    --workspace-name myapp-logs -g myapp-prod-rg --query id -o tsv)

# Get connection string
az monitor app-insights component show \
  --app myapp-insights \
  --resource-group myapp-prod-rg \
  --query connectionString -o tsv
```

### SDK Integration

```python
# Python — FastAPI / Flask
from azure.monitor.opentelemetry import configure_azure_monitor

configure_azure_monitor(
    connection_string="InstrumentationKey=xxx;IngestionEndpoint=..."
)

# Now all requests, exceptions, dependencies auto-tracked
```

```javascript
// Node.js
const { useAzureMonitor } = require("@azure/monitor-opentelemetry");
useAzureMonitor({
  azureMonitorExporterOptions: {
    connectionString: process.env.APPLICATIONINSIGHTS_CONNECTION_STRING,
  },
});
```

### Application Map

Automatically generates a visual map of your application's dependencies and their health — services, databases, external APIs, queues — with latency and failure rates for each connection.

### Live Metrics

Real-time streaming of requests, failures, server health — zero latency, useful during deployments.

### Smart Detection (Anomaly Detection)

Automatically detects anomalies in request rate, failure rate, response time, and dependency failures — no threshold configuration needed.

---

## Alerts

### Metric Alerts

```bash
# Alert when CPU > 80%
az monitor metrics alert create \
  --name high-cpu-alert \
  --resource-group myapp-prod-rg \
  --scopes $(az vm show -g myapp-prod-rg -n my-vm --query id -o tsv) \
  --condition "avg Percentage CPU > 80" \
  --window-size 5m \
  --evaluation-frequency 1m \
  --severity 2 \
  --action $(az monitor action-group show \
    --name myapp-action-group -g myapp-prod-rg --query id -o tsv)

# Alert when AKS pod count drops
az monitor metrics alert create \
  --name pod-count-alert \
  --resource-group myapp-prod-rg \
  --scopes $(az aks show -n my-aks -g myapp-prod-rg --query id -o tsv) \
  --condition "avg kube_pod_status_ready < 3" \
  --window-size 5m \
  --severity 1
```

### Log Alerts (KQL-based)

```bash
# Alert when error rate > 5%
az monitor scheduled-query create \
  --name high-error-rate \
  --resource-group myapp-prod-rg \
  --scopes $(az monitor log-analytics workspace show \
    --workspace-name myapp-logs -g myapp-prod-rg --query id -o tsv) \
  --condition-query "AppRequests
    | where TimeGenerated > ago(5m)
    | summarize Total=count(), Errors=countif(Success==false)
    | extend ErrorRate = 100.0 * Errors / Total
    | where ErrorRate > 5" \
  --condition-time-aggregation Count \
  --condition-operator GreaterThan \
  --condition-threshold 0 \
  --evaluation-frequency 5m \
  --window-size 5m \
  --severity 2 \
  --action $(az monitor action-group show \
    --name myapp-action-group -g myapp-prod-rg --query id -o tsv)
```

### Action Groups (Where Alerts Go)

```bash
# Create action group
az monitor action-group create \
  --name myapp-action-group \
  --resource-group myapp-prod-rg \
  --short-name myapp \
  --email-receiver name=oncall email=oncall@mycompany.com \
  --webhook-receiver name=pagerduty uri=https://events.pagerduty.com/...

# Add SMS receiver
az monitor action-group update \
  --name myapp-action-group \
  --resource-group myapp-prod-rg \
  --sms-receiver name=phone country-code=49 phone-number=1234567890
```

**Action types:** Email, SMS, Push notification, Voice, Webhook, Azure Function, Logic App, Automation Runbook, ITSM (ServiceNow, JIRA).

---

## Container Insights (AKS Monitoring)

```bash
# Enable Container Insights on AKS
az aks enable-addons \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --addons monitoring \
  --workspace-resource-id $(az monitor log-analytics workspace show \
    --workspace-name myapp-logs -g myapp-prod-rg --query id -o tsv)
```

Provides out-of-the-box dashboards for:
- Cluster health (nodes, pods, containers)
- Resource utilisation (CPU, memory per namespace/pod)
- Controller performance
- Container live logs

---

## Workbooks & Dashboards

**Workbooks** — interactive reports combining KQL queries, metrics, parameters, and visualisations.

**Dashboards** — pinned tiles for at-a-glance monitoring.

```bash
# Pin a metric chart to dashboard (via Portal)
# Azure Monitor → Metrics → create chart → Pin to Dashboard

# Export workbook as JSON
az monitor app-insights workbook show \
  --resource-group myapp-prod-rg \
  --name <workbook-guid>
```

---

## Quick Reference

```bash
# Log Analytics
az monitor log-analytics workspace create --workspace-name x -g rg
az monitor diagnostic-settings create --name x --resource <id> --workspace <id>

# Metrics
az monitor metrics list --resource <id> --metric "Percentage CPU"
az monitor metrics list-definitions --resource <id>

# Alerts
az monitor metrics alert create --name x --scopes <id> --condition "avg CPU > 80"
az monitor scheduled-query create --name x --condition-query "KQL..."
az monitor action-group create --name x --email-receiver name=x email=x

# App Insights
az monitor app-insights component create --app x -g rg --workspace <id>
az monitor app-insights component show --app x -g rg --query connectionString

Key KQL tables:
  ContainerLog, KubePodInventory, KubeNodeInventory   → AKS
  AppRequests, AppExceptions, AppDependencies          → Application Insights
  AzureActivity                                        → who did what in Azure
  AzureMetrics                                         → resource metrics
  Heartbeat                                            → agent health

Managed Prometheus + Grafana → az aks update --enable-azure-monitor-metrics
Container Insights           → az aks enable-addons --addons monitoring
```
