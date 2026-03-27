# 📖 Linux Core Concepts & Theory

The fundamentals every DevOps engineer needs to understand about Linux — before touching any commands.

> Linux is the operating system your containers, VMs, and Kubernetes nodes run on. The better you understand it, the faster you debug production issues.

---

## 📚 Table of Contents

- [1. The Linux Architecture](#1-the-linux-architecture)
- [2. The Filesystem Hierarchy](#2-the-filesystem-hierarchy)
- [3. Everything is a File](#3-everything-is-a-file)
- [4. Processes](#4-processes)
- [5. Signals](#5-signals)
- [6. Users & Groups](#6-users--groups)
- [7. Permissions](#7-permissions)
- [8. File Descriptors & I/O Redirection](#8-file-descriptors--io-redirection)
- [9. The Boot Process](#9-the-boot-process)
- [10. Kernel & System Calls](#10-kernel--system-calls)
- [11. Linux in the Context of DevOps & Containers](#11-linux-in-the-context-of-devops--containers)
- [Key Terms Glossary](#key-terms-glossary)

---

## 1. The Linux Architecture

Linux is structured in layers. Understanding the layers helps you understand where problems originate.

```
┌─────────────────────────────────────────┐
│            User Space                    │
│                                          │
│  ┌──────────────────────────────────┐   │
│  │   Applications & Tools           │   │
│  │   (bash, nginx, kubectl, etc.)   │   │
│  └──────────────────────────────────┘   │
│                                          │
│  ┌──────────────────────────────────┐   │
│  │   C Standard Library (glibc)     │   │
│  │   (wraps syscalls in C functions)│   │
│  └──────────────────────────────────┘   │
│                                          │
├──────────────── syscall interface ───────┤
│                                          │
│            Kernel Space                  │
│                                          │
│  ┌──────────────────────────────────┐   │
│  │   Linux Kernel                   │   │
│  │   Process mgmt, memory, FS, net  │   │
│  └──────────────────────────────────┘   │
│                                          │
├──────────────────────────────────────────┤
│            Hardware                      │
│   CPU, RAM, Disk, Network interfaces     │
└─────────────────────────────────────────┘
```

- **Hardware** — physical or virtual resources
- **Kernel** — the core of the OS, manages hardware access, processes, memory, and networking
- **System call interface** — the only way user-space programs can ask the kernel to do privileged work
- **glibc** — wraps raw syscalls into familiar C functions (`open()`, `read()`, `fork()`)
- **Applications** — everything you interact with, including shells, web servers, and tools

---

## 2. The Filesystem Hierarchy

Linux organizes everything in a single tree starting from `/` (root). Unlike Windows, there are no drive letters.

```
/
├── bin/        Essential user binaries (ls, cp, bash)
├── sbin/       System binaries (fdisk, iptables) — usually for root
├── etc/        Configuration files (nginx.conf, ssh/sshd_config)
├── home/       User home directories (/home/fasih)
├── root/       Home directory for the root user
├── var/        Variable data — logs, spools, runtime files
│   ├── log/    System and application logs
│   └── run/    PID files, sockets
├── tmp/        Temporary files — cleared on reboot
├── usr/        User programs and libraries
│   ├── bin/    Non-essential user binaries
│   ├── lib/    Libraries for /usr/bin programs
│   └── local/  Locally installed software
├── lib/        Shared libraries for /bin and /sbin
├── proc/       Virtual filesystem — live kernel/process info
├── sys/        Virtual filesystem — kernel device and driver info
├── dev/        Device files (disks, terminals, random)
├── mnt/        Temporary mount points
├── media/      Auto-mounted removable media (USB, CD)
├── boot/       Kernel, initrd, bootloader files
├── opt/        Optional third-party software
└── run/        Runtime data for processes since last boot
```

### Key directories for DevOps

| Directory | Why you care |
|-----------|-------------|
| `/etc/` | All config files live here — nginx, systemd units, SSH, cron |
| `/var/log/` | System and application logs — first place to check when something breaks |
| `/proc/` | Live process and kernel info — read by `ps`, `top`, `free` |
| `/sys/` | Hardware and kernel tuning — used to change kernel parameters at runtime |
| `/run/` | PID files and sockets — check here if a service won't start |
| `/tmp/` | Temporary files — world-writable, cleared on reboot |

---

## 3. Everything is a File

One of Linux's core design principles: **everything is represented as a file**.

This includes:
- Regular files and directories (obviously)
- **Devices** — `/dev/sda` (disk), `/dev/null` (discard), `/dev/random` (random bytes)
- **Processes** — `/proc/1234/` (directory for process 1234)
- **Sockets** — Unix domain sockets used for inter-process communication
- **Named pipes (FIFOs)** — for streaming data between processes

### Why this matters

Because everything is a file, you can use the same tools (`cat`, `ls`, `read`, `write`) on very different things:

```bash
# Read a process's command line
cat /proc/1234/cmdline

# See how much memory the system has
cat /proc/meminfo

# Write to a kernel parameter at runtime (no restart needed)
echo 1 > /proc/sys/net/ipv4/ip_forward

# Discard output by redirecting to /dev/null
some-command > /dev/null 2>&1

# Generate random bytes
cat /dev/urandom | head -c 16 | base64
```

### `/proc` — the process filesystem

`/proc` is a **virtual filesystem** — it doesn't exist on disk. The kernel generates its contents on the fly when you read from it.

```bash
/proc/
├── 1/              # Process with PID 1 (init/systemd)
│   ├── cmdline     # Full command that started this process
│   ├── status      # State, memory usage, UID
│   ├── fd/         # Open file descriptors
│   ├── maps        # Memory mappings
│   └── environ     # Environment variables
├── cpuinfo         # CPU details
├── meminfo         # Memory usage breakdown
├── net/            # Network stats (connections, interfaces)
├── sys/            # Kernel parameters (tunable)
└── loadavg         # Load average (same as uptime)
```

---

## 4. Processes

A process is a running instance of a program. Every process has:

| Attribute | Description |
|-----------|-------------|
| **PID** | Process ID — unique identifier |
| **PPID** | Parent Process ID — who spawned it |
| **UID/GID** | User and Group ID — who it runs as |
| **State** | Running, Sleeping, Stopped, Zombie |
| **Priority/Nice** | Scheduling priority (-20 highest, +19 lowest) |
| **File descriptors** | Open files, sockets, pipes |
| **Memory maps** | Virtual memory regions |

### Process states

```
         fork()
Parent ──────────► Child (new process)
                      │
              ┌───────┴───────┐
              │               │
           Running         Sleeping
              │           (waiting for I/O,
              │            signal, or timer)
              │
           Stopped        ← received SIGSTOP
              │
           Zombie         ← exited but parent hasn't called wait()
```

| State | Code | What it means |
|-------|------|--------------|
| Running | R | Actively using CPU or in run queue |
| Sleeping (interruptible) | S | Waiting for I/O, can be woken by signal |
| Sleeping (uninterruptible) | D | Waiting for I/O, cannot be interrupted — often means disk/NFS issue |
| Stopped | T | Paused by SIGSTOP or job control (Ctrl+Z) |
| Zombie | Z | Finished but parent hasn't collected exit status yet |

> ⚠️ **D state (uninterruptible sleep)** is significant — processes stuck in D state usually mean a storage or NFS problem. They can't be killed with `kill -9`.

### Process creation

All processes (except PID 1) are created by **forking**:

```
PID 1 (systemd)
   │
   ├── fork() → PID 100 (bash)
   │                │
   │                └── fork() → PID 200 (ls)
   │                     └── exec() → replaces process image with ls binary
   │
   └── fork() → PID 101 (sshd)
```

1. `fork()` — creates an exact copy of the parent process
2. `exec()` — replaces the copy's memory with a new program
3. `wait()` — parent waits for child to finish and collects exit code

### Process priorities

```bash
# Start a process with low priority (nice value 10)
nice -n 10 my-cpu-heavy-script.sh

# Change priority of a running process
renice -n 5 -p 1234

# View priorities in top
top   # PR column = kernel priority, NI column = nice value
```

---

## 5. Signals

Signals are software interrupts sent to processes. They're how the OS and other processes communicate asynchronously.

### Common signals

| Signal | Number | Default action | When used |
|--------|--------|---------------|----------|
| `SIGHUP` | 1 | Terminate | Reload config (many daemons catch this) |
| `SIGINT` | 2 | Terminate | Ctrl+C — interrupt from keyboard |
| `SIGQUIT` | 3 | Core dump | Ctrl+\\ — quit with core dump |
| `SIGKILL` | 9 | Terminate | **Cannot be caught or ignored** — force kill |
| `SIGTERM` | 15 | Terminate | Graceful shutdown request (default for `kill`) |
| `SIGSTOP` | 19 | Stop | **Cannot be caught or ignored** — pause process |
| `SIGCONT` | 18 | Continue | Resume a stopped process |
| `SIGUSR1/2` | 30/31 | Terminate | Custom signals — app-defined behavior |

### SIGTERM vs SIGKILL — the critical difference

```
SIGTERM (15) — polite request to stop
  → Process CAN catch this signal
  → Can clean up: close connections, flush buffers, write state
  → Process might ignore it if it chooses to

SIGKILL (9) — forced termination by kernel
  → Process CANNOT catch, block, or ignore this
  → Kernel kills the process immediately
  → No cleanup — open files may be corrupted, connections dropped abruptly
```

**Always try SIGTERM first. Only use SIGKILL if SIGTERM doesn't work.**

```bash
# Send SIGTERM (default)
kill 1234
kill -15 1234
kill -SIGTERM 1234

# Force kill — last resort
kill -9 1234
kill -SIGKILL 1234

# Reload config (SIGHUP)
kill -1 1234
kill -HUP $(pidof nginx)
```

### Signals in containers

Containers and Kubernetes use signals for graceful shutdown:
- Kubernetes sends `SIGTERM` to PID 1 in a container when stopping a pod
- After `terminationGracePeriodSeconds` (default 30s), it sends `SIGKILL`
- Your app **must** handle `SIGTERM` to shut down gracefully

```go
// Go — handle SIGTERM for graceful shutdown
sigCh := make(chan os.Signal, 1)
signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)
<-sigCh
// cleanup code here
```

---

## 6. Users & Groups

Linux is a multi-user system. Every process, file, and resource has an owner.

### Key concepts

| Concept | Description |
|---------|-------------|
| **UID** | User ID — a number identifying a user (root = 0) |
| **GID** | Group ID — a number identifying a group |
| **Real UID** | Who you actually are |
| **Effective UID** | Who you're acting as (changed by sudo/setuid) |
| **root** | UID 0 — has unrestricted access to everything |

### User categories

```
UID 0          → root (superuser)
UID 1-999      → system users (nginx, postgres, nobody) — no login shell
UID 1000+      → regular users (you)
```

### Important files

```bash
/etc/passwd     # User accounts (username, UID, GID, home, shell)
/etc/shadow     # Hashed passwords (root-readable only)
/etc/group      # Group definitions
/etc/sudoers    # Who can run sudo and what they can run
```

```bash
# /etc/passwd format:
# username:x:UID:GID:comment:home:shell
fasih:x:1000:1000:Fasih:/home/fasih:/bin/bash
nginx:x:101:101:nginx user:/var/cache/nginx:/sbin/nologin
```

### sudo vs su

```bash
# sudo — run a single command as root (or another user)
sudo apt update
sudo -u postgres psql

# su — switch to another user entirely
su -          # switch to root (needs root password)
su - fasih    # switch to user fasih

# sudo su - — become root using YOUR password (if sudoer)
sudo su -
```

---

## 7. Permissions

Every file and directory has three permission sets and three permission types.

### Permission structure

```
-rwxr-xr--  1  fasih  developers  4096  Jan 15  myfile.sh
│└─┬─┘└─┬─┘└─┬─┘
│  │    │    │
│  │    │    └── Other permissions (everyone else)
│  │    └─────── Group permissions
│  └──────────── Owner permissions
└─────────────── File type (- file, d directory, l symlink, c char device)
```

### Permission types

| Symbol | Octal | On file | On directory |
|--------|-------|---------|-------------|
| `r` | 4 | Read file contents | List directory contents |
| `w` | 2 | Modify file | Create/delete files inside |
| `x` | 1 | Execute file | Enter directory (cd into it) |

### Octal notation

```
rwx = 4+2+1 = 7
rw- = 4+2+0 = 6
r-x = 4+0+1 = 5
r-- = 4+0+0 = 4
--- = 0+0+0 = 0

# chmod 755 myfile
# Owner: rwx (7), Group: r-x (5), Other: r-x (5)
chmod 755 myfile.sh    # owner can do everything, others can read+execute
chmod 644 config.conf  # owner read/write, others read-only
chmod 600 id_rsa       # SSH key — owner only, others nothing
chmod 700 ~/.ssh       # SSH dir — owner only
```

### Special permissions

| Permission | Octal | Effect on file | Effect on directory |
|-----------|-------|---------------|-------------------|
| **SetUID** | 4000 | Runs as file owner (e.g. `sudo`, `passwd`) | No effect |
| **SetGID** | 2000 | Runs as file's group | New files inherit directory's group |
| **Sticky bit** | 1000 | No effect | Only file owner can delete their files |

```bash
# Sticky bit on /tmp — everyone can write but only delete their own files
ls -la / | grep tmp
# drwxrwxrwt  — the 't' means sticky bit is set

# SetUID on /usr/bin/passwd — runs as root even when called by normal user
ls -la /usr/bin/passwd
# -rwsr-xr-x — the 's' means SetUID is set
```

### Changing ownership

```bash
# Change owner
chown fasih myfile

# Change owner and group
chown fasih:developers myfile

# Change recursively
chown -R fasih:developers /var/www/

# Change group only
chgrp developers myfile
```

---

## 8. File Descriptors & I/O Redirection

Every process gets three standard file descriptors when it starts:

| FD | Name | Default | Description |
|----|------|---------|-------------|
| 0 | stdin | Keyboard | Standard input |
| 1 | stdout | Terminal | Standard output |
| 2 | stderr | Terminal | Standard error |

### Redirection

```bash
# Redirect stdout to a file (overwrite)
command > output.txt

# Redirect stdout to a file (append)
command >> output.txt

# Redirect stderr to a file
command 2> errors.txt

# Redirect both stdout and stderr to same file
command > output.txt 2>&1
command &> output.txt          # shorthand

# Discard all output
command > /dev/null 2>&1

# Redirect file as stdin
command < input.txt

# Here document — multiline stdin
cat << EOF
line 1
line 2
EOF
```

### Pipes

A pipe connects stdout of one command to stdin of the next:

```bash
# Basic pipe
cat /var/log/syslog | grep ERROR

# Chain multiple pipes
cat /var/log/syslog | grep ERROR | awk '{print $5}' | sort | uniq -c | sort -rn

# tee — write to file AND pass to next command
command | tee output.txt | grep something
```

### Named pipes (FIFOs)

```bash
# Create a named pipe
mkfifo /tmp/mypipe

# Process 1 writes to it
echo "hello" > /tmp/mypipe

# Process 2 reads from it (blocks until data arrives)
cat /tmp/mypipe
```

---

## 9. The Boot Process

Understanding boot helps you debug systems that won't start.

```
Power on
    │
    ▼
BIOS / UEFI
  Performs POST (Power-On Self Test)
  Finds bootable device
    │
    ▼
Bootloader (GRUB2)
  Loads the kernel and initrd from /boot/
  Passes kernel parameters (e.g. root filesystem location)
    │
    ▼
Kernel
  Decompresses itself into memory
  Detects hardware, loads drivers
  Mounts initrd (temporary root filesystem)
  Mounts real root filesystem
  Starts PID 1
    │
    ▼
PID 1 — systemd (or init on older systems)
  Reads unit files from /etc/systemd/system/
  Starts services in dependency order
  Reaches the target (e.g. multi-user.target)
    │
    ▼
Login prompt / SSH available
```

### Key boot files

```bash
/boot/vmlinuz-*      # Compressed kernel image
/boot/initrd.img-*   # Initial RAM disk (temporary root FS)
/boot/grub/grub.cfg  # GRUB bootloader config

/etc/systemd/system/ # systemd unit files (your services)
/lib/systemd/system/ # Default systemd unit files (packages)
```

---

## 10. Kernel & System Calls

### What is a system call?

User-space programs can't directly access hardware. They must ask the kernel through **system calls (syscalls)**. Common syscalls:

| Syscall | What it does |
|---------|-------------|
| `open()` | Open a file |
| `read()` | Read from file descriptor |
| `write()` | Write to file descriptor |
| `fork()` | Create a child process |
| `exec()` | Replace process image with new program |
| `exit()` | Terminate process |
| `socket()` | Create a network socket |
| `mmap()` | Map file or memory into address space |

### Kernel parameters (sysctl)

The kernel exposes tunable parameters via `/proc/sys/` and the `sysctl` command. These are important for performance tuning in Kubernetes nodes.

```bash
# View all kernel parameters
sysctl -a

# View a specific parameter
sysctl net.ipv4.ip_forward

# Set temporarily (lost on reboot)
sysctl -w net.ipv4.ip_forward=1

# Set permanently
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
sysctl -p     # reload
```

### Important kernel parameters for DevOps

```bash
# Enable IP forwarding (required for Kubernetes networking)
net.ipv4.ip_forward = 1

# Increase max open files (important for high-traffic services)
fs.file-max = 2097152

# Increase network connection backlog
net.core.somaxconn = 65535

# Disable swap (required for Kubernetes)
vm.swappiness = 0

# Increase inotify watches (needed for many dev tools)
fs.inotify.max_user_watches = 524288
```

---

## 11. Linux in the Context of DevOps & Containers

### How containers use Linux primitives

Containers are not magic — they're just Linux processes with extra isolation. Kubernetes and Docker use these kernel features:

| Linux Feature | What it provides | Used for |
|--------------|----------------|---------|
| **Namespaces** | Isolation — process can't see outside its namespace | PID, network, mount, user isolation per container |
| **cgroups** | Resource limits — CPU, memory, I/O per group | Kubernetes resource requests/limits |
| **seccomp** | Syscall filtering — block dangerous syscalls | Container security policies |
| **capabilities** | Fine-grained root privileges | Running containers without full root |
| **overlayfs** | Layered filesystem | Container image layers |

### Namespaces — what each container gets

```
Container
├── PID namespace      → container has its own PID 1
├── Network namespace  → container has its own network interface, IP
├── Mount namespace    → container has its own filesystem view
├── UTS namespace      → container has its own hostname
├── IPC namespace      → container has its own shared memory
└── User namespace     → container can have its own UID mapping
```

```bash
# See namespaces of a running container
docker inspect <container-id> | grep -i pid
ls -la /proc/<pid>/ns/
```

### cgroups — how resource limits work

When you set `resources.limits.cpu: "500m"` in a Kubernetes pod spec, Kubernetes creates a cgroup that limits that container to 0.5 CPU cores. The kernel enforces this at the hardware level.

```bash
# See cgroups for a container
cat /sys/fs/cgroup/memory/kubepods/.../memory.limit_in_bytes
cat /sys/fs/cgroup/cpu/kubepods/.../cpu.cfs_quota_us
```

### OOMKill — what actually happens

When a container exceeds its memory limit:
1. The kernel's OOM (Out of Memory) killer triggers
2. It selects the process exceeding the limit
3. Sends `SIGKILL` — no cleanup, immediate death
4. Kubernetes sees the container exit with code 137 (128 + 9)
5. Kubernetes restarts the container (CrashLoopBackOff if it keeps happening)

```bash
# Check for OOMKills
dmesg | grep -i "oom\|killed"
kubectl describe pod <pod> | grep -i oom
```

---

## Key Terms Glossary

| Term | Definition |
|------|-----------|
| **Kernel** | Core of the OS — manages hardware, processes, memory, networking |
| **User space** | Everything running outside the kernel (apps, shells, libraries) |
| **Syscall** | A request from user space to the kernel to perform privileged work |
| **PID** | Process ID — unique number identifying a running process |
| **PPID** | Parent Process ID — the process that created this one |
| **fork()** | System call that creates a copy of the current process |
| **exec()** | System call that replaces the current process with a new program |
| **Signal** | Software interrupt sent to a process |
| **SIGTERM** | Polite shutdown request — process can catch and handle it |
| **SIGKILL** | Forced kill by the kernel — cannot be caught or ignored |
| **File descriptor** | An integer handle for an open file, socket, or pipe |
| **stdin/stdout/stderr** | Standard input (0), output (1), and error (2) streams |
| **Pipe** | Connects stdout of one process to stdin of another |
| **UID** | User ID — number identifying a user (root = 0) |
| **GID** | Group ID — number identifying a group |
| **chmod** | Change file permissions |
| **chown** | Change file ownership |
| **Sticky bit** | Only file owner can delete files in a directory |
| **SetUID** | Run executable as its owner, not the calling user |
| **Namespace** | Linux isolation mechanism — separates PID, network, filesystem views |
| **cgroup** | Linux mechanism for limiting and accounting resource usage |
| **OOMKill** | Kernel killing a process that exceeded its memory limit |
| **inode** | Data structure storing file metadata (permissions, timestamps, size) |
| **Symlink** | Symbolic link — a pointer to another file or directory |
| **Hardlink** | Another directory entry pointing to the same inode |
| **GRUB** | Bootloader — loads the kernel at system start |
| **initrd** | Temporary root filesystem used during kernel boot |
| **systemd** | PID 1 on modern Linux — manages services and the boot process |
| **sysctl** | Tool to read and write kernel parameters at runtime |
| **/proc** | Virtual filesystem exposing live kernel and process information |
| **D state** | Uninterruptible sleep — process waiting for I/O, cannot be killed |
| **Zombie** | A process that has exited but whose parent hasn't called wait() |
| **overlayfs** | Layered filesystem used by Docker/containerd for container images |

---

*Next: [Essential Commands →](./02-essential-commands.md) — the commands you'll use every day as a DevOps engineer.*
