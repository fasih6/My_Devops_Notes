# 📋 Playbooks & Tasks

Writing real-world Ansible playbooks — variables, loops, conditionals, error handling, and task control.

---

## 📚 Table of Contents

- [1. Task Anatomy](#1-task-anatomy)
- [2. Variables](#2-variables)
- [3. Loops](#3-loops)
- [4. Conditionals](#4-conditionals)
- [5. Error Handling](#5-error-handling)
- [6. Task Control](#6-task-control)
- [7. Blocks](#7-blocks)
- [8. Tags](#8-tags)
- [9. Includes & Imports](#9-includes--imports)
- [10. Real-World Playbook Examples](#10-real-world-playbook-examples)
- [Cheatsheet](#cheatsheet)

---

## 1. Task Anatomy

Every task has a name, a module call, and optional control keywords:

```yaml
- name: Install and configure nginx           # human-readable description
  ansible.builtin.apt:                        # module (FQCN preferred)
    name: nginx                               # module arguments
    state: present
  become: true                                # escalate to root
  when: ansible_os_family == "Debian"        # conditional
  notify: Reload nginx                        # trigger handler on change
  register: nginx_install                     # capture result
  tags: [nginx, install]                      # run selectively
  ignore_errors: false                        # don't skip on failure
  retries: 3                                  # retry on failure
  delay: 5                                    # seconds between retries
  timeout: 30                                 # task timeout in seconds
  vars:                                       # task-level variable
    pkg_version: "1.24"
```

---

## 2. Variables

### Defining variables

```yaml
# In a playbook
- name: Deploy app
  hosts: webservers
  vars:
    app_name: myapp
    app_port: 8080
    app_version: "v1.2.3"
    app_dirs:
      - /opt/myapp
      - /var/log/myapp
      - /etc/myapp

  vars_files:
    - vars/common.yml
    - vars/production.yml

  tasks:
    - name: Create app directory
      ansible.builtin.file:
        path: "{{ app_dir }}"
        state: directory
```

```yaml
# vars/common.yml
app_user: myapp
app_group: myapp
log_level: info
max_connections: 100
```

### Using variables

```yaml
# Basic substitution
- name: Create directory
  ansible.builtin.file:
    path: "{{ app_dir }}"
    state: directory

# In strings
- name: Deploy version
  ansible.builtin.debug:
    msg: "Deploying {{ app_name }} version {{ app_version }} to {{ inventory_hostname }}"

# Nested variables (dict)
vars:
  database:
    host: db.example.com
    port: 5432
    name: myapp_db

- name: Show db host
  ansible.builtin.debug:
    msg: "DB: {{ database.host }}:{{ database.port }}/{{ database.name }}"
# OR
    msg: "DB: {{ database['host'] }}"

# Variable in variable name (avoid if possible)
- name: Set environment-specific var
  ansible.builtin.set_fact:
    current_db: "{{ vars['db_' + env + '_host'] }}"
```

### set_fact — dynamic variables

```yaml
- name: Get current date
  ansible.builtin.set_fact:
    deploy_date: "{{ ansible_date_time.date }}"
    backup_name: "backup-{{ inventory_hostname }}-{{ ansible_date_time.epoch }}.tar.gz"

- name: Set fact based on condition
  ansible.builtin.set_fact:
    is_primary: true
  when: inventory_hostname == groups['databases'][0]
```

### group_vars and host_vars

```
inventory/
├── hosts.yml
├── group_vars/
│   ├── all.yml              # applies to ALL hosts
│   ├── all/
│   │   ├── common.yml
│   │   └── vault.yml        # encrypted secrets
│   ├── webservers.yml       # applies to webservers group
│   └── databases.yml        # applies to databases group
└── host_vars/
    ├── web1.example.com.yml # applies to this host only
    └── db1.example.com.yml
```

```yaml
# group_vars/all.yml
ntp_server: pool.ntp.org
timezone: Europe/Berlin
ansible_python_interpreter: /usr/bin/python3

# group_vars/webservers.yml
nginx_worker_processes: auto
nginx_worker_connections: 1024
http_port: 80
https_port: 443

# host_vars/web1.example.com.yml
server_id: 1
backup_enabled: true
```

---

## 3. Loops

### loop — basic iteration

```yaml
# Loop over a list
- name: Install packages
  ansible.builtin.apt:
    name: "{{ item }}"
    state: present
  loop:
    - nginx
    - git
    - curl
    - htop

# Loop over a list variable
vars:
  packages:
    - nginx
    - git
    - curl

- name: Install packages
  ansible.builtin.apt:
    name: "{{ item }}"
    state: present
  loop: "{{ packages }}"

# Loop over dicts
- name: Create users
  ansible.builtin.user:
    name: "{{ item.name }}"
    groups: "{{ item.groups }}"
    shell: "{{ item.shell | default('/bin/bash') }}"
  loop:
    - { name: alice, groups: docker, shell: /bin/bash }
    - { name: bob,   groups: sudo }
    - { name: carol, groups: developers }

# Loop with index (loop_var)
- name: Create numbered files
  ansible.builtin.file:
    path: "/opt/app/worker-{{ item }}"
    state: directory
  loop: "{{ range(1, 5) | list }}"
  # Creates: worker-1, worker-2, worker-3, worker-4

# Loop with index tracking
- name: Show item and index
  ansible.builtin.debug:
    msg: "Item {{ ansible_loop.index }}/{{ ansible_loop.length }}: {{ item }}"
  loop: "{{ packages }}"
  loop_control:
    extended: true
    label: "{{ item }}"    # cleaner output (shows item name only)
```

### Nested loops (with_nested / product filter)

```yaml
- name: Create dirs for each user and environment
  ansible.builtin.file:
    path: "/opt/{{ item[0] }}/{{ item[1] }}"
    state: directory
  loop: "{{ ['alice', 'bob'] | product(['dev', 'prod']) | list }}"
```

### Loop over registered results

```yaml
- name: Get all log files
  ansible.builtin.find:
    paths: /var/log
    patterns: "*.log"
    size: 100m
  register: large_logs

- name: Compress large logs
  ansible.builtin.command:
    cmd: "gzip {{ item.path }}"
    creates: "{{ item.path }}.gz"
  loop: "{{ large_logs.files }}"
  loop_control:
    label: "{{ item.path }}"
```

---

## 4. Conditionals

### when — skip tasks based on conditions

```yaml
# Based on OS family
- name: Install nginx on Debian
  ansible.builtin.apt:
    name: nginx
    state: present
  when: ansible_os_family == "Debian"

- name: Install nginx on RedHat
  ansible.builtin.yum:
    name: nginx
    state: present
  when: ansible_os_family == "RedHat"

# Based on variable
- name: Enable debug logging
  ansible.builtin.lineinfile:
    path: /etc/app/config
    line: "log_level=debug"
  when: debug_mode | bool

# Based on registered result
- name: Check if app is installed
  ansible.builtin.stat:
    path: /opt/myapp/bin/server
  register: app_binary

- name: Install app (only if not present)
  ansible.builtin.unarchive:
    src: myapp.tar.gz
    dest: /opt/
  when: not app_binary.stat.exists

# Based on command result
- name: Check if service exists
  ansible.builtin.command: systemctl status myapp
  register: service_status
  failed_when: false           # don't fail even if service doesn't exist
  changed_when: false          # this task never changes anything

- name: Start service if it exists
  ansible.builtin.service:
    name: myapp
    state: started
  when: service_status.rc == 0

# Multiple conditions (AND)
- name: Only on production web servers
  ansible.builtin.debug:
    msg: "Production web server"
  when:
    - env == "production"
    - inventory_hostname in groups['webservers']

# OR condition
- name: Run on Ubuntu or Debian
  ansible.builtin.apt:
    name: nginx
    state: present
  when: >
    ansible_distribution == "Ubuntu" or
    ansible_distribution == "Debian"

# Checking if variable is defined
- name: Use custom port if set
  ansible.builtin.debug:
    msg: "Port: {{ custom_port }}"
  when: custom_port is defined

- name: Use default if not set
  ansible.builtin.debug:
    msg: "Port: {{ app_port | default(8080) }}"
```

---

## 5. Error Handling

### ignore_errors

```yaml
- name: Try to stop old service (may not exist)
  ansible.builtin.service:
    name: old-myapp
    state: stopped
  ignore_errors: true        # continue even if this fails
```

### failed_when — custom failure conditions

```yaml
- name: Run database migration
  ansible.builtin.command: /opt/myapp/bin/migrate
  register: migration_result
  failed_when:
    - migration_result.rc != 0
    - "'already up to date' not in migration_result.stdout"
  # Fails only if: non-zero exit AND output doesn't say "already up to date"

- name: Check disk usage
  ansible.builtin.command: df -h /
  register: disk_usage
  failed_when: "'100%' in disk_usage.stdout"
```

### changed_when — suppress false changes

```yaml
# Command modules always report "changed" — override this
- name: Check app version
  ansible.builtin.command: /opt/myapp/bin/server --version
  register: app_version
  changed_when: false         # this task never actually changes anything

- name: Run idempotent script
  ansible.builtin.command: /opt/scripts/configure.sh
  register: script_result
  changed_when: "'already configured' not in script_result.stdout"
```

### block / rescue / always

The Ansible equivalent of try/catch/finally:

```yaml
- name: Deploy application
  block:
    - name: Pull new image
      community.docker.docker_image:
        name: myapp:{{ version }}
        source: pull

    - name: Stop old container
      community.docker.docker_container:
        name: myapp
        state: stopped

    - name: Start new container
      community.docker.docker_container:
        name: myapp
        image: myapp:{{ version }}
        state: started

  rescue:
    - name: Deployment failed — rollback
      community.docker.docker_container:
        name: myapp
        image: myapp:{{ previous_version }}
        state: started

    - name: Alert the team
      ansible.builtin.uri:
        url: "{{ slack_webhook }}"
        method: POST
        body_format: json
        body:
          text: "Deployment of {{ version }} FAILED — rolled back to {{ previous_version }}"

  always:
    - name: Clean up temp files
      ansible.builtin.file:
        path: /tmp/deploy-artifacts
        state: absent
```

---

## 6. Task Control

### delegate_to — run task on different host

```yaml
# Run a task on localhost (the control node)
- name: Download release artifact
  ansible.builtin.get_url:
    url: "https://releases.example.com/app-{{ version }}.tar.gz"
    dest: /tmp/app.tar.gz
  delegate_to: localhost

# Run task on a specific host (e.g. load balancer)
- name: Remove server from load balancer
  community.general.haproxy:
    state: disabled
    host: "{{ inventory_hostname }}"
  delegate_to: loadbalancer.example.com
```

### run_once — run task on only one host

```yaml
# Only run once across all targeted hosts
- name: Run database migration (only on first web server)
  ansible.builtin.command: /opt/myapp/bin/migrate
  run_once: true
  delegate_to: "{{ groups['webservers'][0] }}"
```

### async — run tasks in background

```yaml
# Start a long-running task without waiting
- name: Start long backup job
  ansible.builtin.command: /opt/scripts/backup.sh
  async: 3600          # max time to wait (seconds)
  poll: 0              # don't wait — fire and forget

# Poll for completion later
- name: Start app build
  ansible.builtin.command: make build
  async: 600
  poll: 0
  register: build_job

- name: Wait for build to complete
  ansible.builtin.async_status:
    jid: "{{ build_job.ansible_job_id }}"
  register: job_result
  until: job_result.finished
  retries: 60
  delay: 10
```

### until — retry until condition is met

```yaml
- name: Wait for app to be healthy
  ansible.builtin.uri:
    url: http://localhost:8080/health
    status_code: 200
  register: health_check
  until: health_check.status == 200
  retries: 12             # try 12 times
  delay: 10               # wait 10 seconds between tries
  # Total wait: up to 2 minutes
```

---

## 7. Blocks

Blocks group tasks together and let you apply common settings:

```yaml
- name: Configure web server
  block:
    - name: Install nginx
      ansible.builtin.apt:
        name: nginx
        state: present

    - name: Copy config
      ansible.builtin.template:
        src: nginx.conf.j2
        dest: /etc/nginx/nginx.conf

    - name: Start nginx
      ansible.builtin.service:
        name: nginx
        state: started

  when: ansible_os_family == "Debian"   # applies to ALL tasks in block
  become: true                           # applies to ALL tasks in block
  tags: [nginx]                          # applies to ALL tasks in block
```

---

## 8. Tags

Tags let you run or skip specific parts of a playbook:

```yaml
tasks:
  - name: Install packages
    ansible.builtin.apt:
      name: "{{ item }}"
      state: present
    loop: "{{ packages }}"
    tags: [install, packages]

  - name: Deploy config
    ansible.builtin.template:
      src: app.conf.j2
      dest: /etc/app/app.conf
    tags: [config, deploy]

  - name: Restart service
    ansible.builtin.service:
      name: myapp
      state: restarted
    tags: [restart, deploy]
```

```bash
# Run only install tasks
ansible-playbook deploy.yml --tags install

# Run config and restart
ansible-playbook deploy.yml --tags "config,restart"

# Skip restart tasks
ansible-playbook deploy.yml --skip-tags restart

# Special tags
ansible-playbook deploy.yml --tags always   # tasks tagged 'always' always run
ansible-playbook deploy.yml --tags never    # tasks tagged 'never' only run when explicitly called
```

---

## 9. Includes & Imports

### import_tasks vs include_tasks

| | `import_tasks` | `include_tasks` |
|--|---------------|----------------|
| **Timing** | Static — loaded at parse time | Dynamic — loaded at runtime |
| **Tags** | Tags from parent apply | Must tag the include itself |
| **Conditionals** | `when` applied to each imported task | `when` controls whether to include at all |
| **Use when** | File is always needed | File included based on condition/variable |

```yaml
# import_tasks — static, always loaded
- name: Configure firewall
  ansible.builtin.import_tasks: tasks/firewall.yml

# include_tasks — dynamic, loaded at runtime
- name: Include OS-specific tasks
  ansible.builtin.include_tasks: "tasks/{{ ansible_os_family | lower }}.yml"
  # Can dynamically choose debian.yml or redhat.yml based on host

- name: Include tasks if needed
  ansible.builtin.include_tasks: tasks/ssl.yml
  when: ssl_enabled | bool
```

### import_playbook

```yaml
# site.yml — master playbook
- name: Import base configuration
  ansible.builtin.import_playbook: playbooks/base.yml

- name: Import web server config
  ansible.builtin.import_playbook: playbooks/webservers.yml

- name: Import database config
  ansible.builtin.import_playbook: playbooks/databases.yml
```

---

## 10. Real-World Playbook Examples

### Deploy a web application

```yaml
---
- name: Deploy MyApp
  hosts: webservers
  become: true
  vars:
    app_name: myapp
    app_version: "{{ version | default('latest') }}"
    app_dir: /opt/myapp
    app_user: myapp
    app_port: 8080

  pre_tasks:
    - name: Update apt cache
      ansible.builtin.apt:
        update_cache: true
        cache_valid_time: 3600
      when: ansible_os_family == "Debian"

  tasks:
    - name: Create app user
      ansible.builtin.user:
        name: "{{ app_user }}"
        shell: /bin/bash
        system: true
        create_home: false

    - name: Create app directories
      ansible.builtin.file:
        path: "{{ item }}"
        state: directory
        owner: "{{ app_user }}"
        mode: '0755'
      loop:
        - "{{ app_dir }}"
        - "{{ app_dir }}/logs"
        - "{{ app_dir }}/config"

    - name: Deploy application binary
      ansible.builtin.unarchive:
        src: "releases/{{ app_name }}-{{ app_version }}.tar.gz"
        dest: "{{ app_dir }}"
        owner: "{{ app_user }}"
        remote_src: false
      notify: Restart app

    - name: Deploy application config
      ansible.builtin.template:
        src: app.conf.j2
        dest: "{{ app_dir }}/config/app.conf"
        owner: "{{ app_user }}"
        mode: '0640'
      notify: Restart app

    - name: Deploy systemd unit file
      ansible.builtin.template:
        src: myapp.service.j2
        dest: /etc/systemd/system/myapp.service
        mode: '0644'
      notify:
        - Reload systemd
        - Restart app

    - name: Enable and start app
      ansible.builtin.systemd:
        name: myapp
        state: started
        enabled: true
        daemon_reload: true

    - name: Wait for app to be healthy
      ansible.builtin.uri:
        url: "http://localhost:{{ app_port }}/health"
        status_code: 200
      register: health
      until: health.status == 200
      retries: 10
      delay: 5

  post_tasks:
    - name: Verify deployment
      ansible.builtin.debug:
        msg: "{{ app_name }} {{ app_version }} deployed successfully on {{ inventory_hostname }}"

  handlers:
    - name: Reload systemd
      ansible.builtin.systemd:
        daemon_reload: true

    - name: Restart app
      ansible.builtin.systemd:
        name: myapp
        state: restarted
```

### Rolling deployment (zero downtime)

```yaml
---
- name: Rolling deployment
  hosts: webservers
  become: true
  serial: 1              # one server at a time
  max_fail_percentage: 0 # stop if any server fails

  tasks:
    - name: Remove from load balancer
      community.general.haproxy:
        state: disabled
        host: "{{ inventory_hostname }}"
        socket: /var/run/haproxy/admin.sock
      delegate_to: "{{ groups['loadbalancers'][0] }}"

    - name: Wait for connections to drain
      ansible.builtin.wait_for:
        timeout: 30

    - name: Deploy new version
      ansible.builtin.include_tasks: tasks/deploy.yml

    - name: Verify health
      ansible.builtin.uri:
        url: http://localhost:8080/health
        status_code: 200
      retries: 10
      delay: 5

    - name: Add back to load balancer
      community.general.haproxy:
        state: enabled
        host: "{{ inventory_hostname }}"
        socket: /var/run/haproxy/admin.sock
      delegate_to: "{{ groups['loadbalancers'][0] }}"
```

---

## Cheatsheet

```yaml
# Task with all common options
- name: Task name
  module_name:
    arg: value
  become: true
  when: condition
  register: result
  notify: handler_name
  tags: [tag1, tag2]
  ignore_errors: true
  retries: 3
  delay: 5
  loop: "{{ list }}"

# Conditionals
when: ansible_os_family == "Debian"
when: variable is defined
when: not variable | bool
when: "'string' in other_string"
when: result.rc == 0

# Loops
loop: [item1, item2, item3]
loop: "{{ my_list }}"
loop_control:
  label: "{{ item.name }}"

# Error handling
failed_when: result.rc != 0
changed_when: false
ignore_errors: true

# Variable defaults
"{{ var | default('fallback') }}"
"{{ var | default(omit) }}"      # omit argument if var undefined
```

---

*Next: [Roles & Galaxy →](./03-ansible-roles-galaxy.md)*
