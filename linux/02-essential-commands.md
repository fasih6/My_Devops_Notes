# 🛠️ Essential Linux Commands

The commands every DevOps engineer reaches for daily — with real examples, not just syntax.

> Don't memorize these. Understand what they do and when to reach for them. The rest comes with practice.

---

## 📚 Table of Contents

- [1. Navigation & File Operations](#1-navigation--file-operations)
- [2. Viewing & Searching Files](#2-viewing--searching-files)
- [3. Process Management](#3-process-management)
- [4. User & Permission Commands](#4-user--permission-commands)
- [5. Networking Commands](#5-networking-commands)
- [6. Disk & Storage Commands](#6-disk--storage-commands)
- [7. System Information](#7-system-information)
- [8. Package Management](#8-package-management)
- [9. Text Processing](#9-text-processing)
- [10. Archiving & Compression](#10-archiving--compression)
- [11. SSH & Remote Operations](#11-ssh--remote-operations)
- [12. Everyday DevOps One-Liners](#12-everyday-devops-one-liners)

---

## 1. Navigation & File Operations

```bash
# Navigation
pwd                        # print current directory
cd /etc/nginx              # go to directory
cd ~                       # go to home directory
cd -                       # go to previous directory
ls -la                     # list all files with details
ls -lah                    # same but human-readable sizes
tree /etc/systemd          # tree view of directory (install: apt install tree)

# File operations
cp file.txt backup.txt     # copy file
cp -r dir/ backup/         # copy directory recursively
mv old.txt new.txt         # move or rename
rm file.txt                # delete file
rm -rf dir/                # delete directory and contents (careful!)
mkdir -p /opt/app/config   # create directory and parents
touch file.txt             # create empty file or update timestamp
ln -s /etc/nginx /opt/nginx-config  # create symlink
ln file.txt hardlink.txt   # create hardlink

# Find files
find / -name "nginx.conf"              # find by name
find /var/log -name "*.log" -mtime -1  # logs modified in last 1 day
find /tmp -size +100M                  # files larger than 100MB
find . -type f -name "*.sh" -exec chmod +x {} \;  # find and execute
locate nginx.conf                      # fast find (uses index, run updatedb first)
which kubectl                          # find binary location
whereis nginx                          # find binary, source, and man pages
```

---

## 2. Viewing & Searching Files

```bash
# View file contents
cat file.txt               # print entire file
cat -n file.txt            # with line numbers
less file.txt              # paginated view (q to quit, / to search)
head -n 20 file.txt        # first 20 lines
tail -n 50 file.txt        # last 50 lines
tail -f /var/log/syslog    # follow log in real time (Ctrl+C to stop)
tail -f /var/log/syslog | grep ERROR  # follow and filter

# Search inside files
grep "ERROR" /var/log/app.log             # search for pattern
grep -i "error" /var/log/app.log          # case insensitive
grep -r "database" /etc/                  # search recursively
grep -n "ERROR" app.log                   # show line numbers
grep -v "DEBUG" app.log                   # exclude lines matching pattern
grep -c "ERROR" app.log                   # count matching lines
grep -A 5 "ERROR" app.log                 # 5 lines after match
grep -B 3 "ERROR" app.log                 # 3 lines before match
grep -E "ERROR|WARN" app.log              # extended regex (OR)
grep -l "nginx" /etc/**/*.conf            # list files containing pattern

# Search with context (great for debugging)
grep -A 10 -B 5 "Exception" app.log      # 5 lines before, 10 after

# Difference between files
diff file1.txt file2.txt
diff -u file1.txt file2.txt              # unified format (like git diff)

# Word count
wc -l file.txt             # count lines
wc -w file.txt             # count words
wc -c file.txt             # count bytes
```

---

## 3. Process Management

```bash
# View processes
ps aux                     # all processes, detailed
ps aux | grep nginx        # find specific process
ps -ef --forest            # tree view showing parent-child relationships
pgrep nginx                # get PID(s) of process by name
pidof nginx                # same as pgrep

# Interactive process viewers
top                        # live process monitor (q to quit)
htop                       # better top — color, mouse support (apt install htop)

# top keyboard shortcuts:
# P — sort by CPU
# M — sort by memory
# k — kill a process
# r — renice (change priority)
# 1 — show per-CPU stats

# Kill processes
kill 1234                  # send SIGTERM to PID 1234
kill -9 1234               # send SIGKILL (force kill)
kill -HUP 1234             # send SIGHUP (reload config)
killall nginx              # kill all processes named nginx
pkill -f "python app.py"   # kill by matching full command line

# Background / foreground
command &                  # run in background
jobs                       # list background jobs
fg %1                      # bring job 1 to foreground
bg %1                      # send job 1 to background
nohup command &            # run command immune to hangup (survives logout)
disown %1                  # detach job from shell (won't be killed on logout)

# Process priority
nice -n 10 command         # start with low priority (nice 10)
renice -n 5 -p 1234        # change priority of running process

# Wait for processes
wait                       # wait for all background jobs to finish
wait 1234                  # wait for specific PID
```

---

## 4. User & Permission Commands

```bash
# User info
whoami                     # current username
id                         # UID, GID, and groups
id fasih                   # info for another user
groups                     # list your groups
w                          # who is logged in and what they're doing
last                       # login history
lastlog                    # last login for all users

# Switch users
sudo command               # run command as root
sudo -u postgres psql      # run as specific user
sudo -i                    # interactive root shell
su - fasih                 # switch to user fasih

# User management
useradd -m -s /bin/bash fasih      # create user with home dir and bash shell
usermod -aG docker fasih           # add user to docker group
usermod -aG sudo fasih             # add user to sudo group
userdel -r fasih                   # delete user and home directory
passwd fasih                       # set user password
chage -l fasih                     # password expiry info

# Permissions
chmod 755 script.sh                # rwxr-xr-x
chmod +x script.sh                 # add execute for all
chmod -R 644 /var/www/html/        # recursive
chmod u+x,g-w,o-rwx file          # symbolic mode
chown fasih:developers file.txt    # change owner and group
chown -R www-data /var/www/        # recursive ownership change
chgrp developers file.txt          # change group only

# Check effective permissions
namei -l /path/to/file             # show permissions at each path component
stat file.txt                      # detailed file metadata
```

---

## 5. Networking Commands

```bash
# Interface and IP info
ip addr                    # show all interfaces and IPs (modern)
ip addr show eth0          # show specific interface
ip link                    # show link state
ip route                   # show routing table
ip route show default      # show default gateway

# Test connectivity
ping -c 4 google.com       # ping 4 times and stop
traceroute google.com      # trace network path
mtr google.com             # combined ping + traceroute (apt install mtr)

# DNS
dig google.com             # DNS lookup
dig google.com A           # lookup A records
dig @8.8.8.8 google.com    # use specific DNS server
nslookup google.com        # simpler DNS lookup

# Connections and ports
ss -tuln                   # listening TCP/UDP sockets (modern netstat)
ss -tulnp                  # with process names (needs sudo)
ss -tnp                    # established TCP connections with process
lsof -i :8080              # what process is using port 8080

# HTTP requests
curl https://example.com                      # basic GET
curl -I https://example.com                   # headers only
curl -X POST -d '{"key":"val"}' \
  -H "Content-Type: application/json" \
  https://api.example.com                     # POST with JSON
curl -o output.html https://example.com       # save to file
curl -L https://example.com                   # follow redirects
curl -v https://example.com                   # verbose (shows TLS, headers)
curl -w "%{http_code}" -o /dev/null \
  https://example.com                         # just status code
wget https://example.com/file.tar.gz          # download file

# Firewall
iptables -L -n -v          # list all rules with counters
ufw status                 # Ubuntu firewall status
ufw allow 80               # allow port 80

# Network capture (debugging)
tcpdump -i eth0            # capture on interface
tcpdump -i eth0 port 80    # capture HTTP traffic
tcpdump -i eth0 host 10.0.0.1  # capture traffic to/from IP
tcpdump -w capture.pcap    # write to file for Wireshark
```

---

## 6. Disk & Storage Commands

```bash
# Disk usage
df -h                      # disk space usage (human-readable)
df -hT                     # with filesystem types
du -sh /var/log/           # size of directory
du -sh /var/log/*          # size of each item in directory
du -sh * | sort -h         # sort by size
du --max-depth=1 -h /      # top-level directory sizes

# Block devices
lsblk                      # list block devices (disks, partitions)
lsblk -f                   # with filesystem info
fdisk -l                   # list partitions (needs sudo)
blkid                      # show UUIDs and filesystem types

# Mount / unmount
mount                      # show all mounted filesystems
mount /dev/sdb1 /mnt/data  # mount a partition
umount /mnt/data           # unmount
mount -t nfs server:/share /mnt/nfs  # mount NFS

# Inodes (when "disk full" but df shows space)
df -i                      # inode usage
find / -xdev -printf '%h\n' \
  | sort | uniq -c \
  | sort -rn | head         # dirs with most files

# Swap
swapon --show              # show swap devices and usage
free -h                    # memory and swap overview
swapoff -a                 # disable all swap (required for Kubernetes)

# /proc filesystem for memory details
cat /proc/meminfo          # detailed memory breakdown
```

---

## 7. System Information

```bash
# System overview
uname -a                   # kernel version, architecture, hostname
uname -r                   # kernel version only
hostname                   # system hostname
hostname -I                # all IP addresses
uptime                     # how long running, load averages
cat /etc/os-release        # OS name and version

# Hardware
lscpu                      # CPU info (cores, threads, architecture)
lsmem                      # memory info
lspci                      # PCI devices (network cards, GPUs)

# Load and performance
vmstat 1 5                 # memory, swap, CPU stats every 1s, 5 times
iostat -x 1                # disk I/O stats (apt install sysstat)

# Memory
free -h                    # RAM and swap usage
cat /proc/meminfo          # detailed breakdown

# Logs
journalctl                         # all systemd journal logs
journalctl -u nginx                # logs for nginx service
journalctl -u nginx --since today  # today's nginx logs
journalctl -f                      # follow live logs
journalctl -p err                  # only error level and above
journalctl --since "2024-01-15 10:00" \
  --until "2024-01-15 11:00"       # time range
dmesg | tail -20                   # recent kernel messages
dmesg | grep -i error              # kernel errors
```

---

## 8. Package Management

```bash
# Debian / Ubuntu (apt)
apt update                         # update package index
apt upgrade                        # upgrade all packages
apt install nginx                  # install package
apt remove nginx                   # remove package
apt purge nginx                    # remove package and config files
apt autoremove                     # remove unused dependencies
apt search nginx                   # search for package
apt show nginx                     # package details
dpkg -l | grep nginx               # list installed packages matching name
dpkg -L nginx                      # list files installed by package

# RHEL / CentOS / Amazon Linux (yum/dnf)
yum update                         # update all
yum install nginx                  # install
yum remove nginx                   # remove
dnf install nginx                  # dnf is newer yum replacement
rpm -qa | grep nginx               # list installed RPM packages

# Install from binary (common for DevOps tools)
curl -LO "https://dl.k8s.io/release/$(curl -L -s \
  https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
sudo mv kubectl /usr/local/bin/
```

---

## 9. Text Processing

These are essential for log analysis and automation:

```bash
# awk — column-based text processing
awk '{print $1}' file.txt            # print first column
awk '{print $1, $3}' file.txt        # print columns 1 and 3
awk -F: '{print $1}' /etc/passwd     # use : as delimiter, print usernames
awk '/ERROR/ {print $0}' app.log     # print lines matching pattern
awk '{sum += $3} END {print sum}'    # sum column 3
awk 'NR==5' file.txt                 # print line 5
awk 'NR>=5 && NR<=10' file.txt       # print lines 5-10

# sed — stream editor for substitution
sed 's/old/new/' file.txt            # replace first occurrence per line
sed 's/old/new/g' file.txt           # replace all occurrences
sed -i 's/old/new/g' file.txt        # edit file in place
sed -n '5,10p' file.txt              # print lines 5-10
sed '/^#/d' file.txt                 # delete comment lines
sed 's/^[[:space:]]*//' file.txt     # remove leading whitespace

# sort and uniq
sort file.txt                        # alphabetical sort
sort -n file.txt                     # numeric sort
sort -rn file.txt                    # reverse numeric sort
sort -k2 file.txt                    # sort by column 2
uniq file.txt                        # remove consecutive duplicates
uniq -c file.txt                     # count occurrences
sort file.txt | uniq -c | sort -rn   # frequency count (very useful)

# cut — extract columns
cut -d: -f1 /etc/passwd              # extract usernames (delimiter :, field 1)
cut -d, -f1,3 data.csv               # extract columns 1 and 3 from CSV

# tr — translate or delete characters
echo "Hello World" | tr 'a-z' 'A-Z' # uppercase
echo "a:b:c" | tr ':' ','           # replace : with ,
cat file.txt | tr -d '\r'           # remove carriage returns (Windows files)

# xargs — build commands from stdin
cat list.txt | xargs rm              # delete files listed in list.txt
find . -name "*.log" | xargs gzip   # compress all log files
echo "1 2 3" | xargs -n1 echo       # process one item at a time

# Practical log analysis pipeline
cat /var/log/nginx/access.log \
  | awk '{print $9}' \               # extract status codes
  | sort \
  | uniq -c \                        # count each status code
  | sort -rn                         # sort by frequency
```

---

## 10. Archiving & Compression

```bash
# tar — most common
# Flags: c=create x=extract z=gzip j=bzip2 v=verbose f=filename t=list C=directory
tar -czf archive.tar.gz dir/         # create gzip compressed archive
tar -cjf archive.tar.bz2 dir/        # create bzip2 compressed archive
tar -xzf archive.tar.gz              # extract gzip archive
tar -xzf archive.tar.gz -C /opt/     # extract to specific directory
tar -tzf archive.tar.gz              # list contents without extracting
tar -czf backup.tar.gz \
  --exclude='*.log' /var/www/        # exclude files

# gzip / gunzip
gzip file.txt                        # compress (removes original)
gzip -k file.txt                     # keep original
gunzip file.txt.gz                   # decompress
zcat file.txt.gz                     # read compressed file without extracting

# zip / unzip
zip -r archive.zip dir/              # create zip recursively
unzip archive.zip                    # extract
unzip -l archive.zip                 # list contents
```

---

## 11. SSH & Remote Operations

```bash
# Basic SSH
ssh user@server                      # connect to server
ssh -p 2222 user@server              # non-standard port
ssh -i ~/.ssh/id_rsa user@server     # specify key file
ssh -J bastion user@internal-server  # jump through bastion host

# SSH key management
ssh-keygen -t ed25519 -C "fasih@work"  # generate ED25519 key (preferred)
ssh-keygen -t rsa -b 4096              # generate RSA 4096 key
ssh-copy-id user@server                # copy public key to server

# SSH config file (~/.ssh/config) — saves typing
# Host prod-server
#     HostName 10.0.0.100
#     User fasih
#     IdentityFile ~/.ssh/prod_key
#
# Host internal
#     HostName 192.168.1.50
#     ProxyJump bastion     ← auto jump through bastion
#
# Then just: ssh prod-server

# Copy files
scp file.txt user@server:/tmp/          # copy file to server
scp user@server:/tmp/file.txt .         # copy from server
scp -r dir/ user@server:/opt/           # copy directory
rsync -avz dir/ user@server:/opt/dir/   # sync (faster, resumable)
rsync -avz --delete dir/ \
  user@server:/opt/dir/                 # sync and delete removed files

# Port forwarding
ssh -L 8080:localhost:80 user@server    # forward local 8080 to server port 80
ssh -R 8080:localhost:3000 user@server  # reverse — expose local port via server

# Execute remote command
ssh user@server "df -h"
ssh user@server "sudo systemctl restart nginx"
ssh user@server < script.sh             # run local script on remote server

# SSH security (/etc/ssh/sshd_config)
# PermitRootLogin no
# PasswordAuthentication no
# PubkeyAuthentication yes
# AllowUsers fasih
```

---

## 12. Everyday DevOps One-Liners

Real commands for real situations:

```bash
# Find what's using disk space
du -sh /* 2>/dev/null | sort -h | tail -20

# Watch a command refresh every 2 seconds
watch -n 2 'kubectl get pods -n monitoring'
watch -n 1 'ss -tnp | grep :80'

# Monitor log file for errors
tail -f /var/log/app.log | grep --line-buffered "ERROR\|WARN"

# Check if a port is open on a remote host
nc -zv google.com 443

# See what files a process has open
lsof -p 1234                       # by PID
lsof /var/log/nginx/access.log     # who has this file open

# Count HTTP status codes in nginx access log
awk '{print $9}' /var/log/nginx/access.log \
  | sort | uniq -c | sort -rn

# Replace text across multiple files
find . -name "*.conf" \
  -exec sed -i 's/old-hostname/new-hostname/g' {} \;

# Run a command on multiple servers
for server in web1 web2 web3; do
  echo "=== $server ==="
  ssh $server "uptime && df -h /"
done

# Create a timestamped backup
cp nginx.conf nginx.conf.bak.$(date +%Y%m%d-%H%M%S)

# Check TLS certificate expiry date
echo | openssl s_client -connect example.com:443 2>/dev/null \
  | openssl x509 -noout -dates

# Kill whatever is using port 8080
kill $(lsof -t -i:8080)

# Generate a random password
openssl rand -base64 32

# Decode a Kubernetes secret (base64)
kubectl get secret my-secret -o jsonpath='{.data.password}' | base64 -d

# Quick HTTP server to share files in current directory
python3 -m http.server 8080

# Tail multiple log files at once
tail -f /var/log/nginx/access.log /var/log/nginx/error.log

# Find processes in D state (uninterruptible sleep — usually disk/NFS issue)
ps aux | awk '$8 == "D" {print}'

# Check OOMKill events
dmesg | grep -i "killed process"

# Monitor memory of a specific process every second
watch -n 1 "ps -p $(pidof nginx) -o pid,vsz,rss,pmem,cmd"
```

---

*Next: [Process Management →](./03-linux-process-management.md) — systemd, services, and keeping processes alive.*
