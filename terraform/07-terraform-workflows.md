# 🏗️ Workflows & Best Practices

Project structure, GitOps patterns, naming conventions, and production-grade Terraform.

---

## 📚 Table of Contents

- [1. Project Structure](#1-project-structure)
- [2. Naming Conventions](#2-naming-conventions)
- [3. The Standard Workflow](#3-the-standard-workflow)
- [4. Environment Management](#4-environment-management)
- [5. Secrets & Sensitive Data](#5-secrets--sensitive-data)
- [6. Tagging Strategy](#6-tagging-strategy)
- [7. Code Organization Best Practices](#7-code-organization-best-practices)
- [8. Common Anti-Patterns](#8-common-anti-patterns)
- [Cheatsheet](#cheatsheet)

---

## 1. Project Structure

### Recommended layout

```
terraform/
├── modules/                    # reusable modules
│   ├── vpc/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf
│   │   └── README.md
│   ├── eks/
│   └── rds/
│
├── environments/               # environment-specific configs
│   ├── staging/
│   │   ├── main.tf            # calls modules
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── versions.tf        # backend config
│   │   └── terraform.tfvars   # staging values
│   └── production/
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── versions.tf
│       └── terraform.tfvars   # production values
│
└── bootstrap/                  # one-time setup (S3 state backend, etc.)
    ├── main.tf
    └── README.md
```

### Alternative: split by component

```
terraform/
├── 01-networking/              # VPC, subnets (run first)
│   ├── main.tf
│   └── backend.tf
├── 02-security/                # IAM, security groups (depends on networking)
│   └── main.tf
├── 03-compute/                 # EKS, EC2 (depends on networking + security)
│   └── main.tf
├── 04-data/                    # RDS, ElastiCache (depends on networking)
│   └── main.tf
└── 05-apps/                    # App deployments (depends on everything)
    └── main.tf
```

### File naming per directory

```
main.tf         → primary resources
variables.tf    → input variable declarations
outputs.tf      → output values
locals.tf       → local values and computed expressions
versions.tf     → terraform{} block with backend and required_providers
data.tf         → data sources (when many)
iam.tf          → IAM resources (when many)
sg.tf           → security groups (when many)
```

---

## 2. Naming Conventions

### Resource naming

```hcl
# Pattern: <project>-<environment>-<component>-<type>
# Examples:
resource "aws_vpc" "main" {
  tags = { Name = "myapp-production-vpc" }
}

resource "aws_eks_cluster" "main" {
  name = "myapp-production-eks"
}

resource "aws_db_instance" "main" {
  identifier = "myapp-production-postgres"
}

# In HCL: use snake_case for resource names
resource "aws_instance" "web_server" { ... }    # good
resource "aws_instance" "webServer" { ... }     # bad
resource "aws_instance" "WebServer" { ... }     # bad

# Avoid:
resource "aws_instance" "this" { ... }          # too generic (use if only one of its type)
resource "aws_instance" "instance" { ... }      # redundant (type already in block label)
```

### Variable naming

```hcl
# Descriptive, snake_case
variable "vpc_cidr_block" { ... }
variable "eks_cluster_version" { ... }
variable "db_instance_class" { ... }
variable "enable_deletion_protection" { ... }
variable "allowed_cidr_blocks" { ... }
```

### Module naming

```
modules/vpc/
modules/eks-cluster/
modules/rds-postgres/
modules/s3-static-website/
```

---

## 3. The Standard Workflow

### Day-to-day development

```bash
# 1. Write/edit .tf files

# 2. Format
terraform fmt -recursive

# 3. Validate syntax
terraform validate

# 4. Preview changes
terraform plan -out=tfplan

# 5. Review the plan carefully!
# Ask yourself:
#   - Are all changes expected?
#   - Any unexpected destroys?
#   - Any replacement (-/+) that shouldn't happen?

# 6. Apply
terraform apply tfplan

# 7. Verify
terraform output
# Manually verify in cloud console
```

### Code review checklist

```
Before committing:
✅ terraform fmt has been run
✅ terraform validate passes
✅ terraform plan output reviewed
✅ No unexpected destroys or replacements
✅ New variables have descriptions and validations
✅ New resources follow naming conventions
✅ Sensitive values are marked sensitive = true
✅ Resources have required tags
✅ .terraform.lock.hcl is committed
✅ terraform.tfvars is NOT committed (if contains secrets)
```

---

## 4. Environment Management

### Separate directories (recommended)

```hcl
# environments/production/main.tf
module "vpc" {
  source = "../../modules/vpc"

  name               = "myapp-production"
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  enable_nat_gateway = true
  tags               = local.common_tags
}

# environments/production/versions.tf
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "mycompany-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}

# environments/production/terraform.tfvars
environment    = "production"
instance_count = 5
instance_type  = "t3.large"
```

### Environment-specific values

```hcl
locals {
  env_config = {
    development = {
      instance_type      = "t3.micro"
      min_size           = 1
      max_size           = 2
      deletion_protection = false
      backup_retention    = 1
    }
    staging = {
      instance_type      = "t3.small"
      min_size           = 2
      max_size           = 4
      deletion_protection = false
      backup_retention    = 3
    }
    production = {
      instance_type      = "t3.large"
      min_size           = 3
      max_size           = 10
      deletion_protection = true
      backup_retention    = 14
    }
  }
  config = local.env_config[var.environment]
}
```

---

## 5. Secrets & Sensitive Data

### Never commit secrets to Git

```bash
# .gitignore
*.tfvars           # contains variable values (may include secrets)
*.tfvars.json
!example.tfvars    # commit example file without actual secrets
terraform.tfstate
terraform.tfstate.backup
.terraform/
crash.log
```

### Patterns for handling secrets

```hcl
# Pattern 1 — AWS SSM Parameter Store
data "aws_ssm_parameter" "db_password" {
  name            = "/production/database/password"
  with_decryption = true
}

resource "aws_db_instance" "main" {
  password = data.aws_ssm_parameter.db_password.value
}

# Pattern 2 — AWS Secrets Manager
data "aws_secretsmanager_secret_version" "db" {
  secret_id = "production/myapp/database"
}

locals {
  db_creds = jsondecode(data.aws_secretsmanager_secret_version.db.secret_string)
}

resource "aws_db_instance" "main" {
  username = local.db_creds["username"]
  password = local.db_creds["password"]
}

# Pattern 3 — Environment variables (for Terraform itself)
# TF_VAR_db_password=secret terraform apply
variable "db_password" {
  type      = string
  sensitive = true
}

# Pattern 4 — Let the service manage credentials (best)
resource "aws_db_instance" "main" {
  manage_master_user_password = true   # AWS rotates automatically
}
```

---

## 6. Tagging Strategy

Consistent tagging is critical for cost allocation, security, and operations.

```hcl
# locals.tf — define all common tags once
locals {
  required_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
    Owner       = var.team
    CostCenter  = var.cost_center
  }

  common_tags = merge(local.required_tags, var.additional_tags)
}

# Apply to all resources
resource "aws_vpc" "main" {
  cidr_block = var.cidr_block
  tags       = merge(local.common_tags, { Name = "${var.project}-${var.environment}-vpc" })
}

# Use AWS provider default_tags to apply to all resources automatically
provider "aws" {
  region = var.region
  default_tags {
    tags = local.required_tags
  }
}

# With default_tags, individual resources only need Name tag
resource "aws_vpc" "main" {
  cidr_block = var.cidr_block
  tags       = { Name = "${var.project}-${var.environment}-vpc" }
  # required_tags applied automatically by provider
}
```

---

## 7. Code Organization Best Practices

### Use locals to DRY up repeated values

```hcl
# BAD — repeated everywhere
resource "aws_instance" "web" {
  tags = {
    Project     = "myapp"
    Environment = "production"
    ManagedBy   = "Terraform"
  }
}
resource "aws_db_instance" "main" {
  tags = {
    Project     = "myapp"     # duplicated
    Environment = "production" # duplicated
    ManagedBy   = "Terraform"  # duplicated
  }
}

# GOOD — define once in locals
locals {
  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
}

resource "aws_instance" "web" {
  tags = merge(local.common_tags, { Name = "web" })
}
resource "aws_db_instance" "main" {
  tags = merge(local.common_tags, { Name = "database" })
}
```

### One resource per file when managing large configurations

```
eks-cluster.tf          → aws_eks_cluster + aws_eks_node_group
eks-iam.tf              → IAM roles and policies for EKS
eks-addons.tf           → EKS add-ons (CoreDNS, kube-proxy, VPC CNI)
```

### Use `moved` block for refactoring

```hcl
# When renaming a resource, use moved block instead of destroy + recreate
moved {
  from = aws_instance.web_server
  to   = aws_instance.web
}

# When moving a resource into a module
moved {
  from = aws_instance.web
  to   = module.compute.aws_instance.web
}
```

---

## 8. Common Anti-Patterns

### ❌ Hardcoding values

```hcl
# BAD
resource "aws_instance" "web" {
  ami           = "ami-12345678"           # hardcoded, region-specific
  instance_type = "t3.micro"              # hardcoded, not parameterized
  subnet_id     = "subnet-abc123"         # hardcoded, not reusable
}

# GOOD
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id   # data source
  instance_type = var.instance_type        # parameterized
  subnet_id     = module.vpc.private_subnet_ids[0]  # from module
}
```

### ❌ count for named resources

```hcl
# BAD — if you add az at index 0, it renumbers all others
resource "aws_subnet" "private" {
  count             = length(var.availability_zones)
  availability_zone = var.availability_zones[count.index]
  # If you remove az[0], aws_subnet.private[1] becomes aws_subnet.private[0]
  # Terraform destroys [0] and recreates [1] as [0] — unexpected!
}

# GOOD — for_each uses stable keys
resource "aws_subnet" "private" {
  for_each          = toset(var.availability_zones)
  availability_zone = each.key
  # Adding or removing one AZ only affects that specific subnet
}
```

### ❌ Not locking provider versions

```hcl
# BAD — next terraform init might get a breaking provider update
terraform {
  required_providers {
    aws = { source = "hashicorp/aws" }
  }
}

# GOOD — lock to tested version range
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"    # allow patch and minor, not major
    }
  }
}
```

### ❌ Giant single-file configurations

```hcl
# BAD — 1000-line main.tf
# GOOD — split into logical files:
#   networking.tf, compute.tf, database.tf, iam.tf, monitoring.tf
```

### ❌ Sensitive data in outputs without sensitive = true

```hcl
# BAD — password visible in terraform output
output "db_password" {
  value = aws_db_instance.main.password
}

# GOOD
output "db_password" {
  value     = aws_db_instance.main.password
  sensitive = true
}
```

---

## Cheatsheet

```bash
# Standard workflow
terraform fmt -recursive
terraform validate
terraform plan -out=tfplan
terraform apply tfplan

# Check before committing
terraform fmt -check -recursive      # fails if formatting needed
terraform validate
trivy config .                        # security scan (install trivy)
tfsec .                               # alternative security scanner
checkov -d .                          # another security scanner

# Working with environments
cd environments/production
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars

# Useful aliases
alias tf='terraform'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'
alias tfi='terraform init'
alias tfo='terraform output'
alias tfs='terraform state'
```

---

*Next: [Cloud-Specific Patterns →](./08-cloud-patterns.md)*
