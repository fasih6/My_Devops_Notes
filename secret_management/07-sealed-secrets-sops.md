# Sealed Secrets & SOPS — GitOps-Safe Secret Encryption

## The GitOps Secrets Problem

GitOps stores all desired state in Git. That's great for infrastructure and application config — but secrets cannot be committed to Git in plaintext.

```
The tension:
  GitOps principle: "Everything in Git"
  Security principle: "Never store secrets in Git"

  How do you reconcile these?
```

Two main solutions:
1. **Sealed Secrets** — encrypt K8s Secrets into SealedSecret objects safe for Git
2. **SOPS** — encrypt any file (YAML, JSON, .env) for Git, decrypt at apply time

Both let you commit encrypted secrets to Git while keeping the actual values protected.

---

## Sealed Secrets

### What Is Sealed Secrets?

Sealed Secrets is a Kubernetes controller + CLI tool by Bitnami. It works like this:

```
┌──────────────────────────────────────────────────────────┐
│                   Sealed Secrets Flow                     │
│                                                          │
│  1. SealedSecrets controller generates RSA key pair      │
│     Public key: available to everyone (used to encrypt)  │
│     Private key: stored in K8s Secret (never leaves)     │
│                                                          │
│  2. Developer encrypts a K8s Secret with the public key  │
│     kubeseal < secret.yaml > sealed-secret.yaml          │
│                                                          │
│  3. SealedSecret committed to Git (safe — encrypted)     │
│                                                          │
│  4. ArgoCD/Flux applies SealedSecret to cluster          │
│                                                          │
│  5. Controller decrypts with private key                 │
│     Creates standard K8s Secret                          │
│     Pod consumes K8s Secret normally                     │
└──────────────────────────────────────────────────────────┘
```

The private key never leaves the cluster. Only the cluster that generated the key pair can decrypt the SealedSecrets.

### Installing Sealed Secrets

```bash
# Install the controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets \
  --namespace kube-system \
  --set fullnameOverride=sealed-secrets-controller

# Install kubeseal CLI
# macOS
brew install kubeseal
# Linux
curl -sL https://github.com/bitnami-labs/sealed-secrets/releases/download/v0.24.0/kubeseal-0.24.0-linux-amd64.tar.gz \
  | tar xz && mv kubeseal /usr/local/bin/
```

### Creating a SealedSecret

```bash
# Step 1: Create a standard K8s Secret YAML (don't apply it)
kubectl create secret generic checkout-db-secret \
  --from-literal=db-password="supersecret" \
  --from-literal=db-username="checkout_user" \
  --namespace checkout \
  --dry-run=client \
  -o yaml > checkout-db-secret.yaml

# Step 2: Seal the secret (encrypts using cluster's public key)
kubeseal \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  --format yaml \
  < checkout-db-secret.yaml \
  > checkout-db-sealed-secret.yaml

# Step 3: Commit sealed-secret to Git (safe to commit)
git add checkout-db-sealed-secret.yaml
git commit -m "Add checkout DB sealed secret"

# Step 4: Apply to cluster (controller decrypts and creates K8s Secret)
kubectl apply -f checkout-db-sealed-secret.yaml
```

### SealedSecret Output

```yaml
# checkout-db-sealed-secret.yaml (safe to commit to Git)
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: checkout-db-secret
  namespace: checkout
spec:
  encryptedData:
    db-password: AgBKKmV3Xqp9... (long encrypted string)
    db-username: AgCHJKLmN8Rp... (long encrypted string)
  template:
    metadata:
      name: checkout-db-secret
      namespace: checkout
    type: Opaque
```

The encrypted values cannot be decrypted without the controller's private key. Committing this to Git is safe.

### Sealing Scopes

Sealed Secrets supports three scopes that control where the secret can be decrypted:

```bash
# Strict (default) — tied to specific name + namespace
# Cannot be moved to different namespace or renamed
kubeseal --scope strict < secret.yaml > sealed.yaml

# Namespace-wide — can be renamed within the same namespace
kubeseal --scope namespace-wide < secret.yaml > sealed.yaml

# Cluster-wide — can be used anywhere in the cluster
kubeseal --scope cluster-wide < secret.yaml > sealed.yaml
```

Use `strict` for production — it prevents a sealed secret from one namespace being applied in another.

### Key Rotation

The controller automatically generates new keys every 30 days. Old keys are kept to decrypt previously sealed secrets.

```bash
# Fetch the current public key (for offline sealing)
kubeseal --fetch-cert \
  --controller-name=sealed-secrets-controller \
  --controller-namespace=kube-system \
  > sealed-secrets-cert.pem

# Seal using a local cert (no cluster access needed)
kubeseal \
  --cert=sealed-secrets-cert.pem \
  --format yaml \
  < secret.yaml > sealed.yaml
```

### Re-sealing After Key Rotation

When keys rotate, existing SealedSecrets still work (old keys retained). But best practice is to re-seal with the new key:

```bash
# Re-seal all secrets in a directory with current key
for f in k8s/secrets/*.yaml; do
  kubeseal --re-encrypt < "$f" > "$f.new" && mv "$f.new" "$f"
done
git add k8s/secrets/ && git commit -m "Re-seal secrets with new key"
```

---

## SOPS (Secrets OPerationS)

### What Is SOPS?

SOPS is a file encryption tool by Mozilla. Unlike Sealed Secrets (Kubernetes-specific), SOPS can encrypt any file format — YAML, JSON, ENV, INI, binary.

SOPS encrypts only the values in a file, leaving keys/structure readable:

```yaml
# Before SOPS encryption:
database:
  password: supersecret
  username: checkout_user
stripe:
  api_key: sk_live_abc123

# After SOPS encryption:
database:
  password: ENC[AES256_GCM,data:abc123...,type:str]
  username: ENC[AES256_GCM,data:def456...,type:str]
stripe:
  api_key: ENC[AES256_GCM,data:ghi789...,type:str]
sops:
  kms: []
  age:
    - recipient: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac97
      enc: |
        -----BEGIN AGE ENCRYPTED FILE-----
        ...
  version: 3.8.1
```

The structure is readable — you can see which keys exist and do git diffs on structure changes. Only the values are encrypted.

### SOPS Key Backends

| Backend | Key management | Best for |
|---------|---------------|---------|
| **age** | Simple keypair | Individual developers, small teams |
| **PGP/GPG** | GPG keyring | Legacy, teams with GPG infrastructure |
| **AWS KMS** | AWS managed | AWS environments |
| **Azure Key Vault** | Azure managed | Azure environments |
| **GCP KMS** | GCP managed | GCP environments |
| **HashiCorp Vault** | Vault Transit | Multi-cloud, self-hosted |

### SOPS with age (Recommended for Simplicity)

age is a modern, simple encryption tool. No key servers, no trust web — just a keypair.

```bash
# Install age
brew install age        # macOS
apt install age         # Ubuntu

# Generate a keypair
age-keygen -o key.txt
# Output:
# Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac97
# key.txt contains the private key — keep this secret!

# Set private key location for SOPS
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
```

```yaml
# .sops.yaml — SOPS configuration (commit to Git, no secrets)
creation_rules:
  # Development secrets — encrypted with developer keys
  - path_regex: k8s/overlays/dev/.*\.yaml
    age: >-
      age1dev1abc...,
      age1dev2def...

  # Production secrets — encrypted with ops team keys + CI key
  - path_regex: k8s/overlays/prod/.*\.yaml
    age: >-
      age1ops1abc...,
      age1ops2def...,
      age1cicd123...         # CI/CD system's public key

  # Vault-specific secrets
  - path_regex: vault/.*\.yaml
    azure_keyvault: https://my-keyvault.vault.azure.net/keys/sops-key/version
```

```bash
# Encrypt a file
sops --encrypt k8s/overlays/prod/secrets.yaml > k8s/overlays/prod/secrets.enc.yaml

# Or encrypt in-place
sops --encrypt --in-place k8s/overlays/prod/secrets.yaml

# Edit an encrypted file (decrypts temporarily, opens editor, re-encrypts on save)
sops k8s/overlays/prod/secrets.yaml

# Decrypt (for piping to kubectl)
sops --decrypt k8s/overlays/prod/secrets.yaml | kubectl apply -f -

# View decrypted without writing to disk
sops --decrypt k8s/overlays/prod/secrets.yaml
```

### SOPS with Azure Key Vault

```bash
# Encrypt using Azure Key Vault key
sops --encrypt \
  --azure-kv https://my-keyvault.vault.azure.net/keys/sops-key/abc123 \
  secrets.yaml > secrets.enc.yaml

# .sops.yaml configuration
creation_rules:
  - path_regex: .*\.yaml
    azure_keyvault: https://my-keyvault.vault.azure.net/keys/sops-key/abc123
```

Decryption requires Azure access (Managed Identity or CLI login). In CI/CD, use Workload Identity or a service principal with `Key Vault Crypto User` role.

### SOPS with Flux (GitOps Integration)

Flux has native SOPS support — it decrypts SOPS-encrypted files before applying:

```bash
# Create the age private key as a K8s Secret (Flux reads this)
kubectl create secret generic sops-age \
  --namespace=flux-system \
  --from-file=age.agekey=~/.config/sops/age/keys.txt
```

```yaml
# Flux Kustomization — enable SOPS decryption
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: checkout-app
  namespace: flux-system
spec:
  interval: 10m
  path: ./k8s/overlays/prod
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
  decryption:
    provider: sops
    secretRef:
      name: sops-age               # Flux uses this key to decrypt
```

Flux automatically decrypts SOPS-encrypted YAML files in the path before applying. The private key lives in the cluster as a K8s Secret — never in Git.

### SOPS with ArgoCD

ArgoCD doesn't have native SOPS support but works via the `argocd-vault-plugin` or the `helm-secrets` plugin:

```yaml
# ArgoCD Application with SOPS via helm-secrets
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: checkout
spec:
  source:
    repoURL: https://github.com/myorg/myrepo
    targetRevision: main
    path: helm/checkout
    helm:
      valueFiles:
        - secrets+age-import:///helm-secrets-private-keys/key.txt?secrets.enc.yaml
```

---

## Sealed Secrets vs SOPS — When to Use Which

| Criteria | Sealed Secrets | SOPS |
|----------|---------------|------|
| Scope | Kubernetes Secrets only | Any file (YAML, JSON, .env, etc.) |
| Encryption unit | Entire K8s Secret | Individual values in any file |
| GitOps tool | Works with any (ArgoCD, Flux) | Native Flux support; ArgoCD needs plugin |
| Key management | Controller manages keys | You manage keys (age, KMS, etc.) |
| Structure readable in Git | No (entire object encrypted) | Yes (keys visible, values encrypted) |
| Cluster dependency | Yes — needs controller to decrypt | No — can decrypt anywhere with key |
| Multi-cluster | Needs re-sealing per cluster | Single key can cover all clusters |
| Developer UX | Simple (one CLI command) | Slightly more setup (.sops.yaml) |
| Rotation | Re-seal all secrets on key rotation | Re-encrypt files with new key |
| Best for | Pure K8s secrets, simple GitOps | Mixed files, multi-cluster, Helm values |

**Recommendation:**
- **Flux + SOPS (age or KMS):** cleanest GitOps experience, native integration
- **ArgoCD + Sealed Secrets:** simpler for teams new to GitOps secrets
- **Large orgs, multi-cluster:** SOPS with centralized KMS (Azure Key Vault / AWS KMS)

---

## Interview Questions — Sealed Secrets & SOPS

**Q: How do Sealed Secrets allow secrets to be committed to Git safely?**
A: The Sealed Secrets controller generates an RSA key pair. The public key is available to developers and used to encrypt Kubernetes Secrets into SealedSecret objects. The private key stays inside the cluster. SealedSecret objects — which contain only ciphertext — are safe to commit to Git. When ArgoCD or Flux applies them, the controller decrypts with the private key and creates standard Kubernetes Secrets.

**Q: What is the difference between Sealed Secrets and SOPS?**
A: Sealed Secrets works only with Kubernetes Secrets and encrypts the entire object. SOPS works with any file format (YAML, JSON, .env) and encrypts only values while leaving structure readable — making git diffs meaningful. SOPS supports multiple key backends (age, Azure Key Vault, AWS KMS) and isn't cluster-dependent. Sealed Secrets is simpler to set up; SOPS is more flexible and better suited for multi-cluster or mixed-file scenarios.

**Q: How does Flux handle SOPS-encrypted secrets?**
A: The age (or KMS) private key is stored as a Kubernetes Secret in the flux-system namespace. The Flux Kustomization resource is configured with `decryption.provider: sops` and a reference to that key secret. Flux automatically decrypts SOPS-encrypted files before applying them — the private key never leaves the cluster, and encrypted files are safe in Git.

**Q: What happens to Sealed Secrets when the controller's key rotates?**
A: The controller keeps all historical private keys — old SealedSecrets can still be decrypted. However, best practice is to re-seal all secrets with the new public key to ensure they can be decrypted even if old keys are eventually purged. This is done by running `kubeseal --re-encrypt` on all sealed secret files and committing the result to Git.
