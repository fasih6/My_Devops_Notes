# ⚙️ Ansible

A complete Ansible knowledge base — from core concepts to production-grade project structure.

> Ansible is the most widely used configuration management tool in DevOps. It's agentless, YAML-based, and runs over plain SSH — which is why it shows up in almost every German DevOps job description.

---

## 🗺️ Learning Path

```
01 → 02 → 03 → 04 → 05 → 06 → 07 → 08
 │     │     │     │     │     │     │     │
 │     │     │     │     │     │     │     └── Practice interview Q&A
 │     │     │     │     │     │     └──────── Structure real projects
 │     │     │     │     │     └────────────── Generate dynamic configs
 │     │     │     │     └──────────────────── Encrypt secrets safely
 │     │     │     └────────────────────────── Manage any infrastructure
 │     │     └──────────────────────────────── Reuse code across projects
 │     └────────────────────────────────────── Write real playbooks
 └──────────────────────────────────────────── Understand the foundation
```

---

## 📚 Contents

| # | File | What you'll learn |
|---|------|------------------|
| 01 | [Core Concepts](./01-ansible-core-concepts.md) | How Ansible works, inventory, modules, playbooks, idempotency |
| 02 | [Playbooks & Tasks](./02-ansible-playbooks-tasks.md) | Variables, loops, conditionals, error handling, rolling deploys |
| 03 | [Roles & Galaxy](./03-ansible-roles-galaxy.md) | Role structure, reusable code, Galaxy, collections |
| 04 | [Inventory Management](./04-ansible-inventory.md) | Static/dynamic inventory, AWS/GCP, host patterns |
| 05 | [Vault — Secrets](./05-ansible-vault.md) | Encrypting secrets, CI/CD integration, best practices |
| 06 | [Jinja2 Templating](./06-ansible-jinja2.md) | Dynamic config files, filters, loops, real templates |
| 07 | [Best Practices](./07-ansible-best-practices.md) | Project structure, testing with Molecule, CI/CD pipeline |
| 08 | [Interview Q&A](./08-ansible-interview-qa.md) | Core, scenario-based, and advanced interview questions |

---

## ⚡ Quick Reference

### Run a playbook

```bash
# Basic run
ansible-playbook -i inventories/production/ site.yml

# Dry run — see what would change
ansible-playbook -i inventories/production/ site.yml --check --diff

# Limit to specific hosts
ansible-playbook site.yml --limit webservers
ansible-playbook site.yml --limit "web1.example.com,web2.example.com"

# Run specific tags only
ansible-playbook site.yml --tags "config,restart"
ansible-playbook site.yml --skip-tags restart

# With vault password
ansible-playbook site.yml --vault-password-file ~/.vault_pass

# Extra variables
ansible-playbook site.yml -e "version=v1.2.3 env=production"

# Verbose output
ansible-playbook site.yml -v     # verbose
ansible-playbook site.yml -vvv   # very verbose (shows SSH commands)
```

### Ad-hoc commands

```bash
# Test connectivity
ansible all -i inventory/ -m ping

# Run command on all hosts
ansible webservers -i inventory/ -m command -a "uptime"
ansible all -i inventory/ -m shell -a "df -h | grep /dev/sda"

# Gather facts from a host
ansible web1 -i inventory/ -m setup
ansible web1 -i inventory/ -m setup -a "filter=ansible_distribution*"

# Copy file to hosts
ansible webservers -i inventory/ -m copy -a "src=file.txt dest=/tmp/"

# Install package on all hosts
ansible all -i inventory/ -m apt -a "name=htop state=present" --become
```

### Galaxy

```bash
# Install from requirements.yml
ansible-galaxy install -r requirements.yml
ansible-galaxy collection install -r requirements.yml

# Create new role
ansible-galaxy role init myrole

# List installed
ansible-galaxy role list
ansible-galaxy collection list
```

### Vault

```bash
# Encrypt a value
ansible-vault encrypt_string 'MySecret' --name 'db_password'

# Create encrypted file
ansible-vault create group_vars/all/vault.yml

# Edit encrypted file
ansible-vault edit group_vars/all/vault.yml

# View encrypted file
ansible-vault view group_vars/all/vault.yml
```

---

## 🧠 Key Concepts at a Glance

| Concept | One-line summary |
|---------|-----------------|
| **Agentless** | No software needed on target servers — uses SSH |
| **Idempotency** | Run the same playbook 10 times, get the same result |
| **Playbook** | YAML file containing one or more plays |
| **Play** | Maps a group of hosts to a list of tasks |
| **Task** | Single action using one module |
| **Module** | Code that does the actual work (apt, copy, service) |
| **Role** | Reusable, structured collection of tasks/templates/vars |
| **Handler** | Task that runs once at end of play, only when notified |
| **Fact** | Auto-discovered info about a host (OS, IP, memory) |
| **Register** | Capture task output into a variable |
| **Vault** | AES-256 encryption for secrets — safe to commit to Git |
| **`become`** | Privilege escalation — run task as root via sudo |
| **`serial`** | Limit how many hosts run in parallel (rolling deploy) |
| **`delegate_to`** | Run a task on a different host than current target |
| **`check mode`** | Dry run — shows what would change without changing it |
| **FQCN** | Fully Qualified Collection Name — `ansible.builtin.apt` |
| **`import_tasks`** | Static include — loaded at parse time |
| **`include_tasks`** | Dynamic include — loaded at runtime |
| **`defaults/`** | Role defaults — low priority, easy to override |
| **`vars/`** | Role vars — high priority, hard to override |

---

## 🗂️ Folder Structure

```
ansible/
├── 00-ansible-index.md             ← You are here
├── 01-ansible-core-concepts.md
├── 02-ansible-playbooks-tasks.md
├── 03-ansible-roles-galaxy.md
├── 04-ansible-inventory.md
├── 05-ansible-vault.md
├── 06-ansible-jinja2.md
├── 07-ansible-best-practices.md
└── 08-ansible-interview-qa.md
```

---

## 🔗 How Ansible Connects to DevOps

| Ansible topic | Where it shows up |
|--------------|------------------|
| Playbooks & roles | Provisioning new servers, configuring services |
| Dynamic inventory | Auto-discovering EC2/GKE/AKS nodes |
| Vault | Managing secrets in CI/CD pipelines |
| Templates | Generating nginx, systemd, app config files dynamically |
| Rolling deploys (`serial`) | Zero-downtime deployments |
| `delegate_to` | Removing servers from load balancers before deploying |
| Galaxy | Reusing community roles instead of writing from scratch |
| Molecule | Testing infrastructure code like application code |
| CI/CD integration | Automatically applying config on merge to main |

---

*Notes are living documents — updated as I learn and build.*
