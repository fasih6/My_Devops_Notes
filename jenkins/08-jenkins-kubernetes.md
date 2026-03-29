# ☸️ Jenkins with Kubernetes

Kubernetes plugin, pod templates, Helm deployments, and running Jenkins on Kubernetes.

---

## 📚 Table of Contents

- [1. Running Jenkins on Kubernetes](#1-running-jenkins-on-kubernetes)
- [2. Kubernetes Plugin — Pod Agents](#2-kubernetes-plugin--pod-agents)
- [3. Pod Templates](#3-pod-templates)
- [4. Deploying with kubectl in Pipelines](#4-deploying-with-kubectl-in-pipelines)
- [5. Helm Deployments](#5-helm-deployments)
- [6. RBAC for Jenkins on Kubernetes](#6-rbac-for-jenkins-on-kubernetes)
- [7. Complete K8s-Native Pipeline](#7-complete-k8s-native-pipeline)
- [Cheatsheet](#cheatsheet)

---

## 1. Running Jenkins on Kubernetes

### Install Jenkins on Kubernetes with Helm

```bash
# Add Jenkins Helm chart
helm repo add jenkins https://charts.jenkins.io
helm repo update

# Create namespace
kubectl create namespace jenkins

# Create values file
cat > jenkins-values.yaml << 'EOF'
controller:
  image: jenkins/jenkins
  tag: lts-jdk17

  # Admin user
  adminUser: admin
  adminPassword: your-secure-password  # use --set or secret instead

  # Resources
  resources:
    requests:
      cpu: 500m
      memory: 1Gi
    limits:
      cpu: 2
      memory: 4Gi

  # JVM options
  javaOpts: "-Xms512m -Xmx2g -Dhudson.slaves.NodeProvisioner.initialDelay=0"

  # Plugins to install
  installPlugins:
    - kubernetes:latest
    - workflow-aggregator:latest
    - git:latest
    - blueocean:latest
    - credentials:latest
    - configuration-as-code:latest
    - pipeline-stage-view:latest
    - slack:latest

  # Configuration as Code
  JCasC:
    configScripts:
      jenkins-config: |
        jenkins:
          systemMessage: "Jenkins CI/CD"
          numExecutors: 0
          clouds:
            - kubernetes:
                name: "kubernetes"
                namespace: "jenkins"
                jenkinsUrl: "http://jenkins.jenkins.svc.cluster.local:8080"
                jenkinsTunnel: "jenkins-agent.jenkins.svc.cluster.local:50000"

  # Persistence
  persistence:
    enabled: true
    storageClass: gp3
    size: 50Gi

  # Ingress
  ingress:
    enabled: true
    ingressClassName: nginx
    hostName: jenkins.example.com
    annotations:
      cert-manager.io/cluster-issuer: letsencrypt-prod
    tls:
      - secretName: jenkins-tls
        hosts: [jenkins.example.com]

agent:
  enabled: true
  namespace: jenkins
  resources:
    requests:
      cpu: 200m
      memory: 256Mi
    limits:
      cpu: 1
      memory: 1Gi

serviceAccount:
  create: true
  name: jenkins
EOF

# Install
helm install jenkins jenkins/jenkins \
  --namespace jenkins \
  --values jenkins-values.yaml

# Get admin password
kubectl get secret jenkins -n jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d
```

### Persistent Jenkins home backup

```bash
# Backup Jenkins home
kubectl exec -n jenkins jenkins-0 -- tar czf - /var/jenkins_home \
  | gzip > jenkins-backup-$(date +%Y%m%d).tar.gz

# Restore
kubectl exec -n jenkins jenkins-0 -- tar xzf - -C / < jenkins-backup.tar.gz
```

---

## 2. Kubernetes Plugin — Pod Agents

The Kubernetes plugin creates a pod for each Jenkins build. The pod contains:
- **JNLP container** — connects to Jenkins controller (always required)
- **Your containers** — tools needed for the build

```groovy
pipeline {
    agent {
        kubernetes {
            // Inline YAML pod spec
            yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
    app: my-build
spec:
  serviceAccountName: jenkins-agent
  containers:
    - name: jnlp
      image: jenkins/inbound-agent:latest-jdk17
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
    - name: maven
      image: maven:3.9-eclipse-temurin-17
      command: [sleep]
      args: [infinity]
      resources:
        requests:
          cpu: 500m
          memory: 1Gi
        limits:
          cpu: 2
          memory: 2Gi
      volumeMounts:
        - name: m2-cache
          mountPath: /root/.m2
  volumes:
    - name: m2-cache
      persistentVolumeClaim:
        claimName: maven-cache
"""
        }
    }
    stages {
        stage('Build') {
            steps {
                container('maven') {
                    sh 'mvn clean package'
                }
            }
        }
    }
}
```

---

## 3. Pod Templates

### Reusable pod templates (JCasC or shared library)

```yaml
# jenkins.yaml (JCasC) — define reusable pod templates
jenkins:
  clouds:
    - kubernetes:
        name: kubernetes
        templates:
          - name: maven-builder
            label: maven
            containers:
              - name: maven
                image: maven:3.9-eclipse-temurin-17
                command: sleep
                args: infinity
                resourceRequestCpu: "500m"
                resourceRequestMemory: "1Gi"
                resourceLimitCpu: "2"
                resourceLimitMemory: "2Gi"
            volumes:
              - persistentVolumeClaim:
                  claimName: maven-cache
                  mountPath: /root/.m2
                  readOnly: false

          - name: node-builder
            label: nodejs
            containers:
              - name: node
                image: node:20-alpine
                command: sleep
                args: infinity
                resourceRequestCpu: "200m"
                resourceRequestMemory: "512Mi"

          - name: helm-deployer
            label: helm
            serviceAccount: jenkins-deployer
            containers:
              - name: helm
                image: alpine/helm:3.13
                command: sleep
                args: infinity
                resourceRequestCpu: "100m"
                resourceRequestMemory: "128Mi"
```

### Shared library pod templates

```groovy
// vars/podTemplates.groovy — define templates in shared library
def pythonPod() {
    return """
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: python
      image: python:3.11-slim
      command: [sleep]
      args: [infinity]
      resources:
        requests:
          cpu: 200m
          memory: 256Mi
"""
}

def dockerBuildPod() {
    return """
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: docker
      image: docker:24-dind
      securityContext:
        privileged: true
      env:
        - name: DOCKER_TLS_CERTDIR
          value: ""
      resources:
        requests:
          cpu: 500m
          memory: 512Mi
"""
}

def helmPod(String namespace = 'staging') {
    return """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-deployer
  containers:
    - name: helm
      image: alpine/helm:3.13
      command: [sleep]
      args: [infinity]
"""
}

// In Jenkinsfile:
@Library('company-jenkins-lib') _

pipeline {
    agent {
        kubernetes {
            yaml podTemplates.pythonPod()
        }
    }
    stages {
        stage('Test') {
            steps {
                container('python') {
                    sh 'pytest'
                }
            }
        }
    }
}
```

---

## 4. Deploying with kubectl in Pipelines

### Using kubectl container

```groovy
pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-deployer   # RBAC-controlled SA
  containers:
    - name: kubectl
      image: bitnami/kubectl:1.28
      command: [sleep]
      args: [infinity]
"""
        }
    }
    stages {
        stage('Deploy') {
            steps {
                container('kubectl') {
                    sh '''
                        kubectl set image deployment/my-app \
                            app=registry.example.com/my-app:${GIT_COMMIT:0:8} \
                            --namespace production
                        kubectl rollout status deployment/my-app --namespace production
                    '''
                }
            }
        }
    }
}
```

### Using kubeconfig credential

```groovy
stage('Deploy to Remote Cluster') {
    steps {
        container('kubectl') {
            withCredentials([file(credentialsId: 'kubeconfig-production', variable: 'KUBECONFIG')]) {
                sh '''
                    kubectl --kubeconfig=$KUBECONFIG \
                        set image deployment/my-app \
                        app=registry.example.com/my-app:${GIT_COMMIT:0:8} \
                        --namespace production
                '''
            }
        }
    }
}
```

---

## 5. Helm Deployments

### Helm deploy container in pod

```groovy
pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-deployer
  containers:
    - name: helm
      image: alpine/helm:3.13.0
      command: [sleep]
      args: [infinity]
      resources:
        requests:
          cpu: 100m
          memory: 128Mi
"""
        }
    }

    environment {
        APP_NAME = 'my-app'
        IMAGE_TAG = "${GIT_COMMIT.take(8)}"
    }

    stages {
        stage('Deploy Staging') {
            when { branch 'main' }
            steps {
                container('helm') {
                    sh '''
                        helm upgrade --install ${APP_NAME} ./helm/${APP_NAME} \
                            --namespace staging \
                            --create-namespace \
                            --values helm/${APP_NAME}/values-staging.yaml \
                            --set image.tag=${IMAGE_TAG} \
                            --atomic \
                            --timeout 5m \
                            --cleanup-on-fail
                    '''
                }
            }
        }

        stage('Approve Production') {
            when { branch 'main' }
            steps {
                timeout(time: 30, unit: 'MINUTES') {
                    input message: "Deploy ${APP_NAME}:${IMAGE_TAG} to production?",
                          submitter: 'ops-team'
                }
            }
        }

        stage('Deploy Production') {
            when { branch 'main' }
            steps {
                container('helm') {
                    sh '''
                        helm upgrade --install ${APP_NAME} ./helm/${APP_NAME} \
                            --namespace production \
                            --values helm/${APP_NAME}/values-production.yaml \
                            --set image.tag=${IMAGE_TAG} \
                            --atomic \
                            --timeout 10m
                    '''
                }
            }
            post {
                success {
                    slackSend channel: '#deployments', color: 'good',
                        message: "🚀 ${APP_NAME}:${IMAGE_TAG} deployed to production"
                }
            }
        }

        stage('Rollback Option') {
            when {
                allOf {
                    branch 'main'
                    expression { currentBuild.result == 'FAILURE' }
                }
            }
            steps {
                container('helm') {
                    script {
                        def rollback = input(
                            message: "Deployment failed. Roll back?",
                            parameters: [booleanParam(name: 'ROLLBACK', defaultValue: true)]
                        )
                        if (rollback) {
                            sh "helm rollback ${APP_NAME} --namespace production --wait"
                        }
                    }
                }
            }
        }
    }
}
```

---

## 6. RBAC for Jenkins on Kubernetes

### ServiceAccount for Jenkins controller

```yaml
# jenkins-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins
  namespace: jenkins

---
# Allow Jenkins to create/delete pods in its namespace (for agents)
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: jenkins-agent-role
  namespace: jenkins
rules:
  - apiGroups: [""]
    resources: [pods, pods/exec, pods/log, secrets, configmaps]
    verbs: [get, list, watch, create, update, patch, delete]
  - apiGroups: [""]
    resources: [events]
    verbs: [get, list, watch]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: jenkins-agent-binding
  namespace: jenkins
subjects:
  - kind: ServiceAccount
    name: jenkins
    namespace: jenkins
roleRef:
  kind: Role
  name: jenkins-agent-role
  apiGroup: rbac.authorization.k8s.io
```

### ServiceAccount for deployment agent

```yaml
# jenkins-deployer-rbac.yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: jenkins-deployer
  namespace: jenkins

---
# Allow deployer to manage workloads in staging and production
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: jenkins-deployer
rules:
  - apiGroups: [apps]
    resources: [deployments, statefulsets, daemonsets, replicasets]
    verbs: [get, list, watch, create, update, patch]
  - apiGroups: [""]
    resources: [services, configmaps, secrets, pods]
    verbs: [get, list, watch, create, update, patch]
  - apiGroups: [networking.k8s.io]
    resources: [ingresses]
    verbs: [get, list, watch, create, update, patch]

---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: jenkins-deployer-binding
subjects:
  - kind: ServiceAccount
    name: jenkins-deployer
    namespace: jenkins
roleRef:
  kind: ClusterRole
  name: jenkins-deployer
  apiGroup: rbac.authorization.k8s.io
```

---

## 7. Complete K8s-Native Pipeline

```groovy
// Full pipeline: build on K8s → push to registry → deploy to K8s

pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins-deployer
  containers:
    - name: jnlp
      image: jenkins/inbound-agent:latest-jdk17
      resources:
        requests: {cpu: 200m, memory: 256Mi}
    - name: docker
      image: docker:24-dind
      securityContext:
        privileged: true
      env:
        - name: DOCKER_TLS_CERTDIR
          value: ""
      resources:
        requests: {cpu: 500m, memory: 512Mi}
        limits: {cpu: 2, memory: 2Gi}
    - name: helm
      image: alpine/helm:3.13
      command: [sleep]
      args: [infinity]
      resources:
        requests: {cpu: 100m, memory: 128Mi}
"""
        }
    }

    environment {
        REGISTRY  = 'registry.example.com'
        APP_NAME  = 'my-app'
        IMAGE_TAG = "${GIT_COMMIT.take(8)}"
        IMAGE     = "${REGISTRY}/${APP_NAME}:${IMAGE_TAG}"
    }

    stages {
        stage('Build & Push') {
            steps {
                container('docker') {
                    withCredentials([usernamePassword(
                        credentialsId: 'registry-creds',
                        usernameVariable: 'REG_USER',
                        passwordVariable: 'REG_PASS'
                    )]) {
                        sh '''
                            docker login -u $REG_USER -p $REG_PASS $REGISTRY
                            docker build -t $IMAGE .
                            docker push $IMAGE
                        '''
                    }
                }
            }
        }

        stage('Deploy') {
            when { branch 'main' }
            steps {
                container('helm') {
                    sh '''
                        helm upgrade --install $APP_NAME ./helm/$APP_NAME \
                            --namespace staging \
                            --set image.tag=$IMAGE_TAG \
                            --atomic --timeout 5m
                    '''
                }
            }
        }
    }

    post {
        always {
            cleanWs()
        }
    }
}
```

---

## Cheatsheet

```groovy
// K8s pod agent
agent {
    kubernetes {
        yaml """
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: jenkins
  containers:
    - name: build-tool
      image: tool:version
      command: [sleep]
      args: [infinity]
"""
    }
}

// Use specific container
steps {
    container('build-tool') {
        sh 'build-command'
    }
}

// Helm deploy
container('helm') {
    sh '''
        helm upgrade --install app ./helm/app \
            --namespace staging \
            --set image.tag=$IMAGE_TAG \
            --atomic --timeout 5m
    '''
}
```

---

*Next: [Security & Administration →](./09-security-administration.md)*
