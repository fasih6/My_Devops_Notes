# Secure CI/CD Pipeline Integration

## The Secure Pipeline Concept

A secure pipeline doesn't just build and deploy — it acts as an automated security gate. Every stage enforces controls, and the pipeline **fails fast** when security issues are found.

```
┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐
│  Commit  │  │  Build   │  │  Scan    │  │  Deploy  │  │ Operate  │
│          │  │          │  │          │  │          │  │          │
│ Secrets  │→ │ SBOM gen │→ │ SAST     │→ │ Sign     │→ │ Falco    │
│ detect   │  │ Image    │  │ SCA      │  │ Policy   │  │ Audit    │
│ Lint IaC │  │ build    │  │ Trivy    │  │ gate     │  │ SIEM     │
│ Pre-hook │  │          │  │ DAST     │  │          │  │          │
└──────────┘  └──────────┘  └──────────┘  └──────────┘  └──────────┘
        FAIL FAST ←──────────────────────────────────────
```

## GitLab CI — Full Secure Pipeline

```yaml
# .gitlab-ci.yml — comprehensive secure pipeline

stages:
  - pre-check
  - build
  - security-scan
  - sign-and-attest
  - deploy-staging
  - dast
  - deploy-production

variables:
  DOCKER_DRIVER: overlay2
  IMAGE_TAG: ${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}
  TRIVY_CACHE_DIR: ".trivycache/"

# ─── PRE-CHECK STAGE ───────────────────────────────────────────────

secret-detection:
  stage: pre-check
  include:
    - template: Security/Secret-Detection.gitlab-ci.yml
  variables:
    SECRET_DETECTION_HISTORIC_SCAN: "false"  # only scan new changes in MR

gitleaks:
  stage: pre-check
  image: zricethezav/gitleaks:latest
  script:
    - gitleaks detect --source . --log-opts "-n 50" --exit-code 1

lint-iac:
  stage: pre-check
  image: bridgecrew/checkov:latest
  script:
    - checkov -d . --framework terraform,kubernetes,helm --soft-fail
  artifacts:
    when: always
    reports:
      sast: results.sarif

# ─── BUILD STAGE ───────────────────────────────────────────────────

build-image:
  stage: build
  image: docker:24
  services:
    - docker:24-dind
  script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    - docker build
        --label "org.opencontainers.image.source=${CI_PROJECT_URL}"
        --label "org.opencontainers.image.revision=${CI_COMMIT_SHA}"
        -t ${IMAGE_TAG}
        .
    - docker push ${IMAGE_TAG}

# ─── SECURITY SCAN STAGE ───────────────────────────────────────────

sast:
  stage: security-scan
  include:
    - template: Security/SAST.gitlab-ci.yml

dependency-scan:
  stage: security-scan
  image: aquasec/trivy:latest
  script:
    # Scan filesystem for dependency vulnerabilities
    - trivy fs
        --exit-code 0        # don't fail on this run — report only
        --format json
        --output trivy-fs.json
        .
    # Fail on critical findings
    - trivy fs
        --exit-code 1
        --severity CRITICAL
        --no-progress
        .
  cache:
    paths:
      - .trivycache/
  artifacts:
    when: always
    paths:
      - trivy-fs.json

container-scan:
  stage: security-scan
  image: aquasec/trivy:latest
  script:
    # Scan the built image
    - trivy image
        --exit-code 0
        --format json
        --output trivy-image.json
        ${IMAGE_TAG}
    # Fail on critical
    - trivy image
        --exit-code 1
        --severity CRITICAL
        --no-progress
        --ignore-unfixed
        ${IMAGE_TAG}
    # Generate SBOM
    - trivy image
        --format cyclonedx
        --output sbom.json
        ${IMAGE_TAG}
  cache:
    paths:
      - .trivycache/
  artifacts:
    when: always
    paths:
      - trivy-image.json
      - sbom.json
    reports:
      cyclonedx: sbom.json

# ─── SIGN & ATTEST ─────────────────────────────────────────────────

sign-image:
  stage: sign-and-attest
  image: cgr.dev/chainguard/cosign:latest
  script:
    # Keyless signing using GitLab OIDC
    - cosign sign --yes ${IMAGE_TAG}

    # Attach SBOM as attestation
    - cosign attest
        --yes
        --predicate sbom.json
        --type cyclonedx
        ${IMAGE_TAG}
  id_tokens:
    SIGSTORE_ID_TOKEN:
      aud: sigstore
  needs:
    - container-scan
  only:
    - main

# ─── DEPLOY STAGING ────────────────────────────────────────────────

deploy-staging:
  stage: deploy-staging
  environment:
    name: staging
    url: https://staging.myapp.example.com
  script:
    - helm upgrade --install myapp ./charts/myapp
        --namespace staging
        --set image.tag=${CI_COMMIT_SHA}
        --set image.repository=${CI_REGISTRY_IMAGE}
        --wait
  needs:
    - sign-image
  only:
    - main

# ─── DAST ──────────────────────────────────────────────────────────

dast-baseline:
  stage: dast
  image: ghcr.io/zaproxy/zaproxy:stable
  script:
    - zap-baseline.py
        -t https://staging.myapp.example.com
        -r zap-report.html
        -J zap-report.json
        -I
  artifacts:
    when: always
    paths:
      - zap-report.html
      - zap-report.json
  needs:
    - deploy-staging
  only:
    - main

# ─── DEPLOY PRODUCTION ─────────────────────────────────────────────

deploy-production:
  stage: deploy-production
  environment:
    name: production
    url: https://myapp.example.com
  script:
    - helm upgrade --install myapp ./charts/myapp
        --namespace production
        --set image.tag=${CI_COMMIT_SHA}
        --set image.repository=${CI_REGISTRY_IMAGE}
        --wait
  when: manual            # require manual approval for production
  needs:
    - dast-baseline
  only:
    - main
```

## Security Gates — When to Block

Defining clear pass/fail thresholds is key to a useful security pipeline:

```yaml
# Recommended gate thresholds
gates:
  secret-detection:
    any-finding: FAIL        # zero tolerance for secrets

  sast:
    critical: FAIL
    high: FAIL
    medium: WARN             # report, don't block
    low: INFO

  container-scan:
    critical: FAIL
    high: FAIL (if fix available)
    high: WARN (if no fix available — unfixed)
    medium: WARN

  sca-dependencies:
    critical: FAIL
    high: FAIL
    medium: WARN

  dast:
    high: FAIL
    medium: WARN

  image-signing:
    unsigned: FAIL           # only signed images go to production
```

## Jenkins — Secure Pipeline

```groovy
// Jenkinsfile — secure pipeline

pipeline {
    agent { label 'docker' }

    environment {
        IMAGE_TAG = "${env.DOCKER_REGISTRY}/${env.JOB_NAME}:${env.GIT_COMMIT}"
        SNYK_TOKEN = credentials('snyk-token')
        SONAR_TOKEN = credentials('sonar-token')
    }

    stages {
        stage('Secret Detection') {
            steps {
                sh 'gitleaks detect --source . --log-opts "-n 30" --exit-code 1'
            }
        }

        stage('SAST') {
            steps {
                sh """
                    semgrep --config=auto --json > semgrep-results.json || true
                    # Fail on ERROR severity
                    ERRORS=\$(cat semgrep-results.json | jq '[.results[] | select(.extra.severity=="ERROR")] | length')
                    [ "\$ERRORS" -gt 0 ] && exit 1 || true
                """
            }
            post {
                always {
                    archiveArtifacts 'semgrep-results.json'
                }
            }
        }

        stage('SCA') {
            steps {
                sh """
                    snyk test --severity-threshold=high --json > snyk-results.json || true
                    snyk monitor
                """
            }
        }

        stage('Build Image') {
            steps {
                sh "docker build -t ${IMAGE_TAG} ."
                sh "docker push ${IMAGE_TAG}"
            }
        }

        stage('Container Scan') {
            steps {
                sh """
                    # Report only — full results
                    trivy image --format json --output trivy-results.json ${IMAGE_TAG}

                    # Gate — fail on critical
                    trivy image --exit-code 1 --severity CRITICAL ${IMAGE_TAG}

                    # Generate SBOM
                    trivy image --format cyclonedx --output sbom.json ${IMAGE_TAG}
                """
            }
            post {
                always {
                    archiveArtifacts 'trivy-results.json, sbom.json'
                }
            }
        }

        stage('Sign Image') {
            when { branch 'main' }
            steps {
                withCredentials([file(credentialsId: 'cosign-key', variable: 'COSIGN_KEY')]) {
                    sh "cosign sign --key ${COSIGN_KEY} ${IMAGE_TAG}"
                }
            }
        }

        stage('Deploy Staging') {
            when { branch 'main' }
            steps {
                sh """
                    helm upgrade --install myapp ./charts/myapp \
                        --namespace staging \
                        --set image.tag=${env.GIT_COMMIT}
                """
            }
        }

        stage('DAST') {
            when { branch 'main' }
            steps {
                sh """
                    docker run --rm \
                        -v \$(pwd):/zap/wrk/:rw \
                        ghcr.io/zaproxy/zaproxy:stable \
                        zap-baseline.py \
                        -t https://staging.myapp.example.com \
                        -r zap-report.html \
                        -J zap-report.json \
                        -I
                """
            }
            post {
                always {
                    publishHTML([
                        allowMissing: false,
                        reportDir: '.',
                        reportFiles: 'zap-report.html',
                        reportName: 'DAST Report'
                    ])
                }
            }
        }

        stage('Deploy Production') {
            when { branch 'main' }
            input {
                message "Deploy to production?"
                ok "Deploy"
                submitter "ops-team"
            }
            steps {
                sh """
                    helm upgrade --install myapp ./charts/myapp \
                        --namespace production \
                        --set image.tag=${env.GIT_COMMIT}
                """
            }
        }
    }

    post {
        failure {
            slackSend(
                channel: '#security-alerts',
                color: 'danger',
                message: "Security gate failed: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
            )
        }
    }
}
```

## Signed Commits and Branch Protection

```bash
# Configure Git commit signing with GPG
gpg --gen-key
git config --global user.signingkey <YOUR_GPG_KEY_ID>
git config --global commit.gpgsign true

# Sign a commit
git commit -S -m "feat: add login endpoint"

# Verify a signed commit
git log --show-signature -1
```

GitLab branch protection (via API or UI):
```yaml
# GitLab CI push rules (project settings)
# Enable:
# - Reject unsigned commits
# - Check whether the commit author is a GitLab user
# - Prevent secrets (built-in detection)
```

## Supply Chain Security — Provenance

```yaml
# Generate build provenance attestation with cosign
# SLSA (Supply-chain Levels for Software Artifacts) Level 2

generate-provenance:
  stage: sign-and-attest
  image: cgr.dev/chainguard/cosign:latest
  script:
    # Create SLSA provenance predicate
    - |
      cat > provenance.json << EOF
      {
        "buildType": "https://gitlab.com/pipeline",
        "builder": {
          "id": "${CI_SERVER_URL}/pipelines/${CI_PIPELINE_ID}"
        },
        "invocation": {
          "configSource": {
            "uri": "${CI_PROJECT_URL}",
            "digest": {"sha1": "${CI_COMMIT_SHA}"}
          }
        },
        "materials": [
          {
            "uri": "${CI_PROJECT_URL}",
            "digest": {"sha1": "${CI_COMMIT_SHA}"}
          }
        ]
      }
      EOF

    # Attach as attestation
    - cosign attest
        --yes
        --predicate provenance.json
        --type slsaprovenance
        ${IMAGE_TAG}
  id_tokens:
    SIGSTORE_ID_TOKEN:
      aud: sigstore
```

## Pipeline Security Best Practices

**Credentials and secrets:**
- Never print variables or secrets in pipeline logs (`set +x` before sensitive commands)
- Use masked/protected CI variables for secrets
- Integrate with Vault for short-lived credentials
- Rotate pipeline tokens regularly

**Pipeline hardening:**
- Pin tool versions (`aquasec/trivy:0.48.0` not `aquasec/trivy:latest`)
- Verify checksums of downloaded tools
- Run builds in isolated, ephemeral environments
- Separate pipelines for build, test, deploy with minimal permissions each

**Artifact security:**
- Sign all images before push to production
- Scan images at pull time (not just build time)
- Enforce image signing in Kubernetes with Kyverno
- Retain SBOMs alongside deployed versions

**Access control:**
- Principle of least privilege for CI/CD service accounts
- Use workload identity (IRSA, Azure Workload Identity) not static keys
- Separate credentials per environment (staging vs production)
- Require MFA for pipeline configuration changes

**Monitoring the pipeline itself:**
- Audit pipeline configuration changes
- Alert on unexpected pipeline failures (could indicate tampering)
- Log all deployments with user, timestamp, image digest
