# 🐳 Docker & Container Builds

Building Docker images in Jenkins — Docker Pipeline plugin, registry management, and caching.

---

## 📚 Table of Contents

- [1. Docker Pipeline Plugin](#1-docker-pipeline-plugin)
- [2. Building Images](#2-building-images)
- [3. Registry Authentication](#3-registry-authentication)
- [4. Build Caching](#4-build-caching)
- [5. Multi-Stage & Multi-Platform Builds](#5-multi-stage--multi-platform-builds)
- [6. Image Scanning in Jenkins](#6-image-scanning-in-jenkins)
- [7. Docker Compose in CI](#7-docker-compose-in-ci)
- [8. Complete Docker Pipeline](#8-complete-docker-pipeline)
- [Cheatsheet](#cheatsheet)

---

## 1. Docker Pipeline Plugin

The **Docker Pipeline plugin** provides the `docker` global variable for working with Docker images in pipelines.

```groovy
// Core Docker Pipeline methods
docker.build(...)        // build an image
docker.image(...)        // reference an existing image
docker.withRegistry(...) // authenticate and push
docker.withServer(...)   // use remote Docker daemon
```

---

## 2. Building Images

### Basic build and push

```groovy
pipeline {
    agent any
    environment {
        REGISTRY = 'registry.example.com'
        IMAGE    = "${REGISTRY}/my-app:${GIT_COMMIT.take(8)}"
    }
    stages {
        stage('Build') {
            steps {
                script {
                    def img = docker.build("${IMAGE}")
                }
            }
        }

        stage('Push') {
            steps {
                script {
                    docker.withRegistry("https://${REGISTRY}", 'registry-credentials') {
                        def img = docker.image("${IMAGE}")
                        img.push()
                        img.push('latest')   // also tag as latest
                    }
                }
            }
        }
    }
}
```

### docker.build() options

```groovy
// Build with custom Dockerfile
def img = docker.build('my-app:latest', '-f Dockerfile.prod .')

// Build with build args
def img = docker.build('my-app:latest',
    "--build-arg VERSION=${VERSION} " +
    "--build-arg BUILD_DATE=${BUILD_DATE} " +
    ".")

// Build from a subdirectory
def img = docker.build('my-app:latest', './docker/app')

// Build with cache-from
def img = docker.build('my-app:latest',
    "--cache-from registry.example.com/my-app:latest " +
    "--build-arg BUILDKIT_INLINE_CACHE=1 " +
    ".")
```

### Using docker.image() to run commands

```groovy
// Run a command inside a Docker image (one-off)
docker.image('python:3.11-slim').inside {
    sh 'python --version'
    sh 'pip install pytest && pytest'
}

// With args
docker.image('postgres:15').inside('-e POSTGRES_PASSWORD=test') {
    sh 'psql -h localhost -U postgres -c "SELECT 1"'
}
```

---

## 3. Registry Authentication

### docker.withRegistry()

```groovy
// Docker Hub
docker.withRegistry('https://registry.hub.docker.com', 'dockerhub-credentials') {
    docker.build('myuser/my-app:latest').push()
}

// AWS ECR
def ecrLogin = sh(
    script: 'aws ecr get-login-password --region eu-central-1',
    returnStdout: true
).trim()

docker.withRegistry(
    'https://123456789.dkr.ecr.eu-central-1.amazonaws.com',
    ecr:eu-central-1:aws-credentials'   // ecr: prefix uses ECR credential type
) {
    docker.build("123456789.dkr.ecr.eu-central-1.amazonaws.com/my-app:${GIT_COMMIT.take(8)}").push()
}

// GitLab Container Registry
docker.withRegistry(
    'https://registry.gitlab.com',
    'gitlab-registry-credentials'
) {
    docker.build("registry.gitlab.com/mygroup/my-project:${GIT_COMMIT.take(8)}").push()
}

// Private registry with custom CA
docker.withRegistry(
    'https://registry.example.com',
    'registry-credentials'
) {
    docker.build('registry.example.com/my-app:latest').push()
}
```

### Credential types for registries

```groovy
// Username/Password (most common)
credentials('registry-credentials')

// AWS ECR (uses AWS credentials to get ECR login)
'ecr:eu-central-1:aws-credentials'

// Google Container Registry
'gcr:my-gcp-project:gcp-service-account-key'
```

---

## 4. Build Caching

### Registry-based caching (works across agents)

```groovy
stage('Build with Cache') {
    steps {
        script {
            def registryImage = "registry.example.com/my-app"
            def cacheTag = "buildcache"

            // Pull cache layer
            sh "docker pull ${registryImage}:${cacheTag} || true"

            // Build using cache
            docker.withRegistry('https://registry.example.com', 'registry-credentials') {
                def img = docker.build(
                    "${registryImage}:${GIT_COMMIT.take(8)}",
                    "--cache-from ${registryImage}:${cacheTag} " +
                    "--build-arg BUILDKIT_INLINE_CACHE=1 " +
                    "."
                )
                img.push()

                // Update cache tag
                img.push(cacheTag)
            }
        }
    }
}
```

### BuildKit cache mounts

```groovy
// Enable BuildKit
withEnv(['DOCKER_BUILDKIT=1']) {
    sh '''
        docker build \
            --secret id=github_token,env=GITHUB_TOKEN \
            --build-arg BUILDKIT_INLINE_CACHE=1 \
            --cache-from registry.example.com/my-app:cache \
            --cache-to type=registry,ref=registry.example.com/my-app:cache,mode=max \
            -t registry.example.com/my-app:${GIT_COMMIT:0:8} \
            .
    '''
}
```

### Local volume cache (single agent)

```groovy
// Mount cache directories via Docker volume
docker.image('python:3.11-slim').inside(
    '-v pip-cache:/root/.cache/pip'   // persistent volume on the agent
) {
    sh 'pip install -r requirements.txt'
    sh 'pytest'
}
```

---

## 5. Multi-Stage & Multi-Platform Builds

### Multi-stage builds

```groovy
stage('Build Multi-Stage') {
    steps {
        script {
            // Build only the builder stage (for testing)
            def builderImg = docker.build('my-app:builder', '--target builder .')
            builderImg.inside {
                sh 'go test ./...'
            }

            // Build the final production image
            def prodImg = docker.build("registry.example.com/my-app:${GIT_COMMIT.take(8)}", '.')

            docker.withRegistry('https://registry.example.com', 'registry-credentials') {
                prodImg.push()
            }
        }
    }
}
```

### Multi-platform builds (buildx)

```groovy
stage('Multi-Platform Build') {
    steps {
        withEnv(['DOCKER_BUILDKIT=1']) {
            withCredentials([usernamePassword(
                credentialsId: 'registry-credentials',
                usernameVariable: 'REG_USER',
                passwordVariable: 'REG_PASS'
            )]) {
                sh '''
                    # Setup buildx
                    docker run --privileged --rm tonistiigi/binfmt --install all
                    docker buildx create --name multiplatform --use || true
                    docker buildx inspect --bootstrap

                    # Login
                    docker login -u $REG_USER -p $REG_PASS registry.example.com

                    # Build and push multi-platform
                    docker buildx build \
                        --platform linux/amd64,linux/arm64 \
                        --cache-from type=registry,ref=registry.example.com/my-app:cache \
                        --cache-to type=registry,ref=registry.example.com/my-app:cache,mode=max \
                        -t registry.example.com/my-app:${GIT_COMMIT:0:8} \
                        -t registry.example.com/my-app:latest \
                        --push \
                        .
                '''
            }
        }
    }
}
```

---

## 6. Image Scanning in Jenkins

### Trivy security scan

```groovy
stage('Security Scan') {
    agent {
        docker {
            image 'aquasec/trivy:latest'
            args '--entrypoint=""'
        }
    }
    steps {
        sh """
            trivy image \
                --exit-code 1 \
                --severity HIGH,CRITICAL \
                --format table \
                --no-progress \
                registry.example.com/my-app:${GIT_COMMIT.take(8)}
        """
    }
    post {
        always {
            sh """
                trivy image \
                    --format json \
                    --output trivy-report.json \
                    registry.example.com/my-app:${GIT_COMMIT.take(8)} || true
            """
            archiveArtifacts 'trivy-report.json'
        }
    }
}
```

### Trivy scan as shared library function

```groovy
// vars/trivyScan.groovy
def call(Map config = [:]) {
    def image = config.image ?: error('image is required')
    def severity = config.severity ?: 'HIGH,CRITICAL'
    def exitCode = config.exitCode != null ? config.exitCode : 1

    docker.image('aquasec/trivy:latest').inside('--entrypoint=""') {
        sh """
            trivy image \
                --exit-code ${exitCode} \
                --severity ${severity} \
                --no-progress \
                ${image}
        """
    }
}
```

---

## 7. Docker Compose in CI

```groovy
stage('Integration Tests') {
    steps {
        sh '''
            # Start all services
            docker compose -f docker-compose.test.yml up -d

            # Wait for services to be ready
            timeout 60 bash -c 'until curl -sf http://localhost:8080/health; do sleep 2; done'

            # Run tests
            docker compose -f docker-compose.test.yml \
                run --rm test pytest tests/integration/
        '''
    }
    post {
        always {
            sh 'docker compose -f docker-compose.test.yml down -v || true'
        }
    }
}
```

---

## 8. Complete Docker Pipeline

```groovy
// Complete Docker build, test, scan, and push pipeline

pipeline {
    agent none

    options {
        timeout(time: 30, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20'))
        disableConcurrentBuilds(abortPrevious: true)
    }

    environment {
        REGISTRY    = 'registry.example.com'
        APP_NAME    = 'my-app'
        IMAGE_TAG   = "${GIT_COMMIT.take(8)}"
        IMAGE       = "${REGISTRY}/${APP_NAME}:${IMAGE_TAG}"
        IMAGE_CACHE = "${REGISTRY}/${APP_NAME}:buildcache"
    }

    stages {
        stage('Build') {
            agent { label 'docker' }
            steps {
                script {
                    sh "docker pull ${IMAGE_CACHE} || true"

                    docker.withRegistry("https://${REGISTRY}", 'registry-credentials') {
                        def img = docker.build(
                            IMAGE,
                            "--cache-from ${IMAGE_CACHE} " +
                            "--build-arg BUILDKIT_INLINE_CACHE=1 " +
                            "--build-arg VERSION=${IMAGE_TAG} " +
                            "."
                        )

                        img.push()
                        if (env.BRANCH_NAME == 'main') {
                            img.push('latest')
                            img.push('buildcache')
                        }
                    }
                }
            }
        }

        stage('Scan') {
            agent {
                docker {
                    image 'aquasec/trivy:latest'
                    args '--entrypoint=""'
                    label 'docker'
                }
            }
            steps {
                sh """
                    trivy image \
                        --exit-code 0 \
                        --severity HIGH,CRITICAL \
                        --format json \
                        --output trivy.json \
                        ${IMAGE}

                    # Fail on CRITICAL only
                    trivy image \
                        --exit-code 1 \
                        --severity CRITICAL \
                        ${IMAGE}
                """
            }
            post {
                always {
                    archiveArtifacts allowEmptyArchive: true, artifacts: 'trivy.json'
                }
            }
        }

        stage('Deploy Staging') {
            when { branch 'main' }
            agent { label 'deploy' }
            environment {
                KUBECONFIG = credentials('kubeconfig-staging')
            }
            steps {
                sh """
                    helm upgrade --install ${APP_NAME} ./helm/${APP_NAME} \
                        --namespace staging \
                        --set image.tag=${IMAGE_TAG} \
                        --atomic --timeout 5m
                """
            }
        }
    }

    post {
        failure {
            slackSend channel: '#ci', color: 'danger',
                message: "❌ Docker build failed: ${JOB_NAME} #${BUILD_NUMBER}\n${BUILD_URL}"
        }
    }
}
```

---

## Cheatsheet

```groovy
// Build
def img = docker.build('my-app:tag')
def img = docker.build('my-app:tag', '--cache-from cache-img -f Dockerfile.prod .')

// Push with auth
docker.withRegistry('https://registry.example.com', 'cred-id') {
    img.push()
    img.push('latest')
}

// Run inside image
docker.image('python:3.11').inside {
    sh 'pytest'
}

// With environment
docker.image('python:3.11').inside('-e DB_URL=... -v /tmp:/tmp') {
    sh 'pytest'
}

// BuildKit
withEnv(['DOCKER_BUILDKIT=1']) {
    sh 'docker build --secret id=token,env=TOKEN ...'
}

// ECR login
sh '''
    aws ecr get-login-password | docker login \
        --username AWS \
        --password-stdin 123456789.dkr.ecr.eu-central-1.amazonaws.com
'''
```

---

*Next: [Jenkins with Kubernetes →](./08-jenkins-kubernetes.md)*
