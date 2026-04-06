# Databases & Stateful Workloads — Index & Mental Model

## Why Databases Matter for DevOps Engineers

Most DevOps engineers treat databases as a black box — "that's the DBA's job." This is a mistake. In modern cloud-native environments:

- You deploy databases to Kubernetes (StatefulSets, operators)
- You write and run database migrations in CI/CD pipelines
- You design backup strategies that meet RPO/RTO requirements
- You configure replication and failover for high availability
- You monitor slow queries and connection pool exhaustion
- You rotate database credentials via secrets management
- You provision managed database services via Terraform
- You respond to database incidents at 3am on-call

You don't need to be a DBA. But you need to understand databases well enough to operate them reliably, deploy changes safely, and debug them under pressure.

---

## The Core Mental Model

```
┌─────────────────────────────────────────────────────────────┐
│              DATABASE OPERATIONS LANDSCAPE                   │
│                                                             │
│  DESIGN          DEPLOY           OPERATE          RECOVER  │
│  ─────────       ──────────       ─────────        ──────── │
│  Schema design   Migrations       Monitoring       Backup   │
│  Index strategy  Zero-downtime    Slow queries     Restore  │
│  Data model      Blue-green       Connection pools  Failover│
│  Normalization   Rollback plan    Replication      DR plan  │
│                                                             │
│              ↑ DevOps engineers own all of this ↑           │
└─────────────────────────────────────────────────────────────┘
```

---

## Database Categories

```
RELATIONAL (SQL)                    NON-RELATIONAL (NoSQL)
────────────────────────────────    ──────────────────────────────
PostgreSQL    ← most popular        MongoDB      ← document store
MySQL/MariaDB ← widely deployed     Redis        ← key-value / cache
Azure SQL     ← managed, Azure      Cassandra    ← wide-column
SQLite        ← embedded            DynamoDB     ← managed, AWS
                                    Cosmos DB    ← managed, Azure

When to use SQL:                    When to use NoSQL:
  - Strong consistency needed         - Flexible/changing schema
  - Complex queries/joins             - Horizontal scale priority
  - ACID transactions required        - Specific access patterns
  - Reporting and analytics           - High write throughput
  - Compliance requirements           - Document/graph/time-series
```

---

## Folder Contents

| File | What's Inside |
|------|--------------|
| `01-core-concepts.md` | Stateful vs stateless with failure scenarios · Full ACID breakdown with bank transfer example · Isolation levels (READ UNCOMMITTED → SERIALIZABLE) · WAL/binlog durability mechanics · CAP theorem with diagram and CP vs AP examples · PACELC extension · BASE vs ACID comparison · PostgreSQL MVCC and operational implications · InnoDB vs MyISAM · Connection pooling math · PgBouncer config (all 3 pooling modes) · ProxySQL read/write splitting · Pool sizing formula · N+1 query problem |
| `02-postgresql.md` | Full process architecture diagram · Critical postgresql.conf parameters (memory, WAL, autovacuum, logging, replication) · pg_hba.conf auth config · User/role creation with least privilege · pg_dump/pg_restore with all flags · 10 essential monitoring SQL queries (running queries, table sizes, unused indexes, bloat, replication lag, lock detection) · Streaming replication full setup · Replication slots with disk-fill warning · Sync vs async replication modes · Logical replication · PITR with WAL archiving · Key extensions |
| `03-mysql-mariadb.md` | MySQL vs MariaDB comparison · Thread-based vs process-based architecture · Full InnoDB my.cnf tuning (buffer pool, redo log, I/O, transactions) · Binlog formats (STATEMENT/ROW/MIXED) with recommendation · Binlog operations and PITR via mysqlbinlog · GTID replication full setup with all status fields · Replication topologies · mysqldump with all flags · Percona XtraBackup full + incremental · Monitoring queries (buffer pool hit rate, table sizes, full scans) · MariaDB Galera Cluster |
| `04-mongodb.md` | Document model vs relational comparison · When to use/avoid MongoDB · Replica set architecture with oplog diagram · mongod.conf with WiredTiger tuning · Read preferences with connection string examples · Sharding with shard key selection (good vs bad) · Full sharding setup · Indexes (single/compound/unique/sparse/TTL/text/partial) with explain · Aggregation pipeline with revenue example · mongodump/mongorestore with oplog and PITR · User management · Connection string reference |
| `05-redis.md` | All 6 data structures (String, Hash, List, Set, Sorted Set, Stream) with complete commands and use cases · RDB vs AOF persistence with pros/cons and redis.conf configs · Primary-replica replication · Sentinel HA with architecture diagram and config · Redis Cluster with slot distribution and hash tags · 5 use cases (caching, sessions, distributed locking, rate limiting, pub/sub) with working examples · Production config (maxmemory policies, security, slow log) |
| `06-databases-on-kubernetes.md` | StatefulSet vs Deployment comparison · Three StatefulSet guarantees (stable names, DNS, storage) · Full PostgreSQL StatefulSet YAML (init containers, probes, resources, volumeClaimTemplates) · Azure storage class comparison (Retain policy, allowVolumeExpansion, WaitForFirstConsumer) · PVC resizing · CloudNativePG full Cluster CRD with Azure Blob backup · MongoDB Community Operator · Redis Operator · PodDisruptionBudgets for all three · Velero with database-consistent hooks · 6 common pitfalls |
| `07-backup-restore.md` | RPO/RTO defined with 3-tier example · Backup type comparison (logical/physical/snapshot/continuous) · pgBackRest full config (Azure Blob, encryption, compression, retention) · All pgBackRest operations (full/diff/incremental/PITR) · MySQL XtraBackup full + incremental · MongoDB mongodump with oplog and PITR · Azure Backup CLI · Velero with pre/post hooks · Automated restore verification script with alerting · Complete checklist (weekly/monthly/annually) |
| `08-migrations-schema-changes.md` | Why migrations are harder than code deployments (rolling deployment problem) · Flyway naming + SQL examples · Flyway init container for K8s · Liquibase YAML with explicit rollback · golang-migrate · Zero-downtime patterns: expand-contract (full 3-phase), NOT NULL without locking (batched backfill + NOT VALID), CREATE INDEX CONCURRENTLY, column type change via dual-write trigger, table rename via shadow table · Always-forward philosophy · Pre-production checklist · lock_timeout/statement_timeout safety · Progress monitoring queries |
| `09-high-availability-replication.md` | Primary-replica, Patroni, ProxySQL, failover automation |
| `10-azure-managed-databases.md` | Azure SQL, Flexible Server, Cosmos DB, Azure Cache for Redis |
| `11-performance-observability.md` | Slow queries, EXPLAIN, indexes, exporters, dashboards |
| `12-interview-qa.md` | 18+ interview questions with full answers |

---

## Key Terms at a Glance

| Term | Definition |
|------|-----------|
| **ACID** | Atomicity, Consistency, Isolation, Durability — transaction guarantees |
| **CAP theorem** | A distributed system can only guarantee 2 of: Consistency, Availability, Partition tolerance |
| **BASE** | Basically Available, Soft state, Eventually consistent — NoSQL model |
| **RPO** | Recovery Point Objective — max acceptable data loss (time) |
| **RTO** | Recovery Time Objective — max acceptable downtime after failure |
| **WAL** | Write-Ahead Log — durability mechanism in PostgreSQL |
| **Binlog** | Binary log in MySQL — used for replication and point-in-time recovery |
| **Replication** | Copying data from primary to replica for HA and read scaling |
| **Failover** | Promoting a replica to primary when primary fails |
| **Connection pooling** | Reusing DB connections to reduce overhead (PgBouncer, ProxySQL) |
| **StatefulSet** | Kubernetes workload for stateful apps — stable network identity + persistent storage |
| **PVC** | PersistentVolumeClaim — how pods request storage in Kubernetes |
| **Operator** | Kubernetes controller that automates database lifecycle management |
| **Migration** | A versioned, reproducible change to database schema |
| **Expand-contract** | Zero-downtime migration pattern — add before remove |
| **Sharding** | Horizontal partitioning of data across multiple database nodes |

---

## Why This Topic Differentiates You

Most DevOps candidates know CI/CD and Kubernetes. Fewer know:
- How to design a zero-downtime database migration
- How to configure Patroni for automatic PostgreSQL failover
- How to size a connection pool correctly
- How to recover a database from a backup to a point in time
- What the CAP theorem means for your architecture choices

This knowledge is what separates junior from mid/senior DevOps and Platform engineers. It also directly maps to real incidents — most production outages involve a database in some way.
