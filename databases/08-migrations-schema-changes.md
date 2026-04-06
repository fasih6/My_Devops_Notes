# Migrations & Schema Changes — Flyway, Liquibase, Zero-Downtime Patterns

## Why Database Migrations Are Hard

Application code deployments are relatively easy — deploy new code, old code is gone. Database migrations are fundamentally different:

```
The migration challenge:

  Application code:
    Deploy v2 → v1 is gone → clean slate
    Rollback: redeploy v1

  Database schema:
    Apply migration → old schema is gone → data must survive
    Rollback: must undo structural change without losing data
    During deployment: BOTH old and new app versions run simultaneously
                       (rolling deployment) → schema must support BOTH

  The hard constraint:
    Between deploy start and deploy end, v1 and v2 of the app
    run simultaneously against the SAME database.
    Your schema must work with BOTH versions during this window.
```

---

## Migration Tools

### Flyway

Flyway is the most popular SQL-based migration tool. It tracks which migrations have been applied using a metadata table (`flyway_schema_history`).

```
Migration file naming convention:
  V{version}__{description}.sql       → Versioned migration (runs once)
  U{version}__{description}.sql       → Undo migration (optional rollback)
  R__{description}.sql                → Repeatable migration (runs when checksum changes)

Example:
  V1__Create_orders_table.sql
  V2__Add_status_to_orders.sql
  V3__Create_order_items_table.sql
  R__Create_or_replace_views.sql
```

```sql
-- V1__Create_orders_table.sql
CREATE TABLE orders (
  id          BIGSERIAL PRIMARY KEY,
  user_id     BIGINT NOT NULL,
  total_cents BIGINT NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_orders_user_id ON orders(user_id);

-- V2__Add_status_to_orders.sql
ALTER TABLE orders
  ADD COLUMN status VARCHAR(50) NOT NULL DEFAULT 'pending';

CREATE INDEX idx_orders_status ON orders(status);

-- V3__Add_order_items_table.sql
CREATE TABLE order_items (
  id         BIGSERIAL PRIMARY KEY,
  order_id   BIGINT NOT NULL REFERENCES orders(id),
  product_id BIGINT NOT NULL,
  quantity   INT NOT NULL,
  unit_cents BIGINT NOT NULL
);

CREATE INDEX idx_order_items_order_id ON order_items(order_id);
```

```yaml
# Flyway configuration (flyway.conf or application.yaml)
flyway:
  url: jdbc:postgresql://postgres.internal:5432/checkout
  user: checkout_migrations
  password: ${DB_MIGRATION_PASSWORD}
  locations: classpath:db/migration
  baselineOnMigrate: true           # For databases that already exist
  validateOnMigrate: true           # Validate checksums before running
  outOfOrder: false                 # Don't allow out-of-order migrations
  placeholders:
    schema: public

# Run in CI/CD (before application deployment)
flyway migrate

# Check migration status
flyway info

# Validate applied migrations haven't changed
flyway validate

# Repair checksum mismatch (after editing a migration — usually wrong approach)
flyway repair
```

### Flyway in Kubernetes — Init Container Pattern

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: checkout-api
spec:
  template:
    spec:
      initContainers:
        - name: flyway-migrate
          image: flyway/flyway:10
          args:
            - -url=jdbc:postgresql://postgres.internal:5432/checkout
            - -user=checkout_migrations
            - -password=$(DB_MIGRATION_PASSWORD)
            - -locations=filesystem:/flyway/sql
            - migrate
          env:
            - name: DB_MIGRATION_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: checkout-db-secret
                  key: migration-password
          volumeMounts:
            - name: migrations
              mountPath: /flyway/sql

      containers:
        - name: checkout-api
          image: myregistry/checkout-api:v2.0.0
          # ... app container

      volumes:
        - name: migrations
          configMap:
            name: checkout-migrations
```

The init container runs Flyway migrations before the application starts. If migration fails, the init container fails and the Deployment rollout stops — the old version keeps running.

### Liquibase

Liquibase is more flexible than Flyway — supports XML, YAML, JSON, and SQL changelogs. Better for database-agnostic migrations.

```yaml
# db/changelog/db.changelog-master.yaml
databaseChangeLog:
  - include:
      file: db/changelog/v1-create-orders.yaml
  - include:
      file: db/changelog/v2-add-status.yaml

---
# db/changelog/v1-create-orders.yaml
databaseChangeLog:
  - changeSet:
      id: 1
      author: devops-team
      changes:
        - createTable:
            tableName: orders
            columns:
              - column:
                  name: id
                  type: BIGINT
                  autoIncrement: true
                  constraints:
                    primaryKey: true
              - column:
                  name: user_id
                  type: BIGINT
                  constraints:
                    nullable: false
              - column:
                  name: total_cents
                  type: BIGINT
                  constraints:
                    nullable: false
              - column:
                  name: created_at
                  type: TIMESTAMPTZ
                  defaultValueComputed: NOW()

---
# db/changelog/v2-add-status.yaml
databaseChangeLog:
  - changeSet:
      id: 2
      author: devops-team
      rollback:                    # Explicit rollback (Liquibase feature)
        - dropColumn:
            tableName: orders
            columnName: status
      changes:
        - addColumn:
            tableName: orders
            columns:
              - column:
                  name: status
                  type: VARCHAR(50)
                  defaultValue: pending
                  constraints:
                    nullable: false
```

```bash
# Liquibase CLI
liquibase update                  # Apply pending changes
liquibase status                  # Show pending changes
liquibase rollback-count 1        # Rollback last 1 changeset
liquibase generate-changelog      # Generate changelog from existing database
liquibase diff                    # Diff two databases
```

### golang-migrate (for Go projects)

```bash
# Install
go install -tags 'postgres' github.com/golang-migrate/migrate/v4/cmd/migrate@latest

# Create migration files
migrate create -ext sql -dir db/migrations -seq create_orders_table
# Creates: 000001_create_orders_table.up.sql and 000001_create_orders_table.down.sql

# Apply migrations
migrate -path db/migrations -database "postgresql://user:pass@host/dbname?sslmode=disable" up

# Rollback last migration
migrate -path db/migrations -database "..." down 1

# Check version
migrate -path db/migrations -database "..." version
```

---

## Zero-Downtime Migration Patterns

The hardest migrations are structural changes during rolling deployments. Here are the patterns that make them safe.

### The Fundamental Rule

**Every migration must be backward compatible with the previous version of the application.**

During a rolling deployment, both old (v1) and new (v2) app versions run simultaneously. The database must work with both.

### Pattern 1: Expand-Contract (The Most Important Pattern)

Also called "parallel change" or "blue-green migration." Used for renaming columns, changing types, splitting or merging columns.

```
Example: Rename column "total" → "total_cents"

WRONG approach (causes downtime):
  Migration: ALTER TABLE orders RENAME COLUMN total TO total_cents;
  Deploy new app
  → Window where v1 app (uses "total") runs against new schema (has "total_cents") → BROKEN

CORRECT approach (expand-contract):

Phase 1 — EXPAND (additive only, fully backward compatible):
  Migration: ALTER TABLE orders ADD COLUMN total_cents BIGINT;
  Deploy: Copy data from total to total_cents via background job
  Both v1 (reads total) and v2 (reads total_cents) work fine
  Dual-write: new app writes to BOTH columns

Phase 2 — MIGRATE DATA:
  UPDATE orders SET total_cents = total WHERE total_cents IS NULL;
  Verify: all rows have total_cents populated

Phase 3 — CONTRACT (remove old column after all v1 instances are gone):
  Migration: ALTER TABLE orders DROP COLUMN total;
  This migration runs AFTER v2 is fully deployed and v1 is gone
  Safe: no running code uses "total" anymore
```

```
Timeline:
  Week 1: Deploy Phase 1 migration + v2 app (dual-write to both columns)
  Week 1: Background job backfills total_cents for all existing rows
  Week 2: Verify all rows have total_cents, remove dual-write
  Week 3: Deploy Phase 3 migration (drop old column)

This is slow — but it's safe. Never rush schema migrations.
```

### Pattern 2: Adding a NOT NULL Column

Adding a NOT NULL column to a large table requires special handling — a naïve ALTER TABLE will lock the entire table.

```sql
-- WRONG: Locks table for minutes/hours on large tables
ALTER TABLE orders ADD COLUMN fulfilled_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

-- CORRECT: Add nullable first, backfill, then add constraint

-- Step 1: Add column as nullable (fast, no lock)
ALTER TABLE orders ADD COLUMN fulfilled_at TIMESTAMPTZ;

-- Step 2: Backfill in batches (avoids long transaction holding lock)
DO $$
DECLARE
  batch_size INT := 10000;
  last_id BIGINT := 0;
  max_id BIGINT;
BEGIN
  SELECT MAX(id) INTO max_id FROM orders;
  WHILE last_id < max_id LOOP
    UPDATE orders
    SET fulfilled_at = created_at  -- Or whatever default makes sense
    WHERE id > last_id AND id <= last_id + batch_size
      AND fulfilled_at IS NULL;
    last_id := last_id + batch_size;
    PERFORM pg_sleep(0.1);  -- Brief pause to avoid overwhelming DB
  END LOOP;
END $$;

-- Step 3: Add NOT NULL constraint (validates all rows, but fast if all populated)
-- In PostgreSQL 12+: ADD CONSTRAINT with NOT VALID + VALIDATE CONSTRAINT
ALTER TABLE orders ADD CONSTRAINT orders_fulfilled_at_not_null CHECK (fulfilled_at IS NOT NULL) NOT VALID;
-- NOT VALID: adds constraint without scanning (fast)
-- Then validate in background:
ALTER TABLE orders VALIDATE CONSTRAINT orders_fulfilled_at_not_null;
-- VALIDATE takes ShareUpdateExclusiveLock (doesn't block reads/writes)
```

### Pattern 3: Adding an Index Without Locking

```sql
-- WRONG: Locks table during index build (blocks all writes)
CREATE INDEX idx_orders_status ON orders(status);

-- CORRECT: Build concurrently (no table lock, slightly slower)
CREATE INDEX CONCURRENTLY idx_orders_status ON orders(status);

-- For MySQL:
ALTER TABLE orders ADD INDEX idx_status (status), ALGORITHM=INPLACE, LOCK=NONE;
```

`CONCURRENTLY` allows reads and writes during index build. It takes longer but never locks. Use it for all index creation in production.

### Pattern 4: Zero-Downtime Column Type Change

```sql
-- Example: Change status VARCHAR(50) → status_id INT (FK to status table)

-- Step 1: Add new column
ALTER TABLE orders ADD COLUMN status_id INT REFERENCES order_statuses(id);

-- Step 2: Create trigger to dual-write (keeps both in sync during transition)
CREATE OR REPLACE FUNCTION sync_order_status()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status IS NOT NULL AND NEW.status_id IS NULL THEN
    SELECT id INTO NEW.status_id FROM order_statuses WHERE name = NEW.status;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER sync_order_status_trigger
  BEFORE INSERT OR UPDATE ON orders
  FOR EACH ROW EXECUTE FUNCTION sync_order_status();

-- Step 3: Backfill existing rows
UPDATE orders o
SET status_id = s.id
FROM order_statuses s
WHERE o.status = s.name AND o.status_id IS NULL;

-- Step 4: Deploy new app version (uses status_id, not status)
-- Step 5: After v1 is gone:
ALTER TABLE orders DROP COLUMN status;
DROP TRIGGER sync_order_status_trigger ON orders;
DROP FUNCTION sync_order_status();
```

### Pattern 5: Table Rename (Shadow Table)

Renaming a table requires a shadow table approach:

```sql
-- Step 1: Create new table with new name
CREATE TABLE order_transactions (LIKE orders INCLUDING ALL);
-- Copy data
INSERT INTO order_transactions SELECT * FROM orders;

-- Step 2: Create view with old name (backward compatible)
CREATE VIEW orders AS SELECT * FROM order_transactions;
-- Make view writable (PostgreSQL)
CREATE RULE orders_insert AS ON INSERT TO orders DO INSTEAD
  INSERT INTO order_transactions VALUES (NEW.*);
CREATE RULE orders_update AS ON UPDATE TO orders DO INSTEAD
  UPDATE order_transactions SET ... WHERE id = OLD.id;
CREATE RULE orders_delete AS ON DELETE TO orders DO INSTEAD
  DELETE FROM order_transactions WHERE id = OLD.id;

-- Step 3: Deploy new app using order_transactions
-- Step 4: Drop view and old rules once v1 is gone
DROP VIEW orders;
```

---

## Migration Best Practices

### Always Forward (No Down Migrations in Production)

```
Philosophy: Never roll back a migration in production.

Reason: Your database has live data written by the new schema.
        Rolling back the schema may lose or corrupt that data.

Instead:
  Write a NEW migration that undoes the change safely.
  This preserves data integrity and audit history.

Exception: If you catch the mistake before any production traffic
           hits the new schema, a rollback is safe.
```

### Migration Checklist

```
Before writing a migration:
  □ Does this migration support the previous app version (backward compatible)?
  □ Does this change lock any tables? How long?
  □ Is this safe to run while the application is live?
  □ Have I tested this on a production-sized dataset (not just dev)?
  □ Is there a rollback plan if this goes wrong?

Before running in production:
  □ Tested on staging with production-like data volume
  □ Measured duration on staging (extrapolate to production)
  □ Backup taken immediately before migration
  □ Deployment window communicated to stakeholders
  □ Rollback plan documented and ready
  □ Database metrics monitored during migration

During migration:
  □ Monitor: lock waits, active connections, replication lag
  □ Have kill switch ready (can you terminate the migration if needed?)
```

### Long-Running Migration Safety

For migrations that take more than a few seconds on a large table:

```sql
-- Set a lock timeout (don't wait forever for a lock)
SET lock_timeout = '5s';   -- Fail rather than wait >5s for a lock

-- Set a statement timeout (don't run forever)
SET statement_timeout = '10min';

-- Check estimated duration before running
EXPLAIN (ANALYZE, BUFFERS) ALTER TABLE orders ADD COLUMN new_field INT;
-- (EXPLAIN won't actually run the ALTER, but similar SELECTs give duration clues)

-- Monitor migration progress (PostgreSQL 12+)
SELECT phase, blocks_done, blocks_total,
       round(blocks_done::numeric/nullif(blocks_total,0)*100, 2) AS pct
FROM pg_stat_progress_create_index;  -- For CREATE INDEX CONCURRENTLY

SELECT phase, heap_blks_scanned, heap_blks_total,
       round(heap_blks_scanned::numeric/nullif(heap_blks_total,0)*100, 2) AS pct
FROM pg_stat_progress_cluster;       -- For CLUSTER/VACUUM FULL
```

---

## Interview Questions — Migrations

**Q: What is the expand-contract pattern and why is it necessary?**
A: Expand-contract (or parallel change) is a pattern for making breaking schema changes without downtime. In a rolling deployment, old and new app versions run simultaneously against the same database, so the schema must support both. The pattern has three phases: Expand (add the new column/table while keeping the old — backward compatible), Migrate (backfill data, deploy new app that uses both), Contract (remove the old column/table once all old app instances are gone). Without this pattern, renaming a column causes failures in the old app version during the deployment window.

**Q: How do you add a NOT NULL column to a large table without downtime?**
A: Never add a NOT NULL column with a DEFAULT in one statement on a large table — it rewrites the entire table and holds a lock for minutes. Instead: (1) Add the column as nullable (fast, no lock), (2) Backfill existing rows in small batches with brief pauses to avoid overwhelming the database, (3) Add a CHECK constraint with NOT VALID (fast, no table scan), (4) VALIDATE CONSTRAINT in a separate transaction (takes ShareUpdateExclusiveLock, which doesn't block reads or writes).

**Q: Why use CREATE INDEX CONCURRENTLY instead of CREATE INDEX?**
A: Regular `CREATE INDEX` holds an exclusive lock on the table for the duration of the index build — blocking all reads and writes. On a large table this can take minutes or hours. `CREATE INDEX CONCURRENTLY` builds the index in the background, allowing reads and writes throughout. It takes about twice as long but never blocks. Always use CONCURRENTLY for index creation in production. The only downside: if it fails, it leaves an invalid index that must be dropped manually.
