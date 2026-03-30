# Azure Real-World Patterns 🏗️

> Part of my DevOps journey — azure folder

---

## Pattern 1: Classic 3-Tier Web Architecture

```
Internet
    ↓
Azure DNS (myapp.com)
    ↓
Azure Front Door (global CDN + WAF + routing)
    ↓
┌─────────────────────────────────────────────┐
│  VNet: 10.0.0.0/16  (East US)               │
│                                              │
│  ┌──────────────────────────────────────┐   │
│  │ Application Gateway Subnet           │   │
│  │ Application Gateway + WAF v2         │   │
│  └──────────────┬───────────────────────┘   │
│                 ↓                            │
│  ┌──────────────────────────────────────┐   │
│  │ App Subnet (AZ1, AZ2, AZ3)          │   │
│  │ VMSS (Ubuntu, App code)             │   │
│  │ or AKS node pool                    │   │
│  └──────────────┬───────────────────────┘   │
│                 ↓                            │
│  ┌──────────────────────────────────────┐   │
│  │ DB Subnet                            │   │
│  │ Azure SQL / PostgreSQL (Zone-redundant│   │
│  │ Azure Cache for Redis                │   │
│  └──────────────────────────────────────┘   │
└─────────────────────────────────────────────┘
```

**Supporting services:**
- Key Vault — secrets, certs, encryption keys
- Azure Monitor + Log Analytics — metrics and logs
- Application Insights — app performance monitoring
- Defender for Cloud — security posture

**Terraform module structure:**
```hcl
module "vnet"     { source = "Azure/vnet/azurerm" }
module "appgw"    { source = "Azure/application-gateway/azurerm" }
module "vmss"     { source = "Azure/compute/azurerm" }
module "sql"      { source = "Azure/database/azurerm" }
module "redis"    { source = "Azure/redis/azurerm" }
module "keyvault" { source = "Azure/keyvault/azurerm" }
```

---

## Pattern 2: Microservices on AKS with GitOps

```
Developers
  ↓ push code
GitHub (app repos)
  ↓ GitHub Actions
  → build Docker image
  → push to ACR
  → update image tag in config repo (Helm values)
Config Repo (Helm charts / K8s manifests)
  ↓ ArgoCD / Flux detects change
AKS Cluster
  ├── Namespace: frontend     (React, Nginx)
  ├── Namespace: api          (Node.js, Go)
  ├── Namespace: payments     (Java)
  └── Namespace: data-workers (Python)

Supporting infrastructure:
  Azure DNS → Ingress NGINX → Services → Pods
  ACR → AKS (pull via managed identity)
  Key Vault → CSI driver → K8s Secrets → Pods
  Azure Monitor + Container Insights → dashboards
  Application Insights → distributed tracing
```

**GitHub Actions pipeline:**
```yaml
name: Build and Deploy

on:
  push:
    branches: [main]

env:
  ACR_NAME: myappregistry
  IMAGE_NAME: myapp
  AKS_CLUSTER: my-aks
  RESOURCE_GROUP: myapp-prod-rg

jobs:
  build-push:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Build and push to ACR
        run: |
          az acr build \
            --registry $ACR_NAME \
            --image $IMAGE_NAME:${{ github.sha }} \
            .

      - name: Update Helm values
        run: |
          # Update image tag in config repo
          git clone https://github.com/myorg/myapp-config.git
          cd myapp-config
          sed -i "s/tag: .*/tag: ${{ github.sha }}/" helm/myapp/values-prod.yaml
          git commit -am "chore: update myapp to ${{ github.sha }}"
          git push
          # ArgoCD detects this change and syncs to AKS
```

---

## Pattern 3: Azure DevOps CI/CD Pipeline

Azure DevOps (ADO) is Microsoft's integrated DevOps platform — repos, pipelines, boards, artifacts.

```yaml
# azure-pipelines.yml
trigger:
  branches:
    include: [main]

variables:
  acrName: 'myappregistry'
  aksCluster: 'my-aks'
  resourceGroup: 'myapp-prod-rg'
  imageName: 'myapp'
  tag: '$(Build.BuildId)'

stages:
- stage: Build
  jobs:
  - job: BuildPush
    pool:
      vmImage: ubuntu-latest
    steps:
    - task: AzureCLI@2
      displayName: 'Build and push to ACR'
      inputs:
        azureSubscription: 'my-service-connection'
        scriptType: bash
        scriptLocation: inlineScript
        inlineScript: |
          az acr build \
            --registry $(acrName) \
            --image $(imageName):$(tag) \
            .

- stage: Test
  dependsOn: Build
  jobs:
  - job: RunTests
    pool:
      vmImage: ubuntu-latest
    steps:
    - script: npm ci && npm test
      displayName: 'Run unit tests'
    - task: PublishTestResults@2
      inputs:
        testResultsFiles: '**/test-results.xml'

- stage: DeployStaging
  dependsOn: Test
  jobs:
  - deployment: DeployToStaging
    environment: staging
    pool:
      vmImage: ubuntu-latest
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureCLI@2
            displayName: 'Deploy to AKS staging'
            inputs:
              azureSubscription: 'my-service-connection'
              scriptType: bash
              scriptLocation: inlineScript
              inlineScript: |
                az aks get-credentials -n $(aksCluster) -g $(resourceGroup)
                helm upgrade myapp ./helm/myapp \
                  --namespace staging \
                  --set image.tag=$(tag) \
                  --wait

- stage: DeployProduction
  dependsOn: DeployStaging
  jobs:
  - deployment: DeployToProduction
    environment: production  # requires approval in ADO
    pool:
      vmImage: ubuntu-latest
    strategy:
      runOnce:
        deploy:
          steps:
          - task: AzureCLI@2
            displayName: 'Deploy to AKS production'
            inputs:
              azureSubscription: 'my-service-connection'
              scriptType: bash
              scriptLocation: inlineScript
              inlineScript: |
                helm upgrade myapp ./helm/myapp \
                  --namespace production \
                  --set image.tag=$(tag) \
                  --wait
```

---

## Pattern 4: Event-Driven Microservices

```
Order Service (Container App)
  ↓ publishes OrderPlaced event
Service Bus Topic: order-events
  ├── Subscription: payments    → Azure Function → Stripe
  ├── Subscription: inventory   → Azure Function → DynamoDB
  ├── Subscription: email       → Azure Function → SendGrid
  └── Subscription: analytics   → Event Hub → Stream Analytics → Synapse
```

```bicep
// Service Bus with topic and subscriptions
resource serviceBus 'Microsoft.ServiceBus/namespaces@2022-10-01-preview' = {
  name: 'myapp-servicebus'
  location: location
  sku: { name: 'Premium' }
}

resource ordersTopic 'Microsoft.ServiceBus/namespaces/topics@2022-10-01-preview' = {
  parent: serviceBus
  name: 'order-events'
}

resource paymentsSub 'Microsoft.ServiceBus/namespaces/topics/subscriptions@2022-10-01-preview' = {
  parent: ordersTopic
  name: 'payments-sub'
}
```

---

## Pattern 5: Disaster Recovery

### Active-Passive (Pilot Light) with Azure Site Recovery

```
Primary Region (East US)         DR Region (West US)
  AKS + App workloads     →      Azure Site Recovery replication
  Azure SQL (primary)     →      Failover group (read replica in West US)
  Blob Storage (GRS)      →      Auto-replicated to West US
  DNS: myapp.com → EUS LB       DNS: myapp.com → WUS LB (Traffic Manager failover)
```

```bash
# Azure Traffic Manager for DNS failover
az network traffic-manager profile create \
  --name myapp-tm \
  --resource-group myapp-prod-rg \
  --routing-method Priority \
  --unique-dns-name myapp-global

az network traffic-manager endpoint create \
  --name primary-endpoint \
  --profile-name myapp-tm \
  --resource-group myapp-prod-rg \
  --type azureEndpoints \
  --priority 1 \
  --target-resource-id /subscriptions/.../publicIPAddresses/myapp-eastus-pip

az network traffic-manager endpoint create \
  --name dr-endpoint \
  --profile-name myapp-tm \
  --resource-group myapp-prod-rg \
  --type azureEndpoints \
  --priority 2 \
  --target-resource-id /subscriptions/.../publicIPAddresses/myapp-westus-pip
```

### Active-Active Multi-Region

```
Azure Front Door (global load balancer + CDN)
  ├── East US backend (full stack)
  │   └── AKS + Azure SQL primary
  └── West Europe backend (full stack)
      └── AKS + Azure SQL geo-replica

Cosmos DB Global Distribution:
  Multi-region writes → each region handles local traffic
  Sub-10ms reads worldwide
```

---

## Pattern 6: Azure Landing Zone (Enterprise)

```
Azure AD Tenant
└── Root Management Group
    ├── Platform MG
    │   ├── Identity Subscription     → Entra ID, AD DS
    │   ├── Connectivity Subscription → Hub VNet, ExpressRoute, VPN GW, Azure FW, DNS
    │   └── Management Subscription   → Monitor, Defender, Policy, Automation
    └── Landing Zones MG
        ├── Corp MG (private connectivity)
        │   ├── Production Subscription → Spoke VNet peered to Hub
        │   └── Dev/Test Subscription   → Spoke VNet peered to Hub
        └── Online MG (public-facing)
            └── Online Subscription     → Public-facing apps
```

**Hub VNet contains:**
- Azure Firewall (centralised traffic inspection)
- VPN Gateway / ExpressRoute (on-prem connectivity)
- Azure Bastion (secure VM access)
- Private DNS Zones

**Spoke VNets contain:**
- Application workloads
- Peered to Hub (for shared services and on-prem access)
- NSGs on every subnet

---

## Terraform + Azure: Best Practices

```hcl
# backend.tf — remote state in Azure Blob Storage
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "mycompanytfstate"
    container_name       = "tfstate"
    key                  = "prod/myapp/terraform.tfstate"
  }
}

# providers.tf
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# versions.tf
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 3.0"
    }
  }
}
```

---

## Quick Reference — Pattern Checklist

```
3-tier web:        DNS → Front Door → App Gateway + WAF → VMSS/AKS → Azure SQL + Redis
Microservices:     ACR → AKS + GitOps (ArgoCD/Flux) → Key Vault CSI → Azure Monitor
CI/CD ADO:         Repos → Pipelines → Environments (with approvals) → AKS
Event-driven:      Container Apps → Service Bus Topics → Functions → downstream services
DR active-passive: Traffic Manager → primary + failover region → SQL failover groups
DR active-active:  Front Door → multi-region AKS + Cosmos DB global distribution
Landing zone:      Hub-spoke VNet → Platform subs → Landing zone subs → governance via Policy
```
