# 🦊 GitLab CI/CD

A complete GitLab CI/CD knowledge base — from core concepts to production-grade pipelines, security scanning, and Kubernetes deployments.

> GitLab is the most widely adopted DevOps platform in Germany. It provides everything in one tool — CI/CD, container registry, environments, security scanning, and Kubernetes integration. Knowing it deeply is a major hiring advantage.

---

## 🗺️ Learning Path

```
01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10
 │     │     │     │     │     │     │     │     │     │
 │     │     │     │     │     │     │     │     │     └── Interview prep
 │     │     │     │     │     │     │     │     └──────── K8s integration
 │     │     │     │     │     │     │     └────────────── Security scanning
 │     │     │     │     │     │     └──────────────────── Advanced features
 │     │     │     │     │     └────────────────────────── Deployment patterns
 │     │     │     │     └──────────────────────────────── Docker builds
 │     │     │     └────────────────────────────────────── Variables & secrets
 │     │     └──────────────────────────────────────────── Runners
 │     └────────────────────────────────────────────────── Pipeline config
 └──────────────────────────────────────────────────────── How GitLab CI works
```

---

## 📚 Contents

| # | File | What you'll learn |
|---|------|------------------|
| 01 | [Core Concepts](./01-core-concepts.md) | Pipelines, jobs, stages, runners, artifacts, cache |
| 02 | [Pipeline Configuration](./02-pipeline-configuration.md) | rules, needs/DAG, include, extends, anchors, workflow |
| 03 | [Runners](./03-runners.md) | Registration, executors, Docker, Kubernetes, autoscaling |
| 04 | [Variables & Secrets](./04-variables-secrets.md) | Predefined vars, masked/protected, Vault, OIDC |
| 05 | [Docker & Container Builds](./05-docker-container-builds.md) | DinD, socket, Kaniko, registry, caching, scanning |
| 06 | [Deployment Patterns](./06-deployment-patterns.md) | Environments, canary, blue-green, review apps, rollbacks |
| 07 | [Advanced Features](./07-advanced-features.md) | DAG, parent-child, merge trains, dynamic pipelines |
| 08 | [Security & Compliance](./08-security-compliance.md) | SAST, secret detection, DAST, container scanning, compliance |
| 09 | [GitLab with Kubernetes](./09-gitlab-kubernetes.md) | Agent, kubectl, Helm deploys, GitOps, Auto DevOps |
| 10 | [Interview Q&A](./10-interview-qa.md) | Core, scenario-based, and advanced interview questions |

---

## ⚡ Quick Reference

### Essential .gitlab-ci.yml patterns

```yaml
# Minimal pipeline
stages: [test, build, deploy]

test:
  stage: test
  image: python:3.11
  script: pytest

build:
  stage: build
  image: docker:24
  services: [docker:24-dind]
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

deploy:
  stage: deploy
  environment:
    name: production
    url: https://example.com
  script: helm upgrade --install my-app ./chart --set image.tag=$CI_COMMIT_SHORT_SHA
  when: manual
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
      when: manual
```

### Most-used predefined variables

```bash
$CI_REGISTRY_IMAGE        # registry.gitlab.com/group/project
$CI_COMMIT_SHORT_SHA      # abc12345
$CI_COMMIT_REF_SLUG       # URL-safe branch name
$CI_COMMIT_BRANCH         # branch name
$CI_COMMIT_TAG            # tag (only for tag pipelines)
$CI_PIPELINE_SOURCE       # push, merge_request_event, schedule
$CI_DEFAULT_BRANCH        # main
$CI_PROJECT_DIR           # /builds/group/project
$CI_ENVIRONMENT_NAME      # staging, production
$CI_MERGE_REQUEST_IID     # MR number
$CI_JOB_TOKEN            # job authentication token
```

### Rules quick reference

```yaml
# Common conditions
- if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'      # main branch
- if: '$CI_PIPELINE_SOURCE == "merge_request_event"' # MR pipeline
- if: '$CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/'        # semver tag
- if: '$CI_PIPELINE_SOURCE == "schedule"'            # scheduled
- changes: ["Dockerfile", "src/**"]                  # file changes (MR only)
- when: never                                        # never run
- when: manual                                       # require manual trigger
```

---

## 🧠 Key Concepts at a Glance

| Concept | One-line summary |
|---------|-----------------|
| **Pipeline** | Full CI/CD run — collection of stages and jobs |
| **Stage** | Ordered group of parallel jobs |
| **Job** | Single unit of work executed by a runner |
| **Runner** | Agent that picks up and executes jobs |
| **Executor** | How runner runs jobs (docker, shell, kubernetes) |
| **Artifact** | Files produced by a job, passed to later jobs |
| **Cache** | Files persisted between pipelines (speed up deps) |
| **rules** | Conditional job execution (replaces only/except) |
| **needs** | DAG — run job as soon as dependency finishes |
| **extends** | Template inheritance — DRY pipeline config |
| **include** | Split config across multiple files |
| **workflow** | Pipeline-level rules (prevent/allow pipeline creation) |
| **environment** | Tracked deployment target with history |
| **Review App** | Temporary env per MR — live preview of changes |
| **interruptible** | Cancel old pipeline when new push arrives |
| **resource_group** | Serialize deployments — one at a time |
| **parent-child** | Pipeline that triggers sub-pipelines |
| **merge train** | Queue MRs and test sequentially with previous MRs |
| **SAST** | Static analysis for code vulnerabilities |
| **Secret Detection** | Scan for accidentally committed secrets |
| **GitLab Agent** | Pull-based K8s integration — runs in your cluster |
| **Auto DevOps** | Zero-config CI/CD — GitLab detects language, builds + deploys |
| **DinD** | Docker-in-Docker — run Docker inside a CI container |
| **Kaniko** | Build Docker images without Docker daemon (K8s-friendly) |
| **OIDC** | Keyless authentication to AWS/GCP using JWT tokens |

---

## 🗂️ Folder Structure

```
cicd/gitlab/
├── 00-gitlab-index.md          ← You are here
├── 01-core-concepts.md
├── 02-pipeline-configuration.md
├── 03-runners.md
├── 04-variables-secrets.md
├── 05-docker-container-builds.md
├── 06-deployment-patterns.md
├── 07-advanced-features.md
├── 08-security-compliance.md
├── 09-gitlab-kubernetes.md
└── 10-interview-qa.md
```

---

## 🔗 How GitLab CI Connects to the Rest of Your Notes

| Topic | Connection |
|-------|-----------|
| **Docker** | GitLab CI builds Docker images, pushes to GitLab Registry |
| **Kubernetes** | GitLab Agent deploys to K8s, Helm charts deployed from CI |
| **Helm** | `helm upgrade --install` in deploy jobs |
| **Terraform** | `terraform plan/apply` in CI jobs, OIDC for AWS auth |
| **Networking** | Runners need network access, VPC endpoints for private clusters |
| **Security** | Built-in SAST/DAST/container scanning, Vault integration |
| **Observability** | Deploy Prometheus/Grafana from CI, monitor deployments |

---

*Notes are living documents — updated as I learn and build.*
