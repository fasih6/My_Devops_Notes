# Secrets Management — Interview Q&A

## How to Use This File

These questions range from junior to senior/lead level. Each answer has:
- **Short answer** — what you say in the first 30–60 seconds
- **Depth** — what you add if they probe further
- **Signal** — what the interviewer is actually assessing

---

## Section 1: Foundations

### Q1: What is secret sprawl and how do you fix it?

**Short answer:**
Secret sprawl is when secrets exist in many uncontrolled locations — Git repos, .env files, Slack messages, CI/CD variables, Docker images. The fix is centralized secrets management: a single authoritative store (Vault, Azure Key Vault) with access control, audit logging, and rotation.

**Depth:**
The danger of sprawl is that when a secret leaks, you don't know all the places it exists or who has it. You can't revoke it effectively. Centralized management gives you: one place to rotate (rotation propagates everywhere), one audit log (you know exactly who accessed what), and one access control model (RBAC, not informal sharing).

**Fix in practice:**
- Secret scanning in CI/CD to detect new sprawl
- Migrate existing secrets to a central store
- Block future sprawl with pre-commit hooks (gitleaks)
- ESO or Vault Agent to deliver secrets to apps without them needing to know the store

**Signal:** Tests whether you understand the operational reality of secrets, not just the theory. Mentioning audit trail and blast radius signals maturity.

---

### Q2: What is the difference between static and dynamic secrets?

**Short answer:**
Static secrets have a fixed value and long lifespan — they're created once and rotated infrequently. Dynamic secrets are generated on-demand per requester, unique per consumer, and expire automatically (e.g. Vault generates a unique database user per service with a 1-hour TTL).

**Depth:**
The key advantage of dynamic secrets is blast radius. If a static DB password leaks, the attacker has it for potentially years and it's shared by all services. If a dynamic credential leaks, it expires in an hour and is unique — revoking it doesn't affect any other service. Vault's database engine is the canonical example: each service gets its own `vault-svcname-randomstring` DB user that auto-expires.

**When static is unavoidable:**
External API keys (Stripe, Twilio) can't be dynamically generated — the external service issues them. Use static secrets with rotation policies (every 90 days) and store in Key Vault/Vault.

**Signal:** Interviewers want to hear "blast radius" and "unique per consumer" — these signal you understand the security implications, not just the mechanical difference.

---

### Q3: Why is base64 encoding not encryption?

**Short answer:**
Base64 is a reversible encoding — anyone can decode it with `base64 -d` in one second. No key is required. Encryption requires a key; without the key, the data is unreadable. Kubernetes stores secrets as base64 by default — they are NOT encrypted without explicitly enabling encryption at rest with a KMS provider.

**Depth:**
This trips up many people who assume Kubernetes Secrets are protected. The base64 value in a Secret object is trivially reversible. Anyone with `kubectl get secret -o yaml` access gets the plaintext value. etcd backups contain plaintext secrets. To actually protect secrets in Kubernetes, you need: (1) encryption at rest via KMS provider (Azure Key Vault, AWS KMS), (2) strict RBAC to limit who can `get` secrets, and ideally (3) an external secret management system like ESO or Vault so secrets aren't stored in etcd at all.

**Signal:** This is a common "gotcha" question. Getting it right — and explaining the fix — signals you've worked with Kubernetes in production, not just studied it.

---

### Q4: What are the key principles of good secrets management?

**Short answer:**
Never store in Git, least privilege access, prefer short-lived credentials, audit all access, rotate automatically, separate secrets by environment, and fail closed (if the secret store is unavailable, fail — don't fall back to hardcoded defaults).

**Depth (expand on any one):**
- **Least privilege:** a frontend service should not have the database password. Each service gets only the secrets it needs. Use Vault policies with specific paths and `resourceNames` in K8s RBAC.
- **Short-lived:** a credential valid for 1 hour has 1/8760th the blast radius of one valid for a year. Prefer dynamic secrets or certificate-based auth with short TTLs.
- **Fail closed:** the most dangerous failure mode is falling back to a hardcoded default when the secret store is unavailable. Applications should fail to start rather than use a default. This forces the team to fix the secret management problem rather than silently operating with insecure defaults.

---

## Section 2: Tools

### Q5: How does HashiCorp Vault's Kubernetes auth method work?

**Short answer:**
A pod sends its ServiceAccount JWT token to Vault's login endpoint. Vault calls the Kubernetes TokenReview API to verify the token is valid and belongs to the expected ServiceAccount in the expected namespace. If verified, Vault checks which role this ServiceAccount is bound to and issues a Vault token with the associated policies.

**Depth:**
The elegance is that no pre-shared secret is needed — the pod's Kubernetes identity IS the credential. Setup: enable kubernetes auth, configure Vault with the K8s API server address, create a role binding a ServiceAccount+namespace to a policy. The pod doesn't need to know any Vault credentials — it just presents its own K8s identity.

```bash
vault write auth/kubernetes/role/checkout \
  bound_service_account_names=checkout-sa \
  bound_service_account_namespaces=checkout \
  policies=checkout-policy \
  ttl=1h
```

**Signal:** Tests whether you understand Vault's identity model. "No pre-shared secret needed" is the key insight — it's the same OIDC/workload identity pattern applied to Vault.

---

### Q6: What is the difference between Azure Key Vault access policies and Azure RBAC?

**Short answer:**
Access policies (legacy) grant permissions at the vault level — you get/list/delete all secrets of a type. Azure RBAC (recommended) uses standard Azure role assignments, supports secret-level scope, integrates with Azure Policy and Conditional Access, and is consistent with all other Azure resource permissions.

**Depth:**
The critical limitation of access policies: you can grant "read secrets" but not "read only THIS specific secret." RBAC solves this — scope the role assignment to a specific secret's resource ID for fine-grained access. RBAC also has full Azure Policy support, can be enforced at the management group level, and appears in standard Azure activity logs. New deployments should always use RBAC. The migration path from policies to RBAC is: enable RBAC authorization on the vault, assign equivalent roles, verify, then remove old policies.

---

### Q7: What is the External Secrets Operator and what problem does it solve?

**Short answer:**
ESO is a Kubernetes operator that syncs secrets from external backends (Vault, Azure Key Vault, AWS Secrets Manager) into native Kubernetes Secrets. It solves the disconnect between external secret management systems and Kubernetes — without ESO, secrets must be manually copied into K8s, which is error-prone and doesn't support rotation.

**Depth:**
ESO's key CRDs: `SecretStore` (how to connect to the backend, namespaced) and `ExternalSecret` (what to fetch and where to put it). The `refreshInterval` controls how often ESO checks the backend for updates — when a secret is rotated externally, ESO updates the K8s Secret within one refresh cycle. Pair with Stakater Reloader for pods using env vars (rolling restart when the Secret changes).

**The vs-Vault-Agent comparison:** ESO is a cluster-level operator — simpler at scale. Vault Agent is a per-pod sidecar — better for dynamic secrets with lease management. ESO supports 20+ backends; Vault Agent only works with Vault.

---

## Section 3: Kubernetes & GitOps

### Q8: How do Sealed Secrets allow committing encrypted secrets to Git?

**Short answer:**
The Sealed Secrets controller generates an RSA key pair. The public key is available to developers for encryption. The private key stays inside the cluster. Developers run `kubeseal` to encrypt a K8s Secret into a SealedSecret object (ciphertext only). SealedSecrets are safe to commit to Git. When applied, the controller decrypts with the private key and creates a standard K8s Secret.

**Depth:**
Key points: the private key never leaves the cluster, so even if your Git repo is public, SealedSecrets are unreadable. Sealed Secrets support scopes — `strict` ties the sealed secret to a specific name+namespace, preventing it from being applied elsewhere. On key rotation (every 30 days), old keys are retained so existing sealed secrets still decrypt. Best practice: re-seal with the new key periodically with `kubeseal --re-encrypt`.

---

### Q9: What is SOPS and how does it differ from Sealed Secrets?

**Short answer:**
SOPS encrypts any file format (YAML, JSON, .env) and only encrypts values — keys/structure remain readable in Git. Sealed Secrets only works with Kubernetes Secret objects and encrypts the entire object. SOPS supports multiple key backends (age, Azure Key Vault, AWS KMS) and isn't cluster-dependent.

**Depth:**
SOPS's readable structure is a significant advantage: you can do meaningful `git diff` on SOPS-encrypted files (you see which keys changed, just not the values). Flux has native SOPS support — configure a Kustomization with `decryption.provider: sops` and the private key as a K8s Secret. ArgoCD needs a plugin (argocd-vault-plugin or helm-secrets). For multi-cluster GitOps, SOPS with a shared KMS key is better than Sealed Secrets — no re-sealing per cluster needed.

---

### Q10: How do you handle secret rotation in a Kubernetes environment?

**Short answer:**
Depends on the delivery mechanism. For volume-mounted secrets: ESO updates the K8s Secret, kubelet syncs the updated file to running pods within ~1 minute — no restart needed. For env-var-based secrets: use Stakater Reloader, which watches K8s Secrets and triggers rolling restarts when they change. For Vault dynamic secrets with Vault Agent: the agent renews leases and re-renders templates automatically.

**Depth:**
The full rotation flow with ESO + Reloader:
1. Rotate secret in Azure Key Vault (new version)
2. ESO detects change on next `refreshInterval` (e.g. 1h) and updates K8s Secret
3. Reloader detects K8s Secret change and triggers rolling restart of annotated Deployments
4. New pods start with updated env vars from the new K8s Secret
5. Old pods drain normally
6. Zero downtime — rolling update, old pods serve traffic until new ones are ready

---

## Section 4: CI/CD

### Q11: What is the bootstrap problem in CI/CD secrets management?

**Short answer:**
To fetch secrets from a secret store, the pipeline needs a credential. But that credential is itself a secret — usually stored as a long-lived CI platform variable, which is exactly what you're trying to avoid. OIDC solves this: CI platforms issue a signed JWT per job, verified cryptographically against the platform's public keys. No pre-shared secret needed.

**Depth:**
Without OIDC: GitLab variable `VAULT_TOKEN` is a long-lived Vault token. If it leaks, an attacker has indefinite Vault access. With OIDC: GitLab issues a signed JWT for every job. Vault verifies the JWT against GitLab's JWKS endpoint and checks `bound_claims` (repo, branch, ref). If a feature branch tries to access prod secrets, the bound_claims check fails. The token expires in 20 minutes. Nothing to rotate, nothing to leak long-term.

---

### Q12: How do you prevent secrets from being committed to Git in a CI/CD pipeline?

**Short answer:**
Defense in depth: (1) pre-commit hooks with gitleaks block secrets at commit time, (2) CI/CD secret detection (GitLab built-in, GitHub Actions gitleaks) scans every MR/PR, (3) repo-level push rules block patterns matching known secret formats. Multiple layers because any single layer can be bypassed.

**Depth:**
Pre-commit is most valuable — it catches mistakes before they enter Git history. CI/CD scanning catches anything that slipped through (developer without hooks, direct push). Push rules are the last resort. Additionally: train developers on what constitutes a secret, provide easy alternatives (`.env.example` files with placeholder values, developer-specific secret stores), and ensure that when a secret IS accidentally committed, the process is clear: rotate immediately (not just delete from Git — history is permanent), and do a postmortem on why pre-commit didn't catch it.

---

## Section 5: Architecture & Design

### Q13: How would you design a secrets management system for a microservices platform on AKS?

**Short answer:**
Azure Key Vault as the backend, ESO to sync secrets into K8s Secrets per namespace, Workload Identity for AKS pod authentication to Key Vault, SOPS or Sealed Secrets for GitOps-safe secret storage in Git, cert-manager for TLS certificate lifecycle, and KMS encryption at rest for etcd.

**Full architecture:**
```
Git (SOPS-encrypted secrets)
  ↓ Flux decrypts and applies
ExternalSecret CRDs per namespace
  ↓ ESO syncs
Azure Key Vault ← single source of truth
  ↓ ESO reads
Kubernetes Secrets (KMS-encrypted in etcd)
  ↓ consumed by
Application Pods (via env vars or volume mounts)

Auth chain:
  Pod ServiceAccount → Workload Identity → Azure AD → Key Vault RBAC
  No static credentials anywhere in the chain

Additional layers:
  - cert-manager + Vault PKI (or AKV) for TLS certs
  - Stakater Reloader for rolling restarts on secret rotation
  - Azure Monitor alerts for Key Vault access anomalies
  - gitleaks in CI/CD to prevent new sprawl
```

**Signal:** This question tests end-to-end design thinking. Interviewers want to see: a clear source of truth, least-privilege access, no static credentials, rotation handling, and auditability.

---

### Q14: A developer reports they accidentally committed a database password to Git. What do you do?

**Short answer:**
Rotate the credential immediately — treat it as compromised from the moment of commit. Then clean Git history. Then find out why the controls didn't catch it.

**Detailed response:**

**Step 1 — Rotate immediately (priority 1)**
```
Generate new DB password
Update in Key Vault/Vault
Rolling restart of services to pick up new credential
Verify all services using new credential
Revoke old credential in DB
```
Do not wait to clean Git first — rotation is the priority.

**Step 2 — Clean Git history**
```
git filter-branch or git filter-repo to remove the secret from history
Force push to all branches (coordinate with team)
Ask all contributors to re-clone
If repo is on GitHub/GitLab: contact support to purge caches
```
Cleaning history is important but secondary to rotation — the secret is already out.

**Step 3 — Assess exposure**
```
Check Key Vault/DB audit logs: was the credential used between commit and rotation?
If yes: treat as breach — escalate, notify stakeholders
If no: rotation was fast enough, likely no exposure
```

**Step 4 — Fix the controls**
```
Why didn't the pre-commit hook catch it?
Did the developer not have gitleaks installed?
→ Make pre-commit hooks mandatory and enforced server-side
Did the CI/CD secret detection miss it?
→ Review detection rules and patterns
```

**Signal:** Tests incident response thinking. "Rotate first, clean history second" is the key insight — many people get this backwards.

---

### Q15: What is the principle of "fail closed" in secrets management and why does it matter?

**Short answer:**
If the secret management system is unavailable, applications should fail to start rather than fall back to hardcoded defaults or insecure configurations. Failing closed means choosing security over availability when the two are in conflict.

**Why it matters:**
The alternative — failing open — creates a dangerous pattern: the secret store goes down, apps fall back to a default password, the ops team "fixes" availability by keeping the default in place, and the default becomes permanent. Failing closed forces the team to treat secret store availability as a hard dependency, invest in its reliability, and never accept insecure fallbacks.

**Practical implementation:**
```python
# Fail open (dangerous)
db_password = os.getenv("DB_PASSWORD", "default_password")   # NEVER do this

# Fail closed (correct)
db_password = os.getenv("DB_PASSWORD")
if not db_password:
    raise RuntimeError("DB_PASSWORD not set — cannot start without credentials")
```

**Signal:** Tests security mindset. Engineers who understand fail-closed have internalized that availability sometimes must yield to security — not the other way around.

---

## Quick Reference — Key Concepts Cheat Sheet

| Concept | One-liner |
|---------|----------|
| Secret sprawl | Secrets in many uncontrolled locations |
| Static secret | Fixed value, long-lived, shared |
| Dynamic secret | Generated on-demand, unique, auto-expiring |
| Blast radius | Damage scope if a secret is compromised |
| Vault auth method | How workloads prove their identity to Vault |
| Vault secret engine | Plugin that generates/stores secrets (KV, DB, PKI) |
| Vault policy | HCL document defining path-level access |
| ESO | Kubernetes operator syncing secrets from external backends |
| SecretStore | ESO CRD: connection config to a secret backend |
| ExternalSecret | ESO CRD: what to fetch and where to put it |
| Sealed Secrets | K8s secrets encrypted for Git (cluster-specific) |
| SOPS | File encryption tool (any format, value-level, multi-backend) |
| KMS encryption | Encrypting K8s etcd data with an external key manager |
| OIDC in CI/CD | Secretless auth using signed JWTs per pipeline job |
| Workload Identity | AKS pods authenticating to Azure via federated identity |
| Break-glass | Emergency access when primary channels fail |
| Rotation | Replacing a secret value to limit exposure window |
| Zero-downtime rotation | Dual-active: old+new both valid during transition |
| Audit trail | Log of every secret access (who, when, from where) |
| Fail closed | Refuse to start rather than use insecure defaults |
