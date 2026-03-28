# 🏗️ Terraform Core Concepts & Architecture

How Terraform works — providers, state, the plan/apply lifecycle, and the declarative model.

> Terraform is the standard tool for Infrastructure as Code (IaC). It provisions cloud resources — EC2 instances, VPCs, databases, Kubernetes clusters — by describing the desired state in code and making it real.

---

## 📚 Table of Contents

- [1. What is Terraform?](#1-what-is-terraform)
- [2. How Terraform Works](#2-how-terraform-works)
- [3. Providers](#3-providers)
- [4. State](#4-state)
- [5. The Plan/Apply Lifecycle](#5-the-planapply-lifecycle)
- [6. Terraform vs Other IaC Tools](#6-terraform-vs-other-iac-tools)
- [7. Core Terraform Commands](#7-core-terraform-commands)
- [8. Terraform Configuration Files](#8-terraform-configuration-files)
- [Key Terms Glossary](#key-terms-glossary)

---

## 1. What is Terraform?

Terraform is an open-source IaC tool by HashiCorp. You describe your infrastructure in HCL (HashiCorp Configuration Language) and Terraform provisions it across any cloud or service.

### What Terraform does

```
You write:                    Terraform creates:
──────────────────────────    ─────────────────────────────────
resource "aws_instance" {     EC2 instance in AWS
  ami           = "..."       with the specified AMI,
  instance_type = "t3.micro"  instance type, and tags
  tags = { Name = "web" }
}
```

### Key characteristics

- **Declarative** — describe *what* you want, not *how* to create it
- **Idempotent** — run `apply` multiple times, same result
- **Provider-agnostic** — AWS, GCP, Azure, Kubernetes, GitHub, Datadog, 1000+ providers
- **State-aware** — tracks what it has created, enabling updates and destroys
- **Plan before apply** — preview changes before making them

---

## 2. How Terraform Works

```
Your .tf files (desired state)
         │
         ▼
terraform init
  - Downloads providers
  - Initializes backend (remote state)
         │
         ▼
terraform plan
  - Reads current state (terraform.tfstate)
  - Queries real infrastructure (provider APIs)
  - Calculates diff: desired vs current
  - Shows execution plan (+ create, ~ update, - destroy)
         │
         ▼  (you review and approve)
         ▼
terraform apply
  - Executes the plan
  - Calls provider APIs to create/update/destroy resources
  - Updates state file with new actual state
         │
         ▼
Infrastructure matches your code ✅
```

### The dependency graph

Terraform builds a DAG (Directed Acyclic Graph) of resource dependencies:

```
aws_vpc ──────────────────► aws_subnet
    │                            │
    └──► aws_internet_gateway    └──► aws_instance
                                          │
aws_security_group ───────────────────────┘
```

Resources with no dependencies are created in parallel. Resources that depend on others are created in order.

---

## 3. Providers

Providers are plugins that let Terraform interact with external APIs. Each provider handles authentication and translates HCL into API calls.

```hcl
# Configure providers in terraform block
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
    github = {
      source  = "integrations/github"
      version = "~> 5.0"
    }
  }
  required_terraform = ">= 1.6.0"
}

# Configure the AWS provider
provider "aws" {
  region = "eu-central-1"

  default_tags {
    tags = {
      ManagedBy   = "Terraform"
      Environment = var.environment
      Project     = "my-project"
    }
  }
}

# Multiple provider configurations (aliases)
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

# Use aliased provider in a resource
resource "aws_s3_bucket" "cdn" {
  provider = aws.us-east-1
  bucket   = "my-cdn-bucket"
}
```

### How providers work

```
terraform init
    │
    ▼
Downloads provider plugins from registry.terraform.io
    │ (or custom registry)
    ▼
.terraform/providers/
  └── registry.terraform.io/hashicorp/aws/5.0.0/linux_amd64/
      └── terraform-provider-aws (binary)

At runtime:
  Terraform ←→ Provider plugin ←→ Cloud API
             gRPC              HTTPS
```

### Provider registry

```bash
# Find providers at:
# https://registry.terraform.io/browse/providers

# Official providers (hashicorp/): aws, google, azurerm, kubernetes
# Partner providers: datadog/datadog, grafana/grafana
# Community providers: thousands more
```

---

## 4. State

The **state file** is the most important concept in Terraform. It maps your configuration to real-world resources.

```json
// terraform.tfstate (simplified)
{
  "version": 4,
  "terraform_version": "1.6.0",
  "resources": [
    {
      "type": "aws_instance",
      "name": "web",
      "provider": "provider[\"registry.terraform.io/hashicorp/aws\"]",
      "instances": [
        {
          "attributes": {
            "id": "i-0a1b2c3d4e5f6g7h8",
            "ami": "ami-12345678",
            "instance_type": "t3.micro",
            "public_ip": "3.14.159.26",
            "tags": { "Name": "web-server" }
          }
        }
      ]
    }
  ]
}
```

### Why state matters

```
Without state:
  Terraform doesn't know what it has created
  Can't update or destroy existing resources
  Can't detect drift (manual changes)

With state:
  Terraform knows: "aws_instance.web = i-0a1b2c3d..."
  Can update only what changed
  Can detect if someone manually deleted a resource
  Can destroy exactly what it created
```

### State problems to avoid

```
❌ Committing state to Git — state contains sensitive values
❌ Multiple people editing state simultaneously — corruption
❌ Losing state — can't manage existing infrastructure

✅ Remote state (S3, GCS, Azure Blob, Terraform Cloud)
✅ State locking (DynamoDB, Terraform Cloud)
✅ State encryption
```

---

## 5. The Plan/Apply Lifecycle

### terraform plan output

```
Terraform will perform the following actions:

  # aws_instance.web will be created
  + resource "aws_instance" "web" {
      + ami           = "ami-12345678"
      + id            = (known after apply)        # set by AWS
      + instance_type = "t3.micro"
      + public_ip     = (known after apply)        # set by AWS
      + tags          = {
          + "Name" = "web-server"
        }
    }

  # aws_s3_bucket.logs will be updated in-place
  ~ resource "aws_s3_bucket" "logs" {
      ~ tags = {
          ~ "Environment" = "staging" -> "production"
        }
    }

  # aws_security_group.old will be destroyed
  - resource "aws_security_group" "old" {
      - id   = "sg-abc123"
      - name = "old-sg"
    }

Plan: 1 to add, 1 to change, 1 to destroy.
```

### Change symbols

| Symbol | Meaning |
|--------|---------|
| `+` | Will be created |
| `-` | Will be destroyed |
| `~` | Will be updated in-place |
| `-/+` | Will be destroyed and recreated (replacement) |
| `<= ` | Will be read (data source) |

### Apply with auto-approve (CI/CD)

```bash
# Always review plan before apply in production
terraform plan -out=tfplan     # save plan to file
terraform apply tfplan         # apply saved plan (no prompt)

# Or auto-approve (use with caution)
terraform apply -auto-approve
```

### Resource lifecycle

```hcl
resource "aws_instance" "web" {
  ami           = "ami-12345678"
  instance_type = "t3.micro"

  lifecycle {
    # Never destroy this resource (protect production)
    prevent_destroy = true

    # Create new resource before destroying old one (zero downtime)
    create_before_destroy = true

    # Ignore changes to these attributes (managed outside Terraform)
    ignore_changes = [
      ami,
      user_data,
    ]

    # Custom condition — fail if violated
    precondition {
      condition     = var.environment != "production" || var.instance_type != "t2.micro"
      error_message = "t2.micro is not allowed in production."
    }
  }
}
```

---

## 6. Terraform vs Other IaC Tools

| | Terraform | Pulumi | Ansible | CloudFormation |
|--|-----------|--------|---------|----------------|
| **Language** | HCL | Python/TS/Go | YAML | JSON/YAML |
| **Type** | IaC | IaC | Config mgmt | IaC |
| **State** | State file | State file | Stateless | AWS manages |
| **Multi-cloud** | ✅ Yes | ✅ Yes | ✅ Yes | ❌ AWS only |
| **Cloud-specific** | No | No | No | Yes |
| **Maturity** | Very mature | Growing | Very mature | Mature |
| **Community** | Huge | Growing | Huge | Large |

### Terraform vs Ansible

| | Terraform | Ansible |
|--|-----------|---------|
| **Primary use** | Provision infrastructure | Configure software on servers |
| **Example** | Create EC2, VPC, RDS | Install nginx, deploy app |
| **State** | Manages state | Stateless (mostly) |
| **Together** | Terraform creates server → Ansible configures it | — |

---

## 7. Core Terraform Commands

```bash
# Initialize — must run first, or after adding providers/modules
terraform init
terraform init -upgrade         # upgrade providers to latest allowed version
terraform init -reconfigure     # change backend config

# Plan — show what would change
terraform plan
terraform plan -out=tfplan      # save plan to file
terraform plan -target=aws_instance.web  # plan only this resource
terraform plan -var="env=prod"  # override variable
terraform plan -var-file=prod.tfvars     # load variables from file

# Apply — create/update/destroy infrastructure
terraform apply
terraform apply tfplan          # apply saved plan
terraform apply -auto-approve   # skip confirmation (CI/CD)
terraform apply -target=aws_instance.web  # apply only this resource

# Destroy — destroy all resources
terraform destroy
terraform destroy -auto-approve
terraform destroy -target=aws_instance.web  # destroy only this resource

# State commands
terraform show                  # show current state
terraform state list            # list all resources in state
terraform state show aws_instance.web  # show specific resource
terraform state mv              # rename/move resource in state
terraform state rm              # remove resource from state (not from cloud)
terraform import aws_instance.web i-abc123  # import existing resource

# Formatting and validation
terraform fmt                   # format .tf files
terraform fmt -recursive        # format all files recursively
terraform fmt -check            # exit 1 if files need formatting
terraform validate              # check configuration syntax

# Output
terraform output                # show all outputs
terraform output instance_ip    # show specific output
terraform output -json          # JSON format

# Refresh
terraform refresh               # update state to match real infrastructure
# (deprecated in favor of: terraform apply -refresh-only)

# Graph
terraform graph                 # output dependency graph (DOT format)
terraform graph | dot -Tpng > graph.png  # visualize
```

---

## 8. Terraform Configuration Files

```
my-infrastructure/
├── main.tf           # main resources
├── variables.tf      # input variable declarations
├── outputs.tf        # output value declarations
├── providers.tf      # provider configuration
├── versions.tf       # required_providers and terraform block
├── data.tf           # data source lookups
├── locals.tf         # local values
├── terraform.tfvars  # variable values (don't commit secrets!)
├── prod.tfvars       # environment-specific values
└── .terraform.lock.hcl  # provider version lock file (commit this!)
```

### File conventions

```hcl
# versions.tf — always separate this
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "my-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

# providers.tf — provider configuration
provider "aws" {
  region = var.aws_region
}
```

### .terraform.lock.hcl — commit this!

```hcl
# .terraform.lock.hcl — locks exact provider versions
provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.31.0"
  constraints = "~> 5.0"
  hashes = [
    "h1:abc123...",   # integrity hash
  ]
}
```

This ensures everyone on the team uses the same provider version. Commit it to Git.

---

## Key Terms Glossary

| Term | Definition |
|------|-----------|
| **HCL** | HashiCorp Configuration Language — the language Terraform uses |
| **Provider** | Plugin that connects Terraform to a specific API (AWS, GCP, etc.) |
| **Resource** | A piece of infrastructure managed by Terraform (EC2, VPC, etc.) |
| **Data source** | Read-only lookup of existing infrastructure |
| **State** | JSON file mapping configuration to real-world resources |
| **Backend** | Where state is stored (local, S3, GCS, Terraform Cloud) |
| **Plan** | Preview of changes Terraform will make |
| **Apply** | Execute the plan — actually create/update/destroy resources |
| **Module** | Reusable group of resources |
| **Workspace** | Separate state environment within the same configuration |
| **Variable** | Input parameter to a Terraform configuration |
| **Output** | Value exported from a Terraform configuration |
| **Local** | Named expression in a configuration (not exposed as input/output) |
| **Drift** | Difference between state and actual infrastructure (manual changes) |
| **Idempotent** | Running apply multiple times produces the same result |
| **DAG** | Directed Acyclic Graph — how Terraform models resource dependencies |
| **Lock file** | `.terraform.lock.hcl` — pins exact provider versions |
| **State lock** | Prevents concurrent `apply` operations from corrupting state |

---

*Next: [HCL Language Deep Dive →](./02-hcl-language.md)*
