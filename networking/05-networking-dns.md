# 🔍 DNS Deep Dive

How DNS works, record types, Route53, CoreDNS, split-horizon, and troubleshooting.

---

## 📚 Table of Contents

- [1. How DNS Works](#1-how-dns-works)
- [2. DNS Record Types](#2-dns-record-types)
- [3. TTL & Caching](#3-ttl--caching)
- [4. AWS Route53](#4-aws-route53)
- [5. CoreDNS in Kubernetes](#5-coredns-in-kubernetes)
- [6. Split-Horizon DNS](#6-split-horizon-dns)
- [7. DNSSEC](#7-dnssec)
- [8. DNS Troubleshooting](#8-dns-troubleshooting)
- [Cheatsheet](#cheatsheet)

---

## 1. How DNS Works

DNS (Domain Name System) translates human-readable names to IP addresses. It's a hierarchical, distributed database.

### The resolution process

```
Browser wants IP for: api.example.com

1. Check local DNS cache
   → cached? return immediately

2. Ask OS resolver (/etc/resolv.conf)
   nameserver 8.8.8.8  ← Google's DNS

3. 8.8.8.8 checks its cache
   → cached? return to client

4. 8.8.8.8 asks a Root Name Server (.)
   "Who knows about .com?"
   Root servers: a.root-servers.net to m.root-servers.net

5. Root server responds:
   "For .com, ask: a.gtld-servers.net"

6. 8.8.8.8 asks TLD server (a.gtld-servers.net)
   "Who knows about example.com?"

7. TLD server responds:
   "For example.com, ask: ns1.example.com"

8. 8.8.8.8 asks authoritative name server (ns1.example.com)
   "What's the IP of api.example.com?"

9. Authoritative server responds:
   "api.example.com → 93.184.216.34 (TTL: 300)"

10. 8.8.8.8 caches the answer and returns to client

11. Client caches the answer, connects to 93.184.216.34
```

### DNS hierarchy

```
.                          ← Root (.)
├── com.                   ← Top-Level Domain (TLD)
│   ├── example.com.       ← Second-Level Domain
│   │   ├── www.           ← Subdomain
│   │   └── api.           ← Subdomain
│   └── google.com.
├── org.
├── de.                    ← Country-code TLD
└── io.
```

### Recursive vs Authoritative DNS

```
Recursive resolver (8.8.8.8, 1.1.1.1, your ISP):
  - Clients query this
  - Does the work of finding the answer
  - Caches results
  - "I'll find out for you"

Authoritative nameserver (your DNS provider):
  - The definitive source for a domain
  - Has the actual DNS records
  - "I am the source of truth for example.com"
  - Does NOT cache — returns directly from zone data
```

---

## 2. DNS Record Types

### A record (IPv4 address)

```
api.example.com.  300  IN  A  93.184.216.34
                   │       │
                  TTL    record type
```

### AAAA record (IPv6 address)

```
api.example.com.  300  IN  AAAA  2606:2800:220:1:248:1893:25c8:1946
```

### CNAME record (alias)

```
# Canonical name — points to another hostname (not IP)
www.example.com.  300  IN  CNAME  example.com.
blog.example.com. 300  IN  CNAME  mycompany.wordpress.com.

# Rules:
# - Can't use CNAME at zone apex (example.com itself)
# - Resolves the target hostname for its IP (chain)
# - CANNOT coexist with other records at same name
```

### MX record (mail)

```
# Mail exchanger — where to deliver email for the domain
example.com.  300  IN  MX  10 mail1.example.com.
example.com.  300  IN  MX  20 mail2.example.com.
                       │
                   Priority (lower = preferred)
```

### TXT record (text — many uses)

```
# SPF — who can send email for this domain
example.com.  300  IN  TXT  "v=spf1 include:_spf.google.com ~all"

# DKIM — email signing
mail._domainkey.example.com. 300 IN TXT "v=DKIM1; k=rsa; p=..."

# DMARC — email authentication policy
_dmarc.example.com. 300 IN TXT "v=DMARC1; p=quarantine; rua=mailto:..."

# Domain verification (Google, AWS, etc.)
example.com. 300 IN TXT "google-site-verification=abc123..."

# Let's Encrypt DNS-01 challenge
_acme-challenge.example.com. 60 IN TXT "abc123..."
```

### NS record (name servers)

```
# Delegates authority for the domain to these name servers
example.com.  172800  IN  NS  ns1.example.com.
example.com.  172800  IN  NS  ns2.example.com.
```

### SOA record (Start of Authority)

```
# Metadata about the zone
example.com. 900 IN SOA ns1.example.com. admin.example.com. (
    2024011501  ; Serial number
    3600        ; Refresh (how often secondary NS checks primary)
    900         ; Retry (how often secondary retries on failure)
    604800      ; Expire (how long secondary serves stale data)
    300         ; Negative TTL (how long to cache NXDOMAIN)
)
```

### SRV record (service location)

```
# Service discovery — where is service X running?
_http._tcp.example.com. 300 IN SRV 10 5 80 web.example.com.
                                    │  │  │  └── hostname
                                    │  │  └── port
                                    │  └── weight
                                    └── priority

# Used by: Kubernetes, SIP, XMPP, some databases
```

### PTR record (reverse DNS)

```
# IP → hostname (reverse lookup)
34.216.184.93.in-addr.arpa. 300 IN PTR api.example.com.

# Used for: email deliverability, logging, security
dig -x 93.184.216.34    # reverse lookup
```

### CAA record (Certificate Authority Authorization)

```
# Specifies which CAs can issue certs for the domain
example.com. 300 IN CAA 0 issue "letsencrypt.org"
example.com. 300 IN CAA 0 issue "amazon.com"
example.com. 300 IN CAA 0 issuewild "letsencrypt.org"
```

### ALIAS / ANAME (Route53 Alias)

```
# Like CNAME but works at zone apex, resolves to IP
# Route53-specific — replaces A record with dynamic IP lookup

example.com.  A  ALIAS  my-alb-123.eu-central-1.elb.amazonaws.com.

# Allows: example.com → ALB DNS name
# Without ALIAS: can't point example.com (apex) to ALB
```

---

## 3. TTL & Caching

TTL (Time To Live) — how long DNS resolvers cache a record.

```
api.example.com.  300  IN  A  93.184.216.34
                   │
                  300 seconds = 5 minutes

After 5 minutes, resolver re-queries the authoritative server.
Before 5 minutes: uses cached value (even if you changed it)
```

### TTL strategy

| Situation | Recommended TTL |
|-----------|----------------|
| Normal stable records | 300-3600s (5 min - 1 hour) |
| Before planned migration | Lower to 60s (1 day before) |
| During migration | Keep at 60s |
| After migration stabilized | Raise back to 300-3600s |
| Rapidly changing IPs | 30-60s |
| CDN records (CNAME) | 60-300s |

```bash
# Check current TTL
dig api.example.com | grep -A2 "ANSWER SECTION"
# api.example.com.  287  IN  A  93.184.216.34
#                    │
#                remaining TTL (seconds)

# Before migration: lower TTL to 60
# Wait for old TTL to expire (current TTL value)
# Then change the IP
# Traffic cuts over within 60 seconds
```

---

## 4. AWS Route53

Route53 is AWS's managed DNS service — authoritative nameserver + health checking + routing policies.

### Hosted zones

```bash
# Public hosted zone — accessible from internet
# example.com → Route53 manages DNS records

# Private hosted zone — accessible within VPC only
# db.internal → resolves only for VPC members

aws route53 list-hosted-zones
aws route53 list-resource-record-sets \
  --hosted-zone-id XXXXXXXXXXXXX
```

### Routing policies

```
Simple:        Single IP or value — basic
Weighted:      A% to server 1, B% to server 2 (canary deployments)
Latency:       Route to AWS region with lowest latency
Failover:      Primary + secondary (health check based)
Geolocation:   EU users → EU server, US users → US server
Geoproximity:  Route based on distance (with bias)
Multivalue:    Return multiple IPs (basic load balancing)
```

```hcl
# Weighted routing — canary deployment
resource "aws_route53_record" "api_v1" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.example.com"
  type    = "A"
  ttl     = 60

  weighted_routing_policy {
    weight = 90    # 90% to v1
  }

  set_identifier = "api-v1"
  records        = ["10.0.1.5"]
}

resource "aws_route53_record" "api_v2" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.example.com"
  type    = "A"
  ttl     = 60

  weighted_routing_policy {
    weight = 10    # 10% to v2
  }

  set_identifier = "api-v2"
  records        = ["10.0.1.6"]
}
```

### Health checks

```hcl
resource "aws_route53_health_check" "api" {
  fqdn              = "api.example.com"
  port              = 443
  type              = "HTTPS"
  resource_path     = "/health"
  failure_threshold = 3
  request_interval  = 30

  tags = { Name = "api-health" }
}

# Failover routing with health check
resource "aws_route53_record" "api_primary" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "api.example.com"
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.api.id
  alias {
    name    = aws_lb.primary.dns_name
    zone_id = aws_lb.primary.zone_id
    evaluate_target_health = true
  }
}
```

---

## 5. CoreDNS in Kubernetes

CoreDNS is the cluster DNS server in Kubernetes. Every pod uses it for service discovery.

### Pod DNS config

```bash
# Inside any pod:
cat /etc/resolv.conf
# nameserver 10.96.0.10    ← CoreDNS ClusterIP
# search default.svc.cluster.local svc.cluster.local cluster.local
# options ndots:5
```

### DNS search domains explained

```
Query: my-service
ndots:5 means: if query has fewer than 5 dots, try search domains first

Resolution order:
1. my-service.default.svc.cluster.local  ← try same namespace
2. my-service.svc.cluster.local
3. my-service.cluster.local
4. my-service (external lookup)
```

### Service DNS naming

```
<service>.<namespace>.svc.cluster.local

Examples:
postgres.production.svc.cluster.local
redis.default.svc.cluster.local
my-api.staging.svc.cluster.local

Short forms (from same namespace):
postgres                    ← same namespace only
postgres.production         ← cross-namespace
```

### CoreDNS ConfigMap

```yaml
# kubectl get configmap coredns -n kube-system -o yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        errors
        health {
           lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
           pods insecure
           fallthrough in-addr.arpa ip6.arpa
           ttl 30
        }
        prometheus :9153
        forward . /etc/resolv.conf {
           max_concurrent 1000
        }
        cache 30
        loop
        reload
        loadbalance
    }
```

### Add custom DNS entries

```yaml
# Add entries for external services
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
data:
  Corefile: |
    .:53 {
        # ... existing config ...

        # Forward internal.company.com to company DNS
        internal.company.com:53 {
            forward . 10.0.0.2 10.0.0.3
        }

        # Add a hosts entry
        hosts {
            10.0.0.100 legacy-service.internal
            fallthrough
        }
    }
```

---

## 6. Split-Horizon DNS

The same domain returns different answers depending on where the query comes from.

```
Query: api.example.com

From internet → 93.184.216.34 (public ALB IP)
From within VPC → 10.0.1.50 (internal ALB IP or pod IP)
```

### Why split-horizon?

- Private services shouldn't be reachable from internet
- Internal traffic should use internal IPs (avoid internet hairpinning)
- Different behavior per environment (dev vs prod resolution)

### AWS Route53 split-horizon

```hcl
# Public hosted zone
resource "aws_route53_zone" "public" {
  name = "example.com"
}

resource "aws_route53_record" "api_public" {
  zone_id = aws_route53_zone.public.zone_id
  name    = "api.example.com"
  type    = "A"
  alias {
    name    = aws_lb.external.dns_name
    zone_id = aws_lb.external.zone_id
    evaluate_target_health = true
  }
}

# Private hosted zone (same domain, different answers within VPC)
resource "aws_route53_zone" "private" {
  name = "example.com"
  vpc {
    vpc_id = aws_vpc.main.id
  }
}

resource "aws_route53_record" "api_private" {
  zone_id = aws_route53_zone.private.zone_id
  name    = "api.example.com"
  type    = "A"
  alias {
    name    = aws_lb.internal.dns_name
    zone_id = aws_lb.internal.zone_id
    evaluate_target_health = true
  }
}

# Result:
# From VPC: api.example.com → 10.0.1.50 (internal ALB)
# From internet: api.example.com → 93.184.216.34 (external ALB)
```

---

## 7. DNSSEC

DNSSEC adds cryptographic signatures to DNS records, preventing DNS spoofing.

```
Without DNSSEC:
  Attacker can intercept DNS response and return fake IP
  (DNS cache poisoning)

With DNSSEC:
  Zone signs all records with private key
  Resolver verifies signature with public key
  Tampered records fail verification

Adoption: increasing but not universal (~30% of domains)
Important for: banking, healthcare, government
```

---

## 8. DNS Troubleshooting

```bash
# Basic lookup
dig example.com
dig example.com A
dig example.com MX
dig example.com TXT
nslookup example.com
host example.com

# Query specific DNS server
dig @8.8.8.8 example.com        # Google DNS
dig @1.1.1.1 example.com        # Cloudflare DNS
dig @10.0.0.2 example.com       # Internal DNS

# Trace full resolution path
dig +trace example.com           # shows every step from root

# Reverse lookup
dig -x 93.184.216.34

# Check all records
dig example.com ANY

# Check NS records (who is authoritative?)
dig example.com NS
dig NS example.com @8.8.8.8

# Check if record propagated (after DNS change)
# Query multiple public DNS servers
for ns in 8.8.8.8 1.1.1.1 9.9.9.9 208.67.222.222; do
  echo -n "$ns: "
  dig @$ns +short api.example.com
done

# Check SOA (serial number — increments on each zone change)
dig example.com SOA

# Kubernetes DNS debugging
kubectl exec -it my-pod -- nslookup kubernetes.default
kubectl exec -it my-pod -- nslookup my-service.production.svc.cluster.local
kubectl exec -it my-pod -- cat /etc/resolv.conf
kubectl logs -n kube-system -l k8s-app=kube-dns    # CoreDNS logs

# Run a debug pod with DNS tools
kubectl run dns-debug --image=nicolaka/netshoot -it --rm -- bash
# Inside: dig, nslookup, host all available
```

### Common DNS issues

```bash
# Issue: nslookup works but dig doesn't (or vice versa)
# → They use different resolution paths; check /etc/resolv.conf and /etc/nsswitch.conf

# Issue: DNS works from laptop but not from pod
kubectl exec pod -- cat /etc/resolv.conf    # check nameserver
kubectl get pods -n kube-system | grep coredns  # is CoreDNS running?

# Issue: intermittent DNS failures in Kubernetes
# → Common with ndots:5 and conntrack table full
# Fix: reduce search domains, increase conntrack table
kubectl get cm coredns -n kube-system -o yaml  # check config

# Issue: DNS not propagating after record change
# → Old TTL hasn't expired yet; wait for it
dig +nocmd example.com | grep "ANSWER SECTION" -A5   # check remaining TTL
```

---

## Cheatsheet

```bash
# Lookup
dig example.com                  # A record
dig example.com MX               # mail records
dig example.com NS               # nameservers
dig example.com TXT              # text records
dig +short example.com           # just the IP
dig +trace example.com           # full resolution trace
dig @8.8.8.8 example.com        # use specific resolver

# Reverse
dig -x 93.184.216.34

# Check propagation
for ns in 8.8.8.8 1.1.1.1 9.9.9.9; do
  echo "$ns: $(dig @$ns +short api.example.com)"
done

# Kubernetes
kubectl exec pod -- nslookup my-service
kubectl exec pod -- nslookup my-service.other-ns.svc.cluster.local
kubectl get cm coredns -n kube-system -o yaml

# Record patterns
A:     hostname → IPv4
AAAA:  hostname → IPv6
CNAME: hostname → hostname (alias)
MX:    domain → mail server
TXT:   domain → text (SPF, DKIM, verification)
NS:    domain → nameservers
PTR:   IP → hostname (reverse)
SRV:   service → host:port
CAA:   domain → allowed CAs
```

---

*Next: [Firewalls & Security Groups →](./06-firewalls-security-groups.md)*
