# 🎭 Roles & Galaxy

Structure reusable Ansible code with roles — and use the community's work via Ansible Galaxy.

---

## 📚 Table of Contents

- [1. What is a Role?](#1-what-is-a-role)
- [2. Role Directory Structure](#2-role-directory-structure)
- [3. Creating a Role](#3-creating-a-role)
- [4. Using Roles in Playbooks](#4-using-roles-in-playbooks)
- [5. Role Variables & Defaults](#5-role-variables--defaults)
- [6. Role Dependencies](#6-role-dependencies)
- [7. Ansible Galaxy](#7-ansible-galaxy)
- [8. Collections](#8-collections)
- [9. Real-World Role Example — nginx](#9-real-world-role-example--nginx)
- [Cheatsheet](#cheatsheet)

---

## 1. What is a Role?

A role is a **standardized, reusable unit of Ansible automation**. Instead of copying tasks between playbooks, you package them into a role that can be shared and reused.

```
Without roles:                    With roles:
─────────────                     ─────────────
site.yml (500 lines)              site.yml (20 lines)
                                  roles/
                                    nginx/
                                    postgresql/
                                    myapp/
```

A role is just a **directory with a specific structure**. Ansible automatically loads tasks, variables, templates, and handlers from the right subdirectories.

---

## 2. Role Directory Structure

```
roles/
└── nginx/                         # role name
    ├── tasks/
    │   ├── main.yml               # entry point — always loaded
    │   ├── install.yml            # imported by main.yml
    │   └── configure.yml          # imported by main.yml
    ├── handlers/
    │   └── main.yml               # handlers for this role
    ├── templates/
    │   ├── nginx.conf.j2          # Jinja2 templates
    │   └── vhost.conf.j2
    ├── files/
    │   ├── nginx-logrotate        # static files (no templating)
    │   └── ssl/
    ├── vars/
    │   └── main.yml               # role variables (high priority)
    ├── defaults/
    │   └── main.yml               # default values (lowest priority — override easily)
    ├── meta/
    │   └── main.yml               # role metadata and dependencies
    ├── tests/
    │   ├── inventory
    │   └── test.yml               # test playbook for the role
    └── README.md
```

### What each directory is for

| Directory | Purpose | Priority |
|-----------|---------|---------|
| `tasks/` | The work the role does | — |
| `handlers/` | Triggered by notify — scoped to role | — |
| `templates/` | Jinja2 template files (.j2) | — |
| `files/` | Static files to copy verbatim | — |
| `vars/` | Role variables — hard to override | High |
| `defaults/` | Default values — easy to override | Lowest |
| `meta/` | Role info, Galaxy metadata, dependencies | — |
| `tests/` | Test playbook for the role | — |

**`defaults/` vs `vars/`:**
- Use `defaults/` for values you *expect* users to override (ports, paths, feature flags)
- Use `vars/` for values that are internal to the role and shouldn't change

---

## 3. Creating a Role

```bash
# Create role skeleton automatically
ansible-galaxy role init nginx
ansible-galaxy role init --offline nginx   # without contacting Galaxy

# Or manually create the structure
mkdir -p roles/nginx/{tasks,handlers,templates,files,vars,defaults,meta}
touch roles/nginx/{tasks,handlers,vars,defaults,meta}/main.yml
```

### tasks/main.yml

```yaml
---
# roles/nginx/tasks/main.yml
- name: Import install tasks
  ansible.builtin.import_tasks: install.yml

- name: Import configure tasks
  ansible.builtin.import_tasks: configure.yml

- name: Import ssl tasks
  ansible.builtin.import_tasks: ssl.yml
  when: nginx_ssl_enabled | bool
```

### tasks/install.yml

```yaml
---
# roles/nginx/tasks/install.yml
- name: Install nginx
  ansible.builtin.package:
    name: nginx
    state: "{{ nginx_package_state }}"

- name: Create nginx directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    owner: root
    group: root
    mode: '0755'
  loop:
    - "{{ nginx_conf_dir }}"
    - "{{ nginx_vhost_dir }}"
    - "{{ nginx_log_dir }}"
```

### handlers/main.yml

```yaml
---
# roles/nginx/handlers/main.yml
- name: Reload nginx
  ansible.builtin.service:
    name: nginx
    state: reloaded

- name: Restart nginx
  ansible.builtin.service:
    name: nginx
    state: restarted

- name: Test nginx config
  ansible.builtin.command: nginx -t
  changed_when: false
```

### defaults/main.yml

```yaml
---
# roles/nginx/defaults/main.yml
nginx_package_state: present
nginx_service_state: started
nginx_service_enabled: true

nginx_conf_dir: /etc/nginx
nginx_vhost_dir: /etc/nginx/conf.d
nginx_log_dir: /var/log/nginx

nginx_worker_processes: auto
nginx_worker_connections: 1024
nginx_keepalive_timeout: 65

nginx_ssl_enabled: false
nginx_ssl_cert: ""
nginx_ssl_key: ""

nginx_vhosts: []
```

### meta/main.yml

```yaml
---
# roles/nginx/meta/main.yml
galaxy_info:
  role_name: nginx
  author: fasih
  description: Install and configure nginx
  license: MIT
  min_ansible_version: "2.12"
  platforms:
    - name: Ubuntu
      versions:
        - "20.04"
        - "22.04"
    - name: Debian
      versions:
        - "11"
        - "12"
  galaxy_tags:
    - nginx
    - web
    - proxy

dependencies:
  - role: common           # this role requires 'common' role first
```

---

## 4. Using Roles in Playbooks

```yaml
# Simple role usage
- name: Configure web servers
  hosts: webservers
  become: true
  roles:
    - nginx
    - myapp

# Role with variables
- name: Configure web servers
  hosts: webservers
  become: true
  roles:
    - role: nginx
      vars:
        nginx_worker_processes: 4
        nginx_ssl_enabled: true

    - role: myapp
      vars:
        app_port: 9090

# Mixing roles and tasks
- name: Configure web servers
  hosts: webservers
  become: true

  pre_tasks:
    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: true

  roles:
    - common
    - nginx

  tasks:
    - name: Additional custom task
      ansible.builtin.debug:
        msg: "Roles complete"

  post_tasks:
    - name: Verify setup
      ansible.builtin.uri:
        url: http://localhost/health

# include_role — dynamic role inclusion
- name: Include role conditionally
  ansible.builtin.include_role:
    name: ssl
  when: ssl_enabled | bool

# import_role — static role inclusion
- name: Import role
  ansible.builtin.import_role:
    name: common
  tags: [common]
```

### Role execution order

```
pre_tasks
    │
    ▼
roles (in order listed)
    │
    ▼
tasks
    │
    ▼
post_tasks
    │
    ▼
handlers (run at end, once)
```

---

## 5. Role Variables & Defaults

```yaml
# defaults/main.yml — users should override these
app_port: 8080
app_debug: false
app_log_level: info

# vars/main.yml — internal role values, don't override
_app_config_dir: /etc/myapp
_app_systemd_dir: /etc/systemd/system

# Accessing in templates and tasks
- name: Configure app
  ansible.builtin.template:
    src: app.conf.j2
    dest: "{{ _app_config_dir }}/app.conf"
```

### Override defaults from playbook

```yaml
# Method 1 — vars in role call
roles:
  - role: myapp
    vars:
      app_port: 9090
      app_log_level: debug

# Method 2 — group_vars
# group_vars/webservers.yml
app_port: 9090

# Method 3 — host_vars
# host_vars/web1.example.com.yml
app_port: 9091

# Method 4 — extra vars (highest priority)
ansible-playbook site.yml -e "app_port=9092"
```

---

## 6. Role Dependencies

Declare roles that must run before your role in `meta/main.yml`:

```yaml
# roles/myapp/meta/main.yml
dependencies:
  - role: common
  - role: nginx
    vars:
      nginx_ssl_enabled: true
  - role: postgresql
    vars:
      pg_port: 5432
```

When you apply `myapp`, Ansible automatically applies `common`, `nginx`, and `postgresql` first.

---

## 7. Ansible Galaxy

Galaxy is Ansible's community hub for sharing and downloading roles and collections.

### Installing roles from Galaxy

```bash
# Install a role
ansible-galaxy role install geerlingguy.nginx
ansible-galaxy role install geerlingguy.postgresql

# Install specific version
ansible-galaxy role install geerlingguy.nginx,3.1.0

# Install to specific path
ansible-galaxy role install geerlingguy.nginx -p roles/

# Install from requirements file (best practice)
ansible-galaxy role install -r requirements.yml
```

### requirements.yml — managing dependencies

```yaml
# requirements.yml
---
roles:
  # From Galaxy
  - name: geerlingguy.nginx
    version: "3.1.0"

  - name: geerlingguy.postgresql
    version: "3.3.0"

  # From GitHub
  - name: my-custom-nginx
    src: https://github.com/myorg/ansible-nginx
    version: main

  # From a tarball
  - name: offline-role
    src: https://example.com/roles/offline-role.tar.gz

collections:
  - name: community.general
    version: ">=6.0.0"
  - name: community.docker
    version: "3.4.0"
  - name: amazon.aws
    version: "6.0.0"
```

```bash
# Install everything from requirements.yml
ansible-galaxy install -r requirements.yml

# Install both roles and collections
ansible-galaxy role install -r requirements.yml
ansible-galaxy collection install -r requirements.yml

# Or install both at once
ansible-galaxy install -r requirements.yml --roles-path ./roles
```

### Commonly used Galaxy roles

```yaml
# Jeff Geerling's roles — production quality, widely used
- geerlingguy.nginx
- geerlingguy.postgresql
- geerlingguy.mysql
- geerlingguy.redis
- geerlingguy.docker
- geerlingguy.java
- geerlingguy.nodejs
- geerlingguy.firewall
```

### Publishing your own role to Galaxy

```bash
# Login to Galaxy
ansible-galaxy login

# Import your role (GitHub repo must be named ansible-<rolename>)
ansible-galaxy role import myusername ansible-nginx

# Setup your meta/main.yml with galaxy_info first
```

---

## 8. Collections

Collections bundle modules, roles, plugins, and playbooks into a distributable package. They're the modern replacement for standalone roles.

```bash
# Install a collection
ansible-galaxy collection install community.general
ansible-galaxy collection install community.docker
ansible-galaxy collection install amazon.aws
ansible-galaxy collection install google.cloud
ansible-galaxy collection install azure.azcollection

# List installed collections
ansible-galaxy collection list

# Install from requirements.yml (recommended)
ansible-galaxy collection install -r requirements.yml
```

### Using collection modules

```yaml
# Without collection (old way)
- name: Manage Docker container
  docker_container:
    name: myapp
    image: myapp:latest

# With FQCN — Fully Qualified Collection Name (correct way)
- name: Manage Docker container
  community.docker.docker_container:
    name: myapp
    image: myapp:latest

- name: Create AWS EC2 instance
  amazon.aws.ec2_instance:
    name: my-server
    instance_type: t3.micro
    image_id: ami-12345678
    region: eu-central-1
```

### Collection directory structure (if building your own)

```
my_namespace/my_collection/
├── galaxy.yml
├── README.md
├── plugins/
│   ├── modules/
│   └── inventory/
├── roles/
│   └── my_role/
└── playbooks/
    └── site.yml
```

---

## 9. Real-World Role Example — nginx

A complete, production-ready nginx role:

```
roles/nginx/
├── tasks/
│   ├── main.yml
│   ├── install.yml
│   └── vhosts.yml
├── handlers/
│   └── main.yml
├── templates/
│   ├── nginx.conf.j2
│   └── vhost.conf.j2
├── defaults/
│   └── main.yml
└── meta/
    └── main.yml
```

```yaml
# defaults/main.yml
nginx_user: www-data
nginx_worker_processes: auto
nginx_worker_connections: 1024
nginx_keepalive_timeout: 65
nginx_server_tokens: "off"
nginx_ssl_enabled: false
nginx_vhosts: []
```

```yaml
# tasks/main.yml
---
- name: Install nginx
  ansible.builtin.import_tasks: install.yml

- name: Configure vhosts
  ansible.builtin.import_tasks: vhosts.yml
  when: nginx_vhosts | length > 0
```

```yaml
# tasks/install.yml
---
- name: Install nginx package
  ansible.builtin.apt:
    name: nginx
    state: present
    update_cache: true
  notify: Restart nginx

- name: Deploy nginx.conf
  ansible.builtin.template:
    src: nginx.conf.j2
    dest: /etc/nginx/nginx.conf
    mode: '0644'
    validate: nginx -t -c %s
  notify: Reload nginx

- name: Enable and start nginx
  ansible.builtin.service:
    name: nginx
    state: started
    enabled: true
```

```yaml
# tasks/vhosts.yml
---
- name: Deploy vhost configs
  ansible.builtin.template:
    src: vhost.conf.j2
    dest: "/etc/nginx/conf.d/{{ item.name }}.conf"
    mode: '0644'
  loop: "{{ nginx_vhosts }}"
  notify: Reload nginx

- name: Remove unconfigured vhosts
  ansible.builtin.file:
    path: "/etc/nginx/conf.d/{{ item }}"
    state: absent
  loop: "{{ nginx_vhosts_remove | default([]) }}"
  notify: Reload nginx
```

```jinja2
{# templates/nginx.conf.j2 #}
user {{ nginx_user }};
worker_processes {{ nginx_worker_processes }};
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections {{ nginx_worker_connections }};
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;
    server_tokens {{ nginx_server_tokens }};
    keepalive_timeout {{ nginx_keepalive_timeout }};

    include /etc/nginx/conf.d/*.conf;
}
```

```yaml
# Using the role in a playbook
- name: Configure web servers
  hosts: webservers
  become: true
  roles:
    - role: nginx
      vars:
        nginx_worker_processes: 4
        nginx_vhosts:
          - name: myapp
            server_name: myapp.example.com
            proxy_pass: http://localhost:8080
          - name: api
            server_name: api.example.com
            proxy_pass: http://localhost:9090
```

---

## Cheatsheet

```bash
# Create role
ansible-galaxy role init myrole

# Install from Galaxy
ansible-galaxy role install geerlingguy.nginx
ansible-galaxy install -r requirements.yml

# Install collection
ansible-galaxy collection install community.docker

# List installed
ansible-galaxy role list
ansible-galaxy collection list
```

```yaml
# Use role in playbook
roles:
  - common
  - role: nginx
    vars:
      nginx_port: 443

# Role defaults (easy to override)
# defaults/main.yml
port: 8080

# Role vars (hard to override)
# vars/main.yml
_internal_path: /opt/app

# dependencies in meta/main.yml
dependencies:
  - role: common
  - role: nginx
```

---

*Next: [Inventory Management →](./04-ansible-inventory.md)*
