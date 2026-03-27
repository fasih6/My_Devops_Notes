# 🏗️ Best Practices & Project Structure

Production-ready Ansible project layout, coding standards, and patterns used by real teams.

---

## 📚 Table of Contents

- [1. Project Structure](#1-project-structure)
- [2. Playbook Best Practices](#2-playbook-best-practices)
- [3. Variable Best Practices](#3-variable-best-practices)
- [4. Role Best Practices](#4-role-best-practices)
- [5. Security Best Practices](#5-security-best-practices)
- [6. Performance Best Practices](#6-performance-best-practices)
- [7. Testing Ansible Code](#7-testing-ansible-code)
- [8. CI/CD with Ansible](#8-cicd-with-ansible)
- [Cheatsheet](#cheatsheet)

---

## 1. Project Structure

### Recommended layout

```
ansible/
├── ansible.cfg                    # project-level config
├── requirements.yml               # Galaxy roles and collections
├── site.yml                       # master playbook — imports all others
│
├── inventories/
│   ├── production/
│   │   ├── hosts.yml
│   │   ├── aws_ec2.yml            # dynamic inventory
│   │   └── group_vars/
│   │       ├── all/
│   │       │   ├── vars.yml       # non-sensitive vars
│   │       │   └── vault.yml      # encrypted secrets
│   │       ├── webservers.yml
│   │       └── databases.yml
│   └── staging/
│       ├── hosts.yml
│       └── group_vars/
│           └── all/
│               ├── vars.yml
│               └── vault.yml
│
├── playbooks/
│   ├── site.yml                   # full stack deploy
│   ├── webservers.yml             # web tier only
│   ├── databases.yml              # db tier only
│   └── maintenance/
│       ├── update-packages.yml
│       └── rotate-logs.yml
│
├── roles/
│   ├── common/                    # base config every server gets
│   ├── nginx/
│   ├── postgresql/
│   └── myapp/
│
└── .github/
    └── workflows/
        └── ansible-lint.yml
```

### ansible.cfg

```ini
[defaults]
inventory           = inventories/production/
roles_path          = roles
collections_paths   = ~/.ansible/collections
host_key_checking   = false
retry_files_enabled = false
stdout_callback     = yaml
forks               = 20
timeout             = 30
remote_user         = ubuntu
private_key_file    = ~/.ssh/id_ed25519
gathering           = smart
fact_caching        = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 86400

[privilege_escalation]
become              = true
become_method       = sudo
become_user         = root

[ssh_connection]
pipelining          = true
ssh_args            = -o ControlMaster=auto -o ControlPersist=60s -o StrictHostKeyChecking=no
```

### site.yml — master playbook

```yaml
---
# site.yml — run everything in the right order
- name: Apply common configuration
  ansible.builtin.import_playbook: playbooks/common.yml

- name: Configure load balancers
  ansible.builtin.import_playbook: playbooks/loadbalancers.yml

- name: Configure web servers
  ansible.builtin.import_playbook: playbooks/webservers.yml

- name: Configure database servers
  ansible.builtin.import_playbook: playbooks/databases.yml
```

---

## 2. Playbook Best Practices

### Use FQCN for modules

```yaml
# Bad — short module names (deprecated and ambiguous)
- apt:
    name: nginx
- copy:
    src: file.txt
    dest: /tmp/

# Good — Fully Qualified Collection Names
- ansible.builtin.apt:
    name: nginx
- ansible.builtin.copy:
    src: file.txt
    dest: /tmp/
```

### Always name your tasks

```yaml
# Bad
- apt:
    name: nginx
    state: present

# Good — descriptive names make output readable
- name: Install nginx web server
  ansible.builtin.apt:
    name: nginx
    state: present
```

### Use tags consistently

```yaml
# Apply tags at the play and task level
- name: Configure web servers
  hosts: webservers
  tags: [web, deploy]

  tasks:
    - name: Install nginx
      ansible.builtin.apt:
        name: nginx
      tags: [nginx, install, packages]

    - name: Deploy nginx config
      ansible.builtin.template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf
      tags: [nginx, config]
```

```bash
# Run specific parts
ansible-playbook site.yml --tags install
ansible-playbook site.yml --tags config --check
ansible-playbook site.yml --skip-tags restart
```

### Validate configs before reloading services

```yaml
- name: Deploy nginx config
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    validate: nginx -t -c %s        # validate BEFORE writing to dest
  notify: Reload nginx
```

### Use pre_tasks and post_tasks

```yaml
- name: Deploy application
  hosts: webservers
  become: true

  pre_tasks:
    - name: Ensure apt cache is fresh
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600

    - name: Check disk space
      ansible.builtin.assert:
        that: ansible_mounts | selectattr('mount', 'equalto', '/') | map(attribute='size_available') | first > 1073741824
        fail_msg: "Less than 1GB free on /"

  roles:
    - myapp

  post_tasks:
    - name: Verify app is responding
      ansible.builtin.uri:
        url: "http://localhost:{{ app_port }}/health"
        status_code: 200
      retries: 5
      delay: 5
```

---

## 3. Variable Best Practices

### Naming conventions

```yaml
# Use lowercase with underscores
app_port: 8080                    # good
appPort: 8080                     # bad (camelCase)
APP_PORT: 8080                    # bad (uppercase — looks like env var)

# Prefix role variables with role name (avoid collisions)
nginx_port: 80                    # good — clearly from nginx role
nginx_worker_processes: auto      # good
port: 80                          # bad — too generic, will clash

# Prefix vault variables with vault_
vault_db_password: "..."
vault_api_key: "..."

# Reference vault vars in plain vars
db_password: "{{ vault_db_password }}"
```

### Separate sensitive from non-sensitive

```
group_vars/production/
├── vars.yml       # commit freely
└── vault.yml      # encrypted — still safe to commit
```

```yaml
# vars.yml
db_host: db.example.com
db_port: 5432
db_name: myapp
db_user: myapp
db_password: "{{ vault_db_password }}"     # reference to vault var

# vault.yml (encrypted)
vault_db_password: SuperSecret123
```

### Don't hardcode environment-specific values in roles

```yaml
# Bad — hardcoded in role defaults
# roles/myapp/defaults/main.yml
db_host: db.production.example.com   # wrong! production-specific in a shared role

# Good — generic default, override in inventory
# roles/myapp/defaults/main.yml
db_host: localhost                    # safe default for local dev

# inventories/production/group_vars/all/vars.yml
db_host: db.production.example.com   # production override
```

---

## 4. Role Best Practices

### One role, one purpose

```
# Bad — "everything" role
roles/
└── server/
    tasks/
      main.yml   # installs nginx, postgres, app, configures firewall, etc.

# Good — focused roles
roles/
├── common/      # base OS config (NTP, users, packages)
├── nginx/       # web server only
├── postgresql/  # database only
├── myapp/       # application only
└── firewall/    # firewall rules only
```

### Use defaults, not vars, for user-facing settings

```yaml
# defaults/main.yml — users SHOULD override these
nginx_port: 80
nginx_ssl_enabled: false

# vars/main.yml — users should NOT override these
_nginx_config_dir: /etc/nginx   # internal implementation detail
_nginx_pid_file: /run/nginx.pid
```

### Always provide a README.md for roles

```markdown
# Role: nginx

Installs and configures nginx on Debian/Ubuntu.

## Requirements
None.

## Role Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `nginx_port` | `80` | HTTP port |
| `nginx_ssl_enabled` | `false` | Enable HTTPS |
| `nginx_worker_processes` | `auto` | Worker process count |

## Example Playbook

```yaml
- hosts: webservers
  roles:
    - role: nginx
      vars:
        nginx_ssl_enabled: true
        nginx_port: 443
```
```

---

## 5. Security Best Practices

```yaml
# Never run as root — use become only when needed
- name: Install package (needs root)
  ansible.builtin.apt:
    name: nginx
  become: true

- name: Deploy app config (runs as app user)
  ansible.builtin.template:
    src: app.conf.j2
    dest: /opt/myapp/config/app.conf
  become: true
  become_user: myapp     # become app user, not root

# Harden SSH config via Ansible
- name: Harden SSH configuration
  ansible.builtin.lineinfile:
    path: /etc/ssh/sshd_config
    regexp: "{{ item.regexp }}"
    line: "{{ item.line }}"
  loop:
    - { regexp: '^PermitRootLogin',        line: 'PermitRootLogin no' }
    - { regexp: '^PasswordAuthentication', line: 'PasswordAuthentication no' }
    - { regexp: '^X11Forwarding',          line: 'X11Forwarding no' }
  notify: Reload sshd

# Check mode — always test before applying
ansible-playbook site.yml --check --diff

# Diff shows exactly what will change
ansible-playbook site.yml --diff
```

---

## 6. Performance Best Practices

### Enable pipelining

```ini
# ansible.cfg
[ssh_connection]
pipelining = true    # reduces SSH connections per task — big speedup
```

### Increase forks (parallel connections)

```ini
[defaults]
forks = 20     # default is 5 — increase for large inventories
```

### Cache facts

```ini
[defaults]
gathering = smart                        # only gather if not cached
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts
fact_caching_timeout = 3600              # cache for 1 hour
```

### Skip fact gathering when not needed

```yaml
- name: Quick task — no facts needed
  hosts: webservers
  gather_facts: false      # saves ~1-2 seconds per host

  tasks:
    - name: Restart nginx
      ansible.builtin.service:
        name: nginx
        state: restarted
```

### Use async for slow tasks

```yaml
- name: Run slow migration
  ansible.builtin.command: /opt/myapp/bin/migrate
  async: 600       # max 10 minutes
  poll: 10         # check every 10 seconds
```

---

## 7. Testing Ansible Code

### ansible-lint — static analysis

```bash
# Install
pip install ansible-lint

# Run
ansible-lint site.yml
ansible-lint roles/nginx/

# Config — .ansible-lint
skip_list:
  - yaml[truthy]           # allow true/false instead of yes/no
  - name[casing]           # don't enforce task name casing
warn_list:
  - experimental
```

### Check mode + diff

```bash
# See what would change — no changes made
ansible-playbook site.yml --check --diff

# Check specific tags
ansible-playbook site.yml --check --diff --tags config
```

### Molecule — full role testing

Molecule tests roles by spinning up actual containers/VMs and running the role against them.

```bash
# Install
pip install molecule molecule-docker

# Initialize molecule in a role
cd roles/nginx
molecule init scenario --driver-name docker

# Test the role
molecule test      # full lifecycle: create → converge → verify → destroy

# Individual steps
molecule create    # spin up test containers
molecule converge  # run the role
molecule verify    # run tests
molecule destroy   # clean up
```

```yaml
# molecule/default/molecule.yml
driver:
  name: docker

platforms:
  - name: ubuntu-22
    image: geerlingguy/docker-ubuntu2204-ansible
    pre_build_image: true
  - name: ubuntu-20
    image: geerlingguy/docker-ubuntu2004-ansible
    pre_build_image: true

provisioner:
  name: ansible

verifier:
  name: ansible
```

```yaml
# molecule/default/verify.yml
---
- name: Verify nginx role
  hosts: all
  become: true
  tasks:
    - name: Check nginx is installed
      ansible.builtin.package_facts:
        manager: apt
    - name: Assert nginx is installed
      ansible.builtin.assert:
        that: "'nginx' in ansible_facts.packages"

    - name: Check nginx is running
      ansible.builtin.service_facts:
    - name: Assert nginx is running
      ansible.builtin.assert:
        that: ansible_facts.services['nginx.service'].state == 'running'

    - name: Check nginx responds
      ansible.builtin.uri:
        url: http://localhost
        status_code: 200
```

---

## 8. CI/CD with Ansible

### GitHub Actions workflow

```yaml
# .github/workflows/deploy.yml
name: Deploy with Ansible

on:
  push:
    branches: [main]

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Set up Python
        uses: actions/setup-python@v4
        with:
          python-version: '3.11'

      - name: Install dependencies
        run: pip install ansible ansible-lint

      - name: Run ansible-lint
        run: ansible-lint site.yml

  deploy:
    runs-on: ubuntu-latest
    needs: lint
    environment: production

    steps:
      - uses: actions/checkout@v4

      - name: Install Ansible
        run: pip install ansible boto3

      - name: Install Galaxy requirements
        run: ansible-galaxy install -r requirements.yml

      - name: Set up SSH key
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_PRIVATE_KEY }}" > ~/.ssh/id_ed25519
          chmod 600 ~/.ssh/id_ed25519

      - name: Create vault password file
        run: echo "${{ secrets.VAULT_PASSWORD }}" > .vault_pass

      - name: Run playbook (check mode first)
        run: |
          ansible-playbook \
            -i inventories/production/ \
            --vault-password-file .vault_pass \
            --check \
            site.yml

      - name: Run playbook
        run: |
          ansible-playbook \
            -i inventories/production/ \
            --vault-password-file .vault_pass \
            site.yml

      - name: Clean up
        if: always()
        run: rm -f .vault_pass ~/.ssh/id_ed25519
```

---

## Cheatsheet

```bash
# Lint
ansible-lint site.yml

# Check mode (dry run)
ansible-playbook site.yml --check --diff

# Run specific tags
ansible-playbook site.yml --tags "config,restart"

# Limit to specific hosts
ansible-playbook site.yml --limit "web1.example.com"

# Molecule testing
molecule test
molecule converge && molecule verify
```

```
Project checklist:
✅ ansible.cfg in project root
✅ Requirements in requirements.yml
✅ Separate inventories per environment
✅ Secrets encrypted with Vault
✅ Role vars prefixed with role name
✅ vault_ prefix on vault variables
✅ FQCN for all modules
✅ All tasks named
✅ ansible-lint passing
✅ README.md for every role
```

---

*Next: [Interview Q&A →](./08-ansible-interview-qa.md)*
