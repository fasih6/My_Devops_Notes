# 🦊 GitLab CI — Core Concepts

Pipelines, jobs, stages, runners, and the anatomy of `.gitlab-ci.yml`.

> GitLab CI/CD is one of the most complete CI/CD platforms — everything in one tool: code, CI, registry, environments, security scanning, and deployments. Understanding it deeply is essential for German DevOps roles where GitLab is widely adopted.

---

## 📚 Table of Contents

- [1. What is GitLab CI/CD?](#1-what-is-gitlab-cicd)
- [2. The .gitlab-ci.yml File](#2-the-gitlab-ciyml-file)
- [3. Pipelines](#3-pipelines)
- [4. Jobs](#4-jobs)
- [5. Stages](#5-stages)
- [6. Runners](#6-runners)
- [7. Artifacts & Cache](#7-artifacts--cache)
- [8. Pipeline Triggers](#8-pipeline-triggers)
- [9. GitLab CI vs GitHub Actions](#9-gitlab-ci-vs-github-actions)
- [Key Terms Glossary](#key-terms-glossary)

---

## 1. What is GitLab CI/CD?

GitLab CI/CD is a built-in continuous integration and delivery platform. Unlike GitHub Actions (which needs external tools for many things), GitLab provides the full DevOps lifecycle in one platform:

```
Code → CI Pipeline → Container Registry → Environments → Deploy → Monitor
 │         │               │                   │            │
 Git    Build/Test       Docker           Staging/Prod   Kubernetes
        Scan/Lint        images           tracking       Helm deploy
```

### Why GitLab CI stands out

- **Everything in one tool** — no need for separate Jenkins, Artifactory, Argo CD
- **Auto DevOps** — zero-config pipelines for common stacks
- **Built-in security scanning** — SAST, DAST, dependency scanning, secrets detection
- **GitLab Container Registry** — no external registry needed
- **Environments** — track what's deployed where, who deployed it
- **Merge request pipelines** — full CI on every MR, not just main
- **GitLab Runners** — self-hosted or GitLab.com shared runners

---

## 2. The .gitlab-ci.yml File

Every GitLab CI pipeline is defined in `.gitlab-ci.yml` at the repository root.

### Minimal example

```yaml
# .gitlab-ci.yml
stages:
  - test
  - build
  - deploy

test:
  stage: test
  image: python:3.11
  script:
    - pip install -r requirements.txt
    - pytest

build:
  stage: build
  script:
    - docker build -t my-app:$CI_COMMIT_SHORT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

deploy:
  stage: deploy
  script:
    - helm upgrade --install my-app ./chart --set image.tag=$CI_COMMIT_SHORT_SHA
  environment:
    name: production
```

### Full structure

```yaml
# Global defaults (applied to all jobs unless overridden)
default:
  image: ubuntu:22.04
  before_script:
    - apt-get update -qq
  retry: 2
  timeout: 10 minutes
  interruptible: true

# Global variables
variables:
  DOCKER_DRIVER: overlay2
  FF_USE_FASTZIP: "true"

# Stage order
stages:
  - lint
  - test
  - build
  - security
  - deploy-staging
  - deploy-production

# Include other files
include:
  - local: '.gitlab/ci/build.yml'
  - project: 'mygroup/shared-ci'
    ref: main
    file: '/templates/docker-build.yml'
  - template: 'Security/SAST.gitlab-ci.yml'

# Jobs
my-job:
  stage: test
  ...
```

---

## 3. Pipelines

A **pipeline** is a collection of jobs organized in stages. Every push to a branch (by default) triggers a new pipeline.

### Pipeline types

| Type | When triggered | What runs |
|------|---------------|-----------|
| **Branch pipeline** | Push to branch | All jobs for that branch |
| **Merge request pipeline** | MR opened/updated | Jobs with `rules: - if: $CI_PIPELINE_SOURCE == "merge_request_event"` |
| **Tag pipeline** | Tag pushed | Jobs with `rules: - if: $CI_COMMIT_TAG` |
| **Scheduled pipeline** | Cron schedule | All or filtered jobs |
| **Manual pipeline** | Run Pipeline button | All jobs |
| **API/webhook triggered** | External trigger | Configured jobs |

### Pipeline execution flow

```
Stage: lint          Stage: test        Stage: build       Stage: deploy
┌─────────────┐      ┌─────────────┐    ┌─────────────┐   ┌─────────────┐
│ lint-python │      │ unit-tests  │    │ build-image │   │  staging    │
│ lint-docker │──────│ integration │────│             │───│  production │
│ lint-helm   │      │ e2e-tests   │    │             │   │             │
└─────────────┘      └─────────────┘    └─────────────┘   └─────────────┘
  (all parallel)       (all parallel)     (sequential)       (sequential)

Stages run sequentially.
Jobs within a stage run in parallel.
If any job fails → subsequent stages don't run (by default).
```

### Viewing pipelines

```bash
# GitLab UI: Project → CI/CD → Pipelines

# GitLab CLI (glab)
glab ci list
glab ci view
glab ci run
glab ci retry <pipeline-id>
```

---

## 4. Jobs

A **job** is the smallest unit in GitLab CI — a set of commands run by a runner.

### Full job anatomy

```yaml
my-comprehensive-job:
  # Which stage it belongs to
  stage: test

  # Docker image to use (overrides global default)
  image:
    name: python:3.11-slim
    entrypoint: [""]    # override entrypoint (for images that set one)

  # Services (additional containers available during job)
  services:
    - name: postgres:15
      alias: db
    - name: redis:7
      alias: redis

  # Run before main script
  before_script:
    - pip install -r requirements.txt
    - echo "Starting tests"

  # The main commands
  script:
    - pytest --cov=app --cov-report=xml
    - coverage report

  # Run after script (even if script fails)
  after_script:
    - echo "Tests complete"

  # Environment variables for this job
  variables:
    DATABASE_URL: "postgresql://postgres@db/test"
    REDIS_URL: "redis://redis:6379"

  # Artifacts (files to preserve after job)
  artifacts:
    when: always    # always, on_success, on_failure
    expire_in: 1 week
    paths:
      - coverage.xml
      - junit-report.xml
    reports:
      junit: junit-report.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml

  # Cache (speed up jobs by persisting files)
  cache:
    key: "$CI_COMMIT_REF_SLUG-python"
    paths:
      - .pip-cache/
    policy: pull-push    # pull at start, push at end

  # When to run (conditions)
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == "main"'

  # Resource limits
  timeout: 30 minutes
  retry:
    max: 2
    when:
      - runner_system_failure
      - stuck_or_timeout_failure

  # Runner selection
  tags:
    - docker
    - eu-west

  # Job can be triggered manually
  when: on_success   # on_success, on_failure, always, manual, delayed, never

  # Allow failure without failing the pipeline
  allow_failure: false

  # Only run after specific jobs (DAG)
  needs:
    - job: lint
      artifacts: false
```

### Job keywords summary

| Keyword | Purpose |
|---------|---------|
| `stage` | Which stage the job belongs to |
| `image` | Docker image to run the job in |
| `services` | Additional containers (database, cache) |
| `script` | Commands to execute |
| `before_script` | Commands before script |
| `after_script` | Commands after script (always runs) |
| `variables` | Job-level environment variables |
| `rules` | Conditions for running the job |
| `only/except` | (legacy) Branch/tag filters |
| `when` | Execution timing (on_success, manual, etc.) |
| `needs` | DAG — run after specific jobs, not stages |
| `artifacts` | Files to save after job |
| `cache` | Files to persist between jobs/pipelines |
| `tags` | Select specific runner |
| `timeout` | Maximum job duration |
| `retry` | Retry on failure |
| `allow_failure` | Pipeline continues even if job fails |
| `environment` | Deployment target (for tracking) |
| `parallel` | Run N copies of the job in parallel |

---

## 5. Stages

Stages define the order of execution. All jobs in a stage run in parallel. Next stage only starts when all jobs in the current stage succeed.

```yaml
stages:
  - validate     # runs first
  - test         # runs after validate
  - build        # runs after test
  - deploy       # runs last

# If no stages defined, GitLab uses defaults:
# .pre → build → test → deploy → .post
```

### Special stages

```yaml
# .pre — always runs before all other stages
setup:
  stage: .pre
  script: echo "This always runs first"

# .post — always runs after all other stages
cleanup:
  stage: .post
  script: echo "This always runs last"
  when: always    # even if pipeline fails
```

---

## 6. Runners

Runners are agents that execute jobs. GitLab connects to runners to run pipeline jobs.

### Runner types

| Type | Description | Use for |
|------|-------------|---------|
| **Shared runners** | GitLab.com managed | Public projects, simple jobs |
| **Group runners** | Available to all projects in a group | Team-shared configuration |
| **Project runners** | Available to one project only | Project-specific requirements |

### Executor types

| Executor | How it runs jobs | Best for |
|---------|-----------------|---------|
| `docker` | Each job in a fresh Docker container | Most use cases |
| `shell` | Directly on the runner machine | Legacy, system-level tasks |
| `kubernetes` | Pod in a Kubernetes cluster | Cloud-native, autoscaling |
| `docker+machine` | Auto-provisions cloud VMs | Autoscaling on AWS/GCP |
| `virtualbox` | VM per job | Testing across OS types |

```yaml
# Specify runner with tags
my-job:
  tags:
    - docker          # only run on runners with "docker" tag
    - high-memory     # AND "high-memory" tag
```

---

## 7. Artifacts & Cache

### Artifacts — pass files between jobs

```yaml
build:
  stage: build
  script:
    - go build -o app ./...
  artifacts:
    paths:
      - app           # binary
      - dist/         # directory
    expire_in: 1 hour

deploy:
  stage: deploy
  needs:
    - job: build
      artifacts: true    # download artifacts from build job
  script:
    - ./app --version    # use the artifact
```

### Cache — speed up repeated operations

```yaml
# Cache pip packages
test:
  cache:
    key:
      files:
        - requirements.txt    # cache key based on file hash
    paths:
      - .pip-cache/
  script:
    - pip install --cache-dir .pip-cache -r requirements.txt

# Cache node_modules
frontend:
  cache:
    key:
      files:
        - package-lock.json
    paths:
      - node_modules/
  script:
    - npm ci
    - npm run build
```

### Artifacts vs Cache

| | Artifacts | Cache |
|--|-----------|-------|
| **Purpose** | Pass build outputs between jobs | Speed up by reusing files |
| **Scope** | Per pipeline, per job | Across pipelines |
| **Downloaded by** | Later jobs (explicitly) | All jobs that declare cache |
| **Examples** | Binaries, reports, coverage | node_modules, pip packages |

---

## 8. Pipeline Triggers

```yaml
# 1. Push trigger (default — any push to any branch)
# No configuration needed

# 2. Schedule trigger
# GitLab UI: CI/CD → Schedules → New schedule
# Cron: "0 2 * * *" → daily at 2am

# 3. API trigger
curl -X POST \
  --form token=MY_TRIGGER_TOKEN \
  --form ref=main \
  https://gitlab.com/api/v4/projects/123/trigger/pipeline

# 4. Upstream pipeline trigger (parent-child)
trigger-downstream:
  trigger:
    project: mygroup/my-other-project
    branch: main

# 5. Manual trigger in pipeline
deploy-production:
  when: manual
  script: ./deploy.sh production
```

### Predefined CI variables for trigger detection

```yaml
# Detect pipeline source in rules
rules:
  - if: '$CI_PIPELINE_SOURCE == "push"'
  - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
  - if: '$CI_PIPELINE_SOURCE == "schedule"'
  - if: '$CI_PIPELINE_SOURCE == "api"'
  - if: '$CI_PIPELINE_SOURCE == "trigger"'
  - if: '$CI_PIPELINE_SOURCE == "web"'        # manual run from UI
  - if: '$CI_PIPELINE_SOURCE == "pipeline"'   # triggered by another pipeline
```

---

## 9. GitLab CI vs GitHub Actions

| Feature | GitLab CI | GitHub Actions |
|---------|-----------|----------------|
| **Config file** | `.gitlab-ci.yml` | `.github/workflows/*.yml` |
| **Trigger keyword** | `rules`, `only/except` | `on:` |
| **Job definition** | Flat (all jobs at same level) | Inside `jobs:` block |
| **Stages** | Explicit `stages:` | Implicit via `needs:` |
| **Parallel jobs** | Same stage runs parallel | Explicit `matrix:` |
| **Artifacts** | `artifacts:` keyword | `actions/upload-artifact` |
| **Secrets** | CI/CD Variables (masked/protected) | Repository/org secrets |
| **Container Registry** | Built-in GitLab Registry | GHCR |
| **Security scanning** | Built-in (SAST, DAST, etc.) | Via marketplace actions |
| **Environments** | Built-in tracking | Deployments (basic) |
| **Self-hosted runners** | GitLab Runner | GitHub Actions Runner |
| **Pricing** | 400 CI mins free, more for paid | 2000 mins free |

---

## Key Terms Glossary

| Term | Definition |
|------|-----------|
| **Pipeline** | Full CI/CD run — collection of stages and jobs |
| **Stage** | Group of parallel jobs; stages run sequentially |
| **Job** | Single unit of work — commands run by a runner |
| **Runner** | Agent that executes jobs |
| **Executor** | How the runner runs jobs (docker, shell, kubernetes) |
| **Artifact** | Files produced by a job, passed to subsequent jobs |
| **Cache** | Files persisted between pipeline runs to speed up jobs |
| **Environment** | Deployment target (staging, production) |
| **Trigger token** | Token to start a pipeline via API |
| **DAG** | Directed Acyclic Graph — job ordering via `needs:` |
| **MR pipeline** | Pipeline that runs on a merge request |
| **Protected branch** | Branch with restricted push/merge (usually main) |
| **Protected variable** | Variable only available in pipelines for protected branches |
| **Masked variable** | Variable hidden from job logs |

---

*Next: [Pipeline Configuration Deep Dive →](./02-pipeline-configuration.md)*
