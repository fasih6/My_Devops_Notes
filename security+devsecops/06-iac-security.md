# IaC Security — Infrastructure as Code Scanning

## Why IaC Security Matters

Infrastructure as Code means your cloud configurations — VPCs, S3 buckets, IAM roles, Kubernetes manifests — are defined in files. Misconfigurations in those files create real security vulnerabilities:
- S3 bucket with public read access → data breach
- Security group with `0.0.0.0/0` on all ports → full exposure
- K8s pod running as root with host mounts → container escape

IaC security scans these files **before** they reach production.

## Checkov — Terraform, CloudFormation, K8s, Helm

Most popular open-source IaC scanner. Supports 1000+ checks.

```bash
# Install
pip install checkov

# Scan a Terraform directory
checkov -d ./terraform

# Scan a specific file
checkov -f main.tf

# Scan Kubernetes manifests
checkov -d ./k8s/manifests

# Scan Helm charts
checkov -d ./charts/myapp --framework helm

# Scan Dockerfile
checkov -f Dockerfile

# Scan ARM templates (Azure)
checkov -d . --framework arm

# Output formats
checkov -d . --output cli          # default human-readable
checkov -d . --output json         # JSON
checkov -d . --output sarif        # SARIF (for GitLab/GitHub security reports)

# Only check specific frameworks
checkov -d . --framework terraform,kubernetes

# Fail on specific severity
checkov -d . --check HIGH          # only run HIGH severity checks
checkov -d . --soft-fail           # report but exit 0 (don't fail pipeline)

# Skip specific checks
checkov -d . --skip-check CKV_AWS_18,CKV_AWS_21
```

Common Checkov findings:

```hcl
# CKV_AWS_18 — S3 bucket without access logging
resource "aws_s3_bucket" "data" {
  bucket = "my-data-bucket"
  # Missing: aws_s3_bucket_logging
}

# CKV_AWS_21 — S3 bucket versioning not enabled
resource "aws_s3_bucket" "data" {
  bucket = "my-data-bucket"
  # Missing: aws_s3_bucket_versioning with enabled = true
}

# CKV_AWS_23 — Security group allows all traffic from 0.0.0.0/0
resource "aws_security_group_rule" "bad" {
  type        = "ingress"
  from_port   = 0
  to_port     = 65535
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]  # violation
}
```

Checkov inline suppression:
```hcl
resource "aws_security_group_rule" "internal_only" {
  #checkov:skip=CKV_AWS_23: This is an internal VPN-only security group
  type        = "ingress"
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = ["10.0.0.0/8"]
}
```

## tfsec — Terraform-Focused

```bash
# Install
brew install tfsec

# Scan Terraform
tfsec .

# Include passed checks in output
tfsec . --include-passed

# Soft fail (don't exit 1)
tfsec . --soft-fail

# Ignore specific checks
tfsec . --exclude aws-s3-enable-bucket-logging

# SARIF output
tfsec . --format sarif --out tfsec-results.sarif

# Config file
tfsec --config-file tfsec.yml .
```

`tfsec.yml` config:
```yaml
minimum_severity: MEDIUM
exclude:
  - aws-s3-enable-bucket-logging  # accepted risk, reason documented
```

## Terraform-native: terraform validate & plan scanning

```bash
# Syntax validation (built-in)
terraform validate

# Plan and scan the plan file
terraform plan -out=tfplan
terraform show -json tfplan > tfplan.json

# Scan the plan (not just source)
checkov --file tfplan.json --file-type json

# Infracost — cost estimation in CI (not security but useful)
infracost breakdown --path . --format json > infracost.json
```

## OPA — Open Policy Agent

OPA is a general-purpose policy engine. You write policies in **Rego** (OPA's policy language) and enforce them across Terraform, Kubernetes, APIs, and more.

```
OPA Architecture:
Query (input JSON) → OPA + Policy (Rego) → Decision (allow/deny)
```

### Rego Basics

```rego
# policies/deny_public_s3.rego
package main

# Deny S3 buckets with public ACL
deny[msg] {
  resource := input.resource.aws_s3_bucket[name]
  resource.acl == "public-read"
  msg := sprintf("S3 bucket '%s' must not be public-read", [name])
}

# Deny missing encryption
deny[msg] {
  resource := input.resource.aws_s3_bucket[name]
  not resource.server_side_encryption_configuration
  msg := sprintf("S3 bucket '%s' must have encryption enabled", [name])
}
```

### Conftest — OPA for IaC Files

Conftest runs OPA policies against structured config files (Terraform, K8s YAML, Helm, Dockerfiles).

```bash
# Install
brew install conftest

# Test Terraform plan against policies
terraform plan -out=tfplan
terraform show -json tfplan | conftest test -

# Test Kubernetes manifests
conftest test deploy.yaml --policy ./policies/

# Test Helm chart output
helm template myapp ./charts/myapp | conftest test -

# Test Dockerfile
conftest test Dockerfile --policy ./policies/

# Multiple policy directories
conftest test deploy.yaml --policy ./policies/k8s --policy ./policies/shared
```

Policy for Kubernetes (Conftest):
```rego
# policies/k8s.rego
package main

deny[msg] {
  input.kind == "Pod"
  container := input.spec.containers[_]
  not container.securityContext.runAsNonRoot
  msg := sprintf("Container '%s' must set runAsNonRoot: true", [container.name])
}

deny[msg] {
  input.kind == "Deployment"
  not input.spec.template.spec.securityContext.runAsNonRoot
  msg := "Deployment pods must run as non-root"
}

warn[msg] {
  input.kind == "Deployment"
  container := input.spec.template.spec.containers[_]
  not container.resources.limits
  msg := sprintf("Container '%s' has no resource limits set", [container.name])
}
```

## Kyverno — Kubernetes-Native Policy

Kyverno uses YAML (not Rego) for Kubernetes policies. Much easier for K8s engineers.

```yaml
# Require non-root containers
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-run-as-non-root
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-runAsNonRoot
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Containers must run as non-root"
      pattern:
        spec:
          =(initContainers):
          - =(securityContext):
              =(runAsNonRoot): "true"
          containers:
          - securityContext:
              runAsNonRoot: true

---
# Require resource limits
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: require-resource-limits
spec:
  validationFailureAction: Enforce
  rules:
  - name: validate-resources
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Resource limits are required"
      pattern:
        spec:
          containers:
          - resources:
              limits:
                memory: "?*"
                cpu: "?*"

---
# Disallow privileged containers
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-privileged
spec:
  validationFailureAction: Enforce
  rules:
  - name: check-privileged
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "Privileged containers are not allowed"
      pattern:
        spec:
          =(initContainers):
          - =(securityContext):
              =(privileged): "false"
          containers:
          - =(securityContext):
              =(privileged): "false"

---
# Mutating policy — automatically add labels
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: add-labels
spec:
  rules:
  - name: add-team-label
    match:
      any:
      - resources:
          kinds: [Pod]
    mutate:
      patchStrategicMerge:
        metadata:
          labels:
            +(managed-by): kyverno
```

## IaC Security in CI/CD

```yaml
# GitLab CI — complete IaC security pipeline

stages:
  - validate
  - security
  - plan
  - apply

terraform-validate:
  stage: validate
  image: hashicorp/terraform:latest
  script:
    - terraform init -backend=false
    - terraform validate
    - terraform fmt -check -recursive

checkov-scan:
  stage: security
  image: bridgecrew/checkov:latest
  script:
    - checkov -d . --framework terraform --output cli --output sarif --output-file-path .
  artifacts:
    when: always
    reports:
      sast: results.sarif
    paths:
      - results.sarif

tfsec-scan:
  stage: security
  image: aquasec/tfsec:latest
  script:
    - tfsec . --format sarif --out tfsec.sarif --soft-fail
  artifacts:
    when: always
    paths:
      - tfsec.sarif

conftest-k8s:
  stage: security
  image: openpolicyagent/conftest:latest
  script:
    - conftest test ./k8s/ --policy ./policies/
  rules:
    - changes:
        - k8s/**/*
        - policies/**/*

terraform-plan:
  stage: plan
  image: hashicorp/terraform:latest
  script:
    - terraform init
    - terraform plan -out=tfplan
    - terraform show -json tfplan > tfplan.json
    
    # Scan the plan file too (catches dynamic resource issues)
    - checkov --file tfplan.json --file-type json
  artifacts:
    paths:
      - tfplan
```

## Helm Chart Security Scanning

```bash
# Checkov scans Helm charts
checkov -d ./charts/myapp --framework helm

# helm template + conftest
helm template myapp ./charts/myapp -f values.yaml | conftest test -

# datree — Helm chart policy enforcement
helm datree test ./charts/myapp

# Kubesec — security risk scores for K8s YAML
# Scan a manifest
curl -sSX POST \
  --data-binary @deployment.yaml \
  https://v2.kubesec.io/scan

# Or local binary
kubesec scan deployment.yaml
```

## Azure-Specific IaC Security

```bash
# tfsec has Azure-specific checks
tfsec . --include-only azure

# Key Azure checks:
# - azure-storage-default-action-deny
# - azure-network-no-public-ingress
# - azure-keyvault-ensure-secret-expiry
# - azure-database-enable-audit
# - azure-container-configured-to-use-rbac
```

ARM template scanning with Checkov:
```bash
checkov -d . --framework arm
```

Bicep — convert to ARM then scan:
```bash
az bicep build --file main.bicep --outfile main.json
checkov -f main.json --file-type json
```
