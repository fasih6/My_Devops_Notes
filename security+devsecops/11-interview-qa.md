# DevSecOps — Interview Q&A

## Core Concepts

**Q: What is DevSecOps and how does it differ from DevOps?**

DevOps integrates development and operations into a continuous delivery pipeline. DevSecOps adds security as a first-class concern throughout that pipeline — not as a final gate but as an embedded practice at every stage. The key idea is shift-left: catching vulnerabilities at code time (cheap) rather than post-deployment (expensive).

Traditional: Dev → Ops → Security reviews at the end
DevSecOps: Security integrated at every stage — pre-commit hooks, CI scanning, runtime monitoring

---

**Q: What is "shift-left" in security?**

Shift-left means moving security activities earlier in the SDLC. A developer finding a SQL injection pattern in their IDE costs 5 minutes to fix. The same issue found in production after exploitation can cost millions. Shift-left implements this via:
- IDE plugins (SonarLint, Semgrep)
- Pre-commit hooks (gitleaks, detect-secrets)
- SAST in CI on every PR
- Security unit tests
- Threat modeling during design

---

**Q: Explain the CIA triad with examples.**

CIA = Confidentiality, Integrity, Availability.

- **Confidentiality**: only authorised parties can access data. Example: encrypting S3 buckets, using RBAC so only the payments team can read card data.
- **Integrity**: data hasn't been tampered with. Example: signing container images with cosign so you know the image in production is what was built in CI.
- **Availability**: systems are accessible when needed. Example: rate limiting an API to prevent DoS attacks from taking down the service.

---

**Q: What is OWASP Top 10 and why does it matter to a DevOps engineer?**

OWASP Top 10 is a list of the most critical web application security risks. As a DevOps engineer it matters because:
- SAST tools (Semgrep, SonarQube) map their rules to OWASP categories
- CI/CD pipelines should be configured to fail on OWASP violations
- Infrastructure decisions affect OWASP categories (e.g. security misconfiguration is OWASP #5)
- Interview panels frequently ask which OWASP categories you address with your tools

Key ones to know: Injection (SQL, command), Broken Access Control, Security Misconfiguration, Vulnerable Components.

---

**Q: What is the difference between SAST, DAST, SCA, and container scanning?**

| Type | When | Finds | Tools |
|------|------|-------|-------|
| SAST | Code written | Vulnerable source code patterns | Semgrep, SonarQube |
| SCA | Build time | Vulnerable third-party libraries | Snyk, OWASP Dep-Check |
| Container scan | Image built | CVEs in OS packages + dependencies | Trivy, Grype |
| DAST | App running | Live exploitable vulnerabilities | OWASP ZAP |

They complement each other — SAST finds what's in your code, SCA finds what your dependencies bring, container scanning finds what's in the OS layer, DAST confirms real exploitability.

---

## Tools Questions

**Q: How would you integrate Trivy into a CI/CD pipeline?**

I'd add it as a dedicated security stage after the image build:

```yaml
# Stage 1: report all findings
trivy image --format json --output report.json ${IMAGE_TAG}

# Stage 2: gate — fail pipeline on critical
trivy image --exit-code 1 --severity CRITICAL --ignore-unfixed ${IMAGE_TAG}

# Stage 3: generate SBOM for attestation
trivy image --format cyclonedx --output sbom.json ${IMAGE_TAG}
```

The key design decisions:
- `--ignore-unfixed` on the gate to avoid failing on CVEs with no available patch
- Separate report vs gate steps so you always get the full report even when it fails
- Generate SBOM for auditability and incident response

---

**Q: Explain how HashiCorp Vault's dynamic secrets work.**

Instead of creating a static database password and storing it somewhere, Vault creates a unique, short-lived credential for each request:

1. Application authenticates to Vault (e.g. using Kubernetes service account)
2. Application requests database credentials
3. Vault connects to the database and creates a new user with the requested permissions
4. Vault returns the credentials with a TTL (e.g. 1 hour)
5. After TTL expires, Vault revokes the credentials and the database user is deleted

Benefits: No credential sharing between services, no long-lived static passwords, automatic rotation, full audit trail of who requested which credentials.

---

**Q: You've found a critical CVE in a production container image. Walk me through your response.**

1. **Assess**: Check if the vulnerable component is actually reachable/exploitable in our context. CVSS 9.0 is serious but context matters.
2. **Check for fix**: Does a patched version exist? If yes, update immediately.
3. **Temporary mitigation**: If no fix exists, can we mitigate at the network/WAF layer?
4. **Update and redeploy**: Rebuild the image with patched base image or dependency, run through the pipeline (including re-scan to verify the fix).
5. **Review pipeline**: Why didn't we catch this earlier? Update the scan policy if needed.
6. **Document**: Create an incident ticket, document the finding, mitigation, and timeline.

For future prevention: add it to `.trivyignore` with documented reasoning if it's a false positive, or tighten the severity threshold that fails the build.

---

**Q: How do you prevent secrets from being committed to Git?**

Layered approach:
1. **Pre-commit hooks** — `gitleaks protect --staged` runs before every commit, blocks if it finds keys/tokens
2. **CI scanning** — gitleaks or truffleHog runs on every pipeline, scanning recent history
3. **IDE plugins** — Snyk or GitGuardian plugins warn developers in real time
4. **Branch protection** — GitLab/GitHub secret push protection as a server-side check
5. **Developer training** — developers understand why this matters and use `.env.example` not `.env`

If a secret does get committed, treat it as compromised immediately — rotate the credential before removing it from history (removing it from history doesn't help if it's already indexed anywhere).

---

**Q: What is an SBOM and why is it important?**

A Software Bill of Materials is a machine-readable inventory of every component in a software artefact — like a nutrition label for code. It lists direct and transitive dependencies, versions, licenses, and known vulnerabilities.

It's important because:
- **Incident response**: When Log4Shell dropped, teams with SBOMs knew within hours if they were affected. Teams without SBOMs spent weeks manually checking.
- **Compliance**: US Executive Order 14028 requires SBOMs for federal software
- **Supply chain security**: Makes it possible to audit what third-party code you're shipping
- **License compliance**: Identifies if you're accidentally shipping GPL code in a proprietary product

I generate SBOMs with Syft or Trivy and attach them as cosign attestations to container images.

---

**Q: What is OPA/Kyverno and when would you use each?**

Both are Kubernetes admission controllers that enforce policies. The choice depends on the team's background:

**OPA/Gatekeeper**: Uses Rego language. More powerful and flexible — you can write arbitrary logic. Better for complex, cross-cutting policies. Steeper learning curve. Good choice if you already use OPA for Terraform/API policy too (unified policy engine).

**Kyverno**: Uses YAML-native policies. Much easier for Kubernetes engineers who already know YAML. Supports validate, mutate, and generate policies. Less expressive than Rego for complex logic but covers 95% of real use cases.

For a team of Kubernetes operators without dedicated security engineers, I'd choose Kyverno for adoption speed. For a platform team with security focus and cross-cutting policy needs, OPA.

---

**Q: How do you handle a situation where a security scan is blocking too many false positives and slowing down deployments?**

This is a real operational challenge. My approach:

1. **Triage the findings**: Are they truly false positives or accepted risks? Document each one.
2. **Use suppression files** properly: `.trivyignore`, `checkov:skip`, `# nosec` with mandatory comments explaining why.
3. **Tune thresholds**: Consider `--ignore-unfixed` for container scans — CVEs with no available fix shouldn't block deployment.
4. **Separate gate vs report**: Gate only on Critical, report everything. Teams see all findings but aren't blocked by Medium.
5. **Track baseline**: Only fail on *new* findings introduced in this MR, not existing ones.
6. **Create a findings backlog**: Existing findings get tracked as security debt with SLAs, not immediate pipeline blockers.

The goal is high signal, low noise — if developers learn to ignore the scanner because it always cries wolf, you've lost the security benefit entirely.

---

## Kubernetes Security Questions

**Q: Explain Kubernetes RBAC. How would you give a CI/CD pipeline minimal permissions to deploy?**

RBAC has four objects: Role (namespace-scoped permissions), ClusterRole (cluster-wide), RoleBinding (binds Role to a subject), ClusterRoleBinding (binds ClusterRole).

For a CI/CD pipeline deploying to a specific namespace, I'd create:
```yaml
# Minimal role for deployment
kind: Role
rules:
- apiGroups: ["apps"]
  resources: ["deployments"]
  verbs: ["get", "list", "create", "update", "patch"]
- apiGroups: [""]
  resources: ["services", "configmaps"]
  verbs: ["get", "list", "create", "update", "patch"]
# NO secrets access, NO cluster-wide access
```

Then bind it to a service account used only by the pipeline, in only the target namespace.

---

**Q: What is the difference between a NetworkPolicy and a firewall rule?**

A firewall rule operates at the network perimeter — traffic from outside to inside. A Kubernetes NetworkPolicy operates at the pod level within the cluster.

Without NetworkPolicy, all pods in a cluster can talk to all other pods by default. A compromise of one pod can lead to lateral movement to every other service. NetworkPolicies implement microsegmentation — a frontend pod can only talk to the backend, the backend can only talk to the database.

Key difference: NetworkPolicy is declarative K8s YAML, applied by the CNI plugin (Cilium, Calico). It's about pod-to-pod communication, not external ingress.

---

**Q: What does `allowPrivilegeEscalation: false` do and why is it important?**

It prevents a container process from gaining more privileges than its parent process — specifically it blocks `setuid` binaries and `sudo`. Without this, a low-privilege process inside a container could escalate to root even if you set `runAsUser: 10001`.

Combined with `capabilities.drop: [ALL]` and `runAsNonRoot: true`, this is the core of container process hardening. It prevents many container escape techniques that rely on privilege escalation.

---

## Compliance Questions

**Q: What GDPR requirements directly affect how you build a platform?**

Several:
- **Data residency**: Storage resources (S3, databases) must be in EU regions. I enforce this with Terraform/OPA policies.
- **Encryption**: All PII must be encrypted at rest and in transit. I implement this with KMS-managed encryption and HTTPS-only ingress.
- **Access control**: Only authorised users/services can access PII. RBAC, IAM roles with least privilege.
- **Audit logging**: All access to sensitive data must be logged. Vault audit log, K8s audit log, CloudTrail.
- **Right to erasure**: Architecture must support deleting a specific user's data. This affects database design and logging — no PII in immutable logs.
- **Breach notification**: Must notify DPA within 72 hours. Requires detection capability (monitoring, SIEM) and an incident response plan.

---

**Q: What is the difference between SOC 2 and ISO 27001?**

ISO 27001 is an international standard for an Information Security Management System (ISMS). It requires organisations to define, implement, and continuously improve security management. Popular in Europe and large enterprises.

SOC 2 is a US auditing standard (AICPA) focused on five Trust Services Criteria: Security, Availability, Processing Integrity, Confidentiality, Privacy. Common for SaaS companies selling to US enterprise customers.

For Germany: ISO 27001 is more commonly required. Many large German companies (automotive, banking, insurance) require vendors to be ISO 27001 certified. SOC 2 is increasingly requested as well for international customers.

---

## Scenario Questions

**Q: Your team wants to deploy faster but security scans are adding 20 minutes to every pipeline. How do you address this?**

I'd analyse the pipeline first to find what's taking time, then optimise:

1. **Parallelise scans**: SAST, SCA, and container scan can run in parallel, not sequentially. This alone often cuts time by 60%.
2. **Cache Trivy/Snyk databases**: Vulnerability DB downloads are slow. Cache them in CI.
3. **Scope scanning**: Only scan changed files for SAST on non-main branches, not the full codebase.
4. **Fail fast for secrets**: Secret detection is fast — run it first. If it fails, don't run the slow scans.
5. **Pre-built base image**: Maintain a hardened base image with fewer CVEs so container scans are faster.
6. **Separate gate from full report**: The gate (fail/pass) can use `--timeout 5m`, while full reports run async.

The goal is feedback under 10 minutes for most changes.

---

**Q: A developer accidentally pushed AWS credentials to a public GitHub repo. What do you do?**

Immediate response (treat as confirmed compromise, not just potential):
1. **Rotate immediately**: Revoke the exposed key in AWS IAM — don't wait. Even if you got there in 1 minute, scanners index GitHub in seconds.
2. **Check CloudTrail**: Look for any API calls using that key after the commit time. Assume it was used.
3. **Contain blast radius**: If there were unauthorised API calls, what did the attacker do? Are there new IAM users, EC2 instances, data exfiltrated?
4. **Clean up GitHub**: Remove from history (though this doesn't help if it was already indexed). GitHub has a secret scanning feature that may have already notified you.
5. **Post-incident review**: Why didn't pre-commit hooks catch this? Add gitleaks as a pre-commit hook and to CI.
6. **GDPR check**: Was any personal data accessed? If yes, 72-hour DPA notification applies.
