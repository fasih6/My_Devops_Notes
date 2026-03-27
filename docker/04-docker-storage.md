# 💾 Storage & Volumes

Bind mounts, volumes, tmpfs — how Docker manages persistent and ephemeral data.

---

## 📚 Table of Contents

- [1. Storage Overview](#1-storage-overview)
- [2. Volumes](#2-volumes)
- [3. Bind Mounts](#3-bind-mounts)
- [4. tmpfs Mounts](#4-tmpfs-mounts)
- [5. Storage Drivers](#5-storage-drivers)
- [6. Data Management Patterns](#6-data-management-patterns)
- [7. Backup & Restore](#7-backup--restore)
- [Cheatsheet](#cheatsheet)

---

## 1. Storage Overview

```
Container filesystem:
┌───────────────────────────────────────┐
│  Writable container layer (ephemeral) │ ← lost when container removed
├───────────────────────────────────────┤
│  Image layers (read-only)             │
└───────────────────────────────────────┘

Persistent storage options:
├── Volumes        → managed by Docker, stored in /var/lib/docker/volumes/
├── Bind mounts    → any host path mounted into container
└── tmpfs mounts   → in-memory, not on disk
```

| | Volumes | Bind mounts | tmpfs |
|--|---------|------------|-------|
| **Location** | Docker-managed | Host filesystem | Memory |
| **Managed by** | Docker | User | Docker |
| **Portable** | Yes | No (host-path) | Yes |
| **Backup** | Docker commands | Host filesystem tools | No (RAM) |
| **Performance** | Good | Depends on OS | Fastest |
| **Use for** | Databases, persistent data | Development, configs | Secrets, caches |

---

## 2. Volumes

Volumes are the **preferred** way to persist data. Docker manages them — they're stored at `/var/lib/docker/volumes/` on the host.

### Managing volumes

```bash
# Create a named volume
docker volume create my-data

# List volumes
docker volume ls
docker volume ls --filter name=my-data

# Inspect volume (find the actual path)
docker volume inspect my-data
# Shows: Mountpoint: /var/lib/docker/volumes/my-data/_data

# Remove volume
docker volume rm my-data

# Remove all unused volumes
docker volume prune

# Remove volume with container
docker rm -v my-container    # removes anonymous volumes
```

### Using volumes

```bash
# Named volume
docker run -d \
  -v my-data:/var/lib/postgresql/data \
  --name postgres \
  postgres:15

# Anonymous volume (Docker generates a name)
docker run -d \
  -v /var/lib/postgresql/data \
  postgres:15

# New --mount syntax (more explicit, preferred)
docker run -d \
  --mount type=volume,source=my-data,target=/var/lib/postgresql/data \
  postgres:15

# Read-only volume
docker run -d \
  -v my-config:/etc/app:ro \
  my-app
```

### Volume sharing between containers

```bash
# Two containers sharing the same volume
docker run -d -v shared-data:/data --name producer my-producer
docker run -d -v shared-data:/data --name consumer my-consumer

# Both containers read/write to the same data
```

### Volume drivers (plugins)

```bash
# Use external storage (NFS, AWS EFS, Azure Files)
docker volume create \
  --driver local \
  --opt type=nfs \
  --opt o=addr=nfs-server,rw \
  --opt device=:/exports/data \
  nfs-volume

docker run -d -v nfs-volume:/data my-app
```

---

## 3. Bind Mounts

Bind mounts link a host path directly into a container. Great for development — code changes are immediately visible.

```bash
# Bind mount a directory
docker run -d \
  -v /host/path:/container/path \
  my-app

# New --mount syntax
docker run -d \
  --mount type=bind,source=/host/path,target=/container/path \
  my-app

# Common development pattern — mount source code
docker run -d \
  -v $(pwd):/app \
  -w /app \
  -p 3000:3000 \
  node:20 \
  npm run dev

# Read-only bind mount (protect host data)
docker run -d \
  -v /etc/localtime:/etc/localtime:ro \
  -v /host/config:/etc/app:ro \
  my-app

# Single file bind mount
docker run -d \
  -v /host/nginx.conf:/etc/nginx/nginx.conf:ro \
  nginx
```

### Bind mounts vs volumes

```
Development:
  Use bind mounts → live code reload, direct file access from host

Production:
  Use volumes → portability, Docker manages lifecycle, better performance on non-Linux
```

---

## 4. tmpfs Mounts

tmpfs mounts are stored in the host's memory — never written to disk. Perfect for sensitive data like secrets.

```bash
# tmpfs mount
docker run -d \
  --tmpfs /tmp \
  my-app

# With options
docker run -d \
  --tmpfs /tmp:rw,noexec,nosuid,size=100m \
  my-app

# --mount syntax
docker run -d \
  --mount type=tmpfs,target=/tmp,tmpfs-size=100m \
  my-app
```

Use cases:
- Temporary files that shouldn't be on disk (secrets, session data)
- Performance-sensitive scratch space
- Containers with read-only root filesystem that need `/tmp`

---

## 5. Storage Drivers

Docker uses storage drivers to manage the image layers. The default on modern Linux is `overlay2`.

```bash
# Check storage driver
docker info | grep "Storage Driver"
# Storage Driver: overlay2

# Storage driver locations
ls /var/lib/docker/overlay2/    # overlay2 layer data
ls /var/lib/docker/volumes/     # named volumes
```

### overlay2 — how it works

```
Container view (/merged):
  Combines all layers into one unified filesystem

Layers on disk:
  /var/lib/docker/overlay2/<sha>/
  ├── diff/      ← this layer's files
  ├── link       ← short name for this layer
  ├── lower      ← references to lower layers
  └── work/      ← overlayfs working directory
```

---

## 6. Data Management Patterns

### Sidecar container for data initialization

```bash
# Initialize data before app starts
docker run --rm \
  -v app-data:/data \
  busybox \
  sh -c "echo 'initial data' > /data/init.txt"

# Now start app with pre-initialized volume
docker run -d \
  -v app-data:/data \
  my-app
```

### Read-only root filesystem + writable volumes

```bash
# Security best practice: read-only root, writable volumes for needed paths
docker run -d \
  --read-only \
  --tmpfs /tmp \
  --tmpfs /var/run \
  -v app-logs:/var/log/app \
  my-app
```

### Volume for database persistence

```bash
# PostgreSQL with persistent volume
docker run -d \
  --name postgres \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=myapp \
  -v postgres-data:/var/lib/postgresql/data \
  --restart unless-stopped \
  postgres:15

# Data survives container removal
docker rm postgres
docker run -d --name postgres \
  -v postgres-data:/var/lib/postgresql/data \   # same volume = same data
  postgres:15
```

---

## 7. Backup & Restore

### Backup a volume

```bash
# Backup volume to tarball
docker run --rm \
  -v my-data:/data \
  -v $(pwd):/backup \
  busybox \
  tar czf /backup/my-data-backup.tar.gz -C /data .

# With timestamp
docker run --rm \
  -v postgres-data:/data \
  -v $(pwd):/backup \
  busybox \
  tar czf /backup/postgres-$(date +%Y%m%d).tar.gz -C /data .
```

### Restore a volume

```bash
# Create new volume
docker volume create restored-data

# Restore from backup
docker run --rm \
  -v restored-data:/data \
  -v $(pwd):/backup \
  busybox \
  tar xzf /backup/my-data-backup.tar.gz -C /data

# Copy between volumes
docker run --rm \
  -v source-volume:/from \
  -v dest-volume:/to \
  busybox \
  cp -a /from/. /to/
```

---

## Cheatsheet

```bash
# Volumes
docker volume create my-vol
docker volume ls
docker volume inspect my-vol
docker volume rm my-vol
docker volume prune

# Run with volume
docker run -v my-vol:/data my-app             # named volume
docker run -v /host/path:/data my-app         # bind mount
docker run --tmpfs /tmp my-app                # tmpfs

# Mount syntax (explicit)
docker run --mount type=volume,source=my-vol,target=/data my-app
docker run --mount type=bind,source=$(pwd),target=/app my-app
docker run --mount type=tmpfs,target=/tmp,tmpfs-size=100m my-app

# Read-only
docker run -v my-vol:/data:ro my-app
docker run --read-only my-app                 # read-only root filesystem

# Backup volume
docker run --rm -v my-vol:/data -v $(pwd):/backup \
  busybox tar czf /backup/backup.tar.gz -C /data .
```

---

*Next: [Docker Compose →](./05-docker-compose.md)*
