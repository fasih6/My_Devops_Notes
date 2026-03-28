# 🎯 Terraform Interview Q&A

Real Terraform questions asked in DevOps interviews — with complete answers.

---

## 📚 Table of Contents

- [🔥 Core Concepts](#-core-concepts)
- [📝 HCL & Configuration](#-hcl--configuration)
- [🗄️ State Management](#️-state-management)
- [📦 Modules](#-modules)
- [🔥 Scenario-Based Questions](#-scenario-based-questions)
- [🧠 Advanced Questions](#-advanced-questions)
- [💬 Questions to Ask the Interviewer](#-questions-to-ask-the-interviewer)

---

## 🔥 Core Concepts

---

**Q: What is Terraform and what problems does it solve?**

Terraform is an Infrastructure as Code tool that lets you define cloud resources in declarative configuration files and provision them across any cloud provider. It solves three key problems:

1. **Manual infrastructure** — clicking in cloud consoles is error-prone, not reproducible, and doesn't scale. Terraform makes infrastructure reproducible and version-controlled.
2. **Environment drift** — dev, staging, and production environments gradually diverge. Terraform ensures they're all provisioned from the same code.
3. **Multi-cloud management** — one tool (Terraform) manages resources across AWS, GCP, Azure, Kubernetes, GitHub, and thousands of other providers.

---

**Q: What is the difference between declarative and imperative IaC?**

**Declarative** (Terraform, CloudFormation): You describe the desired end state. "I want 3 EC2 instances with these properties." Terraform figures out how to get there — what to create, update, or delete.

**Imperative** (Ansible for provisioning, shell scripts): You describe the steps to take. "Run this command, create this resource, then run this." You control the order and logic.

Terraform is declarative — you don't write `create_instance()`, you write `resource "aws_instance"`. Terraform handles the rest.

---

**Q: What is the Terraform state file and why is it important?**

The state file (`terraform.tfstate`) is a JSON file that maps your Terraform configuration to real-world infrastructure. It records: "the resource `aws_instance.web` corresponds to EC2 instance `i-0a1b2c3d4e5f6g7h8`."

Without state:
- Terraform can't know what it has already created
- Can't calculate what needs to change
- Can't destroy specific resources

With state, Terraform knows the current state and can compute the diff between current and desired.

**State must be handled carefully:**
- Never commit to Git (contains sensitive values)
- Store remotely (S3 + DynamoDB for teams)
- Enable encryption at rest
- Use locking to prevent concurrent modifications

---

**Q: What is a Terraform provider?**

A provider is a plugin that translates Terraform configuration into API calls for a specific service. There are providers for AWS, GCP, Azure, Kubernetes, GitHub, Datadog, and thousands more.

Each provider is a separate binary downloaded by `terraform init`. The AWS provider translates `resource "aws_instance"` into EC2 API calls. The Kubernetes provider translates `resource "kubernetes_deployment"` into Kubernetes API calls.

Providers are versioned and pinned in `terraform.lock.hcl` to ensure reproducible builds.

---

**Q: What happens during `terraform plan`?**

1. Reads current state from the state file
2. Queries the provider APIs to detect any drift (manual changes)
3. Reads your configuration files (desired state)
4. Calculates the diff: what needs to be created (+), updated (~), or destroyed (-)
5. Shows the execution plan without making any changes

The plan output is your opportunity to review changes before they happen. Always review it carefully — especially unexpected destroys or replacements (-/+).

---

**Q: What is the difference between `terraform destroy` and removing a resource from configuration?**

**`terraform destroy`** destroys ALL resources managed by the current configuration.

**Removing a resource from configuration** and running `terraform apply` destroys only that specific resource — Terraform sees it's in state but not in config, so it destroys it.

There's also `terraform state rm resource.name` which removes a resource from state WITHOUT destroying it in the cloud. Useful when you want Terraform to stop managing something without deleting it.

---

## 📝 HCL & Configuration

---

**Q: What is the difference between `count` and `for_each`?**

Both create multiple instances of a resource, but they work differently:

`count` uses an integer — resources are addressed by index (`aws_instance.servers[0]`). If you remove an item from the middle, Terraform renumbers everything and destroys/recreates resources unnecessarily.

`for_each` uses a map or set — resources are addressed by key (`aws_instance.servers["web-1"]`). Removing one key only affects that specific resource, not others.

**Use `for_each` when possible** — it's more stable. Use `count` only for simple on/off resource creation (`count = var.enabled ? 1 : 0`).

---

**Q: What is the difference between a variable, a local, and an output?**

**Variable** — input to a module or configuration. Set by the caller (via `.tfvars`, `-var`, environment variables). Has a declared type and optional validation.

**Local** — a named expression computed within the module. Not settable from outside, not accessible from outside. Used to avoid repetition (DRY).

**Output** — a value exported from a module or configuration. Used by parent modules to consume child module values, or displayed after `terraform apply`.

---

**Q: What does `lifecycle { create_before_destroy = true }` do?**

By default, when a resource needs to be replaced (destroyed and recreated), Terraform destroys the old resource first, then creates the new one. This causes downtime.

`create_before_destroy = true` reverses the order: creates the new resource first, then destroys the old one. This enables zero-downtime replacements for resources that support it.

Use it for: EC2 instances behind a load balancer, ACM certificates (with DNS validation), security groups.

---

## 🗄️ State Management

---

**Q: How do you manage Terraform state for a team?**

Use a remote backend with locking:

```hcl
terraform {
  backend "s3" {
    bucket         = "company-terraform-state"
    key            = "production/terraform.tfstate"
    region         = "eu-central-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}
```

- **S3** stores the state file (encrypted)
- **DynamoDB** provides state locking (prevents concurrent applies)
- S3 versioning preserves state history for recovery

Every `terraform plan` and `apply` acquires a lock, preventing two people or CI jobs from running simultaneously.

---

**Q: What is state drift and how do you detect it?**

Drift occurs when someone makes changes to infrastructure directly (via console, CLI) without updating Terraform. The state says one thing, reality is different.

Detect drift:
```bash
terraform plan   # will show changes needed to reconcile
terraform apply -refresh-only  # updates state to match reality without changing infra
```

Prevent drift:
- Enforce all changes through Terraform (via policy/culture)
- Use AWS Config or equivalent to detect out-of-band changes
- Regular `terraform plan` runs in CI to detect drift

---

**Q: What is `terraform import` and when would you use it?**

`terraform import` brings existing infrastructure (not created by Terraform) under Terraform management. It adds the resource to the state file without creating it.

Use when:
- You're adopting Terraform for existing infrastructure
- Someone created a resource manually that now needs to be managed as code
- You lost state but the infrastructure still exists

```bash
# Old way
terraform import aws_instance.web i-0a1b2c3d4e5f6g7h8

# Terraform 1.5+ — use import blocks in config
import {
  to = aws_instance.web
  id = "i-0a1b2c3d4e5f6g7h8"
}
terraform plan -generate-config-out=generated.tf
```

After importing, you must write the matching HCL and ensure `terraform plan` shows no changes.

---

## 📦 Modules

---

**Q: What is a Terraform module and why use them?**

A module is any directory containing Terraform files. The root configuration is a module. Modules you call from it are child modules.

Why use them:
1. **Reusability** — write VPC logic once, use it for dev, staging, production
2. **Encapsulation** — hide complexity, expose a clean interface (variables/outputs)
3. **Versioning** — pin modules to tested versions, upgrade when ready
4. **Team collaboration** — platform team publishes modules, app teams consume them

---

**Q: What is the difference between `module.x.output` and `data.x.y.attribute`?**

`module.x.output` accesses a value exported by a child module that Terraform is managing. The module must be in your configuration.

`data.x.y.attribute` queries an external data source — it reads information from the provider API without managing it. Used for: looking up AMIs, existing VPCs, SSM parameters, IAM policies.

---

## 🔥 Scenario-Based Questions

---

**Scenario 1: Your `terraform plan` shows unexpected destroys. What do you do?**

```
1. Don't panic and don't apply yet

2. Understand WHY the destroy is planned
   - Resource was deleted manually? (drift)
   - Configuration changed in a breaking way?
   - count → for_each migration causing renaming?
   - Provider upgrade changed the resource behavior?

3. If it's drift (manual deletion):
   terraform apply -refresh-only  # update state to match reality
   # Then decide: re-create it with Terraform, or remove from state

4. If it's a forced replacement you want to avoid:
   Check if lifecycle { create_before_destroy = true } helps
   Check if ignore_changes can help

5. If it's count/for_each renaming:
   Use moved {} blocks to rename without destroy/recreate:
   moved {
     from = aws_subnet.private[0]
     to   = aws_subnet.private["eu-central-1a"]
   }

6. If it's intentional — review carefully and apply
```

---

**Scenario 2: State is locked and no one is running Terraform. What do you do?**

```
1. Confirm no one is actually running Terraform
   Check CI/CD pipelines, ask team

2. Get the lock ID from the error message
   "Error acquiring the state lock"
   "ID: abc123-def456..."

3. Force-unlock
   terraform force-unlock abc123-def456

4. If using DynamoDB, check and delete the lock item directly
   aws dynamodb scan --table-name terraform-state-lock
   aws dynamodb delete-item --table-name terraform-state-lock \
     --key '{"LockID": {"S": "bucket/key/terraform.tfstate"}}'
```

---

**Scenario 3: You need to rename a resource in Terraform without destroying it. How?**

Use a `moved` block (Terraform 1.1+):

```hcl
moved {
  from = aws_instance.web_server
  to   = aws_instance.web
}
```

Run `terraform plan` — it should show the move without any destroy/create. Then `terraform apply`. After applying, remove the `moved` block.

For older Terraform versions:
```bash
terraform state mv aws_instance.web_server aws_instance.web
```

---

**Scenario 4: You accidentally destroyed a production database. How do you recover?**

```
1. DON'T PANIC — act methodically

2. Check if the database still exists
   AWS might have a deletion protection or snapshot
   aws rds describe-db-instances --db-instance-identifier my-db

3. If deletion protection was enabled — good, it's still there
   terraform apply   # will recreate the config, find the DB exists

4. If not protected but RDS backup exists:
   Restore from the automated snapshot
   aws rds restore-db-instance-from-db-snapshot \
     --db-instance-identifier my-db-restored \
     --db-snapshot-identifier rds:my-db-2024-01-15

5. After restoring, import the new instance:
   # Update your Terraform config with new identifier
   terraform import aws_db_instance.main my-db-restored

6. Prevention:
   lifecycle { prevent_destroy = true }  # in the resource
   Set deletion protection in the resource
   Add -target to avoid touching databases unless intended
```

---

**Scenario 5: How do you handle secrets in Terraform without committing them to Git?**

```
Options (best to worst):

1. Let the service manage credentials
   resource "aws_db_instance" "main" {
     manage_master_user_password = true  # AWS rotates via Secrets Manager
   }

2. Read from AWS SSM/Secrets Manager at plan time
   data "aws_ssm_parameter" "db_password" {
     name            = "/prod/db/password"
     with_decryption = true
   }

3. Environment variables (CI/CD)
   TF_VAR_db_password in GitHub/GitLab secrets
   Never in .tfvars files

4. HashiCorp Vault integration
   data "vault_generic_secret" "db" {
     path = "secret/production/database"
   }

AVOID:
❌ Storing passwords in .tfvars committed to Git
❌ Hardcoding secrets in .tf files
❌ Putting secrets in Terraform outputs (even with sensitive=true — they're in state!)
```

---

## 🧠 Advanced Questions

---

**Q: What is the Terraform dependency graph and why does it matter?**

Terraform builds a Directed Acyclic Graph (DAG) of resource dependencies before executing. Resources with no dependencies run in parallel. Resources that depend on others (via references) run after their dependencies.

This matters for:
- **Performance** — parallel execution is much faster for large configurations
- **Correctness** — ensures resources are created/destroyed in the right order
- **Debugging** — `terraform graph | dot -Tpng > graph.png` visualizes the dependency chain

When you use a reference (`vpc_id = aws_vpc.main.id`), Terraform automatically creates an edge in the graph. `depends_on` creates explicit edges for dependencies that aren't captured by references.

---

**Q: What is the difference between `terraform apply -refresh-only` and `terraform refresh`?**

`terraform refresh` (deprecated) updated the state to match real infrastructure, making permanent changes to the state file without your review.

`terraform apply -refresh-only` (replacement) shows you what state changes would be made and asks for confirmation. Much safer — you can review before committing.

Use it to detect drift: if someone manually changed something, `-refresh-only` shows you the diff between state and reality, then updates state to reflect reality.

---

**Q: How would you split a large Terraform configuration into multiple state files?**

Split by lifecycle and team ownership:

```
networking/     → VPC, subnets, route tables (stable, ops team)
  backend: s3 key "networking/terraform.tfstate"

security/       → IAM roles, security groups (semi-stable)
  backend: s3 key "security/terraform.tfstate"

eks/            → Kubernetes cluster (stable once created)
  backend: s3 key "eks/terraform.tfstate"

databases/      → RDS, ElastiCache (stable)
  backend: s3 key "databases/terraform.tfstate"

apps/           → Application deployments (frequently changing)
  backend: s3 key "apps/terraform.tfstate"
```

Connect them with `terraform_remote_state` data source:

```hcl
data "terraform_remote_state" "networking" {
  backend = "s3"
  config = {
    bucket = "my-state-bucket"
    key    = "networking/terraform.tfstate"
    region = "eu-central-1"
  }
}

resource "aws_eks_cluster" "main" {
  vpc_id     = data.terraform_remote_state.networking.outputs.vpc_id
  subnet_ids = data.terraform_remote_state.networking.outputs.private_subnet_ids
}
```

Benefits: blast radius reduction, faster plans, team independence, separate blast radii.

---

## 💬 Questions to Ask the Interviewer

**On their Terraform setup:**
- "How is your Terraform state organized — one state or split by component/environment?"
- "Do you use Terraform Cloud / HCP Terraform, or self-managed with S3?"
- "Do you have a standard module library your teams use?"

**On their practices:**
- "How do you handle Terraform in CI/CD — do you use Atlantis, GitHub Actions, or something else?"
- "Is there an approval process before `terraform apply` in production?"
- "How do you handle secrets — SSM Parameter Store, Vault, or something else?"

**On their challenges:**
- "What's the biggest Terraform incident you've had and what did you learn?"
- "How do you handle state drift — is there monitoring for out-of-band changes?"
- "Do you have guardrails preventing people from applying Terraform locally to production?"

---

*Good luck — deep Terraform knowledge like this is rare and highly valued. 🚀*
