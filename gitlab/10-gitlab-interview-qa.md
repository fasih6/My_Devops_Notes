# 🎯 GitLab CI Interview Q&A

Real GitLab CI/CD questions asked in DevOps interviews — with complete answers.

---

## 📚 Table of Contents

- [🔥 Core Concepts](#-core-concepts)
- [⚙️ Pipeline Configuration](#️-pipeline-configuration)
- [🏃 Runners & Infrastructure](#-runners--infrastructure)
- [🚀 Deployments & Environments](#-deployments--environments)
- [🔐 Security](#-security)
- [🔥 Scenario-Based Questions](#-scenario-based-questions)
- [🧠 Advanced Questions](#-advanced-questions)
- [💬 Questions to Ask the Interviewer](#-questions-to-ask-the-interviewer)

---

## 🔥 Core Concepts

---

**Q: What is the difference between a stage and a job in GitLab CI?**

A **stage** is a group that defines execution order — stages run sequentially, and a stage only starts when all jobs in the previous stage succeed.

A **job** is the actual unit of work — a set of commands executed by a runner. Jobs within the same stage run in parallel.

```yaml
stages: [build, test, deploy]   # 3 stages, sequential

build-app:    stage: build     # these two
build-docs:   stage: build     # run in parallel

unit-tests:   stage: test      # waits for both builds
e2e-tests:    stage: test      # also parallel

deploy:       stage: deploy    # waits for all tests
```

---

**Q: What is the difference between `artifacts` and `cache` in GitLab CI?**

**Artifacts** are files produced by a job that you want to pass to subsequent jobs in the same pipeline, or keep for download after the pipeline. They are tied to a specific pipeline and job, and are uploaded to and downloaded from GitLab.

**Cache** is for storing files between pipeline runs to speed up subsequent pipelines — typically package manager downloads like `node_modules/` or `.pip-cache/`. Cache is stored on the runner and not guaranteed to be present.

Rule of thumb: artifacts for things you *need* (build output, test reports), cache for things that *speed things up* (dependencies).

---

**Q: What is `needs` and how does it differ from stages?**

`needs` enables DAG (Directed Acyclic Graph) pipelines — a job can start as soon as its declared dependencies finish, without waiting for the entire previous stage.

Without `needs`: test-frontend waits for both build-frontend AND build-backend to finish.
With `needs: [build-frontend]`: test-frontend starts as soon as build-frontend finishes, even if build-backend is still running.

This can significantly reduce total pipeline time for independent workstreams — frontend and backend pipelines can run completely independently and in parallel through all stages.

---

**Q: What is the difference between `rules` and `only/except`?**

Both control when a job runs, but `rules` is more powerful and is the modern replacement for `only/except`.

`only/except` is simple but limited:
```yaml
only: [main]
except: [schedules]
```

`rules` supports conditional logic, variable overrides, file change detection, and dynamic `when`:
```yaml
rules:
  - if: '$CI_COMMIT_BRANCH == "main" && $CI_PIPELINE_SOURCE != "schedule"'
    variables:
      DEPLOY_ENV: production
  - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    changes: ["src/**"]
    when: on_success
  - when: never
```

Always use `rules` for new pipelines. `only/except` can't be combined with `rules`.

---

## ⚙️ Pipeline Configuration

---

**Q: How would you avoid duplicate pipelines (one from a push, one from an MR)?**

Use the `workflow` keyword to cancel the branch pipeline when an MR exists for that branch:

```yaml
workflow:
  rules:
    - if: '$CI_COMMIT_BRANCH && $CI_OPEN_MERGE_REQUESTS'
      when: never    # skip branch pipeline if MR exists
    - if: '$CI_COMMIT_BRANCH'
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
```

This way only the MR pipeline runs (not both branch + MR pipelines simultaneously).

---

**Q: How do you share configuration between jobs without repeating yourself?**

Three approaches, in order of preference:

1. **`extends`** — template inheritance. Define a hidden job (starts with `.`) and extend it:
```yaml
.docker-base:
  image: docker:24
  services: [docker:24-dind]
  before_script:
    - docker login -u $CI_REGISTRY_USER -p $CI_REGISTRY_PASSWORD $CI_REGISTRY

build-app:
  extends: .docker-base
  script: docker build -t my-app .
```

2. **`include`** — split configuration into multiple files and include them.

3. **YAML anchors** — work within the same file only.

`extends` is preferred over YAML anchors because it works across included files and GitLab understands it for better UI feedback.

---

**Q: What is a parent-child pipeline and when would you use it?**

A parent-child pipeline is where one pipeline triggers sub-pipelines using the `trigger` keyword. The child pipeline runs independently with its own jobs and stages.

Use cases:
- **Monorepos** — trigger separate pipelines per microservice, only when that service's files change
- **Organizational complexity** — split a huge `.gitlab-ci.yml` into manageable child configs
- **Shared infrastructure** — one parent orchestrates multiple downstream deployments

```yaml
trigger-frontend:
  trigger:
    include: .gitlab/ci/frontend.yml
    strategy: depend   # parent waits for child
  rules:
    - changes: ["frontend/**"]
```

---

## 🏃 Runners & Infrastructure

---

**Q: What is a GitLab Runner and what executors are available?**

A GitLab Runner is an agent that picks up jobs from GitLab and executes them. It's a Go binary that runs anywhere — VM, bare metal, container, or Kubernetes pod.

The executor defines how the runner runs jobs:
- **docker** — each job in a fresh container (most common, isolated, reproducible)
- **shell** — directly on the runner machine (no isolation, good for legacy)
- **kubernetes** — each job as a Kubernetes pod (cloud-native, autoscaling)
- **docker+machine** — auto-provisions cloud VMs (autoscaling on AWS/GCP)

The docker executor is the most common for modern CI.

---

**Q: What is the difference between shared runners and project runners?**

**Shared runners** are available to all projects on the GitLab instance. GitLab.com provides shared runners with a free monthly CI minute quota. Good for general workloads.

**Project runners** (or group runners) are registered to a specific project or group. Use when you need:
- Specific hardware (GPUs, high memory)
- Access to internal network resources
- Custom software installed
- Higher concurrency than shared runners allow
- Security isolation (don't want your code running on shared infrastructure)

---

**Q: How do you make a runner only pick up jobs for specific projects?**

Use the `locked` flag and `tags`:

```bash
# Lock runner to specific project
gitlab-runner register \
  --locked true \               # only runs for the project it's registered to
  --tag-list "production,secure"

# In .gitlab-ci.yml
deploy-production:
  tags:
    - production    # only runs on runners with this tag
    - secure
```

You can also configure protected runners that only run jobs on protected branches/tags.

---

## 🚀 Deployments & Environments

---

**Q: What is a GitLab Environment and what benefits does it provide?**

A GitLab Environment is a tracked deployment target — it records every deployment, who deployed it, when, and what version is currently running.

Benefits:
- **Deployment history** — see every deployment, roll back via UI by clicking "Re-deploy"
- **Live environment link** — click through to the running application from the GitLab pipeline
- **Stop environments** — tear down temporary review apps with one click
- **Deployment tiers** — label critical/production/staging environments
- **Protected environments** — require approvals before deploying

```yaml
deploy:
  environment:
    name: production
    url: https://example.com
```

---

**Q: How do you implement review apps in GitLab CI?**

Review apps create temporary environments for each merge request — letting you see a live preview of the code changes.

```yaml
deploy-review:
  script:
    - helm upgrade --install review-$CI_MERGE_REQUEST_IID ./chart
        --set ingress.host=mr-$CI_MERGE_REQUEST_IID.review.example.com
        --set image.tag=$CI_COMMIT_SHORT_SHA
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    url: https://mr-$CI_MERGE_REQUEST_IID.review.example.com
    on_stop: stop-review
    auto_stop_in: 2 days
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'

stop-review:
  script: helm uninstall review-$CI_MERGE_REQUEST_IID
  environment:
    name: review/$CI_COMMIT_REF_SLUG
    action: stop
  when: manual
```

GitLab adds a "View app" button to the MR, linking to the review app URL.

---

## 🔐 Security

---

**Q: What is the difference between masked and protected variables?**

**Masked** — the value is hidden in job logs. If the variable appears in output, GitLab replaces it with `[MASKED]`. Requirement: single line, at least 8 printable ASCII characters.

**Protected** — the variable is only available in pipelines running on protected branches or tags (usually `main`, `production`). A job on a feature branch cannot access the variable at all.

Best practice for production secrets: **both masked AND protected**. Also scope them to the `production` environment. This way only pipelines that merge to main and deploy to production can access the secret, and it never appears in logs.

---

**Q: How does GitLab handle security scanning and where do results appear?**

GitLab has built-in templates for SAST, secret detection, dependency scanning, container scanning, and DAST. You include them with:

```yaml
include:
  - template: Security/SAST.gitlab-ci.yml
  - template: Security/Secret-Detection.gitlab-ci.yml
```

Results appear in:
1. **Merge request** — security findings tab shows new vulnerabilities introduced by the MR
2. **Security Dashboard** — project-level view of all vulnerabilities over time
3. **Vulnerability Report** — manage, dismiss, or create issues for findings
4. **MR blocking** — configured to require approval or block merge on HIGH/CRITICAL findings

---

## 🔥 Scenario-Based Questions

---

**Scenario 1: Your pipeline takes 45 minutes. How do you speed it up?**

```
1. Identify the bottleneck
   Look at the pipeline graph — which jobs take longest?
   Which jobs are waiting for other jobs unnecessarily?

2. Parallelize with DAG (needs)
   If frontend and backend pipelines are independent, they shouldn't wait
   for each other at every stage. Use needs to run them in parallel end-to-end.

3. Cache dependencies
   Cache: node_modules, .pip-cache, go module cache
   Key by lock file hash: changes only when deps change
   policy: pull for jobs that only read, pull-push for the one that updates

4. Fail fast
   Put lint and quick checks in early stages
   Use interruptible: true — cancel old pipelines when new push arrives

5. Build only what changed
   In monorepos: use rules: changes to only run affected service pipelines

6. Optimize Docker builds
   Layer ordering: dependencies before code
   BuildKit cache mounts for pip/npm
   Registry caching --cache-from

7. Run on faster runners
   More CPUs, more memory, faster disk (SSD)
   Kubernetes executor with appropriate resources
```

---

**Scenario 2: A secret was accidentally committed to the repository. What do you do?**

```
1. IMMEDIATELY revoke/rotate the exposed secret
   The secret is compromised — assume it was seen. Rotate first, remove later.

2. Remove from git history
   git filter-branch (old) or BFG Repo Cleaner (easier):
   bfg --delete-files secrets.env
   git push --force

   For GitLab: also run "Clean up" in project settings after rewriting history

3. Check who could have seen it
   - Anyone who cloned/forked the repo
   - GitLab CI job logs (if variable was printed)
   - Any CI artifacts that captured the value

4. Audit usage
   Check cloud provider logs for API calls using the exposed key
   Set up alerts for suspicious activity

5. Prevent recurrence
   - Enable Secret Detection in CI pipeline
   - Install pre-commit hooks (gitleaks, detect-secrets)
   - Educate team on using CI/CD variables instead of hardcoding
```

---

**Scenario 3: Your production deployment failed halfway through. What do you do?**

```
1. Assess the damage
   kubectl get pods -n production          # what's running?
   helm status my-app --namespace production # what did Helm do?
   kubectl get events -n production        # what happened?

2. If using --atomic flag:
   Helm automatically rolled back — you're already on the previous version
   Confirm: helm history my-app

3. If NOT using --atomic:
   Manual rollback:
   helm rollback my-app --namespace production --wait

4. Use GitLab environment to re-deploy previous version:
   GitLab UI → Deployments → Environments → production
   Find the last successful deployment → click Re-deploy

5. Fix the issue in the code, push a new commit
   New pipeline builds and deploys the fix

6. Post-mortem:
   Why did it fail?
   Add --atomic to prevent partial deployments in future
   Add smoke tests that run after deployment
   Consider canary deployment to limit blast radius
```

---

**Scenario 4: You need to deploy to 20 microservices in a monorepo. How do you structure the pipeline?**

```
Approach: parent-child pipelines with change detection

1. Parent pipeline detects which services changed
   git diff --name-only $CI_MERGE_REQUEST_DIFF_BASE_SHA HEAD

2. For each changed service, trigger a child pipeline
   trigger-api:
     trigger:
       include: services/api/.gitlab-ci.yml
       strategy: depend
     rules:
       - changes: ["services/api/**"]

3. Each service has its own .gitlab-ci.yml with:
   - Test
   - Build (Docker image)
   - Deploy to staging
   - Deploy to production (manual)

4. Services that didn't change don't run at all
   → Fast pipelines, only work on what changed

5. Shared templates for common jobs:
   - .gitlab/templates/docker-build.yml
   - .gitlab/templates/helm-deploy.yml
   Include from each service's pipeline
```

---

## 🧠 Advanced Questions

---

**Q: What is the GitLab Agent for Kubernetes and why is it preferred over certificate-based integration?**

The GitLab Agent (agentk) is a component that runs inside your Kubernetes cluster and maintains a persistent connection to GitLab. It uses a pull-based model — the agent polls GitLab for changes and applies them, rather than GitLab pushing to your cluster.

Advantages over certificate-based integration:
- **Works with private clusters** — no need to expose the Kubernetes API to GitLab's IP ranges
- **More secure** — no cluster credentials stored in GitLab
- **GitOps support** — agent can auto-sync manifests from Git (like ArgoCD)
- **CI/CD tunnel** — use kubectl in CI jobs without storing kubeconfig
- **Actively maintained** — certificate-based integration is deprecated

---

**Q: What is a merge train and why would you use it?**

A merge train queues merge requests and tests each one with all previously-queued commits included. Instead of testing MR-A and MR-B independently against main, it tests: main, main+MR-A, main+MR-A+MR-B.

This prevents the "last green merge" problem: MR-A and MR-B both test green independently, but together they break. With merge trains, you discover integration issues before merging, not after.

Trade-off: merge trains are slower (more pipeline runs per MR) but much safer for teams that merge frequently to a shared branch.

---

**Q: How would you implement OIDC authentication for GitLab CI to AWS without static credentials?**

Use GitLab's ID tokens feature to get a JWT, then exchange it for AWS credentials via STS:

```yaml
deploy:
  id_tokens:
    AWS_OIDC_TOKEN:
      aud: sts.amazonaws.com    # must match IAM OIDC provider
  script:
    - CREDS=$(aws sts assume-role-with-web-identity
        --role-arn arn:aws:iam::123456789:role/gitlab-ci
        --web-identity-token $AWS_OIDC_TOKEN
        --role-session-name $CI_JOB_ID)
    - export AWS_ACCESS_KEY_ID=$(echo $CREDS | jq -r .Credentials.AccessKeyId)
    - export AWS_SECRET_ACCESS_KEY=$(echo $CREDS | jq -r .Credentials.SecretAccessKey)
    - export AWS_SESSION_TOKEN=$(echo $CREDS | jq -r .Credentials.SessionToken)
    - aws s3 sync dist/ s3://my-bucket/
```

In AWS: create an IAM OIDC provider for `https://gitlab.com`, then an IAM role with trust policy that checks `sub` matches your project path and `aud` matches `sts.amazonaws.com`. No static AWS credentials stored anywhere.

---

## 💬 Questions to Ask the Interviewer

**On their GitLab setup:**
- "Do you use GitLab.com or self-hosted GitLab? What version?"
- "Do you run your own runners or use GitLab shared runners?"
- "How do you manage runner autoscaling — docker+machine, Kubernetes, or fixed runners?"

**On their practices:**
- "How is your .gitlab-ci.yml structured — single file or split across includes?"
- "Do you use parent-child pipelines, and if so for what use cases?"
- "How do you handle secrets — GitLab CI variables, Vault integration, or something else?"

**On their challenges:**
- "What's your average pipeline duration? Have you done any optimization work?"
- "Do you use merge trains? What was the experience adopting them?"
- "How do you handle compliance requirements — compliance pipelines, scan execution policies?"

---

*Good luck — GitLab CI expertise is highly valued in the German market where it's widely adopted. 🚀*
