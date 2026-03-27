# 🐧 Linux for DevOps

A structured knowledge base covering Linux from the ground up — built for DevOps and cloud engineering roles.

> Linux is the operating system everything runs on. Containers, Kubernetes nodes, CI runners, cloud VMs — all Linux. The deeper your understanding, the faster you solve production problems.

---

## 🗺️ Learning Path

Work through these in order — each file builds on the previous one.

```
01 → 02 → 03 → 04 → 05 → 06
 │     │     │     │     │     │
 │     │     │     │     │     └── Automate everything with bash
 │     │     │     │     └──────── Disks, LVM, mounts, Kubernetes PVs
 │     │     │     └────────────── Interfaces, routing, DNS, firewalls
 │     │     └──────────────────── systemd, services, cron, cgroups
 │     └────────────────────────── The commands you use every single day
 └──────────────────────────────── How Linux actually works under the hood
```

---

## 📚 Contents

| # | File | What you'll learn |
|---|------|------------------|
| 01 | [Core Concepts & Theory](./01-linux-concepts-theory.md) | Kernel, filesystem hierarchy, processes, signals, permissions, boot process, namespaces, cgroups |
| 02 | [Essential Commands](./02-linux-essential-commands.md) | Navigation, grep, text processing, SSH, networking commands, everyday one-liners |
| 03 | [Process Management](./03-linux-process-management.md) | systemd, unit files, journald, cron, systemd timers, resource limits, troubleshooting |
| 04 | [Networking](./04-linux-networking.md) | Interfaces, routing, DNS, ss, iptables, curl, tcpdump, Kubernetes networking |
| 05 | [Storage & Filesystems](./05-linux-storage.md) | Partitions, ext4/xfs, LVM, mounting, NFS, Kubernetes PV/PVC |
| 06 | [Shell Scripting](./06-linux-shell-scripting.md) | Bash scripting, error handling, functions, real DevOps scripts, debugging |

---

## ⚡ Quick Reference

### Most-reached-for commands

```bash
# Find what's using disk
du --max-depth=1 -h / 2>/dev/null | sort -h | tail -20
df -h && df -i                         # space and inodes

# Find a process
ps aux | grep nginx
pgrep -a nginx
ss -tulnp | grep :8080                 # what's on port 8080

# Service management
systemctl status nginx
systemctl restart nginx
journalctl -u nginx -f                 # follow logs
journalctl -u nginx -p err             # errors only

# Network debugging
ip addr                                # interfaces and IPs
ss -tulnp                              # listening ports
curl -I https://example.com           # HTTP headers
dig example.com                        # DNS lookup

# File searching
grep -r "pattern" /etc/               # search in files
find /var/log -name "*.log" -mtime -1 # recently modified
lsof | grep deleted                    # deleted files still held open

# Permissions
chmod 755 script.sh
chown -R www-data /var/www/
namei -l /path/to/file                 # permissions at each level

# SSH
ssh -J bastion user@internal           # jump through bastion
ssh-copy-id user@server                # copy SSH key
rsync -avz dir/ user@server:/opt/      # sync files
```

### systemd cheatsheet

```bash
systemctl start|stop|restart nginx
systemctl enable --now nginx           # enable + start
systemctl status nginx
systemctl daemon-reload                # after editing unit files
journalctl -u nginx --since today
journalctl -f                          # follow all logs
```

### Shell scripting essentials

```bash
#!/usr/bin/env bash
set -euo pipefail                      # safety net — always include

VAR="${ENV_VAR:-default}"              # default value
VAR="${ENV_VAR:?must be set}"          # required variable

[[ -f "$FILE" ]]                       # file exists
[[ -z "$STR" ]]                        # empty string
[[ $A -gt $B ]]                        # numeric comparison

trap 'cleanup' EXIT                    # always run cleanup
TMPFILE=$(mktemp); trap "rm -f $TMPFILE" EXIT

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
error() { echo "ERROR: $*" >&2; exit 1; }
```

### Troubleshooting flow

```
Something is broken
        │
        ├── Service down?
        │   systemctl status <service>
        │   journalctl -u <service> -n 50
        │
        ├── Disk full?
        │   df -h && df -i
        │   du --max-depth=1 -h / | sort -h | tail -20
        │   lsof | grep deleted
        │
        ├── High CPU/memory?
        │   top / htop
        │   ps aux --sort=-%cpu | head -10
        │
        ├── Network issue?
        │   ping <host>
        │   ss -tulnp | grep <port>
        │   curl -v <url>
        │   dig <hostname>
        │
        └── Process crashed?
            journalctl -k | grep -i oom
            dmesg | grep -i "killed\|error"
            systemctl status <service>
```

---

## 🧠 Key Concepts at a Glance

| Concept | One-line summary |
|---------|-----------------|
| **Kernel** | Core of the OS — manages hardware, processes, memory, networking |
| **PID 1** | systemd — the first process, parent of everything |
| **Namespace** | Linux isolation mechanism — each container gets its own PID, network, filesystem view |
| **cgroup** | Limits CPU, memory, I/O for a group of processes — how Kubernetes enforces resource limits |
| **Signal** | Software interrupt to a process — SIGTERM (graceful), SIGKILL (force, uncatchable) |
| **inode** | Stores file metadata — run out of inodes and you can't create files even with free disk space |
| **File descriptor** | Integer handle for an open file/socket/pipe (0=stdin, 1=stdout, 2=stderr) |
| **Symlink** | Pointer to another file — breaks if target is deleted |
| **Hardlink** | Another name for the same inode — survives target rename |
| **LVM** | Abstraction over physical disks — resize volumes without downtime |
| **set -euo pipefail** | Bash safety net — exit on error, treat unset vars as errors, fail pipe if any command fails |
| **D state** | Uninterruptible sleep — process waiting on I/O, cannot be killed (usually disk/NFS issue) |
| **Zombie** | Exited process whose parent hasn't called wait() — cleans up on its own |
| **OOMKill** | Kernel killed a process for exceeding memory limit — exit code 137 |
| **TCP TIME_WAIT** | Normal connection-closing state — high count is expected on busy servers |
| **SIGHUP** | Traditionally means "reload config" — sent to daemons like nginx, sshd |
| **Fork** | Create a child process — all processes are created this way |
| **Exec** | Replace current process image with a new program |
| **Scrape interval** | How often Prometheus pulls metrics |
| **veth pair** | Virtual ethernet pair connecting a container to the host network |

---

## 🗂️ Folder Structure

```
linux/
├── 00-linux-index.md                  ← You are here
├── 01-linux-concepts-theory.md
├── 02-linux-essential-commands.md
├── 03-linux-process-management.md
├── 04-linux-networking.md
├── 05-linux-storage.md
└── 06-linux-shell-scripting.md
```

---

## 🔗 How This Connects to DevOps

| Linux topic | Where it shows up in DevOps |
|------------|---------------------------|
| Processes & signals | Kubernetes pod lifecycle, graceful shutdown, SIGTERM handling |
| Namespaces & cgroups | How Docker and Kubernetes containers actually work |
| Filesystem & inodes | Kubernetes PV/PVC, container image layers (overlayfs) |
| systemd | Managing services on nodes, writing startup scripts |
| Networking | Kubernetes CNI, pod networking, iptables rules for Services |
| Shell scripting | CI/CD pipelines, deployment scripts, automation |
| Storage & LVM | Persistent volumes, node disk management |
| journald/logs | Debugging pods, log forwarding to Loki/CloudWatch |

---

*Notes are living documents — updated as I learn and build.*
