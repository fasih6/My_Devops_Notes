# Secrets in GitOps

## The Core Problem

GitOps = Git is source of truth. But secrets cannot be stored in Git in plaintext. Three solutions exist, each with different trade-offs.

| Solution | Where secret lives | What's in Git | Best for |
|----------|-------------------|---------------|---------|
| Sealed Secrets | etcd (cluster) | Encrypted blob | Simple setups, one cluster |
| SOPS | Key management service | Encrypted YAML | Multi-cluster, team-managed keys |
| External Secrets Operator | Vault / AWS SM / Azure KV | ExternalSecret manifest (no secret value) | Enterprise, existing secret stores |

## Sealed Secrets

Bitnami Sealed Secrets encrypts a K8s Secret with the **cluster's public key**. Only that cluster can decrypt it. Safe to commit to Git.

```bash
# Install controller
helm repo add sealed-secrets https://bitnami-labs.github.io/sealed-secrets
helm install sealed-secrets sealed-secrets/sealed-secrets -n kube-system

# Install kubeseal CLI
brew install kubeseal

# Fetch cluster's public certificate
kubeseal --fetch-cert > cluster-cert.pem

# Create and seal a secret
kubectl create secret generic db-creds \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml \
  | kubeseal --cert cluster-cert.pem --format yaml \
  > sealed-db-creds.yaml   # ← safe to commit

git add sealed-db-creds.yaml && git commit -m "feat: add sealed DB creds"
```

```yaml
# What a SealedSecret looks like — safe to commit
apiVersion: bitnami.com/v1alpha1
kind: SealedSecret
metadata:
  name: db-creds
  namespace: production
spec:
  encryptedData:
    password: AgBy3i4OJSWK+PiTySYZZA9rO43cGDEq...
  template:
    metadata:
      name: db-creds
      namespace: production
```

Scopes (controls portability):
- `strict` (default) — bound to exact name + namespace
- `namespace-wide` — can be renamed within namespace
- `cluster-wide` — usable anywhere in cluster

Rotation: when the cluster's sealing key rotates (every 30 days by default), old secrets still decrypt. Use `--re-encrypt` to update old SealedSecrets to the new key.

## SOPS — Encrypt Files with Age or KMS

SOPS encrypts specific fields in YAML files. Works with Age keys, PGP, AWS KMS, GCP KMS, Azure Key Vault.

```bash
# Install
brew install sops age

# Generate Age key pair
age-keygen -o ~/.config/sops/age/keys.txt
# Public key: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p

# .sops.yaml — configuration file (commit this)
creation_rules:
  - path_regex: .*/secrets/.*\.yaml
    age: age1ql3z7hjy54pw3hyww5ayyfg7zqgvc7w3j2elw8zmrj2kg5sfn9aqmcac8p
    encrypted_regex: "^(data|stringData)$"   # only encrypt these keys

# Encrypt a secret file
sops --encrypt secrets/db-creds.yaml > secrets/db-creds.enc.yaml
# Or encrypt in-place:
sops --encrypt --in-place secrets/db-creds.yaml

# Decrypt (requires private key)
sops --decrypt secrets/db-creds.enc.yaml

# Edit encrypted file (decrypts to editor, re-encrypts on save)
sops secrets/db-creds.yaml
```

Flux SOPS decryption:
```yaml
# Tell Flux to decrypt with SOPS
spec:
  decryption:
    provider: sops
    secretRef:
      name: sops-age-key

---
# Create the decryption key secret (one-time setup)
# kubectl create secret generic sops-age-key \
#   --from-file=age.agekey=~/.config/sops/age/keys.txt \
#   -n flux-system
```

AWS KMS with SOPS (no key to manage locally):
```yaml
# .sops.yaml
creation_rules:
  - kms: arn:aws:kms:eu-central-1:123456789:key/abc-123
    encrypted_regex: "^(data|stringData)$"
```

## External Secrets Operator (ESO)

ESO syncs secrets from external stores into K8s Secrets at runtime. Nothing secret ever touches Git.

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  -n external-secrets --create-namespace
```

```yaml
# SecretStore — connection to Vault (commit this — no secrets)
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: production
spec:
  provider:
    vault:
      server: "https://vault.example.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "production-apps"

---
# ExternalSecret — what to pull (commit this — no secrets)
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-creds
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: db-creds             # creates this K8s Secret
    creationPolicy: Owner
  data:
    - secretKey: password      # key in resulting K8s Secret
      remoteRef:
        key: production/myapp/db   # path in Vault
        property: password

---
# ESO with AWS Secrets Manager + IRSA
apiVersion: external-secrets.io/v1beta1
kind: ClusterSecretStore
metadata:
  name: aws-secrets-manager
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-central-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa
            namespace: external-secrets
```

## Choosing Between Them

```
Single cluster, small team, simple needs → Sealed Secrets
  Easy to start, zero external dependencies

Multi-cluster or want key flexibility → SOPS + Age/KMS
  Works everywhere, key rotation without re-sealing

Enterprise with Vault/AWS SM already → ESO
  Best long-term, central secret governance, audit trail
  Secrets never in Git even in encrypted form
```
