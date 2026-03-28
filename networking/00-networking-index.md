# 🌐 Networking Deep Dive

A complete networking knowledge base for DevOps — from TCP/IP fundamentals to service meshes and CDNs.

> Networking is the invisible glue of every system. When production breaks, the cause is almost always networking. This folder gives you the deep understanding to debug anything and design robust systems.

---

## 🗺️ Learning Path

```
01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10
 │     │     │     │     │     │     │     │     │     │
 │     │     │     │     │     │     │     │     │     └── Interview prep
 │     │     │     │     │     │     │     │     └──────── CDN & edge
 │     │     │     │     │     │     │     └────────────── Service mesh
 │     │     │     │     │     │     └──────────────────── Debug anything
 │     │     │     │     │     └────────────────────────── Firewalls
 │     │     │     │     └──────────────────────────────── DNS
 │     │     │     └────────────────────────────────────── TLS/certs
 │     │     └──────────────────────────────────────────── Load balancers
 │     └────────────────────────────────────────────────── VPCs & cloud
 └──────────────────────────────────────────────────────── TCP/IP foundations
```

---

## 📚 Contents

| # | File | What you'll learn |
|---|------|------------------|
| 01 | [Core Concepts](./01-core-concepts.md) | OSI model, TCP/IP, subnets, routing, ARP, NAT, TCP handshake |
| 02 | [VPCs & Cloud Networking](./02-vpc-cloud-networking.md) | AWS VPC, subnets, IGW, NAT Gateway, peering, Transit Gateway, endpoints |
| 03 | [Load Balancers](./03-load-balancers.md) | L4 vs L7, ALB/NLB, algorithms, health checks, SSL termination |
| 04 | [TLS/SSL](./04-tls-ssl.md) | Certificates, TLS handshake, mTLS, cert-manager, ACM |
| 05 | [DNS Deep Dive](./05-dns-deep-dive.md) | Resolution, record types, Route53, CoreDNS, split-horizon |
| 06 | [Firewalls & Security Groups](./06-firewalls-security-groups.md) | iptables, Security Groups, NACLs, GCP firewall, WAF |
| 07 | [Network Troubleshooting](./07-network-troubleshooting.md) | Tools, methodology, scenarios, cloud + K8s debugging |
| 08 | [Service Mesh & K8s Networking](./08-service-mesh-kubernetes-networking.md) | Istio, Cilium/eBPF, Linkerd, K8s networking internals |
| 09 | [CDN & Edge Networking](./09-cdn-edge-networking.md) | CloudFront, caching, cache invalidation, edge security |
| 10 | [Interview Q&A](./10-interview-qa.md) | Core, scenario-based, and advanced networking interview questions |

---

## ⚡ Quick Reference

### Subnetting cheatsheet

```
CIDR  Hosts   Mask
/24   254      255.255.255.0
/25   126      255.255.255.128
/26   62       255.255.255.192
/27   30       255.255.255.224
/28   14       255.255.255.240
/29   6        255.255.255.248
/30   2        255.255.255.252
/32   1 (host) 255.255.255.255

Private ranges:
  10.0.0.0/8       (16M addresses)
  172.16.0.0/12    (1M addresses)
  192.168.0.0/16   (65K addresses)
```

### TCP states

```
LISTEN      → waiting for connection
ESTABLISHED → active connection
TIME_WAIT   → waiting after close (2*MSL)
CLOSE_WAIT  → received FIN, app hasn't closed
```

### Troubleshooting commands

```bash
# Reachability
ping -c 4 10.0.0.5
mtr --report 10.0.0.5
nc -zv 10.0.0.5 443
curl -v https://10.0.0.5/health

# Ports
ss -tulnp | grep :8080
lsof -i :8080

# DNS
dig api.example.com +short
dig @8.8.8.8 api.example.com
dig +trace api.example.com

# Capture
tcpdump -i eth0 port 443 -nn
tcpdump -i eth0 host 10.0.0.5 -w /tmp/cap.pcap

# Routes
ip route
ip route get 8.8.8.8

# Kubernetes
kubectl get endpoints my-svc
kubectl exec pod -- nslookup my-svc
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash
```

---

## 🧠 Key Concepts at a Glance

| Concept | One-line summary |
|---------|-----------------|
| **OSI L3** | Network layer — IP addresses, routing, subnets |
| **OSI L4** | Transport layer — TCP/UDP, ports, connection state |
| **OSI L7** | Application layer — HTTP, DNS, TLS |
| **CIDR** | IP/prefix notation — /24 = 254 hosts |
| **Private IPs** | 10.x, 172.16-31.x, 192.168.x — not routable on internet |
| **Default route** | 0.0.0.0/0 — where packets go if no better match |
| **ARP** | Resolves IP → MAC address on local network |
| **NAT** | Translates private IPs to public for internet access |
| **SNAT** | Outbound NAT (AWS NAT Gateway) |
| **DNAT** | Inbound port forwarding (Docker port mapping) |
| **TCP handshake** | SYN → SYN-ACK → ACK (3-way) |
| **TIME_WAIT** | TCP state after close — waits 2*MSL for stray packets |
| **VPC** | Isolated virtual network in the cloud |
| **Public subnet** | Has route to Internet Gateway |
| **Private subnet** | No IGW route — outbound via NAT Gateway |
| **Security Group** | Stateful, instance-level, allow-only |
| **NACL** | Stateless, subnet-level, allow + deny, ordered |
| **VPC Peering** | Private VPC-to-VPC connection (non-transitive) |
| **Transit Gateway** | Hub-and-spoke multi-VPC routing (transitive) |
| **VPC Endpoint** | Private access to AWS services without internet |
| **ALB** | L7 HTTP LB — path/host routing, WAF, SSL termination |
| **NLB** | L4 TCP/UDP LB — ultra-low latency, static IP |
| **TLS** | Encrypts + authenticates network connections |
| **mTLS** | Both client and server present certificates |
| **cert-manager** | Auto-provisions and renews K8s TLS certificates |
| **DNS TTL** | How long resolvers cache a record |
| **Split-horizon DNS** | Same domain returns different IPs inside vs outside VPC |
| **CoreDNS** | Kubernetes cluster DNS server |
| **iptables** | Linux kernel firewall — also used by Docker + Kubernetes |
| **eBPF** | Run programs in Linux kernel — used by Cilium for fast networking |
| **Service mesh** | Infrastructure layer handling mTLS, retries, observability |
| **CDN** | Serves content from edge locations near users |
| **Cache-Control** | HTTP header controlling how long content is cached |
| **Edge location** | CDN PoP close to users for low latency |

---

## 🗂️ Folder Structure

```
networking/
├── 00-networking-index.md             ← You are here
├── 01-core-concepts.md
├── 02-vpc-cloud-networking.md
├── 03-load-balancers.md
├── 04-tls-ssl.md
├── 05-dns-deep-dive.md
├── 06-firewalls-security-groups.md
├── 07-network-troubleshooting.md
├── 08-service-mesh-kubernetes-networking.md
├── 09-cdn-edge-networking.md
└── 10-interview-qa.md
```

---

## 🔗 How Networking Connects to the Rest of Your Notes

| Topic | Connection |
|-------|-----------|
| **Kubernetes** | CNI handles pod networking, CoreDNS for service discovery, kube-proxy for Services |
| **Helm** | Ingress controllers (nginx, ALB) deployed via Helm manage L7 routing |
| **Docker** | Docker uses iptables NAT for port mapping, bridge networks for container DNS |
| **Terraform** | Provisions VPCs, subnets, SGs, ALBs, Route53 records, CloudFront distributions |
| **Observability** | Network metrics (latency, error rate, packet loss) are key SLIs |
| **Linux** | iptables, ip commands, /proc/sys/net — all Linux networking primitives |

---

*Notes are living documents — updated as I learn and build.*
