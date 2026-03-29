# Compliance & Governance

## Why Compliance Matters in DevOps

Compliance is not just about auditors and paperwork — it directly shapes architecture decisions. In Germany and the EU, compliance requirements affect:
- Where data can be stored (GDPR data residency)
- How secrets must be managed (ISO 27001 controls)
- What logging you must retain (SOC 2, NIS2 audit trails)
- How you respond to incidents (GDPR 72-hour breach notification)

As a DevOps/Platform engineer, you implement the technical controls that satisfy compliance requirements.

## GDPR — What Engineers Need to Know

GDPR (General Data Protection Regulation) is EU law. It applies to any company processing EU personal data.

### Key Principles with Engineering Impact

| Principle | Engineering implication |
|-----------|------------------------|
| **Data minimisation** | Don't log PII you don't need. Strip it from logs |
| **Purpose limitation** | Don't use analytics data for unrelated purposes |
| **Storage limitation** | Implement data retention policies, auto-delete old data |
| **Integrity and confidentiality** | Encrypt PII at rest and in transit |
| **Accountability** | Audit logs for all data access — who read what, when |
| **Right to erasure** | Architecture must support deleting a user's data |

### PII in Logs

```python
# Bad — PII in logs
logger.info(f"User {user.email} logged in from {request.remote_addr}")

# Good — use IDs, not PII
logger.info(f"User {user.id} logged in", extra={"user_id": user.id})

# Structured log without PII
{
  "timestamp": "2024-01-15T10:23:00Z",
  "event": "user.login",
  "user_id": "usr_abc123",      # internal ID, not email
  "ip_hash": "sha256:abc...",   # hashed IP, not raw IP
  "result": "success"
}
```

Log scrubbing (using vector.dev or FluentBit):
```yaml
# vector.toml — redact PII from logs before shipping to Elasticsearch
[transforms.redact_pii]
type = "remap"
inputs = ["app_logs"]
source = '''
  .message = redact(.message, filters: ["us_social_security_number", "email_address"])
  .fields.email = "[REDACTED]"
'''
```

### Data Residency

GDPR requires that EU personal data stays in the EU (or in countries with adequacy decisions).

```hcl
# Terraform — enforce EU region for data storage
resource "aws_s3_bucket" "user_data" {
  bucket = "company-user-data"
  # EU Frankfurt — GDPR compliant
}

resource "aws_s3_bucket" "user_data_config" {
  provider = aws.eu-central-1  # enforce region in provider

  # Enable encryption
  server_side_encryption_configuration {
    rule {
      apply_server_side_encryption_by_default {
        sse_algorithm = "aws:kms"
      }
    }
  }
}

# Block public access
resource "aws_s3_bucket_public_access_block" "user_data" {
  bucket                  = aws_s3_bucket.user_data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

### GDPR Breach Notification

GDPR requires notifying supervisory authorities within **72 hours** of discovering a breach. This means:
- You must have breach detection (monitoring, alerting)
- You must have an incident response plan
- You must know what data was affected (SBOM equivalent for data — data inventory)

## SOC 2

SOC 2 is a US standard (from AICPA) but increasingly required by global companies — especially SaaS selling to US enterprise customers.

SOC 2 Trust Services Criteria:

| Criteria | Engineering focus |
|----------|------------------|
| **Security** | Access controls, encryption, vulnerability management |
| **Availability** | Uptime SLAs, disaster recovery, monitoring |
| **Processing Integrity** | Data processing is complete and accurate |
| **Confidentiality** | Sensitive data identified and protected |
| **Privacy** | PII handling (overlaps with GDPR) |

Controls you'll implement as a DevOps engineer:

```
Access control:
  ✓ MFA enforced for all engineers
  ✓ Least-privilege IAM roles
  ✓ Access reviews (quarterly)
  ✓ Offboarding process automated

Change management:
  ✓ All changes go through CI/CD (no manual edits in prod)
  ✓ Peer review required for all code changes
  ✓ Deployment approvals for production

Vulnerability management:
  ✓ Automated scanning (SAST, SCA, container scan)
  ✓ SLA for patching critical CVEs (< 7 days)
  ✓ CVE tracking in ticketing system

Logging & monitoring:
  ✓ All production access logged
  ✓ Log retention ≥ 1 year
  ✓ Alerts on anomalous access
  ✓ Uptime monitoring with SLAs
```

## ISO 27001

Common in German enterprise. An ISMS (Information Security Management System) framework.

Key controls relevant to DevOps:

| Control | Implementation |
|---------|---------------|
| **A.8.2** — Information classification | Tag resources with data classification labels |
| **A.9.4** — Access control to systems | IAM, RBAC, SSH key management |
| **A.12.1** — Operations procedures | Documented runbooks, DR procedures |
| **A.12.6** — Vulnerability management | Automated scanning, patch management SLAs |
| **A.14.2** — Security in dev processes | SAST, SCA, code review gates |
| **A.16.1** — Incident management | Incident response plan, post-mortems |
| **A.17.1** — Business continuity | Backup + restore testing, RTO/RPO defined |

## Policy-as-Code with OPA

OPA (Open Policy Agent) lets you define compliance policies as code and enforce them automatically.

```rego
# policies/data-residency.rego
package data_residency

# Deny AWS resources outside EU regions
deny[msg] {
  resource := input.resource.aws_s3_bucket[name]
  provider := input.provider.aws
  not startswith(provider.region, "eu-")
  msg := sprintf("S3 bucket '%s' must be in an EU region (GDPR compliance)", [name])
}

# Deny RDS without encryption
deny[msg] {
  resource := input.resource.aws_db_instance[name]
  not resource.storage_encrypted
  msg := sprintf("RDS instance '%s' must have storage encryption enabled (ISO 27001 A.10.1)", [name])
}
```

```rego
# policies/tagging.rego
package tagging

required_tags := {"environment", "team", "data-classification", "cost-centre"}

# Require tags for cost and compliance
deny[msg] {
  resource := input.resource.aws_s3_bucket[name]
  provided := {tag | resource.tags[tag]}
  missing := required_tags - provided
  count(missing) > 0
  msg := sprintf("Bucket '%s' missing required tags: %v", [name, missing])
}
```

## Audit Logging

Compliance frameworks all require audit trails. What to log:

```yaml
# What must be auditable:
- Authentication events (login, logout, failed attempts)
- Authorisation decisions (access granted/denied)
- Data access (who read sensitive data, when)
- Configuration changes (who changed what, when)
- Privileged operations (kubectl exec, sudo, cloud console access)
- Secret access (who read which secret from Vault)
```

Vault audit logging:
```bash
# Enable file audit log
vault audit enable file file_path=/vault/logs/audit.log

# Enable syslog
vault audit enable syslog

# Audit log format (every request/response logged)
{
  "time": "2024-01-15T10:23:00.000Z",
  "type": "request",
  "auth": {
    "client_token": "hmac-sha256:abc...",
    "accessor": "hmac-sha256:def...",
    "display_name": "kubernetes-production/myapp-sa",
    "policies": ["default", "myapp-policy"]
  },
  "request": {
    "id": "abc123",
    "operation": "read",
    "path": "secret/data/myapp/config"
  }
}
```

Kubernetes audit log retention with Loki:
```yaml
# Grafana Loki — ship K8s audit logs
apiVersion: v1
kind: ConfigMap
metadata:
  name: promtail-config
data:
  promtail.yaml: |
    scrape_configs:
    - job_name: kubernetes-audit
      static_configs:
      - targets:
          - localhost
        labels:
          job: kubernetes-audit
          __path__: /var/log/kubernetes/audit.log
      pipeline_stages:
      - json:
          expressions:
            user: user.username
            verb: verb
            resource: objectRef.resource
            namespace: objectRef.namespace
      - labels:
          user:
          verb:
          resource:
```

## Compliance Automation Tools

### Cloud Compliance Scanning

```bash
# Prowler — AWS/Azure/GCP compliance scanner
# Checks against CIS, GDPR, SOC2, ISO 27001, NIST

# AWS checks
prowler aws --compliance gdpr
prowler aws --compliance cis_level2_1.4.0
prowler aws --compliance soc2

# Azure checks
prowler azure --compliance cis_m365
prowler azure --compliance gdpr

# Output formats
prowler aws --output-formats json,html --output-directory ./results
```

```bash
# ScoutSuite — multi-cloud security auditing
python scout.py aws
python scout.py azure
```

### Policy Libraries

```bash
# Terraform Sentinel (HashiCorp) — enterprise
# Use with Terraform Cloud/Enterprise

# Example Sentinel policy
import "tfplan/v2" as tfplan

# Require all S3 buckets to be in EU
deny_non_eu_s3 = rule {
  all tfplan.resource_changes as _, rc {
    rc.type is not "aws_s3_bucket" or
    rc.change.after.region matches "^eu-"
  }
}

main = rule { deny_non_eu_s3 }
```

## NIS2 — EU Cybersecurity Directive (2024)

NIS2 (Network and Information Security Directive 2) expanded scope and requirements:

Affects: Essential entities (energy, transport, health, water, digital infra) and Important entities (postal, waste, chemicals, food, manufacturing).

Engineering requirements:
- Risk assessment and security policies
- Incident handling procedures
- Business continuity and backup management
- Supply chain security (vetting third-party software)
- Security in system acquisition and development
- Policies for cryptography and encryption
- HR security, access control, asset management
- Multi-factor authentication

Breach reporting: **24 hours** for early warning, **72 hours** for incident notification (stricter than GDPR).

## Data Classification

Tag your infrastructure with data sensitivity levels:

```hcl
# Terraform resource tagging for data classification
locals {
  compliance_tags = {
    "data-classification" = "confidential"  # public | internal | confidential | restricted
    "gdpr-relevant"       = "true"
    "data-residency"      = "eu"
    "retention-days"      = "365"
    "owner"               = "platform-team"
  }
}

resource "aws_s3_bucket" "user_data" {
  bucket = "company-user-pii"
  tags   = local.compliance_tags
}
```

Kubernetes namespace labels for compliance:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    data-classification: confidential
    gdpr-relevant: "true"
    environment: production
    team: platform
    # Pod security enforced at namespace level
    pod-security.kubernetes.io/enforce: restricted
```

## Incident Response Process

```
1. DETECT           2. CONTAIN          3. ERADICATE
Monitoring alert    Isolate affected    Remove threat,
SIEM event          systems             rotate credentials
User report         Block attacker IP   Patch vulnerability
                    Revoke tokens

4. RECOVER          5. POST-INCIDENT
Restore service     Root cause analysis
Verify integrity    Incident report
Resume operations   Process improvement
                    Notify affected
                    users (GDPR: 72h)
```

Post-incident report template:
```markdown
# Incident Report: [Title]

**Date:** YYYY-MM-DD
**Severity:** Critical / High / Medium / Low
**Duration:** X hours
**Impact:** Describe user/data impact

## Timeline
- HH:MM — Incident detected
- HH:MM — Incident response team notified
- HH:MM — Root cause identified
- HH:MM — Containment action taken
- HH:MM — Service restored

## Root Cause
[Technical root cause]

## Contributing Factors
[What made this possible?]

## Resolution
[What was done to fix it?]

## Action Items
| Action | Owner | Due date |
|--------|-------|----------|
| Patch X | Team A | 2024-02-01 |
| Add monitoring for Y | Team B | 2024-01-25 |

## GDPR Notification Required?
[ ] Yes — notify DPA within 72 hours
[ ] No — data not affected
```
