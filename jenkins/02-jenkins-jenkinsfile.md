# 📄 Jenkinsfile & Pipeline as Code

Declarative vs scripted pipelines, stages, steps, post conditions, and the full Jenkinsfile anatomy.

---

## 📚 Table of Contents

- [1. Declarative vs Scripted Pipeline](#1-declarative-vs-scripted-pipeline)
- [2. Declarative Pipeline Anatomy](#2-declarative-pipeline-anatomy)
- [3. Stages & Steps](#3-stages--steps)
- [4. Post Conditions](#4-post-conditions)
- [5. Environment & Parameters](#5-environment--parameters)
- [6. Options](#6-options)
- [7. When Directives (Conditions)](#7-when-directives-conditions)
- [8. Common Steps Reference](#8-common-steps-reference)
- [9. Complete Real-World Jenkinsfile](#9-complete-real-world-jenkinsfile)
- [Cheatsheet](#cheatsheet)

---

## 1. Declarative vs Scripted Pipeline

### Declarative (modern — use this)

```groovy
pipeline {
    agent any
    stages {
        stage('Build') {
            steps {
                sh 'make build'
            }
        }
    }
}
```

- Structured, opinionated syntax
- Validated before execution (catches syntax errors early)
- Better UI visualization in Blue Ocean
- Supports `script {}` blocks for imperative code when needed
- **Use for all new pipelines**

### Scripted (legacy — avoid for new pipelines)

```groovy
node('linux') {
    stage('Build') {
        sh 'make build'
    }
    stage('Test') {
        sh 'make test'
    }
}
```

- Full Groovy programming power
- No structure validation — errors only at runtime
- More flexible but harder to read and maintain
- Still seen in older enterprise Jenkins installations

### Mixing: script block in declarative

```groovy
pipeline {
    agent any
    stages {
        stage('Complex Logic') {
            steps {
                script {
                    // Full Groovy here
                    def version = sh(
                        script: 'git describe --tags',
                        returnStdout: true
                    ).trim()
                    env.APP_VERSION = version
                    echo "Building version: ${version}"
                }
            }
        }
    }
}
```

---

## 2. Declarative Pipeline Anatomy

```groovy
pipeline {
    // ── Top-level required ─────────────────────────────────────

    // WHERE to run — agent selection
    agent {
        label 'linux && docker'
        // or: any, none, docker, kubernetes
    }

    // ── Optional top-level directives ─────────────────────────

    // Global environment variables
    environment {
        APP_NAME    = 'my-app'
        REGISTRY    = 'registry.example.com'
        IMAGE       = "${REGISTRY}/${APP_NAME}:${BUILD_NUMBER}"
    }

    // Build parameters (shown in "Build with Parameters" UI)
    parameters {
        string(name: 'BRANCH', defaultValue: 'main', description: 'Branch to build')
        choice(name: 'ENVIRONMENT', choices: ['staging', 'production'], description: 'Target env')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip test stage')
        password(name: 'API_KEY', description: 'API Key')
    }

    // Global pipeline options
    options {
        timeout(time: 1, unit: 'HOURS')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        disableConcurrentBuilds()
        timestamps()
        ansiColor('xterm')
    }

    // When to auto-trigger
    triggers {
        pollSCM('H/5 * * * *')
        cron('H 2 * * *')
    }

    // Tool installations (must be configured in Jenkins → Tools)
    tools {
        maven 'Maven 3.9'
        jdk 'JDK 17'
        nodejs 'Node 20'
    }

    // ── Stages — the actual work ───────────────────────────────
    stages {
        stage('Build') {
            steps {
                sh 'mvn clean package -DskipTests'
            }
        }
        stage('Test') {
            steps {
                sh 'mvn test'
            }
        }
    }

    // ── Post — always runs after stages ───────────────────────
    post {
        always {
            junit '**/target/surefire-reports/*.xml'
            cleanWs()
        }
        success {
            slackSend color: 'good', message: "Build ${BUILD_NUMBER} succeeded"
        }
        failure {
            slackSend color: 'danger', message: "Build ${BUILD_NUMBER} FAILED"
            emailext to: 'team@example.com', subject: "Build Failed", body: "${BUILD_URL}"
        }
    }
}
```

---

## 3. Stages & Steps

### Stage anatomy

```groovy
stage('Deploy') {
    // Stage-level agent (overrides top-level)
    agent {
        label 'deploy-agent'
    }

    // Stage-level environment
    environment {
        DEPLOY_ENV = 'production'
    }

    // Stage-level options
    options {
        timeout(time: 10, unit: 'MINUTES')
        retry(3)
    }

    // Stage-level condition
    when {
        branch 'main'
    }

    // The actual steps
    steps {
        sh './deploy.sh ${DEPLOY_ENV}'
    }

    // Stage-level post
    post {
        success {
            echo "Deployed to ${DEPLOY_ENV}"
        }
    }
}
```

### Parallel stages

```groovy
stage('Test in Parallel') {
    parallel {
        stage('Unit Tests') {
            steps { sh 'pytest tests/unit/' }
        }
        stage('Integration Tests') {
            steps { sh 'pytest tests/integration/' }
            agent { label 'integration-agent' }
        }
        stage('E2E Tests') {
            steps { sh 'cypress run' }
        }
    }
}
```

### Sequential stages (within a stage)

```groovy
stage('Deploy Pipeline') {
    stages {
        stage('Deploy Staging') {
            steps { sh './deploy.sh staging' }
        }
        stage('Smoke Test') {
            steps { sh './smoke-test.sh staging' }
        }
        stage('Deploy Production') {
            steps { sh './deploy.sh production' }
            input {
                message "Deploy to production?"
                ok "Yes, deploy"
                submitter "ops-team"
            }
        }
    }
}
```

---

## 4. Post Conditions

`post` runs after stages complete. Can be at pipeline level or stage level.

```groovy
post {
    always {
        // Always runs — for cleanup, publishing results
        junit 'results/**/*.xml'
        cleanWs()
    }
    success {
        // Only on SUCCESS
        archiveArtifacts 'dist/**/*'
        slackSend color: 'good', message: "✅ ${JOB_NAME} #${BUILD_NUMBER} succeeded"
    }
    failure {
        // Only on FAILURE
        slackSend color: 'danger', message: "❌ ${JOB_NAME} #${BUILD_NUMBER} failed"
        emailext(
            to: 'team@example.com',
            subject: "Build Failed: ${JOB_NAME} #${BUILD_NUMBER}",
            body: "See: ${BUILD_URL}"
        )
    }
    unstable {
        // Tests failed but build continued
        slackSend color: 'warning', message: "⚠️ ${JOB_NAME} #${BUILD_NUMBER} unstable"
    }
    aborted {
        echo "Build was aborted"
    }
    changed {
        // Only when result changed from previous build
        // (success after failure, or failure after success)
        echo "Build result changed!"
    }
    fixed {
        // Was failing, now succeeds
        slackSend color: 'good', message: "✅ ${JOB_NAME} is back to normal"
    }
    regression {
        // Was passing, now fails
        slackSend color: 'danger', message: "🔴 ${JOB_NAME} regression detected"
    }
    cleanup {
        // Always runs LAST (after all other post conditions)
        echo "Cleanup complete"
    }
}
```

---

## 5. Environment & Parameters

### Environment variables

```groovy
environment {
    // Static values
    APP_NAME = 'my-service'
    REGISTRY = 'registry.example.com'

    // Credential binding — safely injects secrets
    DOCKER_CREDENTIALS  = credentials('docker-registry-credentials')
    // Creates: DOCKER_CREDENTIALS_USR, DOCKER_CREDENTIALS_PSW

    AWS_ACCESS_KEY_ID     = credentials('aws-access-key')
    AWS_SECRET_ACCESS_KEY = credentials('aws-secret-key')

    // Computed (using Groovy GString)
    IMAGE_TAG = "${REGISTRY}/${APP_NAME}:${BUILD_NUMBER}"
    DEPLOY_TAG = "${GIT_COMMIT.take(8)}"
}
```

### Parameters

```groovy
parameters {
    // Text input
    string(
        name: 'BRANCH',
        defaultValue: 'main',
        description: 'Branch to deploy'
    )

    // Dropdown
    choice(
        name: 'ENVIRONMENT',
        choices: ['development', 'staging', 'production'],
        description: 'Target deployment environment'
    )

    // Checkbox
    booleanParam(
        name: 'RUN_TESTS',
        defaultValue: true,
        description: 'Run test suite'
    )

    // Password (masked)
    password(
        name: 'DEPLOY_TOKEN',
        description: 'Deployment authorization token'
    )

    // Multi-line text
    text(
        name: 'NOTES',
        defaultValue: '',
        description: 'Release notes'
    )
}

// Access parameters
stage('Deploy') {
    when {
        expression { params.ENVIRONMENT != 'production' || params.DEPLOY_TOKEN != '' }
    }
    steps {
        echo "Deploying to: ${params.ENVIRONMENT}"
        sh "./deploy.sh ${params.ENVIRONMENT}"
    }
}
```

---

## 6. Options

```groovy
options {
    // Timeout for entire pipeline
    timeout(time: 2, unit: 'HOURS')     // SECONDS, MINUTES, HOURS, DAYS

    // Only keep N builds in history
    buildDiscarder(logRotator(
        numToKeepStr: '10',              // keep 10 builds
        artifactNumToKeepStr: '5'        // keep artifacts for 5 builds
    ))

    // Prevent multiple builds running simultaneously
    disableConcurrentBuilds()
    disableConcurrentBuilds(abortPrevious: true)  // abort older if new starts

    // Retry whole pipeline on failure
    retry(3)

    // Skip default checkout (do it manually in steps)
    skipDefaultCheckout()

    // Timestamps in console output (Timestamper plugin)
    timestamps()

    // ANSI color in console (AnsiColor plugin)
    ansiColor('xterm')

    // Don't fail build if no stages ran
    skipStagesAfterUnstable()

    // Quiet period (wait N seconds after trigger before building)
    quietPeriod(30)

    // Checkout options
    checkoutToSubdirectory('src')
    newContainerPerStage()   // Docker agent: new container per stage
}
```

---

## 7. When Directives (Conditions)

Control whether a stage runs.

```groovy
stage('Deploy Production') {
    when {
        // Single condition
        branch 'main'

        // Multiple conditions (AND by default)
        allOf {
            branch 'main'
            not { changeRequest() }           // not a PR
        }

        // OR conditions
        anyOf {
            branch 'main'
            branch 'release/*'
        }
    }
    steps { sh './deploy.sh production' }
}

// Common when conditions:
when { branch 'main' }                           // branch name matches
when { branch pattern: 'release/.*', comparator: 'REGEXP' }  // regex
when { tag 'v*' }                                // tag matches glob
when { tag pattern: '^v\\d+\\.\\d+\\.\\d+$', comparator: 'REGEXP' }
when { environment name: 'DEPLOY_ENV', value: 'production' }
when { expression { return params.DEPLOY == true } }   // Groovy expression
when { changeRequest() }                         // is a pull/merge request
when { not { branch 'main' } }                  // NOT main
when { buildingTag() }                           // is building a tag
when { triggeredBy 'UserIdCause' }              // triggered by user (not scheduled)

// beforeAgent: true — evaluate when BEFORE allocating agent (saves resources)
stage('Optional Deploy') {
    when {
        beforeAgent true
        branch 'main'
    }
    agent { label 'deploy' }
    steps { sh './deploy.sh' }
}
```

---

## 8. Common Steps Reference

### Shell / batch

```groovy
// Shell (Linux/Mac)
sh 'echo hello'
sh './scripts/build.sh'
sh '''
    set -euo pipefail
    echo "Building..."
    make build
    echo "Done"
'''

// Capture output
def version = sh(script: 'git describe --tags', returnStdout: true).trim()
def exitCode = sh(script: 'test -f file.txt', returnStatus: true)

// Windows batch
bat 'dir'
bat 'mvn clean package'
```

### File operations

```groovy
// Write file
writeFile file: 'config.json', text: '{"key": "value"}'

// Read file
def content = readFile 'config.json'

// Read properties file
def props = readProperties file: 'build.properties'
echo props['version']

// Copy file
sh 'cp src/config.yml dist/'

// Check if file exists
if (fileExists('target/app.jar')) {
    echo "JAR exists"
}

// Delete directory
deleteDir()   // delete current workspace
dir('target') { deleteDir() }
```

### Source control

```groovy
// Checkout (usually done automatically with Multibranch)
checkout scm   // use job's configured SCM

// Checkout specific branch
checkout([
    $class: 'GitSCM',
    branches: [[name: '*/main']],
    userRemoteConfigs: [[url: 'https://github.com/myorg/myrepo.git',
                         credentialsId: 'github-token']]
])

// Get current commit
def commit = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
```

### Input (manual approval)

```groovy
// Simple approval
input 'Deploy to production?'

// With options
def approval = input(
    message: 'Deploy to production?',
    ok: 'Yes, deploy!',
    submitter: 'ops-team,admin',        // restrict who can approve
    parameters: [
        choice(name: 'REGION', choices: ['eu-central-1', 'us-east-1'])
    ]
)
echo "Approved by: ${approval}"

// Timeout on input (auto-abort if not approved in time)
timeout(time: 30, unit: 'MINUTES') {
    input 'Ready to deploy?'
}
```

### Credentials

```groovy
// Username/password
withCredentials([usernamePassword(
    credentialsId: 'my-credentials',
    usernameVariable: 'USERNAME',
    passwordVariable: 'PASSWORD'
)]) {
    sh 'docker login -u $USERNAME -p $PASSWORD registry.example.com'
}

// Secret text
withCredentials([string(credentialsId: 'api-token', variable: 'API_TOKEN')]) {
    sh 'curl -H "Authorization: Bearer $API_TOKEN" https://api.example.com'
}

// SSH key
withCredentials([sshUserPrivateKey(
    credentialsId: 'deploy-key',
    keyFileVariable: 'SSH_KEY',
    usernameVariable: 'SSH_USER'
)]) {
    sh 'ssh -i $SSH_KEY $SSH_USER@server.example.com "deploy.sh"'
}

// File credential
withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG_FILE')]) {
    sh 'kubectl --kubeconfig=$KUBECONFIG_FILE get pods'
}
```

---

## 9. Complete Real-World Jenkinsfile

```groovy
// Complete Jenkinsfile for a Python/Docker application

pipeline {
    agent none    // No global agent — specify per stage

    options {
        timeout(time: 1, unit: 'HOURS')
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds(abortPrevious: true)
        timestamps()
        ansiColor('xterm')
    }

    environment {
        REGISTRY     = 'registry.example.com'
        APP_NAME     = 'my-app'
        IMAGE_TAG    = "${REGISTRY}/${APP_NAME}:${GIT_COMMIT.take(8)}"
        IMAGE_LATEST = "${REGISTRY}/${APP_NAME}:latest"
        DOCKER_CREDS = credentials('registry-credentials')
    }

    parameters {
        choice(name: 'DEPLOY_ENV', choices: ['staging', 'production'], description: 'Target environment')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip tests')
    }

    stages {
        // ── Lint ───────────────────────────────────────────────
        stage('Lint') {
            agent { label 'python && docker' }
            steps {
                sh '''
                    pip install ruff mypy --quiet
                    ruff check .
                    mypy app/
                '''
            }
        }

        // ── Test ───────────────────────────────────────────────
        stage('Test') {
            when { not { expression { params.SKIP_TESTS } } }
            agent {
                docker {
                    image 'python:3.11-slim'
                    args '--network test-network'
                }
            }
            steps {
                sh '''
                    pip install -r requirements.txt -q
                    pytest tests/ \
                        --junitxml=test-results.xml \
                        --cov=app \
                        --cov-report=xml:coverage.xml
                '''
            }
            post {
                always {
                    junit 'test-results.xml'
                    recordCoverage(
                        tools: [[parser: 'COBERTURA', pattern: 'coverage.xml']]
                    )
                }
            }
        }

        // ── Build ──────────────────────────────────────────────
        stage('Build Image') {
            agent { label 'docker' }
            steps {
                sh '''
                    docker login -u $DOCKER_CREDS_USR -p $DOCKER_CREDS_PSW $REGISTRY
                    docker build \
                        --cache-from $IMAGE_LATEST \
                        --build-arg BUILDKIT_INLINE_CACHE=1 \
                        --build-arg VERSION=${GIT_COMMIT.take(8)} \
                        -t $IMAGE_TAG \
                        -t $IMAGE_LATEST \
                        .
                    docker push $IMAGE_TAG
                    docker push $IMAGE_LATEST
                '''
            }
        }

        // ── Deploy Staging ─────────────────────────────────────
        stage('Deploy Staging') {
            when {
                anyOf {
                    branch 'main'
                    expression { params.DEPLOY_ENV == 'staging' }
                }
            }
            agent { label 'deploy' }
            environment {
                KUBECONFIG = credentials('kubeconfig-staging')
            }
            steps {
                sh '''
                    helm upgrade --install ${APP_NAME} ./helm/${APP_NAME} \
                        --namespace staging \
                        --set image.tag=${GIT_COMMIT.take(8)} \
                        --values helm/${APP_NAME}/values-staging.yaml \
                        --atomic \
                        --timeout 5m
                '''
            }
            post {
                success {
                    slackSend(
                        channel: '#deployments',
                        color: 'good',
                        message: "✅ ${APP_NAME} deployed to staging (${GIT_COMMIT.take(8)})"
                    )
                }
            }
        }

        // ── Deploy Production ──────────────────────────────────
        stage('Deploy Production') {
            when {
                allOf {
                    branch 'main'
                    expression { params.DEPLOY_ENV == 'production' }
                }
            }
            agent { label 'deploy' }
            environment {
                KUBECONFIG = credentials('kubeconfig-production')
            }
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: "Deploy ${APP_NAME} ${GIT_COMMIT.take(8)} to PRODUCTION?",
                          ok: 'Deploy',
                          submitter: 'ops-team'
                }
                sh '''
                    helm upgrade --install ${APP_NAME} ./helm/${APP_NAME} \
                        --namespace production \
                        --set image.tag=${GIT_COMMIT.take(8)} \
                        --values helm/${APP_NAME}/values-production.yaml \
                        --atomic \
                        --timeout 10m
                '''
            }
        }
    }

    post {
        always {
            node('linux') {
                cleanWs()
            }
        }
        failure {
            slackSend(
                channel: '#ci-alerts',
                color: 'danger',
                message: "❌ ${JOB_NAME} #${BUILD_NUMBER} FAILED\n${BUILD_URL}"
            )
        }
        fixed {
            slackSend(
                channel: '#ci-alerts',
                color: 'good',
                message: "✅ ${JOB_NAME} is back to normal"
            )
        }
    }
}
```

---

## Cheatsheet

```groovy
// Agent types
agent any
agent none
agent { label 'linux && docker' }
agent { docker { image 'python:3.11' } }
agent { kubernetes { yaml '''...''' } }

// Common steps
sh 'command'
sh(script: 'cmd', returnStdout: true).trim()
sh(script: 'cmd', returnStatus: true)
bat 'windows-command'
echo 'message'
input 'Approve?'
timeout(time: 10, unit: 'MINUTES') { ... }
retry(3) { ... }
sleep(time: 30, unit: 'SECONDS')
error 'Forced failure message'
unstable 'Mark as unstable'

// Files
writeFile file: 'out.txt', text: 'content'
readFile 'in.txt'
archiveArtifacts 'dist/**/*'
stash name: 'build', includes: 'target/*.jar'
unstash 'build'

// When
when { branch 'main' }
when { tag 'v*' }
when { expression { return env.BRANCH_NAME == 'main' } }
when { changeRequest() }
when { not { branch 'main' } }
```

---

*Next: [Shared Libraries →](./03-shared-libraries.md)*
