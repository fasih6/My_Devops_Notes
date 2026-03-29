# ☸️ GitLab with Kubernetes

Kubernetes integration, GitLab Agent, Helm deployments, and Auto DevOps.

---

## 📚 Table of Contents

- [1. GitLab Kubernetes Integration](#1-gitlab-kubernetes-integration)
- [2. GitLab Agent for Kubernetes](#2-gitlab-agent-for-kubernetes)
- [3. Deploying with kubectl in CI](#3-deploying-with-kubectl-in-ci)
- [4. Helm Deployments in GitLab CI](#4-helm-deployments-in-gitlab-ci)
- [5. GitOps with GitLab Agent](#5-gitops-with-gitlab-agent)
- [6. Auto DevOps](#6-auto-devops)
- [7. GitLab Runner on Kubernetes](#7-gitlab-runner-on-kubernetes)
- [Cheatsheet](#cheatsheet)

---

## 1. GitLab Kubernetes Integration

GitLab integrates with Kubernetes for:
- Deploying applications from CI pipelines
- Running GitLab Runners as pods
- Reviewing deployments in the GitLab UI
- GitOps-style reconciliation

### Two integration methods

```
Method 1: GitLab Agent (agentk) — RECOMMENDED
  - Pull-based (agent runs in cluster, pulls from GitLab)
  - No direct API access from GitLab to cluster
  - Works with private clusters
  - Supports GitOps reconciliation
  - CI/CD tunnel for kubectl access

Method 2: Certificate-based (legacy) — AVOID FOR NEW PROJECTS
  - Push-based (GitLab connects to K8s API)
  - Deprecated in newer GitLab versions
  - Requires network access from GitLab to cluster API
```

---

## 2. GitLab Agent for Kubernetes

The GitLab Agent (agentk) is a small application running in your cluster that maintains a persistent connection to GitLab.

### Install the agent

```bash
# 1. Register agent in GitLab
#    Infrastructure → Kubernetes clusters → Connect a cluster
#    Create agent configuration: .gitlab/agents/<name>/config.yaml
#    GitLab shows you the helm install command

# 2. Install with Helm
helm repo add gitlab https://charts.gitlab.io
helm install gitlab-agent gitlab/gitlab-agent \
  --namespace gitlab-agent \
  --create-namespace \
  --set config.token=<YOUR_AGENT_TOKEN> \
  --set config.kasAddress=wss://kas.gitlab.com  # GitLab.com KAS address
  # For self-hosted: wss://gitlab.example.com/-/kubernetes-agent/
```

### Agent configuration

```yaml
# .gitlab/agents/production-cluster/config.yaml

# Allow CI jobs from these projects to use this agent
ci_access:
  projects:
    - id: mygroup/my-project
    - id: mygroup/shared-deployments
  groups:
    - id: mygroup              # all projects in group

# GitOps configuration — auto-sync manifests
gitops:
  manifest_projects:
    - id: mygroup/k8s-manifests
      default_namespace: production
      paths:
        - glob: 'apps/**/*.yaml'
        - glob: 'apps/**/*.yml'
```

---

## 3. Deploying with kubectl in CI

### Using the agent tunnel (no credentials needed)

```yaml
# With GitLab Agent, you can use kubectl directly — agent provides the connection

deploy:
  stage: deploy
  image: bitnami/kubectl:latest
  script:
    - |
      # Set context to use GitLab Agent tunnel
      kubectl config use-context mygroup/my-project:production-cluster

      # Now use kubectl normally
      kubectl set image deployment/my-app \
        app=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA \
        --namespace production

      kubectl rollout status deployment/my-app --namespace production
  environment:
    name: production
```

### Using kubeconfig stored as CI variable

```yaml
deploy:
  stage: deploy
  image: bitnami/kubectl:latest
  before_script:
    # KUBECONFIG is a File-type CI variable containing kubeconfig content
    - mkdir -p ~/.kube
    - cp $KUBECONFIG ~/.kube/config
    - chmod 600 ~/.kube/config
  script:
    - kubectl set image deployment/my-app
        app=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
        --namespace production
    - kubectl rollout status deployment/my-app --namespace production
  after_script:
    - rm -f ~/.kube/config
  environment:
    name: production
```

### Using OIDC for EKS (keyless)

```yaml
deploy-eks:
  id_tokens:
    AWS_OIDC_TOKEN:
      aud: sts.amazonaws.com
  script:
    # Exchange token for AWS credentials
    - |
      CREDS=$(aws sts assume-role-with-web-identity \
        --role-arn $AWS_ROLE_ARN \
        --role-session-name gitlab-ci-$CI_JOB_ID \
        --web-identity-token $AWS_OIDC_TOKEN)
      export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .Credentials.AccessKeyId)
      export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .Credentials.SecretAccessKey)
      export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .Credentials.SessionToken)

    # Update kubeconfig
    - aws eks update-kubeconfig --name my-cluster --region eu-central-1

    # Deploy
    - kubectl set image deployment/my-app
        app=$CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
        --namespace production
```

---

## 4. Helm Deployments in GitLab CI

### Standard Helm deployment

```yaml
.helm-base:
  image: alpine/helm:3.13.0
  before_script:
    - helm repo add myrepo https://charts.example.com
    - helm repo update

deploy-staging:
  extends: .helm-base
  stage: deploy-staging
  before_script:
    - !reference [.helm-base, before_script]
    # Configure cluster access via agent
    - kubectl config use-context mygroup/my-project:staging-cluster
  script:
    - |
      helm upgrade --install my-app myrepo/my-app \
        --namespace staging \
        --create-namespace \
        --values helm/values-staging.yaml \
        --set image.repository=$CI_REGISTRY_IMAGE \
        --set image.tag=$CI_COMMIT_SHORT_SHA \
        --set deploymentAnnotations."gitlab\.com/piplineUrl"="$CI_PIPELINE_URL" \
        --atomic \
        --timeout 5m \
        --cleanup-on-fail
  environment:
    name: staging
    url: https://staging.example.com

deploy-production:
  extends: .helm-base
  stage: deploy-production
  before_script:
    - !reference [.helm-base, before_script]
    - kubectl config use-context mygroup/my-project:production-cluster
  script:
    - |
      helm upgrade --install my-app myrepo/my-app \
        --namespace production \
        --values helm/values-production.yaml \
        --set image.repository=$CI_REGISTRY_IMAGE \
        --set image.tag=$CI_COMMIT_SHORT_SHA \
        --atomic \
        --timeout 10m
  environment:
    name: production
    url: https://example.com
  when: manual
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
      when: manual
```

### Helm diff in MR (show changes before apply)

```yaml
helm-diff:
  stage: validate
  image: alpine/helm:3.13.0
  before_script:
    - helm plugin install https://github.com/databus23/helm-diff
    - kubectl config use-context mygroup/my-project:staging-cluster
  script:
    - |
      helm diff upgrade my-app myrepo/my-app \
        --namespace staging \
        --values helm/values-staging.yaml \
        --set image.tag=$CI_COMMIT_SHORT_SHA \
        --allow-unreleased
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
```

---

## 5. GitOps with GitLab Agent

The GitLab Agent can automatically sync Kubernetes manifests from a Git repo.

### How it works

```
Git repo (manifests)        GitLab Agent
      │                          │
      │  git push              polls for changes
      │                          │
      ▼                          ▼
.gitlab/agents/             detects new commit
  production/                   │
    config.yaml            kubectl apply -f ...
                                  │
apps/                      Kubernetes cluster
  deployment.yaml          (auto-synced)
  service.yaml
```

### Agent config for GitOps

```yaml
# .gitlab/agents/production-cluster/config.yaml
gitops:
  manifest_projects:
    - id: mygroup/k8s-manifests  # GitLab project with manifests
      default_namespace: production
      reconcile_timeout: 3600s
      dry_run_strategy: none      # none, client, server
      prune: true                 # delete resources removed from Git
      prune_propagation_policy: foreground
      paths:
        - glob: 'environments/production/**/*.yaml'
```

### Manifest project structure

```
k8s-manifests/
├── environments/
│   ├── staging/
│   │   ├── deployment.yaml
│   │   ├── service.yaml
│   │   └── ingress.yaml
│   └── production/
│       ├── deployment.yaml
│       ├── service.yaml
│       └── ingress.yaml
└── base/
    └── namespace.yaml
```

### CI pipeline updates manifests (GitOps-style)

```yaml
# CI pipeline builds image, then updates the manifest repo
update-manifest:
  stage: update-manifest
  image: alpine:latest
  before_script:
    - apk add --no-cache git curl
  script:
    - |
      # Clone the manifest repo
      git clone https://gitlab-ci-token:$CI_JOB_TOKEN@gitlab.com/mygroup/k8s-manifests.git
      cd k8s-manifests

      # Update image tag in manifest
      sed -i "s|image: $CI_REGISTRY_IMAGE:.*|image: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA|" \
        environments/staging/deployment.yaml

      # Commit and push
      git config user.email "ci@gitlab.com"
      git config user.name "GitLab CI"
      git add environments/staging/deployment.yaml
      git commit -m "Update staging image to $CI_COMMIT_SHORT_SHA [skip ci]"
      git push origin main
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
```

---

## 6. Auto DevOps

Auto DevOps provides a default CI/CD pipeline with zero configuration — GitLab detects your language and applies best practices automatically.

### What Auto DevOps does

```
Auto Build         → Builds Docker image (Heroku buildpacks or Dockerfile)
Auto Test          → Runs test suite (language-detected)
Auto Code Quality  → Code quality report in MR
Auto SAST          → Security scanning
Auto Container Scanning → Image vulnerability scan
Auto Dependency Scanning → Dependency vulnerability scan
Auto Deploy        → Deploys to Kubernetes with Helm
Auto Browser Performance Testing → Lighthouse performance test
Auto DAST          → Dynamic security testing
```

### Enable Auto DevOps

```
Project → Settings → CI/CD → Auto DevOps:
  ☑ Default to Auto DevOps pipeline

# Or via .gitlab-ci.yml
include:
  - template: Auto-DevOps.gitlab-ci.yml
```

### Auto DevOps with Kubernetes

```
Requirements:
  1. GitLab Kubernetes integration (Agent or cluster)
  2. Ingress controller installed
  3. cert-manager installed (for TLS)
  4. Container registry enabled

Auto DevOps will:
  - Build image → push to GitLab registry
  - Deploy to Kubernetes with auto-generated Helm chart
  - Create Review Apps for each MR
  - Promote to staging → production with manual gates
```

### Customizing Auto DevOps

```yaml
# Override specific Auto DevOps jobs
include:
  - template: Auto-DevOps.gitlab-ci.yml

# Override the test job
test:
  script:
    - pytest --cov=app

# Disable specific jobs
sast:
  rules:
    - when: never    # disable SAST from Auto DevOps
```

---

## 7. GitLab Runner on Kubernetes

```yaml
# values.yaml for gitlab-runner Helm chart
gitlabUrl: https://gitlab.com
runnerToken: glrt-TOKEN

# Number of concurrent jobs
concurrent: 10

# Runner configuration
runners:
  config: |
    [[runners]]
      [runners.kubernetes]
        namespace = "gitlab-runners"
        image = "ubuntu:22.04"
        cpu_request = "100m"
        cpu_limit = "1"
        memory_request = "128Mi"
        memory_limit = "1Gi"
        service_cpu_request = "100m"
        service_memory_request = "64Mi"
        pull_policy = "if-not-present"

        [[runners.kubernetes.volumes.host_path]]
          name = "docker-sock"
          mount_path = "/var/run/docker.sock"
          host_path = "/var/run/docker.sock"

# Resource requests for the runner manager pod
resources:
  requests:
    memory: 128Mi
    cpu: 100m
  limits:
    memory: 256Mi
    cpu: 200m

# Runner pod tolerations
tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "gitlab-runner"
    effect: "NoSchedule"
```

```bash
# Install/upgrade
helm upgrade --install gitlab-runner gitlab/gitlab-runner \
  --namespace gitlab-runner \
  --create-namespace \
  --values values.yaml
```

---

## Cheatsheet

```yaml
# Agent-based kubectl access
script:
  - kubectl config use-context mygroup/project:agent-name
  - kubectl get pods -n production

# Helm deploy
script:
  - |
    helm upgrade --install my-app ./chart \
      --namespace production \
      --set image.tag=$CI_COMMIT_SHORT_SHA \
      --atomic --timeout 5m

# GitOps: update manifest repo
script:
  - git clone https://gitlab-ci-token:$CI_JOB_TOKEN@gitlab.com/group/k8s-manifests.git
  - cd k8s-manifests
  - sed -i "s|image:.*|image: $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA|" deploy.yaml
  - git add . && git commit -m "Update image" && git push

# OIDC EKS access
id_tokens:
  AWS_TOKEN:
    aud: sts.amazonaws.com
```

---

*Next: [Interview Q&A →](./10-interview-qa.md)*
