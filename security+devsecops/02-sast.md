# SAST — Static Application Security Testing

## What Is SAST?

SAST analyses source code, bytecode, or binaries **without executing the application**. It finds security issues at the code level by scanning for vulnerable patterns.

```
Developer pushes code
        ↓
SAST tool scans source files
        ↓
Reports: file, line, severity, description
        ↓
Developer fixes before merge (shift-left)
```

**Strengths:**
- Runs before deployment — catches issues early
- Full code coverage (every code path, not just exercised ones)
- No running environment needed

**Limitations:**
- High false positive rate (code may look vulnerable but context makes it safe)
- Cannot find runtime/configuration issues
- Language-specific (a Python tool won't scan Go)

## Key SAST Tools

### Semgrep

Open-source, fast, highly customisable. Uses rule patterns written in YAML.

```yaml
# Example Semgrep rule: detect hardcoded AWS keys
rules:
  - id: hardcoded-aws-key
    patterns:
      - pattern: |
          $X = "AKIA..."
    message: Possible hardcoded AWS access key found in $X
    languages: [python, javascript, go, java]
    severity: ERROR
    metadata:
      category: security
      cwe: CWE-798
```

Run Semgrep:
```bash
# Scan with community rules
semgrep --config=auto .

# Scan with specific ruleset
semgrep --config=p/owasp-top-ten .

# Scan only Python files
semgrep --config=p/python .

# Output as JSON for CI integration
semgrep --config=auto --json > semgrep-results.json

# Run as CI check (exit 1 if findings)
semgrep --config=auto --error .
```

Semgrep rule categories:
- `p/owasp-top-ten` — OWASP Top 10 coverage
- `p/secrets` — hardcoded secrets detection
- `p/docker` — Dockerfile security
- `p/terraform` — IaC security
- `p/golang`, `p/python`, `p/java` — language-specific

### SonarQube / SonarCloud

Enterprise-grade code quality + security platform. Provides a web dashboard, trend tracking, quality gates.

Key concepts:
- **Quality Gate** — a pass/fail threshold applied to every scan (e.g. no Critical vulns, coverage > 80%)
- **Issues** — bugs, vulnerabilities, code smells
- **Security Hotspots** — code that needs human review (not automatically a vulnerability)
- **Technical Debt** — time estimate to fix all issues

```yaml
# GitLab CI integration with SonarQube
sonarqube-check:
  image: sonarsource/sonar-scanner-cli:latest
  stage: test
  variables:
    SONAR_USER_HOME: "${CI_PROJECT_DIR}/.sonar"
    GIT_DEPTH: "0"
  script:
    - sonar-scanner
      -Dsonar.projectKey=${CI_PROJECT_NAME}
      -Dsonar.sources=.
      -Dsonar.host.url=${SONAR_HOST_URL}
      -Dsonar.login=${SONAR_TOKEN}
      -Dsonar.qualitygate.wait=true  # fail pipeline if gate fails
  allow_failure: false
  only:
    - merge_requests
    - main
```

### Bandit (Python-specific)

Purpose-built Python SAST tool from PyCQA.

```bash
# Basic scan
bandit -r ./src

# Scan with specific severity threshold
bandit -r ./src -l  # low severity and above
bandit -r ./src -ll # medium and above
bandit -r ./src -lll # high only

# JSON output
bandit -r ./src -f json -o bandit-report.json

# Exclude test files
bandit -r ./src --exclude ./src/tests
```

Common Bandit findings:
- `B106` — hardcoded password
- `B201` — Flask debug mode enabled
- `B303` — MD5/SHA1 (weak hash)
- `B501` — SSL verify disabled
- `B608` — SQL injection via string concatenation

### Other Tools by Language

| Language | Tool | Notes |
|----------|------|-------|
| Java | SpotBugs + Find Security Bugs | Plugin-based |
| JavaScript/TypeScript | ESLint + security plugins | `eslint-plugin-security` |
| Go | gosec | Built for Go |
| PHP | PHPCS + Security audit | |
| .NET/C# | Security Code Scan | Free, Visual Studio plugin |
| Ruby | Brakeman | Rails-focused |
| Universal | CodeQL (GitHub) | Powerful, query-based |

## Integrating SAST in GitLab CI

```yaml
# .gitlab-ci.yml — SAST integration

stages:
  - test
  - sast

# GitLab built-in SAST (uses multiple tools based on language detection)
include:
  - template: Security/SAST.gitlab-ci.yml

# GitLab SAST variables
variables:
  SAST_EXCLUDED_PATHS: "spec,test,tests,tmp"
  SAST_EXCLUDED_ANALYZERS: ""  # exclude specific analyzers
  SAST_SEVERITY_LEVEL: "medium"  # only report medium+ severity

# Custom Semgrep job
semgrep:
  stage: sast
  image: returntocorp/semgrep:latest
  script:
    - semgrep ci --config=auto
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
```

## Integrating SAST in Jenkins

```groovy
// Jenkinsfile — SAST stage

pipeline {
    agent any
    stages {
        stage('SAST Scan') {
            steps {
                // Run Semgrep
                sh 'semgrep --config=auto --json > semgrep-results.json || true'

                // Publish results
                publishHTML(target: [
                    reportDir: '.',
                    reportFiles: 'semgrep-results.json',
                    reportName: 'Semgrep SAST Report'
                ])

                // Fail on high severity findings
                sh '''
                    CRITICAL=$(cat semgrep-results.json | jq '[.results[] | select(.extra.severity=="ERROR")] | length')
                    if [ "$CRITICAL" -gt "0" ]; then
                        echo "Found $CRITICAL critical findings — failing pipeline"
                        exit 1
                    fi
                '''
            }
        }
    }
}
```

## Quality Gates and Thresholds

The key question: **when should a SAST finding fail the build?**

Common approach:

```
CRITICAL / HIGH (CVSS 7+)  →  Fail the pipeline (block merge)
MEDIUM (CVSS 4-6.9)        →  Warn, require security team review
LOW (CVSS 0-3.9)           →  Report only, do not block
INFORMATIONAL              →  Log to dashboard only
```

Practical tips for reducing noise:
- Use `.semgrepignore` / `.sonarignore` to exclude test files and generated code
- Mark false positives with inline comments (`# nosec` for Bandit, `// NOSONAR` for Sonar)
- Track findings in a SAST findings backlog — don't expect zero findings on day one
- Set baselines — fail only on **new** findings introduced in the current MR

## False Positives — Handling Them

SAST tools generate false positives. A 20-30% false positive rate is normal.

Suppression examples:
```python
# Python — suppress Bandit finding on a specific line
import subprocess
result = subprocess.run(cmd, shell=True)  # nosec B602

# Multiple suppression
result = subprocess.run(cmd, shell=True)  # nosec B602, B603
```

```java
// Java — suppress SonarQube finding
@SuppressWarnings("java:S2245")  // suppress specific rule
public void someMethod() { ... }
```

```yaml
# Semgrep — project-level ignore file
# .semgrepignore
tests/
vendor/
node_modules/
**/*.min.js
```

## SAST in the Development Workflow

```
IDE Plugin (real-time)      Pre-commit Hook         CI Pipeline
       ↓                           ↓                      ↓
Developer sees issue      Blocks commit if        Blocks merge if
as they type              critical issue found    quality gate fails
(SonarLint, Semgrep)      (pre-commit + Semgrep)  (SonarQube gate)
```

**IDE plugins** to recommend to developers:
- SonarLint (VS Code, IntelliJ) — same rules as SonarQube, real-time
- Semgrep for VS Code
- Snyk (also does secrets and SCA)

**Pre-commit hook setup:**
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/returntocorp/semgrep
    rev: v1.45.0
    hooks:
      - id: semgrep
        args: ['--config=auto', '--error']
```

## SAST vs Other Scanning Types

| Type | When | What it finds | Example tools |
|------|------|---------------|---------------|
| SAST | Code written | Source code vulnerabilities | Semgrep, SonarQube |
| SCA | Build time | Vulnerable dependencies | Snyk, OWASP Dep-Check |
| Secret scanning | Commit time | Hardcoded secrets | git-secrets, truffleHog |
| DAST | Runtime | Live app vulnerabilities | OWASP ZAP, Burp Suite |
| IAST | Runtime | Code + runtime combined | Contrast Security |
| Container scanning | Image build | CVEs in image layers | Trivy, Grype |
