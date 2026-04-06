# MySQL / MariaDB — Architecture, Replication, Binlog, InnoDB, Backups

## MySQL vs MariaDB

MariaDB is a community fork of MySQL created in 2009 (after Oracle acquired MySQL). For DevOps purposes they are nearly identical in configuration, replication, and tooling.

```
MySQL:    Owned by Oracle. Enterprise features behind license.
          MySQL 8.x is the current major version.
          Used by: Meta, YouTube, Twitter, WordPress

MariaDB:  Community fork, always open source.
          Drop-in replacement for MySQL in most cases.
          Extra features: Aria engine, CONNECT engine, better JSON support
          Used by: Wikipedia, WordPress hosting, many Linux distros (default)

Key differences (operationally):
  - Replication: MariaDB GTID syntax differs slightly from MySQL
  - JSON: MariaDB uses a LONGTEXT internally; MySQL has native JSON type
  - Storage engines: MariaDB has Aria (crash-safe MyISAM replacement)
  - Authentication: MySQL 8 uses caching_sha2_password by default (may need config)
```

---

## MySQL Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                       MySQL Server                            │
│                                                              │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Connection Layer                        │    │
│  │  Thread pool / one thread per connection             │    │
│  │  Authentication, SSL, connection management          │    │
│  └────────────────────────┬────────────────────────────┘    │
│                           ↓                                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              SQL Layer                               │    │
│  │  Parser → Optimizer → Executor                       │    │
│  │  Query cache (removed in MySQL 8)                    │    │
│  └────────────────────────┬────────────────────────────┘    │
│                           ↓                                  │
│  ┌─────────────────────────────────────────────────────┐    │
│  │           Storage Engine Layer (pluggable)           │    │
│  │  InnoDB (default) | MyISAM (legacy) | Memory | CSV   │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                              │
│  ┌──────────────────┐    ┌──────────────────────────────┐   │
│  │   Binary Log     │    │      InnoDB Engine            │   │
│  │   (binlog)       │    │  - Buffer Pool               │   │
│  │   - Replication  │    │  - Redo Log (WAL equivalent) │   │
│  │   - PITR         │    │  - Doublewrite Buffer        │   │
│  │   - Audit        │    │  - Clustered Index (PK)      │   │
│  └──────────────────┘    └──────────────────────────────┘   │
└──────────────────────────────────────────────────────────────┘
```

**Key difference from PostgreSQL:** MySQL uses threads (not processes) per connection. This makes raw connection overhead lower than PostgreSQL, but connection pooling (ProxySQL) is still important for large-scale deployments.

---

## InnoDB — Critical Configuration

```ini
# my.cnf / my.ini — InnoDB settings

[mysqld]
# Memory
innodb_buffer_pool_size = 75%_of_RAM   # Most critical setting — InnoDB data cache
                                        # e.g. 8GB RAM → innodb_buffer_pool_size = 6G
innodb_buffer_pool_instances = 8        # Parallel buffer pool instances (reduce contention)
                                        # One per GB of buffer pool, max 8

# Redo Log
innodb_log_file_size = 512M             # Larger = better write performance, slower crash recovery
innodb_log_files_in_group = 2           # Standard: 2 log files
innodb_flush_log_at_trx_commit = 1      # 1=fully durable (ACID), 2=flush per second (risk 1s loss)

# I/O
innodb_flush_method = O_DIRECT          # Bypass OS cache for data files (avoid double buffering)
innodb_io_capacity = 2000               # IOPS available (SSD: 2000-10000, HDD: 200-400)
innodb_io_capacity_max = 4000           # Max burst IOPS

# Transactions
innodb_lock_wait_timeout = 50           # Seconds before lock wait times out
innodb_deadlock_detect = on             # Auto-detect and rollback deadlocks
transaction_isolation = READ-COMMITTED  # Usually better performance than REPEATABLE READ

# Connections
max_connections = 200
thread_cache_size = 50                  # Reuse threads

# Replication
server_id = 1                           # Unique per server in replication
log_bin = /var/log/mysql/mysql-bin      # Enable binary logging
binlog_format = ROW                     # ROW is safest for replication
expire_logs_days = 7                    # Auto-purge old binlogs
binlog_row_image = MINIMAL              # Log only changed columns (reduces binlog size)
gtid_mode = ON                          # Enable GTID replication (recommended)
enforce_gtid_consistency = ON

# Slow query log
slow_query_log = 1
slow_query_log_file = /var/log/mysql/slow.log
long_query_time = 1                     # Log queries > 1 second
log_queries_not_using_indexes = 1       # Log queries without index usage
```

---

## Binary Log (Binlog)

The binlog is MySQL's equivalent of PostgreSQL's WAL — it records all changes to data and schema.

```
Binlog formats:
  STATEMENT: logs the SQL statement
    → Compact, but non-deterministic functions (NOW(), RAND()) can cause inconsistency
    → Not recommended

  ROW: logs the actual row changes (before/after)
    → Larger, but fully deterministic and safe
    → Recommended for production

  MIXED: uses STATEMENT normally, ROW for unsafe statements
    → Compromise, but harder to reason about
```

```bash
# List binlog files
mysql -u root -p -e "SHOW BINARY LOGS;"

# Show binlog events (what changes were made)
mysqlbinlog /var/log/mysql/mysql-bin.000042 | head -100

# Point-in-time recovery using binlog
# 1. Restore last full backup
# 2. Replay binlog from backup time to recovery point
mysqlbinlog \
  --start-datetime="2024-11-15 00:00:00" \
  --stop-datetime="2024-11-15 14:30:00" \
  /var/log/mysql/mysql-bin.000042 \
  /var/log/mysql/mysql-bin.000043 \
  | mysql -u root -p

# Purge old binlogs (if expire_logs_days is not set)
mysql -u root -p -e "PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 7 DAY);"
```

---

## MySQL Replication

### GTID-Based Replication (Recommended)

GTID (Global Transaction ID) assigns a unique ID to every transaction. Replicas track which GTIDs they've applied — no need to track binlog position manually.

```bash
# On PRIMARY: configure my.cnf
[mysqld]
server_id = 1
log_bin = mysql-bin
binlog_format = ROW
gtid_mode = ON
enforce_gtid_consistency = ON
log_replica_updates = ON    # Needed for multi-replica chains

# Create replication user
mysql -u root -p -e "
  CREATE USER 'replicator'@'%' IDENTIFIED BY 'repl_password';
  GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%';
  FLUSH PRIVILEGES;
"

# On REPLICA: configure my.cnf
[mysqld]
server_id = 2                   # Must be unique
log_bin = mysql-bin
binlog_format = ROW
gtid_mode = ON
enforce_gtid_consistency = ON
read_only = ON                  # Prevent writes to replica
super_read_only = ON            # Prevent even SUPER user writes

# On REPLICA: start replication
mysql -u root -p << 'EOF'
CHANGE REPLICATION SOURCE TO
  SOURCE_HOST='primary.internal',
  SOURCE_PORT=3306,
  SOURCE_USER='replicator',
  SOURCE_PASSWORD='repl_password',
  SOURCE_AUTO_POSITION=1;        -- GTID mode: auto-position
START REPLICA;
EOF

# Check replication status
mysql -u root -p -e "SHOW REPLICA STATUS\G" | grep -E "Running|Lag|Error"
```

### Key Replication Status Fields

```sql
SHOW REPLICA STATUS\G
-- Replica_IO_Running: Yes         ← IO thread connected to primary
-- Replica_SQL_Running: Yes        ← SQL thread applying events
-- Seconds_Behind_Source: 0        ← Replication lag in seconds
-- Last_SQL_Error:                 ← Any errors applying events
-- Retrieved_Gtid_Set:             ← GTIDs received
-- Executed_Gtid_Set:              ← GTIDs applied
```

### Replication Topologies

```
Single Primary + Replica (most common):
  Primary → Replica1
  Primary → Replica2
  Use ProxySQL: writes to primary, reads to replicas

Chain replication (for geo-distribution):
  Primary → Intermediate → Replica
  Reduces load on primary, adds lag

Multi-source replication (MariaDB):
  Replica ← Primary1
  Replica ← Primary2
  Useful for consolidating data from multiple sources

Group Replication / InnoDB Cluster (MySQL 8):
  Multi-primary with conflict detection
  Built-in failover and membership management
```

---

## Backup Strategies

### mysqldump — Logical Backup

```bash
# Single database backup
mysqldump \
  --host=localhost \
  --user=backup_user \
  --password \
  --single-transaction \    # Consistent snapshot without locking (InnoDB)
  --routines \              # Include stored procedures and functions
  --triggers \              # Include triggers
  --events \                # Include events
  --set-gtid-purged=OFF \   # Don't include GTID info (for restore to different server)
  checkout > checkout_$(date +%Y%m%d_%H%M%S).sql

# All databases
mysqldump \
  --all-databases \
  --single-transaction \
  --routines \
  --events \
  --master-data=2 \         # Include binlog position (for replica setup)
  > full_backup_$(date +%Y%m%d).sql

# Compress on the fly
mysqldump --single-transaction checkout | gzip > checkout_backup.sql.gz

# Restore
gunzip < checkout_backup.sql.gz | mysql -u root -p checkout
```

### Percona XtraBackup — Physical Backup (Recommended for Large DBs)

XtraBackup performs hot physical backups without locking the database:

```bash
# Full backup
xtrabackup \
  --backup \
  --user=backup_user \
  --password=backup_pass \
  --target-dir=/backup/full_$(date +%Y%m%d)

# Prepare backup (apply redo log — makes backup consistent)
xtrabackup --prepare --target-dir=/backup/full_20241115

# Incremental backup (faster, smaller)
xtrabackup \
  --backup \
  --incremental-basedir=/backup/full_20241115 \
  --target-dir=/backup/inc_$(date +%Y%m%d_%H%M%S)

# Restore
# 1. Stop MySQL
systemctl stop mysql
# 2. Clear data directory
rm -rf /var/lib/mysql/*
# 3. Copy backup
xtrabackup --copy-back --target-dir=/backup/full_20241115
# 4. Fix permissions
chown -R mysql:mysql /var/lib/mysql
# 5. Start MySQL
systemctl start mysql
```

---

## Essential MySQL Monitoring Queries

```sql
-- Check running queries
SELECT id, user, host, db, command, time, state, left(info, 100) AS query
FROM information_schema.processlist
WHERE command != 'Sleep'
ORDER BY time DESC;

-- Kill a query
KILL QUERY 12345;    -- Kill the query, keep connection
KILL 12345;          -- Kill the connection entirely

-- Check InnoDB status (shows deadlocks, transactions, buffer pool)
SHOW ENGINE INNODB STATUS\G

-- Check slow query count
SHOW GLOBAL STATUS LIKE 'Slow_queries';

-- Check buffer pool hit rate (should be > 99%)
SELECT
  (1 - (Innodb_buffer_pool_reads / Innodb_buffer_pool_read_requests)) * 100
    AS buffer_pool_hit_rate
FROM (
  SELECT
    SUM(CASE WHEN Variable_name = 'Innodb_buffer_pool_reads'
        THEN Variable_value ELSE 0 END) AS Innodb_buffer_pool_reads,
    SUM(CASE WHEN Variable_name = 'Innodb_buffer_pool_read_requests'
        THEN Variable_value ELSE 0 END) AS Innodb_buffer_pool_read_requests
  FROM information_schema.global_status
  WHERE Variable_name IN ('Innodb_buffer_pool_reads', 'Innodb_buffer_pool_read_requests')
) t;

-- Check table sizes
SELECT
  table_schema,
  table_name,
  round(data_length / 1024 / 1024, 2) AS data_mb,
  round(index_length / 1024 / 1024, 2) AS index_mb,
  round((data_length + index_length) / 1024 / 1024, 2) AS total_mb
FROM information_schema.tables
WHERE table_schema NOT IN ('information_schema', 'performance_schema', 'mysql')
ORDER BY (data_length + index_length) DESC
LIMIT 20;

-- Find missing indexes (queries doing full table scans)
SELECT *
FROM sys.statements_with_full_table_scans
ORDER BY total_latency DESC
LIMIT 20;
```

---

## MariaDB-Specific Features

```sql
-- Galera Cluster (synchronous multi-primary replication)
-- Used by MariaDB for true multi-master HA
-- All nodes can accept writes
-- Synchronous replication — no data loss on failure
-- Configuration in my.cnf:
[mysqld]
wsrep_on = ON
wsrep_provider = /usr/lib/galera/libgalera_smm.so
wsrep_cluster_address = gcomm://node1,node2,node3
wsrep_cluster_name = checkout_cluster
wsrep_node_address = 10.0.1.1
wsrep_node_name = node1
wsrep_sst_method = rsync

-- Spider storage engine (sharding across multiple MySQL/MariaDB servers)
-- Transparent sharding — queries routed automatically
INSTALL PLUGIN spider SONAME 'ha_spider';
```

---

## Interview Questions — MySQL/MariaDB

**Q: What is the difference between MySQL binlog formats and which should you use?**
A: There are three formats: STATEMENT logs the SQL query (compact but unreliable for non-deterministic functions), ROW logs the actual row-level changes before and after (larger but fully reliable and safe), and MIXED uses STATEMENT normally but switches to ROW for unsafe statements. Always use ROW in production — it's deterministic, safe for replication, and required for point-in-time recovery accuracy. The size overhead is acceptable with `binlog_row_image = MINIMAL`.

**Q: How does GTID replication improve on traditional position-based replication?**
A: Traditional position-based replication requires tracking a specific binlog filename and position on the primary. If the primary fails and you need to point replicas to a new primary, you must manually find the equivalent position on the new primary — a complex, error-prone process. With GTID, every transaction has a globally unique ID. Replicas simply track which GTIDs they've applied. Failover becomes: `CHANGE REPLICATION SOURCE TO SOURCE_AUTO_POSITION=1` — the replica automatically finds where to resume based on GTIDs. Much simpler and less error-prone.

**Q: What is `--single-transaction` in mysqldump and why is it important?**
A: `--single-transaction` takes a consistent snapshot of InnoDB tables without acquiring locks, by starting a transaction before the dump. This means the backup is consistent (a point-in-time snapshot) while the database remains fully available for reads and writes during the backup. Without it, mysqldump uses `LOCK TABLES`, which blocks all writes for the duration of the backup — potentially hours for large databases. Always use `--single-transaction` for InnoDB backups.
