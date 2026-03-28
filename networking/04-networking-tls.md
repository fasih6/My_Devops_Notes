# 🔒 TLS/SSL Deep Dive

Certificates, the TLS handshake, mTLS, cert-manager, and certificate management in production.

---

## 📚 Table of Contents

- [1. TLS Fundamentals](#1-tls-fundamentals)
- [2. X.509 Certificates](#2-x509-certificates)
- [3. Certificate Authorities](#3-certificate-authorities)
- [4. TLS Handshake](#4-tls-handshake)
- [5. Mutual TLS (mTLS)](#5-mutual-tls-mtls)
- [6. Certificate Management](#6-certificate-management)
- [7. cert-manager in Kubernetes](#7-cert-manager-in-kubernetes)
- [8. TLS in Practice](#8-tls-in-practice)
- [Cheatsheet](#cheatsheet)

---

## 1. TLS Fundamentals

TLS (Transport Layer Security) provides three guarantees:

```
Confidentiality:  Data is encrypted — only sender and receiver can read it
Integrity:        Data can't be modified in transit without detection
Authentication:   Server (and optionally client) identity is verified
```

### TLS versions

| Version | Status | Notes |
|---------|--------|-------|
| SSL 2.0/3.0 | Deprecated — disable! | Critically vulnerable |
| TLS 1.0/1.1 | Deprecated — disable! | PCI DSS requires ≥1.2 |
| TLS 1.2 | Current minimum | Still widely supported |
| TLS 1.3 | Recommended | Faster, more secure, simpler |

```bash
# Check TLS version used by a server
curl -v https://example.com 2>&1 | grep "SSL connection"
openssl s_client -connect example.com:443 2>/dev/null | grep "Protocol"

# Force specific TLS version
curl --tlsv1.2 https://example.com
curl --tlsv1.3 https://example.com
```

---

## 2. X.509 Certificates

A TLS certificate is an X.509 document containing:

```
Certificate:
  Version: 3
  Serial Number: 1234567890
  Signature Algorithm: sha256WithRSAEncryption
  Issuer: CN=DigiCert TLS RSA SHA256 2020 CA1, O=DigiCert Inc
  Validity:
    Not Before: Jan 15 00:00:00 2024 GMT
    Not After:  Jan 15 23:59:59 2025 GMT
  Subject: CN=*.example.com, O=Example Inc
  Subject Alternative Names:
    DNS:*.example.com
    DNS:example.com
  Public Key: (RSA 2048-bit or ECDSA P-256)
  Extensions:
    Key Usage: Digital Signature, Key Encipherment
    Extended Key Usage: TLS Web Server Authentication
    Basic Constraints: CA:FALSE
  Signature: (signed by issuer's private key)
```

### Certificate types

| Type | Coverage | Validation | Use |
|------|---------|-----------|-----|
| DV (Domain Validation) | Specific domains | Prove domain control | General web |
| OV (Organization Validation) | Domain + org info verified | Org verification | Business sites |
| EV (Extended Validation) | DV + OV + extra | Extensive org check | Finance, legal |
| Wildcard | `*.example.com` | Domain control | Multiple subdomains |
| SAN/Multi-domain | Multiple domains | Per-domain | Multiple sites |

### Certificate fields explained

```bash
# View certificate details
openssl x509 -in cert.pem -text -noout

# View server certificate
echo | openssl s_client -connect example.com:443 2>/dev/null \
  | openssl x509 -noout -text

# Check expiry
echo | openssl s_client -connect example.com:443 2>/dev/null \
  | openssl x509 -noout -enddate

# Check what domains it covers (SANs)
echo | openssl s_client -connect example.com:443 2>/dev/null \
  | openssl x509 -noout -text | grep -A1 "Subject Alternative"
```

---

## 3. Certificate Authorities

A Certificate Authority (CA) signs certificates, vouching for the identity of the certificate holder.

### Chain of trust

```
Root CA (self-signed — trusted by browsers/OS)
    │ signs
    ▼
Intermediate CA
    │ signs
    ▼
End-entity certificate (your server)

Browser receives server cert → checks signature → traces chain to trusted Root CA
```

### Let's Encrypt — free, automated certs

```
Let's Encrypt is a free, automated CA.
Certificates are valid for 90 days.
Automated renewal via ACME protocol.

ACME challenge types:
- HTTP-01: prove control by serving file at /.well-known/acme-challenge/
- DNS-01:  prove control by adding TXT record to DNS
- TLS-ALPN-01: prove control via TLS extension

DNS-01 is required for:
- Wildcard certificates
- Internal services not reachable from internet
```

### Private CA (for internal services)

```
For internal microservices, you don't need a public CA.
Use a private CA:
- AWS Private CA (ACM PCA)
- HashiCorp Vault PKI
- cert-manager with self-signed root

Private CA signs internal service certificates
All internal services trust the private CA root
External clients don't (and shouldn't) trust it
```

---

## 4. TLS Handshake

### TLS 1.2 handshake

```
Client                              Server
  │                                    │
  │── ClientHello ───────────────────►│
  │   TLS version, cipher suites,      │
  │   random number, session ID        │
  │                                    │
  │◄─ ServerHello ────────────────────│
  │   Chosen cipher suite,             │
  │   random number                    │
  │                                    │
  │◄─ Certificate ────────────────────│
  │   Server's certificate chain       │
  │                                    │
  │◄─ ServerKeyExchange ──────────────│
  │   (for DHE/ECDHE cipher suites)    │
  │                                    │
  │◄─ ServerHelloDone ────────────────│
  │                                    │
  │── ClientKeyExchange ─────────────►│
  │   Pre-master secret (encrypted     │
  │   with server's public key)        │
  │                                    │
  │── ChangeCipherSpec ──────────────►│
  │── Finished ─────────────────────►│
  │                                    │
  │◄─ ChangeCipherSpec ───────────────│
  │◄─ Finished ────────────────────── │
  │                                    │
  │←──────── Encrypted data ─────────►│

2 round trips before data flows
```

### TLS 1.3 handshake (faster)

```
Client                              Server
  │                                    │
  │── ClientHello ───────────────────►│
  │   + Key share (DH public key)      │
  │   + Supported versions             │
  │                                    │
  │◄─ ServerHello ────────────────────│
  │   + Key share (DH public key)      │
  │◄─ Certificate ────────────────────│
  │◄─ CertificateVerify ──────────────│
  │◄─ Finished ────────────────────── │
  │                                    │
  │── Finished ─────────────────────►│
  │                                    │
  │←──────── Encrypted data ─────────►│

1 round trip! (vs 2 for TLS 1.2)
Also: 0-RTT resumption for repeat connections
```

### Session resumption

```
TLS 1.2: Session IDs or Session Tickets
  - Client presents session ID/ticket
  - Skip certificate verification for resumed sessions

TLS 1.3: PSK (Pre-Shared Key)
  - Server sends session ticket after handshake
  - Client uses ticket for 0-RTT (zero round-trip) resumption
  - Caution: 0-RTT has replay attack risk for non-idempotent requests
```

---

## 5. Mutual TLS (mTLS)

Standard TLS: **server** authenticates to **client**.
mTLS: **both** server and client authenticate to each other.

```
Standard TLS:
  Server presents certificate → Client verifies
  Client is anonymous

mTLS:
  Server presents certificate → Client verifies
  Client presents certificate → Server verifies
  Both are authenticated
```

### mTLS use cases

- **Service mesh** (Istio, Linkerd) — pod-to-pod encrypted and authenticated
- **API authentication** — client cert instead of API key
- **Zero trust networking** — every service must prove identity
- **IoT devices** — device certificates for authentication

### Setting up mTLS

```bash
# Create a private CA
openssl genrsa -out ca-key.pem 4096
openssl req -new -x509 -days 3650 -key ca-key.pem -out ca-cert.pem \
  -subj "/CN=My Private CA"

# Create server certificate signed by CA
openssl genrsa -out server-key.pem 2048
openssl req -new -key server-key.pem -out server-csr.pem \
  -subj "/CN=my-service"
openssl x509 -req -days 365 -in server-csr.pem \
  -CA ca-cert.pem -CAkey ca-key.pem -out server-cert.pem

# Create client certificate signed by CA
openssl genrsa -out client-key.pem 2048
openssl req -new -key client-key.pem -out client-csr.pem \
  -subj "/CN=my-client"
openssl x509 -req -days 365 -in client-csr.pem \
  -CA ca-cert.pem -CAkey ca-key.pem -out client-cert.pem

# Test mTLS
curl --cacert ca-cert.pem \
     --cert client-cert.pem \
     --key client-key.pem \
     https://my-service:8443/api
```

### mTLS in nginx

```nginx
server {
    listen 443 ssl;
    ssl_certificate     /etc/ssl/server-cert.pem;
    ssl_certificate_key /etc/ssl/server-key.pem;

    # Require client certificate
    ssl_client_certificate /etc/ssl/ca-cert.pem;
    ssl_verify_client on;
    ssl_verify_depth 2;

    location /api {
        # Client certificate info available in headers
        proxy_set_header X-Client-Cert $ssl_client_cert;
        proxy_set_header X-Client-CN   $ssl_client_s_dn_cn;
        proxy_pass http://backend;
    }
}
```

---

## 6. Certificate Management

### Certificate lifecycle

```
Issue → Deploy → Monitor expiry → Renew → Deploy renewed cert

Common failure: forgetting to renew → certificate expires → service outage
Best practice: automate renewal (Let's Encrypt + cert-manager)
```

### AWS Certificate Manager (ACM)

```bash
# Request public certificate (validated via DNS or email)
aws acm request-certificate \
  --domain-name example.com \
  --subject-alternative-names "*.example.com" \
  --validation-method DNS

# List certificates and their expiry
aws acm list-certificates
aws acm describe-certificate --certificate-arn arn:aws:acm:...

# ACM auto-renews certificates before expiry
# Used directly with ALB, CloudFront — no manual deployment

# For EC2/EKS — import existing cert or use ACM PCA
```

### Checking certificate expiry

```bash
# Check a remote certificate
echo | openssl s_client -connect example.com:443 -servername example.com 2>/dev/null \
  | openssl x509 -noout -enddate
# enddate=Jan 15 23:59:59 2025 GMT

# Days until expiry
echo | openssl s_client -connect example.com:443 2>/dev/null \
  | openssl x509 -noout -checkend $((30*86400))
# Returns 0 if cert valid for 30+ days, 1 if expiring within 30 days

# Prometheus alert for cert expiry (with blackbox exporter)
# probe_ssl_earliest_cert_expiry - time() < 30 * 24 * 3600
```

---

## 7. cert-manager in Kubernetes

cert-manager automatically provisions and renews TLS certificates in Kubernetes.

```
cert-manager watches Certificate resources
    │
    │ requests certificate from:
    │   Let's Encrypt (ACME)
    │   Vault
    │   AWS ACM
    │   Self-signed
    ▼
Issues certificate → stores as Kubernetes Secret
    │
    ▼
Ingress/Pod uses the Secret
    │
cert-manager monitors expiry
    │ 30 days before expiry:
    ▼
Automatically renews → updates Secret
```

### Install cert-manager

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

### ClusterIssuer for Let's Encrypt

```yaml
# HTTP-01 challenge (for internet-facing services)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-account-key
    solvers:
      - http01:
          ingress:
            class: nginx

---
# DNS-01 challenge (for wildcard certs or internal services)
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod-dns
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - dns01:
          route53:
            region: eu-central-1
            hostedZoneID: XXXXXXXXXXXXX
```

### Certificate resource

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-app-tls
  namespace: production
spec:
  secretName: my-app-tls-secret    # Kubernetes Secret created here
  issuerRef:
    name: letsencrypt-prod
    kind: ClusterIssuer
  commonName: api.example.com
  dnsNames:
    - api.example.com
    - "*.api.example.com"
  duration: 2160h                  # 90 days
  renewBefore: 720h                # renew 30 days before expiry
```

### Auto-cert via Ingress annotation

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod   # auto-provision cert
spec:
  tls:
    - hosts:
        - api.example.com
      secretName: my-app-tls-secret   # cert-manager creates this
  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: my-app
                port:
                  number: 80
```

```bash
# Check certificate status
kubectl get certificate -A
kubectl describe certificate my-app-tls -n production

# Check the ACME challenge
kubectl get challenges -A
kubectl describe challenge my-app-tls-... -n production

# Check the secret was created
kubectl get secret my-app-tls-secret -n production
kubectl get secret my-app-tls-secret -n production -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -noout -text
```

---

## 8. TLS in Practice

### TLS configuration best practices

```nginx
# nginx TLS config — modern profile
server {
    listen 443 ssl;
    http2 on;

    ssl_certificate     /etc/ssl/cert.pem;
    ssl_certificate_key /etc/ssl/key.pem;

    # TLS 1.2 minimum, prefer 1.3
    ssl_protocols TLSv1.2 TLSv1.3;

    # Strong cipher suites
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;   # Let client choose (TLS 1.3 handles this)

    # Session resumption
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;         # Disable for perfect forward secrecy

    # OCSP stapling
    ssl_stapling on;
    ssl_stapling_verify on;
    resolver 8.8.8.8 8.8.4.4 valid=300s;

    # Security headers
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header X-Frame-Options DENY always;
    add_header X-Content-Type-Options nosniff always;
}
```

### Common TLS issues

```bash
# Certificate not trusted (self-signed or wrong CA)
curl: (60) SSL certificate problem: self signed certificate
Fix: add --cacert ca.pem or configure trust store

# Certificate expired
curl: (60) SSL certificate problem: certificate has expired
Fix: renew certificate

# Hostname mismatch (cert for different domain)
curl: (51) SSL: certificate subject name 'other.example.com' does not match target host
Fix: use correct hostname or fix SANs on certificate

# TLS version mismatch
curl: (35) error:1408F10B:SSL routines
Fix: check allowed TLS versions on server

# Check TLS configuration grade
# https://www.ssllabs.com/ssltest/ — free online test
```

---

## Cheatsheet

```bash
# Certificate inspection
openssl x509 -in cert.pem -text -noout              # view cert
openssl x509 -in cert.pem -noout -enddate           # expiry
openssl x509 -in cert.pem -noout -subject           # subject/domains
openssl verify -CAfile ca.pem cert.pem              # verify chain

# Remote certificate
echo | openssl s_client -connect host:443 -servername host 2>/dev/null \
  | openssl x509 -noout -text

# Generate self-signed cert (dev only)
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout key.pem -out cert.pem -subj "/CN=localhost"

# Test TLS
curl -v https://example.com                         # verbose (shows TLS)
curl -k https://example.com                         # ignore cert errors
curl --cacert ca.pem https://internal.example.com  # custom CA

# cert-manager
kubectl get certificate -A
kubectl get clusterissuer
kubectl describe challenge <name> -n <ns>           # debug ACME

# Check expiry days remaining
python3 -c "
import ssl, datetime
cert = ssl.get_server_certificate(('example.com', 443))
x509 = ssl.DER_cert_to_PEM_cert(ssl.PEM_cert_to_DER_cert(cert))
print(x509)
"
```

---

*Next: [DNS Deep Dive →](./05-dns-deep-dive.md)*
