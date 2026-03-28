# ⚙️ Configuration & Secrets

ConfigMaps, Secrets, and environment variables — how to inject configuration into pods cleanly and securely.

---

## 📚 Table of Contents

- [1. ConfigMaps](#1-configmaps)
- [2. Secrets](#2-secrets)
- [3. Injecting Config into Pods](#3-injecting-config-into-pods)
- [4. Secret Management Best Practices](#4-secret-management-best-practices)
- [5. External Secrets Operator](#5-external-secrets-operator)
- [Cheatsheet](#cheatsheet)

---

## 1. ConfigMaps

ConfigMaps store **non-sensitive** configuration data as key-value pairs.

### Creating ConfigMaps

```yaml
# From YAML manifest
apiVersion: v1
kind: ConfigMap
metadata:
  name: app-config
  namespace: production
data:
  # Simple key-value pairs
  APP_ENV: production
  LOG_LEVEL: info
  MAX_CONNECTIONS: "100"

  # Multi-line values (entire files)
  nginx.conf: |
    server {
        listen 80;
        server_name example.com;
        location / {
            proxy_pass http://localhost:8080;
        }
    }

  app.properties: |
    db.host=postgres.production
    db.port=5432
    db.name=myapp
```

```bash
# From command line
kubectl create configmap app-config \
  --from-literal=APP_ENV=production \
  --from-literal=LOG_LEVEL=info

# From a file (key = filename, value = file contents)
kubectl create configmap nginx-config --from-file=nginx.conf

# From a directory (one key per file)
kubectl create configmap app-configs --from-file=configs/

# View
kubectl get configmap app-config -o yaml
kubectl describe configmap app-config
```

---

## 2. Secrets

Secrets store **sensitive** data — passwords, tokens, certificates. Values are base64-encoded (not encrypted by default — see best practices).

### Secret types

| Type | Use |
|------|-----|
| `Opaque` | Generic key-value (default) |
| `kubernetes.io/tls` | TLS certificate and key |
| `kubernetes.io/dockerconfigjson` | Docker registry credentials |
| `kubernetes.io/service-account-token` | ServiceAccount token |
| `kubernetes.io/ssh-auth` | SSH private key |

### Creating Secrets

```yaml
# Opaque secret — values must be base64 encoded
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
  namespace: production
type: Opaque
data:
  password: cGFzc3dvcmQxMjM=    # base64 of "password123"
  username: bXlhcHA=             # base64 of "myapp"

# OR use stringData — Kubernetes encodes for you
apiVersion: v1
kind: Secret
metadata:
  name: db-secret
  namespace: production
type: Opaque
stringData:
  password: password123          # plaintext — Kubernetes encodes it
  username: myapp
  connection-string: "postgresql://myapp:password123@postgres:5432/myapp"
```

```bash
# From command line
kubectl create secret generic db-secret \
  --from-literal=password=password123 \
  --from-literal=username=myapp

# TLS secret from cert files
kubectl create secret tls tls-secret \
  --cert=server.crt \
  --key=server.key

# Docker registry secret
kubectl create secret docker-registry registry-creds \
  --docker-server=registry.example.com \
  --docker-username=myuser \
  --docker-password=mypassword \
  --docker-email=admin@example.com

# View secret (base64 encoded)
kubectl get secret db-secret -o yaml

# Decode a secret value
kubectl get secret db-secret -o jsonpath='{.data.password}' | base64 -d
```

---

## 3. Injecting Config into Pods

### Method 1 — Environment variables (individual keys)

```yaml
spec:
  containers:
    - name: app
      env:
        # Static value
        - name: APP_ENV
          value: production

        # From ConfigMap
        - name: LOG_LEVEL
          valueFrom:
            configMapKeyRef:
              name: app-config
              key: LOG_LEVEL

        # From Secret
        - name: DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-secret
              key: password
              optional: false    # fail if secret doesn't exist
```

### Method 2 — envFrom (load all keys at once)

```yaml
spec:
  containers:
    - name: app
      envFrom:
        # Load all keys from ConfigMap as env vars
        - configMapRef:
            name: app-config
            optional: false

        # Load all keys from Secret as env vars
        - secretRef:
            name: db-secret

        # Add prefix to avoid naming collisions
        - configMapRef:
            name: feature-flags
          prefix: FEATURE_
```

### Method 3 — Volume mount (files)

Best for: large configs, nginx/app config files, TLS certificates.

```yaml
spec:
  containers:
    - name: app
      volumeMounts:
        - name: config
          mountPath: /etc/app           # directory
          readOnly: true
        - name: nginx-config
          mountPath: /etc/nginx/nginx.conf
          subPath: nginx.conf           # mount single file, not directory
          readOnly: true
        - name: tls
          mountPath: /etc/ssl
          readOnly: true

  volumes:
    - name: config
      configMap:
        name: app-config
        # optional: mount specific keys only
        items:
          - key: app.properties
            path: app.properties
            mode: 0444

    - name: nginx-config
      configMap:
        name: nginx-config

    - name: tls
      secret:
        secretName: tls-secret
        defaultMode: 0400    # restrict permissions on secret files
```

### Method 4 — Projected volumes (combine multiple sources)

```yaml
volumes:
  - name: combined-config
    projected:
      sources:
        - configMap:
            name: app-config
        - secret:
            name: db-secret
        - serviceAccountToken:
            path: token
            expirationSeconds: 3600
```

### ConfigMap/Secret hot reload

Volumes update automatically when ConfigMap/Secret changes (~1-2 minutes). Environment variables do NOT update — pod must restart.

```bash
# Update ConfigMap
kubectl edit configmap app-config
# OR
kubectl apply -f app-config.yaml

# Force pod restart to pick up env var changes
kubectl rollout restart deployment/my-app
```

---

## 4. Secret Management Best Practices

### Enable encryption at rest

By default, Secrets are stored **unencrypted** in etcd. Enable encryption:

```yaml
# /etc/kubernetes/encryption-config.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: <base64-encoded-32-byte-key>
      - identity: {}    # fallback for unencrypted secrets
```

### Use RBAC to restrict Secret access

```yaml
# Only allow specific ServiceAccounts to read specific Secrets
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: secret-reader
  namespace: production
rules:
  - apiGroups: [""]
    resources: ["secrets"]
    resourceNames: ["db-secret", "tls-secret"]   # specific secrets only
    verbs: ["get"]
```

### Never commit Secrets to Git

```bash
# .gitignore
secrets/
*secret*.yaml
*-secret.yaml

# Use sealed-secrets or external secrets instead
```

### Secrets best practices checklist

```
✅ Enable etcd encryption at rest
✅ Use RBAC to restrict who can read secrets
✅ Never commit plaintext secrets to Git
✅ Use External Secrets Operator for production (pull from Vault/AWS SSM)
✅ Rotate secrets regularly
✅ Use short-lived tokens where possible (projected service account tokens)
✅ Audit secret access with Kubernetes audit logs
✅ Mount secrets as volumes (not env vars) when possible — harder to leak
```

---

## 5. External Secrets Operator

In production, secrets should live in a **secrets manager** (HashiCorp Vault, AWS Secrets Manager, GCP Secret Manager) — not in Kubernetes Secrets. The External Secrets Operator syncs them automatically.

### 🔹 What is External Secrets Operator (ESO)?

- **External Secrets Operator (ESO)** is a Kubernetes operator that **automatically syncs secrets** from an external secrets manager into Kubernetes.  
- This allows you to **keep secrets in a secure external store** (AWS Secrets Manager, HashiCorp Vault, GCP Secret Manager) instead of storing them directly in Kubernetes Secrets.

### 🔹 Why use it?

- **Security:** Secrets are **not stored in Kubernetes** in plain YAML or etcd.  
- **Central management:** All secrets live in one secure place.  
- **Automatic syncing:** Updates in the external secrets manager are automatically reflected in Kubernetes.  
- **Auditability:** External managers often provide audit logs of secret access.

### 🔹 How it works (high-level flow)

1. Admin creates a **SecretDefinition** (or ExternalSecret resource) in Kubernetes:
2. ESO watches the ExternalSecret resource.
3. It fetches the secret from the external secrets manager (AWS Secrets Manager in this case).
4. ESO creates/updates a Kubernetes Secret automatically in the specified namespace.
5. Applications can reference this Kubernetes Secret as usual (envFrom or volumeMount).

### External Secrets Operator Setup & Workflow
Step 1: Install External Secrets Operator
Step 2: Create a SecretStore / ClusterSecretStore (This defines how to connect to the external secrets manager)
Step 3: Create an ExternalSecret (This defines which secret to fetch from the external store and how to map it to a Kubernetes Secret.)
Step 4: ESO syncs the secret (ESO watches ExternalSecret resources continuously.)
Step 5: Pod consumes the secret (Applications can use the synced Kubernetes Secret like normal: envFrom: in Deployment/StatefulSet / volumeMounts as files )

```
AWS Secrets Manager / Vault / GCP Secret Manager
                │
                │  External Secrets Operator reads
                ▼
        Kubernetes Secret (synced automatically)
                │
                ▼
             Pod uses it
```

### Install External Secrets Operator

```bash
helm repo add external-secrets https://charts.external-secrets.io
helm install external-secrets external-secrets/external-secrets \
  --namespace external-secrets \
  --create-namespace
```

### SecretStore — connection to the backend

```yaml
# Connect to AWS Secrets Manager
apiVersion: external-secrets.io/v1beta1
kind: SecretStore
metadata:
  name: aws-secret-store
  namespace: production
spec:
  provider:
    aws:
      service: SecretsManager
      region: eu-central-1
      auth:
        jwt:
          serviceAccountRef:
            name: external-secrets-sa   # ServiceAccount with IAM role
```

### ExternalSecret — pull a secret

```yaml
apiVersion: external-secrets.io/v1beta1
kind: ExternalSecret
metadata:
  name: db-secret
  namespace: production
spec:
  refreshInterval: 1h              # re-sync every hour

  secretStoreRef:
    name: aws-secret-store
    kind: SecretStore

  target:
    name: db-secret                # name of the K8s Secret to create
    creationPolicy: Owner

  data:
    - secretKey: password          # key in K8s Secret
      remoteRef:
        key: production/myapp/db   # path in AWS Secrets Manager
        property: password         # field within the secret JSON
    - secretKey: username
      remoteRef:
        key: production/myapp/db
        property: username
```

```bash
# Check sync status
kubectl get externalsecret -n production
kubectl describe externalsecret db-secret -n production
# SecretSyncedError → check SecretStore credentials
```

---

## Cheatsheet

```bash
# ConfigMap
kubectl create configmap my-config --from-literal=key=value
kubectl create configmap my-config --from-file=config.yaml
kubectl get configmap my-config -o yaml
kubectl edit configmap my-config

# Secret
kubectl create secret generic my-secret --from-literal=password=secret
kubectl create secret tls tls-secret --cert=cert.crt --key=cert.key
kubectl get secret my-secret -o yaml
kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d

# Reload after ConfigMap change
kubectl rollout restart deployment/my-app

# External Secrets
kubectl get externalsecret -A
kubectl describe externalsecret my-secret
```

```yaml
# Quick env injection pattern
env:
  - name: DB_PASSWORD
    valueFrom:
      secretKeyRef:
        name: db-secret
        key: password
envFrom:
  - configMapRef:
      name: app-config
```

---

*Next: [RBAC & Security →](./06-rbac-security.md) — roles, service accounts, and pod security.*
