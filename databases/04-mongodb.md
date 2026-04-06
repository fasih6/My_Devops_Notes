# MongoDB — Document Model, Replica Sets, Sharding, Indexes, Operations

## What Is MongoDB?

MongoDB is the leading document-oriented NoSQL database. Instead of rows in tables, it stores JSON-like documents (BSON) in collections.

```
Relational (PostgreSQL/MySQL):        MongoDB:
─────────────────────────────────    ──────────────────────────────────
Database                              Database
  └── Table                             └── Collection
        └── Row (fixed schema)                └── Document (flexible schema)
              └── Column                             └── Field

SQL:                                  MongoDB query:
SELECT * FROM orders                  db.orders.find(
WHERE user_id = 1                       { user_id: 1,
  AND status = 'pending'                  status: "pending" }
ORDER BY created_at DESC;             ).sort({ created_at: -1 })
LIMIT 10;                             .limit(10)
```

---

## When to Use MongoDB

```
USE MONGODB when:
  ✅ Schema changes frequently (evolving data models)
  ✅ Documents naturally fit the data (embedded objects, arrays)
  ✅ Horizontal scaling is required (sharding)
  ✅ High write throughput needed
  ✅ Hierarchical / nested data (e.g. product catalogs with variable attributes)
  ✅ Real-time analytics on operational data

DON'T USE MONGODB when:
  ❌ Complex multi-table joins are required
  ❌ Strong ACID transactions across many documents are needed
  ❌ Data is naturally relational and well-defined
  ❌ Team is more comfortable with SQL
  ❌ Compliance requires proven SQL tooling
```

---

## MongoDB Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    MongoDB Replica Set                       │
│                                                             │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐  │
│  │   PRIMARY    │    │  SECONDARY   │    │  SECONDARY   │  │
│  │              │    │              │    │              │  │
│  │  Reads+Writes│    │  Reads only  │    │  Reads only  │  │
│  │              │→→→→│  (replication│→→→→│  (replication│  │
│  │              │    │   from oplog)│    │   from oplog)│  │
│  └──────────────┘    └──────────────┘    └──────────────┘  │
│         │                                                   │
│         ↓                                                   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │              Oplog (Operations Log)                   │  │
│  │  Capped collection recording all write operations     │  │
│  │  Secondaries tail the oplog to replicate changes      │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
```

### Key Components

**Oplog:** MongoDB's equivalent of WAL/binlog. A capped collection in the `local` database recording all write operations. Secondaries continuously tail the oplog of the primary to replicate changes.

**WiredTiger:** Default storage engine since MongoDB 3.2. Document-level locking, compression (snappy/zlib), MVCC, journal for crash recovery.

**mongod:** The primary daemon process (database server).

**mongos:** Query router for sharded clusters — routes queries to the correct shard.

**Config servers:** Store cluster metadata for sharded clusters.

---

## Replica Sets

A replica set is MongoDB's primary high availability mechanism — a group of mongod instances that maintain the same data.

### Replica Set Configuration

```javascript
// Initialize replica set (run on one node)
rs.initiate({
  _id: "rs0",
  members: [
    { _id: 0, host: "mongo1.internal:27017", priority: 2 },  // Higher priority = preferred primary
    { _id: 1, host: "mongo2.internal:27017", priority: 1 },
    { _id: 2, host: "mongo3.internal:27017", priority: 1 }
  ]
})

// Check replica set status
rs.status()
// Shows: primary, secondaries, oplog lag, health

// Check replication lag
rs.printReplicationInfo()         // Oplog size and time coverage
rs.printSecondaryReplicationInfo() // Lag per secondary

// Add a new member
rs.add("mongo4.internal:27017")

// Remove a member
rs.remove("mongo4.internal:27017")

// Step down primary (for maintenance)
rs.stepDown(60)  // Step down for 60 seconds, forces new election
```

### mongod.conf for Replica Set Member

```yaml
# mongod.conf
storage:
  dbPath: /var/lib/mongodb
  journal:
    enabled: true
  wiredTiger:
    engineConfig:
      cacheSizeGB: 4          # WiredTiger cache = 50% of RAM by default
      journalCompressor: snappy
    collectionConfig:
      blockCompressor: snappy

systemLog:
  destination: file
  path: /var/log/mongodb/mongod.log
  logAppend: true

net:
  port: 27017
  bindIp: 0.0.0.0
  tls:
    mode: requireTLS
    certificateKeyFile: /etc/ssl/mongo.pem
    CAFile: /etc/ssl/ca.pem

replication:
  replSetName: "rs0"
  oplogSizeMB: 10240         # 10GB oplog — larger = more recovery window

security:
  authorization: enabled
  keyFile: /etc/mongodb/keyfile   # Shared key for intra-cluster auth

operationProfiling:
  slowOpThresholdMs: 100          # Log operations > 100ms
  mode: slowOp
```

### Read Preferences

MongoDB allows routing reads to secondaries:

```javascript
// Read from primary only (default, strongest consistency)
db.collection.find({}).readPref("primary")

// Read from nearest member (lowest latency)
db.collection.find({}).readPref("nearest")

// Read from secondary (offload reads, slight staleness)
db.collection.find({}).readPref("secondary")

// Read from secondary if available, otherwise primary
db.collection.find({}).readPref("secondaryPreferred")

// Application-level read preference (in connection string)
mongodb://mongo1:27017,mongo2:27017,mongo3:27017/checkout?replicaSet=rs0&readPreference=secondaryPreferred
```

---

## Sharding — Horizontal Scaling

Sharding distributes data across multiple replica sets (shards) for horizontal scale beyond what one replica set can handle.

```
Without sharding:
  One replica set → max ~TB of data, limited write throughput

With sharding:
  Shard 1 (rs0): stores user_id 0-33%
  Shard 2 (rs1): stores user_id 33-66%
  Shard 3 (rs2): stores user_id 66-100%

  mongos routes: "Find user 12345" → shard 1
  mongos routes: "Find user 67890" → shard 3
```

### Shard Key Selection — Critical Decision

The shard key determines how data is distributed. A bad shard key causes:
- **Hotspots:** all writes going to one shard
- **Scatter-gather queries:** queries that must hit every shard

```javascript
// Bad shard key: monotonically increasing (e.g. ObjectId, timestamp)
// All new documents go to the last shard → hotspot

// Good shard key: high cardinality, even distribution, query-aligned
sh.shardCollection("checkout.orders", { user_id: "hashed" })  // Hashed = even distribution

// Compound shard key (range + hash)
sh.shardCollection("checkout.events", { user_id: 1, created_at: 1 })
// Good when: most queries filter by user_id (co-locates user data on one shard)
```

### Sharding Setup

```javascript
// On mongos router
// Enable sharding on database
sh.enableSharding("checkout")

// Shard a collection (choose shard key carefully)
sh.shardCollection("checkout.orders", { user_id: "hashed" })

// Check shard distribution
sh.status()                    // Overview of all shards and chunks
db.orders.getShardDistribution()  // Per-shard document count
```

---

## Indexes — Critical for Performance

```javascript
// Single field index
db.orders.createIndex({ user_id: 1 })         // Ascending
db.orders.createIndex({ created_at: -1 })     // Descending (good for sort)

// Compound index (field order matters!)
db.orders.createIndex({ user_id: 1, status: 1, created_at: -1 })
// Supports queries on: user_id, (user_id, status), (user_id, status, created_at)
// Does NOT support queries on: status alone, created_at alone

// Unique index
db.users.createIndex({ email: 1 }, { unique: true })

// Sparse index (only indexes documents where field exists)
db.users.createIndex({ phone: 1 }, { sparse: true })

// TTL index (auto-delete documents after N seconds)
db.sessions.createIndex({ created_at: 1 }, { expireAfterSeconds: 86400 })  // 24 hours

// Text index (for full-text search)
db.products.createIndex({ name: "text", description: "text" })
db.products.find({ $text: { $search: "wireless headphones" } })

// Partial index (only index documents matching a filter)
db.orders.createIndex(
  { created_at: 1 },
  { partialFilterExpression: { status: "pending" } }  // Only index pending orders
)

// Check index usage with explain
db.orders.find({ user_id: 123 }).explain("executionStats")
// Look for: IXSCAN (good) vs COLLSCAN (bad — full collection scan)

// List all indexes
db.orders.getIndexes()

// Drop an index
db.orders.dropIndex({ user_id: 1 })
```

---

## Aggregation Pipeline

MongoDB's aggregation pipeline processes documents through a series of stages:

```javascript
// Example: Revenue by product category, last 30 days
db.orders.aggregate([
  // Stage 1: Filter
  { $match: {
    created_at: { $gte: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000) },
    status: "completed"
  }},

  // Stage 2: Unwind array of items
  { $unwind: "$items" },

  // Stage 3: Join with products collection
  { $lookup: {
    from: "products",
    localField: "items.product_id",
    foreignField: "_id",
    as: "product"
  }},

  // Stage 4: Group by category
  { $group: {
    _id: "$product.category",
    total_revenue: { $sum: { $multiply: ["$items.quantity", "$items.price"] } },
    order_count: { $sum: 1 }
  }},

  // Stage 5: Sort by revenue
  { $sort: { total_revenue: -1 } },

  // Stage 6: Limit results
  { $limit: 10 }
])
```

---

## Backup Strategies

### mongodump — Logical Backup

```bash
# Backup entire cluster/replica set
mongodump \
  --uri="mongodb://backup_user:password@mongo1:27017,mongo2:27017,mongo3:27017/?replicaSet=rs0&readPreference=secondary" \
  --out=/backup/$(date +%Y%m%d_%H%M%S) \
  --gzip \
  --oplog              # Include oplog for point-in-time consistency

# Backup single database
mongodump \
  --uri="mongodb://..." \
  --db=checkout \
  --out=/backup/checkout_$(date +%Y%m%d) \
  --gzip

# Restore
mongorestore \
  --uri="mongodb://root:password@localhost:27017" \
  --gzip \
  --oplogReplay \      # Replay oplog for consistency
  /backup/20241115_143500

# Restore single collection
mongorestore \
  --uri="mongodb://..." \
  --db=checkout \
  --collection=orders \
  /backup/20241115_143500/checkout/orders.bson.gz
```

### Cloud Backup (MongoDB Atlas / Ops Manager)

For production, use continuous cloud backup:
- **MongoDB Atlas:** Built-in continuous backup with point-in-time recovery
- **Ops Manager / Cloud Manager:** Self-hosted MongoDB with backup management
- Both support: scheduled snapshots, oplog-based PITR, cross-region restore

```javascript
// Check oplog window (how far back you can restore)
use local
db.oplog.rs.stats().maxSize           // Max oplog size in bytes
db.oplog.rs.find().sort({$natural: 1}).limit(1)  // Oldest oplog entry timestamp
db.oplog.rs.find().sort({$natural:-1}).limit(1)  // Newest oplog entry timestamp
```

---

## Essential MongoDB Operations

```javascript
// User management
use admin
db.createUser({
  user: "checkout_app",
  pwd: "secure_password",
  roles: [{ role: "readWrite", db: "checkout" }]
})

db.createUser({
  user: "backup_user",
  pwd: "backup_password",
  roles: [
    { role: "backup", db: "admin" },
    { role: "clusterMonitor", db: "admin" }
  ]
})

// Check current operations
db.currentOp({ "active": true, "secs_running": { $gt: 10 } })

// Kill a long-running operation
db.killOp(opId)

// Check collection stats
db.orders.stats()
db.orders.totalSize()

// Compact a collection (reclaim space — takes collection offline)
db.runCommand({ compact: "orders" })

// Repair database (after unclean shutdown)
db.repairDatabase()

// Enable profiler (log slow queries)
db.setProfilingLevel(1, { slowms: 100 })   // Log ops > 100ms
db.system.profile.find().sort({ ts: -1 }).limit(10)  // View profiler output
```

---

## Connection String Reference

```
# Replica set connection string
mongodb://user:password@mongo1:27017,mongo2:27017,mongo3:27017/checkout?replicaSet=rs0

# With TLS
mongodb://user:password@mongo1:27017/checkout?replicaSet=rs0&tls=true&tlsCAFile=/etc/ssl/ca.pem

# With read preference (reads to secondaries)
mongodb://user:password@mongo1:27017,mongo2:27017,mongo3:27017/checkout?replicaSet=rs0&readPreference=secondaryPreferred

# Atlas connection string
mongodb+srv://user:password@cluster0.abc123.mongodb.net/checkout?retryWrites=true&w=majority
```

---

## Interview Questions — MongoDB

**Q: When would you choose MongoDB over PostgreSQL?**
A: MongoDB is better when the data model is flexible and evolves frequently (no ALTER TABLE needed), when documents are naturally hierarchical (embedded arrays and objects), when horizontal sharding is needed at scale, or when you're building event-driven systems with high write throughput. PostgreSQL is better for complex relationships requiring joins, strong ACID transactions across multiple entities, or when the team is more comfortable with SQL. For most new projects, evaluate the data model first — if it's naturally document-like, MongoDB; if it's naturally relational, PostgreSQL.

**Q: How does MongoDB replication work and how does it handle failover?**
A: MongoDB uses replica sets — typically 3+ nodes where one is primary and others are secondaries. Secondaries continuously tail the primary's oplog to replicate changes. If the primary becomes unavailable, the secondaries hold an election. The secondary with the most up-to-date oplog and highest priority wins. Clients using a MongoDB driver automatically discover the new primary via the replica set topology. The election typically completes in 10-30 seconds. Connections strings should include all replica set members so clients can find the new primary automatically.

**Q: What is a good shard key and what happens with a bad one?**
A: A good shard key has high cardinality (many distinct values), even distribution of writes, and aligns with common query patterns. A bad shard key — like a monotonically increasing ObjectId or timestamp — causes a hotspot: all new documents go to the last shard, creating an uneven write distribution. Use `{ field: "hashed" }` for even distribution when you don't need range queries on the shard key. For user-centric apps, sharding on user_id (hashed or range) is often a good choice because user data co-locates on the same shard.
