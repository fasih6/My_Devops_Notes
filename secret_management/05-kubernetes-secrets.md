# Kubernetes Secrets — Native Secrets, Encryption at Rest, RBAC

## What Are Kubernetes Secrets?

Kubernetes Secrets are API objects that store sensitive data — passwords, tokens, keys — and make them available to pods without embedding them in container images or pod specs.

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: checkout-db-secret
  namespace: checkout
type: Opaque
data:
  db-password: c3VwZXJzZWNyZXQ=    # base64-encoded "supersecret"
  db-username: Y2hlY2tvdXRfdXNlcg== # base64-encoded "checkout_user"
```

---

## The Base64 Myth — Kubernetes Secrets Are Not Encrypted by Default

This is the most important thing to understand about Kubernetes Secrets:

```
base64 encoding ≠ encryption

echo "supersecret" | base64
→ c3VwZXJzZWNyZXQ=

echo "c3VwZXJzZWNyZXQ=" | base64 -d
→ supersecret

Anyone with access to the Secret object can trivially decode it.
```

**Default Kubernetes Secret storage:**
- Stored in etcd as base64-encoded plaintext
- Anyone with `kubectl get secret` access can read all values
- etcd backups contain plaintext secrets
- etcd traffic contains plaintext secrets (if not TLS encrypted)

**What this means in practice:**
A Kubernetes Secret without encryption at rest provides access control (RBAC) but not confidentiality. If etcd is compromised, all secrets are compromised.

---

## Encryption at Rest

Kubernetes supports encrypting Secret data before writing to etcd using a `EncryptionConfiguration`.

### Encryption Providers

| Provider | Key management | Security level |
|----------|---------------|----------------|
| `identity` | None (default) | No encryption |
| `aescbc` | Local key in config file | Encrypted, but key is on disk |
| `aesgcm` | Local key in config file | Encrypted, key on disk |
| `secretbox` | Local key in config file | Encrypted, key on disk |
| `kms` (v1) | External KMS (Key Vault, KMS) | Best — key never on disk |
| `kms` (v2) | External KMS, DEK caching | Best — improved performance |

### KMS Encryption (Recommended for Production)

KMS encryption uses an external key management service (Azure Key Vault, AWS KMS, HashiCorp Vault) to hold the encryption key. Kubernetes never has the key in plaintext — it sends data to the KMS for encryption/decryption.

**AKS — Encryption at Rest with Azure Key Vault:**

```bash
# Create Key Vault and key for AKS encryption
az keyvault create \
  --name aks-etcd-keyvault \
  --resource-group myRG \
  --location westeurope \
  --enable-rbac-authorization true

az keyvault key create \
  --vault-name aks-etcd-keyvault \
  --name aks-encryption-key \
  --kty RSA \
  --size 2048

# Enable KMS encryption on AKS cluster
az aks update \
  --resource-group myRG \
  --name myAKS \
  --enable-azure-keyvault-kms \
  --azure-keyvault-kms-key-id \
    "https://aks-etcd-keyvault.vault.azure.net/keys/aks-encryption-key/<version>" \
  --azure-keyvault-kms-key-vault-network-access Public
```

With KMS enabled, every Secret written to etcd is encrypted with a data encryption key (DEK), and the DEK is encrypted with the key in Azure Key Vault. etcd never contains plaintext secrets.

### Verifying Encryption at Rest

```bash
# Check if a secret is encrypted in etcd
# Run from a control plane node or via AKS API server

kubectl create secret generic test-secret \
  --from-literal=test-key=test-value \
  -n default

# Read directly from etcd (bypasses K8s API decryption)
ETCDCTL_API=3 etcdctl \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key \
  get /registry/secrets/default/test-secret | hexdump -C

# Without KMS: you'll see base64-encoded plaintext
# With KMS: you'll see encrypted binary data starting with "k8s:enc:kms:v2:"
```

---

## Secret Types

Kubernetes defines built-in secret types for common use cases:

| Type | Used for |
|------|---------|
| `Opaque` | Arbitrary user-defined data (most common) |
| `kubernetes.io/service-account-token` | ServiceAccount tokens |
| `kubernetes.io/dockerconfigjson` | Docker registry credentials |
| `kubernetes.io/tls` | TLS certificate and key |
| `kubernetes.io/ssh-auth` | SSH authentication keys |
| `kubernetes.io/basic-auth` | Username/password |
| `bootstrap.kubernetes.io/token` | Node bootstrap tokens |

```bash
# Create a TLS secret from cert files
kubectl create secret tls checkout-tls \
  --cert=checkout.crt \
  --key=checkout.key \
  -n checkout

# Create a docker registry secret
kubectl create secret docker-registry myregistry-cred \
  --docker-server=myregistry.azurecr.io \
  --docker-username=<username> \
  --docker-password=<password> \
  -n checkout
```

---

## Consuming Secrets in Pods

### Method 1: Environment Variables

```yaml
containers:
  - name: checkout-api
    image: myregistry/checkout-api:latest
    env:
      # Single key from secret
      - name: DB_PASSWORD
        valueFrom:
          secretKeyRef:
            name: checkout-db-secret
            key: db-password

      # All keys from secret as env vars
    envFrom:
      - secretRef:
          name: checkout-db-secret
```

**Limitation:** Environment variables are visible to all processes in the container, may appear in process listings, and don't update when the Secret changes (pod restart required).

### Method 2: Volume Mounts (preferred)

```yaml
volumes:
  - name: db-secret-vol
    secret:
      secretName: checkout-db-secret
      defaultMode: 0400       # Read-only for owner only

containers:
  - name: checkout-api
    volumeMounts:
      - name: db-secret-vol
        mountPath: /var/secrets/db
        readOnly: true

# Results in files:
# /var/secrets/db/db-password  (content: "supersecret")
# /var/secrets/db/db-username  (content: "checkout_user")
```

**Advantages of volume mounts:**
- Secret updates propagate to running pods (within the kubelet sync period, ~1 min)
- Files can have restrictive permissions (0400)
- Secrets are in a tmpfs mount — not written to container disk
- Application reads file → less exposure than process environment

### Method 3: Projected Volumes (combining multiple sources)

```yaml
volumes:
  - name: all-secrets
    projected:
      sources:
        - secret:
            name: checkout-db-secret
        - secret:
            name: checkout-api-keys
        - configMap:
            name: checkout-config
        - serviceAccountToken:
            path: vault-token
            expirationSeconds: 3600
            audience: vault
```

Projected volumes combine secrets, configmaps, and tokens into a single mount point.

---

## RBAC for Secrets — Least Privilege

RBAC is the primary access control mechanism for Kubernetes Secrets. Without proper RBAC, any pod in the cluster could read any secret.

### Viewing Current Secret Access

```bash
# Who can read secrets in the checkout namespace?
kubectl auth can-i get secrets \
  --namespace checkout \
  --as system:serviceaccount:checkout:checkout-sa

# List all rolebindings in a namespace
kubectl get rolebindings,clusterrolebindings \
  --all-namespaces \
  -o custom-columns='KIND:kind,NAMESPACE:metadata.namespace,NAME:metadata.name,ROLE:roleRef.name,SUBJECTS:subjects[*].name'
```

### Creating Least-Privilege Secret Access

```yaml
# Role — read only specific secrets in checkout namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: checkout-secret-reader
  namespace: checkout
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["checkout-db-secret", "checkout-api-keys"]  # Only these secrets
    verbs: ["get"]
  # Note: no "list" permission — can't enumerate all secrets

---
# RoleBinding — bind role to ServiceAccount
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: checkout-secret-reader-binding
  namespace: checkout
subjects:
  - kind: ServiceAccount
    name: checkout-sa
    namespace: checkout
roleRef:
  kind: Role
  name: checkout-secret-reader
  apiGroup: rbac.authorization.k8s.io
```

**Key RBAC rules for secrets:**
- Never grant `list` on secrets without `resourceNames` — it allows enumerating all secrets
- Never grant `watch` on secrets — it allows receiving secret values on changes
- Use `resourceNames` to restrict to specific secrets, not all secrets in a namespace
- Avoid ClusterRoles with secret access — namespace-scoped Roles are safer

### Audit Secret Access with RBAC

```bash
# Find all ServiceAccounts that can read secrets
kubectl auth can-i get secrets \
  --as system:serviceaccount:default:default \
  --namespace checkout

# Use kubectl-who-can (plugin) for comprehensive view
kubectl-who-can get secrets -n checkout
```

---

## Immutable Secrets

Immutable secrets prevent changes after creation — useful for secrets baked into deployments:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: checkout-immutable-config
  namespace: checkout
type: Opaque
immutable: true          # Cannot be modified — only deleted and recreated
data:
  config-hash: "abc123"
```

Benefits:
- Protects against accidental modification
- Improves kube-apiserver performance (no need to watch for changes)
- Forces intentional rotation (delete + recreate)

---

## Secret Size Limits and Best Practices

```
Maximum secret size: 1MB (etcd limit)
Maximum secrets per namespace: no hard limit, but watch etcd memory
```

### Best Practices Summary

```
✅ DO:
  - Enable encryption at rest (KMS provider)
  - Use volume mounts over environment variables
  - Apply RBAC with specific resourceNames
  - Set appropriate file permissions (0400 or 0440)
  - Use External Secrets Operator to sync from Key Vault/Vault
  - Enable audit logging on the API server
  - Use namespaces to isolate secrets between teams

❌ DON'T:
  - Assume base64 = encrypted
  - Grant list/watch on secrets without resourceNames
  - Use default ServiceAccount (has broad permissions)
  - Store secrets in ConfigMaps
  - Log secret values in application code
  - Mount secrets you don't need in a pod
  - Use ClusterRoleBindings for secret access unless truly cross-namespace
```

---

## Interview Questions — Kubernetes Secrets

**Q: Are Kubernetes Secrets secure by default?**
A: No. By default, Kubernetes Secrets are base64-encoded (not encrypted) and stored in plaintext in etcd. Base64 is trivially reversible. Anyone with etcd access or a backup of etcd has all secrets in plaintext. To make secrets secure, you must: enable encryption at rest (preferably with a KMS provider like Azure Key Vault), apply strict RBAC to limit who can read secrets, and use external secret management systems (ESO, Vault) where possible.

**Q: What is the difference between using environment variables and volume mounts for secrets?**
A: Volume mounts are preferred. They store secrets in tmpfs (not on disk), support automatic updates when secrets change (without pod restart), allow restrictive file permissions (0400), and are not visible in process environment dumps. Environment variables are visible to all processes, appear in crash reports and debug dumps, and don't update without a pod restart.

**Q: How do you restrict a ServiceAccount to only read specific secrets?**
A: Create a Role with the `get` verb on the specific `resourceNames` (secret names). Avoid `list` and `watch` without resourceNames — these allow enumerating all secrets or receiving their values on changes. Bind the Role to the ServiceAccount via a RoleBinding in the same namespace. Never use ClusterRoles for secret access unless cross-namespace access is genuinely needed.

**Q: What is encryption at rest for Kubernetes Secrets and how does it work with Azure?**
A: Encryption at rest encrypts secret data before writing to etcd. With AKS and Azure Key Vault KMS, each secret is encrypted with a data encryption key (DEK), and the DEK is wrapped (encrypted) by a key stored in Azure Key Vault. etcd stores only encrypted data — the encryption key never touches etcd. If etcd is compromised, the data is unreadable without access to Azure Key Vault.
