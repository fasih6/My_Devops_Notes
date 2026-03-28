# 🚀 CI/CD Integration

Automating Terraform with GitHub Actions, GitLab CI, and Atlantis.

---

## 📚 Table of Contents

- [1. CI/CD Principles for Terraform](#1-cicd-principles-for-terraform)
- [2. GitHub Actions](#2-github-actions)
- [3. GitLab CI](#3-gitlab-ci)
- [4. Atlantis — GitOps for Terraform](#4-atlantis--gitops-for-terraform)
- [5. Terraform Cloud / HCP Terraform](#5-terraform-cloud--hcp-terraform)
- [Cheatsheet](#cheatsheet)

---

## 1. CI/CD Principles for Terraform

```
PR opened:
  1. terraform fmt --check      → formatting
  2. terraform validate         → syntax
  3. tflint                     → lint
  4. trivy config / checkov     → security
  5. terraform plan             → post plan as PR comment

PR merged to main:
  6. Manual approval (or auto for non-prod)
  7. terraform apply            → deploy
  8. Notify (Slack/Teams)
```

### Key practices

```
✅ Never auto-apply without plan review
✅ Use saved plan files (plan -out / apply planfile)
✅ State locking prevents concurrent applies
✅ Pin provider versions (.terraform.lock.hcl)
✅ Separate workflows per environment
✅ Use OIDC/IAM roles (no static credentials in CI)
✅ Store state in remote backend (S3 + DynamoDB)
```

---

## 2. GitHub Actions

### Complete Terraform workflow

```yaml
# .github/workflows/terraform.yml
name: Terraform

on:
  push:
    branches: [main]
    paths: ['terraform/**']
  pull_request:
    branches: [main]
    paths: ['terraform/**']

permissions:
  contents: read
  id-token: write       # OIDC token for AWS
  pull-requests: write  # comment on PRs

env:
  TF_VERSION: "1.6.0"
  WORKING_DIR: "./terraform/environments/production"

jobs:
  # ── Validate ────────────────────────────────────────────────────
  validate:
    name: Validate
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: ${{ env.WORKING_DIR }}

    steps:
      - uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Format Check
        run: terraform fmt -check -recursive
        working-directory: ./terraform

      - name: Terraform Init
        run: terraform init -backend=false    # skip backend for validation

      - name: Terraform Validate
        run: terraform validate

      - name: Run tflint
        uses: terraform-linters/setup-tflint@v4
        with:
          tflint_version: latest
      - run: tflint --recursive
        working-directory: ./terraform

      - name: Run Trivy security scan
        uses: aquasecurity/trivy-action@master
        with:
          scan-type: config
          scan-ref: ./terraform
          exit-code: 1
          severity: CRITICAL,HIGH

  # ── Plan ────────────────────────────────────────────────────────
  plan:
    name: Plan
    runs-on: ubuntu-latest
    needs: validate
    defaults:
      run:
        working-directory: ${{ env.WORKING_DIR }}

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials (OIDC)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789:role/github-actions-terraform
          aws-region: eu-central-1

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init

      - name: Terraform Plan
        id: plan
        run: |
          terraform plan \
            -var-file=terraform.tfvars \
            -out=tfplan \
            -no-color
        continue-on-error: true   # post plan even if it fails

      - name: Save plan artifact
        uses: actions/upload-artifact@v4
        with:
          name: tfplan
          path: ${{ env.WORKING_DIR }}/tfplan
          retention-days: 7

      - name: Post plan to PR
        uses: actions/github-script@v7
        if: github.event_name == 'pull_request'
        with:
          script: |
            const { data: comments } = await github.rest.issues.listComments({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
            });

            // Delete old plan comments
            const tfComments = comments.filter(c => c.body.includes('Terraform Plan'));
            for (const comment of tfComments) {
              await github.rest.issues.deleteComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                comment_id: comment.id,
              });
            }

            const planOutput = `${{ steps.plan.outputs.stdout }}`;
            const status = '${{ steps.plan.outcome }}' === 'success' ? '✅' : '❌';

            await github.rest.issues.createComment({
              owner: context.repo.owner,
              repo: context.repo.repo,
              issue_number: context.issue.number,
              body: `## ${status} Terraform Plan\n\`\`\`\n${planOutput.substring(0, 65000)}\n\`\`\``,
            });

  # ── Apply ────────────────────────────────────────────────────────
  apply:
    name: Apply
    runs-on: ubuntu-latest
    needs: plan
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    environment: production     # requires manual approval in GitHub
    defaults:
      run:
        working-directory: ${{ env.WORKING_DIR }}

    steps:
      - uses: actions/checkout@v4

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789:role/github-actions-terraform
          aws-region: eu-central-1

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: ${{ env.TF_VERSION }}

      - name: Terraform Init
        run: terraform init

      - name: Download plan artifact
        uses: actions/download-artifact@v4
        with:
          name: tfplan
          path: ${{ env.WORKING_DIR }}

      - name: Terraform Apply
        run: terraform apply -auto-approve tfplan

      - name: Notify on success
        if: success()
        uses: slackapi/slack-github-action@v1
        with:
          payload: '{"text":"✅ Terraform applied successfully to production"}'
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}

      - name: Notify on failure
        if: failure()
        uses: slackapi/slack-github-action@v1
        with:
          payload: '{"text":"❌ Terraform apply FAILED in production"}'
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
```

### AWS OIDC setup (no static credentials)

```hcl
# In Terraform — create the OIDC provider and role
resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = ["6938fd4d98bab03faadb97b34396831e3780aea1"]
}

resource "aws_iam_role" "github_actions" {
  name = "github-actions-terraform"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:myorg/my-repo:*"
        }
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "github_actions_terraform" {
  role       = aws_iam_role.github_actions.name
  policy_arn = aws_iam_policy.terraform_permissions.arn
}
```

---

## 3. GitLab CI

```yaml
# .gitlab-ci.yml
stages:
  - validate
  - plan
  - apply

variables:
  TF_ROOT: "${CI_PROJECT_DIR}/terraform/environments/production"
  TF_VERSION: "1.6.0"

.terraform-base: &terraform-base
  image:
    name: hashicorp/terraform:${TF_VERSION}
    entrypoint: [""]
  before_script:
    - cd ${TF_ROOT}
    - terraform init
  cache:
    key: "${CI_COMMIT_REF_SLUG}"
    paths:
      - ${TF_ROOT}/.terraform/

# ── Validate ──────────────────────────────────────────────────────
fmt:
  stage: validate
  <<: *terraform-base
  script:
    - terraform fmt -check -recursive ${CI_PROJECT_DIR}/terraform
  rules:
    - changes: ["terraform/**"]

validate:
  stage: validate
  <<: *terraform-base
  script:
    - terraform validate
  rules:
    - changes: ["terraform/**"]

security-scan:
  stage: validate
  image:
    name: aquasec/trivy:latest
    entrypoint: [""]
  script:
    - trivy config --exit-code 1 --severity HIGH,CRITICAL ${CI_PROJECT_DIR}/terraform
  rules:
    - changes: ["terraform/**"]

# ── Plan ──────────────────────────────────────────────────────────
plan:
  stage: plan
  <<: *terraform-base
  script:
    - |
      terraform plan \
        -var-file=terraform.tfvars \
        -out=tfplan \
        -no-color | tee plan.txt
  artifacts:
    name: plan
    paths:
      - ${TF_ROOT}/tfplan
      - ${TF_ROOT}/plan.txt
    expire_in: 7 days
    reports:
      terraform: ${TF_ROOT}/plan.txt
  rules:
    - changes: ["terraform/**"]

# ── Apply ──────────────────────────────────────────────────────────
apply:
  stage: apply
  <<: *terraform-base
  environment:
    name: production
    url: https://console.aws.amazon.com
  script:
    - terraform apply -auto-approve tfplan
  dependencies:
    - plan
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
      changes: ["terraform/**"]
      when: manual      # require manual trigger
```

---

## 4. Atlantis — GitOps for Terraform

Atlantis is a self-hosted tool that runs Terraform plan and apply via GitHub/GitLab PR comments.

```bash
# Install Atlantis
helm install atlantis runatlantis/atlantis \
  --set orgAllowlist="github.com/myorg/*" \
  --set github.user="atlantis-bot" \
  --set github.token="$GITHUB_TOKEN" \
  --set github.secret="$WEBHOOK_SECRET" \
  --namespace atlantis \
  --create-namespace
```

### atlantis.yaml

```yaml
# atlantis.yaml — in repo root
version: 3

projects:
  - name: networking
    dir: terraform/environments/production/networking
    workspace: default
    autoplan:
      when_modified: ["*.tf", "*.tfvars", "../../modules/**/*.tf"]
      enabled: true
    apply_requirements: [approved, mergeable]

  - name: eks
    dir: terraform/environments/production/eks
    workspace: default
    autoplan:
      when_modified: ["*.tf", "*.tfvars", "../../modules/eks/**/*.tf"]
      enabled: true
    apply_requirements: [approved, mergeable]
    workflow: custom_workflow

workflows:
  custom_workflow:
    plan:
      steps:
        - init
        - run: trivy config . --exit-code 1
        - plan:
            extra_args: ["-var-file=production.tfvars"]
    apply:
      steps:
        - apply
```

### Atlantis PR workflow

```
Developer opens PR
    │
    ▼
Atlantis auto-runs terraform plan
    │
    ▼
Atlantis posts plan output as PR comment:
  "Ran Plan for project: networking dir: terraform/..."
  "+ 2 to add, 0 to change, 0 to destroy"
    │
    ▼
Team reviews plan in PR
    │
    ▼
Reviewer comments: "atlantis apply"
    │
    ▼
Atlantis runs terraform apply
Posts result to PR
    │
    ▼
PR can be merged
```

---

## 5. Terraform Cloud / HCP Terraform

HashiCorp's managed Terraform service — handles state, runs, and team collaboration.

```hcl
# versions.tf
terraform {
  cloud {
    organization = "my-company"
    workspaces {
      name = "production-eks"
      # OR use tags for multiple workspaces:
      # tags = ["production"]
    }
  }
}
```

```bash
# Login to Terraform Cloud
terraform login

# Init (connects to TFC workspace)
terraform init

# Plan runs in TFC (not locally)
terraform plan

# Apply (can require approval in TFC UI)
terraform apply
```

### TFC vs self-managed

| | Terraform Cloud | Self-managed (S3 + GitHub Actions) |
|--|----------------|-----------------------------------|
| **Cost** | Free tier available | S3 + compute costs |
| **State** | Managed | S3 + DynamoDB |
| **Runs** | Remote (TFC) | CI runners |
| **Setup** | Minimal | More setup |
| **Team features** | Built-in | Custom |
| **Best for** | Teams wanting managed solution | Teams with existing CI/CD |

---

## Cheatsheet

```bash
# GitHub Actions — key steps
- uses: hashicorp/setup-terraform@v3
  with: { terraform_version: "1.6.0" }

- uses: aws-actions/configure-aws-credentials@v4
  with:
    role-to-assume: arn:aws:iam::123456789:role/github-actions
    aws-region: eu-central-1

# Terraform steps in CI
terraform fmt -check -recursive
terraform init
terraform validate
tflint --recursive
trivy config . --exit-code 1 --severity CRITICAL,HIGH
terraform plan -out=tfplan -no-color
terraform apply -auto-approve tfplan

# Atlantis commands in PR comments
atlantis plan         → run plan
atlantis apply        → run apply (after approval)
atlantis plan -d path → plan specific directory
```

---

*Next: [Interview Q&A →](./11-interview-qa.md)*
