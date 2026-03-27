# 🚀 CI/CD Integration

Automating Helm deployments with GitHub Actions, GitLab CI, and chart release pipelines.

---

## 📚 Table of Contents

- [1. CI/CD Principles for Helm](#1-cicd-principles-for-helm)
- [2. GitHub Actions Workflows](#2-github-actions-workflows)
- [3. GitLab CI Pipelines](#3-gitlab-ci-pipelines)
- [4. Chart Releaser — Publishing Charts](#4-chart-releaser--publishing-charts)
- [5. GitOps with ArgoCD](#5-gitops-with-argocd)
- [6. Best Practices](#6-best-practices)
- [Cheatsheet](#cheatsheet)

---

## 1. CI/CD Principles for Helm

### The deployment pipeline

```
Code pushed to Git
        │
        ▼
CI: Build & Test
  - Run unit tests
  - Build Docker image
  - Push image to registry
        │
        ▼
CI: Helm Lint & Template
  - helm lint
  - helm template (verify rendering)
  - helm diff (show changes)
        │
        ▼
CD: Deploy to Staging
  - helm upgrade --install (staging)
  - helm test (run tests)
        │
        ▼
CD: Deploy to Production
  - Approval gate (manual or auto)
  - helm upgrade --install (production)
  - Verify rollout
  - Rollback on failure
```

### Key principles

```
1. helm upgrade --install — always idempotent
2. --atomic — auto-rollback on failure
3. --wait — wait for rollout before declaring success
4. --timeout — don't wait forever
5. helm diff — show changes before applying (review step)
6. Store secrets encrypted (helm-secrets + SOPS)
7. One values file per environment
8. Lock chart versions (Chart.lock)
```

---

## 2. GitHub Actions Workflows

### Application deployment workflow

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]
  workflow_dispatch:
    inputs:
      environment:
        description: Target environment
        required: true
        default: staging
        type: choice
        options: [staging, production]

env:
  REGISTRY: ghcr.io
  IMAGE_NAME: ${{ github.repository }}
  CHART_PATH: ./helm/my-app

jobs:
  # ── Build & Push Image ─────────────────────────────────────────
  build:
    name: Build & Push Image
    runs-on: ubuntu-latest
    outputs:
      image-tag: ${{ steps.meta.outputs.version }}
    steps:
      - uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Login to GitHub Container Registry
        uses: docker/login-action@v3
        with:
          registry: ${{ env.REGISTRY }}
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Extract metadata
        id: meta
        uses: docker/metadata-action@v5
        with:
          images: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}
          tags: |
            type=sha,prefix=,suffix=,format=short
            type=ref,event=branch
            type=semver,pattern={{version}}

      - name: Build and push
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ${{ steps.meta.outputs.tags }}
          labels: ${{ steps.meta.outputs.labels }}
          cache-from: type=gha
          cache-to: type=gha,mode=max

  # ── Helm Validate ──────────────────────────────────────────────
  helm-validate:
    name: Helm Lint & Template
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v3
        with:
          version: v3.13.0

      - name: Helm lint
        run: |
          helm lint ${{ env.CHART_PATH }}
          helm lint ${{ env.CHART_PATH }} -f ${{ env.CHART_PATH }}/values-staging.yaml

      - name: Helm template (verify rendering)
        run: |
          helm template my-app ${{ env.CHART_PATH }} \
            -f ${{ env.CHART_PATH }}/values-staging.yaml \
            --set image.tag=test-sha \
            > /dev/null

      - name: Install helm-diff plugin
        run: helm plugin install https://github.com/databus23/helm-diff

  # ── Deploy to Staging ──────────────────────────────────────────
  deploy-staging:
    name: Deploy to Staging
    runs-on: ubuntu-latest
    needs: [build, helm-validate]
    environment: staging
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v3
        with:
          version: v3.13.0

      - name: Install helm-secrets
        run: helm plugin install https://github.com/jkroepke/helm-secrets

      - name: Configure AWS credentials (for SOPS KMS)
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789:role/github-actions-staging
          aws-region: eu-central-1

      - name: Configure kubectl
        uses: azure/k8s-set-context@v3
        with:
          method: kubeconfig
          kubeconfig: ${{ secrets.KUBE_CONFIG_STAGING }}

      - name: Deploy to staging
        run: |
          helm secrets upgrade --install my-app ${{ env.CHART_PATH }} \
            --namespace staging \
            --create-namespace \
            --values ${{ env.CHART_PATH }}/values.yaml \
            --values ${{ env.CHART_PATH }}/values-staging.yaml \
            --values ${{ env.CHART_PATH }}/secrets/staging.enc.yaml \
            --set image.tag=${{ needs.build.outputs.image-tag }} \
            --set deploymentAnnotations."deploy-time"="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
            --atomic \
            --timeout 10m \
            --wait

      - name: Run Helm tests
        run: helm test my-app --namespace staging --logs

  # ── Deploy to Production ───────────────────────────────────────
  deploy-production:
    name: Deploy to Production
    runs-on: ubuntu-latest
    needs: [deploy-staging]
    environment:
      name: production
      url: https://my-app.example.com
    steps:
      - uses: actions/checkout@v4

      - name: Set up Helm
        uses: azure/setup-helm@v3

      - name: Install helm-secrets
        run: helm plugin install https://github.com/jkroepke/helm-secrets

      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v4
        with:
          role-to-assume: arn:aws:iam::123456789:role/github-actions-production
          aws-region: eu-central-1

      - name: Configure kubectl
        uses: azure/k8s-set-context@v3
        with:
          method: kubeconfig
          kubeconfig: ${{ secrets.KUBE_CONFIG_PRODUCTION }}

      - name: Show diff before deploying
        run: |
          helm plugin install https://github.com/databus23/helm-diff
          helm secrets diff upgrade my-app ${{ env.CHART_PATH }} \
            --namespace production \
            --values ${{ env.CHART_PATH }}/values.yaml \
            --values ${{ env.CHART_PATH }}/values-production.yaml \
            --values ${{ env.CHART_PATH }}/secrets/production.enc.yaml \
            --set image.tag=${{ needs.build.outputs.image-tag }} \
            --allow-unreleased

      - name: Deploy to production
        run: |
          helm secrets upgrade --install my-app ${{ env.CHART_PATH }} \
            --namespace production \
            --create-namespace \
            --values ${{ env.CHART_PATH }}/values.yaml \
            --values ${{ env.CHART_PATH }}/values-production.yaml \
            --values ${{ env.CHART_PATH }}/secrets/production.enc.yaml \
            --set image.tag=${{ needs.build.outputs.image-tag }} \
            --atomic \
            --timeout 15m \
            --wait \
            --cleanup-on-fail

      - name: Run smoke tests
        run: |
          helm test my-app --namespace production --logs

      - name: Notify on success
        if: success()
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "✅ Deployed my-app ${{ needs.build.outputs.image-tag }} to production"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}

      - name: Notify on failure
        if: failure()
        uses: slackapi/slack-github-action@v1
        with:
          payload: |
            {
              "text": "❌ Deployment of my-app ${{ needs.build.outputs.image-tag }} to production FAILED"
            }
        env:
          SLACK_WEBHOOK_URL: ${{ secrets.SLACK_WEBHOOK }}
```

### Rollback workflow

```yaml
# .github/workflows/rollback.yml
name: Rollback

on:
  workflow_dispatch:
    inputs:
      environment:
        required: true
        type: choice
        options: [staging, production]
      revision:
        description: "Revision to rollback to (empty = previous)"
        required: false

jobs:
  rollback:
    runs-on: ubuntu-latest
    environment: ${{ inputs.environment }}
    steps:
      - name: Configure kubectl
        uses: azure/k8s-set-context@v3
        with:
          kubeconfig: ${{ secrets[format('KUBE_CONFIG_{0}', inputs.environment)] }}

      - name: Rollback
        run: |
          if [ -n "${{ inputs.revision }}" ]; then
            helm rollback my-app ${{ inputs.revision }} \
              --namespace ${{ inputs.environment }} \
              --wait --timeout 10m
          else
            helm rollback my-app \
              --namespace ${{ inputs.environment }} \
              --wait --timeout 10m
          fi

      - name: Show current status
        run: |
          helm status my-app --namespace ${{ inputs.environment }}
          helm history my-app --namespace ${{ inputs.environment }}
```

---

## 3. GitLab CI Pipelines

```yaml
# .gitlab-ci.yml
stages:
  - build
  - validate
  - deploy-staging
  - deploy-production

variables:
  HELM_VERSION: "3.13.0"
  CHART_PATH: "helm/my-app"

# ── Reusable setup ──────────────────────────────────────────────
.helm-setup: &helm-setup
  before_script:
    - curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash -s -- --version v${HELM_VERSION}
    - helm plugin install https://github.com/jkroepke/helm-secrets
    - helm plugin install https://github.com/databus23/helm-diff
    - kubectl config use-context "$KUBE_CONTEXT"

# ── Build ────────────────────────────────────────────────────────
build-image:
  stage: build
  image: docker:24
  services: [docker:dind]
  script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY
    - docker build -t $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA .
    - docker push $CI_REGISTRY_IMAGE:$CI_COMMIT_SHORT_SHA

# ── Validate ─────────────────────────────────────────────────────
helm-lint:
  stage: validate
  image: alpine/helm:${HELM_VERSION}
  script:
    - helm lint ${CHART_PATH}
    - helm lint ${CHART_PATH} -f ${CHART_PATH}/values-staging.yaml
    - helm template my-app ${CHART_PATH} -f ${CHART_PATH}/values-staging.yaml > /dev/null

# ── Deploy Staging ───────────────────────────────────────────────
deploy-staging:
  stage: deploy-staging
  environment:
    name: staging
    url: https://staging.my-app.example.com
  <<: *helm-setup
  script:
    - |
      helm secrets upgrade --install my-app ${CHART_PATH} \
        --namespace staging \
        --create-namespace \
        --values ${CHART_PATH}/values.yaml \
        --values ${CHART_PATH}/values-staging.yaml \
        --values ${CHART_PATH}/secrets/staging.enc.yaml \
        --set image.tag=${CI_COMMIT_SHORT_SHA} \
        --atomic \
        --timeout 10m \
        --wait
    - helm test my-app --namespace staging --logs
  only:
    - main

# ── Deploy Production ────────────────────────────────────────────
deploy-production:
  stage: deploy-production
  environment:
    name: production
    url: https://my-app.example.com
  when: manual             # require manual approval
  <<: *helm-setup
  script:
    - |
      helm secrets diff upgrade my-app ${CHART_PATH} \
        --namespace production \
        --values ${CHART_PATH}/values.yaml \
        --values ${CHART_PATH}/values-production.yaml \
        --values ${CHART_PATH}/secrets/production.enc.yaml \
        --set image.tag=${CI_COMMIT_SHORT_SHA} \
        --allow-unreleased
    - |
      helm secrets upgrade --install my-app ${CHART_PATH} \
        --namespace production \
        --create-namespace \
        --values ${CHART_PATH}/values.yaml \
        --values ${CHART_PATH}/values-production.yaml \
        --values ${CHART_PATH}/secrets/production.enc.yaml \
        --set image.tag=${CI_COMMIT_SHORT_SHA} \
        --atomic \
        --timeout 15m \
        --cleanup-on-fail
  only:
    - main
```

---

## 4. Chart Releaser — Publishing Charts

**chart-releaser** (cr) automates publishing Helm charts to GitHub Pages.

```yaml
# .github/workflows/release-chart.yml
name: Release Chart

on:
  push:
    branches: [main]
    paths:
      - 'charts/**'

jobs:
  release:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      - name: Configure Git
        run: |
          git config user.name "$GITHUB_ACTOR"
          git config user.email "$GITHUB_ACTOR@users.noreply.github.com"

      - name: Install Helm
        uses: azure/setup-helm@v3

      - name: Add dependency repos
        run: |
          helm repo add bitnami https://charts.bitnami.com/bitnami

      - name: Run chart-releaser
        uses: helm/chart-releaser-action@v1.6.0
        env:
          CR_TOKEN: ${{ secrets.GITHUB_TOKEN }}
        with:
          charts_dir: charts      # directory containing your charts
```

This action:
1. Detects changed charts
2. Packages them
3. Creates GitHub Releases with the chart tarballs
4. Updates `index.yaml` on the `gh-pages` branch

---

## 5. GitOps with ArgoCD

ArgoCD watches a Git repository and automatically syncs Helm charts to a cluster.

```yaml
# ArgoCD Application — deploy a Helm chart from a repo
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: my-app
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/myorg/my-app
    targetRevision: main
    path: helm/my-app
    helm:
      valueFiles:
        - values.yaml
        - values-production.yaml
      parameters:
        - name: image.tag
          value: v1.2.3

  destination:
    server: https://kubernetes.default.svc
    namespace: production

  syncPolicy:
    automated:
      prune: true            # delete resources removed from Git
      selfHeal: true         # re-sync if manual changes are made
    syncOptions:
      - CreateNamespace=true
      - ServerSideApply=true
```

---

## 6. Best Practices

```bash
# Always use --atomic in CI — auto-rollback on failure
helm upgrade --install my-app ./chart --atomic --timeout 10m

# Always use --wait — ensure rollout is complete
helm upgrade --install my-app ./chart --wait --timeout 10m

# Show diff before deploying (manual review or PR comment)
helm diff upgrade my-app ./chart --values values-prod.yaml --allow-unreleased

# Pin Helm version in CI — don't use latest
uses: azure/setup-helm@v3
with:
  version: v3.13.0   # pinned

# Use --cleanup-on-fail on upgrades — clean up new resources if upgrade fails
helm upgrade my-app ./chart --cleanup-on-fail

# Rollback strategy in CI
helm upgrade --install my-app ./chart --atomic || {
  echo "Deployment failed, checking rollback..."
  helm rollback my-app --wait
  exit 1
}

# Tag images with Git SHA — always traceable
image.tag: ${{ github.sha }}   # GitHub
image.tag: ${CI_COMMIT_SHORT_SHA}  # GitLab
```

---

## Cheatsheet

```bash
# Idempotent deploy with secrets
helm secrets upgrade --install my-app ./chart \
  --namespace production \
  --create-namespace \
  --values values.yaml \
  --values values-production.yaml \
  --values secrets/production.enc.yaml \
  --set image.tag=abc123 \
  --atomic \
  --timeout 10m \
  --wait \
  --cleanup-on-fail

# Show diff before deploying
helm diff upgrade my-app ./chart \
  --values values-production.yaml \
  --allow-unreleased

# Rollback
helm rollback my-app          # to previous revision
helm rollback my-app 3        # to revision 3
helm rollback my-app --wait   # wait for rollback to complete

# Run tests after deploy
helm test my-app --namespace production --logs
```

---

*Next: [OCI Registries →](./08-oci-registries.md)*
