# 🔐 Variables, Credentials & Secrets

Managing secrets securely in Jenkins — credential types, binding, Vault integration, and best practices.

---

## 📚 Table of Contents

- [1. Environment Variables](#1-environment-variables)
- [2. Jenkins Credentials Store](#2-jenkins-credentials-store)
- [3. Credential Types](#3-credential-types)
- [4. withCredentials — Credential Binding](#4-withcredentials--credential-binding)
- [5. Credentials in environment {} Block](#5-credentials-in-environment--block)
- [6. HashiCorp Vault Integration](#6-hashicorp-vault-integration)
- [7. AWS Credentials & OIDC](#7-aws-credentials--oidc)
- [8. Security Best Practices](#8-security-best-practices)
- [Cheatsheet](#cheatsheet)

---

## 1. Environment Variables

### Built-in Jenkins variables

```groovy
// Available in all pipelines automatically
env.BUILD_NUMBER        // "42"
env.BUILD_ID            // "42"
env.BUILD_URL           // "https://jenkins.example.com/job/my-job/42/"
env.JOB_NAME            // "my-folder/my-job"
env.JOB_BASE_NAME       // "my-job"
env.WORKSPACE           // "/home/jenkins/workspace/my-job"
env.JENKINS_URL         // "https://jenkins.example.com/"
env.GIT_COMMIT          // full SHA: "abc123def456..."
env.GIT_BRANCH          // "origin/main"
env.GIT_URL             // "https://github.com/myorg/myrepo.git"
env.BRANCH_NAME         // "main" (Multibranch only)
env.CHANGE_ID           // PR number (Multibranch PR only)
env.CHANGE_TITLE        // PR title (Multibranch PR only)
env.CHANGE_AUTHOR       // PR author (Multibranch PR only)
env.TAG_NAME            // tag name (when building a tag)
```

### Setting environment variables

```groovy
pipeline {
    // Global — available in all stages
    environment {
        APP_NAME = 'my-service'
        REGISTRY = 'registry.example.com'
        IMAGE    = "${REGISTRY}/${APP_NAME}:${BUILD_NUMBER}"
        // Note: variables can reference other env vars in the SAME block
    }

    stages {
        stage('Build') {
            // Stage-level — only in this stage
            environment {
                BUILD_ENV = 'production'
            }
            steps {
                echo "Building ${APP_NAME} for ${BUILD_ENV}"

                // Set dynamically in steps using script block
                script {
                    env.GIT_SHORT_COMMIT = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()
                    env.APP_VERSION = "1.2.${BUILD_NUMBER}"
                }

                echo "Commit: ${env.GIT_SHORT_COMMIT}"
            }
        }
    }
}
```

### Accessing environment variables

```groovy
// In Groovy code
echo env.BUILD_NUMBER
echo "${env.APP_NAME}:${env.BUILD_NUMBER}"

// In shell commands (dollar-sign expansion)
sh 'echo $APP_NAME'          // shell variable expansion
sh "echo ${env.APP_NAME}"    // Groovy GString (resolved before shell)
sh "echo ${APP_NAME}"        // shorthand (works in environment context)

// In when conditions
when {
    environment name: 'DEPLOY_ENV', value: 'production'
}
```

---

## 2. Jenkins Credentials Store

Jenkins has a built-in encrypted credentials store. Credentials are stored in `$JENKINS_HOME/credentials.xml` (AES-encrypted).

### Credential scopes

| Scope | Accessible from |
|-------|----------------|
| **Global** | All jobs and pipelines |
| **System** | Jenkins system (internal use) |
| **Folder** | Jobs within a specific folder |

### Managing credentials

```
Jenkins → Manage Jenkins → Credentials → System → Global credentials
  → Add Credentials
    Kind: Username with password
    Username: myuser
    Password: ****
    ID: my-registry-credentials   ← use this ID in pipelines
    Description: Docker registry credentials

Folder credentials:
Jenkins → [Folder] → Credentials → [Folder Scope]
  → Add Credentials
```

### Jenkins CLI for credentials

```bash
# Using jenkins-cli.jar
java -jar jenkins-cli.jar -s https://jenkins.example.com \
  -auth user:api-token \
  create-credentials-by-xml system::system::jenkins _ \
  < credentials.xml

# Using Configuration as Code (preferred for automation)
```

---

## 3. Credential Types

### Username with password

```groovy
// Credential stored as: ID = 'docker-registry-creds'
// Username: myuser
// Password: mypassword

withCredentials([usernamePassword(
    credentialsId: 'docker-registry-creds',
    usernameVariable: 'DOCKER_USER',
    passwordVariable: 'DOCKER_PASS'
)]) {
    sh 'docker login -u $DOCKER_USER -p $DOCKER_PASS registry.example.com'
}
```

### Secret text (token, API key)

```groovy
withCredentials([string(
    credentialsId: 'slack-token',
    variable: 'SLACK_TOKEN'
)]) {
    sh 'curl -H "Authorization: Bearer $SLACK_TOKEN" https://slack.com/api/...'
}
```

### Secret file (kubeconfig, certificates)

```groovy
withCredentials([file(
    credentialsId: 'kubeconfig-production',
    variable: 'KUBECONFIG'
)]) {
    sh 'kubectl get pods --namespace production'
}

// Certificate credential
withCredentials([certificate(
    credentialsId: 'server-cert',
    keystoreVariable: 'SERVER_CERT',
    passwordVariable: 'CERT_PASSWORD'
)]) {
    sh 'curl --cert $SERVER_CERT:$CERT_PASSWORD https://api.internal'
}
```

### SSH private key

```groovy
withCredentials([sshUserPrivateKey(
    credentialsId: 'deploy-ssh-key',
    keyFileVariable: 'SSH_KEY_FILE',
    usernameVariable: 'SSH_USER',
    passphraseVariable: 'SSH_PASSPHRASE'
)]) {
    sh '''
        ssh -i $SSH_KEY_FILE \
            -o StrictHostKeyChecking=no \
            $SSH_USER@production-server.example.com \
            "cd /app && git pull && ./deploy.sh"
    '''
}
```

### AWS credentials (Access Key + Secret)

```groovy
// Using AWS Credentials plugin
withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
    credentialsId: 'aws-production',
    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
]]) {
    sh '''
        aws s3 sync dist/ s3://my-bucket/
        aws cloudfront create-invalidation --distribution-id $CF_DIST_ID --paths "/*"
    '''
}
```

---

## 4. withCredentials — Credential Binding

The `withCredentials` block is the most common and secure way to use credentials.

```groovy
// Multiple credentials in one block
withCredentials([
    usernamePassword(
        credentialsId: 'db-credentials',
        usernameVariable: 'DB_USER',
        passwordVariable: 'DB_PASS'
    ),
    string(
        credentialsId: 'api-token',
        variable: 'API_TOKEN'
    ),
    file(
        credentialsId: 'ssl-cert',
        variable: 'SSL_CERT_FILE'
    )
]) {
    sh '''
        export DATABASE_URL="postgresql://$DB_USER:$DB_PASS@db.example.com/myapp"
        curl -H "Authorization: Bearer $API_TOKEN" \
             --cert $SSL_CERT_FILE \
             https://api.example.com/data
    '''
}
```

### Important security note

```groovy
// Jenkins masks credential values in console output
// These will show as **** in the logs:
sh 'echo $DB_PASS'          // prints ****
echo "Password: ${DB_PASS}" // prints Password: ****

// BUT — don't explicitly expose them:
sh "echo ${DB_PASS}"        // DANGEROUS — Groovy resolves before Jenkins masks
// Use environment variable form: sh 'echo $DB_PASS' (single quotes)
```

---

## 5. Credentials in environment {} Block

Credentials can be bound in the `environment` block for pipeline-wide access.

```groovy
pipeline {
    environment {
        // Bind credentials in environment block
        REGISTRY_CREDENTIALS = credentials('registry-creds')
        // Creates:
        //   REGISTRY_CREDENTIALS_USR = username
        //   REGISTRY_CREDENTIALS_PSW = password

        AWS_ACCESS_KEY_ID     = credentials('aws-access-key-id')
        AWS_SECRET_ACCESS_KEY = credentials('aws-secret-access-key')

        // String secret
        SLACK_WEBHOOK = credentials('slack-webhook-url')
    }

    stages {
        stage('Build') {
            steps {
                sh '''
                    docker login -u $REGISTRY_CREDENTIALS_USR \
                                 -p $REGISTRY_CREDENTIALS_PSW \
                                 registry.example.com
                '''
            }
        }
        stage('Notify') {
            steps {
                sh 'curl -X POST $SLACK_WEBHOOK -d \'{"text":"Build done"}\''
            }
        }
    }
}
```

---

## 6. HashiCorp Vault Integration

Jenkins can fetch secrets dynamically from Vault at build time. Requires the HashiCorp Vault plugin.

### Configuration (JCasC)

```yaml
# jenkins.yaml
credentials:
  system:
    domainCredentials:
      - credentials:
          - vaultTokenCredential:
              id: "vault-token"
              token: "{AES256:...}"   # encrypted
              description: "Vault root token"

unclassified:
  hashicorpVault:
    configuration:
      vaultUrl: "https://vault.example.com"
      vaultCredentialId: "vault-token"
      engineVersion: 2
```

### Using Vault in Jenkinsfile

```groovy
pipeline {
    agent any
    stages {
        stage('Deploy') {
            steps {
                withVault(configuration: [
                    vaultUrl: 'https://vault.example.com',
                    vaultCredentialId: 'vault-token',
                    engineVersion: 2
                ], vaultSecrets: [
                    [
                        path: 'secret/data/production/database',
                        secretValues: [
                            [envVar: 'DB_PASSWORD', vaultKey: 'password'],
                            [envVar: 'DB_USERNAME', vaultKey: 'username']
                        ]
                    ],
                    [
                        path: 'secret/data/production/api',
                        secretValues: [
                            [envVar: 'API_KEY', vaultKey: 'key']
                        ]
                    ]
                ]) {
                    sh './deploy.sh'
                }
            }
        }
    }
}
```

### Vault with AppRole authentication (production pattern)

```groovy
// Use AppRole instead of root token
withVault(configuration: [
    vaultUrl: 'https://vault.example.com',
    vaultCredentialId: 'vault-approle',   // AppRole credential
    engineVersion: 2
], vaultSecrets: [...]) {
    sh './deploy.sh'
}
```

---

## 7. AWS Credentials & OIDC

### Static credentials (avoid in production)

```groovy
// Store as Username/Password credential:
// Username = AWS Access Key ID
// Password = AWS Secret Access Key

withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
    credentialsId: 'aws-credentials',
    accessKeyVariable: 'AWS_ACCESS_KEY_ID',
    secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
]]) {
    sh 'aws s3 ls'
}
```

### IAM role (EC2/EKS — best for cloud-hosted Jenkins)

```groovy
// If Jenkins runs on EC2 with an IAM instance role:
// No credentials needed! AWS SDK auto-picks up the role

stage('Deploy to AWS') {
    agent { label 'aws-agent' }    // agent with IAM role
    steps {
        sh 'aws s3 sync dist/ s3://my-bucket/'  // just works
    }
}
```

### OIDC with AWS (keyless, most secure)

```groovy
// Requires: jenkins-oidc-plugin or custom OIDC flow
// Generate a short-lived token and exchange for AWS credentials

stage('AWS Deploy') {
    steps {
        script {
            // Exchange Jenkins identity token for AWS credentials
            def creds = sh(
                script: '''
                    TOKEN=$(cat /var/run/secrets/jenkins/token)
                    aws sts assume-role-with-web-identity \
                        --role-arn arn:aws:iam::123456789:role/jenkins-deploy \
                        --role-session-name jenkins-$BUILD_NUMBER \
                        --web-identity-token $TOKEN \
                        --duration-seconds 3600
                ''',
                returnStdout: true
            )
            def json = readJSON text: creds
            env.AWS_ACCESS_KEY_ID = json.Credentials.AccessKeyId
            env.AWS_SECRET_ACCESS_KEY = json.Credentials.SecretAccessKey
            env.AWS_SESSION_TOKEN = json.Credentials.SessionToken
        }
        sh 'aws s3 sync dist/ s3://my-bucket/'
    }
}
```

---

## 8. Security Best Practices

```
DO:
✅ Use credential IDs (never hardcode values)
✅ Use withCredentials block — Jenkins masks values in logs
✅ Use single quotes around shell commands with secrets ('$VAR' not "$VAR")
✅ Use IAM roles for Jenkins on EC2/Kubernetes (no static keys)
✅ Use Vault for dynamic, short-lived secrets
✅ Scope credentials to folders (not global) when possible
✅ Rotate credentials regularly
✅ Audit credential usage (Jenkins logs who accessed what)
✅ Use protected credentials (not readable by jobs from forks)

DON'T:
❌ Hardcode passwords in Jenkinsfile (it's in source control!)
❌ echo/print credential values in build logs
❌ Use "$CRED_VAR" in shell (double quotes — Groovy resolves first)
❌ Store .env files with secrets in the workspace
❌ Use root/admin credentials for CI — use dedicated CI service accounts
❌ Give CI credentials more permissions than needed

# Check for leaked secrets in build logs:
# If you see a real password in console output → rotate it immediately
```

---

## Cheatsheet

```groovy
// Environment block
environment {
    MY_VAR = 'value'
    CRED_USER = credentials('my-creds')  // creates CRED_USER_USR + CRED_USER_PSW
}

// withCredentials
withCredentials([
    usernamePassword(credentialsId: 'id', usernameVariable: 'USR', passwordVariable: 'PWD'),
    string(credentialsId: 'token-id', variable: 'TOKEN'),
    file(credentialsId: 'file-id', variable: 'MY_FILE'),
    sshUserPrivateKey(credentialsId: 'ssh-id', keyFileVariable: 'SSH_KEY')
]) {
    sh 'use $USR and $PWD'  // single quotes! never double quotes with secrets
}

// Built-in vars
env.BUILD_NUMBER
env.GIT_COMMIT
env.BRANCH_NAME    // multibranch only
env.JOB_NAME
env.WORKSPACE
env.BUILD_URL

// Set dynamically
script {
    env.MY_VAR = sh(script: 'date +%Y%m%d', returnStdout: true).trim()
}
```

---

*Next: [Pipeline Patterns →](./06-pipeline-patterns.md)*
