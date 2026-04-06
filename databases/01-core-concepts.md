# Core Concepts — ACID, CAP, BASE, Stateful Workloads, Connection Pooling

## Stateful vs Stateless Workloads

Understanding this distinction is fundamental to operating databases in cloud-native environments.

```
STATELESS WORKLOAD:
  - No local state that matters between requests
  - Any instance can handle any request
  - Scale horizontally by adding identical copies
  - Kill and replace any pod without data loss
  - Examples: API servers, web frontends, workers

STATEFUL WORKLOAD:
  - Maintains persistent data that must survive restarts
  - Each instance may have unique data or role (primary/replica)
  - Scaling and replacement require careful coordination
  - Data must be preserved across pod restarts and reschedules
  - Examples: databases, message queues, distributed caches
```

### Why Stateful Workloads Are Harder to Operate

```
Stateless pod failure:
  Pod crashes → Kubernetes replaces it → new pod starts → identical behavior
  No data loss, no coordination needed

Stateful pod failure:
  Primary DB pod crashes → data must be preserved on the PVC
  Another pod must be promoted to primary (failover)
  Clients must be redirected to new primary
  Replicas must be reconnected to new primary
  Data integrity must be verified
  All of this must happen correctly, in order, without data loss
```

This is why databases on Kubernetes are significantly more complex than stateless applications.

---

## ACID — Transactional Guarantees

ACID is the set of properties that guarantee database transactions are processed reliably. Every SQL database claims ACID compliance — understanding what each property means helps you reason about data integrity.

### Atomicity

A transaction is all-or-nothing. Either every operation in the transaction succeeds, or none of them do.

```
Example — bank transfer:
  BEGIN;
    UPDATE accounts SET balance = balance - 100 WHERE id = 1;  -- debit
    UPDATE accounts SET balance = balance + 100 WHERE id = 2;  -- credit
  COMMIT;

  If the credit fails:
    Without atomicity: account 1 is debited, account 2 is not credited → money disappears
    With atomicity: the entire transaction is rolled back → neither account changes
```

### Consistency

A transaction brings the database from one valid state to another. Data integrity constraints are always enforced.

```
Example:
  Table has constraint: balance >= 0
  A transaction that would create a negative balance is rejected
  The database remains in a consistent (valid) state
```

### Isolation

Concurrent transactions don't interfere with each other. The result is as if transactions ran sequentially.

```
Isolation levels (weakest to strongest):
  READ UNCOMMITTED  → can read uncommitted changes (dirty reads) — almost never used
  READ COMMITTED    → only read committed data (default in PostgreSQL)
  REPEATABLE READ   → same query returns same result within a transaction
  SERIALIZABLE      → full isolation, as if transactions ran one at a time

Higher isolation = stronger consistency, higher contention/lower performance
Lower isolation = higher performance, risk of anomalies (dirty reads, phantom reads)
```

### Durability

Once a transaction is committed, it persists — even if the system crashes immediately after.

```
Implementation:
  Write-Ahead Log (WAL) in PostgreSQL:
    Before changing data files, write the change to the WAL
    WAL is flushed to disk before commit returns to client
    On crash recovery: replay WAL to restore committed state

  Binary Log (binlog) in MySQL:
    Similar concept — log of all changes for recovery and replication
```

---

## CAP Theorem

The CAP theorem states that a distributed system can only guarantee **two of three** properties simultaneously:

```
C — Consistency:    Every read receives the most recent write
A — Availability:   Every request receives a response (not an error)
P — Partition tolerance: System continues operating despite network partitions

In any real distributed system, network partitions WILL happen.
Therefore, the real choice is: CP or AP.
```

```
┌─────────────────────────────────────────────────────────┐
│                    CAP THEOREM                           │
│                                                         │
│           Consistency (C)                               │
│                △                                        │
│               / \                                       │
│              /   \                                      │
│             / CP  \                                     │
│            /       \                                    │
│           /─────────\                                   │
│          /     CA    \  ← CA is theoretical only        │
│         /   (no part  \   (partitions always happen)    │
│        /    tolerance)  \                               │
│       ───────────────────                               │
│  Availability (A) ────── Partition tolerance (P)        │
│                    AP                                   │
└─────────────────────────────────────────────────────────┘
```

### CP Systems (Consistency + Partition Tolerance)

Choose consistency over availability. During a partition, the system refuses to answer rather than risk returning stale data.

```
Examples: PostgreSQL (with synchronous replication), HBase, Zookeeper, etcd
Use case: Financial transactions, inventory management — wrong data is worse than no data
Behavior during partition: Returns error rather than stale data
```

### AP Systems (Availability + Partition Tolerance)

Choose availability over consistency. During a partition, the system responds with potentially stale data.

```
Examples: Cassandra, CouchDB, DynamoDB (eventual consistency mode), DNS
Use case: Social media feeds, product catalogs — slightly stale data is acceptable
Behavior during partition: Returns best available data (may be stale)
```

### PACELC — The Extended Model

CAP only describes behavior during partitions. PACELC extends it to normal operation:

```
PAC: When there's a Partition, choose between Availability and Consistency
ELC: Else (no partition), choose between Latency and Consistency

Systems trade off latency vs consistency even when healthy.
PostgreSQL with sync replication: low latency writes impossible (must wait for replica ack)
PostgreSQL with async replication: fast writes, but replica may lag
```

---

## BASE — The NoSQL Consistency Model

BASE is the alternative to ACID, common in NoSQL databases:

```
BA — Basically Available:
  System guarantees availability, but may return stale or partial data

S  — Soft state:
  The state of the system may change over time even without input
  (replicas catching up, eventual convergence)

E  — Eventually consistent:
  Given no new updates, all replicas will eventually converge to the same value
  "Eventually" might be milliseconds or seconds
```

```
ACID vs BASE comparison:

              ACID                    BASE
─────────────────────────────────────────────────────
Consistency   Strong, immediate        Eventual
Availability  May refuse during issue  Always responds
Transactions  Full ACID support        Limited or none
Scaling       Vertical (harder)        Horizontal (easier)
Use case      Financial, relational    Social, IoT, catalog
Examples      PostgreSQL, MySQL        MongoDB, Cassandra, Redis
```

---

## Storage Engines

The storage engine is the component that actually reads and writes data to disk. Different engines make different tradeoffs.

### PostgreSQL — Heap Storage

PostgreSQL uses a heap-based storage model:
- All table data stored in heap files (unordered)
- Index separate from heap (B-tree, Hash, GiST, GIN, BRIN)
- MVCC (Multi-Version Concurrency Control) for isolation — old row versions kept until VACUUM
- WAL for durability

```
MVCC in PostgreSQL:
  Instead of locking rows for reads, PostgreSQL keeps multiple versions
  Reader sees consistent snapshot from transaction start
  Writer creates new row version, old version kept for concurrent readers
  VACUUM removes old versions no longer needed

Implication: Heavy writes + no VACUUM = table bloat (disk fills with dead tuples)
```

### MySQL InnoDB

InnoDB is MySQL's primary storage engine (default since MySQL 5.5):
- Clustered index: data stored in primary key order (B+ tree)
- Secondary indexes reference primary key (not physical row location)
- MVCC for concurrent reads
- Redo log (like WAL) for durability
- Doublewrite buffer for crash safety

```
InnoDB vs MyISAM (legacy):
  InnoDB: ACID, foreign keys, row-level locking, crash recovery
  MyISAM: No transactions, table-level locking, faster for read-heavy, no crash recovery
  → Always use InnoDB. MyISAM is legacy and being deprecated.
```

### MongoDB — WiredTiger

MongoDB's default storage engine since 3.2:
- Document-level concurrency (MVCC)
- Compression (snappy by default)
- Journal (WAL equivalent) for durability
- Checkpoint every 60 seconds + journal for point-in-time recovery

---

## Connection Pooling

Every database connection consumes resources — memory, file descriptors, CPU for SSL handshake. Connection pooling reuses connections to reduce this overhead.

```
WITHOUT CONNECTION POOLING:
  1000 app instances × 10 connections each = 10,000 DB connections
  PostgreSQL struggles beyond ~500 connections (memory, context switching)
  Each new connection: TCP handshake + SSL + auth = 50-100ms

WITH CONNECTION POOLING:
  1000 app instances → PgBouncer pool → 100 DB connections
  App gets connection from pool (microseconds, no TCP/SSL/auth)
  DB has 100 connections it can handle easily
```

### PgBouncer (PostgreSQL)

PgBouncer is the standard connection pooler for PostgreSQL:

```
Pooling modes:
  Session pooling:     One server connection per client session
                       Connection returned to pool when client disconnects
                       Safest, least efficient

  Transaction pooling: One server connection per transaction
                       Connection returned to pool after COMMIT/ROLLBACK
                       Most efficient — RECOMMENDED for most apps
                       Limitation: prepared statements and some session features don't work

  Statement pooling:   One server connection per statement
                       Maximum efficiency, very limited compatibility
                       Rarely used
```

```ini
# pgbouncer.ini
[databases]
checkout = host=postgres.internal port=5432 dbname=checkout

[pgbouncer]
listen_addr = 0.0.0.0
listen_port = 5432
auth_type = md5
auth_file = /etc/pgbouncer/userlist.txt

pool_mode = transaction         # Transaction pooling
max_client_conn = 1000          # Max clients connecting to PgBouncer
default_pool_size = 25          # Server connections per database/user pair
min_pool_size = 5               # Keep at least this many open
reserve_pool_size = 5           # Extra connections for burst
reserve_pool_timeout = 5        # Seconds before using reserve pool
server_idle_timeout = 600       # Close idle server connections after 10 min
client_idle_timeout = 0         # Never close idle client connections
```

### ProxySQL (MySQL)

ProxySQL is the standard proxy/pooler for MySQL:
- Connection pooling
- Read/write splitting (send reads to replicas, writes to primary)
- Query routing and rewriting
- Built-in monitoring

```sql
-- ProxySQL admin interface
-- Add backend MySQL servers
INSERT INTO mysql_servers(hostgroup_id, hostname, port)
VALUES (0, 'mysql-primary.internal', 3306),   -- hostgroup 0 = write
       (1, 'mysql-replica1.internal', 3306),  -- hostgroup 1 = read
       (1, 'mysql-replica2.internal', 3306);

-- Query rules: route SELECTs to replicas, writes to primary
INSERT INTO mysql_query_rules(rule_id, active, match_pattern, destination_hostgroup)
VALUES (1, 1, '^SELECT', 1),    -- SELECT → replicas (hostgroup 1)
       (2, 1, '.*', 0);         -- Everything else → primary (hostgroup 0)

LOAD MYSQL SERVERS TO RUNTIME;
LOAD MYSQL QUERY RULES TO RUNTIME;
SAVE MYSQL SERVERS TO DISK;
```

### Connection Pool Sizing Formula

```
Optimal pool size formula (from HikariCP research):
  pool_size = (core_count × 2) + effective_spindle_count

For a 4-core server with SSD (1 effective spindle):
  pool_size = (4 × 2) + 1 = 9 connections

This seems small — but it's optimal. More connections = more context switching overhead.
The formula assumes I/O-bound workloads (which databases are).

Practical PostgreSQL guideline:
  max_connections = 100-200 (for small-medium instances)
  PgBouncer pool_size = 10-25 per database/user pair
  App instances can be in the thousands — PgBouncer absorbs them
```

---

## The N+1 Query Problem

A common application-level performance issue that DevOps engineers should recognize:

```
N+1 problem:
  1 query: SELECT * FROM orders WHERE user_id = 1  → returns 100 orders
  100 queries: for each order → SELECT * FROM products WHERE id = ?

  Total: 101 queries for what could be 1 query (with JOIN)

  At scale: 1000 users loading their orders = 100,100 queries
  DB is overwhelmed not by complex queries but by sheer volume

Fix: Use JOIN, eager loading, or batch queries
DevOps relevance: Appears in slow query logs as many identical queries per second
```

---

## Interview Questions — Core Concepts

**Q: What is the CAP theorem and what does it mean for choosing a database?**
A: CAP states a distributed system can guarantee only two of: Consistency (every read gets the latest write), Availability (every request gets a response), and Partition Tolerance (system works despite network splits). Since partitions happen in any real distributed system, the real choice is CP (consistency over availability) or AP (availability over consistency). For financial data choose CP (PostgreSQL with sync replication). For social feeds, choose AP (Cassandra, DynamoDB). Understanding this helps you choose the right database for the right use case.

**Q: What is MVCC and why does it matter for PostgreSQL operations?**
A: MVCC (Multi-Version Concurrency Control) allows readers and writers to not block each other — readers see a consistent snapshot, writers create new row versions. The operational implication: old row versions accumulate as "dead tuples" and must be cleaned up by VACUUM. Without regular VACUUM, tables bloat, queries slow down, and eventually transaction ID wraparound can occur (catastrophic). Monitoring table bloat and ensuring autovacuum runs properly is an important PostgreSQL operational concern.

**Q: What is connection pooling and why is it necessary?**
A: Each database connection consumes significant resources — memory, file descriptors, and CPU for SSL handshake. Without pooling, 1000 app instances each with 10 connections = 10,000 DB connections, which overwhelms PostgreSQL. PgBouncer sits between the app and database, maintaining a small pool of actual DB connections (e.g. 25) and multiplexing thousands of app connections onto them. Transaction-mode pooling is most efficient — the DB connection is returned to the pool after each transaction, not held for the entire session.
