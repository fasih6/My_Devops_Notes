# Secrets Management

## The Secrets Problem

A "secret" is any sensitive credential: API keys, database passwords, private keys, certificates, tokens.

Secrets in code are one of the most common and impactful security failures:
- Hardcoded in source code (committed to Git — permanent exposure)
- In environment files (`.env`) committed accidentally
- In CI/CD logs (printed by verbose scripts)
- Baked into Docker images
- In Kubernetes YAML committed to repos

The rule: **secrets should never be in your code, your configs, or your container images.**

## Secret Detection — Prevent Leaks Before They Happen

### truffleHog

Scans Git history for secrets. Finds things even after commits are deleted (Git history is permanent).

```bash
# Install
pip install trufflehog

# Scan a git repo (local)
trufflehog git file://./

# Scan a remote GitHub repo
trufflehog github --repo https://github.com/org/repo

# Scan a specific branch
trufflehog git file://./ --branch main

# Scan only recent commits (last 50)
trufflehog git file://./ --since-commit HEAD~50

# JSON output
trufflehog git file://./ --json
```

### git-secrets (AWS)

Prevents committing AWS credentials and other patterns.

```bash
# Install
brew install git-secrets

# Set up in a repo
git secrets --install
git secrets --register-aws  # adds AWS key patterns

# Add custom patterns
git secrets --add 'password\s*=\s*.+'
git secrets --add 'api_key\s*=\s*.+'

# Scan existing history
git secrets --scan-history

# Scan staged changes
git secrets --scan
```

### detect-secrets (Yelp)

A baseline-based secret detector — tracks known false positives.

```bash
# Install
pip install detect-secrets

# Create a baseline (initial scan)
detect-secrets scan > .secrets.baseline

# Update baseline after reviewing
detect-secrets scan --update .secrets.baseline

# Audit baseline (mark false positives)
detect-secrets audit .secrets.baseline

# Use as pre-commit hook
detect-secrets-hook --baseline .secrets.baseline
```

### Gitleaks

Fast, widely used in CI/CD pipelines.

```bash
# Install
brew install gitleaks

# Scan a repo
gitleaks detect --source .

# Scan git history
gitleaks detect --source . --log-opts="--all"

# Protect mode (pre-commit hook style)
gitleaks protect --staged

# Output to SARIF (for GitHub/GitLab security reports)
gitleaks detect --source . --report-format sarif --report-path results.sarif
```

Pre-commit hook integration:
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

## HashiCorp Vault

The industry-standard secrets manager for dynamic secrets, rotation, and auditing.

### Core Concepts

```
┌─────────────────────────────────────────────────────┐
│                   HashiCorp Vault                    │
│                                                      │
│  Auth Methods        Secret Engines    Policies      │
│  ─────────────       ─────────────     ────────      │
│  • Kubernetes        • KV (static)     • Who can     │
│  • AWS IAM           • Database        • read what   │
│  • OIDC/JWT          • PKI (certs)                   │
│  • AppRole           • AWS (dynamic)                 │
│  • Token             • SSH                           │
│                                                      │
│  Audit Log — every read/write/delete is logged       │
└─────────────────────────────────────────────────────┘
```

### Basic Vault Operations

```bash
# Start dev server (for learning only — never in prod)
vault server -dev

# Set env vars
export VAULT_ADDR='http://127.0.0.1:8200'
export VAULT_TOKEN='dev-root-token'

# Write a secret (KV v2)
vault kv put secret/myapp/database \
  username=dbuser \
  password=supersecret

# Read a secret
vault kv get secret/myapp/database

# Read a specific field
vault kv get -field=password secret/myapp/database

# List secrets
vault kv list secret/myapp/

# Delete a secret
vault kv delete secret/myapp/database

# View secret history (KV v2)
vault kv metadata get secret/myapp/database
vault kv get -version=2 secret/myapp/database
```

### Dynamic Secrets (Database Example)

This is where Vault shines — generating short-lived, unique credentials per request.

```bash
# Enable database secrets engine
vault secrets enable database

# Configure a PostgreSQL connection
vault write database/config/mypostgres \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@postgres:5432/mydb" \
  allowed_roles="app-role" \
  username="vault-admin" \
  password="vault-admin-password"

# Create a role with 1-hour lease
vault write database/roles/app-role \
  db_name=mypostgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; \
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

# Generate credentials (each call creates a unique user)
vault read database/creds/app-role
# Returns:
# lease_id   = database/creds/app-role/abc123...
# username   = v-app-role-xyz789
# password   = A1B2C3D4...
# (credentials auto-expire after 1h and user is deleted)
```

### Kubernetes Auth Method

How pods authenticate with Vault without static tokens.

```bash
# Enable Kubernetes auth
vault auth enable kubernetes

# Configure it
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Create a policy
vault policy write myapp-policy - <<EOF
path "secret/data/myapp/*" {
  capabilities = ["read"]
}
EOF

# Create a role binding service account to policy
vault write auth/kubernetes/role/myapp \
  bound_service_account_names=myapp-sa \
  bound_service_account_namespaces=production \
  policies=myapp-policy \
  ttl=1h
```

Pod using Vault Agent to get secrets:
```yaml
apiVersion: v1
kind: Pod
metadata:
  name: myapp
  annotations:
    vault.hashicorp.com/agent-inject: "true"
    vault.hashicorp.com/role: "myapp"
    vault.hashicorp.com/agent-inject-secret-config: "secret/data/myapp/config"
    vault.hashicorp.com/agent-inject-template-config: |
      {{- with secret "secret/data/myapp/config" -}}
      export DB_PASSWORD="{{ .Data.data.db_password }}"
      {{- end }}
spec:
  serviceAccountName: myapp-sa
  containers:
  - name: app
    image: myapp:latest
```

## External Secrets Operator (ESO)

ESO syncs secrets from external secret stores (Vault, AWS Secrets Manager, Azure Key Vault, GCP Secret Manager) into Kubernetes Secrets automatically.

```yaml
# Install
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets -n external-secrets --create-namespace

# SecretStore — connection to Vault
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: vault-backend
  namespace: production
spec:
  provider:
    vault:
      server: "https://vault.company.com"
      path: "secret"
      version: "v2"
      auth:
        kubernetes:
          mountPath: "kubernetes"
          role: "myapp"

---
# ExternalSecret — which secrets to pull and how to map them
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: myapp-secrets
  namespace: production
spec:
  refreshInterval: 1h            # re-sync every hour
  secretStoreRef:
    name: vault-backend
    kind: SecretStore
  target:
    name: myapp-secret           # creates this K8s Secret
    creationPolicy: Owner
  data:
  - secretKey: DB_PASSWORD       # key in the K8s Secret
    remoteRef:
      key: myapp/config          # path in Vault
      property: db_password      # field in Vault secret
```

ESO with AWS Secrets Manager:
```yaml
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secrets
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-central-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa  # uses IRSA (IAM Roles for Service Accounts)
```

## Kubernetes Secrets — The Problem

Kubernetes native Secrets are base64 encoded, not encrypted. Anyone with kubectl access can read them.

```bash
# This is NOT encryption
kubectl get secret myapp-secret -o jsonpath='{.data.password}' | base64 -d
# prints the actual password

# Secrets are stored unencrypted in etcd by default
# Anyone with etcd access can read all secrets
```

### Encryption at Rest for etcd

```yaml
# EncryptionConfiguration — encrypts secrets in etcd
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
    - secrets
    providers:
    - aescbc:
        keys:
        - name: key1
          secret: <base64-encoded-32-byte-key>
    - identity: {}  # fallback for reading existing unencrypted data
```

### Sealed Secrets (Bitnami)

Encrypts K8s Secrets so they can safely be committed to Git.

```bash
# Install kubeseal
brew install kubeseal

# Get the certificate from the cluster
kubeseal --fetch-cert > public-cert.pem

# Create a regular K8s secret
kubectl create secret generic myapp-secret \
  --from-literal=password=supersecret \
  --dry-run=client -o yaml > secret.yaml

# Seal it (encrypt with cluster's public key)
kubeseal --cert public-cert.pem --format yaml < secret.yaml > sealed-secret.yaml

# Commit sealed-secret.yaml to Git safely
# Only the cluster can decrypt it

# Apply to cluster
kubectl apply -f sealed-secret.yaml
```

## Secrets in CI/CD Pipelines

```yaml
# GitLab CI — correct way to use secrets
# Store secrets in GitLab CI/CD Variables (masked and protected)
# Access via environment variables — NEVER print them

deploy:
  script:
    - echo "Deploying to ${ENVIRONMENT}"
    - kubectl create secret generic app-secret
        --from-literal=db-password=${DB_PASSWORD}  # injected from CI var
        --dry-run=client -o yaml | kubectl apply -f -

  # WRONG — leaks secret to logs
  # - echo "Using password: ${DB_PASSWORD}"
```

Vault integration in GitLab CI:
```yaml
# Use GitLab's native Vault integration (JWT auth)
deploy:
  id_tokens:
    VAULT_ID_TOKEN:
      aud: https://vault.company.com
  secrets:
    DB_PASSWORD:
      vault: production/data/myapp/config/db_password@secret
      file: false
  script:
    - echo "DB password is available as $DB_PASSWORD"
```

## Secret Rotation

Static secrets should be rotated regularly. Dynamic secrets (Vault) rotate automatically.

Rotation strategy:
```
Static credentials rotation process:
1. Generate new credential
2. Update all consumers (zero-downtime: add new, remove old)
3. Revoke old credential
4. Verify no usage of old credential

Rotation frequency (recommended):
- Service account keys: 90 days
- API keys: 90 days  
- Database passwords: 30 days (or use dynamic secrets)
- TLS certificates: 90 days (or automate with cert-manager)
- Signing keys: annually
```

## What Never to Do

```bash
# NEVER hardcode secrets
database_password = "SuperSecret123"
api_key = "sk-abc123..."

# NEVER in environment files committed to Git
# .env
DB_PASSWORD=mysecretpassword  # committed to repo

# NEVER in Dockerfiles
ENV API_KEY=sk-abc123

# NEVER in K8s YAML committed to Git
apiVersion: v1
kind: Secret
data:
  password: bXlzZWNyZXQ=  # base64 of "mysecret" — still readable!

# NEVER print secrets in logs
echo "Using token: $MY_SECRET_TOKEN"
```

## Secret Scanning in CI — GitLab Native

```yaml
# GitLab built-in secret detection
include:
  - template: Security/Secret-Detection.gitlab-ci.yml

variables:
  SECRET_DETECTION_HISTORIC_SCAN: "true"  # also scan git history
```
