# SRE with Azure — Reliability on the Azure Platform

## Azure's Reliability Building Blocks

Azure provides a layered reliability model. Understanding it lets you design systems that survive failures at every level — from a single VM to an entire region.

---

## Azure Reliability Hierarchy

```
Geography (e.g. Europe)
  └── Region (e.g. West Europe — Amsterdam)
        └── Availability Zone (e.g. Zone 1, Zone 2, Zone 3)
              └── Data Center
                    └── Fault Domain (rack-level failure isolation)
                          └── Update Domain (maintenance isolation)
```

### Availability Zones (AZs)

Each Azure region has 3 Availability Zones. Each zone is:
- Physically separate (different building or campus)
- Independent power, cooling, and networking
- Connected via low-latency fiber (< 2ms between zones)

**Zone failure** (rare but happens): one AZ goes down, two remain.

For high-availability workloads, deploy across all 3 zones.

### Region Pairs

Each Azure region is paired with another region in the same geography:
- West Europe ↔ North Europe
- Germany West Central ↔ Germany North

Region pairs are used for:
- Geo-redundant storage (GRS) replication
- Azure Site Recovery (disaster recovery)
- Sequential update rollouts (Azure doesn't update both paired regions simultaneously)

For multi-region SLOs (99.99%+), design for active-active or active-passive across region pairs.

---

## Azure SLA Guarantees (Know These)

Azure publishes SLAs for its services. Your internal SLO should always be tighter than the Azure SLA.

| Service | Azure SLA | Notes |
|---------|-----------|-------|
| VM (single instance, Premium SSD) | 99.9% | Single VM, same zone |
| VM (availability set) | 99.95% | Spread across fault/update domains |
| VM (availability zones) | 99.99% | Spread across 3 AZs |
| AKS (control plane) | 99.95% | With uptime SLA enabled |
| Azure SQL (Business Critical) | 99.99% | Multi-AZ |
| Azure App Service | 99.95% | |
| Azure Load Balancer (Standard) | 99.99% | |
| Azure Front Door | 99.99% | Global |

**Key insight:** A single VM has only 99.9% SLA. That's 8.7 hours downtime/year. Always use multiple instances with AZs for production SLOs.

**Composite SLA formula:**
If Service A (99.9%) depends on Service B (99.9%):
```
Composite SLA = 99.9% × 99.9% = 99.8%
```
Dependencies multiply risk. More dependencies = lower composite SLA.

---

## Azure Monitor — SLI Instrumentation

Azure Monitor is the central observability platform. For SRE, the key capabilities are:

### Metrics

Azure automatically collects platform metrics for all Azure services:
- VM: CPU, disk I/O, network
- AKS: pod count, node CPU/memory, API server latency
- SQL: DTU/vCore usage, connection count, deadlocks
- App Service: request count, response time, error rate

**Custom metrics** from your application:
```csharp
// .NET example using Azure Monitor SDK
var client = new MetricsAdvisorClient(...);
// Or use OpenTelemetry → Azure Monitor exporter
```

### Log Analytics Workspace

Centralizes logs from:
- Azure resources (Diagnostic Settings → Log Analytics)
- AKS containers (Container Insights)
- Application logs (Application Insights)

**KQL query for SLI — availability:**
```kql
requests
| where timestamp > ago(28d)
| summarize
    total = count(),
    successful = countif(success == true)
| extend availability = todouble(successful) / todouble(total) * 100
```

**KQL query for SLI — p99 latency:**
```kql
requests
| where timestamp > ago(28d)
| summarize percentile(duration, 99) by bin(timestamp, 1h)
| render timechart
```

### Application Insights — SLI for Applications

Application Insights provides distributed tracing, request tracking, and availability monitoring.

**Availability tests** (synthetic monitoring):
```
URL ping test: Hit /health every 5 minutes from 5 global locations
Multi-step test: Simulate a user flow (login → search → checkout)
Alert if: 3+ locations fail simultaneously → page on-call
```

This is your **external SLI** — measuring from the user's perspective, not from inside the cluster.

---

## Azure Monitor Alerts — SLO Alerting

### Metric Alert for Error Rate

```json
{
  "alertRule": {
    "name": "CheckoutHighErrorRate",
    "severity": 1,
    "criteria": {
      "metricName": "Http5xx",
      "metricNamespace": "Microsoft.Web/sites",
      "operator": "GreaterThan",
      "threshold": 10,
      "aggregation": "Total",
      "windowSize": "PT5M"
    },
    "actions": [
      {"actionGroupId": "/subscriptions/.../actionGroups/sre-oncall"}
    ]
  }
}
```

### Action Groups — Alert Routing

Action Groups define what happens when an alert fires:

```
Action Group: sre-oncall
  Actions:
    - Email: sre-team@company.com
    - SMS: +49 xxx (on-call phone)
    - Webhook: https://api.pagerduty.com/v2/enqueue
    - Azure Function: auto-remediation function
```

For critical alerts: webhook to PagerDuty/Opsgenie for on-call paging.
For warning alerts: email only, no page.

---

## AKS Reliability Configuration

### Enabling AKS Uptime SLA

By default, AKS control plane SLA is "free tier" (best effort). Enable paid uptime SLA for 99.95%:

```bash
az aks create \
  --resource-group myRG \
  --name myAKS \
  --tier standard \           # Enables 99.95% SLA on control plane
  --zones 1 2 3 \            # Spread across all AZs
  --node-count 3
```

### Node Pool Across Availability Zones

```bash
az aks nodepool add \
  --resource-group myRG \
  --cluster-name myAKS \
  --name productionpool \
  --node-count 6 \
  --zones 1 2 3              # 2 nodes per zone = AZ resilience
```

### AKS + Azure Monitor Integration

```bash
az aks enable-addons \
  --resource-group myRG \
  --name myAKS \
  --addons monitoring \
  --workspace-resource-id /subscriptions/.../workspaces/myLAW
```

This enables Container Insights — pre-built dashboards for:
- Node CPU/memory
- Pod restarts (leading indicator of liveness probe failures)
- Container resource requests vs limits
- Failed pod scheduling

### Recommended AKS Alerts for SRE

```
Alert: OOMKilled containers
  Query: KubePodCrashLooping (container restarts > 5 in 10 min)
  Severity: SEV 2
  Runbook: Check memory limits, application memory leak

Alert: Pending pods
  Query: KubePodNotScheduled (pod pending > 5 min)
  Severity: SEV 3
  Runbook: Check node resources, node pool scaling

Alert: Node not ready
  Query: KubeNodeNotReady
  Severity: SEV 2
  Runbook: Check node health, drain and replace if persistent

Alert: PersistentVolumeClaim pending
  Query: KubePersistentVolumeFillingUp
  Severity: SEV 1 (if < 10% remaining)
  Runbook: Expand PVC or clean up data
```

---

## Azure Chaos Studio — Chaos Engineering on Azure

Azure Chaos Studio is Azure's native chaos engineering service.

### Available Fault Types

```
VM faults:
  - Virtual Machine Shutdown
  - VM CPU Pressure
  - VM Memory Pressure
  - VM Kill Process

AKS faults:
  - AKS Chaos Mesh Pod Chaos (kill pods)
  - AKS Chaos Mesh Network Chaos (add latency)
  - AKS Chaos Mesh DNS Chaos (corrupt DNS)

Azure Service faults:
  - Service Bus faults (stop processing messages)
  - Cosmos DB faults (stop replication)
  - Network Security Group faults (block traffic)
```

### Running a Chaos Experiment

```bash
# Enable chaos on a resource
az chaos target create \
  --resource-group myRG \
  --resource-type Microsoft.Compute/virtualMachines \
  --resource-name myVM \
  --location westeurope \
  --target-type Microsoft-VirtualMachine

# Create an experiment
az chaos experiment create \
  --resource-group myRG \
  --name "AZ-Failure-Simulation" \
  --location westeurope \
  --identity "{type: SystemAssigned}" \
  --steps "[{name: 'Kill AZ1', branches: [{name: 'Kill pods in AZ1', actions: [...]}]}]"
```

---

## Azure Site Recovery — DR for SLOs

For SLOs requiring multi-region resilience:

**RTO** (Recovery Time Objective): How fast you recover
**RPO** (Recovery Point Objective): How much data you can lose

```
Tier 1 services (payment, auth):
  RTO: < 15 minutes
  RPO: 0 (zero data loss)
  Solution: Active-active across regions, Azure Traffic Manager

Tier 2 services (reporting, analytics):
  RTO: < 4 hours
  RPO: < 1 hour
  Solution: Active-passive, Azure Site Recovery, geo-redundant storage

Tier 3 services (batch jobs, non-critical):
  RTO: < 24 hours
  RPO: < 24 hours
  Solution: Backup and restore from Azure Backup
```

---

## Azure Cost vs Reliability Tradeoffs

A common SRE conversation: how much reliability does this architecture buy, and what does it cost?

```
Single VM (East US):
  SLA: 99.9%
  Cost: $X/month
  Downtime allowed: 8.7 hours/year

Availability Set (2 VMs):
  SLA: 99.95%
  Cost: $2X/month
  Downtime allowed: 4.4 hours/year

Availability Zones (3 VMs across zones):
  SLA: 99.99%
  Cost: $3X/month + zone egress costs
  Downtime allowed: 52 minutes/year

Active-Active Multi-Region:
  SLA: 99.995%+
  Cost: $6X+ (replicated infra + data transfer)
  Downtime allowed: 26 minutes/year
```

Match the architecture to the SLO requirement. Over-engineering is wasteful; under-engineering means SLA breaches.

---

## Interview Questions — SRE with Azure

**Q: What is the difference between an Availability Set and Availability Zones in Azure?**
A: An Availability Set spreads VMs across fault domains (separate racks) and update domains within a single data center — protects against hardware failures and rolling maintenance. Availability Zones spread VMs across physically separate facilities (different buildings) — protects against data center-level failures. AZs provide 99.99% SLA vs 99.95% for Availability Sets.

**Q: How do you implement SLO monitoring in Azure?**
A: Use Application Insights for application-level SLIs (request success rate, latency percentiles) with KQL queries in Log Analytics. Create Azure Monitor alerts based on error rates and latency thresholds. Use availability tests (synthetic monitoring) from multiple global locations. Route critical alerts to PagerDuty via Action Group webhooks.

**Q: What is Azure Chaos Studio and when would you use it?**
A: Azure Chaos Studio is Azure's native chaos engineering service that injects controlled failures into Azure resources (VM shutdowns, network delays, pod chaos in AKS). Use it to validate that your resilience architecture (PDBs, multi-AZ deployment, circuit breakers) works as designed before a real failure occurs.

**Q: What are RTO and RPO and how do they inform architecture decisions?**
A: RTO (Recovery Time Objective) is how quickly you must restore service after a failure. RPO (Recovery Point Objective) is the maximum data loss you can accept. A payment service might need RTO < 15 min and RPO = 0 (no data loss), requiring active-active multi-region. A reporting service might tolerate RTO < 4 hours and RPO < 1 hour, which is achievable with a simpler active-passive setup and geo-redundant storage.
