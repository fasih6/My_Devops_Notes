# Secret Rotation & Lifecycle — Keeping Secrets Healthy Over Time

## Why Rotation Matters

A secret that never rotates is a secret that:
- Is valid indefinitely if leaked
- May be held by ex-employees or decommissioned services
- Cannot be safely revoked without disruption
- Grows in blast radius over time (more systems may have cached it)

Rotation limits the window of exposure. A secret rotated daily has a maximum exposure window of 24 hours. A secret never rotated has an unbounded exposure window.

```
Risk = Exposure Window × Probability of Compromise

Short TTL → small exposure window → lower risk even if compromised
Long TTL  → large exposure window → high risk if compromised
```

---

## Rotation Strategies

### Strategy 1: Manual Rotation

A human generates a new secret, updates it in the secret store, and updates all consumers.

```
Pros:  Simple to understand, no tooling required
Cons:  Toil-heavy, error-prone, gets skipped, doesn't scale
When:  Small teams, infrequent rotation, non-critical secrets
```

Manual rotation process:
```
1. Generate new secret value
2. Update in Vault/Key Vault
3. Update every service that uses the secret (restart or reload)
4. Verify all services are using new value
5. Invalidate old secret
6. Document rotation in audit log
```

The risk: step 3-4 is where things break. If any service is missed, it fails. Coordination across multiple teams is required.

### Strategy 2: Automatic Rotation (Scheduled)

A rotation job runs on a schedule and rotates secrets automatically.

```
Azure Key Vault:    Built-in rotation policy (rotates on schedule)
HashiCorp Vault:    Database engine auto-rotates static role passwords
AWS Secrets Manager: Built-in rotation with Lambda functions
```

**Azure Key Vault automatic rotation:**
```bash
# Set rotation policy on a secret
az keyvault secret set-attributes \
  --vault-name my-keyvault \
  --name checkout-db-password \
  --expires "2025-12-31T00:00:00Z"

# Configure rotation policy
az keyvault secret rotation-policy update \
  --vault-name my-keyvault \
  --name checkout-db-password \
  --value @rotation-policy.json
```

```json
// rotation-policy.json
{
  "lifetimeActions": [
    {
      "trigger": {
        "timeBeforeExpiry": "P30D"     // 30 days before expiry
      },
      "action": {
        "type": "Rotate"               // Auto-rotate
      }
    },
    {
      "trigger": {
        "timeBeforeExpiry": "P7D"      // 7 days before expiry
      },
      "action": {
        "type": "Notify"               // Send notification
      }
    }
  ],
  "attributes": {
    "expiryTime": "P1Y"                // Secret expires 1 year after creation
  }
}
```

**HashiCorp Vault static role rotation (Database engine):**
```bash
# Create a static role — Vault manages a single DB user but rotates password automatically
vault write database/static-roles/checkout-app \
  db_name=checkout-postgres \
  username="checkout_app_user" \          # Vault manages this existing user
  rotation_period="24h" \                 # Rotate every 24 hours
  rotation_statements="ALTER USER \"{{name}}\" WITH PASSWORD '{{password}}';"

# Vault automatically rotates the password every 24 hours
# Services read current password via:
vault read database/static-creds/checkout-app
```

### Strategy 3: Dynamic Secrets (Best)

Not rotation at all — secrets are generated fresh per request and expire automatically.

```
Request credentials → get unique credential with 1-hour TTL
After 1 hour → credential automatically invalidated
Next request → get new unique credential

No rotation ceremony needed. Expiry IS rotation.
```

Dynamic secrets are covered in `02-hashicorp-vault.md` and `03-vault-advanced.md`.

---

## Zero-Downtime Rotation

The hardest part of rotation is updating consumers without causing downtime. Three patterns:

### Pattern 1: Dual-Active (Two Valid Versions)

Keep both old and new secret valid simultaneously during the transition:

```
Step 1: Generate new secret, activate it alongside old
  Old secret: valid ✅
  New secret: valid ✅

Step 2: Rolling update — consumers gradually switch to new secret
  Service A restarts with new secret ✅
  Service B restarts with new secret ✅
  Service C restarts with new secret ✅

Step 3: Verify all consumers using new secret

Step 4: Revoke old secret
  Old secret: invalid ❌
  New secret: valid ✅
```

**Example — dual active database users:**
```sql
-- Step 1: Create new DB user with new password
CREATE USER checkout_user_v2 WITH PASSWORD 'new-secure-password';
GRANT SELECT, INSERT, UPDATE ON ALL TABLES IN SCHEMA public TO checkout_user_v2;

-- Step 2: Update secret store with new credentials
vault kv put secret/checkout/db \
  username=checkout_user_v2 \
  password=new-secure-password

-- Step 3: Rolling restart of services (they pick up new credentials)
kubectl rollout restart deploy/checkout-api -n checkout

-- Step 4: Wait for rollout to complete, verify no errors

-- Step 5: Revoke old user
REVOKE ALL ON ALL TABLES IN SCHEMA public FROM checkout_user_v1;
DROP USER checkout_user_v1;
```

### Pattern 2: Versioned Secrets (Key Vault / Vault KV v2)

Both Azure Key Vault and Vault KV v2 maintain secret versions. During rotation, consumers can read the previous version while transitioning:

```
Azure Key Vault versioning:
  Version 1 (old): enabled=true  ← old consumers still work
  Version 2 (new): enabled=true  ← new consumers use this

  Consumers gradually updated to use "latest" version
  Once all consumers updated → disable Version 1
```

```bash
# Azure Key Vault — disable old version after rotation
az keyvault secret set-attributes \
  --vault-name my-keyvault \
  --name checkout-db-password \
  --version <old-version-id> \
  --enabled false
```

### Pattern 3: Lease Renewal (Vault Dynamic Secrets)

For Vault dynamic secrets, consumers renew leases before expiry:

```
Vault Agent or application SDK renews lease when < 50% TTL remains:

  00:00 — Credential issued, TTL=1h
  00:25 — Vault Agent renews lease (< 50% remaining)
  00:50 — Vault Agent renews lease again
  01:00 — If renewal fails → application gets new credential
           Old credential automatically revoked
```

No rotation ceremony — Vault handles everything.

---

## Rotation for Specific Secret Types

### Database Credentials

```
Recommendation: Dynamic secrets (Vault) or static role with 24h rotation

Manual rotation process (if no Vault):
  1. Generate new password
  2. ALTER USER checkout_user WITH PASSWORD 'new-password'
  3. Update Key Vault secret
  4. Wait for ESO/CSI driver to sync (or force refresh)
  5. Rolling restart of services consuming the secret
  6. Verify services running cleanly
  
Rotation frequency: every 30 days (static), 1 hour (dynamic)
```

### API Keys (External Services)

```
Challenge: External services (Stripe, Twilio) issue API keys
           You can't dynamically generate them from your side

Process:
  1. Generate new API key in the external service's dashboard
  2. Store new key in Key Vault/Vault alongside old key
  3. Update services to use new key (rolling restart)
  4. Verify all traffic uses new key (monitor API calls with new key)
  5. Revoke old key in the external service

Rotation frequency: every 90 days minimum
```

### TLS Certificates

```
Recommendation: Short-lived certs (24-72h) via cert-manager or Vault PKI
→ No manual rotation needed at all

For long-lived certs (not recommended):
  cert-manager handles automatic renewal:
    renewBefore: 30d   ← renew 30 days before expiry
  Alert if cert < 14 days from expiry (cert-manager failed to renew)

Rotation frequency: cert-manager handles it
```

### Cloud Provider Credentials (Service Principals, IAM Keys)

```
Recommendation: Use Managed Identity / Workload Identity — no static keys
→ No rotation needed

If static keys are unavoidable (legacy):
  Azure: rotate service principal client secret every 90 days
  AWS: rotate IAM access key every 90 days
  
Process:
  1. Create new key/secret alongside old
  2. Update in secret store
  3. Update consumers
  4. Delete old key/secret

Rotation frequency: every 90 days maximum
```

### Encryption Keys

```
Encryption key rotation is special — you must re-encrypt all existing data:

  Step 1: Generate new key version
  Step 2: Re-encrypt all data with new key
  Step 3: Retire old key version (keep for decrypting legacy data if needed)

Azure Key Vault: supports key rotation policies
  → New key version generated automatically
  → Old version kept for decryption of existing data
  → Application uses "current" version (always latest)

Rotation frequency: annually or per compliance requirement
```

---

## Secret Expiry and Alerts

Set expiry on all static secrets and alert before expiry:

```bash
# Azure Key Vault — set expiry on creation
az keyvault secret set \
  --vault-name my-keyvault \
  --name checkout-db-password \
  --value "supersecret" \
  --expires "2025-03-31T00:00:00Z"

# Alert when secret expires within 30 days (Azure Monitor)
# AzureDiagnostics KQL query:
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where OperationName == "SecretNearExpiry"
| where TimeGenerated > ago(1d)
| project SecretName = id_s, ExpiryTime = resultDescription_s
```

```yaml
# Prometheus alert for cert-manager certificates near expiry
- alert: CertificateExpiringSoon
  expr: |
    certmanager_certificate_expiration_timestamp_seconds
    - time() < 14 * 24 * 3600
  for: 1h
  labels:
    severity: warning
  annotations:
    summary: "Certificate {{ $labels.name }} expires in less than 14 days"
    runbook: "https://wiki.internal/runbooks/cert-expiry"
```

---

## Secret Access Reviews

Regular access reviews ensure least privilege is maintained over time:

```
Quarterly review checklist:
  □ Which services have access to each secret?
  □ Do all services still need the access they have?
  □ Are there any orphaned credentials (services decommissioned)?
  □ Are any secrets shared across environments (dev secrets used in prod)?
  □ Are rotation schedules being followed?
  □ Are any secrets approaching expiry?
  □ Are audit logs being reviewed for anomalous access patterns?
```

```bash
# List all policies attached to Vault tokens (who has access to what)
vault policy list

# Check which auth roles have which policies
vault list auth/kubernetes/role
vault read auth/kubernetes/role/checkout
# Shows: bound_service_account_names, policies, ttl

# Azure Key Vault — list all role assignments
az role assignment list \
  --scope /subscriptions/<sub>/.../vaults/my-keyvault \
  --output table
```

---

## Break-Glass Procedures

A break-glass procedure is an emergency access mechanism for when normal access channels fail.

```
Scenario: Vault is unavailable. Production is down.
          The checkout service can't get DB credentials.
          Normal secret management is broken.

Break-glass procedure:
  1. Designated break-glass holder (on-call lead) uses emergency credentials
  2. Emergency credentials are stored in a physically secure location
     (e.g. printed in a sealed envelope in a locked safe, OR
      in a separate, isolated secret store not dependent on Vault)
  3. Access is logged manually and reviewed immediately after
  4. Emergency credentials are rotated immediately after use
  5. Postmortem: why was break-glass needed? How to prevent?
```

**Break-glass requirements:**
- Emergency credentials must be accessible when primary systems are down
- Access must require at least two people (dual-control)
- Every use must be logged and reviewed
- Credentials must be rotated after every use
- Procedure must be tested annually (before you need it)

---

## Audit Trail — Who Accessed What and When

All secret accesses must be logged. This enables:
- Detecting unauthorized access (anomaly detection)
- Forensics after a breach (what did the attacker access?)
- Compliance reporting (who accessed PII-adjacent secrets)
- Access reviews (which services are actively using which secrets)

```bash
# Vault audit log (JSON format)
vault audit enable file file_path=/vault/logs/vault-audit.log

# Sample audit log entry
{
  "time": "2024-11-15T14:35:22Z",
  "type": "request",
  "auth": {
    "client_token": "hmac-sha256:abc...",
    "accessor": "hmac-sha256:def...",
    "display_name": "kubernetes-checkout/checkout-sa",
    "policies": ["checkout-policy"],
    "metadata": {
      "role": "checkout",
      "service_account_name": "checkout-sa",
      "service_account_namespace": "checkout"
    }
  },
  "request": {
    "operation": "read",
    "path": "database/creds/checkout-app",
    "remote_address": "10.0.1.45"
  }
}

# Azure Key Vault audit (Log Analytics)
AzureDiagnostics
| where ResourceProvider == "MICROSOFT.KEYVAULT"
| where OperationName == "SecretGet"
| where ResultType == "Success"
| project TimeGenerated, CallerIPAddress,
    identity_claim_unique_name_s, requestUri_s
| order by TimeGenerated desc
```

---

## Interview Questions — Secret Rotation & Lifecycle

**Q: What is zero-downtime secret rotation and how do you achieve it?**
A: Zero-downtime rotation keeps both old and new secrets valid simultaneously during the transition. The process: generate the new secret, activate it alongside the old one, do a rolling restart of all consumers (they pick up the new secret), verify all consumers are using the new secret, then revoke the old one. For databases this means creating a new user with new credentials while the old user remains valid, then dropping the old user after the rollout completes.

**Q: How often should secrets be rotated?**
A: It depends on the secret type and risk level. Database credentials: dynamic (hourly) with Vault, or every 30 days static. API keys to external services: every 90 days. TLS certificates: automated via cert-manager with 24-72h TTL (short-lived) or 30-day renewal for longer-lived certs. Cloud provider credentials: avoid static keys entirely with Managed Identity; if unavoidable, rotate every 90 days. Encryption keys: annually or per compliance requirement. The general rule: the shorter the TTL, the smaller the blast radius if compromised.

**Q: What is a break-glass procedure in secrets management?**
A: A break-glass procedure is an emergency access mechanism used when normal secret management channels are unavailable. It requires: storing emergency credentials in a physically secure, offline location; dual-control access (two people required to use it); mandatory logging of every use; immediate rotation of emergency credentials after use; and annual testing. It exists because if Vault is down and you have no other way to get credentials, production suffers — break-glass is the last resort that keeps the business running.

**Q: How do you detect unauthorized secret access?**
A: Enable audit logging on all secret backends (Vault audit devices, Azure Key Vault diagnostic logs to Log Analytics). Set up alerts for: access from unexpected IP addresses, access outside business hours for human identities, access to secrets by services that shouldn't need them, high-frequency access that might indicate exfiltration, and failed access attempts (potential credential stuffing). Review audit logs regularly and look for anomalies — a service that normally accesses 2 secrets but suddenly accesses 50 is a red flag.
