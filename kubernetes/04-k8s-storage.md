# 💾 Storage

PersistentVolumes, PersistentVolumeClaims, StorageClasses, and CSI drivers — how Kubernetes manages persistent data.

---

## 📚 Table of Contents

- [1. Storage Concepts](#1-storage-concepts)
- [2. Volumes](#2-volumes)
- [3. PersistentVolume (PV)](#3-persistentvolume-pv)
- [4. PersistentVolumeClaim (PVC)](#4-persistentvolumeclaim-pvc)
- [5. StorageClass & Dynamic Provisioning](#5-storageclass--dynamic-provisioning)
- [6. CSI Drivers](#6-csi-drivers)
- [7. Volume Snapshots](#7-volume-snapshots)
- [8. Storage in StatefulSets](#8-storage-in-statefulsets)
- [9. Storage Troubleshooting](#9-storage-troubleshooting)
- [Cheatsheet](#cheatsheet)

---

## 1. Storage Concepts

### The storage hierarchy

```
StorageClass     ← HOW to provision (e.g. AWS EBS gp3, NFS)
     │
     │  dynamic provisioning
     ▼
PersistentVolume ← WHAT storage exists (actual disk)
     │
     │  bound to
     ▼
PersistentVolumeClaim ← REQUEST for storage (from a pod)
     │
     │  mounted into
     ▼
   Pod/Container
```

### Access modes

| Mode | Short | Meaning | Typical use |
|------|-------|---------|------------|
| `ReadWriteOnce` | RWO | One node reads/writes | Most databases, EBS |
| `ReadOnlyMany` | ROX | Many nodes read | Shared read-only config |
| `ReadWriteMany` | RWX | Many nodes read/write | Shared storage, NFS |
| `ReadWriteOncePod` | RWOP | One pod reads/writes | Strict single-pod guarantee |

### Reclaim policies

| Policy | What happens when PVC is deleted |
|--------|----------------------------------|
| `Retain` | PV kept, data preserved, must manually reclaim |
| `Delete` | PV and underlying storage deleted automatically |
| `Recycle` | (deprecated) Basic scrub and make available again |

---

## 2. Volumes

Volumes are storage attached to a pod. Unlike containers, volumes survive container restarts within the same pod.

| Volume Type     | Description |
|-----------------|-------------|
| **emptyDir**    | Temporary storage that exists **only while the pod runs**. Cleared when pod is deleted. Shared among all containers in the pod. |
| **hostPath**    | Mount a file or directory from the **node's filesystem** into the pod. Useful for accessing host resources, but less portable. |

### emptyDir — ephemeral shared storage

```yaml
spec:
  containers:
    - name: app
      volumeMounts:
        - name: cache
          mountPath: /cache
    - name: sidecar
      volumeMounts:
        - name: cache
          mountPath: /shared-cache   # same volume, shared between containers

  volumes:
    - name: cache
      emptyDir: {}        # empty on pod start, deleted when pod dies
      # emptyDir:
      #   medium: Memory  # store in RAM (tmpfs) — faster, counts against memory limit
      #   sizeLimit: 500Mi
```

**Use for:** Temporary cache, shared data between containers in a pod, scratch space.

### hostPath — mount from node filesystem

```yaml
volumes:
  - name: host-logs
    hostPath:
      path: /var/log
      type: Directory    # Directory, File, DirectoryOrCreate, FileOrCreate, Socket
```

⚠️ **Security risk** — pod can access host filesystem. Only use for system-level pods (DaemonSets, monitoring agents).

### configMap and secret volumes

```yaml
volumes:
  - name: config
    configMap:
      name: my-config
      items:
        - key: nginx.conf
          path: nginx.conf      # filename in the volume

  - name: certs
    secret:
      secretName: tls-secret
      defaultMode: 0400         # file permissions
```

### projected — combine multiple sources

```yaml
volumes:
  - name: combined
    projected:
      sources:
        - configMap:
            name: my-config
        - secret:
            name: my-secret
        - serviceAccountToken:
            path: token
            expirationSeconds: 3600
```

---

## 3. PersistentVolume (PV)

A PV is a piece of storage in the cluster — either manually provisioned by an admin or automatically by a StorageClass.

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-postgres-data
  labels:
    type: local
spec:
  capacity:
    storage: 20Gi

  accessModes:
    - ReadWriteOnce

  persistentVolumeReclaimPolicy: Retain

  storageClassName: fast-ssd    # must match PVC's storageClassName

  # The actual storage backend:

  # Option 1 — AWS EBS
  awsElasticBlockStore:
    volumeID: vol-0a1b2c3d4e5f6
    fsType: ext4

  # Option 2 — NFS
  nfs:
    server: nfs-server.example.com
    path: /data/postgres

  # Option 3 — Local disk (node-specific)
  local:
    path: /mnt/disks/ssd1
  nodeAffinity:
    required:
      nodeSelectorTerms:
        - matchExpressions:
            - key: kubernetes.io/hostname
              operator: In
              values: [worker-1]

  # Option 4 — hostPath (dev/testing only)
  hostPath:
    path: /data/postgres
```

### PV phases

| Phase | Meaning |
|-------|---------|
| `Available` | Not yet bound to a PVC |
| `Bound` | Bound to a PVC — in use |
| `Released` | PVC deleted, PV not yet reclaimed |
| `Failed` | Automatic reclamation failed |

```bash
kubectl get pv
# Shows: NAME, CAPACITY, ACCESS MODES, RECLAIM POLICY, STATUS, CLAIM, STORAGECLASS
```

---

## 4. PersistentVolumeClaim (PVC)

A PVC is a request for storage by a user/pod. Kubernetes binds it to a matching PV.

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data
  namespace: production
spec:
  accessModes:
    - ReadWriteOnce

  storageClassName: fast-ssd    # empty string = no StorageClass (manual PV)

  resources:
    requests:
      storage: 20Gi

  # Optional: select specific PV by labels
  selector:
    matchLabels:
      type: ssd
```

### Using PVC in a pod

```yaml
spec:
  containers:
    - name: postgres
      image: postgres:15
      volumeMounts:
        - name: data
          mountPath: /var/lib/postgresql/data

  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: postgres-data    # name of the PVC
        readOnly: false
```

### PVC binding

```
PVC requests: 20Gi, RWO, fast-ssd StorageClass
                │
                ▼
Kubernetes finds matching PV:
  - storageClassName matches
  - capacity >= requested
  - accessModes compatible
                │
                ▼
PV.status = Bound
PVC.status = Bound
```

```bash
kubectl get pvc
# Shows: NAME, STATUS, VOLUME, CAPACITY, ACCESS MODES, STORAGECLASS

# Describe PVC — see why it's Pending
kubectl describe pvc postgres-data
# Check Events section
```

---

## 5. StorageClass & Dynamic Provisioning

A StorageClass defines **how** storage is provisioned automatically when a PVC is created.

```yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"  # default SC

provisioner: ebs.csi.aws.com    # which CSI driver to use

parameters:                      # driver-specific parameters
  type: gp3
  iops: "3000"
  throughput: "125"
  encrypted: "true"
  kmsKeyId: arn:aws:kms:...

reclaimPolicy: Delete            # Delete or Retain
volumeBindingMode: WaitForFirstConsumer   # Immediate or WaitForFirstConsumer
allowVolumeExpansion: true        # allow PVC resize

mountOptions:
  - discard                       # TRIM support for SSDs
```

### volumeBindingMode

| Mode | When PV is created | Use for |
|------|-------------------|---------|
| `Immediate` | When PVC is created | Network storage (not topology-aware) |
| `WaitForFirstConsumer` | When pod is scheduled | Local storage, zone-aware cloud disks |

**Always use `WaitForFirstConsumer` for cloud disks** — it ensures the disk is created in the same availability zone as the pod.

### Common StorageClass examples

```yaml
# AWS EBS gp3
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: ebs-gp3
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer
allowVolumeExpansion: true

# GCP Persistent Disk
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gcp-ssd
provisioner: pd.csi.storage.gke.io
parameters:
  type: pd-ssd
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer

# Azure Disk
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: azure-disk
provisioner: disk.csi.azure.com
parameters:
  skuName: Premium_LRS
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer

# NFS (for ReadWriteMany)
---
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: nfs
provisioner: nfs.csi.k8s.io
parameters:
  server: nfs-server.example.com
  share: /data
reclaimPolicy: Delete
volumeBindingMode: Immediate
```

### Default StorageClass

```bash
# View StorageClasses
kubectl get storageclass
# The (default) one is used when PVC doesn't specify storageClassName

# Set default
kubectl patch storageclass ebs-gp3 -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
```

### Expanding a PVC

```bash
# Requires allowVolumeExpansion: true on StorageClass

# Edit PVC to request more storage
kubectl edit pvc postgres-data
# Change spec.resources.requests.storage from 20Gi to 50Gi

# Check expansion status
kubectl describe pvc postgres-data
# Look for: "Waiting for user to (re-)start a pod..."
# For filesystem expansion, pod must be restarted
```

---

## 6. CSI Drivers

The **Container Storage Interface (CSI)** is the standard interface between Kubernetes and storage systems.

### CSI driver components

```
StorageClass references provisioner: ebs.csi.aws.com
                │
                ▼
CSI Driver (runs as pods in cluster)
├── Controller Plugin (StatefulSet) — creates/deletes volumes
└── Node Plugin (DaemonSet) — mounts/unmounts volumes on nodes
```

### Common CSI drivers

| Cloud/Storage | CSI Driver | Install |
|--------------|-----------|---------|
| AWS EBS | `ebs.csi.aws.com` | `helm install aws-ebs-csi-driver` |
| GCP PD | `pd.csi.storage.gke.io` | Pre-installed on GKE |
| Azure Disk | `disk.csi.azure.com` | Pre-installed on AKS |
| NFS | `nfs.csi.k8s.io` | `helm install csi-driver-nfs` |
| Longhorn | `driver.longhorn.io` | `helm install longhorn` |
| Rook/Ceph | `rook-ceph.rbd.csi.ceph.com` | `helm install rook-ceph` |

```bash
# Check installed CSI drivers
kubectl get csidrivers

# Check CSI driver pods
kubectl get pods -n kube-system | grep csi
```

---

## 7. Volume Snapshots

Take point-in-time snapshots of PVCs — supported by most CSI drivers.

```yaml
# VolumeSnapshotClass — how to take snapshots
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshotClass
metadata:
  name: csi-aws-vsc
driver: ebs.csi.aws.com
deletionPolicy: Delete
```

```yaml
# Take a snapshot
apiVersion: snapshot.storage.k8s.io/v1
kind: VolumeSnapshot
metadata:
  name: postgres-snapshot-2024-01-15
  namespace: production
spec:
  volumeSnapshotClassName: csi-aws-vsc
  source:
    persistentVolumeClaimName: postgres-data
```

```yaml
# Restore from snapshot — create PVC from snapshot
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-data-restored
spec:
  dataSource:
    name: postgres-snapshot-2024-01-15
    kind: VolumeSnapshot
    apiGroup: snapshot.storage.k8s.io
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: ebs-gp3
```

```bash
kubectl get volumesnapshots -n production
kubectl describe volumesnapshot postgres-snapshot-2024-01-15
```

---

## 8. Storage in StatefulSets

StatefulSets use `volumeClaimTemplates` to create a PVC per pod automatically.

```yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: postgres
spec:
  serviceName: postgres
  replicas: 3
  selector:
    matchLabels:
      app: postgres
  template:
    metadata:
      labels:
        app: postgres
    spec:
      containers:
        - name: postgres
          image: postgres:15
          volumeMounts:
            - name: data
              mountPath: /var/lib/postgresql/data

  # Creates one PVC per pod replica
  volumeClaimTemplates:
    - metadata:
        name: data          # becomes: data-postgres-0, data-postgres-1, data-postgres-2
      spec:
        accessModes: [ReadWriteOnce]
        storageClassName: ebs-gp3
        resources:
          requests:
            storage: 20Gi
```

```bash
# PVCs created by StatefulSet
kubectl get pvc
# data-postgres-0    Bound    pvc-abc    20Gi   RWO   ebs-gp3
# data-postgres-1    Bound    pvc-def    20Gi   RWO   ebs-gp3
# data-postgres-2    Bound    pvc-ghi    20Gi   RWO   ebs-gp3

# Scale down — pods deleted, PVCs RETAINED
kubectl scale statefulset postgres --replicas=1
kubectl get pvc    # data-postgres-1 and data-postgres-2 still exist!

# Scale back up — existing PVCs reattach to the same pods
kubectl scale statefulset postgres --replicas=3
```

---

## 9. Storage Troubleshooting

### PVC stuck in Pending

```bash
kubectl describe pvc my-pvc
# Look at Events — common causes:

# 1. No matching PV (manual provisioning)
# "no persistent volumes available for this claim and no storage class is set"
kubectl get pv    # check if PV exists with matching size/accessMode/storageClass

# 2. StorageClass doesn't exist
# "storageclass.storage.k8s.io 'fast-ssd' not found"
kubectl get storageclass

# 3. CSI driver not installed
# "driver not found"
kubectl get csidrivers

# 4. WaitForFirstConsumer — waiting for pod to be scheduled
# "waiting for first consumer to be created before binding"
# Normal — PVC binds when a pod using it is scheduled
```

### Pod stuck in ContainerCreating with volume error

```bash
kubectl describe pod my-pod
# Common errors:

# "Unable to attach or mount volumes"
# → PVC not bound yet, or PV in wrong AZ

# "Multi-Attach error for volume: volume is already used by pod"
# → RWO volume being used by pod on different node
# → Delete old pod first, or use RWX storage

# "volume 'pvc-xxx' is being deleted"
# → Old pod still releasing the volume, wait or force-delete old pod
```

### Disk full inside container

```bash
kubectl exec my-pod -- df -h    # check disk usage inside pod

# Check PVC usage
kubectl exec my-pod -- du -sh /data/*

# Expand PVC (if StorageClass allows it)
kubectl edit pvc my-pvc
# Increase spec.resources.requests.storage
```

---

## Cheatsheet

```bash
# PV and PVC
kubectl get pv
kubectl get pvc -A
kubectl describe pvc my-pvc        # debug pending PVC — check Events
kubectl delete pvc my-pvc

# StorageClass
kubectl get storageclass
kubectl describe sc ebs-gp3

# Volume snapshots
kubectl get volumesnapshots -A
kubectl describe volumesnapshot my-snap

# Storage inside a pod
kubectl exec my-pod -- df -h
kubectl exec my-pod -- du -sh /data

# CSI drivers
kubectl get csidrivers
kubectl get pods -n kube-system | grep csi
```

```yaml
# Quick PVC template
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-pvc
  namespace: default
spec:
  accessModes: [ReadWriteOnce]
  storageClassName: ebs-gp3
  resources:
    requests:
      storage: 10Gi
```

---

*Next: [Configuration & Secrets →](./05-configuration-secrets.md) — ConfigMaps, Secrets, and managing application config.*
