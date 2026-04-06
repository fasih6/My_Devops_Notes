# Multi-Cluster GitOps

## Why Multi-Cluster

Production environments often span multiple clusters: regional clusters for latency, separate clusters for environments, dedicated clusters for compliance. GitOps scales to this well — the same Git-as-source-of-truth principle applies, just with more destinations.

## ArgoCD Multi-Cluster

ArgoCD runs in a management cluster and registers external clusters as targets.

```bash
# Register an external cluster (uses current kubeconfig context)
argocd cluster add my-production-context --name prod-eu-central-1

# List registered clusters
argocd cluster list

# Get cluster info
argocd cluster get prod-eu-central-1
```

ArgoCD stores cluster credentials as Secrets in the `argocd` namespace:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: prod-eu-central-1
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
type: Opaque
stringData:
  name: prod-eu-central-1
  server: https://prod-api.example.com
  config: |
    {
      "bearerToken": "<token>",
      "tlsClientConfig": {
        "caData": "<base64-ca-cert>"
      }
    }
```

Label clusters for ApplicationSet generators:
```bash
kubectl label secret prod-eu-central-1 \
  environment=production \
  region=eu \
  -n argocd
```

```yaml
# Deploy to all production clusters automatically
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: myapp-production
  namespace: argocd
spec:
  generators:
    - clusters:
        selector:
          matchLabels:
            environment: production    # only prod clusters
  template:
    metadata:
      name: "myapp-{{name}}"          # e.g. myapp-prod-eu-central-1
    spec:
      project: default
      source:
        repoURL: https://github.com/myorg/gitops-repo
        targetRevision: main
        path: environments/production/myapp
      destination:
        server: "{{server}}"          # each cluster's API URL
        namespace: production
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
```

## Flux Multi-Cluster — Hub and Spoke

One management cluster (hub) runs Flux and targets multiple spoke clusters via Kubeconfig secrets.

```
Management cluster (Flux runs here)
  ├── Kustomization targeting prod-eu (via kubeconfig secret)
  └── Kustomization targeting prod-us (via kubeconfig secret)

prod-eu cluster  ← Flux applies here remotely
prod-us cluster  ← Flux applies here remotely
```

```bash
# Create kubeconfig secret for each spoke cluster
kubectl create secret generic prod-eu-kubeconfig \
  --from-file=value=./prod-eu-kubeconfig.yaml \
  -n flux-system
```

```yaml
# Kustomization targeting the spoke
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: apps-prod-eu
  namespace: flux-system
spec:
  kubeConfig:
    secretRef:
      name: prod-eu-kubeconfig    # apply to remote cluster
  interval: 5m
  sourceRef:
    kind: GitRepository
    name: gitops-repo
  path: ./environments/production
  prune: true
```

## GitOps Fleet Management Tools

### Cluster API (CAPI) + GitOps

CAPI provisions clusters declaratively. Combined with Flux/ArgoCD, the entire cluster lifecycle is GitOps-managed:

```yaml
# Declare a cluster in Git → CAPI creates it → Flux bootstraps GitOps onto it
apiVersion: cluster.x-k8s.io/v1beta1
kind: Cluster
metadata:
  name: prod-eu-west-1
spec:
  clusterNetwork:
    pods:
      cidrBlocks: ["192.168.0.0/16"]
  controlPlaneRef:
    apiVersion: controlplane.cluster.x-k8s.io/v1beta1
    kind: KubeadmControlPlane
    name: prod-eu-west-1
  infrastructureRef:
    apiVersion: infrastructure.cluster.x-k8s.io/v1beta1
    kind: AWSManagedCluster
    name: prod-eu-west-1
```

### Rancher Fleet

Rancher Fleet is a multi-cluster GitOps tool built into Rancher. It scales to thousands of clusters.

```yaml
# fleet.yaml — in your application repo
namespace: production
helm:
  releaseName: myapp
  chart: ./charts/myapp
  values:
    replicaCount: 3
targets:
  - name: production
    clusterSelector:
      matchLabels:
        env: production
```

### Azure Arc + GitOps

Azure Arc extends Azure management to any Kubernetes cluster (on-prem, other clouds). It integrates natively with Flux.

```bash
# Connect a cluster to Arc
az connectedk8s connect \
  --name prod-onprem-cluster \
  --resource-group rg-production \
  --location westeurope

# Enable GitOps extension (installs Flux)
az k8s-configuration flux create \
  --cluster-name prod-onprem-cluster \
  --cluster-type connectedClusters \
  --resource-group rg-production \
  --name gitops-config \
  --namespace flux-system \
  --scope cluster \
  --url https://github.com/myorg/gitops-repo \
  --branch main \
  --kustomization name=apps path=./environments/production prune=true
```

## Multi-Cluster Patterns

### Environment-per-cluster (most common)
```
dev cluster     ← dev environment
staging cluster ← staging environment
prod-eu cluster ← production EU
prod-us cluster ← production US (DR / expansion)
```

### Workload separation
```
platform cluster ← ingress, monitoring, cert-manager, Vault
app cluster A    ← team A workloads
app cluster B    ← team B workloads (isolated for compliance)
```

### Blue-green clusters (zero-downtime cluster upgrades)
```
blue cluster  ← currently live (100% traffic)
green cluster ← new K8s version (build here, test, then shift traffic)
```

## Cross-Cluster Service Discovery

With multi-cluster, services in different clusters need to communicate:

- **Submariner** — connects cluster networks, enables cross-cluster DNS
- **Istio multi-cluster** — service mesh spans clusters
- **AWS Cloud Map / Azure DNS** — external DNS for cross-cluster discovery
- **Skupper** — application-layer connectivity without network changes
