# Azure Cost Management 💰

> Part of my DevOps journey — azure folder

---

## Azure Cost Management + Billing

The central hub for all cost visibility, analysis, budgets, and recommendations. Available in the Azure portal under "Cost Management + Billing."

---

## Cost Analysis

Analyse spend by subscription, resource group, resource, service, tag, location, and more.

```bash
# Get cost via CLI (requires cost management extension)
az costmanagement query \
  --type Usage \
  --timeframe MonthToDate \
  --dataset-aggregation totalCost=sum(Cost) \
  --dataset-groupby name=ServiceName type=Dimension

# Export usage data to Storage Account
az costmanagement export create \
  --name monthly-export \
  --type Usage \
  --scope /subscriptions/<subscription-id> \
  --storage-account-id /subscriptions/.../storageAccounts/mybillingaccount \
  --storage-container billing \
  --time-frame MonthToDate \
  --recurrence Monthly \
  --recurrence-period from=2024-01-01 to=2025-01-01
```

---

## Budgets & Alerts

```bash
# Create monthly budget with email alert
az consumption budget create \
  --budget-name monthly-limit \
  --amount 1000 \
  --time-grain Monthly \
  --category Cost \
  --resource-group myapp-prod-rg \
  --time-period start=2024-01-01 end=2025-01-01 \
  --notifications '[{
    "enabled": true,
    "operator": "GreaterThan",
    "threshold": 80,
    "contactEmails": ["team@mycompany.com"],
    "contactRoles": ["Owner"],
    "thresholdType": "Percentage"
  }, {
    "enabled": true,
    "operator": "GreaterThan",
    "threshold": 100,
    "contactEmails": ["team@mycompany.com", "manager@mycompany.com"],
    "thresholdType": "Percentage"
  }]'

# List budgets
az consumption budget list --resource-group myapp-prod-rg --output table
```

**Budget actions (beyond email alerts):**
- Trigger Azure Automation runbook (e.g. auto-stop VMs)
- Trigger Logic App (e.g. send Teams notification)
- Trigger Action Group (email, SMS, webhook, PagerDuty)

---

## Azure Reservations (≈ AWS Reserved Instances)

Commit to 1 or 3 years for specific resources in exchange for significant discounts.

| Resource | 1yr discount | 3yr discount |
|----------|------------|------------|
| Virtual Machines | ~40% | ~60% |
| SQL Database | ~33% | ~55% |
| Cosmos DB | ~20% | ~35% |
| Blob Storage | ~20% | ~38% |
| App Service | ~41% | ~58% |
| AKS (nodes are VMs) | ~40% | ~60% |

```bash
# List reservations
az reservations reservation list --output table

# List reservation orders
az reservations reservation-order list --output table
```

Purchase in Azure Portal: Search "Reservations" → Add → Select resource type.

**Reservation flexibility:**
- **Instance size flexibility** — reservation applies to same VM series (Standard_D2s_v5 covers D2/D4/D8 proportionally)
- **Shared scope** — applies across any subscription in your tenant
- **Exchange/refund** — can exchange for a different reservation (within limits)

---

## Azure Savings Plans (≈ AWS Savings Plans)

Flexible commitment — commit to a spend rate ($/hour) for 1 or 3 years. Applies automatically to eligible compute usage.

```
Compute Savings Plan: applies to VMs, Container Apps, Functions, ACI
                      any region, any OS, any VM family
1yr: ~15-23% savings | 3yr: ~30-37% savings
```

**Savings Plan vs Reservation:**
- Savings Plan — flexible (any VM size/region/OS), lower discount
- Reservation — specific (exact VM size + region), higher discount
- Use both: Savings Plan for baseline flexibility + Reservations for predictable workloads

---

## Azure Advisor — Cost Recommendations

AI-powered recommendations to reduce cost, improve security, reliability, performance.

```bash
# Get cost recommendations
az advisor recommendation list \
  --category Cost \
  --output table

# Suppress a recommendation
az advisor recommendation disable \
  --recommendation-id <id> \
  --days-to-suppress 30
```

**Common Advisor cost recommendations:**
- Right-size underutilised VMs
- Shut down idle VMs
- Delete unattached managed disks
- Buy reservations for consistently running resources
- Remove unused public IP addresses
- Use Azure Hybrid Benefit

---

## Azure Hybrid Benefit

Use existing Windows Server or SQL Server licences in Azure — significant savings.

```bash
# Enable Hybrid Benefit on VM (Windows Server)
az vm update \
  --name my-windows-vm \
  --resource-group myapp-prod-rg \
  --license-type Windows_Server

# Enable on Azure SQL
az sql db update \
  --name mydb \
  --server myapp-sql-server \
  --resource-group myapp-prod-rg \
  --license-type LicenseIncluded  # or BasePrice (AHB)
```

**Savings:** Windows Server VMs → up to 40% off. SQL Server → up to 55% off.

---

## Spot VMs

Use spare Azure capacity at up to 90% discount. Can be evicted with 30 seconds notice.

```bash
# Create Spot VM
az vm create \
  --name spot-vm \
  --resource-group myapp-dev-rg \
  --image Ubuntu2204 \
  --size Standard_D4s_v5 \
  --priority Spot \
  --eviction-policy Deallocate \
  --max-price 0.10 \
  --admin-username azureuser \
  --ssh-key-values ~/.ssh/id_rsa.pub

# Spot in VMSS
az vmss create \
  --name spot-vmss \
  --resource-group myapp-dev-rg \
  --image Ubuntu2204 \
  --vm-sku Standard_D4s_v5 \
  --priority Spot \
  --eviction-policy Deallocate \
  --max-price -1  # -1 = pay current spot price (never exceed on-demand price)
```

**Eviction policies:**
- `Deallocate` — VM stops but disk/config kept (can restart when capacity available)
- `Delete` — VM and disk completely removed

---

## Tagging for Cost Allocation

```bash
# Tag a resource group
az group update \
  --name myapp-prod-rg \
  --tags Environment=production Team=platform CostCenter=engineering

# Tag individual resources
az resource tag \
  --ids $(az vm show -g myapp-prod-rg -n my-vm --query id -o tsv) \
  --tags Environment=production Service=api

# Tag via policy (enforce tags on all resources)
az policy assignment create \
  --name require-env-tag \
  --policy "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025" \
  --scope /subscriptions/<sub-id> \
  --params '{"tagName": {"value": "Environment"}}'

# List resources without a specific tag
az resource list \
  --query "[?tags.Environment==null].{Name:name, Type:type, RG:resourceGroup}" \
  --output table
```

**Activate tags for cost reporting:** Azure Portal → Cost Management → Cost Analysis → Group by Tag.

---

## Cost Optimisation Checklist

### Compute
```
[ ] Right-size VMs (Advisor recommendations)
[ ] Deallocate dev/test VMs nights and weekends (~70% savings)
[ ] Use Spot VMs for batch jobs, CI/CD agents (~90% savings)
[ ] Enable auto-shutdown on dev VMs
[ ] Use Savings Plans + Reservations for production
[ ] Enable Azure Hybrid Benefit (Windows/SQL licences)
[ ] Use Burstable VMs (B-series) for low-CPU workloads
[ ] Consider Container Apps/Functions instead of always-on VMs
```

### Storage
```
[ ] Set lifecycle policies on Blob Storage (cool → archive → delete)
[ ] Delete unattached managed disks (Advisor will flag these)
[ ] Use LRS instead of GRS for non-critical data
[ ] Enable Blob Storage soft delete and versioning cautiously (adds storage cost)
[ ] Clean up old snapshots
```

### Database
```
[ ] Stop dev/test databases when not in use
[ ] Use Azure SQL Serverless (auto-pauses when idle)
[ ] Delete old automated backups (check retention policy)
[ ] Use Cosmos DB autoscale to avoid over-provisioning
[ ] Purchase reservations for production databases
```

### Network
```
[ ] Delete unused public IP addresses (~$3.65/month each)
[ ] Minimise cross-region data transfer
[ ] Use Azure CDN to reduce origin egress
[ ] Delete unused load balancers, VPN gateways
```

---

## Quick Reference

```bash
# Budgets
az consumption budget create --budget-name x --amount 1000 --time-grain Monthly

# Advisor
az advisor recommendation list --category Cost --output table

# Reservations
az reservations reservation list --output table

# Spot VMs
az vm create --priority Spot --eviction-policy Deallocate --max-price 0.10

# Hybrid Benefit
az vm update --license-type Windows_Server

# Tagging
az group update --tags Environment=production Team=platform
az resource tag --ids <resource-id> --tags Environment=production

Key tools:    Cost Management + Billing, Azure Advisor, Reservations, Savings Plans
Key savings:  Spot (90%), Reservations (60%), Savings Plans (37%), Hybrid Benefit (55%)
Key strategy: tag everything → right-size → reserve steady-state → spot for batch
```
