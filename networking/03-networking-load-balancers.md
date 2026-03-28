# ⚖️ Load Balancers

L4 vs L7, ALB/NLB, health checks, sticky sessions, algorithms, and cloud patterns.

---

## 📚 Table of Contents

- [1. Load Balancing Fundamentals](#1-load-balancing-fundamentals)
- [2. L4 vs L7 Load Balancers](#2-l4-vs-l7-load-balancers)
- [3. Load Balancing Algorithms](#3-load-balancing-algorithms)
- [4. Health Checks](#4-health-checks)
- [5. AWS Load Balancers (ALB, NLB, CLB)](#5-aws-load-balancers-alb-nlb-clb)
- [6. Sticky Sessions](#6-sticky-sessions)
- [7. SSL Termination](#7-ssl-termination)
- [8. Load Balancers in Kubernetes](#8-load-balancers-in-kubernetes)
- [Cheatsheet](#cheatsheet)

---

## 1. Load Balancing Fundamentals

A load balancer distributes incoming traffic across multiple backend servers (targets), improving availability and scalability.

```
Clients
  │  │  │
  ▼  ▼  ▼
[Load Balancer]  ← single entry point
  │  │  │
  ▼  ▼  ▼
[S1][S2][S3]     ← backend servers (targets)
```

### Why load balancers

- **High availability** — if one server dies, traffic routes to healthy ones
- **Horizontal scaling** — add more servers to handle more load
- **Health checking** — automatically remove unhealthy backends
- **SSL termination** — handle TLS at the LB, plain HTTP to backends
- **Single entry point** — one IP/DNS for many servers

---

## 2. L4 vs L7 Load Balancers

### Layer 4 (Transport layer) — TCP/UDP

```
L4 LB sees:
  - IP addresses (source and destination)
  - TCP/UDP ports
  - Does NOT see HTTP headers, URLs, cookies

Operation:
  - Fast — no packet inspection
  - Lower latency
  - Protocol-agnostic (works for any TCP/UDP traffic)
  - Connection-level routing

Use for: databases, game servers, SMTP, any non-HTTP TCP traffic
AWS: Network Load Balancer (NLB)
```

### Layer 7 (Application layer) — HTTP/HTTPS

```
L7 LB sees:
  - Everything L4 sees +
  - HTTP headers (Host, User-Agent, etc.)
  - URL paths (/api, /static)
  - HTTP methods (GET, POST)
  - Cookies
  - Request body

Operation:
  - Content-based routing
  - Can modify requests/responses
  - HTTP-specific features (redirects, rewrites, sticky sessions)
  - Higher overhead (terminates and re-initiates connections)

Use for: web apps, APIs, microservices
AWS: Application Load Balancer (ALB)
```

### Comparison

| Feature | L4 (NLB) | L7 (ALB) |
|---------|----------|----------|
| Protocol | Any TCP/UDP | HTTP/HTTPS/gRPC/WebSocket |
| Routing by | IP/port | URL, headers, method, host |
| TLS termination | Optional (passthrough possible) | Yes |
| Latency | Ultra-low (~100µs) | Low (ms) |
| WebSockets | Yes | Yes |
| Static IP | Yes (EIP) | No (DNS) |
| Preserve client IP | Yes (directly) | X-Forwarded-For header |
| gRPC | Yes | Yes |
| WAF integration | No | Yes |
| Cost | Lower | Higher |

---

## 3. Load Balancing Algorithms

### Round Robin

```
Request 1 → Server A
Request 2 → Server B
Request 3 → Server C
Request 4 → Server A (back to start)

Simple, even distribution.
Problem: doesn't account for server capacity or current load.
```

### Weighted Round Robin

```
Server A (weight 3): handles 3x more requests
Server B (weight 1): handles 1x requests

Requests: A, A, A, B, A, A, A, B...

Use for: mixed server capacity, canary deployments
```

### Least Connections

```
Route to server with fewest active connections.

Server A: 100 connections
Server B: 50 connections  ← next request goes here
Server C: 75 connections

Better than round robin when requests have varying duration.
```

### Least Response Time

```
Route to server with lowest response time + fewest connections.
Best for minimizing user-perceived latency.
```

### IP Hash (sticky by source IP)

```
hash(client_IP) mod num_servers → always same server

Client 1.2.3.4 → always Server B
Client 5.6.7.8 → always Server C

Problem: uneven distribution if clients are behind a NAT
(all traffic appears from one IP)
```

### Random

```
Pick a random server.
Approaches round robin at large scale.
Simple to implement.
```

---

## 4. Health Checks

Load balancers continuously probe backend servers and only send traffic to healthy ones.

### Health check types

```
HTTP/HTTPS health check:
  - Send GET /health to each backend
  - Expect HTTP 200-399 response
  - Configurable: path, port, timeout, intervals

TCP health check:
  - Open TCP connection to backend
  - Success if connection established
  - Lower overhead than HTTP

gRPC health check:
  - Uses gRPC health checking protocol
  - Service and method level health
```

### Health check configuration

```
Healthy threshold:   2 consecutive successes → mark healthy
Unhealthy threshold: 3 consecutive failures  → mark unhealthy
Interval:            30 seconds
Timeout:             5 seconds (failure if no response)
Path:                /health or /healthz
Expected codes:      200-299

Timeline:
  t=0s:   health check fails (first failure)
  t=30s:  health check fails (second failure)
  t=60s:  health check fails (third failure) → UNHEALTHY, removed from rotation
  t=90s:  health check passes (first success)
  t=120s: health check passes (second success) → HEALTHY, added back
```

### Designing health endpoints

```python
# Good health endpoint — checks real dependencies
@app.route('/health')
def health():
    try:
        db.execute('SELECT 1')      # database reachable?
        redis.ping()                # cache reachable?
        return {'status': 'ok'}, 200
    except Exception as e:
        return {'status': 'error', 'detail': str(e)}, 503

# Bad health endpoint — just returns 200 always
@app.route('/health')
def health():
    return 'ok', 200   # doesn't actually check anything
```

---

## 5. AWS Load Balancers (ALB, NLB, CLB)

### Application Load Balancer (ALB)

```
Best for: HTTP/HTTPS, microservices, containers, gRPC

Features:
- Path-based routing (/api → api-service, /static → static-service)
- Host-based routing (api.example.com → api-service)
- Header/method-based routing
- Redirects (HTTP → HTTPS)
- Fixed response (return 404 without hitting backend)
- WAF integration
- User authentication (Cognito, OIDC)
- WebSocket support
- gRPC support
- Lambda as target
- IP-based targets (for ECS/EKS)
```

```hcl
# ALB listener rules (priority order)
resource "aws_lb_listener_rule" "api" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }

  condition {
    path_pattern { values = ["/api/*"] }
  }
}

resource "aws_lb_listener_rule" "redirect_www" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 200

  action {
    type = "redirect"
    redirect {
      host        = "example.com"
      status_code = "HTTP_301"
    }
  }

  condition {
    host_header { values = ["www.example.com"] }
  }
}
```

### Network Load Balancer (NLB)

```
Best for: ultra-low latency, static IP, non-HTTP protocols

Features:
- Static IP per AZ (or Elastic IP)
- Ultra-low latency (~100 microseconds)
- Preserves source IP (no X-Forwarded-For needed)
- TCP, UDP, TLS passthrough
- Cross-zone load balancing
- Zonal isolation (traffic stays in AZ unless cross-zone enabled)
- PrivateLink compatible (expose services to other VPCs)

Use for:
- Databases (PostgreSQL, MySQL)
- Gaming servers
- IoT applications
- When static IP is required for whitelisting
```

### Classic Load Balancer (CLB) — Legacy

```
Original AWS LB — avoid for new architectures.
Only use if already exists and migration isn't planned.
Does both L4 and L7 but less feature-rich than ALB/NLB.
```

### Choosing the right AWS LB

```
Need path/host-based routing?          → ALB
Need WAF integration?                  → ALB
Serving HTTP/HTTPS traffic?            → ALB
Need static IP?                        → NLB
Need ultra-low latency?                → NLB
Need TCP/UDP (non-HTTP)?               → NLB
Need PrivateLink?                      → NLB
Exposing to Kubernetes?                → ALB (with AWS LB Controller)
```

---

## 6. Sticky Sessions

Sticky sessions (session affinity) ensure requests from the same client always go to the same backend.

### Why and when

```
When needed:
  - Stateful applications storing session data in memory
  - Applications that don't use distributed session storage
  - Long-running WebSocket connections

When NOT needed (preferred):
  - Stateless applications
  - Apps using Redis/database for session storage
  - REST APIs
```

### ALB sticky sessions (duration-based)

```hcl
resource "aws_lb_target_group" "app" {
  name     = "my-app"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id

  stickiness {
    type            = "lb_cookie"
    cookie_duration = 86400  # 1 day in seconds
    enabled         = true
  }
}
```

```
ALB sets cookie: AWSALB=<hash> or AWSALBAPP=<app-cookie>
Client sends cookie on subsequent requests
ALB routes to same target based on cookie hash

Duration-based: ALB generates cookie
Application-based: app generates cookie, ALB reads it
```

### Problems with sticky sessions

```
- If backend fails, session is lost anyway
- Uneven distribution (popular user → one server gets all their traffic)
- Prevents scaling down (can't remove server while sessions active)
- Better solution: store sessions externally (Redis, DynamoDB)
```

---

## 7. SSL Termination

### Termination at load balancer

```
Client ──── HTTPS ────► [Load Balancer] ──── HTTP ────► Backend
             TLS                              Plain
         terminated here

Benefits:
- Backend doesn't need TLS certificates
- Lower CPU on backends
- Centralized cert management
- Can inspect/modify HTTP traffic

AWS: ALB handles TLS, routes HTTP to targets
```

### End-to-end encryption (re-encryption)

```
Client ──── HTTPS ────► [Load Balancer] ──── HTTPS ────► Backend
             TLS                               TLS
         terminated                        re-encrypted

Benefits:
- Traffic encrypted throughout
- Compliance requirements
- Backend identity verification

AWS ALB: configure HTTPS listener + HTTPS target group
NLB: TLS listener + TLS target group, or TLS passthrough
```

### TLS passthrough

```
Client ──── HTTPS ────► [Load Balancer] ──── HTTPS ────► Backend
             TLS                               TLS
         NOT terminated                    terminated here

Benefits:
- Backend handles TLS (mutual TLS, client certs)
- LB can't inspect traffic (pure L4 forwarding)

AWS: NLB with TCP listener (not TLS)
```

---

## 8. Load Balancers in Kubernetes

### Service type LoadBalancer

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
    service.beta.kubernetes.io/aws-load-balancer-scheme: "internet-facing"
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
```

```
Creates: Cloud LB → Node's NodePort → kube-proxy → Pod
```

### AWS Load Balancer Controller (preferred for AWS)

```yaml
# Creates ALB for each Ingress
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-app
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip    # route directly to pod IPs
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/certificate-arn: arn:aws:acm:...
    alb.ingress.kubernetes.io/healthcheck-path: /health
spec:
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

### nginx Ingress Controller

```yaml
# One NLB/LB for all services, nginx routes internally
# More cost-effective than ALB per Ingress
annotations:
  nginx.ingress.kubernetes.io/rewrite-target: /
  nginx.ingress.kubernetes.io/ssl-redirect: "true"
  nginx.ingress.kubernetes.io/proxy-body-size: "50m"
  nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
```

---

## Cheatsheet

```bash
# AWS CLI
aws elbv2 describe-load-balancers
aws elbv2 describe-target-groups
aws elbv2 describe-target-health \
  --target-group-arn arn:aws:elasticloadbalancing:...

# Kubernetes
kubectl get svc -A | grep LoadBalancer     # find LB services
kubectl describe ingress my-ingress        # ingress details
kubectl get ingress -A

# Test LB
curl -I https://my-lb.example.com/health
curl -H "Host: api.example.com" http://lb-dns-name/api/status

# Check ALB access logs (if enabled in S3)
aws s3 ls s3://my-alb-logs/
```

---

*Next: [TLS/SSL Deep Dive →](./04-tls-ssl.md)*
