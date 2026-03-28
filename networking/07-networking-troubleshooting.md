# 🔧 Network Troubleshooting

Tools, methodology, and real scenarios — debugging network problems systematically.

---

## 📚 Table of Contents

- [1. Troubleshooting Methodology](#1-troubleshooting-methodology)
- [2. Essential Tools](#2-essential-tools)
- [3. Layer-by-Layer Debugging](#3-layer-by-layer-debugging)
- [4. Common Scenarios](#4-common-scenarios)
- [5. Cloud-Specific Troubleshooting](#5-cloud-specific-troubleshooting)
- [6. Kubernetes Network Debugging](#6-kubernetes-network-debugging)
- [Cheatsheet](#cheatsheet)

---

## 1. Troubleshooting Methodology

### The OSI approach — work bottom up

```
When connectivity fails, start at Layer 1 and work up:

L1 Physical    → Is the cable plugged in? Is the interface up?
L2 Data Link   → ARP working? MAC addresses resolving?
L3 Network     → Can you ping? Routing table correct?
L4 Transport   → Is the port open? Connection refused or timeout?
L7 Application → Is the service running? Correct response codes?
```

### The isolation technique

```
Connectivity problem between A and B:

1. Can A ping itself (localhost)?      → Tests L3 locally
2. Can A ping its gateway?             → Tests local network
3. Can A ping B's IP directly?         → Tests routing
4. Can A reach B's port (nc/curl)?     → Tests firewall + service
5. Does the app work on B locally?     → Tests the application
```

### Ask these questions first

```
- What changed recently? (deployment, config change, network change)
- When did it start? (specific time → check change log around that time)
- Who is affected? (one user, one pod, one AZ, everyone?)
- Is it intermittent or consistent?
- What error exactly? (timeout vs refused vs wrong response)
```

---

## 2. Essential Tools

### ping — basic reachability

```bash
ping google.com                    # test reachability
ping -c 4 10.0.0.5                # 4 packets
ping -i 0.2 -c 50 10.0.0.5       # fast ping for packet loss check
ping -s 8972 10.0.0.5             # large packet (test MTU/fragmentation)

# Analyze output:
# Round trip time consistently high → latency issue
# Packet loss → intermittent connectivity
# 100% loss → no path or firewall blocking ICMP
```

### traceroute / mtr — path analysis

```bash
traceroute google.com              # each hop to destination
traceroute -T google.com           # TCP traceroute (bypass ICMP blocks)
traceroute -p 443 google.com       # specific port

mtr google.com                     # continuous traceroute with statistics
mtr --report google.com            # single run with report
mtr --report --no-dns google.com   # no DNS lookups (faster)

# mtr output:
# Host               Loss%  Snt  Last   Avg  Best  Wrst StDev
# 10.0.0.1            0.0%  100   0.4   0.4   0.3   0.8  0.1
# 203.0.113.1        15.0%  100  45.2  46.1  44.8  52.3  1.2  ← packet loss here
```

### netcat (nc) — test ports

```bash
# Test TCP connectivity
nc -zv 10.0.0.5 443               # z=zero-io, v=verbose
nc -zv 10.0.0.5 80
nc -w 5 -zv 10.0.0.5 8080        # 5s timeout

# Listen on a port (for testing)
nc -l 8080                         # listen on 8080
nc -l 8080 -k                      # keep listening

# Simple HTTP test
echo -e "GET / HTTP/1.0\r\n" | nc google.com 80

# Port scan
nc -zv 10.0.0.5 20-1024           # scan port range
```

### curl — HTTP testing

```bash
# Full request details
curl -v https://example.com

# Just the status code
curl -o /dev/null -s -w "%{http_code}" https://example.com

# Timing breakdown
curl -w "\ntime_namelookup: %{time_namelookup}\ntime_connect: %{time_connect}\ntime_starttransfer: %{time_starttransfer}\ntime_total: %{time_total}\n" \
  -o /dev/null -s https://example.com

# Override DNS (test specific server without DNS)
curl --resolve example.com:443:93.184.216.34 https://example.com

# Follow redirects
curl -L https://example.com

# With custom headers
curl -H "Host: api.example.com" http://10.0.0.5/health
curl -H "Authorization: Bearer TOKEN" https://api.example.com/data

# Test POST
curl -X POST -H "Content-Type: application/json" \
  -d '{"key":"value"}' https://api.example.com/endpoint

# Check TLS certificate
curl -vI https://example.com 2>&1 | grep -E "subject|expire|issuer|SSL"
```

### ss / netstat — connections and listening ports

```bash
# Listening ports
ss -tulnp                          # TCP+UDP, listening, numeric, process
ss -tulnp | grep :8080             # specific port
ss -tulnp | grep LISTEN            # all listening

# Established connections
ss -tnp                            # TCP established with process
ss -tnp | grep :443                # HTTPS connections

# Connection counts by state
ss -s                              # summary

# All connections to a specific destination
ss -tn dst 10.0.0.5

# Check if port is in use before binding
ss -tulnp | grep :8080 || echo "Port 8080 is free"
```

### tcpdump — packet capture

```bash
# Capture on interface
tcpdump -i eth0

# Specific host
tcpdump -i eth0 host 10.0.0.5

# Specific port
tcpdump -i eth0 port 443

# Specific protocol
tcpdump -i eth0 icmp
tcpdump -i eth0 tcp

# Verbose + no DNS
tcpdump -i eth0 -vnn port 8080

# Save to file (for Wireshark)
tcpdump -i eth0 -w capture.pcap

# Read saved capture
tcpdump -r capture.pcap

# Watch HTTP GET requests
tcpdump -i eth0 -A port 80 | grep "GET "

# DNS queries
tcpdump -i eth0 port 53

# Show TCP handshakes
tcpdump -i eth0 'tcp[tcpflags] & (tcp-syn|tcp-fin) != 0'

# Capture and filter
tcpdump -i eth0 -nn 'host 10.0.0.5 and port 443 and tcp[tcpflags] = tcp-syn'
```

### dig — DNS debugging

```bash
dig example.com                    # A record
dig +short example.com             # just IP
dig @8.8.8.8 example.com          # use specific resolver
dig +trace example.com             # trace full resolution
dig -x 93.184.216.34              # reverse lookup

# Check propagation across multiple DNS servers
for ns in 8.8.8.8 1.1.1.1 9.9.9.9 208.67.222.222; do
  printf "%-15s: %s\n" "$ns" "$(dig @$ns +short api.example.com)"
done
```

### nmap — port scanning

```bash
# Scan open ports
nmap 10.0.0.5                      # default scan
nmap -p 80,443,8080 10.0.0.5      # specific ports
nmap -p 1-1024 10.0.0.5           # range
nmap -sV 10.0.0.5                  # version detection
nmap -O 10.0.0.5                   # OS detection

# Scan subnet
nmap 10.0.0.0/24                   # all hosts
nmap -p 22 10.0.0.0/24 --open     # find hosts with SSH open
```

### lsof — what process owns a socket

```bash
lsof -i                            # all network connections
lsof -i :8080                      # who is on port 8080
lsof -i TCP:443                    # TCP connections on 443
lsof -p 1234                       # all files opened by PID 1234
lsof -i -n -P | grep LISTEN        # all listening sockets
```

### ip — network interface and routing

```bash
# Interfaces
ip addr                            # all interfaces
ip addr show eth0                  # specific interface
ip link                            # link status

# Routes
ip route                           # routing table
ip route get 8.8.8.8              # which route used for this IP

# Neighbors (ARP table)
ip neigh                           # ARP cache

# Add/remove routes (temporary)
ip route add 192.168.100.0/24 via 10.0.0.1
ip route del 192.168.100.0/24
```

---

## 3. Layer-by-Layer Debugging

### Layer 1-2: Physical & Data Link

```bash
# Check interface status
ip link show eth0
# UP = enabled, LOWER_UP = cable connected

# Check for errors
ip -s link show eth0
# RX errors, TX errors → hardware/driver issue

# Check ARP table
ip neigh
arp -n

# Clear ARP cache
ip neigh flush all
```

### Layer 3: Network

```bash
# Can you ping the gateway?
ip route | grep default            # find default gateway
ping $(ip route | grep default | awk '{print $3}')

# Check routing table
ip route
# No default route → can't reach internet

# Traceroute to find where it breaks
mtr --report 8.8.8.8

# Is IP forwarding enabled (needed for routing/containers)?
cat /proc/sys/net/ipv4/ip_forward
# 0 = disabled → sysctl -w net.ipv4.ip_forward=1
```

### Layer 4: Transport

```bash
# Is the port open?
nc -zv 10.0.0.5 443
# Connection refused → service not listening or firewall blocking
# Timeout → firewall dropping packets

# What's listening?
ss -tulnp | grep :443

# Check firewall rules
iptables -L -n -v | grep 443

# TCP handshake test (with tcpdump)
# Terminal 1:
tcpdump -i eth0 host 10.0.0.5 and port 443
# Terminal 2:
nc -zv 10.0.0.5 443
# See: SYN, SYN-ACK, ACK → connection works
# See: SYN, RST → port closed
# See: SYN, SYN, SYN → firewall dropping (timeout)
```

### Layer 7: Application

```bash
# HTTP response code
curl -o /dev/null -s -w "%{http_code}" http://10.0.0.5/health

# Full request/response
curl -v http://10.0.0.5/api/status

# Check app logs
journalctl -u myapp -f
kubectl logs deployment/myapp -f

# Check if app is running
systemctl status myapp
ps aux | grep myapp
```

---

## 4. Common Scenarios

### "Connection refused"

```
Port is not open or service isn't listening

Debug:
1. ss -tulnp | grep :<port>   → is anything listening?
2. Check service status: systemctl status myapp
3. Check config: is service binding to 0.0.0.0 or just localhost?
4. iptables -L | grep <port>  → is it being blocked?

Common causes:
- Service crashed or not started
- Service listening on wrong IP (127.0.0.1 instead of 0.0.0.0)
- Wrong port in config
```

### "Connection timed out"

```
Packet is being dropped (not rejected)

Debug:
1. tcpdump → see SYN packets sent but no SYN-ACK coming back
2. Check firewall rules on both client and server
3. Check security groups / NACLs in AWS
4. Check routing: ip route get <destination>

Common causes:
- Firewall silently dropping packets (vs reject which sends RST)
- Security group missing allow rule
- NACL blocking return traffic (stateless!)
- Routing problem (packet reaches wrong host)
```

### "Cannot resolve hostname"

```
DNS failure

Debug:
1. dig api.example.com          → DNS query
2. dig @8.8.8.8 api.example.com → try different resolver
3. cat /etc/resolv.conf         → check DNS server
4. ping <DNS server IP>         → can you reach it?
5. systemctl status systemd-resolved  → DNS resolver running?

Common causes:
- Wrong DNS server configured
- DNS server unreachable (firewall blocking port 53)
- Record doesn't exist (typo in domain)
- TTL not expired after DNS change
```

### High latency

```
Performance issue somewhere in the path

Debug:
1. mtr --report 8.8.8.8        → find which hop has high latency
2. curl timing breakdown        → is it DNS, connect, or TTFB?
3. ss -i | grep -A3 <dest>     → check TCP retransmissions
4. top / iostat                 → is the server CPU/disk-bound?

Common causes:
- Distant server (choose region closer to users)
- Overloaded backend (CPU/memory)
- DNS resolution slow (use shorter TTL or closer resolver)
- Network congestion
- Too many TCP retransmissions (packet loss)
```

---

## 5. Cloud-Specific Troubleshooting

### AWS troubleshooting

```bash
# VPC Flow Logs query (CloudWatch Insights)
# Find rejected traffic to port 8080:
# fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, action
# | filter dstPort = 8080 and action = "REJECT"
# | sort @timestamp desc

# Check security group rules
aws ec2 describe-security-groups --group-ids sg-abc123 \
  | jq '.SecurityGroups[0].IpPermissions'

# Check NACL rules
aws ec2 describe-network-acls --filters "Name=vpc-id,Values=vpc-abc123"

# Check route tables
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-abc123"

# Test connectivity via SSM (no SSH needed)
aws ssm start-session --target i-0a1b2c3d4e5f6g7h8

# Check EC2 reachability analyzer
aws ec2 create-network-insights-path \
  --source i-0a1b2c3d \
  --destination i-0e5f6g7h \
  --protocol tcp
aws ec2 start-network-insights-analysis --network-insights-path-id nip-...
```

### EKS specific

```bash
# Can pods reach each other?
kubectl exec -it pod-a -- nc -zv pod-b-ip 8080
kubectl exec -it pod-a -- curl http://pod-b-ip:8080/health

# Can pods reach services?
kubectl exec -it my-pod -- nslookup kubernetes.default
kubectl exec -it my-pod -- curl http://my-service.namespace.svc.cluster.local

# Check CNI plugin
kubectl get pods -n kube-system | grep -E "calico|flannel|cilium|aws-node"
kubectl logs -n kube-system aws-node-xxxxx    # CNI agent logs

# Check node networking
kubectl describe node worker-1 | grep -A5 "Conditions"
kubectl get events --field-selector reason=FailedCreatePodSandBox
```

---

## 6. Kubernetes Network Debugging

```bash
# Run a debug pod in any namespace with full networking tools
kubectl run netshoot \
  --image=nicolaka/netshoot \
  -it --rm \
  --namespace production \
  -- bash

# Inside netshoot pod:
nslookup my-service
dig my-service.production.svc.cluster.local
curl http://my-service:8080/health
nc -zv postgres 5432
tcpdump -i any port 8080

# Check pod-to-pod connectivity
kubectl exec -it pod-a -- ping $(kubectl get pod pod-b -o jsonpath='{.status.podIP}')

# Check DNS resolution
kubectl exec -it my-pod -- cat /etc/resolv.conf
kubectl exec -it my-pod -- nslookup kubernetes.default.svc.cluster.local

# Check CoreDNS logs
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Check which network policy applies
kubectl get networkpolicies -A
kubectl describe networkpolicy my-policy -n production

# Check endpoint health
kubectl get endpoints my-service
# ENDPOINTS column empty → no pods selected by service selector

# Check service selector vs pod labels
kubectl describe svc my-service | grep Selector
kubectl get pods --show-labels | grep app=my-app
```

---

## Cheatsheet

```bash
# Reachability
ping -c 4 10.0.0.5                 # basic
mtr --report 10.0.0.5             # with loss stats
nc -zv 10.0.0.5 443               # port test
curl -v https://10.0.0.5          # HTTP test

# Port check
ss -tulnp | grep :8080            # who's on port 8080
lsof -i :8080                     # which process
nmap -p 80,443,8080 10.0.0.5     # port scan

# DNS
dig api.example.com +short
dig @8.8.8.8 api.example.com     # try specific resolver
dig +trace api.example.com        # full trace

# Capture
tcpdump -i eth0 port 443 -nn     # capture HTTPS traffic
tcpdump -i eth0 host 10.0.0.5 -w /tmp/capture.pcap

# Routes
ip route                          # routing table
ip route get 8.8.8.8             # which route for this IP
ip neigh                          # ARP table

# Kubernetes
kubectl exec -it pod -- bash
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash
kubectl get endpoints my-service  # check service targets
kubectl logs -n kube-system -l k8s-app=kube-dns  # CoreDNS
```

---

*Next: [Service Mesh & Advanced Kubernetes Networking →](./08-service-mesh-kubernetes-networking.md)*
