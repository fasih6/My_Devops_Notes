# 🤖 Agents & Nodes

Static agents, dynamic cloud agents, Kubernetes pod agents, and managing your build fleet.

---

## 📚 Table of Contents

- [1. Agent Concepts](#1-agent-concepts)
- [2. Static Agents (Permanent Nodes)](#2-static-agents-permanent-nodes)
- [3. Docker Agents](#3-docker-agents)
- [4. Kubernetes Pod Agents](#4-kubernetes-pod-agents)
- [5. Cloud Agents (AWS EC2, Azure)](#5-cloud-agents-aws-ec2-azure)
- [6. Agent Labels & Selection](#6-agent-labels--selection)
- [7. Agent Best Practices](#7-agent-best-practices)
- [Cheatsheet](#cheatsheet)

---

## 1. Agent Concepts

An **agent** (formerly called "slave" or "node") is a machine that runs Jenkins build jobs. The **controller** orchestrates but should not run builds itself.

### Agent connection methods

| Method | Description | Use for |
|--------|-------------|---------|
| **SSH** | Controller SSHes into agent | Linux agents |
| **JNLP/WebSocket** | Agent connects OUT to controller | Firewalled agents, Windows |
| **Inbound agent** | Agent polls controller | Cloud/dynamic agents |

### Executor

An executor is a thread slot for running one build. An agent with 4 executors can run 4 concurrent builds.

```
Agent node "linux-builder-1":
  Executors: 4
  └── Executor 1: running "project-a #42"
  └── Executor 2: running "project-b #17"
  └── Executor 3: idle
  └── Executor 4: idle
```

---

## 2. Static Agents (Permanent Nodes)

A static agent is a long-lived machine registered in Jenkins permanently.

### Adding a static agent via UI

```
Jenkins → Manage Jenkins → Nodes → New Node
  Node name: linux-builder-01
  Type: Permanent Agent
  
  Remote root directory: /home/jenkins/workspace
  Labels: linux docker maven
  Usage: Use this node as much as possible
  
  Launch method: Launch agent via SSH
    Host: 10.0.0.5
    Credentials: jenkins-ssh-key
    Host Key Verification: Non verifying (or Known hosts)
  
  Availability: Keep this agent online as much as possible
```

### Node configuration as code (JCasC)

```yaml
# jenkins.yaml (Configuration as Code)
jenkins:
  nodes:
    - permanent:
        name: "linux-builder-01"
        labelString: "linux docker maven"
        remoteFS: "/home/jenkins/workspace"
        numExecutors: 4
        launcher:
          ssh:
            host: "10.0.0.5"
            port: 22
            credentialsId: "jenkins-ssh-key"
            launchTimeoutSeconds: 60
            maxNumRetries: 10
            retryWaitTime: 15
            sshHostKeyVerificationStrategy: "nonVerifyingKeyVerificationStrategy"
        retentionStrategy: "always"
```

### Setting up the agent machine

```bash
# On the agent machine (Linux):
# Create jenkins user
sudo useradd -m -s /bin/bash jenkins
sudo mkdir -p /home/jenkins/workspace
sudo chown jenkins:jenkins /home/jenkins/workspace

# Install Java (required for Jenkins agent)
sudo apt install -y default-jdk

# Add SSH public key for jenkins user
sudo mkdir -p /home/jenkins/.ssh
sudo echo "ssh-ed25519 AAAAC3Nz... jenkins@controller" >> /home/jenkins/.ssh/authorized_keys
sudo chmod 600 /home/jenkins/.ssh/authorized_keys
sudo chown -R jenkins:jenkins /home/jenkins/.ssh

# Install required tools (Docker, kubectl, helm, etc.)
sudo apt install -y docker.io
sudo usermod -aG docker jenkins
```

---

## 3. Docker Agents

Run each build in a fresh Docker container — clean, isolated, no leftover state.

### In-pipeline Docker agent

```groovy
pipeline {
    agent {
        docker {
            image 'python:3.11-slim'
            label 'docker-host'    // run on agent with this label
            args '-v /tmp:/tmp --network host'
            registryUrl 'https://registry.example.com'
            registryCredentialsId 'registry-credentials'
            alwaysPull true        // always pull latest image
        }
    }
    stages {
        stage('Test') {
            steps {
                sh 'python --version'
                sh 'pip install pytest && pytest'
            }
        }
    }
}
```

### Per-stage Docker agents

```groovy
pipeline {
    agent none    // no global agent

    stages {
        stage('Lint') {
            agent {
                docker { image 'pyfound/black:latest_release' }
            }
            steps { sh 'black --check .' }
        }

        stage('Test') {
            agent {
                docker {
                    image 'python:3.11-slim'
                    args '--network test-network'
                }
            }
            steps { sh 'pytest' }
        }

        stage('Build Image') {
            agent {
                docker {
                    image 'docker:24'
                    args '-v /var/run/docker.sock:/var/run/docker.sock'
                }
            }
            steps {
                sh 'docker build -t my-app:latest .'
            }
        }
    }
}
```

### Docker with services (sidecar containers)

```groovy
// Use docker-compose or --network for sidecars
stage('Integration Test') {
    agent {
        docker {
            image 'python:3.11'
            args '--network integration-test-net'
        }
    }
    steps {
        // Start postgres as sidecar (must be on same network)
        sh '''
            docker run -d --name postgres --network integration-test-net \
              -e POSTGRES_PASSWORD=test postgres:15
            sleep 5
            pytest tests/integration/
        '''
    }
    post {
        always {
            sh 'docker rm -f postgres || true'
        }
    }
}
```

---

## 4. Kubernetes Pod Agents

Each build runs as a Kubernetes pod — native cloud-native approach. Requires the Kubernetes plugin.

### Basic pod agent

```groovy
pipeline {
    agent {
        kubernetes {
            yaml '''
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
          cpu: 500m
          memory: 512Mi
        limits:
          cpu: 1
          memory: 1Gi
'''
        }
    }
    stages {
        stage('Test') {
            steps {
                container('python') {
                    sh 'pytest tests/'
                }
            }
        }
    }
}
```

### Multi-container pod agent

```groovy
pipeline {
    agent {
        kubernetes {
            yaml """
apiVersion: v1
kind: Pod
metadata:
  labels:
    jenkins: agent
spec:
  serviceAccountName: jenkins-agent
  containers:
    # Default JNLP container (always required — don't remove)
    - name: jnlp
      image: jenkins/inbound-agent:latest
      resources:
        requests:
          cpu: 200m
          memory: 256Mi

    # Build container
    - name: python
      image: python:3.11-slim
      command: [sleep]
      args: [infinity]
      resources:
        requests:
          cpu: 500m
          memory: 512Mi

    # Docker-in-Docker for building images
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

    # Kubectl/Helm for deployments
    - name: deploy
      image: alpine/helm:3.13
      command: [sleep]
      args: [infinity]

  volumes:
    - name: docker-sock
      emptyDir: {}
"""
        }
    }

    stages {
        stage('Test') {
            steps {
                container('python') {
                    sh '''
                        pip install -r requirements.txt
                        pytest --junitxml=results.xml
                    '''
                }
            }
            post {
                always {
                    junit 'results.xml'
                }
            }
        }

        stage('Build Image') {
            steps {
                container('docker') {
                    withCredentials([usernamePassword(
                        credentialsId: 'registry-credentials',
                        usernameVariable: 'REGISTRY_USER',
                        passwordVariable: 'REGISTRY_PASS'
                    )]) {
                        sh '''
                            docker login -u $REGISTRY_USER -p $REGISTRY_PASS registry.example.com
                            docker build -t registry.example.com/my-app:${GIT_COMMIT::8} .
                            docker push registry.example.com/my-app:${GIT_COMMIT::8}
                        '''
                    }
                }
            }
        }

        stage('Deploy') {
            steps {
                container('deploy') {
                    withCredentials([file(credentialsId: 'kubeconfig', variable: 'KUBECONFIG')]) {
                        sh '''
                            helm upgrade --install my-app ./helm/my-app \
                                --namespace staging \
                                --set image.tag=${GIT_COMMIT::8} \
                                --atomic
                        '''
                    }
                }
            }
        }
    }
}
```

### Kubernetes plugin configuration (JCasC)

```yaml
# jenkins.yaml
jenkins:
  clouds:
    - kubernetes:
        name: "kubernetes"
        serverUrl: ""       # empty = in-cluster config
        namespace: "jenkins"
        jenkinsUrl: "http://jenkins.jenkins.svc.cluster.local:8080"
        jenkinsTunnel: "jenkins-agent.jenkins.svc.cluster.local:50000"
        maxRequestsPerHostStr: "32"
        podLabels:
          - key: "jenkins"
            value: "agent"
        templates:
          - name: "default"
            label: "k8s"
            containers:
              - name: "jnlp"
                image: "jenkins/inbound-agent:latest"
                resourceRequestCpu: "100m"
                resourceRequestMemory: "256Mi"
                resourceLimitCpu: "500m"
                resourceLimitMemory: "512Mi"
```

---

## 5. Cloud Agents (AWS EC2, Azure)

Auto-provision cloud VMs on demand, terminate when idle.

### AWS EC2 plugin configuration

```yaml
# JCasC
jenkins:
  clouds:
    - amazonEC2:
        name: "aws-ec2"
        region: "eu-central-1"
        credentialsId: "aws-credentials"
        sshKeysCredentialsId: "ec2-ssh-key"
        templates:
          - ami: "ami-ubuntu-22.04"
            description: "Ubuntu 22.04 Docker Builder"
            instanceType: T3Large
            labelString: "linux docker"
            numExecutors: 2
            remoteFS: "/home/ubuntu"
            securityGroups: "jenkins-agent-sg"
            subnetId: "subnet-abc123"
            useEphemeralBotInstance: true
            idleTerminationMinutes: "15"
            minimumNumberOfInstances: 0   # scale to zero
            maximumTotalUses: 1           # fresh instance per build (ephemeral)
            userData: |
              #!/bin/bash
              apt-get update -y
              apt-get install -y docker.io java-17-openjdk
              usermod -aG docker ubuntu
              systemctl start docker
```

---

## 6. Agent Labels & Selection

Labels let you route jobs to specific agents.

```groovy
// Request agent by label
pipeline {
    agent { label 'linux' }        // any agent with 'linux' label
    agent { label 'linux && docker' }   // must have BOTH labels
    agent { label 'linux || macos' }    // either label
}

// Stage-level agent override
stage('Windows Tests') {
    agent { label 'windows' }
    steps { bat 'pytest' }
}
```

### Common label conventions

```
OS:          linux, windows, macos
Tools:       docker, kubectl, helm, maven, node, python
Environment: production, staging, deploy
Hardware:    high-memory, gpu, fast-ssd
Cloud:       aws, gcp, azure
Team:        platform, backend, frontend
```

---

## 7. Agent Best Practices

```
✅ Run zero executors on the controller (builds should never run there)
✅ Use Kubernetes agents for cloud-native setups (autoscaling, isolation)
✅ Use Docker agents for tool isolation (each build gets clean environment)
✅ Label agents clearly (linux, docker, deploy — not "agent1")
✅ Set resource limits on Kubernetes pod agents
✅ Use ephemeral agents (fresh environment per build)
✅ Shared workspaces need cleanup → use cleanWs() in post.always
✅ Set buildDiscarder to limit workspace disk usage
✅ Monitor agent queue depth (slow builds = need more agents)

Static agents:
✅ Keep agent Java version compatible with controller
✅ Install only tools needed (minimize attack surface)
✅ Use dedicated jenkins user (not root)
✅ Keep tools up to date (security patches)

Kubernetes agents:
✅ Set resource requests AND limits
✅ Use serviceAccountName with minimal RBAC
✅ Use namespace for isolation
✅ Pin image versions (don't use :latest in production)
```

---

## Cheatsheet

```groovy
// Static agent
agent { label 'linux' }
agent { label 'linux && docker' }

// Docker agent
agent {
    docker {
        image 'python:3.11'
        label 'docker-host'
        args '-v /tmp:/tmp'
    }
}

// Kubernetes agent
agent {
    kubernetes {
        yaml '''
apiVersion: v1
kind: Pod
spec:
  containers:
    - name: python
      image: python:3.11
      command: [sleep]
      args: [infinity]
'''
    }
}

// Use specific container in K8s pod
steps {
    container('python') {
        sh 'pytest'
    }
}

// No agent — specify per stage
agent none
```

---

*Next: [Variables, Credentials & Secrets →](./05-variables-credentials-secrets.md)*
