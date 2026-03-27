# 📦 Inventory Management

Managing static and dynamic inventories — from simple host lists to auto-discovered cloud infrastructure.

---

## 📚 Table of Contents

- [1. Static Inventory](#1-static-inventory)
- [2. Inventory Variables](#2-inventory-variables)
- [3. Dynamic Inventory](#3-dynamic-inventory)
- [4. AWS Dynamic Inventory](#4-aws-dynamic-inventory)
- [5. GCP Dynamic Inventory](#5-gcp-dynamic-inventory)
- [6. Inventory Patterns & Targeting](#6-inventory-patterns--targeting)
- [7. Inventory Best Practices](#7-inventory-best-practices)
- [Cheatsheet](#cheatsheet)

---

## 1. Static Inventory

### INI format

```ini
# inventory/hosts.ini

# Standalone hosts (no group)
mail.example.com
backup.example.com

[webservers]
web1.example.com
web2.example.com
web3.example.com

# With inline variables
[webservers]
web1.example.com ansible_host=10.0.1.1 ansible_user=ubuntu
web2.example.com ansible_host=10.0.1.2 ansible_user=ubuntu

# Range shorthand
web[1:3].example.com     # web1, web2, web3
db[a:c].example.com      # dba, dbb, dbc
10.0.1.[1:5]             # 10.0.1.1 through 10.0.1.5

[databases]
db1.example.com
db2.example.com

[loadbalancers]
lb1.example.com

# Group of groups
[production:children]
webservers
databases
loadbalancers

[staging:children]
webservers
databases

# Group variables
[webservers:vars]
ansible_user=ubuntu
http_port=80
nginx_worker_processes=4

[databases:vars]
ansible_user=postgres
pg_port=5432
```

### YAML format (preferred for complex inventories)

```yaml
# inventory/hosts.yml
all:
  vars:
    ansible_python_interpreter: /usr/bin/python3
    timezone: Europe/Berlin

  children:
    production:
      children:
        webservers:
          vars:
            http_port: 80
            nginx_worker_processes: auto
          hosts:
            web1.example.com:
              ansible_host: 10.0.1.1
              server_id: 1
            web2.example.com:
              ansible_host: 10.0.1.2
              server_id: 2

        databases:
          vars:
            pg_port: 5432
            pg_max_connections: 200
          hosts:
            db1.example.com:
              ansible_host: 10.0.2.1
              db_role: primary
            db2.example.com:
              ansible_host: 10.0.2.2
              db_role: replica

        loadbalancers:
          hosts:
            lb1.example.com:
              ansible_host: 10.0.3.1

    staging:
      vars:
        http_port: 8080
      children:
        webservers:
          hosts:
            staging-web1.example.com:
              ansible_host: 10.1.1.1
```

---

## 2. Inventory Variables

### Directory structure for variables

```
inventory/
├── hosts.yml                    # host definitions
├── group_vars/
│   ├── all.yml                  # applies to every host
│   ├── all/
│   │   ├── vars.yml             # general vars
│   │   └── vault.yml            # encrypted secrets
│   ├── webservers.yml           # applies to webservers group
│   ├── webservers/
│   │   ├── vars.yml
│   │   └── vault.yml
│   ├── databases.yml
│   └── production.yml
└── host_vars/
    ├── web1.example.com.yml     # vars for this host only
    ├── web1.example.com/
    │   ├── vars.yml
    │   └── vault.yml
    └── db1.example.com.yml
```

```yaml
# group_vars/all.yml
ntp_servers:
  - pool.ntp.org
  - time.cloudflare.com
dns_servers:
  - 8.8.8.8
  - 1.1.1.1
default_shell: /bin/bash
ansible_python_interpreter: /usr/bin/python3

# group_vars/webservers.yml
nginx_version: "1.24"
ssl_cert_dir: /etc/ssl/certs
app_port: 8080
log_retention_days: 30

# host_vars/web1.example.com.yml
server_role: primary
backup_enabled: true
monitoring_tags:
  environment: production
  team: platform
```

---

## 3. Dynamic Inventory

Dynamic inventory scripts query external sources (AWS, GCP, Azure, VMware, etc.) and return host lists at runtime.

### How dynamic inventory works

```
ansible-playbook -i inventory/ site.yml
         │
         │  if inventory/ contains executable scripts or plugins
         ▼
  Ansible runs the inventory plugin/script
         │
         ▼
  Plugin queries AWS/GCP/CMDB/etc.
         │
         ▼
  Returns JSON with hosts and variables
         │
         ▼
  Ansible uses that as the inventory
```

### JSON format returned by dynamic inventory

```json
{
  "webservers": {
    "hosts": ["10.0.1.1", "10.0.1.2"],
    "vars": {
      "http_port": 80
    }
  },
  "databases": {
    "hosts": ["10.0.2.1"]
  },
  "_meta": {
    "hostvars": {
      "10.0.1.1": {
        "ansible_host": "10.0.1.1",
        "instance_id": "i-abc123"
      }
    }
  }
}
```

### Using an inventory directory (mix static + dynamic)

```
inventory/
├── hosts.yml          # static hosts
├── aws_ec2.yml        # dynamic AWS inventory plugin config
└── group_vars/
    └── all.yml
```

Ansible reads everything in the directory — static and dynamic together.

---

## 4. AWS Dynamic Inventory

### Setup

```bash
# Install required collection
ansible-galaxy collection install amazon.aws

# Install boto3 (AWS SDK for Python)
pip install boto3 botocore

# Configure AWS credentials (choose one)
# Option 1 — Environment variables
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_DEFAULT_REGION="eu-central-1"

# Option 2 — AWS credentials file
# ~/.aws/credentials
[default]
aws_access_key_id = AKIA...
aws_secret_access_key = ...

# Option 3 — IAM role (best for EC2/EKS — no credentials needed)
```

### aws_ec2.yml — inventory plugin config

```yaml
# inventory/aws_ec2.yml
plugin: amazon.aws.aws_ec2

# AWS regions to query
regions:
  - eu-central-1
  - eu-west-1

# Filter to specific instances
filters:
  instance-state-name: running    # only running instances
  "tag:Environment": production   # only production tagged

# Include instances without public IPs
include_filters:
  - tag:Ansible: managed          # only instances tagged Ansible=managed

# Use private IP for connection (within VPC)
use_private_ip: true

# Group instances by their tags
keyed_groups:
  - prefix: env
    key: tags.Environment         # creates groups: env_production, env_staging
  - prefix: role
    key: tags.Role                # creates groups: role_web, role_db
  - prefix: az
    key: placement.availability_zone  # groups by AZ

# Auto-group by region
groups:
  webservers: "'web' in tags.Role"
  databases: "'db' in tags.Role"

# Variables to pull from instance metadata
hostnames:
  - private-ip-address            # use private IP as hostname
  - dns-name                      # fallback to DNS name

# Compose host variables from EC2 metadata
compose:
  ansible_host: private_ip_address
  instance_id: instance_id
  instance_type: instance_type
  environment: tags.Environment
```

### Testing AWS dynamic inventory

```bash
# List all discovered hosts
ansible-inventory -i inventory/aws_ec2.yml --list

# Show as graph
ansible-inventory -i inventory/aws_ec2.yml --graph

# Ping all discovered hosts
ansible all -i inventory/aws_ec2.yml -m ping

# Target specific tag-based group
ansible env_production -i inventory/aws_ec2.yml -m ping
ansible role_web -i inventory/aws_ec2.yml -m command -a "uptime"
```

### Tagging EC2 instances for Ansible

Use consistent tags on your EC2 instances:

```
Tag Key          Tag Value
──────────────   ─────────────────
Name             web1-production
Environment      production
Role             web
Project          myapp
Ansible          managed           ← filter only Ansible-managed hosts
```

---

## 5. GCP Dynamic Inventory

```bash
# Install collection
ansible-galaxy collection install google.cloud

# Install Google auth libraries
pip install requests google-auth
```

```yaml
# inventory/gcp_compute.yml
plugin: google.cloud.gcp_compute

# GCP project and auth
projects:
  - my-gcp-project-id

auth_kind: serviceaccount
service_account_file: /path/to/service-account.json
# OR use application default credentials:
# auth_kind: application

# Filter instances
filters:
  - status = RUNNING
  - labels.environment = production

# Group by labels
keyed_groups:
  - prefix: env
    key: labels.environment
  - prefix: role
    key: labels.role

# Use internal IP
hostnames:
  - name
  - networkInterfaces[0].networkIP

compose:
  ansible_host: networkInterfaces[0].networkIP
```

---

## 6. Inventory Patterns & Targeting

### Host patterns — selecting what to target

```bash
# All hosts
ansible all -m ping

# Specific group
ansible webservers -m ping

# Specific host
ansible web1.example.com -m ping

# Multiple groups (union)
ansible webservers:databases -m ping

# Intersection (hosts in both groups)
ansible "webservers:&production" -m ping

# Exclusion (webservers but NOT staging)
ansible "webservers:!staging" -m ping

# Wildcard
ansible "web*.example.com" -m ping

# Regex (prefix with ~)
ansible "~web[0-9]+" -m ping

# Index (first host in group)
ansible "webservers[0]" -m ping

# Range (first 3 hosts in group)
ansible "webservers[0:2]" -m ping
```

### Limiting in playbooks

```yaml
# Playbook-level host limit
- name: Deploy to webservers
  hosts: webservers:&production     # intersection
```

```bash
# Override at runtime
ansible-playbook site.yml --limit "webservers:!web3.example.com"
ansible-playbook site.yml --limit @failed_hosts.txt   # retry file
```

### Special groups

| Group | Contains |
|-------|---------|
| `all` | Every host in inventory |
| `ungrouped` | Hosts not in any group |

---

## 7. Inventory Best Practices

### Environment separation

```
inventories/
├── production/
│   ├── hosts.yml
│   └── group_vars/
│       ├── all.yml
│       └── webservers.yml
└── staging/
    ├── hosts.yml
    └── group_vars/
        ├── all.yml
        └── webservers.yml
```

```bash
# Run against specific environment
ansible-playbook -i inventories/production/ site.yml
ansible-playbook -i inventories/staging/ site.yml
```

### Recommended inventory structure

```
inventory/
├── production/
│   ├── hosts.yml            # host definitions
│   ├── aws_ec2.yml          # dynamic AWS inventory
│   └── group_vars/
│       ├── all/
│       │   ├── vars.yml     # non-sensitive vars
│       │   └── vault.yml    # encrypted secrets
│       ├── webservers.yml
│       └── databases.yml
├── staging/
│   └── ...
└── development/
    └── ...
```

### Keep secrets out of inventory

```yaml
# group_vars/all/vars.yml — safe to commit
db_host: db.example.com
db_port: 5432
db_name: myapp

# group_vars/all/vault.yml — encrypted with ansible-vault
db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  38623534353830393665...
```

---

## Cheatsheet

```bash
# List inventory
ansible-inventory -i inventory/ --list
ansible-inventory -i inventory/ --graph

# Test connectivity
ansible all -i inventory/ -m ping
ansible webservers -i inventory/ -m ping

# Ad-hoc commands
ansible all -i inventory/ -m command -a "uptime"
ansible webservers -i inventory/ -m shell -a "df -h"

# Dynamic inventory (AWS)
ansible-inventory -i inventory/aws_ec2.yml --graph
ansible all -i inventory/aws_ec2.yml -m ping

# Host patterns
ansible "webservers:&production" -m ping   # intersection
ansible "webservers:!staging" -m ping      # exclusion
ansible "web[0:2]" -m ping                 # range
```

---

*Next: [Vault — Secrets Management →](./05-ansible-vault.md)*
