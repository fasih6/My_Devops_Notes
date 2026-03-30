# Azure Security — Key Vault, Defender & More 🔒

> Part of my DevOps journey — azure folder

---

## Azure Security Layers

```
┌─────────────────────────────────────────────┐
│  Identity & Access    Entra ID, RBAC, PIM   │
├─────────────────────────────────────────────┤
│  Network Security     NSG, Firewall, WAF,   │
│                       DDoS, Private Endpoints│
├─────────────────────────────────────────────┤
│  Data Protection      Key Vault, Encryption, │
│                       Backup                 │
├─────────────────────────────────────────────┤
│  Threat Detection     Defender for Cloud,    │
│                       Sentinel               │
├─────────────────────────────────────────────┤
│  Governance           Policy, Blueprints,    │
│                       Management Groups      │
└─────────────────────────────────────────────┘
```

---

## Azure Key Vault

Centralised **secrets, keys, and certificates management**. Equivalent to AWS Secrets Manager + KMS combined.

```bash
# Create Key Vault
az keyvault create \
  --name myapp-kv \
  --resource-group myapp-prod-rg \
  --location germanywestcentral \
  --sku standard \
  --enable-rbac-authorization true \       # use RBAC (recommended over access policies)
  --enable-soft-delete true \
  --soft-delete-retention-days 90 \
  --enable-purge-protection true           # prevents permanent deletion for retention period

# Grant access via RBAC (preferred)
az role assignment create \
  --assignee <user-or-sp-object-id> \
  --role "Key Vault Secrets User" \        # read secrets
  --scope $(az keyvault show -n myapp-kv -g myapp-prod-rg --query id -o tsv)

az role assignment create \
  --assignee <admin-object-id> \
  --role "Key Vault Administrator" \       # full access
  --scope $(az keyvault show -n myapp-kv -g myapp-prod-rg --query id -o tsv)
```

### Secrets

```bash
# Create secret
az keyvault secret set \
  --vault-name myapp-kv \
  --name db-password \
  --value "MySecurePassword123!"

# Create from file
az keyvault secret set \
  --vault-name myapp-kv \
  --name ssl-certificate \
  --file ./cert.pem

# Get secret value
az keyvault secret show \
  --vault-name myapp-kv \
  --name db-password \
  --query value -o tsv

# List secrets
az keyvault secret list \
  --vault-name myapp-kv \
  --output table

# Set expiration
az keyvault secret set-attributes \
  --vault-name myapp-kv \
  --name db-password \
  --expires "2025-12-31T00:00:00Z"

# Soft-delete and recover
az keyvault secret delete --vault-name myapp-kv --name db-password
az keyvault secret recover --vault-name myapp-kv --name db-password
az keyvault secret purge --vault-name myapp-kv --name db-password   # permanent (requires purge protection disabled)
```

### Keys (Encryption Keys)

```bash
# Create RSA key
az keyvault key create \
  --vault-name myapp-kv \
  --name myapp-encryption-key \
  --kty RSA \
  --size 4096 \
  --ops encrypt decrypt sign verify

# Create encryption key for Customer-Managed Key (CMK)
az keyvault key create \
  --vault-name myapp-kv \
  --name storage-cmk \
  --kty RSA \
  --size 2048 \
  --protection software

# Enable CMK on Storage Account
az storage account update \
  --name myappstorage \
  --resource-group myapp-prod-rg \
  --encryption-key-source Microsoft.Keyvault \
  --encryption-key-vault https://myapp-kv.vault.azure.net \
  --encryption-key-name storage-cmk \
  --encryption-key-version $(az keyvault key show \
    --vault-name myapp-kv --name storage-cmk --query key.kid -o tsv | cut -d'/' -f6)
```

### Certificates

```bash
# Create self-signed certificate
az keyvault certificate create \
  --vault-name myapp-kv \
  --name myapp-ssl-cert \
  --policy "$(az keyvault certificate get-default-policy)"

# Import existing certificate
az keyvault certificate import \
  --vault-name myapp-kv \
  --name myapp-ssl-cert \
  --file ./certificate.pfx \
  --password "PfxPassword123"

# Download certificate
az keyvault certificate download \
  --vault-name myapp-kv \
  --name myapp-ssl-cert \
  --file ./cert.pem \
  --encoding PEM
```

### Key Vault in Applications

```python
# Python — access Key Vault with Managed Identity
from azure.identity import DefaultAzureCredential
from azure.keyvault.secrets import SecretClient

credential = DefaultAzureCredential()   # uses Managed Identity automatically in Azure
client = SecretClient(
    vault_url="https://myapp-kv.vault.azure.net",
    credential=credential
)

secret = client.get_secret("db-password")
print(secret.value)
```

```yaml
# Reference Key Vault in App Service / Function App config
# In app settings: @Microsoft.KeyVault(SecretUri=...)
az webapp config appsettings set \
  --name myapp-webapp \
  --resource-group myapp-prod-rg \
  --settings "DB_PASSWORD=@Microsoft.KeyVault(VaultName=myapp-kv;SecretName=db-password)"
```

### Private Endpoint for Key Vault

```bash
# Disable public access
az keyvault update \
  --name myapp-kv \
  --resource-group myapp-prod-rg \
  --public-network-access Disabled

# Create private endpoint
az network private-endpoint create \
  --name kv-private-endpoint \
  --resource-group myapp-prod-rg \
  --vnet-name myapp-vnet \
  --subnet app-subnet \
  --private-connection-resource-id $(az keyvault show \
    -n myapp-kv -g myapp-prod-rg --query id -o tsv) \
  --connection-name kv-conn \
  --group-id vault
```

---

## Microsoft Defender for Cloud

Unified **Cloud Security Posture Management (CSPM)** + **Cloud Workload Protection Platform (CWPP)**. Equivalent to AWS Security Hub + GuardDuty combined.

```bash
# Enable Defender for Cloud (basic — free)
az security auto-provisioning-setting update \
  --name mma \
  --auto-provision On

# Enable enhanced protection plans
az security pricing create \
  --name VirtualMachines \
  --tier Standard        # paid plan

az security pricing create --name SqlServers --tier Standard
az security pricing create --name AppServices --tier Standard
az security pricing create --name Containers --tier Standard     # covers AKS
az security pricing create --name KeyVaults --tier Standard
az security pricing create --name Dns --tier Standard
az security pricing create --name StorageAccounts --tier Standard

# View security recommendations
az security assessment list --output table

# View alerts
az security alert list --output table

# Get Secure Score
az security secure-score-controls list --output table
```

### Defender Plans

| Plan | Protects | Key Features |
|------|---------|-------------|
| **Defender for Servers** | VMs, on-prem | Vulnerability assessment, JIT VM access, adaptive controls |
| **Defender for Containers** | AKS, ACR | Image scanning, K8s threat detection, registry scanning |
| **Defender for SQL** | Azure SQL, SQL Server | SQL injection detection, anomalous access |
| **Defender for Storage** | Blob, Files | Malware scanning, anomaly detection, data exfiltration alerts |
| **Defender for Key Vault** | Key Vault | Suspicious access patterns, unusual geo alerts |
| **Defender for App Service** | App Service | Web attack detection |

### Just-In-Time (JIT) VM Access

Locks down SSH/RDP ports and opens them only when requested, for a limited time.

```bash
# Enable JIT on VM
az security jit-policy create \
  --resource-group myapp-prod-rg \
  --resource-name my-vm \
  --resource-type Microsoft.Compute/virtualMachines \
  --location germanywestcentral \
  --kind Basic

# Request JIT access (opens port for 3 hours)
az security jit-policy initiate \
  --resource-group myapp-prod-rg \
  --resource-name my-vm \
  --resource-type Microsoft.Compute/virtualMachines \
  --location germanywestcentral
```

---

## Azure Policy

Enforce organisational standards at scale. Evaluate resources for compliance and automatically remediate non-compliant ones.

```bash
# List built-in policies
az policy definition list --query "[?policyType=='BuiltIn'].{Name:displayName, Id:name}" \
  --output table | head -20

# Assign policy: require tags
az policy assignment create \
  --name require-environment-tag \
  --display-name "Require Environment tag on all resources" \
  --policy "96670d01-0a4d-4649-9c89-2d3abc0a5025" \
  --scope /subscriptions/<sub-id> \
  --params '{"tagName": {"value": "Environment"}}'

# Assign policy: allowed locations (GDPR — restrict to Germany)
az policy assignment create \
  --name allowed-locations \
  --display-name "Restrict resources to Germany" \
  --policy "e56962a6-4747-49cd-b67b-bf8b01975c4f" \
  --scope /subscriptions/<sub-id> \
  --params '{"listOfAllowedLocations": {"value": ["germanywestcentral", "germanynorth"]}}'

# Assign policy: require HTTPS on storage
az policy assignment create \
  --name storage-https-only \
  --policy "404c3081-a854-4457-ae30-26a93ef643f9" \
  --scope /subscriptions/<sub-id>

# Check compliance state
az policy state list \
  --subscription <sub-id> \
  --filter "complianceState eq 'NonCompliant'" \
  --output table

# Create remediation task (fix non-compliant resources)
az policy remediation create \
  --name fix-storage-https \
  --policy-assignment storage-https-only \
  --resource-group myapp-prod-rg
```

### Policy Initiatives (Policy Sets)

Group multiple policies into one assignment.

```bash
# Assign Azure Security Benchmark initiative
az policy assignment create \
  --name azure-security-benchmark \
  --policy-set-definition "1f3afdf9-d0c9-4c3d-847f-89da613e70a8" \
  --scope /subscriptions/<sub-id>
```

### Custom Policy

```json
{
  "mode": "All",
  "displayName": "Require specific VM sizes",
  "policyRule": {
    "if": {
      "allOf": [
        { "field": "type", "equals": "Microsoft.Compute/virtualMachines" },
        {
          "not": {
            "field": "Microsoft.Compute/virtualMachines/sku.name",
            "in": ["Standard_D2s_v5", "Standard_D4s_v5", "Standard_D8s_v5"]
          }
        }
      ]
    },
    "then": { "effect": "deny" }
  }
}
```

---

## Microsoft Sentinel

**Cloud-native SIEM + SOAR** — collect security events, detect threats with ML, investigate and respond.

```bash
# Enable Sentinel on Log Analytics workspace
az sentinel workspace create \
  --workspace-name myapp-logs \
  --resource-group myapp-prod-rg

# Connect data connectors (Azure Activity, Entra ID, etc.)
az sentinel data-connector create \
  --workspace-name myapp-logs \
  --resource-group myapp-prod-rg \
  --data-connector-id AzureActiveDirectory \
  --etag "*"
```

**Key capabilities:**
- Collect data from Azure, on-prem, multi-cloud, SaaS
- Built-in analytics rules (detect known attack patterns)
- ML-based anomaly detection
- Investigation graph (visualise attack paths)
- Automated playbooks (Logic Apps) for response

---

## DDoS Protection

```bash
# Enable DDoS Network Protection on VNet (Standard plan)
az network ddos-protection create \
  --name myapp-ddos-plan \
  --resource-group myapp-prod-rg \
  --location germanywestcentral

az network vnet update \
  --name myapp-vnet \
  --resource-group myapp-prod-rg \
  --ddos-protection-plan myapp-ddos-plan \
  --ddos-protection true
```

| Plan | Protection | Cost |
|------|-----------|------|
| **Basic** (default) | Infrastructure-level protection | Free |
| **Network** | Enhanced, per-VNet, adaptive tuning, attack analytics | ~$2,944/month |
| **IP** | Per public IP protection | ~$199/IP/month |

---

## Private Endpoints

Access Azure services from your VNet without going over the internet. Eliminates public exposure.

```bash
# Private endpoint for Storage Account
az network private-endpoint create \
  --name storage-private-ep \
  --resource-group myapp-prod-rg \
  --vnet-name myapp-vnet \
  --subnet app-subnet \
  --private-connection-resource-id $(az storage account show \
    -n myappstorage -g myapp-prod-rg --query id -o tsv) \
  --connection-name storage-conn \
  --group-id blob

# Private DNS zone for blob (so FQDN resolves to private IP)
az network private-dns zone create \
  --name privatelink.blob.core.windows.net \
  --resource-group myapp-prod-rg

az network private-dns link vnet create \
  --zone-name privatelink.blob.core.windows.net \
  --resource-group myapp-prod-rg \
  --name myapp-vnet-link \
  --virtual-network myapp-vnet \
  --registration-enabled false

# Disable public access on storage
az storage account update \
  --name myappstorage \
  --resource-group myapp-prod-rg \
  --public-network-access Disabled
```

---

## Security Checklist

### Identity
```
[ ] Enable MFA for all human users
[ ] No account sharing — one identity per person
[ ] Service Principals use federated credentials (no client secrets where possible)
[ ] Use Managed Identities for Azure services (no stored credentials)
[ ] Enable Privileged Identity Management (PIM) for admin roles (JIT elevation)
[ ] Review and remove unused role assignments quarterly
```

### Network
```
[ ] All subnets have NSGs
[ ] No * source in NSG inbound rules for SSH/RDP
[ ] Use Azure Bastion for VM access (no public SSH/RDP)
[ ] Private Endpoints for Key Vault, Storage, databases
[ ] Disable public access on Storage Accounts, Key Vaults
[ ] Enable DDoS Protection Standard for production
[ ] WAF enabled on Application Gateway / Front Door
```

### Data
```
[ ] Encryption at rest enabled (all services — default in Azure)
[ ] Customer-Managed Keys for sensitive data
[ ] Key Vault soft-delete + purge protection enabled
[ ] Storage soft delete enabled
[ ] Backup strategy in place (Azure Backup)
[ ] No secrets in code or environment variables (use Key Vault)
```

### Monitoring
```
[ ] Defender for Cloud enabled (at least free tier)
[ ] Enhanced plans enabled for critical services (Servers, Containers, SQL)
[ ] Diagnostic logs sent to Log Analytics
[ ] Alerts on critical security events
[ ] Microsoft Sentinel for SIEM (if enterprise)
[ ] Activity Log retention ≥ 90 days
```

---

## Quick Reference

```bash
# Key Vault
az keyvault create --name x -g rg --enable-rbac-authorization true --enable-purge-protection
az keyvault secret set --vault-name x --name y --value z
az keyvault secret show --vault-name x --name y --query value -o tsv
az keyvault secret list --vault-name x --output table

# RBAC on Key Vault
az role assignment create --assignee x --role "Key Vault Secrets User" --scope <kv-id>

# Defender
az security pricing create --name VirtualMachines --tier Standard
az security assessment list --output table
az security alert list --output table

# Policy
az policy assignment create --name x --policy <id> --scope /subscriptions/<sub>
az policy state list --filter "complianceState eq 'NonCompliant'"
az policy remediation create --name x --policy-assignment x

# Private Endpoints
az network private-endpoint create --name x --vnet-name v --subnet s \
  --private-connection-resource-id <resource-id> --group-id blob

Key services:
  Key Vault     = secrets + keys + certs (AWS Secrets Manager + KMS)
  Defender      = CSPM + threat protection (AWS Security Hub + GuardDuty)
  Sentinel      = SIEM + SOAR
  Policy        = enforce standards + compliance
  Private Endpoints = private access to Azure services (no internet)
  DDoS Standard = volumetric attack protection
  JIT VM Access = time-limited SSH/RDP access
```
