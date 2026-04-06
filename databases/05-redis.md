# Redis — Data Structures, Persistence, Replication, Cluster, Use Cases

## What Is Redis?

Redis (Remote Dictionary Server) is an in-memory data structure store used as a database, cache, message broker, and queue. It is:
- Extremely fast — microsecond read/write latency (data lives in RAM)
- Single-threaded for commands (no locking, predictable performance)
- Persistent (optional — RDB snapshots or AOF log)
- Highly available (Sentinel for HA, Cluster for horizontal scale)

```
Redis vs traditional databases:
  Traditional DB: data on disk, read into memory on access → millisecond latency
  Redis:          data in memory, persisted to disk optionally → microsecond latency

Redis vs Memcached:
  Memcached: pure cache, strings only, no persistence, simple
  Redis:     rich data structures, persistence, replication, Lua scripting, pub/sub
  → Always prefer Redis over Memcached for new deployments
```

---

## Redis Data Structures

Redis is not just a key-value store — it supports rich data structures, each with specific commands and use cases.

### String

The simplest type. Can store text, integers, or binary data (up to 512MB).

```bash
# Basic operations
SET user:1:name "Alice"
GET user:1:name           # "Alice"
DEL user:1:name

# With expiry (TTL)
SET session:abc123 "user_data" EX 3600    # Expires in 3600 seconds
SET session:abc123 "user_data" PX 3600000 # Expires in 3600000 milliseconds
TTL session:abc123                         # Remaining TTL in seconds
PERSIST session:abc123                     # Remove expiry

# Atomic integer operations (no race conditions)
SET page:views 0
INCR page:views           # 1 (atomic increment)
INCRBY page:views 5       # 6
DECR page:views           # 5
GETSET page:views 0       # Returns old value (5), sets to 0

# NX / XX flags
SET lock:resource "owner" NX EX 30   # Set ONLY if not exists (distributed lock)
SET config:value "new" XX            # Set ONLY if exists
```

### Hash

A map of field-value pairs. Perfect for storing objects.

```bash
# Store a user object
HSET user:1 name "Alice" email "alice@example.com" age 30
HGET user:1 name                     # "Alice"
HMGET user:1 name email              # ["Alice", "alice@example.com"]
HGETALL user:1                       # All fields and values
HKEYS user:1                         # ["name", "email", "age"]
HVALS user:1                         # ["Alice", "alice@example.com", "30"]
HEXISTS user:1 email                 # 1 (exists)
HDEL user:1 age                      # Remove field
HINCRBY user:1 login_count 1         # Atomic increment on hash field

# Memory efficient: hashes with <= 128 fields use ziplist encoding
# Store small objects as hashes, not as individual string keys
```

### List

An ordered linked list. Can be used as a stack (LIFO) or queue (FIFO).

```bash
# Queue (FIFO) — task queue pattern
RPUSH queue:emails "task1" "task2" "task3"  # Push to right
LPOP queue:emails                            # Pop from left → "task1"

# Stack (LIFO)
LPUSH stack:undo "action1"
LPOP stack:undo                              # "action1"

# Blocking pop (wait until item available — consumer pattern)
BLPOP queue:emails 30                        # Block up to 30 seconds waiting for item

# List operations
LLEN queue:emails                            # Length
LRANGE queue:emails 0 -1                     # All elements
LINDEX queue:emails 0                        # First element (no pop)
LINSERT queue:emails BEFORE "task2" "task1b"

# Trim to keep only recent N items
RPUSH recent:events "event1"
LTRIM recent:events 0 99                     # Keep only last 100 events
```

### Set

An unordered collection of unique strings. Perfect for tags, memberships, unique visitors.

```bash
SADD tags:post:1 "redis" "database" "nosql"
SMEMBERS tags:post:1              # {"redis", "database", "nosql"}
SISMEMBER tags:post:1 "redis"    # 1 (is member)
SCARD tags:post:1                # 3 (cardinality)
SREM tags:post:1 "nosql"         # Remove member

# Set operations (very powerful)
SADD user:1:friends 2 3 4 5
SADD user:2:friends 3 4 6 7
SINTER user:1:friends user:2:friends   # {3, 4} — mutual friends
SUNION user:1:friends user:2:friends   # {2, 3, 4, 5, 6, 7}
SDIFF user:1:friends user:2:friends    # {2, 5} — user1's friends not shared with user2

# Random member (useful for sampling)
SRANDMEMBER tags:post:1           # Random tag
SPOP tags:post:1                  # Remove and return random member
```

### Sorted Set (ZSet)

Like a set, but each member has a score. Members are ordered by score. Perfect for leaderboards, rate limiting, priority queues.

```bash
# Leaderboard
ZADD leaderboard 1500 "alice" 2300 "bob" 800 "charlie"
ZRANGE leaderboard 0 -1 WITHSCORES    # All members, lowest score first
ZREVRANGE leaderboard 0 2 WITHSCORES  # Top 3 (highest scores)
ZSCORE leaderboard "bob"              # 2300
ZRANK leaderboard "alice"             # Rank from lowest (0-indexed)
ZREVRANK leaderboard "bob"            # Rank from highest
ZINCRBY leaderboard 100 "alice"       # alice now has 1600
ZRANGEBYSCORE leaderboard 1000 2000   # Members with score 1000-2000

# Rate limiting with sorted sets
# Add request with timestamp as score
ZADD rate:user:1 1731234567 "req1"
# Remove old requests (outside window)
ZREMRANGEBYSCORE rate:user:1 0 (now - window)
# Count requests in window
ZCARD rate:user:1
```

### Stream

Append-only log of messages. Like Kafka but simpler. For event sourcing, activity feeds.

```bash
# Produce events
XADD events:orders * order_id 123 user_id 1 amount 99.99
# * = auto-generated ID (timestamp-sequence: 1731234567890-0)

# Read events
XRANGE events:orders - +           # All events
XRANGE events:orders - + COUNT 10  # First 10 events

# Consumer groups (for parallel processing)
XGROUP CREATE events:orders checkout-consumers $ MKSTREAM
XREADGROUP GROUP checkout-consumers worker1 COUNT 10 STREAMS events:orders >
# > = undelivered messages only
XACK events:orders checkout-consumers 1731234567890-0  # Acknowledge processed
```

---

## Redis Persistence

Redis offers two persistence mechanisms that can be used independently or together.

### RDB (Redis Database) — Snapshots

RDB creates point-in-time snapshots of the dataset at configured intervals.

```
How it works:
  Redis forks the process → child writes snapshot to disk → parent continues serving requests
  Snapshot is a compact binary file (redis.rdb)

Pros:
  - Single compact file — easy to backup and restore
  - Fast restarts (load RDB on startup)
  - Minimal impact on Redis performance (fork-based)

Cons:
  - Data loss between snapshots (e.g. last 5 minutes if Redis crashes)
  - Fork can be slow on large datasets with limited memory
```

```bash
# redis.conf — RDB configuration
save 3600 1     # Save if at least 1 key changed in 3600 seconds
save 300 100    # Save if at least 100 keys changed in 300 seconds
save 60 10000   # Save if at least 10000 keys changed in 60 seconds

rdbcompression yes    # Compress RDB file (LZF)
rdbfilename dump.rdb
dir /var/lib/redis    # RDB file location

# Manual snapshot
redis-cli BGSAVE       # Background save (async)
redis-cli LASTSAVE     # Timestamp of last successful save
```

### AOF (Append-Only File) — Write Log

AOF logs every write command. On restart, Redis replays the log to rebuild state.

```
How it works:
  Every write command appended to AOF file
  On restart: replay all commands to reconstruct dataset

Pros:
  - Much more durable than RDB (fsync every second = max 1 second data loss)
  - Human-readable (text format of Redis commands)
  - Corruption-safe (truncated AOF can be repaired with redis-check-aof)

Cons:
  - Larger file than RDB
  - Slower restarts (must replay all commands)
  - AOF rewrite needed periodically (compacts redundant commands)
```

```bash
# redis.conf — AOF configuration
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec    # fsync every second (recommended)
                        # always: fsync every write (safest, slowest)
                        # no: let OS decide (fastest, least safe)

# AOF rewrite (compact the log — removes redundant commands)
auto-aof-rewrite-percentage 100   # Rewrite when AOF is 100% larger than last rewrite
auto-aof-rewrite-min-size 64mb    # Don't rewrite unless AOF is at least 64MB

# Manual rewrite
redis-cli BGREWRITEAOF
```

### RDB + AOF (Recommended for Production)

```bash
# Use both for best durability + fast restart:
save 3600 1
save 300 100
save 60 10000
appendonly yes
appendfsync everysec

# On restart: Redis uses AOF (more complete) if both exist
# RDB provides fast backup, AOF provides durability
```

---

## Replication

Redis uses primary-replica (formerly master-slave) replication.

```bash
# redis.conf on replica
replicaof primary.internal 6379
replica-read-only yes              # Replicas reject writes
replica-serve-stale-data yes       # Serve stale data if disconnected from primary

# Check replication status
redis-cli INFO replication
# role: master/slave, connected_slaves, master_replid, master_repl_offset
# slave0: ip=10.0.1.2,port=6379,state=online,offset=12345,lag=0

# Promote replica to primary (for manual failover)
redis-cli REPLICAOF NO ONE
```

---

## Redis Sentinel — High Availability

Sentinel monitors Redis instances and performs automatic failover.

```
┌─────────────────────────────────────────────────────────────┐
│                    Redis Sentinel Setup                      │
│                                                             │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐             │
│  │Sentinel 1│    │Sentinel 2│    │Sentinel 3│             │
│  └────┬─────┘    └────┬─────┘    └────┬─────┘             │
│       │               │               │                     │
│       └───────────────┼───────────────┘                     │
│                       ↓ monitors                            │
│               ┌───────────────┐                             │
│               │    Primary    │ → replica1, replica2        │
│               └───────────────┘                             │
│                                                             │
│  When primary fails: sentinels vote → promote best replica  │
│  Clients connect to sentinel: "give me current primary addr"│
└─────────────────────────────────────────────────────────────┘
```

```bash
# sentinel.conf
sentinel monitor myredis primary.internal 6379 2  # 2 = quorum (votes needed for failover)
sentinel down-after-milliseconds myredis 5000      # Mark down after 5s no response
sentinel failover-timeout myredis 60000            # Failover timeout 60s
sentinel parallel-syncs myredis 1                  # 1 replica syncs at a time during failover

# Start sentinel
redis-sentinel /etc/redis/sentinel.conf
# or
redis-server /etc/redis/sentinel.conf --sentinel

# Query sentinel
redis-cli -p 26379 SENTINEL masters          # Current primary info
redis-cli -p 26379 SENTINEL slaves myredis   # Replica info
redis-cli -p 26379 SENTINEL get-master-addr-by-name myredis  # Current primary host:port
```

---

## Redis Cluster — Horizontal Scaling

Redis Cluster shards data across multiple primary nodes (each with replicas).

```
3-primary cluster:
  Primary 1 → slots 0-5460     (1/3 of keyspace)
  Primary 2 → slots 5461-10922 (1/3 of keyspace)
  Primary 3 → slots 10923-16383(1/3 of keyspace)

  Each primary has replicas for HA
  Total: 6 nodes minimum (3 primaries + 3 replicas)

Key routing:
  Redis hashes the key → determines slot → routes to correct shard
  Client libraries handle routing transparently (with CLUSTER MOVED redirects)
```

```bash
# Create Redis Cluster
redis-cli --cluster create \
  10.0.1.1:7000 10.0.1.2:7000 10.0.1.3:7000 \   # Primaries
  10.0.1.1:7001 10.0.1.2:7001 10.0.1.3:7001 \   # Replicas
  --cluster-replicas 1                             # 1 replica per primary

# Cluster configuration (redis.conf)
cluster-enabled yes
cluster-config-file nodes.conf
cluster-node-timeout 5000              # 5 seconds before node considered down
cluster-require-full-coverage yes      # Reject commands if any slots uncovered

# Cluster management
redis-cli --cluster info localhost:7000           # Cluster overview
redis-cli --cluster check localhost:7000          # Check cluster health
redis-cli --cluster rebalance localhost:7000      # Rebalance slots

# Hash tags — force keys to same slot (needed for multi-key operations)
SET {user:1}:name "Alice"
SET {user:1}:email "alice@example.com"
# Both keys hash to the slot of "user:1"
```

---

## Common Redis Use Cases

### 1. Caching (Most Common)

```bash
# Cache-aside pattern:
# 1. Check cache
GET product:123
# If miss:
# 2. Fetch from database
# 3. Store in cache with TTL
SET product:123 '{"id":123,"name":"Widget","price":9.99}' EX 3600
```

### 2. Session Storage

```bash
SET session:abc123 '{"user_id":1,"role":"admin"}' EX 86400  # 24-hour session
GET session:abc123
DEL session:abc123  # Logout
```

### 3. Distributed Locking (Redlock)

```bash
# Simple lock (single Redis node)
SET lock:order:123 "worker-1" NX EX 30    # Acquire lock, expires in 30s
# Returns OK if acquired, nil if already locked
DEL lock:order:123                         # Release lock

# For production: use Redlock algorithm (multiple Redis nodes)
# Libraries: redis-py (Python), ioredis (Node.js), Redisson (Java)
```

### 4. Rate Limiting

```bash
# Sliding window rate limiting
# Count requests in last 60 seconds
MULTI
  ZADD rate:user:1 {current_time} {request_id}
  ZREMRANGEBYSCORE rate:user:1 0 {current_time - 60}
  ZCARD rate:user:1
EXEC
# If ZCARD > limit → reject request
```

### 5. Pub/Sub (Event Broadcasting)

```bash
# Subscriber
SUBSCRIBE notifications:user:1

# Publisher
PUBLISH notifications:user:1 '{"type":"order_shipped","order_id":123}'

# Pattern subscribe
PSUBSCRIBE notifications:*   # All notification channels
```

---

## Redis Configuration Best Practices

```bash
# redis.conf — production essentials
bind 127.0.0.1 10.0.1.1    # Bind to specific interfaces only (not 0.0.0.0)
requirepass "strong_password"  # Authentication
rename-command FLUSHALL ""  # Disable dangerous commands
rename-command FLUSHDB ""
rename-command DEBUG ""
rename-command CONFIG ""    # Or restrict to admin only

maxmemory 4gb               # Maximum memory limit
maxmemory-policy allkeys-lru  # Evict least recently used keys when full
                               # Other policies:
                               # volatile-lru: evict keys with TTL set, LRU
                               # allkeys-lru: evict any key, LRU (for cache use case)
                               # noeviction: return error when full (for queue use case)

hz 10                       # Background task frequency (increase for faster expiry)
latency-tracking yes        # Enable latency monitoring
slowlog-log-slower-than 10000  # Log commands > 10ms (in microseconds)
slowlog-max-len 128
```

---

## Interview Questions — Redis

**Q: What is the difference between Redis RDB and AOF persistence, and which should you use?**
A: RDB creates periodic point-in-time snapshots — compact, fast to restore, but you lose data since the last snapshot. AOF logs every write command — more durable (max 1 second loss with `appendfsync everysec`), but larger files and slower restarts. For production, use both: RDB for fast restarts and easy backups, AOF for durability. If Redis crashes, it uses AOF to rebuild state (more complete than RDB).

**Q: What is the difference between Redis Sentinel and Redis Cluster?**
A: Sentinel provides high availability for a single Redis dataset — it monitors primary/replicas and performs automatic failover when the primary fails. The dataset fits on one node. Cluster provides both high availability AND horizontal scaling — it shards data across multiple primaries (each with replicas), allowing datasets larger than one node's memory. Use Sentinel when your data fits on one node but you need HA. Use Cluster when you need to scale beyond one node's capacity.

**Q: What is the LRU eviction policy in Redis and when would you use it?**
A: LRU (Least Recently Used) evicts keys that haven't been accessed recently when Redis reaches its `maxmemory` limit. `allkeys-lru` evicts any key, making Redis behave like a pure cache — it always accepts new writes by evicting old data. `volatile-lru` only evicts keys that have a TTL set. Use `allkeys-lru` when Redis is a cache and you're comfortable with data being evicted. Use `noeviction` when Redis stores data you can't lose (queues, session store where loss is not acceptable) — Redis returns an error rather than silently evicting data.
