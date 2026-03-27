# 📖 Ansible Core Concepts & Theory

How Ansible works, why it exists, and the building blocks you need to understand before writing a single playbook.

> Ansible is the most widely used configuration management tool in DevOps. It's agentless, readable, and works over plain SSH — which is why it's everywhere.

---

## 📚 Table of Contents

- [1. What is Ansible?](#1-what-is-ansible)
- [2. How Ansible Works](#2-how-ansible-works)
- [3. Ansible vs Other Tools](#3-ansible-vs-other-tools)
- [4. Core Components](#4-core-components)
- [5. Inventory](#5-inventory)
- [6. Modules](#6-modules)
- [7. Playbooks](#7-playbooks)
- [8. Variables & Facts](#8-variables--facts)
- [9. Handlers](#9-handlers)
- [10. Ansible Configuration](#10-ansible-configuration)
- [11. Idempotency — The Most Important Concept](#11-idempotency--the-most-important-concept)
- [Key Terms Glossary](#key-terms-glossary)

---

## 1. What is Ansible?

Ansible is an **agentless automation tool** for:

- **Configuration management** — ensure servers are in a desired state
- **Application deployment** — deploy code across many servers
- **Orchestration** — coordinate multi-step processes across systems
- **Provisioning** — set up new servers from scratch

The key word is **agentless** — you don't install anything on the target servers. Ansible connects over SSH (Linux) or WinRM (Windows), runs tasks, and disconnects. That's it.

```
Your machine (control node)
        │
        │  SSH
        │
        ├──► web1.server.com
        ├──► web2.server.com
        └──► db1.server.com

No agents installed on target servers.
Ansible connects, does the work, disconnects.
```

---

## 2. How Ansible Works

### The execution flow

```
1. You run: ansible-playbook deploy.yml

2. Ansible reads:
   - Inventory (which servers to target)
   - Playbook (what to do)
   - Variables (how to customize)

3. For each target host:
   a. Opens SSH connection
   b. Copies a small Python script to /tmp on the remote host
   c. Executes the script
   d. Reads the result (JSON)
   e. Removes the script
   f. Closes SSH connection

4. Reports results: ok, changed, failed, skipped
```

### The control node

The machine you run Ansible from. Requires:
- Python 3.8+
- Ansible installed (`pip install ansible`)
- SSH access to target hosts

### The managed nodes (target hosts)

Machines Ansible configures. Require:
- Python 3 installed (most Linux distros have it)
- SSH server running
- User with sudo access (or root)
- **No Ansible installation needed**

### What happens on the remote host

```
Ansible control node
        │
        │  1. SSH connect
        ▼
Remote host (/tmp/ansible-tmp-*)
        │
        │  2. Upload module code (Python)
        │  3. Execute module
        │  4. Module outputs JSON result
        │  5. Ansible reads result
        │  6. Delete temp files
        │  7. SSH disconnect
```

---

## 3. Ansible vs Other Tools

| | Ansible | Puppet | Chef | Terraform |
|--|---------|--------|------|-----------|
| **Agent** | Agentless (SSH) | Agent required | Agent required | Agentless (API) |
| **Language** | YAML | DSL (Ruby-like) | Ruby DSL | HCL |
| **Learning curve** | Low | High | High | Medium |
| **Push vs Pull** | Push | Pull | Pull | Push |
| **Primary use** | Config mgmt, deployment | Config mgmt | Config mgmt | Infrastructure provisioning |
| **State** | No state by default | Has state | Has state | State file |

### Ansible vs Terraform — common interview question

| | Ansible | Terraform |
|--|---------|-----------|
| **What it does** | Configures software on existing servers | Creates and destroys infrastructure |
| **Example** | Install nginx, deploy app, manage config files | Create EC2 instances, VPCs, RDS databases |
| **State** | Stateless by default | Maintains state file |
| **Idempotency** | Module-level | Built into resource model |

**They complement each other** — Terraform provisions the servers, Ansible configures them.

```
Terraform creates EC2 instances
           │
           ▼
Ansible installs software, deploys app, configures services
```

---

## 4. Core Components

```
┌─────────────────────────────────────────────────────┐
│                    Ansible                           │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │Inventory │  │Playbooks │  │    Variables      │  │
│  │(who)     │  │(what)    │  │    (how)          │  │
│  └──────────┘  └──────────┘  └──────────────────┘  │
│                                                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────────────┐  │
│  │ Modules  │  │  Roles   │  │    Templates      │  │
│  │(actions) │  │(reuse)   │  │    (Jinja2)       │  │
│  └──────────┘  └──────────┘  └──────────────────┘  │
│                                                      │
│  ┌──────────┐  ┌──────────┐                         │
│  │ Handlers │  │  Vault   │                         │
│  │(triggers)│  │(secrets) │                         │
│  └──────────┘  └──────────┘                         │
└─────────────────────────────────────────────────────┘
```

| Component | What it is | Analogy |
|-----------|-----------|---------|
| **Inventory** | List of target hosts | Address book |
| **Playbook** | Ordered list of tasks | Recipe |
| **Task** | A single action (install package, copy file) | One step in the recipe |
| **Module** | The code that does the actual work | Kitchen tool |
| **Role** | Reusable collection of tasks, vars, templates | Meal kit |
| **Handler** | Task triggered by change notification | Alarm |
| **Variable** | Customizable value | Ingredient amount |
| **Template** | File with dynamic content (Jinja2) | Mad-lib |
| **Vault** | Encrypted secrets store | Safe |
| **Fact** | Auto-discovered info about a host | Reconnaissance |

---

## 5. Inventory

The inventory tells Ansible **which servers to manage** and how to connect to them.

### Static inventory (INI format)

```ini
# inventory/hosts.ini

# Ungrouped hosts
mail.example.com

# Group: webservers
[webservers]
web1.example.com
web2.example.com
192.168.1.100

# With connection variables
[webservers]
web1.example.com ansible_user=ubuntu ansible_port=22
web2.example.com ansible_user=ubuntu ansible_ssh_private_key_file=~/.ssh/web.pem

# Group: databases
[databases]
db1.example.com
db2.example.com

# Group of groups
[production:children]
webservers
databases

# Group variables
[webservers:vars]
ansible_user=ubuntu
http_port=80
max_connections=100
```

### Static inventory (YAML format — preferred)

```yaml
# inventory/hosts.yml
all:
  children:
    webservers:
      hosts:
        web1.example.com:
          ansible_user: ubuntu
          http_port: 80
        web2.example.com:
          ansible_user: ubuntu
          http_port: 80
      vars:
        max_connections: 100

    databases:
      hosts:
        db1.example.com:
          ansible_user: postgres
        db2.example.com:
          ansible_user: postgres
      vars:
        pg_port: 5432

    production:
      children:
        webservers:
        databases:
```

### Built-in inventory variables

| Variable | Description |
|----------|-------------|
| `ansible_host` | IP or hostname to connect to |
| `ansible_port` | SSH port (default: 22) |
| `ansible_user` | SSH user |
| `ansible_password` | SSH password (use Vault!) |
| `ansible_ssh_private_key_file` | Path to SSH private key |
| `ansible_become` | Enable privilege escalation |
| `ansible_become_user` | User to become (default: root) |
| `ansible_python_interpreter` | Python path on remote host |

### Inventory commands

```bash
# List all hosts in inventory
ansible-inventory -i inventory/ --list
ansible-inventory -i inventory/ --graph

# Ping all hosts (test connectivity)
ansible all -i inventory/ -m ping

# Ping specific group
ansible webservers -i inventory/ -m ping

# Run ad-hoc command on group
ansible webservers -i inventory/ -m command -a "uptime"
ansible all -i inventory/ -m shell -a "df -h"
```

---

## 6. Modules

Modules are the units of work in Ansible. Every task uses a module. There are thousands of built-in modules.

### Essential modules

```yaml
# Package management
- name: Install nginx
  ansible.builtin.apt:
    name: nginx
    state: present          # present, absent, latest

- name: Install multiple packages
  ansible.builtin.apt:
    name:
      - nginx
      - curl
      - git
    state: present
    update_cache: true      # run apt update first

# For RHEL/CentOS
- name: Install nginx on RedHat
  ansible.builtin.yum:
    name: nginx
    state: present

# Service management
- name: Start and enable nginx
  ansible.builtin.service:
    name: nginx
    state: started          # started, stopped, restarted, reloaded
    enabled: true           # start on boot

# File operations
- name: Create directory
  ansible.builtin.file:
    path: /opt/myapp
    state: directory        # directory, file, absent, link, touch
    owner: myapp
    group: myapp
    mode: '0755'

- name: Copy file to remote
  ansible.builtin.copy:
    src: files/nginx.conf
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: '0644'
    backup: true            # keep backup of old file

- name: Deploy template
  ansible.builtin.template:
    src: templates/nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    mode: '0644'

- name: Create symlink
  ansible.builtin.file:
    src: /opt/myapp-v1.2.3
    dest: /opt/myapp
    state: link

# User management
- name: Create user
  ansible.builtin.user:
    name: myapp
    shell: /bin/bash
    groups: docker
    append: true            # add to groups, don't replace

# Command execution
- name: Run a command
  ansible.builtin.command:
    cmd: /opt/myapp/bin/migrate
    chdir: /opt/myapp      # working directory

- name: Run a shell command (supports pipes, redirects)
  ansible.builtin.shell:
    cmd: "cat /etc/passwd | grep myapp | wc -l"

# Get/check remote info
- name: Check if file exists
  ansible.builtin.stat:
    path: /opt/myapp/bin/server
  register: app_binary

- name: Fail if binary missing
  ansible.builtin.fail:
    msg: "Application binary not found"
  when: not app_binary.stat.exists

# Line in file
- name: Add line to config
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: '^PasswordAuthentication'
    line: 'PasswordAuthentication no'
    state: present

# Fetch file from remote
- name: Download log file
  ansible.builtin.fetch:
    src: /var/log/app.log
    dest: ./logs/
    flat: false

# Wait for conditions
- name: Wait for port 8080 to open
  ansible.builtin.wait_for:
    port: 8080
    host: localhost
    timeout: 60

- name: Wait for file to appear
  ansible.builtin.wait_for:
    path: /tmp/ready
    timeout: 30
```

### Module return values

Every module returns a result you can register and use:

```yaml
- name: Get service status
  ansible.builtin.service_facts:

- name: Check if nginx is running
  ansible.builtin.debug:
    msg: "nginx state: {{ ansible_facts.services['nginx.service'].state }}"

- name: Run command and capture output
  ansible.builtin.command: whoami
  register: whoami_result

- name: Show the output
  ansible.builtin.debug:
    msg: "Running as: {{ whoami_result.stdout }}"

# Common register fields:
# result.stdout       — command output
# result.stderr       — error output
# result.rc           — return code
# result.changed      — whether something changed
# result.failed       — whether it failed
# result.stat.exists  — from stat module
```

---

## 7. Playbooks

A playbook is a YAML file containing one or more **plays**. Each play targets a group of hosts and runs a list of tasks.

### Minimal playbook structure

```yaml
---
# deploy.yml
- name: Deploy web application        # play name
  hosts: webservers                   # target group from inventory
  become: true                        # use sudo

  tasks:
    - name: Install nginx
      ansible.builtin.apt:
        name: nginx
        state: present

    - name: Start nginx
      ansible.builtin.service:
        name: nginx
        state: started
        enabled: true
```

### Multi-play playbook

```yaml
---
- name: Configure database servers
  hosts: databases
  become: true
  tasks:
    - name: Install PostgreSQL
      ansible.builtin.apt:
        name: postgresql
        state: present

- name: Configure web servers
  hosts: webservers
  become: true
  tasks:
    - name: Install nginx
      ansible.builtin.apt:
        name: nginx
        state: present
```

### Play-level options

```yaml
- name: My play
  hosts: webservers
  become: true                   # escalate to root
  become_user: root              # become this user
  gather_facts: true             # collect host facts (default: true)
  serial: 2                      # run on 2 hosts at a time (rolling deploy)
  max_fail_percentage: 20        # stop if >20% of hosts fail
  any_errors_fatal: true         # stop all hosts if any host fails
  environment:                   # set environment variables
    APP_ENV: production
  vars:                          # play-level variables
    app_port: 8080
  tags:                          # run with --tags
    - deploy
    - web
```

### Running playbooks

```bash
# Basic run
ansible-playbook -i inventory/ deploy.yml

# Limit to specific hosts or groups
ansible-playbook -i inventory/ deploy.yml --limit webservers
ansible-playbook -i inventory/ deploy.yml --limit web1.example.com

# Dry run (check mode — no changes made)
ansible-playbook -i inventory/ deploy.yml --check

# Show diff of changed files
ansible-playbook -i inventory/ deploy.yml --diff

# Verbose output
ansible-playbook -i inventory/ deploy.yml -v      # verbose
ansible-playbook -i inventory/ deploy.yml -vvv    # very verbose

# Run only tasks with specific tags
ansible-playbook -i inventory/ deploy.yml --tags "nginx,config"
ansible-playbook -i inventory/ deploy.yml --skip-tags "restart"

# Pass extra variables
ansible-playbook -i inventory/ deploy.yml -e "version=v1.2.3 env=production"
ansible-playbook -i inventory/ deploy.yml -e @vars/extra.yml

# Step through tasks one by one
ansible-playbook -i inventory/ deploy.yml --step
```

---

## 8. Variables & Facts

### Variable precedence (lowest to highest)

```
1.  role defaults          (roles/myrole/defaults/main.yml)
2.  inventory file vars    ([group:vars] in hosts.ini)
3.  inventory group_vars   (group_vars/all.yml)
4.  inventory host_vars    (host_vars/web1.yml)
5.  playbook group_vars
6.  playbook host_vars
7.  host facts             (gathered automatically)
8.  play vars              (vars: in playbook)
9.  task vars              (vars: in a task)
10. role vars              (roles/myrole/vars/main.yml)
11. extra vars (-e)        (highest priority — always wins)
```

### Facts — auto-discovered host information

```yaml
# Facts are gathered automatically before tasks run
# Access them via ansible_facts or ansible_ prefix

- name: Show OS info
  ansible.builtin.debug:
    msg: "OS: {{ ansible_facts['distribution'] }} {{ ansible_facts['distribution_version'] }}"

# Common facts
ansible_facts['hostname']          # hostname
ansible_facts['fqdn']              # fully qualified domain name
ansible_facts['default_ipv4']['address']  # primary IP
ansible_facts['os_family']         # Debian, RedHat, etc.
ansible_facts['distribution']      # Ubuntu, CentOS, etc.
ansible_facts['distribution_version']  # 22.04, 8, etc.
ansible_facts['memtotal_mb']       # total RAM in MB
ansible_facts['processor_count']   # number of CPUs
ansible_facts['mounts']            # mounted filesystems

# Gather facts manually
ansible all -i inventory/ -m setup                    # all facts
ansible all -i inventory/ -m setup -a "filter=ansible_distribution*"

# Disable fact gathering (speeds up playbook if you don't need facts)
- name: My play
  gather_facts: false
```

---

## 9. Handlers

Handlers are tasks that only run when **notified** by another task — and only if that task made a change.

```yaml
tasks:
  - name: Copy nginx config
    ansible.builtin.template:
      src: nginx.conf.j2
      dest: /etc/nginx/nginx.conf
    notify: Reload nginx         # trigger handler only if config changed

  - name: Copy SSL certificate
    ansible.builtin.copy:
      src: cert.pem
      dest: /etc/ssl/cert.pem
    notify: Reload nginx         # same handler, deduplicated

handlers:
  - name: Reload nginx
    ansible.builtin.service:
      name: nginx
      state: reloaded
```

**Key behavior:**
- Handlers run **once** at the end of the play — even if notified multiple times
- They only run if the notifying task **changed** something
- If the play fails, handlers don't run (use `--force-handlers` to override)

```yaml
# Force handlers to run even if play fails
- name: My play
  hosts: webservers
  force_handlers: true
  tasks: ...
  handlers: ...
```

---

## 10. Ansible Configuration

Ansible reads config from `ansible.cfg` (in order of precedence):
1. `ANSIBLE_CONFIG` environment variable
2. `./ansible.cfg` (current directory — most common)
3. `~/.ansible.cfg`
4. `/etc/ansible/ansible.cfg`

```ini
# ansible.cfg — project-level config
[defaults]
inventory       = inventory/           # default inventory path
remote_user     = ubuntu               # default SSH user
private_key_file = ~/.ssh/id_ed25519   # default SSH key
host_key_checking = false             # don't prompt for new host keys
retry_files_enabled = false           # don't create .retry files
stdout_callback = yaml                # prettier output
forks           = 20                  # parallel connections (default: 5)
timeout         = 30                  # SSH connection timeout
gathering       = smart               # only gather facts if not cached
fact_caching    = memory              # cache facts in memory

[privilege_escalation]
become          = true                # use sudo by default
become_method   = sudo
become_user     = root
become_ask_pass = false

[ssh_connection]
ssh_args        = -o ControlMaster=auto -o ControlPersist=60s
pipelining      = true                # speed up by reducing SSH connections
```

---

## 11. Idempotency — The Most Important Concept

Idempotency means running the same playbook multiple times produces the **same result** as running it once.

```
First run:
  Install nginx    → CHANGED (nginx wasn't installed)
  Start nginx      → CHANGED (nginx wasn't running)

Second run:
  Install nginx    → OK (already installed, nothing to do)
  Start nginx      → OK (already running, nothing to do)

Tenth run:
  Install nginx    → OK
  Start nginx      → OK
```

### Why it matters

- You can run playbooks safely at any time — they self-correct
- You can run the same playbook on new AND existing servers
- You can use it for drift detection — run and see what changed

### Modules are idempotent by design

Most Ansible modules check current state before making changes:

```yaml
# This only installs nginx if it's not already installed
- name: Install nginx
  apt:
    name: nginx
    state: present   # "ensure present" — not "install"

# This only starts nginx if it's not already running
- name: Start nginx
  service:
    name: nginx
    state: started   # "ensure started" — not "run start command"
```

### When idempotency breaks — watch out for these

```yaml
# BAD — shell/command modules are NOT idempotent
- name: Create user
  ansible.builtin.shell: useradd myapp   # fails on second run (user exists)

# GOOD — use the right module
- name: Create user
  ansible.builtin.user:
    name: myapp
    state: present   # idempotent — does nothing if user exists

# BAD — appends to file every run
- name: Add to file
  ansible.builtin.shell: echo "setting=value" >> /etc/app.conf

# GOOD — lineinfile is idempotent
- name: Add to file
  ansible.builtin.lineinfile:
    path: /etc/app.conf
    line: "setting=value"
    state: present

# When you must use shell/command — add creates/removes to make it idempotent
- name: Extract archive
  ansible.builtin.command:
    cmd: tar -xzf /tmp/app.tar.gz -C /opt/
    creates: /opt/app/bin/server    # skip if this file already exists
```

---

## Key Terms Glossary

| Term | Definition |
|------|-----------|
| **Control node** | Machine where Ansible is installed and run from |
| **Managed node** | Target server Ansible configures (no Ansible needed) |
| **Inventory** | List of managed hosts and how to connect to them |
| **Playbook** | YAML file containing plays — the main unit of Ansible automation |
| **Play** | Maps a group of hosts to a list of tasks |
| **Task** | A single action using a module |
| **Module** | The code that performs an action (install, copy, restart) |
| **Role** | Reusable, structured collection of tasks, vars, templates, handlers |
| **Handler** | Task that runs only when notified by a changed task |
| **Variable** | Customizable value used in tasks and templates |
| **Fact** | Auto-discovered information about a managed host |
| **Template** | Jinja2 file that generates dynamic config files |
| **Vault** | Ansible's encrypted secrets management |
| **Tag** | Label on a task to run selectively |
| **Register** | Capture the output of a task into a variable |
| **Idempotency** | Running the same playbook multiple times produces the same result |
| **Become** | Privilege escalation — running tasks as root via sudo |
| **Ad-hoc command** | One-off Ansible command without a playbook |
| **Galaxy** | Ansible's community hub for sharing roles |
| **Collections** | Bundled modules, roles, and plugins distributed via Galaxy |

---

*Next: [Playbooks & Tasks →](./02-playbooks-tasks.md) — writing real-world playbooks with variables, loops, conditionals, and error handling.*
