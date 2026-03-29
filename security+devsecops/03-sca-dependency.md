# SCA — Software Composition Analysis & Dependency Security

## What Is SCA?

SCA identifies and analyses **third-party and open-source components** in your codebase. It checks them against vulnerability databases (NVD, OSV, GitHub Advisory) and reports CVEs.

Modern applications are 80-90% third-party code. SCA is how you manage that risk.

```
Your app
├── express@4.18.2         ← direct dependency
│   ├── body-parser@1.20.1 ← transitive dependency
│   └── path-to-regexp@0.1.7 ← transitive (has CVE!)
└── lodash@4.17.21         ← direct (check for prototype pollution CVEs)
```

## Key Tools

### Snyk

Commercial (free tier available) — integrates deeply with IDEs, CI/CD, and registries.

```bash
# Install
npm install -g snyk

# Authenticate
snyk auth

# Test a project (npm, pip, maven, gradle, go, etc.)
snyk test

# Test with JSON output
snyk test --json > snyk-results.json

# Monitor project (sends results to Snyk dashboard)
snyk monitor

# Fix vulnerabilities automatically (updates package.json)
snyk fix

# Test Docker image
snyk container test nginx:latest

# Test IaC files
snyk iac test ./terraform/
```

Snyk in GitLab CI:
```yaml
snyk-security:
  stage: test
  image: snyk/snyk:node
  script:
    - snyk auth ${SNYK_TOKEN}
    - snyk test --severity-threshold=high --json > snyk-report.json
  artifacts:
    when: always
    paths:
      - snyk-report.json
  allow_failure: false  # fail pipeline on high/critical
```

### OWASP Dependency-Check

Free, open-source. Scans for CVEs in project dependencies using NVD data.

```bash
# Run against a Java project
dependency-check.sh \
  --project "MyApp" \
  --scan ./target \
  --format HTML \
  --out ./reports

# Run with suppression file (for false positives)
dependency-check.sh \
  --project "MyApp" \
  --scan . \
  --suppression dependency-check-suppressions.xml

# Fail on CVSS score >= 7 (high severity)
dependency-check.sh \
  --scan . \
  --failOnCVSS 7
```

Suppression file example (for false positives):
```xml
<?xml version="1.0" encoding="UTF-8"?>
<suppressions xmlns="https://jeremylong.github.io/DependencyCheck/dependency-suppression.1.3.xsd">
  <suppress>
    <notes>False positive: this CVE affects a different module we don't use</notes>
    <cve>CVE-2023-12345</cve>
  </suppress>
</suppressions>
```

### pip-audit (Python)

```bash
# Install
pip install pip-audit

# Audit current environment
pip-audit

# Audit from requirements file
pip-audit -r requirements.txt

# JSON output
pip-audit -r requirements.txt -f json

# Fix (upgrades vulnerable packages)
pip-audit --fix -r requirements.txt
```

### npm audit (Node.js — built-in)

```bash
# Basic audit
npm audit

# JSON output
npm audit --json

# Fix automatically
npm audit fix

# Fix breaking changes too
npm audit fix --force

# Only show high+ severity
npm audit --audit-level=high
```

### Trivy for Dependencies

Trivy (covered more in container security) also scans dependency files:
```bash
# Scan a directory for dependency vulnerabilities
trivy fs .

# Scan specific lock files
trivy fs --scanners vuln package-lock.json

# Scan a git repo
trivy repo https://github.com/org/repo
```

## Software Bill of Materials (SBOM)

An SBOM is a complete, machine-readable inventory of all components in your software — like a nutrition label but for code.

**Why SBOMs matter:**
- US Executive Order 14028 (2021) requires SBOMs for federal software
- Enables rapid response to zero-days (e.g. instantly know if you use Log4j)
- Required for many enterprise security compliance programmes

### SBOM Formats

| Format | Standard body | Common use |
|--------|--------------|-----------|
| **SPDX** | Linux Foundation | Broad industry adoption |
| **CycloneDX** | OWASP | DevSecOps focused, richer security metadata |

### Generating SBOMs

```bash
# Syft — generates SBOMs from container images, directories
# Install
curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh

# Generate SBOM for a Docker image
syft nginx:latest -o spdx-json > sbom.spdx.json
syft nginx:latest -o cyclonedx-json > sbom.cyclonedx.json

# Generate SBOM for a directory
syft dir:. -o cyclonedx-json > sbom.json

# Generate SBOM for a Go project
syft . -o cyclonedx-json > sbom.json
```

```bash
# Grype — vulnerability scanner that uses Syft SBOMs as input
# Install
curl -sSfL https://raw.githubusercontent.com/anchore/grype/main/install.sh | sh

# Scan image
grype nginx:latest

# Scan SBOM
grype sbom:./sbom.cyclonedx.json

# Fail if severity >= high
grype nginx:latest --fail-on high

# JSON output
grype nginx:latest -o json > grype-results.json
```

### Attaching SBOMs to Container Images

```bash
# Using cosign (signing + attestation)
# Generate SBOM
syft nginx:latest -o cyclonedx-json > sbom.json

# Attach SBOM as attestation to image
cosign attest \
  --predicate sbom.json \
  --type cyclonedx \
  registry.example.com/myapp:v1.0.0

# Verify SBOM attestation
cosign verify-attestation \
  --type cyclonedx \
  registry.example.com/myapp:v1.0.0
```

## Dependency Management Best Practices

### Pin Your Versions

```
# Bad — allows any minor/patch version, surprises possible
requests>=2.0.0

# Good — exact version pinned
requests==2.31.0
```

```json
// package.json — bad (caret allows minor bumps)
"dependencies": {
  "express": "^4.18.2"
}

// Good — use package-lock.json and commit it
// package-lock.json locks the entire tree
```

### Lock Files — Always Commit Them

| Ecosystem | Lock file | Commit it? |
|-----------|-----------|-----------|
| npm | `package-lock.json` | Yes |
| Yarn | `yarn.lock` | Yes |
| Python pip | `requirements.txt` (pinned) or `poetry.lock` | Yes |
| Go | `go.sum` | Yes |
| Ruby | `Gemfile.lock` | Yes |
| Rust | `Cargo.lock` | Yes (for apps), optional for libs |

### Dependency Update Strategies

**Renovate Bot / Dependabot** — automated PRs for dependency updates:

```yaml
# .github/dependabot.yml
version: 2
updates:
  - package-ecosystem: "npm"
    directory: "/"
    schedule:
      interval: "weekly"
    groups:
      dev-dependencies:
        dependency-type: "development"

  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
```

```json
// renovate.json — more control
{
  "extends": ["config:base"],
  "vulnerabilityAlerts": {
    "enabled": true,
    "labels": ["security"]
  },
  "packageRules": [
    {
      "matchUpdateTypes": ["patch"],
      "automerge": true
    }
  ]
}
```

## Private Package Registries

Using a private/proxied registry adds a layer of protection against supply-chain attacks.

```
Developer → Private Registry (Nexus/Artifactory/JFrog) → Public Registry (npmjs, PyPI)
                    ↑
          Scans packages before caching
          Blocks packages with critical CVEs
          Provides audit log of all downloads
```

Configure npm to use a private registry:
```bash
# .npmrc
registry=https://nexus.company.com/repository/npm-proxy/
//nexus.company.com/repository/npm-proxy/:_authToken=${NPM_TOKEN}
```

Configure pip:
```bash
# pip.conf
[global]
index-url = https://nexus.company.com/repository/pypi-proxy/simple/
trusted-host = nexus.company.com
```

## CI/CD Integration Pattern

Complete SCA stage in a CI pipeline:

```yaml
# GitLab CI — SCA stage
dependency-scan:
  stage: security
  image: aquasec/trivy:latest
  script:
    # Scan filesystem for dependency vulnerabilities
    - trivy fs --exit-code 0 --no-progress --format json -o trivy-fs.json .
    
    # Fail on critical findings
    - trivy fs --exit-code 1 --no-progress --severity CRITICAL .
    
    # Generate SBOM
    - trivy fs --format cyclonedx --output sbom.json .
  artifacts:
    when: always
    paths:
      - trivy-fs.json
      - sbom.json
    reports:
      # GitLab native SBOM report
      cyclonedx: sbom.json
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == "main"'
```

## Real-World Incidents — Why SCA Matters

**Log4Shell (CVE-2021-44228)** — December 2021
- Log4j 2.x JNDI injection — remote code execution with CVSS 10.0
- Affected thousands of applications using Java
- Companies with SBOMs could identify exposure in hours; others took weeks
- Lesson: know what's in your software before an incident

**XZ Utils (CVE-2024-3094)** — March 2024
- Malicious backdoor inserted by a compromised maintainer over 2 years
- Affected xz 5.6.0 and 5.6.1 — in Linux distributions
- Caught by accident (performance anomaly in SSH)
- Lesson: supply chain attacks are patient and sophisticated

**event-stream (2018)**
- Popular npm package with 2M downloads/week
- New malicious maintainer added code to steal Bitcoin wallets
- Lesson: even tiny transitive dependencies matter

## Key Metrics to Track

| Metric | What it measures |
|--------|-----------------|
| Mean Time to Remediate (MTTR) critical CVEs | How fast you patch high-severity vulns |
| % of critical CVEs remediated within SLA | Compliance with your own security policy |
| Number of known CVEs in production | Current risk exposure |
| SBOM coverage | % of services with up-to-date SBOMs |
| Dependency freshness | How outdated your dependencies are on average |
