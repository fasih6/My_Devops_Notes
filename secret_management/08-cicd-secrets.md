# CI/CD Secrets — GitLab CI, Jenkins, OIDC Secretless Auth

## The CI/CD Secrets Problem

CI/CD pipelines need secrets to do their jobs:
- Docker registry credentials to push images
- Cloud provider credentials to deploy infrastructure
- Kubernetes credentials to deploy applications
- API keys for external services (Slack notifications, SonarQube, etc.)

The challenge: how do you give a pipeline access to secrets without:
- Hardcoding them in pipeline YAML (committed to Git)
- Creating long-lived credentials that never rotate
- Giving pipelines broader access than they need

---

## The Evolution of CI/CD Secret Management

```
Level 0 — Hardcoded (never do this):
  pipeline.yaml: STRIPE_KEY=sk_live_abc123
  Problem: in Git forever, anyone with repo access has the key

Level 1 — CI/CD platform variables:
  Secret stored in GitLab/Jenkins UI
  Injected as env var at runtime
  Better: not in Git; but broad access, no rotation, no audit

Level 2 — External secret store + static credentials:
  Pipeline fetches secrets from Vault/Key Vault using a token
  Better: centralized, audited; but pipeline still needs a token → back to Level 1

Level 3 — OIDC / Workload Identity (secretless auth):
  Pipeline authenticates with a signed JWT (issued per job)
  No pre-shared secrets needed at all
  Best: short-lived, scoped, no credential management
```

Level 3 is the gold standard. Let's understand each in detail.

---

## GitLab CI — Secret Management Approaches

### Approach 1: GitLab CI/CD Variables (Level 1)

GitLab stores secrets as masked CI/CD variables, injected as environment variables at pipeline runtime.

```yaml
# .gitlab-ci.yml
deploy:
  stage: deploy
  script:
    - echo "Deploying with $STRIPE_API_KEY"    # Variable injected automatically
    - kubectl --token="$K8S_TOKEN" apply -f manifests/
```

```
Variable configuration in GitLab UI:
  Settings → CI/CD → Variables
  Key: STRIPE_API_KEY
  Value: sk_live_abc123
  Type: Variable (or File)
  Protected: true    ← only on protected branches
  Masked: true       ← value hidden in job logs
  Environment scope: production  ← only injected in prod environment
```

**Variable types:**
- `Variable` — injected as environment variable
- `File` — written to a temp file, `$VARNAME` contains the file path (useful for kubeconfig, certificates)

**Variable scoping:**
```
Scope: *                 → all branches, all environments
Scope: production        → only jobs with environment: production
Protected: true          → only protected branches (main, release/*)
```

**Limitations of CI/CD variables:**
- No automatic rotation
- Broad access — anyone who can read the variable in GitLab UI has the secret
- No fine-grained audit trail per pipeline job
- Static — long-lived credentials

### Approach 2: GitLab + HashiCorp Vault (JWT Auth)

GitLab can authenticate to Vault using its built-in OIDC JWT token — no pre-shared Vault token needed.

```yaml
# .gitlab-ci.yml
variables:
  VAULT_ADDR: "https://vault.internal:8200"

fetch-secrets:
  stage: .pre
  image: hashicorp/vault:latest
  id_tokens:
    VAULT_ID_TOKEN:
      aud: "https://vault.internal"   # Audience matches Vault JWT config
  script:
    # Authenticate to Vault using GitLab's OIDC token
    - export VAULT_TOKEN=$(vault write -field=token auth/jwt/login \
        role=gitlab-ci \
        jwt=$VAULT_ID_TOKEN)

    # Fetch secrets
    - export DB_PASSWORD=$(vault kv get -field=password secret/checkout/db)
    - export STRIPE_KEY=$(vault kv get -field=api_key secret/checkout/stripe)

    # Write to dotenv file for downstream jobs
    - echo "DB_PASSWORD=$DB_PASSWORD" >> secrets.env
    - echo "STRIPE_KEY=$STRIPE_KEY" >> secrets.env
  artifacts:
    reports:
      dotenv: secrets.env     # Passes env vars to downstream jobs
```

**Vault configuration for GitLab JWT auth:**
```bash
vault auth enable jwt

vault write auth/jwt/config \
  jwks_url="https://gitlab.com/-/jwks" \
  bound_issuer="https://gitlab.com"

vault write auth/jwt/role/gitlab-ci \
  role_type="jwt" \
  bound_claims_type="glob" \
  bound_claims='{
    "project_path": "myorg/myrepo",
    "ref_type": "branch",
    "ref": "main"
  }' \
  user_claim="sub" \
  policies="gitlab-ci-policy" \
  ttl="20m"
```

The `bound_claims` ensure only pipelines from the specific repo and branch can authenticate. A forked repo or a feature branch gets a different JWT claim and is denied.

### Approach 3: GitLab + Azure Key Vault (OIDC)

GitLab can authenticate to Azure using its OIDC token — exchange for an Azure access token, then call Key Vault:

```yaml
# .gitlab-ci.yml
fetch-azure-secrets:
  stage: .pre
  id_tokens:
    AZURE_ID_TOKEN:
      aud: "api://AzureADTokenExchange"
  script:
    # Exchange GitLab OIDC token for Azure access token
    - |
      AZURE_TOKEN=$(curl -s -X POST \
        "https://login.microsoftonline.com/$AZURE_TENANT_ID/oauth2/v2.0/token" \
        -d "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
        -d "client_id=$AZURE_CLIENT_ID" \
        -d "client_assertion_type=urn:ietf:params:oauth:client-assertion-type:jwt-bearer" \
        -d "client_assertion=$AZURE_ID_TOKEN" \
        -d "scope=https://vault.azure.net/.default" \
        -d "requested_token_use=on_behalf_of" | jq -r '.access_token')

    # Fetch secret from Azure Key Vault
    - |
      DB_PASSWORD=$(curl -s \
        -H "Authorization: Bearer $AZURE_TOKEN" \
        "https://my-keyvault.vault.azure.net/secrets/checkout-db-password?api-version=7.4" \
        | jq -r '.value')
```

**Azure configuration — federated identity for GitLab:**
```bash
# Create user-assigned managed identity for GitLab CI
az identity create \
  --resource-group myRG \
  --name gitlab-ci-identity

# Create federated credential
az identity federated-credential create \
  --identity-name gitlab-ci-identity \
  --resource-group myRG \
  --name gitlab-federation \
  --issuer "https://gitlab.com" \
  --subject "project_path:myorg/myrepo:ref_type:branch:ref:main" \
  --audiences "api://AzureADTokenExchange"

# Grant Key Vault Secrets User role
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $(az identity show --name gitlab-ci-identity --resource-group myRG \
    --query principalId -o tsv) \
  --scope /subscriptions/<sub>/.../vaults/my-keyvault
```

No client secret needed. GitLab's JWT is exchanged for an Azure token automatically.

### GitLab Secret Detection

GitLab includes built-in secret detection that scans commits and MRs for accidentally committed secrets:

```yaml
# .gitlab-ci.yml — enable secret detection
include:
  - template: Security/Secret-Detection.gitlab-ci.yml

secret_detection:
  variables:
    SECRET_DETECTION_HISTORIC_SCAN: "true"  # Scan full git history
```

GitLab Secret Detection uses gitleaks rules to detect patterns like AWS keys, GitHub tokens, Stripe keys, etc. Failed jobs block MR merges when configured as required.

---

## Jenkins — Secret Management Approaches

### Jenkins Credentials Store (Built-in)

Jenkins has a built-in credentials store accessed via the Credentials plugin:

```groovy
// Jenkinsfile — using stored credentials
pipeline {
  agent any
  stages {
    stage('Deploy') {
      steps {
        // Username + password
        withCredentials([usernamePassword(
          credentialsId: 'checkout-db-creds',
          usernameVariable: 'DB_USER',
          passwordVariable: 'DB_PASS'
        )]) {
          sh 'kubectl set env deploy/checkout DB_USER=$DB_USER DB_PASS=$DB_PASS'
        }

        // Secret text (single value)
        withCredentials([string(
          credentialsId: 'stripe-api-key',
          variable: 'STRIPE_KEY'
        )]) {
          sh './deploy.sh'
        }

        // File (kubeconfig, certificate)
        withCredentials([file(
          credentialsId: 'prod-kubeconfig',
          variable: 'KUBECONFIG'
        )]) {
          sh 'kubectl apply -f manifests/'
        }

        // SSH key
        withCredentials([sshUserPrivateKey(
          credentialsId: 'deploy-ssh-key',
          keyFileVariable: 'SSH_KEY',
          usernameVariable: 'SSH_USER'
        )]) {
          sh 'ssh -i $SSH_KEY $SSH_USER@server.internal "sudo systemctl restart app"'
        }
      }
    }
  }
}
```

**Credential scopes in Jenkins:**
- `Global` — available to all jobs in all folders
- `System` — only for Jenkins internal use (email, agents)
- `Folder` — only jobs within a specific folder
- `Pipeline` — only within a specific pipeline (most restrictive)

Use folder-scoped credentials to limit blast radius: the payment team's credentials are in the payment folder, not accessible to the checkout team.

### Jenkins + HashiCorp Vault Plugin

The HashiCorp Vault plugin for Jenkins fetches secrets from Vault at pipeline runtime:

```groovy
// Jenkinsfile — using Vault plugin
pipeline {
  agent any
  environment {
    // Vault plugin injects secrets as env vars
    SECRET = vault(
      path: 'secret/checkout/db',
      secretValues: [
        [envVar: 'DB_PASSWORD', vaultKey: 'password'],
        [envVar: 'DB_USERNAME', vaultKey: 'username']
      ]
    )
  }
  stages {
    stage('Deploy') {
      steps {
        sh 'echo "Deploying with $DB_USERNAME"'
      }
    }
  }
}
```

**Jenkins global Vault configuration:**
```groovy
// jenkins.yaml (JCasC)
unclassified:
  hashicorpVault:
    configuration:
      vaultUrl: "https://vault.internal:8200"
      vaultCredentialId: "vault-approle"   # Jenkins credential containing AppRole secret-id
      engineVersion: 2
```

### Jenkins AppRole Auth for Vault

```bash
# Create AppRole for Jenkins
vault write auth/approle/role/jenkins \
  secret_id_ttl=10m \
  token_ttl=20m \
  token_max_ttl=30m \
  policies=jenkins-policy

# Jenkins stores the Role ID (public) as a regular credential
# Jenkins fetches a fresh Secret ID per build from a trusted source
```

### Masking Secrets in Jenkins Logs

Always mask secrets in logs. Jenkins does this automatically with `withCredentials`, but be careful:

```groovy
// BAD — secret visible in logs
sh "curl -H 'Authorization: Bearer ${STRIPE_KEY}' https://api.stripe.com"

// GOOD — withCredentials masks the value in logs
withCredentials([string(credentialsId: 'stripe-key', variable: 'STRIPE_KEY')]) {
  sh "curl -H 'Authorization: Bearer ${STRIPE_KEY}' https://api.stripe.com"
  // Jenkins replaces STRIPE_KEY value with **** in log output
}
```

**Important:** Jenkins masking is not foolproof. If the secret value appears in a base64-encoded form or is split across multiple arguments, it may not be masked.

---

## OIDC / Workload Identity — Secretless CI/CD (Best Practice)

### The Problem with All Above Approaches

Even with Vault or Key Vault integration, CI/CD pipelines still need a credential to authenticate to the secret store. That credential is itself a secret — the bootstrap problem.

```
"How does the pipeline authenticate to Vault?"
→ "With a Vault AppRole Secret ID"
"Where is the Secret ID stored?"
→ "In a GitLab CI variable"
→ Back to Level 1 — a long-lived secret in the CI platform
```

### OIDC Solves the Bootstrap Problem

Modern CI/CD platforms (GitLab, GitHub Actions, CircleCI) issue a signed OIDC JWT token per job. This token:
- Is cryptographically signed by the CI platform
- Contains claims about the job (repo, branch, pipeline ID)
- Expires after minutes
- Requires no pre-shared secret to verify — verifiers check against the platform's public keys

```
Secretless flow:

  Pipeline job starts
       ↓
  CI platform issues OIDC JWT (signed, short-lived, contains job claims)
       ↓
  Pipeline sends JWT to Vault/AKV/AWS
       ↓
  Vault/AKV verifies JWT against CI platform's public JWKS endpoint
  Checks bound_claims: is this from the right repo/branch?
       ↓
  If verified: issues short-lived access token/secret
       ↓
  Pipeline uses secret → secret expires after job
       ↓
  No pre-shared credentials anywhere
```

### GitHub Actions + Azure (OIDC)

```yaml
# .github/workflows/deploy.yaml
name: Deploy
on:
  push:
    branches: [main]

permissions:
  id-token: write     # Required to request OIDC token
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      # Azure login using OIDC — no credentials stored anywhere
      - uses: azure/login@v1
        with:
          client-id: ${{ vars.AZURE_CLIENT_ID }}
          tenant-id: ${{ vars.AZURE_TENANT_ID }}
          subscription-id: ${{ vars.AZURE_SUBSCRIPTION_ID }}

      # Now fetch secrets from Key Vault using the authenticated identity
      - name: Get secrets from Key Vault
        uses: azure/get-keyvault-secrets@v1
        with:
          keyvault: my-keyvault
          secrets: 'checkout-db-password, stripe-api-key'
        id: keyvault-secrets

      - name: Deploy
        env:
          DB_PASSWORD: ${{ steps.keyvault-secrets.outputs.checkout-db-password }}
          STRIPE_KEY: ${{ steps.keyvault-secrets.outputs.stripe-api-key }}
        run: ./scripts/deploy.sh
```

**Azure configuration for GitHub Actions OIDC:**
```bash
az identity federated-credential create \
  --identity-name github-actions-identity \
  --resource-group myRG \
  --name github-main \
  --issuer "https://token.actions.githubusercontent.com" \
  --subject "repo:myorg/myrepo:ref:refs/heads/main" \
  --audiences "api://AzureADTokenExchange"
```

The `client-id`, `tenant-id`, and `subscription-id` are not secrets — they're IDs that identify which Azure resources to use. The actual authentication is done cryptographically via the OIDC token.

---

## Secret Scanning in CI/CD

Every CI/CD pipeline should scan for accidentally committed secrets:

```yaml
# GitLab — built-in secret detection
include:
  - template: Security/Secret-Detection.gitlab-ci.yml

# GitHub Actions — using gitleaks
- name: Scan for secrets
  uses: gitleaks/gitleaks-action@v2
  env:
    GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}

# Jenkins — run gitleaks in pipeline
stage('Secret Scan') {
  steps {
    sh 'gitleaks detect --source . --report-format json --report-path gitleaks-report.json'
  }
  post {
    always {
      archiveArtifacts artifacts: 'gitleaks-report.json'
    }
  }
}
```

---

## Interview Questions — CI/CD Secrets

**Q: What is the bootstrap problem in CI/CD secrets management and how does OIDC solve it?**
A: The bootstrap problem is: to fetch secrets from a secret store, the pipeline needs a credential. But that credential is itself a secret that needs to be stored somewhere — usually a CI platform variable, which is a long-lived, broadly accessible credential. OIDC solves this because CI platforms (GitLab, GitHub Actions) issue a signed JWT per job. The secret store (Vault, Azure Key Vault) verifies this JWT cryptographically against the platform's public keys — no pre-shared secret needed. Credentials are job-scoped and expire in minutes.

**Q: How do you scope secrets in GitLab CI to prevent a feature branch from accessing production secrets?**
A: Use GitLab CI variable scoping with environment scope set to `production` and the variable marked as `Protected`. Protected variables are only injected into pipelines running on protected branches (main, release/*). Feature branches, which are not protected, don't receive the variable. For Vault JWT auth, use `bound_claims` to restrict which GitLab refs can authenticate — for example, binding to `ref: main` means only the main branch pipeline gets a Vault token.

**Q: What is the difference between using Jenkins withCredentials vs directly accessing environment variables for secrets?**
A: `withCredentials` provides two key benefits: it automatically masks the secret value in build logs (replacing it with `****`), and it scopes the secret to only the block where it's needed — reducing the window of exposure. Direct environment variables are visible throughout the entire pipeline and may appear unmasked in logs, especially if the script echoes variables or a command prints its arguments. Always use `withCredentials` for any sensitive value in Jenkins.

**Q: How would you prevent secrets from being committed to a GitLab repo?**
A: Multiple layers: (1) pre-commit hooks using gitleaks or detect-secrets that scan staged changes before commit, (2) GitLab's built-in Secret Detection CI template that scans every MR, (3) GitLab repository push rules that block commits matching secret patterns, (4) configure the MR pipeline to require the secret detection job to pass before merge. Defense in depth — pre-commit catches most cases, CI/CD catches anything that slipped through, and push rules are a last resort.
