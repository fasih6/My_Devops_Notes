# 🌐 Docker Networking

Bridge, host, overlay networks — how containers communicate with each other and the outside world.

---

## 📚 Table of Contents

- [1. Networking Fundamentals](#1-networking-fundamentals)
- [2. Network Drivers](#2-network-drivers)
- [3. Bridge Networks](#3-bridge-networks)
- [4. Host & None Networks](#4-host--none-networks)
- [5. DNS & Service Discovery](#5-dns--service-discovery)
- [6. Port Publishing](#6-port-publishing)
- [7. Overlay Networks (Swarm)](#7-overlay-networks-swarm)
- [8. Network Troubleshooting](#8-network-troubleshooting)
- [Cheatsheet](#cheatsheet)

---

## 1. Networking Fundamentals

### How container networking works

```
Host machine
┌────────────────────────────────────────────────────┐
│  eth0 (192.168.1.100) ← host NIC                  │
│                                                    │
│  docker0 (172.17.0.1) ← default bridge            │
│  ├── container A (172.17.0.2)                      │
│  └── container B (172.17.0.3)                      │
│                                                    │
│  br-abc123 (172.18.0.1) ← custom bridge           │
│  ├── container C (172.18.0.2)                      │
│  └── container D (172.18.0.3)                      │
└────────────────────────────────────────────────────┘
```

Each container gets its own network namespace — isolated network stack with its own interfaces, routing table, and iptables rules.

### Network types overview

| Driver | Communication | Use case |
|--------|--------------|---------|
| `bridge` | Containers on same bridge | Default, single host |
| `host` | Shares host network stack | Performance-critical, no isolation |
| `none` | No network | Maximum isolation |
| `overlay` | Multi-host container networking | Docker Swarm |
| `macvlan` | Container gets MAC/IP on LAN | Legacy apps needing direct network access |

---

## 2. Network Drivers

```bash
# List networks
docker network ls
# NETWORK ID   NAME      DRIVER    SCOPE
# abc123def    bridge    bridge    local   ← default bridge
# xyz456ghi    host      host      local
# uvw789jkl    none      null      local

# Create a network
docker network create my-network
docker network create --driver bridge my-bridge
docker network create --subnet 172.20.0.0/16 --gateway 172.20.0.1 my-network

# Inspect a network
docker network inspect my-network
docker network inspect bridge    # see default bridge config

# Remove network
docker network rm my-network
docker network prune             # remove all unused networks
```

---

## 3. Bridge Networks

### Default bridge (docker0)

The default bridge is created automatically. Containers on it can communicate by IP, but NOT by name (no DNS).

```bash
# Run two containers on default bridge
docker run -d --name c1 nginx
docker run -d --name c2 alpine sleep infinity

# c2 can reach c1 by IP (find it with docker inspect)
docker exec c2 ping 172.17.0.2

# But NOT by name (no DNS on default bridge)
docker exec c2 ping c1     # FAILS on default bridge
```

### Custom bridge (user-defined)

Custom bridges have **automatic DNS** — containers can find each other by name.

```bash
# Create custom bridge
docker network create my-app-network

# Connect containers to it
docker run -d --name db --network my-app-network postgres:15
docker run -d --name api --network my-app-network my-api-image

# Now containers can reach each other by name
docker exec api ping db           # works!
docker exec api curl http://db:5432

# Connect existing container to network
docker network connect my-app-network existing-container

# Disconnect
docker network disconnect my-app-network existing-container
```

### Container in multiple networks

```bash
# Container can be in multiple networks
docker network create frontend-net
docker network create backend-net

docker run -d --name api \
  --network backend-net \
  my-api

# Connect to second network
docker network connect frontend-net api

# Now "api" is in both networks
```

---

## 4. Host & None Networks

### Host network

Container shares the host's network stack — no isolation, highest performance.

```bash
docker run -d --network host nginx

# Container listens on host's port 80 directly
# No port mapping needed (or possible)
curl http://localhost    # works directly

# Use cases:
# - Performance-critical apps (no NAT overhead)
# - Network monitoring tools
# - Legacy apps that need specific ports
```

⚠️ Not recommended for most apps — loses network isolation and can conflict with host ports.

### None network

Container has no network connectivity at all.

```bash
docker run --network none my-app

# Use cases:
# - Batch jobs that don't need networking
# - Maximum security isolation
# - CPU/memory-only tasks
```

---

## 5. DNS & Service Discovery

### How DNS works in Docker

On custom bridge networks, Docker runs an embedded DNS server (127.0.0.11):

```bash
# Check DNS config inside container
docker exec my-container cat /etc/resolv.conf
# nameserver 127.0.0.11    ← Docker's internal DNS
# options ndots:0

# DNS resolution flow:
# 1. Container queries 127.0.0.11
# 2. Docker DNS checks if name matches any container on same network
# 3. Returns container's IP if found
# 4. Falls back to host's DNS for external names
```

### DNS aliases

```bash
# Connect container with an alias
docker network connect --alias db-primary my-network postgres-0

# Other containers can reach it as "db-primary"
docker exec api curl http://db-primary:5432
```

### External DNS

```bash
# Set custom DNS server
docker run --dns 8.8.8.8 my-app

# Add to /etc/hosts
docker run --add-host db.internal:10.0.0.5 my-app

# Set search domains
docker run --dns-search mycompany.internal my-app
```

---

## 6. Port Publishing

### Port mapping

```bash
# Map host port to container port
docker run -p 8080:80 nginx        # all interfaces: 0.0.0.0:8080 → container:80
docker run -p 127.0.0.1:8080:80 nginx  # localhost only
docker run -p 8080:80/tcp nginx    # explicit TCP
docker run -p 5353:53/udp dns-server   # UDP

# Map multiple ports
docker run -p 80:80 -p 443:443 nginx

# Random host port (Docker assigns)
docker run -p 80 nginx             # assigns random host port

# Publish ALL exposed ports (random host ports)
docker run -P nginx                # uses EXPOSE instruction in Dockerfile

# Find the assigned port
docker port my-container
docker port my-container 80
```

### Port mapping under the hood

Docker uses iptables rules to implement port mapping:

```bash
# See iptables rules Docker creates
sudo iptables -t nat -L DOCKER -n --line-numbers

# DNAT rule routes host:8080 → container:80
# OUTPUT chain handles local connections
# PREROUTING chain handles external connections
```

---

## 7. Overlay Networks (Swarm)

Overlay networks span multiple Docker hosts — used with Docker Swarm.

```bash
# Initialize Swarm (only needed for overlay)
docker swarm init

# Create overlay network
docker network create --driver overlay my-overlay

# Deploy service on overlay
docker service create \
  --name my-service \
  --network my-overlay \
  --replicas 3 \
  my-app

# Services find each other by service name
# Load balanced across all replicas automatically
```

---

## 8. Network Troubleshooting

### Debug connectivity between containers

```bash
# Run a debug container on the same network
docker run --rm -it --network my-app-network nicolaka/netshoot bash

# Inside netshoot container:
ping db                           # can we reach db container?
nslookup db                       # DNS resolution
curl http://api:8080/health       # HTTP check
nc -zv db 5432                    # TCP port check
traceroute api                    # trace the route

# Check what network a container is on
docker inspect my-container | grep -A20 Networks

# List all networks a container is connected to
docker inspect my-container --format='{{range $k, $v := .NetworkSettings.Networks}}{{$k}}{{"\n"}}{{end}}'
```

### Check which container is using a port

```bash
# On the host
ss -tulnp | grep :8080
lsof -i :8080

# Check port mapping
docker ps --format "table {{.Names}}\t{{.Ports}}"
docker port my-container
```

### Common networking issues

```bash
# Container can't reach internet
docker exec my-container curl https://google.com
# Fix: check host routing, DNS, iptables

# Containers can't find each other by name
# → They're on different networks or default bridge (no DNS)
docker inspect c1 | grep NetworkMode
docker inspect c2 | grep NetworkMode
# Fix: use custom bridge network

# Port not accessible from host
docker ps    # check port mapping
# If no port mapping → use -p flag
# If port mapped → check firewall, check container is actually listening

# High latency between containers
# → They might be on overlay network or different bridges
# → Use --network host for performance-critical communication
```

---

## Cheatsheet

```bash
# Networks
docker network ls
docker network create my-network
docker network inspect my-network
docker network connect my-network my-container
docker network disconnect my-network my-container
docker network rm my-network
docker network prune

# Run with network
docker run --network my-network my-app
docker run --network host my-app        # share host network
docker run --network none my-app        # no network

# Port mapping
docker run -p 8080:80 nginx             # host:container
docker run -p 127.0.0.1:8080:80 nginx  # localhost only
docker run -P nginx                     # publish all EXPOSE'd ports

# DNS
docker run --dns 8.8.8.8 my-app
docker run --add-host db.local:10.0.0.5 my-app

# Debug
docker exec my-container cat /etc/resolv.conf
docker inspect my-container | grep -A20 Networks
docker run --rm -it --network my-network nicolaka/netshoot bash
```

---

*Next: [Storage & Volumes →](./04-storage-volumes.md)*
