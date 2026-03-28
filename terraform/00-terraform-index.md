# 🏗️ Terraform & IaC

A complete Terraform knowledge base — from core concepts to production-grade infrastructure as code.

> Terraform is the most widely used IaC tool in DevOps. It provisions cloud infrastructure across AWS, GCP, Azure, and 1000+ other providers. Every cloud-native company uses it. Understanding it deeply is what makes you a complete DevOps engineer.

---

## 🗺️ Learning Path

```
01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10 → 11
 │     │     │     │     │     │     │     │     │     │     │
 │     │     │     │     │     │     │     │     │     │     └── Interview prep
 │     │     │     │     │     │     │     │     │     └──────── Automate it
 │     │     │     │     │     │     │     │     └────────────── Test it
 │     │     │     │     │     │     │     └──────────────────── Cloud patterns
 │     │     │     │     │     │     └────────────────────────── Structure & conventions
 │     │     │     │     │     └──────────────────────────────── Reuse with modules
 │     │     │     │     └────────────────────────────────────── Manage state safely
 │     │     │     └──────────────────────────────────────────── Parameterize configs
 │     │     └────────────────────────────────────────────────── Write real resources
 │     └──────────────────────────────────────────────────────── HCL language mastery
 └────────────────────────────────────────────────────────────── How Terraform works
```

---

## 📚 Contents

| # | File | What you'll learn |
|---|------|------------------|
| 01 | [Core Concepts](./01-terraform-core-concepts.md) | Providers, state, plan/apply lifecycle, commands |
| 02 | [HCL Language](./02-terraform-hcl.md) | Types, expressions, functions, loops, dynamic blocks |
| 03 | [Resources & Data Sources](./03-terraform-resources.md) | Writing infrastructure, dependencies, AWS/GCP/K8s patterns |
| 04 | [Variables, Outputs & Locals](./04-terraform-variables.md) | Parameterizing configs, validation, secrets handling |
| 05 | [State Management](./05-terraform-state.md) | Remote backends, locking, import, workspaces, recovery |
| 06 | [Modules](./06-terraform-modules.md) | Writing modules, registry, versioning, composition |
| 07 | [Workflows & Best Practices](./07-terraform-workflows.md) | Project structure, naming, anti-patterns, tagging |
| 08 | [Cloud Patterns](./08-terraform-cloud-patterns.md) | AWS EKS/ALB/Route53, GCP GKE, Azure AKS |
| 09 | [Testing & Validation](./09-terraform-testing.md) | tflint, checkov, Trivy, Terratest, native test framework |
| 10 | [CI/CD Integration](./10-terraform-cicd.md) | GitHub Actions, GitLab CI, Atlantis, TFC |
| 11 | [Interview Q&A](./11-terraform-interview-qa.md) | Core, scenario-based, and advanced Q&A |

---

## ⚡ Quick Reference

### Essential commands

```bash
# Initialize (always first)
terraform init
terraform init -upgrade         # upgrade providers

# Plan & Apply
terraform fmt -recursive        # format first
terraform validate              # syntax check
terraform plan -out=tfplan      # save plan
terraform apply tfplan          # apply saved plan
terraform apply -auto-approve   # skip prompt (CI only)

# Destroy
terraform destroy
terraform destroy -target=aws_instance.web

# State
terraform state list
terraform state show aws_instance.web
terraform state mv aws_instance.old aws_instance.new
terraform state rm aws_instance.unwanted
terraform import aws_instance.web i-abc123

# Inspect
terraform output
terraform output -json
terraform show
terraform graph | dot -Tpng > graph.png

# Workspaces
terraform workspace new staging
terraform workspace select production
terraform workspace list
```

### Common CI steps

```bash
terraform fmt -check -recursive
terraform init
terraform validate
tflint --recursive
trivy config . --exit-code 1 --severity CRITICAL,HIGH
terraform plan -out=tfplan -no-color
terraform apply -auto-approve tfplan
```

---

## 🧠 Key Concepts at a Glance

| Concept | One-line summary |
|---------|-----------------|
| **Provider** | Plugin connecting Terraform to a specific API (AWS, GCP, etc.) |
| **Resource** | A piece of infrastructure managed by Terraform |
| **Data source** | Read-only query of existing infrastructure |
| **State** | JSON file mapping Terraform config to real-world resources |
| **Remote backend** | Where state is stored for teams (S3, GCS, TFC) |
| **State locking** | Prevents concurrent applies from corrupting state |
| **Plan** | Preview of changes before applying — always review! |
| **Apply** | Actually create/update/destroy infrastructure |
| **Module** | Reusable directory of Terraform files |
| **Variable** | Input parameter to a configuration |
| **Local** | Named computed expression within a module |
| **Output** | Value exported from a module |
| **for_each** | Create multiple resources from a map/set — preferred over count |
| **count** | Create N copies of a resource — use for on/off (0 or 1) |
| **depends_on** | Explicit dependency when Terraform can't infer it |
| **lifecycle** | Control resource creation/update/destroy behavior |
| **create_before_destroy** | Create new before destroying old — zero-downtime |
| **prevent_destroy** | Protect a resource from accidental deletion |
| **Drift** | Real infrastructure differs from state (manual changes) |
| **Idempotent** | Run plan+apply N times → same result |
| **DAG** | Dependency graph — enables parallel resource creation |
| **Workspace** | Separate state environments within one configuration |
| **OIDC** | Federated identity — no static credentials in CI |
| **tflint** | Linter for Terraform — catches more than validate |
| **checkov/Trivy** | Security scanner for IaC — finds misconfigurations |
| **Terratest** | Go library for integration testing real infrastructure |
| **Atlantis** | GitOps tool — plan/apply via PR comments |

---

## 🗂️ Folder Structure

```
terraform/
├── 00-terraform-index.md          ← You are here
├── 01-terraform-core-concepts.md
├── 02-terraform-hcl.md
├── 03-terraform-resources.md
├── 04-terraform-variables.md
├── 05-terraform-state.md
├── 06-terraform-modules.md
├── 07-terraform-workflows.md
├── 08-terraform-cloud-patterns.md
├── 09-terraform-testing.md
├── 10-terraform-cicd.md
└── 11-terraform-interview-qa.md
```

---

## 🔗 How Terraform Connects to the Rest of Your Notes

| Topic | Connection |
|-------|-----------|
| **Kubernetes** | Terraform provisions EKS/GKE/AKS clusters, K8s provider manages namespaces/RBAC |
| **Helm** | Terraform can invoke Helm releases via helm provider |
| **Docker** | Terraform provisions ECR/GCR/ACR registries, ECS services |
| **Ansible** | Terraform creates servers → Ansible configures them |
| **Observability** | Terraform provisions CloudWatch, Grafana Cloud, Datadog resources |
| **CI/CD** | GitHub Actions / GitLab CI run Terraform plan/apply |

---

*Notes are living documents — updated as I learn and build.*
