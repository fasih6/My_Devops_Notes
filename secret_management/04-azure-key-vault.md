# Azure Key Vault — Architecture, RBAC, AKS Integration, Rotation

## What Is Azure Key Vault?

Azure Key Vault is Azure's managed secrets management service. It stores and controls access to three types of sensitive assets:

```
┌─────────────────────────────────────────────────────────┐
│                   Azure Key Vault                        │
│                                                         │
│  SECRETS    → Arbitrary key-value pairs                 │
│               (DB passwords, API keys, connection strs) │
│                                                         │
│  KEYS       → Cryptographic keys (RSA, EC, AES)         │
│               Used for encrypt/decrypt, sign/verify     │
│               Key material never leaves Key Vault        │
│                                                         │
│  CERTIFICATES → X.509 TLS certificates                  │
│                 Lifecycle management + auto-renewal      │
└─────────────────────────────────────────────────────────┘
```

Key Vault is deeply integrated with Azure services — VMs, AKS, App Service, Azure Functions, and Azure DevOps all have native Key Vault integration.

---

## Key Vault vs Managed HSM

| Feature | Key Vault (Standard) | Key Vault (Premium) | Managed HSM |
|---------|---------------------|--------------------|-----------:|
| Secret storage | ✅ | ✅ | ❌ (keys only) |
| Software-protected keys | ✅ | ✅ | ❌ |
| HSM-protected keys | ❌ | ✅ | ✅ |
| FIPS 140-2 Level | Level 1 | Level 2 | Level 3 |
| Dedicated HSM | ❌ | ❌ | ✅ |
| Use case | General workloads | Regulated, needs HSM | Financial, PCI-DSS, HIPAA |
| Pricing | Lowest | Medium | Highest |

**When to use Managed HSM:** Compliance requirements (PCI-DSS, HIPAA, FedRAMP) that mandate FIPS 140-2 Level 3 and dedicated hardware. Most Azure workloads use Key Vault Premium.

---

## Access Control — Vault Access Policies vs RBAC

Azure Key Vault supports two access models. Understanding both is important for interviews.

### Legacy: Vault Access Policies

The original model. Permissions are set at the Key Vault level, not per-secret.

```bash
# Grant a service principal access to get/list secrets
az keyvault set-policy \
  --name my-keyvault \
  --object-id <service-principal-object-id> \
  --secret-permissions get list \
  --key-permissions get list unwrapKey wrapKey \
  --certificate-permissions get list
```

**Problems with Vault Access Policies:**
- All-or-nothing at the vault level — you can't grant access to specific secrets
- No integration with Azure Policy or Conditional Access
- Harder to audit
- Microsoft recommends migrating away from this model

### Modern: Azure RBAC (Recommended)

Uses Azure role assignments — consistent with all other Azure resource permissions.

```bash
# Enable RBAC authorization on the Key Vault
az keyvault update \
  --name my-keyvault \
  --resource-group myRG \
  --enable-rbac-authorization true

# Assign role to a managed identity
az role assignment create \
  --role "Key Vault Secrets User" \           # Read-only secrets
  --assignee <managed-identity-principal-id> \
  --scope /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.KeyVault/vaults/my-keyvault
```

### Built-in Key Vault RBAC Roles

| Role | Permissions | Use for |
|------|-------------|---------|
| **Key Vault Administrator** | Full control | Vault admins |
| **Key Vault Secrets Officer** | CRUD secrets | CI/CD, automation |
| **Key Vault Secrets User** | Read secrets only | Applications |
| **Key Vault Crypto Officer** | CRUD keys | Key management |
| **Key Vault Crypto User** | Use keys (encrypt/decrypt/sign) | Applications |
| **Key Vault Certificate Officer** | CRUD certificates | Cert management |
| **Key Vault Reader** | Read metadata only | Monitoring, auditing |

**Best practice:** Assign `Key Vault Secrets User` to application managed identities — read-only access to secrets. Assign `Key Vault Secrets Officer` to automation/CI pipelines that need to write secrets.

---

## Managed Identity — The Right Way to Access Key Vault

Never use service principal secrets or connection strings to access Key Vault from Azure workloads. Use Managed Identity instead.

### System-Assigned Managed Identity

```bash
# Enable system-assigned identity on a VM
az vm identity assign \
  --resource-group myRG \
  --name myVM

# Grant Key Vault access to the VM's identity
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $(az vm show --resource-group myRG --name myVM \
    --query identity.principalId -o tsv) \
  --scope /subscriptions/<sub>/.../vaults/my-keyvault
```

The VM can now access Key Vault without any credentials — Azure handles the identity token automatically.

### User-Assigned Managed Identity (preferred for AKS)

```bash
# Create the identity
az identity create \
  --resource-group myRG \
  --name checkout-workload-identity

# Get the principal ID
PRINCIPAL_ID=$(az identity show \
  --resource-group myRG \
  --name checkout-workload-identity \
  --query principalId -o tsv)

# Grant Key Vault access
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $PRINCIPAL_ID \
  --scope /subscriptions/<sub>/.../vaults/my-keyvault
```

User-assigned identities can be shared across multiple resources and are not deleted when a resource is deleted — making them better for AKS workloads.

---

## AKS Integration — Workload Identity + Key Vault

Two approaches for AKS pods to access Key Vault:

### Option 1: AKS Secrets Store CSI Driver (recommended)

The CSI driver mounts Key Vault secrets directly as files or environment variables in pods, syncing them to Kubernetes Secrets.

```bash
# Enable on AKS cluster
az aks enable-addons \
  --addons azure-keyvault-secrets-provider \
  --name myAKS \
  --resource-group myRG
```

```yaml
# SecretProviderClass — defines what to sync from Key Vault
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: checkout-secrets
  namespace: checkout
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    clientID: "<user-assigned-managed-identity-client-id>"
    keyvaultName: "my-keyvault"
    cloudName: "AzurePublicCloud"
    objects: |
      array:
        - |
          objectName: checkout-db-password   # Secret name in Key Vault
          objectType: secret
          objectVersion: ""                  # Latest version
        - |
          objectName: stripe-api-key
          objectType: secret
        - |
          objectName: checkout-tls-cert
          objectType: cert
    tenantId: "<azure-tenant-id>"
  secretObjects:                             # Sync to K8s Secret
    - secretName: checkout-k8s-secret
      type: Opaque
      data:
        - objectName: checkout-db-password
          key: db-password
        - objectName: stripe-api-key
          key: stripe-key

---
# Pod using the SecretProviderClass
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-api
  namespace: checkout
spec:
  template:
    spec:
      serviceAccountName: checkout-sa
      volumes:
        - name: secrets-store
          csi:
            driver: secrets-store.csi.k8s.io
            readOnly: true
            volumeAttributes:
              secretProviderClass: checkout-secrets
      containers:
        - name: checkout-api
          image: myregistry/checkout-api:latest
          env:
            # From synced K8s Secret
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: checkout-k8s-secret
                  key: db-password
          volumeMounts:
            - name: secrets-store
              mountPath: /mnt/secrets
              readOnly: true
```

### Option 2: AKS Workload Identity + Azure SDK

The pod uses its Kubernetes ServiceAccount token to get an Azure AD token, then calls Key Vault directly using the Azure SDK:

```bash
# Enable OIDC issuer and Workload Identity on AKS
az aks update \
  --resource-group myRG \
  --name myAKS \
  --enable-oidc-issuer \
  --enable-workload-identity

# Get OIDC issuer URL
OIDC_ISSUER=$(az aks show \
  --resource-group myRG \
  --name myAKS \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

# Create federated identity credential
az identity federated-credential create \
  --name checkout-federated \
  --identity-name checkout-workload-identity \
  --resource-group myRG \
  --issuer $OIDC_ISSUER \
  --subject "system:serviceaccount:checkout:checkout-sa" \
  --audience api://AzureADTokenExchange
```

```yaml
# ServiceAccount with workload identity annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: checkout-sa
  namespace: checkout
  annotations:
    azure.workload.identity/client-id: "<user-assigned-managed-identity-client-id>"
```

```python
# In application code (Python example)
from azure.identity import WorkloadIdentityCredential
from azure.keyvault.secrets import SecretClient

credential = WorkloadIdentityCredential()
client = SecretClient(
    vault_url="https://my-keyvault.vault.azure.net/",
    credential=credential
)
secret = client.get_secret("checkout-db-password")
```

No secrets needed to access Key Vault — the pod's Kubernetes identity is automatically exchanged for an Azure AD token.

---

## Key Vault Operations — CLI Reference

```bash
# Create a Key Vault
az keyvault create \
  --name my-keyvault \
  --resource-group myRG \
  --location westeurope \
  --enable-rbac-authorization true \
  --enable-soft-delete true \          # Deleted items retained 90 days
  --enable-purge-protection true       # Cannot purge until retention period ends

# Secrets
az keyvault secret set \
  --vault-name my-keyvault \
  --name checkout-db-password \
  --value "supersecret" \
  --expires "2025-12-31T00:00:00Z"   # Optional expiry

az keyvault secret show \
  --vault-name my-keyvault \
  --name checkout-db-password

az keyvault secret list \
  --vault-name my-keyvault

az keyvault secret set-attributes \
  --vault-name my-keyvault \
  --name checkout-db-password \
  --enabled false                     # Disable without deleting

# Secret versions
az keyvault secret show \
  --vault-name my-keyvault \
  --name checkout-db-password \
  --version <version-id>

az keyvault secret list-versions \
  --vault-name my-keyvault \
  --name checkout-db-password

# Keys
az keyvault key create \
  --vault-name my-keyvault \
  --name checkout-encryption-key \
  --kty RSA \
  --size 2048

az keyvault key encrypt \
  --vault-name my-keyvault \
  --name checkout-encryption-key \
  --algorithm RSA-OAEP \
  --value "base64-encoded-data"

# Certificates
az keyvault certificate create \
  --vault-name my-keyvault \
  --name checkout-tls \
  --policy @cert-policy.json

az keyvault certificate show \
  --vault-name my-keyvault \
  --name checkout-tls
```

---

## Certificate Lifecycle Management

Key Vault can manage the entire certificate lifecycle — creation, renewal, and storage:

```json
// cert-policy.json — certificate issuance policy
{
  "issuerParameters": {
    "name": "Self"              // or "DigiCert", "GlobalSign" for public certs
  },
  "keyProperties": {
    "exportable": true,
    "keySize": 2048,
    "keyType": "RSA",
    "reuseKey": false
  },
  "lifetimeActions": [
    {
      "action": {"actionType": "AutoRenew"},
      "trigger": {"daysBeforeExpiry": 30}   // Auto-renew 30 days before expiry
    }
  ],
  "secretProperties": {
    "contentType": "application/x-pkcs12"
  },
  "x509CertificateProperties": {
    "subject": "CN=checkout.internal",
    "subjectAlternativeNames": {
      "dnsNames": ["checkout.internal", "checkout.checkout.svc.cluster.local"]
    },
    "validityInMonths": 12
  }
}
```

Key Vault sends notifications (via Event Grid) when a certificate is about to expire, even if auto-renewal is configured — so you can verify renewal succeeded.

---

## Key Vault Monitoring and Diagnostics

```bash
# Enable diagnostic logging
az monitor diagnostic-settings create \
  --name keyvault-diagnostics \
  --resource /subscriptions/<sub>/.../vaults/my-keyvault \
  --logs '[{"category": "AuditEvent", "enabled": true}]' \
  --metrics '[{"category": "AllMetrics", "enabled": true}]' \
  --workspace /subscriptions/<sub>/.../workspaces/myLAW
```

### Key KQL Queries for Security Monitoring

```kql
// All secret access events in last 24 hours
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where OperationName == "SecretGet"
| where TimeGenerated > ago(24h)
| project TimeGenerated, CallerIPAddress, identity_claim_oid_g, ResultType

// Failed access attempts (unauthorized)
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where ResultType != "Success"
| where TimeGenerated > ago(7d)
| summarize count() by CallerIPAddress, OperationName
| order by count_ desc

// Secret access by identity (who accessed what)
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where OperationName in ("SecretGet", "SecretSet", "SecretDelete")
| summarize count() by identity_claim_unique_name_s, OperationName
```

---

## Interview Questions — Azure Key Vault

**Q: What is the difference between Azure Key Vault access policies and Azure RBAC for Key Vault?**
A: Access policies (legacy) grant permissions at the vault level — you can't restrict to specific secrets, only to types (get/list/delete for secrets). Azure RBAC (recommended) uses standard Azure role assignments, integrates with Azure Policy and Conditional Access, supports secret-level granularity via scope, and provides a consistent access model with all other Azure resources. New deployments should use RBAC.

**Q: How do AKS pods access Key Vault securely without storing credentials?**
A: Via Workload Identity or the Secrets Store CSI Driver. With Workload Identity, the pod's Kubernetes ServiceAccount is federated with an Azure Managed Identity — the pod's JWT token is exchanged for an Azure AD token automatically, which is used to call Key Vault. No secrets are stored anywhere. With the CSI Driver, Key Vault secrets are mounted directly into pods as files or synced to Kubernetes Secrets, using a managed identity for authentication.

**Q: What is soft delete and purge protection in Key Vault and why enable them?**
A: Soft delete retains deleted secrets/keys/certs for a configurable retention period (7-90 days, default 90) — accidental deletions can be recovered. Purge protection prevents permanently deleting (purging) items until the retention period expires, even by vault administrators. Together they protect against accidental data loss and malicious insider deletion of secrets. Enable both for any production Key Vault.

**Q: What types of objects does Azure Key Vault store and how do they differ?**
A: Secrets store arbitrary string values (passwords, connection strings, API keys). Keys store cryptographic key material (RSA, EC, AES) — the key never leaves Key Vault, applications call Key Vault APIs to encrypt/decrypt/sign. Certificates manage X.509 TLS certificates including lifecycle, auto-renewal, and the associated private key. Each type has its own RBAC roles and operations.
