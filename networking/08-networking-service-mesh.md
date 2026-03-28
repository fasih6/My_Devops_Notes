# 🕸️ Service Mesh & Advanced Kubernetes Networking

Istio, Cilium, eBPF, and how advanced networking works inside a Kubernetes cluster.

---

## 📚 Table of Contents

- [1. Why Service Mesh?](#1-why-service-mesh)
- [2. How Service Mesh Works](#2-how-service-mesh-works)
- [3. Istio Deep Dive](#3-istio-deep-dive)
- [4. Cilium & eBPF](#4-cilium--ebpf)
- [5. Linkerd](#5-linkerd)
- [6. Kubernetes Networking Internals](#6-kubernetes-networking-internals)
- [7. Choosing a Service Mesh](#7-choosing-a-service-mesh)
- [Cheatsheet](#cheatsheet)

---

## 1. Why Service Mesh?

As microservices grow, cross-cutting networking concerns multiply:

```
Without service mesh — each service implements its own:
  ❌ mTLS (or no encryption between services)
  ❌ Retry logic (or none)
  ❌ Circuit breaking (or none)
  ❌ Distributed tracing (heavy instrumentation)
  ❌ Rate limiting (per-service)
  ❌ Traffic splitting (complex to implement)

With service mesh — infrastructure handles it automatically:
  ✅ mTLS between all services (zero code changes)
  ✅ Retries with backoff
  ✅ Circuit breaking
  ✅ Distributed tracing (automatic span injection)
  ✅ Rate limiting via policy
  ✅ Traffic splitting (canary, A/B testing)
```

---

## 2. How Service Mesh Works

### The sidecar pattern (Istio, Linkerd)

```
Pod without mesh:         Pod with mesh:
┌──────────────┐          ┌────────────────────────┐
│  Your app    │          │  Your app  │   Envoy   │
│  :8080       │          │  :8080     │  sidecar  │
└──────────────┘          │            │  :15001   │
                          └────────────────────────┘

All inbound AND outbound traffic intercepted by Envoy
App talks to localhost — Envoy handles all networking
App code is unmodified
```

### Traffic interception (iptables)

```
When Envoy sidecar is injected:
  iptables rules redirect ALL traffic through Envoy:

  Inbound: any port → Envoy (:15006) → your app (:8080)
  Outbound: any port → Envoy (:15001) → destination

  App calls "http://other-service:8080"
  → iptables intercepts → Envoy handles
  → Envoy applies: mTLS, retries, circuit breaking, tracing
  → Envoy forwards to destination Envoy
  → Destination Envoy forwards to destination app
```

### The eBPF approach (Cilium)

```
Without sidecar:
  No extra container per pod
  eBPF programs in the kernel intercept traffic
  Lower overhead, faster, simpler
  More transparent to workloads
```

---

## 3. Istio Deep Dive

Istio is the most feature-rich service mesh. Built on Envoy proxy.

### Architecture

```
Control Plane (istiod):
  Pilot     → pushes routing config to Envoy sidecars
  Citadel   → manages certificates (mTLS)
  Galley    → validates configuration

Data Plane:
  Envoy sidecar per pod — enforces policies, collects telemetry
```

### Installation

```bash
# Install Istio with istioctl
curl -L https://istio.io/downloadIstio | sh -
export PATH=$PWD/istio-1.20.0/bin:$PATH

# Install with default profile
istioctl install --set profile=default

# Enable sidecar injection for a namespace
kubectl label namespace production istio-injection=enabled

# Verify installation
istioctl verify-install
kubectl get pods -n istio-system
```

### Traffic management

#### VirtualService — routing rules

```yaml
# Route 90% to v1, 10% to v2 (canary deployment)
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: my-app
  namespace: production
spec:
  hosts:
    - my-app
  http:
    - match:
        - headers:
            x-canary:
              exact: "true"
      route:
        - destination:
            host: my-app
            subset: v2
    - route:
        - destination:
            host: my-app
            subset: v1
          weight: 90
        - destination:
            host: my-app
            subset: v2
          weight: 10
```

#### DestinationRule — traffic policies per subset

```yaml
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: my-app
  namespace: production
spec:
  host: my-app
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        h2UpgradePolicy: UPGRADE
    loadBalancer:
      simple: LEAST_CONN
    outlierDetection:
      consecutive5xxErrors: 5
      interval: 30s
      baseEjectionTime: 30s
  subsets:
    - name: v1
      labels:
        version: v1
    - name: v2
      labels:
        version: v2
```

#### Gateway — ingress/egress

```yaml
# Istio Gateway replaces traditional Ingress
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: my-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingressgateway
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: my-tls-secret
      hosts:
        - api.example.com

---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: api-vs
spec:
  hosts:
    - api.example.com
  gateways:
    - istio-system/my-gateway
  http:
    - route:
        - destination:
            host: my-api
            port:
              number: 8080
```

### Security — mTLS

```yaml
# Enforce mTLS for all services in namespace
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: production
spec:
  mtls:
    mode: STRICT    # STRICT = require mTLS, PERMISSIVE = allow both

---
# Authorization policy — who can talk to what
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-frontend
  namespace: production
spec:
  selector:
    matchLabels:
      app: backend
  rules:
    - from:
        - source:
            principals: ["cluster.local/ns/production/sa/frontend"]
      to:
        - operation:
            methods: ["GET", "POST"]
            paths: ["/api/*"]
```

### Observability

```bash
# Kiali — service mesh visualization
kubectl port-forward svc/kiali -n istio-system 20001:20001

# Distributed tracing (Jaeger)
kubectl port-forward svc/jaeger -n istio-system 16686:16686

# Metrics (Prometheus)
kubectl port-forward svc/prometheus -n istio-system 9090:9090

# Envoy stats for a pod
kubectl exec my-pod -c istio-proxy -- curl localhost:15000/stats
kubectl exec my-pod -c istio-proxy -- curl localhost:15000/clusters

# Check mTLS is working
istioctl authn tls-check my-pod.production
```

### Resilience features

```yaml
# Retries
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
spec:
  http:
    - retries:
        attempts: 3
        perTryTimeout: 2s
        retryOn: "5xx,retriable-4xx,connect-failure,reset"
      timeout: 10s
      route:
        - destination:
            host: my-service

---
# Circuit breaker (in DestinationRule)
spec:
  trafficPolicy:
    outlierDetection:
      consecutive5xxErrors: 5       # open circuit after 5 errors
      interval: 10s                  # evaluation window
      baseEjectionTime: 30s          # how long to eject
      maxEjectionPercent: 100        # max % of hosts to eject
```

---

## 4. Cilium & eBPF

Cilium is a CNI plugin and service mesh that uses eBPF instead of iptables or sidecars.

### What is eBPF?

```
eBPF (extended Berkeley Packet Filter):
  Run sandboxed programs in the Linux kernel
  Triggered by kernel events (network packets, syscalls, etc.)
  No kernel module needed, verified for safety
  Extremely fast — runs in kernel space

Traditional path:
  Packet → iptables rules (many) → conntrack → userspace → iptables (many) → output

eBPF path:
  Packet → eBPF program (direct kernel bypass) → output

Result: ~10x lower latency, ~5x higher throughput vs iptables
```

### Cilium installation

```bash
# Install with Helm
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set kubeProxyReplacement=strict \    # replace kube-proxy entirely
  --set hostServices.enabled=true \
  --set externalIPs.enabled=true \
  --set nodePort.enabled=true

# Verify
cilium status
cilium connectivity test
```

### Cilium Network Policy (L7 aware)

```yaml
# L3/L4 policy (like standard NetworkPolicy)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  endpointSelector:
    matchLabels:
      app: backend
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP

---
# L7 HTTP policy (Cilium-specific — can filter by HTTP method/path)
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: api-policy
spec:
  endpointSelector:
    matchLabels:
      app: api
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: frontend
      toPorts:
        - ports:
            - port: "8080"
              protocol: TCP
          rules:
            http:
              - method: "GET"
                path: "/api/products"
              - method: "POST"
                path: "/api/orders"
              # All other paths/methods DENIED automatically
```

### Hubble — observability for Cilium

```bash
# Hubble is Cilium's observability platform
cilium hubble enable

# Port-forward Hubble UI
cilium hubble ui

# CLI — watch traffic
hubble observe --pod-selector app=my-app
hubble observe --namespace production --verdict DROPPED
hubble observe --type drop --follow

# Get flows
hubble observe --from-pod production/frontend \
               --to-pod production/backend
```

### Cilium Cluster Mesh

```bash
# Connect two clusters for cross-cluster service discovery
cilium clustermesh enable
cilium clustermesh connect --destination-context k8s-cluster-2

# Services become accessible across clusters
# my-service.production.svc.cluster.local → pods in either cluster
```

---

## 5. Linkerd

Linkerd is a lightweight service mesh — simpler than Istio, lower overhead.

```bash
# Install Linkerd
curl --proto '=https' --tlsv1.2 -sSfL https://run.linkerd.io/install | sh
linkerd install --crds | kubectl apply -f -
linkerd install | kubectl apply -f -

# Inject sidecar (linkerd-proxy, not Envoy)
kubectl annotate namespace production \
  linkerd.io/inject=enabled

# Check mesh status
linkerd check
linkerd viz install | kubectl apply -f -
linkerd viz dashboard
```

### Linkerd vs Istio

| | Linkerd | Istio |
|--|---------|-------|
| **Proxy** | Linkerd2-proxy (Rust) | Envoy (C++) |
| **Complexity** | Simple | Complex |
| **Resource overhead** | Low (~10MB/pod) | High (~50MB/pod) |
| **Features** | Core mesh features | Full feature set |
| **Learning curve** | Gentle | Steep |
| **Protocols** | HTTP/1.1, HTTP/2, gRPC | All + TCP |
| **Best for** | Getting started, low overhead | Full-featured, complex routing |

---

## 6. Kubernetes Networking Internals

### How pod-to-pod networking works

```
Node 1                          Node 2
┌─────────────────────┐         ┌─────────────────────┐
│  Pod A (10.244.1.2) │         │  Pod B (10.244.2.3) │
│     │               │         │       │             │
│   veth0             │         │     veth0           │
│     │               │         │       │             │
│  cbr0 bridge        │         │  cbr0 bridge        │
│  (10.244.1.0/24)    │         │  (10.244.2.0/24)    │
│     │               │         │       │             │
│   eth0              │         │     eth0            │
└──────┼──────────────┘         └───────┼─────────────┘
       │                                │
       └────── Network (overlay) ───────┘
              or underlay routing

Packet: Pod A → Pod B
1. Pod A sends to 10.244.2.3
2. Kernel routes to cbr0 (not local subnet)
3. cbr0 sends to eth0 (node's physical interface)
4. CNI encapsulates (VXLAN/GENEVE) or routes via BGP
5. Arrives at Node 2's eth0
6. CNI decapsulates, routes to cbr0
7. cbr0 delivers to Pod B's veth0
```

### How Services work (kube-proxy + iptables)

```
Service ClusterIP: 10.96.100.1:80
Pods: 10.244.1.2:8080, 10.244.2.3:8080, 10.244.3.4:8080

iptables rules (created by kube-proxy):
  KUBE-SERVICES chain:
    -d 10.96.100.1/32 -p tcp --dport 80 → KUBE-SVC-XXXXX

  KUBE-SVC-XXXXX chain (load balancing):
    33% probability → KUBE-SEP-POD1
    50% probability → KUBE-SEP-POD2
    remaining       → KUBE-SEP-POD3

  KUBE-SEP-POD1 chain (DNAT):
    -j DNAT --to-destination 10.244.1.2:8080

Traffic flow:
  Pod A → 10.96.100.1:80
  → iptables: match KUBE-SERVICES → KUBE-SVC → random KUBE-SEP
  → DNAT: destination changed to 10.244.2.3:8080
  → packet sent to Pod B
  → response: SNAT back to 10.96.100.1:80 (conntrack handles this)
```

### IPVS mode (faster than iptables)

```bash
# Switch kube-proxy to IPVS mode
kubectl edit configmap kube-proxy -n kube-system
# Change: mode: "ipvs"

# Check IPVS rules
ipvsadm -Ln

# IPVS uses hash tables (O(1)) vs iptables linear scan (O(n))
# Much faster for large clusters with thousands of services
```

---

## 7. Choosing a Service Mesh

```
Don't use a service mesh if:
  - You have < 10 services
  - Team doesn't have bandwidth to manage it
  - Simple HTTP + JWT/API keys suffice
  - Monolith or very simple microservices

Use Linkerd if:
  - Want service mesh benefits without complexity
  - Low resource overhead matters
  - HTTP/gRPC traffic primarily
  - Team new to service mesh

Use Istio if:
  - Need advanced traffic management (canary, A/B)
  - Complex authorization policies
  - Multi-cluster support
  - Rich observability features
  - Team can invest in learning curve

Use Cilium if:
  - Maximum performance (eBPF vs iptables)
  - Want to replace kube-proxy too
  - Need L7 network policies (HTTP method/path)
  - Running on newer Linux kernels (5.10+)
  - AWS EKS (native IPAM support)
```

---

## Cheatsheet

```bash
# Istio
istioctl install --set profile=default
istioctl analyze                       # check for config issues
istioctl proxy-status                  # all proxies in sync?
kubectl label namespace prod istio-injection=enabled
kubectl exec pod -c istio-proxy -- curl localhost:15000/stats

# Cilium
cilium status
cilium connectivity test
hubble observe --namespace production --verdict DROPPED
hubble observe --follow --type drop

# Linkerd
linkerd check
linkerd viz dashboard
linkerd top deploy/my-app              # live request rate

# General K8s networking
kubectl get endpoints -A               # service targets
kubectl get networkpolicies -A         # network policies
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash
kubectl exec pod -- tcpdump -i any port 8080
```

---

*Next: [CDN & Edge Networking →](./09-cdn-edge-networking.md)*
