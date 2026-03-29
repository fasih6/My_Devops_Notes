# 🔄 Pipeline Patterns

Parallel execution, matrix builds, error handling, retries, notifications, and real-world patterns.

---

## 📚 Table of Contents

- [1. Parallel Execution](#1-parallel-execution)
- [2. Matrix Builds](#2-matrix-builds)
- [3. Error Handling & Recovery](#3-error-handling--recovery)
- [4. Retry Logic](#4-retry-logic)
- [5. Notifications](#5-notifications)
- [6. Build Parameters Patterns](#6-build-parameters-patterns)
- [7. Pipeline Optimization](#7-pipeline-optimization)
- [8. Common Patterns Library](#8-common-patterns-library)
- [Cheatsheet](#cheatsheet)

---

## 1. Parallel Execution

### Parallel stages

```groovy
stage('Test Suite') {
    parallel {
        stage('Unit Tests') {
            agent { docker { image 'python:3.11' } }
            steps {
                sh 'pytest tests/unit/ --junitxml=unit-results.xml'
            }
            post {
                always { junit 'unit-results.xml' }
            }
        }

        stage('Integration Tests') {
            agent { label 'integration' }
            steps {
                sh 'pytest tests/integration/ --junitxml=integration-results.xml'
            }
            post {
                always { junit 'integration-results.xml' }
            }
        }

        stage('E2E Tests') {
            agent { docker { image 'cypress/included:13' } }
            steps {
                sh 'cypress run --reporter junit --reporter-options "mochaFile=e2e-results.xml"'
            }
            post {
                always {
                    junit 'e2e-results.xml'
                    publishHTML target: [
                        reportDir: 'cypress/reports',
                        reportFiles: 'index.html',
                        reportName: 'Cypress Report'
                    ]
                }
            }
        }
    }
}
```

### Parallel with failFast

```groovy
stage('Parallel Tests') {
    failFast true    // if any parallel branch fails, cancel all others
    parallel {
        stage('Branch A') {
            steps { sh './test-a.sh' }
        }
        stage('Branch B') {
            steps { sh './test-b.sh' }
        }
    }
}
```

### Dynamic parallel stages (programmatic)

```groovy
stage('Test All Services') {
    steps {
        script {
            def services = ['api', 'worker', 'scheduler', 'notifier']

            def parallelStages = services.collectEntries { service ->
                ["Test ${service}": {
                    stage("Test ${service}") {
                        agent { label 'docker' }
                        sh "cd services/${service} && pytest"
                    }
                }]
            }

            parallel parallelStages
        }
    }
}
```

---

## 2. Matrix Builds

Test across multiple combinations (OS, language versions, etc.).

### axis in declarative pipeline

```groovy
pipeline {
    agent none
    stages {
        stage('Test Matrix') {
            matrix {
                axes {
                    axis {
                        name 'PYTHON_VERSION'
                        values '3.9', '3.10', '3.11', '3.12'
                    }
                    axis {
                        name 'OS'
                        values 'linux', 'macos'
                    }
                }
                // Exclude specific combinations
                excludes {
                    exclude {
                        axis {
                            name 'OS'
                            values 'macos'
                        }
                        axis {
                            name 'PYTHON_VERSION'
                            values '3.9'
                        }
                    }
                }
                agent {
                    docker {
                        image "python:${PYTHON_VERSION}-slim"
                        label "${OS}"
                    }
                }
                stages {
                    stage('Test') {
                        steps {
                            sh 'python --version'
                            sh 'pip install pytest && pytest tests/'
                        }
                        post {
                            always {
                                junit 'test-results*.xml'
                            }
                        }
                    }
                }
            }
        }
    }
}
```

### Manual matrix with loops

```groovy
stage('Multi-Region Deploy') {
    steps {
        script {
            def regions = ['eu-central-1', 'us-east-1', 'ap-southeast-1']

            def deployStages = regions.collectEntries { region ->
                ["Deploy ${region}": {
                    withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                        credentialsId: "aws-${region}"]]) {
                        sh """
                            AWS_DEFAULT_REGION=${region} \
                            helm upgrade --install my-app ./helm/my-app \
                                --set image.tag=${env.GIT_COMMIT.take(8)}
                        """
                    }
                }]
            }

            parallel deployStages
        }
    }
}
```

---

## 3. Error Handling & Recovery

### try/catch in script blocks

```groovy
stage('Deploy') {
    steps {
        script {
            try {
                sh 'helm upgrade --install my-app ./helm/my-app --atomic --timeout 5m'
            } catch (Exception e) {
                echo "Deployment failed: ${e.message}"

                // Attempt rollback
                sh 'helm rollback my-app --wait || true'

                // Re-throw to fail the build
                throw e
            }
        }
    }
}
```

### catchError — continue pipeline after failure

```groovy
stage('Optional Security Scan') {
    steps {
        catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
            sh 'trivy image --exit-code 1 --severity HIGH my-app:latest'
        }
    }
}
// Pipeline continues even if trivy finds vulnerabilities
// Build is marked UNSTABLE but not FAILED
```

### warnError — mark as unstable with warning

```groovy
stage('Performance Tests') {
    steps {
        warnError('Performance tests failed — marking UNSTABLE') {
            sh 'k6 run --vus 50 --duration 30s load-test.js'
        }
    }
}
```

### Combining error handlers

```groovy
pipeline {
    agent any
    stages {
        stage('Test') {
            steps {
                catchError(buildResult: 'UNSTABLE', stageResult: 'UNSTABLE') {
                    sh 'pytest tests/ --junitxml=results.xml'
                }
            }
        }

        stage('Security') {
            steps {
                // Don't fail pipeline on security issues — just warn
                catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
                    sh 'semgrep --error src/'
                }
            }
        }

        stage('Deploy') {
            when {
                // Only deploy if tests passed (not unstable)
                expression { currentBuild.resultIsBetterOrEqualTo('SUCCESS') }
            }
            steps {
                sh './deploy.sh'
            }
        }
    }
}
```

### Timeout protection

```groovy
stage('Deploy') {
    steps {
        timeout(time: 10, unit: 'MINUTES') {
            sh 'helm upgrade --install my-app ./helm --atomic'
        }
    }
}

// Timeout with retry
stage('Flaky External Test') {
    steps {
        timeout(time: 5, unit: 'MINUTES') {
            retry(3) {
                sh './test-external-api.sh'
            }
        }
    }
}
```

---

## 4. Retry Logic

```groovy
// Simple retry
retry(3) {
    sh './unstable-command.sh'
}

// Retry with delay (using sleep)
script {
    def maxRetries = 3
    def retryCount = 0
    def success = false

    while (!success && retryCount < maxRetries) {
        try {
            sh './deploy.sh'
            success = true
        } catch (e) {
            retryCount++
            if (retryCount >= maxRetries) throw e
            echo "Attempt ${retryCount} failed, retrying in 30s..."
            sleep(time: 30, unit: 'SECONDS')
        }
    }
}

// waitUntil — wait for condition
waitUntil {
    def status = sh(
        script: 'curl -s -o /dev/null -w "%{http_code}" https://staging.example.com/health',
        returnStdout: true
    ).trim()
    return status == '200'
}
```

---

## 5. Notifications

### Slack

```groovy
// Basic notification
slackSend(
    channel: '#deployments',
    color: 'good',                    // good (green), warning, danger (red), or hex
    message: "✅ ${env.JOB_NAME} #${env.BUILD_NUMBER} deployed successfully"
)

// Rich notification with blocks
slackSend(
    channel: '#deployments',
    color: currentBuild.result == 'SUCCESS' ? 'good' : 'danger',
    blocks: """[
        {
            "type": "section",
            "text": {
                "type": "mrkdwn",
                "text": "*${currentBuild.result == 'SUCCESS' ? '✅' : '❌'} ${env.JOB_NAME}*"
            }
        },
        {
            "type": "section",
            "fields": [
                {"type": "mrkdwn", "text": "*Build:* #${env.BUILD_NUMBER}"},
                {"type": "mrkdwn", "text": "*Branch:* ${env.BRANCH_NAME}"},
                {"type": "mrkdwn", "text": "*Duration:* ${currentBuild.durationString}"},
                {"type": "mrkdwn", "text": "*Author:* ${env.GIT_AUTHOR_NAME}"}
            ]
        },
        {
            "type": "actions",
            "elements": [
                {
                    "type": "button",
                    "text": {"type": "plain_text", "text": "View Build"},
                    "url": "${env.BUILD_URL}"
                }
            ]
        }
    ]"""
)
```

### Email

```groovy
// Simple email
mail(
    to: 'team@example.com',
    subject: "Build ${env.BUILD_NUMBER} ${currentBuild.result}",
    body: "See: ${env.BUILD_URL}"
)

// Rich email (emailext plugin)
emailext(
    to: 'team@example.com',
    subject: "Build ${env.BUILD_NUMBER}: ${currentBuild.result}",
    body: '''${SCRIPT, template="groovy-html.template"}''',
    recipientProviders: [
        [$class: 'DevelopersRecipientProvider'],   // people who committed
        [$class: 'RequesterRecipientProvider']     // person who triggered
    ],
    attachLog: true,
    compressLog: true
)
```

### Notification helper function (shared library pattern)

```groovy
// vars/notify.groovy
def success(String message = '') {
    def msg = message ?: "✅ ${env.JOB_NAME} #${env.BUILD_NUMBER} succeeded"
    slackSend channel: '#ci', color: 'good', message: msg
}

def failure(String message = '') {
    def msg = message ?: "❌ ${env.JOB_NAME} #${env.BUILD_NUMBER} FAILED\n${env.BUILD_URL}"
    slackSend channel: '#ci', color: 'danger', message: msg
}

def changed() {
    def status = currentBuild.result == 'SUCCESS' ? '✅ Fixed' : '🔴 Broken'
    slackSend channel: '#ci', color: currentBuild.result == 'SUCCESS' ? 'good' : 'danger',
        message: "${status}: ${env.JOB_NAME} #${env.BUILD_NUMBER}"
}

// In Jenkinsfile:
post {
    success { notify.success() }
    failure { notify.failure() }
    changed { notify.changed() }
}
```

---

## 6. Build Parameters Patterns

### Conditional deployment with parameters

```groovy
parameters {
    choice(name: 'ENVIRONMENT', choices: ['staging', 'production'])
    booleanParam(name: 'FORCE_DEPLOY', defaultValue: false)
    string(name: 'VERSION', defaultValue: '', description: 'Override version')
}

stages {
    stage('Deploy') {
        when {
            anyOf {
                expression { params.FORCE_DEPLOY }
                branch 'main'
            }
        }
        steps {
            script {
                def version = params.VERSION ?: env.GIT_COMMIT.take(8)
                sh "./deploy.sh ${params.ENVIRONMENT} ${version}"
            }
        }
    }
}
```

### Input with parameters (runtime approval)

```groovy
stage('Approve Production') {
    when { branch 'main' }
    steps {
        script {
            def approval = input(
                message: "Deploy to production?",
                parameters: [
                    choice(name: 'ACTION', choices: ['deploy', 'abort']),
                    string(name: 'REASON', description: 'Reason for deployment')
                ],
                submitter: 'ops-team',
                submitterParameter: 'APPROVED_BY'
            )

            if (approval.ACTION != 'deploy') {
                error "Deployment aborted"
            }

            echo "Approved by: ${approval.APPROVED_BY}"
            echo "Reason: ${approval.REASON}"
        }
    }
}
```

---

## 7. Pipeline Optimization

### Skip stages based on git changes

```groovy
stage('Frontend Tests') {
    when {
        changeset 'frontend/**'   // only run if frontend files changed
    }
    steps {
        sh 'cd frontend && npm test'
    }
}

stage('Backend Tests') {
    when {
        changeset 'backend/**'
    }
    steps {
        sh 'cd backend && pytest'
    }
}
```

### Conditional stash/unstash

```groovy
stage('Build') {
    steps {
        sh 'go build -o bin/app ./...'
        stash name: 'binary', includes: 'bin/**'
    }
}

stage('Test') {
    parallel {
        stage('Unit') {
            steps {
                unstash 'binary'
                sh './bin/app test --unit'
            }
        }
        stage('Integration') {
            steps {
                unstash 'binary'
                sh './bin/app test --integration'
            }
        }
    }
}
```

---

## 8. Common Patterns Library

### Promotion pipeline (stage gates)

```groovy
// Build once, promote through environments
pipeline {
    agent none

    environment {
        IMAGE_TAG = "${GIT_COMMIT.take(8)}"
        IMAGE     = "registry.example.com/my-app:${IMAGE_TAG}"
    }

    stages {
        stage('Build & Test') {
            agent { label 'docker' }
            steps {
                sh 'docker build -t $IMAGE .'
                sh 'docker run $IMAGE pytest tests/'
                sh 'docker push $IMAGE'
            }
        }

        stage('→ Staging') {
            agent { label 'deploy' }
            steps {
                sh 'helm upgrade --install my-app ./helm --set image.tag=$IMAGE_TAG --namespace staging --atomic'
            }
            post {
                success {
                    slackSend channel: '#deployments', color: 'good',
                        message: "Deployed ${IMAGE_TAG} to staging"
                }
            }
        }

        stage('Staging Acceptance') {
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: "Staging looks good? Promote to production?",
                          submitter: 'tech-leads'
                }
            }
        }

        stage('→ Production') {
            agent { label 'deploy' }
            steps {
                sh 'helm upgrade --install my-app ./helm --set image.tag=$IMAGE_TAG --namespace production --atomic'
            }
            post {
                success {
                    slackSend channel: '#deployments', color: 'good',
                        message: "🚀 ${IMAGE_TAG} deployed to PRODUCTION"
                }
            }
        }
    }
}
```

---

## Cheatsheet

```groovy
// Parallel stages
stage('Parallel') {
    failFast true
    parallel {
        stage('A') { steps { sh './a.sh' } }
        stage('B') { steps { sh './b.sh' } }
    }
}

// Error handling
catchError(buildResult: 'UNSTABLE', stageResult: 'FAILURE') {
    sh './possibly-failing.sh'
}

// Retry with timeout
timeout(time: 5, unit: 'MINUTES') {
    retry(3) { sh './flaky.sh' }
}

// When conditions
when { branch 'main' }
when { changeset 'src/**' }
when { expression { params.DEPLOY == 'true' } }
when { expression { currentBuild.resultIsBetterOrEqualTo('SUCCESS') } }
when { not { branch 'main' } }
when { allOf { branch 'main'; not { changeRequest() } } }

// Notifications
post {
    success { slackSend color: 'good', message: "✅ ${JOB_NAME} passed" }
    failure { slackSend color: 'danger', message: "❌ ${JOB_NAME} failed\n${BUILD_URL}" }
    unstable { slackSend color: 'warning', message: "⚠️ ${JOB_NAME} unstable" }
    fixed { slackSend color: 'good', message: "✅ ${JOB_NAME} fixed" }
}
```

---

*Next: [Docker & Container Builds →](./07-docker-container-builds.md)*
