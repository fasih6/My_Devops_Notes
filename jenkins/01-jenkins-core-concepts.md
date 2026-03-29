# 🔧 Jenkins Core Concepts & Architecture

How Jenkins works — controllers, agents, jobs, builds, plugins, and the Jenkins ecosystem.

> Jenkins is the most widely deployed CI/CD automation server in the world. Despite newer tools like GitLab CI and GitHub Actions, Jenkins is still dominant in enterprise environments — especially in Germany. Understanding it deeply opens doors to many existing DevOps roles.

---

## 📚 Table of Contents

- [1. What is Jenkins?](#1-what-is-jenkins)
- [2. Jenkins Architecture](#2-jenkins-architecture)
- [3. Jobs & Builds](#3-jobs--builds)
- [4. Plugins](#4-plugins)
- [5. Jenkins UI Overview](#5-jenkins-ui-overview)
- [6. Folder Organization](#6-folder-organization)
- [7. Build Triggers](#7-build-triggers)
- [8. Jenkins vs GitLab CI vs GitHub Actions](#8-jenkins-vs-gitlab-ci-vs-github-actions)
- [Key Terms Glossary](#key-terms-glossary)

---

## 1. What is Jenkins?

Jenkins is an open-source automation server. It automates building, testing, and deploying software. Originally developed as Hudson at Sun Microsystems, it was forked and renamed Jenkins in 2011.

### What Jenkins does

```
Source code pushed
        │
        ▼
Jenkins detects change (webhook/poll)
        │
        ▼
Runs build on an agent:
  - Checkout code
  - Run tests
  - Build artifact (JAR, Docker image, etc.)
  - Push to registry
  - Deploy to staging/production
        │
        ▼
Reports result (email, Slack, dashboard)
```

### Why Jenkins is still relevant

```
✅ Mature ecosystem — 1800+ plugins
✅ Highly customizable — any tool can be integrated
✅ Self-hosted — full control over infrastructure
✅ Large talent pool — most DevOps engineers know it
✅ Enterprise features — RBAC, audit logs, SSO
✅ Runs anywhere — on-prem, cloud, Kubernetes

❌ Complex to configure and maintain
❌ Groovy DSL learning curve
❌ Plugin compatibility issues
❌ UI is dated
❌ Resource-heavy for the controller
```

---

## 2. Jenkins Architecture

### Controller (master) + Agent (worker) model

```
┌──────────────────────────────────────────────────────┐
│                  Jenkins Controller                    │
│                                                        │
│  ┌──────────────┐  ┌──────────────┐  ┌────────────┐  │
│  │  Job Config  │  │  Build Queue │  │  Plugin    │  │
│  │  & History   │  │  & Schedule  │  │  Manager   │  │
│  └──────────────┘  └──────────────┘  └────────────┘  │
│                                                        │
│  Web UI + REST API + CLI                               │
└───────────────────────┬──────────────────────────────┘
                        │ (JNLP / SSH / WebSocket)
           ┌────────────┼────────────┐
           │            │            │
    ┌──────┴──┐  ┌──────┴──┐  ┌────┴────┐
    │ Agent 1 │  │ Agent 2 │  │ Agent 3 │
    │ Linux   │  │ Windows │  │ K8s pod │
    │ docker  │  │ .NET    │  │ any job │
    └─────────┘  └─────────┘  └─────────┘
```

### Controller responsibilities

- Stores all configuration (jobs, credentials, plugins)
- Schedules builds and assigns them to agents
- Provides the web UI and REST API
- Records build history and logs
- **Should NOT run build jobs** (resource contention with UI)

### Agent responsibilities

- Runs the actual build steps
- Can be specialized (Linux, Windows, Docker, high-memory)
- Connects to controller via SSH, JNLP, or WebSocket
- Executes workspace operations

### Controller-only configuration

```groovy
// Best practice: restrict controller to administrative tasks only
// Jenkins UI → Manage Jenkins → Nodes → controller → # of executors → set to 0
// This ensures no builds run on the controller
```

### How a build flows

```
1. Developer pushes code → webhook hits Jenkins
2. Controller receives webhook → finds matching job
3. Controller adds build to queue
4. Controller finds available agent matching job's requirements
5. Controller sends job to agent
6. Agent checks out code, runs steps, reports result
7. Agent sends logs/artifacts back to controller
8. Controller records result, sends notifications
```

---

## 3. Jobs & Builds

### Job types

| Job Type | Description | Use for |
|---------|-------------|---------|
| **Freestyle** | GUI-configured, single-branch | Legacy, simple scripts |
| **Pipeline** | Groovy DSL (Jenkinsfile) | Modern CI/CD |
| **Multibranch Pipeline** | Pipeline per branch/PR | Feature branches, MRs |
| **Organization Folder** | Scans GitHub/GitLab org for repos | Organization-wide CI |
| **Matrix** | Build across combinations | Multi-platform testing |
| **External Job** | Record external process results | Legacy integration |

### Freestyle vs Pipeline

```
Freestyle:
  - Configured via GUI (Build Steps, Post-build Actions)
  - Hard to version control (stored as XML in Jenkins)
  - Limited conditionals and loops
  - No pipeline visualization
  - Fine for simple, unchanging jobs

Pipeline:
  - Defined in Jenkinsfile (stored in SCM with code)
  - Full Groovy programming
  - Stage visualization (Blue Ocean)
  - Conditional execution, loops, functions
  - Shared libraries for reuse
  - Modern standard
```

### Build lifecycle

```
Build states:
  Triggered → Queued → Running → Completed

Completed states:
  SUCCESS  → all steps passed
  UNSTABLE → build ran but some tests failed
  FAILURE  → build failed (script error, compilation error)
  ABORTED  → manually cancelled
  NOT_BUILT → skipped (conditional)
```

```groovy
// Access build result in Jenkinsfile
pipeline {
    agent any
    stages {
        stage('Test') {
            steps {
                sh 'pytest || true'  // don't fail build on test failure
            }
            post {
                always {
                    junit 'test-results.xml'
                }
                failure {
                    echo "Tests failed"
                    currentBuild.result = 'UNSTABLE'
                }
            }
        }
    }
    post {
        success { echo "Build ${currentBuild.number} succeeded" }
        failure { echo "Build ${currentBuild.number} failed" }
    }
}
```

### Build artifacts

```groovy
// Archive artifacts (makes them downloadable from build page)
archiveArtifacts artifacts: 'target/*.jar', fingerprint: true

// Archive with pattern
archiveArtifacts artifacts: 'dist/**/*', allowEmptyArchive: true

// Stash/unstash (pass files between stages on different agents)
stash name: 'compiled-app', includes: 'target/*.jar'
unstash 'compiled-app'
```

---

## 4. Plugins

Jenkins gets most of its functionality from plugins. There are 1800+ plugins available.

### Essential plugins

| Plugin | What it does |
|--------|-------------|
| **Git** | Git SCM integration |
| **Pipeline** | Core pipeline support |
| **Blue Ocean** | Modern pipeline UI |
| **Credentials** | Secure credential storage |
| **Kubernetes** | Dynamic Kubernetes agents |
| **Docker Pipeline** | Build and use Docker images |
| **GitHub Branch Source** | Scan GitHub orgs for repos |
| **GitLab** | GitLab integration (webhooks, MR status) |
| **LDAP / Active Directory** | Enterprise authentication |
| **Role-based Authorization** | RBAC for Jenkins |
| **Slack Notification** | Send build notifications to Slack |
| **JUnit** | Parse and display test results |
| **Jacoco / Cobertura** | Code coverage reports |
| **SonarQube Scanner** | Code quality analysis |
| **HashiCorp Vault** | Fetch secrets from Vault |
| **AWS Credentials** | AWS credential management |
| **Timestamper** | Add timestamps to console output |
| **AnsiColor** | Colorize console output |
| **Build Timeout** | Kill builds that run too long |
| **Workspace Cleanup** | Clean workspace after build |

### Managing plugins

```
Jenkins UI → Manage Jenkins → Plugins

Install: Available plugins → search → Install
Update:  Updates tab → check all → Download and install
Remove:  Installed tab → Uninstall

# Important: always test plugin updates in non-production Jenkins first
# Plugin updates can break existing pipelines
```

### Plugin best practices

```
✅ Pin plugin versions in production (plugin.txt or jenkins-plugin-cli)
✅ Test updates in dev Jenkins before applying to production
✅ Minimize number of plugins (each = potential security risk + maintenance)
✅ Use Configuration as Code (JCasC) to version-control plugin config
✅ Monitor plugin security advisories
```

---

## 5. Jenkins UI Overview

```
Dashboard
├── New Item               → create job/folder
├── People                 → users with recent builds
├── Build History          → recent builds across all jobs
├── Manage Jenkins         → admin settings
│   ├── System             → global config (paths, environment, SCM)
│   ├── Plugins            → install/update plugins
│   ├── Nodes              → manage agents
│   ├── Credentials        → manage secrets
│   ├── Configuration as Code → JCasC
│   └── System Log         → Jenkins logs
└── My Views               → custom dashboards

Job page:
├── Build Now              → trigger manual build
├── Configure              → edit job config
├── Build History          → past builds (left sidebar)
└── [build #]
    ├── Console Output     → full build log
    ├── Pipeline Steps     → step-by-step view
    ├── Test Results       → parsed JUnit output
    ├── Artifacts          → downloadable files
    └── Changes            → commits in this build
```

---

## 6. Folder Organization

Use folders to organize jobs by team, project, or environment.

```
Jenkins
├── Platform/                      ← Folder
│   ├── infrastructure-pipeline
│   ├── kubernetes-upgrade
│   └── monitoring-deploy
├── Backend/                       ← Folder
│   ├── api-service/               ← Nested folder
│   │   ├── main                   ← branch pipeline
│   │   ├── staging                ← branch pipeline
│   │   └── feature-*              ← auto-discovered branches
│   └── worker-service/
└── Frontend/
    └── web-app/
```

### Creating folders via Job DSL / JCasC

```groovy
// Jenkinsfile for a folder seed job (Job DSL plugin)
job('Backend/api-service/deploy') {
    scm {
        git('https://gitlab.com/myorg/api-service.git')
    }
    triggers {
        scm('H/5 * * * *')
    }
    steps {
        shell('./deploy.sh')
    }
}
```

---

## 7. Build Triggers

### Webhook (push-based — preferred)

```groovy
// Jenkinsfile — configure in GitHub/GitLab settings to call:
// https://jenkins.example.com/github-webhook/
// https://jenkins.example.com/project/my-job  (for GitLab)

properties([
    pipelineTriggers([
        [$class: 'GitHubPushTrigger'],      // GitHub
        [$class: 'GitLabPushTrigger'],      // GitLab
    ])
])
```

### SCM Polling (pull-based — avoid for new setups)

```groovy
// Poll every 5 minutes (uses H for load distribution)
triggers {
    pollSCM('H/5 * * * *')
}
// H = hash-based offset — distributes load across Jenkins
// H/5 * * * * = every 5 minutes, at a consistent offset per job
```

### Schedule (cron)

```groovy
triggers {
    cron('H 2 * * *')    // daily at ~2am (H distributes exact time)
    cron('H 8 * * 1-5')  // weekdays at ~8am
    cron('@weekly')       // once a week
    cron('@midnight')     // once a day, midnight
}
```

### Upstream trigger

```groovy
// Run this pipeline when another job completes
triggers {
    upstream(upstreamProjects: 'my-upstream-job', threshold: hudson.model.Result.SUCCESS)
}
```

### Manual trigger via API

```bash
# Trigger a build via REST API
curl -X POST https://jenkins.example.com/job/my-job/build \
  --user user:api-token

# Trigger with parameters
curl -X POST https://jenkins.example.com/job/my-job/buildWithParameters \
  --user user:api-token \
  --data-urlencode json='{"parameter":[{"name":"BRANCH","value":"main"}]}'
```

---

## 8. Jenkins vs GitLab CI vs GitHub Actions

| Feature | Jenkins | GitLab CI | GitHub Actions |
|---------|---------|-----------|----------------|
| **Setup** | Self-hosted, complex | SaaS or self-hosted | SaaS or self-hosted |
| **Pipeline def** | Jenkinsfile (Groovy) | .gitlab-ci.yml (YAML) | .github/workflows/*.yml (YAML) |
| **Agent setup** | Manual or cloud plugin | Runners (auto or manual) | GitHub-hosted or self-hosted |
| **Extensibility** | 1800+ plugins | Templates + components | 10,000+ marketplace actions |
| **Secrets** | Credentials store | CI/CD Variables | Repository secrets |
| **Cost** | Infrastructure only | Free tier + paid | Free tier + paid |
| **Learning curve** | High (Groovy + plugins) | Medium | Low |
| **Enterprise use** | Very high | High | Growing |
| **Flexibility** | Maximum | High | High |

---

## Key Terms Glossary

| Term | Definition |
|------|-----------|
| **Controller** | Jenkins master — orchestrates builds, stores config, serves UI |
| **Agent** | Worker node that runs build steps |
| **Executor** | A thread on an agent that runs one build at a time |
| **Job** | A configured automation task in Jenkins |
| **Build** | A single execution of a job |
| **Pipeline** | Jenkins job defined as code (Jenkinsfile) |
| **Stage** | Named section of a pipeline |
| **Step** | Single action within a stage |
| **Workspace** | Directory on agent where build files are kept |
| **Artifact** | File produced by a build, archived for download |
| **Stash** | Temporary file storage passed between stages/agents |
| **Fingerprint** | MD5 hash tracking which builds used a file |
| **Plugin** | Extension that adds features to Jenkins |
| **Shared Library** | Reusable Groovy code shared across pipelines |
| **Credentials** | Secure storage for secrets (username/password, tokens, SSH keys) |
| **JCasC** | Jenkins Configuration as Code — YAML-based Jenkins config |
| **Blue Ocean** | Modern pipeline visualization UI |
| **Multibranch** | Job that automatically creates pipelines per branch/PR |
| **JNLP** | Java Network Launch Protocol — agent connection method |
| **Groovy** | Programming language used for Jenkinsfiles and shared libraries |

---

*Next: [Jenkinsfile & Pipeline as Code →](./02-jenkinsfile-pipeline.md)*
