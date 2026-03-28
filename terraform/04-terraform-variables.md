# 📊 Variables, Outputs & Locals

Parameterizing Terraform configurations — inputs, computed values, and exported results.

---

## 📚 Table of Contents

- [1. Input Variables](#1-input-variables)
- [2. Variable Files & Precedence](#2-variable-files--precedence)
- [3. Locals](#3-locals)
- [4. Output Values](#4-output-values)
- [5. Sensitive Values](#5-sensitive-values)
- [6. Variable Validation](#6-variable-validation)
- [Cheatsheet](#cheatsheet)

---

## 1. Input Variables

Variables make your configuration reusable and environment-specific.

### Variable declaration

```hcl
# variables.tf

# Simple variable
variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "eu-central-1"
}

# Required variable (no default — must be provided)
variable "environment" {
  description = "Deployment environment (development, staging, production)"
  type        = string
}

# Number
variable "instance_count" {
  description = "Number of EC2 instances"
  type        = number
  default     = 1
}

# Boolean
variable "enable_deletion_protection" {
  description = "Enable deletion protection on the database"
  type        = bool
  default     = false
}

# List
variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
  default     = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
}

# Map
variable "tags" {
  description = "Additional tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Object
variable "database_config" {
  description = "Database configuration"
  type = object({
    instance_class    = string
    allocated_storage = number
    multi_az          = optional(bool, false)
    backup_days       = optional(number, 7)
  })
  default = {
    instance_class    = "db.t3.micro"
    allocated_storage = 20
  }
}

# List of objects
variable "subnet_configs" {
  description = "Subnet configurations"
  type = list(object({
    cidr_block        = string
    availability_zone = string
    public            = bool
  }))
  default = []
}

# Sensitive variable (masked in plan/apply output)
variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}
```

---

## 2. Variable Files & Precedence

### Precedence (lowest to highest)

```
1. Default values in variable declarations
2. terraform.tfvars (auto-loaded)
3. terraform.tfvars.json (auto-loaded)
4. *.auto.tfvars (auto-loaded, alphabetical)
5. -var-file=file.tfvars (command line)
6. -var="key=value" (command line, highest)
```

### .tfvars files

```hcl
# terraform.tfvars (default, auto-loaded)
region      = "eu-central-1"
environment = "development"
instance_count = 1

# prod.tfvars (explicit file)
region      = "eu-central-1"
environment = "production"
instance_count = 5
enable_deletion_protection = true
database_config = {
  instance_class    = "db.t3.medium"
  allocated_storage = 100
  multi_az          = true
  backup_days       = 14
}
tags = {
  CostCenter = "platform"
  Owner      = "platform-team"
}
```

```bash
# Apply with specific var file
terraform plan -var-file=prod.tfvars
terraform apply -var-file=prod.tfvars

# Multiple var files (later overrides earlier)
terraform apply \
  -var-file=base.tfvars \
  -var-file=prod.tfvars

# Override single variable
terraform apply -var="environment=production" -var="instance_count=3"

# From environment variables (TF_VAR_ prefix)
export TF_VAR_db_password="secret123"
export TF_VAR_environment="production"
terraform apply
```

### Environment variable pattern

```bash
# Use TF_VAR_ for sensitive values — never in .tfvars files
export TF_VAR_db_password=$(aws ssm get-parameter --name /prod/db/password --with-decryption --query Parameter.Value --output text)
```

---

## 3. Locals

Locals are named expressions within a module — computed once, referenced many times.

```hcl
# locals.tf

locals {
  # Simple computed values
  name_prefix = "${var.project}-${var.environment}"
  account_id  = data.aws_caller_identity.current.account_id
  region      = data.aws_region.current.name

  # Merged tags (base + user-provided)
  common_tags = merge(
    {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "Terraform"
      Owner       = "platform-team"
    },
    var.tags  # user can add/override
  )

  # Computed from variables
  is_production = var.environment == "production"

  # Subnet configuration
  public_subnets = {
    for idx, az in var.availability_zones :
    az => cidrsubnet(var.vpc_cidr, 8, idx)
  }
  private_subnets = {
    for idx, az in var.availability_zones :
    az => cidrsubnet(var.vpc_cidr, 8, idx + 10)
  }

  # Instance type based on environment
  instance_type = local.is_production ? "t3.large" : "t3.micro"

  # Database config with defaults
  db_config = merge(
    {
      instance_class    = "db.t3.micro"
      allocated_storage = 20
      multi_az          = false
    },
    var.database_config
  )

  # CIDR blocks for subnets
  az_count = length(var.availability_zones)
}

# Use locals in resources
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  tags       = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_instance" "web" {
  instance_type = local.instance_type
  tags          = merge(local.common_tags, { Name = "${local.name_prefix}-web" })
}
```

---

## 4. Output Values

Outputs expose values from a module — used by other modules or displayed after apply.

```hcl
# outputs.tf

# Simple output
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

# Computed output
output "vpc_arn" {
  description = "ARN of the VPC"
  value       = aws_vpc.main.arn
}

# List of values
output "public_subnet_ids" {
  description = "IDs of public subnets"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "IDs of private subnets"
  value       = values(aws_subnet.private)[*].id
}

# Map output
output "subnet_by_az" {
  description = "Subnet ID by availability zone"
  value       = { for az, subnet in aws_subnet.private : az => subnet.id }
}

# Object output
output "database" {
  description = "Database connection details"
  value = {
    endpoint = aws_db_instance.main.endpoint
    port     = aws_db_instance.main.port
    name     = aws_db_instance.main.db_name
  }
}

# Sensitive output (masked in CLI output)
output "db_password" {
  description = "Database password"
  value       = aws_db_instance.main.password
  sensitive   = true
}

# Conditional output
output "load_balancer_dns" {
  description = "DNS name of the load balancer (if created)"
  value       = var.create_alb ? aws_lb.main[0].dns_name : null
}
```

### Accessing outputs

```bash
# Show all outputs
terraform output

# Show specific output
terraform output vpc_id
terraform output -json    # all as JSON
terraform output -json public_subnet_ids

# Access in another module
module "vpc" {
  source = "./modules/vpc"
}

resource "aws_instance" "web" {
  subnet_id = module.vpc.private_subnet_ids[0]
}
```

---

## 5. Sensitive Values

```hcl
# Mark variable as sensitive
variable "api_key" {
  type      = string
  sensitive = true
}

# Mark output as sensitive
output "api_endpoint" {
  value     = "https://api.example.com?key=${var.api_key}"
  sensitive = true   # masks in CLI output
}

# Sensitive values in state
# WARNING: sensitive = true masks in PLAN/APPLY output
# But values ARE stored in plain text in state file!
# → Always encrypt state storage
# → Restrict access to state file
# → Consider using external secret managers for passwords
```

### Avoid storing secrets in Terraform state

```hcl
# BAD — password stored in state
resource "aws_db_instance" "main" {
  password = var.db_password    # ends up in tfstate
}

# BETTER — generate and store in AWS Secrets Manager
resource "random_password" "db" {
  length  = 24
  special = true
}

resource "aws_secretsmanager_secret" "db_password" {
  name = "${var.project}/db/password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = random_password.db.result
}

resource "aws_db_instance" "main" {
  # password managed via Secrets Manager rotation
  manage_master_user_password = true
}
```

---

## 6. Variable Validation

```hcl
variable "environment" {
  type        = string
  description = "Environment name"

  validation {
    condition     = contains(["development", "staging", "production"], var.environment)
    error_message = "Environment must be development, staging, or production."
  }
}

variable "instance_type" {
  type = string

  validation {
    condition     = can(regex("^t3\\.", var.instance_type))
    error_message = "Instance type must be a t3 family instance."
  }
}

variable "cidr_block" {
  type = string

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "port" {
  type = number

  validation {
    condition     = var.port >= 1 && var.port <= 65535
    error_message = "Port must be between 1 and 65535."
  }
}

variable "tags" {
  type = map(string)

  validation {
    condition     = contains(keys(var.tags), "Owner")
    error_message = "Tags must include an Owner key."
  }
}

# Multiple validations
variable "backup_retention_days" {
  type = number

  validation {
    condition     = var.backup_retention_days >= 1
    error_message = "Backup retention must be at least 1 day."
  }

  validation {
    condition     = var.backup_retention_days <= 35
    error_message = "Backup retention cannot exceed 35 days (AWS limit)."
  }
}
```

---

## Cheatsheet

```hcl
# Variable
variable "name" {
  description = "..."
  type        = string
  default     = "value"
  sensitive   = false
  validation {
    condition     = length(var.name) > 0
    error_message = "Name cannot be empty."
  }
}

# Local
locals {
  name_prefix = "${var.project}-${var.environment}"
  common_tags = merge({ Project = var.project }, var.tags)
  is_prod     = var.environment == "production"
}

# Output
output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
  sensitive   = false
}
```

```bash
# Provide variables
terraform apply -var="environment=production"
terraform apply -var-file=prod.tfvars
export TF_VAR_db_password="secret"

# View outputs
terraform output
terraform output -json vpc_id
```

---

*Next: [State Management →](./05-state-management.md)*
