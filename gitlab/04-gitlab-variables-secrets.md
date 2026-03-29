# 🔐 Variables & Secrets

CI/CD variables, masked values, Vault integration, and secure secret management in GitLab.

---

## 📚 Table of Contents

- [1. CI/CD Variables](#1-cicd-variables)
- [2. Predefined Variables](#2-predefined-variables)
- [3. Variable Precedence](#3-variable-precedence)
- [4. Masked & Protected Variables](#4-masked--protected-variables)
- [5. Variable Types & Files](#5-variable-types--files)
- [6. Vault Integration](#6-vault-integration)
- [7. External Secret Managers](#7-external-secret-managers)
- [8. Security Best Practices](#8-security-best-practices)
- [Cheatsheet](#cheatsheet)

---

## 1. CI/CD Variables

Variables are key-value pairs injected into pipeline jobs as environment variables.

### Setting variables

```
Locations (in order of precedence):
  1. .gitlab-ci.yml (in job or globally)
  2. GitLab UI → Settings → CI/CD → Variables
  3. GitLab API
  4. Trigger API (--form variables[KEY]=value)
  5. Schedule variables
```

### In .gitlab-ci.yml

```yaml
# Global variables (available to all jobs)
variables:
  APP_ENV: production
  LOG_LEVEL: info
  MAX_RETRIES: "3"              # always strings in CI
  DOCKER_DRIVER: overlay2

# Job-level variables (override global)
test:
  variables:
    APP_ENV: test
    DATABASE_URL: "postgresql://postgres@localhost/test"
  script:
    - echo $APP_ENV             # prints "test"
    - echo $LOG_LEVEL           # prints "info" (from global)
```

### In GitLab UI

```
Settings → CI/CD → Variables → Add variable

Fields:
  Type:         Variable (string) or File
  Key:          VARIABLE_NAME (all caps, underscore separated)
  Value:        the secret value
  Protected:    only available in protected branches/tags
  Masked:       hidden from job logs
  Expand:       whether $VAR references in value are expanded
  Environments: restrict to specific environments
```

---

## 2. Predefined Variables

GitLab provides hundreds of predefined variables automatically. Most important ones:

### Repository & commit info

```bash
CI_COMMIT_SHA              # full commit SHA: abc123def456...
CI_COMMIT_SHORT_SHA        # short SHA: abc123de
CI_COMMIT_BRANCH           # branch name: main
CI_COMMIT_REF_NAME         # branch or tag: main / v1.2.3
CI_COMMIT_REF_SLUG         # URL-safe version: main / v1-2-3
CI_COMMIT_TAG              # tag name (only set for tag pipelines)
CI_COMMIT_MESSAGE          # commit message
CI_COMMIT_TITLE            # first line of commit message
CI_COMMIT_AUTHOR           # "Name <email>"
CI_COMMIT_TIMESTAMP        # ISO 8601 timestamp

CI_DEFAULT_BRANCH          # usually "main"
CI_PROJECT_PATH            # group/project: mygroup/my-project
CI_PROJECT_NAME            # project name: my-project
CI_PROJECT_NAMESPACE       # group: mygroup
CI_PROJECT_URL             # https://gitlab.com/mygroup/my-project
```

### Pipeline info

```bash
CI_PIPELINE_ID             # unique pipeline ID (global)
CI_PIPELINE_IID            # pipeline ID within project (sequential)
CI_PIPELINE_SOURCE         # push, merge_request_event, schedule, etc.
CI_PIPELINE_URL            # URL to view the pipeline
CI_JOB_ID                  # job ID
CI_JOB_NAME               # job name as defined in .gitlab-ci.yml
CI_JOB_STAGE              # stage name
CI_JOB_URL                # URL to view the job
CI_JOB_TOKEN              # token for API authentication
CI_NODE_INDEX             # 1-based index for parallel jobs
CI_NODE_TOTAL             # total parallel instances
```

### Registry & deployment

```bash
CI_REGISTRY                # registry.gitlab.com (or self-hosted)
CI_REGISTRY_IMAGE          # registry.gitlab.com/group/project
CI_REGISTRY_USER           # gitlab-ci-token (for login)
CI_REGISTRY_PASSWORD       # token to login to registry

CI_ENVIRONMENT_NAME        # environment name (if set in job)
CI_ENVIRONMENT_SLUG        # URL-safe environment name
CI_ENVIRONMENT_URL         # environment URL
```

### Runner info

```bash
CI_RUNNER_ID               # runner ID
CI_RUNNER_DESCRIPTION      # runner description
CI_RUNNER_TAGS             # comma-separated runner tags
CI_BUILDS_DIR              # where builds are stored
CI_PROJECT_DIR             # /builds/group/project (root of repo)
```

### Merge request variables (only set in MR pipelines)

```bash
CI_MERGE_REQUEST_ID              # MR database ID
CI_MERGE_REQUEST_IID             # MR number within project
CI_MERGE_REQUEST_TITLE           # MR title
CI_MERGE_REQUEST_SOURCE_BRANCH_NAME   # feature branch
CI_MERGE_REQUEST_TARGET_BRANCH_NAME   # usually main
CI_MERGE_REQUEST_APPROVED        # true/false
CI_OPEN_MERGE_REQUESTS           # list of open MRs for this branch
```

### Useful in scripts

```yaml
build:
  script:
    # Use predefined vars for tagging
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA .
    - docker tag $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA $CI_REGISTRY_IMAGE:latest

    # Create release name including branch
    - helm upgrade --install my-app-$CI_COMMIT_REF_SLUG ./chart

    # Conditional logic
    - |
      if [ "$CI_COMMIT_BRANCH" == "main" ]; then
        echo "Deploying to production"
      else
        echo "Running in $CI_COMMIT_BRANCH"
      fi
```

---

## 3. Variable Precedence

Variables are resolved in this order (highest wins):

```
1. Trigger variables (API --form variables[KEY]=value)
2. Scheduled pipeline variables
3. Manual pipeline variables (run pipeline UI)
4. Project variables (Settings → CI/CD)
5. Group variables (parent group → CI/CD)
6. Instance variables (admin level)
7. .gitlab-ci.yml job variables
8. .gitlab-ci.yml global variables
9. Predefined variables (lowest)
```

```yaml
# Example: PROJECT variable DATABASE_URL overrides this:
variables:
  DATABASE_URL: "postgresql://localhost/dev"   # lowest priority

# UI variable DATABASE_URL="postgresql://prod-db/prod" wins
```

---

## 4. Masked & Protected Variables

### Masked variables

```
Masked = value is hidden in job logs

Requirements for masking:
  - Value is a single line
  - At least 8 characters
  - Only printable ASCII (base64 encoded if needed)
  - No multi-line values → use File type instead

Example:
  DB_PASSWORD = "my-secret-password"  → shows as [MASKED] in logs

# Manual masking in scripts (if variable not masked in UI):
echo "PASS=${DB_PASSWORD:0:3}***"    # show only first 3 chars
echo "::add-mask::$MY_VAR"           # GitHub Actions equivalent (GitLab does it automatically)
```

### Protected variables

```
Protected = only available in pipelines for protected branches/tags

Protected branches: main, production, release/*
Protected variables:
  PROD_DB_PASSWORD    → only available in main/production pipelines
  DEPLOY_KEY          → only usable in protected branches

Jobs on feature branches: PROD_DB_PASSWORD = ""  (empty)
Jobs on main: PROD_DB_PASSWORD = "actual-value"

Set a branch as protected:
  Settings → Repository → Protected Branches → Add
```

### Best practice: Mask + Protect sensitive variables

```
For production secrets:
  ✅ Masked (hidden from logs)
  ✅ Protected (only available in protected branches)
  ✅ Scoped to production environment
```

---

## 5. Variable Types & Files

### Variable type (default)

```yaml
# String variable
DB_HOST = "postgres.production.internal"
```

### File type

```yaml
# File variable — value is written to a temp file, variable = path to file
# Use for: certificates, kubeconfig, .env files, SSH keys

# In GitLab UI:
#   Type: File
#   Key: KUBECONFIG
#   Value: (paste entire kubeconfig YAML)
#
# In job: KUBECONFIG = /path/to/temp/file

deploy:
  script:
    - kubectl --kubeconfig=$KUBECONFIG get pods

# For SSH keys:
#   Type: File
#   Key: SSH_PRIVATE_KEY
#   Value: (paste private key, including header/footer)
```

### Variable expansion

```yaml
variables:
  BASE_URL: "https://api.example.com"
  API_URL: "${BASE_URL}/v1"    # expands to https://api.example.com/v1

# Disable expansion:
variables:
  RAW_VALUE:
    value: "literal $VAR not expanded"
    expand: false
```

---

## 6. Vault Integration

HashiCorp Vault integration lets jobs fetch secrets directly from Vault — no secrets stored in GitLab.

### JWT authentication

```yaml
# .gitlab-ci.yml
deploy:
  secrets:
    DATABASE_PASSWORD:
      vault: production/db/password@secret    # path@mount
      # vault: <path>/<secret>/<key>@<engine-mount>
    API_KEY:
      vault: production/api/key@secret
  script:
    - echo "DB password from Vault: $DATABASE_PASSWORD"
```

### Vault server configuration

```hcl
# Enable JWT auth in Vault
vault auth enable jwt

vault write auth/jwt/config \
  jwks_url="https://gitlab.com/-/jwks" \
  bound_issuer="https://gitlab.com"

# Create policy
vault policy write ci-deploy - <<EOF
path "secret/data/production/*" {
  capabilities = ["read"]
}
EOF

# Create role
vault write auth/jwt/role/ci-deploy \
  role_type="jwt" \
  policies="ci-deploy" \
  bound_claims_type="glob" \
  bound_claims.project_path="mygroup/my-project*" \
  bound_claims.ref_type="branch" \
  bound_claims.ref="main" \
  user_claim="user_email"
```

### Configure in GitLab project

```
Settings → CI/CD → Variables → Add variable:
  VAULT_SERVER_URL = https://vault.example.com
  VAULT_AUTH_ROLE  = ci-deploy
  VAULT_AUTH_PATH  = jwt
```

---

## 7. External Secret Managers

### AWS Secrets Manager / Parameter Store

```yaml
# Install AWS CLI in job, then fetch secrets
deploy:
  before_script:
    # Fetch secret from SSM (uses IRSA or runner IAM role)
    - export DB_PASSWORD=$(aws ssm get-parameter
        --name "/production/db/password"
        --with-decryption
        --query "Parameter.Value"
        --output text)
  script:
    - ./deploy.sh
```

### Using CI variables for AWS authentication

```yaml
# Never hardcode AWS keys — use variables
variables:
  AWS_DEFAULT_REGION: eu-central-1
  # AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY set in GitLab UI
  # Better: use OIDC/ID token for keyless auth
```

### OIDC / ID token (keyless AWS auth)

```yaml
deploy:
  id_tokens:
    AWS_OIDC_TOKEN:
      aud: sts.amazonaws.com
  script:
    - |
      # Exchange GitLab JWT for AWS credentials
      CREDS=$(aws sts assume-role-with-web-identity \
        --role-arn arn:aws:iam::123456789:role/gitlab-ci \
        --role-session-name gitlab-ci-$CI_JOB_ID \
        --web-identity-token $AWS_OIDC_TOKEN \
        --duration-seconds 3600)

      export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r '.Credentials.AccessKeyId')
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r '.Credentials.SecretAccessKey')
      export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r '.Credentials.SessionToken')

    - aws s3 cp dist/ s3://my-bucket/ --recursive
```

---

## 8. Security Best Practices

```
DO:
✅ Mask all sensitive variables
✅ Protect production secrets (protected variables)
✅ Use Vault or cloud secrets managers for credentials
✅ Use OIDC/keyless auth for cloud providers (no static keys)
✅ Scope variables to specific environments
✅ Rotate secrets regularly
✅ Audit variable access logs

DON'T:
❌ Hardcode secrets in .gitlab-ci.yml (committed to Git!)
❌ Echo or print secret variables in scripts
❌ Use non-protected variables for production deployments
❌ Share runner tokens
❌ Store .env files with secrets in the repository

# If you accidentally expose a secret:
# 1. Rotate/revoke the secret immediately
# 2. Remove from git history: git filter-branch or BFG
# 3. Audit who might have seen it
```

---

## Cheatsheet

```yaml
# Global variables
variables:
  APP_ENV: production
  LOG_LEVEL: info

# Job variables
my-job:
  variables:
    LOCAL_VAR: value
  script:
    - echo $LOCAL_VAR
    - echo $APP_ENV              # from global
    - echo $CI_COMMIT_SHORT_SHA  # predefined

# Common predefined variables
$CI_REGISTRY_IMAGE       # full image path
$CI_COMMIT_SHORT_SHA     # short git SHA
$CI_COMMIT_REF_SLUG      # URL-safe branch name
$CI_PROJECT_DIR          # repo root path
$CI_PIPELINE_SOURCE      # push, schedule, merge_request_event
$CI_ENVIRONMENT_NAME     # staging, production

# Vault secrets
secrets:
  MY_SECRET:
    vault: path/to/secret/key@mount

# OIDC token for keyless auth
id_tokens:
  AWS_TOKEN:
    aud: sts.amazonaws.com
```

---

*Next: [Docker & Container Builds →](./05-docker-container-builds.md)*
