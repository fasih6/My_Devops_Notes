# 🔧 Jenkins CI/CD

A complete Jenkins knowledge base — from core concepts to production-grade pipelines, Kubernetes agents, and enterprise administration.

> Jenkins is the dominant CI/CD server in enterprise environments globally, especially in Germany. Despite newer tools, most existing enterprise DevOps roles still use Jenkins. Knowing it deeply alongside GitLab CI makes you a complete CI/CD engineer.

---

## 🗺️ Learning Path

```
01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10
 │     │     │     │     │     │     │     │     │     │
 │     │     │     │     │     │     │     │     │     └── Interview prep
 │     │     │     │     │     │     │     │     └──────── Security & admin
 │     │     │     │     │     │     │     └────────────── K8s integration
 │     │     │     │     │     │     └──────────────────── Docker builds
 │     │     │     │     │     └────────────────────────── Pipeline patterns
 │     │     │     │     └──────────────────────────────── Secrets management
 │     │     │     └────────────────────────────────────── Agents & nodes
 │     │     └──────────────────────────────────────────── Shared libraries
 │     └────────────────────────────────────────────────── Jenkinsfile mastery
 └──────────────────────────────────────────────────────── How Jenkins works
```

---

## 📚 Contents

| # | File | What you'll learn |
|---|------|------------------|
| 01 | [Core Concepts](./01-core-concepts.md) | Architecture, jobs, plugins, triggers, controller vs agent |
| 02 | [Jenkinsfile & Pipeline](./02-jenkinsfile-pipeline.md) | Declarative vs scripted, stages, post, when, complete examples |
| 03 | [Shared Libraries](./03-shared-libraries.md) | Writing reusable pipeline code, vars/, src/, testing |
| 04 | [Agents & Nodes](./04-agents-nodes.md) | Static, Docker, Kubernetes pod agents, labels, autoscaling |
| 05 | [Variables, Credentials & Secrets](./05-variables-credentials-secrets.md) | withCredentials, Vault, OIDC, built-in vars |
| 06 | [Pipeline Patterns](./06-pipeline-patterns.md) | Parallel, matrix, error handling, retry, notifications |
| 07 | [Docker & Container Builds](./07-docker-container-builds.md) | Docker Pipeline plugin, registry, caching, multi-platform |
| 08 | [Jenkins with Kubernetes](./08-jenkins-kubernetes.md) | Kubernetes plugin, pod templates, Helm deploys, RBAC |
| 09 | [Security & Administration](./09-security-administration.md) | RBAC, JCasC, backup, plugin management, monitoring |
| 10 | [Interview Q&A](./10-interview-qa.md) | Core, scenario-based, and advanced interview questions |

---

## ⚡ Quick Reference

### Minimal Jenkinsfile

```groovy
pipeline {
    agent any
    stages {
        stage('Build') {
            steps { sh 'make build' }
        }
        stage('Test') {
            steps { sh 'make test' }
            post { always { junit 'results/*.xml' } }
        }
        stage('Deploy') {
            when { branch 'main' }
            steps { sh './deploy.sh' }
        }
    }
    post {
        failure { slackSend color: 'danger', message: "❌ ${JOB_NAME} failed" }
    }
}
```

### Common pipeline patterns

```groovy
// Parallel stages
stage('Test') {
    parallel {
        stage('Unit')  { steps { sh 'pytest tests/unit/' } }
        stage('E2E')   { steps { sh 'cypress run' } }
    }
}

// Kubernetes pod agent
agent {
    kubernetes {
        yaml """
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: build
      image: python:3.11
      command: [sleep]
      args: [infinity]
"""
    }
}

// Use credentials
withCredentials([usernamePassword(
    credentialsId: 'registry-creds',
    usernameVariable: 'USR',
    passwordVariable: 'PWD'
)]) {
    sh 'docker login -u $USR -p $PWD registry.example.com'
}

// Error handling
catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
    sh './optional-check.sh'
}
```

---

## 🧠 Key Concepts at a Glance

| Concept | One-line summary |
|---------|-----------------|
| **Controller** | Jenkins master — orchestrates, stores config, provides UI |
| **Agent** | Worker node — runs the actual build steps |
| **Executor** | Thread slot on an agent — runs one build at a time |
| **Pipeline** | Groovy DSL (Jenkinsfile) defining your CI/CD workflow |
| **Declarative** | Structured pipeline syntax — use this for new pipelines |
| **Scripted** | Raw Groovy pipeline — legacy, more flexible |
| **Multibranch** | Auto-creates pipelines per branch/PR |
| **Stage** | Named section of a pipeline |
| **Step** | Single action within a stage |
| **Shared Library** | Reusable Groovy code callable from any Jenkinsfile |
| **Stash/Unstash** | Pass files between stages/agents within a pipeline |
| **Artifact** | File archived for download after a build |
| **Credentials Store** | Encrypted secret storage in Jenkins |
| **withCredentials** | Scope secrets to a code block — Jenkins masks values in logs |
| **JCasC** | Jenkins Configuration as Code — YAML-defined Jenkins config |
| **Blue Ocean** | Modern pipeline visualization UI |
| **Kubernetes Plugin** | Dynamic pod agents — one pod per build |
| **Docker Pipeline** | Build/run Docker images in pipelines |
| **when** | Conditional stage execution |
| **post** | Actions after stages complete (success, failure, always) |
| **input** | Manual approval gate in a pipeline |
| **catchError** | Continue pipeline after failure, mark as unstable |
| **parallel** | Run multiple stages simultaneously |
| **matrix** | Build across combinations (OS, language versions) |

---

## 🗂️ Folder Structure

```
cicd/jenkins/
├── 00-jenkins-index.md          ← You are here
├── 01-core-concepts.md
├── 02-jenkinsfile-pipeline.md
├── 03-shared-libraries.md
├── 04-agents-nodes.md
├── 05-variables-credentials-secrets.md
├── 06-pipeline-patterns.md
├── 07-docker-container-builds.md
├── 08-jenkins-kubernetes.md
├── 09-security-administration.md
└── 10-interview-qa.md
```

---

## 🔗 How Jenkins Connects to the Rest of Your Notes

| Topic | Connection |
|-------|-----------|
| **Docker** | Jenkins builds Docker images via Docker Pipeline plugin |
| **Kubernetes** | Jenkins runs on K8s, agents run as pods, deploys to K8s |
| **Helm** | Helm commands in deploy stages, Kubernetes pod with helm container |
| **Terraform** | `terraform plan/apply` in Jenkins stages |
| **Secrets/Vault** | Jenkins Vault plugin fetches secrets dynamically |
| **Networking** | Jenkins controller-agent communication, webhook ingress |
| **Observability** | Prometheus plugin exposes Jenkins metrics |

---

*Notes are living documents — updated as I learn and build.*
