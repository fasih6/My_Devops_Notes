# Azure CLI & PowerShell 🖥️

> Part of my DevOps journey — azure folder

---

## Azure CLI (az)

The primary cross-platform CLI for managing Azure. Works on Linux, macOS, Windows.

### Installation

```bash
# Linux (Ubuntu/Debian)
curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash

# macOS
brew install azure-cli

# Verify
az --version
```

### Authentication

```bash
# Interactive login (browser-based)
az login

# Login with service principal (CI/CD)
az login \
  --service-principal \
  --username <app-id> \
  --password <client-secret> \
  --tenant <tenant-id>

# Login with managed identity (from Azure VM, ACI, etc.)
az login --identity

# Login with federated token (GitHub Actions OIDC)
# Handled automatically by azure/login@v1 action

# Check current login
az account show
az account list --output table

# Switch subscription
az account set --subscription "My Subscription"
az account set --subscription "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"

# Logout
az logout
```

### Output Formats

```bash
az vm list --output json      # JSON (default, pipe to jq)
az vm list --output table     # Human-readable table
az vm list --output tsv       # Tab-separated (for shell scripting)
az vm list --output yaml      # YAML
az vm list --output jsonc     # JSON with color
```

### Querying with JMESPath

```bash
# Get VM names
az vm list --query "[].name" --output tsv

# Get name + location + status
az vm list --query "[].{Name:name, Location:location, State:powerState}" --output table

# Filter running VMs
az vm list \
  --query "[?powerState=='VM running'].name" \
  --output tsv

# Get first VM's public IP
az vm show \
  --name my-vm \
  --resource-group myapp-prod-rg \
  --query publicIps \
  --show-details \
  --output tsv

# Get storage account endpoints
az storage account show \
  --name myappstorage \
  --resource-group myapp-prod-rg \
  --query primaryEndpoints \
  --output json
```

### Common CLI Commands

```bash
# ── Account & Subscription ─────────────────────────────────
az account show
az account list
az account set --subscription x
az account get-access-token          # get JWT token for current user

# ── Resource Groups ────────────────────────────────────────
az group create --name rg --location eastus
az group list --output table
az group delete --name rg --yes

# ── Identity ───────────────────────────────────────────────
az ad user list --output table
az ad sp create-for-rbac --name x --role Contributor --scopes /subscriptions/...
az identity create --name x --resource-group rg
az role assignment create --assignee x --role Contributor --scope /subscriptions/...
az role assignment list --resource-group rg

# ── VMs ────────────────────────────────────────────────────
az vm create --name x --resource-group rg --image Ubuntu2204 --size Standard_D2s_v5
az vm list --output table
az vm start / stop / deallocate / restart / delete --name x -g rg
az vm show --name x -g rg --query publicIps --show-details -d

# ── Networking ─────────────────────────────────────────────
az network vnet create --name x --resource-group rg --address-prefix 10.0.0.0/16
az network vnet subnet create --name x --vnet-name v -g rg --address-prefix 10.0.1.0/24
az network nsg create --name x -g rg
az network nsg rule create --name x --nsg-name n -g rg --priority 100 --direction Inbound ...

# ── Storage ────────────────────────────────────────────────
az storage account create --name x -g rg --sku Standard_LRS --kind StorageV2
az storage container create --name x --account-name x
az storage blob upload --container-name x --name path --file ./file -a x
az storage blob list --container-name x --account-name x --output table

# ── AKS ────────────────────────────────────────────────────
az aks create --name x -g rg --node-count 3 --node-vm-size Standard_D4s_v5
az aks get-credentials --name x -g rg
az aks nodepool add --name x --cluster-name c -g rg
az aks upgrade --name x -g rg --kubernetes-version 1.29
az aks delete --name x -g rg --yes

# ── Functions ──────────────────────────────────────────────
az functionapp create --name x -g rg --storage-account x --consumption-plan-location eastus --runtime python
az functionapp config appsettings set --name x -g rg --settings KEY=VALUE
az functionapp log tail --name x -g rg

# ── Monitor ────────────────────────────────────────────────
az monitor log-analytics workspace create --workspace-name x -g rg
az monitor metrics list --resource <resource-id> --metric "Percentage CPU"
az monitor alert list -g rg --output table

# ── Key Vault ──────────────────────────────────────────────
az keyvault create --name x -g rg --sku standard
az keyvault secret set --vault-name x --name db-password --value "secret"
az keyvault secret show --vault-name x --name db-password --query value -o tsv
az keyvault secret list --vault-name x --output table
```

### CLI Tips & Tricks

```bash
# Wait for resource to be ready
az vm wait --name my-vm -g myapp-prod-rg --created
az aks wait --name my-aks -g myapp-prod-rg --created

# Dry run (what-if) for deployments
az deployment group what-if \
  --resource-group myapp-prod-rg \
  --template-file main.bicep

# Interactive mode (tab completion, docs inline)
az interactive

# Find commands
az find "create vm"
az vm create --help

# Output to file
az vm list --output json > vms.json

# Set defaults (avoid typing --resource-group and --location every time)
az configure --defaults group=myapp-prod-rg location=eastus
az configure --defaults group=   # clear defaults

# Environment variable overrides
export AZURE_SUBSCRIPTION_ID=xxxxx
export AZURE_TENANT_ID=xxxxx
```

---

## PowerShell Az Module

```powershell
# Install Az module
Install-Module -Name Az -AllowClobber -Scope CurrentUser

# Login
Connect-AzAccount
Connect-AzAccount -ServicePrincipal -Credential $cred -Tenant $tenantId

# Select subscription
Get-AzSubscription
Set-AzContext -SubscriptionId "xxxx"

# Resource Groups
New-AzResourceGroup -Name "myapp-prod-rg" -Location "East US"
Get-AzResourceGroup | Format-Table
Remove-AzResourceGroup -Name "myapp-prod-rg" -Force

# VMs
Get-AzVM | Format-Table Name, ResourceGroupName, Location
Start-AzVM -Name "my-vm" -ResourceGroupName "myapp-prod-rg"
Stop-AzVM -Name "my-vm" -ResourceGroupName "myapp-prod-rg" -Force

# Storage
$storageAccount = Get-AzStorageAccount -ResourceGroupName "myapp-prod-rg" -Name "myappstorage"
$ctx = $storageAccount.Context
Get-AzStorageBlob -Container "mycontainer" -Context $ctx

# AKS
Get-AzAksCluster | Format-Table Name, ResourceGroupName, KubernetesVersion
Import-AzAksCredential -ResourceGroupName "myapp-prod-rg" -Name "my-aks"
```

---

## ARM Templates

Azure Resource Manager JSON templates — Azure's native IaC.

```json
{
  "$schema": "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#",
  "contentVersion": "1.0.0.0",
  "parameters": {
    "vmName": { "type": "string", "defaultValue": "my-vm" },
    "location": { "type": "string", "defaultValue": "[resourceGroup().location]" },
    "adminUsername": { "type": "string" },
    "adminPassword": { "type": "secureString" }
  },
  "variables": {
    "nicName": "[concat(parameters('vmName'), '-nic')]"
  },
  "resources": [
    {
      "type": "Microsoft.Compute/virtualMachines",
      "apiVersion": "2023-07-01",
      "name": "[parameters('vmName')]",
      "location": "[parameters('location')]",
      "properties": {
        "hardwareProfile": { "vmSize": "Standard_D2s_v5" },
        "osProfile": {
          "computerName": "[parameters('vmName')]",
          "adminUsername": "[parameters('adminUsername')]",
          "adminPassword": "[parameters('adminPassword')]"
        },
        "storageProfile": {
          "imageReference": {
            "publisher": "Canonical",
            "offer": "0001-com-ubuntu-server-jammy",
            "sku": "22_04-lts-gen2",
            "version": "latest"
          }
        },
        "networkProfile": {
          "networkInterfaces": [{ "id": "[resourceId('Microsoft.Network/networkInterfaces', variables('nicName'))]" }]
        }
      }
    }
  ],
  "outputs": {
    "vmId": { "type": "string", "value": "[resourceId('Microsoft.Compute/virtualMachines', parameters('vmName'))]" }
  }
}
```

```bash
# Deploy ARM template
az deployment group create \
  --resource-group myapp-prod-rg \
  --template-file main.json \
  --parameters vmName=my-vm adminUsername=azureuser adminPassword=MyPass123!

# Preview changes (what-if)
az deployment group what-if \
  --resource-group myapp-prod-rg \
  --template-file main.json
```

---

## Bicep (Preferred over ARM JSON)

Bicep is a clean DSL that compiles to ARM JSON. Much more readable.

```bicep
// main.bicep
param vmName string = 'my-vm'
param location string = resourceGroup().location
param adminUsername string
@secure()
param adminPassword string

var nicName = '${vmName}-nic'

resource vm 'Microsoft.Compute/virtualMachines@2023-07-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_D2s_v5'
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
      adminPassword: adminPassword
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
        version: 'latest'
      }
    }
    networkProfile: {
      networkInterfaces: [{ id: nic.id }]
    }
  }
}

output vmId string = vm.id
```

```bash
# Install Bicep
az bicep install

# Compile to ARM (for inspection)
az bicep build --file main.bicep

# Deploy directly
az deployment group create \
  --resource-group myapp-prod-rg \
  --template-file main.bicep \
  --parameters adminUsername=azureuser adminPassword=MyPass123!

# Preview
az deployment group what-if \
  --resource-group myapp-prod-rg \
  --template-file main.bicep
```

---

## Quick Reference

```bash
# Auth
az login
az login --service-principal --username x --password x --tenant x
az account show / list
az account set --subscription x

# Defaults
az configure --defaults group=rg location=eastus

# Querying
--output json|table|tsv|yaml
--query "[].name"
--query "[?location=='eastus'].{Name:name}"

# Deployment
az deployment group create --template-file main.bicep --parameters key=value
az deployment group what-if --template-file main.bicep

# Key Vault
az keyvault create --name x -g rg
az keyvault secret set --vault-name x --name y --value z
az keyvault secret show --vault-name x --name y --query value -o tsv

az find "keyword"         → find CLI commands
az <command> --help       → get help
az interactive            → interactive mode with autocomplete
```
