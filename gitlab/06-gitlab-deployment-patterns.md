# 🚀 Deployment Patterns

Environments, rolling deployments, canary, rollbacks, and manual gates in GitLab CI.

---

## 📚 Table of Contents

- [1. GitLab Environments](#1-gitlab-environments)
- [2. Deployment Strategies](#2-deployment-strategies)
- [3. Manual Gates & Approvals](#3-manual-gates--approvals)
- [4. Rollbacks](#4-rollbacks)
- [5. Environment-Specific Variables](#5-environment-specific-variables)
- [6. Review Apps](#6-review-apps)
- [7. Release Management](#7-release-management)
- [8. Complete Deployment Pipeline](#8-complete-deployment-pipeline)
- [Cheatsheet](#cheatsheet)

---

## 1. GitLab Environments

Environments track what's deployed where — giving you a history of deployments per environment.

```yaml
deploy-staging:
  script: ./deploy.sh staging
  environment:
    name: staging                           # environment name
    url: https://staging.example.com        # shown in GitLab UI
    on_stop: stop-staging                   # job to tear down environment

stop-staging:
  script: ./teardown.sh staging
  environment:
    name: staging
    action: stop                            # marks this as the stop job
  when: manual

deploy-production:
  script: ./deploy.sh production
  environment:
    name: production
    url: https://example.com
    deployment_tier: production             # critical, production, staging, testing, development, other
```

### Dynamic environments (per MR)

```yaml
deploy-review:
  script:
    - ./deploy.sh review-$CI_MERGE_REQUEST_IID
  environment:
    name: review/$CI_COMMIT_REF_SLUG        # creates unique env per branch
    url: https://$CI_COMMIT_REF_SLUG.review.example.com
    on_stop: stop-review
    auto_stop_in: 2 days                    # auto-stop after 2 days
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'

stop-review:
  script:
    - ./teardown.sh review-$CI_MERGE_REQUEST_IID
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    action: stop
  when: manual
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      when: manual
```

### Environment tiers

```yaml
environment:
  deployment_tier: production    # affects display and access controls
  # Values: critical, production, staging, testing, development, other
```

---

## 2. Deployment Strategies

### Rolling deployment

```yaml
deploy:
  stage: deploy
  script:
    - |
      helm upgrade --install my-app ./helm/my-app \
        --namespace production \
        --set image.tag=$CI_COMMIT_SHORT_SHA \
        --set deployment.strategy=RollingUpdate \
        --set deployment.maxSurge=1 \
        --set deployment.maxUnavailable=0 \
        --atomic \
        --timeout 10m
  environment:
    name: production
```

### Canary deployment

```yaml
# Deploy canary (10% traffic)
deploy-canary:
  stage: deploy-canary
  script:
    - |
      helm upgrade --install my-app-canary ./helm/my-app \
        --namespace production \
        --set image.tag=$CI_COMMIT_SHORT_SHA \
        --set replicaCount=1 \
        --set canary.enabled=true \
        --set canary.weight=10
  environment:
    name: production/canary
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'

# Validate canary (monitor error rates)
validate-canary:
  stage: validate-canary
  script:
    - sleep 300   # wait 5 minutes
    - ./scripts/check-error-rate.sh production 1%
  needs: [deploy-canary]
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'

# Full production deployment (after canary looks good)
deploy-production:
  stage: deploy-production
  script:
    - helm upgrade --install my-app ./helm/my-app
        --namespace production
        --set image.tag=$CI_COMMIT_SHORT_SHA
    - helm uninstall my-app-canary --namespace production || true
  needs: [validate-canary]
  when: manual
  environment:
    name: production
```

### Blue-Green deployment

```yaml
# Determine current color
determine-color:
  stage: pre-deploy
  script:
    - |
      CURRENT=$(kubectl get service my-app -n production
        -o jsonpath='{.spec.selector.color}' 2>/dev/null || echo "blue")
      if [ "$CURRENT" == "blue" ]; then
        echo "DEPLOY_COLOR=green" >> deploy.env
        echo "CURRENT_COLOR=blue" >> deploy.env
      else
        echo "DEPLOY_COLOR=blue" >> deploy.env
        echo "CURRENT_COLOR=green" >> deploy.env
      fi
  artifacts:
    reports:
      dotenv: deploy.env

deploy-new-color:
  stage: deploy
  needs:
    - job: determine-color
      artifacts: true
  script:
    - |
      helm upgrade --install my-app-$DEPLOY_COLOR ./helm/my-app \
        --namespace production \
        --set image.tag=$CI_COMMIT_SHORT_SHA \
        --set color=$DEPLOY_COLOR
  environment:
    name: production/$DEPLOY_COLOR

switch-traffic:
  stage: switch
  needs: [deploy-new-color]
  script:
    - |
      kubectl patch service my-app -n production \
        -p '{"spec":{"selector":{"color":"'"$DEPLOY_COLOR"'"}}}'
  when: manual

cleanup-old:
  stage: cleanup
  needs: [switch-traffic]
  script:
    - helm uninstall my-app-$CURRENT_COLOR --namespace production
  when: manual
```

---

## 3. Manual Gates & Approvals

### Basic manual job

```yaml
deploy-production:
  stage: deploy
  script: ./deploy.sh production
  when: manual               # requires someone to click "Play" in GitLab UI
  environment:
    name: production
```

### Protected environments (require approval)

```
Settings → CI/CD → Protected Environments:
  Environment: production
  Allowed to deploy: Maintainers, Deployers group
  Required approvals: 2   (need 2 approvals before deployment runs)
```

### Blocking manual job with allow_failure

```yaml
review-deployment:
  stage: validate
  script:
    - echo "Please review the staging deployment"
    - echo "Then approve the production deployment"
  when: manual
  allow_failure: false   # pipeline waits here — next stages blocked

deploy-production:
  stage: deploy
  needs: [review-deployment]
  script: ./deploy.sh production
```

### Timed deployment (delayed)

```yaml
auto-deploy-staging:
  stage: deploy
  script: ./deploy.sh staging
  when: delayed
  start_in: 10 minutes    # auto-runs after 10 min (can be cancelled)
```

---

## 4. Rollbacks

### Helm rollback

```yaml
rollback-production:
  stage: rollback
  script:
    - |
      helm rollback my-app \
        --namespace production \
        --wait \
        --timeout 5m
  environment:
    name: production
    action: prepare    # prevents creating a new deployment record
  when: manual
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
```

### Rollback to specific version

```yaml
rollback-to-version:
  stage: rollback
  script:
    - |
      helm history my-app --namespace production
      helm rollback my-app $HELM_REVISION --namespace production
  when: manual
  variables:
    HELM_REVISION: ""    # set via manual pipeline variables
```

### Using GitLab environments for rollback

```
GitLab UI → Deployments → Environments → production
  → Shows list of all deployments
  → Click "Re-deploy" on any previous deployment
  → Reruns the deploy job from that pipeline with that image tag
```

---

## 5. Environment-Specific Variables

```yaml
# Scope variables to specific environments in GitLab UI:
# Settings → CI/CD → Variables → Add:
#   Key: DB_HOST
#   Value: staging-db.internal
#   Environment scope: staging

# Settings → CI/CD → Variables → Add:
#   Key: DB_HOST
#   Value: prod-db.internal
#   Environment scope: production

# In job — the correct value is injected based on environment
deploy:
  script:
    - echo "DB_HOST=$DB_HOST"    # staging job: staging-db.internal
  environment:
    name: staging                 # this determines which scoped variable applies
```

---

## 6. Review Apps

Review Apps create a temporary, live environment for every merge request.

```yaml
# .gitlab-ci.yml
deploy-review:
  stage: review
  script:
    - |
      # Deploy to a dynamic subdomain based on MR number
      REVIEW_DOMAIN="mr-${CI_MERGE_REQUEST_IID}.review.example.com"
      helm upgrade --install \
        review-$CI_MERGE_REQUEST_IID \
        ./helm/my-app \
        --namespace review \
        --create-namespace \
        --set image.tag=$CI_COMMIT_SHORT_SHA \
        --set ingress.host=$REVIEW_DOMAIN
      echo "Review app available at: https://$REVIEW_DOMAIN"
  environment:
    name: review/$CI_MERGE_REQUEST_IID
    url: https://mr-$CI_MERGE_REQUEST_IID.review.example.com
    on_stop: stop-review
    auto_stop_in: 2 days
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'

stop-review:
  stage: review
  script:
    - helm uninstall review-$CI_MERGE_REQUEST_IID --namespace review
  environment:
    name: review/$CI_MERGE_REQUEST_IID
    action: stop
  when: manual
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      when: manual
```

---

## 7. Release Management

### Create a GitLab Release

```yaml
create-release:
  stage: release
  image: registry.gitlab.com/gitlab-org/release-cli:latest
  script:
    - echo "Creating release for $CI_COMMIT_TAG"
  release:
    name: "Release $CI_COMMIT_TAG"
    description: "See CHANGELOG.md for details"
    tag_name: $CI_COMMIT_TAG
    ref: $CI_COMMIT_SHA
    milestones:
      - "v1.2"
    assets:
      links:
        - name: "Docker Image"
          url: "$CI_REGISTRY_IMAGE:$CI_COMMIT_TAG"
          link_type: image
  rules:
    - if: '$CI_COMMIT_TAG =~ /^v\d+\.\d+\.\d+$/'

# Generate changelog automatically
generate-changelog:
  stage: prepare
  image: registry.gitlab.com/gitlab-org/release-cli:latest
  script:
    - |
      release-cli generate-changelog \
        --starting-version $PREV_TAG \
        > CHANGELOG.md
  artifacts:
    paths: [CHANGELOG.md]
  rules:
    - if: '$CI_COMMIT_TAG'
```

---

## 8. Complete Deployment Pipeline

```yaml
# Complete staging + production pipeline

stages:
  - test
  - build
  - deploy-staging
  - validate-staging
  - deploy-production

# ── Deploy Staging (automatic on main) ───────────────────────────
deploy-staging:
  stage: deploy-staging
  image: alpine/helm:3.13
  before_script:
    - apk add --no-cache curl
    - echo "$KUBECONFIG_STAGING" > /tmp/kubeconfig
  script:
    - |
      KUBECONFIG=/tmp/kubeconfig helm upgrade --install my-app ./helm/my-app \
        --namespace staging \
        --create-namespace \
        --values helm/my-app/values-staging.yaml \
        --set image.tag=$CI_COMMIT_SHORT_SHA \
        --atomic \
        --timeout 5m \
        --wait
  after_script:
    - rm -f /tmp/kubeconfig
  environment:
    name: staging
    url: https://staging.example.com
    on_stop: stop-staging
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'

stop-staging:
  stage: deploy-staging
  image: alpine/helm:3.13
  before_script:
    - echo "$KUBECONFIG_STAGING" > /tmp/kubeconfig
  script:
    - KUBECONFIG=/tmp/kubeconfig helm uninstall my-app --namespace staging
  environment:
    name: staging
    action: stop
  when: manual
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'

# ── Validate Staging (smoke test) ────────────────────────────────
smoke-test:
  stage: validate-staging
  image: curlimages/curl:latest
  needs: [deploy-staging]
  script:
    - |
      # Wait for deployment to stabilize
      sleep 30
      # Check health endpoint
      curl -sf https://staging.example.com/health | grep '"status":"ok"'
      # Check API
      curl -sf https://staging.example.com/api/v1/status
      echo "Smoke tests passed!"
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'

# ── Deploy Production (manual approval) ──────────────────────────
deploy-production:
  stage: deploy-production
  image: alpine/helm:3.13
  needs: [smoke-test]
  before_script:
    - echo "$KUBECONFIG_PRODUCTION" > /tmp/kubeconfig
  script:
    - |
      KUBECONFIG=/tmp/kubeconfig helm upgrade --install my-app ./helm/my-app \
        --namespace production \
        --values helm/my-app/values-production.yaml \
        --set image.tag=$CI_COMMIT_SHORT_SHA \
        --atomic \
        --timeout 10m \
        --cleanup-on-fail
  after_script:
    - rm -f /tmp/kubeconfig
  environment:
    name: production
    url: https://example.com
  when: manual    # human must click Play in GitLab UI
  rules:
    - if: '$CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH'
      when: manual
```

---

## Cheatsheet

```yaml
# Basic environment
environment:
  name: staging
  url: https://staging.example.com
  on_stop: stop-job
  auto_stop_in: 1 week

# Dynamic environment (per MR)
environment:
  name: review/$CI_COMMIT_REF_SLUG
  url: https://$CI_COMMIT_REF_SLUG.review.example.com

# Stop action
environment:
  name: staging
  action: stop

# Manual deployment
when: manual

# Delayed deployment
when: delayed
start_in: 30 minutes

# dotenv artifact (pass variables between jobs)
artifacts:
  reports:
    dotenv: deploy.env

# Release
release:
  name: Release $CI_COMMIT_TAG
  tag_name: $CI_COMMIT_TAG
  description: Release notes
```

---

*Next: [Advanced Features →](./07-advanced-features.md)*
