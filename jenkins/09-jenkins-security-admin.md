# 🛡️ Security & Administration

RBAC, hardening, Configuration as Code, backup, and keeping Jenkins healthy.

---

## 📚 Table of Contents

- [1. Authentication & Authorization](#1-authentication--authorization)
- [2. Role-Based Access Control (RBAC)](#2-role-based-access-control-rbac)
- [3. Security Hardening](#3-security-hardening)
- [4. Configuration as Code (JCasC)](#4-configuration-as-code-jcasc)
- [5. Backup & Recovery](#5-backup--recovery)
- [6. Plugin Management](#6-plugin-management)
- [7. Monitoring & Maintenance](#7-monitoring--maintenance)
- [8. Upgrade Strategy](#8-upgrade-strategy)
- [Cheatsheet](#cheatsheet)

---

## 1. Authentication & Authorization

### Authentication options

| Method | Use case |
|--------|---------|
| **Jenkins internal database** | Small teams, development |
| **LDAP / Active Directory** | Enterprise (most common) |
| **SAML 2.0** | SSO with Okta, Azure AD, etc. |
| **GitHub OAuth** | Teams using GitHub |
| **GitLab OAuth** | Teams using GitLab |
| **Matrix Authorization** | Fine-grained per-user/group |

### LDAP configuration (JCasC)

```yaml
# jenkins.yaml
jenkins:
  securityRealm:
    ldap:
      configurations:
        - server: "ldap://ldap.company.com:389"
          rootDN: "dc=company,dc=com"
          userSearchBase: "ou=users"
          userSearch: "uid={0}"
          groupSearchBase: "ou=groups"
          groupMembershipStrategy:
            fromGroupSearch:
              filter: "member={0},ou=users,dc=company,dc=com"
          managerDN: "cn=jenkins,dc=company,dc=com"
          managerPasswordSecret: "{AES256:...}"
```

### GitHub OAuth (JCasC)

```yaml
jenkins:
  securityRealm:
    github:
      githubWebUri: "https://github.com"
      githubApiUri: "https://api.github.com"
      clientID: "${GITHUB_CLIENT_ID}"
      clientSecret: "${GITHUB_CLIENT_SECRET}"
      oauthScopes: "read:org"
```

---

## 2. Role-Based Access Control (RBAC)

Use the **Role-based Authorization Strategy** plugin.

### Role types

| Role type | Scope |
|-----------|-------|
| **Global roles** | Apply to all Jenkins |
| **Item roles** | Apply to specific jobs/folders (regex match) |
| **Agent roles** | Apply to specific agents |

### JCasC RBAC configuration

```yaml
jenkins:
  authorizationStrategy:
    roleBased:
      roles:
        global:
          - name: "admin"
            description: "Full access"
            permissions:
              - "Overall/Administer"
            assignments:
              - "admin-user"
              - "devops-team"    # LDAP group

          - name: "developer"
            description: "Build and view jobs"
            permissions:
              - "Overall/Read"
              - "Job/Build"
              - "Job/Read"
              - "Job/Cancel"
              - "View/Read"
            assignments:
              - "developers"    # LDAP group

          - name: "viewer"
            description: "Read-only access"
            permissions:
              - "Overall/Read"
              - "Job/Read"
              - "View/Read"
            assignments:
              - "all-users"

        items:
          - name: "frontend-team"
            description: "Frontend team jobs"
            pattern: "Frontend/.*"    # regex matching job paths
            permissions:
              - "Job/Build"
              - "Job/Configure"
              - "Job/Read"
              - "Job/Workspace"
              - "Run/Update"
            assignments:
              - "frontend-developers"

          - name: "ops-deploy"
            description: "Ops team production deploys"
            pattern: ".*/deploy-production"
            permissions:
              - "Job/Build"
              - "Job/Read"
            assignments:
              - "ops-team"
```

### Matrix Authorization (simpler alternative)

```yaml
jenkins:
  authorizationStrategy:
    projectMatrix:
      permissions:
        - "Overall/Administer:admin"
        - "Overall/Read:authenticated"    # all logged-in users
        - "Job/Read:authenticated"
        - "Job/Build:developers"
        - "Job/Configure:admins"
```

---

## 3. Security Hardening

### Checklist

```
✅ Disable agent-to-controller security (check: Manage Jenkins → Security → Agent Protection)
✅ Enable CSRF protection
✅ Disable old/unused agents
✅ Use HTTPS only (redirect HTTP to HTTPS)
✅ Set controller executors to 0 (no builds on controller)
✅ Enable audit logging
✅ Regular security updates
✅ Restrict script approvals (Groovy sandbox)
✅ Limit job workspace access
✅ Use credentials instead of hardcoded values
✅ Enable content security policy headers
```

### CSRF protection (JCasC)

```yaml
jenkins:
  crumbIssuer:
    standard:
      excludeClientIPFromCrumb: false
```

### Content Security Policy

```groovy
// Configure in Jenkins startup options or via JCasC
// System.setProperty("hudson.model.DirectoryBrowserSupport.CSP", "default-src 'self'")
```

### Groovy script approval

```
When a Jenkinsfile uses methods not in the sandbox:
  "Scripts not permitted to use method X" error appears

Manage Jenkins → In-process Script Approval:
  Review and approve signatures carefully
  Only approve signatures you understand
```

### Disable agent protocols

```yaml
# Keep only modern protocols
jenkins:
  agentProtocols:
    - "JNLP4-connect"    # keep
    - "Ping"             # keep
    # Remove: JNLP, JNLP2, JNLP3-connect (older, less secure)
```

---

## 4. Configuration as Code (JCasC)

JCasC lets you version-control your entire Jenkins configuration as YAML.

### Install JCasC plugin

```
Jenkins → Manage Plugins → Available → Configuration as Code
```

### Complete JCasC example

```yaml
# jenkins.yaml
jenkins:
  systemMessage: "Production Jenkins CI/CD"
  numExecutors: 0    # No builds on controller

  # Authentication
  securityRealm:
    ldap:
      configurations:
        - server: "ldap://ldap.company.com"
          rootDN: "dc=company,dc=com"
          userSearchBase: "ou=users"

  # Authorization
  authorizationStrategy:
    roleBased:
      roles:
        global:
          - name: admin
            permissions: ["Overall/Administer"]
            assignments: ["admin-group"]

  # Global properties
  globalNodeProperties:
    - envVars:
        env:
          - key: DOCKER_REGISTRY
            value: registry.example.com
          - key: COMPANY_DOMAIN
            value: example.com

  # Clouds (Kubernetes)
  clouds:
    - kubernetes:
        name: kubernetes
        namespace: jenkins
        jenkinsUrl: http://jenkins.jenkins.svc.cluster.local:8080

  # Credentials
credentials:
  system:
    domainCredentials:
      - credentials:
          - usernamePassword:
              id: "registry-credentials"
              username: "ci-user"
              password: "${REGISTRY_PASSWORD}"
              description: "Docker registry"
          - string:
              id: "slack-token"
              secret: "${SLACK_BOT_TOKEN}"
              description: "Slack notification token"

# Unclassified settings
unclassified:
  slackNotifier:
    teamDomain: mycompany
    tokenCredentialId: slack-token
    room: "#jenkins"

  gitLabConnectionConfig:
    connections:
      - name: "GitLab"
        gitLabHostUrl: "https://gitlab.example.com"
        apiTokenId: "gitlab-api-token"
        clientBuilderId: "autodetect"

  timestamper:
    allPipelines: true
    systemTimeFormat: "HH:mm:ss"
    elapsedTimeFormat: "''HH:mm:ss.S''"
```

### Apply JCasC

```bash
# JCasC is loaded from:
# 1. $JENKINS_HOME/casc.yaml
# 2. Path in CASC_JENKINS_CONFIG environment variable
# 3. URL (http/https/file) in CASC_JENKINS_CONFIG

# When on Kubernetes (Helm):
helm install jenkins jenkins/jenkins \
  --set controller.JCasC.configScripts.my-config="$(cat jenkins.yaml)"

# Reload without restart:
# Jenkins → Manage Jenkins → Configuration as Code → Reload existing configuration
```

---

## 5. Backup & Recovery

### What to backup

```
$JENKINS_HOME/
├── config.xml                 ← Global Jenkins config
├── credentials.xml            ← Encrypted credentials
├── plugins/                   ← Installed plugins
├── jobs/                      ← Job configurations and build history
│   └── my-job/
│       ├── config.xml         ← Job config
│       └── builds/            ← Build logs and artifacts
├── nodes/                     ← Agent configurations
├── users/                     ← User accounts
└── secrets/                   ← Encryption keys (CRITICAL — protect this)
```

### Backup script

```bash
#!/bin/bash
# backup-jenkins.sh
JENKINS_HOME=/var/jenkins_home
BACKUP_DIR=/backup/jenkins
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/jenkins-backup-${DATE}.tar.gz"

mkdir -p $BACKUP_DIR

# Create backup (exclude large/regeneratable data)
tar czf $BACKUP_FILE \
  --exclude="${JENKINS_HOME}/workspace" \
  --exclude="${JENKINS_HOME}/jobs/*/builds/*/archive" \
  --exclude="${JENKINS_HOME}/.m2" \
  $JENKINS_HOME

echo "Backup created: $BACKUP_FILE"

# Upload to S3
aws s3 cp $BACKUP_FILE s3://my-jenkins-backups/

# Keep only last 7 days
find $BACKUP_DIR -name "*.tar.gz" -mtime +7 -delete

echo "Backup complete"
```

### Backup with Kubernetes

```bash
# Backup PVC
kubectl exec -n jenkins jenkins-0 -- \
  tar czf - /var/jenkins_home \
  | gzip > jenkins-backup-$(date +%Y%m%d).tar.gz

# Upload to S3
aws s3 cp jenkins-backup-$(date +%Y%m%d).tar.gz \
  s3://my-jenkins-backups/

# ThinBackup plugin (automated, UI-based)
# Manages incremental backups, keeps N copies
```

### Disaster recovery

```bash
# Restore from backup
kubectl cp jenkins-backup.tar.gz jenkins/jenkins-0:/tmp/
kubectl exec -n jenkins jenkins-0 -- \
  tar xzf /tmp/jenkins-backup.tar.gz -C /

# Restart Jenkins
kubectl rollout restart deployment/jenkins -n jenkins
```

---

## 6. Plugin Management

### Pin plugin versions (reproducible Jenkins)

```
# plugins.txt — checked into source control
kubernetes:3987.v1d8f80e6f279
workflow-aggregator:596.v8c21c963d92d
git:5.1.0
blueocean:1.27.9
configuration-as-code:1670.v564dc8b_982d0
```

```bash
# Install plugins from file (jenkins-plugin-cli)
docker run --rm \
  -v plugins.txt:/usr/share/jenkins/ref/plugins.txt \
  jenkins/jenkins:lts \
  jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt

# Or in custom Docker image:
FROM jenkins/jenkins:lts-jdk17
COPY plugins.txt /usr/share/jenkins/ref/plugins.txt
RUN jenkins-plugin-cli --plugin-file /usr/share/jenkins/ref/plugins.txt
```

---

## 7. Monitoring & Maintenance

### Prometheus metrics

```yaml
# Install Prometheus plugin
# Exposes metrics at: /prometheus
# Configure in Prometheus:
scrape_configs:
  - job_name: 'jenkins'
    metrics_path: '/prometheus'
    static_configs:
      - targets: ['jenkins.jenkins.svc.cluster.local:8080']
```

### Key metrics to monitor

```promql
# Build queue length (are builds piling up?)
jenkins_queue_size_value

# Active executors
jenkins_executors_in_use_value

# Build duration
jenkins_builds_duration_milliseconds_summary

# Build results
jenkins_builds_last_build_result_ordinal

# Disk usage
jenkins_disk_usage_bytes

# Failed builds in last hour
increase(jenkins_builds_failed_build_count_total[1h])
```

### Workspace cleanup

```groovy
// In pipeline — clean workspace after each build
post {
    always {
        cleanWs(cleanWhenNotBuilt: false,
                deleteDirs: true,
                disableDeferredWipeout: true,
                notFailBuild: true)
    }
}

// Workspace Cleanup plugin: periodic cleanup of old workspaces
// Jenkins → Manage Jenkins → System → Workspace Cleanup
```

---

## 8. Upgrade Strategy

```
Upgrade process (follow for each version bump):

1. Review release notes and changelogs
   https://www.jenkins.io/changelog/

2. Check plugin compatibility
   Review: Manage Plugins → Check compatibility

3. Test in non-production Jenkins first
   - Spin up identical Jenkins instance
   - Apply upgrade
   - Test all critical pipelines

4. Backup production Jenkins (before upgrading)
   ./backup-jenkins.sh

5. Upgrade controller
   # Docker:
   docker pull jenkins/jenkins:lts-jdk17
   docker restart jenkins

   # Kubernetes:
   helm upgrade jenkins jenkins/jenkins \
     --set controller.tag=lts-jdk17-2023-11

6. Verify after upgrade
   - Check all agents connect
   - Run test pipelines
   - Check critical jobs

7. Update plugins (separately from controller upgrade)
   Manage Jenkins → Plugins → Updates → Select all → Update
   Restart Jenkins after plugin updates
```

---

## Cheatsheet

```bash
# Restart Jenkins (graceful)
curl -X POST https://jenkins.example.com/safeRestart \
  --user admin:api-token

# Reload JCasC
curl -X POST https://jenkins.example.com/configuration-as-code/reload \
  --user admin:api-token

# Get plugin list
curl https://jenkins.example.com/pluginManager/api/json?depth=1 \
  --user admin:api-token \
  | jq '.plugins[] | "\(.shortName):\(.version)"' -r > plugins.txt

# List all jobs
curl https://jenkins.example.com/api/json?tree=jobs[name] \
  --user admin:api-token

# Trigger build via API
curl -X POST https://jenkins.example.com/job/my-job/build \
  --user admin:api-token

# Check build queue
curl https://jenkins.example.com/queue/api/json \
  --user admin:api-token
```

---

*Next: [Interview Q&A →](./10-interview-qa.md)*
