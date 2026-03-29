# 🛡️ Security & Compliance

SAST, DAST, dependency scanning, secrets detection, and compliance frameworks in GitLab.

---

## 📚 Table of Contents

- [1. GitLab Security Overview](#1-gitlab-security-overview)
- [2. SAST — Static Application Security Testing](#2-sast--static-application-security-testing)
- [3. Secret Detection](#3-secret-detection)
- [4. Dependency Scanning](#4-dependency-scanning)
- [5. Container Scanning](#5-container-scanning)
- [6. DAST — Dynamic Application Security Testing](#6-dast--dynamic-application-security-testing)
- [7. License Compliance](#7-license-compliance)
- [8. Compliance Pipelines](#8-compliance-pipelines)
- [9. Security Dashboard & Policies](#9-security-dashboard--policies)
- [Cheatsheet](#cheatsheet)

---

## 1. GitLab Security Overview

GitLab has built-in security scanning — no external tools needed (though you can add them).

```
Security scanning types:
  SAST                → code vulnerabilities (SQLi, XSS, etc.)
  Secret Detection    → API keys, passwords in code
  Dependency Scanning → vulnerable libraries/packages
  Container Scanning  → CVEs in Docker images
  DAST                → running app vulnerabilities
  API Fuzzing         → API-level vulnerability testing
  Coverage-guided Fuzzing → unit-level fuzzing
  Infrastructure as Code → Terraform/Helm security issues
  License Compliance  → dependency license compliance
```

### Free vs paid scanning

```
Free (all plans):
  SAST — most analyzers
  Secret Detection
  
Paid (Ultimate):
  Full SAST with more rules
  Dependency Scanning
  Container Scanning
  DAST
  License Compliance
  Security Dashboard
  Vulnerability Management
  Compliance Frameworks
```

---

## 2. SAST — Static Application Security Testing

SAST analyzes source code without running it, looking for security vulnerabilities.

### Enable with template

```yaml
include:
  - template: Security/SAST.gitlab-ci.yml

# That's it! GitLab auto-detects your language and runs the right analyzer

# Language → Analyzer mapping:
# Python    → Semgrep, Bandit
# Go        → Gosec, Semgrep
# Java      → SpotBugs, Semgrep
# JS/TS     → NodeJsScan, Semgrep
# Ruby      → Brakeman
# C/C++     → Flawfinder
# PHP       → phpcs-security-audit
```

### Custom SAST configuration

```yaml
include:
  - template: Security/SAST.gitlab-ci.yml

variables:
  # Exclude paths from scanning
  SAST_EXCLUDED_PATHS: "tests/, vendor/, node_modules/"

  # Fail pipeline on vulnerabilities
  SAST_EXCLUDED_ANALYZERS: ""   # run all analyzers

  # Severity threshold
  SAST_SEVERITY_LEVEL: "High"   # Critical, High, Medium, Low, Info

  # Semgrep rules
  SEMGREP_RULES: "p/ci-owasp-top-ten"
```

### Custom Semgrep rules

```yaml
include:
  - template: Security/SAST.gitlab-ci.yml

semgrep-sast:
  variables:
    SEMGREP_RULES: >-
      p/owasp-top-ten
      p/python
      .semgrep/custom-rules.yml
```

```yaml
# .semgrep/custom-rules.yml
rules:
  - id: hardcoded-password
    pattern: |
      password = "..."
    message: "Hardcoded password detected"
    severity: ERROR
    languages: [python]
```

### SAST in MR — blocking vulnerabilities

```yaml
# Configure in GitLab:
# Settings → CI/CD → Security configuration:
#   MR approval required for: High, Critical vulnerabilities
#   Pipeline fails on: Critical vulnerabilities
```

---

## 3. Secret Detection

Scans your code history for accidentally committed secrets — API keys, tokens, passwords.

```yaml
include:
  - template: Security/Secret-Detection.gitlab-ci.yml
```

### What it detects

```
AWS access keys:    AKIA[0-9A-Z]{16}
GitLab tokens:      glpat-[a-zA-Z0-9_-]{20}
GitHub tokens:      gh[ps]_[a-zA-Z0-9]{36}
Private keys:       -----BEGIN (RSA|EC|DSA) PRIVATE KEY-----
JWT tokens:         eyJ[a-zA-Z0-9-_=]+\.[a-zA-Z0-9-_=]+\.?[a-zA-Z0-9-_.+/=]*
Database URLs:      postgresql://user:password@host
Slack webhooks:     https://hooks.slack.com/services/...
```

### Scanning git history

```yaml
include:
  - template: Security/Secret-Detection.gitlab-ci.yml

variables:
  SECRET_DETECTION_HISTORIC_SCAN: "true"  # scan full git history (not just latest commit)
```

### Handling false positives

```bash
# Add .gitleaks.toml to suppress false positives
[allowlist]
  description = "Test fixtures"
  regexes = [
    '''EXAMPLE_KEY_[A-Z0-9]+''',
  ]
  paths = [
    '''tests/fixtures/''',
  ]
```

---

## 4. Dependency Scanning

Scans your application dependencies for known vulnerabilities (CVEs).

```yaml
include:
  - template: Security/Dependency-Scanning.gitlab-ci.yml

variables:
  DS_EXCLUDED_PATHS: "tests/"
  DS_MAX_DEPTH: 2    # how deep to scan nested dependencies
```

### Language support

```
Python:   pip, pipenv, poetry
Node.js:  npm, yarn
Ruby:     bundler
Java:     Maven, Gradle
Go:       Go modules
PHP:      Composer
.NET:     NuGet
```

### Handling vulnerabilities

```yaml
# GitLab creates merge requests to update vulnerable dependencies
# Settings → Security and Compliance → Vulnerability Management

# You can also:
# 1. Dismiss a finding (if it's not exploitable in your context)
# 2. Create an issue to track remediation
# 3. Set a "Fix by" date
```

---

## 5. Container Scanning

Scans Docker images for OS-level vulnerabilities (CVEs in apt packages, etc.).

```yaml
include:
  - template: Security/Container-Scanning.gitlab-ci.yml

variables:
  CS_IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
  CS_SEVERITY_THRESHOLD: HIGH    # only report HIGH and CRITICAL
  CS_DOCKERFILE_PATH: Dockerfile
```

### Using Trivy directly (more control)

```yaml
trivy-scan:
  stage: scan
  image: aquasec/trivy:latest
  needs: [build-image]
  script:
    # Fail on CRITICAL vulnerabilities
    - trivy image --exit-code 1 --severity CRITICAL $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

    # Generate GitLab-compatible report
    - trivy image
        --format gitlab
        --output gl-container-scanning-report.json
        $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
  artifacts:
    reports:
      container_scanning: gl-container-scanning-report.json
```

---

## 6. DAST — Dynamic Application Security Testing

DAST tests a running application for vulnerabilities — actual HTTP requests against your app.

```yaml
include:
  - template: DAST.gitlab-ci.yml

variables:
  DAST_WEBSITE: "https://staging.example.com"
  DAST_BROWSER_SCAN: "true"           # use browser-based scanning
  DAST_FULL_SCAN_ENABLED: "false"     # passive scan only (less intrusive)
  DAST_AUTH_URL: "https://staging.example.com/login"
  DAST_USERNAME: $DAST_TEST_USER
  DAST_PASSWORD: $DAST_TEST_PASSWORD
  DAST_USERNAME_FIELD: "username"
  DAST_PASSWORD_FIELD: "password"
```

### DAST with Review Apps

```yaml
# Perfect pattern: deploy review app → DAST scan it → stop review app
dast:
  stage: dast
  needs: [deploy-review]
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    action: verify
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
```

### API security testing (DAST for APIs)

```yaml
include:
  - template: API-Security.gitlab-ci.yml

variables:
  APISEC_URL: "https://staging-api.example.com"
  APISEC_API_SPECIFICATION: "openapi.yaml"    # your OpenAPI/Swagger spec
```

---

## 7. License Compliance

Scans dependencies and checks their licenses against an allowlist/denylist.

```yaml
include:
  - template: Security/License-Scanning.gitlab-ci.yml

# GitLab → Security & Compliance → License Compliance:
# Allowed licenses: MIT, Apache-2.0, BSD-2-Clause, BSD-3-Clause
# Denied licenses: GPL-3.0, AGPL-3.0  (copyleft — may require open-sourcing your code)
```

---

## 8. Compliance Pipelines

Compliance frameworks enforce pipeline requirements across all projects in a group.

### Create a compliance pipeline

```yaml
# Compliance framework configuration (in a separate project)
# .gitlab/compliance/pipeline.yml

stages:
  - pre-compliance
  - test
  - security
  - post-compliance

# These jobs ALWAYS run — project's .gitlab-ci.yml can't remove them
compliance-check:
  stage: pre-compliance
  script:
    - echo "Compliance checks running for $CI_PROJECT_PATH"
    - ./scripts/check-branch-protection.sh
    - ./scripts/check-code-owners.sh
  allow_failure: false

sast:
  stage: security
  # Uses project's SAST configuration but enforces it runs
  image: registry.gitlab.com/security-products/semgrep:latest
  script:
    - semgrep --config=auto --json > gl-sast-report.json || true
  artifacts:
    reports:
      sast: gl-sast-report.json

secret-detection:
  stage: security
  image: registry.gitlab.com/security-products/secrets:latest
  script:
    - /analyzer run
  artifacts:
    reports:
      secret_detection: gl-secret-detection-report.json

audit-log:
  stage: post-compliance
  script:
    - |
      curl -X POST "$COMPLIANCE_WEBHOOK" \
        -H "Content-Type: application/json" \
        -d "{
          \"project\": \"$CI_PROJECT_PATH\",
          \"pipeline\": $CI_PIPELINE_ID,
          \"commit\": \"$CI_COMMIT_SHA\",
          \"user\": \"$GITLAB_USER_EMAIL\",
          \"status\": \"$CI_JOB_STATUS\"
        }"
  when: always
```

### Apply compliance framework

```
Admin → Compliance → Frameworks → Create framework
  Name: SOC2 Pipeline Compliance
  Pipeline configuration: .gitlab/compliance/pipeline.yml
  Project: mygroup/compliance-project

Group → Settings → General → Compliance frameworks
  Apply "SOC2 Pipeline Compliance" to all projects in group
```

---

## 9. Security Dashboard & Policies

### Security Dashboard

```
Project → Security & Compliance → Security Dashboard

Shows:
  - All vulnerabilities across scanning types
  - Severity distribution
  - Trends over time
  - Vulnerabilities introduced per MR
  - Status: detected, confirmed, dismissed, resolved
```

### Scan execution policies

```yaml
# .gitlab/security-policies/scan-policy.yml
scan_execution_policy:
  - name: "Required Security Scans"
    description: "SAST and secret detection must always run"
    enabled: true
    rules:
      - type: pipeline
        branches:
          - main
          - "release/*"
    actions:
      - scan: sast
      - scan: secret_detection
      - scan: container_scanning
        variables:
          CS_SEVERITY_THRESHOLD: HIGH
```

### Merge request approval policies

```yaml
# Require security team approval for HIGH/CRITICAL vulnerabilities
scan_result_policy:
  - name: "High Severity Approval"
    description: "Security team must approve HIGH+ vulnerabilities"
    enabled: true
    rules:
      - type: scan_finding
        scanners: [sast, secret_detection]
        vulnerabilities_allowed: 0
        severity_levels: [critical, high]
        vulnerability_states: [newly_detected]
    actions:
      - type: require_approval
        approvals_required: 1
        user_approvers_ids: [12345]  # security team lead ID
```

---

## Cheatsheet

```yaml
# Include security templates
include:
  - template: Security/SAST.gitlab-ci.yml
  - template: Security/Secret-Detection.gitlab-ci.yml
  - template: Security/Dependency-Scanning.gitlab-ci.yml
  - template: Security/Container-Scanning.gitlab-ci.yml
  - template: DAST.gitlab-ci.yml

# Container scanning with custom image
variables:
  CS_IMAGE: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

# DAST target
variables:
  DAST_WEBSITE: https://staging.example.com

# Trivy scan
trivy-scan:
  image: aquasec/trivy:latest
  script:
    - trivy image --exit-code 1 --severity CRITICAL $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
  artifacts:
    reports:
      container_scanning: gl-container-scanning-report.json

# SAST configuration
variables:
  SAST_EXCLUDED_PATHS: "tests/, vendor/"
  SAST_SEVERITY_LEVEL: High
```

---

*Next: [GitLab with Kubernetes →](./09-gitlab-kubernetes.md)*
