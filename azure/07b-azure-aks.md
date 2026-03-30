# Azure Kubernetes Service (AKS) — Deep Dive ☸️

> Part of my DevOps journey — azure folder

---

## Why AKS?

AKS is Azure's managed Kubernetes offering. Azure manages the control plane (free), you manage the worker nodes. Deep integration with Azure services: ACR, Key Vault, Entra ID, Azure Monitor, Azure Policy, and more.

---

## AKS Architecture

```
┌─────────────────────────────────────────────────────┐
│                  AKS Cluster                         │
│                                                      │
│  Control Plane (managed by Azure — free)             │
│  ├── API Server                                      │
│  ├── etcd                                            │
│  ├── Scheduler                                       │
│  └── Controller Manager (HA across 3 AZs)           │
│                                                      │
│  Node Pools (you pay for these VMs)                  │
│  ├── System Pool  (CriticalAddonsOnly taint)         │
│  │   └── kube-system pods (CoreDNS, etc.)            │
│  └── User Pool(s) (your workloads)                   │
│      ├── Zone 1 nodes                                │
│      ├── Zone 2 nodes                                │
│      └── Zone 3 nodes                                │
└─────────────────────────────────────────────────────┘
```

---

## Cluster Creation — Production-Ready

```bash
# Create resource group
az group create --name myapp-prod-rg --location germanywestcentral

# Create Log Analytics workspace for monitoring
az monitor log-analytics workspace create \
  --workspace-name myapp-logs \
  --resource-group myapp-prod-rg

# Create AKS cluster
az aks create \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --location germanywestcentral \
  --kubernetes-version 1.29 \
  --node-count 3 \
  --node-vm-size Standard_D4s_v5 \
  --nodepool-name systempool \
  --nodepool-labels nodepool=system \
  --zones 1 2 3 \
  --enable-managed-identity \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --network-policy azure \
  --vnet-subnet-id /subscriptions/<sub>/resourceGroups/myapp-prod-rg/providers/Microsoft.Network/virtualNetworks/myapp-vnet/subnets/aks-subnet \
  --pod-cidr 192.168.0.0/16 \
  --service-cidr 172.16.0.0/16 \
  --dns-service-ip 172.16.0.10 \
  --attach-acr myappregistry \
  --enable-cluster-autoscaler \
  --min-count 3 \
  --max-count 10 \
  --enable-addons monitoring,azure-keyvault-secrets-provider \
  --workspace-resource-id /subscriptions/<sub>/resourceGroups/myapp-prod-rg/providers/Microsoft.OperationalInsights/workspaces/myapp-logs \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --auto-upgrade-channel stable \
  --node-os-upgrade-channel NodeImage \
  --enable-secret-rotation \
  --uptime-sla \
  --generate-ssh-keys

# Get credentials
az aks get-credentials --name my-aks --resource-group myapp-prod-rg

# Verify
kubectl get nodes -o wide
kubectl get pods --all-namespaces
```

---

## Node Pools

### System vs User Node Pools

```
System pool:  runs kube-system pods (CoreDNS, metrics-server)
              has CriticalAddonsOnly=true:NoSchedule taint
              always needed, min 1 node

User pool:    runs your application workloads
              can scale to 0
              use multiple for different VM sizes/workloads
```

```bash
# Add user node pool
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
  --labels workload=application env=production \
  --node-taints workload=application:NoSchedule \
  --max-pods 110 \
  --os-disk-size-gb 128 \
  --os-disk-type Ephemeral \
  --mode User

# Add spot node pool (for batch/non-critical)
az aks nodepool add \
  --name spotpool \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --node-count 0 \
  --node-vm-size Standard_D4s_v5 \
  --priority Spot \
  --eviction-policy Delete \
  --spot-max-price -1 \
  --enable-cluster-autoscaler \
  --min-count 0 \
  --max-count 50 \
  --labels workload=batch \
  --node-taints kubernetes.azure.com/scalesetpriority=spot:NoSchedule \
  --mode User

# Scale node pool manually
az aks nodepool scale \
  --name apppool \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --node-count 5

# Upgrade node pool OS image
az aks nodepool upgrade \
  --name apppool \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --node-image-only

# List node pools
az aks nodepool list \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --output table

# Delete node pool
az aks nodepool delete \
  --name spotpool \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg
```

---

## Networking Options

### CNI Plugins

| Plugin | Mode | Pod IPs | Use case |
|--------|------|---------|---------|
| **Azure CNI** | Traditional | From VNet subnet | Max compatibility, direct VNet integration |
| **Azure CNI Overlay** | Overlay | Private CIDR | Fewer IPs consumed from VNet, recommended |
| **Kubenet** | Overlay | Private CIDR | Simple, limited features (avoid for prod) |

```bash
# Azure CNI Overlay (recommended for new clusters)
--network-plugin azure \
--network-plugin-mode overlay \
--pod-cidr 192.168.0.0/16
```

### Ingress Options

| Option | Use case |
|--------|---------|
| **Nginx Ingress** | Most common, community-supported |
| **AGIC** (Application Gateway Ingress) | Integrates with Azure Application Gateway + WAF |
| **Azure Service Mesh** | Istio-based, mTLS, advanced traffic management |

```bash
# Install NGINX Ingress via Helm
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install nginx-ingress ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --set controller.service.annotations."service\.beta\.kubernetes\.io/azure-load-balancer-health-probe-request-path"=/healthz

# Enable AGIC add-on
az aks enable-addons \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --addons ingress-appgw \
  --appgw-name myapp-agw \
  --appgw-subnet-cidr 10.2.0.0/16
```

---

## Workload Identity (≈ AWS IRSA)

Give pods fine-grained Azure RBAC permissions without node-level credentials.

```bash
# Get OIDC issuer URL
export OIDC_URL=$(az aks show \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --query "oidcIssuerProfile.issuerUrl" -o tsv)

# Create managed identity
az identity create \
  --name myapp-identity \
  --resource-group myapp-prod-rg

export IDENTITY_CLIENT_ID=$(az identity show \
  --name myapp-identity \
  --resource-group myapp-prod-rg \
  --query clientId -o tsv)

# Create federated credential
az identity federated-credential create \
  --name myapp-fed-cred \
  --identity-name myapp-identity \
  --resource-group myapp-prod-rg \
  --issuer $OIDC_URL \
  --subject "system:serviceaccount:myapp:myapp-sa" \
  --audience "api://AzureADTokenExchange"

# Grant Key Vault access to identity
az role assignment create \
  --assignee $IDENTITY_CLIENT_ID \
  --role "Key Vault Secrets User" \
  --scope $(az keyvault show --name myapp-kv -g myapp-prod-rg --query id -o tsv)
```

```yaml
# Kubernetes Service Account
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp-sa
  namespace: myapp
  annotations:
    azure.workload.identity/client-id: "<IDENTITY_CLIENT_ID>"
    azure.workload.identity/tenant-id: "<TENANT_ID>"

---
# Deployment using Workload Identity
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
  namespace: myapp
spec:
  template:
    metadata:
      labels:
        app: myapp
        azure.workload.identity/use: "true"
    spec:
      serviceAccountName: myapp-sa
      containers:
        - name: myapp
          image: myappregistry.azurecr.io/myapp:latest
```

---

## Key Vault CSI Driver — Mount Secrets as Volumes

```yaml
# SecretProviderClass
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: myapp-secrets
  namespace: myapp
spec:
  provider: azure
  secretObjects:
    - secretName: myapp-k8s-secret    # creates K8s Secret
      type: Opaque
      data:
        - objectName: db-password
          key: password
  parameters:
    usePodIdentity: "false"
    clientID: "<IDENTITY_CLIENT_ID>"
    keyvaultName: myapp-kv
    cloudName: ""
    objects: |
      array:
        - |
          objectName: db-password
          objectType: secret
          objectVersion: ""
        - |
          objectName: api-key
          objectType: secret
    tenantId: "<TENANT_ID>"

---
# Use in Deployment
spec:
  containers:
    - name: myapp
      env:
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: myapp-k8s-secret
              key: password
      volumeMounts:
        - name: secrets-store
          mountPath: /mnt/secrets
          readOnly: true
  volumes:
    - name: secrets-store
      csi:
        driver: secrets-store.csi.k8s.io
        readOnly: true
        volumeAttributes:
          secretProviderClass: myapp-secrets
```

---

## KEDA — Event-Driven Autoscaling

Scale pods based on external event sources (Service Bus queue depth, Event Hub lag, HTTP requests, etc.).

```bash
# Enable KEDA
az aks update \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --enable-keda
```

```yaml
# Scale deployment based on Service Bus queue depth
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: myapp-scaler
  namespace: myapp
spec:
  scaleTargetRef:
    name: order-processor
  minReplicaCount: 0       # scale to zero when idle
  maxReplicaCount: 50
  triggers:
    - type: azure-servicebus
      metadata:
        queueName: orders-queue
        namespace: myapp-servicebus
        messageCount: "5"   # scale out per 5 messages
      authenticationRef:
        name: servicebus-auth
```

---

## GitOps with Flux

```bash
# Enable Flux extension
az k8s-configuration flux create \
  --name myapp-flux \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --cluster-type managedClusters \
  --scope cluster \
  --url https://github.com/myorg/myapp-config \
  --branch main \
  --kustomization name=infra path=./infrastructure prune=true \
  --kustomization name=apps path=./apps prune=true dependsOn=infra

# Check Flux status
az k8s-configuration flux show \
  --name myapp-flux \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --cluster-type managedClusters
```

---

## Cluster Upgrades

```bash
# Check available versions
az aks get-upgrades \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --output table

# Upgrade control plane
az aks upgrade \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --kubernetes-version 1.30 \
  --control-plane-only   # upgrade control plane first

# Upgrade node pool
az aks nodepool upgrade \
  --name apppool \
  --cluster-name my-aks \
  --resource-group myapp-prod-rg \
  --kubernetes-version 1.30

# Auto-upgrade channels
# none | patch | stable | rapid | node-image
az aks update \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --auto-upgrade-channel stable \
  --node-os-upgrade-channel NodeImage
```

---

## AKS Troubleshooting

```bash
# Check cluster health
az aks show --name my-aks --resource-group myapp-prod-rg --query agentPoolProfiles
kubectl get nodes
kubectl get pods --all-namespaces | grep -v Running

# Check node issues
kubectl describe node <node-name>
kubectl top nodes

# Pod debugging
kubectl describe pod <pod-name> -n myapp
kubectl logs <pod-name> -n myapp --previous
kubectl exec -it <pod-name> -n myapp -- /bin/sh
kubectl events -n myapp --sort-by='.lastTimestamp'

# Network debugging
kubectl run debug --image=nicolaka/netshoot --rm -it --restart=Never -- bash
curl http://myapp-service.myapp.svc.cluster.local

# AKS diagnostics
az aks kollect \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --storage-account myappstorage \
  --container-name aks-diagnostics

# Check periscope (node-level diagnostics)
az aks run-command \
  --name my-aks \
  --resource-group myapp-prod-rg \
  --command "kubectl get pods -n kube-system"
```

---

## Quick Reference

```bash
# Cluster
az aks create / show / update / delete --name x --resource-group rg
az aks get-credentials --name x --resource-group rg
az aks upgrade --name x --kubernetes-version 1.30
az aks get-upgrades --name x --output table
az aks enable-addons --addons x

# Node pools
az aks nodepool add / scale / upgrade / delete
az aks nodepool list --cluster-name x --output table

# Workload Identity
az identity create --name x --resource-group rg
az identity federated-credential create --identity-name x --subject system:serviceaccount:ns:sa
az role assignment create --assignee <clientId> --role "Key Vault Secrets User" --scope <kv-id>

# Useful kubectl
kubectl get nodes -o wide
kubectl top nodes / pods
kubectl describe pod x -n ns
kubectl logs x -n ns --previous
kubectl run debug --image=nicolaka/netshoot --rm -it -- bash
```
