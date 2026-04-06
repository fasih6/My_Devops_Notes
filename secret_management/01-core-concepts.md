# Core Concepts — Secrets Management Foundations

## The Secret Lifecycle

Every secret has a lifecycle. Managing this lifecycle is the core job of secrets management:

```
┌─────────────────────────────────────────────────────────────┐
│                    SECRET LIFECYCLE                          │
│                                                             │
│  1. CREATION    → Generated securely, stored encrypted      │
│  2. STORAGE     → Centralized, access-controlled vault      │
│  3. DISTRIBUTION→ Delivered to authorized consumers only    │
│  4. USE         → Consumed by application at runtime        │
│  5. ROTATION    → Replaced before or after expiry           │
│  6. REVOCATION  → Immediately invalidated when compromised  │
│  7. DELETION    → Permanently removed when no longer needed │
└─────────────────────────────────────────────────────────────┘
```

Failing at any stage creates a vulnerability. Most organizations handle creation and storage reasonably well — but fail at rotation, revocation, and deletion.

---

## Static vs Dynamic Secrets — Deep Dive

### Static Secrets

A static secret is created once and used repeatedly, often for a long time.

```
Characteristics:
  - Same value every time it's accessed
  - Long-lived (months to years)
  - Shared across multiple services or environments
  - Rotation requires coordination (update everywhere at once)
  - If leaked: entire exposure window = time since last rotation

Examples:
  - Database password in environment variable
  - API key stored in Key Vault, retrieved at startup
  - SSH private key for server access
```

**The rotation problem with static secrets:**
When you rotate a static database password, you must update every service that uses it simultaneously — or services start failing. This coordination cost causes teams to avoid rotation, which means secrets stay valid for years.

### Dynamic Secrets

A dynamic secret is generated on-demand for a specific requester and expires automatically.

```
Characteristics:
  - Unique value generated per request
  - Short-lived (minutes to hours)
  - Each consumer gets their own credential
  - Rotation is automatic — just don't renew
  - If leaked: exposure window = time-to-live (TTL)

Example flow (Vault + PostgreSQL):
  1. checkout-service requests DB credentials from Vault
  2. Vault creates a new PostgreSQL user: vault-checkout-1a2b3c
     with password: randomly-generated-32-char-string
     with TTL: 1 hour
  3. checkout-service uses these credentials
  4. After 1 hour: Vault automatically drops the DB user
  5. The leaked credential is now invalid

No coordination needed. No rotation ceremony. Automatic expiry.
```

### When to use which

| Scenario | Use |
|----------|-----|
| Database credentials (supporting Vault) | Dynamic |
| API keys to external services (no dynamic support) | Static + rotation |
| TLS certificates | Dynamic (cert-manager / Vault PKI) |
| Cloud IAM credentials | Dynamic (OIDC, workload identity) |
| Encryption keys (AES, RSA) | Static, stored in HSM/Key Vault |
| SSH keys for servers | Static (with short TTL if using Vault SSH) |

---

## Zero Trust and Secrets

Zero Trust is a security model with one core principle: **never trust, always verify.**

In the context of secrets management:

```
Traditional (perimeter trust):
  "This service is inside our network, so it's trusted"
  → Services share credentials liberally
  → Network access = identity

Zero Trust:
  "Every access request must be authenticated and authorized,
   regardless of where it comes from"
  → Each service has a unique identity
  → Access to secrets is granted per identity, per secret
  → Even internal services must prove who they are
```

### Machine Identity

Zero trust requires that every workload — every pod, every VM, every CI/CD pipeline — has a cryptographic identity that can be verified.

```
Kubernetes:  ServiceAccount → JWT token → verified by Vault/AKV
Azure VMs:   Managed Identity → verified by Azure AD
CI/CD:       OIDC token → verified by secret backend
```

These identities replace username/password authentication for machines. No human manages the credentials — the platform issues and rotates them automatically.

---

## Secret Engines — Categories of Secrets

Different types of secrets have different characteristics and management needs:

### Key-Value Secrets (KV)
Simple key-value pairs. Most common type.
```
path: secret/data/checkout/db
value: {
  "host": "postgres.internal",
  "username": "checkout_user",
  "password": "s3cur3p@ss"
}
```

### Database Credentials
Dynamic or static credentials for databases (PostgreSQL, MySQL, MongoDB, etc.)
```
Dynamic: Vault generates a unique user per request
Static: Vault manages a single user but rotates the password automatically
```

### PKI / TLS Certificates
X.509 certificates for service-to-service TLS (mTLS) and external HTTPS.
```
Vault PKI engine or cert-manager issues short-lived certificates
No manual certificate renewal — fully automated
```

### Encryption Keys
Symmetric (AES) or asymmetric (RSA/EC) keys for encrypting data.
```
Never leave the key management system
Applications call an API: "encrypt this data" / "decrypt this data"
Keys are used without being exposed to the application
```

### Cloud Credentials
Short-lived tokens for cloud providers.
```
AWS: STS AssumeRole → temporary access key + secret + session token
Azure: Managed Identity token → OAuth2 bearer token
GCP: Workload Identity → service account token
```

### SSH Certificates
Short-lived SSH certificates instead of long-lived authorized_keys.
```
Engineer authenticates to Vault → receives SSH cert valid for 30 minutes
Connects to server → server verifies cert against Vault CA
No permanent keys on servers, no authorized_keys management
```

---

## Secret Anti-Patterns — What NOT to Do

### Anti-pattern 1: Secrets in environment variables at build time

```dockerfile
# WRONG — secret baked into image layer
FROM node:18
ENV DATABASE_URL=postgresql://user:password@host/db
RUN npm install
```

The secret is now in every layer of the Docker image. Anyone who pulls the image has the secret. It's in your container registry logs. It's in your CI/CD build logs.

**Fix:** Inject secrets at runtime (not build time) via Vault Agent, External Secrets Operator, or mounted secret volumes.

### Anti-pattern 2: Logging secrets

```python
# WRONG
logger.info(f"Connecting to database with credentials: {db_password}")
```

Logs are often sent to centralized logging systems, stored for months, and accessible to many people.

**Fix:** Never log secret values. Log that a secret was accessed, not what its value is.

### Anti-pattern 3: Secrets in configuration files committed to Git

```yaml
# config.yaml — WRONG, committed to Git
database:
  password: "supersecret123"
```

Git history is permanent. Even if you delete the file and force-push, the secret exists in forks, clones, and git reflog.

**Fix:** Use secret references in config files (`${DB_PASSWORD}` resolved at runtime), not values.

### Anti-pattern 4: Overly broad secret access

```
# WRONG: one token with access to all secrets
vault token create -policy=read-all-secrets

# RIGHT: scoped token per service
vault token create -policy=checkout-db-read-only
```

### Anti-pattern 5: No secret scanning in CI/CD

Relying on engineers to never commit secrets. Humans make mistakes.

**Fix:** Add pre-commit hooks (gitleaks, detect-secrets) and CI/CD scanning (trufflehog, GitGuardian) to catch secrets before they merge.

---

## Secret Scanning Tools

| Tool | How it works | Use case |
|------|-------------|---------|
| **gitleaks** | Scans git history for secret patterns | Pre-commit hook, CI/CD gate |
| **detect-secrets** | Detects secrets, maintains allowlist | Pre-commit, developer workflow |
| **trufflehog** | Deep git history scan, entropy analysis | CI/CD, security audits |
| **GitGuardian** | SaaS, monitors GitHub/GitLab in real-time | Organization-wide monitoring |
| **git-secrets** | AWS-focused, prevents AWS key commits | AWS-heavy teams |

### Pre-commit hook with gitleaks

```bash
# Install gitleaks
brew install gitleaks   # macOS
# or
apt install gitleaks    # Linux

# Run as pre-commit hook
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks
```

Now every `git commit` scans the staged changes. If a secret pattern is detected, the commit is blocked.

---

## The Secrets Management Maturity Model

Where does your organization sit?

```
Level 0 — Ad hoc (most organizations start here)
  Secrets in .env files, Git, Slack, spreadsheets
  No rotation, no audit, no access control

Level 1 — Basic vault
  Secrets stored in a vault (Vault, Key Vault, Secrets Manager)
  Manual access, no rotation, basic audit

Level 2 — Controlled access
  RBAC on secrets — each service gets only what it needs
  Some automated rotation
  Audit logs reviewed

Level 3 — Dynamic and automated
  Dynamic secrets where possible
  Automated rotation for static secrets
  Secret scanning in CI/CD
  Regular access reviews

Level 4 — Zero trust secrets
  Machine identities for all workloads
  All secrets dynamic or short-lived
  No human ever sees production secrets
  Automated breach detection and response
  Break-glass procedures documented and tested
```

Most companies are at Level 1-2. Knowing Level 3-4 makes you stand out.

---

## Interview Questions — Core Concepts

**Q: What is secret sprawl and why is it dangerous?**
A: Secret sprawl is when secrets exist in many uncontrolled locations — Git repos, Slack messages, .env files, CI variables, Docker images. It's dangerous because when a secret leaks, you don't know all the places it exists, who has it, or how to revoke it effectively. Centralized secrets management eliminates sprawl by making the vault the single source of truth.

**Q: What is the difference between static and dynamic secrets?**
A: Static secrets have a fixed value and long lifespan — they're created once and rotated infrequently. Dynamic secrets are generated on-demand per requester and expire automatically (e.g. Vault generating a unique database user per service with a 1-hour TTL). Dynamic secrets massively reduce blast radius: if leaked, they expire quickly and each consumer has unique credentials that can be individually revoked.

**Q: Why is base64 encoding not the same as encryption?**
A: Base64 is an encoding scheme — it's completely reversible without any key. Anyone can decode a base64 string with a single command (`base64 -d`). Encryption requires a key. Kubernetes stores secrets as base64-encoded values by default, which means anyone with API server access can trivially read them. Encryption at rest (using a KMS provider) is a separate, necessary step.
