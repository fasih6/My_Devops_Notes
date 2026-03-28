# 🗄️ State Management

Remote state, locking, workspaces, import, and managing state safely in teams.

---

## 📚 Table of Contents

- [1. State Fundamentals](#1-state-fundamentals)
- [2. Remote Backends](#2-remote-backends)
- [3. State Locking](#3-state-locking)
- [4. State Commands](#4-state-commands)
- [5. Importing Existing Resources](#5-importing-existing-resources)
- [6. Workspaces](#6-workspaces)
- [7. State Splitting Strategies](#7-state-splitting-strategies)
- [8. Recovering from State Problems](#8-recovering-from-state-problems)
- [Cheatsheet](#cheatsheet)

---

## 1. State Fundamentals

Terraform state maps your configuration to real-world resources. Without it, Terraform can't update or destroy what it created.

### Local state (default, development only)

```
terraform.tfstate          ← main state file
terraform.tfstate.backup   ← previous state (auto-backup)
```

```bash
# View current state
terraform show
cat terraform.tfstate    # raw JSON

# Never commit terraform.tfstate to Git
echo "terraform.tfstate" >> .gitignore
echo "terraform.tfstate.backup" >> .gitignore
echo ".terraform/" >> .gitignore
```

### Why remote state is essential for teams

```
Problem with local state in teams:
  Person A: terraform apply → updates local state
  Person B: terraform apply → doesn't know about A's changes
  Result: duplicate resources, conflicts, corruption

Solution: Remote state
  Both A and B read/write from a central location
  State locking prevents concurrent operations
```

---

## 2. Remote Backends

### AWS S3 (most common)

```hcl
# versions.tf
terraform {
  backend "s3" {
    bucket         = "my-company-terraform-state"
    key            = "production/eks/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true                              # encrypt state at rest
    dynamodb_table = "terraform-state-lock"           # for locking
    
    # Optional: role to assume for state access
    role_arn = "arn:aws:iam::123456789:role/terraform-state-access"
  }
}
```

#### Bootstrap the S3 backend

```hcl
# bootstrap/main.tf — run this ONCE to create the backend
resource "aws_s3_bucket" "terraform_state" {
  bucket = "my-company-terraform-state"
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"    # keep state history
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.terraform_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_lock" {
  name         = "terraform-state-lock"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
```

### GCP Cloud Storage

```hcl
terraform {
  backend "gcs" {
    bucket  = "my-company-terraform-state"
    prefix  = "production/gke"
    # State file: gs://bucket/production/gke/default.tfstate
  }
}
```

### Azure Blob Storage

```hcl
terraform {
  backend "azurerm" {
    resource_group_name  = "terraform-state-rg"
    storage_account_name = "mycompanyterraformstate"
    container_name       = "terraform-state"
    key                  = "production.tfstate"
  }
}
```

### Terraform Cloud / HCP Terraform

```hcl
terraform {
  cloud {
    organization = "my-company"
    workspaces {
      name = "production-eks"
    }
  }
}
```

### Reading state from another workspace (remote state data source)

```hcl
# Read outputs from another Terraform workspace's state
data "terraform_remote_state" "vpc" {
  backend = "s3"
  config = {
    bucket = "my-company-terraform-state"
    key    = "production/vpc/terraform.tfstate"
    region = "eu-central-1"
  }
}

# Use VPC outputs in this configuration
resource "aws_subnet" "app" {
  vpc_id     = data.terraform_remote_state.vpc.outputs.vpc_id
  cidr_block = "10.0.10.0/24"
}
```

---

## 3. State Locking

State locking prevents multiple people or CI jobs from running `terraform apply` simultaneously, which would corrupt the state.

```bash
# Locking happens automatically on plan and apply
# You'll see: "Acquiring state lock. This may take a few moments..."

# If a lock is stuck (crash during apply):
terraform force-unlock LOCK_ID
# Get LOCK_ID from the error message:
# Error: Error acquiring the state lock
# Lock Info: ID: abc123-def456...

# View lock info
aws dynamodb get-item \
  --table-name terraform-state-lock \
  --key '{"LockID": {"S": "my-company-terraform-state/production/eks/terraform.tfstate"}}'
```

---

## 4. State Commands

```bash
# List all resources in state
terraform state list
terraform state list aws_instance.*    # filter by type

# Show details of a specific resource
terraform state show aws_instance.web
terraform state show 'aws_instance.servers[0]'
terraform state show 'aws_instance.servers["web-1"]'   # for_each

# Move resource in state (rename without destroying)
terraform state mv aws_instance.web aws_instance.webserver
terraform state mv 'module.old_name' 'module.new_name'

# Remove resource from state (won't destroy actual resource)
terraform state rm aws_instance.web
# Use when: resource was deleted manually, or you want Terraform to stop managing it

# Pull/push state (for manual inspection)
terraform state pull > current-state.json
terraform state push fixed-state.json   # DANGEROUS — use carefully

# Replace a resource (force destroy + create)
terraform apply -replace=aws_instance.web

# Refresh state from real infrastructure
terraform apply -refresh-only
# (previously: terraform refresh)
```

---

## 5. Importing Existing Resources

Import brings existing infrastructure under Terraform management.

### CLI import (Terraform 1.5+)

```hcl
# import block in configuration (Terraform 1.5+)
import {
  to = aws_instance.web
  id = "i-0a1b2c3d4e5f6g7h8"
}

# Then run:
# terraform plan   ← shows what will be imported
# terraform apply  ← imports the resource
```

### Generate configuration for imported resources

```bash
# Terraform 1.5+ can generate the HCL for you
terraform plan -generate-config-out=generated.tf
# Generates the resource block based on the actual infrastructure
# Edit as needed, then run terraform apply
```

### Old-style import command

```bash
# For older Terraform versions
terraform import aws_instance.web i-0a1b2c3d4e5f6g7h8
terraform import aws_s3_bucket.logs my-logs-bucket
terraform import aws_route53_record.www "ZONE_ID_RECORD_ID_TYPE"

# For_each resources — use the key
terraform import 'aws_subnet.private["eu-central-1a"]' subnet-abc123

# Module resources
terraform import 'module.vpc.aws_vpc.main' vpc-abc123
```

### Import workflow

```bash
# Step 1: Write the resource block
resource "aws_instance" "web" {
  # Fill in attributes based on the real resource
  ami           = "ami-12345678"
  instance_type = "t3.micro"
}

# Step 2: Import
terraform import aws_instance.web i-0a1b2c3d4e5f6g7h8

# Step 3: Plan to see what differs
terraform plan
# If there are diffs: update your HCL to match reality
# If no diffs: you're done

# Step 4: Apply (optional, only if you want to bring into desired state)
terraform apply
```

---

## 6. Workspaces

Workspaces provide separate state files within the same configuration. Each workspace has its own state.

```bash
# List workspaces
terraform workspace list
# * default    ← currently selected
#   staging
#   production

# Create workspace
terraform workspace new staging
terraform workspace new production

# Switch workspace
terraform workspace select production
terraform workspace select default

# Show current workspace
terraform workspace show

# Delete workspace (must be empty)
terraform workspace delete staging
```

### Use workspace name in configuration

```hcl
# Different instance types per workspace
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = terraform.workspace == "production" ? "t3.large" : "t3.micro"

  tags = {
    Name        = "web-${terraform.workspace}"
    Environment = terraform.workspace
  }
}

# Different configurations via map lookup
locals {
  workspace_config = {
    default    = { instance_type = "t3.micro",  count = 1 }
    staging    = { instance_type = "t3.small",  count = 2 }
    production = { instance_type = "t3.large",  count = 5 }
  }
  config = local.workspace_config[terraform.workspace]
}

resource "aws_instance" "web" {
  count         = local.config.count
  instance_type = local.config.instance_type
}
```

### Workspaces vs separate directories

| | Workspaces | Separate directories |
|--|------------|---------------------|
| **Code duplication** | One codebase | Separate code per env |
| **State separation** | Separate state per workspace | Completely separate |
| **Risk** | Easy to apply to wrong env | Harder to make mistakes |
| **Recommended for** | Very similar environments | Different environments |
| **Best practice** | Use with caution | Preferred by most teams |

**Many teams prefer separate directories** (see State Splitting below) over workspaces for environments with different configurations.

---

## 7. State Splitting Strategies

### Split by component (recommended)

```
terraform/
├── networking/          ← VPC, subnets, routing
│   ├── main.tf
│   └── backend.tf (key: "networking/terraform.tfstate")
├── eks/                 ← Kubernetes cluster
│   ├── main.tf
│   └── backend.tf (key: "eks/terraform.tfstate")
├── rds/                 ← Databases
│   ├── main.tf
│   └── backend.tf (key: "rds/terraform.tfstate")
└── apps/                ← Application resources
    ├── main.tf
    └── backend.tf (key: "apps/terraform.tfstate")
```

Benefits:
- Faster plan/apply (fewer resources)
- Blast radius reduction (bug in apps/ doesn't affect networking/)
- Teams can work independently

### Split by environment

```
terraform/
├── environments/
│   ├── staging/
│   │   ├── main.tf
│   │   └── terraform.tfvars
│   └── production/
│       ├── main.tf
│       └── terraform.tfvars
└── modules/             ← shared reusable modules
    ├── vpc/
    └── eks/
```

---

## 8. Recovering from State Problems

### State corruption

```bash
# State has versioning enabled in S3 — restore previous version
aws s3 ls s3://my-bucket/production/terraform.tfstate --versions
aws s3api get-object \
  --bucket my-bucket \
  --key production/terraform.tfstate \
  --version-id YOUR_VERSION_ID \
  terraform.tfstate.backup

# Push the backup back
terraform state push terraform.tfstate.backup
```

### Resource accidentally destroyed (state knows, cloud doesn't have it)

```bash
# Remove from state so Terraform doesn't try to update it
terraform state rm aws_instance.web

# Recreate it
terraform apply
```

### Resource exists in cloud but not in state

```bash
# Import it
terraform import aws_instance.web i-0a1b2c3d4e5f6g7h8
```

### State lock stuck after crash

```bash
# Get the lock ID from the error message
terraform force-unlock abc123-def456-...
```

---

## Cheatsheet

```bash
# State inspection
terraform state list
terraform state show aws_instance.web

# State manipulation
terraform state mv aws_instance.old aws_instance.new
terraform state rm aws_instance.unwanted
terraform state pull > backup.json

# Import
terraform import aws_instance.web i-abc123
terraform plan -generate-config-out=generated.tf  # 1.5+

# Workspaces
terraform workspace new staging
terraform workspace select production
terraform workspace list

# Force refresh (update state from real infra)
terraform apply -refresh-only

# Force replace
terraform apply -replace=aws_instance.web

# Unlock stuck state
terraform force-unlock LOCK_ID
```

---

*Next: [Modules →](./06-modules.md)*
