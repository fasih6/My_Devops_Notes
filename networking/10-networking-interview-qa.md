# 🎯 Networking Interview Q&A

Real networking questions asked in DevOps interviews — with complete answers.

---

## 📚 Table of Contents

- [🔥 Core Concepts](#-core-concepts)
- [☁️ Cloud Networking](#️-cloud-networking)
- [⚖️ Load Balancers & TLS](#️-load-balancers--tls)
- [🔍 DNS](#-dns)
- [🔥 Firewalls & Security](#-firewalls--security)
- [☸️ Kubernetes Networking](#️-kubernetes-networking)
- [🔥 Scenario-Based Questions](#-scenario-based-questions)
- [🧠 Advanced Questions](#-advanced-questions)
- [💬 Questions to Ask the Interviewer](#-questions-to-ask-the-interviewer)

---

## 🔥 Core Concepts

---

**Q: Explain the OSI model and which layers matter most for DevOps.**

The OSI model has 7 layers describing how data flows through a network. For DevOps, the most relevant are:

**Layer 3 (Network)** — IP addresses, routing, subnets. This is where VPCs, CIDR blocks, and route tables operate.

**Layer 4 (Transport)** — TCP and UDP, ports, connection state. Load balancer types (L4 vs L7), security group port rules, and connection timeouts live here.

**Layer 7 (Application)** — HTTP, HTTPS, DNS, gRPC. Ingress controllers, path-based routing, WAF rules, and SSL termination all operate here.

When debugging: start at L1 (is the interface up?) and work up. Most DevOps incidents are at L3/L4 (routing, firewall) or L7 (app error, DNS).

---

**Q: What is the difference between TCP and UDP? When would you use each?**

**TCP** is connection-oriented — establishes a session via the three-way handshake (SYN→SYN-ACK→ACK), guarantees ordered delivery, and retransmits lost packets. The overhead makes it reliable but slightly slower.

**UDP** is connectionless — just sends packets with no handshake, no acknowledgment, no ordering guarantee. If a packet is lost, it's gone unless the application handles it.

Use TCP for: databases, web (HTTP), file transfers, SSH — anything where data integrity matters.

Use UDP for: DNS (small, fast), video streaming (stale frame better than delayed frame), VoIP, gaming, and QUIC/HTTP3 (which builds reliability on top of UDP).

---

**Q: What is NAT and why is it used?**

NAT (Network Address Translation) translates private IP addresses to public ones. It allows many devices with private IPs (10.x, 172.16.x, 192.168.x) to share one public IP.

There are two types relevant to DevOps:

**SNAT (Source NAT)** — outbound traffic from a private network to the internet. The NAT gateway replaces the private source IP with its own public IP. AWS NAT Gateway does this.

**DNAT (Destination NAT)** — port forwarding. Incoming traffic to a public IP:port is redirected to a private IP:port. Used by Docker port mapping, Kubernetes NodePort, and iptables DNAT rules.

---

**Q: What is a subnet and how do you calculate how many hosts fit in one?**

A subnet is a subdivision of an IP network. In CIDR notation, the prefix length tells you how many bits are the network portion — the remaining bits are for hosts.

Formula: `2^(32 - prefix) - 2` = usable hosts (subtract 2 for network and broadcast addresses).

Common examples:
- `/24` → 2⁸ - 2 = 254 hosts
- `/25` → 2⁷ - 2 = 126 hosts  
- `/26` → 2⁶ - 2 = 62 hosts
- `/28` → 2⁴ - 2 = 14 hosts

In AWS, subnets lose 5 addresses to AWS reserved uses (network, VPC router, DNS, future, broadcast), so a `/24` gives 251 usable IPs.

---

## ☁️ Cloud Networking

---

**Q: What is the difference between a public and private subnet in AWS?**

A **public subnet** has a route to the Internet Gateway (`0.0.0.0/0 → igw-xxx`). Instances can have public IPs and be directly reachable from the internet. Use for: ALBs, NAT Gateways, bastion hosts.

A **private subnet** has no route to the Internet Gateway. Instances have only private IPs. Outbound internet access (for updates, pulling images) goes through a NAT Gateway in the public subnet. Use for: application servers, databases, EKS nodes.

---

**Q: What is VPC peering and what are its limitations?**

VPC peering creates a private network connection between two VPCs — traffic stays on AWS's backbone, not the internet. You connect them by creating a peering connection and adding routes in both VPCs' route tables.

Key limitations:
- **Non-transitive** — if A↔B and B↔C, A cannot reach C via B. You'd need A↔C peering separately.
- **No overlapping CIDRs** — 10.0.0.0/16 can't peer with 10.0.0.0/16.
- **Must update both route tables** and security groups.
- **Scales poorly** — 10 VPCs need 45 peerings (N*(N-1)/2).

For connecting many VPCs, use Transit Gateway instead — it's a hub-and-spoke model where VPCs connect to the TGW and routing is transitive.

---

**Q: What is a VPC endpoint and why would you use one?**

A VPC endpoint lets EC2 instances/pods access AWS services (S3, DynamoDB, SSM, ECR, etc.) without traffic leaving the AWS network — no internet, no NAT Gateway required.

Two types:
- **Gateway endpoints** (S3, DynamoDB only) — free, add to route tables
- **Interface endpoints** — an ENI in your VPC, private IP, used for most AWS services

Why use them:
1. **Cost** — S3 gateway endpoint saves NAT Gateway data processing charges (~$0.045/GB)
2. **Security** — private access, no internet exposure
3. **Required for private EKS nodes** — nodes without NAT need interface endpoints for ECR, EC2, SSM

---

## ⚖️ Load Balancers & TLS

---

**Q: What is the difference between an L4 and L7 load balancer?**

An **L4 load balancer** operates at the transport layer — it sees IP addresses and TCP/UDP ports, routes connections, but doesn't inspect the content. It's fast and protocol-agnostic. AWS NLB is L4.

An **L7 load balancer** operates at the application layer — it terminates and re-initiates connections, reads HTTP headers, URL paths, cookies, and can make routing decisions based on content. It can redirect HTTP to HTTPS, route `/api/*` to the API service and `/static/*` to S3. AWS ALB is L7.

Use NLB for: databases, gaming, anything non-HTTP, ultra-low latency, static IP requirement.
Use ALB for: web applications, APIs, microservices, Kubernetes Ingress.

---

**Q: Explain the TLS handshake.**

TLS 1.3 (simplified, 1 round trip):
1. **ClientHello** — client sends supported TLS versions, cipher suites, and its Diffie-Hellman key share
2. **ServerHello + Certificate + CertificateVerify + Finished** — server chooses cipher, sends its DH key share, certificate, and a Finished message (all encrypted with derived keys)
3. **Client Finished** — client verifies certificate against trusted CAs, derives the same session keys, sends Finished
4. **Data flows** encrypted with symmetric session keys

The key exchange uses Diffie-Hellman — both sides derive the same session key without ever sending it over the wire. Even if someone records the traffic and later gets the server's private key, they can't decrypt it (perfect forward secrecy).

---

**Q: What is mTLS and when would you use it?**

Standard TLS authenticates the server to the client. mTLS (mutual TLS) adds client authentication — both sides present certificates and verify each other.

Use for:
- **Service mesh** — Istio and Linkerd enforce mTLS between all pods. Even if an attacker gets inside the cluster, they can't impersonate a service without a valid certificate.
- **API authentication** — client presents a certificate instead of an API key. Harder to leak than a token.
- **Zero trust networking** — "never trust, always verify" — every service must prove identity.

---

## 🔍 DNS

---

**Q: Walk me through what happens when you type a URL in a browser.**

1. Browser checks its DNS cache for the hostname
2. If not cached, asks the OS resolver (/etc/resolv.conf → usually 8.8.8.8 or ISP's DNS)
3. Resolver checks its own cache
4. If not cached, resolver starts recursive resolution:
   - Asks a root name server: "who handles .com?"
   - Root says: "ask a.gtld-servers.net"
   - Resolver asks TLD server: "who handles example.com?"
   - TLD says: "ask ns1.example.com"
   - Resolver asks authoritative server: "what's the IP for api.example.com?"
   - Gets the answer (e.g., 93.184.216.34 with TTL 300)
5. Resolver caches the answer and returns it to the browser
6. Browser opens TCP connection to 93.184.216.34:443
7. TLS handshake (verifies server cert, establishes encrypted session)
8. Browser sends HTTP GET request
9. Server responds with HTML

---

**Q: What is a TTL and why does it matter for DNS migrations?**

TTL (Time To Live) is how long DNS resolvers cache a record. If TTL is 3600, resolvers hold the cached answer for 1 hour before re-querying.

For migrations, TTL matters enormously:

**Before migration** (1-2 days in advance): lower the TTL to 60 seconds. Wait for the current TTL to expire everywhere (so all caches have the new low TTL).

**During migration**: change the DNS record to the new IP. Because TTL is 60s, traffic cuts over within ~60 seconds.

**After migration** (when stable): raise TTL back to normal (300-3600s) to reduce DNS query load.

If you change a record without lowering TTL first, some users will be stuck on the old IP for up to the full TTL duration — sometimes hours.

---

**Q: What is split-horizon DNS?**

Split-horizon DNS returns different answers for the same hostname depending on where the query comes from.

Common use case: `api.example.com` should resolve to:
- The external ALB IP (93.x.x.x) for internet users
- The internal ALB IP (10.0.x.x) for traffic within the VPC

In AWS, you create both a public hosted zone and a private hosted zone for the same domain. The private zone is associated with a VPC — queries from within that VPC get the private answer. Internet queries get the public answer.

This avoids "hairpinning" (internal traffic going out to the internet and back) and keeps internal traffic private.

---

## 🔥 Firewalls & Security

---

**Q: What is the difference between AWS Security Groups and NACLs?**

**Security Groups** are stateful, instance-level firewalls. Stateful means if you allow inbound port 80, the return traffic is automatically allowed — you only write allow rules, no explicit return rules needed. They only allow, never deny. All rules are evaluated and the most permissive wins.

**NACLs** are stateless, subnet-level firewalls. Stateless means you must explicitly allow both directions — inbound and outbound (including ephemeral ports 1024-65535 for return traffic). They can both allow and deny. Rules are evaluated in number order — first match wins.

In practice: use Security Groups for everything. Use NACLs only when you need to explicitly block a CIDR range across all resources in a subnet — like blocking a known malicious IP.

---

## ☸️ Kubernetes Networking

---

**Q: How does a Kubernetes Service route traffic to pods?**

When you create a ClusterIP Service, kube-proxy (running on every node) creates iptables DNAT rules:

1. Service gets a virtual ClusterIP (e.g., 10.96.0.1)
2. kube-proxy creates iptables rules: traffic to 10.96.0.1:80 → randomly DNAT to one of the pod IPs
3. Pod sends request to ClusterIP → iptables intercepts → rewrites destination to a pod IP → sends to that pod
4. Response: conntrack (connection tracking) reverses the NAT for the return packet

kube-proxy watches the API server for Service and Endpoints changes and keeps iptables rules up to date. When a pod dies, its IP is removed from Endpoints and the iptables rules are updated within seconds.

---

**Q: What is the difference between a ClusterIP, NodePort, and LoadBalancer service?**

**ClusterIP** (default) — virtual IP only accessible within the cluster. Used for service-to-service communication.

**NodePort** — exposes the service on a static port (30000-32767) on every node. Accessible from outside via `<any-node-ip>:<nodeport>`. kube-proxy routes to the right pod. Useful for development or when you manage your own load balancer.

**LoadBalancer** — creates a cloud load balancer (AWS ELB, GCP LB) pointing to the NodePort. The single external IP/DNS routes through the cloud LB → NodePort → kube-proxy → pod. This is how you expose services externally in production on cloud clusters.

---

## 🔥 Scenario-Based Questions

---

**Scenario 1: An application suddenly can't reach an external API. Walk through your debug process.**

```
1. Verify the problem
   curl -v https://external-api.example.com    # from the affected pod/host
   
2. Is it DNS?
   dig external-api.example.com                # does it resolve?
   dig @8.8.8.8 external-api.example.com      # try different resolver
   
3. Is it routing/network?
   curl -v https://8.8.8.8                     # skip DNS, use IP
   ping external-api.example.com              # basic reachability
   mtr external-api.example.com               # trace the path
   
4. Is it the firewall?
   nc -zv external-api.example.com 443        # can we reach port 443?
   Check security group outbound rules
   Check NACL rules
   
5. Is it the NAT Gateway? (if in private subnet)
   curl https://checkip.amazonaws.com         # should show NAT EIP
   Check NAT Gateway is in RUNNING state
   Check route table: 0.0.0.0/0 → nat-xxx
   
6. Is it the external API?
   curl from a different machine/network
   Check their status page
```

---

**Scenario 2: Users in Europe experience high latency to your US-hosted app. What do you do?**

```
Short-term:
  1. Measure: curl timing breakdown → is it DNS, connect, or TTFB?
  2. Add CloudFront or another CDN in front of static assets
  3. Cache API responses at the CDN where possible

Medium-term:
  4. Deploy to eu-central-1 (Frankfurt) for European users
  5. Use Route53 latency-based routing: EU users → Frankfurt, US users → us-east-1
  6. Database: use read replicas in EU, writes go to US primary

Long-term:
  7. Evaluate multi-region active-active architecture
  8. Use a global database (DynamoDB Global Tables, CockroachDB, PlanetScale)
```

---

**Scenario 3: A Kubernetes pod can reach external services but can't reach another pod in the same cluster. What's wrong?**

```
1. Check if the target service exists
   kubectl get svc my-service -n production
   
2. Check service endpoints — are pods selected?
   kubectl get endpoints my-service -n production
   # If ENDPOINTS = <none> → selector doesn't match pod labels
   
3. Check selector vs pod labels
   kubectl describe svc my-service | grep Selector
   kubectl get pods --show-labels -n production
   
4. Test DNS resolution
   kubectl exec source-pod -- nslookup my-service.production.svc.cluster.local
   
5. Test connectivity directly to pod IP (bypass Service)
   TARGET_IP=$(kubectl get pod target-pod -o jsonpath='{.status.podIP}')
   kubectl exec source-pod -- nc -zv $TARGET_IP 8080
   
6. Check NetworkPolicy — is traffic being blocked?
   kubectl get networkpolicies -n production
   kubectl describe networkpolicy -n production
   
7. Check if CNI plugin is running
   kubectl get pods -n kube-system | grep -E "calico|cilium|aws-node"
```

---

**Scenario 4: Your site's SSL certificate expired. What's the immediate fix and how do you prevent it?**

```
Immediate fix:
  1. If using cert-manager:
     kubectl delete certificate my-cert -n production
     kubectl apply -f certificate.yaml   # recreate → triggers renewal
     kubectl describe certificate my-cert -n production   # watch status

  2. If using ACM:
     ACM renews automatically — check if validation DNS record still exists
     aws acm describe-certificate --certificate-arn arn:...
     
  3. If manual:
     Renew certificate from CA
     Update secret in Kubernetes or load in ALB/nginx
     
Prevention:
  1. Use cert-manager (auto-renews 30 days before expiry)
  2. Use ACM for ALB/CloudFront (auto-renews)
  3. Set up monitoring:
     Prometheus + blackbox exporter:
     probe_ssl_earliest_cert_expiry - time() < 30 * 24 * 3600
     Alert: "Certificate expires in less than 30 days"
  4. AWS Certificate Manager has expiry notifications via EventBridge
```

---

## 🧠 Advanced Questions

---

**Q: Explain how eBPF makes Cilium faster than traditional iptables-based networking.**

iptables processes network packets using linked lists of rules — every packet traverses the entire chain until a match is found. With thousands of Kubernetes Services, this is O(n) per packet. Adding or removing rules also requires rewriting entire chains.

eBPF runs small sandboxed programs directly in the Linux kernel, triggered by network events. Cilium installs eBPF programs that use hash maps for lookups — O(1) per packet regardless of how many services exist. Network policy enforcement, load balancing, and observability all happen in kernel space without the userspace overhead of traditional approaches.

Result: ~10x lower latency and ~5x higher throughput compared to iptables kube-proxy mode, especially at scale with thousands of services.

---

**Q: What is the difference between a service mesh sidecar approach and eBPF-based approach?**

**Sidecar approach** (Istio/Linkerd): An Envoy or Linkerd proxy is injected as an additional container in every pod. iptables rules intercept all traffic and redirect it through the sidecar. The sidecar handles mTLS, retries, circuit breaking, and telemetry. Cons: extra container per pod (~50-100MB RAM), network latency added by sidecar hops, operational complexity.

**eBPF approach** (Cilium): No sidecar container. eBPF programs in the kernel handle networking, security enforcement, and telemetry collection. Lower overhead, lower latency, simpler pod spec (no injected container). Cons: requires newer kernel (5.10+), more complex to debug when things go wrong.

The trend is toward eBPF — Cilium is now the default CNI on many managed Kubernetes services.

---

**Q: What causes the ephemeral port problem in Kubernetes and how is it solved?**

When a pod makes many outbound connections (to a database, Redis, external API), Linux assigns an ephemeral source port for each connection from the range 32768-60999. Kubernetes pods doing SNAT (Source NAT) through the node's IP can exhaust this range under high connection rates — causing "cannot assign requested address" errors.

Solutions:
1. **Connection pooling** — reuse connections instead of creating new ones per request
2. **Increase ephemeral port range** — `sysctl net.ipv4.ip_local_port_range = 1024 65535`
3. **Use IPVS** mode for kube-proxy (better connection management than iptables)
4. **Cilium** — avoids SNAT entirely for pod-to-pod traffic in native routing mode

---

## 💬 Questions to Ask the Interviewer

**On their network architecture:**
- "How is your VPC structured — single VPC with many subnets, or multiple VPCs?"
- "Do you use Transit Gateway or VPC peering for connectivity between environments?"
- "Are your EKS nodes fully private, or do they have internet access via NAT?"

**On their tooling:**
- "What CNI plugin do you use — Calico, Cilium, or the AWS VPC CNI?"
- "Do you use a service mesh? Which one and for what use cases?"
- "How do you manage TLS certificates — cert-manager, ACM, or manual?"

**On their challenges:**
- "What's been your most painful networking incident and what did you learn?"
- "How do you handle DNS changes and minimize impact from TTL delays?"
- "Have you hit any scalability limits with iptables-based networking?"

---

*Good luck — deep networking knowledge like this is genuinely rare in DevOps candidates. 🚀*
