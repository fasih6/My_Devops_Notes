# 🌐 Core Networking Concepts

OSI model, TCP/IP, subnets, routing, ARP — the fundamentals every DevOps engineer must know.

> Networking is the invisible glue of every system. When things break, the cause is almost always networking. This file is your foundation — everything else builds on it.

---

## 📚 Table of Contents

- [1. The OSI Model](#1-the-osi-model)
- [2. TCP/IP Protocol Suite](#2-tcpip-protocol-suite)
- [3. IP Addressing & Subnetting](#3-ip-addressing--subnetting)
- [4. Routing](#4-routing)
- [5. ARP — Address Resolution Protocol](#5-arp--address-resolution-protocol)
- [6. DHCP](#6-dhcp)
- [7. NAT — Network Address Translation](#7-nat--network-address-translation)
- [8. TCP Deep Dive](#8-tcp-deep-dive)
- [9. UDP](#9-udp)
- [10. ICMP & Ping](#10-icmp--ping)
- [Key Terms Glossary](#key-terms-glossary)

---

## 1. The OSI Model

The OSI (Open Systems Interconnection) model is a conceptual framework describing how data flows through a network in 7 layers. As a DevOps engineer, you work primarily at layers 3, 4, and 7.

```
Layer 7 — Application     HTTP, HTTPS, DNS, SSH, gRPC, SMTP
Layer 6 — Presentation    TLS/SSL encryption, data encoding
Layer 5 — Session         Session management, TLS handshake
Layer 4 — Transport       TCP (reliable), UDP (fast) — ports live here
Layer 3 — Network         IP addresses, routing — packets
Layer 2 — Data Link       MAC addresses, switches — frames
Layer 1 — Physical        Cables, fiber, wireless — bits
```

### What each layer does for DevOps

| Layer | DevOps relevance |
|-------|-----------------|
| **L7 Application** | HTTP status codes, API routing, Ingress rules, WAF |
| **L4 Transport** | TCP/UDP, ports, connection states, load balancer types |
| **L3 Network** | IP addressing, subnets, routing tables, VPCs |
| **L2 Data Link** | MAC addresses, ARP, VLANs, network switches |

### Where things break

```
"Website is down"
    │
    ├── L7 issue → app crash, wrong response code, bad route
    ├── L4 issue → port closed, connection refused, timeout
    ├── L3 issue → wrong IP, routing table missing, firewall block
    └── L1/L2 issue → cable unplugged, switch misconfigured
```

---

## 2. TCP/IP Protocol Suite

The practical networking model used in the real world — 4 layers (not 7):

```
Application Layer   → HTTP, DNS, SSH, TLS
Transport Layer     → TCP, UDP
Internet Layer      → IP, ICMP, ARP
Network Access      → Ethernet, Wi-Fi
```

### How a web request travels through layers

```
Browser sends GET https://api.example.com/users

Application (L7): HTTP GET /users + TLS encryption
        │ adds HTTP headers, TLS record
        ▼
Transport (L4): TCP segment
        │ adds source port (52341) + dest port (443)
        ▼
Internet (L3): IP packet
        │ adds source IP (10.0.1.5) + dest IP (93.184.216.34)
        ▼
Network Access (L2): Ethernet frame
        │ adds source MAC + dest MAC (next hop router)
        ▼
Physical: bits on wire/wireless

At the destination — all layers strip their headers in reverse
```

---

## 3. IP Addressing & Subnetting

### IPv4 address structure

```
192.168.1.100
 │   │  │  │
 │   │  │  └── 100 (host part)
 │   │  └───── 1   (subnet)
 │   └──────── 168 (network)
 └──────────── 192 (network)

Each number = 8 bits (octet) → total 32 bits
Range: 0.0.0.0 to 255.255.255.255
```

### CIDR notation

```
192.168.1.0/24
             │
             └── /24 = subnet mask bits
                 24 bits for network → 8 bits for hosts
                 → 256 addresses (254 usable, .0=network, .255=broadcast)

/32 → single host (1 address)
/31 → 2 addresses (point-to-point links)
/30 → 4 addresses (2 usable)
/29 → 8 addresses (6 usable)
/28 → 16 addresses (14 usable)
/27 → 32 addresses (30 usable)
/26 → 64 addresses (62 usable)
/25 → 128 addresses (126 usable)
/24 → 256 addresses (254 usable)
/23 → 512 addresses (510 usable)
/22 → 1024 addresses
/16 → 65,536 addresses
/8  → 16,777,216 addresses
```

### Private IP ranges (RFC 1918)

```
10.0.0.0/8         → 10.0.0.0 – 10.255.255.255    (16M addresses)
172.16.0.0/12      → 172.16.0.0 – 172.31.255.255  (1M addresses)
192.168.0.0/16     → 192.168.0.0 – 192.168.255.255 (65K addresses)

Special:
127.0.0.0/8        → Loopback (localhost = 127.0.0.1)
169.254.0.0/16     → Link-local (APIPA — no DHCP)
0.0.0.0            → This host (default route = "anywhere")
255.255.255.255    → Broadcast
```

### Subnetting examples

```
Goal: Divide 10.0.0.0/16 into subnets for:
  - 3 public subnets (one per AZ)
  - 3 private subnets (one per AZ)

Public subnets (/24 each → 254 hosts):
  10.0.1.0/24   → eu-central-1a public
  10.0.2.0/24   → eu-central-1b public
  10.0.3.0/24   → eu-central-1c public

Private subnets (/24 each → 254 hosts):
  10.0.11.0/24  → eu-central-1a private
  10.0.12.0/24  → eu-central-1b private
  10.0.13.0/24  → eu-central-1c private
```

### Calculating subnet from CIDR

```
10.0.1.0/24

Network address: 10.0.1.0
Broadcast:       10.0.1.255
First usable:    10.0.1.1
Last usable:     10.0.1.254
Subnet mask:     255.255.255.0
Hosts:           254

Formula: 2^(32-prefix) - 2 = usable hosts
  /24 → 2^8 - 2 = 254
  /25 → 2^7 - 2 = 126
  /26 → 2^6 - 2 = 62
```

### IPv6 (brief)

```
Format: 2001:0db8:85a3:0000:0000:8a2e:0370:7334
        (8 groups of 4 hex digits)

Abbreviated: 2001:db8:85a3::8a2e:370:7334
             (:: = consecutive zero groups)

/128 = single host
/64  = standard subnet
/48  = typical allocation per site

Link-local: fe80::/10
Loopback:   ::1/128
```

---

## 4. Routing

Routing determines how packets travel from source to destination.

### Routing table

Every host and router has a routing table — looked up for every outgoing packet:

```
Destination      Gateway         Interface
─────────────────────────────────────────
10.0.0.0/24      0.0.0.0         eth0      (local — send directly)
10.0.1.0/24      10.0.0.1        eth0      (via gateway)
172.16.0.0/12    10.0.0.1        eth0      (via gateway)
0.0.0.0/0        10.0.0.1        eth0      (default route — everything else)

# "0.0.0.0/0" = default route = "for anything not matching above, go here"
```

```bash
# View routing table on Linux
ip route
route -n         # older command
netstat -rn

# Typical output:
# default via 10.0.0.1 dev eth0    ← default gateway
# 10.0.0.0/24 dev eth0 proto kernel ← local subnet
```

### How routing works

```
Packet destined for 8.8.8.8:

1. Check routing table — longest prefix match
   - 0.0.0.0/0 matches → send to default gateway (10.0.0.1)

2. ARP for 10.0.0.1's MAC address
3. Send Ethernet frame to gateway's MAC

4. Gateway receives → decrement TTL → check its routing table
5. Repeat until destination is reached
```

### Longest prefix match

```
Routing table has:
  10.0.0.0/8  → via gateway A
  10.0.1.0/24 → via gateway B

Packet to 10.0.1.5:
  Matches both, but /24 is more specific (longer prefix)
  → sent to gateway B
```

### BGP (Border Gateway Protocol)

BGP is how the internet routes between autonomous systems (ISPs, cloud providers):

```
AS (Autonomous System) = a network under one organization's control
AWS = AS16509
Google = AS15169
Cloudflare = AS13335

BGP exchanges routes between ASes:
"I can reach 1.1.1.0/24" — Cloudflare announces to peers
Peers learn this route and add to their tables
```

---

## 5. ARP — Address Resolution Protocol

ARP resolves IP addresses to MAC addresses on the local network.

```
Host A (10.0.0.1) wants to talk to Host B (10.0.0.2):

1. A checks ARP cache — is 10.0.0.2's MAC known?
2. If not: A broadcasts ARP request
   "Who has 10.0.0.2? Tell 10.0.0.1"
   → sent to FF:FF:FF:FF:FF:FF (broadcast)

3. Host B responds: "10.0.0.2 is at aa:bb:cc:dd:ee:ff"
   → sent unicast to A

4. A caches the mapping and sends the frame to B's MAC

ARP cache (on Linux):
arp -n
ip neigh
# 10.0.0.2 dev eth0 lladdr aa:bb:cc:dd:ee:ff REACHABLE
```

### Gratuitous ARP

An ARP announcement (not a response to a request) — used to:
- Update ARP caches after IP change
- Detect IP conflicts
- High availability failover (announce new MAC for existing IP)

---

## 6. DHCP

DHCP automatically assigns IP addresses to hosts. The DORA process:

```
Client          Server
  │                │
  │── DISCOVER ───►│  "Anyone out there? I need an IP"
  │                │  (broadcast — client has no IP yet)
  │◄── OFFER ──────│  "I can give you 10.0.0.50 for 24 hours"
  │                │
  │── REQUEST ────►│  "Yes please, I want 10.0.0.50"
  │                │
  │◄── ACK ────────│  "Confirmed. 10.0.0.50 is yours"
  │                │
  Client uses 10.0.0.50 until lease expires
```

DHCP provides: IP address, subnet mask, default gateway, DNS servers, lease time.

---

## 7. NAT — Network Address Translation

NAT translates private IP addresses to public ones, allowing private networks to access the internet.

### Source NAT (SNAT / Masquerading)

```
Private network (10.0.0.0/24) → Internet

Packet from 10.0.0.5:3000 → 8.8.8.8:53
NAT router translates:
  Source: 10.0.0.5:3000 → 203.0.113.1:54321 (public IP:new port)

Response from 8.8.8.8:53 → 203.0.113.1:54321
NAT router translates back:
  Destination: 203.0.113.1:54321 → 10.0.0.5:3000
```

NAT maintains a translation table mapping (private IP:port) ↔ (public IP:port).

### Destination NAT (DNAT) — Port forwarding

```
External request → 203.0.113.1:80
Router: DNAT → 10.0.0.10:8080 (internal web server)

# Linux iptables DNAT rule:
iptables -t nat -A PREROUTING -p tcp --dport 80 \
  -j DNAT --to-destination 10.0.0.10:8080
```

### NAT in Kubernetes

Every `kubectl port-forward` and `Service` type `LoadBalancer`/`NodePort` uses NAT under the hood via iptables/IPVS rules.

---

## 8. TCP Deep Dive

### Three-way handshake

```
Client                    Server
  │                          │
  │──── SYN (seq=1000) ─────►│  "I want to connect, my seq starts at 1000"
  │                          │
  │◄─── SYN-ACK ─────────────│  "OK, your seq+1=1001, my seq starts at 2000"
  │     (seq=2000, ack=1001) │
  │                          │
  │──── ACK (ack=2001) ──────►│  "Acknowledged"
  │                          │
  │       [data flows]       │
```

### Four-way termination

```
Client                    Server
  │──── FIN ────────────────►│  "I'm done sending"
  │◄─── ACK ─────────────────│  "Got it"
  │◄─── FIN ─────────────────│  "I'm done too"
  │──── ACK ────────────────►│  "Got it"
  │
  Client waits TIME_WAIT (2*MSL ≈ 60s) before closing
```

### TCP connection states

| State | When |
|-------|------|
| `LISTEN` | Server waiting for connections |
| `SYN_SENT` | Client sent SYN |
| `SYN_RECV` | Server received SYN, sent SYN-ACK |
| `ESTABLISHED` | Connection active |
| `FIN_WAIT_1` | Sent FIN |
| `FIN_WAIT_2` | Received ACK of FIN |
| `TIME_WAIT` | Waiting 2*MSL after final ACK |
| `CLOSE_WAIT` | Received FIN, waiting to close |
| `LAST_ACK` | Sent FIN, waiting for ACK |
| `CLOSED` | No connection |

### TCP flags

| Flag | Meaning |
|------|---------|
| SYN | Synchronize — initiate connection |
| ACK | Acknowledge — confirm receipt |
| FIN | Finish — close connection gracefully |
| RST | Reset — abrupt close |
| PSH | Push — send data immediately |
| URG | Urgent data |

### TCP tuning for production

```bash
# View TCP settings
sysctl net.ipv4.tcp_*

# Key parameters
net.ipv4.tcp_max_syn_backlog = 4096      # SYN queue size
net.core.somaxconn = 65535               # accept queue size
net.ipv4.tcp_keepalive_time = 60         # keepalive after 60s idle
net.ipv4.tcp_keepalive_intvl = 10        # probe interval
net.ipv4.tcp_keepalive_probes = 6        # probes before drop
net.ipv4.tcp_fin_timeout = 15            # TIME_WAIT duration
net.ipv4.ip_local_port_range = 1024 65535  # ephemeral port range
net.ipv4.tcp_tw_reuse = 1               # reuse TIME_WAIT sockets
```

---

## 9. UDP

UDP is connectionless — no handshake, no guaranteed delivery, no ordering.

```
Client → Server: just sends the datagram
No acknowledgment, no retransmission
If it's lost: application handles it (or doesn't)
```

### When UDP beats TCP

| Use case | Why UDP |
|---------|---------|
| DNS queries | Small, fast, retry at application level |
| Video streaming | Stale frame better than delayed frame |
| VoIP/gaming | Low latency critical, small loss acceptable |
| QUIC (HTTP/3) | UDP + reliability built into protocol |
| StatsD/metrics | Some loss acceptable, no overhead |

---

## 10. ICMP & Ping

ICMP (Internet Control Message Protocol) — carries control messages, not user data.

```bash
# Ping — ICMP Echo Request/Reply
ping google.com
ping -c 4 google.com       # 4 packets
ping -s 1400 google.com    # large packet (test MTU)
ping -i 0.2 google.com     # fast ping (0.2s interval)

# Traceroute — uses ICMP TTL exceeded
traceroute google.com
mtr google.com             # continuous traceroute

# ICMP message types
0  → Echo Reply (ping response)
3  → Destination Unreachable
     code 0: network unreachable
     code 1: host unreachable
     code 3: port unreachable
     code 4: fragmentation needed (path MTU)
8  → Echo Request (ping)
11 → Time Exceeded (TTL expired — traceroute)

# Why ICMP matters
- Ping blocked? Doesn't mean host is down — might be firewall
- "Destination unreachable" = routing problem or firewall
- TTL expired = routing loop or too many hops
- Fragmentation needed = MTU mismatch (tunnel issues)
```

---

## Key Terms Glossary

| Term | Definition |
|------|-----------|
| **OSI model** | 7-layer framework for network communication |
| **TCP/IP** | 4-layer practical networking model used in the internet |
| **IP address** | 32-bit (IPv4) or 128-bit (IPv6) identifier for a host |
| **CIDR** | Classless Inter-Domain Routing — IP/prefix notation |
| **Subnet** | Subdivision of a network |
| **Subnet mask** | Determines which part of an IP is network vs host |
| **Gateway** | Router that forwards packets to other networks |
| **Default route** | 0.0.0.0/0 — where to send packets with no better match |
| **Routing table** | List of routes a host/router uses to forward packets |
| **BGP** | Border Gateway Protocol — routing between autonomous systems |
| **ARP** | Resolves IP addresses to MAC addresses on local network |
| **MAC address** | 48-bit hardware address burned into a network interface |
| **DHCP** | Automatically assigns IP addresses to hosts |
| **NAT** | Translates private IP:port to public IP:port |
| **SNAT** | Source NAT — outbound traffic from private to public |
| **DNAT** | Destination NAT — port forwarding |
| **TTL** | Time To Live — decremented at each hop, prevents loops |
| **MTU** | Maximum Transmission Unit — largest frame size (usually 1500 bytes) |
| **TCP** | Reliable, ordered, connection-oriented transport protocol |
| **UDP** | Fast, connectionless, best-effort transport protocol |
| **SYN** | TCP synchronize flag — initiates a connection |
| **ACK** | TCP acknowledge flag — confirms receipt |
| **TIME_WAIT** | TCP state after closing — waits 2*MSL for delayed packets |
| **ICMP** | Internet Control Message Protocol — ping, traceroute |
| **Autonomous System** | Network under one organization's BGP control |

---

*Next: [VPCs & Cloud Networking →](./02-vpc-cloud-networking.md)*
