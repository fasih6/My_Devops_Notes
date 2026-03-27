# 🌐 Networking

Services, Ingress, DNS, CNI, and Network Policies — how pods communicate inside and outside the cluster.

---

## 📚 Table of Contents

- [1. Kubernetes Networking Model](#1-kubernetes-networking-model)
- [2. Services](#2-services)
- [3. Ingress](#3-ingress)
- [4. DNS in Kubernetes](#4-dns-in-kubernetes)
- [5. CNI Plugins](#5-cni-plugins)
- [6. Network Policies](#6-network-policies)
- [7. Service Mesh (Overview)](#7-service-mesh-overview)
- [Cheatsheet](#cheatsheet)

---

## 1. Kubernetes Networking Model

### Core networking rules

Kubernetes enforces these rules — enforced by the CNI plugin:

1. **Every pod gets its own IP** — no NAT between pods
2. **All pods can communicate with all other pods** — across nodes, without NAT
3. **Agents on a node can communicate with all pods on that node**
4. **Pod IP is the same from inside and outside** — no port mapping

```
Node 1                          Node 2
┌─────────────────┐             ┌─────────────────┐
│  Pod A           │             │  Pod C           │
│  IP: 10.244.1.2  │◄───────────►│  IP: 10.244.2.3  │
│                  │  direct     │                  │
│  Pod B           │  routing    │  Pod D           │
│  IP: 10.244.1.3  │             │  IP: 10.244.2.4  │
└─────────────────┘             └─────────────────┘
```

### Pod IPs are ephemeral

Pods are replaced constantly — new pod, new IP. That's why you never talk to pods directly by IP. You use **Services** which provide a stable endpoint.

---

## 2. Services

A Service provides a **stable IP and DNS name** to a set of pods, load-balancing traffic across them.

### Service types

| Type | Accessible from | Use case |
|------|----------------|---------|
| `ClusterIP` | Inside cluster only | Internal service-to-service |
| `NodePort` | Outside cluster via node IP:port | Development, on-prem without LB |
| `LoadBalancer` | Outside cluster via cloud LB | Production external exposure |
| `ExternalName` | Maps to external DNS name | Alias for external service |
| `Headless` | Direct pod DNS (no load balancing) | StatefulSets, direct pod access |

### ClusterIP (default)

```yaml
apiVersion: v1
kind: Service
metadata:
  name: my-app
  namespace: production
spec:
  type: ClusterIP           # default, can be omitted
  selector:
    app: my-app             # matches pod labels
  ports:
    - name: http
      port: 80              # Service port (what clients connect to)
      targetPort: 8080      # Container port (what pod listens on)
      protocol: TCP
    - name: metrics
      port: 9090
      targetPort: 9090
```

```bash
# Access from inside cluster
curl http://my-app.production.svc.cluster.local
curl http://my-app.production    # short form within namespace
curl http://my-app               # shortest form within same namespace
```

### NodePort

```yaml
spec:
  type: NodePort
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
      nodePort: 30080      # must be 30000-32767 (or omit for auto-assign)
```

```bash
# Access from outside
curl http://<any-node-ip>:30080
```

### LoadBalancer

```yaml
spec:
  type: LoadBalancer
  selector:
    app: my-app
  ports:
    - port: 80
      targetPort: 8080
  # Optional: request specific IP or annotations for cloud config
  loadBalancerIP: 10.0.0.100
  annotations:
    service.beta.kubernetes.io/aws-load-balancer-type: nlb
    service.beta.kubernetes.io/aws-load-balancer-cross-zone-load-balancing-enabled: "true"
```

```bash
# Get the external IP
kubectl get svc my-app
# EXTERNAL-IP will show once cloud LB is provisioned
```

### Headless Service

No ClusterIP — DNS returns pod IPs directly. Used for StatefulSets and direct pod addressing.

```yaml
spec:
  clusterIP: None    # makes it headless
  selector:
    app: postgres
  ports:
    - port: 5432
```

```bash
# DNS returns all pod IPs
dig postgres.production.svc.cluster.local
# Returns: 10.244.1.2, 10.244.2.3, 10.244.3.4

# Access specific pod (StatefulSet)
dig postgres-0.postgres.production.svc.cluster.local
```

### ExternalName

```yaml
spec:
  type: ExternalName
  externalName: my-database.us-east-1.rds.amazonaws.com
  # No selector — maps to external DNS name
```

### How Services route traffic

```
Client pod
    │
    │  connects to Service ClusterIP
    ▼
kube-proxy (iptables rules on the node)
    │
    │  selects a random healthy pod endpoint
    ▼
Target pod
```

```bash
# See Service endpoints (which pods are selected)
kubectl get endpoints my-app
kubectl describe endpoints my-app

# If endpoints are empty — selector doesn't match any pod labels
```

---

## 3. Ingress

An **Ingress** routes external HTTP/HTTPS traffic to internal Services based on hostname and path rules.

```
Internet
   │
   ▼
LoadBalancer Service (single entry point)
   │
   ▼
Ingress Controller (nginx, traefik, etc.)
   │
   ├── api.example.com       → api-service:80
   ├── app.example.com/v1    → app-v1-service:80
   └── app.example.com/v2    → app-v2-service:80
```

### Ingress Controller

Ingress rules do nothing without an **Ingress Controller** — a pod that reads Ingress objects and configures a reverse proxy.

```bash
# Install nginx ingress controller
helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx
helm install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace

# Check it's running
kubectl get pods -n ingress-nginx
kubectl get svc -n ingress-nginx    # note the EXTERNAL-IP
```

### Ingress manifest

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: my-ingress
  namespace: production
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
    nginx.ingress.kubernetes.io/ssl-redirect: "true"
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    cert-manager.io/cluster-issuer: letsencrypt-prod   # for TLS

spec:
  ingressClassName: nginx      # which controller to use

  tls:
    - hosts:
        - api.example.com
        - app.example.com
      secretName: tls-secret   # K8s Secret with TLS cert and key

  rules:
    - host: api.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: api-service
                port:
                  number: 80

    - host: app.example.com
      http:
        paths:
          - path: /v1
            pathType: Prefix
            backend:
              service:
                name: app-v1-service
                port:
                  number: 80
          - path: /v2
            pathType: Prefix
            backend:
              service:
                name: app-v2-service
                port:
                  number: 80
          - path: /
            pathType: Prefix
            backend:
              service:
                name: app-service
                port:
                  number: 80
```

### PathType options

| PathType | Behavior |
|----------|---------|
| `Exact` | Exact path match only `/foo` ≠ `/foo/` |
| `Prefix` | Prefix match `/foo` matches `/foo`, `/foo/bar` |
| `ImplementationSpecific` | Controller decides |

### TLS with cert-manager

```bash
# Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true
```

```yaml
# ClusterIssuer — issues certificates from Let's Encrypt
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: admin@example.com
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
      - http01:
          ingress:
            class: nginx
```

---

## 4. DNS in Kubernetes

### CoreDNS

Kubernetes runs **CoreDNS** as the cluster DNS server. Every pod is configured to use it.

```bash
# CoreDNS pods
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Pod's DNS config
kubectl exec my-pod -- cat /etc/resolv.conf
# nameserver 10.96.0.10        ← CoreDNS cluster IP
# search default.svc.cluster.local svc.cluster.local cluster.local
# options ndots:5
```

### DNS naming scheme

```
<service>.<namespace>.svc.<cluster-domain>

Examples:
my-app.production.svc.cluster.local
postgres.production.svc.cluster.local
redis.default.svc.cluster.local

# Short forms (within the cluster):
my-app.production.svc.cluster.local   # full
my-app.production                      # from any namespace
my-app                                 # from same namespace only
```

### StatefulSet pod DNS

```
<pod-name>.<service>.<namespace>.svc.<cluster-domain>

postgres-0.postgres.production.svc.cluster.local
postgres-1.postgres.production.svc.cluster.local
```

### DNS debugging

```bash
# Test DNS from inside a pod
kubectl exec -it my-pod -- nslookup kubernetes.default
kubectl exec -it my-pod -- nslookup my-service.production
kubectl exec -it my-pod -- dig my-service.production.svc.cluster.local

# Run a debug pod with DNS tools
kubectl run dns-debug --image=nicolaka/netshoot -it --rm -- bash
# Inside: nslookup, dig, curl all available

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns

# CoreDNS ConfigMap (customization)
kubectl get configmap coredns -n kube-system -o yaml
```

---

## 5. CNI Plugins

The **Container Network Interface (CNI)** plugin is responsible for pod networking — assigning IPs, enabling pod-to-pod communication, and implementing Network Policies.

### Popular CNI plugins

| Plugin | Features | Best for |
|--------|---------|---------|
| **Calico** | Network Policies, BGP routing, eBPF support | Most production clusters |
| **Flannel** | Simple overlay network, no Network Policies | Simple setups, dev clusters |
| **Cilium** | eBPF-based, advanced Network Policies, L7 visibility | High-performance, observability |
| **Weave** | Simple, works across clouds | Multi-cloud setups |
| **AWS VPC CNI** | Uses real VPC IPs for pods | EKS clusters |

### How CNI works

```
New pod scheduled on node
        │
        ▼
kubelet calls CNI plugin
        │
        ▼
CNI plugin:
  1. Creates veth pair (virtual ethernet)
  2. Moves one end into pod network namespace
  3. Assigns IP from pod CIDR
  4. Configures routing on host
        │
        ▼
Pod has IP, can communicate with other pods
```

```bash
# Check which CNI is running
kubectl get pods -n kube-system | grep -E "calico|flannel|cilium|weave"
ls /etc/cni/net.d/                    # CNI config files
ls /opt/cni/bin/                      # CNI binaries
```

---

## 6. Network Policies

By default, all pods can communicate with all other pods. **Network Policies** restrict this traffic.

> ⚠️ Network Policies only work if your CNI plugin supports them (Calico, Cilium, Weave — yes; Flannel — no).

### Default deny all

```yaml
# Deny all ingress traffic to pods in this namespace
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-ingress
  namespace: production
spec:
  podSelector: {}    # applies to ALL pods
  policyTypes:
    - Ingress
  # No ingress rules = deny all ingress
```

```yaml
# Deny all egress
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-egress
  namespace: production
spec:
  podSelector: {}
  policyTypes:
    - Egress
```

### Allow specific traffic

```yaml
# Allow frontend to talk to backend on port 8080
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend          # this policy applies to backend pods

  policyTypes:
    - Ingress

  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: frontend  # allow FROM frontend pods
      ports:
        - protocol: TCP
          port: 8080
```

```yaml
# Allow backend to reach database
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-backend-to-db
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: postgres         # applies to postgres pods

  policyTypes:
    - Ingress

  ingress:
    - from:
        - podSelector:
            matchLabels:
              app: backend
        - namespaceSelector:
            matchLabels:
              name: production   # only from production namespace
      ports:
        - protocol: TCP
          port: 5432
```

### Allow egress to DNS and specific services

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-egress
  namespace: production
spec:
  podSelector:
    matchLabels:
      app: backend

  policyTypes:
    - Egress

  egress:
    # Allow DNS
    - to:
        - namespaceSelector:
            matchLabels:
              kubernetes.io/metadata.name: kube-system
      ports:
        - protocol: UDP
          port: 53
        - protocol: TCP
          port: 53

    # Allow to database
    - to:
        - podSelector:
            matchLabels:
              app: postgres
      ports:
        - protocol: TCP
          port: 5432

    # Allow to external API
    - to:
        - ipBlock:
            cidr: 0.0.0.0/0
            except:
              - 10.0.0.0/8       # block access to internal network
      ports:
        - protocol: TCP
          port: 443
```

### Network Policy selectors reference

```yaml
ingress:
  - from:
      # By pod labels
      - podSelector:
          matchLabels:
            app: frontend

      # By namespace
      - namespaceSelector:
          matchLabels:
            environment: production

      # By pod AND namespace (both must match)
      - namespaceSelector:
          matchLabels:
            environment: production
        podSelector:
          matchLabels:
            app: frontend

      # By IP range
      - ipBlock:
          cidr: 10.0.0.0/8
          except:
            - 10.1.0.0/16
```

---

## 7. Service Mesh (Overview)

A service mesh adds a layer of infrastructure for service-to-service communication — without changing application code.

### What a service mesh provides

| Feature | Without mesh | With mesh |
|---------|-------------|----------|
| mTLS | Manual, per-app | Automatic |
| Retries | Per-app | Automatic |
| Circuit breaking | Per-app | Automatic |
| Traffic splitting | Complex | Simple config |
| Observability (L7) | Per-app instrumentation | Automatic |

### How it works (sidecar pattern)

```
Pod
├── Your app container
└── Envoy sidecar (injected automatically)
        │
        │  All traffic goes through Envoy
        ▼
Envoy sidecar of target pod
└── Your app container
```

### Popular service meshes

| Mesh | Proxy | Best for |
|------|-------|---------|
| **Istio** | Envoy | Feature-rich, complex |
| **Linkerd** | Linkerd2-proxy | Simpler, lower overhead |
| **Cilium** | eBPF | High performance, no sidecar needed |

---

## Cheatsheet

```bash
# Services
kubectl get svc
kubectl get svc -A
kubectl describe svc my-service
kubectl get endpoints my-service   # which pods are selected

# Port forwarding
kubectl port-forward svc/my-service 8080:80
kubectl port-forward pod/my-pod 8080:8080

# Ingress
kubectl get ingress -A
kubectl describe ingress my-ingress

# DNS debugging
kubectl exec -it pod -- nslookup my-service.namespace
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash

# Network policies
kubectl get networkpolicies -A
kubectl describe networkpolicy allow-frontend

# Common DNS patterns
# Same namespace:     my-service
# Cross-namespace:    my-service.other-namespace
# Full:               my-service.namespace.svc.cluster.local
# StatefulSet pod:    pod-0.svc.namespace.svc.cluster.local
```

---

*Next: [Storage →](./04-storage.md) — PersistentVolumes, PVCs, StorageClasses, and CSI drivers.*
