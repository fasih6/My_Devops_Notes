# HashiCorp Vault — Architecture, Auth, Secret Engines, Policies

## What Is Vault?

HashiCorp Vault is the industry-standard open-source secrets management platform. It provides a unified interface to any secret — while providing tight access control, a detailed audit log, and support for dynamic secrets.

Vault is not just a key-value store for secrets. It is a full secrets lifecycle management system:
- Stores secrets encrypted at rest
- Issues dynamic credentials to databases, cloud providers, PKI
- Authenticates workloads using platform identities (Kubernetes, AWS IAM, Azure AD)
- Leases secrets with TTLs and automatic expiry
- Provides a complete audit trail of every secret access

---

## Vault Architecture

```
┌────────────────────────────────────────────────────────────┐
│                      VAULT SERVER                          │
│                                                            │
│  ┌──────────────┐   ┌──────────────┐   ┌───────────────┐ │
│  │  Auth Methods│   │Secret Engines│   │  Audit Devices│ │
│  │              │   │              │   │               │ │
│  │ - Kubernetes │   │ - KV v2      │   │ - File        │ │
│  │ - JWT/OIDC   │   │ - Database   │   │ - Syslog      │ │
│  │ - Azure AD   │   │ - PKI        │   │ - Socket      │ │
│  │ - AppRole    │   │ - AWS        │   │               │ │
│  │ - Token      │   │ - SSH        │   │               │ │
│  └──────────────┘   └──────────────┘   └───────────────┘ │
│           │                 │                             │
│           └────────┬────────┘                             │
│                    ↓                                       │
│  ┌─────────────────────────────────────┐                  │
│  │           Policy Engine             │                  │
│  │  (who can access what secrets)      │                  │
│  └─────────────────────────────────────┘                  │
│                    ↓                                       │
│  ┌─────────────────────────────────────┐                  │
│  │           Storage Backend           │                  │
│  │  Consul / Integrated (Raft) / etcd  │                  │
│  └─────────────────────────────────────┘                  │
└────────────────────────────────────────────────────────────┘
```

### Core Components

**Auth Methods:** How Vault verifies the identity of a requester. A Kubernetes pod proves identity via its ServiceAccount JWT token. A CI/CD pipeline proves identity via an OIDC token. A human proves identity via LDAP or SSO.

**Secret Engines:** Plugins that generate, store, or encrypt secrets. KV engine stores static key-value pairs. Database engine generates dynamic database credentials. PKI engine issues TLS certificates.

**Policies:** HCL documents that define what paths a token can access and what operations it can perform.

**Audit Devices:** Log every request and response to Vault (file, syslog, or network socket).

**Storage Backend:** Where Vault stores its encrypted data. Vault encrypts everything before writing to storage — the storage backend never sees plaintext.

---

## Vault Data Model — Paths

Everything in Vault is accessed via a path. The path structure determines which secret engine handles the request:

```
vault <engine-mount>/<engine-specific-path>

Examples:
  secret/data/checkout/db        → KV v2 engine at mount "secret"
  database/creds/checkout-role   → Database engine, dynamic creds
  pki/issue/checkout-cert        → PKI engine, issue certificate
  auth/kubernetes/login          → Kubernetes auth method login
```

Policies grant access to paths. Think of paths like a filesystem — you can grant read on a specific path or a wildcard.

---

## Auth Methods — How Workloads Authenticate

### 1. Kubernetes Auth (most important for K8s workloads)

Pods authenticate using their ServiceAccount JWT token:

```
Pod → sends ServiceAccount JWT to Vault
Vault → calls Kubernetes TokenReview API to verify the JWT
Vault → checks: does this ServiceAccount in this namespace match a role?
Vault → if yes: issues a Vault token with the bound policies
Pod  → uses Vault token to read secrets
```

**Setup:**

```bash
# Enable Kubernetes auth
vault auth enable kubernetes

# Configure with K8s API server details
vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# Create a role binding ServiceAccount to a policy
vault write auth/kubernetes/role/checkout \
  bound_service_account_names=checkout-sa \
  bound_service_account_namespaces=checkout \
  policies=checkout-policy \
  ttl=1h
```

Now when a pod with ServiceAccount `checkout-sa` in namespace `checkout` authenticates, it gets a Vault token with `checkout-policy` attached, valid for 1 hour.

### 2. AppRole Auth (for CI/CD and non-K8s workloads)

AppRole uses a Role ID (public) + Secret ID (private) pair:

```bash
# Enable AppRole
vault auth enable approle

# Create a role
vault write auth/approle/role/gitlab-ci \
  secret_id_ttl=10m \        # Secret ID expires in 10 minutes
  token_ttl=20m \            # Issued token valid for 20 minutes
  token_max_ttl=30m \
  policies=gitlab-ci-policy

# Get Role ID (public, can be stored in CI config)
vault read auth/approle/role/gitlab-ci/role-id

# Get Secret ID (private, fetched dynamically per pipeline run)
vault write -f auth/approle/role/gitlab-ci/secret-id
```

The GitLab CI pipeline fetches a fresh Secret ID per run from a trusted source (e.g. a Vault-aware CI plugin). Secret IDs expire after 10 minutes — tight window, reduces blast radius.

### 3. JWT/OIDC Auth (for GitLab CI, GitHub Actions, Azure)

Modern CI/CD platforms issue OIDC tokens per job. Vault can verify these without any pre-shared secret:

```bash
vault auth enable jwt

vault write auth/jwt/config \
  oidc_discovery_url="https://gitlab.com" \
  default_role="gitlab-ci"

vault write auth/jwt/role/gitlab-ci \
  role_type="jwt" \
  bound_claims='{"project_path": "myorg/myrepo", "ref": "main"}' \
  user_claim="sub" \
  policies=gitlab-ci-policy \
  ttl=20m
```

This is **secretless authentication** — the CI pipeline never needs a pre-shared secret to access Vault. GitLab issues a signed JWT per job, Vault verifies the signature against GitLab's public keys.

### 4. Token Auth (direct, for humans and testing)

```bash
# Create a token directly (for development/testing)
vault token create -policy=checkout-policy -ttl=1h

# Login with a token
vault login s.XXXXXXXXXXXXXXXX
```

Never use long-lived tokens for production workloads. Use platform-native auth methods instead.

---

## Secret Engines

### KV v2 (Key-Value Version 2)

The most common engine. Stores arbitrary key-value pairs with versioning.

```bash
# Enable KV v2 at path "secret"
vault secrets enable -path=secret kv-v2

# Write a secret
vault kv put secret/checkout/db \
  host="postgres.internal" \
  username="checkout_user" \
  password="s3cur3p@ss"

# Read a secret
vault kv get secret/checkout/db

# Read specific version
vault kv get -version=2 secret/checkout/db

# List secrets at a path
vault kv list secret/checkout/

# Delete (soft delete — recoverable)
vault kv delete secret/checkout/db

# Permanently destroy a version
vault kv destroy -versions=1 secret/checkout/db
```

**Versioning:** KV v2 keeps up to 10 versions by default. You can roll back to a previous version if a secret is accidentally overwritten.

### Database Engine (Dynamic Secrets)

Generates unique, short-lived database credentials on demand.

```bash
# Enable database engine
vault secrets enable database

# Configure PostgreSQL connection
vault write database/config/checkout-postgres \
  plugin_name=postgresql-database-plugin \
  connection_url="postgresql://{{username}}:{{password}}@postgres.internal:5432/checkout" \
  allowed_roles="checkout-app" \
  username="vault-admin" \
  password="vault-admin-password"

# Create a role with SQL template
vault write database/roles/checkout-app \
  db_name=checkout-postgres \
  creation_statements="CREATE ROLE \"{{name}}\" WITH LOGIN PASSWORD '{{password}}' VALID UNTIL '{{expiration}}'; GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO \"{{name}}\";" \
  revocation_statements="DROP ROLE IF EXISTS \"{{name}}\";" \
  default_ttl="1h" \
  max_ttl="24h"

# Request credentials (what the app does at startup)
vault read database/creds/checkout-app
# Returns:
#   username: v-checkout-app-abc123
#   password: randomly-generated-password
#   lease_duration: 1h
#   lease_id: database/creds/checkout-app/xyz789
```

After 1 hour, Vault automatically runs the revocation SQL — the user is dropped. The credential is dead even if leaked.

### PKI Engine (TLS Certificates)

Issues short-lived TLS certificates for services.

```bash
# Enable PKI engine
vault secrets enable pki

# Configure max TTL
vault secrets tune -max-lease-ttl=8760h pki

# Generate root CA (or import existing)
vault write pki/root/generate/internal \
  common_name="internal.company.com" \
  ttl=8760h

# Create a role for issuing certificates
vault write pki/roles/checkout-cert \
  allowed_domains="checkout.internal,checkout.svc.cluster.local" \
  allow_subdomains=true \
  max_ttl=72h

# Issue a certificate
vault write pki/issue/checkout-cert \
  common_name="checkout.internal" \
  ttl=24h
# Returns: certificate, private_key, issuing_ca, serial_number
```

Short-lived certificates (24-72h) eliminate the need to manage certificate revocation lists (CRLs) — expired certs simply stop working.

---

## Vault Policies

Policies define what a token can do. Written in HCL.

### Policy Syntax

```hcl
# Policy: checkout-policy
# Allows reading DB creds and KV secrets for checkout service

# Read dynamic DB credentials
path "database/creds/checkout-app" {
  capabilities = ["read"]
}

# Read and list KV secrets for checkout
path "secret/data/checkout/*" {
  capabilities = ["read", "list"]
}

# Explicitly deny access to other services' secrets
path "secret/data/payment/*" {
  capabilities = ["deny"]
}

# Allow renewing own leases (needed for long-running services)
path "sys/leases/renew" {
  capabilities = ["update"]
}
```

### Capabilities Reference

| Capability | HTTP equivalent | What it allows |
|-----------|----------------|---------------|
| `create` | POST | Create new data at path |
| `read` | GET | Read data at path |
| `update` | POST/PUT | Update existing data |
| `delete` | DELETE | Delete data |
| `list` | LIST | List keys at path |
| `deny` | — | Explicitly deny, overrides all other policies |
| `sudo` | — | Access root-protected paths |

### Applying a Policy

```bash
# Write policy to Vault
vault policy write checkout-policy checkout-policy.hcl

# Check what a token can do
vault token capabilities s.TOKEN_VALUE secret/data/checkout/db
```

---

## Vault in Production — HA Setup

Development mode (`vault server -dev`) runs in-memory with no persistence. Never use dev mode in production.

### Production Setup with Integrated Storage (Raft)

```hcl
# vault.hcl — production configuration
ui = true
log_level = "INFO"

storage "raft" {
  path    = "/vault/data"
  node_id = "vault-node-1"

  retry_join {
    leader_api_addr = "https://vault-node-2:8200"
  }
  retry_join {
    leader_api_addr = "https://vault-node-3:8200"
  }
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_cert_file = "/vault/tls/vault.crt"
  tls_key_file  = "/vault/tls/vault.key"
}

seal "azurekeyvault" {
  tenant_id      = "TENANT_ID"
  vault_name     = "vault-auto-unseal"
  key_name       = "vault-unseal-key"
}

api_addr = "https://vault.internal:8200"
cluster_addr = "https://vault.internal:8201"
```

### Vault Initialization and Unseal

```bash
# Initialize Vault (first time only)
vault operator init \
  -key-shares=5 \          # Split master key into 5 parts
  -key-threshold=3          # Need 3 of 5 to unseal

# Vault outputs 5 unseal keys and 1 root token
# Store these securely — this is the most sensitive operation

# Unseal (manual, requires 3 of 5 key holders)
vault operator unseal KEY_1
vault operator unseal KEY_2
vault operator unseal KEY_3

# With auto-unseal (Azure Key Vault seal above), Vault unseals automatically on restart
```

**Auto-unseal with Azure Key Vault** is strongly recommended for production. Without it, Vault requires manual unsealing after every restart — which is operational toil and a reliability risk.

---

## Vault CLI Quick Reference

```bash
# Authentication
vault login -method=kubernetes role=checkout     # K8s auth
vault login -method=oidc                        # OIDC/browser
vault token lookup                              # Check current token

# KV operations
vault kv get secret/checkout/db                 # Read secret
vault kv put secret/checkout/db key=value       # Write secret
vault kv list secret/checkout/                  # List secrets
vault kv metadata get secret/checkout/db        # Show versions
vault kv patch secret/checkout/db key=newvalue  # Update single key

# Dynamic secrets
vault read database/creds/checkout-app          # Get DB creds
vault lease renew <lease-id>                    # Renew credential
vault lease revoke <lease-id>                   # Revoke credential early

# Admin operations
vault auth list                                  # List auth methods
vault secrets list                               # List secret engines
vault policy list                                # List policies
vault policy read checkout-policy               # Read a policy
vault audit list                                 # List audit devices

# Status
vault status                                     # Seal status, cluster info
vault operator members                           # Raft cluster members
```

---

## Interview Questions — HashiCorp Vault

**Q: What is the difference between Vault auth methods and secret engines?**
A: Auth methods handle identity — they verify who or what is making the request and issue a Vault token. Secret engines handle secrets — they generate, store, or encrypt secrets. Auth and secret engines are separate concerns: auth methods answer "who are you?", secret engines answer "here's what you're allowed to access."

**Q: How does Kubernetes auth work in Vault?**
A: A pod sends its ServiceAccount JWT token to Vault's login endpoint. Vault calls the Kubernetes TokenReview API to verify the token is valid and belongs to the expected ServiceAccount in the expected namespace. If verified, Vault checks which role this ServiceAccount is bound to and issues a Vault token with the associated policies. The pod never needs a pre-shared secret — its Kubernetes identity is the credential.

**Q: What are dynamic secrets and what problem do they solve?**
A: Dynamic secrets are generated on-demand per requester with a short TTL — Vault creates a unique database user with a random password valid for 1 hour, then automatically drops it. They solve the blast radius problem of static credentials: if a dynamic secret leaks, it expires quickly and is unique to one consumer (no other service is affected). With static secrets, one leaked password might be shared by many services and valid for years.

**Q: What is Vault's Raft storage and why use it over Consul?**
A: Raft is Vault's integrated storage backend — Vault runs its own distributed consensus without needing a separate Consul cluster. It simplifies the operational footprint (one system instead of two), reduces failure modes, and is now the recommended production storage backend since Vault 1.4. Consul storage is still supported but adds operational complexity.
