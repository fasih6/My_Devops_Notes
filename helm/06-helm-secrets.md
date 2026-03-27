# 🔐 Secrets Management

Encrypting sensitive values in Helm — helm-secrets, SOPS, and Vault integration.

---

## 📚 Table of Contents

- [1. The Problem with Helm Values & Secrets](#1-the-problem-with-helm-values--secrets)
- [2. helm-secrets + SOPS](#2-helm-secrets--sops)
- [3. SOPS Encryption Backends](#3-sops-encryption-backends)
- [4. Workflow with helm-secrets](#4-workflow-with-helm-secrets)
- [5. Vault Integration](#5-vault-integration)
- [6. External Secrets Operator (Recap)](#6-external-secrets-operator-recap)
- [7. Secrets Management Comparison](#7-secrets-management-comparison)
- [Cheatsheet](#cheatsheet)

---

## 1. The Problem with Helm Values & Secrets

```yaml
# values-production.yaml — NEVER commit this to Git as-is
database:
  password: MySuperSecretPassword123
  apiKey: sk-abc123xyz
  tlsKey: |
    -----BEGIN PRIVATE KEY-----
    MIIEvQIBADANBgkqhkiG9w0BAQEFAASC...
    -----END PRIVATE KEY-----
```

The challenge: values files are plain text and need to be in Git for GitOps to work. The solution: encrypt the sensitive values before committing.

### Options

| Approach | Encryption | Where secrets live | Complexity |
|----------|-----------|-------------------|-----------|
| **helm-secrets + SOPS** | File-level encryption | Git (encrypted) | Low-medium |
| **Vault + Agent Injector** | Vault manages secrets | Vault | Medium-high |
| **External Secrets Operator** | Cloud secrets manager | AWS/GCP/Azure SM | Medium |
| **Sealed Secrets** | Public key encryption | Git (encrypted) | Low |

---

## 2. helm-secrets + SOPS

**SOPS** (Secrets OPerationS) encrypts YAML/JSON files using age, PGP, AWS KMS, GCP KMS, or Azure Key Vault. **helm-secrets** is a Helm plugin that decrypts SOPS-encrypted files before passing them to Helm.

### Install

```bash
# Install helm-secrets plugin
helm plugin install https://github.com/jkroepke/helm-secrets

# Install SOPS
brew install sops        # macOS
# OR download from: https://github.com/getsops/sops/releases

# Install age (modern encryption, recommended over PGP)
brew install age         # macOS
apt install age          # Ubuntu
```

### Create an age key pair

```bash
# Generate age key pair
age-keygen -o ~/.config/sops/age/keys.txt

# Output:
# Public key: age1abc123xyz...
# Secret key written to /Users/fasih/.config/sops/age/keys.txt

# Set environment variable for SOPS to find the key
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt
```

### Configure SOPS — .sops.yaml

```yaml
# .sops.yaml — in the root of your helm chart or repo
creation_rules:
  # Encrypt files matching this pattern with age
  - path_regex: secrets.*\.yaml$
    age: >-
      age1abc123publickey...
      age1def456publickey...   # multiple keys — any can decrypt

  # Different encryption for different environments
  - path_regex: secrets/production/.*\.yaml$
    age: age1prodpublickey...
    aws_profile: production

  - path_regex: secrets/staging/.*\.yaml$
    age: age1stagingpublickey...
```

---

## 3. SOPS Encryption Backends

### age (recommended — simple and modern)

```bash
# Generate key
age-keygen -o keys.txt

# Encrypt
SOPS_AGE_RECIPIENTS=age1abc123... sops -e secrets.yaml > secrets.enc.yaml

# Decrypt
SOPS_AGE_KEY_FILE=keys.txt sops -d secrets.enc.yaml
```

### AWS KMS

```bash
# Create a KMS key in AWS Console or CLI
aws kms create-key --description "Helm secrets key"

# .sops.yaml
creation_rules:
  - path_regex: secrets\.yaml$
    kms: arn:aws:kms:eu-central-1:123456789:key/mrk-abc123

# Encrypt (uses AWS credentials from environment)
sops -e secrets.yaml > secrets.enc.yaml

# No key file needed — AWS IAM controls access
```

### GCP KMS

```yaml
# .sops.yaml
creation_rules:
  - path_regex: secrets\.yaml$
    gcp_kms: projects/my-project/locations/global/keyRings/my-ring/cryptoKeys/my-key
```

### PGP (older, more complex)

```bash
# Generate PGP key
gpg --full-generate-key

# Get fingerprint
gpg --list-keys

# .sops.yaml
creation_rules:
  - path_regex: secrets\.yaml$
    pgp: ABC123DEF456...   # fingerprint
```

---

## 4. Workflow with helm-secrets

### Create and encrypt a secrets file

```yaml
# secrets.yaml — plaintext (NEVER commit this)
database:
  password: MySuperSecret123
  apiKey: sk-abc123xyz
redis:
  password: RedisPassword456
```

```bash
# Encrypt in place
sops -e -i secrets.yaml
# OR encrypt to new file
sops -e secrets.yaml > secrets.enc.yaml

# Encrypted file looks like:
# database:
#     password: ENC[AES256_GCM,data:abc123...,iv:...,tag:...,type:str]
#     apiKey: ENC[AES256_GCM,data:xyz789...,iv:...,tag:...,type:str]
# sops:
#     kms: []
#     gcp_kms: []
#     age:
#         - recipient: age1abc123...
#           enc: |
#             -----BEGIN AGE ENCRYPTED FILE-----
#             ...
```

### Edit an encrypted file

```bash
# Opens in $EDITOR, decrypted — saves encrypted
sops secrets.enc.yaml

# View without editing
sops -d secrets.enc.yaml
```

### Use encrypted files with Helm

```bash
# helm secrets - prefix tells the plugin to decrypt before use
helm secrets install my-app ./my-chart \
  -f values.yaml \
  -f secrets/secrets.enc.yaml

helm secrets upgrade my-app ./my-chart \
  -f values.yaml \
  -f secrets/production.enc.yaml \
  --set image.tag=v1.2.3

# upgrade --install (idempotent)
helm secrets upgrade --install my-app ./my-chart \
  -f values.yaml \
  -f secrets/production.enc.yaml

# Dry run with decryption
helm secrets template my-app ./my-chart \
  -f values.yaml \
  -f secrets/production.enc.yaml
```

### Project structure

```
my-chart/
├── Chart.yaml
├── values.yaml               # non-sensitive defaults — commit freely
├── values-production.yaml    # production overrides (non-sensitive) — commit
├── values-staging.yaml       # staging overrides — commit
├── secrets/
│   ├── .sops.yaml           # SOPS config — commit
│   ├── production.enc.yaml  # encrypted secrets — commit
│   └── staging.enc.yaml     # encrypted secrets — commit
└── templates/
    └── ...
```

### Rotating encrypted secrets

```bash
# Update a secret value
sops secrets/production.enc.yaml
# Edit the value in your editor, save — SOPS re-encrypts

# Rotate encryption keys (re-encrypt with new key)
sops updatekeys secrets/production.enc.yaml
# Updates .sops.yaml with new keys first, then run this
```

---

## 5. Vault Integration

HashiCorp Vault is a secrets management platform. Kubernetes pods can authenticate to Vault and retrieve secrets dynamically.

### Vault Agent Injector

The Vault Agent Injector injects a sidecar into pods that annotates with Vault config.

```yaml
# Deployment with Vault Agent injector annotations
spec:
  template:
    metadata:
      annotations:
        vault.hashicorp.com/agent-inject: "true"
        vault.hashicorp.com/role: "my-app"
        vault.hashicorp.com/agent-inject-secret-db: "secret/data/production/database"
        vault.hashicorp.com/agent-inject-template-db: |
          {{- with secret "secret/data/production/database" -}}
          export DB_PASSWORD="{{ .Data.data.password }}"
          export DB_USERNAME="{{ .Data.data.username }}"
          {{- end }}
```

The agent writes the secret to `/vault/secrets/db` inside the pod.

### Vault Secrets Operator (newer approach)

```yaml
# VaultStaticSecret — syncs Vault secret to K8s Secret
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: db-credentials
  namespace: production
spec:
  type: kv-v2
  mount: secret
  path: production/database
  destination:
    name: db-secret              # creates/updates this K8s Secret
    create: true
  refreshAfter: 30s
  vaultAuthRef: default
```

### Helm chart for Vault integration

```bash
# Install Vault
helm repo add hashicorp https://helm.releases.hashicorp.com
helm install vault hashicorp/vault \
  --namespace vault \
  --create-namespace \
  --set "server.ha.enabled=true" \
  --set "server.ha.replicas=3"

# Install Vault Secrets Operator
helm install vault-secrets-operator hashicorp/vault-secrets-operator \
  --namespace vault-secrets-operator-system \
  --create-namespace
```

---

## 6. External Secrets Operator (Recap)

Syncs secrets from AWS Secrets Manager, GCP Secret Manager, Azure Key Vault, or Vault into Kubernetes Secrets automatically.

```yaml
# ExternalSecret — pulls from AWS Secrets Manager
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: production-db-secret
  namespace: production
spec:
  refreshInterval: 1h
  secretStoreRef:
    name: aws-secret-store
    kind: SecretStore
  target:
    name: db-secret
    creationPolicy: Owner
  data:
    - secretKey: password
      remoteRef:
        key: production/myapp/database
        property: password
```

```yaml
# Use in Helm values.yaml
config:
  database:
    existingSecret: db-secret    # references the synced K8s Secret
    passwordKey: password
```

---

## 7. Secrets Management Comparison

| | helm-secrets + SOPS | Vault | External Secrets |
|--|---------------------|-------|-----------------|
| **Secret storage** | Git (encrypted) | Vault server | Cloud SM |
| **Key management** | age/KMS keys | Vault policies | IAM roles |
| **Rotation** | Manual re-encrypt | Vault handles | Cloud SM handles |
| **GitOps friendly** | ✅ Yes | ⚠️ Partial | ✅ Yes |
| **Setup complexity** | Low | High | Medium |
| **Best for** | Small teams, simple setup | Large orgs, dynamic secrets | Cloud-native environments |

### Recommended approach by team size

```
Small team / startup:
  → helm-secrets + SOPS + age keys stored in password manager

Medium team:
  → External Secrets Operator + AWS Secrets Manager / GCP SM
  → Secrets live in cloud, synced to K8s automatically

Large enterprise:
  → HashiCorp Vault with dynamic secrets
  → Short-lived credentials, fine-grained access control
```

---

## Cheatsheet

```bash
# SOPS + age
age-keygen -o ~/.config/sops/age/keys.txt
export SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt

# Encrypt
sops -e secrets.yaml > secrets.enc.yaml
sops -e -i secrets.yaml          # in place

# Decrypt
sops -d secrets.enc.yaml
sops -d -i secrets.enc.yaml     # in place

# Edit encrypted file
sops secrets.enc.yaml

# helm-secrets
helm secrets install my-app ./chart -f values.yaml -f secrets.enc.yaml
helm secrets upgrade --install my-app ./chart -f values.yaml -f secrets.enc.yaml
helm secrets template my-app ./chart -f values.yaml -f secrets.enc.yaml

# View decrypted (for debugging)
helm secrets dec secrets.enc.yaml     # writes secrets.yaml.dec
```

---

*Next: [CI/CD Integration →](./07-cicd-integration.md)*
