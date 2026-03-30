# Azure Entra ID (Azure AD) & RBAC 🔐

> Part of my DevOps journey — azure folder

---

## What is Entra ID?

Azure Entra ID (formerly Azure Active Directory / Azure AD) is Microsoft's cloud-based **identity and access management** service. It's the foundation of all Azure security — every Azure interaction is authenticated through Entra ID.

```
AWS IAM     ≈    Entra ID + Azure RBAC
(combined)       (separated: identity vs authorisation)
```

**Key difference from AWS IAM:** Entra ID handles *identity* (authentication — who are you?). Azure RBAC handles *authorisation* (what can you do?). They work together but are separate systems.

---

## Core Components

### Users

Individual identities — employees, admins, service accounts.

```bash
# Create user
az ad user create \
  --display-name "Fasih Ahmed" \
  --user-principal-name fasih@mycompany.onmicrosoft.com \
  --password "TempPass123!" \
  --force-change-password-next-sign-in true

# List users
az ad user list --output table

# Get user details
az ad user show --id fasih@mycompany.onmicrosoft.com
```

### Groups

Collections of users. Assign RBAC roles to groups — not individual users.

```bash
# Create group
az ad group create \
  --display-name "DevOps Engineers" \
  --mail-nickname "devops-engineers"

# Add member
az ad group member add \
  --group "DevOps Engineers" \
  --member-id <user-object-id>

# List group members
az ad group member list --group "DevOps Engineers"
```

### Service Principals

An identity for **applications and services** — equivalent to an AWS IAM Role for applications. Used when apps need to access Azure resources.

```bash
# Create service principal (returns appId, password, tenant)
az ad sp create-for-rbac \
  --name "myapp-cicd-sp" \
  --role Contributor \
  --scopes /subscriptions/<subscription-id>/resourceGroups/myapp-prod-rg

# Output:
# {
#   "appId": "xxx",         ← client ID
#   "displayName": "myapp-cicd-sp",
#   "password": "xxx",      ← client secret (save now, not shown again!)
#   "tenant": "xxx"         ← tenant ID
# }

# List service principals
az ad sp list --display-name "myapp" --output table

# Delete service principal
az ad sp delete --id <appId>
```

**Common use cases:**
- CI/CD pipelines authenticating to Azure (GitHub Actions, GitLab CI, Jenkins)
- Terraform authenticating to deploy infrastructure
- Applications accessing Key Vault, Storage, databases

### Managed Identities

Like AWS IAM instance profiles — Azure automatically manages credentials. No secrets to store or rotate.

```
System-assigned:  tied to one resource, deleted when resource is deleted
User-assigned:    created separately, can be assigned to multiple resources
```

```bash
# Create user-assigned managed identity
az identity create \
  --name myapp-identity \
  --resource-group myapp-prod-rg

# Assign to VM
az vm identity assign \
  --name my-vm \
  --resource-group myapp-prod-rg \
  --identities myapp-identity

# Assign to AKS (for workload identity)
az aks update \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --enable-managed-identity
```

**Use managed identities instead of service principals whenever possible** — no secrets to manage.

---

## Azure RBAC

Role-Based Access Control controls what authenticated identities can do with Azure resources.

```
Who (security principal)  +  What (role)  +  Where (scope)  =  Access
User / Group / SP / MI      Contributor     Resource Group
```

### Built-in Roles

| Role | What it can do |
|------|---------------|
| **Owner** | Full access + manage access (assign roles) |
| **Contributor** | Full access to resources, cannot manage access |
| **Reader** | View resources only |
| **User Access Administrator** | Manage access only, no resource access |
| **AKS Cluster Admin** | Full K8s cluster access |
| **AKS RBAC Admin** | Manage K8s RBAC |
| **ACR Pull** | Pull images from container registry |
| **Storage Blob Data Contributor** | Read/write/delete blob data |
| **Key Vault Secrets User** | Read secrets from Key Vault |
| **Virtual Machine Contributor** | Manage VMs but not networking/storage |

### RBAC Scopes (hierarchy)

```
Management Group → Subscription → Resource Group → Resource
(broadest)                                          (narrowest)
```

Roles assigned at a higher scope are inherited by all children.

```bash
# Assign role
az role assignment create \
  --assignee fasih@mycompany.com \
  --role "Contributor" \
  --scope /subscriptions/<sub-id>/resourceGroups/myapp-prod-rg

# Assign to service principal at subscription level
az role assignment create \
  --assignee <service-principal-appId> \
  --role "Reader" \
  --scope /subscriptions/<sub-id>

# List role assignments
az role assignment list \
  --resource-group myapp-prod-rg \
  --output table

# Remove role assignment
az role assignment delete \
  --assignee fasih@mycompany.com \
  --role "Contributor" \
  --resource-group myapp-prod-rg
```

### Custom Roles

```json
{
  "Name": "VM Operator",
  "Description": "Can start, stop, restart VMs but not create/delete",
  "Actions": [
    "Microsoft.Compute/virtualMachines/start/action",
    "Microsoft.Compute/virtualMachines/restart/action",
    "Microsoft.Compute/virtualMachines/deallocate/action",
    "Microsoft.Compute/virtualMachines/read"
  ],
  "NotActions": [],
  "AssignableScopes": [
    "/subscriptions/<subscription-id>"
  ]
}
```

```bash
az role definition create --role-definition @custom-role.json
```

---

## Azure Policy

Enforce organisational standards and assess compliance at scale.

```bash
# Assign built-in policy: require tags on resource groups
az policy assignment create \
  --name "require-env-tag" \
  --display-name "Require Environment tag" \
  --policy "/providers/Microsoft.Authorization/policyDefinitions/96670d01-0a4d-4649-9c89-2d3abc0a5025" \
  --scope /subscriptions/<sub-id>

# List policy assignments
az policy assignment list --output table

# Check compliance state
az policy state list --output table
```

**Common built-in policies:**
- Require specific tags on resources
- Allowed locations (restrict resources to specific regions)
- Allowed VM SKUs
- Require HTTPS on storage accounts
- Require encryption at rest

---

## Entra ID Authentication Methods

```
Password + MFA          → standard human login
Service Principal       → app authenticates with client ID + secret/certificate
Managed Identity        → Azure-managed, no secret needed
Certificate             → more secure than client secret
Federated Credentials   → OIDC for GitHub Actions, Kubernetes workload identity
```

### GitHub Actions → Azure (Federated Credentials — no secrets)

```bash
# Create service principal
az ad app create --display-name "github-actions-sp"

# Create federated credential (OIDC — no secret needed)
az ad app federated-credential create \
  --id <app-id> \
  --parameters '{
    "name": "github-main",
    "issuer": "https://token.actions.githubusercontent.com",
    "subject": "repo:myorg/myrepo:ref:refs/heads/main",
    "audiences": ["api://AzureADTokenExchange"]
  }'

# Assign role
az role assignment create \
  --assignee <app-id> \
  --role Contributor \
  --scope /subscriptions/<sub-id>
```

```yaml
# GitHub Actions workflow
- uses: azure/login@v1
  with:
    client-id: ${{ secrets.AZURE_CLIENT_ID }}
    tenant-id: ${{ secrets.AZURE_TENANT_ID }}
    subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}
    # No client secret needed with federated credentials!
```

---

## Quick Reference

```bash
# Identity
az ad user create / list / show / delete
az ad group create / member add / member list
az ad sp create-for-rbac --name x --role x --scopes x
az identity create --name x --resource-group rg

# RBAC
az role assignment create --assignee x --role x --scope x
az role assignment list --resource-group rg
az role assignment delete --assignee x --role x
az role definition list --output table
az role definition create --role-definition @file.json

# Policy
az policy assignment create --name x --policy x --scope x
az policy state list

Key concepts:
  Entra ID = identity (authentication)
  RBAC = authorisation (what can you do)
  Service Principal = identity for apps/CI-CD
  Managed Identity = service principal with auto-managed credentials
  Scope: MG > Subscription > Resource Group > Resource
```
