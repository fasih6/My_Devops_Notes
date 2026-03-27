# 🧩 Jinja2 Templating

Generate dynamic configuration files using Ansible's template engine.

---

## 📚 Table of Contents

- [1. What is Jinja2?](#1-what-is-jinja2)
- [2. Template Syntax](#2-template-syntax)
- [3. Variables in Templates](#3-variables-in-templates)
- [4. Filters](#4-filters)
- [5. Control Structures](#5-control-structures)
- [6. Tests](#6-tests)
- [7. Template Module](#7-template-module)
- [8. Real-World Template Examples](#8-real-world-template-examples)
- [Cheatsheet](#cheatsheet)

---

## 1. What is Jinja2?

Jinja2 is a Python templating engine used by Ansible to generate dynamic files. Instead of maintaining separate config files per environment, you write one template with variables.

```
nginx.conf.j2 (template)
    + group_vars/production.yml (variables)
    = /etc/nginx/nginx.conf (final file on server)
```

---

## 2. Template Syntax

```jinja2
{# This is a comment — not included in output #}

{{ variable }}              {# outputs a variable value #}

{% if condition %}          {# control statement (if, for, set) #}
{% endif %}

{{ variable | filter }}     {# apply a filter to a variable #}
```

---

## 3. Variables in Templates

```jinja2
{# Basic variable #}
server_name {{ domain }};

{# Nested dict #}
host={{ database.host }}
port={{ database.port }}

{# Default value if variable is undefined #}
timeout={{ request_timeout | default(30) }}

{# Conditional default #}
log_level={{ log_level | default('info') }}

{# Ansible facts #}
# Configured on {{ ansible_hostname }} ({{ ansible_default_ipv4.address }})
# OS: {{ ansible_distribution }} {{ ansible_distribution_version }}
# Generated: {{ ansible_date_time.iso8601 }}

{# Loop index in variable #}
worker_{{ loop.index }}_port={{ base_port + loop.index }}
```

---

## 4. Filters

Filters transform variable values. They're the most useful Jinja2 feature for DevOps templates.

```jinja2
{# String filters #}
{{ name | upper }}                  {# HELLO #}
{{ name | lower }}                  {# hello #}
{{ name | capitalize }}             {# Hello #}
{{ name | title }}                  {# Hello World #}
{{ name | trim }}                   {# remove whitespace #}
{{ name | replace('old', 'new') }}  {# string replace #}
{{ name | truncate(50) }}           {# max 50 chars #}

{# Number filters #}
{{ size | int }}                    {# convert to integer #}
{{ ratio | float }}                 {# convert to float #}
{{ size | abs }}                    {# absolute value #}
{{ memory | human_readable }}       {# 1.5 GB #}

{# List filters #}
{{ list | join(', ') }}             {# "a, b, c" #}
{{ list | sort }}                   {# sorted list #}
{{ list | unique }}                 {# deduplicated #}
{{ list | length }}                 {# count items #}
{{ list | first }}                  {# first item #}
{{ list | last }}                   {# last item #}
{{ list | min }}                    {# minimum value #}
{{ list | max }}                    {# maximum value #}
{{ list | flatten }}                {# flatten nested lists #}
{{ list | reverse | list }}         {# reverse a list #}

{# Dict filters #}
{{ dict | dict2items }}             {# convert dict to list of {key, value} #}
{{ items | items2dict }}            {# convert list of {key, value} to dict #}
{{ dict.keys() | list }}            {# list of keys #}
{{ dict.values() | list }}          {# list of values #}

{# Boolean / existence filters #}
{{ var | bool }}                    {# convert to boolean #}
{{ var | default('fallback') }}     {# use fallback if undefined #}
{{ var | default(omit) }}           {# omit argument entirely if undefined #}
{{ var | mandatory }}               {# fail if undefined #}

{# Path / file filters #}
{{ path | basename }}               {# /etc/nginx/nginx.conf → nginx.conf #}
{{ path | dirname }}                {# /etc/nginx/nginx.conf → /etc/nginx #}
{{ path | expanduser }}             {# ~/file → /home/user/file #}

{# Encoding filters #}
{{ secret | b64encode }}            {# base64 encode #}
{{ encoded | b64decode }}           {# base64 decode #}
{{ text | hash('sha256') }}         {# SHA256 hash #}
{{ password | password_hash('sha512') }}  {# password hash for /etc/shadow #}

{# JSON/YAML filters #}
{{ data | to_json }}                {# convert to JSON string #}
{{ data | to_nice_json }}           {# pretty JSON #}
{{ data | to_yaml }}                {# convert to YAML string #}
{{ json_string | from_json }}       {# parse JSON string #}
{{ yaml_string | from_yaml }}       {# parse YAML string #}

{# Networking filters #}
{{ ip | ipaddr }}                   {# validate/format IP address #}
{{ cidr | ipaddr('network') }}      {# get network address from CIDR #}
{{ ip | ipsubnet(24) }}             {# get /24 subnet containing IP #}

{# Chaining filters #}
{{ servers | map(attribute='hostname') | join(', ') }}
{{ packages | selectattr('enabled', 'true') | map(attribute='name') | list }}
```

---

## 5. Control Structures

### if / elif / else

```jinja2
{% if env == 'production' %}
log_level = error
max_connections = 1000
{% elif env == 'staging' %}
log_level = warn
max_connections = 100
{% else %}
log_level = debug
max_connections = 10
{% endif %}

{# Inline conditional #}
debug_mode = {{ 'true' if env == 'development' else 'false' }}

{# With variable check #}
{% if ssl_enabled is defined and ssl_enabled %}
ssl_certificate {{ ssl_cert }};
ssl_certificate_key {{ ssl_key }};
{% endif %}
```

### for loops

```jinja2
{# Loop over a list #}
{% for server in backend_servers %}
    server {{ server.host }}:{{ server.port }};
{% endfor %}

{# Loop with index #}
{% for item in items %}
{{ loop.index }}. {{ item }}        {# 1-based index #}
{{ loop.index0 }}. {{ item }}       {# 0-based index #}
{% endfor %}

{# Loop metadata #}
{% for item in items %}
{% if loop.first %}[START] {% endif %}
{{ item }}
{% if loop.last %}[END] {% endif %}
{% if not loop.last %}, {% endif %}
{% endfor %}

{# Loop over dict #}
{% for key, value in config.items() %}
{{ key }} = {{ value }}
{% endfor %}

{# Loop with condition #}
{% for server in servers if server.enabled %}
upstream {{ server.name }} {{ server.host }}:{{ server.port }};
{% endfor %}

{# Loop with else (runs if list is empty) #}
{% for server in servers %}
server {{ server }};
{% else %}
server localhost;
{% endfor %}
```

### set — define variables in templates

```jinja2
{% set max_workers = ansible_processor_count * 2 %}
worker_processes {{ max_workers }};

{% set db_url = 'postgresql://' + db_user + ':' + db_password + '@' + db_host + ':' + db_port|string + '/' + db_name %}
DATABASE_URL={{ db_url }}

{# Set a list #}
{% set enabled_modules = [] %}
{% for mod in modules %}
{% if mod.enabled %}{% set _ = enabled_modules.append(mod.name) %}{% endif %}
{% endfor %}
```

---

## 6. Tests

Tests check a condition and return true/false. Used in `when` conditions and templates:

```jinja2
{# In templates #}
{% if var is defined %}
{% if var is undefined %}
{% if var is none %}
{% if var is string %}
{% if var is number %}
{% if var is iterable %}
{% if var is mapping %}            {# is a dict #}
{% if var is sequence %}           {# is a list or string #}
{% if list is empty %}
{% if "pattern" is match(var) %}   {# regex match #}
{% if "sub" is in var %}

{# In playbook when conditions #}
when: var is defined
when: var is not defined
when: var is none
when: result is failed
when: result is succeeded
when: result is changed
when: result is skipped
```

---

## 7. Template Module

```yaml
- name: Deploy nginx config
  ansible.builtin.template:
    src: templates/nginx.conf.j2     # relative to role or playbook
    dest: /etc/nginx/nginx.conf
    owner: root
    group: root
    mode: '0644'
    backup: true                     # keep backup of previous version
    validate: nginx -t -c %s         # validate before deploying (%s = temp path)
  notify: Reload nginx

- name: Deploy app config
  ansible.builtin.template:
    src: app.conf.j2
    dest: /etc/myapp/app.conf
    owner: myapp
    group: myapp
    mode: '0640'
```

### Template search path

Ansible looks for templates in this order:
1. `templates/` directory in the current role
2. `templates/` directory next to the playbook
3. Path relative to the playbook

---

## 8. Real-World Template Examples

### nginx.conf.j2

```jinja2
{# roles/nginx/templates/nginx.conf.j2 #}
user {{ nginx_user | default('www-data') }};
worker_processes {{ nginx_worker_processes | default('auto') }};
error_log /var/log/nginx/error.log {{ nginx_error_log_level | default('warn') }};
pid /run/nginx.pid;

events {
    worker_connections {{ nginx_worker_connections | default(1024) }};
    multi_accept on;
}

http {
    sendfile on;
    tcp_nopush on;
    keepalive_timeout {{ nginx_keepalive_timeout | default(65) }};
    server_tokens {{ nginx_server_tokens | default('off') }};

    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent"';

    access_log /var/log/nginx/access.log main;

    {% if nginx_gzip_enabled | default(true) %}
    gzip on;
    gzip_vary on;
    gzip_min_length 1000;
    gzip_types text/plain text/css application/json application/javascript;
    {% endif %}

    include /etc/nginx/conf.d/*.conf;
}
```

### vhost.conf.j2

```jinja2
{# roles/nginx/templates/vhost.conf.j2 #}
upstream {{ item.name }}_backend {
{% for server in item.backend_servers %}
    server {{ server.host }}:{{ server.port }}{% if server.weight is defined %} weight={{ server.weight }}{% endif %};
{% endfor %}
}

server {
    listen 80;
    server_name {{ item.server_name }};

{% if item.ssl_enabled | default(false) %}
    listen 443 ssl;
    ssl_certificate {{ item.ssl_cert }};
    ssl_certificate_key {{ item.ssl_key }};
    ssl_protocols TLSv1.2 TLSv1.3;

    # Redirect HTTP to HTTPS
    if ($scheme != "https") {
        return 301 https://$host$request_uri;
    }
{% endif %}

    location / {
        proxy_pass http://{{ item.name }}_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout {{ item.proxy_timeout | default(60) }}s;
    }

{% if item.health_check is defined %}
    location {{ item.health_check.path | default('/health') }} {
        proxy_pass http://{{ item.name }}_backend;
        access_log off;
    }
{% endif %}
}
```

### systemd service template

```jinja2
{# templates/myapp.service.j2 #}
[Unit]
Description={{ app_name }} Application
Documentation=https://github.com/myorg/{{ app_name }}
After=network.target
{% if app_requires_db | default(false) %}
After=postgresql.service
Requires=postgresql.service
{% endif %}

[Service]
Type=simple
User={{ app_user }}
Group={{ app_group }}
WorkingDirectory={{ app_dir }}

Environment=APP_ENV={{ env }}
Environment=APP_PORT={{ app_port }}
Environment=LOG_LEVEL={{ log_level | default('info') }}
{% for key, value in app_env_vars.items() %}
Environment={{ key }}={{ value }}
{% endfor %}

ExecStart={{ app_dir }}/bin/{{ app_name }} \
    --port {{ app_port }} \
    --config {{ app_dir }}/config/app.conf

Restart=on-failure
RestartSec=10
StartLimitIntervalSec=300
StartLimitBurst=5

LimitNOFILE={{ app_max_open_files | default(65536) }}
NoNewPrivileges=true
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

### PostgreSQL pg_hba.conf template

```jinja2
{# templates/pg_hba.conf.j2 #}
# Generated by Ansible — do not edit manually
# {{ ansible_managed }}

# TYPE  DATABASE    USER        ADDRESS         METHOD
local   all         postgres                    peer
local   all         all                         md5
host    all         all         127.0.0.1/32    md5
host    all         all         ::1/128         md5

{% for rule in pg_hba_rules %}
{{ rule.type | ljust(8) }}{{ rule.database | ljust(12) }}{{ rule.user | ljust(12) }}{{ rule.address | ljust(16) }}{{ rule.method }}
{% endfor %}
```

### Environment file template (.env)

```jinja2
{# templates/app.env.j2 #}
# Application environment — generated by Ansible
# Host: {{ inventory_hostname }} | Date: {{ ansible_date_time.iso8601 }}

APP_NAME={{ app_name }}
APP_ENV={{ env }}
APP_PORT={{ app_port }}
APP_DEBUG={{ 'true' if env == 'development' else 'false' }}

# Database
DATABASE_URL=postgresql://{{ db_user }}:{{ db_password }}@{{ db_host }}:{{ db_port }}/{{ db_name }}
DATABASE_POOL_SIZE={{ db_pool_size | default(10) }}

# Redis
REDIS_URL=redis://{{ redis_host }}:{{ redis_port | default(6379) }}/{{ redis_db | default(0) }}

# AWS
AWS_REGION={{ aws_region | default('eu-central-1') }}
{% if aws_s3_bucket is defined %}
S3_BUCKET={{ aws_s3_bucket }}
{% endif %}

# Feature flags
{% for flag, enabled in feature_flags.items() %}
FEATURE_{{ flag | upper }}={{ 'true' if enabled else 'false' }}
{% endfor %}
```

---

## Cheatsheet

```jinja2
{# Variable output #}
{{ variable }}
{{ dict.key }} or {{ dict['key'] }}
{{ list[0] }}

{# Default value #}
{{ var | default('fallback') }}

{# Common filters #}
{{ text | upper | lower | trim }}
{{ list | join(', ') | sort | unique | length }}
{{ data | to_nice_json }}
{{ value | bool | int | float }}

{# Conditional #}
{% if condition %}...{% elif other %}...{% else %}...{% endif %}
{{ 'yes' if condition else 'no' }}

{# Loop #}
{% for item in list %}
{{ loop.index }} {{ item }}
{% endfor %}

{# Loop over dict #}
{% for key, value in dict.items() %}
{{ key }} = {{ value }}
{% endfor %}

{# Comment #}
{# this is a comment #}

{# ansible_managed — adds "do not edit" header #}
# {{ ansible_managed }}
```

---

*Next: [Best Practices & Project Structure →](./07-ansible-best-practices.md)*
