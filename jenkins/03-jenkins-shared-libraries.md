# 📚 Shared Libraries

Writing reusable Groovy pipeline code shared across all teams and projects.

---

## 📚 Table of Contents

- [1. What are Shared Libraries?](#1-what-are-shared-libraries)
- [2. Library Structure](#2-library-structure)
- [3. Global Variables (vars/)](#3-global-variables-vars)
- [4. Groovy Classes (src/)](#4-groovy-classes-src)
- [5. Resources (resources/)](#5-resources-resources)
- [6. Loading Libraries in Pipelines](#6-loading-libraries-in-pipelines)
- [7. Testing Shared Libraries](#7-testing-shared-libraries)
- [8. Real-World Library Example](#8-real-world-library-example)
- [Cheatsheet](#cheatsheet)

---

## 1. What are Shared Libraries?

Shared Libraries are reusable Groovy code that can be called from any Jenkinsfile. Instead of copying the same build/deploy logic into every project, you write it once in a library and reference it everywhere.

```
Without shared library:
  project-a/Jenkinsfile:  stage('Build') { sh 'docker build ...' docker push ... }
  project-b/Jenkinsfile:  stage('Build') { sh 'docker build ...' docker push ... }
  project-c/Jenkinsfile:  stage('Build') { sh 'docker build ...' docker push ... }
  (duplicated logic — hard to update, inconsistent)

With shared library:
  project-a/Jenkinsfile:  dockerBuild image: 'my-app', tag: env.GIT_COMMIT
  project-b/Jenkinsfile:  dockerBuild image: 'my-worker', tag: env.GIT_COMMIT
  project-c/Jenkinsfile:  dockerBuild image: 'my-api', tag: env.GIT_COMMIT
  (one place to update, consistent behavior)
```

### Benefits

- **DRY** — write build/deploy logic once
- **Consistency** — all pipelines follow the same patterns
- **Maintainability** — fix bugs in one place, all pipelines benefit
- **Versioning** — pin library version per project, upgrade when ready
- **Abstraction** — hide complexity from developers

---

## 2. Library Structure

```
my-jenkins-library/
├── vars/                      ← Global variables (callable functions)
│   ├── dockerBuild.groovy     ← def call(Map config) { ... }
│   ├── helmDeploy.groovy
│   ├── notifySlack.groovy
│   └── runTests.groovy
├── src/                       ← Groovy classes (for complex logic)
│   └── com/
│       └── mycompany/
│           └── ci/
│               ├── Docker.groovy
│               ├── Helm.groovy
│               └── Utils.groovy
├── resources/                 ← Static files (scripts, configs)
│   ├── scripts/
│   │   └── run-tests.sh
│   └── config/
│       └── lint-rules.yaml
└── README.md
```

---

## 3. Global Variables (vars/)

Global variables are the most common way to create callable steps.

### Simple step

```groovy
// vars/sayHello.groovy
def call(String name) {
    echo "Hello, ${name}!"
}

// In Jenkinsfile:
sayHello 'World'
```

### Map-based configuration (preferred pattern)

```groovy
// vars/dockerBuild.groovy
def call(Map config = [:]) {
    // Set defaults
    config.registry = config.registry ?: 'registry.example.com'
    config.dockerfile = config.dockerfile ?: 'Dockerfile'
    config.context = config.context ?: '.'
    config.push = config.push != null ? config.push : true

    // Validate required params
    if (!config.image) {
        error "dockerBuild: 'image' parameter is required"
    }
    if (!config.tag) {
        error "dockerBuild: 'tag' parameter is required"
    }

    def fullTag = "${config.registry}/${config.image}:${config.tag}"

    echo "Building ${fullTag}"

    withCredentials([usernamePassword(
        credentialsId: config.credentialsId ?: 'registry-credentials',
        usernameVariable: 'REGISTRY_USER',
        passwordVariable: 'REGISTRY_PASS'
    )]) {
        sh """
            docker login -u \$REGISTRY_USER -p \$REGISTRY_PASS ${config.registry}
            docker build \\
                --cache-from ${config.registry}/${config.image}:latest \\
                --build-arg BUILDKIT_INLINE_CACHE=1 \\
                -f ${config.dockerfile} \\
                -t ${fullTag} \\
                ${config.context}
        """

        if (config.push) {
            sh "docker push ${fullTag}"

            if (config.tagAsLatest) {
                sh """
                    docker tag ${fullTag} ${config.registry}/${config.image}:latest
                    docker push ${config.registry}/${config.image}:latest
                """
            }
        }
    }

    return fullTag    // return the full image tag for use in calling pipeline
}

// In Jenkinsfile:
def imageTag = dockerBuild(
    image: 'my-app',
    tag: env.GIT_COMMIT.take(8),
    tagAsLatest: env.BRANCH_NAME == 'main'
)
echo "Built: ${imageTag}"
```

### Step with stages (wraps pipeline stages)

```groovy
// vars/withNotifications.groovy
def call(String jobName, Closure body) {
    try {
        body()
        slackSend(
            channel: '#deployments',
            color: 'good',
            message: "✅ ${jobName} succeeded (build #${env.BUILD_NUMBER})"
        )
    } catch (e) {
        slackSend(
            channel: '#deployments',
            color: 'danger',
            message: "❌ ${jobName} FAILED (build #${env.BUILD_NUMBER})\n${env.BUILD_URL}"
        )
        throw e    // re-throw to fail the build
    }
}

// In Jenkinsfile:
withNotifications('my-service deploy') {
    stage('Deploy') {
        sh './deploy.sh'
    }
}
```

### Accessing pipeline context (steps, env, currentBuild)

```groovy
// vars/gitInfo.groovy
// Must use 'steps' to access pipeline DSL inside classes/vars
def call() {
    def commit = steps.sh(
        script: 'git rev-parse --short HEAD',
        returnStdout: true
    ).trim()

    def branch = steps.env.BRANCH_NAME ?: steps.sh(
        script: 'git rev-parse --abbrev-ref HEAD',
        returnStdout: true
    ).trim()

    return [commit: commit, branch: branch]
}
```

---

## 4. Groovy Classes (src/)

For complex logic that benefits from OOP.

```groovy
// src/com/mycompany/ci/Helm.groovy
package com.mycompany.ci

class Helm implements Serializable {
    private def script    // Jenkins pipeline script context

    Helm(script) {
        this.script = script
    }

    def deploy(Map config) {
        config.namespace = config.namespace ?: 'default'
        config.timeout = config.timeout ?: '5m'

        script.sh """
            helm upgrade --install ${config.release} ${config.chart} \\
                --namespace ${config.namespace} \\
                --create-namespace \\
                --set image.tag=${config.imageTag} \\
                --atomic \\
                --timeout ${config.timeout}
        """
    }

    def rollback(String release, String namespace = 'default') {
        script.sh "helm rollback ${release} --namespace ${namespace} --wait"
    }

    def uninstall(String release, String namespace = 'default') {
        script.sh "helm uninstall ${release} --namespace ${namespace} || true"
    }
}
```

```groovy
// Using the class in a Jenkinsfile
@Library('my-jenkins-library') _
import com.mycompany.ci.Helm

pipeline {
    agent any
    stages {
        stage('Deploy') {
            steps {
                script {
                    def helm = new Helm(this)    // 'this' = pipeline context
                    helm.deploy(
                        release: 'my-app',
                        chart: './helm/my-app',
                        namespace: 'production',
                        imageTag: env.GIT_COMMIT.take(8)
                    )
                }
            }
        }
    }
}
```

---

## 5. Resources (resources/)

Static files bundled with the library.

```groovy
// vars/runLint.groovy
def call(String configFile = null) {
    if (!configFile) {
        // Load default lint config from library resources
        def lintConfig = libraryResource 'config/lint-rules.yaml'
        writeFile file: '.lint-rules.yaml', text: lintConfig
        configFile = '.lint-rules.yaml'
    }

    sh "ruff check --config ${configFile} ."
}
```

```groovy
// vars/runTests.groovy
def call(Map config = [:]) {
    // Load test runner script from library
    def testScript = libraryResource 'scripts/run-tests.sh'
    writeFile file: 'run-tests.sh', text: testScript
    sh 'chmod +x run-tests.sh && ./run-tests.sh'
}
```

---

## 6. Loading Libraries in Pipelines

### Method 1 — @Library annotation (per-pipeline)

```groovy
// Load specific version
@Library('my-jenkins-library@v2.0') _

// Load main branch
@Library('my-jenkins-library') _

// Load multiple libraries
@Library(['my-jenkins-library@v2', 'company-standards@main']) _

// The underscore _ imports all vars (equivalent to import *)
// Or import specific classes:
@Library('my-jenkins-library') import com.mycompany.ci.Helm
```

### Method 2 — Global trusted library (automatic)

```
Jenkins UI → Manage Jenkins → System → Global Trusted Pipeline Libraries
  Name: my-jenkins-library
  Default version: main
  Load implicitly: ✓   ← always available, no @Library needed
  Source:
    SCM: Git
    Repository URL: https://gitlab.com/myorg/jenkins-library.git
    Credentials: gitlab-token
```

### Method 3 — Dynamic library loading

```groovy
// Load dynamically at runtime
def lib = library('my-jenkins-library@main')
lib.com.mycompany.ci.Helm.new(this).deploy(...)
```

### Configure library in Jenkins UI

```
Jenkins → Manage Jenkins → System → Global Trusted Pipeline Libraries
  Add Library:
    Name: company-pipeline-lib
    Default version: main
    Allow default version to be overridden: ✓
    Include @Library changes in job recent changes: ✓
    Source Code Management: Git
      Repository URL: https://gitlab.com/platform/jenkins-library.git
      Credentials: jenkins-gitlab-token
      Behaviors: Discover branches
```

---

## 7. Testing Shared Libraries

Use the `jenkins-pipeline-unit` library for unit testing.

```groovy
// test/vars/DockerBuildTest.groovy
import com.lesfurets.jenkins.unit.BasePipelineTest
import org.junit.Before
import org.junit.Test
import static org.junit.Assert.assertEquals

class DockerBuildTest extends BasePipelineTest {

    @Before
    void setUp() {
        super.setUp()
    }

    @Test
    void testDockerBuildWithDefaults() {
        def script = loadScript('vars/dockerBuild.groovy')

        // Mock pipeline steps
        helper.registerAllowedMethod('sh', [String.class], null)
        helper.registerAllowedMethod('withCredentials', [List.class, Closure.class], { _, c -> c() })

        // Call the function
        script.call(image: 'my-app', tag: 'abc123')

        // Verify sh was called with expected args
        def calls = helper.callStack.findAll { it.methodName == 'sh' }
        assert calls.any { it.args[0].contains('docker build') }
        assert calls.any { it.args[0].contains('my-app:abc123') }
    }
}
```

```groovy
// build.gradle for running tests
dependencies {
    testImplementation 'com.lesfurets:jenkins-pipeline-unit:1.21'
    testImplementation 'junit:junit:4.13'
}
```

```bash
# Run tests
./gradlew test
```

---

## 8. Real-World Library Example

### Complete library structure for a DevOps team

```
company-jenkins-library/
├── vars/
│   ├── dockerBuild.groovy         ← build & push Docker image
│   ├── helmDeploy.groovy          ← deploy with Helm
│   ├── runTests.groovy            ← run test suite
│   ├── sonarScan.groovy           ← SonarQube analysis
│   ├── trivyScan.groovy           ← Trivy security scan
│   ├── notifySlack.groovy         ← Slack notifications
│   ├── gitTag.groovy              ← create/push git tags
│   └── standardPipeline.groovy   ← complete pipeline template
├── src/com/company/ci/
│   ├── Docker.groovy
│   ├── Helm.groovy
│   └── Utils.groovy
└── resources/
    └── scripts/
        └── smoke-test.sh
```

### standardPipeline.groovy — complete pipeline template

```groovy
// vars/standardPipeline.groovy
// One call sets up a complete CI/CD pipeline

def call(Map config = [:]) {
    config.appName = config.appName ?: error('appName is required')
    config.registry = config.registry ?: 'registry.example.com'
    config.runTests = config.runTests != null ? config.runTests : true
    config.deployStaging = config.deployStaging != null ? config.deployStaging : true
    config.deployProduction = config.deployProduction ?: false

    pipeline {
        agent none

        options {
            timeout(time: 1, unit: 'HOURS')
            buildDiscarder(logRotator(numToKeepStr: '20'))
            disableConcurrentBuilds(abortPrevious: true)
            timestamps()
        }

        environment {
            IMAGE_TAG = "${config.registry}/${config.appName}:${GIT_COMMIT.take(8)}"
        }

        stages {
            stage('Test') {
                when { expression { config.runTests } }
                agent { label 'docker' }
                steps {
                    runTests(config.testConfig ?: [:])
                }
            }

            stage('Build') {
                agent { label 'docker' }
                steps {
                    script {
                        dockerBuild(
                            image: config.appName,
                            tag: env.GIT_COMMIT.take(8),
                            registry: config.registry,
                            tagAsLatest: env.BRANCH_NAME == 'main'
                        )
                    }
                }
            }

            stage('Security Scan') {
                agent { label 'docker' }
                steps {
                    trivyScan(image: env.IMAGE_TAG)
                }
            }

            stage('Deploy Staging') {
                when {
                    allOf {
                        branch 'main'
                        expression { config.deployStaging }
                    }
                }
                agent { label 'deploy' }
                steps {
                    helmDeploy(
                        release: config.appName,
                        chart: "./helm/${config.appName}",
                        namespace: 'staging',
                        imageTag: env.GIT_COMMIT.take(8)
                    )
                }
            }

            stage('Deploy Production') {
                when {
                    allOf {
                        branch 'main'
                        expression { config.deployProduction }
                    }
                }
                agent { label 'deploy' }
                steps {
                    timeout(time: 30, unit: 'MINUTES') {
                        input message: "Deploy ${config.appName} to production?",
                              submitter: 'ops-team'
                    }
                    helmDeploy(
                        release: config.appName,
                        chart: "./helm/${config.appName}",
                        namespace: 'production',
                        imageTag: env.GIT_COMMIT.take(8)
                    )
                }
            }
        }

        post {
            failure {
                notifySlack(
                    message: "❌ ${config.appName} pipeline failed",
                    color: 'danger'
                )
            }
        }
    }
}
```

```groovy
// Project Jenkinsfile — just 5 lines!
@Library('company-jenkins-library@main') _

standardPipeline(
    appName: 'my-service',
    deployProduction: true
)
```

---

## Cheatsheet

```groovy
// Load library
@Library('my-lib@v2.0') _
@Library(['lib1', 'lib2@main']) _

// Call global var
myStep arg1, arg2
myStep(param1: 'value', param2: 42)

// Call in script block
script {
    def result = myStep(key: 'value')
}

// vars/myStep.groovy structure
def call(Map config = [:]) {
    config.key = config.key ?: 'default'
    sh "echo ${config.key}"
}

// src/ class structure
package com.company.ci
class MyClass implements Serializable {
    def script
    MyClass(script) { this.script = script }
    def myMethod() { script.sh 'echo hello' }
}

// Load resource
def content = libraryResource 'path/to/file.sh'
writeFile file: 'file.sh', text: content

// Use class from library
import com.company.ci.MyClass
def obj = new MyClass(this)
obj.myMethod()
```

---

*Next: [Agents & Nodes →](./04-agents-nodes.md)*
