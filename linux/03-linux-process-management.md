# ⚙️ Process Management

Understand how Linux manages processes, services, and daemons — and how to control them.

> In DevOps, you're constantly starting, stopping, monitoring, and debugging processes. systemd is the backbone of all of it on modern Linux.

---

## 📚 Table of Contents

- [1. systemd — The Init System](#1-systemd--the-init-system)
- [2. Unit Files](#2-unit-files)
- [3. Managing Services with systemctl](#3-managing-services-with-systemctl)
- [4. Journald — Centralized Logging](#4-journald--centralized-logging)
- [5. Process Monitoring — ps, top, htop](#5-process-monitoring--ps-top-htop)
- [6. Process Signals & Control](#6-process-signals--control)
- [7. cgroups & Resource Limits](#7-cgroups--resource-limits)
- [8. Scheduling — cron & systemd Timers](#8-scheduling--cron--systemd-timers)
- [9. Process Troubleshooting Scenarios](#9-process-troubleshooting-scenarios)
- [Cheatsheet](#cheatsheet)

---

## 1. systemd — The Init System

### What is systemd?

systemd is PID 1 — the first process the kernel starts after boot. Everything else is a child of systemd. It's responsible for:

- Starting services in the correct order (respecting dependencies)
- Keeping services alive (auto-restart on failure)
- Managing logging via `journald`
- Handling system shutdown and reboot
- Mounting filesystems
- Managing devices

```
Kernel starts
     │
     ▼
systemd (PID 1)
     │
     ├── Reads unit files from /etc/systemd/system/ and /lib/systemd/system/
     │
     ├── Resolves dependencies between units
     │
     ├── Starts units in parallel where possible
     │
     └── Reaches target (e.g. multi-user.target = all services up)
```

### Targets — replacing old runlevels

Old SysV init had runlevels (0-6). systemd replaced them with **targets**:

| Old Runlevel | systemd Target | Description |
|-------------|----------------|-------------|
| 0 | `poweroff.target` | Shutdown |
| 1 | `rescue.target` | Single user, minimal services |
| 3 | `multi-user.target` | Full multi-user, no GUI |
| 5 | `graphical.target` | Full multi-user with GUI |
| 6 | `reboot.target` | Reboot |

```bash
# See current target
systemctl get-default

# Change default target
systemctl set-default multi-user.target

# Switch to a target right now
systemctl isolate rescue.target
```

### systemd directory structure

```
/lib/systemd/system/       # Default unit files (from packages) — don't edit
/etc/systemd/system/       # Your overrides and custom units — edit here
/run/systemd/system/       # Runtime units (temporary, lost on reboot)

# Override a package's unit file without editing it:
/etc/systemd/system/nginx.service.d/override.conf
```

---

## 2. Unit Files

A unit file tells systemd how to manage a resource. The most common type is a **service unit**.

### Service unit anatomy

```ini
# /etc/systemd/system/my-app.service

[Unit]
Description=My Application Server
Documentation=https://github.com/myorg/my-app
After=network.target          # start after network is up
After=postgresql.service      # start after postgres
Requires=postgresql.service   # hard dependency — if postgres fails, we fail
Wants=redis.service           # soft dependency — start redis if possible

[Service]
Type=simple                   # process stays in foreground
User=myapp                    # run as this user (not root!)
Group=myapp
WorkingDirectory=/opt/my-app

# Environment
Environment=APP_ENV=production
EnvironmentFile=/etc/my-app/env  # load from file

# The main process
ExecStart=/opt/my-app/bin/server --port 8080

# Commands run before/after start
ExecStartPre=/opt/my-app/bin/migrate
ExecStartPost=/bin/sleep 2

# Reload config without restart (triggered by: systemctl reload my-app)
ExecReload=/bin/kill -HUP $MAINPID

# Cleanup on stop
ExecStop=/bin/kill -TERM $MAINPID

# Restart behavior
Restart=always                # always restart if process exits
RestartSec=5                  # wait 5 seconds before restarting
StartLimitIntervalSec=60      # within this window...
StartLimitBurst=3             # ...allow max 3 restart attempts

# Resource limits
LimitNOFILE=65536             # max open file descriptors
LimitNPROC=4096               # max processes

# Security hardening
NoNewPrivileges=true          # can't gain new privileges
PrivateTmp=true               # isolated /tmp
ReadOnlyPaths=/etc            # /etc is read-only

[Install]
WantedBy=multi-user.target    # enable this service for normal boot
```

### Service types

| Type | Behavior | Use when |
|------|----------|---------|
| `simple` | PID from ExecStart is the main process | Most apps — process stays in foreground |
| `forking` | Process forks and parent exits | Old-style daemons that daemonize themselves |
| `oneshot` | Process runs and exits | Scripts, one-time tasks |
| `notify` | Process sends sd_notify() when ready | Apps that signal readiness explicitly |
| `dbus` | Process registers on D-Bus when ready | Desktop services |
| `idle` | Like simple but waits for jobs to finish | Batch jobs |

### Restart policies

| Value | When it restarts |
|-------|-----------------|
| `no` | Never (default) |
| `always` | Always — success, failure, signal |
| `on-failure` | Only on non-zero exit or signal |
| `on-abnormal` | Signal, watchdog timeout, or core dump |
| `on-success` | Only on clean exit (rare) |

```ini
# Robust restart config for a production service
Restart=on-failure
RestartSec=10
StartLimitIntervalSec=300    # 5 minute window
StartLimitBurst=5            # max 5 restarts in that window
# After 5 failures in 5 minutes, systemd gives up
```

### Override a unit file (without editing the original)

```bash
# The clean way — creates an override file
systemctl edit nginx

# This opens an editor and creates:
# /etc/systemd/system/nginx.service.d/override.conf

# Example override — increase file descriptor limit
[Service]
LimitNOFILE=100000

# After editing, reload systemd
systemctl daemon-reload
systemctl restart nginx
```

---

## 3. Managing Services with systemctl

### Essential systemctl commands

```bash
# Start / stop / restart
systemctl start nginx
systemctl stop nginx
systemctl restart nginx
systemctl reload nginx        # reload config without full restart (if supported)
systemctl reload-or-restart nginx  # try reload, fall back to restart

# Enable / disable (controls whether it starts on boot)
systemctl enable nginx        # create symlink to start on boot
systemctl disable nginx       # remove symlink
systemctl enable --now nginx  # enable AND start immediately
systemctl disable --now nginx # disable AND stop immediately

# Status and inspection
systemctl status nginx        # status, last few log lines, PID, uptime
systemctl is-active nginx     # returns "active" or "inactive"
systemctl is-enabled nginx    # returns "enabled" or "disabled"
systemctl is-failed nginx     # returns "failed" if in failed state

# List services
systemctl list-units --type=service          # all active services
systemctl list-units --type=service --all    # including inactive
systemctl list-unit-files --type=service     # all unit files and their state

# System state
systemctl is-system-running    # running, degraded, maintenance, etc.
systemctl list-jobs            # pending jobs

# Reload after editing unit files
systemctl daemon-reload        # MUST run after editing any unit file

# Reset a failed service (clears the failed state)
systemctl reset-failed nginx

# Mask a service (prevents it from being started at all)
systemctl mask nginx
systemctl unmask nginx
```

### Reading systemctl status output

```
● nginx.service - A high performance web server
     Loaded: loaded (/lib/systemd/system/nginx.service; enabled; vendor preset: enabled)
     Active: active (running) since Mon 2024-01-15 10:23:45 UTC; 2h 15min ago
       Docs: man:nginx(8)
    Process: 1234 ExecStartPre=/usr/sbin/nginx -t (code=exited, status=0/SUCCESS)
   Main PID: 1235 (nginx)
      Tasks: 3 (limit: 4915)
     Memory: 6.2M
        CPU: 150ms
     CGroup: /system.slice/nginx.service
             ├─1235 nginx: master process /usr/sbin/nginx
             ├─1236 nginx: worker process
             └─1237 nginx: worker process

Jan 15 10:23:45 server nginx[1235]: nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
Jan 15 10:23:45 server systemd[1]: Started A high performance web server.
```

Key things to read:
- **Loaded** — where the unit file is, and if it's enabled
- **Active** — current state and how long it's been running
- **Main PID** — the process ID of the main process
- **CGroup** — shows the process tree
- **Log lines** — last few journal entries for this service

---

## 4. Journald — Centralized Logging

systemd's `journald` collects logs from all services, the kernel, and the boot process into a single structured database.

### Basic journalctl usage

```bash
# All logs (newest at bottom)
journalctl

# Follow live logs (like tail -f)
journalctl -f

# Logs for a specific service
journalctl -u nginx
journalctl -u nginx -f                  # follow nginx logs

# Time filtering
journalctl --since today
journalctl --since "2024-01-15"
journalctl --since "2024-01-15 10:00" --until "2024-01-15 11:00"
journalctl --since "1 hour ago"

# Priority filtering
journalctl -p err                       # errors and above
journalctl -p warning                   # warnings and above
journalctl -p debug                     # everything (very verbose)

# Priority levels: emerg, alert, crit, err, warning, notice, info, debug

# Kernel messages only
journalctl -k
journalctl -k --since today

# Show last N lines
journalctl -n 50
journalctl -u nginx -n 100

# Output formats
journalctl -u nginx -o json            # JSON output
journalctl -u nginx -o json-pretty     # pretty JSON
journalctl -u nginx -o short-iso       # with ISO timestamps
journalctl -u nginx -o cat             # just the message, no metadata

# Boot logs
journalctl -b                          # current boot
journalctl -b -1                       # previous boot
journalctl --list-boots                # list all recorded boots

# Disk usage
journalctl --disk-usage

# Vacuum old logs
journalctl --vacuum-time=7d            # delete logs older than 7 days
journalctl --vacuum-size=500M          # keep only 500MB of logs
```

### journald configuration

```ini
# /etc/systemd/journald.conf

[Journal]
Storage=persistent          # persist to disk (default: auto)
Compress=yes                # compress stored logs
SystemMaxUse=1G             # max disk space for system logs
SystemKeepFree=500M         # keep this much free on disk
MaxRetentionSec=30day       # delete logs older than 30 days
MaxFileSec=1week            # rotate log files weekly
ForwardToSyslog=no          # don't forward to rsyslog (if not needed)
```

```bash
# Apply changes
systemctl restart systemd-journald
```

---

## 5. Process Monitoring — ps, top, htop

### ps — process snapshot

```bash
# Most useful formats
ps aux                      # all processes, BSD style
ps -ef                      # all processes, UNIX style
ps -ef --forest             # with ASCII tree showing parent-child
ps aux --sort=-%cpu         # sort by CPU descending
ps aux --sort=-%mem         # sort by memory descending

# Custom output columns
ps -eo pid,ppid,user,%cpu,%mem,stat,cmd
ps -eo pid,ppid,user,%cpu,%mem,stat,cmd --sort=-%cpu | head -20

# Find specific processes
ps aux | grep nginx
ps -C nginx                 # by command name (cleaner)
pgrep -l nginx              # PID and name
pgrep -a nginx              # PID and full command line

# Column meanings
# USER — process owner
# PID  — process ID
# %CPU — CPU usage percentage
# %MEM — memory usage percentage
# VSZ  — virtual memory size (KB)
# RSS  — resident set size / physical RAM used (KB)
# STAT — process state (S=sleeping, R=running, D=uninterruptible, Z=zombie, T=stopped)
# START — when it started
# TIME — total CPU time consumed
# COMMAND — command name or line
```

### top — interactive live view

```bash
top                         # launch top

# Inside top — keyboard shortcuts
q           # quit
P           # sort by CPU (default)
M           # sort by memory
T           # sort by total CPU time
k           # kill a process (enter PID, then signal)
r           # renice a process (change priority)
1           # toggle per-CPU view
c           # show full command line
u           # filter by username
f           # field management (add/remove columns)
W           # save current config to ~/.toprc
```

### Understanding top output

```
top - 10:45:23 up 2 days,  3:12,  2 users,  load average: 0.52, 0.38, 0.35
Tasks: 185 total,   1 running, 184 sleeping,   0 stopped,   0 zombie
%Cpu(s):  5.2 us,  1.3 sy,  0.0 ni, 92.8 id,  0.5 wa,  0.0 hi,  0.2 si
MiB Mem :  15987.3 total,   2341.5 free,   8234.1 used,   5411.7 buff/cache
MiB Swap:   2048.0 total,   2048.0 free,      0.0 used.   7253.2 avail Mem
```

| Field | Meaning |
|-------|---------|
| `load average: 0.52, 0.38, 0.35` | 1, 5, 15 min averages. On 4-core system, 4.0 = fully loaded |
| `us` | User space CPU % |
| `sy` | Kernel/system CPU % |
| `id` | Idle CPU % |
| `wa` | I/O wait — high = disk or network bottleneck |
| `buff/cache` | Memory used for disk cache — available if needed |

> 💡 **Load average rule of thumb:** Load / number of cores. If load is 3.5 on a 4-core system, you're at 87% — watch it. If load is 8.0 on a 4-core system, the system is overloaded.

### htop — better top

```bash
# Install
apt install htop

# Launch
htop

# htop features over top:
# - Color coded, easier to read
# - Mouse support — click to select/kill
# - Horizontal and vertical scrolling
# - Tree view with T
# - Filter with / (search)
# - F9 to send signals
# - Shows CPU per core by default
```

---

## 6. Process Signals & Control

```bash
# Send signals
kill -SIGTERM 1234          # graceful shutdown
kill -SIGKILL 1234          # force kill (cannot be caught)
kill -SIGHUP 1234           # reload config
kill -SIGSTOP 1234          # pause process
kill -SIGCONT 1234          # resume paused process

# Kill by name
killall nginx               # SIGTERM to all nginx processes
killall -9 nginx            # SIGKILL to all nginx processes
pkill nginx                 # same as killall
pkill -f "python manage.py" # match against full command line

# List all signals
kill -l

# Job control in shell
Ctrl+C                      # send SIGINT (interrupt)
Ctrl+Z                      # send SIGSTOP (pause, put in background)
Ctrl+\                      # send SIGQUIT (quit with core dump)

fg                          # bring last background job to foreground
bg                          # send last stopped job to background
jobs                        # list all background/stopped jobs
jobs -l                     # with PIDs

# Keep process running after logout
nohup command > output.log 2>&1 &
disown %1                   # disown a job already running

# tmux / screen — better alternative to nohup
tmux new -s mysession       # new named session
tmux attach -t mysession    # reattach after disconnect
screen -S mysession         # screen alternative
```

---

## 7. cgroups & Resource Limits

### What are cgroups?

Control groups (cgroups) are a Linux kernel feature for limiting, accounting, and isolating resource usage of process groups.

This is exactly what Kubernetes uses to enforce `resources.limits.cpu` and `resources.limits.memory`.

```bash
# See cgroup hierarchy
ls /sys/fs/cgroup/

# See which cgroup a process belongs to
cat /proc/1234/cgroup

# See memory limit of a container (from the host)
cat /sys/fs/cgroup/memory/kubepods/besteffort/pod.../memory.limit_in_bytes

# See CPU quota of a container
cat /sys/fs/cgroup/cpu/kubepods/.../cpu.cfs_quota_us    # allowed microseconds
cat /sys/fs/cgroup/cpu/kubepods/.../cpu.cfs_period_us   # per period
# quota/period = CPU cores allowed. 50000/100000 = 0.5 cores
```

### ulimit — per-process resource limits

```bash
# View limits for current shell
ulimit -a

# View specific limits
ulimit -n          # max open file descriptors (nofile)
ulimit -u          # max user processes (nproc)
ulimit -v          # max virtual memory

# Set limits for current session
ulimit -n 65536    # set max open files to 65536

# Set permanent limits in /etc/security/limits.conf
# username   type    resource    value
nginx        soft    nofile      65536
nginx        hard    nofile      65536
*            soft    nproc       4096
*            hard    nproc       8192
```

### systemd resource limits in unit files

```ini
[Service]
# CPU
CPUQuota=50%              # max 50% of one CPU core
CPUWeight=100             # relative scheduling weight (default 100)

# Memory
MemoryLimit=512M          # hard memory limit (cgroup v1)
MemoryMax=512M            # hard memory limit (cgroup v2)
MemoryHigh=400M           # soft limit — throttle above this

# File descriptors
LimitNOFILE=65536

# Processes
LimitNPROC=512

# Tasks (threads)
TasksMax=512
```

---

## 8. Scheduling — cron & systemd Timers

### cron — traditional job scheduler

```bash
# Edit your crontab
crontab -e

# List your crontab
crontab -l

# Edit another user's crontab (as root)
crontab -u fasih -e

# System-wide crontabs
/etc/crontab           # system crontab (has user field)
/etc/cron.d/           # drop-in crontab files
/etc/cron.daily/       # scripts run daily
/etc/cron.weekly/      # scripts run weekly
/etc/cron.hourly/      # scripts run hourly
```

### Cron syntax

```
┌───────── minute (0-59)
│ ┌─────── hour (0-23)
│ │ ┌───── day of month (1-31)
│ │ │ ┌─── month (1-12)
│ │ │ │ ┌─ day of week (0=Sun, 6=Sat)
│ │ │ │ │
* * * * * command

# Examples
0 * * * *     command     # every hour at :00
*/15 * * * *  command     # every 15 minutes
0 2 * * *     command     # daily at 2am
0 2 * * 0     command     # every Sunday at 2am
0 2 1 * *     command     # 1st of every month at 2am
0 2 * * 1-5   command     # weekdays at 2am
@reboot       command     # once on startup
@daily        command     # same as 0 0 * * *
@hourly       command     # same as 0 * * * *
```

```bash
# Common cron entries
# Daily backup at 2am
0 2 * * * /opt/scripts/backup.sh >> /var/log/backup.log 2>&1

# Clear temp files every Sunday
0 3 * * 0 find /tmp -mtime +7 -delete

# Health check every 5 minutes
*/5 * * * * curl -sf http://localhost:8080/health || systemctl restart my-app
```

### systemd Timers — modern alternative to cron

systemd timers are more powerful than cron — they integrate with journald (logs automatically), support dependencies, and can catch up on missed runs.

```bash
# List all timers
systemctl list-timers --all
```

A timer needs two unit files — a `.timer` and a `.service`:

```ini
# /etc/systemd/system/backup.timer
[Unit]
Description=Daily backup timer
Requires=backup.service

[Timer]
OnCalendar=daily              # run daily at midnight
OnCalendar=*-*-* 02:00:00    # or specifically at 2am
RandomizedDelaySec=30m        # random delay up to 30 min (spreads load)
Persistent=true               # catch up if system was off during scheduled time

[Install]
WantedBy=timers.target
```

```ini
# /etc/systemd/system/backup.service
[Unit]
Description=Daily backup job

[Service]
Type=oneshot
ExecStart=/opt/scripts/backup.sh
User=backup
```

```bash
# Enable and start the timer
systemctl enable --now backup.timer

# Check when it last ran and next run
systemctl status backup.timer

# Manually trigger the service (test it)
systemctl start backup.service

# View logs
journalctl -u backup.service
```

### cron vs systemd timers

| | cron | systemd Timer |
|--|------|--------------|
| **Logging** | Must redirect manually | Automatic via journald |
| **Missed runs** | Skipped | Can catch up (Persistent=true) |
| **Dependencies** | None | Full systemd dependency support |
| **Resource limits** | None | Full cgroup limits |
| **Setup** | One line | Two unit files |
| **Debugging** | Hard | `systemctl status` + journalctl |
| **Use when** | Simple, quick tasks | Production workloads, need logging |

---

## 9. Process Troubleshooting Scenarios

---

**Scenario: Service won't start**

```bash
# Step 1 — Check status and error message
systemctl status my-app

# Step 2 — Check recent logs
journalctl -u my-app -n 50
journalctl -u my-app --since "5 minutes ago"

# Step 3 — Test the ExecStart command manually as the service user
sudo -u myapp /opt/my-app/bin/server --port 8080

# Step 4 — Check if port is already in use
ss -tulnp | grep :8080

# Step 5 — Check file permissions
ls -la /opt/my-app/bin/server
namei -l /opt/my-app/bin/server    # check each path component

# Step 6 — Check dependency services
systemctl status postgresql
systemctl status redis

# Step 7 — Validate unit file syntax
systemd-analyze verify /etc/systemd/system/my-app.service
```

---

**Scenario: Process consuming too much CPU**

```bash
# Identify which process
top -o %CPU        # sort by CPU in top
ps aux --sort=-%cpu | head -10

# Find out what it's doing
strace -p 1234     # trace syscalls (slow — use sparingly)
perf top           # CPU profiling (apt install linux-perf)
lsof -p 1234       # see open files

# Reduce its priority without killing it
renice -n 15 -p 1234     # lower priority (10-19 = lower, -20 = highest)

# If it's a runaway process
kill -SIGTERM 1234
# Wait a few seconds, then if still running:
kill -SIGKILL 1234
```

---

**Scenario: Process stuck in D state (uninterruptible sleep)**

```bash
# Find D state processes
ps aux | awk '$8 == "D" {print}'

# Check what it's waiting for
cat /proc/1234/wchan        # shows kernel function it's waiting in
ls -la /proc/1234/fd        # open file descriptors

# Common causes:
# - NFS mount hung → umount -f -l /mnt/nfs
# - Disk I/O stuck → check dmesg for disk errors
# - You CANNOT kill -9 a D-state process — must resolve the underlying cause
```

---

**Scenario: Zombie processes accumulating**

```bash
# Find zombie processes
ps aux | grep Z
ps aux | awk '$8 == "Z" {print}'

# Find the parent of the zombie
ps -o ppid= -p <zombie-pid>   # get PPID
ps aux | grep <ppid>          # check parent

# Zombies can't be killed directly — they're already dead
# Solution: fix or restart the parent process
# If parent is dead too, zombie will be adopted by init and cleaned up

kill -CHLD <parent-pid>       # signal parent to collect zombie's exit status
```

---

**Scenario: Service keeps restarting (CrashLoopBackOff equivalent)**

```bash
# Check how many times it's restarted
systemctl status my-app | grep "Started\|Failed"

# Check logs from each crash
journalctl -u my-app --since "1 hour ago" | grep -A5 "Failed\|Error\|killed"

# Check if OOMKilled
journalctl -k | grep -i "killed process\|oom"
dmesg | grep -i oom

# Check resource limits
systemctl show my-app | grep -E "Memory|CPU|Limit"

# Temporarily disable restart to investigate
systemctl stop my-app
# Then manually run the binary to see what happens
```

---

## Cheatsheet

```bash
# Service lifecycle
systemctl start|stop|restart|reload|status nginx
systemctl enable|disable nginx
systemctl enable --now nginx      # enable + start in one command
systemctl daemon-reload           # REQUIRED after editing unit files
systemctl reset-failed nginx      # clear failed state

# Inspect
systemctl status nginx
systemctl show nginx              # all properties
systemctl cat nginx               # show the unit file
systemctl list-dependencies nginx # what it depends on

# Logs
journalctl -u nginx -f            # follow nginx logs
journalctl -u nginx -p err        # errors only
journalctl -u nginx --since today # today's logs
journalctl -b                     # current boot logs

# Processes
ps aux --sort=-%cpu | head        # top CPU consumers
ps aux --sort=-%mem | head        # top memory consumers
ps -ef --forest                   # process tree
pgrep -a nginx                    # find PIDs by name

# Signals
kill -SIGTERM 1234                # graceful stop
kill -SIGHUP 1234                 # reload config
kill -SIGKILL 1234                # force kill

# Cron
crontab -e                        # edit crontab
crontab -l                        # list crontab

# Timers
systemctl list-timers --all       # list all timers
systemctl status backup.timer     # timer status and next run
```

---

*Next: [Networking →](./04-linux-networking.md) — ip, ss, DNS, and debugging network problems.*
