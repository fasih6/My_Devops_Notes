# 📦 Modules

Writing reusable Terraform modules, using the registry, versioning, and module composition.

---

## 📚 Table of Contents

- [1. What are Modules?](#1-what-are-modules)
- [2. Module Structure](#2-module-structure)
- [3. Writing a Module](#3-writing-a-module)
- [4. Using Modules](#4-using-modules)
- [5. Module Sources](#5-module-sources)
- [6. Module Versioning](#6-module-versioning)
- [7. Terraform Registry](#7-terraform-registry)
- [8. Module Composition Patterns](#8-module-composition-patterns)
- [Cheatsheet](#cheatsheet)

---

## 1. What are Modules?

A module is any directory containing `.tf` files. Every Terraform configuration is a module — the **root module**. Modules you call from your root are **child modules**.

```
Without modules:
  1000-line main.tf with VPC, EKS, RDS, IAM all mixed together

With modules:
  main.tf (30 lines) — calls vpc, eks, rds modules
  modules/vpc/       — reusable VPC configuration
  modules/eks/       — reusable EKS cluster
  modules/rds/       — reusable RDS database
```

Benefits:
- **Reusability** — use the same VPC module in dev, staging, production
- **Encapsulation** — hide complexity behind a clean interface
- **Versioning** — pin modules to tested versions
- **Team collaboration** — teams publish and consume shared modules

---

## 2. Module Structure

```
modules/
└── vpc/
    ├── main.tf        # resources
    ├── variables.tf   # input variables (the module's API)
    ├── outputs.tf     # values exposed to the caller
    ├── versions.tf    # required providers and Terraform version
    ├── locals.tf      # internal computed values
    └── README.md      # documentation
```

---

## 3. Writing a Module

### modules/vpc/variables.tf

```hcl
variable "name" {
  description = "Name prefix for all resources"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrhost(var.cidr_block, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "availability_zones" {
  description = "List of availability zones"
  type        = list(string)
}

variable "public_subnet_count" {
  description = "Number of public subnets"
  type        = number
  default     = 3
}

variable "private_subnet_count" {
  description = "Number of private subnets"
  type        = number
  default     = 3
}

variable "enable_nat_gateway" {
  description = "Create NAT gateway for private subnets"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

### modules/vpc/main.tf

```hcl
locals {
  public_subnets = {
    for i, az in slice(var.availability_zones, 0, var.public_subnet_count) :
    az => cidrsubnet(var.cidr_block, 8, i)
  }

  private_subnets = {
    for i, az in slice(var.availability_zones, 0, var.private_subnet_count) :
    az => cidrsubnet(var.cidr_block, 8, i + 10)
  }

  common_tags = merge(
    var.tags,
    { ManagedBy = "Terraform" }
  )
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr_block
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = merge(local.common_tags, { Name = "${var.name}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-igw" })
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-public-${each.key}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  for_each = local.private_subnets

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = merge(local.common_tags, {
    Name = "${var.name}-private-${each.key}"
    Tier = "private"
  })
}

resource "aws_eip" "nat" {
  count      = var.enable_nat_gateway ? 1 : 0
  domain     = "vpc"
  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = values(aws_subnet.public)[0].id
  depends_on    = [aws_internet_gateway.this]

  tags = merge(local.common_tags, { Name = "${var.name}-nat" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = var.enable_nat_gateway ? 1 : 0
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[0].id
  }

  tags = merge(local.common_tags, { Name = "${var.name}-private-rt" })
}

resource "aws_route_table_association" "private" {
  for_each       = var.enable_nat_gateway ? aws_subnet.private : {}
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[0].id
}
```

### modules/vpc/outputs.tf

```hcl
output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "vpc_cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "List of public subnet IDs"
  value       = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  description = "List of private subnet IDs"
  value       = [for s in aws_subnet.private : s.id]
}

output "public_subnet_ids_by_az" {
  description = "Map of AZ to public subnet ID"
  value       = { for az, s in aws_subnet.public : az => s.id }
}

output "nat_gateway_ip" {
  description = "Public IP of the NAT gateway"
  value       = var.enable_nat_gateway ? aws_eip.nat[0].public_ip : null
}
```

---

## 4. Using Modules

```hcl
# Root module using the vpc module
module "vpc" {
  source = "./modules/vpc"          # local module

  # Pass input variables
  name               = "${var.project}-${var.environment}"
  cidr_block         = "10.0.0.0/16"
  availability_zones = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  enable_nat_gateway = var.environment == "production"
  tags = {
    Project     = var.project
    Environment = var.environment
  }
}

# Use module outputs
resource "aws_instance" "web" {
  subnet_id = module.vpc.private_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.web.id]
  # ...
}

output "vpc_id" {
  value = module.vpc.vpc_id
}
```

### Multiple instances of the same module

```hcl
# Different VPCs for different environments
module "vpc_staging" {
  source     = "./modules/vpc"
  name       = "staging"
  cidr_block = "10.0.0.0/16"
  availability_zones = ["eu-central-1a", "eu-central-1b"]
}

module "vpc_production" {
  source     = "./modules/vpc"
  name       = "production"
  cidr_block = "10.1.0.0/16"
  availability_zones = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  enable_nat_gateway = true
}
```

---

## 5. Module Sources

```hcl
# Local path
module "vpc" {
  source = "./modules/vpc"
  source = "../shared-modules/vpc"
}

# Terraform Registry (official/partner/community)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
}

# GitHub
module "vpc" {
  source = "github.com/myorg/terraform-modules//vpc"
  source = "git::https://github.com/myorg/terraform-modules.git//vpc?ref=v1.2.0"
}

# Private Git (SSH)
module "vpc" {
  source = "git::ssh://git@github.com/myorg/terraform-modules.git//vpc?ref=v1.2.0"
}

# Bitbucket
module "vpc" {
  source = "bitbucket.org/myorg/terraform-modules//vpc"
}

# HTTP archive
module "vpc" {
  source = "https://example.com/terraform-modules/vpc.zip"
}

# S3 (for private modules)
module "vpc" {
  source = "s3::https://s3.amazonaws.com/my-bucket/terraform-modules/vpc.zip"
}

# OCI registry (Terraform 1.5+)
module "vpc" {
  source  = "oci://registry.example.com/terraform-modules/vpc"
  version = "1.0.0"
}
```

---

## 6. Module Versioning

Always version modules for production use:

```hcl
# Pin to exact version (safest for production)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.1.2"
}

# Allow patch updates (~): 5.1.x
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.1"
}

# Allow minor updates (^): 5.x.x
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"
}

# Minimum version
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = ">= 5.0.0"
}
```

### Module lock file

```bash
# After adding/changing module sources:
terraform init   # downloads modules and updates .terraform.lock.hcl

# Force download (ignore cache)
terraform init -upgrade
```

---

## 7. Terraform Registry

The public Terraform Registry (registry.terraform.io) hosts:
- Official modules (by HashiCorp)
- Partner modules (by cloud providers)
- Community modules

### Popular community modules

```hcl
# AWS VPC module (most popular)
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "my-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["eu-central-1a", "eu-central-1b", "eu-central-1c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true
  single_nat_gateway = false    # one NAT per AZ for HA

  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = local.common_tags
}

# AWS EKS module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "my-cluster"
  cluster_version = "1.28"
  vpc_id          = module.vpc.vpc_id
  subnet_ids      = module.vpc.private_subnets

  eks_managed_node_groups = {
    general = {
      instance_types = ["t3.medium"]
      min_size       = 2
      max_size       = 5
      desired_size   = 2
    }
  }
}

# AWS RDS module
module "db" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 6.0"

  identifier = "my-db"
  engine     = "postgres"
  engine_version = "15"
  instance_class = "db.t3.micro"

  db_name  = "myapp"
  username = "myapp"

  vpc_security_group_ids = [aws_security_group.db.id]
  subnet_ids             = module.vpc.private_subnets

  create_db_subnet_group = true
}
```

### Publishing to the registry

```
Requirements:
- GitHub repo named terraform-<provider>-<name>
  e.g., terraform-aws-vpc, terraform-google-gke

- Standard module structure (main.tf, variables.tf, outputs.tf, README.md)
- Semantic versioned Git tags (v1.0.0)

- Connect GitHub to registry.terraform.io
- Click "Publish Module"
```

---

## 8. Module Composition Patterns

### Wrapper module — thin wrapper over a community module

```hcl
# modules/vpc/main.tf — company standards wrapper
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  # Pass through variables
  name = var.name
  cidr = var.cidr_block
  azs  = var.availability_zones

  private_subnets = var.private_subnets
  public_subnets  = var.public_subnets

  # Enforce company standards
  enable_nat_gateway   = true     # always required
  enable_dns_hostnames = true     # always required
  enable_dns_support   = true     # always required

  # Enforce tagging
  tags = merge(var.tags, {
    ManagedBy = "Terraform"
    Team      = "platform"
  })
}
```

### Composing modules together

```hcl
# main.tf — compose multiple modules
module "vpc" {
  source             = "./modules/vpc"
  name               = local.name_prefix
  cidr_block         = "10.0.0.0/16"
  availability_zones = local.azs
}

module "eks" {
  source              = "./modules/eks"
  cluster_name        = local.name_prefix
  kubernetes_version  = "1.28"
  vpc_id              = module.vpc.vpc_id         # output from vpc module
  subnet_ids          = module.vpc.private_subnet_ids
}

module "rds" {
  source     = "./modules/rds"
  identifier = "${local.name_prefix}-db"
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnet_ids
}
```

---

## Cheatsheet

```hcl
# Call a module
module "my_module" {
  source  = "./modules/vpc"     # local
  source  = "org/module/aws"    # registry
  version = "~> 1.0"            # version constraint

  # Pass inputs
  name       = "my-name"
  cidr_block = "10.0.0.0/16"
}

# Use module outputs
resource "aws_instance" "web" {
  subnet_id = module.my_module.private_subnet_ids[0]
}

output "vpc_id" {
  value = module.my_module.vpc_id
}
```

```bash
# Module operations
terraform init         # download modules
terraform init -upgrade # upgrade to latest allowed version
terraform get          # download modules without other init steps

# Target a module
terraform plan -target=module.vpc
terraform apply -target=module.eks
```

---

*Next: [Workflows & Best Practices →](./07-workflows-best-practices.md)*
