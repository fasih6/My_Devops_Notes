# ⚙️ Pipeline Configuration Deep Dive

Rules, needs, includes, extends, anchors — writing maintainable, powerful GitLab CI pipelines.

---

## 📚 Table of Contents

- [1. Rules — Conditional Job Execution](#1-rules--conditional-job-execution)
- [2. needs — DAG Pipelines](#2-needs--dag-pipelines)
- [3. include — Splitting Configuration](#3-include--splitting-configuration)
- [4. extends — Template Inheritance](#4-extends--template-inheritance)
- [5. YAML Anchors & Aliases](#5-yaml-anchors--aliases)
- [6. default — Global Defaults](#6-default--global-defaults)
- [7. workflow — Pipeline-Level Rules](#7-workflow--pipeline-level-rules)
- [8. Parallel Jobs & Matrix](#8-parallel-jobs--matrix)
- [9. Complete Real-World Pipeline](#9-complete-real-world-pipeline)
- [Cheatsheet](#cheatsheet)

---

## 1. Rules — Conditional Job Execution

`rules` replaces the older `only/except` system. It gives you precise control over when a job runs.

### Basic rules

```yaml
deploy-production:
  script: ./deploy.sh production
  rules:
    # Run only on main branch, not on MRs
    - if: '$CI_COMMIT_BRANCH == "main"'
      when: on_success

    # Skip on merge requests
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      when: never

    # Default: don't run
    - when: never
```

### Rules with multiple conditions

```yaml
build:
  script: docker build .
  rules:
    # Run on main branch (always)
    - if: '$CI_COMMIT_BRANCH == "main"'

    # Run on MR if Dockerfile changed
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      changes:
        - Dockerfile
        - .dockerignore
        - src/**/*

    # Run on tags
    - if: '$CI_COMMIT_TAG'
```

### rules: variables — override variables per condition

```yaml
deploy:
  script: ./deploy.sh $ENVIRONMENT
  rules:
    - if: '$CI_COMMIT_BRANCH == "main"'
      variables:
        ENVIRONMENT: staging
    - if: '$CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/'
      variables:
        ENVIRONMENT: production
      when: manual
```

### Common rules patterns

```yaml
# Only on default branch
- if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'

# Only on MR
- if: '$CI_PIPELINE_SOURCE == "merge_request_event"'

# Only on tags matching semver
- if: '$CI_COMMIT_TAG =~ /^v[0-9]+\.[0-9]+\.[0-9]+$/'

# Only on schedule
- if: '$CI_PIPELINE_SOURCE == "schedule"'

# Only when files changed (MR only — changes is MR-aware)
- if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
  changes:
    - "**/*.py"
    - requirements.txt

# Skip drafts (MR title starts with Draft:)
- if: '$CI_MERGE_REQUEST_TITLE =~ /^(Draft:|WIP:)/'
  when: never

# Manual on non-main branches
- if: '$CI_COMMIT_BRANCH != "main"'
  when: manual
- when: on_success    # automatic on main
```

### rules vs only/except (legacy)

```yaml
# OLD (only/except) — avoid for new pipelines
deploy:
  only:
    - main
  except:
    - schedules

# NEW (rules) — preferred
deploy:
  rules:
    - if: '$CI_COMMIT_BRANCH == "main" && $CI_PIPELINE_SOURCE != "schedule"'
```

---

## 2. needs — DAG Pipelines

`needs` breaks out of stage-based execution. Jobs with `needs` run as soon as their dependencies complete — regardless of stage.

### Without needs (stage-based)

```
Stage: build        Stage: test         Stage: deploy
build-frontend  ──► test-frontend  ──► deploy-frontend
build-backend   ──► test-backend   ──► deploy-backend
build-docs          (waits for BOTH builds before any test runs)
```

### With needs (DAG)

```yaml
build-frontend:
  stage: build
  script: npm run build

build-backend:
  stage: build
  script: go build ./...

test-frontend:
  stage: test
  needs: [build-frontend]    # runs as soon as build-frontend finishes
  script: npm test

test-backend:
  stage: test
  needs: [build-backend]     # runs as soon as build-backend finishes
  script: go test ./...

deploy-frontend:
  stage: deploy
  needs: [test-frontend]
  script: ./deploy-frontend.sh

deploy-backend:
  stage: deploy
  needs: [test-backend]
  script: ./deploy-backend.sh
```

```
Timeline with needs (much faster):
t=0:  build-frontend  build-backend
t=5:  test-frontend   test-backend   (as soon as each build finishes)
t=8:  deploy-frontend deploy-backend (as soon as each test finishes)

Without needs:
t=0:  build-frontend  build-backend
t=10: test-frontend   test-backend   (wait for ALL builds)
t=20: deploy-frontend deploy-backend (wait for ALL tests)
```

### needs with artifacts

```yaml
build:
  stage: build
  script: go build -o app ./...
  artifacts:
    paths: [app]

test:
  stage: test
  needs:
    - job: build
      artifacts: true    # download app artifact
  script: ./app --test

# needs with artifacts: false (just ordering, no artifact download)
lint:
  needs:
    - job: setup
      artifacts: false
```

### needs: optional

```yaml
deploy:
  needs:
    - job: build
    - job: security-scan
      optional: true    # continue even if security-scan didn't run
```

---

## 3. include — Splitting Configuration

`include` allows you to split your pipeline across multiple files and reuse shared templates.

### include types

```yaml
include:
  # 1. Local file in same repo
  - local: '.gitlab/ci/test.yml'
  - local: '.gitlab/ci/deploy.yml'

  # 2. File from another project (version pinned)
  - project: 'mygroup/shared-ci-templates'
    ref: 'v2.0'
    file:
      - '/templates/docker-build.yml'
      - '/templates/helm-deploy.yml'

  # 3. GitLab built-in templates
  - template: 'Security/SAST.gitlab-ci.yml'
  - template: 'Security/Secret-Detection.gitlab-ci.yml'
  - template: 'Code-Quality.gitlab-ci.yml'

  # 4. Remote URL
  - remote: 'https://example.com/ci-templates/common.yml'
```

### Recommended project structure

```
.gitlab-ci.yml              ← main file (orchestrates)
.gitlab/
└── ci/
    ├── variables.yml       ← global variables
    ├── lint.yml            ← lint jobs
    ├── test.yml            ← test jobs
    ├── build.yml           ← build jobs
    ├── security.yml        ← security scanning
    └── deploy.yml          ← deployment jobs
```

```yaml
# .gitlab-ci.yml (main file — clean and readable)
include:
  - local: .gitlab/ci/variables.yml
  - local: .gitlab/ci/lint.yml
  - local: .gitlab/ci/test.yml
  - local: .gitlab/ci/build.yml
  - local: .gitlab/ci/security.yml
  - local: .gitlab/ci/deploy.yml
  - template: Security/SAST.gitlab-ci.yml

stages:
  - lint
  - test
  - build
  - security
  - deploy
```

---

## 4. extends — Template Inheritance

`extends` lets jobs inherit configuration from a template job. Cleaner than anchors.

```yaml
# Define a template (starts with . to not run as standalone job)
.docker-job:
  image: docker:24
  services:
    - docker:24-dind
  variables:
    DOCKER_DRIVER: overlay2
    DOCKER_BUILDKIT: "1"
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY

# Extend the template
build-app:
  extends: .docker-job
  stage: build
  script:
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

build-worker:
  extends: .docker-job
  stage: build
  script:
    - docker build -f Dockerfile.worker -t $CI_REGISTRY_IMAGE/worker:$CI_COMMIT_SHORT_SHA .
    - docker push $CI_REGISTRY_IMAGE/worker:$CI_COMMIT_SHORT_SHA
```

### Multiple extends

```yaml
.base-job:
  retry: 2
  timeout: 10 minutes

.python-job:
  extends: .base-job
  image: python:3.11-slim
  before_script:
    - pip install -r requirements.txt

.test-job:
  extends: .python-job
  artifacts:
    reports:
      junit: junit-report.xml

unit-tests:
  extends: .test-job
  stage: test
  script:
    - pytest --junitxml=junit-report.xml
```

### extends merge behavior

```yaml
# Template
.base:
  variables:
    KEY1: value1
    KEY2: value2
  script:
    - echo "base"

# Child
my-job:
  extends: .base
  variables:
    KEY2: overridden     # overrides KEY2
    KEY3: new-value      # adds KEY3
  script:
    - echo "child"       # completely replaces script

# Result:
# variables: {KEY1: value1, KEY2: overridden, KEY3: new-value}
# script: [echo "child"]   ← script replaced, not merged
```

---

## 5. YAML Anchors & Aliases

YAML anchors (`&`) define reusable blocks, aliases (`*`) reference them.

```yaml
# Define anchor
.test-config: &test-config
  stage: test
  image: python:3.11
  before_script:
    - pip install -r requirements.txt
  cache:
    key: python-deps
    paths: [.pip-cache/]

# Use anchor
unit-tests:
  <<: *test-config          # merge anchor content
  script:
    - pytest tests/unit/

integration-tests:
  <<: *test-config          # same config
  script:
    - pytest tests/integration/
  services:
    - postgres:15
```

### Anchors vs extends

```
extends (preferred):
  + Works across included files
  + GitLab-aware (better UI, error messages)
  + Cleaner syntax

YAML anchors:
  + Standard YAML (works in any YAML processor)
  - Only within same file
  - Script arrays merge instead of replace with <<
```

---

## 6. default — Global Defaults

`default` sets defaults for all jobs that don't override them.

```yaml
default:
  image: ubuntu:22.04
  before_script:
    - echo "Pipeline: $CI_PIPELINE_ID"
  after_script:
    - echo "Job done: $CI_JOB_NAME"
  retry:
    max: 2
    when:
      - runner_system_failure
      - stuck_or_timeout_failure
  timeout: 30 minutes
  interruptible: true    # cancel job when newer pipeline starts
  tags:
    - docker
```

---

## 7. workflow — Pipeline-Level Rules

`workflow` controls whether a pipeline is created at all — before any jobs run.

```yaml
workflow:
  name: '$CI_COMMIT_BRANCH pipeline'   # pipeline display name
  rules:
    # Don't create pipeline for draft MRs
    - if: '$CI_MERGE_REQUEST_TITLE =~ /^(Draft:|WIP:)/'
      when: never

    # Don't create pipeline on push if MR exists
    # (avoid duplicate pipelines — run MR pipeline instead)
    - if: '$CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS'
      when: never

    # Create pipeline for pushes
    - if: '$CI_COMMIT_BRANCH'

    # Create pipeline for MRs
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'

    # Create pipeline for tags
    - if: '$CI_COMMIT_TAG'
```

---

## 8. Parallel Jobs & Matrix

### parallel — run N copies of a job

```yaml
# Run 5 copies of the same job in parallel
rspec:
  script: bundle exec rspec
  parallel: 5
  # Each gets: CI_NODE_INDEX (1-5), CI_NODE_TOTAL (5)
  # Use these to split test suite across nodes
```

### parallel: matrix — run with different variables

```yaml
# Build for multiple platforms and Python versions
build:
  script:
    - echo "Building $PLATFORM with Python $PYTHON_VERSION"
    - ./build.sh
  parallel:
    matrix:
      - PYTHON_VERSION: ["3.9", "3.10", "3.11"]
        PLATFORM: [linux, darwin]

# Creates 6 jobs:
# build: [linux, 3.9]
# build: [linux, 3.10]
# build: [linux, 3.11]
# build: [darwin, 3.9]
# build: [darwin, 3.10]
# build: [darwin, 3.11]
```

```yaml
# Deploy to multiple environments in parallel
deploy:
  script: ./deploy.sh $ENVIRONMENT $REGION
  parallel:
    matrix:
      - ENVIRONMENT: [staging]
        REGION: [eu-central-1, us-east-1]
      - ENVIRONMENT: [production]
        REGION: [eu-central-1]
        when: manual
```

---

## 9. Complete Real-World Pipeline

```yaml
# .gitlab-ci.yml — production-ready Python/Docker pipeline

workflow:
  rules:
    - if: '$CI_MERGE_REQUEST_TITLE =~ /^Draft:/'
      when: never
    - if: '$CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS'
      when: never
    - when: always

stages:
  - validate
  - test
  - build
  - security
  - deploy-staging
  - deploy-production

default:
  image: python:3.11-slim
  retry:
    max: 2
    when: [runner_system_failure, stuck_or_timeout_failure]
  interruptible: true

variables:
  PIP_CACHE_DIR: "$CI_PROJECT_DIR/.pip-cache"
  DOCKER_DRIVER: overlay2
  DOCKER_BUILDKIT: "1"

include:
  - template: Security/SAST.gitlab-ci.yml
  - template: Security/Secret-Detection.gitlab-ci.yml

# ── Validate ──────────────────────────────────────────────────────
lint:
  stage: validate
  cache:
    key: pip-$CI_COMMIT_REF_SLUG
    paths: [.pip-cache/]
  before_script:
    - pip install ruff mypy
  script:
    - ruff check .
    - mypy app/
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'

# ── Test ──────────────────────────────────────────────────────────
.python-test-base:
  cache:
    key:
      files: [requirements.txt]
    paths: [.pip-cache/]
  before_script:
    - pip install --cache-dir .pip-cache -r requirements.txt

unit-tests:
  extends: .python-test-base
  stage: test
  services:
    - postgres:15-alpine
    - redis:7-alpine
  variables:
    DATABASE_URL: "postgresql://postgres:postgres@postgres/test"
    REDIS_URL: "redis://redis:6379"
    POSTGRES_PASSWORD: postgres
    POSTGRES_DB: test
  script:
    - pytest tests/unit/ tests/integration/
        --junitxml=report.xml
        --cov=app
        --cov-report=xml:coverage.xml
  coverage: '/TOTAL.*\s+(\d+%)$/'
  artifacts:
    when: always
    reports:
      junit: report.xml
      coverage_report:
        coverage_format: cobertura
        path: coverage.xml
    expire_in: 1 week
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'

# ── Build ─────────────────────────────────────────────────────────
build-image:
  stage: build
  image: docker:24
  services: [docker:24-dind]
  needs: [unit-tests]
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
  script:
    - |
      docker build \
        --cache-from $CI_REGISTRY_IMAGE:latest \
        --build-arg BUILDKIT_INLINE_CACHE=1 \
        --build-arg VERSION=$CI_COMMIT_SHORT_SHA \
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA \
        -t $CI_REGISTRY_IMAGE:$CI_COMMIT_REF_SLUG \
        .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_REF_SLUG
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
    - if: '$CI_COMMIT_TAG'

# ── Deploy Staging ────────────────────────────────────────────────
deploy-staging:
  stage: deploy-staging
  image: alpine/helm:3.13
  needs: [build-image]
  environment:
    name: staging
    url: https://staging.example.com
    on_stop: stop-staging
  before_script:
    - helm repo add myrepo https://charts.example.com
  script:
    - |
      helm upgrade --install my-app ./helm/my-app \
        --namespace staging \
        --create-namespace \
        --values helm/my-app/values-staging.yaml \
        --set image.tag=$CI_COMMIT_SHORT_SHA \
        --atomic \
        --timeout 5m
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'

stop-staging:
  stage: deploy-staging
  image: alpine/helm:3.13
  environment:
    name: staging
    action: stop
  script:
    - helm uninstall my-app --namespace staging
  when: manual
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'

# ── Deploy Production ─────────────────────────────────────────────
deploy-production:
  stage: deploy-production
  image: alpine/helm:3.13
  needs: [deploy-staging]
  environment:
    name: production
    url: https://example.com
  script:
    - |
      helm upgrade --install my-app ./helm/my-app \
        --namespace production \
        --values helm/my-app/values-production.yaml \
        --set image.tag=$CI_COMMIT_SHORT_SHA \
        --atomic \
        --timeout 10m
  when: manual    # require manual approval
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
      when: manual
    - if: '$CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/'
      when: manual
```

---

## Cheatsheet

```yaml
# Rules patterns
rules:
  - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
  - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
  - if: '$CI_COMMIT_TAG =~ /^v\d+/'
  - if: '$CI_PIPELINE_SOURCE == "schedule"'
  - changes: ["Dockerfile", "src/**"]   # file-change trigger (MR only)
  - when: never   # default: don't run

# needs — DAG
needs: [job-a, job-b]
needs:
  - job: build
    artifacts: true
  - job: lint
    artifacts: false
    optional: true

# extends — inheritance
.base-template:
  retry: 2
  tags: [docker]

my-job:
  extends: .base-template
  script: echo "hello"

# parallel matrix
parallel:
  matrix:
    - VAR1: [a, b]
      VAR2: [x, y]

# include
include:
  - local: .gitlab/ci/test.yml
  - template: Security/SAST.gitlab-ci.yml
  - project: group/shared-ci
    ref: main
    file: /templates/build.yml
```

---

*Next: [Runners →](./03-runners.md)*
