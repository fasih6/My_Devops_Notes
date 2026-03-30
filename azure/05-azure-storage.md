# Azure Storage 🗄️

> Part of my DevOps journey — azure folder

---

## Azure Storage Account

All Azure Storage services (Blob, Files, Tables, Queues) live inside a **Storage Account** — the top-level container. Storage account names must be globally unique, 3-24 characters, lowercase alphanumeric only.

```bash
# Create storage account
az storage account create \
  --name myappstorageprod \
  --resource-group myapp-prod-rg \
  --location eastus \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --https-only true \
  --tags Environment=production

# Get connection string
az storage account show-connection-string \
  --name myappstorageprod \
  --resource-group myapp-prod-rg \
  --output tsv

# Get access keys
az storage account keys list \
  --account-name myappstorageprod \
  --resource-group myapp-prod-rg
```

### Storage Account SKUs (Redundancy)

| SKU | Redundancy | Copies | Use case |
|-----|-----------|--------|---------|
| **LRS** | Locally Redundant | 3 copies, same DC | Cheapest, dev/non-critical |
| **ZRS** | Zone Redundant | 3 copies, 3 AZs | Production, AZ resilience |
| **GRS** | Geo Redundant | 6 copies, 2 regions | Regional DR, async replication |
| **GZRS** | Geo+Zone Redundant | 6 copies, 3 AZs + 2 regions | Maximum durability |
| **RA-GRS** | Read-Access Geo | GRS + read from secondary | Read from DR region |

---

## Blob Storage (≈ AWS S3)

Object storage for unstructured data — files, images, videos, backups, logs, static websites.

### Blob Types

| Type | Use case |
|------|---------|
| **Block Blob** | Files, images, documents (most common) |
| **Append Blob** | Log files (append-only) |
| **Page Blob** | VM disks (random access, 512-byte pages) |

### Access Tiers (Storage Classes)

| Tier | Access | Cost | Use case |
|------|--------|------|---------|
| **Hot** | Instant | High storage, low access | Frequently accessed |
| **Cool** | Instant | Lower storage, access fee | Infrequent, 30-day min |
| **Cold** | Instant | Even lower, higher access fee | Rare access, 90-day min |
| **Archive** | Hours (rehydrate first) | Lowest storage, high retrieval | Long-term archival, 180-day min |

```bash
# Create container (like S3 bucket prefix)
az storage container create \
  --name mycontainer \
  --account-name myappstorageprod \
  --public-access off

# Upload blob
az storage blob upload \
  --account-name myappstorageprod \
  --container-name mycontainer \
  --name folder/file.txt \
  --file ./local-file.txt

# Upload directory
az storage blob upload-batch \
  --account-name myappstorageprod \
  --destination mycontainer/uploads \
  --source ./local-folder

# Download
az storage blob download \
  --account-name myappstorageprod \
  --container-name mycontainer \
  --name folder/file.txt \
  --file ./downloaded-file.txt

# List blobs
az storage blob list \
  --account-name myappstorageprod \
  --container-name mycontainer \
  --output table

# Generate SAS URL (time-limited access)
az storage blob generate-sas \
  --account-name myappstorageprod \
  --container-name mycontainer \
  --name file.txt \
  --permissions r \
  --expiry 2024-12-31T00:00:00Z \
  --output tsv

# Delete blob
az storage blob delete \
  --account-name myappstorageprod \
  --container-name mycontainer \
  --name folder/file.txt

# Copy blob between accounts
az storage blob copy start \
  --destination-account-name destinationaccount \
  --destination-container destcontainer \
  --destination-blob destfile.txt \
  --source-account-name sourceaccount \
  --source-container sourcecontainer \
  --source-blob sourcefile.txt
```

### Lifecycle Management

```bash
az storage account management-policy create \
  --account-name myappstorageprod \
  --resource-group myapp-prod-rg \
  --policy '{
    "rules": [
      {
        "name": "archive-old-logs",
        "enabled": true,
        "type": "Lifecycle",
        "definition": {
          "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["logs/"] },
          "actions": {
            "baseBlob": {
              "tierToCool": { "daysAfterModificationGreaterThan": 30 },
              "tierToArchive": { "daysAfterModificationGreaterThan": 90 },
              "delete": { "daysAfterModificationGreaterThan": 365 }
            }
          }
        }
      }
    ]
  }'
```

### Static Website Hosting

```bash
# Enable static website
az storage blob service-properties update \
  --account-name myappstorageprod \
  --static-website \
  --index-document index.html \
  --404-document 404.html

# Upload site files
az storage blob upload-batch \
  --account-name myappstorageprod \
  --destination '$web' \
  --source ./dist

# Get website URL
az storage account show \
  --name myappstorageprod \
  --resource-group myapp-prod-rg \
  --query primaryEndpoints.web \
  --output tsv
```

---

## Azure Files (≈ AWS EFS)

**Managed SMB/NFS file shares** — mount on Windows, Linux, and macOS. Share files across VMs.

```bash
# Create file share
az storage share create \
  --name myfileshare \
  --account-name myappstorageprod \
  --quota 100  # GB

# Mount on Linux (SMB)
sudo apt install cifs-utils
sudo mkdir /mnt/azurefiles
sudo mount -t cifs //myappstorageprod.file.core.windows.net/myfileshare \
  /mnt/azurefiles \
  -o username=myappstorageprod,password=<access-key>,serverino

# Upload file to share
az storage file upload \
  --account-name myappstorageprod \
  --share-name myfileshare \
  --source ./config.json \
  --path config/config.json
```

**Azure File Sync** — sync on-premises Windows file servers with Azure Files. Hybrid file storage.

---

## Managed Disks (≈ AWS EBS)

Block storage for Azure VMs. Managed by Azure — no storage account needed.

| Type | Max IOPS | Max Throughput | Use case |
|------|---------|---------------|---------|
| **Standard HDD** | 2,000 | 500 MB/s | Dev/test, backups |
| **Standard SSD** | 6,000 | 750 MB/s | Web servers, light prod |
| **Premium SSD** | 20,000 | 900 MB/s | Production databases |
| **Premium SSD v2** | 80,000 | 1,200 MB/s | I/O intensive DBs |
| **Ultra Disk** | 160,000 | 4,000 MB/s | SAP HANA, mission critical |

```bash
# Create managed disk
az disk create \
  --name myapp-datadisk \
  --resource-group myapp-prod-rg \
  --size-gb 256 \
  --sku Premium_LRS \
  --zone 1

# Attach to VM
az vm disk attach \
  --vm-name my-vm \
  --resource-group myapp-prod-rg \
  --name myapp-datadisk

# Create snapshot
az snapshot create \
  --name myapp-disk-snapshot \
  --resource-group myapp-prod-rg \
  --source myapp-datadisk
```

---

## Storage Security

```bash
# Disable storage account key access (force AAD auth only)
az storage account update \
  --name myappstorageprod \
  --resource-group myapp-prod-rg \
  --allow-shared-key-access false

# Enable private endpoint (access only from VNet)
az network private-endpoint create \
  --name storage-private-endpoint \
  --resource-group myapp-prod-rg \
  --vnet-name myapp-vnet \
  --subnet app-subnet \
  --private-connection-resource-id $(az storage account show \
    --name myappstorageprod -g myapp-prod-rg --query id -o tsv) \
  --connection-name myapp-storage-conn \
  --group-id blob

# Enable soft delete (recovery window)
az storage blob service-properties delete-policy update \
  --account-name myappstorageprod \
  --enable true \
  --days-retained 30

# Enable versioning
az storage account blob-service-properties update \
  --account-name myappstorageprod \
  --resource-group myapp-prod-rg \
  --enable-versioning true
```

---

## Quick Reference

```
Storage Account:   top-level container for all storage services
Blob:              object storage (hot/cool/cold/archive tiers)
Files:             managed SMB/NFS file shares
Disks:             block storage for VMs (Standard HDD/SSD, Premium SSD, Ultra)
Tables:            NoSQL key-value store (simple, cheap)
Queues:            simple message queue (max 64KB messages)

Redundancy:        LRS → ZRS → GRS → GZRS (increasing durability + cost)

az storage account create --name x --sku Standard_LRS --kind StorageV2
az storage container create --name x --account-name x
az storage blob upload --container-name x --name path --file ./local
az storage blob upload-batch --destination x --source ./folder
az storage blob generate-sas --permissions r --expiry yyyy-mm-dd
az storage share create --name x --quota 100
az disk create --name x --size-gb 256 --sku Premium_LRS
```
