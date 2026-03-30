# Azure Networking 🌐

> Part of my DevOps journey — azure folder

---

## Virtual Network (VNet)

A VNet is your **private network in Azure** — equivalent to AWS VPC. Resources inside a VNet can communicate privately. VNets are scoped to a single region.

```
VNet: 10.0.0.0/16  (East US)
├── Subnet: web-subnet        10.0.1.0/24   ← public-facing resources
├── Subnet: app-subnet        10.0.2.0/24   ← application servers
├── Subnet: db-subnet         10.0.3.0/24   ← databases
└── Subnet: AzureBastionSubnet 10.0.4.0/26  ← required name for Bastion
```

```bash
# Create VNet
az network vnet create \
  --name myapp-vnet \
  --resource-group myapp-prod-rg \
  --address-prefix 10.0.0.0/16 \
  --location eastus

# Create subnet
az network vnet subnet create \
  --name app-subnet \
  --resource-group myapp-prod-rg \
  --vnet-name myapp-vnet \
  --address-prefix 10.0.2.0/24

# List subnets
az network vnet subnet list \
  --resource-group myapp-prod-rg \
  --vnet-name myapp-vnet \
  --output table
```

**Key difference from AWS:** Azure VNets don't have a concept of public vs private subnets at the subnet level. A subnet's "public/private" nature is determined by whether resources have public IPs and how NSG rules and route tables are configured.

---

## Network Security Groups (NSG)

NSGs are **stateful packet filters** — equivalent to AWS Security Groups but can be applied at both the subnet level AND the NIC (network interface) level.

```
Inbound rules:
Priority  Name            Port   Protocol  Source          Action
100       Allow-HTTP      80     TCP       *               Allow
110       Allow-HTTPS     443    TCP       *               Allow
200       Allow-SSH       22     TCP       10.0.0.0/8      Allow
65000     AllowVnetInBound *     *         VirtualNetwork  Allow  (default)
65500     DenyAllInBound  *     *         *               Deny   (default)

Outbound rules:
65000     AllowVnetOutBound *   *         VirtualNetwork  Allow  (default)
65001     AllowInternetOut  *   *         *               Allow  (default)
65500     DenyAllOutBound   *   *         *               Deny   (default)
```

Lower priority number = evaluated first. First match wins.

```bash
# Create NSG
az network nsg create \
  --name web-nsg \
  --resource-group myapp-prod-rg

# Add inbound rule
az network nsg rule create \
  --name Allow-HTTP \
  --nsg-name web-nsg \
  --resource-group myapp-prod-rg \
  --priority 100 \
  --direction Inbound \
  --access Allow \
  --protocol Tcp \
  --destination-port-ranges 80 443

# Associate NSG with subnet
az network vnet subnet update \
  --name web-subnet \
  --resource-group myapp-prod-rg \
  --vnet-name myapp-vnet \
  --network-security-group web-nsg

# Associate NSG with NIC
az network nic update \
  --name myvm-nic \
  --resource-group myapp-prod-rg \
  --network-security-group web-nsg
```

**NSG flow logs** — log all traffic for security analysis and troubleshooting, stored in Storage Account.

---

## Route Tables (User Defined Routes)

Override Azure's default routing — force traffic through NVAs (firewalls), Azure Firewall, or block internet access.

```bash
# Create route table
az network route-table create \
  --name app-route-table \
  --resource-group myapp-prod-rg

# Add route (force all internet traffic through Azure Firewall)
az network route-table route create \
  --name route-to-internet \
  --route-table-name app-route-table \
  --resource-group myapp-prod-rg \
  --address-prefix 0.0.0.0/0 \
  --next-hop-type VirtualAppliance \
  --next-hop-ip-address 10.0.0.4  # Azure Firewall private IP

# Associate with subnet
az network vnet subnet update \
  --name app-subnet \
  --resource-group myapp-prod-rg \
  --vnet-name myapp-vnet \
  --route-table app-route-table
```

---

## VNet Peering

Connect two VNets so resources communicate via private IPs. Works within a region (VNet peering) and across regions (Global VNet peering).

```
VNet-A (10.0.0.0/16) ←→ Peering ←→ VNet-B (172.16.0.0/16)
```

```bash
# Peer VNet-A → VNet-B
az network vnet peering create \
  --name vnet-a-to-b \
  --resource-group myapp-prod-rg \
  --vnet-name vnet-a \
  --remote-vnet vnet-b \
  --allow-vnet-access

# Peer VNet-B → VNet-A (peering must be created in both directions)
az network vnet peering create \
  --name vnet-b-to-a \
  --resource-group myapp-prod-rg \
  --vnet-name vnet-b \
  --remote-vnet vnet-a \
  --allow-vnet-access
```

**Not transitive** — same as AWS. Use Azure Virtual WAN or a hub VNet for hub-and-spoke.

---

## Hub-and-Spoke Network Topology

The standard enterprise network pattern in Azure:

```
On-premises
     ↓ VPN/ExpressRoute
Hub VNet (shared services)
  ├── Azure Firewall
  ├── VPN Gateway
  ├── Bastion Host
  └── DNS servers
       ↕ peering      ↕ peering      ↕ peering
Spoke VNet A        Spoke VNet B    Spoke VNet C
(Production)        (Staging)       (Dev)
```

---

## VPN Gateway

Encrypted tunnel between Azure VNet and on-premises network over the public internet.

```bash
# Create VPN Gateway (takes 15-45 minutes)
az network vnet-gateway create \
  --name myapp-vpn-gw \
  --resource-group myapp-prod-rg \
  --vnet myapp-vnet \
  --gateway-type Vpn \
  --vpn-type RouteBased \
  --sku VpnGw1 \
  --public-ip-address vpn-gw-pip
```

**SKUs:** Basic → VpnGw1 → VpnGw2 → VpnGw3 → VpnGw4 → VpnGw5 (increasing bandwidth/tunnels)

---

## ExpressRoute

**Dedicated private connection** from on-premises to Azure — bypasses the public internet. Equivalent to AWS Direct Connect.

```
On-premises DC → ExpressRoute Circuit → Azure Region
                (partner-provided,
                 50Mbps to 10Gbps)
```

Benefits: consistent latency, higher bandwidth, enhanced security, lower data transfer cost.

---

## Azure Load Balancer

| Type | Layer | Use case |
|------|-------|---------|
| **Azure Load Balancer** | Layer 4 (TCP/UDP) | Internal or public, high throughput, low latency |
| **Application Gateway** | Layer 7 (HTTP/HTTPS) | Web apps, SSL termination, URL routing, WAF |
| **Azure Front Door** | Layer 7 + CDN | Global, multi-region, CDN + WAF + routing |
| **Traffic Manager** | DNS level | DNS-based routing across regions |

### Application Gateway (≈ AWS ALB)

```bash
az network application-gateway create \
  --name myapp-agw \
  --resource-group myapp-prod-rg \
  --vnet-name myapp-vnet \
  --subnet agw-subnet \
  --sku Standard_v2 \
  --http-settings-port 80 \
  --frontend-port 80 \
  --routing-rule-type Basic \
  --public-ip-address myapp-agw-pip
```

**Application Gateway features:**
- URL path-based routing (`/api/*` → backend pool A)
- Multi-site hosting (different domains → different backend pools)
- SSL/TLS termination
- Cookie-based session affinity
- WAF (Web Application Firewall) — OWASP rule sets
- Autoscaling

### Azure Front Door (≈ AWS CloudFront + ALB + Route 53)

```bash
az afd profile create \
  --profile-name myapp-afd \
  --resource-group myapp-prod-rg \
  --sku Standard_AzureFrontDoor
```

Global HTTP load balancer with built-in CDN, WAF, and intelligent routing.

---

## Azure DNS

```bash
# Create DNS zone
az network dns zone create \
  --name myapp.com \
  --resource-group myapp-prod-rg

# Add A record
az network dns record-set a add-record \
  --zone-name myapp.com \
  --resource-group myapp-prod-rg \
  --record-set-name www \
  --ipv4-address 20.1.2.3

# Add CNAME
az network dns record-set cname set-record \
  --zone-name myapp.com \
  --resource-group myapp-prod-rg \
  --record-set-name api \
  --cname myapp-agw.eastus.cloudapp.azure.com

# List records
az network dns record-set list \
  --zone-name myapp.com \
  --resource-group myapp-prod-rg \
  --output table
```

**Private DNS zones** — DNS resolution within VNets without exposure to internet:

```bash
az network private-dns zone create \
  --name privatelink.blob.core.windows.net \
  --resource-group myapp-prod-rg

az network private-dns link vnet create \
  --zone-name privatelink.blob.core.windows.net \
  --resource-group myapp-prod-rg \
  --name myapp-vnet-link \
  --virtual-network myapp-vnet \
  --registration-enabled false
```

---

## Azure Bastion

Secure RDP/SSH to VMs through the browser — no public IP on VMs, no open SSH/RDP ports.

```bash
az network bastion create \
  --name myapp-bastion \
  --resource-group myapp-prod-rg \
  --vnet-name myapp-vnet \
  --public-ip-address bastion-pip \
  --location eastus
# Subnet must be named "AzureBastionSubnet" with /26 or larger
```

---

## Azure Firewall

Managed, cloud-native network security — centralise firewall rules across all VNets.

```bash
az network firewall create \
  --name myapp-firewall \
  --resource-group myapp-prod-rg \
  --location eastus \
  --sku-tier Premium
```

---

## Quick Reference

```bash
# VNet
az network vnet create --name x --resource-group rg --address-prefix 10.0.0.0/16
az network vnet subnet create --name x --vnet-name v --address-prefix 10.0.1.0/24

# NSG
az network nsg create --name x --resource-group rg
az network nsg rule create --name x --nsg-name n --priority 100 --direction Inbound ...
az network vnet subnet update --nsg x

# Peering (must create in both directions)
az network vnet peering create --name x --vnet-name v --remote-vnet r --allow-vnet-access

# DNS
az network dns zone create --name domain.com --resource-group rg
az network dns record-set a add-record --zone-name x --record-set-name y --ipv4-address z

Key services:
  VNet = private network (AWS VPC)
  NSG = stateful firewall at subnet + NIC level (AWS Security Group)
  App Gateway = Layer 7 LB + WAF (AWS ALB)
  Azure Front Door = global CDN + LB + WAF (AWS CloudFront + ALB)
  ExpressRoute = dedicated connection (AWS Direct Connect)
  Bastion = secure browser-based RDP/SSH (no public IPs)
```
