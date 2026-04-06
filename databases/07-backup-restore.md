# Backup & Restore — Strategies, RPO/RTO, Tools, Verification

## Why Backup Strategy Matters

A backup that hasn't been tested is not a backup — it's hope.

Most teams discover their backup strategy is broken during a disaster. The goal is to know your backup works before you need it, and to have a clear, practiced restore procedure that meets your RPO and RTO targets.

```
The three backup failures:
  1. No backups exist (negligence)
  2. Backups exist but can't be restored (untested, corrupted, missing dependencies)
  3. Backups can be restored but take too long (RTO exceeded)
```

---

## RPO and RTO — The Governing Metrics

Before choosing a backup strategy, define these for each database:

```
RPO — Recovery Point Objective:
  Maximum acceptable data loss measured in time
  "How much data can we afford to lose?"

  RPO = 0:      Zero data loss — requires synchronous replication
  RPO = 1 hour: Can lose up to 1 hour of data
  RPO = 24 hours: Daily backups are sufficient

RTO — Recovery Time Objective:
  Maximum acceptable downtime after a failure
  "How long can we be down before restoring?"

  RTO = 15 min:  Need hot standby and automated failover
  RTO = 4 hours: Need backup readily available, practiced restore
  RTO = 24 hours: Cold backup acceptable

Common tiers:
  Tier 1 (payment DB): RPO=0, RTO=15min   → Synchronous replication + hot standby
  Tier 2 (user DB):    RPO=1h, RTO=1h     → Async replication + PITR
  Tier 3 (analytics):  RPO=24h, RTO=4h    → Daily backup + restore procedure
```

---

## Backup Types

### Logical Backup

Exports data as SQL statements or structured data (JSON, CSV) that can be imported into any compatible database.

```
Pros:
  - Database/version independent (restore to different version)
  - Human-readable (SQL statements)
  - Selective restore (specific tables, rows, schemas)
  - Smaller than physical for sparse databases

Cons:
  - Slow for large databases (must serialize all data)
  - Slow restore (must execute all SQL statements)
  - Point-in-time: consistent only if database is idle or using --single-transaction

Tools: pg_dump (PostgreSQL), mysqldump (MySQL), mongodump (MongoDB)
Use for: Development, small databases (< 50GB), selective restores, migrations
```

### Physical Backup

Copies the actual database files (data pages, WAL/binlog).

```
Pros:
  - Fast backup and restore (file copy)
  - Supports point-in-time recovery (with WAL/binlog)
  - Better for large databases

Cons:
  - Database/version dependent (must restore to same/compatible version)
  - Larger backup size
  - Cannot do selective table restore easily

Tools: pgBackRest, pg_basebackup (PostgreSQL), XtraBackup (MySQL), mongodump with --oplog
Use for: Production databases, large databases (> 50GB), PITR requirements
```

### Snapshot Backup

Creates a point-in-time snapshot of the storage volume (not the database).

```
Pros:
  - Near-instantaneous (volume snapshot)
  - No database downtime
  - Easy to automate (cloud provider APIs)

Cons:
  - May capture inconsistent state (mid-transaction)
  - Volume-dependent (same cloud provider)
  - Cannot do selective table restore

Tools: Azure Disk Snapshots, AWS EBS Snapshots, Velero (K8s)
Use for: Quick recovery point, combined with database-level backups
Important: Always quiesce the database or use database-aware snapshots
```

### Continuous Backup (WAL/Binlog Streaming)

Continuously streams WAL/binlog to a remote location, enabling restore to any second.

```
Pros:
  - Enables true point-in-time recovery
  - Near-zero RPO
  - Minimal storage overhead per backup cycle

Cons:
  - Requires WAL archiving setup
  - More complex to restore
  - Ongoing storage cost for WAL files

Tools: pgBackRest (PostgreSQL), AWS RDS PITR, Azure Flexible Server PITR
Use for: Production databases requiring RPO < 1 hour
```

---

## pgBackRest — PostgreSQL Backup Tool

pgBackRest is the recommended backup tool for PostgreSQL. It supports full, differential, and incremental backups, WAL archiving, parallel processing, and encryption.

### pgBackRest Configuration

```ini
# /etc/pgbackrest/pgbackrest.conf

[global]
repo1-type=azure                          # Azure Blob Storage backend
repo1-azure-account=mybackupaccount
repo1-azure-key=<storage-key>
repo1-azure-container=postgres-backups
repo1-path=/backup/checkout-postgres

repo1-retention-full=4                    # Keep 4 full backups
repo1-retention-diff=14                   # Keep 14 differential backups
repo1-retention-archive=14               # Keep 14 days of WAL archives

repo1-cipher-type=aes-256-cbc            # Encrypt backups
repo1-cipher-pass=<encryption-password>

compress-type=lz4                        # Fast compression
compress-level=3
process-max=4                            # Parallel backup/restore processes

log-level-console=info
log-level-file=detail
log-path=/var/log/pgbackrest

[checkout-postgres]
pg1-path=/var/lib/postgresql/data
pg1-host=postgres-primary.internal
pg1-user=pgbackrest
pg1-port=5432
```

### PostgreSQL Configuration for pgBackRest

```ini
# postgresql.conf
archive_mode = on
archive_command = 'pgbackrest --stanza=checkout-postgres archive-push %p'
archive_timeout = 60          # Archive WAL at least every 60 seconds

# For backup from standby (recommended — no impact on primary)
archive_mode = always         # Archive on standby too
```

### pgBackRest Operations

```bash
# Initialize stanza (one-time setup)
pgbackrest --stanza=checkout-postgres stanza-create

# Full backup
pgbackrest --stanza=checkout-postgres backup --type=full

# Differential backup (changes since last full)
pgbackrest --stanza=checkout-postgres backup --type=diff

# Incremental backup (changes since last backup of any type)
pgbackrest --stanza=checkout-postgres backup --type=incr

# List backups
pgbackrest --stanza=checkout-postgres info

# Check backup integrity
pgbackrest --stanza=checkout-postgres check

# Restore — latest backup
pgbackrest --stanza=checkout-postgres restore

# Restore — point in time
pgbackrest --stanza=checkout-postgres restore \
  --target="2024-11-15 14:30:00" \
  --target-action=promote

# Restore — specific backup label
pgbackrest --stanza=checkout-postgres restore \
  --set=20241115-020000F   # Full backup label

# Restore specific tablespace/database (selective)
pgbackrest --stanza=checkout-postgres restore \
  --db-include=checkout   # Only restore this database
```

### Scheduled Backups with cron

```bash
# /etc/cron.d/pgbackrest
# Full backup weekly (Sunday 1am)
0 1 * * 0 postgres pgbackrest --stanza=checkout-postgres backup --type=full

# Differential backup daily (Mon-Sat 1am)
0 1 * * 1-6 postgres pgbackrest --stanza=checkout-postgres backup --type=diff

# Alert if backup hasn't run in 25 hours
# (monitoring via backup info timestamp)
```

---

## MySQL Backup with XtraBackup

```bash
# Full backup
xtrabackup \
  --backup \
  --user=backup_user \
  --password=$BACKUP_PASSWORD \
  --host=127.0.0.1 \
  --target-dir=/backup/full_$(date +%Y%m%d) \
  --parallel=4 \               # Parallel backup threads
  --compress \
  --compress-threads=4

# Prepare (make consistent)
xtrabackup --prepare \
  --apply-log-only \           # Don't rollback incomplete transactions (for incremental)
  --target-dir=/backup/full_20241115

# Incremental backup
xtrabackup \
  --backup \
  --incremental-basedir=/backup/full_20241115 \
  --target-dir=/backup/inc_$(date +%Y%m%d_%H%M)

# Prepare with incremental
xtrabackup --prepare \
  --apply-log-only \
  --target-dir=/backup/full_20241115 \
  --incremental-dir=/backup/inc_20241115_0200

# Final prepare (allow rollback of incomplete transactions)
xtrabackup --prepare --target-dir=/backup/full_20241115

# Restore
systemctl stop mysql
rm -rf /var/lib/mysql/*
xtrabackup --copy-back --target-dir=/backup/full_20241115
chown -R mysql:mysql /var/lib/mysql
systemctl start mysql
```

---

## MongoDB Backup with mongodump

```bash
# Consistent replica set backup (read from secondary)
mongodump \
  --uri="mongodb://backup_user:pass@mongo1:27017,mongo2:27017/?replicaSet=rs0&readPreference=secondary" \
  --oplog \                    # Include oplog for consistent point-in-time
  --gzip \
  --out=/backup/mongo_$(date +%Y%m%d_%H%M%S)

# Restore with oplog replay
mongorestore \
  --uri="mongodb://root:pass@localhost:27017" \
  --oplogReplay \
  --gzip \
  /backup/mongo_20241115_143500

# Point-in-time restore (using oplog)
mongorestore \
  --uri="mongodb://root:pass@localhost:27017" \
  --oplogReplay \
  --oplogLimit=1731234567:1 \  # Timestamp:ordinal — stop replaying here
  --gzip \
  /backup/mongo_20241115_000000
```

---

## Cloud-Native Backup Solutions

### Azure Backup for PostgreSQL Flexible Server

```bash
# Enable long-term retention backup via Azure portal or CLI
az postgres flexible-server backup create \
  --resource-group myRG \
  --name checkout-postgres \
  --backup-name "manual-backup-20241115"

# List available backups
az postgres flexible-server backup list \
  --resource-group myRG \
  --name checkout-postgres

# Restore to new server
az postgres flexible-server restore \
  --resource-group myRG \
  --name checkout-postgres-restored \
  --source-server checkout-postgres \
  --restore-time "2024-11-15T14:30:00Z"
```

### Velero for Kubernetes Database Backup

See `06-databases-on-kubernetes.md` for Velero setup.

```bash
# Database-consistent backup using pre/post hooks
velero backup create postgres-backup \
  --include-namespaces databases \
  --snapshot-volumes=true \
  --hooks.resources.databases.pre[0].exec.command='["/bin/bash", "-c", "psql -U postgres -c CHECKPOINT"]' \
  --hooks.resources.databases.post[0].exec.command='["/bin/bash", "-c", "echo backup complete"]'
```

---

## Backup Verification — Non-Negotiable

A backup that can't be restored is worthless. Test restores regularly:

### Automated Restore Testing

```bash
#!/bin/bash
# verify-backup.sh — Run weekly in CI/CD or cron

set -euo pipefail

BACKUP_DATE=$(date -d "yesterday" +%Y%m%d)
TEST_DB="checkout_restore_test"
LOG_FILE="/var/log/backup-verification-$(date +%Y%m%d).log"

echo "Starting backup verification for $BACKUP_DATE" | tee -a $LOG_FILE

# Step 1: Restore yesterday's backup to test database
echo "Restoring backup..." | tee -a $LOG_FILE
pgbackrest --stanza=checkout-postgres restore \
  --db-include=checkout \
  --target="$BACKUP_DATE 23:59:59" \
  --target-action=promote \
  --pg1-path=/tmp/restore_test \
  >> $LOG_FILE 2>&1

# Step 2: Start temporary PostgreSQL instance
pg_ctl start -D /tmp/restore_test -o "-p 5433" -l /tmp/restore_test.log

sleep 10

# Step 3: Run validation queries
echo "Running validation queries..." | tee -a $LOG_FILE

EXPECTED_ROWS=10000
ACTUAL_ROWS=$(psql -p 5433 -d checkout -c "SELECT COUNT(*) FROM orders" -t -A)

if [ "$ACTUAL_ROWS" -lt "$EXPECTED_ROWS" ]; then
  echo "VALIDATION FAILED: Expected >$EXPECTED_ROWS rows, got $ACTUAL_ROWS" | tee -a $LOG_FILE
  # Alert: send to PagerDuty, Slack, etc.
  curl -X POST $SLACK_WEBHOOK_URL \
    -d '{"text":"⚠️ Backup verification FAILED for checkout-postgres. Check logs."}'
  exit 1
fi

echo "VALIDATION PASSED: $ACTUAL_ROWS rows found" | tee -a $LOG_FILE

# Step 4: Cleanup
pg_ctl stop -D /tmp/restore_test
rm -rf /tmp/restore_test

echo "Backup verification complete" | tee -a $LOG_FILE
```

### Backup Verification Checklist

```
Weekly:
  □ Restore latest backup to isolated test environment
  □ Run validation queries (row counts, data integrity checks)
  □ Measure restore time (compare to RTO target)
  □ Verify backup size trend (growing normally? sudden drop = missing data?)

Monthly:
  □ Full PITR test — restore to specific timestamp 7 days ago
  □ Verify WAL archive continuity (no gaps)
  □ Test restore on different hardware/region

Annually:
  □ Full disaster recovery drill — simulate primary data center loss
  □ Measure actual RTO against target
  □ Update runbooks based on what you learned
```

---

## Interview Questions — Backup & Restore

**Q: What is the difference between RPO and RTO and how do they drive your backup strategy?**
A: RPO (Recovery Point Objective) is the maximum acceptable data loss — "how far back can we restore to?" An RPO of 1 hour means you can lose at most 1 hour of data, so you need backups or WAL archiving at least every hour. RTO (Recovery Time Objective) is the maximum acceptable downtime — "how quickly must we be back online?" An RTO of 15 minutes means you need a hot standby ready to promote, not a cold restore from backup. Together they determine your architecture: zero RPO needs synchronous replication; 15-minute RTO needs automated failover; 24-hour RTO can be met with daily backups.

**Q: What is the difference between logical and physical database backups?**
A: Logical backups (pg_dump, mysqldump) export data as SQL statements — portable, version-independent, allow selective restore, but slow for large databases. Physical backups (pgBackRest, XtraBackup) copy the actual database files — fast, support PITR via WAL/binlog archiving, but version-dependent and can't easily restore individual tables. For production use both: physical backups with WAL archiving for PITR and fast full restores; logical backups for selective table restores, migrations, and version upgrades.

**Q: How do you verify that your backups are working?**
A: Automated restore testing — weekly, restore the latest backup to an isolated environment, run validation queries (row counts, data integrity checks), and measure restore time against RTO. Alert if validation fails. Never rely on "the backup job shows green" — only a successful restore proves the backup is valid. Also check: WAL archive continuity (no gaps between backups), backup size trends (a sudden drop may indicate missing data), and restore from different failure scenarios (disk corruption, accidental deletion, PITR to specific timestamp).
