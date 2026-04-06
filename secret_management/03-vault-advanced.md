# Vault Advanced — Dynamic Secrets, PKI, Vault Agent, Kubernetes Integration

## Vault Agent — Sidecar for Secret Injection

Vault Agent is a client-side daemon that runs alongside your application and handles all Vault interaction automatically:

- Authenticates to Vault using platform identity (Kubernetes, AWS, Azure)
- Renews tokens before they expire
- Fetches secrets and renders them as files or environment variables
- Re-renders templates when secrets rotate

```
Without Vault Agent:
  App → authenticates to Vault → fetches secrets → manages renewal → uses secrets
  App code must handle: auth, retry, renewal, error handling

With Vault Agent (sidecar):
  Vault Agent → authenticates → fetches secrets → writes to shared volume
  App → reads secrets from files (no Vault SDK needed, no auth logic in app)
```

### Vault Agent as Kubernetes Sidecar

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-api
  namespace: checkout
spec:
  template:
    spec:
      serviceAccountName: checkout-sa   # Used for Vault K8s auth
      volumes:
        - name: vault-secrets
          emptyDir: {}                  # Shared volume between agent and app
        - name: vault-agent-config
          configMap:
            name: vault-agent-config

      initContainers:
        - name: vault-agent-init
          image: hashicorp/vault:1.15
          args: ["agent", "-config=/vault/config/agent.hcl", "-exit-after-auth"]
          volumeMounts:
            - name: vault-secrets
              mountPath: /vault/secrets
            - name: vault-agent-config
              mountPath: /vault/config

      containers:
        - name: vault-agent
          image: hashicorp/vault:1.15
          args: ["agent", "-config=/vault/config/agent.hcl"]
          volumeMounts:
            - name: vault-secrets
              mountPath: /vault/secrets
            - name: vault-agent-config
              mountPath: /vault/config

        - name: checkout-api
          image: myregistry/checkout-api:latest
          env:
            - name: DB_CREDS_FILE
              value: /vault/secrets/db-creds.json
          volumeMounts:
            - name: vault-secrets
              mountPath: /vault/secrets
              readOnly: true
```

### Vault Agent Config

```hcl
# agent.hcl
vault {
  address = "https://vault.internal:8200"
}

auto_auth {
  method "kubernetes" {
    mount_path = "auth/kubernetes"
    config = {
      role = "checkout"
    }
  }

  sink "file" {
    config = {
      path = "/vault/secrets/.vault-token"
    }
  }
}

template {
  source      = "/vault/config/db-creds.ctmpl"
  destination = "/vault/secrets/db-creds.json"
  # Re-render when secret changes or lease renews
}

template {
  source      = "/vault/config/app-config.ctmpl"
  destination = "/vault/secrets/app-config.json"
}
```

### Consul Template Syntax (for templates)

```
# db-creds.ctmpl
{{ with secret "database/creds/checkout-app" }}
{
  "host": "postgres.internal",
  "username": "{{ .Data.username }}",
  "password": "{{ .Data.password }}"
}
{{ end }}

# app-config.ctmpl
{{ with secret "secret/data/checkout/config" }}
{
  "stripe_key": "{{ .Data.data.stripe_api_key }}",
  "redis_url": "{{ .Data.data.redis_url }}"
}
{{ end }}
```

The init container runs once at pod startup (fetches initial secrets), then the sidecar keeps running to renew leases and re-render templates if secrets change.

---

## Vault Secrets Operator (VSO) — Kubernetes-Native Approach

VSO is the newer, Kubernetes-native alternative to Vault Agent. Instead of sidecars, it uses a cluster-level operator that syncs Vault secrets into native Kubernetes Secrets.

```
Vault Agent (sidecar approach):
  Runs per-pod → files on shared volume → app reads files

Vault Secrets Operator (operator approach):
  Runs once per cluster → syncs to K8s Secret objects → app uses native K8s secrets
```

### VSO Custom Resources

```yaml
# VaultConnection — where is Vault?
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultConnection
metadata:
  name: vault-connection
  namespace: checkout
spec:
  address: https://vault.internal:8200
  skipTLSVerify: false
  caCertSecretRef: vault-ca-cert

---
# VaultAuth — how does this namespace authenticate?
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultAuth
metadata:
  name: checkout-vault-auth
  namespace: checkout
spec:
  vaultConnectionRef: vault-connection
  method: kubernetes
  mount: kubernetes
  kubernetes:
    role: checkout
    serviceAccount: checkout-sa

---
# VaultStaticSecret — sync a KV secret to a K8s Secret
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultStaticSecret
metadata:
  name: checkout-config
  namespace: checkout
spec:
  vaultAuthRef: checkout-vault-auth
  mount: secret
  type: kv-v2
  path: checkout/config
  refreshAfter: 30s          # Re-sync every 30 seconds
  destination:
    name: checkout-config    # Creates this K8s Secret
    create: true

---
# VaultDynamicSecret — sync dynamic DB creds to a K8s Secret
apiVersion: secrets.hashicorp.com/v1beta1
kind: VaultDynamicSecret
metadata:
  name: checkout-db-creds
  namespace: checkout
spec:
  vaultAuthRef: checkout-vault-auth
  mount: database
  path: creds/checkout-app
  destination:
    name: checkout-db-creds
    create: true
  rolloutRestartTargets:
    - kind: Deployment
      name: checkout-api    # Restart deployment when creds rotate
```

### VSO vs Vault Agent — When to Use Which

| Criteria | Vault Agent (sidecar) | Vault Secrets Operator |
|----------|----------------------|----------------------|
| K8s version required | Any | 1.23+ |
| App changes needed | Read from file path | Use native K8s secret env vars |
| Secret visibility | Files in pod only | K8s Secret (visible in etcd) |
| Rotation handling | Agent re-renders template | VSO updates Secret, restarts pods |
| Multi-namespace | Per-pod config | Cluster-level operator |
| Complexity | Higher (per-pod config) | Lower (cluster-level CRDs) |

VSO is the recommended approach for greenfield Kubernetes setups. Vault Agent is better when you can't modify the app to read from K8s secrets or need file-based secret injection.

---

## Vault PKI Engine — Internal Certificate Authority

The PKI engine turns Vault into a full certificate authority. Applications can request short-lived TLS certificates on-demand without any manual certificate management.

### Two-Tier PKI Setup (Root CA + Intermediate CA)

Best practice: keep the root CA offline and use an intermediate CA for day-to-day issuance.

```bash
# Step 1: Enable and configure Root CA (keep offline or in separate Vault)
vault secrets enable -path=pki pki
vault secrets tune -max-lease-ttl=87600h pki  # 10 years max for root

vault write -field=certificate pki/root/generate/internal \
  common_name="Internal Root CA" \
  ttl=87600h > root-ca.crt

# Step 2: Enable and configure Intermediate CA
vault secrets enable -path=pki_int pki
vault secrets tune -max-lease-ttl=43800h pki_int  # 5 years max

# Generate CSR for intermediate
vault write -format=json pki_int/intermediate/generate/internal \
  common_name="Internal Intermediate CA" | jq -r '.data.csr' > int-ca.csr

# Sign intermediate with root
vault write -format=json pki/root/sign-intermediate \
  csr=@int-ca.csr \
  format=pem_bundle \
  ttl=43800h | jq -r '.data.certificate' > int-ca-signed.crt

# Import signed intermediate cert
vault write pki_int/intermediate/set-signed certificate=@int-ca-signed.crt

# Step 3: Create issuance role
vault write pki_int/roles/checkout-cert \
  issuer_ref="default" \
  allowed_domains="checkout.internal,checkout.svc.cluster.local" \
  allow_subdomains=true \
  allow_glob_domains=false \
  max_ttl=72h              # Certificates valid max 72 hours

# Step 4: Issue a certificate
vault write pki_int/issue/checkout-cert \
  common_name="checkout.internal" \
  alt_names="checkout.checkout.svc.cluster.local" \
  ttl=24h
```

### Why Short-Lived Certificates?

```
Traditional (1-year certs):
  Issued → manually renewed → manually deployed → manually rotated
  If compromised: must revoke via CRL, CRL distribution is unreliable
  Operational burden: calendar reminders, renewal ceremonies

Vault PKI (24-72h certs):
  Issued automatically → expire automatically → no revocation needed
  If compromised: cert expires in hours anyway
  Operational burden: near zero — cert-manager or Vault Agent handles it
```

### Integration with cert-manager

cert-manager can use Vault as its CA backend:

```yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    server: https://vault.internal:8200
    path: pki_int/sign/checkout-cert
    auth:
      kubernetes:
        role: cert-manager
        mountPath: /v1/auth/kubernetes
        serviceAccountRef:
          name: cert-manager

---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: checkout-tls
  namespace: checkout
spec:
  secretName: checkout-tls-secret
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  dnsNames:
    - checkout.internal
    - checkout.checkout.svc.cluster.local
  duration: 24h
  renewBefore: 8h           # Renew 8 hours before expiry
```

cert-manager automatically requests a new certificate from Vault when the current one is 8 hours from expiry. The certificate in the Kubernetes Secret is always fresh.

---

## Vault SSH Engine — Short-Lived SSH Access

The SSH engine issues signed SSH certificates instead of managing authorized_keys:

```bash
# Enable SSH engine
vault secrets enable ssh

# Create a CA for signing
vault write ssh/config/ca generate_signing_key=true

# Create a role for engineer SSH access
vault write ssh/roles/engineer-ssh \
  key_type=ca \
  ttl=30m \                      # SSH cert valid 30 minutes
  allowed_users="ubuntu,ec2-user" \
  default_user="ubuntu" \
  allowed_extensions="permit-pty,permit-port-forwarding"

# Engineer requests SSH cert
vault write ssh/sign/engineer-ssh \
  public_key=@~/.ssh/id_rsa.pub \
  valid_principals="ubuntu"
# Returns: signed SSH certificate valid for 30 minutes
```

On the server side, configure SSHD to trust Vault's CA:
```
# /etc/ssh/sshd_config
TrustedUserCAKeys /etc/ssh/vault_ca.pub
```

Result: No authorized_keys files. No long-lived SSH keys on servers. Engineers get 30-minute access windows. Revocation is automatic — the cert expires.

---

## Vault Namespaces (Enterprise)

Vault Enterprise supports namespaces — isolated environments within a single Vault cluster. Used for multi-tenancy:

```
vault/
  ├── namespace: platform-team/
  │     ├── auth methods for platform team
  │     ├── secret engines for platform team
  │     └── policies for platform team
  ├── namespace: checkout-team/
  │     ├── auth methods for checkout team
  │     └── secret engines for checkout team
  └── namespace: payment-team/
        └── strict isolation from other teams
```

Each namespace is completely isolated. An admin in `checkout-team/` cannot see `payment-team/` secrets. The root namespace admin manages namespace creation.

For the open-source Vault, mount paths serve a similar (but less isolated) purpose:

```
# Separate mounts per team
vault secrets enable -path=checkout/secret kv-v2
vault secrets enable -path=payment/secret kv-v2
```

---

## Interview Questions — Vault Advanced

**Q: What is Vault Agent and why use it instead of calling Vault directly from the app?**
A: Vault Agent is a sidecar that handles all Vault interaction — authentication, token renewal, secret fetching, and template rendering. Using it means the application doesn't need any Vault SDK, doesn't handle auth retry logic, and doesn't manage token lifetimes. The app just reads a file. This simplifies application code, works with any language, and centralizes Vault interaction patterns.

**Q: What is the Vault Secrets Operator and how does it differ from Vault Agent?**
A: VSO is a Kubernetes operator that syncs Vault secrets into native Kubernetes Secret objects at the cluster level. Vault Agent runs as a per-pod sidecar and writes secrets to files. VSO is simpler to manage at scale (one operator, not one sidecar per pod), and apps can use standard Kubernetes secret env vars. The tradeoff: VSO secrets are visible in etcd (mitigated by encryption at rest), while Vault Agent secrets exist only in pod memory/tmpfs.

**Q: Why use short-lived TLS certificates from Vault PKI instead of traditional 1-year certificates?**
A: Short-lived certificates (24-72h) eliminate the need for certificate revocation infrastructure (CRL, OCSP). If a cert is compromised, it expires within hours anyway. Rotation is fully automated — Vault Agent or cert-manager renews before expiry with no human involvement. The operational burden drops to near zero compared to traditional certificate management ceremonies.
