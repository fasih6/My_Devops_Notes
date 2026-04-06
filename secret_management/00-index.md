# Secrets Management — Index & Mental Model

## What Is a Secret?

A secret is any piece of sensitive data that grants access to a system, resource, or capability. If exposed, it can be used by an attacker to impersonate a service, exfiltrate data, or take control of infrastructure.

Common secrets:
- Database passwords and connection strings
- API keys and tokens (Stripe, Twilio, GitHub, cloud providers)
- TLS/SSL private keys and certificates
- SSH private keys
- OAuth client secrets
- Encryption keys
- Cloud provider credentials (AWS access keys, Azure service principal secrets)
- JWT signing secrets

The defining property: **a secret's value is its confidentiality.** The moment it's exposed, it must be considered compromised — no matter who saw it.

---

## The Problem: Secret Sprawl

Most organizations start with secrets in the wrong places:

```
The secret sprawl problem:

  .env files committed to Git          ← most common breach vector
  Hardcoded in application source      ← found in code reviews / leaks
  Pasted into Slack / email            ← accidental exposure
  Stored in CI/CD pipeline variables   ← often too broadly accessible
  Copied between environments manually ← stale, forgotten, not rotated
  Shared in shared password docs       ← no audit trail, no access control
  Embedded in Docker images            ← extracted from image layers
  In Kubernetes Secrets (unencrypted)  ← base64 ≠ encryption
```

Secret sprawl means secrets exist in many places, with no central visibility, no rotation, no audit trail, and no way to respond quickly when one is compromised.

**The blast radius of secret sprawl:** When a secret leaks, you don't know where it's been used, who has it, or how long it's been exposed. You can't respond effectively.

---

## The Solution: Centralized Secrets Management

A secrets management platform provides:

```
┌─────────────────────────────────────────────────────────┐
│              Secrets Management Platform                 │
│                                                         │
│  Storage      → Encrypted at rest, centralized          │
│  Access       → Identity-based, least privilege          │
│  Audit        → Every access logged with who/when/why   │
│  Rotation     → Automatic, without downtime             │
│  Leasing      → Secrets expire, reducing stale access   │
│  Dynamic      → Generate secrets on-demand, revoke fast │
└─────────────────────────────────────────────────────────┘
```

---

## The Mental Model: Static vs Dynamic Secrets

This is one of the most important concepts in secrets management:

```
STATIC SECRETS (traditional):
  One long-lived password shared across services
  → Created once, rotated rarely (or never)
  → If leaked: unknown blast radius, hard to revoke
  → Example: DB password "supersecret123" used for 3 years

DYNAMIC SECRETS (modern):
  Generated on-demand, unique per consumer, short-lived
  → Vault generates a new DB user+password for each request
  → Credential lives for 1 hour, then expires automatically
  → If leaked: attacker has 1 hour window, not 3 years
  → Revocation is instant — just don't renew the lease
```

Dynamic secrets are the gold standard. Not every tool supports them — HashiCorp Vault does.

---

## The Threat Model

What are you protecting against?

| Threat | Example | Mitigation |
|--------|---------|------------|
| **Accidental exposure** | Secret committed to Git | Pre-commit hooks, secret scanning |
| **Insider threat** | Employee copies prod DB password | Least privilege, audit logs, dynamic secrets |
| **Compromised CI/CD** | Attacker gets pipeline access | OIDC auth, short-lived tokens, scoped permissions |
| **Compromised application** | App is RCE'd, attacker reads env vars | Secret injection at runtime, not at build time |
| **Supply chain attack** | Dependency exfiltrates secrets | Secret scanning, runtime isolation |
| **Stale credentials** | Forgotten API key from ex-employee | Rotation policy, leasing, access reviews |
| **Container image leak** | Secrets baked into Docker layers | Never put secrets in images |

---

## Key Principles of Secrets Management

**1. Never store secrets in Git**
Git is permanent. Even deleted commits can be recovered. Treat any secret committed to Git as compromised immediately.

**2. Least privilege**
Every service should only have access to the secrets it needs. A frontend service should not have access to the database password.

**3. Short-lived credentials**
Prefer secrets that expire. A token valid for 1 hour has a smaller blast radius than one valid for 1 year.

**4. Audit everything**
Every secret access should be logged: who accessed it, when, from where. This enables incident response when a breach is suspected.

**5. Rotate regularly, rotate automatically**
Manual rotation is toil and gets skipped. Automate rotation. The shorter the rotation period, the smaller the window of exposure.

**6. Separate secrets by environment**
Production secrets must never be used in development or staging. Separate secret stores, separate access controls.

**7. Fail closed**
If the secret management system is unavailable, applications should fail rather than fall back to hardcoded defaults.

---

## Folder Contents

| File | Topic |
|------|-------|
| `01-core-concepts.md` | Secret lifecycle, threat model, static vs dynamic, zero trust |
| `02-hashicorp-vault.md` | Vault architecture, auth methods, secret engines, policies |
| `03-vault-advanced.md` | Dynamic secrets, PKI, Vault Agent, Kubernetes integration |
| `04-azure-key-vault.md` | AKV architecture, RBAC, AKS integration, rotation |
| `05-kubernetes-secrets.md` | Native K8s secrets, encryption at rest, RBAC |
| `06-external-secrets-operator.md` | ESO architecture, SecretStore, ExternalSecret CRD |
| `07-sealed-secrets-sops.md` | GitOps-safe secrets, Sealed Secrets, SOPS with age/KMS |
| `08-cicd-secrets.md` | GitLab CI, Jenkins, OIDC-based secretless auth |
| `09-secret-rotation-lifecycle.md` | Rotation patterns, zero-downtime rotation, break-glass |
| `10-interview-qa.md` | 15+ interview questions with full answers |

---

## Tools Landscape at a Glance

| Tool | Type | Best for |
|------|------|---------|
| **HashiCorp Vault** | Dedicated secrets manager | Dynamic secrets, PKI, multi-cloud, self-hosted |
| **Azure Key Vault** | Cloud-native secrets manager | Azure workloads, managed certs, HSM |
| **AWS Secrets Manager** | Cloud-native secrets manager | AWS workloads, automatic RDS rotation |
| **External Secrets Operator** | K8s sync layer | Syncing secrets from any backend into K8s |
| **Sealed Secrets** | GitOps encryption | Encrypting K8s secrets safe for Git |
| **SOPS** | File encryption | Encrypting any file (YAML, JSON, .env) for Git |
| **cert-manager** | Certificate lifecycle | Automated TLS cert issuance and renewal |

---

## Why This Topic Matters in Interviews

Secrets management knowledge signals:
- You understand **security as a system**, not just a checklist
- You can **design for breach** — assuming secrets will be exposed and limiting the damage
- You know the **operational reality** — rotation, audit, access control in production
- You understand **zero trust** — verify every access, trust nothing by default

Every DevOps, DevSecOps, and Platform Engineer role will touch secrets. Knowing this topic well differentiates you.
