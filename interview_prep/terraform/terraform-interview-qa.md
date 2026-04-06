# Terraform Interview Q&A — All Levels

> **Coverage**: Beginner → Intermediate → Advanced → Scenario-Based  
> **Format**: Mix of concise answers, bullet points, tables, and code snippets  
> **Total**: 120+ questions across 10 topic sections  
> **Relevance**: DevOps/Cloud Engineer roles, IaC interviews, AWS/Azure/GCP positions

---

## Table of Contents

1. [Terraform Fundamentals](#1-terraform-fundamentals)
2. [Providers, Resources & Data Sources](#2-providers-resources--data-sources)
3. [Variables, Outputs & Locals](#3-variables-outputs--locals)
4. [State Management](#4-state-management)
5. [Modules](#5-modules)
6. [Terraform CLI & Workflow](#6-terraform-cli--workflow)
7. [Workspaces, Backends & Remote Operations](#7-workspaces-backends--remote-operations)
8. [Functions, Expressions & Meta-Arguments](#8-functions-expressions--meta-arguments)
9. [Advanced Terraform & Best Practices](#9-advanced-terraform--best-practices)
10. [Scenario-Based & Real-World Questions](#10-scenario-based--real-world-questions)

---

## 1. Terraform Fundamentals

---

**Q1. What is Terraform?**

Terraform is an open-source **Infrastructure as Code (IaC)** tool developed by HashiCorp. It allows you to define, provision, and manage infrastructure across multiple cloud providers and services using a **declarative configuration language** (HCL — HashiCorp Configuration Language).

Key capabilities:
- Provision cloud resources (AWS, Azure, GCP, Kubernetes, etc.)
- Manage infrastructure lifecycle (create, update, destroy)
- Track infrastructure state
- Plan changes before applying them

---

**Q2. What is Infrastructure as Code (IaC)?**

IaC is the practice of managing and provisioning infrastructure through **machine-readable configuration files** rather than manual processes. Benefits:

| Benefit | Description |
|---|---|
| **Reproducibility** | Same config produces same infrastructure every time |
| **Version control** | Infrastructure changes tracked in Git |
| **Automation** | Provision without manual clicks in consoles |
| **Consistency** | No configuration drift between environments |
| **Speed** | Provision hundreds of resources in minutes |
| **Documentation** | Code IS the documentation |

---

**Q3. What is HCL (HashiCorp Configuration Language)?**

HCL is the language used to write Terraform configurations. It is:
- Human-readable and writable
- JSON-compatible (Terraform also accepts `.tf.json` files)
- Declarative — you describe **what** you want, not how to create it

```hcl
# Example HCL syntax
resource "aws_instance" "web" {
  ami           = "ami-0c55b159cbfafe1f0"
  instance_type = "t2.micro"

  tags = {
    Name = "WebServer"
    Env  = "production"
  }
}
```

---

**Q4. What is the difference between declarative and imperative IaC?**

| Declarative (Terraform) | Imperative (Ansible scripts, bash) |
|---|---|
| Describe desired end state | Describe step-by-step instructions |
| Tool figures out how to achieve it | You define how to achieve it |
| Idempotent by design | Idempotency requires manual effort |
| Examples: Terraform, CloudFormation | Examples: Ansible (procedural), bash scripts |

---

**Q5. What are the main Terraform competitors?**

| Tool | Provider | Notes |
|---|---|---|
| **Pulumi** | Pulumi Inc | Uses general-purpose languages (Python, Go, TypeScript) |
| **AWS CloudFormation** | AWS | AWS-only; JSON/YAML |
| **Azure Bicep / ARM** | Microsoft | Azure-only |
| **Ansible** | Red Hat | Primarily config management; can provision infra |
| **OpenTofu** | CNCF | Open-source Terraform fork (post BSL license change) |
| **Crossplane** | CNCF | Kubernetes-native IaC using CRDs |

---

**Q6. What is OpenTofu and why does it exist?**

OpenTofu is an **open-source fork of Terraform** created after HashiCorp changed Terraform's license from MPL (Mozilla Public License) to BSL (Business Source License) in August 2023. BSL restricts commercial use by competitors.

OpenTofu is now a CNCF project and aims to be a drop-in replacement for Terraform. Most HCL code works unchanged between the two.

---

**Q7. What are the key Terraform concepts?**

| Concept | Description |
|---|---|
| **Provider** | Plugin that connects to an API (AWS, Azure, Kubernetes) |
| **Resource** | Infrastructure object managed by Terraform (EC2 instance, S3 bucket) |
| **Data Source** | Read-only query of existing infrastructure |
| **Module** | Reusable group of resources |
| **State** | File tracking what Terraform has created |
| **Plan** | Preview of changes before applying |
| **Workspace** | Isolated state environment |
| **Backend** | Where state is stored |
| **Variable** | Input parameter to make configs reusable |
| **Output** | Values exported from a module or root config |

---

**Q8. What is idempotency in Terraform?**

Idempotency means running `terraform apply` **multiple times produces the same result**. If the infrastructure already matches the desired state, Terraform makes no changes. This is a core property — Terraform compares the current state (from state file) with the desired state (from config) and only applies the diff.

---

**Q9. What file types does Terraform use?**

| Extension | Purpose |
|---|---|
| `.tf` | Main configuration files (HCL) |
| `.tf.json` | JSON-format configuration (alternative to HCL) |
| `.tfvars` | Variable value files |
| `.tfvars.json` | JSON variable value files |
| `.tfstate` | State file (local or remote) |
| `.tfstate.backup` | Backup of previous state |
| `.terraform/` | Local directory for provider plugins and modules |
| `.terraform.lock.hcl` | Dependency lock file (provider versions) |

---

**Q10. What is the `.terraform.lock.hcl` file?**

The lock file records the **exact provider versions** used in a configuration, including their checksums. It ensures reproducible runs across different machines and CI environments:

```hcl
provider "registry.terraform.io/hashicorp/aws" {
  version     = "5.31.0"
  constraints = "~> 5.0"
  hashes = [
    "h1:abc123...",
    "zh:def456...",
  ]
}
```

```bash
# Always commit .terraform.lock.hcl to Git
# Update provider versions with:
terraform init -upgrade
```

---

## 2. Providers, Resources & Data Sources

---

**Q11. What is a Terraform provider?**

A provider is a **plugin** that allows Terraform to interact with a specific API or service. Providers are responsible for:
- Understanding API authentication
- Mapping Terraform resources to API calls
- Managing CRUD operations for resources

```hcl
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
  }
}

provider "aws" {
  region  = "eu-central-1"
  profile = "mycompany"
}
```

---

**Q12. How are providers installed?**

```bash
# terraform init downloads providers declared in configuration
terraform init

# Providers are stored in:
.terraform/providers/registry.terraform.io/hashicorp/aws/5.31.0/...

# Upgrade providers
terraform init -upgrade
```

Providers are downloaded from the **Terraform Registry** (`registry.terraform.io`) by default.

---

**Q13. What is a resource in Terraform?**

A resource represents an **infrastructure object** to be created, updated, or destroyed. Each resource has a type, a local name, and arguments:

```hcl
resource "<PROVIDER>_<TYPE>" "<LOCAL_NAME>" {
  # Arguments
}

# Example
resource "aws_s3_bucket" "my_bucket" {
  bucket = "my-unique-bucket-name"

  tags = {
    Environment = "production"
  }
}
```

Resource address format: `aws_s3_bucket.my_bucket`

---

**Q14. What is a data source in Terraform?**

A data source allows Terraform to **read information** from existing infrastructure or external sources without managing it. Used to fetch IDs, AMIs, VPC details, etc.:

```hcl
# Read the latest Amazon Linux 2 AMI ID
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

# Use in a resource
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
}
```

---

**Q15. What is the difference between a resource and a data source?**

| Resource | Data Source |
|---|---|
| Declared with `resource` block | Declared with `data` block |
| Terraform **creates and manages** it | Terraform only **reads** it |
| Included in state | Referenced but not owned by state |
| Can be updated or destroyed | Read-only; never destroyed by Terraform |
| Example: create an S3 bucket | Example: fetch existing VPC ID |

---

**Q16. How do you reference attributes of another resource?**

Using the resource address and attribute name:

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "public" {
  vpc_id     = aws_vpc.main.id          # Reference vpc_id from above
  cidr_block = "10.0.1.0/24"
}

resource "aws_security_group" "web" {
  vpc_id = aws_vpc.main.id
  name   = "web-sg-${aws_vpc.main.id}"  # Use in string
}
```

---

**Q17. What are provider aliases and when do you use them?**

Provider aliases allow using **multiple configurations of the same provider** — e.g., deploying to multiple AWS regions:

```hcl
provider "aws" {
  region = "eu-central-1"
}

provider "aws" {
  alias  = "us_east"
  region = "us-east-1"
}

resource "aws_s3_bucket" "eu_bucket" {
  bucket = "my-eu-bucket"
  # Uses default provider (eu-central-1)
}

resource "aws_s3_bucket" "us_bucket" {
  provider = aws.us_east               # Use alias
  bucket   = "my-us-bucket"
}
```

---

**Q18. What is the `terraform` block?**

The `terraform` block configures Terraform itself — required provider versions, backend, and required Terraform version:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket = "my-terraform-state"
    key    = "prod/terraform.tfstate"
    region = "eu-central-1"
  }
}
```

---

**Q19. What is resource meta-argument `depends_on`?**

`depends_on` explicitly declares a dependency between resources when Terraform cannot automatically infer it:

```hcl
resource "aws_iam_role_policy" "example" {
  role   = aws_iam_role.example.name
  policy = data.aws_iam_policy_document.example.json
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  depends_on = [
    aws_iam_role_policy.example    # Wait for IAM policy to be created first
  ]
}
```

Terraform automatically handles dependencies when you reference resource attributes. Use `depends_on` only for hidden dependencies (e.g., IAM propagation).

---

**Q20. What is a `null_resource` and when is it used?**

A `null_resource` is a resource that does nothing by itself but is used to run **provisioners** or create explicit dependencies when no real resource is needed:

```hcl
resource "null_resource" "run_script" {
  triggers = {
    always_run = timestamp()    # Re-run on every apply
  }

  provisioner "local-exec" {
    command = "echo 'Infrastructure ready' > /tmp/ready.txt"
  }
}
```

Modern alternative: use `terraform_data` resource (Terraform 1.4+).

---

## 3. Variables, Outputs & Locals

---

**Q21. What are input variables in Terraform?**

Input variables make Terraform configurations **reusable and configurable** without hardcoding values:

```hcl
variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "environment" {
  description = "Deployment environment"
  type        = string
  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}
```

---

**Q22. What are the variable types in Terraform?**

| Type | Example |
|---|---|
| `string` | `"eu-central-1"` |
| `number` | `3` |
| `bool` | `true` |
| `list(string)` | `["a", "b", "c"]` |
| `set(string)` | `["a", "b"]` (unordered, unique) |
| `map(string)` | `{key = "value"}` |
| `object({...})` | `{name = string, age = number}` |
| `tuple([...])` | `[string, number, bool]` |
| `any` | Any type |

---

**Q23. How do you pass variable values to Terraform?**

In order of precedence (highest to lowest):

```bash
# 1. CLI -var flag (highest priority)
terraform apply -var="environment=prod"

# 2. CLI -var-file flag
terraform apply -var-file="prod.tfvars"

# 3. Auto-loaded .tfvars files
# terraform.tfvars or *.auto.tfvars are loaded automatically

# 4. Environment variables
export TF_VAR_environment=prod

# 5. Default value in variable block (lowest priority)
```

```hcl
# terraform.tfvars
environment   = "production"
instance_type = "t3.small"
region        = "eu-central-1"
```

---

**Q24. What are output values in Terraform?**

Outputs expose values from your configuration — useful for:
- Passing values between modules
- Displaying useful info after apply
- Exposing values to external tools (CI/CD, scripts)

```hcl
output "instance_public_ip" {
  description = "Public IP of the web server"
  value       = aws_instance.web.public_ip
}

output "rds_endpoint" {
  description = "RDS connection endpoint"
  value       = aws_db_instance.main.endpoint
  sensitive   = true    # Redacted from CLI output; still in state
}
```

```bash
# View outputs after apply
terraform output
terraform output instance_public_ip
terraform output -json    # Machine-readable
```

---

**Q25. What are local values (`locals`) in Terraform?**

Locals define **named expressions** within a module — reduce repetition and improve readability:

```hcl
locals {
  common_tags = {
    Project     = "MyApp"
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  name_prefix = "${var.project}-${var.environment}"
  is_prod     = var.environment == "prod"
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = local.is_prod ? "t3.large" : "t3.micro"

  tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-web"
  })
}
```

---

**Q26. What is the difference between variables, locals, and outputs?**

| | Variables | Locals | Outputs |
|---|---|---|---|
| Direction | Input (from outside) | Internal | Output (to outside) |
| Set by | User/CI/tfvars | Config author | Config author |
| Recomputed | On each call | Within module | After apply |
| Use case | Parameterize configs | DRY, computed values | Share values between modules/tools |

---

**Q27. What is variable validation?**

Validation blocks enforce constraints on variable values:

```hcl
variable "cidr_block" {
  type        = string
  description = "VPC CIDR block"

  validation {
    condition     = can(cidrnetmask(var.cidr_block))
    error_message = "Must be a valid CIDR block like 10.0.0.0/16."
  }
}

variable "instance_count" {
  type    = number
  default = 1

  validation {
    condition     = var.instance_count >= 1 && var.instance_count <= 10
    error_message = "Instance count must be between 1 and 10."
  }
}
```

---

**Q28. What does `sensitive = true` do for a variable or output?**

Marking a variable or output as `sensitive` prevents Terraform from displaying its value in CLI output and plan output. However:
- The value is still stored in state (potentially in plaintext)
- State file must be protected (encryption, access control)
- Sensitive values propagate — any expression using a sensitive value becomes sensitive

```hcl
variable "db_password" {
  type      = string
  sensitive = true
}

output "db_password_out" {
  value     = var.db_password
  sensitive = true    # Required if value is sensitive
}
```

---

**Q29. How do you use environment variables with Terraform?**

```bash
# TF_VAR_<variable_name> pattern
export TF_VAR_region="eu-central-1"
export TF_VAR_db_password="mysecretpassword"

# Terraform-specific env vars
export TF_LOG=DEBUG               # Enable debug logging
export TF_LOG_PATH=/tmp/tf.log    # Log to file
export TF_DATA_DIR=.terraform     # Override .terraform directory
export TF_CLI_ARGS="-parallelism=5"  # Default CLI args
export TF_WORKSPACE=production    # Set workspace
```

---

**Q30. What is the `object` variable type and when is it useful?**

The `object` type groups multiple typed attributes into a structured variable:

```hcl
variable "database" {
  type = object({
    instance_class    = string
    allocated_storage = number
    multi_az          = bool
    engine_version    = string
  })
  default = {
    instance_class    = "db.t3.micro"
    allocated_storage = 20
    multi_az          = false
    engine_version    = "8.0"
  }
}

resource "aws_db_instance" "main" {
  instance_class    = var.database.instance_class
  allocated_storage = var.database.allocated_storage
  multi_az          = var.database.multi_az
}
```

---

## 4. State Management

---

**Q31. What is Terraform state?**

Terraform state is a **JSON file** (`terraform.tfstate`) that maps your configuration resources to real-world infrastructure objects. It:
- Tracks resource IDs, attributes, and metadata
- Enables Terraform to compute diffs between desired and actual state
- Records dependencies between resources
- Stores sensitive values (must be protected)

---

**Q32. Why is state important and what happens if it is lost?**

State is critical because:
- Without state, Terraform doesn't know what it has created
- Terraform would try to recreate all resources (causing duplicates or errors)
- Dependency graph cannot be built without state

If state is lost:
- Use `terraform import` to re-import existing resources
- Reconstruct state manually (painful and error-prone)
- This is why **remote state with locking** is essential

---

**Q33. What is remote state and why is it used?**

Remote state stores `terraform.tfstate` in a shared, centralized location instead of locally. Benefits:

| Benefit | Description |
|---|---|
| **Collaboration** | Multiple team members share the same state |
| **Locking** | Prevents concurrent applies (race conditions) |
| **Security** | State not stored on developer laptops |
| **Backup** | Cloud storage provides versioning and durability |
| **CI/CD** | Pipelines access state consistently |

---

**Q34. What are common remote state backends?**

| Backend | Notes |
|---|---|
| **S3 + DynamoDB** | Most popular for AWS; S3 stores state, DynamoDB handles locking |
| **Azure Blob Storage** | Native Azure option |
| **Google Cloud Storage** | Native GCP option |
| **Terraform Cloud / HCP Terraform** | HashiCorp's managed backend |
| **HTTP** | Generic HTTP backend |
| **Consul** | HashiCorp's service mesh (less common now) |
| **Kubernetes** | Store state in K8s Secrets (not recommended for production) |

---

**Q35. How do you configure an S3 remote backend?**

```hcl
terraform {
  backend "s3" {
    bucket         = "my-company-terraform-state"
    key            = "environments/production/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"    # For state locking
    kms_key_id     = "arn:aws:kms:eu-central-1:123456789:key/abc-123"
  }
}
```

```bash
# Create the S3 bucket and DynamoDB table first (bootstrapping)
aws s3 mb s3://my-company-terraform-state --region eu-central-1
aws s3api put-bucket-versioning \
  --bucket my-company-terraform-state \
  --versioning-configuration Status=Enabled

aws dynamodb create-table \
  --table-name terraform-state-lock \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region eu-central-1
```

---

**Q36. What is state locking?**

State locking prevents **multiple Terraform operations from running simultaneously** and corrupting the state file. When a `terraform apply` starts, it acquires a lock. If another operation tries to run, it waits or fails.

With S3 backend, locking uses DynamoDB. If a lock is stuck (e.g., interrupted apply):

```bash
# Force unlock (use with caution)
terraform force-unlock <LOCK_ID>
```

---

**Q37. What is `terraform state` and its subcommands?**

```bash
# List all resources in state
terraform state list

# Show details of a specific resource
terraform state show aws_instance.web

# Move a resource to a new address (rename without destroying)
terraform state mv aws_instance.web aws_instance.webserver

# Remove a resource from state (without destroying it)
terraform state rm aws_s3_bucket.old_bucket

# Pull remote state to local file
terraform state pull > state.json

# Push local state to remote
terraform state push state.json
```

---

**Q38. What is `terraform import`?**

`terraform import` brings **existing infrastructure** under Terraform management by adding it to the state file:

```bash
# Import existing AWS EC2 instance
terraform import aws_instance.web i-0a1b2c3d4e5f

# Import existing S3 bucket
terraform import aws_s3_bucket.mybucket my-existing-bucket

# Import Kubernetes Deployment
terraform import kubernetes_deployment.nginx default/nginx
```

After import:
1. The resource appears in state
2. You must write the matching `resource` block in your config
3. Run `terraform plan` to verify no unintended changes

---

**Q39. What are the risks of storing sensitive data in Terraform state?**

By default, Terraform state stores all resource attributes in **plaintext JSON** — including:
- Database passwords
- Private keys
- Access tokens

Mitigations:
- Enable **encryption at rest** on the backend (S3 KMS, Azure CMK)
- Restrict **access** to the state backend (IAM policies, RBAC)
- Use **`sensitive = true`** in outputs (prevents display, not storage)
- Use **Vault** or **Secrets Manager** for secrets — store references, not values

---

**Q40. What is `terraform refresh` and when is it used?**

`terraform refresh` (deprecated in favor of `terraform apply -refresh-only`) reconciles the state file with real-world infrastructure **without making changes**:

```bash
# Update state to match actual infrastructure
terraform apply -refresh-only

# Old command (deprecated but still works)
terraform refresh
```

Use when:
- Manual changes were made outside Terraform
- You want to detect drift without applying changes

---

## 5. Modules

---

**Q41. What is a Terraform module?**

A module is a **container for multiple resources** that are used together. Every Terraform configuration is a module (the root module). Child modules are called from the root module.

Benefits:
- Reusability — define once, use in many places
- Encapsulation — hide implementation details
- Consistency — enforce standards across teams
- DRY — Don't Repeat Yourself

---

**Q42. What is the structure of a Terraform module?**

```
modules/ec2-instance/
├── main.tf          # Resources
├── variables.tf     # Input variables
├── outputs.tf       # Output values
├── versions.tf      # Provider/Terraform version constraints
└── README.md        # Documentation
```

---

**Q43. How do you call a module?**

```hcl
# Call a local module
module "web_server" {
  source = "./modules/ec2-instance"

  instance_type = "t3.small"
  environment   = var.environment
  name          = "web"
}

# Call a Terraform Registry module
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
}

# Reference module output
output "vpc_id" {
  value = module.vpc.vpc_id
}
```

---

**Q44. What module sources are supported?**

| Source | Example |
|---|---|
| Local path | `"./modules/vpc"` |
| Terraform Registry | `"terraform-aws-modules/vpc/aws"` |
| GitHub (HTTPS) | `"github.com/myorg/tf-modules//vpc"` |
| GitHub (SSH) | `"git@github.com:myorg/tf-modules.git//vpc"` |
| S3 bucket | `"s3::https://s3.amazonaws.com/bucket/vpc.zip"` |
| Git (generic) | `"git::https://example.com/modules.git//vpc?ref=v1.2"` |

> The `//` double-slash separates the repo URL from the subdirectory path.

---

**Q45. What is the difference between root module and child module?**

| Root Module | Child Module |
|---|---|
| The top-level directory where `terraform apply` is run | Called from root or another module using `module` block |
| Has direct access to provider configs | Inherits provider from parent |
| Directly manages state | State managed under `module.<name>` prefix |
| One per working directory | Can have many |

---

**Q46. How do you pass data between modules?**

**Parent to child** — via module input variables:
```hcl
module "database" {
  source   = "./modules/rds"
  vpc_id   = module.vpc.vpc_id      # Pass VPC ID from vpc module
  env      = var.environment
}
```

**Child to parent** — via module outputs:
```hcl
# In modules/rds/outputs.tf
output "db_endpoint" {
  value = aws_db_instance.main.endpoint
}

# In root main.tf
resource "aws_ssm_parameter" "db_endpoint" {
  name  = "/myapp/db_endpoint"
  value = module.database.db_endpoint
}
```

---

**Q47. What is module versioning and why is it important?**

```hcl
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"    # Allow 5.x but not 6.x
}
```

Version constraints:
- `= 5.0.0` — exact version
- `~> 5.0` — allow patch updates (5.0.x)
- `~> 5` — allow minor updates (5.x)
- `>= 5.0, < 6.0` — range

Always pin module versions in production to ensure reproducibility.

---

**Q48. What is the Terraform Registry?**

The Terraform Registry (`registry.terraform.io`) is a public repository of:
- **Providers** — plugins for cloud services
- **Modules** — reusable configuration building blocks

Popular modules: `terraform-aws-modules/vpc/aws`, `terraform-aws-modules/eks/aws`, `terraform-google-modules/network/google`

```bash
# Modules can also be published privately in HCP Terraform
# or served from a private Git repository
```

---

**Q49. What are module best practices?**

- **Single responsibility**: Each module does one thing well (vpc, rds, eks)
- **Versioning**: Always version modules; pin versions in root config
- **Documentation**: Include `README.md` and `description` on all variables/outputs
- **Minimal surface area**: Only expose variables that need to be configurable
- **No provider configuration inside modules**: Pass provider via root config
- **Outputs**: Expose all IDs and ARNs that callers might need
- **Don't use remote state data sources inside modules**: Makes modules less reusable

---

**Q50. What is module composition vs. inheritance?**

Terraform uses **composition** (not inheritance). You build complex infrastructure by composing multiple simple modules:

```hcl
# Root module composes everything
module "network" { source = "./modules/vpc" }
module "compute" {
  source = "./modules/ec2"
  vpc_id = module.network.vpc_id
}
module "database" {
  source    = "./modules/rds"
  vpc_id    = module.network.vpc_id
  subnet_ids = module.network.private_subnet_ids
}
```

---

## 6. Terraform CLI & Workflow

---

**Q51. What is the core Terraform workflow?**

```
Write → Init → Plan → Apply → Destroy
```

```bash
# 1. Write HCL configuration files

# 2. Initialize — download providers, modules, configure backend
terraform init

# 3. Plan — preview changes (no infrastructure changes made)
terraform plan
terraform plan -out=tfplan    # Save plan to file

# 4. Apply — execute the plan
terraform apply
terraform apply tfplan        # Apply saved plan (no confirmation prompt)

# 5. Destroy — remove all managed infrastructure
terraform destroy
```

---

**Q52. What does `terraform init` do?**

```bash
terraform init
```

1. Reads `terraform` block in config
2. Downloads required **providers** to `.terraform/`
3. Downloads required **modules** to `.terraform/modules/`
4. Configures the **backend** (creates state if needed)
5. Creates `.terraform.lock.hcl` if not present

```bash
# Useful flags
terraform init -upgrade          # Upgrade providers to latest allowed version
terraform init -reconfigure      # Reconfigure backend (ignore cached state)
terraform init -backend=false    # Skip backend configuration
terraform init -migrate-state    # Migrate state to new backend
```

---

**Q53. What does `terraform plan` show?**

`terraform plan` shows a **preview** of changes without making any real changes:

```
# Output symbols:
+ Resource will be created
~ Resource will be updated in-place
- Resource will be destroyed
-/+ Resource will be destroyed and re-created (replacement)
<= Data source will be read

Plan: 3 to add, 1 to change, 0 to destroy.
```

```bash
terraform plan -out=plan.tfplan   # Save plan
terraform plan -var="env=prod"    # Pass variables
terraform plan -target=aws_instance.web  # Plan only specific resource
terraform plan -refresh=false     # Skip state refresh
```

---

**Q54. What is the difference between `terraform apply` and `terraform apply -auto-approve`?**

```bash
# Interactive — prompts for confirmation
terraform apply

# Non-interactive — auto-approves (for CI/CD)
terraform apply -auto-approve

# Apply a saved plan (no prompt needed — plan already approved)
terraform apply plan.tfplan
```

Always use saved plans in CI/CD to ensure what was reviewed is what gets applied.

---

**Q55. What does `terraform destroy` do?**

`terraform destroy` removes all infrastructure managed by the current configuration:

```bash
terraform destroy                           # Destroys all resources
terraform destroy -target=aws_instance.web # Destroy specific resource
terraform destroy -auto-approve            # Skip confirmation

# Alternative using apply
terraform apply -destroy
```

> Always run `terraform plan -destroy` first to preview what will be destroyed.

---

**Q56. What is `terraform fmt`?**

`terraform fmt` automatically formats Terraform configuration files to follow the **canonical style**:

```bash
terraform fmt             # Format files in current directory
terraform fmt -recursive  # Format all files recursively
terraform fmt -check      # Check formatting without making changes (CI)
terraform fmt -diff       # Show diff of formatting changes
```

Always run `terraform fmt` before committing — include it in CI checks.

---

**Q57. What is `terraform validate`?**

`terraform validate` checks the configuration for **syntax and logical errors** without accessing any remote APIs:

```bash
terraform validate
# Success: "The configuration is valid."
# Error: "Error: Reference to undeclared resource"
```

Validates:
- HCL syntax
- Resource argument types
- Required arguments
- References to existing resources/variables

Does NOT validate:
- Whether credentials are valid
- Whether resources actually exist
- Provider-specific API constraints

---

**Q58. What is `terraform output` and `terraform show`?**

```bash
# Show all defined outputs
terraform output

# Show specific output
terraform output vpc_id

# Show in JSON format
terraform output -json

# Show current state in human-readable format
terraform show

# Show a saved plan
terraform show plan.tfplan

# Show state as JSON
terraform show -json
```

---

**Q59. What is `-target` flag and when should it be used?**

`-target` limits plan/apply to specific resources:

```bash
terraform plan -target=aws_instance.web
terraform apply -target=module.database
terraform destroy -target=aws_s3_bucket.logs
```

> **Use sparingly** — `-target` creates partial applies that can leave state inconsistent. It's useful for debugging or recovering from errors, not for regular workflow. Avoid in production pipelines.

---

**Q60. What is `terraform taint` and `terraform untaint`?**

`terraform taint` marks a resource for **forced replacement** on the next apply (deprecated in Terraform 1.0+):

```bash
# Old way (deprecated)
terraform taint aws_instance.web

# New way — use -replace flag
terraform apply -replace=aws_instance.web
```

`-replace` is the modern replacement for `taint`. It destroys and recreates the resource without affecting others.

---

## 7. Workspaces, Backends & Remote Operations

---

**Q61. What are Terraform workspaces?**

Workspaces allow you to use **multiple state files** from the same configuration, enabling isolated environments:

```bash
# List workspaces
terraform workspace list

# Create a new workspace
terraform workspace new staging

# Switch workspace
terraform workspace select production

# Show current workspace
terraform workspace show

# Delete workspace (must switch away first)
terraform workspace delete staging
```

The default workspace is named `default`.

---

**Q62. How do you use the current workspace in configuration?**

```hcl
locals {
  instance_type = terraform.workspace == "production" ? "t3.large" : "t3.micro"
  environment   = terraform.workspace
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = local.instance_type

  tags = {
    Environment = local.environment
  }
}
```

Each workspace gets its own state file at:
`s3://my-bucket/terraform.tfstate.d/<workspace>/terraform.tfstate`

---

**Q63. What are the limitations of workspaces?**

- Workspaces share the **same backend configuration** — not suitable for truly separate accounts or regions
- Workspaces are not visible in the directory structure — easy to forget which workspace is active
- Not a replacement for separate state files per environment (e.g., separate directories)

**Recommendation**: For strong environment isolation (separate AWS accounts, different providers), use **separate directories** with separate backends rather than workspaces.

---

**Q64. What is the `remote` backend / HCP Terraform?**

HCP Terraform (formerly Terraform Cloud) is HashiCorp's managed service for:
- Remote state storage and locking
- Remote plan and apply execution (with audit logs)
- Policy enforcement (Sentinel/OPA)
- Team access controls
- VCS integration (auto-plan on PR, auto-apply on merge)
- Private module registry

```hcl
terraform {
  cloud {
    organization = "my-company"
    workspaces {
      name = "production"
    }
  }
}
```

---

**Q65. What is partial backend configuration?**

Backend configuration can be split between the `terraform` block and a separate file — useful for sensitive values or CI/CD:

```hcl
# main.tf — partial config (no sensitive values)
terraform {
  backend "s3" {
    bucket = "my-state-bucket"
    region = "eu-central-1"
  }
}
```

```bash
# Pass remaining config at init time
terraform init \
  -backend-config="key=prod/terraform.tfstate" \
  -backend-config="dynamodb_table=terraform-locks"
```

---

**Q66. How do you migrate state between backends?**

```bash
# Step 1: Update backend config in main.tf to new backend
# Step 2: Re-init with migration
terraform init -migrate-state

# Terraform will ask: "Do you want to copy existing state to the new backend?"
# Type 'yes'

# Step 3: Verify state was migrated
terraform state list
```

---

**Q67. What is `terraform_remote_state` data source?**

Reads **outputs from another Terraform state** — useful for sharing values between separate configurations:

```hcl
# In networking configuration (outputs vpc_id)
output "vpc_id" {
  value = aws_vpc.main.id
}

# In application configuration (reads networking state)
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "my-terraform-state"
    key    = "networking/terraform.tfstate"
    region = "eu-central-1"
  }
}

resource "aws_instance" "web" {
  vpc_security_group_ids = [data.terraform_remote_state.networking.outputs.vpc_id]
}
```

---

## 8. Functions, Expressions & Meta-Arguments

---

**Q68. What are the common Terraform built-in functions?**

```hcl
# String functions
length("hello")              # 5
upper("hello")               # "HELLO"
lower("HELLO")               # "hello"
trim("  hello  ", " ")       # "hello"
replace("hello world", "world", "terraform")  # "hello terraform"
format("Hello, %s!", "World")  # "Hello, World!"
join(", ", ["a", "b", "c"])  # "a, b, c"
split(",", "a,b,c")          # ["a", "b", "c"]

# Collection functions
length(["a", "b", "c"])      # 3
merge({a=1}, {b=2})          # {a=1, b=2}
flatten([[1,2],[3]])         # [1, 2, 3]
toset(["a", "b", "a"])       # {"a", "b"}
keys({a=1, b=2})             # ["a", "b"]
values({a=1, b=2})           # [1, 2]
contains(["a","b"], "a")     # true
lookup({a=1}, "a", 0)        # 1 (with default)

# Numeric functions
max(1, 2, 3)                 # 3
min(1, 2, 3)                 # 1
ceil(1.2)                    # 2
floor(1.9)                   # 1

# Encoding functions
base64encode("hello")        # "aGVsbG8="
base64decode("aGVsbG8=")     # "hello"
jsonencode({key = "value"})  # "{\"key\":\"value\"}"
jsondecode("{\"key\":\"value\"}")

# Filesystem functions
file("userdata.sh")          # Read file contents
filebase64("script.sh")      # Read as base64
templatefile("tmpl.tpl", {name = "world"})  # Render template

# IP functions
cidrsubnet("10.0.0.0/16", 8, 1)   # "10.0.1.0/24"
cidrhost("10.0.0.0/24", 5)        # "10.0.0.5"
```

---

**Q69. What is the conditional expression in Terraform?**

The ternary conditional operator:

```hcl
# condition ? true_value : false_value
instance_type = var.environment == "prod" ? "t3.large" : "t3.micro"
enable_ha     = var.environment == "prod" ? true : false
subnet_id     = var.use_private ? aws_subnet.private.id : aws_subnet.public.id
```

---

**Q70. What is `for_each` meta-argument?**

`for_each` creates **multiple instances** of a resource from a map or set:

```hcl
variable "buckets" {
  default = {
    logs    = "eu-central-1"
    backups = "eu-west-1"
    assets  = "us-east-1"
  }
}

resource "aws_s3_bucket" "this" {
  for_each = var.buckets
  bucket   = "mycompany-${each.key}"
  # each.key   = "logs", "backups", "assets"
  # each.value = "eu-central-1", etc.

  tags = {
    Purpose = each.key
    Region  = each.value
  }
}

# Reference: aws_s3_bucket.this["logs"].arn
```

---

**Q71. What is the `count` meta-argument?**

`count` creates **N identical instances** of a resource:

```hcl
resource "aws_instance" "web" {
  count         = var.instance_count
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  tags = {
    Name = "web-${count.index}"   # count.index = 0, 1, 2...
  }
}

# Reference: aws_instance.web[0].id, aws_instance.web[1].id
# All instances: aws_instance.web[*].id
```

---

**Q72. What is the difference between `count` and `for_each`?**

| Feature | `count` | `for_each` |
|---|---|---|
| Input | Number | Map or Set of strings |
| Identifier | Integer index | Map key |
| Removing middle item | Shifts indices → unexpected changes | Only removes specific key |
| Referencing | `resource[0]`, `resource[*]` | `resource["key"]` |
| Best for | Identical resources | Resources with distinct configs |
| Recommended | Only for simple cases | Preferred in most situations |

> **Prefer `for_each`** — removing an item from a `count` list shifts indices and can cause unintended destroy/recreate of other resources.

---

**Q73. What is the `for` expression?**

`for` expressions transform collections:

```hcl
# Transform a list
variable "names" {
  default = ["alice", "bob", "charlie"]
}

locals {
  upper_names = [for name in var.names : upper(name)]
  # Result: ["ALICE", "BOB", "CHARLIE"]

  # With filtering
  long_names = [for name in var.names : name if length(name) > 4]
  # Result: ["alice", "charlie"]

  # Map transformation
  name_lengths = {for name in var.names : name => length(name)}
  # Result: {alice = 5, bob = 3, charlie = 7}
}
```

---

**Q74. What is the `dynamic` block?**

`dynamic` generates repeated nested blocks dynamically:

```hcl
variable "ingress_rules" {
  default = [
    { from_port = 80,  to_port = 80,  protocol = "tcp" },
    { from_port = 443, to_port = 443, protocol = "tcp" },
    { from_port = 22,  to_port = 22,  protocol = "tcp" },
  ]
}

resource "aws_security_group" "web" {
  name = "web-sg"

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      from_port   = ingress.value.from_port
      to_port     = ingress.value.to_port
      protocol    = ingress.value.protocol
      cidr_blocks = ["0.0.0.0/0"]
    }
  }
}
```

---

**Q75. What is `lifecycle` meta-argument?**

`lifecycle` controls how Terraform handles resource creation, updates, and deletion:

```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  lifecycle {
    # Prevent destruction of this resource
    prevent_destroy = true

    # Create new resource before destroying old one (zero-downtime replacement)
    create_before_destroy = true

    # Ignore changes to specific attributes
    ignore_changes = [
      ami,                    # Don't replace if AMI changes
      tags["LastModified"],   # Ignore auto-updated tag
    ]

    # Custom condition — fail if violated
    precondition {
      condition     = var.environment != "prod" || var.instance_type == "t3.large"
      error_message = "Production must use t3.large."
    }
  }
}
```

---

**Q76. What is `templatefile()` function?**

Renders a template file with variable substitutions:

```bash
# userdata.tpl
#!/bin/bash
echo "Hello, ${name}!"
apt-get install -y ${package}
```

```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"
  user_data     = templatefile("userdata.tpl", {
    name    = "World"
    package = "nginx"
  })
}
```

---

**Q77. What are `precondition` and `postcondition` checks?**

Custom validation checks during plan and apply:

```hcl
resource "aws_instance" "web" {
  ami           = var.ami_id
  instance_type = var.instance_type

  lifecycle {
    precondition {
      condition     = data.aws_ami.selected.architecture == "x86_64"
      error_message = "Only x86_64 AMIs are supported."
    }

    postcondition {
      condition     = self.public_ip != ""
      error_message = "Instance must have a public IP."
    }
  }
}
```

---

## 9. Advanced Terraform & Best Practices

---

**Q78. What is Terragrunt and why is it used?**

Terragrunt is a **thin wrapper around Terraform** that adds:
- DRY configurations (avoid repeating backend, provider config)
- Automatic remote state management
- Dependency management between Terraform modules
- Environment-specific variable injection

```hcl
# terragrunt.hcl
remote_state {
  backend = "s3"
  config = {
    bucket  = "my-terraform-state"
    key     = "${path_relative_to_include()}/terraform.tfstate"
    region  = "eu-central-1"
    encrypt = true
  }
}

terraform {
  source = "git::https://github.com/myorg/modules.git//vpc?ref=v1.2.0"
}

inputs = {
  environment = "production"
  cidr_block  = "10.0.0.0/16"
}
```

---

**Q79. What is Terraform's dependency graph and how is it built?**

Terraform builds a **Directed Acyclic Graph (DAG)** of all resources and their dependencies:

1. Each resource is a node
2. References between resources create directed edges
3. Terraform applies resources in parallel where possible (no dependencies)
4. Resources with dependencies are applied in order

```bash
# Visualize the dependency graph
terraform graph | dot -Tsvg > graph.svg
```

---

**Q80. What are provisioners in Terraform and when should they be used?**

Provisioners run scripts on local or remote machines after resource creation:

```hcl
resource "aws_instance" "web" {
  ami           = data.aws_ami.amazon_linux.id
  instance_type = "t3.micro"

  # Run script remotely via SSH
  provisioner "remote-exec" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y nginx",
    ]
    connection {
      type        = "ssh"
      user        = "ubuntu"
      private_key = file("~/.ssh/id_rsa")
      host        = self.public_ip
    }
  }

  # Run script locally after creation
  provisioner "local-exec" {
    command = "echo ${self.public_ip} >> inventory.txt"
  }
}
```

> **Avoid provisioners when possible** — they are a last resort. Use user_data, cloud-init, Ansible, or baked AMIs instead. Provisioners break Terraform's declarative model.

---

**Q81. What is a `moved` block in Terraform?**

The `moved` block allows **renaming or moving resources** without destroying and recreating them:

```hcl
# Rename a resource
moved {
  from = aws_instance.web
  to   = aws_instance.webserver
}

# Move resource into a module
moved {
  from = aws_instance.web
  to   = module.compute.aws_instance.web
}

# Move resource out of a module
moved {
  from = module.old_module.aws_s3_bucket.assets
  to   = aws_s3_bucket.assets
}
```

Run `terraform plan` to verify, then `terraform apply`. After apply, the `moved` block can be removed.

---

**Q82. What is the `check` block in Terraform?**

`check` blocks define **assertions** that warn (but don't fail) when violated — useful for health checks after deployment:

```hcl
check "website_health" {
  data "http" "website" {
    url = "https://${aws_lb.web.dns_name}/health"
  }

  assert {
    condition     = data.http.website.status_code == 200
    error_message = "Website health check failed! Got ${data.http.website.status_code}"
  }
}
```

Introduced in Terraform 1.5. Unlike `precondition`/`postcondition`, `check` failures only produce warnings.

---

**Q83. What are Terraform provider development best practices?**

When writing custom providers:
- Use the Terraform Plugin Framework (not older Plugin SDK)
- Implement full CRUD for all resources
- Handle eventual consistency (retry logic)
- Mark sensitive attributes with `Sensitive: true`
- Write acceptance tests using `resource.Test`
- Follow the provider naming convention: `terraform-provider-<name>`

---

**Q84. What is Sentinel in Terraform?**

Sentinel is HashiCorp's **policy-as-code framework** available in HCP Terraform and Terraform Enterprise. It enforces policies before `terraform apply`:

```python
# Sentinel policy example
import "tfplan/v2" as tfplan

# Deny creation of instances larger than t3.large
main = rule {
  all tfplan.resource_changes as _, changes {
    changes.type is "aws_instance" and
    changes.change.after.instance_type not in ["t3.xlarge", "t3.2xlarge", "m5.xlarge"]
  }
}
```

Open-source alternative: **OPA (Open Policy Agent)** with `conftest`.

---

**Q85. How do you test Terraform configurations?**

| Tool | Type | Description |
|---|---|---|
| `terraform validate` | Static | Syntax and type checking |
| `terraform plan` | Static | Preview changes |
| **Terratest** | Integration | Go-based testing framework; deploys real infrastructure |
| **kitchen-terraform** | Integration | Test Kitchen plugin |
| **Checkov** | Security scan | Static analysis for security misconfigs |
| **tfsec** | Security scan | Lightweight security scanner |
| **infracost** | Cost estimation | Estimate cost of planned changes |
| **conftest/OPA** | Policy | Policy testing with Rego |

```go
// Terratest example
func TestVpcModule(t *testing.T) {
    opts := &terraform.Options{
        TerraformDir: "../modules/vpc",
        Vars: map[string]interface{}{
            "cidr_block": "10.0.0.0/16",
        },
    }
    defer terraform.Destroy(t, opts)
    terraform.InitAndApply(t, opts)

    vpcId := terraform.Output(t, opts, "vpc_id")
    assert.NotEmpty(t, vpcId)
}
```

---

**Q86. What is `terraform console` and when is it useful?**

An interactive REPL for evaluating Terraform expressions:

```bash
terraform console

# Inside console:
> length(["a", "b", "c"])
3

> cidrsubnet("10.0.0.0/16", 8, 1)
"10.0.1.0/24"

> upper("hello")
"HELLO"

> var.environment
"production"

# Great for testing expressions and functions before putting them in config
```

---

**Q87. What is `terraform graph` and what is it used for?**

```bash
# Generate dependency graph in DOT format
terraform graph

# Visualize (requires graphviz)
terraform graph | dot -Tpng > graph.png
terraform graph | dot -Tsvg > graph.svg

# Filter for specific plan
terraform graph -plan=plan.tfplan
```

Useful for:
- Understanding complex resource dependencies
- Debugging dependency cycles
- Documentation

---

**Q88. What are Terraform best practices for team environments?**

**Structure:**
- Separate state per environment (different backends or workspace)
- Separate root modules per environment or use Terragrunt
- Store modules in a separate versioned repo

**State:**
- Always use remote state with locking in teams
- Enable versioning and encryption on state backend
- Never commit `.tfstate` files to Git

**Code quality:**
- Run `terraform fmt`, `terraform validate`, `tfsec` in CI
- Use `terraform plan -out=plan.tffile` in CI; apply the plan artifact
- Pin provider and module versions

**Security:**
- Never hardcode credentials — use IAM roles, environment vars, or secret managers
- Mark sensitive variables and outputs
- Use least-privilege IAM roles for Terraform execution

**CI/CD:**
- Plan on PR/MR; apply on merge to main
- Use `-auto-approve` only in fully automated pipelines with guardrails
- Store plan output as CI artifact for review

---

**Q89. What is the difference between `terraform.tfvars` and `variables.tf`?**

| `variables.tf` | `terraform.tfvars` |
|---|---|
| Declares variable names, types, descriptions, defaults | Provides actual values for variables |
| Part of the module code | Environment-specific configuration |
| Committed to Git | May or may not be committed (depends on sensitivity) |
| `variable "env" { type = string }` | `env = "production"` |

---

**Q90. How do you handle Terraform state in a CI/CD pipeline?**

```yaml
# GitLab CI example
stages:
  - validate
  - plan
  - apply

variables:
  TF_ROOT: ${CI_PROJECT_DIR}/infrastructure
  TF_STATE_NAME: ${CI_ENVIRONMENT_NAME}

validate:
  stage: validate
  script:
    - terraform init -backend=false
    - terraform validate
    - terraform fmt -check -recursive

plan:
  stage: plan
  script:
    - terraform init
    - terraform plan -out=plan.tfplan
  artifacts:
    paths:
      - plan.tfplan
    expire_in: 1 hour

apply:
  stage: apply
  script:
    - terraform init
    - terraform apply plan.tfplan
  when: manual    # Manual gate for production
  environment:
    name: production
```

---

## 10. Scenario-Based & Real-World Questions

---

**Q91. SCENARIO: A colleague ran `terraform apply` without a plan file and accidentally destroyed a database. How do you recover?**

```bash
# 1. Check if DB has automated backups (RDS snapshot, Azure backup)
aws rds describe-db-snapshots --db-instance-identifier my-db

# 2. Restore from snapshot
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier my-db-restored \
  --db-snapshot-identifier my-db-snapshot-2024

# 3. Re-import the restored resource into Terraform state
terraform import aws_db_instance.main my-db-restored

# 4. Update Terraform config to match restored resource
# 5. Run terraform plan to ensure no further changes

# Prevention:
# - Always use -out plan file, apply the plan in CI
# - Enable prevent_destroy = true on databases
# - Use separate IAM roles with limited destroy permissions
# - Set up S3 state versioning to roll back state if needed
```

---

**Q92. SCENARIO: Two team members ran `terraform apply` simultaneously. What happens and how do you prevent it?**

With remote state locking (S3 + DynamoDB):
- Second apply fails immediately: `"Error: Error acquiring the state lock"`
- DynamoDB record shows lock details: who locked it and when

```bash
# If lock is stuck (interrupted apply)
terraform force-unlock <LOCK_ID>

# Prevention:
# 1. Use remote backend with locking (always)
# 2. Use CI/CD pipeline as the only way to apply
# 3. Restrict direct terraform access to production
# 4. Use HCP Terraform which handles this natively
```

---

**Q93. SCENARIO: You need to refactor Terraform code to rename a resource without destroying and recreating it. How?**

```hcl
# Old code
resource "aws_instance" "web" { ... }

# New code
resource "aws_instance" "webserver" { ... }

# Add moved block
moved {
  from = aws_instance.web
  to   = aws_instance.webserver
}
```

```bash
# Verify no destroy/create
terraform plan
# Should show: "aws_instance.web has moved to aws_instance.webserver"
# Plan: 0 to add, 0 to change, 0 to destroy

terraform apply
# After apply, remove the moved block
```

---

**Q94. SCENARIO: You have an existing AWS VPC not managed by Terraform. How do you bring it under Terraform management?**

```bash
# Step 1: Write the resource block in config matching the existing VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}

# Step 2: Import the existing VPC
terraform import aws_vpc.main vpc-0a1b2c3d4e5f

# Step 3: Run plan to see if any drift exists
terraform plan
# If plan shows changes, update your config to match actual state

# Step 4: Apply to reconcile any drift
terraform apply
```

---

**Q95. SCENARIO: `terraform plan` shows a resource will be replaced (destroyed + created) but you want in-place update. How do you investigate?**

```bash
# 1. Check which argument is forcing replacement
terraform plan -detailed-exitcode
# Look for: "# forces replacement" annotation in plan output

# 2. Common causes:
# - Changing an immutable argument (e.g., DB subnet_group_name, instance AZ)
# - Changing AMI (can use lifecycle.ignore_changes = [ami])
# - Changing key_name on EC2

# 3. Solutions:
# Option A — Use create_before_destroy if replacement is unavoidable
lifecycle {
  create_before_destroy = true
}

# Option B — Ignore the changing attribute
lifecycle {
  ignore_changes = [ami]
}

# Option C — Use -replace selectively and during maintenance window
terraform apply -replace=aws_instance.web
```

---

**Q96. SCENARIO: How do you structure Terraform for a multi-environment, multi-region AWS setup?**

**Recommended structure:**

```
terraform/
├── modules/
│   ├── vpc/
│   ├── eks/
│   └── rds/
├── environments/
│   ├── dev/
│   │   ├── eu-central-1/
│   │   │   ├── main.tf
│   │   │   ├── variables.tf
│   │   │   ├── terraform.tfvars
│   │   │   └── backend.tf
│   │   └── us-east-1/
│   ├── staging/
│   │   └── eu-central-1/
│   └── production/
│       ├── eu-central-1/
│       └── us-east-1/
└── global/
    ├── iam/
    └── route53/
```

Each environment/region directory has its own:
- Backend configuration (separate state files)
- `terraform.tfvars` with environment-specific values
- Calls to shared modules with environment-specific parameters

---

**Q97. SCENARIO: You need to create 10 similar S3 buckets with slightly different configurations. What is the best approach?**

```hcl
# Define bucket configurations as a map
variable "buckets" {
  type = map(object({
    versioning  = bool
    logging     = bool
    region      = string
  }))
  default = {
    "logs"    = { versioning = false, logging = false, region = "eu-central-1" }
    "backups" = { versioning = true,  logging = false, region = "eu-central-1" }
    "assets"  = { versioning = false, logging = true,  region = "us-east-1"   }
  }
}

resource "aws_s3_bucket" "this" {
  for_each = var.buckets
  bucket   = "mycompany-${each.key}-${local.account_id}"
}

resource "aws_s3_bucket_versioning" "this" {
  for_each = { for k, v in var.buckets : k => v if v.versioning }
  bucket   = aws_s3_bucket.this[each.key].id
  versioning_configuration {
    status = "Enabled"
  }
}
```

---

**Q98. SCENARIO: A `terraform apply` fails halfway through. What is the state of your infrastructure and how do you recover?**

Terraform applies changes **sequentially** (with parallelism for independent resources). If it fails halfway:
- Some resources were created successfully (in state)
- Some resources failed (not in state or partially created)
- State reflects what was successfully applied so far

Recovery:
```bash
# 1. Fix the underlying issue (wrong config, permission, quota)

# 2. Re-run terraform apply — it will only apply what's missing
terraform apply

# 3. If state is inconsistent, use terraform state commands
terraform state list           # See what's in state
terraform state show <resource> # Inspect resource
terraform state rm <resource>   # Remove orphaned resource from state

# 4. Import manually created resources if needed
terraform import aws_instance.web i-0abc123
```

---

**Q99. SCENARIO: How do you pass secrets to Terraform without hardcoding them?**

**Option 1 — Environment variables:**
```bash
export TF_VAR_db_password=$(aws secretsmanager get-secret-value \
  --secret-id my-db-password --query SecretString --output text)
terraform apply
```

**Option 2 — AWS Secrets Manager data source:**
```hcl
data "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "myapp/prod/db-password"
}

resource "aws_db_instance" "main" {
  password = jsondecode(data.aws_secretsmanager_secret_version.db_password.secret_string)["password"]
}
```

**Option 3 — Vault provider:**
```hcl
provider "vault" {
  address = "https://vault.example.com"
}

data "vault_generic_secret" "db" {
  path = "secret/myapp/db"
}

resource "aws_db_instance" "main" {
  password = data.vault_generic_secret.db.data["password"]
}
```

**Option 4 — CI/CD secrets injection:**
Pass secrets as CI environment variables — never store in Git or state if avoidable.

---

**Q100. SCENARIO: How do you implement a GitOps workflow for Terraform?**

```
Developer creates branch
        ↓
Makes Terraform changes
        ↓
Opens PR/MR
        ↓
CI runs: fmt → validate → tfsec → plan
    - terraform fmt -check
    - terraform validate
    - tfsec .
    - terraform plan -out=plan.tfplan
    - Post plan output as PR comment (using tfcmt or similar)
        ↓
Team reviews plan output in PR
        ↓
PR approved + merged to main
        ↓
CD pipeline runs:
    - terraform init
    - terraform apply plan.tfplan  (applies the reviewed plan)
        ↓
Notification sent (Slack) with apply summary
```

Tools: **Atlantis** (self-hosted GitOps for Terraform), **HCP Terraform** VCS integration, or custom CI/CD pipeline.

---

**Q101. What is Atlantis and how does it work?**

Atlantis is an open-source tool that implements a **GitOps workflow for Terraform** using pull requests:

1. Developer opens a PR with Terraform changes
2. Atlantis auto-runs `terraform plan` and posts output as PR comment
3. Reviewer approves the plan in the PR comment (`atlantis apply`)
4. Atlantis runs `terraform apply` and posts results
5. PR is merged

```yaml
# atlantis.yaml
version: 3
projects:
- name: production-vpc
  dir: environments/production/vpc
  workspace: default
  autoplan:
    when_modified: ["*.tf", "../modules/**/*.tf"]
    enabled: true
```

---

**Q102. How do you use Terraform with Kubernetes?**

```hcl
provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_cert)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    command     = "aws"
  }
}

resource "kubernetes_namespace" "production" {
  metadata {
    name = "production"
    labels = {
      env = "production"
    }
  }
}

resource "kubernetes_deployment" "nginx" {
  metadata {
    name      = "nginx"
    namespace = kubernetes_namespace.production.metadata[0].name
  }
  spec {
    replicas = 3
    selector {
      match_labels = { app = "nginx" }
    }
    template {
      metadata { labels = { app = "nginx" } }
      spec {
        container {
          name  = "nginx"
          image = "nginx:1.25"
        }
      }
    }
  }
}
```

---

**Q103. What is `terraform apply -refresh=false` and when is it used?**

Skips the state refresh step during apply — Terraform uses cached state instead of querying APIs:

```bash
terraform apply -refresh=false
```

Use when:
- You trust the state is accurate (no out-of-band changes)
- API rate limits are an issue (large number of resources)
- Speed is critical in CI/CD

Avoid when: you suspect drift between state and actual infrastructure.

---

**Q104. What are common Terraform anti-patterns?**

| Anti-pattern | Problem | Solution |
|---|---|---|
| Hardcoding values | Not reusable | Use variables |
| Monolithic root module | Hard to manage, slow plans | Split into multiple modules |
| No remote state | No team collaboration | Always use remote backend |
| Using `count` for unique resources | Index shifting causes surprises | Use `for_each` with meaningful keys |
| Storing secrets in tfvars | Security risk | Use secret managers |
| No version pins | Breaking changes from updates | Pin provider and module versions |
| Provisioners for everything | Imperative, fragile | Use cloud-init, user_data, Ansible |
| Giant `terraform.tfvars` | All envs mixed up | Separate vars files per env |
| Not using modules | Code duplication | Extract reusable modules |
| Committing `.terraform/` dir | Bloats repo | Add to `.gitignore` |

---

**Q105. What should be in `.gitignore` for a Terraform project?**

```gitignore
# Local Terraform directory
.terraform/

# State files (never commit local state)
*.tfstate
*.tfstate.backup
*.tfstate.d/

# Variable files that may contain secrets
*.tfvars
!terraform.tfvars.example   # Commit example without real values

# Plan files
*.tfplan
plan.out

# Override files (local overrides)
override.tf
override.tf.json
*_override.tf

# Crash log
crash.log

# Terraform lock file — COMMIT THIS
# .terraform.lock.hcl  ← do NOT add to .gitignore
```

---

**Q106. What is the difference between `terraform destroy` and removing resources from config?**

| `terraform destroy` | Remove resource from config |
|---|---|
| Explicitly destroys all managed resources | On next `terraform apply`, resource is pruned |
| Clears state completely | Resource remains until apply runs |
| Immediate | Applied on next pipeline run |
| Use for full environment teardown | Use when deprecating a specific resource |

When you remove a resource from config and run `terraform apply`, Terraform sees it as "exists in state but not in config" → destroys it.

---

**Q107. What is `terraform providers` command?**

```bash
# Show required providers and their sources
terraform providers

# Show providers used in a specific plan
terraform providers lock \
  -platform=linux_amd64 \
  -platform=darwin_arm64

# Mirror providers to a local directory (for air-gapped environments)
terraform providers mirror ./vendor
```

---

**Q108. How do you handle breaking changes in provider updates?**

```hcl
# Pin to current major version to avoid breaking changes
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"    # Allows 5.x, blocks 6.x
    }
  }
}
```

```bash
# Test provider upgrade in a non-prod environment first
terraform init -upgrade   # In dev environment

# Review changelog for breaking changes
# Update config to accommodate breaking changes
# Then upgrade in staging → production

# Lock file ensures all team members use same version
git add .terraform.lock.hcl
```

---

**Q109. What are the key Terraform interview questions asked specifically about AWS?**

Common AWS + Terraform scenarios:

```hcl
# 1. Create VPC with public and private subnets
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
  cidr    = "10.0.0.0/16"
  azs     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]
  enable_nat_gateway = true
  single_nat_gateway = false   # One NAT per AZ for HA
}

# 2. EKS cluster
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.0"
  cluster_name    = "my-cluster"
  cluster_version = "1.28"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets
  eks_managed_node_groups = {
    main = {
      instance_types = ["t3.medium"]
      min_size       = 1
      max_size       = 5
      desired_size   = 2
    }
  }
}
```

---

**Q110. What is `terraform show -json` used for and how is it parsed?**

```bash
# Show current state as JSON
terraform show -json > state.json

# Show plan as JSON (for programmatic processing)
terraform plan -out=plan.tfplan
terraform show -json plan.tfplan > plan.json

# Parse with jq
cat plan.json | jq '.resource_changes[] | select(.change.actions[] == "create")'
cat plan.json | jq '[.resource_changes[] | .type] | unique'
```

Useful for:
- Custom plan parsers in CI
- Cost estimation tools (infracost reads plan JSON)
- Policy enforcement (OPA/conftest reads plan JSON)
- Audit and reporting

---

**Q111. What is the `required_providers` block and why is it important?**

```hcl
terraform {
  required_version = ">= 1.6.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.31"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.24"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
  }
}
```

Without `required_providers`:
- Terraform assumes provider is from `hashicorp/<name>`
- No version constraint = always downloads latest (breaking changes risk)
- Team members may use different provider versions

Always declare `required_providers` with version constraints in every configuration.

---

**Q112. How do you handle Terraform in an air-gapped (no internet) environment?**

```bash
# Mirror providers to a local directory
terraform providers mirror /opt/terraform-mirror

# Or download manually and set up a local registry

# Configure Terraform to use local mirror
cat > ~/.terraformrc <<EOF
provider_installation {
  filesystem_mirror {
    path    = "/opt/terraform-mirror"
    include = ["registry.terraform.io/*/*"]
  }
  direct {
    exclude = ["registry.terraform.io/*/*"]
  }
}
EOF

# Use a private registry (Artifactory, Nexus)
terraform {
  required_providers {
    aws = {
      source = "my-registry.example.com/hashicorp/aws"
    }
  }
}
```

---

**Q113. What is the `ephemeral` resource type in Terraform (1.10+)?**

Ephemeral resources are **read-only, not stored in state** — designed for short-lived values like tokens and dynamic secrets:

```hcl
ephemeral "aws_secretsmanager_secret_version" "db_password" {
  secret_id = "my-db-password"
}

# The secret value is never written to state
# Fetched fresh on each plan/apply
```

Unlike data sources (which are stored in state), ephemeral resources leave no trace — ideal for secrets.

---

**Q114. What is `terraform test` (Terraform 1.6+)?**

Native testing framework for Terraform modules:

```hcl
# tests/vpc.tftest.hcl
run "create_vpc" {
  variables {
    cidr_block  = "10.0.0.0/16"
    environment = "test"
  }

  assert {
    condition     = aws_vpc.main.cidr_block == "10.0.0.0/16"
    error_message = "VPC CIDR block should be 10.0.0.0/16"
  }

  assert {
    condition     = length(aws_subnet.public) == 2
    error_message = "Should create 2 public subnets"
  }
}
```

```bash
terraform test
# Runs tests, creates real infrastructure, validates assertions, destroys
```

---

**Q115. What is `tostring`, `tonumber`, `tobool` and type conversion in Terraform?**

```hcl
# Explicit type conversion
tostring(42)           # "42"
tostring(true)         # "true"
tonumber("42")         # 42
tonumber("3.14")       # 3.14
tobool("true")         # true
tobool("false")        # false
tolist(toset(["b","a","c"]))  # Converts set to list (sorted)
toset(["a","b","a"])   # {"a","b"} — deduplicates

# Type checking
try(tonumber("abc"), 0)   # Returns 0 if conversion fails
can(tonumber("42"))       # true — can this be converted?
can(tonumber("abc"))      # false
```

---

**Q116. How do you use `try()` and `can()` functions?**

```hcl
# try() - return first successful expression, or last if all fail
locals {
  # Safe attribute access — returns empty string if attribute doesn't exist
  db_endpoint = try(aws_db_instance.main.endpoint, "")

  # Try parsing JSON, fallback to default
  config = try(jsondecode(var.config_json), {})
}

# can() - returns bool whether expression can be evaluated without error
variable "optional_port" {
  default = null
}

locals {
  port = can(var.optional_port + 0) ? var.optional_port : 80
}
```

---

**Q117. What is the Terraform `templatestring` function (1.9+)?**

```hcl
# Inline template rendering (alternative to templatefile for small templates)
locals {
  user_data = templatestring(<<-EOT
    #!/bin/bash
    echo "Hello, ${name}!"
    export ENV="${environment}"
  EOT
  , {
    name        = var.server_name
    environment = var.environment
  })
}
```

---

**Q118. How do you organize Terraform code for a large platform team?**

**Repository structure:**
```
platform-terraform/
├── modules/                    # Shared internal modules
│   ├── vpc/
│   ├── eks/
│   ├── rds/
│   └── monitoring/
├── live/                       # Live infrastructure (Terragrunt or plain)
│   ├── dev/
│   │   ├── eu-central-1/
│   │   └── us-east-1/
│   ├── staging/
│   └── production/
├── global/                     # Account-level resources
│   ├── iam/
│   ├── route53/
│   └── ecr/
└── tests/                      # Terratest or terraform test files
```

**Team workflows:**
- Modules versioned and published to private registry or Git tags
- Each team calls approved module versions
- Platform team reviews/approves PRs that change shared modules
- Separate pipelines per environment with approval gates for production

---

**Q119. What are the most important Terraform CLI commands to memorize?**

```bash
# Core workflow
terraform init
terraform fmt -recursive
terraform validate
terraform plan -out=plan.tfplan
terraform apply plan.tfplan
terraform destroy

# State management
terraform state list
terraform state show <resource>
terraform state mv <from> <to>
terraform state rm <resource>
terraform import <resource> <id>

# Debugging
terraform console
terraform graph
terraform show
terraform output -json
terraform providers

# Advanced
terraform apply -replace=<resource>
terraform apply -target=<resource>
terraform apply -refresh-only
terraform force-unlock <lock-id>
terraform workspace list/new/select
```

---

**Q120. What are the top Terraform interview questions asked in German DevOps roles?**

Based on DACH region DevOps hiring trends:

1. **"Explain Terraform state and why remote state is important"** — Always asked
2. **"How do you structure Terraform for multiple environments?"** — Workspaces vs. directories
3. **"What is the difference between count and for_each?"** — Index vs key, when to use each
4. **"How do you handle secrets in Terraform?"** — Vault, AWS SM, sensitive variables
5. **"How do you prevent someone from accidentally destroying production?"** — prevent_destroy, CI/CD gates, separate state
6. **"What happens if two people run terraform apply at the same time?"** — State locking
7. **"How do you test Terraform code?"** — Terratest, tfsec, validate, plan review
8. **"How do you import existing infrastructure into Terraform?"** — terraform import
9. **"What is a moved block and when do you use it?"** — Resource refactoring without destroy
10. **"How do you structure modules and what goes in a module?"** — Variables, outputs, main, versions

---

*End of Terraform Interview Q&A — 120 Questions (All Levels)*

---

## What's Next in the Series?

| Priority | Tool | Status |
|---|---|---|
| ✅ Done | Kubernetes (480 Q) | Complete |
| ✅ Done | ArgoCD (120 Q) | Complete |
| ✅ Done | Terraform (120 Q) | Complete |
| 3️⃣ Next | Helm | Ready to build |
| 4️⃣ After | OpenShift EX280 | Ready to build |
