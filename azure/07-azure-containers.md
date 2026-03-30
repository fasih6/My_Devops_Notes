# Azure Containers — ACR, AKS, Container Apps & ACI 🐳

> Part of my DevOps journey — azure folder

---

## Container Services Overview

| Service | AWS Equivalent | Use case |
|---------|---------------|---------|
| **ACR** (Azure Container Registry) | ECR | Private Docker registry |
| **AKS** (Azure Kubernetes Service) | EKS | Managed Kubernetes |
| **Container Apps** | ECS Fargate + App Service | Serverless containers, microservices |
| **ACI** (Azure Container Instances) | ECS Fargate tasks | Single containers, quick launches |

---

## ACR — Azure Container Registry

Private Docker registry integrated with Azure RBAC, Entra ID, and vulnerability scanning.

```bash
# Create ACR (name must be globally unique, alphanumeric only)
az acr create \
  --name myappregistry \
  --resource-group myapp-prod-rg \
  --sku Premium \
  --location eastus \
  --admin-enabled false

# Login to ACR
az acr login --name myappregistry

# Build image directly in ACR (no local Docker needed)
az acr build \
  --registry myappregistry \
  --image myapp:1.0.0 \
  --file Dockerfile \
  .

# Or build locally and push
docker build -t myapp:1.0.0 .
docker tag myapp:1.0.0 myappregistry.azurecr.io/myapp:1.0.0
docker push myappregistry.azurecr.io/myapp:1.0.0

# List repositories and tags
az acr repository list --name myappregistry --output table
az acr repository show-tags --name myappregistry --repository myapp --output table

# Geo-replication (Premium only)
az acr replication create \
  --registry myappregistry \
  --location westeurope

# Enable vulnerability scanning
az acr update \
  --name myappregistry \
  --resource-group myapp-prod-rg

# Grant AKS pull access
az role assignment create \
  --assignee $(az aks show --name my-aks --resource-group myapp-prod-rg \
    --query identityProfile.kubeletidentity.objectId -o tsv) \
  --role AcrPull \
  --scope $(az acr show --name myappregistry -g myapp-prod-rg --query id -o tsv)

# Or use the built-in attach command
az aks update \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --attach-acr myappregistry
```

**ACR SKUs:**
- **Basic** — dev/test, limited storage, no geo-replication
- **Standard** — production, more storage
- **Premium** — geo-replication, private endpoints, content trust, 500GB included

---

## AKS — Azure Kubernetes Service

Managed Kubernetes — Azure manages the control plane for free (you pay for worker nodes).

```
Azure manages:              You manage:
├── API Server              ├── Node pools (VM sizes, count)
├── etcd                    ├── Node OS updates (or enable auto-upgrade)
├── Scheduler               ├── Kubernetes workloads (manifests/Helm)
├── Controller Manager      ├── Networking (CNI plugin choice)
├── HA across 3 AZs         └── Storage (CSI drivers)
└── Control plane upgrades (managed)
```

### Create AKS Cluster

```bash
# Create AKS cluster
az aks create \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --location eastus \
  --kubernetes-version 1.29 \
  --node-count 3 \
  --node-vm-size Standard_D4s_v5 \
  --nodepool-name systempool \
  --zones 1 2 3 \
  --enable-managed-identity \
  --network-plugin azure \
  --network-policy azure \
  --vnet-subnet-id /subscriptions/.../subnets/aks-subnet \
  --service-cidr 172.16.0.0/16 \
  --dns-service-ip 172.16.0.10 \
  --attach-acr myappregistry \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 10 \
  --enable-addons monitoring \
  --workspace-resource-id /subscriptions/.../workspaces/myapp-logs \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --auto-upgrade-channel stable \
  --node-os-upgrade-channel NodeImage \
  --generate-ssh-keys

# Get kubeconfig
az aks get-credentials \
  --name my-aks \
  --resource-group myapp-prod-rg

# Verify
kubectl get nodes
kubectl get pods --all-namespaces
```

### Node Pools

AKS clusters can have multiple node pools — different VM sizes for different workloads.

```bash
# Add user node pool (for application workloads)
az aks nodepool add \
  --name apppool \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --node-count 3 \
  --node-vm-size Standard_D4s_v5 \
  --zones 1 2 3 \
  --enable-cluster-autoscaler \
  --min-count 2 \
  --max-count 20 \
  --labels workload=application \
  --node-taints workload=application:NoSchedule

# Add GPU node pool
az aks nodepool add \
  --name gpupool \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --node-count 1 \
  --node-vm-size Standard_NC6s_v3 \
  --labels hardware=gpu

# Scale node pool manually
az aks nodepool scale \
  --name apppool \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --node-count 5

# List node pools
az aks nodepool list \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --output table

# Upgrade node pool OS
az aks nodepool upgrade \
  --name apppool \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --node-image-only
```

### AKS Workload Identity (≈ AWS IRSA)

Give pods fine-grained Azure RBAC permissions without node-level credentials.

```bash
# Create managed identity
az identity create \
  --name myapp-workload-identity \
  --resource-group myapp-prod-rg

# Create service account and federated credential
export AKS_OIDC_ISSUER=$(az aks show --name my-aks -g myapp-prod-rg \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)
export IDENTITY_CLIENT_ID=$(az identity show \
  --name myapp-workload-identity -g myapp-prod-rg --query clientId -o tsv)

az identity federated-credential create \
  --name myapp-fed-cred \
  --identity-name myapp-workload-identity \
  --resource-group myapp-prod-rg \
  --issuer $AKS_OIDC_ISSUER \
  --subject "system:serviceaccount:default:myapp-sa" \
  --audience "api://AzureADTokenExchange"

# Grant permission (e.g. read secrets from Key Vault)
az role assignment create \
  --assignee $IDENTITY_CLIENT_ID \
  --role "Key Vault Secrets User" \
  --scope /subscriptions/.../resourceGroups/.../providers/Microsoft.KeyVault/vaults/myapp-kv
```

```yaml
# Kubernetes Service Account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp-sa
  namespace: default
  annotations:
    azure.workload.identity/client-id: "<IDENTITY_CLIENT_ID>"
---
# Pod using the service account
spec:
  serviceAccountName: myapp-sa
  labels:
    azure.workload.identity/use: "true"
```

### AKS Add-ons & Extensions

```bash
# Enable Key Vault CSI driver (mount secrets as volumes)
az aks addon enable \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --addon azure-keyvault-secrets-provider

# Enable Azure Policy add-on
az aks addon enable \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --addon azure-policy

# Enable Keda (event-driven autoscaling)
az aks update \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --enable-keda

# Enable GitOps (Flux)
az k8s-configuration flux create \
  --name myapp-flux \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --cluster-type managedClusters \
  --scope cluster \
  --url https://github.com/myorg/myapp-config \
  --branch main \
  --kustomization name=apps path=./apps prune=true
```

---

## Azure Container Apps

**Serverless container hosting** — run microservices and event-driven apps without managing Kubernetes. Built on Kubernetes + KEDA + Dapr under the hood.

```bash
# Create Container Apps environment
az containerapp env create \
  --name myapp-cae \
  --resource-group myapp-prod-rg \
  --location eastus \
  --logs-workspace-id $(az monitor log-analytics workspace show \
    -g myapp-prod-rg -n myapp-logs --query customerId -o tsv)

# Create Container App
az containerapp create \
  --name myapp \
  --resource-group myapp-prod-rg \
  --environment myapp-cae \
  --image myappregistry.azurecr.io/myapp:1.0.0 \
  --registry-server myappregistry.azurecr.io \
  --target-port 3000 \
  --ingress external \
  --min-replicas 1 \
  --max-replicas 20 \
  --cpu 0.5 \
  --memory 1.0Gi \
  --env-vars NODE_ENV=production \
  --secrets "db-password=secretvalue" \
  --query properties.configuration.ingress.fqdn

# Update image (deploy new version)
az containerapp update \
  --name myapp \
  --resource-group myapp-prod-rg \
  --image myappregistry.azurecr.io/myapp:2.0.0

# Scale rules (HTTP-based)
az containerapp update \
  --name myapp \
  --resource-group myapp-prod-rg \
  --scale-rule-name http-rule \
  --scale-rule-type http \
  --scale-rule-http-concurrency 50

# View logs
az containerapp logs show \
  --name myapp \
  --resource-group myapp-prod-rg \
  --follow
```

**Container Apps vs AKS:**

| | Container Apps | AKS |
|---|---|---|
| Kubernetes knowledge needed | No | Yes |
| Control | Low | Full |
| Auto-scale to zero | Yes | Yes (with KEDA) |
| Cost when idle | ~$0 | Node VM cost |
| Best for | Microservices, event-driven | Complex K8s workloads |

---

## ACI — Azure Container Instances

Run single containers on-demand without any orchestration. Fast startup, pay per second.

```bash
# Run a container
az container create \
  --name myapp-instance \
  --resource-group myapp-prod-rg \
  --image myappregistry.azurecr.io/myapp:1.0.0 \
  --registry-login-server myappregistry.azurecr.io \
  --registry-username $(az acr credential show -n myappregistry --query username -o tsv) \
  --registry-password $(az acr credential show -n myappregistry --query passwords[0].value -o tsv) \
  --cpu 1 \
  --memory 1.5 \
  --ports 80 \
  --dns-name-label myapp-aci-demo \
  --environment-variables NODE_ENV=production \
  --location eastus

# Get FQDN
az container show \
  --name myapp-instance \
  --resource-group myapp-prod-rg \
  --query ipAddress.fqdn --output tsv

# View logs
az container logs --name myapp-instance --resource-group myapp-prod-rg

# Delete
az container delete --name myapp-instance --resource-group myapp-prod-rg --yes
```

**Use ACI for:** batch jobs, CI/CD build agents, dev/test, quick demos, Kubernetes virtual nodes (burst capacity).

---

## Quick Reference

```bash
# ACR
az acr create --name x --sku Premium
az acr login --name x
az acr build --registry x --image myapp:1.0.0 .
az aks update --attach-acr x

# AKS
az aks create --name x --node-count 3 --node-vm-size Standard_D4s_v5 --enable-managed-identity
az aks get-credentials --name x --resource-group rg
az aks nodepool add --name x --cluster-name c --node-count 3
az aks nodepool scale --name x --cluster-name c --node-count 5
az aks addon enable --addon azure-keyvault-secrets-provider

# Container Apps
az containerapp env create --name x --resource-group rg
az containerapp create --name x --environment e --image x:tag --ingress external
az containerapp update --name x --image x:newtag

# ACI
az container create --name x --image x --cpu 1 --memory 1.5
az container logs --name x
az container delete --name x
```
