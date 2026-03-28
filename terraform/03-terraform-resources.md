# 🔧 Resources & Data Sources

Writing real infrastructure — resources, data sources, dependencies, and common patterns.

---

## 📚 Table of Contents

- [1. Resources](#1-resources)
- [2. Data Sources](#2-data-sources)
- [3. Resource Dependencies](#3-resource-dependencies)
- [4. Common AWS Resources](#4-common-aws-resources)
- [5. Common GCP Resources](#5-common-gcp-resources)
- [6. Common Kubernetes Resources](#6-common-kubernetes-resources)
- [7. Resource Patterns](#7-resource-patterns)
- [Cheatsheet](#cheatsheet)

---

## 1. Resources

Resources are the fundamental building blocks — each represents one real-world infrastructure object.

```hcl
# Syntax
resource "<provider>_<type>" "<local_name>" {
  argument = value
  ...
}

# Examples
resource "aws_vpc" "main" { ... }
resource "google_compute_instance" "web" { ... }
resource "kubernetes_deployment" "app" { ... }
resource "github_repository" "my_repo" { ... }
```

### Resource address

Every resource has a unique address used in references, state, and targeting:

```
resource_type.resource_name
aws_instance.web

# With count:
aws_instance.servers[0]
aws_instance.servers[*]

# With for_each:
aws_instance.servers["web-1"]
```

### Lifecycle hooks

```hcl
resource "aws_instance" "web" {
  ami           = "ami-12345678"
  instance_type = "t3.micro"

  lifecycle {
    # Create replacement before destroying old (zero-downtime for stateless)
    create_before_destroy = true

    # Prevent accidental deletion
    prevent_destroy = true

    # Ignore drift on these fields (managed outside Terraform)
    ignore_changes = [
      ami,
      tags["LastModified"],
    ]

    # Custom precondition — validated before plan/apply
    precondition {
      condition     = contains(["t3.micro", "t3.small", "t3.medium"], var.instance_type)
      error_message = "Instance type must be t3.micro, t3.small, or t3.medium."
    }

    # Custom postcondition — validated after apply
    postcondition {
      condition     = self.public_ip != ""
      error_message = "Instance must have a public IP."
    }
  }
}
```

---

## 2. Data Sources

Data sources query existing infrastructure (not managed by this Terraform) or external data.

```hcl
# Syntax
data "<provider>_<type>" "<local_name>" {
  filter_argument = value
}

# Reference: data.<type>.<name>.<attribute>
```

### Common data source patterns

```hcl
# Look up latest Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]   # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_instance" "web" {
  ami = data.aws_ami.ubuntu.id   # use the looked-up AMI
}

# Look up existing VPC (created outside Terraform)
data "aws_vpc" "existing" {
  tags = {
    Name = "production-vpc"
  }
}

# Or by ID
data "aws_vpc" "existing" {
  id = "vpc-12345678"
}

# Get current AWS account ID and region
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id
  region     = data.aws_region.current.name
}

# Look up existing security group
data "aws_security_group" "existing" {
  name   = "web-sg"
  vpc_id = aws_vpc.main.id
}

# Look up Route53 zone
data "aws_route53_zone" "main" {
  name         = "example.com."
  private_zone = false
}

# Look up SSM parameter (secrets/config)
data "aws_ssm_parameter" "db_password" {
  name            = "/production/database/password"
  with_decryption = true
}

# External data source (call a script)
data "external" "git_version" {
  program = ["bash", "${path.module}/scripts/get-version.sh"]
}

locals {
  app_version = data.external.git_version.result["version"]
}
```

---

## 3. Resource Dependencies

### Implicit dependencies (from references)

```hcl
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"
}

resource "aws_subnet" "private" {
  # Implicit dependency — Terraform knows to create VPC first
  vpc_id     = aws_vpc.main.id
  cidr_block = "10.0.1.0/24"
}

resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.private.id  # another implicit dependency
}
```

### Explicit dependencies

```hcl
resource "aws_s3_object" "config" {
  bucket  = aws_s3_bucket.app.bucket
  key     = "config.json"
  content = jsonencode(local.app_config)

  # Explicit dependency — bucket policy must exist before uploading
  depends_on = [
    aws_s3_bucket_policy.app,
    aws_s3_bucket_versioning.app,
  ]
}
```

---

## 4. Common AWS Resources

### VPC & Networking

```hcl
# VPC
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "${var.project}-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "${var.project}-igw" }
}

# Public subnets
resource "aws_subnet" "public" {
  for_each = {
    "eu-central-1a" = "10.0.1.0/24"
    "eu-central-1b" = "10.0.2.0/24"
    "eu-central-1c" = "10.0.3.0/24"
  }

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = true

  tags = { Name = "${var.project}-public-${each.key}" }
}

# Private subnets
resource "aws_subnet" "private" {
  for_each = {
    "eu-central-1a" = "10.0.11.0/24"
    "eu-central-1b" = "10.0.12.0/24"
    "eu-central-1c" = "10.0.13.0/24"
  }

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = { Name = "${var.project}-private-${each.key}" }
}

# Route table for public subnets
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

# NAT Gateway (for private subnet internet access)
resource "aws_eip" "nat" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.main]
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = values(aws_subnet.public)[0].id  # first public subnet
  depends_on    = [aws_internet_gateway.main]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }
}
```

### EC2

```hcl
# Security group
resource "aws_security_group" "web" {
  name        = "${var.project}-web-sg"
  description = "Security group for web servers"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Key pair
resource "aws_key_pair" "deployer" {
  key_name   = "${var.project}-key"
  public_key = file("~/.ssh/id_ed25519.pub")
}

# EC2 instance
resource "aws_instance" "web" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  subnet_id              = values(aws_subnet.public)[0].id
  vpc_security_group_ids = [aws_security_group.web.id]
  key_name               = aws_key_pair.deployer.key_name
  iam_instance_profile   = aws_iam_instance_profile.web.name

  user_data = templatefile("${path.module}/scripts/user_data.sh.tpl", {
    environment = var.environment
    db_endpoint = aws_db_instance.main.endpoint
  })

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  tags = { Name = "${var.project}-web" }
}
```

### RDS

```hcl
resource "aws_db_subnet_group" "main" {
  name       = "${var.project}-db-subnet-group"
  subnet_ids = [for s in aws_subnet.private : s.id]
}

resource "aws_db_instance" "main" {
  identifier        = "${var.project}-postgres"
  engine            = "postgres"
  engine_version    = "15.3"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "myapp"
  username = "myapp"
  password = var.db_password   # use SSM or Secrets Manager in production

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]

  backup_retention_period = 7
  skip_final_snapshot     = false
  final_snapshot_identifier = "${var.project}-final-snapshot"

  tags = { Name = "${var.project}-postgres" }
}
```

### S3

```hcl
resource "aws_s3_bucket" "app" {
  bucket = "${var.project}-${var.environment}-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_versioning" "app" {
  bucket = aws_s3_bucket.app.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "app" {
  bucket = aws_s3_bucket.app.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

---

## 5. Common GCP Resources

```hcl
# GCP VPC
resource "google_compute_network" "main" {
  name                    = "${var.project}-vpc"
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "private" {
  name          = "${var.project}-private"
  ip_cidr_range = "10.0.0.0/24"
  region        = var.region
  network       = google_compute_network.main.id

  secondary_ip_range {
    range_name    = "pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  secondary_ip_range {
    range_name    = "services"
    ip_cidr_range = "10.2.0.0/20"
  }
}

# GKE Cluster
resource "google_container_cluster" "main" {
  name     = "${var.project}-gke"
  location = var.region

  remove_default_node_pool = true
  initial_node_count       = 1

  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.main.id
  subnetwork      = google_compute_subnetwork.private.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  workload_identity_config {
    workload_pool = "${var.project}.svc.id.goog"
  }
}

resource "google_container_node_pool" "main" {
  name       = "main-pool"
  cluster    = google_container_cluster.main.id
  node_count = 2

  node_config {
    machine_type = "e2-standard-2"
    disk_size_gb = 50
    disk_type    = "pd-ssd"

    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]
  }

  autoscaling {
    min_node_count = 1
    max_node_count = 5
  }
}
```

---

## 6. Common Kubernetes Resources

```hcl
# Namespace
resource "kubernetes_namespace" "app" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

# ConfigMap
resource "kubernetes_config_map" "app" {
  metadata {
    name      = "app-config"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    APP_ENV   = var.environment
    LOG_LEVEL = "info"
  }
}

# Secret
resource "kubernetes_secret" "db" {
  metadata {
    name      = "db-secret"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  data = {
    password = base64encode(var.db_password)
  }
}

# Deployment
resource "kubernetes_deployment" "app" {
  metadata {
    name      = "my-app"
    namespace = kubernetes_namespace.app.metadata[0].name
  }

  spec {
    replicas = var.replicas

    selector {
      match_labels = { app = "my-app" }
    }

    template {
      metadata {
        labels = { app = "my-app" }
      }

      spec {
        container {
          name  = "my-app"
          image = "${var.image_repository}:${var.image_tag}"

          resources {
            requests = { cpu = "100m", memory = "128Mi" }
            limits   = { cpu = "500m", memory = "256Mi" }
          }

          env_from {
            config_map_ref { name = kubernetes_config_map.app.metadata[0].name }
          }
        }
      }
    }
  }
}
```

---

## 7. Resource Patterns

### Null resource — run arbitrary scripts

```hcl
resource "null_resource" "init_db" {
  triggers = {
    # Re-run when these change
    db_endpoint = aws_db_instance.main.endpoint
    script_hash = filemd5("${path.module}/scripts/init_db.sh")
  }

  provisioner "local-exec" {
    command = <<-EOT
      PGPASSWORD=${var.db_password} psql \
        -h ${aws_db_instance.main.endpoint} \
        -U myapp \
        -d myapp \
        -f ${path.module}/scripts/init_db.sh
    EOT
  }

  depends_on = [aws_db_instance.main]
}
```

### Time resource — delays and rotation

```hcl
resource "time_sleep" "wait_for_cluster" {
  create_duration = "30s"
  depends_on      = [aws_eks_cluster.main]
}

resource "kubernetes_config_map" "aws_auth" {
  depends_on = [time_sleep.wait_for_cluster]
  # ...
}

# Rotating passwords
resource "time_rotating" "db_password_rotation" {
  rotation_days = 30
}

resource "random_password" "db_password" {
  keepers = {
    rotation = time_rotating.db_password_rotation.id
  }
  length  = 24
  special = true
}
```

---

## Cheatsheet

```hcl
# Resource
resource "aws_instance" "web" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true
    ignore_changes        = [ami]
  }
}

# Data source
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
  filter { name = "name"; values = ["ubuntu*22.04*"] }
}

# for_each pattern
resource "aws_subnet" "private" {
  for_each   = var.subnet_config          # map
  vpc_id     = aws_vpc.main.id
  cidr_block = each.value.cidr
}

# count pattern
resource "aws_instance" "servers" {
  count         = var.server_count
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  tags          = { Name = "server-${count.index}" }
}
```

---

*Next: [Variables, Outputs & Locals →](./04-variables-outputs-locals.md)*
