# 💾 Storage & Filesystems

How Linux manages disks, partitions, filesystems, and volumes — and how to use them reliably in production.

> Storage problems are silent killers in production — disk full, inode exhaustion, slow I/O. This file gives you the tools to prevent and debug all of them.

---

## 📚 Table of Contents

- [1. Storage Concepts](#1-storage-concepts)
- [2. Disk & Partition Management](#2-disk--partition-management)
- [3. Filesystems](#3-filesystems)
- [4. Mounting & /etc/fstab](#4-mounting--etcfstab)
- [5. LVM — Logical Volume Manager](#5-lvm--logical-volume-manager)
- [6. Disk Usage & Monitoring](#6-disk-usage--monitoring)
- [7. I/O Performance](#7-io-performance)
- [8. Network Storage — NFS & iSCSI](#8-network-storage--nfs--iscsi)
- [9. Storage in Kubernetes — PV & PVC](#9-storage-in-kubernetes--pv--pvc)
- [10. Storage Troubleshooting Scenarios](#10-storage-troubleshooting-scenarios)
- [Cheatsheet](#cheatsheet)

---

## 1. Storage Concepts

### The storage stack

```
Application (writes a file)
        │
        ▼
Virtual Filesystem (VFS)    ← uniform interface regardless of filesystem type
        │
        ▼
Filesystem (ext4, xfs, btrfs)  ← manages files, directories, metadata
        │
        ▼
Block Layer                  ← manages I/O requests, scheduling
        │
        ▼
Device Driver                ← talks to actual hardware
        │
        ▼
Hardware (HDD, SSD, NVMe)
```

### Key terms

| Term | What it means |
|------|--------------|
| **Block device** | Storage device accessed in fixed-size blocks (e.g. `/dev/sda`) |
| **Partition** | A slice of a block device (e.g. `/dev/sda1`) |
| **Filesystem** | Structure that organizes files on a partition (ext4, xfs) |
| **Mount** | Attaching a filesystem to a directory in the tree |
| **Mount point** | The directory where a filesystem is attached |
| **Inode** | Data structure storing file metadata (owner, permissions, timestamps, pointers to data blocks) |
| **Block size** | Minimum unit of storage allocation (usually 4KB) |
| **Sector** | Physical unit on disk (512B or 4096B) |
| **LVM** | Logical Volume Manager — abstraction layer for flexible disk management |
| **RAID** | Redundant Array of Independent Disks — for redundancy and/or performance |

### Inodes explained

Every file has two parts:
1. **The inode** — metadata (name, permissions, timestamps, size, pointers to data blocks)
2. **The data blocks** — actual file contents

```bash
# View inode of a file
stat myfile.txt
ls -i myfile.txt    # show inode number

# Inode usage (you can run out of inodes before running out of disk space)
df -i              # inode usage per filesystem

# Find directories with many files (inode consumers)
find / -xdev -printf '%h\n' | sort | uniq -c | sort -rn | head -20
```

---

## 2. Disk & Partition Management

### Viewing disks and partitions

```bash
# List all block devices in a tree
lsblk
lsblk -f               # with filesystem type and UUID
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT  # custom columns

# Example output:
# NAME   SIZE TYPE FSTYPE MOUNTPOINT
# sda    100G disk
# ├─sda1   1G part vfat   /boot/efi
# ├─sda2   2G part swap   [SWAP]
# └─sda3  97G part ext4   /
# sdb     50G disk        ← new empty disk

# List partitions
fdisk -l               # all disks and partitions (needs sudo)
fdisk -l /dev/sdb      # specific disk
parted -l              # parted alternative

# Show UUIDs and filesystem types
blkid
blkid /dev/sda1

# Disk info
hdparm -I /dev/sda     # disk model, features, RPM
```

### Creating partitions with fdisk

```bash
# Interactive partition editor
fdisk /dev/sdb

# Common fdisk commands (inside the interactive prompt):
# m  — help
# p  — print partition table
# n  — new partition
# d  — delete partition
# t  — change partition type
# w  — write changes (saves to disk)
# q  — quit without saving

# Example: create one partition using the whole disk
fdisk /dev/sdb
> n          # new partition
> p          # primary
> 1          # partition number 1
> (enter)    # first sector (default)
> (enter)    # last sector (default = entire disk)
> w          # write and exit
```

### Creating partitions with parted (GPT — better for large disks)

```bash
parted /dev/sdb

# Inside parted:
(parted) mklabel gpt          # create GPT partition table
(parted) mkpart primary ext4 0% 100%   # use entire disk
(parted) print                # show result
(parted) quit
```

### Device naming conventions

| Name | What it is |
|------|-----------|
| `/dev/sda` | First SATA/SCSI disk |
| `/dev/sdb` | Second SATA/SCSI disk |
| `/dev/sda1` | First partition on sda |
| `/dev/nvme0n1` | First NVMe disk |
| `/dev/nvme0n1p1` | First partition on NVMe disk |
| `/dev/vda` | Virtual disk (KVM/QEMU VMs) |
| `/dev/xvda` | Virtual disk (older AWS EC2) |
| `/dev/md0` | Software RAID device |
| `/dev/mapper/vg-lv` | LVM logical volume |

---

## 3. Filesystems

### Creating a filesystem

```bash
# ext4 — most common, stable, good general purpose
mkfs.ext4 /dev/sdb1
mkfs.ext4 -L "data" /dev/sdb1          # with label

# xfs — better for large files and high performance (default on RHEL/CentOS)
mkfs.xfs /dev/sdb1
mkfs.xfs -L "data" /dev/sdb1

# btrfs — modern, snapshots, checksums (not recommended for production Kubernetes)
mkfs.btrfs /dev/sdb1

# vfat — for EFI/boot partitions
mkfs.vfat /dev/sda1

# Check filesystem type
file -s /dev/sda1
blkid /dev/sda1
```

### Filesystem comparison

| Filesystem | Best for | Max file size | Features |
|-----------|---------|--------------|----------|
| **ext4** | General purpose, VMs | 16TB | Journaling, mature, widely supported |
| **xfs** | Large files, high throughput | 8EB | Excellent parallel I/O, online grow only |
| **btrfs** | Snapshots, checksums | 16EB | Copy-on-write, RAID, snapshots (complex) |
| **tmpfs** | In-memory temp storage | RAM limited | Lives in RAM, lost on reboot |
| **vfat** | Boot partitions, USB | 4GB | Cross-platform compatible |

### Filesystem maintenance

```bash
# Check and repair filesystem (must be unmounted first)
fsck /dev/sdb1                 # auto-detect type
e2fsck /dev/sdb1               # ext2/3/4
e2fsck -f /dev/sdb1            # force check even if clean
xfs_repair /dev/sdb1           # xfs

# Check without repairing
fsck -n /dev/sdb1

# Resize filesystem
# ext4 — can grow online AND shrink (unmounted)
resize2fs /dev/sdb1            # grow to fill partition
resize2fs /dev/sdb1 50G        # resize to 50G

# xfs — can only grow, never shrink
xfs_growfs /mnt/data           # grow to fill underlying partition

# Tune ext4 filesystem parameters
tune2fs -l /dev/sda1           # show current parameters
tune2fs -m 1 /dev/sda1         # reduce reserved blocks from 5% to 1%
tune2fs -L "rootfs" /dev/sda1  # set filesystem label
```

---

## 4. Mounting & /etc/fstab

### Temporary mount (lost on reboot)

```bash
# Mount a filesystem
mount /dev/sdb1 /mnt/data
mount -t ext4 /dev/sdb1 /mnt/data      # specify type
mount -t xfs /dev/sdc1 /mnt/storage

# Mount options
mount -o ro /dev/sdb1 /mnt/data        # read-only
mount -o noexec /dev/sdb1 /mnt/data    # can't execute files
mount -o nosuid /dev/sdb1 /mnt/data    # ignore setuid bits
mount -o remount,rw /                   # remount root as read-write

# Mount by UUID (more reliable than device name)
mount UUID="a1b2c3d4-..." /mnt/data
blkid /dev/sdb1                        # find UUID first

# View currently mounted filesystems
mount                                  # all mounts
mount | grep sdb                       # specific device
cat /proc/mounts                       # kernel's view of mounts
findmnt                                # tree view of mounts
findmnt /mnt/data                      # info about specific mount

# Unmount
umount /mnt/data
umount /dev/sdb1                       # by device
umount -l /mnt/data                    # lazy unmount (when busy)
umount -f /mnt/nfs                     # force unmount (NFS)

# Why can't I unmount? (device is busy)
lsof /mnt/data                         # what processes have files open
fuser -m /mnt/data                     # which processes are using it
fuser -km /mnt/data                    # kill those processes and unmount
```

### /etc/fstab — persistent mounts

`/etc/fstab` defines filesystems that mount automatically at boot.

```bash
# /etc/fstab format:
# <device>  <mountpoint>  <type>  <options>  <dump>  <pass>

# Examples:
UUID=a1b2c3d4-e5f6-7890-abcd-ef1234567890  /           ext4    defaults        0  1
UUID=b2c3d4e5-f6g7-8901-bcde-f12345678901  /boot       ext4    defaults        0  2
UUID=c3d4e5f6-g7h8-9012-cdef-123456789012  /mnt/data   xfs     defaults,nofail 0  2
tmpfs                                       /tmp        tmpfs   defaults,size=2G 0  0
//server/share                              /mnt/cifs   cifs    credentials=/etc/cifs-creds,uid=1000 0  0
server:/export                              /mnt/nfs    nfs     defaults,_netdev 0  0
```

**Options explained:**

| Option | Meaning |
|--------|---------|
| `defaults` | rw, suid, dev, exec, auto, nouser, async |
| `noatime` | Don't update access times — improves performance |
| `nofail` | Don't fail boot if device is missing |
| `_netdev` | Wait for network before mounting (for NFS/CIFS) |
| `ro` | Read-only |
| `noexec` | Can't execute files |
| `nosuid` | Ignore setuid bits |
| `auto` | Mount automatically at boot |
| `noauto` | Don't mount at boot (use manually) |

**Pass field (fsck order):**
- `0` — don't check
- `1` — check first (root filesystem only)
- `2` — check after root

```bash
# Test fstab without rebooting
mount -a              # mount all entries in fstab
mount -a -v           # verbose — see what's being mounted

# Validate fstab syntax before rebooting (critical!)
findmnt --verify --verbose
```

> ⚠️ **Always test `mount -a` after editing `/etc/fstab`** before rebooting. A broken fstab can prevent your system from booting.

---

## 5. LVM — Logical Volume Manager

LVM adds a flexible abstraction layer between physical disks and filesystems. Instead of dealing with fixed partitions, you work with logical volumes that can be resized, snapshotted, and moved.

### LVM concepts

```
Physical Disks
  /dev/sdb   /dev/sdc   /dev/sdd
      │           │          │
      ▼           ▼          ▼
Physical Volumes (PV)    ← initialized for LVM
      │           │          │
      └─────┬─────┘          │
            ▼                │
      Volume Group (VG)  ←──┘   ← pool of storage
      (e.g. "data-vg")
            │
      ┌─────┴──────┐
      ▼            ▼
  Logical       Logical
  Volume        Volume
  (e.g. lv-db)  (e.g. lv-logs)
      │              │
      ▼              ▼
  /dev/data-vg/lv-db  /dev/data-vg/lv-logs
      │              │
  mkfs + mount    mkfs + mount
```

### Setting up LVM from scratch

```bash
# Step 1 — Initialize disks as Physical Volumes
pvcreate /dev/sdb /dev/sdc
pvdisplay                      # show PV details
pvs                            # compact PV list

# Step 2 — Create a Volume Group
vgcreate data-vg /dev/sdb /dev/sdc
vgdisplay                      # show VG details
vgs                            # compact VG list

# Step 3 — Create Logical Volumes
lvcreate -L 20G -n lv-db data-vg      # 20GB volume named lv-db
lvcreate -L 10G -n lv-logs data-vg    # 10GB volume named lv-logs
lvcreate -l 100%FREE -n lv-data data-vg  # use all remaining space
lvdisplay                              # show LV details
lvs                                    # compact LV list

# Step 4 — Create filesystem and mount
mkfs.ext4 /dev/data-vg/lv-db
mkdir -p /var/lib/postgresql
mount /dev/data-vg/lv-db /var/lib/postgresql

# Add to /etc/fstab
echo "/dev/data-vg/lv-db /var/lib/postgresql ext4 defaults 0 2" >> /etc/fstab
```

### Extending volumes (online — no downtime)

```bash
# Add a new disk to the volume group
pvcreate /dev/sdd
vgextend data-vg /dev/sdd

# Extend the logical volume
lvextend -L +10G /dev/data-vg/lv-db      # add 10GB
lvextend -l +100%FREE /dev/data-vg/lv-db  # use all free space

# Grow the filesystem to fill the new space
resize2fs /dev/data-vg/lv-db             # ext4
xfs_growfs /var/lib/postgresql           # xfs (use mountpoint)
```

### Shrinking volumes (ext4 only — requires unmount)

```bash
# Must unmount first
umount /var/lib/postgresql

# Check filesystem
e2fsck -f /dev/data-vg/lv-db

# Shrink filesystem FIRST (always before shrinking LV)
resize2fs /dev/data-vg/lv-db 15G

# Then shrink the logical volume
lvreduce -L 15G /dev/data-vg/lv-db

# Remount
mount /dev/data-vg/lv-db /var/lib/postgresql
```

### LVM snapshots

```bash
# Create a snapshot (point-in-time copy)
lvcreate -L 5G -s -n lv-db-snap /dev/data-vg/lv-db

# Mount the snapshot (read-only backup)
mount -o ro /dev/data-vg/lv-db-snap /mnt/backup

# Restore from snapshot (rollback)
umount /var/lib/postgresql
lvconvert --merge /dev/data-vg/lv-db-snap
# Original LV is restored to snapshot state on next mount

# Remove a snapshot
lvremove /dev/data-vg/lv-db-snap
```

### Useful LVM commands

```bash
# Overview of everything
pvs && vgs && lvs

# Full details
pvdisplay
vgdisplay
lvdisplay

# Scan for PVs (after adding a new disk)
pvscan

# Remove components (in reverse order)
lvremove /dev/data-vg/lv-db
vgremove data-vg
pvremove /dev/sdb
```

---

## 6. Disk Usage & Monitoring

```bash
# Filesystem disk space usage
df -h                          # all filesystems, human-readable
df -hT                         # with filesystem type
df -h /var/log                 # specific path
df -i                          # inode usage (important!)

# Directory size
du -sh /var/log                # size of directory
du -sh /var/log/*              # size of each item
du -sh * | sort -h             # sorted by size
du --max-depth=1 -h /          # top-level only
du --max-depth=2 -h /var | sort -h | tail -20  # find large dirs

# Find large files
find / -type f -size +1G 2>/dev/null           # files over 1GB
find / -type f -size +100M -printf "%s %p\n" \
  | sort -rn | head -20                         # top 20 largest files
find /var/log -name "*.log" -size +100M        # large log files

# Real-time disk I/O monitoring
iostat -x 1                    # extended I/O stats every second
iostat -x -d 1 sda             # specific disk
iotop                          # per-process I/O (apt install iotop)
iotop -o                       # only show processes doing I/O

# Watch df over time
watch -n 5 df -h

# Inode exhaustion — when disk shows free space but can't create files
df -i                          # check inode usage
find / -xdev -printf '%h\n' \
  | sort | uniq -c \
  | sort -rn | head -20        # find directories with most files
```

### Common disk space culprits

```bash
# Large log files
find /var/log -name "*.log" -size +100M
journalctl --disk-usage
du -sh /var/log/*

# Docker images and containers
docker system df               # Docker disk usage
docker system prune            # clean up unused images/containers/volumes

# Old kernel packages (Ubuntu)
dpkg --list | grep linux-image
apt autoremove

# Temporary files
du -sh /tmp
du -sh /var/tmp

# Core dumps
find / -name "core" -o -name "core.*" 2>/dev/null

# Deleted files held open by processes (common gotcha)
lsof | grep deleted            # processes holding deleted files open
# The disk space won't be freed until the process is restarted
```

---

## 7. I/O Performance

### Understanding I/O metrics

```bash
# iostat — the main tool
iostat -x 1

# Key columns:
# %util   — how busy the device is (100% = saturated)
# await   — average I/O wait time in ms (high = slow disk or queue)
# r/s     — reads per second
# w/s     — writes per second
# rMB/s   — read throughput in MB/s
# wMB/s   — write throughput in MB/s
# avgqu-sz — average queue size (high = I/O saturation)
```

### I/O schedulers

The I/O scheduler decides the order in which requests hit the disk:

```bash
# Check current scheduler
cat /sys/block/sda/queue/scheduler
# [mq-deadline] kyber bfq none

# Change scheduler
echo mq-deadline > /sys/block/sda/queue/scheduler  # good for spinning disks
echo none > /sys/block/nvme0n1/queue/scheduler      # best for NVMe/SSD

# Make permanent (add to /etc/udev/rules.d/)
echo 'ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/scheduler}="mq-deadline"' \
  > /etc/udev/rules.d/60-scheduler.rules
```

### I/O tuning for Kubernetes nodes

```bash
# Check for disk I/O wait affecting Kubernetes
top                         # wa% in CPU line — high wa = disk bottleneck
iostat -x 1 | grep -E "Device|sda|nvme"

# Tune read-ahead for sequential workloads
blockdev --setra 256 /dev/sda   # 256 * 512B = 128KB read-ahead

# Disable access time updates (reduces write I/O)
mount -o remount,noatime /

# Add noatime to /etc/fstab for persistent effect
```

---

## 8. Network Storage — NFS & iSCSI

### NFS — Network File System

NFS lets you mount a remote directory as if it were local.

```bash
# --- NFS Server Setup ---
# Install
apt install nfs-kernel-server

# Configure exports (/etc/exports)
/data/shared   10.0.0.0/24(rw,sync,no_subtree_check)
/data/readonly 10.0.0.0/24(ro,sync,no_subtree_check)

# Export options:
# rw/ro          — read-write or read-only
# sync           — write to disk before responding (safe)
# async          — respond before writing (faster but risky)
# no_root_squash — allow root on client to be root on server
# root_squash    — map root to nobody (default, safer)

# Apply exports
exportfs -ra               # reload exports
exportfs -v                # show current exports

# Start NFS server
systemctl enable --now nfs-kernel-server
showmount -e localhost     # verify exports


# --- NFS Client Setup ---
# Install
apt install nfs-common

# Mount manually
mount -t nfs server:/data/shared /mnt/nfs
mount -t nfs -o vers=4,hard,intr server:/data/shared /mnt/nfs

# Mount options:
# vers=4       — use NFSv4 (preferred)
# hard         — retry indefinitely (safer for production)
# soft         — fail after timeout (dangerous for writes)
# intr         — allow signals to interrupt NFS
# noatime      — don't update access times (performance)
# timeo=600    — timeout in tenths of a second

# Add to /etc/fstab for persistent mount
server:/data/shared  /mnt/nfs  nfs  vers=4,hard,intr,_netdev  0  0

# Check NFS mounts
showmount -e server        # see what server exports
nfsstat                    # NFS statistics
```

### iSCSI — block-level network storage

iSCSI presents a remote block device over the network (like a remote hard disk).

```bash
# Install iSCSI initiator
apt install open-iscsi

# Discover targets on a server
iscsiadm -m discovery -t sendtargets -p <server-ip>

# Login to a target
iscsiadm -m node -T <target-name> -p <server-ip> --login

# List connected sessions
iscsiadm -m session

# The iSCSI device appears as a regular block device (e.g. /dev/sdb)
# Format and mount it like any other disk
mkfs.ext4 /dev/sdb
mount /dev/sdb /mnt/iscsi

# Logout
iscsiadm -m node -T <target-name> --logout
```

---

## 9. Storage in Kubernetes — PV & PVC

Understanding how Kubernetes storage maps to Linux storage.

### The storage hierarchy

```
StorageClass          ← defines HOW to provision storage (e.g. AWS EBS, NFS)
       │
       │  dynamic provisioning
       ▼
PersistentVolume (PV) ← actual storage resource (like a disk)
       │
       │  bound to
       ▼
PersistentVolumeClaim (PVC) ← request for storage by a pod
       │
       │  mounted into
       ▼
     Pod
```

### PersistentVolume example

```yaml
# Manual PV — admin creates this
apiVersion: v1
kind: PersistentVolume
metadata:
  name: pv-postgres
spec:
  capacity:
    storage: 20Gi
  accessModes:
    - ReadWriteOnce          # one node can read/write
  persistentVolumeReclaimPolicy: Retain   # don't delete data when PVC deleted
  storageClassName: standard
  hostPath:                  # for local testing only
    path: /mnt/data/postgres
```

### AccessModes

| Mode | Short | Meaning |
|------|-------|---------|
| `ReadWriteOnce` | RWO | One node can read and write |
| `ReadOnlyMany` | ROX | Many nodes can read |
| `ReadWriteMany` | RWX | Many nodes can read and write (requires NFS or similar) |
| `ReadWriteOncePod` | RWOP | Only one pod can read and write |

### PersistentVolumeClaim example

```yaml
# PVC — developer requests storage
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-pvc
  namespace: production
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 20Gi
  storageClassName: standard
```

```yaml
# Pod using the PVC
spec:
  volumes:
    - name: postgres-data
      persistentVolumeClaim:
        claimName: postgres-pvc
  containers:
    - name: postgres
      volumeMounts:
        - name: postgres-data
          mountPath: /var/lib/postgresql/data
```

### StorageClass — dynamic provisioning

```yaml
# AWS EBS StorageClass
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: fast-ssd
provisioner: ebs.csi.aws.com
parameters:
  type: gp3
  iops: "3000"
  throughput: "125"
reclaimPolicy: Delete
volumeBindingMode: WaitForFirstConsumer  # don't provision until pod is scheduled
allowVolumeExpansion: true               # allow PVC resize
```

### Storage debugging commands

```bash
# Check PV and PVC status
kubectl get pv
kubectl get pvc -A
kubectl describe pvc postgres-pvc -n production

# PVC stuck in Pending?
kubectl describe pvc postgres-pvc   # look at Events section
# Common causes:
# - No matching PV available
# - StorageClass doesn't exist
# - Insufficient storage in the cluster

# Check what's mounted inside a pod
kubectl exec -it postgres-pod -- df -h
kubectl exec -it postgres-pod -- mount | grep postgres

# Check volume from the node
# Find which node the pod is on
kubectl get pod postgres-pod -o wide
# SSH to that node, then:
df -h | grep pvc
ls /var/lib/kubelet/pods/

# StorageClass
kubectl get storageclass
kubectl describe storageclass fast-ssd
```

---

## 10. Storage Troubleshooting Scenarios

---

**Scenario: Disk is full — df shows 100%**

```bash
# Step 1 — Find what's using the space
du --max-depth=2 -h / 2>/dev/null | sort -h | tail -30

# Step 2 — Common culprits
du -sh /var/log/*              # large logs
journalctl --disk-usage        # systemd journal
docker system df               # Docker images/volumes
find / -name "*.core" 2>/dev/null  # core dumps
find / -name "*.tmp" -size +100M 2>/dev/null  # large temp files

# Step 3 — Find deleted files still held open
lsof | grep deleted
# These files are "deleted" but disk space won't free until process closes them
# Restart the process holding them to reclaim space

# Step 4 — Emergency space recovery
# Truncate a log file (don't delete it — service might be writing to it)
> /var/log/large-app.log       # truncate to zero
# Or rotate logs
logrotate -f /etc/logrotate.conf

# Step 5 — If it's the journal
journalctl --vacuum-size=200M  # reduce journal to 200MB
journalctl --vacuum-time=3d    # delete logs older than 3 days
```

---

**Scenario: "No space left on device" but df shows free space**

This is inode exhaustion — you have space but no inodes left to create new files.

```bash
# Confirm it's inodes
df -i
# Look for filesystem at 100% IUse%

# Find directories with too many files
find / -xdev -printf '%h\n' \
  | sort | uniq -c \
  | sort -rn | head -20

# Common culprits
ls /var/spool/mqueue | wc -l   # mail queue
ls /tmp | wc -l                # temp files
# Kubernetes: check for leftover ConfigMap/Secret mount files
ls /var/lib/kubelet/pods/ | wc -l

# Clean up
rm -rf /tmp/*
find /var/spool/mqueue -type f -delete
```

---

**Scenario: NFS mount is hanging**

```bash
# Check if NFS server is reachable
ping <nfs-server>
showmount -e <nfs-server>

# Check NFS mount options
mount | grep nfs

# If mounted with soft — processes will hang on I/O
# If mounted with hard — they'll retry indefinitely (safer)

# Find processes stuck waiting on NFS
ps aux | awk '$8 == "D" {print}'   # D state processes = waiting on I/O

# Force unmount a hung NFS mount
umount -l /mnt/nfs    # lazy unmount — detach from filesystem tree
umount -f /mnt/nfs    # force unmount

# Remount with better options
mount -t nfs -o vers=4,hard,intr,timeo=30 server:/share /mnt/nfs
```

---

**Scenario: Kubernetes PVC stuck in Pending**

```bash
# Get full details
kubectl describe pvc <pvc-name> -n <namespace>
# Look at Events section — it will tell you exactly why

# Common causes and fixes:

# 1. No matching PV (manual provisioning)
kubectl get pv                 # check if PV exists with matching size and access mode

# 2. StorageClass doesn't exist
kubectl get storageclass
# Create the StorageClass or fix the PVC's storageClassName

# 3. WaitForFirstConsumer binding mode
# PVC stays Pending until a pod using it is scheduled
kubectl get pod | grep <your-app>  # check if pod is also pending

# 4. CSI driver not installed
kubectl get pods -n kube-system | grep csi

# 5. Insufficient capacity (for local volumes)
kubectl describe node | grep -A5 "Capacity"
```

---

## Cheatsheet

```bash
# Disk info
lsblk -f                          # disks, partitions, filesystems
fdisk -l                          # partition tables
blkid                             # UUIDs and filesystem types

# Usage
df -h                             # filesystem space usage
df -i                             # inode usage
du -sh /path                      # directory size
du --max-depth=1 -h / | sort -h  # find large directories

# Filesystem
mkfs.ext4 /dev/sdb1               # create ext4 filesystem
mkfs.xfs /dev/sdb1                # create xfs filesystem
fsck /dev/sdb1                    # check filesystem (unmounted)
resize2fs /dev/sdb1               # resize ext4 to fill partition

# Mount
mount /dev/sdb1 /mnt/data         # mount filesystem
umount /mnt/data                  # unmount
mount -a                          # mount all fstab entries (test fstab)
findmnt                           # tree view of all mounts

# LVM
pvs && vgs && lvs                 # overview
pvcreate /dev/sdb                 # init disk for LVM
vgcreate myvg /dev/sdb            # create volume group
lvcreate -L 20G -n mylv myvg      # create logical volume
lvextend -l +100%FREE /dev/myvg/mylv  # extend LV
resize2fs /dev/myvg/mylv          # grow filesystem after LV extend

# I/O monitoring
iostat -x 1                       # I/O stats per second
iotop -o                          # per-process I/O
lsof | grep deleted               # deleted files still consuming space

# Kubernetes storage
kubectl get pv && kubectl get pvc -A
kubectl describe pvc <name>       # debug pending PVC
kubectl exec -it <pod> -- df -h   # disk usage inside pod
```

---

*Next: [Shell Scripting →](./06-linux-shell-scripting.md) — bash scripts, pipes, automation, and cron.*
