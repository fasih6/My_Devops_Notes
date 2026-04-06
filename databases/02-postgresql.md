# PostgreSQL — Architecture, Configuration, Replication, Operations

## Why PostgreSQL?

PostgreSQL is the most popular open-source relational database for production workloads. It is:
- The default choice for new cloud-native applications
- Used by Azure (Flexible Server), AWS (RDS/Aurora), GCP (Cloud SQL)
- Fully ACID compliant with strong consistency guarantees
- Extensible (PostGIS for geo, TimescaleDB for time-series, pgvector for AI)
- The database you will encounter most in DevOps/Platform roles

---

## PostgreSQL Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    PostgreSQL Server                         │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │   Postmaster │  │  WAL Writer  │  │  Background      │  │
│  │  (listener)  │  │  (durability)│  │  Workers         │  │
│  └──────┬───────┘  └──────────────┘  │  - Autovacuum    │  │
│         │                            │  - Checkpointer  │  │
│  ┌──────▼────────────────────────┐   │  - Stats         │  │
│  │    Per-connection Backend     │   └──────────────────┘  │
│  │    (one process per client)   │                         │
│  └──────────────────────────────┘                         │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  Shared Memory                        │  │
│  │  - Shared Buffers (data cache)                       │  │
│  │  - WAL Buffers                                       │  │
│  │  - Lock Table                                        │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                  Disk Storage                         │  │
│  │  - Data files ($PGDATA/base/)                        │  │
│  │  - WAL files ($PGDATA/pg_wal/)                       │  │
│  │  - Configuration (postgresql.conf, pg_hba.conf)      │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

**Key architectural point:** PostgreSQL uses one process per connection (not threads). This is why connection pooling (PgBouncer) is critical — spawning hundreds of processes is expensive.

---

## Critical Configuration Parameters

### postgresql.conf — Key Settings

```ini
# Memory
shared_buffers = 25%_of_RAM          # Cache for data pages — most important setting
                                      # e.g. 4GB RAM → shared_buffers = 1GB
effective_cache_size = 75%_of_RAM    # Estimate of OS cache (used by query planner)
work_mem = 4MB                        # Per-operation sort/hash memory
                                      # Careful: 100 connections × 10 sorts = 4GB
maintenance_work_mem = 256MB          # For VACUUM, CREATE INDEX, ALTER TABLE

# WAL and Checkpoints
wal_level = replica                   # Minimum for replication (logical for logical replication)
max_wal_size = 1GB                    # WAL can grow to this size before checkpoint
min_wal_size = 80MB
checkpoint_completion_target = 0.9   # Spread checkpoint I/O over 90% of interval
wal_compression = on                  # Compress WAL (reduces I/O, slight CPU cost)

# Connections
max_connections = 200                 # Max simultaneous connections
                                      # Keep low — use PgBouncer for pooling

# Autovacuum (critical for MVCC health)
autovacuum = on                       # Never disable
autovacuum_vacuum_threshold = 50      # Vacuum after 50 dead tuples + scale factor
autovacuum_vacuum_scale_factor = 0.02 # + 2% of table size
autovacuum_analyze_threshold = 50
autovacuum_analyze_scale_factor = 0.01

# Logging
log_min_duration_statement = 1000    # Log queries slower than 1 second
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on
log_temp_files = 0                   # Log all temp file usage

# Replication
wal_level = replica
max_wal_senders = 10                 # Max replication connections
```

### pg_hba.conf — Client Authentication

```
# pg_hba.conf — controls who can connect from where with what auth method
# TYPE  DATABASE  USER       ADDRESS          METHOD

# Local connections via Unix socket
local   all       postgres                    peer      # OS user must match DB user
local   all       all                         md5       # Password auth for others

# IPv4 connections
host    all       all        127.0.0.1/32     md5       # Localhost password
host    checkout  checkout_user 10.0.0.0/8    scram-sha-256  # App from internal network
host    all       replicator  10.0.1.0/24     scram-sha-256  # Replication user

# Reject everything else
host    all       all        0.0.0.0/0        reject
```

---

## Essential PostgreSQL Operations

### Database and User Management

```sql
-- Create database
CREATE DATABASE checkout
  OWNER = checkout_user
  ENCODING = 'UTF8'
  LC_COLLATE = 'en_US.UTF-8'
  LC_CTYPE = 'en_US.UTF-8'
  TEMPLATE = template0;

-- Create user with limited privileges
CREATE USER checkout_user WITH PASSWORD 'secure_password';
GRANT CONNECT ON DATABASE checkout TO checkout_user;
GRANT USAGE ON SCHEMA public TO checkout_user;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO checkout_user;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO checkout_user;

-- Grant privileges on future tables (important — doesn't apply retroactively)
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO checkout_user;

-- Read-only user (for reporting/analytics)
CREATE USER checkout_reader WITH PASSWORD 'readonly_password';
GRANT CONNECT ON DATABASE checkout TO checkout_reader;
GRANT USAGE ON SCHEMA public TO checkout_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO checkout_reader;
```

### Backup with pg_dump

```bash
# Logical backup — single database
pg_dump \
  --host=localhost \
  --port=5432 \
  --username=postgres \
  --dbname=checkout \
  --format=custom \          # Custom format: compressed, allows parallel restore
  --file=checkout_$(date +%Y%m%d_%H%M%S).dump \
  --verbose

# Restore from custom format
pg_restore \
  --host=localhost \
  --port=5432 \
  --username=postgres \
  --dbname=checkout \
  --format=custom \
  --jobs=4 \                 # Parallel restore (speeds up large databases)
  --verbose \
  checkout_20241115_143500.dump

# Full cluster backup (all databases + roles + tablespaces)
pg_dumpall \
  --host=localhost \
  --username=postgres \
  --file=full_cluster_$(date +%Y%m%d).sql

# Backup specific tables only
pg_dump \
  --table=orders \
  --table=order_items \
  --format=custom \
  --file=orders_backup.dump \
  checkout

# Backup schema only (no data)
pg_dump --schema-only --format=custom --file=schema.dump checkout

# Backup data only (no schema)
pg_dump --data-only --format=custom --file=data.dump checkout
```

### Monitoring Queries

```sql
-- Check running queries (what's happening right now)
SELECT
  pid,
  now() - query_start AS duration,
  state,
  wait_event_type,
  wait_event,
  left(query, 100) AS query
FROM pg_stat_activity
WHERE state != 'idle'
ORDER BY duration DESC;

-- Find long-running queries (> 5 minutes)
SELECT pid, now() - query_start AS duration, query
FROM pg_stat_activity
WHERE state = 'active'
  AND now() - query_start > interval '5 minutes';

-- Kill a stuck query
SELECT pg_cancel_backend(pid);    -- Graceful cancellation
SELECT pg_terminate_backend(pid); -- Forceful termination

-- Check table sizes
SELECT
  relname AS table_name,
  pg_size_pretty(pg_total_relation_size(relid)) AS total_size,
  pg_size_pretty(pg_relation_size(relid)) AS table_size,
  pg_size_pretty(pg_total_relation_size(relid) - pg_relation_size(relid)) AS index_size
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC
LIMIT 20;

-- Check index usage (find unused indexes)
SELECT
  schemaname,
  tablename,
  indexname,
  idx_scan AS index_scans,
  pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE idx_scan = 0
ORDER BY pg_relation_size(indexrelid) DESC;

-- Check table bloat (dead tuples needing vacuum)
SELECT
  relname AS table_name,
  n_live_tup AS live_rows,
  n_dead_tup AS dead_rows,
  round(n_dead_tup::numeric / nullif(n_live_tup + n_dead_tup, 0) * 100, 2) AS bloat_pct,
  last_vacuum,
  last_autovacuum
FROM pg_stat_user_tables
ORDER BY n_dead_tup DESC
LIMIT 20;

-- Check replication lag
SELECT
  client_addr,
  state,
  sent_lsn,
  write_lsn,
  flush_lsn,
  replay_lsn,
  pg_size_pretty(pg_wal_lsn_diff(sent_lsn, replay_lsn)) AS replication_lag
FROM pg_stat_replication;

-- Check connection counts by state
SELECT state, count(*)
FROM pg_stat_activity
GROUP BY state;

-- Check locks (find blocking queries)
SELECT
  blocked.pid AS blocked_pid,
  blocked.query AS blocked_query,
  blocking.pid AS blocking_pid,
  blocking.query AS blocking_query
FROM pg_stat_activity AS blocked
JOIN pg_stat_activity AS blocking
  ON blocking.pid = ANY(pg_blocking_pids(blocked.pid))
WHERE cardinality(pg_blocking_pids(blocked.pid)) > 0;
```

---

## PostgreSQL Replication

### Streaming Replication Setup

```bash
# On PRIMARY: create replication user
psql -U postgres -c "
  CREATE USER replicator WITH REPLICATION ENCRYPTED PASSWORD 'repl_password';
"

# On PRIMARY: configure postgresql.conf
wal_level = replica
max_wal_senders = 5
max_replication_slots = 5

# On PRIMARY: allow replication in pg_hba.conf
host replication replicator 10.0.1.0/24 scram-sha-256

# On REPLICA: create base backup from primary
pg_basebackup \
  --host=primary.internal \
  --username=replicator \
  --pgdata=/var/lib/postgresql/data \
  --wal-method=stream \
  --checkpoint=fast \
  --progress \
  --verbose

# On REPLICA: configure postgresql.conf
hot_standby = on                    # Allow read queries on replica
primary_conninfo = 'host=primary.internal port=5432 user=replicator password=repl_password'
recovery_target_timeline = 'latest'

# Create standby.signal (tells PostgreSQL this is a replica)
touch /var/lib/postgresql/data/standby.signal

# Start replica
pg_ctl start -D /var/lib/postgresql/data
```

### Replication Slots

Replication slots prevent the primary from discarding WAL that the replica hasn't consumed yet:

```sql
-- Create a replication slot (on primary)
SELECT pg_create_physical_replication_slot('replica1_slot');

-- Check replication slots
SELECT slot_name, slot_type, active, restart_lsn,
       pg_size_pretty(pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn)) AS retained_wal
FROM pg_replication_slots;
```

**Warning:** If a replica with a slot goes down, the primary keeps all WAL since the slot position. This can fill disk. Monitor `retained_wal` and drop slots for permanently disconnected replicas:

```sql
SELECT pg_drop_replication_slot('replica1_slot');
```

### Synchronous vs Asynchronous Replication

```ini
# Asynchronous (default):
#   Primary commits → confirms to client → WAL sent to replica later
#   Faster writes, but replica may lag
#   Risk: if primary fails before WAL reaches replica → data loss possible
synchronous_commit = off

# Synchronous:
#   Primary commits → waits for replica to acknowledge WAL receipt → confirms to client
#   Slower writes (adds replica RTT to each commit)
#   Safe: committed data always on replica
synchronous_commit = on
synchronous_standby_names = 'replica1'

# remote_write: wait for replica to write WAL to OS buffer (faster than on)
synchronous_commit = remote_write

# remote_apply: wait for replica to apply the changes (strongest guarantee)
synchronous_commit = remote_apply
```

---

## Logical Replication

Logical replication replicates individual tables (not full WAL stream). Useful for:
- Replicating specific tables to a reporting database
- Zero-downtime major version upgrades
- Cross-version replication

```sql
-- On PUBLISHER (source):
ALTER SYSTEM SET wal_level = 'logical';
SELECT pg_reload_conf();

CREATE PUBLICATION checkout_pub
  FOR TABLE orders, order_items, products;

-- On SUBSCRIBER (destination):
CREATE SUBSCRIPTION checkout_sub
  CONNECTION 'host=publisher.internal user=replicator password=xxx dbname=checkout'
  PUBLICATION checkout_pub;

-- Monitor replication status
SELECT * FROM pg_stat_subscription;
```

---

## Point-in-Time Recovery (PITR)

PITR allows restoring the database to any point in time, not just to a backup. Requires:
1. A base backup (pg_basebackup)
2. Continuous WAL archiving

```bash
# Configure WAL archiving (postgresql.conf)
archive_mode = on
archive_command = 'cp %p /mnt/wal-archive/%f'  # Or: aws s3 cp %p s3://wal-archive/%f

# Restore to a specific point in time
# 1. Restore the base backup
pg_restore --target-dir=/var/lib/postgresql/data backup.tar

# 2. Create recovery.conf (PostgreSQL < 12) or postgresql.conf entries (>= 12)
restore_command = 'cp /mnt/wal-archive/%f %p'
recovery_target_time = '2024-11-15 14:30:00'
recovery_target_action = 'promote'  # promote to primary after recovery

# 3. Create recovery signal
touch /var/lib/postgresql/data/recovery.signal

# 4. Start PostgreSQL — it replays WAL until target time
```

---

## PostgreSQL Extensions — Key Ones for DevOps

```sql
-- PostGIS: geographic/spatial data
CREATE EXTENSION postgis;

-- pg_stat_statements: track query performance statistics
CREATE EXTENSION pg_stat_statements;
-- Then query: SELECT * FROM pg_stat_statements ORDER BY total_exec_time DESC LIMIT 20;

-- uuid-ossp: generate UUIDs
CREATE EXTENSION "uuid-ossp";

-- pg_trgm: trigram-based text search (fast LIKE queries)
CREATE EXTENSION pg_trgm;

-- pgcrypto: cryptographic functions
CREATE EXTENSION pgcrypto;

-- timescaledb: time-series data (hypertables)
CREATE EXTENSION timescaledb;
```

---

## Interview Questions — PostgreSQL

**Q: What is WAL and why is it important for PostgreSQL operations?**
A: WAL (Write-Ahead Log) is PostgreSQL's mechanism for durability and replication. Before any data file is modified, the change is written to the WAL and flushed to disk. On crash recovery, PostgreSQL replays the WAL to restore committed state. For operations, WAL matters because: (1) WAL archiving enables point-in-time recovery — you can restore to any moment, not just backup time; (2) streaming replication sends WAL to replicas; (3) WAL accumulation from replication slots can fill disk; (4) `checkpoint_completion_target` and `max_wal_size` control I/O spikes from checkpoints.

**Q: How do you troubleshoot a slow PostgreSQL database?**
A: Start with `pg_stat_activity` to see running queries and their duration. Check `pg_stat_statements` for the slowest queries by total execution time. Use `EXPLAIN ANALYZE` on slow queries to see the query plan — look for sequential scans on large tables (missing index) or hash joins with large work_mem usage. Check table bloat with `pg_stat_user_tables` (high n_dead_tup means VACUUM is needed). Check connection count — if at `max_connections`, new connections are rejected. Check replication lag if applicable.

**Q: What is the risk of replication slots and how do you mitigate it?**
A: Replication slots prevent the primary from deleting WAL that a replica hasn't consumed. If a replica with a slot goes offline and doesn't reconnect, the primary accumulates WAL indefinitely — potentially filling the disk and crashing the primary. Mitigation: monitor `pg_replication_slots.retained_wal` and alert if it exceeds a threshold (e.g. 10GB). Set `max_slot_wal_keep_size` to limit WAL retained per slot. Drop slots for permanently disconnected replicas immediately.
