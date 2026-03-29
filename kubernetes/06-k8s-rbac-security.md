# 🔐 RBAC & Security

Roles, ServiceAccounts, Pod Security, and hardening your Kubernetes cluster.

---

## 📚 Table of Contents

- [1. RBAC Overview](#1-rbac-overview)
- [2. Roles & ClusterRoles](#2-roles--clusterroles)
- [3. RoleBindings & ClusterRoleBindings](#3-rolebindings--clusterrolebindings)
- [4. ServiceAccounts](#4-serviceaccounts)
- [5. Pod Security](#5-pod-security)
- [6. Security Contexts](#6-security-contexts)
- [7. Admission Controllers](#7-admission-controllers)
- [8. Security Best Practices](#8-security-best-practices)
- [Cheatsheet](#cheatsheet)

---

## 1. RBAC Overview

RBAC (Role-Based Access Control) controls **who can do what** in the cluster.

```
Subject (who)       Verb (what action)     Resource (on what)
─────────────       ──────────────────     ───────────────────
User/Group          get, list, watch       pods
ServiceAccount      create, update         deployments
                    delete, patch          secrets
                    exec                   configmaps
```

### RBAC objects

```
Role            → rules in a namespace
ClusterRole     → rules cluster-wide (or for non-namespaced resources)
RoleBinding     → binds Role/ClusterRole to subject in a namespace
ClusterRoleBinding → binds ClusterRole to subject cluster-wide
```

```
Subject (User/Group/ServiceAccount)
        │
        │  bound by
        ▼
RoleBinding or ClusterRoleBinding
        │
        │  references
        ▼
Role or ClusterRole
        │
        │  contains
        ▼
Rules (apiGroups + resources + verbs)
```

---

## 2. Roles & ClusterRoles

### Role (namespaced)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: production
rules:
  - apiGroups: [""]                    # "" = core API group
    resources: ["pods", "pods/log"]
    verbs: ["get", "list", "watch"]

  - apiGroups: ["apps"]
    resources: ["deployments"]
    verbs: ["get", "list", "watch", "update", "patch"]

  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["app-secret"]      # restrict to specific secret
    verbs: ["get"]
```

### ClusterRole (cluster-wide)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: node-viewer
rules:
  - apiGroups: [""]
    resources: ["nodes"]               # nodes are cluster-scoped
    verbs: ["get", "list", "watch"]

  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list"]

  - apiGroups: ["metrics.k8s.io"]
    resources: ["nodes", "pods"]
    verbs: ["get", "list"]
```

### Common verbs

| Verb | HTTP | What it does |
|------|------|-------------|
| `get` | GET | Read a specific resource |
| `list` | GET | List all resources of a type |
| `watch` | GET+watch | Stream changes to resources |
| `create` | POST | Create a new resource |
| `update` | PUT | Replace a resource |
| `patch` | PATCH | Partially update a resource |
| `delete` | DELETE | Delete a resource |
| `deletecollection` | DELETE | Delete multiple resources |
| `exec` | POST | Execute command in pod |
| `proxy` | * | Proxy to pod/service |

### Common API groups

| API group | Resources |
|-----------|----------|
| `""` (core) | pods, services, configmaps, secrets, nodes, namespaces |
| `apps` | deployments, statefulsets, daemonsets, replicasets |
| `batch` | jobs, cronjobs |
| `networking.k8s.io` | ingresses, networkpolicies |
| `rbac.authorization.k8s.io` | roles, rolebindings, clusterroles |
| `storage.k8s.io` | storageclasses, persistentvolumes |
| `metrics.k8s.io` | pod and node metrics |

---

## 3. RoleBindings & ClusterRoleBindings

### RoleBinding (namespaced)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: production
subjects:
  # User
  - kind: User
    name: fasih
    apiGroup: rbac.authorization.k8s.io

  # Group
  - kind: Group
    name: developers
    apiGroup: rbac.authorization.k8s.io

  # ServiceAccount
  - kind: ServiceAccount
    name: my-app
    namespace: production            # must specify namespace for SA

roleRef:
  kind: Role                         # or ClusterRole
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### ClusterRoleBinding (cluster-wide)

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cluster-admins
subjects:
  - kind: Group
    name: platform-team
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin               # built-in superuser role
  apiGroup: rbac.authorization.k8s.io
```

### Use ClusterRole with RoleBinding (common pattern)

```yaml
# ClusterRole defines the rules (reusable)
# RoleBinding scopes it to a specific namespace

# Grant "pod-reader" ClusterRole only in "production" namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods-in-prod
  namespace: production              # scoped to this namespace
subjects:
  - kind: User
    name: fasih
roleRef:
  kind: ClusterRole                  # referencing a ClusterRole
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### Built-in ClusterRoles

| ClusterRole | Access |
|------------|--------|
| `cluster-admin` | Full superuser access |
| `admin` | Full namespace admin (no node/namespace management) |
| `edit` | Read/write most namespace resources (no RBAC changes) |
| `view` | Read-only access to most namespace resources |

### Check permissions

```bash
# Can I do this?
kubectl auth can-i get pods
kubectl auth can-i create deployments -n production
kubectl auth can-i delete secrets --as=system:serviceaccount:production:my-app

# What can this user do?
kubectl auth can-i --list --as=fasih
kubectl auth can-i --list --as=system:serviceaccount:production:my-app -n production

# List all roles and bindings
kubectl get roles -A
kubectl get rolebindings -A
kubectl get clusterroles
kubectl get clusterrolebindings
```

---

## 4. ServiceAccounts

Every pod runs as a ServiceAccount. It's the identity pods use to authenticate to the Kubernetes API.

### Default ServiceAccount

```yaml
# Every namespace has a "default" ServiceAccount
# Pods use it automatically if none is specified
# The default SA has minimal permissions by default (should stay that way)
```

### Create a custom ServiceAccount

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: my-app
  namespace: production
  annotations:
    # For AWS IRSA (IAM Roles for Service Accounts)
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/my-app-role
```

### Bind ServiceAccount to a Role

```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: my-app-role-binding
  namespace: production
subjects:
  - kind: ServiceAccount
    name: my-app
    namespace: production
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io
```

### Use ServiceAccount in a pod

```yaml
spec:
  serviceAccountName: my-app          # use custom SA
  automountServiceAccountToken: false # don't mount SA token if not needed
  containers:
    - name: app
      ...
```

### ServiceAccount token

The SA token is automatically mounted at:
```
/var/run/secrets/kubernetes.io/serviceaccount/token
```

Used to authenticate API calls from within the pod:

```bash
# From inside a pod
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -sk https://kubernetes.default.svc/api/v1/namespaces/production/pods \
  -H "Authorization: Bearer $TOKEN"
```

### IRSA — IAM Roles for Service Accounts (AWS EKS)

Allows pods to assume AWS IAM roles without access keys:

### 🔹 How it works

1. **Create an IAM role in AWS** with the permissions you want your pod to have.  *Example:* S3 read/write access, DynamoDB access, etc.
2. **Associate the IAM role with a Kubernetes service account** using an OIDC identity provider (EKS clusters create this automatically).
3. **Pods use this service account**, which allows them to assume the IAM role.
4. **Pod automatically gets short-lived AWS credentials** via the role.
5. **Application inside the pod can call AWS APIs** without any static keys.

### 🔹 Flow Summary

- **Pod** → uses service account  
- **Kubernetes** → generates a JWT token for the service account  
- **AWS IAM** → validates the JWT via the OIDC provider  
- **AWS IAM** → issues temporary credentials for the IAM role  
- **Pod** → can now call AWS APIs without static keys

OIDC (OpenID Connect) is used to verify the identity of a Kubernetes Service Account so that AWS can trust it.  
👉 Then IRSA uses OIDC to allow pods to assume IAM roles without access keys.

```yaml
# 1. Annotate ServiceAccount with IAM role ARN
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-access
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/my-s3-reader

# 2. Pod using this SA automatically gets AWS credentials
spec:
  serviceAccountName: s3-access
  # AWS SDK in container automatically uses the projected token
```

---

## 5. Pod Security

### Pod Security Admission (PSA) — Kubernetes 1.25+

PSA enforces security standards at the namespace level using labels:

```yaml
# Label a namespace to enforce security standards
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    # Enforce: reject non-compliant pods
    pod-security.kubernetes.io/enforce: restricted
    # Audit: log non-compliant pods (don't reject)
    pod-security.kubernetes.io/audit: restricted
    # Warn: warn on non-compliant pods
    pod-security.kubernetes.io/warn: restricted
```

### Security standards

| Level | Description | Use for |
|-------|-------------|---------|
| `privileged` | No restrictions | System namespaces (kube-system) |
| `baseline` | Minimal restrictions, prevents privilege escalation | Most workloads |
| `restricted` | Heavily restricted, current best practices | High-security workloads |

### What "restricted" requires

```yaml
spec:
  securityContext:
    runAsNonRoot: true
    seccompProfile:
      type: RuntimeDefault
  containers:
    - securityContext:
        allowPrivilegeEscalation: false
        capabilities:
          drop: [ALL]
        readOnlyRootFilesystem: true
        runAsNonRoot: true
```

---

## 6. Security Contexts

Security contexts define privilege and access control settings for pods and containers.

### Pod-level security context

```yaml
spec:
  securityContext:
    runAsUser: 1000                # run as UID 1000
    runAsGroup: 3000               # run as GID 3000
    fsGroup: 2000                  # volume files owned by this GID
    runAsNonRoot: true             # refuse to run as root
    seccompProfile:
      type: RuntimeDefault         # use container runtime's seccomp profile
    sysctls:
      - name: net.core.somaxconn
        value: "1024"
```

### Container-level security context

```yaml
containers:
  - name: app
    securityContext:
      allowPrivilegeEscalation: false    # can't gain more privileges than parent
      privileged: false                  # no privileged container
      readOnlyRootFilesystem: true       # root filesystem is read-only
      runAsNonRoot: true
      runAsUser: 1000
      capabilities:
        drop:
          - ALL                          # drop all Linux capabilities
        add:
          - NET_BIND_SERVICE             # add only what's needed (bind port < 1024)
```

### Common security context patterns

```yaml
# Minimal permissions — good default for web apps
securityContext:
  runAsNonRoot: true
  runAsUser: 1000
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities:
    drop: [ALL]

# Needs to write to filesystem — use emptyDir for writable dirs
volumeMounts:
  - name: tmp
    mountPath: /tmp
  - name: cache
    mountPath: /app/cache
volumes:
  - name: tmp
    emptyDir: {}
  - name: cache
    emptyDir: {}
```

---

## 7. Admission Controllers

Admission controllers intercept requests to the API server before objects are persisted.

### Built-in admission controllers

| Controller | What it does |
|-----------|-------------|
| `NamespaceLifecycle` | Prevents creating resources in terminating namespaces |
| `LimitRanger` | Enforces LimitRange in namespaces |
| `ResourceQuota` | Enforces ResourceQuota |
| `PodSecurity` | Enforces Pod Security Standards |
| `ServiceAccount` | Automates ServiceAccount management |
| `NodeRestriction` | Limits what kubelets can modify |

### Webhook admission controllers

```yaml
# ValidatingWebhookConfiguration — validate objects
apiVersion: admissionregistration.k8s.io/v1
kind: ValidatingWebhookConfiguration
metadata:
  name: image-policy
webhooks:
  - name: image-policy.example.com
    rules:
      - apiGroups: [""]
        apiVersions: ["v1"]
        operations: ["CREATE"]
        resources: ["pods"]
    clientConfig:
      service:
        name: image-policy-webhook
        namespace: kube-system
        path: /validate
    admissionReviewVersions: ["v1"]
    sideEffects: None
```

---

## 8. Security Best Practices

```yaml
# 1. Always set resource limits
resources:
  requests:
    cpu: "100m"
    memory: "128Mi"
  limits:
    cpu: "500m"
    memory: "256Mi"

# 2. Run as non-root
securityContext:
  runAsNonRoot: true
  runAsUser: 1000

# 3. Drop all capabilities
securityContext:
  capabilities:
    drop: [ALL]
  allowPrivilegeEscalation: false

# 4. Read-only filesystem
securityContext:
  readOnlyRootFilesystem: true

# 5. Don't mount SA token if not needed
spec:
  automountServiceAccountToken: false

# 6. Use specific image tags (not latest)
image: nginx:1.24.0    # not nginx:latest

# 7. Scan images for vulnerabilities
# Tools: Trivy, Snyk, Grype

# 8. Use Network Policies to restrict traffic
# Default deny all, explicitly allow what's needed

# 9. Enable audit logging on API server
# 10. Use Pod Security Standards (restricted for prod)
```

---

## Cheatsheet

```bash
# Check permissions
kubectl auth can-i get pods -n production
kubectl auth can-i --list --as=system:serviceaccount:production:my-app

# RBAC objects
kubectl get roles -A
kubectl get rolebindings -A
kubectl get clusterroles | grep -v system:
kubectl get clusterrolebindings | grep -v system:

# ServiceAccounts
kubectl get serviceaccounts -A
kubectl describe serviceaccount my-app -n production

# Describe why a pod is rejected (PSA)
kubectl describe pod my-pod
# Look for: "forbidden: violates PodSecurity"
```

```yaml
# Minimal secure pod template
spec:
  serviceAccountName: my-app
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    fsGroup: 2000
    seccompProfile:
      type: RuntimeDefault
  containers:
    - name: app
      image: myapp:v1.2.3
      securityContext:
        allowPrivilegeEscalation: false
        readOnlyRootFilesystem: true
        capabilities:
          drop: [ALL]
```

---

*Next: [Helm →](./07-helm.md) — package management for Kubernetes.*
