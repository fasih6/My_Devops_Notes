# Azure Databases 🗃️

> Part of my DevOps journey — azure folder

---

## Database Services Overview

| Service | Type | AWS Equivalent |
|---------|------|---------------|
| **Azure SQL Database** | Managed SQL Server | RDS SQL Server |
| **Azure SQL Managed Instance** | Full SQL Server compatibility | RDS SQL Server (more features) |
| **Azure Database for PostgreSQL** | Managed PostgreSQL | RDS PostgreSQL |
| **Azure Database for MySQL** | Managed MySQL | RDS MySQL |
| **Cosmos DB** | Globally distributed NoSQL | DynamoDB (+ more APIs) |
| **Azure Cache for Redis** | Managed Redis | ElastiCache for Redis |
| **Azure Synapse Analytics** | Data warehouse | Redshift |
| **Azure Database Migration Service** | DB migration | DMS |

---

## Azure SQL Database

Fully managed SQL Server in the cloud. Three deployment options:

| Option | Use case |
|--------|---------|
| **Single Database** | One DB, own compute, simplest |
| **Elastic Pool** | Multiple DBs share compute (cost-efficient for variable workloads) |
| **Managed Instance** | Full SQL Server compatibility, for migrations |

```bash
# Create SQL Server (logical server)
az sql server create \
  --name myapp-sql-server \
  --resource-group myapp-prod-rg \
  --location eastus \
  --admin-user sqladmin \
  --admin-password "MySecurePass123!"

# Create database
az sql db create \
  --name myapp-db \
  --resource-group myapp-prod-rg \
  --server myapp-sql-server \
  --edition GeneralPurpose \
  --compute-model Serverless \
  --family Gen5 \
  --capacity 2 \
  --min-capacity 0.5 \
  --auto-pause-delay 60 \
  --backup-storage-redundancy Zone

# Allow Azure services to connect
az sql server firewall-rule create \
  --name AllowAzureServices \
  --resource-group myapp-prod-rg \
  --server myapp-sql-server \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Add your IP
az sql server firewall-rule create \
  --name MyIP \
  --resource-group myapp-prod-rg \
  --server myapp-sql-server \
  --start-ip-address <your-ip> \
  --end-ip-address <your-ip>

# List databases
az sql db list \
  --resource-group myapp-prod-rg \
  --server myapp-sql-server \
  --output table

# Connection string format
# Server=myapp-sql-server.database.windows.net;Database=myapp-db;User Id=sqladmin;Password=...
```

### Service Tiers (Compute + Storage)

| Tier | vCores | Storage | Use case |
|------|--------|---------|---------|
| **Basic** | Shared | 2GB | Dev/test |
| **Standard (DTU)** | — | Up to 1TB | Predictable workloads |
| **General Purpose** | 2-80 | Up to 4TB | Production, balanced |
| **Business Critical** | 4-80 | Up to 4TB | High IOPS, in-memory, read replicas |
| **Hyperscale** | 2-80 | Up to 100TB | Massive databases |
| **Serverless** | Auto | — | Variable, autopause when idle |

### Azure SQL HA Features

- **Active Geo-Replication** — readable replicas up to 4 regions (like RDS Read Replicas)
- **Auto-failover groups** — automatic failover with one read/write DNS endpoint
- **Zone-redundant deployment** — data across 3 AZs automatically

```bash
# Create secondary (geo-replica)
az sql db replica create \
  --name myapp-db \
  --resource-group myapp-prod-rg \
  --server myapp-sql-server \
  --partner-server myapp-sql-server-west \
  --partner-resource-group myapp-west-rg

# Create failover group
az sql failover-group create \
  --name myapp-fog \
  --resource-group myapp-prod-rg \
  --server myapp-sql-server \
  --partner-server myapp-sql-server-west \
  --add-db myapp-db \
  --failover-policy Automatic
```

---

## Azure Database for PostgreSQL

Managed PostgreSQL — Flexible Server is the recommended deployment option.

```bash
# Create Flexible Server
az postgres flexible-server create \
  --name myapp-postgres \
  --resource-group myapp-prod-rg \
  --location eastus \
  --admin-user pgadmin \
  --admin-password "MySecurePass123!" \
  --sku-name Standard_D2ds_v5 \
  --tier GeneralPurpose \
  --storage-size 128 \
  --version 16 \
  --high-availability ZoneRedundant \
  --zone 1 \
  --standby-zone 2 \
  --backup-retention 7 \
  --geo-redundant-backup Enabled \
  --vnet myapp-vnet \
  --subnet db-subnet

# Create database
az postgres flexible-server db create \
  --server-name myapp-postgres \
  --resource-group myapp-prod-rg \
  --database-name myapp

# Connect
az postgres flexible-server connect \
  --name myapp-postgres \
  --resource-group myapp-prod-rg \
  --admin-user pgadmin \
  --database-name myapp
```

---

## Cosmos DB (≈ AWS DynamoDB, but multi-model)

**Globally distributed, multi-model NoSQL** database. Single-digit millisecond latency globally. Unlike DynamoDB, Cosmos DB supports multiple APIs:

| API | Use case |
|-----|---------|
| **NoSQL (Core)** | Document store, JSON, recommended for new apps |
| **MongoDB** | Migrate existing MongoDB apps |
| **Cassandra** | Migrate Cassandra workloads |
| **Gremlin** | Graph database |
| **Table** | Migrate Azure Table Storage workloads |

### Cosmos DB Key Concepts

```
Account → Database → Container → Items
                               (documents/rows/nodes)
```

**Request Units (RU/s)** — the currency of Cosmos DB. Every operation costs RUs. 1 RU = cost to read a 1KB item.

**Consistency levels** (5 levels, from strongest to weakest):
```
Strong → Bounded staleness → Session → Consistent prefix → Eventual
```

**Partitioning:** Choose a partition key wisely — determines data distribution. Bad partition key = hot partitions = throttling.

```bash
# Create Cosmos DB account
az cosmosdb create \
  --name myapp-cosmos \
  --resource-group myapp-prod-rg \
  --default-consistency-level Session \
  --locations regionName=eastus failoverPriority=0 isZoneRedundant=true \
  --locations regionName=westus failoverPriority=1 isZoneRedundant=false \
  --enable-multiple-write-locations false

# Create database
az cosmosdb sql database create \
  --account-name myapp-cosmos \
  --resource-group myapp-prod-rg \
  --name myapp-db

# Create container with partition key
az cosmosdb sql container create \
  --account-name myapp-cosmos \
  --resource-group myapp-prod-rg \
  --database-name myapp-db \
  --name users \
  --partition-key-path /userId \
  --throughput 400

# Autoscale throughput (scales 10% → max automatically)
az cosmosdb sql container create \
  --account-name myapp-cosmos \
  --resource-group myapp-prod-rg \
  --database-name myapp-db \
  --name orders \
  --partition-key-path /customerId \
  --max-throughput 4000  # autoscales from 400 to 4000 RU/s
```

### Global Distribution

```bash
# Add a region (read replica)
az cosmosdb update \
  --name myapp-cosmos \
  --resource-group myapp-prod-rg \
  --locations regionName=eastus failoverPriority=0 \
              regionName=westeurope failoverPriority=1 \
              regionName=southeastasia failoverPriority=2

# Enable multi-region writes (multi-master)
az cosmosdb update \
  --name myapp-cosmos \
  --resource-group myapp-prod-rg \
  --enable-multiple-write-locations true
```

---

## Azure Cache for Redis

Managed Redis — in-memory data structure store for caching, sessions, pub/sub.

```bash
# Create Redis cache
az redis create \
  --name myapp-redis \
  --resource-group myapp-prod-rg \
  --location eastus \
  --sku Premium \
  --vm-size P1 \
  --redis-version 6 \
  --enable-non-ssl-port false

# Get connection details
az redis show \
  --name myapp-redis \
  --resource-group myapp-prod-rg \
  --query "hostName" -o tsv

az redis list-keys \
  --name myapp-redis \
  --resource-group myapp-prod-rg
```

| SKU | Use case |
|-----|---------|
| Basic | Dev/test, single node, no SLA |
| Standard | Production, primary + replica, 99.9% SLA |
| Premium | Clustering, geo-replication, VNet, persistence |
| Enterprise | Higher performance, RediSearch, Bloom Filter |

---

## Quick Reference

```bash
# Azure SQL
az sql server create --name x --admin-user x --admin-password x
az sql db create --name x --server x --edition GeneralPurpose
az sql server firewall-rule create --name x --start-ip x --end-ip x

# PostgreSQL Flexible Server
az postgres flexible-server create --name x --sku-name Standard_D2ds_v5 --version 16
az postgres flexible-server db create --server-name x --database-name x

# Cosmos DB
az cosmosdb create --name x --default-consistency-level Session
az cosmosdb sql database create --account-name x --name db
az cosmosdb sql container create --account-name x --database-name db --name c --partition-key-path /id

# Redis
az redis create --name x --sku Premium --vm-size P1

Key concepts:
  Azure SQL Serverless:  auto-scales, auto-pauses when idle
  Cosmos DB RU/s:       throughput currency, can be autoscaled
  Cosmos DB APIs:       NoSQL, MongoDB, Cassandra, Gremlin, Table
  Failover groups:      automatic SQL failover across regions
  ZoneRedundant HA:     PostgreSQL standby in different AZ
```
