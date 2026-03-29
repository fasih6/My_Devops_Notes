# DAST & Runtime Security

## DAST — Dynamic Application Security Testing

DAST tests a **running application** from the outside, simulating an attacker. It sends HTTP requests, analyses responses, and finds vulnerabilities that only appear at runtime.

```
SAST: Reads code → finds vulnerable patterns
DAST: Attacks running app → finds exploitable vulnerabilities

SAST finds: SQL injection pattern in code
DAST finds: SQL injection that actually works against your running API
```

DAST strengths:
- Language-agnostic (tests any HTTP endpoint)
- Finds runtime/configuration issues (wrong headers, exposed admin paths)
- More accurate (fewer false positives — actually exploits the issue)

DAST limitations:
- Needs a running environment
- Slower than SAST (can take hours for large apps)
- Requires authentication config
- Can miss code paths not exercised by its crawl

## OWASP ZAP (Zed Attack Proxy)

The most popular open-source DAST tool. Used for automated scanning and manual pen-testing.

### ZAP Baseline Scan (Passive Only — Fast)

```bash
# Passive scan — no attacks, just crawl and observe
docker run --rm \
  -v $(pwd):/zap/wrk/:rw \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py \
  -t https://myapp.example.com \
  -r zap-baseline-report.html \
  -J zap-baseline-report.json

# With authentication
docker run --rm \
  -v $(pwd):/zap/wrk/:rw \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-baseline.py \
  -t https://myapp.example.com \
  -r report.html \
  --hook=/zap/wrk/auth-hook.py  # custom auth script
```

### ZAP Full Scan (Active — Attacks the App)

```bash
# Full attack scan — only run against a test environment!
docker run --rm \
  -v $(pwd):/zap/wrk/:rw \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-full-scan.py \
  -t https://myapp-staging.example.com \
  -r zap-full-report.html \
  -J zap-full-report.json \
  -m 10                          # max 10 minutes crawl
```

### ZAP API Scan

```bash
# Scan a REST API using OpenAPI/Swagger spec
docker run --rm \
  -v $(pwd):/zap/wrk/:rw \
  ghcr.io/zaproxy/zaproxy:stable \
  zap-api-scan.py \
  -t https://myapp.example.com/swagger.json \
  -f openapi \
  -r zap-api-report.html \
  -J zap-api-report.json
```

### ZAP in GitLab CI

```yaml
dast-scan:
  stage: dast
  image: ghcr.io/zaproxy/zaproxy:stable
  variables:
    DAST_TARGET_URL: "https://${CI_ENVIRONMENT_SLUG}.myapp.example.com"
  script:
    # Passive scan only for merge requests
    - zap-baseline.py
        -t ${DAST_TARGET_URL}
        -r zap-report.html
        -J zap-report.json
        -I  # continue even with warnings
  artifacts:
    when: always
    paths:
      - zap-report.html
      - zap-report.json
  rules:
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
      variables:
        DAST_SCAN_TYPE: baseline
    - if: '$CI_COMMIT_BRANCH == "main"'
      variables:
        DAST_SCAN_TYPE: full

# GitLab native DAST integration
include:
  - template: DAST.gitlab-ci.yml

variables:
  DAST_WEBSITE: "https://staging.myapp.example.com"
  DAST_FULL_SCAN_ENABLED: "false"  # passive only in MR, full only in main
  DAST_BROWSER_SCAN: "true"        # use browser-based scanning
```

## Nikto — Web Server Scanner

Fast web server misconfiguration scanner.

```bash
# Install
apt-get install nikto

# Basic scan
nikto -h https://myapp.example.com

# Scan with specific port
nikto -h myapp.example.com -port 8443 -ssl

# Output to file
nikto -h https://myapp.example.com -o nikto-report.html -Format html

# Tuning — select vulnerability categories to test
nikto -h https://myapp.example.com -Tuning 1 2 3 4 5 6 7 8 9 0 a b c
# 1=Interesting files, 2=Misconfiguration, 3=Information disclosure, etc.
```

## Security Headers

Many vulnerabilities come from missing HTTP security headers. These should be set and verified:

| Header | Purpose | Example value |
|--------|---------|---------------|
| `Content-Security-Policy` | Prevent XSS, injection | `default-src 'self'` |
| `Strict-Transport-Security` | Force HTTPS | `max-age=31536000; includeSubDomains` |
| `X-Frame-Options` | Prevent clickjacking | `DENY` or `SAMEORIGIN` |
| `X-Content-Type-Options` | Prevent MIME sniffing | `nosniff` |
| `Referrer-Policy` | Control referrer info | `strict-origin-when-cross-origin` |
| `Permissions-Policy` | Control browser features | `geolocation=(), camera=()` |

Check security headers:
```bash
# curl check
curl -I https://myapp.example.com

# securityheaders.com (online tool)
# Or locally:
curl -sI https://myapp.example.com | grep -E "content-security|strict-transport|x-frame|x-content|referrer"
```

## Runtime Security with Falco

Falco is the de-facto standard for Kubernetes runtime security. It monitors syscalls using eBPF and alerts on anomalous behaviour.

```
Container
  ↓ syscalls
Linux Kernel ←─── eBPF probe (Falco) watches every syscall
                          ↓
                  Rule engine: does this match a threat pattern?
                          ↓
                  Alert → Slack, PagerDuty, SIEM, Kubernetes Audit
```

### Install Falco

```bash
# Helm install
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm install falco falcosecurity/falco \
  --namespace falco \
  --create-namespace \
  --set falco.jsonOutput=true \
  --set falco.logLevel=info \
  --set driver.kind=ebpf  # use eBPF driver (recommended for modern kernels)
```

### Falco Rules

```yaml
# Custom Falco rule — detect shell spawned in container
- rule: Terminal shell in container
  desc: A shell was spawned in a container
  condition: >
    spawned_process
    and container
    and shell_procs
    and not container.image.repository = "our-debug-image"
  output: >
    Shell spawned in container
    (user=%user.name user_loginuid=%user.loginuid
    container=%container.name image=%container.image.repository
    shell=%proc.name parent=%proc.pname
    cmdline=%proc.cmdline)
  priority: WARNING
  tags: [container, shell, mitre_execution]

# Detect unexpected outbound connections
- rule: Unexpected outbound connection
  desc: Container established an outbound connection to unexpected IP
  condition: >
    outbound
    and container
    and not container.image.repository in (allowed_images)
    and not fd.sip in (allowed_ips)
  output: >
    Unexpected outbound connection
    (container=%container.name image=%container.image.repository
    connection=%fd.name)
  priority: ERROR

# Detect writing to /etc (likely malware persistence)
- rule: Write to /etc directory
  desc: A process wrote to /etc inside a container
  condition: >
    open_write
    and container
    and fd.name startswith /etc
    and not proc.name in (package_managers)
  output: >
    File opened for writing in /etc
    (user=%user.name command=%proc.cmdline file=%fd.name)
  priority: ERROR
```

### Falco Outputs / Alerting

```yaml
# falco.yaml — configure outputs
output_timeout: 2000

outputs:
  rate: 1
  max_burst: 1000

# Stdout
stdout_output:
  enabled: true

# File
file_output:
  enabled: true
  keep_alive: false
  filename: /var/log/falco/events.log

# HTTP webhook (for SIEM integration)
http_output:
  enabled: true
  url: https://siem.company.com/falco
  user_agent: "falcosecurity/falco"

# Program output (for custom processing)
program_output:
  enabled: true
  keep_alive: false
  program: "jq '{text: .output}' | curl -d @- -X POST https://hooks.slack.com/..."
```

## eBPF-Based Runtime Security

eBPF (extended Berkeley Packet Filter) allows programs to run safely in the Linux kernel without kernel modules. Modern security tools use it for zero-overhead observability.

Key tools:
- **Falco** — threat detection (syscall-based)
- **Cilium Tetragon** — process and network observability
- **Pixie** — Kubernetes observability without instrumentation
- **Tracee** (Aqua Security) — runtime security and forensics

Cilium Tetragon example:
```yaml
# Trace all exec() calls in a specific namespace
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: "sys-write"
spec:
  kprobes:
  - call: "sys_write"
    syscall: true
    args:
    - index: 0
      type: "int"
    - index: 1
      type: "char_buf"
      sizeArgIndex: 3
    - index: 2
      type: "size_t"
```

## IAST — Interactive Application Security Testing

IAST instruments the application from the inside (agent) and monitors for security issues during normal test execution.

```
Unlike DAST (black-box, external):
IAST puts an agent inside the running app → sees code execution + HTTP traffic

Advantage: Very low false positive rate — sees exactly which code handled the attack
Disadvantage: Language-specific agents, adds overhead, needs running tests
```

Commercial tools: Contrast Security, Seeker (Synopsys), Hdiv

## Runtime Security Architecture

```
┌──────────────────────────────────────────────────────┐
│                   Kubernetes Cluster                  │
│                                                       │
│  ┌───────────┐  ┌───────────┐  ┌───────────┐        │
│  │    Pod    │  │    Pod    │  │    Pod    │        │
│  │  (app)    │  │  (app)    │  │  (app)    │        │
│  └───────────┘  └───────────┘  └───────────┘        │
│        ↓               ↓              ↓              │
│  ┌──────────────────────────────────────────────┐    │
│  │           Falco DaemonSet                    │    │
│  │      (one pod per node, eBPF probe)          │    │
│  └──────────────────────┬───────────────────────┘    │
└─────────────────────────┼────────────────────────────┘
                          ↓
              ┌──────────────────────┐
              │    SIEM / Alerting   │
              │  (Elasticsearch,     │
              │   Splunk, Grafana    │
              │   Loki + alerts)     │
              └──────────────────────┘
```

## Network Policies — Runtime Network Security

```yaml
# Default deny all ingress and egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: production
spec:
  podSelector: {}    # applies to all pods
  policyTypes:
  - Ingress
  - Egress

---
# Allow only specific traffic
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
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
    ports:
    - port: 8080
  egress:
  - to:
    - podSelector:
        matchLabels:
          app: database
    ports:
    - port: 5432
```
