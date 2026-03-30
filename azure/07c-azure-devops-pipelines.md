# Azure DevOps Pipelines 🚀

> Part of my DevOps journey — azure folder
> Note: Azure DevOps (ADO) is widely used in Germany and enterprise environments

---

## What is Azure DevOps?

Azure DevOps is Microsoft's integrated DevOps platform — a suite of tools for the entire software delivery lifecycle.

```
Azure DevOps
├── Boards       → work items, sprints, backlogs (like Jira)
├── Repos        → Git repositories (like GitHub)
├── Pipelines    → CI/CD automation ← focus of this file
├── Test Plans   → manual and automated testing
└── Artifacts    → package management (npm, NuGet, Maven, Docker)
```

**Azure Pipelines** supports:
- YAML pipelines (recommended — pipeline as code)
- Classic pipelines (GUI-based — legacy)
- Hosted agents (Microsoft-managed) or self-hosted agents

---

## Key Concepts

| Term | What it is |
|------|-----------|
| **Pipeline** | The automation definition (YAML file) |
| **Stage** | A logical phase (Build, Test, Deploy) |
| **Job** | A unit of work that runs on an agent |
| **Step** | A single task or script within a job |
| **Agent** | The machine that runs the job |
| **Agent Pool** | Collection of agents |
| **Environment** | A deployment target with history and approvals |
| **Service Connection** | Credentials to connect to external services (Azure, GitHub, Docker Hub) |
| **Variable Group** | Shared variables across pipelines (in Library) |
| **Template** | Reusable YAML fragment |
| **Artifact** | Files produced by a pipeline stage |

---

## YAML Pipeline Structure

```yaml
# azure-pipelines.yml — lives at repo root

name: $(Build.DefinitionName)-$(Build.BuildId)   # build name format

trigger:
  branches:
    include:
      - main
      - release/*
  paths:
    exclude:
      - docs/*
      - '*.md'

pr:
  branches:
    include:
      - main

variables:
  - group: myapp-prod-vars          # variable group from Library
  - name: imageRepository
    value: 'myapp'
  - name: containerRegistry
    value: 'myappregistry.azurecr.io'
  - name: tag
    value: '$(Build.BuildId)'

pool:
  vmImage: ubuntu-latest             # Microsoft-hosted agent

stages:
  - stage: Build
    displayName: 'Build & Test'
    jobs:
      - job: BuildJob
        steps:
          - task: NodeTool@0
            inputs:
              versionSpec: '20.x'

          - script: npm ci
            displayName: 'Install dependencies'

          - script: npm test -- --reporters=junit --reporters=default
            displayName: 'Run tests'

          - task: PublishTestResults@2
            inputs:
              testResultsFormat: JUnit
              testResultsFiles: '**/test-results.xml'
            condition: succeededOrFailed()

          - task: PublishCodeCoverageResults@1
            inputs:
              codeCoverageTool: Cobertura
              summaryFileLocation: '**/coverage/cobertura-coverage.xml'

  - stage: Docker
    displayName: 'Build & Push Image'
    dependsOn: Build
    condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))
    jobs:
      - job: DockerBuild
        steps:
          - task: Docker@2
            displayName: 'Build and push to ACR'
            inputs:
              command: buildAndPush
              repository: $(imageRepository)
              dockerfile: Dockerfile
              containerRegistry: 'myapp-acr-connection'   # service connection name
              tags: |
                $(tag)
                latest

  - stage: DeployStaging
    displayName: 'Deploy to Staging'
    dependsOn: Docker
    jobs:
      - deployment: DeployStaging
        displayName: 'Deploy to AKS staging'
        environment: staging                              # environment name in ADO
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureCLI@2
                  displayName: 'Deploy Helm chart'
                  inputs:
                    azureSubscription: 'my-azure-service-connection'
                    scriptType: bash
                    scriptLocation: inlineScript
                    inlineScript: |
                      az aks get-credentials -n my-aks -g myapp-prod-rg
                      helm upgrade myapp ./helm/myapp \
                        --namespace staging \
                        --create-namespace \
                        --set image.repository=$(containerRegistry)/$(imageRepository) \
                        --set image.tag=$(tag) \
                        --wait --timeout 5m

  - stage: DeployProduction
    displayName: 'Deploy to Production'
    dependsOn: DeployStaging
    jobs:
      - deployment: DeployProd
        displayName: 'Deploy to AKS production'
        environment: production                           # requires approval configured in ADO
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureCLI@2
                  displayName: 'Deploy to production'
                  inputs:
                    azureSubscription: 'my-azure-service-connection'
                    scriptType: bash
                    scriptLocation: inlineScript
                    inlineScript: |
                      helm upgrade myapp ./helm/myapp \
                        --namespace production \
                        --set image.tag=$(tag) \
                        --wait --timeout 10m
```

---

## Triggers

```yaml
# Push trigger
trigger:
  branches:
    include: [main, develop]
    exclude: [feature/*]
  paths:
    include: [src/**, helm/**]
    exclude: [docs/**]
  tags:
    include: ['v*']

# PR trigger
pr:
  branches:
    include: [main]
  drafts: false               # don't trigger for draft PRs

# Scheduled trigger
schedules:
  - cron: "0 2 * * *"        # 2am daily
    displayName: Nightly build
    branches:
      include: [main]
    always: true              # run even if no code changes

# Disable automatic trigger (manual only)
trigger: none
pr: none
```

---

## Agents

### Microsoft-Hosted Agents (free minutes available)

```yaml
pool:
  vmImage: ubuntu-latest       # Ubuntu 22.04
  # vmImage: ubuntu-20.04
  # vmImage: windows-latest
  # vmImage: macOS-latest
```

### Self-Hosted Agents

Install on your own VM, container, or on-premises machine. No usage limits, access to private networks.

```bash
# Download and configure agent
mkdir myagent && cd myagent
wget https://vstsagentpackage.azureedge.net/agent/3.x.x/vsts-agent-linux-x64-3.x.x.tar.gz
tar xzf vsts-agent-linux-x64-3.x.x.tar.gz
./config.sh --url https://dev.azure.com/myorg \
            --auth PAT \
            --token <PAT> \
            --pool mypool \
            --agent myagent
./svc.sh install && ./svc.sh start
```

```yaml
# Use self-hosted agent pool
pool:
  name: mypool               # your self-hosted pool
  demands:
    - docker                 # agent must have docker capability
```

### Agent Containers (for AKS)

```yaml
# Run pipeline job in a Docker container
pool:
  vmImage: ubuntu-latest

container:
  image: node:20-alpine
  options: '--user root'

steps:
  - script: node --version
```

---

## Variables & Variable Groups

```yaml
# Inline variables
variables:
  appName: 'myapp'
  environment: 'production'
  isMain: $[eq(variables['Build.SourceBranch'], 'refs/heads/main')]

# Reference variable group (from Library)
variables:
  - group: myapp-prod-secrets

# Runtime expression (evaluated at runtime)
variables:
  deployEnv: $[variables['environment']]

# Conditional variable
variables:
  - ${{ if eq(variables['Build.SourceBranch'], 'refs/heads/main') }}:
    - name: environment
      value: production
  - ${{ else }}:
    - name: environment
      value: staging
```

**Variable Groups** (ADO Library → Variable Groups):
- Store shared variables across pipelines
- Mark variables as secret (masked in logs)
- Link to Azure Key Vault (variables sourced from Key Vault secrets)

```yaml
# Key Vault-linked variable group
variables:
  - group: myapp-keyvault-vars    # variables sourced from Key Vault
```

---

## Environments & Approvals

Environments track deployments, provide history, and enforce approvals.

**Create environment:** Pipelines → Environments → New Environment → Add approval check

```yaml
- deployment: DeployProd
  environment: production         # references environment in ADO
  strategy:
    runOnce:
      deploy:
        steps:
          - script: echo "Deploying..."
```

**Environment checks you can configure:**
- Manual approval (specific users/groups must approve)
- Branch control (only deploy from main)
- Business hours (only deploy Mon-Fri 9am-5pm)
- Exclusive lock (only one deployment at a time)
- Invoke Azure Function (custom check)

---

## Templates — Reusable Pipeline YAML

```yaml
# templates/build-steps.yml
parameters:
  - name: nodeVersion
    type: string
    default: '20.x'
  - name: runTests
    type: boolean
    default: true

steps:
  - task: NodeTool@0
    inputs:
      versionSpec: ${{ parameters.nodeVersion }}

  - script: npm ci

  - ${{ if eq(parameters.runTests, true) }}:
    - script: npm test
```

```yaml
# azure-pipelines.yml — use the template
stages:
  - stage: Build
    jobs:
      - job: Build
        steps:
          - template: templates/build-steps.yml
            parameters:
              nodeVersion: '20.x'
              runTests: true
```

### Stage Templates

```yaml
# templates/deploy-stage.yml
parameters:
  - name: environment
    type: string
  - name: serviceConnection
    type: string
  - name: namespace
    type: string

stages:
  - stage: Deploy_${{ parameters.environment }}
    jobs:
      - deployment: Deploy
        environment: ${{ parameters.environment }}
        strategy:
          runOnce:
            deploy:
              steps:
                - task: AzureCLI@2
                  inputs:
                    azureSubscription: ${{ parameters.serviceConnection }}
                    scriptType: bash
                    scriptLocation: inlineScript
                    inlineScript: |
                      helm upgrade myapp ./helm/myapp \
                        --namespace ${{ parameters.namespace }} \
                        --set image.tag=$(tag)
```

```yaml
# Use stage template
stages:
  - template: templates/deploy-stage.yml
    parameters:
      environment: staging
      serviceConnection: 'staging-connection'
      namespace: staging

  - template: templates/deploy-stage.yml
    parameters:
      environment: production
      serviceConnection: 'prod-connection'
      namespace: production
```

---

## Service Connections

Service connections store credentials for external services — managed centrally, not in pipeline YAML.

**Create:** Project Settings → Service Connections → New Service Connection

| Type | Use for |
|------|---------|
| Azure Resource Manager | Deploy to Azure subscriptions |
| Docker Registry | Push/pull from ACR, Docker Hub |
| GitHub | Checkout code, trigger pipelines |
| Kubernetes | Deploy to any K8s cluster |
| SSH | Deploy to Linux servers |
| Generic | Any HTTP endpoint |

```yaml
# Use service connection in pipeline
- task: AzureCLI@2
  inputs:
    azureSubscription: 'my-azure-connection'    # service connection name

- task: Docker@2
  inputs:
    containerRegistry: 'myapp-acr-connection'   # service connection name

- task: HelmDeploy@0
  inputs:
    connectionType: Kubernetes
    kubernetesServiceConnection: 'my-aks-connection'
```

---

## Common Pipeline Tasks

```yaml
# Checkout
- checkout: self                # default — checks out current repo
- checkout: git://MyProject/MyRepo@main   # other repo

# Scripts
- script: echo "Hello"
- bash: echo "Linux/macOS"
- pwsh: Write-Host "PowerShell"

# Copy files
- task: CopyFiles@2
  inputs:
    sourceFolder: '$(Build.SourcesDirectory)'
    contents: '**/*.yml'
    targetFolder: '$(Build.ArtifactStagingDirectory)'

# Publish pipeline artifact
- task: PublishPipelineArtifact@1
  inputs:
    targetPath: '$(Build.ArtifactStagingDirectory)'
    artifact: 'drop'

# Download artifact
- task: DownloadPipelineArtifact@2
  inputs:
    artifact: 'drop'
    path: '$(Pipeline.Workspace)/drop'

# Azure CLI
- task: AzureCLI@2
  inputs:
    azureSubscription: 'my-connection'
    scriptType: bash
    scriptLocation: inlineScript
    inlineScript: az group list

# Helm deploy
- task: HelmDeploy@0
  inputs:
    connectionType: Azure Resource Manager
    azureSubscriptionEndpoint: 'my-connection'
    azureResourceGroup: myapp-prod-rg
    kubernetesCluster: my-aks
    namespace: production
    command: upgrade
    chartType: FilePath
    chartPath: ./helm/myapp
    releaseName: myapp
    arguments: --set image.tag=$(tag) --wait

# Publish test results
- task: PublishTestResults@2
  inputs:
    testResultsFormat: JUnit
    testResultsFiles: '**/test-results.xml'

# Terraform
- task: TerraformTaskV4@4
  inputs:
    provider: azurerm
    command: init
    backendServiceArm: 'my-connection'
    backendAzureRmResourceGroupName: terraform-state-rg
    backendAzureRmStorageAccountName: mycompanytfstate
    backendAzureRmContainerName: tfstate
    backendAzureRmKey: prod/terraform.tfstate
```

---

## Conditions

```yaml
# Run step only on main branch
- script: ./deploy.sh
  condition: eq(variables['Build.SourceBranch'], 'refs/heads/main')

# Run step even if previous steps failed
- script: ./cleanup.sh
  condition: always()

# Run step only on failure
- script: ./notify-failure.sh
  condition: failed()

# Complex condition
- script: ./deploy.sh
  condition: and(succeeded(), eq(variables['Build.SourceBranch'], 'refs/heads/main'))

# Continue on error
- script: ./optional-check.sh
  continueOnError: true
```

---

## Parallel Jobs

```yaml
jobs:
  - job: TestLinux
    pool:
      vmImage: ubuntu-latest
    steps:
      - script: npm test

  - job: TestWindows
    pool:
      vmImage: windows-latest
    steps:
      - script: npm test

  - job: TestMac
    pool:
      vmImage: macOS-latest
    steps:
      - script: npm test

# Job that depends on all parallel jobs
  - job: Publish
    dependsOn:
      - TestLinux
      - TestWindows
      - TestMac
    condition: succeeded()
    steps:
      - script: echo "All tests passed"
```

---

## Matrix Strategy

```yaml
jobs:
  - job: Test
    strategy:
      matrix:
        Node18_Ubuntu:
          nodeVersion: '18.x'
          imageName: ubuntu-latest
        Node20_Ubuntu:
          nodeVersion: '20.x'
          imageName: ubuntu-latest
        Node20_Windows:
          nodeVersion: '20.x'
          imageName: windows-latest
    pool:
      vmImage: $(imageName)
    steps:
      - task: NodeTool@0
        inputs:
          versionSpec: $(nodeVersion)
      - script: npm test
```

---

## Quick Reference

```yaml
trigger:            branches, paths, tags — what triggers the pipeline
pr:                 pull request triggers
schedules:          cron-based scheduled runs
pool/vmImage:       Microsoft-hosted agent OS
pool/name:          self-hosted agent pool
variables:          pipeline variables and variable groups
stages:             top-level phases (Build, Test, Deploy)
jobs:               units of work within a stage
deployment:         special job for deployment with environment
steps:              individual tasks within a job
template:           reuse YAML across pipelines
condition:          when to run a step/job/stage
environment:        deployment target with approval gates
dependsOn:          control stage/job execution order
strategy/matrix:    run same job with different variable combinations

Key tasks:
  AzureCLI@2          → run az commands with service connection
  Docker@2            → build/push images
  HelmDeploy@0        → deploy Helm charts to AKS
  TerraformTaskV4@4   → run Terraform commands
  PublishTestResults@2 → publish JUnit/NUnit results
  PublishPipelineArtifact@1 → save files between stages
```
