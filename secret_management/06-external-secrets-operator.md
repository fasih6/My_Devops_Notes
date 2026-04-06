# External Secrets Operator — Syncing Secrets from Any Backend into Kubernetes

## What Is the External Secrets Operator?

The External Secrets Operator (ESO) is a Kubernetes operator that reads secrets from external secret management systems and automatically syncs them into native Kubernetes Secrets.

```
WITHOUT ESO:
  Developer manually copies secret from Vault/Key Vault → kubectl create secret
  → Manual, error-prone, not rotated, no audit trail

WITH ESO:
  ESO watches ExternalSecret CRDs → reads from Vault/AKV/AWS SM → creates/updates K8s Secrets
  → Automated, always in sync, rotation-aware, declarative
```

ESO is the bridge between your secret backend (Vault, Azure Key Vault, AWS Secrets Manager, GCP Secret Manager) and Kubernetes. Applications consume standard Kubernetes Secrets — they don't need to know anything about the underlying secret backend.

---

## ESO Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                        Kubernetes Cluster                     │
│                                                              │
│  ┌─────────────────┐     ┌──────────────────────────────┐   │
│  │ ExternalSecret  │     │  External Secrets Operator   │   │
│  │ (CRD)          │────→│  (watches ExternalSecrets)   │   │
│  │                 │     │                              │   │
│  │ - secretStore   │     │  - Authenticates to backend  │   │
│  │ - remoteRef     │     │  - Fetches secret values     │   │
│  │ - refreshInterval│    │  - Creates/updates K8s Secret│   │
│  └─────────────────┘     │  - Re-syncs on interval      │   │
│                           └──────────────┬───────────────┘   │
│  ┌─────────────────┐                     │                   │
│  │ Kubernetes      │◄────────────────────┘                   │
│  │ Secret          │     (ESO writes here)                   │
│  │ (created by ESO)│                                         │
│  └────────┬────────┘                                         │
│           │ consumed by                                       │
│  ┌────────▼────────┐                                         │
│  │   Application   │                                         │
│  │   Pod           │                                         │
│  └─────────────────┘                                         │
└──────────────────────────────────────────────────────────────┘
         │ reads from
         ▼
┌─────────────────────┐
│  External Backends  │
│                     │
│  - HashiCorp Vault  │
│  - Azure Key Vault  │
│  - AWS Secrets Mgr  │
│  - GCP Secret Mgr   │
│  - 1Password        │
│  - Doppler          │
└─────────────────────┘
```

---

## Installing ESO

```bash
# Install via Helm
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm install external-secrets \
  external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace \
  --set installCRDs=true

# Verify installation
kubectl get pods -n external-secrets
kubectl get crd | grep external-secrets
```

---

## Core CRDs

ESO introduces three main CRDs:

| CRD | Scope | Purpose |
|-----|-------|---------|
| `SecretStore` | Namespaced | Connects to a secret backend for one namespace |
| `ClusterSecretStore` | Cluster-wide | Connects to a secret backend for all namespaces |
| `ExternalSecret` | Namespaced | Defines what secrets to fetch and where to put them |
| `ClusterExternalSecret` | Cluster-wide | ExternalSecret applied across multiple namespaces |
| `PushSecret` | Namespaced | Pushes K8s Secret values TO external backend |

---

## SecretStore — Connecting to a Backend

### SecretStore with Azure Key Vault

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: azure-keyvault-store
  namespace: checkout
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity          # Use AKS Workload Identity
      vaultUrl: "https://my-keyvault.vault.azure.net"
      serviceAccountRef:
        name: checkout-sa                 # ServiceAccount with workload identity annotation
```

### ClusterSecretStore with Azure Key Vault

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: azure-keyvault-cluster-store
spec:
  provider:
    azurekv:
      authType: WorkloadIdentity
      vaultUrl: "https://my-keyvault.vault.azure.net"
      serviceAccountRef:
        name: eso-sa
        namespace: external-secrets      # ESO's own service account
```

### SecretStore with HashiCorp Vault

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-store
  namespace: checkout
spec:
  provider:
    vault:
      server: "https://vault.internal:8200"
      path: "secret"                    # KV mount path
      version: "v2"                     # KV v2
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "checkout"              # Vault role bound to this namespace's SA
          serviceAccountRef:
            name: checkout-sa
```

### SecretStore with AWS Secrets Manager

```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secretsmanager-store
  namespace: checkout
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-west-1
      auth:
        jwt:
          serviceAccountRef:
            name: checkout-sa           # Uses IRSA (IAM Roles for Service Accounts)
```

---

## ExternalSecret — Fetching and Syncing Secrets

### Basic ExternalSecret — Single Secret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: checkout-db-secret
  namespace: checkout
spec:
  refreshInterval: 1h                   # Re-sync from backend every hour

  secretStoreRef:
    name: azure-keyvault-store
    kind: SecretStore

  target:
    name: checkout-db-credentials       # K8s Secret to create/update
    creationPolicy: Owner               # ESO owns this secret (deletes it if ES deleted)
    deletionPolicy: Retain              # Keep K8s secret if ES is deleted

  data:
    - secretKey: db-password            # Key in the K8s Secret
      remoteRef:
        key: checkout-db-password       # Name in Azure Key Vault
    - secretKey: db-username
      remoteRef:
        key: checkout-db-username
```

This creates a Kubernetes Secret named `checkout-db-credentials` with two keys (`db-password`, `db-username`) fetched from Azure Key Vault. It re-syncs every hour — if the secret is rotated in Key Vault, the K8s Secret is updated automatically within 1 hour.

### ExternalSecret — Fetch All Keys from a Path (Vault)

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: checkout-config
  namespace: checkout
spec:
  refreshInterval: 30m

  secretStoreRef:
    name: vault-store
    kind: SecretStore

  target:
    name: checkout-config-secret
    creationPolicy: Owner

  dataFrom:
    - extract:
        key: secret/data/checkout/config  # Fetch ALL keys from this Vault path
```

`dataFrom.extract` fetches all key-value pairs at the path and maps them 1:1 into the K8s Secret. No need to list each key individually.

### ExternalSecret — Transform and Rename Keys

```yaml
spec:
  data:
    - secretKey: DATABASE_URL            # Key name in K8s Secret
      remoteRef:
        key: checkout-db-password
      # Template the value
  target:
    name: checkout-app-env
    template:
      engineVersion: v2
      data:
        DATABASE_URL: "postgresql://{{ .checkout_db_username }}:{{ .checkout_db_password }}@postgres.internal:5432/checkout"
        REDIS_URL: "redis://:{{ .redis_password }}@redis.internal:6379"
```

Templates let you compose multiple secrets into a single value — useful for constructing connection strings from individual components.

### ExternalSecret — Specific Version (Vault/AKV)

```yaml
spec:
  data:
    - secretKey: api-key
      remoteRef:
        key: stripe-api-key
        version: "abc123def456"         # Specific version in AKV
        # or for Vault:
        # version: "3"                 # Specific version number
```

Pinning versions is useful during controlled rotation — pin to old version, test new version, then update to new version once verified.

---

## ClusterExternalSecret — Multi-Namespace Sync

Useful for secrets that many namespaces need (e.g. shared TLS cert, common API key):

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ClusterExternalSecret
metadata:
  name: shared-tls-cert
spec:
  namespaceSelector:
    matchLabels:
      shared-tls: "true"               # Apply to all namespaces with this label

  refreshInterval: 1h

  externalSecretSpec:
    secretStoreRef:
      name: azure-keyvault-cluster-store
      kind: ClusterSecretStore
    target:
      name: shared-tls-secret
      creationPolicy: Owner
    data:
      - secretKey: tls.crt
        remoteRef:
          key: shared-tls-certificate
      - secretKey: tls.key
        remoteRef:
          key: shared-tls-private-key
```

Now every namespace with the label `shared-tls: "true"` automatically gets the TLS secret, kept in sync with Azure Key Vault.

---

## PushSecret — Writing K8s Secrets TO External Backends

PushSecret is the reverse of ExternalSecret — it takes a Kubernetes Secret and pushes it to an external backend. Useful for:
- Seeding a new Key Vault from existing cluster secrets
- Sharing secrets between clusters via a central backend

```yaml
apiVersion: external-secrets.io/v1alpha1
kind: PushSecret
metadata:
  name: push-checkout-secret
  namespace: checkout
spec:
  refreshInterval: 10s
  secretStoreRefs:
    - name: azure-keyvault-store
      kind: SecretStore
  selector:
    secret:
      name: checkout-generated-secret   # K8s Secret to push
  data:
    - match:
        secretKey: api-key              # Key in K8s Secret
        remoteRef:
          remoteKey: checkout-api-key   # Name in Key Vault
```

---

## Rotation Handling — How ESO Responds to Secret Changes

```
Scenario: Secret rotated in Azure Key Vault

1. ESO checks Key Vault on refreshInterval (e.g. every 1h)
2. ESO detects the secret value has changed
3. ESO updates the K8s Secret with the new value
4. Application reads new value:
   - If using volume mount: updated within kubelet sync period (~1 min)
   - If using env var: requires pod restart

For env var-based apps, use reloader:
```

### Stakater Reloader — Auto-Restart Pods on Secret Changes

```yaml
# Install Reloader
helm install reloader stakater/reloader \
  --namespace reloader \
  --create-namespace

# Annotate your Deployment to watch for secret changes
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-api
  annotations:
    secret.reloader.stakater.com/reload: "checkout-db-credentials,checkout-config-secret"
spec:
  # ...
```

When ESO updates `checkout-db-credentials`, Reloader detects the change and triggers a rolling restart of the Deployment — new pods get fresh env vars.

---

## ESO Status and Debugging

```bash
# Check ExternalSecret sync status
kubectl get externalsecret -n checkout
# Output shows: STORE, REFRESH INTERVAL, STATUS, READY

kubectl describe externalsecret checkout-db-secret -n checkout
# Shows: last sync time, conditions, any errors

# Common status conditions:
#   SecretSynced: True    → K8s Secret created/updated successfully
#   SecretSynced: False   → Error syncing (check Events section)

# Force immediate re-sync (delete and recreate — ESO recreates automatically)
kubectl annotate externalsecret checkout-db-secret \
  force-sync=$(date +%s) \
  --overwrite \
  -n checkout

# Check ESO operator logs
kubectl logs -n external-secrets \
  -l app.kubernetes.io/name=external-secrets \
  --tail=100
```

---

## ESO vs Vault Agent vs CSI Driver — Comparison

| Feature | ESO | Vault Agent (sidecar) | CSI Driver |
|---------|-----|----------------------|------------|
| Architecture | Cluster operator | Per-pod sidecar | Per-pod CSI volume |
| Secret visibility | K8s Secret (etcd) | Pod filesystem only | Pod filesystem + optional K8s Secret |
| App changes needed | Use K8s secret | Read from file | Read from file or K8s secret |
| Dynamic secrets | Not natively (refresh interval) | Yes (lease renewal) | Yes (with Vault CSI provider) |
| Multi-backend support | Yes (20+ providers) | Vault only | Provider-specific |
| Rotation handling | Refresh interval + Reloader | Automatic (agent re-renders) | Automatic (CSI re-mounts) |
| Operational complexity | Low (one operator) | High (per-pod config) | Medium |
| Best for | Multi-backend, K8s-native apps | Vault-only, file-based secrets | Per-pod isolation, dynamic secrets |

---

## Interview Questions — External Secrets Operator

**Q: What problem does the External Secrets Operator solve?**
A: ESO solves the disconnect between external secret backends (Vault, Azure Key Vault) and Kubernetes. Without ESO, secrets must be manually copied into Kubernetes Secrets — a manual, error-prone process with no rotation support. ESO automates the sync: it reads from the backend on a configurable interval and keeps Kubernetes Secrets up to date. Applications consume standard K8s secrets and don't need to know about the backend.

**Q: What is the difference between SecretStore and ClusterSecretStore?**
A: SecretStore is namespaced — it can only be referenced by ExternalSecrets in the same namespace. ClusterSecretStore is cluster-scoped — any namespace can reference it. Use SecretStore when different namespaces connect to different backends or authenticate differently. Use ClusterSecretStore for shared backends accessed by many namespaces, managed centrally by the platform team.

**Q: How does ESO handle secret rotation?**
A: ESO re-fetches secrets from the backend on every `refreshInterval` (e.g. every 1 hour). If the value has changed, it updates the Kubernetes Secret. For volume-mounted secrets, the update propagates to running pods within the kubelet sync period. For env-var-based secrets, a pod restart is needed — use Stakater Reloader, which watches for Secret changes and triggers rolling restarts automatically.

**Q: When would you choose ESO over the Vault Agent sidecar?**
A: ESO is preferred when: you have multiple secret backends (not just Vault), your apps use standard Kubernetes env vars/secrets (not file paths), you want a simpler operational model (one operator vs per-pod sidecars), or you're working in a GitOps workflow where ExternalSecret CRDs are committed to Git. Vault Agent is preferred when you need true dynamic secrets with Vault lease management, or when the app must read secrets from files and can't use K8s secrets.
