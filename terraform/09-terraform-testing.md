# 🧪 Testing & Validation

terraform validate, tflint, checkov, Terratest, and contract testing for Terraform.

---

## 📚 Table of Contents

- [1. Static Analysis](#1-static-analysis)
- [2. Security Scanning](#2-security-scanning)
- [3. Terraform Built-in Validation](#3-terraform-built-in-validation)
- [4. Terratest — Integration Testing](#4-terratest--integration-testing)
- [5. Terraform Test Framework (1.6+)](#5-terraform-test-framework-16)
- [6. Testing Strategy](#6-testing-strategy)
- [Cheatsheet](#cheatsheet)

---

## 1. Static Analysis

### terraform fmt

```bash
# Format all .tf files
terraform fmt

# Format recursively
terraform fmt -recursive

# Check without modifying (fails if changes needed — use in CI)
terraform fmt -check -recursive

# Show diff of formatting changes
terraform fmt -diff
```

### terraform validate

```bash
# Check syntax and internal consistency (no cloud API calls)
terraform validate

# Must run terraform init first (downloads providers)
terraform init && terraform validate
```

### tflint — linting beyond validate

```bash
# Install
brew install tflint

# Initialize (download plugins)
tflint --init

# Run
tflint
tflint --recursive    # all subdirectories

# Configuration
cat > .tflint.hcl << 'EOF'
plugin "aws" {
  enabled = true
  version = "0.27.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

rule "terraform_required_version" { enabled = true }
rule "terraform_required_providers" { enabled = true }
rule "terraform_naming_convention" { enabled = true }
rule "aws_instance_invalid_type" { enabled = true }
rule "aws_instance_previous_type" { enabled = true }
EOF
```

---

## 2. Security Scanning

### Trivy (most popular, all-in-one)

```bash
# Install
brew install aquasecurity/trivy/trivy

# Scan Terraform configuration
trivy config .
trivy config ./environments/production/

# Fail on CRITICAL severity
trivy config --severity CRITICAL --exit-code 1 .

# Output formats
trivy config --format json . > report.json
trivy config --format sarif . > results.sarif   # GitHub SARIF
```

### Checkov

```bash
# Install
pip install checkov

# Scan Terraform
checkov -d .
checkov -d ./environments/production/

# Scan specific files
checkov -f main.tf

# Output formats
checkov -d . --output json > report.json
checkov -d . --output sarif > results.sarif

# Skip specific checks
checkov -d . --skip-check CKV_AWS_18,CKV_AWS_86
```

### tfsec (now merged into Trivy)

```bash
# Still usable standalone
tfsec .
tfsec --severity HIGH .
tfsec --format json . > report.json
```

### Common security findings to fix

```hcl
# CKV_AWS_18 — S3 bucket logging not enabled
resource "aws_s3_bucket_logging" "app" {
  bucket        = aws_s3_bucket.app.id
  target_bucket = aws_s3_bucket.logs.id
  target_prefix = "s3-access-logs/"
}

# CKV_AWS_19 — S3 bucket not encrypted
resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# CKV_AWS_86 — S3 public access not blocked
resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CKV_AWS_79 — EC2 metadata service IMDSv2 not required
resource "aws_instance" "web" {
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"   # IMDSv2
    http_put_response_hop_limit = 1
  }
}
```

---

## 3. Terraform Built-in Validation

### Variable validation

```hcl
variable "environment" {
  type = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

### Preconditions and postconditions

```hcl
resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type

  lifecycle {
    # Checked before creating/updating
    precondition {
      condition     = var.environment != "production" || var.instance_type != "t2.micro"
      error_message = "t2.micro is too small for production."
    }

    # Checked after creating/updating
    postcondition {
      condition     = self.public_ip != ""
      error_message = "Instance did not receive a public IP."
    }
  }
}

# Data source postcondition
data "aws_ami" "app" {
  most_recent = true
  owners      = ["self"]

  lifecycle {
    postcondition {
      condition     = self.tags["Validated"] == "true"
      error_message = "AMI has not been validated. Only use validated AMIs."
    }
  }
}
```

---

## 4. Terratest — Integration Testing

Terratest is a Go library for testing Terraform code by actually deploying infrastructure.

```bash
# Install Go first: https://go.dev/doc/install

# Initialize Go module in your test directory
mkdir -p test && cd test
go mod init github.com/myorg/terraform-tests
go get github.com/gruntwork-io/terratest/modules/terraform
go get github.com/gruntwork-io/terratest/modules/aws
go get github.com/stretchr/testify/assert
```

### Basic VPC test

```go
// test/vpc_test.go
package test

import (
    "testing"
    "github.com/gruntwork-io/terratest/modules/terraform"
    "github.com/gruntwork-io/terratest/modules/aws"
    "github.com/stretchr/testify/assert"
)

func TestVPC(t *testing.T) {
    t.Parallel()

    terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
        TerraformDir: "../modules/vpc",
        Vars: map[string]interface{}{
            "name":               "test-vpc",
            "cidr_block":         "10.0.0.0/16",
            "availability_zones": []string{"eu-central-1a", "eu-central-1b"},
        },
        EnvVars: map[string]string{
            "AWS_DEFAULT_REGION": "eu-central-1",
        },
    })

    // Destroy at the end of the test
    defer terraform.Destroy(t, terraformOptions)

    // Create the infrastructure
    terraform.InitAndApply(t, terraformOptions)

    // Get outputs
    vpcID := terraform.Output(t, terraformOptions, "vpc_id")
    publicSubnetIDs := terraform.OutputList(t, terraformOptions, "public_subnet_ids")

    // Assertions
    assert.NotEmpty(t, vpcID)
    assert.Equal(t, 2, len(publicSubnetIDs))

    // Verify the VPC actually exists in AWS
    vpc := aws.GetVpcById(t, vpcID, "eu-central-1")
    assert.Equal(t, "10.0.0.0/16", vpc.CidrBlock)
    assert.True(t, vpc.EnableDnsHostnames)
}
```

### HTTP endpoint test

```go
func TestWebServer(t *testing.T) {
    t.Parallel()

    terraformOptions := &terraform.Options{
        TerraformDir: "../examples/web-server",
    }

    defer terraform.Destroy(t, terraformOptions)
    terraform.InitAndApply(t, terraformOptions)

    // Get the URL from output
    url := terraform.Output(t, terraformOptions, "url")

    // Wait for HTTP 200 (with retries)
    http_helper.HttpGetWithRetry(t, url, nil, 200, "Hello World", 30, 10*time.Second)
}
```

### Run tests

```bash
cd test

# Run all tests
go test -v -timeout 30m ./...

# Run specific test
go test -v -timeout 30m -run TestVPC

# Parallel tests
go test -v -timeout 60m -parallel 8 ./...
```

---

## 5. Terraform Test Framework (1.6+)

Terraform 1.6 introduced a native testing framework — no Go required.

```hcl
# modules/vpc/tests/vpc_test.tftest.hcl
run "creates_vpc_with_correct_cidr" {
  command = plan   # or apply (actually creates resources)

  variables {
    name               = "test-vpc"
    cidr_block         = "10.0.0.0/16"
    availability_zones = ["eu-central-1a", "eu-central-1b"]
  }

  assert {
    condition     = aws_vpc.this.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR block should be 10.0.0.0/16"
  }

  assert {
    condition     = aws_vpc.this.enable_dns_hostnames == true
    error_message = "DNS hostnames should be enabled"
  }
}

run "creates_correct_number_of_subnets" {
  command = plan

  variables {
    name               = "test-vpc"
    cidr_block         = "10.0.0.0/16"
    availability_zones = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  }

  assert {
    condition     = length(aws_subnet.public) == 3
    error_message = "Should create 3 public subnets"
  }

  assert {
    condition     = length(aws_subnet.private) == 3
    error_message = "Should create 3 private subnets"
  }
}

# Test with mock provider (no real AWS needed)
mock_provider "aws" {
  mock_resource "aws_vpc" {
    defaults = {
      id         = "vpc-mock123"
      cidr_block = "10.0.0.0/16"
    }
  }
}
```

```bash
# Run Terraform tests
terraform test

# Run specific test file
terraform test -filter=tests/vpc_test.tftest.hcl

# Verbose output
terraform test -verbose
```

---

## 6. Testing Strategy

### Testing pyramid for Terraform

```
                    ┌───────────────┐
                    │   E2E Tests   │  ← Terratest (full deploy)
                    │ (expensive)   │
                   /└───────────────┘
                  /  ┌─────────────────┐
                 /   │Integration Tests│  ← terraform test (plan/apply)
                /    │  (medium cost)  │
               /     └─────────────────┘
              /       ┌─────────────────────┐
             /        │   Unit Tests /       │  ← validate + tflint + checkov
            /         │ Static Analysis     │
           /          │   (free/fast)       │
          /           └─────────────────────┘
```

### CI pipeline for Terraform

```yaml
# .github/workflows/terraform.yml (see 10-cicd-integration.md for full version)
steps:
  - terraform fmt -check          # formatting
  - terraform init                # initialize
  - terraform validate            # syntax check
  - tflint --recursive            # lint
  - trivy config .                # security scan
  - checkov -d . --quiet          # compliance
  - terraform plan -out=tfplan    # plan (review artifacts)
  # Manual approval gate
  - terraform apply tfplan        # apply
```

---

## Cheatsheet

```bash
# Static analysis
terraform fmt -check -recursive
terraform validate
tflint --recursive

# Security scanning
trivy config .
trivy config --severity HIGH,CRITICAL --exit-code 1 .
checkov -d .

# Native tests (Terraform 1.6+)
terraform test
terraform test -filter=tests/vpc_test.tftest.hcl

# Terratest (Go)
cd test
go test -v -timeout 30m -run TestVPC

# Run all in sequence
terraform fmt -check -recursive && \
terraform validate && \
tflint --recursive && \
trivy config . && \
terraform plan -out=tfplan
```

---

*Next: [CI/CD Integration →](./10-cicd-integration.md)*
