# DevSecOps Core Concepts

## The Shift-Left Principle

"Shift-left" means moving security activities earlier (to the left) in the development timeline.

```
LEFT (early, cheap)                          RIGHT (late, expensive)
│                                                                   │
▼                                                                   ▼
Plan → Code → Build → Test → Release → Deploy → Operate → Monitor
 ↑                                                           ↑
Fix costs $1                                      Fix costs $100+
```

The earlier a vulnerability is found, the cheaper it is to fix. A developer catching a hardcoded secret in their IDE costs minutes. The same secret discovered after a breach costs millions.

## CIA Triad — Security Fundamentals

Every security decision maps back to one or more of these:

| Pillar | Definition | DevOps Example |
|--------|-----------|----------------|
| **Confidentiality** | Data is accessible only to authorised parties | Encrypting secrets, RBAC, least-privilege IAM |
| **Integrity** | Data is not tampered with | Image signing, Git commit signing, checksums |
| **Availability** | Systems are accessible when needed | DDoS protection, rate limiting, redundancy |

## OWASP Top 10 (Web Application Security)

The most critical web application security risks. Every DevSecOps engineer should know these:

1. **Broken Access Control** — Users can access resources they shouldn't (e.g. accessing /api/user/2 when you're user 1)
2. **Cryptographic Failures** — Sensitive data exposed due to weak/missing encryption (HTTP instead of HTTPS, MD5 passwords)
3. **Injection** — Untrusted data sent to an interpreter (SQL injection, command injection, LDAP injection)
4. **Insecure Design** — Flaws in design itself, not just implementation (missing rate limiting, no MFA for admin)
5. **Security Misconfiguration** — Default creds, unnecessary features enabled, verbose error messages
6. **Vulnerable and Outdated Components** — Using libraries with known CVEs (Log4Shell is the prime example)
7. **Identification and Authentication Failures** — Weak passwords, broken session management, no MFA
8. **Software and Data Integrity Failures** — CI/CD pipeline tampering, insecure deserialisation, no signature verification
9. **Security Logging and Monitoring Failures** — Not logging, not alerting, not detecting breaches
10. **Server-Side Request Forgery (SSRF)** — App fetches a remote resource without validating the URL (used to hit AWS metadata endpoint)

## OWASP Top 10 for Containers/Kubernetes (Separate list)

1. Insecure workload configuration (running as root)
2. Supply chain vulnerabilities (untrusted base images)
3. Overly permissive RBAC
4. Lack of network segmentation
5. Inadequate logging and monitoring
6. Broken authentication (exposed dashboards, weak API server auth)
7. Missing secrets management
8. Misconfigured container runtime
9. Insecure container image
10. Vulnerable application code

## Threat Modeling

Threat modeling is the structured process of identifying potential threats before building, so you can design defences in advance.

### STRIDE Framework

The most common threat modeling framework:

| Letter | Threat | Example | Mitigation |
|--------|--------|---------|-----------|
| **S** | Spoofing | Attacker impersonates a service | mTLS, signed JWTs |
| **T** | Tampering | Attacker modifies data in transit | HTTPS, checksums, signing |
| **R** | Repudiation | User denies an action occurred | Audit logging, non-repudiation |
| **I** | Information Disclosure | Sensitive data leaked | Encryption, least privilege |
| **D** | Denial of Service | System made unavailable | Rate limiting, autoscaling |
| **E** | Elevation of Privilege | Lower-privilege user gains more access | Least privilege, RBAC |

### Threat Modeling Process (4 Steps)

```
1. DIAGRAM          2. IDENTIFY         3. MITIGATE         4. VALIDATE
What are we         What can go         How do we           Did we fix it?
building?           wrong?              fix it?
- Data flows        - STRIDE threats    - Controls          - Tests
- Trust             - Attack surface    - Countermeasures   - Reviews
  boundaries        - Entry points      - Risk acceptance   - Re-model
```

### Attack Surface

Everything that can be reached and potentially exploited:
- Network interfaces, open ports
- APIs (REST, gRPC, GraphQL)
- User input fields
- Third-party libraries and dependencies
- Container images and registries
- CI/CD pipeline itself
- Secrets and credentials

## Zero Trust Architecture

**Old model (castle-and-moat):** Trust everything inside the network perimeter.

**Zero Trust:** Never trust, always verify — regardless of whether traffic comes from inside or outside the network.

Zero Trust principles:
- Verify explicitly — always authenticate and authorise based on all available data points
- Use least-privilege access — limit user access with just-in-time and just-enough-access
- Assume breach — minimise blast radius, segment access, verify end-to-end encryption

Zero Trust in practice:
```yaml
# Every service call requires:
- Service identity (mTLS, SPIFFE/SPIRE)
- Short-lived credentials (no long-lived static tokens)
- Network policy (deny-all by default, allow explicitly)
- Audit logging (every request logged)
```

## Principle of Least Privilege

Grant the minimum permissions necessary to perform a task. Nothing more.

In DevOps contexts:
- IAM roles with only the S3 buckets they need, not `s3:*`
- Kubernetes service accounts with only the verbs they need
- CI/CD pipeline tokens that can only push to specific registries
- Developer access only to the environments they work on
- Database users with SELECT only, not ALTER TABLE

```yaml
# Bad — overly permissive
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
rules:
- apiGroups: ["*"]
  resources: ["*"]
  verbs: ["*"]

# Good — least privilege
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "watch"]
```

## Defence in Depth

Layer multiple security controls so that if one fails, others still protect you.

```
Layer 1: Network (firewall, NSG, security groups)
Layer 2: Application (WAF, input validation, authentication)
Layer 3: Data (encryption at rest, encryption in transit)
Layer 4: Identity (MFA, short-lived credentials, RBAC)
Layer 5: Monitoring (SIEM, anomaly detection, alerting)
```

No single control is sufficient. An attacker who bypasses the network firewall still hits the application layer, then the data layer.

## Vulnerability Scoring — CVSS

CVSSv3 scores vulnerabilities from 0.0 to 10.0:

| Score Range | Severity | Action |
|-------------|----------|--------|
| 9.0 – 10.0 | **Critical** | Patch immediately |
| 7.0 – 8.9 | **High** | Patch within 7 days |
| 4.0 – 6.9 | **Medium** | Patch within 30 days |
| 0.1 – 3.9 | **Low** | Patch in next cycle |

CVSS factors: Attack vector, complexity, privileges required, user interaction, scope, impact on C/I/A.

CVE (Common Vulnerabilities and Exposures) — the unique identifier for a known vulnerability. Example: `CVE-2021-44228` is Log4Shell.

## Security in the Software Supply Chain

Modern applications are mostly third-party code. A typical Node.js app might have:
- 10 direct dependencies
- 300+ transitive dependencies
- Thousands of lines of code you didn't write

Supply chain attacks target this:
- **Dependency confusion** — attacker publishes a malicious package with the same name as an internal one
- **Typosquatting** — attacker publishes `reqeusts` (typo of `requests`)
- **Compromised maintainer** — attacker takes over a legitimate package (xz-utils incident 2024)

Defences:
- Pin exact versions (`==1.2.3` not `>=1.2.0`)
- Verify checksums/signatures
- Generate and track SBOMs
- Use private registries with vetted packages
- Scan dependencies for CVEs in CI/CD

## Key Security Standards to Know

| Standard | What it covers | Where you'll see it |
|----------|---------------|---------------------|
| **OWASP** | Web app security risks and testing guide | Development, pen testing |
| **CIS Benchmarks** | Hardening guides for OS, Docker, K8s | Infrastructure |
| **NIST CSF** | Cybersecurity framework (Identify, Protect, Detect, Respond, Recover) | Enterprise security programs |
| **ISO 27001** | Information security management system | German enterprise compliance |
| **SOC 2** | Security, availability, confidentiality controls for SaaS | US companies, increasingly global |
| **GDPR** | Personal data protection | All EU/Germany operations |
| **BSI IT-Grundschutz** | German federal hardening guidelines | German public sector, critical infra |
