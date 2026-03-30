# Azure Compute — VMs, VMSS & App Service 💻

> Part of my DevOps journey — azure folder

---

## Virtual Machines

Azure VMs are equivalent to AWS EC2 — resizable compute instances. You choose the OS, size, networking, and storage.

### VM Series (Instance Families)

| Series | Optimised for | Examples |
|--------|--------------|---------|
| **B** | Burstable, low baseline CPU | B2s, B4ms |
| **D** | General purpose, balanced | D2s_v5, D4s_v5 |
| **E** | Memory optimised | E4s_v5, E8s_v5 |
| **F** | Compute optimised | F4s_v2, F8s_v2 |
| **N** | GPU | NC6s_v3, ND40rs_v2 |
| **L** | Storage optimised (NVMe) | L8s_v3, L16s_v3 |
| **M** | Memory intensive, SAP HANA | M128s, M208ms |

**Size naming:** `Standard_D4s_v5` → Standard tier, D series, 4 vCPUs, s=premium storage, v5=5th gen.

### Purchasing Options

```
Pay-as-you-go:    per-second billing, no commitment, most expensive
Reserved (1yr):   ~40% discount
Reserved (3yr):   ~60% discount
Savings Plans:    flexible commitment ($/hour)
Spot VMs:         up to 90% off, evicted with 30s notice (different from AWS 2min)
Dev/Test:         reduced pricing for non-production (requires MSDN/Visual Studio)
```

### Creating a VM

```bash
# Create VM
az vm create \
  --name my-vm \
  --resource-group myapp-prod-rg \
  --image Ubuntu2204 \
  --size Standard_D2s_v5 \
  --admin-username azureuser \
  --ssh-key-values ~/.ssh/id_rsa.pub \
  --vnet-name myapp-vnet \
  --subnet app-subnet \
  --nsg web-nsg \
  --public-ip-sku Standard \
  --os-disk-size-gb 64 \
  --os-disk-delete-option Delete \
  --storage-sku Premium_LRS \
  --tags Environment=production Team=platform

# No public IP (private only — use Bastion to connect)
az vm create \
  --name my-private-vm \
  --resource-group myapp-prod-rg \
  --image Ubuntu2204 \
  --size Standard_D2s_v5 \
  --admin-username azureuser \
  --ssh-key-values ~/.ssh/id_rsa.pub \
  --vnet-name myapp-vnet \
  --subnet app-subnet \
  --public-ip-address ""   # no public IP
```

### VM Lifecycle

```bash
# Start / stop / restart / delete
az vm start --name my-vm --resource-group myapp-prod-rg
az vm stop --name my-vm --resource-group myapp-prod-rg    # still billed for compute!
az vm deallocate --name my-vm --resource-group myapp-prod-rg  # stops billing
az vm restart --name my-vm --resource-group myapp-prod-rg
az vm delete --name my-vm --resource-group myapp-prod-rg --yes

# List VMs
az vm list --output table
az vm list --resource-group myapp-prod-rg --output table

# Show VM details
az vm show --name my-vm --resource-group myapp-prod-rg

# Get public IP
az vm show --name my-vm --resource-group myapp-prod-rg \
  --query publicIps -d --output tsv

# VM status
az vm get-instance-view --name my-vm --resource-group myapp-prod-rg \
  --query instanceView.statuses --output table
```

> **Stop vs Deallocate:** `stop` keeps the VM allocated (still billed for compute). `deallocate` fully releases compute resources (no compute billing, only storage). Always `deallocate` for non-production.

### Custom Script Extension (Bootstrap)

```bash
az vm extension set \
  --name CustomScript \
  --publisher Microsoft.Azure.Extensions \
  --resource-group myapp-prod-rg \
  --vm-name my-vm \
  --settings '{
    "commandToExecute": "apt update && apt install -y nginx && systemctl enable nginx"
  }'
```

### VM Images

```bash
# List available images
az vm image list --output table
az vm image list --publisher Canonical --output table

# Popular images
Ubuntu2204, Ubuntu2004, Debian11, RHEL9, CentOS85Gen2
Win2022Datacenter, Win2019Datacenter

# Find latest Ubuntu image
az vm image list \
  --publisher Canonical \
  --offer 0001-com-ubuntu-server-jammy \
  --sku 22_04-lts-gen2 \
  --all --output table | tail -5
```

### VM Snapshots and Images

```bash
# Create OS disk snapshot
az snapshot create \
  --name my-vm-snapshot \
  --resource-group myapp-prod-rg \
  --source $(az vm show --name my-vm --resource-group myapp-prod-rg \
    --query storageProfile.osDisk.managedDisk.id -o tsv)

# Create generalised image (for deployment template)
az vm deallocate --name my-vm --resource-group myapp-prod-rg
az vm generalize --name my-vm --resource-group myapp-prod-rg
az image create \
  --name my-vm-image \
  --resource-group myapp-prod-rg \
  --source my-vm
```

---

## Virtual Machine Scale Sets (VMSS)

VMSS is Azure's Auto Scaling Group equivalent — automatically scale a fleet of identical VMs.

```bash
# Create VMSS
az vmss create \
  --name myapp-vmss \
  --resource-group myapp-prod-rg \
  --image Ubuntu2204 \
  --vm-sku Standard_D2s_v5 \
  --instance-count 3 \
  --admin-username azureuser \
  --ssh-key-values ~/.ssh/id_rsa.pub \
  --vnet-name myapp-vnet \
  --subnet app-subnet \
  --lb myapp-lb \
  --upgrade-policy-mode Automatic

# Configure autoscale
az monitor autoscale create \
  --resource-group myapp-prod-rg \
  --resource myapp-vmss \
  --resource-type Microsoft.Compute/virtualMachineScaleSets \
  --name myapp-autoscale \
  --min-count 2 \
  --max-count 10 \
  --count 3

# Add CPU-based scale-out rule
az monitor autoscale rule create \
  --resource-group myapp-prod-rg \
  --autoscale-name myapp-autoscale \
  --condition "Percentage CPU > 70 avg 5m" \
  --scale out 2

# Add CPU-based scale-in rule
az monitor autoscale rule create \
  --resource-group myapp-prod-rg \
  --autoscale-name myapp-autoscale \
  --condition "Percentage CPU < 30 avg 10m" \
  --scale in 1

# Scale manually
az vmss scale \
  --name myapp-vmss \
  --resource-group myapp-prod-rg \
  --new-capacity 5
```

**Upgrade policies:**
- **Automatic** — Azure immediately updates all instances
- **Rolling** — updates in batches
- **Manual** — you control when instances update

---

## App Service

**Fully managed PaaS** for hosting web apps, REST APIs, and mobile backends. No VM management. Supports: .NET, Node.js, Python, Java, PHP, Ruby, containers.

```
App Service Plan (defines compute resources)
└── Web App (your application)
```

### App Service Plans (Pricing Tiers)

| Tier | Features | Use case |
|------|---------|---------|
| **Free/Shared** | Shared infrastructure, limited | Dev/testing only |
| **Basic (B1-B3)** | Dedicated VMs, manual scale | Dev/staging |
| **Standard (S1-S3)** | Auto-scale, custom domains, SSL | Production |
| **Premium (P1v3-P3v3)** | Enhanced scale, VNet integration | High-scale production |
| **Isolated (I1v2-I3v2)** | Dedicated environment (ASE) | Compliance, max isolation |

```bash
# Create App Service Plan
az appservice plan create \
  --name myapp-plan \
  --resource-group myapp-prod-rg \
  --sku P1V3 \
  --is-linux \
  --location eastus

# Create Web App (Node.js)
az webapp create \
  --name myapp-webapp \
  --resource-group myapp-prod-rg \
  --plan myapp-plan \
  --runtime "NODE:20-lts"

# Create Web App (Docker container)
az webapp create \
  --name myapp-webapp \
  --resource-group myapp-prod-rg \
  --plan myapp-plan \
  --deployment-container-image-name myregistry.azurecr.io/myapp:latest

# Deploy code via ZIP
az webapp deployment source config-zip \
  --name myapp-webapp \
  --resource-group myapp-prod-rg \
  --src ./app.zip

# Configure app settings (env vars)
az webapp config appsettings set \
  --name myapp-webapp \
  --resource-group myapp-prod-rg \
  --settings NODE_ENV=production DATABASE_URL=@Microsoft.KeyVault(...)

# Configure custom domain
az webapp config hostname add \
  --webapp-name myapp-webapp \
  --resource-group myapp-prod-rg \
  --hostname www.myapp.com

# Enable managed identity (for Key Vault access)
az webapp identity assign \
  --name myapp-webapp \
  --resource-group myapp-prod-rg

# View logs
az webapp log tail \
  --name myapp-webapp \
  --resource-group myapp-prod-rg

# Open in browser
az webapp browse --name myapp-webapp --resource-group myapp-prod-rg
```

### App Service Deployment Slots

Blue/green deployments without downtime:

```bash
# Create staging slot
az webapp deployment slot create \
  --name myapp-webapp \
  --resource-group myapp-prod-rg \
  --slot staging

# Deploy to staging
az webapp deployment source config-zip \
  --name myapp-webapp \
  --resource-group myapp-prod-rg \
  --slot staging \
  --src ./app.zip

# Swap staging → production (zero downtime)
az webapp deployment slot swap \
  --name myapp-webapp \
  --resource-group myapp-prod-rg \
  --slot staging \
  --target-slot production
```

### App Service VNet Integration

Connect App Service to a VNet to access private resources (databases, internal APIs):

```bash
az webapp vnet-integration add \
  --name myapp-webapp \
  --resource-group myapp-prod-rg \
  --vnet myapp-vnet \
  --subnet app-subnet
```

---

## Quick Reference

```bash
# VMs
az vm create --name x --resource-group rg --image Ubuntu2204 --size Standard_D2s_v5
az vm start / stop / deallocate / restart / delete --name x --resource-group rg
az vm list --output table
az vm show --name x --resource-group rg --query publicIps -d

# VMSS
az vmss create --name x --resource-group rg --image x --instance-count 3
az vmss scale --name x --resource-group rg --new-capacity 5
az monitor autoscale create / rule create

# App Service
az appservice plan create --name x --sku P1V3 --is-linux
az webapp create --name x --plan x --runtime "NODE:20-lts"
az webapp config appsettings set --settings KEY=VALUE
az webapp deployment slot create --slot staging
az webapp deployment slot swap --slot staging --target-slot production
az webapp log tail --name x

stop = still billed | deallocate = no compute billing
```
