# ☁️ VPCs & Cloud Networking

AWS VPC, GCP VPC, subnets, routing, peering, Transit Gateway, and PrivateLink.

---

## 📚 Table of Contents

- [1. VPC Fundamentals](#1-vpc-fundamentals)
- [2. AWS VPC Deep Dive](#2-aws-vpc-deep-dive)
- [3. GCP VPC](#3-gcp-vpc)
- [4. VPC Peering](#4-vpc-peering)
- [5. Transit Gateway (AWS)](#5-transit-gateway-aws)
- [6. PrivateLink & VPC Endpoints](#6-privatelink--vpc-endpoints)
- [7. VPN & Direct Connect](#7-vpn--direct-connect)
- [8. Network Design Patterns](#8-network-design-patterns)
- [Cheatsheet](#cheatsheet)

---

## 1. VPC Fundamentals

A VPC (Virtual Private Cloud) is a logically isolated network within a cloud provider. You control the IP address space, subnets, routing, and gateways.

```
Cloud provider datacenter
┌─────────────────────────────────────────────────────┐
│                    Your VPC                          │
│   10.0.0.0/16                                        │
│                                                      │
│  ┌──────────────────┐  ┌──────────────────┐         │
│  │  Public Subnet   │  │  Private Subnet  │         │
│  │  10.0.1.0/24    │  │  10.0.11.0/24   │         │
│  │                  │  │                  │         │
│  │  [EC2] [ALB]     │  │  [EC2] [RDS]    │         │
│  └──────────────────┘  └──────────────────┘         │
│          │                       │                   │
│   Internet Gateway          NAT Gateway              │
│          │                       │                   │
└──────────┼───────────────────────┼───────────────────┘
           │                       │
         Internet              Internet
      (inbound+outbound)     (outbound only)
```

### Public vs Private subnets

| | Public subnet | Private subnet |
|--|--------------|----------------|
| **Route to internet** | Via Internet Gateway | Via NAT Gateway (outbound only) |
| **Public IPs** | Instances can have public IPs | No public IPs |
| **Use for** | Load balancers, bastion hosts, NAT | Databases, app servers, EKS nodes |
| **Direct inbound** | Yes (from internet) | No |

---

## 2. AWS VPC Deep Dive

### VPC components

```
VPC
├── Internet Gateway (IGW)         ← public internet access
├── NAT Gateway                    ← outbound-only internet for private subnets
├── Subnets (public + private)     ← subdivisions by AZ
├── Route Tables                   ← routing rules per subnet
├── Security Groups                ← stateful instance firewall
├── Network ACLs                   ← stateless subnet firewall
├── VPC Endpoints                  ← private access to AWS services
└── Flow Logs                      ← network traffic logging
```

### Internet Gateway

```
Allows VPC resources with public IPs to communicate with internet.
One IGW per VPC. Horizontally scaled and highly available.

Route table entry for public subnet:
  0.0.0.0/0 → igw-abc123

Without IGW → no internet connectivity, even with public IP.
```

### NAT Gateway

```
Allows private subnet resources to initiate outbound internet connections.
Prevents inbound connections from internet.

Route table entry for private subnet:
  0.0.0.0/0 → nat-abc123

NAT Gateway is in a public subnet (has an EIP).
Traffic: Private EC2 → NAT Gateway → IGW → Internet
```

```bash
# NAT Gateway costs:
# - Hourly charge (~$0.045/hr = ~$32/month per AZ)
# - Data processing charge ($0.045/GB)
# Run one per AZ for HA (recommended for production)
```

### Route tables

```
Public subnet route table:
  10.0.0.0/16  → local      (VPC traffic stays local)
  0.0.0.0/0    → igw-abc123 (internet traffic goes to IGW)

Private subnet route table:
  10.0.0.0/16  → local
  0.0.0.0/0    → nat-abc123 (internet traffic goes to NAT)

Private subnet with no internet:
  10.0.0.0/16  → local
  (no default route)
```

### Security Groups vs Network ACLs

| | Security Groups | Network ACLs |
|--|----------------|-------------|
| **Level** | Instance/ENI | Subnet |
| **Stateful** | Yes — return traffic auto-allowed | No — must allow both directions |
| **Rules** | Allow only | Allow and Deny |
| **Evaluation** | All rules evaluated | Rules evaluated in order (numbered) |
| **Default** | Deny all inbound, allow all outbound | Allow all |

```
# Security Group (stateful):
Inbound: allow port 443 from 0.0.0.0/0
→ Response packets automatically allowed (no outbound rule needed)

# NACL (stateless):
Inbound: allow port 443 from 0.0.0.0/0
Outbound: also need to allow return traffic (ephemeral ports 1024-65535)
```

### VPC Flow Logs

```bash
# Enable flow logs (capture all VPC traffic metadata)
# Can log to CloudWatch Logs or S3

# Flow log record format:
# version account-id interface-id srcaddr dstaddr srcport dstport protocol
# packets bytes windowstart windowend action flow-direction log-status

# Example:
# 2 123456789012 eni-abc123 10.0.1.5 10.0.2.3 52341 8080 6 10 840 ACCEPT OK

# Useful for:
# - Security analysis (who connected to what)
# - Debugging connectivity issues
# - Compliance and audit
```

### Elastic Network Interface (ENI)

```
An ENI is a virtual network interface attached to an EC2 instance.
Each instance has a primary ENI + can have secondary ENIs.

ENI has:
- Primary private IP
- Secondary private IPs (optional)
- One Elastic IP per private IP (optional)
- Security groups
- MAC address

# Use cases for secondary ENIs:
# - Failover (move ENI between instances for same IP)
# - Network appliances (multiple interfaces)
# - Separate IPs per application on same instance
```

### Elastic IP (EIP)

```
Static public IPv4 address. Assigned to an ENI (not an instance directly).
Free when in use, charged when not assigned (~$0.005/hr).

Use for:
- Fixed IP for DNS or external whitelisting
- NAT Gateway (always gets EIP automatically)
- Bastion hosts
- Network appliances
```

---

## 3. GCP VPC

GCP VPC is **global** by default — one VPC spans all regions (unlike AWS where VPCs are regional).

```
GCP VPC (global)
├── Subnet A (us-central1)    10.0.0.0/24
├── Subnet B (eu-west1)       10.0.1.0/24
└── Subnet C (asia-east1)     10.0.2.0/24

All subnets in same VPC can communicate by default
No need for VPC peering within same VPC
```

### GCP firewall rules

```
Applied at VPC level (not subnet level like AWS NACLs)
Stateful — like AWS Security Groups
Target by: network tags, service accounts, or all instances

# Example: allow HTTP to instances tagged "web-server"
resource "google_compute_firewall" "http" {
  name    = "allow-http"
  network = google_compute_network.main.name

  allow {
    protocol = "tcp"
    ports    = ["80", "443"]
  }

  target_tags = ["web-server"]
  source_ranges = ["0.0.0.0/0"]
}
```

### Cloud NAT (GCP)

```
GCP's managed NAT — no instance needed (unlike AWS which has a NAT Gateway resource)

# All instances in private subnets can reach internet via Cloud NAT
# No public IPs needed on instances
```

---

## 4. VPC Peering

VPC Peering connects two VPCs privately — traffic stays on the cloud provider's backbone.

```
VPC A (10.0.0.0/16)  ←──── Peering ────►  VPC B (10.1.0.0/16)
```

### Limitations

- **Non-transitive** — if A↔B and B↔C, A cannot reach C via B
- No overlapping CIDR blocks
- Must update route tables in both VPCs
- Must update security groups to allow the peered CIDR

```bash
# AWS: After creating peering connection, add routes:
# VPC A route table: 10.1.0.0/16 → pcx-abc123
# VPC B route table: 10.0.0.0/16 → pcx-abc123

# Security groups must also allow traffic from peered CIDR
```

### Cross-account peering

```
Account A VPC ←──── Peering ────► Account B VPC
Account A creates peering request
Account B accepts
Both add routes and update security groups
```

---

## 5. Transit Gateway (AWS)

Transit Gateway is a hub-and-spoke network transit hub — solves the non-transitive peering problem.

```
Without TGW (full mesh — N*(N-1)/2 peerings):
VPC A ──── VPC B
VPC A ──── VPC C
VPC B ──── VPC C
(3 peerings for 3 VPCs, 10 for 5, 45 for 10...)

With TGW (hub and spoke):
VPC A ─┐
VPC B ─┤── Transit Gateway ── VPC D
VPC C ─┘                   └── On-premises (VPN)
(N attachments, transitive routing)
```

### TGW components

```
Transit Gateway
├── Attachments          ← VPCs, VPN, Direct Connect
├── Route Tables         ← TGW-level routing
├── Route Propagation    ← auto-populate routes from attachments
└── Resource Shares      ← share TGW across accounts (RAM)
```

```hcl
# Terraform
resource "aws_ec2_transit_gateway" "main" {
  description = "Main transit gateway"
  amazon_side_asn = 64512

  default_route_table_association = "enable"
  default_route_table_propagation = "enable"

  tags = { Name = "main-tgw" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc_a" {
  transit_gateway_id = aws_ec2_transit_gateway.main.id
  vpc_id             = aws_vpc.vpc_a.id
  subnet_ids         = [aws_subnet.vpc_a_private.id]
}
```

---

## 6. PrivateLink & VPC Endpoints

Access AWS services or third-party services without traversing the internet.

### Interface Endpoints (PrivateLink)

```
Without endpoint:
  EC2 → NAT Gateway → Internet → S3/SQS/SSM

With endpoint:
  EC2 → VPC Interface Endpoint → S3/SQS/SSM
  (private, no internet, no data transfer charges)
```

```hcl
# SSM endpoint (required for SSM Session Manager without NAT)
resource "aws_vpc_endpoint" "ssm" {
  vpc_id              = aws_vpc.main.id
  service_name        = "com.amazonaws.eu-central-1.ssm"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true
}

# Required endpoints for EKS nodes without NAT:
# com.amazonaws.REGION.ssm
# com.amazonaws.REGION.ssmmessages
# com.amazonaws.REGION.ec2messages
# com.amazonaws.REGION.ecr.api
# com.amazonaws.REGION.ecr.dkr
# com.amazonaws.REGION.s3 (Gateway endpoint)
```

### Gateway Endpoints (S3 and DynamoDB only — free!)

```hcl
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.eu-central-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]
}
# Traffic to S3 goes through the endpoint, not NAT Gateway
# Saves NAT data processing costs for large S3 workloads
```

---

## 7. VPN & Direct Connect

### Site-to-Site VPN

```
On-premises network ←──── Encrypted VPN tunnel ────► AWS VPC

Components:
- Customer Gateway (CGW)  = your on-prem router
- Virtual Private Gateway (VGW) = AWS side
- VPN Connection = the tunnel

Two tunnels per connection (redundancy):
  Tunnel 1: 169.254.x.x (AWS side) ↔ your public IP
  Tunnel 2: 169.254.x.x (AWS side) ↔ your public IP (different AZ)
```

### AWS Direct Connect

```
On-premises ──── Dedicated fiber line ────► AWS

No internet — private dedicated connection
Lower latency, consistent bandwidth, lower data transfer costs
1Gbps or 10Gbps connections

Used for:
- Large data transfers (cheaper than internet egress)
- Latency-sensitive workloads
- Compliance requirements (no data over internet)
- Hybrid cloud architectures
```

---

## 8. Network Design Patterns

### Three-tier architecture

```
Internet
   │
   ▼
[Internet Gateway]
   │
[Public Subnet]
   [ALB / NAT Gateway]
   │
[Private Subnet - App]
   [ECS / EC2 / EKS]
   │
[Private Subnet - Data]
   [RDS / ElastiCache]
   │
[VPC Endpoints] → AWS Services (no internet)
```

### Hub-and-spoke with Transit Gateway

```
Shared Services VPC (10.0.0.0/16)
  [DNS, monitoring, bastion]
         │
    Transit Gateway
    ┌────┴────┐
    │         │
Dev VPC    Prod VPC
(10.1.0.0)  (10.2.0.0)
         │
    On-premises (VPN)
```

### Recommended CIDR allocation

```
Organization CIDR: 10.0.0.0/8

Per environment:
  Production:  10.0.0.0/16
  Staging:     10.1.0.0/16
  Development: 10.2.0.0/16

Per region (within prod):
  eu-central-1: 10.0.0.0/17
  us-east-1:    10.0.128.0/17

Subnets (within eu-central-1):
  Public:   10.0.0.0/24, 10.0.1.0/24, 10.0.2.0/24
  Private:  10.0.10.0/24, 10.0.11.0/24, 10.0.12.0/24
  Data:     10.0.20.0/24, 10.0.21.0/24, 10.0.22.0/24
```

---

## Cheatsheet

```bash
# AWS CLI — VPC info
aws ec2 describe-vpcs
aws ec2 describe-subnets --filters "Name=vpc-id,Values=vpc-abc123"
aws ec2 describe-route-tables --filters "Name=vpc-id,Values=vpc-abc123"
aws ec2 describe-internet-gateways
aws ec2 describe-nat-gateways

# Check connectivity
# From EC2 in private subnet:
curl https://checkip.amazonaws.com    # should show NAT Gateway EIP
curl https://s3.amazonaws.com         # should work via endpoint if configured

# VPC Flow Logs query (CloudWatch Insights)
# fields @timestamp, srcAddr, dstAddr, srcPort, dstPort, action
# | filter dstPort = 443 and action = "REJECT"
# | sort @timestamp desc
# | limit 20
```

---

*Next: [Load Balancers →](./03-load-balancers.md)*
