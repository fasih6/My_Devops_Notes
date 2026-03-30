# Azure Notes — Index ☁️

> Part of my DevOps journey — azure folder

---

## What is Azure?

Microsoft Azure is the second-largest cloud platform globally, offering 200+ services across compute, storage, databases, networking, AI, and DevOps. Particularly strong in enterprise, hybrid cloud, and Microsoft ecosystem integration.

---

## Folder Structure

| File | What it covers |
|------|---------------|
| `01-azure-core-concepts.md` | Regions, AZs, management hierarchy, ARM, shared responsibility |
| `02-azure-entra-id.md` | Entra ID (Azure AD), users, groups, RBAC, service principals, managed identities |
| `03-azure-networking.md` | VNet, subnets, NSG, peering, VPN Gateway, ExpressRoute, Load Balancer, DNS |
| `04-azure-compute.md` | VMs, VMSS, App Service, Azure Container Instances |
| `05-azure-storage.md` | Blob, Files, Disks, Tables, Queues, lifecycle, security |
| `06-azure-databases.md` | Azure SQL, Cosmos DB, PostgreSQL, MySQL, Redis Cache |
| `07-azure-containers.md` | ACR, AKS, Container Apps, ACI |
| `08-azure-serverless.md` | Functions, Logic Apps, Event Grid, Service Bus, Event Hubs |
| `09-azure-cli-powershell.md` | az CLI, PowerShell Az module, ARM templates, Bicep |
| `10-azure-cost-management.md` | Cost Analysis, Budgets, Reservations, Advisor, tagging |
| `11-azure-real-world-patterns.md` | 3-tier, AKS+GitOps, DevOps pipelines, DR, landing zones |
| `12-azure-interview-qa.md` | Interview Q&As + AWS vs Azure comparison table |

---

## Azure vs AWS — Quick Mental Map

| AWS | Azure | What it does |
|-----|-------|-------------|
| IAM | Entra ID + RBAC | Identity & access |
| VPC | VNet | Private network |
| EC2 | Virtual Machines | Compute |
| S3 | Blob Storage | Object storage |
| EBS | Managed Disks | Block storage |
| RDS | Azure SQL / Database for PostgreSQL | Managed relational DB |
| DynamoDB | Cosmos DB | NoSQL database |
| EKS | AKS | Managed Kubernetes |
| ECR | ACR | Container registry |
| Lambda | Azure Functions | Serverless compute |
| SQS | Service Bus Queues | Message queue |
| SNS | Service Bus Topics / Event Grid | Pub/sub |
| CloudFormation | ARM Templates / Bicep | IaC (native) |
| CloudWatch | Azure Monitor | Monitoring & logging |
| CloudTrail | Activity Log | Audit log |
| Route 53 | Azure DNS | DNS service |
| Direct Connect | ExpressRoute | Dedicated network link |

---

## Azure Management Hierarchy

```
Azure AD Tenant (identity boundary)
└── Management Groups (policy governance)
    └── Subscriptions (billing + resource boundary)
        └── Resource Groups (logical container)
            └── Resources (VMs, DBs, storage, etc.)
```

---

## Learning Path

```
01 Core Concepts → 02 Entra ID → 03 Networking → 04 Compute
                                                       ↓
              07 Containers ← 06 Databases ← 05 Storage
                    ↓
              08 Serverless → 09 CLI & PS → 10 Cost
                                                 ↓
                          11 Real-World Patterns → 12 Interview Q&A
```
