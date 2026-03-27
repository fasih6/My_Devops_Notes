# 🌐 Linux Networking

How Linux handles networking — from interfaces and routing to DNS, firewalls, and debugging real problems.

> Networking is where most production incidents hide. The better you understand this layer, the faster you resolve them.

---

## 📚 Table of Contents

- [1. Networking Fundamentals](#1-networking-fundamentals)
- [2. Network Interfaces](#2-network-interfaces)
- [3. IP Addressing & Routing](#3-ip-addressing--routing)
- [4. DNS Resolution](#4-dns-resolution)
- [5. Ports & Connections — ss and netstat](#5-ports--connections--ss-and-netstat)
- [6. Firewalls — iptables & ufw](#6-firewalls--iptables--ufw)
- [7. HTTP Debugging — curl & wget](#7-http-debugging--curl--wget)
- [8. Packet Capture — tcpdump](#8-packet-capture--tcpdump)
- [9. Network Performance & Diagnostics](#9-network-performance--diagnostics)
- [10. Linux Networking in Kubernetes](#10-linux-networking-in-kubernetes)
- [11. Networking Troubleshooting Scenarios](#11-networking-troubleshooting-scenarios)
- [Cheatsheet](#cheatsheet)

---

## 1. Networking Fundamentals

### The OSI model — simplified for DevOps

You don't need to memorize all 7 layers. Focus on these:

```
Layer 7 — Application    HTTP, HTTPS, DNS, SSH, gRPC
Layer 4 — Transport      TCP (reliable), UDP (fast, unreliable)
Layer 3 — Network        IP addresses, routing
Layer 2 — Data Link      MAC addresses, ARP, switches
Layer 1 — Physical       Cables, signals
```

As a DevOps engineer you work primarily at layers 3, 4, and 7.

### TCP vs UDP

| | TCP | UDP |
|--|-----|-----|
| **Connection** | Connection-oriented (handshake) | Connectionless |
| **Reliability** | Guaranteed delivery, ordering | No guarantees |
| **Speed** | Slower | Faster |
| **Use cases** | HTTP, SSH, databases, Kubernetes API | DNS, metrics (StatsD), video streaming |
| **Error handling** | Retransmits lost packets | Application handles errors |

### TCP handshake — the three-way handshake

```
Client                    Server
  │                          │
  │──── SYN ────────────────►│  "I want to connect"
  │                          │
  │◄─── SYN-ACK ─────────────│  "OK, I'm ready"
  │                          │
  │──── ACK ────────────────►│  "Great, let's go"
  │                          │
  │  ←── data flows ──►      │
  │                          │
  │──── FIN ────────────────►│  "I'm done sending"
  │◄─── FIN-ACK ─────────────│  "Closing my side too"
```

Understanding this matters when debugging connection timeouts, half-open connections, and `TIME_WAIT` states.

### CIDR notation

```
192.168.1.0/24   → 256 addresses (192.168.1.0 - 192.168.1.255)
10.0.0.0/16      → 65536 addresses
10.0.0.0/8       → 16 million addresses
172.16.0.0/12    → private range used by Docker

# Key private ranges
10.0.0.0/8       → class A private
172.16.0.0/12    → class B private
192.168.0.0/16   → class C private (home/office networks)

# Special addresses
127.0.0.1        → loopback (localhost)
0.0.0.0          → all interfaces / default route
255.255.255.255  → broadcast
```

---

## 2. Network Interfaces

### Viewing interfaces

```bash
# Modern way (ip command)
ip addr                    # show all interfaces with IPs
ip addr show eth0          # specific interface
ip link                    # show link state (UP/DOWN, MAC address)
ip link show eth0

# Example output:
# 2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP
#     link/ether 02:42:ac:11:00:02 brd ff:ff:ff:ff:ff:ff
#     inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0

# Older way (still widely used)
ifconfig                   # show all active interfaces
ifconfig eth0              # specific interface
```

### Interface states and flags

| Flag | Meaning |
|------|---------|
| `UP` | Interface is enabled |
| `LOWER_UP` | Physical link is connected |
| `BROADCAST` | Supports broadcast |
| `MULTICAST` | Supports multicast |
| `NO-CARRIER` | Cable unplugged / link down |

```bash
# Bring interface up or down
ip link set eth0 up
ip link set eth0 down

# Add/remove IP address temporarily
ip addr add 192.168.1.200/24 dev eth0
ip addr del 192.168.1.200/24 dev eth0
```

### Common interface names

| Name | What it usually is |
|------|--------------------|
| `eth0`, `ens3`, `enp3s0` | Physical or virtual Ethernet |
| `lo` | Loopback (127.0.0.1) |
| `docker0` | Docker bridge network |
| `flannel.1`, `cni0` | Kubernetes network interfaces |
| `tun0`, `tap0` | VPN tunnel interfaces |
| `veth*` | Virtual ethernet pairs (containers) |

---

## 3. IP Addressing & Routing

### The routing table

The routing table tells the kernel where to send packets:

```bash
ip route                   # show routing table
ip route show              # same
route -n                   # older alternative, numeric output

# Example output:
# default via 10.0.0.1 dev eth0 proto dhcp src 10.0.0.100
# 10.0.0.0/24 dev eth0 proto kernel scope link src 10.0.0.100
# 172.17.0.0/16 dev docker0 proto kernel scope link src 172.17.0.1
```

Reading the routing table:
```
default via 10.0.0.1 dev eth0    → "For all traffic not matching other rules,
                                    send to gateway 10.0.0.1 via eth0"

10.0.0.0/24 dev eth0             → "For 10.0.0.x addresses, send directly on eth0"

172.17.0.0/16 dev docker0        → "For Docker containers, use docker0 interface"
```

### Manipulating routes

```bash
# Add a route
ip route add 10.10.0.0/24 via 192.168.1.1        # route subnet via gateway
ip route add 10.10.0.0/24 dev eth1               # route via specific interface

# Delete a route
ip route del 10.10.0.0/24

# Change default gateway
ip route replace default via 10.0.0.254

# Flush route cache
ip route flush cache
```

### IP forwarding

For a Linux machine to act as a router (required for Kubernetes networking):

```bash
# Check current state
cat /proc/sys/net/ipv4/ip_forward   # 0 = disabled, 1 = enabled

# Enable temporarily
sysctl -w net.ipv4.ip_forward=1

# Enable permanently
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p
```

### ARP — Address Resolution Protocol

ARP resolves IP addresses to MAC addresses on the local network:

```bash
# View ARP table (IP → MAC mappings)
arp -n
ip neigh                   # modern equivalent

# Clear ARP cache
ip neigh flush all

# Manually add an ARP entry
arp -s 192.168.1.200 aa:bb:cc:dd:ee:ff
```

---

## 4. DNS Resolution

### How DNS resolution works

```
Your app requests "api.example.com"
           │
           ▼
/etc/nsswitch.conf → check files first, then dns
           │
           ▼
/etc/hosts → check local overrides
  127.0.0.1 localhost
  10.0.0.5  api.example.com  ← if found here, done
           │
           ▼  (if not in /etc/hosts)
/etc/resolv.conf → which DNS server to ask
  nameserver 8.8.8.8
  nameserver 8.8.4.4
           │
           ▼
DNS server responds with IP
```

### Key DNS files

```bash
# /etc/hosts — local overrides (checked before DNS)
127.0.0.1   localhost
::1         localhost
10.0.0.100  my-server my-server.internal

# /etc/resolv.conf — DNS server config
nameserver 8.8.8.8          # primary DNS
nameserver 8.8.4.4          # secondary DNS
search example.com          # domain search suffix
options ndots:5             # Kubernetes sets this for pod DNS

# /etc/nsswitch.conf — resolution order
hosts: files dns            # check /etc/hosts first, then DNS
```

### DNS tools

```bash
# dig — most detailed, most useful
dig google.com                    # A record lookup
dig google.com A                  # explicit A record
dig google.com AAAA               # IPv6 address
dig google.com MX                 # mail server records
dig google.com NS                 # name server records
dig google.com TXT                # TXT records (SPF, DKIM, etc.)
dig google.com ANY                # all records
dig @8.8.8.8 google.com           # use specific DNS server
dig +short google.com             # just the IP, no extra info
dig +trace google.com             # trace full resolution chain
dig -x 8.8.8.8                    # reverse lookup (IP → hostname)

# nslookup — simpler alternative
nslookup google.com
nslookup google.com 8.8.8.8       # using specific server

# host — quick lookups
host google.com
host -t MX google.com
host 8.8.8.8                      # reverse lookup

# systemd-resolve (modern systems)
resolvectl status                  # DNS config per interface
resolvectl query google.com        # DNS lookup
resolvectl flush-caches            # clear DNS cache
```

### DNS in Kubernetes

Every pod gets DNS automatically via CoreDNS:

```bash
# DNS config inside a pod
cat /etc/resolv.conf
# nameserver 10.96.0.10           ← CoreDNS cluster IP
# search default.svc.cluster.local svc.cluster.local cluster.local
# options ndots:5

# Service DNS naming pattern:
# <service>.<namespace>.svc.cluster.local
# my-app.production.svc.cluster.local

# Test DNS from inside a pod
kubectl exec -it my-pod -- nslookup kubernetes
kubectl exec -it my-pod -- dig my-service.default.svc.cluster.local
```

---

## 5. Ports & Connections — ss and netstat

`ss` (socket statistics) is the modern replacement for `netstat`.

### ss — essential flags

```bash
# Flags reference
# -t  TCP sockets
# -u  UDP sockets
# -l  listening sockets only
# -n  numeric (don't resolve hostnames/ports)
# -p  show process name and PID (needs sudo for other users)
# -a  all sockets (listening + established)
# -e  extended info
# -s  summary statistics

# Most used combinations
ss -tuln                   # listening TCP and UDP, numeric
ss -tulnp                  # + process info (who owns the socket)
ss -tnp                    # established TCP connections with process
ss -s                      # summary: total sockets by state

# Filter by port
ss -tnp sport = :80        # connections FROM port 80
ss -tnp dport = :80        # connections TO port 80

# Filter by state
ss -t state established    # only established connections
ss -t state time-wait      # TIME_WAIT connections (closing)
ss -t state listen         # listening sockets

# Count connections to a port
ss -tn dst :443 | wc -l    # connections to port 443
```

### Understanding connection states

| State | What it means |
|-------|--------------|
| `LISTEN` | Server waiting for incoming connections |
| `ESTABLISHED` | Active connection, data flowing |
| `TIME_WAIT` | Connection closing, waiting for delayed packets |
| `CLOSE_WAIT` | Remote end closed, waiting for local close |
| `SYN_SENT` | Client sent SYN, waiting for SYN-ACK |
| `SYN_RECV` | Server received SYN, sent SYN-ACK |
| `FIN_WAIT` | Sent FIN, waiting for remote to close |

> 💡 **High TIME_WAIT count** is normal for busy HTTP servers. It's connections that just finished. If it's extremely high (tens of thousands), you may need to tune `net.ipv4.tcp_tw_reuse`.

### lsof — list open files (including sockets)

```bash
lsof -i                    # all network connections
lsof -i :8080              # what's using port 8080
lsof -i tcp                # all TCP connections
lsof -i tcp:80             # TCP connections on port 80
lsof -p 1234               # all files open by PID 1234
lsof -u nginx              # files open by nginx user
lsof /var/log/nginx/access.log  # who has this file open
```

---

## 6. Firewalls — iptables & ufw

### iptables — the Linux firewall

iptables filters packets using chains of rules:

```
Packet arrives
      │
      ▼
┌─────────────┐
│  PREROUTING │  (before routing decision — NAT, DNAT)
└──────┬──────┘
       │
       ├── destined for this machine?
       │         │
       ▼         ▼
   FORWARD    INPUT         ← packets going TO this machine
   (routing   (local apps)
   packets
   through)
       │
       ▼
   POSTROUTING  (after routing — SNAT, MASQUERADE)
       │
       ▼
  Packet leaves
```

### iptables chains and tables

```
Tables:   filter (default), nat, mangle, raw
Chains:   INPUT, OUTPUT, FORWARD, PREROUTING, POSTROUTING
Actions:  ACCEPT, DROP, REJECT, LOG, DNAT, SNAT, MASQUERADE
```

```bash
# View rules
iptables -L                          # all filter rules
iptables -L -n -v                    # numeric, with counters
iptables -L INPUT -n -v              # just INPUT chain
iptables -t nat -L -n -v             # NAT table

# Basic rules
iptables -A INPUT -p tcp --dport 80 -j ACCEPT    # allow HTTP
iptables -A INPUT -p tcp --dport 443 -j ACCEPT   # allow HTTPS
iptables -A INPUT -p tcp --dport 22 -j ACCEPT    # allow SSH
iptables -A INPUT -j DROP                         # drop everything else

# Allow established connections
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

# Block specific IP
iptables -A INPUT -s 1.2.3.4 -j DROP

# Rate limiting (protect against brute force)
iptables -A INPUT -p tcp --dport 22 -m limit --limit 3/min -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j DROP

# Delete a rule
iptables -D INPUT -p tcp --dport 80 -j ACCEPT

# Save rules (persist across reboots)
iptables-save > /etc/iptables/rules.v4
iptables-restore < /etc/iptables/rules.v4

# Flush all rules (dangerous — resets to accept all)
iptables -F
```

### NAT with iptables

```bash
# Masquerade outbound traffic (for NAT router / container networking)
iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

# Port forwarding — forward port 80 on host to container on port 8080
iptables -t nat -A PREROUTING -p tcp --dport 80 -j DNAT --to-destination 172.17.0.2:8080
iptables -A FORWARD -p tcp -d 172.17.0.2 --dport 8080 -j ACCEPT
```

### ufw — simplified firewall for Ubuntu

```bash
# Status
ufw status
ufw status verbose

# Enable / disable
ufw enable
ufw disable

# Default policies
ufw default deny incoming
ufw default allow outgoing

# Allow / deny rules
ufw allow 22                         # allow SSH
ufw allow 80/tcp                     # allow HTTP
ufw allow 443/tcp                    # allow HTTPS
ufw allow from 10.0.0.0/24          # allow entire subnet
ufw allow from 10.0.0.5 to any port 22  # specific IP to SSH

ufw deny 8080                        # block port
ufw delete allow 80                  # remove a rule

# Application profiles
ufw app list                         # show available profiles
ufw allow 'Nginx Full'               # allow HTTP + HTTPS
```

---

## 7. HTTP Debugging — curl & wget

```bash
# Basic requests
curl https://example.com                     # GET request
curl -I https://example.com                  # HEAD — headers only
curl -X POST https://api.example.com/data    # POST
curl -X DELETE https://api.example.com/1    # DELETE

# Headers
curl -H "Authorization: Bearer TOKEN" https://api.example.com
curl -H "Content-Type: application/json" -d '{"key":"value"}' https://api.example.com

# Output control
curl -o output.html https://example.com      # save to file
curl -O https://example.com/file.tar.gz      # save with original filename
curl -s https://example.com                  # silent (no progress bar)
curl -S https://example.com                  # show errors even with -s
curl -L https://example.com                  # follow redirects
curl -v https://example.com                  # verbose — shows full request/response

# Timing breakdown (very useful for debugging)
curl -w "\n
    time_namelookup:  %{time_namelookup}s
    time_connect:     %{time_connect}s
    time_appconnect:  %{time_appconnect}s (TLS)
    time_pretransfer: %{time_pretransfer}s
    time_starttransfer: %{time_starttransfer}s (TTFB)
    time_total:       %{time_total}s
    http_code:        %{http_code}
" -o /dev/null -s https://example.com

# Just the status code
curl -w "%{http_code}" -o /dev/null -s https://example.com

# Test with specific DNS (bypass DNS, hit specific IP)
curl --resolve example.com:443:93.184.216.34 https://example.com

# Ignore TLS errors (testing only)
curl -k https://self-signed.example.com

# Follow with client certificate
curl --cert client.crt --key client.key https://mtls.example.com

# Test Kubernetes API from inside cluster
curl -sk https://kubernetes.default.svc/api \
  -H "Authorization: Bearer $(cat /var/run/secrets/kubernetes.io/serviceaccount/token)"

# Upload a file
curl -F "file=@/path/to/file.txt" https://api.example.com/upload

# Rate a series of requests
for i in {1..10}; do
  curl -s -o /dev/null -w "%{http_code}\n" https://example.com
done
```

---

## 8. Packet Capture — tcpdump

tcpdump captures raw network packets — the ultimate debugging tool.

```bash
# Basic capture
tcpdump -i eth0                          # capture all traffic on eth0
tcpdump -i any                           # capture on all interfaces
tcpdump -i eth0 -n                       # numeric (no DNS resolution)
tcpdump -i eth0 -nn                      # numeric ports AND addresses
tcpdump -i eth0 -v                       # verbose
tcpdump -i eth0 -vv                      # more verbose

# Write to file for Wireshark analysis
tcpdump -i eth0 -w capture.pcap
tcpdump -r capture.pcap                  # read from file

# Filter by protocol
tcpdump -i eth0 tcp
tcpdump -i eth0 udp
tcpdump -i eth0 icmp

# Filter by port
tcpdump -i eth0 port 80
tcpdump -i eth0 port 80 or port 443
tcpdump -i eth0 not port 22              # exclude SSH (avoid noise)

# Filter by host
tcpdump -i eth0 host 10.0.0.5
tcpdump -i eth0 src 10.0.0.5            # traffic FROM this IP
tcpdump -i eth0 dst 10.0.0.5            # traffic TO this IP

# Combined filters
tcpdump -i eth0 host 10.0.0.5 and port 443
tcpdump -i eth0 'tcp[tcpflags] & tcp-syn != 0'  # SYN packets only

# Limit capture size
tcpdump -i eth0 -c 100                  # capture only 100 packets
tcpdump -i eth0 -s 0                    # capture full packet (default truncates)

# Practical examples
tcpdump -i eth0 port 53                  # watch DNS queries
tcpdump -i eth0 port 80 -A              # watch HTTP traffic (ASCII)
tcpdump -i eth0 'tcp port 80 and (tcp-syn or tcp-fin)' # track connections
```

---

## 9. Network Performance & Diagnostics

```bash
# Connectivity tests
ping -c 4 google.com                    # basic reachability
ping -i 0.2 -c 20 google.com           # faster pings, check for packet loss
ping -s 1400 google.com                 # large packet (test MTU issues)

# Path analysis
traceroute google.com                   # trace hops to destination
traceroute -T google.com               # use TCP (bypass some firewalls)
mtr google.com                          # continuous traceroute (best tool)
mtr --report google.com                 # run and show report

# Bandwidth test
iperf3 -s                               # start server
iperf3 -c <server-ip>                  # run client test
iperf3 -c <server-ip> -t 30            # 30 second test

# MTU discovery (important for tunnel/VPN issues)
ping -M do -s 1472 google.com          # test if 1500 byte packets get through

# Network interface statistics
ip -s link                              # TX/RX bytes, errors, drops
cat /proc/net/dev                       # per-interface statistics
netstat -i                              # interface stats (older)

# Check for network errors
ip -s link show eth0 | grep -E "errors|dropped"

# TCP connection stats
ss -s                                   # socket summary by state
cat /proc/net/snmp | grep Tcp           # TCP stats from kernel

# Bandwidth usage per connection
nethogs                                 # per-process bandwidth (apt install nethogs)
iftop -i eth0                           # per-connection bandwidth (apt install iftop)
```

---

## 10. Linux Networking in Kubernetes

Understanding how Kubernetes networking works at the Linux level is essential for debugging.

### How pod networking works

```
Pod A (10.244.1.2)              Pod B (10.244.2.3)
      │                                │
   veth0                            veth0
      │                                │
   cni0 bridge (node 1)          cni0 bridge (node 2)
      │                                │
   eth0 (node 1: 10.0.0.1)       eth0 (node 2: 10.0.0.2)
      │                                │
      └──────── physical network ──────┘

Packet: Pod A → Pod B
1. Pod A sends to 10.244.2.3
2. Kernel checks routes → goes to cni0 bridge
3. CNI plugin (flannel/calico) routes to node 2
4. Arrives at node 2 eth0
5. Routes via cni0 to veth of Pod B
```

```bash
# See pod network interfaces from the node
ip addr                              # see all veth interfaces
ip link | grep veth                  # list virtual ethernet pairs

# See routing for pod traffic
ip route | grep 10.244              # pod CIDR routes

# Check which veth belongs to which container
# From the container, get the interface index
kubectl exec -it my-pod -- cat /sys/class/net/eth0/iflink
# Then on the node, find the matching interface
ip link | grep "^<that-index>"

# Check iptables rules Kubernetes creates (for Services)
iptables -t nat -L KUBE-SERVICES -n    # all Kubernetes service rules
iptables -t nat -L -n | grep <service-ip>

# CoreDNS — pod DNS
kubectl get pods -n kube-system | grep coredns
kubectl logs -n kube-system -l k8s-app=kube-dns
```

### Network namespaces (how containers get isolated networks)

```bash
# List network namespaces
ip netns list

# See namespaces of running container (from host)
ls /var/run/docker/netns/
ls /var/run/netns/

# Enter a container's network namespace
nsenter -t <container-pid> -n ip addr    # see container's interfaces from host
nsenter -t <container-pid> -n ss -tulnp  # see container's ports from host

# Get container PID
docker inspect <container> | grep '"Pid"'
crictl inspect <container-id> | grep '"pid"'  # for containerd
```

### CNI plugins — how pods get IPs

```bash
# CNI config location
ls /etc/cni/net.d/                   # CNI plugin config files
cat /etc/cni/net.d/10-flannel.conflist  # flannel example

# CNI binaries
ls /opt/cni/bin/

# Check which CNI is running
kubectl get pods -n kube-system      # look for flannel, calico, weave, etc.
```

---

## 11. Networking Troubleshooting Scenarios

---

**Scenario: Cannot connect to a service on port 8080**

```bash
# Step 1 — Is the service actually listening?
ss -tulnp | grep :8080
# If nothing → service is not running or bound to wrong port

# Step 2 — Is there a firewall blocking it?
iptables -L INPUT -n -v | grep 8080
ufw status | grep 8080

# Step 3 — Can you reach it locally?
curl -v http://localhost:8080/health
# If yes locally but not remotely → firewall issue

# Step 4 — Is it bound to the right interface?
ss -tulnp | grep :8080
# 0.0.0.0:8080 → listening on all interfaces (good)
# 127.0.0.1:8080 → listening on localhost only (won't accept external connections)

# Step 5 — Test from different network positions
curl http://<node-ip>:8080           # from outside the node
curl http://localhost:8080           # from the node itself
kubectl exec -it debug-pod -- curl http://<service-ip>:8080  # from inside cluster
```

---

**Scenario: DNS not resolving**

```bash
# Step 1 — Basic DNS test
dig google.com
nslookup google.com

# Step 2 — Check which DNS server is being used
cat /etc/resolv.conf

# Step 3 — Try a known-good DNS server directly
dig @8.8.8.8 google.com

# Step 4 — If that works, your configured DNS is the problem
# Check /etc/resolv.conf, systemd-resolved, or network manager config

# Step 5 — Check DNS resolution order
cat /etc/nsswitch.conf | grep hosts

# Step 6 — Check /etc/hosts for conflicting entries
cat /etc/hosts

# Step 7 — Clear DNS cache
resolvectl flush-caches                # systemd-resolved
systemctl restart systemd-resolved

# In Kubernetes — debug pod DNS
kubectl exec -it my-pod -- cat /etc/resolv.conf
kubectl exec -it my-pod -- nslookup kubernetes.default
kubectl exec -it my-pod -- dig my-service.default.svc.cluster.local
kubectl logs -n kube-system -l k8s-app=kube-dns  # CoreDNS logs
```

---

**Scenario: High latency to a service**

```bash
# Step 1 — Where is the latency?
curl -w "time_connect: %{time_connect}s\ntime_starttransfer: %{time_starttransfer}s\n" \
  -o /dev/null -s https://example.com

# time_connect high     → TCP/network issue
# time_appconnect high  → TLS handshake slow
# time_starttransfer high (but connect low) → server-side processing slow

# Step 2 — Check the path
mtr --report google.com
# Look for which hop shows high latency or packet loss

# Step 3 — Check local system
# Is the node itself overloaded?
uptime                    # load average
vmstat 1 5               # CPU/memory pressure
iostat -x 1              # disk I/O wait (wa% in top)

# Step 4 — Check for packet loss
ping -c 50 <destination> | tail -3

# Step 5 — Check network interface errors
ip -s link show eth0
# errors or drops increasing? → hardware/driver issue
```

---

**Scenario: Too many connections — port exhaustion**

```bash
# Check how many connections exist
ss -s
ss -tn | wc -l

# Check TIME_WAIT connections
ss -tn state time-wait | wc -l

# Check ephemeral port range
cat /proc/sys/net/ipv4/ip_local_port_range
# default: 32768 60999 = 28231 ports available

# Tune if exhausted
sysctl -w net.ipv4.ip_local_port_range="1024 65535"  # more ports
sysctl -w net.ipv4.tcp_tw_reuse=1                     # reuse TIME_WAIT sockets
sysctl -w net.ipv4.tcp_fin_timeout=15                 # faster cleanup
```

---

## Cheatsheet

```bash
# Interfaces
ip addr                              # show interfaces and IPs
ip link                              # show link state
ip route                             # show routing table

# DNS
dig example.com                      # DNS lookup
dig +short example.com               # just the IP
dig @8.8.8.8 example.com            # use specific DNS server
cat /etc/resolv.conf                 # DNS config
resolvectl flush-caches              # clear DNS cache

# Connections & ports
ss -tulnp                            # listening sockets with process
ss -tnp                              # established connections
ss -s                                # summary
lsof -i :8080                        # who is using port 8080

# Firewall
iptables -L -n -v                    # all rules with counters
ufw status verbose                   # ufw rules

# HTTP debugging
curl -I https://example.com          # headers only
curl -v https://example.com          # verbose (full request/response)
curl -w "%{http_code}" -o /dev/null -s https://example.com  # status code only

# Packet capture
tcpdump -i eth0 port 80 -n          # capture HTTP traffic
tcpdump -i eth0 host 10.0.0.5      # traffic to/from IP
tcpdump -i eth0 -w capture.pcap    # save for Wireshark

# Diagnostics
ping -c 4 google.com                 # reachability
mtr google.com                       # path analysis
netstat -i / ip -s link              # interface stats and errors

# Kubernetes networking
kubectl exec -it pod -- cat /etc/resolv.conf
kubectl exec -it pod -- nslookup kubernetes.default
iptables -t nat -L KUBE-SERVICES -n # Kubernetes service rules
ip route | grep 10.244               # pod CIDR routes
```

---

*Next: [Storage & Filesystems →](./05-linux-storage.md) — disks, LVM, mounts, and managing storage.*
