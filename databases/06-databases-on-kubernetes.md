# Databases on Kubernetes — StatefulSets, PVCs, Storage Classes, Operators

## Should You Run Databases on Kubernetes?

This is one of the most debated topics in the cloud-native space. The honest answer:

```
Run on Kubernetes when:
  ✅ You have experienced K8s operators available (CloudNativePG, MongoDB Operator)
  ✅ Development/staging environments (simplifies parity with production)
  ✅ Smaller-scale deployments where managed services are too expensive
  ✅ You need tight integration with K8s ecosystem (GitOps, secrets, monitoring)
  ✅ Your team has K8s expertise but limited DBA resources

Use managed services (Azure SQL, RDS, Atlas) when:
  ✅ Production databases for business-critical workloads
  ✅ You need guaranteed SLAs and automated failover
  ✅ Your team lacks deep database + Kubernetes expertise
  ✅ Compliance requires managed service guarantees
  ✅ You want to avoid the operational overhead

Reality: Many teams run databases on Kubernetes in production successfully,
but it requires significant expertise in both K8s and the specific database.
```

---

## StatefulSets — The Foundation

StatefulSets are the Kubernetes workload controller designed for stateful applications. Unlike Deployments, they provide:

```
┌────────────────────────────────────────────────────────────┐
│           StatefulSet vs Deployment                         │
│                                                            │
│  Deployment:                  StatefulSet:                 │
│  ─────────────────────────    ──────────────────────────── │
│  Pod names: random hash       Pod names: stable (pod-0,1,2)│
│  Network identity: changes    Network identity: stable     │
│  Storage: ephemeral           Storage: persistent (PVC)    │
│  Scale up: all at once        Scale up: ordered (0,1,2...) │
│  Scale down: random           Scale down: reverse (2,1,0..)│
│  Rolling update: random       Rolling update: ordered      │
│  Use for: stateless apps      Use for: databases, queues   │
└────────────────────────────────────────────────────────────┘
```

### StatefulSet Properties

**Stable network identity:**
Each pod gets a predictable DNS name:
```
<pod-name>.<service-name>.<namespace>.svc.cluster.local

Example for postgres StatefulSet:
  postgres-0.postgres-headless.databases.svc.cluster.local
  postgres-1.postgres-headless.databases.svc.cluster.local
  postgres-2.postgres-headless.databases.svc.cluster.local
```

**Ordered deployment and scaling:**
- Pods start in order: 0 → 1 → 2
- Each pod must be Running and Ready before the next starts
- Pods delete in reverse order: 2 → 1 → 0
- Ensures primary (pod-0) is always started first

**Persistent storage per pod:**
Each pod gets its own PersistentVolumeClaim — pod-0 always gets the same PVC even after rescheduling.

---

## StatefulSet YAML — PostgreSQL Example

```yaml
apiVersion: v1
kind: Service
metadata:
  name: postgres-headless    # Headless service for stable DNS
  namespace: databases
spec:
  clusterIP: None            # Headless — no load balancing, direct pod DNS
  selector:
    app: postgres
  ports:
    - port: 5432
      name: postgres

---
apiVersion: v1
kind: Service
metadata:
  name: postgres             # Regular service for client connections
  namespace: databases
spec:
  selector:
    app: postgres
    role: primary            # Only route to primary pod
  ports:
    - port: 5432

---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
  namespace: databases
spec:
  serviceName: postgres-headless   # Must match headless service name
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      terminationGracePeriodSeconds: 60  # Give PostgreSQL time to shut down cleanly
      securityContext:
        fsGroup: 999                     # PostgreSQL GID

      initContainers:
        - name: init-permissions
          image: busybox
          command: ["sh", "-c", "chown -R 999:999 /var/lib/postgresql/data"]
          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data

      containers:
        - name: postgres
          image: postgres:16
          ports:
            - containerPort: 5432
          env:
            - name: POSTGRES_DB
              value: checkout
            - name: POSTGRES_USER
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: username
            - name: POSTGRES_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: postgres-secret
                  key: password
            - name: PGDATA
              value: /var/lib/postgresql/data/pgdata

          resources:
            requests:
              memory: "2Gi"
              cpu: "500m"
            limits:
              memory: "4Gi"
              cpu: "2000m"

          livenessProbe:
            exec:
              command: ["pg_isready", "-U", "postgres"]
            initialDelaySeconds: 30
            periodSeconds: 10
            failureThreshold: 3

          readinessProbe:
            exec:
              command: ["pg_isready", "-U", "postgres"]
            initialDelaySeconds: 5
            periodSeconds: 5

          volumeMounts:
            - name: postgres-data
              mountPath: /var/lib/postgresql/data
            - name: postgres-config
              mountPath: /etc/postgresql/postgresql.conf
              subPath: postgresql.conf

      volumes:
        - name: postgres-config
          configMap:
            name: postgres-config

  volumeClaimTemplates:          # One PVC per pod — this is the key StatefulSet feature
    - metadata:
        name: postgres-data
      spec:
        accessModes: ["ReadWriteOnce"]   # Only one pod can mount read-write
        storageClassName: managed-premium # Azure Premium SSD
        resources:
          requests:
            storage: 100Gi
```

---

## PersistentVolumes and Storage Classes

### Storage Class Selection — Critical for Database Performance

```yaml
# Azure Premium SSD (recommended for production databases)
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: managed-premium-retain
provisioner: disk.csi.azure.com
parameters:
  skuName: Premium_LRS          # Premium SSD — ~3000 IOPS/disk
  kind: managed
  cachingMode: ReadOnly         # Read caching ON, write caching OFF (durability)
reclaimPolicy: Retain           # RETAIN: don't delete PV when PVC deleted
                                 # (CRITICAL for databases — default is Delete!)
allowVolumeExpansion: true       # Allow resizing without recreation
volumeBindingMode: WaitForFirstConsumer  # Create disk in same AZ as pod
```

### Storage Class Options for AKS

```
managed-csi:          Azure Standard SSD — dev/test
managed-premium:      Azure Premium SSD — production workloads
managed-ultrassd:     Azure Ultra Disk — extremely low latency (<1ms)
azurefile-csi:        Azure File Share — ReadWriteMany (shared across pods)

For databases:
  Production:    managed-premium (3000 IOPS, 125 MB/s)
  High I/O:      managed-ultrassd (up to 160,000 IOPS)
  Shared:        azurefile-csi (ReadWriteMany — but poor random I/O for databases)
```

### Reclaim Policy — Critical for Data Safety

```yaml
# ALWAYS use Retain for database PVCs
# Default Delete will destroy your data when the PVC is deleted!

# If you accidentally delete a PVC with Retain policy:
# 1. The PV status becomes "Released" but data is safe
# 2. Manually patch the PV to reclaim:
kubectl patch pv <pv-name> -p '{"spec":{"claimRef":null}}'
# 3. Recreate the PVC referencing the PV
```

### Resizing a PVC

```bash
# Resize a PVC (storage class must have allowVolumeExpansion: true)
kubectl patch pvc postgres-data-postgres-0 \
  -n databases \
  --type merge \
  -p '{"spec":{"resources":{"requests":{"storage":"200Gi"}}}}'

# Check resize status
kubectl describe pvc postgres-data-postgres-0 -n databases
# Conditions will show: FileSystemResizePending, then success
```

---

## Database Operators

Operators are the correct way to run databases on Kubernetes. They encode operational knowledge (initialization, replication, failover, backup) as a Kubernetes controller.

```
Without operator:
  You manually configure replication, handle failover, manage backups
  Complex, error-prone, requires deep database + K8s knowledge

With operator:
  Declare desired state (e.g. "3 postgres replicas with backup to S3")
  Operator handles: initialization, replication setup, failover, backup, monitoring
  Much safer and more maintainable
```

### CloudNativePG (PostgreSQL) — Recommended

CloudNativePG is the CNCF-graduated operator for PostgreSQL. It is the recommended way to run PostgreSQL on Kubernetes.

```yaml
# Install CloudNativePG
kubectl apply -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml

---
# Cluster definition — replaces all the StatefulSet YAML above
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: checkout-postgres
  namespace: databases
spec:
  instances: 3                    # 1 primary + 2 replicas (auto-configured)
  primaryUpdateStrategy: unsupervised  # Auto-update primary during rolling updates

  postgresql:
    parameters:
      shared_buffers: "1GB"
      max_connections: "200"
      work_mem: "4MB"
      log_min_duration_statement: "1000"

  bootstrap:
    initdb:
      database: checkout
      owner: checkout_user
      secret:
        name: checkout-postgres-secret

  storage:
    size: 100Gi
    storageClass: managed-premium-retain

  resources:
    requests:
      memory: "2Gi"
      cpu: "500m"
    limits:
      memory: "4Gi"
      cpu: "2000m"

  monitoring:
    enablePodMonitor: true        # Integrates with Prometheus operator

  backup:
    retentionPolicy: "30d"        # Keep backups for 30 days
    barmanObjectStore:
      destinationPath: "https://myaccount.blob.core.windows.net/postgres-backups"
      azureCredentials:
        storageAccount:
          name: azure-storage-secret
          key: storage-account
        storageKey:
          name: azure-storage-secret
          key: storage-key

  # Scheduled backups
---
apiVersion: postgresql.cnpg.io/v1
kind: ScheduledBackup
metadata:
  name: checkout-postgres-backup
  namespace: databases
spec:
  schedule: "0 2 * * *"          # Daily at 2am
  cluster:
    name: checkout-postgres
  backupOwnerReference: self
```

```bash
# CloudNativePG kubectl plugin
kubectl cnpg status checkout-postgres -n databases
# Shows: primary, replicas, replication lag, backup status

kubectl cnpg promote checkout-postgres-2 -n databases
# Manually promote replica to primary

kubectl cnpg backup checkout-postgres -n databases
# Trigger immediate backup
```

### MongoDB Kubernetes Operator

```yaml
# Install MongoDB Community Operator
kubectl apply -f https://raw.githubusercontent.com/mongodb/mongodb-kubernetes-operator/master/config/crd/bases/mongodbcommunity.mongodb.com_mongodbcommunity.yaml

---
apiVersion: mongodbcommunity.mongodb.com/v1
kind: MongoDBCommunity
metadata:
  name: checkout-mongodb
  namespace: databases
spec:
  members: 3                     # 1 primary + 2 secondaries
  type: ReplicaSet
  version: "7.0.4"

  security:
    authentication:
      modes: ["SCRAM"]

  users:
    - name: checkout_app
      db: checkout
      passwordSecretRef:
        name: checkout-mongodb-password
      roles:
        - name: readWrite
          db: checkout

  statefulSet:
    spec:
      volumeClaimTemplates:
        - metadata:
            name: data-volume
          spec:
            accessModes: ["ReadWriteOnce"]
            storageClassName: managed-premium-retain
            resources:
              requests:
                storage: 100Gi
```

### Redis Operator (Redis Operator by OT-CONTAINER-KIT)

```yaml
# Redis Cluster via operator
apiVersion: redis.redis.opstreelabs.in/v1beta2
kind: RedisCluster
metadata:
  name: checkout-redis
  namespace: databases
spec:
  clusterSize: 3                 # 3 primaries
  clusterVersion: v7
  persistenceEnabled: true
  redisLeader:
    replicas: 3                  # 3 replicas (one per primary)
  storage:
    volumeClaimTemplate:
      spec:
        storageClassName: managed-premium-retain
        accessModes: ["ReadWriteOnce"]
        resources:
          requests:
            storage: 10Gi
  redisConfig:
    maxmemory: "2gb"
    maxmemory-policy: "allkeys-lru"
```

---

## Pod Disruption Budgets for Databases

Always set PDBs to prevent accidental simultaneous eviction of all database pods:

```yaml
# PostgreSQL PDB — always keep primary + at least 1 replica
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: postgres-pdb
  namespace: databases
spec:
  minAvailable: 2               # Keep at least 2 of 3 pods available
  selector:
    matchLabels:
      app: checkout-postgres    # Match CloudNativePG labels

---
# MongoDB PDB
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: mongodb-pdb
  namespace: databases
spec:
  minAvailable: 2               # Keep quorum (2 of 3 for replica set election)
  selector:
    matchLabels:
      app: checkout-mongodb
```

---

## Backup for Databases on Kubernetes

### Velero — Kubernetes-Native Backup

Velero backs up Kubernetes resources AND PersistentVolume data:

```bash
# Install Velero with Azure Blob storage
velero install \
  --provider azure \
  --plugins velero/velero-plugin-for-microsoft-azure:v1.8.0 \
  --bucket velero-backups \
  --secret-file ./credentials-velero \
  --backup-location-config \
    resourceGroup=myRG,storageAccount=myaccount,subscriptionId=xxxxx \
  --snapshot-location-config \
    apiTimeout=15m,resourceGroup=myRG,subscriptionId=xxxxx

# Backup entire namespace (resources + PVC snapshots)
velero backup create databases-backup \
  --include-namespaces databases \
  --snapshot-volumes=true \
  --wait

# Schedule daily backup
velero schedule create databases-daily \
  --schedule="0 1 * * *" \
  --include-namespaces databases \
  --snapshot-volumes=true \
  --ttl 720h                  # Keep for 30 days

# Restore from backup
velero restore create --from-backup databases-backup

# Check backup status
velero backup describe databases-backup --details
```

---

## Common Pitfalls Running Databases on Kubernetes

```
1. Using default storage class (usually Delete reclaim policy)
   → Fix: Create storage class with Retain policy for all database PVCs

2. Not setting resource limits
   → Noisy neighbor: other pods consume memory, database gets OOMKilled
   → Fix: Always set requests=limits for database pods (Guaranteed QoS)

3. Not setting PodDisruptionBudgets
   → Node drain evicts all replica set members simultaneously → data unavailable
   → Fix: PDB with minAvailable = majority of members

4. Backing up at Kubernetes level only (not database level)
   → PVC snapshot may capture inconsistent state mid-transaction
   → Fix: Use database-native backup (pg_dump, mongodump) + Velero PVC snapshots

5. Not testing failover
   → First time you discover failover doesn't work is during a real incident
   → Fix: Chaos engineering — kill the primary pod regularly in staging

6. Running without an operator
   → Manual replication setup, no automated failover, painful upgrades
   → Fix: Use CloudNativePG, MongoDB Operator, or managed service
```

---

## Interview Questions — Databases on Kubernetes

**Q: What is a StatefulSet and how does it differ from a Deployment?**
A: A StatefulSet provides three guarantees that Deployments don't: stable pod names (postgres-0, postgres-1 — not random hashes), stable network identity via headless service DNS, and stable persistent storage (each pod gets its own PVC that follows it across rescheduling). Deployments treat all pods as interchangeable; StatefulSets treat each pod as unique. For databases, this means pod-0 is always the primary, always has the same DNS name, and always mounts the same data volume.

**Q: What storage class settings are important for production database PVCs?**
A: Three critical settings: `reclaimPolicy: Retain` (default Delete will destroy your data when the PVC is deleted), `allowVolumeExpansion: true` (allows growing the volume without recreation), and `volumeBindingMode: WaitForFirstConsumer` (creates the disk in the same availability zone as the pod — critical for AKS with multi-AZ clusters, otherwise you get cross-AZ disk attachment failures). For performance, use Premium SSD (`skuName: Premium_LRS`) for production databases.

**Q: Why use a database operator instead of a plain StatefulSet?**
A: A plain StatefulSet gives you stable pods with persistent storage but doesn't know anything about the database. You must manually configure replication, handle failover, manage backups, and handle upgrades. An operator encodes all that operational knowledge. CloudNativePG, for example, automatically sets up primary/replica replication, performs automatic failover when the primary fails, integrates backup to object storage, handles rolling upgrades, and exposes Prometheus metrics — all from a single YAML declaration.
