# ☁️ Cloud-Specific Patterns

Real-world Terraform patterns for AWS, GCP, and Azure — authentication, common resources, and EKS/GKE/AKS.

---

## 📚 Table of Contents

- [1. AWS Patterns](#1-aws-patterns)
- [2. GCP Patterns](#2-gcp-patterns)
- [3. Azure Patterns](#3-azure-patterns)
- [4. Multi-Cloud Patterns](#4-multi-cloud-patterns)
- [Cheatsheet](#cheatsheet)

---

## 1. AWS Patterns

### Authentication

```bash
# Option 1 — AWS CLI profile (development)
aws configure
# Creates ~/.aws/credentials and ~/.aws/config

# Option 2 — Environment variables
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="eu-central-1"

# Option 3 — IAM role (EC2, EKS, GitHub Actions OIDC — best for CI)
# No credentials needed — role assumed automatically

# Option 4 — Named profile
export AWS_PROFILE=my-profile
```

```hcl
# Provider with assumed role (cross-account)
provider "aws" {
  region = "eu-central-1"

  assume_role {
    role_arn     = "arn:aws:iam::123456789:role/TerraformRole"
    session_name = "terraform-session"
    external_id  = var.external_id
  }
}
```

### Complete EKS cluster

```hcl
# Using the official EKS module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = "${local.name_prefix}-eks"
  cluster_version = "1.28"

  vpc_id                         = module.vpc.vpc_id
  subnet_ids                     = module.vpc.private_subnets
  cluster_endpoint_public_access = true

  # Enable IRSA (IAM Roles for Service Accounts)
  enable_irsa = true

  # Managed node groups
  eks_managed_node_groups = {
    general = {
      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      min_size     = 2
      max_size     = 10
      desired_size = 3

      labels = { role = "general" }

      taints = []
    }

    spot = {
      instance_types = ["t3.large", "t3.xlarge"]
      capacity_type  = "SPOT"

      min_size     = 0
      max_size     = 10
      desired_size = 0

      labels = { role = "spot" }
      taints = [{
        key    = "spot"
        value  = "true"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  # Cluster access
  enable_cluster_creator_admin_permissions = true

  access_entries = {
    admin = {
      kubernetes_groups = []
      principal_arn     = "arn:aws:iam::123456789:role/AdminRole"
      policy_associations = {
        admin = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  tags = local.common_tags
}

# IRSA — IAM role for a service account
module "irsa_s3" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.0"

  role_name = "${local.name_prefix}-s3-access"

  oidc_providers = {
    ex = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["production:my-app"]
    }
  }

  role_policy_arns = {
    s3 = aws_iam_policy.s3_access.arn
  }
}
```

### IAM patterns

```hcl
# IAM role with assume role policy
resource "aws_iam_role" "app" {
  name = "${local.name_prefix}-app-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

# IAM policy
resource "aws_iam_policy" "s3_read" {
  name = "${local.name_prefix}-s3-read"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        aws_s3_bucket.app.arn,
        "${aws_s3_bucket.app.arn}/*"
      ]
    }]
  })
}

resource "aws_iam_role_policy_attachment" "app_s3" {
  role       = aws_iam_role.app.name
  policy_arn = aws_iam_policy.s3_read.arn
}

# Instance profile (attach role to EC2)
resource "aws_iam_instance_profile" "app" {
  name = "${local.name_prefix}-app-profile"
  role = aws_iam_role.app.name
}
```

### ALB + Target Group

```hcl
resource "aws_lb" "main" {
  name               = "${local.name_prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = module.vpc.public_subnets

  enable_deletion_protection = var.environment == "production"

  access_logs {
    bucket  = aws_s3_bucket.alb_logs.bucket
    prefix  = "alb"
    enabled = true
  }

  tags = local.common_tags
}

resource "aws_lb_target_group" "app" {
  name        = "${local.name_prefix}-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = module.vpc.vpc_id
  target_type = "ip"    # for EKS/ECS (IP-based)

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate.main.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

resource "aws_lb_listener" "http_redirect" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
```

### Route53 + ACM

```hcl
data "aws_route53_zone" "main" {
  name         = var.domain
  private_zone = false
}

resource "aws_acm_certificate" "main" {
  domain_name               = var.domain
  subject_alternative_names = ["*.${var.domain}"]
  validation_method         = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.main.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "main" {
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}

resource "aws_route53_record" "alb" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "app.${var.domain}"
  type    = "A"

  alias {
    name                   = aws_lb.main.dns_name
    zone_id                = aws_lb.main.zone_id
    evaluate_target_health = true
  }
}
```

---

## 2. GCP Patterns

### Authentication

```bash
# Option 1 — gcloud CLI (development)
gcloud auth application-default login

# Option 2 — Service account key (CI — less preferred)
export GOOGLE_CREDENTIALS=/path/to/service-account.json

# Option 3 — Workload Identity (GKE — best for CI)
# No credentials needed — uses GKE's service account
```

```hcl
provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}
```

### Complete GKE cluster

```hcl
resource "google_container_cluster" "main" {
  name     = "${var.project}-gke"
  location = var.region   # regional cluster (3 control plane nodes)

  # Recommended: separate node pools
  remove_default_node_pool = true
  initial_node_count       = 1

  # VPC-native networking
  networking_mode = "VPC_NATIVE"
  network         = google_compute_network.main.id
  subnetwork      = google_compute_subnetwork.gke.id

  ip_allocation_policy {
    cluster_secondary_range_name  = "pods"
    services_secondary_range_name = "services"
  }

  # Security
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block  = "172.16.0.0/28"
  }

  master_authorized_networks_config {
    cidr_blocks {
      cidr_block   = "0.0.0.0/0"
      display_name = "All"
    }
  }

  # Addons
  addons_config {
    http_load_balancing { disabled = false }
    horizontal_pod_autoscaling { disabled = false }
    gce_persistent_disk_csi_driver_config { enabled = true }
  }
}

resource "google_container_node_pool" "general" {
  name     = "general"
  cluster  = google_container_cluster.main.id
  location = var.region

  autoscaling {
    min_node_count  = 1
    max_node_count  = 5
    location_policy = "BALANCED"
  }

  node_config {
    machine_type = "e2-standard-2"
    disk_size_gb = 50
    disk_type    = "pd-ssd"

    # Workload Identity
    service_account = google_service_account.gke_nodes.email
    oauth_scopes    = ["https://www.googleapis.com/auth/cloud-platform"]

    shielded_instance_config {
      enable_secure_boot = true
    }
  }

  management {
    auto_repair  = true
    auto_upgrade = true
  }
}

# Workload Identity for pods
resource "google_service_account" "app" {
  account_id   = "${var.project}-app"
  display_name = "App Service Account"
}

resource "google_service_account_iam_member" "workload_identity" {
  service_account_id = google_service_account.app.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "serviceAccount:${var.project_id}.svc.id.goog[production/my-app]"
}
```

---

## 3. Azure Patterns

### Authentication

```bash
# Option 1 — Azure CLI (development)
az login

# Option 2 — Service principal
export ARM_CLIENT_ID="..."
export ARM_CLIENT_SECRET="..."
export ARM_TENANT_ID="..."
export ARM_SUBSCRIPTION_ID="..."

# Option 3 — Managed Identity (Azure VMs, GitHub Actions OIDC)
```

```hcl
provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}
```

### Complete AKS cluster

```hcl
resource "azurerm_resource_group" "main" {
  name     = "${var.project}-${var.environment}-rg"
  location = var.location
}

resource "azurerm_kubernetes_cluster" "main" {
  name                = "${var.project}-${var.environment}-aks"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  dns_prefix          = "${var.project}-${var.environment}"
  kubernetes_version  = "1.28"

  default_node_pool {
    name                = "system"
    node_count          = 2
    vm_size             = "Standard_D2_v3"
    vnet_subnet_id      = azurerm_subnet.aks.id
    type                = "VirtualMachineScaleSets"
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 5
    os_disk_size_gb     = 50
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    load_balancer_sku  = "standard"
    outbound_type      = "loadBalancer"
    service_cidr       = "10.100.0.0/16"
    dns_service_ip     = "10.100.0.10"
  }

  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.main.id
  }

  azure_policy_enabled = true

  tags = local.common_tags
}

resource "azurerm_kubernetes_cluster_node_pool" "app" {
  name                  = "app"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.main.id
  vm_size               = "Standard_D4_v3"
  node_count            = 2
  vnet_subnet_id        = azurerm_subnet.aks.id
  enable_auto_scaling   = true
  min_count             = 2
  max_count             = 10
  mode                  = "User"

  node_labels = { role = "app" }
  tags        = local.common_tags
}
```

---

## 4. Multi-Cloud Patterns

### Provider aliases for multi-region

```hcl
# Primary region
provider "aws" {
  region = "eu-central-1"
}

# Secondary region
provider "aws" {
  alias  = "us-east-1"
  region = "us-east-1"
}

# Global resources (CloudFront, Route53, ACM for CloudFront)
provider "aws" {
  alias  = "global"
  region = "us-east-1"   # Must be us-east-1 for CloudFront ACM
}

resource "aws_acm_certificate" "cloudfront" {
  provider = aws.global    # CloudFront requires us-east-1
  domain_name = var.domain
  validation_method = "DNS"
}
```

### Conditional cloud resources

```hcl
variable "cloud_provider" {
  type    = string
  default = "aws"
  validation {
    condition     = contains(["aws", "gcp", "azure"], var.cloud_provider)
    error_message = "Must be aws, gcp, or azure."
  }
}

resource "aws_s3_bucket" "storage" {
  count  = var.cloud_provider == "aws" ? 1 : 0
  bucket = var.bucket_name
}

resource "google_storage_bucket" "storage" {
  count    = var.cloud_provider == "gcp" ? 1 : 0
  name     = var.bucket_name
  location = "EU"
}

resource "azurerm_storage_account" "storage" {
  count                    = var.cloud_provider == "azure" ? 1 : 0
  name                     = replace(var.bucket_name, "-", "")
  resource_group_name      = azurerm_resource_group.main.name
  location                 = var.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}
```

---

## Cheatsheet

```bash
# AWS
export AWS_PROFILE=my-profile
# OR
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...

# GCP
gcloud auth application-default login
export GOOGLE_PROJECT=my-project

# Azure
az login
export ARM_SUBSCRIPTION_ID=...

# Common
terraform init
terraform plan -var-file=production.tfvars
terraform apply -var-file=production.tfvars

# EKS kubeconfig
aws eks update-kubeconfig --name my-cluster --region eu-central-1

# GKE kubeconfig
gcloud container clusters get-credentials my-cluster --region eu-central-1

# AKS kubeconfig
az aks get-credentials --name my-cluster --resource-group my-rg
```

---

*Next: [Testing & Validation →](./09-testing-validation.md)*
