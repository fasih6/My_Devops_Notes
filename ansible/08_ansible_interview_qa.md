# 🎯 Ansible Interview Q&A

Real questions asked in DevOps interviews — with complete answers.

---

## 📚 Table of Contents

- [🔥 Core Concepts](#-core-concepts)
- [📋 Playbooks & Tasks](#-playbooks--tasks)
- [🎭 Roles & Structure](#-roles--structure)
- [🔐 Security & Vault](#-security--vault)
- [⚡ Performance & Scaling](#-performance--scaling)
- [🔥 Scenario-Based Questions](#-scenario-based-questions)
- [🧠 Advanced Questions](#-advanced-questions)
- [💬 Questions to Ask the Interviewer](#-questions-to-ask-the-interviewer)

---

## 🔥 Core Concepts

---

**Q: What is Ansible and how does it work?**

Ansible is an agentless IT automation tool. It works by connecting to managed nodes over SSH, copying a small Python script, executing it, reading the JSON result, and cleaning up — all without installing anything on the target server.

You write your desired state in YAML playbooks. Ansible reads the inventory (who to configure), the playbook (what to do), and variables (how to customize), then executes tasks in order.

---

**Q: What does agentless mean, and what are its advantages?**

Agentless means Ansible doesn't require any software installed on the managed nodes. It uses SSH (Linux) or WinRM (Windows) — protocols already present on servers.

Advantages: no agent maintenance, no agent version conflicts, works immediately on any accessible server, lower attack surface (no agent listening on a port).

Disadvantage: requires SSH access from the control node, slightly slower than agent-based tools for very large fleets.

---

**Q: What is idempotency and why does it matter?**

Idempotency means running the same playbook multiple times produces the same result as running it once. If nginx is already installed, `apt: name=nginx state=present` does nothing — it doesn't reinstall it.

This matters because:
- You can safely rerun playbooks to fix drift
- You can apply the same playbook to new AND existing servers
- You can detect configuration drift by checking what changed

Most Ansible modules are idempotent by design. `shell` and `command` modules are not — which is why you should use dedicated modules whenever possible, and add `creates`/`removes` guards when you must use `command`.

---

**Q: What is the difference between a task, a play, and a playbook?**

A **task** is a single action using one module (install a package, copy a file).

A **play** maps a group of hosts to a list of tasks. It defines who (`hosts:`) and what (`tasks:`).

A **playbook** is a YAML file containing one or more plays. It's the main unit of Ansible automation.

```yaml
# This is a playbook
- name: This is a play            # play
  hosts: webservers
  tasks:
    - name: This is a task        # task
      ansible.builtin.apt:
        name: nginx
```

---

**Q: What is the difference between `command` and `shell` modules?**

| | `command` | `shell` |
|--|-----------|---------|
| Executes | Binary directly | Through /bin/sh |
| Supports | Plain commands | Pipes, redirects, variables, &&, \|\| |
| Safer | Yes (no shell injection) | Less safe |
| Example | `ls /tmp` | `cat /etc/passwd \| grep root` |

Use `command` by default. Use `shell` only when you need pipes, redirects, or shell features. Neither is idempotent — use `creates`/`removes` to add idempotency.

---

**Q: What are handlers and when do they run?**

Handlers are tasks that only run when **notified** by another task that made a change. They run **once** at the end of the play — even if notified multiple times.

Classic use case: multiple tasks can modify nginx config files, all notify "Reload nginx", but nginx only reloads once at the end.

If a play fails mid-way, handlers don't run (use `force_handlers: true` or `--force-handlers` to override).

---

**Q: What is the difference between `import_tasks` and `include_tasks`?**

| | `import_tasks` | `include_tasks` |
|--|---------------|----------------|
| **Load time** | Parse time (static) | Runtime (dynamic) |
| **Tags** | Parent tags apply to imported tasks | Must tag the include statement |
| **Conditionals** | `when` applies to each task inside | `when` controls whether to include at all |
| **Use when** | File is always needed | File chosen dynamically at runtime |

```yaml
# Static — always loads debian.yml and redhat.yml at parse time
import_tasks: debian.yml

# Dynamic — decides which file to load at runtime based on OS
include_tasks: "{{ ansible_os_family | lower }}.yml"
```

---

## 📋 Playbooks & Tasks

---

**Q: How do you handle errors in Ansible?**

Three main approaches:

1. **`ignore_errors: true`** — continue even if task fails
2. **`failed_when`** — custom failure condition (e.g., fail only if output contains "ERROR")
3. **`block/rescue/always`** — try/catch/finally equivalent

```yaml
block:
  - name: Try deployment
    ... 
rescue:
  - name: Rollback on failure
    ...
always:
  - name: Always clean up
    ...
```

---

**Q: What is `register` and how do you use it?**

`register` captures the output of a task into a variable for use in subsequent tasks.

```yaml
- name: Check if app binary exists
  ansible.builtin.stat:
    path: /opt/myapp/bin/server
  register: app_binary

- name: Install app only if missing
  ansible.builtin.unarchive:
    src: myapp.tar.gz
    dest: /opt/
  when: not app_binary.stat.exists
```

Common fields: `stdout`, `stderr`, `rc` (return code), `changed`, `failed`, `stat.exists`.

---

**Q: How do you run a task on only one host out of a group?**

Use `run_once: true`:

```yaml
- name: Run database migration once
  ansible.builtin.command: /opt/myapp/bin/migrate
  run_once: true
  delegate_to: "{{ groups['webservers'][0] }}"
```

Or `serial: 1` at the play level to process one host at a time (useful for rolling deployments).

---

**Q: How do you do a rolling deployment in Ansible?**

Use `serial` to limit how many hosts are updated at a time:

```yaml
- name: Rolling deployment
  hosts: webservers
  serial: 1              # one at a time
  max_fail_percentage: 0 # stop if any host fails

  tasks:
    - name: Remove from load balancer
      ...
    - name: Deploy new version
      ...
    - name: Add back to load balancer
      ...
```

`serial: 2` updates 2 at a time, `serial: "25%"` updates 25% at a time.

---

## 🎭 Roles & Structure

---

**Q: What is the difference between `defaults/main.yml` and `vars/main.yml` in a role?**

| | `defaults/main.yml` | `vars/main.yml` |
|--|--------------------|-|
| **Priority** | Lowest (easily overridden) | High (hard to override) |
| **Purpose** | User-facing defaults | Internal implementation values |
| **Override** | By group_vars, host_vars, extra vars | Only by extra vars (-e) |

Use `defaults` for values you expect users to customize (ports, paths, feature flags). Use `vars` for internal constants the role needs that users shouldn't change.

---

**Q: What is Ansible Galaxy?**

Ansible Galaxy is the community hub for sharing and downloading Ansible content — roles and collections. You use `ansible-galaxy role install` to download roles and `ansible-galaxy collection install` for collections.

In practice, `requirements.yml` lists all dependencies so the team can install everything with one command:

```bash
ansible-galaxy install -r requirements.yml
```

---

**Q: What is a collection vs a role?**

A **role** is a structured way to organize tasks, handlers, templates, and variables for one specific purpose (e.g., configure nginx).

A **collection** is a distribution format that bundles multiple roles, modules, plugins, and playbooks together under a namespace. Collections are the modern standard and are distributed through Galaxy.

Example: `community.docker` is a collection containing Docker modules, `community.docker.docker_container` is one module from it.

---

## 🔐 Security & Vault

---

**Q: How does Ansible Vault work?**

Ansible Vault encrypts sensitive data using AES-256. You can encrypt entire files (`ansible-vault encrypt`) or individual values (`ansible-vault encrypt_string`).

Encrypted values look like `$ANSIBLE_VAULT;1.1;AES256...` — unreadable without the password. They're safe to commit to Git.

At runtime, you provide the vault password via `--ask-vault-pass`, `--vault-password-file`, or `ANSIBLE_VAULT_PASSWORD_FILE`. Ansible decrypts automatically before using the values.

---

**Q: What is the recommended way to use Vault in a project?**

Best practice: use `encrypt_string` to encrypt individual values, keep encrypted values in a separate `vault.yml` alongside your plain `vars.yml`. Use a `vault_` prefix naming convention:

```yaml
# vars.yml (readable)
db_password: "{{ vault_db_password }}"

# vault.yml (encrypted — safe to commit)
vault_db_password: !vault |
  $ANSIBLE_VAULT;1.1;AES256
  ...
```

Store the vault password in your CI system's secrets (GitHub Secrets, GitLab CI variables) — never commit it.

---

## ⚡ Performance & Scaling

---

**Q: How do you speed up Ansible playbooks?**

1. **Enable pipelining** in `ansible.cfg`: `pipelining = true` — reduces SSH round trips significantly
2. **Increase forks**: `forks = 20` — more parallel connections (default is 5)
3. **Cache facts**: `gathering = smart` + `fact_caching = jsonfile` — reuse facts across runs
4. **Disable fact gathering** when not needed: `gather_facts: false`
5. **Use `async`** for slow tasks to run them in parallel
6. **Use `--limit`** to only run against needed hosts
7. **Use tags** to skip unneeded sections

---

**Q: What is fact caching and why is it useful?**

Facts are gathered at the start of every play by default (connecting to each host and running `setup`). With large inventories, this takes significant time.

Fact caching stores gathered facts to disk or Redis. On subsequent runs, Ansible reuses cached facts instead of re-gathering them, saving time.

```ini
[defaults]
gathering = smart                     # only gather if not cached
fact_caching = jsonfile
fact_caching_connection = /tmp/facts
fact_caching_timeout = 3600           # cache valid for 1 hour
```

---

## 🔥 Scenario-Based Questions

---

**Scenario 1: Your playbook runs successfully but changes nothing on a server that should be updated. What do you check?**

```
Step 1 — Run with --check --diff to see what Ansible thinks
ansible-playbook site.yml --check --diff --limit web1.example.com

Step 2 — Check the when condition
Is there a `when:` that's evaluating to false?
Add a debug task: - debug: var=ansible_os_family

Step 3 — Check variable values
Are variables set to what you expect?
- debug: var=hostvars[inventory_hostname]

Step 4 — Check if task has `changed_when: false`
It might be running but reporting no change

Step 5 — Check if facts are stale
If using fact caching, delete the cache:
rm -rf /tmp/ansible_facts/*
ansible-playbook site.yml again
```

---

**Scenario 2: A play fails halfway through. How do you resume without rerunning completed tasks?**

Ansible creates a `.retry` file when a play fails (if `retry_files_enabled = true`). Use it to limit the next run:

```bash
# Run only on failed hosts
ansible-playbook site.yml --limit @site.retry
```

Alternatively use tags to run only the sections that failed:

```bash
ansible-playbook site.yml --tags deploy --limit "failed_host1,failed_host2"
```

Or fix the underlying issue and rerun — idempotency means completed tasks will show `ok` and not re-execute.

---

**Scenario 3: You need to deploy to 100 servers but only 10 should be updated at a time. How?**

Use `serial`:

```yaml
- name: Rolling deploy
  hosts: webservers
  serial: 10            # 10 at a time
  # OR
  serial: "10%"         # 10% at a time
  # OR progressive rollout
  serial: [2, 5, 10]    # first 2, then 5, then 10 at a time
```

---

**Scenario 4: A task needs to run only if a file doesn't already exist. How do you implement that?**

Two approaches:

```yaml
# Approach 1 — stat + when
- name: Check if already configured
  ansible.builtin.stat:
    path: /opt/myapp/.configured
  register: config_marker

- name: Run first-time setup
  ansible.builtin.command: /opt/myapp/setup.sh
  when: not config_marker.stat.exists

- name: Mark as configured
  ansible.builtin.file:
    path: /opt/myapp/.configured
    state: touch
  when: not config_marker.stat.exists

# Approach 2 — creates flag on command module
- name: Run setup only if not configured
  ansible.builtin.command:
    cmd: /opt/myapp/setup.sh
    creates: /opt/myapp/.configured   # skip if this file exists
```

---

**Scenario 5: How do you manage different configurations for production vs staging?**

Use separate inventory directories per environment:

```
inventories/
├── production/
│   ├── hosts.yml
│   └── group_vars/all/vars.yml    # production values
└── staging/
    ├── hosts.yml
    └── group_vars/all/vars.yml    # staging values
```

```bash
# Deploy to staging
ansible-playbook -i inventories/staging/ site.yml

# Deploy to production
ansible-playbook -i inventories/production/ site.yml
```

The same playbooks and roles work for both — only the variable values differ.

---

## 🧠 Advanced Questions

---

**Q: What is the difference between static and dynamic inventory?**

Static inventory is a file (INI or YAML) you maintain manually. Dynamic inventory is a script or plugin that queries an external source (AWS, GCP, CMDB) and returns host lists at runtime.

Dynamic inventory is essential for cloud environments where servers come and go. You configure it with a plugin (e.g., `amazon.aws.aws_ec2`) and it automatically discovers running EC2 instances, grouping them by tags.

---

**Q: How do you test Ansible roles?**

Three levels of testing:

1. **ansible-lint** — static analysis, catches YAML issues and bad practices
2. **`--check --diff`** — dry run against real servers, shows what would change
3. **Molecule** — full integration testing. Spins up Docker containers, applies the role, runs assertions to verify the result, then destroys. Can test against multiple OS versions in parallel.

---

**Q: What is `delegate_to` and when would you use it?**

`delegate_to` runs a task on a different host than the one currently being configured. Common use cases:

- Run a task on `localhost` (the control node) — downloading files, sending notifications
- Remove a server from a load balancer before deploying to it
- Run a database migration from one specific host
- Make an API call from the control node

```yaml
- name: Remove from load balancer before deploying
  community.general.haproxy:
    state: disabled
    host: "{{ inventory_hostname }}"
  delegate_to: loadbalancer.example.com
```

---

**Q: How would you structure an Ansible project for a team of 10 engineers?**

Key decisions:

1. **Separate inventory per environment** (`inventories/production/`, `inventories/staging/`)
2. **Roles for every reusable component** — `common`, `nginx`, `postgresql`, `myapp`
3. **requirements.yml** for all Galaxy dependencies — everyone installs the same versions
4. **Vault for all secrets** — `vault_` prefix convention, separate vault passwords per environment
5. **ansible.cfg in repo root** — consistent behavior for everyone
6. **ansible-lint in CI** — blocks merges with bad Ansible code
7. **Molecule for role testing** — roles are tested before merging
8. **README.md for every role** — documents variables and usage
9. **Tags on everything** — allows partial runs without full redeploys
10. **Git history as change record** — all changes through PRs

---

## 💬 Questions to Ask the Interviewer

**On their Ansible setup:**
- "Do you use dynamic or static inventory? If dynamic, which cloud providers?"
- "How do you handle secrets — Vault, HashiCorp Vault, AWS Secrets Manager?"
- "Do you use Molecule for role testing?"

**On their practices:**
- "How do you manage Ansible in CI/CD — do playbooks run automatically on merge?"
- "How do you handle the approval/review process for production Ansible changes?"
- "Are playbooks run manually or triggered by events (new server provision, deployment)?"

**On their challenges:**
- "What's the biggest operational challenge with your current Ansible setup?"
- "Have you had any incidents caused by Ansible changes? How did you recover?"

---

*Good luck — the fact that you've built this notes repo already puts you ahead of most candidates. 🚀*
