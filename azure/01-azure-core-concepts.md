# Azure Core Concepts 🌍

> Part of my DevOps journey — azure folder

---

## Global Infrastructure

### Regions

A region is a geographic area containing one or more data centres. Azure has 60+ regions globally — more than any other cloud provider.

```
eastus          → East US (Virginia)
eastus2         → East US 2 (Virginia)
westus2         → West US 2 (Washington)
westeurope      → West Europe (Netherlands)
northeurope     → North Europe (Ireland)
uksouth         → UK South (London)
centralindia    → Central India (Pune)
australiaeast   → Australia East (New South Wales)
```

**Paired regions:** Every Azure region is paired with another region in the same geography for disaster recovery. If a regional outage occurs, services fail over to the paired region. Example: East US ↔ West US, UK South ↔ UK West.

### Availability Zones

Like AWS AZs — physically separate data centres within a region, connected by low-latency private links. Not all regions have AZs.

```
East US
├── Zone 1 ← separate building, independent power/cooling
├── Zone 2
└── Zone 3
```

### Availability Sets (Legacy)

Before AZs existed, Availability Sets provided HA within a single data centre by spreading VMs across:
- **Fault Domains** — separate physical racks (different power/switch)
- **Update Domains** — staggered maintenance windows

Use AZs for new workloads. Availability Sets are legacy.

---

## Management Hierarchy

```
Azure AD Tenant
└── Root Management Group
    └── Management Groups (optional grouping)
        └── Subscriptions         ← billing boundary, access boundary
            └── Resource Groups   ← logical container for related resources
                └── Resources     ← VMs, storage accounts, databases, etc.
```

### Subscriptions

A subscription is the **billing and access boundary**. All resources belong to a subscription. Costs are aggregated per subscription. You can have multiple subscriptions in one tenant (dev, staging, prod).

```bash
# List subscriptions
az account list --output table

# Set active subscription
az account set --subscription "My Production Subscription"
# or
az account set --subscription "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
```

### Resource Groups

A **logical container** that groups related resources (VMs, databases, networking) for a solution. Resources in a group share a lifecycle — you can deploy, update, and delete them as a group.

```bash
# Create resource group
az group create \
  --name myapp-prod-rg \
  --location eastus \
  --tags Environment=production Team=platform

# List resource groups
az group list --output table

# Delete resource group (deletes ALL resources inside!)
az group delete --name myapp-prod-rg --yes
```

**Best practice:** One resource group per application/environment.
```
myapp-prod-rg    → all production resources for myapp
myapp-staging-rg → all staging resources
shared-rg        → shared services (ACR, Key Vault)
network-rg       → VNets, NSGs, route tables
```

### Management Groups

Group multiple subscriptions for governance. Apply Azure Policy and RBAC at the management group level — inherited by all child subscriptions.

```
Root Management Group
├── Corp MG
│   ├── Production Subscription
│   └── Staging Subscription
├── Dev MG
│   └── Dev Subscription
└── Sandbox MG
    └── Sandbox Subscription
```

---

## Azure Resource Manager (ARM)

ARM is the **deployment and management layer** for Azure — every operation (portal, CLI, PowerShell, SDK, Terraform) goes through ARM.

```
You (Portal / CLI / Terraform)
         ↓
   ARM (authenticates, authorises, routes)
         ↓
Azure Services (Compute, Storage, Network, etc.)
```

**ARM Templates** — JSON files declaring infrastructure (Azure's native IaC):
```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "resources": [
    {
      "type": "Microsoft.Storage/storageAccounts",
      "apiVersion": "2023-01-01",
      "name": "mystorageaccount",
      "location": "[resourceGroup().location]",
      "sku": { "name": "Standard_LRS" },
      "kind": "StorageV2"
    }
  ]
}
```

**Bicep** — cleaner, Azure-native IaC language that compiles to ARM:
```bicep
resource storageAccount 'Microsoft.Storage/storageAccounts@2023-01-01' = {
  name: 'mystorageaccount'
  location: resourceGroup().location
  sku: { name: 'Standard_LRS' }
  kind: 'StorageV2'
}
```

---

## Shared Responsibility Model

Same concept as AWS but Azure-specific:

```
Microsoft manages:            You manage:
├── Physical data centres     ├── Data & encryption
├── Network hardware          ├── Applications
├── Host infrastructure       ├── OS (on IaaS/VMs)
├── Virtualisation layer      ├── Identity & access (Entra ID)
└── PaaS/SaaS runtime         ├── Network config (VNet, NSG)
                              └── Compliance requirements
```

---

## Azure Service Categories

```
Compute          → VMs, VMSS, App Service, Functions, AKS, Container Apps
Storage          → Blob, Files, Disks, Tables, Queues
Databases        → Azure SQL, Cosmos DB, PostgreSQL, MySQL, Redis
Networking       → VNet, Load Balancer, Application Gateway, VPN, ExpressRoute
Identity         → Entra ID (Azure AD), RBAC, Managed Identities
DevOps           → Azure DevOps, GitHub Actions, Container Registry
Monitoring       → Azure Monitor, Log Analytics, Application Insights
Security         → Key Vault, Defender for Cloud, Sentinel, DDoS Protection
AI/ML            → Azure OpenAI, Cognitive Services, ML Studio
Messaging        → Service Bus, Event Grid, Event Hubs
```

---

## Naming Conventions

Azure resources have strict naming rules (length, allowed characters, global uniqueness for some).

```
Pattern: {workload}-{env}-{region}-{type}-{instance}

Examples:
  myapp-prod-eus-rg-001       → resource group
  myapp-prod-eus-vnet-001     → virtual network
  myapp-prod-eus-vm-001       → virtual machine
  myappprodstorage001         → storage account (no hyphens, globally unique)
  myapp-prod-eus-aks-001      → AKS cluster
```

---

## Azure Pricing Model

```
Pay-as-you-go:    no commitment, most expensive
Reservations:     1 or 3 year commit, up to 72% discount
Savings Plans:    1 or 3 year commit, flexible (like AWS Savings Plans)
Spot VMs:         unused capacity, up to 90% off, can be evicted
Dev/Test pricing: reduced rates for non-production workloads
```

---

## Quick Reference

```
Region:           geographic area (eastus, westeurope)
AZ:               isolated DC within region (Zone 1/2/3)
Paired region:    DR failover partner region
Tenant:           Azure AD / Entra ID boundary
Subscription:     billing + access boundary
Resource Group:   logical container, shared lifecycle
ARM:              deployment + management layer for all Azure resources
Bicep:            cleaner Azure-native IaC (preferred over raw ARM JSON)

az account list           → list subscriptions
az account set            → switch subscription
az group create           → create resource group
az group list             → list resource groups
az group delete           → delete resource group + all resources
```
