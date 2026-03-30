# Azure Interview Q&A ❓

> Part of my DevOps journey — azure folder

---

## Core Concepts

**Q: What is the difference between a Subscription, Resource Group, and Resource?**

A Subscription is the billing and access boundary — all resources belong to a subscription and costs are aggregated there. A Resource Group is a logical container for related resources that share a lifecycle (you can deploy, update, and delete them together). A Resource is an individual service instance (a VM, storage account, database). The hierarchy is: Tenant → Management Group → Subscription → Resource Group → Resource.

---

**Q: What is Azure Resource Manager (ARM)?**

ARM is the management layer for all Azure operations. Every action in Azure — whether via the portal, CLI, PowerShell, REST API, Terraform, or SDK — goes through ARM. ARM authenticates the request via Entra ID, checks RBAC authorisation, routes to the appropriate service, and records the operation in the Activity Log. ARM Templates and Bicep are Azure's native IaC formats that interact directly with ARM.

---

**Q: What are Azure Availability Zones and how do they differ from Availability Sets?**

Availability Zones are physically separate data centres within a region — each with independent power, cooling, and networking. Deploying across zones protects against entire data centre failures. Availability Sets are a legacy feature that spreads VMs across fault domains (separate racks) and update domains (staggered maintenance) within a single data centre. For new workloads, always use Availability Zones — they provide stronger isolation and are the modern approach.

---

## Identity & Security

**Q: What is the difference between Entra ID and Azure RBAC?**

Entra ID handles identity (authentication) — it verifies who you are. Azure RBAC handles authorisation — what you're allowed to do with Azure resources. They work together: Entra ID confirms your identity, RBAC determines your permissions. An analogy: Entra ID is the bouncer checking your ID, RBAC is the access control list determining which rooms you can enter.

---

**Q: What is a Managed Identity and why is it preferred over Service Principals?**

A Managed Identity is a service principal whose credentials are automatically managed by Azure — you never see, store, or rotate the credentials. This eliminates the risk of credential leakage or expiry. System-assigned identities are tied to one resource and deleted with it; user-assigned identities can be shared across multiple resources. Use Managed Identities whenever an Azure service needs to access other Azure services. Reserve Service Principals for external systems (GitHub Actions, on-premises apps) that need Azure access.

---

**Q: How does Azure RBAC inheritance work?**

RBAC assignments are inherited down the management hierarchy: a role assigned at the Management Group level is inherited by all Subscriptions, Resource Groups, and Resources beneath it. A role assigned at the Resource Group level is inherited by all Resources in that group. You can assign roles at any level — Management Group, Subscription, Resource Group, or individual Resource. The principle is: assign at the highest level that makes sense, without granting broader access than needed.

---

## Networking

**Q: What is the difference between an NSG and Azure Firewall?**

An NSG is a free, stateful Layer 4 packet filter applied at the subnet or NIC level. It allows you to define inbound/outbound rules based on source/destination IP, port, and protocol. Azure Firewall is a managed, centralised network security service that provides Layer 4 and Layer 7 filtering, FQDN-based rules (allow/deny by domain name), threat intelligence, and centralised logging. NSGs are the first line of defence within a VNet; Azure Firewall is used in the hub VNet to inspect traffic between spokes and to/from the internet.

---

**Q: Explain the hub-and-spoke network topology in Azure.**

Hub-and-spoke is the recommended enterprise network pattern. A central Hub VNet contains shared services: Azure Firewall (centralised traffic inspection), VPN Gateway or ExpressRoute (on-premises connectivity), Azure Bastion (secure VM access), and Private DNS Zones. Spoke VNets contain application workloads and are peered to the Hub. Traffic between spokes and to/from the internet flows through the Hub Firewall. Benefits: centralised security policy, shared connectivity, cost efficiency, and clear isolation between environments.

---

## Compute

**Q: What is the difference between stopping and deallocating a VM?**

Stopping a VM (via the OS shutdown command or `az vm stop`) halts the OS but keeps the VM allocated — Azure still charges for the compute. Deallocating (`az vm deallocate`) fully releases the underlying compute resources — no compute billing, only storage. The public IP may change on restart (unless using a static IP). Always deallocate dev/test VMs when not in use. Auto-shutdown schedules can automate this.

---

**Q: What are the differences between AKS, Container Apps, and ACI?**

ACI runs single containers on-demand — fast startup, per-second billing, no orchestration. Great for batch jobs, quick one-offs, and CI agents. Container Apps is serverless container hosting built on Kubernetes + KEDA — no K8s knowledge needed, auto-scales to zero, best for microservices and event-driven workloads. AKS is fully managed Kubernetes — full control, all K8s ecosystem tools (Helm, ArgoCD, etc.), but requires K8s expertise and always has node VM costs. Choose ACI for one-off tasks, Container Apps for serverless microservices, AKS for complex K8s workloads requiring full control.

---

## Storage

**Q: What are the Azure Blob Storage access tiers and when do you use each?**

Hot is for frequently accessed data — highest storage cost, lowest access cost. Cool is for infrequently accessed data (30-day minimum) — lower storage cost, retrieval fees apply. Cold is for rarely accessed data (90-day minimum) — even lower storage, higher retrieval fees. Archive is for long-term retention (180-day minimum) — cheapest storage, but data must be "rehydrated" (hours) before access. Use lifecycle management policies to automatically transition data between tiers as it ages, reducing cost without manual intervention.

---

**Q: When would you choose Managed Disks over Azure Blob Storage?**

Managed Disks (block storage) attach to VMs — use them for OS disks, database data files, and any workload needing low-latency random I/O (IOPS-intensive workloads like SQL Server, MongoDB). Blob Storage (object storage) is accessed via HTTP/SDK — use it for files, images, backups, static web content, and large unstructured data. You can't mount Blob Storage as a disk for general VM use (there's Azure Files for shared network file storage over SMB/NFS). Choose Managed Disks when you need a virtual hard drive; choose Blob when you need object storage accessible from anywhere.

---

## Databases

**Q: What is Cosmos DB and how does it differ from Azure SQL?**

Cosmos DB is a globally distributed, multi-model NoSQL database designed for millisecond latency at any scale worldwide. It supports multiple APIs (NoSQL, MongoDB, Cassandra, Gremlin, Table). It uses Request Units (RU/s) as the billing metric, and scales throughput independently of storage. Azure SQL is a fully managed relational database based on SQL Server, using SQL for queries, supporting ACID transactions, joins, and complex relationships. Choose Cosmos DB for globally distributed apps requiring consistent low latency, flexible schemas, and massive scale. Choose Azure SQL for relational data, complex queries, strong consistency, and existing SQL expertise.

---

**Q: Explain Cosmos DB partitioning.**

Cosmos DB distributes data across physical partitions based on a partition key you choose. All items with the same partition key value are stored together — enabling efficient queries within a partition. Cross-partition queries are more expensive. Choosing the right partition key is critical: it should have high cardinality (many unique values), distribute data and requests evenly, and align with your most common query patterns. Bad examples: boolean field (only 2 values = hot partition), timestamp (monotonically increasing = hot partition). Good examples: userId, customerId, productCategory.

---

## Serverless

**Q: What is the difference between Service Bus and Event Grid?**

Service Bus is an enterprise message broker for reliable, ordered, transactional message delivery — it guarantees delivery, supports message locking, dead-lettering, sessions for FIFO ordering, and retry logic. Best for command-style messages where the consumer must process each message. Event Grid is a fully managed event routing service for reactive, loosely-coupled architectures — it routes events from Azure services and custom sources to subscribers with at-least-once delivery. Best for notification-style events where you want to react to state changes. Rule of thumb: Service Bus for "do this" messages, Event Grid for "this happened" events.

---

## DevOps

**Q: How does Terraform manage state in Azure?**

Terraform state tracks what infrastructure has been created. For Azure, the recommended backend is Azure Blob Storage with the `azurerm` backend — state is stored in a container in a storage account. State locking is achieved via Azure Blob Storage leases — preventing concurrent applies from corrupting state. Enable versioning on the storage account for state file recovery. Use separate state files per environment (dev/staging/prod) and per component (network, app, database) to limit blast radius. Never commit state files to Git — they contain sensitive data.

---

**Q: How would you implement zero-downtime deployments on AKS?**

Several strategies: (1) Rolling update — Kubernetes default, gradually replaces old pods with new ones, controlled by `maxSurge` and `maxUnavailable`. (2) Blue-green — deploy v2 alongside v1, switch traffic via Service selector or Ingress update, instant rollback by reverting selector. (3) Canary — send a percentage of traffic to v2 (via Ingress NGINX weight annotations or Azure Front Door traffic splitting), gradually increase as confidence grows. Combine with readiness probes (new pods only receive traffic when ready), PodDisruptionBudgets (ensure minimum available during updates), and ArgoCD Rollouts for advanced traffic management.

---

## AWS vs Azure Quick Comparison

| Concept | AWS | Azure |
|---------|-----|-------|
| Identity | IAM | Entra ID + RBAC |
| Private network | VPC | VNet |
| Managed K8s | EKS | AKS |
| Container registry | ECR | ACR |
| Serverless compute | Lambda | Azure Functions |
| Object storage | S3 | Blob Storage |
| Block storage | EBS | Managed Disks |
| File storage | EFS | Azure Files |
| NoSQL | DynamoDB | Cosmos DB |
| Managed SQL | RDS | Azure SQL / Flexible Server |
| In-memory cache | ElastiCache | Azure Cache for Redis |
| Message queue | SQS | Service Bus Queue |
| Pub/sub | SNS | Service Bus Topic / Event Grid |
| Event streaming | Kinesis | Event Hubs |
| Dedicated link | Direct Connect | ExpressRoute |
| CDN | CloudFront | Azure Front Door / CDN |
| DNS | Route 53 | Azure DNS |
| L7 Load Balancer | ALB | Application Gateway |
| Monitoring | CloudWatch | Azure Monitor |
| Audit log | CloudTrail | Activity Log |
| Secrets | Secrets Manager | Key Vault |
| IaC native | CloudFormation | ARM / Bicep |
| Cost tool | Cost Explorer | Cost Management + Billing |
| Commit discount | Savings Plans | Savings Plans + Reservations |
| Spot compute | Spot Instances | Spot VMs (30s eviction notice) |

---

## Quick Study Table

| Topic | Key points |
|-------|-----------|
| Management hierarchy | Tenant → MG → Subscription → RG → Resource |
| Entra ID vs RBAC | Identity (who) vs Authorisation (what) |
| Managed Identity | Auto-managed credentials, no secret needed |
| AZ vs Availability Set | Zones = separate DCs (modern), Sets = same DC racks (legacy) |
| NSG vs Azure Firewall | NIC/subnet L4 filter vs centralised L4+L7 |
| Hub-spoke | Hub = shared services, Spokes = workloads, peered |
| Stop vs Deallocate | Stop = still billed compute, Deallocate = no compute billing |
| Blob tiers | Hot → Cool → Cold → Archive (cost vs access speed) |
| Cosmos DB RU/s | Request Units, throughput currency, can autoscale |
| Service Bus vs Event Grid | Reliable commands vs reactive events |
| ARM backend | azurerm backend with Blob Storage + lease locking |
