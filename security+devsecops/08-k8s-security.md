# Kubernetes Security

## The K8s Security Challenge

Kubernetes is powerful but has a large attack surface by default:
- API server accessible from anywhere without extra config
- Permissive RBAC defaults
- No network policies → pods can reach anything
- Containers run as root if not configured otherwise
- Secrets stored as base64 (not encrypted) by default

The **4 C's of Cloud-Native Security** (from CNCF):

```
Cloud → Cluster → Container → Code

Each layer must be secured independently.
Outer layer breach doesn't automatically compromise inner layers.
```

## RBAC — Role-Based Access Control

RBAC controls who can do what to which resources in Kubernetes.

```
Subject     Verb        Resource
(who)       (can do)    (to what)
user        get         pods
group       list        deployments
service     create      configmaps
account     delete      secrets
```

### RBAC Objects

```yaml
# Role — scoped to a namespace
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: pod-reader
  namespace: production
rules:
- apiGroups: [""]        # "" = core API group
  resources: ["pods", "pods/log"]
  verbs: ["get", "list", "watch"]

---
# ClusterRole — cluster-wide
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: deployment-manager
rules:
- apiGroups: ["apps"]
  resources: ["deployments", "replicasets"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["get", "list", "watch"]

---
# RoleBinding — binds a Role to a Subject
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: read-pods
  namespace: production
subjects:
- kind: ServiceAccount
  name: monitoring-sa
  namespace: production
- kind: User
  name: jane@example.com
  apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: Role
  name: pod-reader
  apiGroup: rbac.authorization.k8s.io

---
# ClusterRoleBinding — binds ClusterRole cluster-wide
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-deployment
subjects:
- kind: ServiceAccount
  name: argocd-application-controller
  namespace: argocd
roleRef:
  kind: ClusterRole
  name: deployment-manager
  apiGroup: rbac.authorization.k8s.io
```

### Service Accounts

```yaml
# Create a dedicated service account (don't use default)
apiVersion: v1
kind: ServiceAccount
metadata:
  name: myapp-sa
  namespace: production
automountServiceAccountToken: false  # opt-in only when needed

---
# Deployment using the service account
apiVersion: apps/v1
kind: Deployment
spec:
  template:
    spec:
      serviceAccountName: myapp-sa
      automountServiceAccountToken: false  # double opt-out
```

### RBAC Audit Commands

```bash
# Check what a user/SA can do
kubectl auth can-i list pods --as=jane@example.com
kubectl auth can-i create deployments --as=system:serviceaccount:production:myapp-sa

# List all permissions for a role
kubectl describe role pod-reader -n production
kubectl describe clusterrole deployment-manager

# Find all role bindings for a service account
kubectl get rolebindings,clusterrolebindings -A \
  -o jsonpath='{range .items[?(@.subjects[].name=="myapp-sa")]}{.metadata.name}{"\n"}{end}'

# Use rbac-lookup (external tool)
kubectl rbac-lookup myapp-sa -k serviceaccount -n production
```

## Pod Security

### Security Context

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: myapp
spec:
  template:
    spec:
      # Pod-level security context
      securityContext:
        runAsNonRoot: true
        runAsUser: 10001
        runAsGroup: 10001
        fsGroup: 10001
        seccompProfile:
          type: RuntimeDefault    # enable default seccomp profile

      containers:
      - name: app
        image: myapp:v1.0.0
        # Container-level security context
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 10001
          capabilities:
            drop: ["ALL"]          # drop all Linux capabilities
            add: ["NET_BIND_SERVICE"]  # only if needed

        # Always set resource limits
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 256Mi

        # Mount only what you need
        volumeMounts:
        - name: tmp
          mountPath: /tmp         # writable temp volume

      volumes:
      - name: tmp
        emptyDir: {}
```

### Pod Security Admission (PSA)

PSA replaced PodSecurityPolicies (PSP) in K8s 1.25+. Three levels:

| Level | What it allows |
|-------|---------------|
| **Privileged** | Everything (no restrictions) |
| **Baseline** | Minimum restrictions (prevents known privilege escalations) |
| **Restricted** | Strongest security (requires non-root, seccomp, no privilege escalation) |

```yaml
# Enforce restricted policy on a namespace
apiVersion: v1
kind: Namespace
metadata:
  name: production
  labels:
    pod-security.kubernetes.io/enforce: restricted
    pod-security.kubernetes.io/enforce-version: latest
    pod-security.kubernetes.io/warn: restricted
    pod-security.kubernetes.io/warn-version: latest
    pod-security.kubernetes.io/audit: restricted
    pod-security.kubernetes.io/audit-version: latest
```

## OPA Gatekeeper

OPA Gatekeeper enforces custom policies using Constraint Templates (Rego-based).

```bash
# Install Gatekeeper
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm install gatekeeper gatekeeper/gatekeeper \
  --namespace gatekeeper-system \
  --create-namespace
```

```yaml
# ConstraintTemplate — defines a reusable policy
apiVersion: templates.gatekeeper.sh/v1
kind: ConstraintTemplate
metadata:
  name: k8srequiredlabels
spec:
  crd:
    spec:
      names:
        kind: K8sRequiredLabels
      validation:
        openAPIV3Schema:
          type: object
          properties:
            labels:
              type: array
              items:
                type: string
  targets:
    - target: admission.k8s.gatekeeper.sh
      rego: |
        package k8srequiredlabels

        violation[{"msg": msg}] {
          provided := {label | input.review.object.metadata.labels[label]}
          required := {label | label := input.parameters.labels[_]}
          missing := required - provided
          count(missing) > 0
          msg := sprintf("Missing required labels: %v", [missing])
        }

---
# Constraint — instantiates the template with parameters
apiVersion: constraints.gatekeeper.sh/v1beta1
kind: K8sRequiredLabels
metadata:
  name: require-team-label
spec:
  match:
    kinds:
    - apiGroups: ["apps"]
      kinds: ["Deployment"]
    namespaces: ["production", "staging"]
  parameters:
    labels: ["team", "app", "version"]
```

## Kyverno (covered more in IaC security)

Kyverno also runs as an admission controller in the cluster:

```bash
# Install Kyverno
helm repo add kyverno https://kyverno.github.io/kyverno/
helm install kyverno kyverno/kyverno \
  --namespace kyverno \
  --create-namespace
```

```yaml
# Kyverno policy — disallow latest tag
apiVersion: kyverno.io/v1
kind: ClusterPolicy
metadata:
  name: disallow-latest-tag
spec:
  validationFailureAction: Enforce
  rules:
  - name: require-image-tag
    match:
      any:
      - resources:
          kinds: [Pod]
    validate:
      message: "An image tag is required and 'latest' is not allowed"
      pattern:
        spec:
          containers:
          - image: "!*:latest & *:*"  # must have tag, must not be latest
```

## Network Policies (Kubernetes)

By default, all pods can talk to all pods. Network Policies restrict this.

```yaml
# Deny all traffic by default
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress

---
# Allow only specific ingress to backend
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-ingress
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: ingress-nginx  # allow ingress controller
  policyTypes:
  - Ingress

---
# Allow egress only to database and DNS
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: backend-egress
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - port: 5432
  - to: []        # allow DNS
    ports:
    - port: 53
      protocol: UDP
    - port: 53
      protocol: TCP
  policyTypes:
  - Egress
```

## API Server Security

```yaml
# kube-apiserver flags (in kubeadm config)
apiServer:
  extraArgs:
    # Disable anonymous auth
    anonymous-auth: "false"

    # Enable audit logging
    audit-log-path: /var/log/kubernetes/audit.log
    audit-log-maxage: "30"
    audit-log-maxbackup: "3"
    audit-log-maxsize: "100"
    audit-policy-file: /etc/kubernetes/audit-policy.yaml

    # Disable insecure port
    insecure-port: "0"

    # Enable RBAC and NodeRestriction
    authorization-mode: "Node,RBAC"
    enable-admission-plugins: "NodeRestriction,PodSecurity"
```

Audit policy:
```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
# Log all changes to secrets at RequestResponse level
- level: RequestResponse
  resources:
  - group: ""
    resources: ["secrets"]

# Log all changes at Metadata level (less verbose)
- level: Metadata
  verbs: ["create", "update", "patch", "delete"]

# Don't log routine reads
- level: None
  verbs: ["get", "list", "watch"]
  resources:
  - group: ""
    resources: ["pods", "configmaps"]
```

## CIS Kubernetes Benchmark

CIS (Center for Internet Security) publishes hardening benchmarks for K8s.

Run kube-bench to check compliance:
```bash
# Run kube-bench in a pod
kubectl apply -f https://raw.githubusercontent.com/aquasecurity/kube-bench/main/job.yaml
kubectl logs job/kube-bench

# Specific component checks
kube-bench run --targets node
kube-bench run --targets master
kube-bench run --targets etcd
kube-bench run --targets policies
```

Key CIS checks:
- `1.2.1` — Ensure API server anonymous auth disabled
- `1.2.6` — Ensure --insecure-port is 0
- `1.2.14` — Ensure audit logging is enabled
- `4.1.1` — Ensure kubelet uses client certificates
- `5.1.1` — Ensure cluster-admin role only used where necessary
- `5.2.1` — Ensure privileged containers are not admitted

## Workload Identity (AWS + K8s)

Pods should not use long-lived AWS credentials. Use IAM Roles for Service Accounts (IRSA):

```yaml
# Service Account with IRSA annotation
apiVersion: v1
kind: ServiceAccount
metadata:
  name: s3-reader-sa
  namespace: production
  annotations:
    eks.amazonaws.com/role-arn: arn:aws:iam::123456789:role/S3ReaderRole

---
# Pod using the service account
apiVersion: v1
kind: Pod
spec:
  serviceAccountName: s3-reader-sa
  containers:
  - name: app
    image: myapp:v1
    # AWS SDK automatically picks up the OIDC token
    # No credentials needed in the container
```

For Azure (AKS) — Workload Identity:
```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: workload-identity-sa
  namespace: production
  annotations:
    azure.workload.identity/client-id: <managed-identity-client-id>
  labels:
    azure.workload.identity/use: "true"
```

## Falco for K8s Runtime (quick reference)

```bash
# Install with Helm
helm install falco falcosecurity/falco \
  --namespace falco --create-namespace \
  --set driver.kind=ebpf \
  --set falco.jsonOutput=true

# View alerts
kubectl logs -n falco -l app.kubernetes.io/name=falco --follow

# Common alerts to watch for:
# - "Terminal shell in container"       → interactive shell spawned
# - "Sensitive file opened for reading" → /etc/shadow, /etc/passwd read
# - "Write below binary dir"            → malware writing to /usr/bin
# - "Unexpected network connection"     → C2 callback attempt
```

## K8s Security Checklist

```
Cluster level:
☐ RBAC enabled (not ABAC)
☐ API server audit logging enabled
☐ etcd encrypted at rest
☐ Network policies deployed (deny-all baseline)
☐ Admission controllers: NodeRestriction, PodSecurity
☐ kube-bench CIS benchmark passes

Workload level:
☐ Pods run as non-root
☐ readOnlyRootFilesystem: true
☐ allowPrivilegeEscalation: false
☐ capabilities dropped (drop: [ALL])
☐ seccompProfile: RuntimeDefault
☐ Resource limits set (CPU + memory)
☐ No hostPath mounts
☐ No privileged: true

Networking:
☐ Default-deny NetworkPolicy per namespace
☐ Ingress TLS only
☐ Service mesh mTLS (if applicable)

Images:
☐ Non-root user in Dockerfile
☐ Distroless or minimal base images
☐ Images scanned (Trivy/Grype)
☐ Images signed (Cosign)
☐ No latest tag in production

Secrets:
☐ No secrets in env vars from ConfigMaps
☐ External secrets (Vault / ESO)
☐ etcd secret encryption enabled
☐ No secrets in Docker image layers
```
