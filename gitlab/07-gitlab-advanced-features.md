# 🧠 Advanced Features

DAG pipelines, merge trains, parent-child pipelines, and advanced GitLab CI patterns.

---

## 📚 Table of Contents

- [1. DAG Pipelines](#1-dag-pipelines)
- [2. Parent-Child Pipelines](#2-parent-child-pipelines)
- [3. Multi-Project Pipelines](#3-multi-project-pipelines)
- [4. Merge Trains](#4-merge-trains)
- [5. Pipeline Efficiency Patterns](#5-pipeline-efficiency-patterns)
- [6. interruptible & Auto-Cancellation](#6-interruptible--auto-cancellation)
- [7. Dynamic Child Pipelines](#7-dynamic-child-pipelines)
- [8. Pipeline as Code — Complete Patterns](#8-pipeline-as-code--complete-patterns)
- [Cheatsheet](#cheatsheet)

---

## 1. DAG Pipelines

DAG (Directed Acyclic Graph) pipelines use `needs` to create job dependencies independent of stages. Jobs run as soon as their dependencies finish — not when the whole stage finishes.

### Performance comparison

```
Stage-based (without needs):
  Stage: build     Stage: test         Stage: deploy
  [build-a]   ──► [test-a]        ──► [deploy-a]
  [build-b]       [test-b]            [deploy-b]
  [build-c]       [test-c]
                  (all builds must complete before any test starts)

DAG (with needs):
  build-a ──► test-a ──► deploy-a
  build-b ──► test-b ──► deploy-b    (all run independently)
  build-c ──► test-c
```

### DAG example

```yaml
stages:
  - build
  - test
  - deploy

build-frontend:
  stage: build
  script: npm run build
  artifacts:
    paths: [dist/]

build-backend:
  stage: build
  script: go build ./...
  artifacts:
    paths: [bin/]

build-worker:
  stage: build
  script: go build ./cmd/worker
  artifacts:
    paths: [worker]

# Each test runs immediately after its build — no waiting
test-frontend:
  stage: test
  needs:
    - job: build-frontend
      artifacts: true
  script: npm test

test-backend:
  stage: test
  needs:
    - job: build-backend
      artifacts: true
  script: go test ./...

test-worker:
  stage: test
  needs:
    - job: build-worker
      artifacts: true
  script: ./worker --test

# Deploys run independently too
deploy-frontend:
  stage: deploy
  needs: [test-frontend]
  script: ./deploy-frontend.sh

deploy-backend:
  stage: deploy
  needs: [test-backend, test-worker]   # wait for both tests
  script: ./deploy-backend.sh
```

### needs: pipeline — cross-pipeline artifacts

```yaml
deploy:
  stage: deploy
  needs:
    - pipeline: $UPSTREAM_PIPELINE_ID
      job: build
```

---

## 2. Parent-Child Pipelines

Split a large pipeline into a parent and multiple child pipelines. Good for monorepos.

```
Parent pipeline
├── Child pipeline A (frontend)
├── Child pipeline B (backend)
└── Child pipeline C (infrastructure)
```

### Static child pipeline

```yaml
# parent .gitlab-ci.yml
stages:
  - triggers

trigger-frontend:
  stage: triggers
  trigger:
    include: .gitlab/ci/frontend.yml    # child pipeline config
    strategy: depend                     # parent waits for child to complete

trigger-backend:
  stage: triggers
  trigger:
    include: .gitlab/ci/backend.yml
    strategy: depend

trigger-infra:
  stage: triggers
  trigger:
    include: .gitlab/ci/infra.yml
    strategy: depend
  rules:
    - changes:
        - terraform/**/*
```

```yaml
# .gitlab/ci/frontend.yml — runs as child pipeline
stages:
  - test
  - build

test-frontend:
  stage: test
  script: npm test

build-frontend:
  stage: build
  script: npm run build
```

### trigger keywords

```yaml
trigger:
  include: path/to/child.yml
  strategy: depend    # parent waits for child (default: parent doesn't wait)
  forward:
    pipeline_variables: true    # forward parent pipeline variables to child
    yaml_variables: true        # forward variables defined in trigger job
```

---

## 3. Multi-Project Pipelines

Trigger pipelines in other GitLab projects.

```yaml
# Trigger downstream project
deploy-downstream:
  trigger:
    project: mygroup/deployment-project   # another GitLab project
    branch: main
    strategy: depend
  variables:
    IMAGE_TAG: $CI_COMMIT_SHORT_SHA       # pass variable to downstream
    DEPLOY_ENV: staging
```

### Downstream project receives trigger

```yaml
# deployment-project/.gitlab-ci.yml
# $IMAGE_TAG and $DEPLOY_ENV available here
deploy:
  script:
    - helm upgrade --install my-app ./chart --set image.tag=$IMAGE_TAG
  environment:
    name: $DEPLOY_ENV
```

### Upstream/downstream linking

```
Build project → deploys image → triggers Deployment project
Deployment project → tracks deployments
GitLab shows linked pipelines in the UI
```

---

## 4. Merge Trains

Merge trains queue MRs and merge them sequentially, testing each with all previously-queued commits included.

```
Without merge train:
  MR-A tests against main at t=0
  MR-B tests against main at t=0  (at the same time)
  Both merge — one might break the other

With merge train:
  MR-A tests against main
  MR-B tests against main + MR-A's changes (queued after A)
  If A's pipeline passes → A merges
  If B's pipeline (with A included) passes → B merges
  Much safer — no integration surprises
```

### Enable merge trains

```
Settings → Merge Requests → Merge options:
  ☑ Enable merged results pipelines
  ☑ Enable merge trains
```

### Pipeline configuration for merge trains

```yaml
# Detect merge train in rules
merge-train-specific-job:
  rules:
    - if: '$CI_MERGE_REQUEST_EVENT_TYPE == "merge_train"'
      variables:
        EXTENDED_TESTS: "true"
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
```

---

## 5. Pipeline Efficiency Patterns

### Sparse checkout — only clone what you need

```yaml
variables:
  GIT_STRATEGY: clone          # clone, fetch, or none
  GIT_CLONE_PATH: $CI_BUILDS_DIR/$CI_CONCURRENT_ID/$CI_PROJECT_NAME
  GIT_DEPTH: 1                 # shallow clone (only latest commit)

# For monorepos with many files:
variables:
  GIT_STRATEGY: none           # don't clone — use artifacts only

# For jobs that don't need the code:
test:
  variables:
    GIT_STRATEGY: none         # don't clone repo for this job
  script:
    - echo "Using only artifacts from previous job"
```

### Caching strategies

```yaml
# Cache node_modules — key based on package-lock.json hash
frontend-test:
  cache:
    key:
      files:
        - package-lock.json
    paths:
      - node_modules/
    policy: pull-push     # pull at start, push at end

# Read-only cache (don't update — for jobs that just use the cache)
frontend-lint:
  cache:
    key:
      files:
        - package-lock.json
    paths:
      - node_modules/
    policy: pull          # only pull, don't update

# Separate cache per branch (isolate experimental changes)
feature-tests:
  cache:
    key: $CI_COMMIT_REF_SLUG   # separate cache per branch
    paths: [.pip-cache/]
```

### Resource groups — prevent concurrent deployments

```yaml
# Only ONE deploy-production can run at a time (even across pipelines)
deploy-production:
  resource_group: production    # globally unique lock
  script: ./deploy.sh production
  environment:
    name: production
```

```
If two pipelines run simultaneously and both reach deploy-production:
  Pipeline 1: acquires resource_group lock → runs
  Pipeline 2: waits for Pipeline 1 to release lock → then runs
```

---

## 6. interruptible & Auto-Cancellation

Stop older pipelines when a newer one starts on the same branch.

```yaml
# Make all jobs interruptible by default
default:
  interruptible: true

# Specific job — don't interrupt deployments
deploy:
  interruptible: false   # always completes, even if new pipeline starts
  script: ./deploy.sh
```

```
Workflow:
  Push → Pipeline A starts
  Push again → Pipeline B starts → Pipeline A is CANCELLED
  (saves runner minutes, only latest matters)

Enable in GitLab:
  Settings → CI/CD → General pipelines → Auto-cancel redundant pipelines
```

---

## 7. Dynamic Child Pipelines

Generate child pipeline configuration at runtime — powerful for monorepos and complex scenarios.

```yaml
# Parent pipeline — generates child config
generate-pipeline:
  stage: setup
  script:
    - |
      # Determine which services changed
      CHANGED=$(git diff --name-only $CI_MERGE_REQUEST_DIFF_BASE_SHA HEAD)
      echo "stages: [test, build, deploy]" > generated-pipeline.yml

      if echo "$CHANGED" | grep -q "^services/api/"; then
        cat >> generated-pipeline.yml << 'EOF'
      test-api:
        stage: test
        script: cd services/api && npm test

      build-api:
        stage: build
        script: docker build services/api -t $CI_REGISTRY_IMAGE/api:$CI_COMMIT_SHORT_SHA
      EOF
      fi

      if echo "$CHANGED" | grep -q "^services/worker/"; then
        cat >> generated-pipeline.yml << 'EOF'
      test-worker:
        stage: test
        script: cd services/worker && go test ./...
      EOF
      fi

      cat generated-pipeline.yml
  artifacts:
    paths:
      - generated-pipeline.yml

# Trigger the dynamically generated child pipeline
run-generated:
  stage: execute
  needs: [generate-pipeline]
  trigger:
    include:
      - artifact: generated-pipeline.yml
        job: generate-pipeline
    strategy: depend
```

---

## 8. Pipeline as Code — Complete Patterns

### Monorepo with affected-only pipelines

```yaml
# .gitlab-ci.yml
stages: [detect, build, test, deploy]

# Detect which services changed
detect-changes:
  stage: detect
  script:
    - |
      echo "CHANGED_SERVICES=" >> changes.env
      for service in api worker frontend; do
        if git diff --name-only $CI_MERGE_REQUEST_DIFF_BASE_SHA HEAD \
            | grep -q "^services/$service/"; then
          echo "CHANGED_$service=true" >> changes.env
        fi
      done
  artifacts:
    reports:
      dotenv: changes.env

build-api:
  stage: build
  needs:
    - job: detect-changes
      artifacts: true
  script: docker build services/api
  rules:
    - if: '$CHANGED_api == "true"'

build-worker:
  stage: build
  needs:
    - job: detect-changes
      artifacts: true
  script: docker build services/worker
  rules:
    - if: '$CHANGED_worker == "true"'
```

### Reusable component templates

```yaml
# .gitlab/components/docker-build.yml
spec:
  inputs:
    image_name:
      description: "Name of the image to build"
    dockerfile:
      description: "Path to Dockerfile"
      default: "Dockerfile"
    context:
      description: "Build context"
      default: "."

---
build-$[[ inputs.image_name ]]:
  image: docker:24
  services: [docker:24-dind]
  variables:
    IMAGE: $CI_REGISTRY_IMAGE/$[[ inputs.image_name ]]:$CI_COMMIT_SHORT_SHA
  script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    - docker build -f $[[ inputs.dockerfile ]] -t $IMAGE $[[ inputs.context ]]
    - docker push $IMAGE
```

```yaml
# Use the component
include:
  - component: $CI_SERVER_HOST/mygroup/ci-components/docker-build@main
    inputs:
      image_name: api
      dockerfile: services/api/Dockerfile
      context: services/api

  - component: $CI_SERVER_HOST/mygroup/ci-components/docker-build@main
    inputs:
      image_name: worker
      dockerfile: services/worker/Dockerfile
```

---

## Cheatsheet

```yaml
# DAG — needs
test:
  needs: [build]
  # OR with options:
  needs:
    - job: build
      artifacts: true
      optional: true

# Child pipeline
trigger-child:
  trigger:
    include: .gitlab/ci/child.yml
    strategy: depend

# Multi-project pipeline
trigger-downstream:
  trigger:
    project: mygroup/other-project
    branch: main
    strategy: depend

# Resource group (serialized deployments)
deploy:
  resource_group: production

# Auto-cancel
default:
  interruptible: true

# Dynamic pipeline artifact
trigger:
  include:
    - artifact: generated.yml
      job: generate

# Sparse clone
variables:
  GIT_DEPTH: 1
  GIT_STRATEGY: fetch   # faster than clone for unchanged repos
```

---

*Next: [Security & Compliance →](./08-security-compliance.md)*
