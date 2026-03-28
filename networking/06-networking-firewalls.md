# 🔥 Firewalls & Security Groups

iptables, nftables, NACLs, security groups, WAF — controlling traffic flow.

---

## 📚 Table of Contents

- [1. Firewall Fundamentals](#1-firewall-fundamentals)
- [2. Linux iptables](#2-linux-iptables)
- [3. nftables (modern iptables)](#3-nftables-modern-iptables)
- [4. AWS Security Groups](#4-aws-security-groups)
- [5. AWS Network ACLs](#5-aws-network-acls)
- [6. GCP Firewall Rules](#6-gcp-firewall-rules)
- [7. Web Application Firewall (WAF)](#7-web-application-firewall-waf)
- [8. Kubernetes Network Policies](#8-kubernetes-network-policies)
- [Cheatsheet](#cheatsheet)

---

## 1. Firewall Fundamentals

A firewall controls which network traffic is allowed or denied based on rules.

### Stateful vs Stateless

```
Stateless firewall:
  Evaluates every packet independently
  Must explicitly allow both directions of traffic
  Example: AWS NACLs, basic iptables without connection tracking

Stateful firewall:
  Tracks connection state (NEW, ESTABLISHED, RELATED)
  Automatically allows return traffic for established connections
  Example: AWS Security Groups, iptables with conntrack, UFW
```

### Firewall rule evaluation

```
Rules evaluated in ORDER:
  Rule 1: Allow port 443 from 0.0.0.0/0
  Rule 2: Deny port 443 from 1.2.3.4
  Rule 3: Deny all

Packet from 1.2.3.4 on port 443:
  → Matches Rule 1 (allow) → ALLOWED (rule 2 never checked!)

For NACLs/iptables: order matters
For Security Groups: all rules evaluated, most permissive wins
```

---

## 2. Linux iptables

iptables is the Linux kernel firewall — also used internally by Docker, Kubernetes, and cloud agents.

### Tables and chains

```
Tables:
  filter  → accept/drop packets (default)
  nat     → network address translation
  mangle  → modify packet headers
  raw     → connection tracking bypass

Chains (within filter table):
  INPUT   → packets destined for this host
  OUTPUT  → packets originating from this host
  FORWARD → packets being routed through this host

Traffic flow:
  Incoming → PREROUTING (nat) → routing decision
                                    │
              ┌─────────────────────┴──────────────────────┐
              │ destined for local                         │ forwarded
              ▼                                            ▼
            INPUT (filter)                           FORWARD (filter)
              │                                            │
              ▼                                            ▼
          Local process                            POSTROUTING (nat)
              │
              ▼
            OUTPUT (filter)
              │
              ▼
         POSTROUTING (nat) → out
```

### iptables commands

```bash
# View rules
iptables -L                       # filter table
iptables -L -n -v                 # with counters, no DNS
iptables -L INPUT -n -v           # specific chain
iptables -t nat -L -n -v          # NAT table
iptables -L -n --line-numbers     # with line numbers (for deletion)

# Add rules
# -A append, -I insert (at position), -D delete

# Allow SSH
iptables -A INPUT -p tcp --dport 22 -j ACCEPT

# Allow HTTP/HTTPS
iptables -A INPUT -p tcp -m multiport --dports 80,443 -j ACCEPT

# Allow from specific IP
iptables -A INPUT -s 10.0.0.5 -j ACCEPT

# Allow established connections (stateful)
iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

# Allow ICMP (ping)
iptables -A INPUT -p icmp -j ACCEPT

# Default deny all (last rule)
iptables -A INPUT -j DROP
iptables -A OUTPUT -j DROP

# Delete rule
iptables -D INPUT 3              # by line number
iptables -D INPUT -p tcp --dport 22 -j ACCEPT  # by rule

# Insert at specific position
iptables -I INPUT 1 -s 192.168.1.0/24 -j ACCEPT

# Flush all rules
iptables -F                      # flush filter
iptables -t nat -F               # flush NAT

# Save rules (persist after reboot)
iptables-save > /etc/iptables/rules.v4
iptables-restore < /etc/iptables/rules.v4
```

### NAT rules (Docker/Kubernetes use these)

```bash
# MASQUERADE — outbound NAT (used by Docker for container internet access)
iptables -t nat -A POSTROUTING -s 172.17.0.0/16 ! -d 172.17.0.0/16 -j MASQUERADE

# DNAT — port forwarding (used by Kubernetes Services)
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 10.0.0.5:8080

# View Docker's iptables rules
iptables -t nat -L -n -v | grep DOCKER
iptables -t nat -L DOCKER -n -v

# View Kubernetes kube-proxy rules
iptables -t nat -L KUBE-SERVICES -n -v
iptables -t nat -L | grep KUBE
```

### Rate limiting

```bash
# Limit SSH connections (anti-brute-force)
iptables -A INPUT -p tcp --dport 22 -m conntrack --ctstate NEW \
  -m limit --limit 3/minute --limit-burst 3 -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j DROP

# Log dropped packets before dropping
iptables -A INPUT -j LOG --log-prefix "DROP: " --log-level 4
iptables -A INPUT -j DROP
```

---

## 3. nftables (modern iptables)

nftables replaces iptables with cleaner syntax and better performance. Default on newer Linux.

```bash
# View ruleset
nft list ruleset

# Basic firewall
nft add table inet filter
nft add chain inet filter input { type filter hook input priority 0 \; policy drop \; }
nft add rule inet filter input ct state established,related accept
nft add rule inet filter input tcp dport { 22, 80, 443 } accept
nft add rule inet filter input icmp type echo-request accept

# View rules
nft list table inet filter

# UFW (Uncomplicated Firewall) — wraps iptables/nftables
ufw enable
ufw allow 22
ufw allow 80/tcp
ufw allow from 10.0.0.0/24
ufw status verbose
ufw deny 8080
```

---

## 4. AWS Security Groups

Security Groups are **stateful** instance-level firewalls. They act as virtual firewalls for EC2, RDS, ECS, EKS nodes, etc.

### Key behaviors

```
Stateful: if you allow inbound port 80, return traffic (outbound) is automatically allowed
Only ALLOW rules: you can't explicitly deny (use NACLs for deny)
All rules evaluated: most permissive applies (unlike NACLs which are ordered)
Associated with ENI: not the subnet (unlike NACLs)
Default SG: allows all outbound, allows all inbound from same SG
```

### Security group rules

```hcl
resource "aws_security_group" "web" {
  name        = "web-sg"
  description = "Web server security group"
  vpc_id      = aws_vpc.main.id

  # Inbound rules
  ingress {
    description = "HTTPS from internet"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP from internet (redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description     = "SSH from bastion only"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion.id]   # reference other SG!
  }

  # Outbound rules
  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "web-sg" }
}

# Database security group (only allow from app servers)
resource "aws_security_group" "database" {
  name   = "database-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    description     = "PostgreSQL from app servers only"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.app.id]   # only from app SG
  }
  # No ingress from internet at all
}
```

### Security group chaining

```
Internet → ALB SG (443) → App SG (8080 from ALB SG) → DB SG (5432 from App SG)

Each layer only allows traffic from the layer before it.
No direct access to app or database from internet.
```

---

## 5. AWS Network ACLs

NACLs are **stateless** subnet-level firewalls. Applied to subnets, not instances.

```
Stateless: must explicitly allow BOTH inbound AND outbound
Ordered rules: evaluated in ascending order (100, 200, 300...)
Can DENY: unlike security groups
Applied at subnet level: affects all resources in subnet
```

```hcl
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.main.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  # Allow inbound HTTPS
  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  # Allow inbound HTTP
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  # Allow return traffic (stateless! must explicitly allow)
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024   # ephemeral ports
    to_port    = 65535
  }

  # Deny known bad IP
  ingress {
    rule_no    = 50
    protocol   = "-1"
    action     = "deny"
    cidr_block = "1.2.3.4/32"
    from_port  = 0
    to_port    = 0
  }

  # Allow all outbound
  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "public-nacl" }
}
```

### SG vs NACL — when to use each

```
Security Groups:
  → Instance-level control
  → "Allow app servers to reach database"
  → Most common — use for everything

NACLs:
  → Subnet-level, coarser control
  → Block a specific IP range across all resources in a subnet
  → Compliance requirement (explicit subnet-level deny)
  → Defense in depth (add NACL on top of SGs)
```

---

## 6. GCP Firewall Rules

GCP firewall rules are **stateful** and applied at VPC level (not subnet level).

```hcl
# Allow HTTP/HTTPS to instances with "web-server" tag
resource "google_compute_firewall" "web" {
  name    = "allow-web"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["web-server"]    # only applies to tagged instances
}

# Allow internal traffic between app and database
resource "google_compute_firewall" "internal_db" {
  name    = "allow-internal-db"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["5432"]
  }

  source_tags = ["app-server"]    # from instances with this tag
  target_tags = ["database"]       # to instances with this tag
}

# Deny all by default (explicit deny rule)
resource "google_compute_firewall" "deny_all" {
  name     = "deny-all-ingress"
  network  = google_compute_network.main.name
  priority = 65534    # lower priority (higher number = lower priority)

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}
```

---

## 7. Web Application Firewall (WAF)

WAF operates at L7 — inspects HTTP requests and blocks based on rules.

### What WAF protects against

```
OWASP Top 10:
  SQL injection:         GET /users?id=1 OR 1=1
  XSS:                   <script>alert('xss')</script>
  Path traversal:        ../../etc/passwd
  Command injection:     ; rm -rf /
  SSRF:                  http://169.254.169.254/

Rate limiting:
  Brute force attacks    → too many requests per IP
  DDoS mitigation        → block suspicious traffic patterns

Geo-blocking:
  Allow only specific countries
  Block known malicious IPs
```

### AWS WAF

```hcl
resource "aws_wafv2_web_acl" "main" {
  name  = "my-waf"
  scope = "REGIONAL"    # or "CLOUDFRONT" for global

  default_action {
    allow {}
  }

  # AWS Managed Rule Groups (pre-built, no config needed)
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action { none {} }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # Rate limiting rule
  rule {
    name     = "RateLimitRule"
    priority = 2
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 2000   # requests per 5 minutes per IP
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  # Geo-block rule
  rule {
    name     = "GeoBlock"
    priority = 3
    action {
      block {}
    }
    statement {
      geo_match_statement {
        country_codes = ["KP", "IR", "SY"]   # block specific countries
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "GeoBlock"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "MainWAF"
    sampled_requests_enabled   = true
  }
}

# Attach WAF to ALB
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
```

---

## 8. Kubernetes Network Policies

Already covered in depth in the Kubernetes networking file. Quick reference:

```yaml
# Default deny all ingress in a namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny
  namespace: production
spec:
  podSelector: {}
  policyTypes: [Ingress]

---
# Allow specific communication
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-api
spec:
  podSelector:
    matchLabels:
      app: api
  policyTypes: [Ingress]
  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend
      ports:
        - port: 8080
```

---

## Cheatsheet

```bash
# iptables
iptables -L -n -v --line-numbers    # view all rules
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -D INPUT 3                 # delete rule #3
iptables -F                         # flush all rules
iptables -t nat -L -n -v           # view NAT rules
iptables-save > /etc/iptables/rules.v4

# UFW
ufw status verbose
ufw allow 22
ufw allow from 10.0.0.0/24
ufw deny 8080
ufw delete allow 22

# AWS CLI
aws ec2 describe-security-groups --group-ids sg-abc123
aws ec2 authorize-security-group-ingress \
  --group-id sg-abc123 \
  --protocol tcp --port 443 --cidr 0.0.0.0/0

# Check what's open
nmap -sV --open 10.0.0.5           # scan open ports
nc -zv 10.0.0.5 443                # check specific port
ss -tulnp | grep :443              # what's listening on 443
```

---

*Next: [Network Troubleshooting →](./07-network-troubleshooting.md)*
