# 🐚 Shell Scripting

Write bash scripts that actually work in production — reliable, readable, and debuggable.

> Shell scripting is the glue of DevOps. Deployments, backups, health checks, automation — all of it runs on bash. Write it well and it saves hours. Write it badly and it causes incidents.

---

## 📚 Table of Contents

- [1. Bash Fundamentals](#1-bash-fundamentals)
- [2. Variables & Data Types](#2-variables--data-types)
- [3. Control Flow](#3-control-flow)
- [4. Functions](#4-functions)
- [5. Input & Output](#5-input--output)
- [6. String Operations](#6-string-operations)
- [7. Arrays](#7-arrays)
- [8. Error Handling](#8-error-handling)
- [9. Pipes & Advanced I/O](#9-pipes--advanced-io)
- [10. Script Structure & Best Practices](#10-script-structure--best-practices)
- [11. Real-World DevOps Scripts](#11-real-world-devops-scripts)
- [12. Debugging Scripts](#12-debugging-scripts)
- [Cheatsheet](#cheatsheet)

---

## 1. Bash Fundamentals

### The shebang line

Every script starts with a shebang — it tells the OS which interpreter to use:

```bash
#!/bin/bash        # use bash explicitly
#!/usr/bin/env bash  # find bash in PATH (more portable)
#!/bin/sh          # POSIX sh — portable but fewer features
```

Use `#!/usr/bin/env bash` for most scripts — it works across different Linux distributions and macOS.

### Making a script executable

```bash
# Create script
touch deploy.sh

# Make executable
chmod +x deploy.sh

# Run it
./deploy.sh

# Or run without making executable
bash deploy.sh
```

### Script exit codes

Every command returns an exit code:
- `0` = success
- Non-zero = failure (1-255, convention: 1 = general error, 2 = misuse, 127 = command not found)

```bash
# Check exit code of last command
echo $?

# Set exit code when exiting
exit 0    # success
exit 1    # general failure
exit 2    # usage error

# Practical example
ls /nonexistent
echo $?   # prints 2

cp file.txt backup.txt
echo $?   # prints 0 if successful
```

---

## 2. Variables & Data Types

### Declaring and using variables

```bash
# Assign (no spaces around =)
NAME="fasih"
AGE=25
IS_PROD=true

# Use (always quote variables)
echo "$NAME"
echo "Hello, $NAME!"
echo "Age: ${AGE}"

# Command substitution — store output of a command
DATE=$(date +%Y-%m-%d)
HOSTNAME=$(hostname)
FREE_MEMORY=$(free -m | awk '/^Mem/ {print $4}')

# Arithmetic
COUNT=5
TOTAL=$((COUNT + 3))    # 8
echo $((10 * 5 - 2))   # 48

# Read-only variables (constants)
readonly MAX_RETRIES=3
declare -r DB_PORT=5432
```

### Variable quoting — the most important rule

```bash
FILENAME="my file.txt"   # filename with a space

# Wrong — treats space as separator, 2 arguments
cp $FILENAME backup      # equivalent to: cp my file.txt backup

# Correct — quotes preserve the space
cp "$FILENAME" backup    # equivalent to: cp "my file.txt" backup

# Single quotes — no expansion at all
echo '$NAME'             # prints: $NAME (literal)
echo "$NAME"             # prints: fasih (expanded)

# Always quote variables unless you specifically need word splitting
```

### Special variables

| Variable | Meaning |
|----------|---------|
| `$0` | Script name |
| `$1`, `$2`, ... | Positional arguments |
| `$#` | Number of arguments |
| `$@` | All arguments as separate words |
| `$*` | All arguments as single string |
| `$$` | Current script's PID |
| `$!` | PID of last background command |
| `$?` | Exit code of last command |
| `$_` | Last argument of previous command |

```bash
#!/usr/bin/env bash
echo "Script name: $0"
echo "First arg:   $1"
echo "All args:    $@"
echo "Arg count:   $#"

# Calling: ./deploy.sh production v1.2.3
# Script name: ./deploy.sh
# First arg:   production
# All args:    production v1.2.3
# Arg count:   2
```

### Environment variables

```bash
# View all environment variables
env
printenv

# View specific variable
echo $PATH
printenv HOME

# Export — make available to child processes
export DB_HOST="10.0.0.5"
export DB_PORT=5432

# Source a file to load variables into current shell
source .env
. .env              # same thing, shorter

# Unset a variable
unset DB_HOST

# Default values (very useful for optional config)
DB_HOST="${DB_HOST:-localhost}"       # use localhost if DB_HOST is unset
DB_PORT="${DB_PORT:-5432}"            # use 5432 if DB_PORT is unset
ENVIRONMENT="${1:-development}"       # use first arg or default to "development"

# Required variables — fail if not set
: "${DB_PASSWORD:?DB_PASSWORD must be set}"
: "${API_KEY:?API_KEY must be set}"
```

---

## 3. Control Flow

### if / elif / else

```bash
# Basic syntax
if [ condition ]; then
    commands
elif [ other_condition ]; then
    commands
else
    commands
fi

# Prefer [[ ]] over [ ] — more features, fewer surprises
if [[ "$ENV" == "production" ]]; then
    echo "Running in production"
fi
```

### Test conditions

```bash
# String comparisons
[[ "$A" == "$B" ]]     # equal
[[ "$A" != "$B" ]]     # not equal
[[ -z "$A" ]]          # empty string
[[ -n "$A" ]]          # non-empty string
[[ "$A" =~ ^[0-9]+$ ]] # regex match

# Numeric comparisons
[[ $A -eq $B ]]        # equal
[[ $A -ne $B ]]        # not equal
[[ $A -lt $B ]]        # less than
[[ $A -le $B ]]        # less than or equal
[[ $A -gt $B ]]        # greater than
[[ $A -ge $B ]]        # greater than or equal

# File tests
[[ -f "$FILE" ]]       # exists and is a regular file
[[ -d "$DIR" ]]        # exists and is a directory
[[ -e "$PATH" ]]       # exists (any type)
[[ -r "$FILE" ]]       # exists and is readable
[[ -w "$FILE" ]]       # exists and is writable
[[ -x "$FILE" ]]       # exists and is executable
[[ -s "$FILE" ]]       # exists and is non-empty
[[ -L "$FILE" ]]       # exists and is a symlink

# Logical operators
[[ $A && $B ]]         # AND
[[ $A || $B ]]         # OR
[[ ! $A ]]             # NOT

# Combining
if [[ -f "$CONFIG" && -r "$CONFIG" ]]; then
    source "$CONFIG"
fi
```

### for loops

```bash
# Loop over a list
for item in one two three; do
    echo "$item"
done

# Loop over files
for file in /etc/nginx/*.conf; do
    echo "Processing: $file"
    nginx -t -c "$file"
done

# Loop over array
SERVERS=("web1" "web2" "web3")
for server in "${SERVERS[@]}"; do
    ssh "$server" "systemctl status nginx"
done

# C-style loop
for ((i=1; i<=10; i++)); do
    echo "Attempt $i"
done

# Loop over command output
for pid in $(pgrep nginx); do
    echo "Nginx PID: $pid"
done

# Loop with index
for i in "${!SERVERS[@]}"; do
    echo "Server $i: ${SERVERS[$i]}"
done
```

### while loops

```bash
# Basic while
COUNT=0
while [[ $COUNT -lt 5 ]]; do
    echo "Count: $COUNT"
    ((COUNT++))
done

# Read file line by line (correct way)
while IFS= read -r line; do
    echo "$line"
done < /etc/hosts

# Read command output line by line
while IFS= read -r container; do
    docker inspect "$container"
done < <(docker ps -q)   # process substitution

# Infinite loop with break
while true; do
    if ping -c1 google.com &>/dev/null; then
        echo "Network is up"
        break
    fi
    echo "Waiting for network..."
    sleep 5
done

# until loop — opposite of while
until [[ -f /tmp/ready ]]; do
    echo "Waiting for ready file..."
    sleep 2
done
```

### case statement

```bash
ENVIRONMENT="$1"

case "$ENVIRONMENT" in
    production|prod)
        DB_HOST="prod-db.internal"
        LOG_LEVEL="error"
        ;;
    staging|stage)
        DB_HOST="staging-db.internal"
        LOG_LEVEL="warn"
        ;;
    development|dev)
        DB_HOST="localhost"
        LOG_LEVEL="debug"
        ;;
    *)
        echo "Unknown environment: $ENVIRONMENT" >&2
        echo "Usage: $0 [production|staging|development]" >&2
        exit 1
        ;;
esac

echo "Connecting to: $DB_HOST"
```

---

## 4. Functions

```bash
# Define a function
greet() {
    local name="$1"          # local variable — only exists in function
    echo "Hello, $name!"
}

# Call it
greet "fasih"

# Function with return value (exit code)
is_running() {
    local service="$1"
    systemctl is-active --quiet "$service"
    # returns 0 if active, non-zero if not
}

if is_running nginx; then
    echo "nginx is running"
fi

# Function that outputs a value
get_container_id() {
    local name="$1"
    docker ps --filter "name=$name" --format "{{.ID}}" | head -1
}

CONTAINER_ID=$(get_container_id "my-app")

# Function with error handling
create_backup() {
    local source="$1"
    local dest="$2"

    if [[ ! -d "$source" ]]; then
        echo "ERROR: Source directory does not exist: $source" >&2
        return 1
    fi

    tar -czf "${dest}/backup-$(date +%Y%m%d).tar.gz" "$source" || {
        echo "ERROR: Backup failed" >&2
        return 1
    }

    echo "Backup created successfully"
    return 0
}

# Usage
create_backup /var/www /opt/backups || exit 1
```

---

## 5. Input & Output

### Reading user input

```bash
# Basic read
read -p "Enter your name: " NAME
echo "Hello, $NAME"

# Read with timeout
read -t 10 -p "Continue? [y/N]: " ANSWER
if [[ $? -ne 0 ]]; then
    echo "Timed out — defaulting to No"
    ANSWER="n"
fi

# Read a password (no echo)
read -s -p "Password: " PASSWORD
echo ""   # newline after silent input

# Read into array
read -ra PARTS <<< "one two three"
echo "${PARTS[0]}"   # one

# Confirm before destructive action
confirm() {
    read -r -p "${1:-Are you sure?} [y/N]: " response
    [[ "$response" =~ ^[Yy]$ ]]
}

if confirm "Delete all logs?"; then
    rm -rf /var/log/app/
fi
```

### Output — stdout and stderr

```bash
# Standard output (stdout)
echo "This is normal output"
printf "Formatted: %s = %d\n" "count" 42

# Standard error (stderr) — always send errors here
echo "ERROR: file not found" >&2

# Formatted logging functions (production pattern)
log_info()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] INFO:  $*"; }
log_warn()  { echo "[$(date '+%Y-%m-%d %H:%M:%S')] WARN:  $*" >&2; }
log_error() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" >&2; }

log_info  "Starting deployment"
log_warn  "Config file not found, using defaults"
log_error "Database connection failed"
```

---

## 6. String Operations

```bash
STR="Hello, World!"

# Length
echo "${#STR}"               # 13

# Substring
echo "${STR:7}"              # World!
echo "${STR:7:5}"            # World
echo "${STR: -6}"            # World! (from end)

# Replace
echo "${STR/World/Fasih}"    # Hello, Fasih!    (first match)
echo "${STR//l/L}"           # HeLLo, WorLd!   (all matches)

# Remove prefix/suffix
FILE="backup-2024-01-15.tar.gz"
echo "${FILE#backup-}"       # 2024-01-15.tar.gz  (remove prefix)
echo "${FILE##*.}"           # gz                 (remove longest prefix up to .)
echo "${FILE%.tar.gz}"       # backup-2024-01-15  (remove suffix)
echo "${FILE%.*}"            # backup-2024-01-15.tar (remove shortest suffix)

# Case conversion
NAME="hello world"
echo "${NAME^^}"             # HELLO WORLD (uppercase)
echo "${NAME,,}"             # hello world (lowercase)

# Check if string contains substring
if [[ "$STR" == *"World"* ]]; then
    echo "Found World"
fi

# Split string
CSV="one,two,three"
IFS=',' read -ra PARTS <<< "$CSV"
for part in "${PARTS[@]}"; do
    echo "$part"
done

# Trim whitespace
trim() {
    local var="$*"
    var="${var#"${var%%[![:space:]]*}"}"   # trim leading
    var="${var%"${var##*[![:space:]]}"}"   # trim trailing
    echo "$var"
}
```

---

## 7. Arrays

```bash
# Declare array
FRUITS=("apple" "banana" "cherry")
declare -a SERVERS=("web1" "web2" "db1")

# Access elements
echo "${FRUITS[0]}"          # apple
echo "${FRUITS[1]}"          # banana
echo "${FRUITS[-1]}"         # cherry (last element)

# All elements
echo "${FRUITS[@]}"          # apple banana cherry

# Number of elements
echo "${#FRUITS[@]}"         # 3

# Add element
FRUITS+=("date")

# Remove element
unset FRUITS[1]              # removes banana
FRUITS=("${FRUITS[@]}")      # re-index array

# Loop over array
for fruit in "${FRUITS[@]}"; do
    echo "$fruit"
done

# Loop with index
for i in "${!FRUITS[@]}"; do
    echo "$i: ${FRUITS[$i]}"
done

# Associative arrays (key-value, bash 4+)
declare -A CONFIG
CONFIG["host"]="10.0.0.5"
CONFIG["port"]="5432"
CONFIG["db"]="myapp"

echo "${CONFIG[host]}"       # 10.0.0.5

# Loop over associative array
for key in "${!CONFIG[@]}"; do
    echo "$key = ${CONFIG[$key]}"
done
```

---

## 8. Error Handling

This is where most scripts fail in production. Good error handling is what separates a professional script from a fragile one.

### set options — the safety net

```bash
#!/usr/bin/env bash
set -euo pipefail

# set -e  (errexit)  — exit immediately if any command fails
# set -u  (nounset)  — treat unset variables as errors
# set -o pipefail    — pipe fails if any command in it fails

# Equivalent to:
# set -e
# set -u
# set -o pipefail

# Why each matters:
# Without -e: a failed command is silently ignored, script continues
# Without -u: typo in variable name silently expands to empty string
# Without pipefail: grep "pattern" file | wc -l always returns 0 even if grep fails
```

### Trap — run cleanup on exit

```bash
#!/usr/bin/env bash
set -euo pipefail

# Create temp file
TMPFILE=$(mktemp)

# Register cleanup — runs on EXIT (including errors)
cleanup() {
    rm -f "$TMPFILE"
    echo "Cleanup complete"
}
trap cleanup EXIT

# Also trap specific signals
trap 'echo "Script interrupted"; exit 130' INT TERM

# Work with temp file
echo "data" > "$TMPFILE"
process_data "$TMPFILE"
# TMPFILE is automatically deleted when script exits, even on error
```

### Robust error handling pattern

```bash
#!/usr/bin/env bash
set -euo pipefail

# Log file
LOGFILE="/var/log/deploy.log"

# Logging
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"; }
error() { log "ERROR: $*" >&2; exit 1; }

# Check dependencies at startup
check_deps() {
    local deps=("curl" "jq" "kubectl")
    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || error "Required command not found: $dep"
    done
}

# Run a command with retry logic
retry() {
    local max_attempts="${1}"
    local delay="${2}"
    local command="${@:3}"
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        log "Attempt $attempt/$max_attempts: $command"
        if eval "$command"; then
            return 0
        fi
        log "Command failed, retrying in ${delay}s..."
        sleep "$delay"
        ((attempt++))
    done

    error "Command failed after $max_attempts attempts: $command"
}

# Usage
check_deps
retry 3 5 curl -sf https://api.example.com/health
```

---

## 9. Pipes & Advanced I/O

### Pipes and pipelines

```bash
# Basic pipe
cat /var/log/syslog | grep ERROR

# Multi-stage pipeline
cat /var/log/nginx/access.log \
    | awk '{print $9}' \         # extract status codes
    | sort \
    | uniq -c \                  # count each
    | sort -rn \                 # sort descending
    | head -10                   # top 10

# Check if a pattern exists (don't use grep in if — use directly)
if grep -q "ERROR" /var/log/app.log; then
    echo "Errors found"
fi
```

### Process substitution

```bash
# Feed command output to another command expecting a file
diff <(ssh server1 "cat /etc/hosts") <(ssh server2 "cat /etc/hosts")

# Loop over command output without subshell (variables persist)
while IFS= read -r line; do
    echo "$line"
done < <(find /var/log -name "*.log")

# Compare sorted outputs
diff <(sort file1.txt) <(sort file2.txt)
```

### Here documents and here strings

```bash
# Here document — multiline input to a command
cat << 'EOF'
This is line 1
This is line 2
Variables like $HOME are NOT expanded (single-quoted EOF)
EOF

cat << EOF
This IS expanded: $HOME
Today: $(date)
EOF

# Here document to create a file
cat > /etc/nginx/conf.d/myapp.conf << EOF
server {
    listen 80;
    server_name ${DOMAIN};
    location / {
        proxy_pass http://localhost:${APP_PORT};
    }
}
EOF

# Here string — single line input
grep "pattern" <<< "test pattern string"
base64 -d <<< "aGVsbG8="
```

### tee — split output to file AND stdout

```bash
# Log output while still displaying it
./deploy.sh | tee deploy.log

# Append to log
./deploy.sh | tee -a deploy.log

# Pass to multiple commands
cat file.txt | tee >(gzip > file.txt.gz) >(wc -l) > /dev/null
```

---

## 10. Script Structure & Best Practices

### Production-ready script template

```bash
#!/usr/bin/env bash
# =============================================================================
# Script: deploy.sh
# Description: Deploys the application to Kubernetes
# Usage: ./deploy.sh <environment> <version>
# Example: ./deploy.sh production v1.2.3
# =============================================================================

set -euo pipefail
IFS=$'\n\t'           # safer IFS — only split on newline and tab

# =============================================================================
# Constants
# =============================================================================
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly LOG_FILE="/var/log/${SCRIPT_NAME%.sh}.log"
readonly TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# =============================================================================
# Logging
# =============================================================================
log()     { echo "[${TIMESTAMP}] INFO:  $*" | tee -a "$LOG_FILE"; }
warn()    { echo "[${TIMESTAMP}] WARN:  $*" | tee -a "$LOG_FILE" >&2; }
error()   { echo "[${TIMESTAMP}] ERROR: $*" | tee -a "$LOG_FILE" >&2; exit 1; }
success() { echo "[${TIMESTAMP}] OK:    $*" | tee -a "$LOG_FILE"; }

# =============================================================================
# Cleanup
# =============================================================================
cleanup() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]]; then
        error "Script failed with exit code: $exit_code"
    fi
    # Add cleanup tasks here
    log "Script finished"
}
trap cleanup EXIT

# =============================================================================
# Usage
# =============================================================================
usage() {
    cat << EOF
Usage: $SCRIPT_NAME <environment> <version>

Arguments:
  environment   Target environment (production|staging|development)
  version       Version to deploy (e.g. v1.2.3)

Options:
  -h, --help    Show this help message
  -d, --dry-run Show what would happen without doing it

Examples:
  $SCRIPT_NAME production v1.2.3
  $SCRIPT_NAME staging latest
EOF
    exit 0
}

# =============================================================================
# Argument parsing
# =============================================================================
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)    usage ;;
        -d|--dry-run) DRY_RUN=true; shift ;;
        -*) error "Unknown option: $1" ;;
        *)  break ;;
    esac
done

ENVIRONMENT="${1:-}"
VERSION="${2:-}"

[[ -z "$ENVIRONMENT" ]] && error "Environment is required. Use --help for usage."
[[ -z "$VERSION" ]] && error "Version is required. Use --help for usage."

# =============================================================================
# Validation
# =============================================================================
validate_environment() {
    case "$ENVIRONMENT" in
        production|staging|development) ;;
        *) error "Invalid environment: $ENVIRONMENT" ;;
    esac
}

check_dependencies() {
    local deps=("kubectl" "curl" "jq")
    for dep in "${deps[@]}"; do
        command -v "$dep" &>/dev/null || error "Required tool not found: $dep"
    done
}

# =============================================================================
# Main
# =============================================================================
main() {
    log "Starting deployment: env=$ENVIRONMENT version=$VERSION"

    validate_environment
    check_dependencies

    if [[ "$DRY_RUN" == true ]]; then
        log "DRY RUN — no changes will be made"
    fi

    log "Deployment complete"
    success "Version $VERSION deployed to $ENVIRONMENT"
}

main "$@"
```

### Best practices summary

```bash
# 1. Always use set -euo pipefail at the top
set -euo pipefail

# 2. Quote all variables
cp "$SOURCE" "$DEST"       # not: cp $SOURCE $DEST

# 3. Use [[ ]] not [ ]
if [[ -f "$FILE" ]]; then  # not: if [ -f $FILE ]; then

# 4. Use local in functions
my_func() {
    local var="value"       # doesn't leak to global scope
}

# 5. Send errors to stderr
echo "Error: something failed" >&2

# 6. Use readonly for constants
readonly MAX_RETRIES=3

# 7. Check command exists before using it
command -v kubectl &>/dev/null || { echo "kubectl not found"; exit 1; }

# 8. Use mktemp for temp files (never hardcode /tmp/myfile)
TMPFILE=$(mktemp)
trap "rm -f $TMPFILE" EXIT

# 9. Validate all inputs at the start
[[ $# -lt 2 ]] && { echo "Usage: $0 <env> <version>"; exit 1; }

# 10. Test with shellcheck
shellcheck deploy.sh
```

---

## 11. Real-World DevOps Scripts

### Health check and auto-restart

```bash
#!/usr/bin/env bash
# Check if a service is healthy, restart if not
set -euo pipefail

SERVICE="$1"
MAX_FAILURES=3
FAILURES=0

check_health() {
    systemctl is-active --quiet "$SERVICE"
}

while true; do
    if check_health; then
        FAILURES=0
    else
        ((FAILURES++))
        echo "[$(date)] WARNING: $SERVICE is down (failure $FAILURES/$MAX_FAILURES)"

        if [[ $FAILURES -ge $MAX_FAILURES ]]; then
            echo "[$(date)] Restarting $SERVICE..."
            systemctl restart "$SERVICE"
            FAILURES=0
        fi
    fi
    sleep 30
done
```

### Backup script with retention

```bash
#!/usr/bin/env bash
set -euo pipefail

SOURCE_DIR="/var/lib/postgresql/data"
BACKUP_DIR="/opt/backups/postgres"
RETAIN_DAYS=7
DATE=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/postgres-${DATE}.tar.gz"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Create backup
log "Starting backup of $SOURCE_DIR"
tar -czf "$BACKUP_FILE" "$SOURCE_DIR"
log "Backup created: $BACKUP_FILE ($(du -sh "$BACKUP_FILE" | cut -f1))"

# Remove old backups
log "Removing backups older than $RETAIN_DAYS days"
find "$BACKUP_DIR" -name "postgres-*.tar.gz" -mtime +"$RETAIN_DAYS" -delete

# List remaining backups
BACKUP_COUNT=$(find "$BACKUP_DIR" -name "postgres-*.tar.gz" | wc -l)
log "Backup complete. $BACKUP_COUNT backups retained."
```

### Wait for a service to be ready

```bash
#!/usr/bin/env bash
# Used in CI/CD pipelines to wait for dependencies
set -euo pipefail

HOST="${1}"
PORT="${2}"
TIMEOUT="${3:-60}"
INTERVAL=2
ELAPSED=0

echo "Waiting for $HOST:$PORT to be ready..."

while ! nc -z "$HOST" "$PORT" 2>/dev/null; do
    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        echo "ERROR: Timed out waiting for $HOST:$PORT after ${TIMEOUT}s" >&2
        exit 1
    fi
    echo "Still waiting... (${ELAPSED}s elapsed)"
    sleep "$INTERVAL"
    ((ELAPSED += INTERVAL))
done

echo "$HOST:$PORT is ready! (${ELAPSED}s)"
```

### Kubernetes rolling deployment checker

```bash
#!/usr/bin/env bash
set -euo pipefail

DEPLOYMENT="$1"
NAMESPACE="${2:-default}"
TIMEOUT=300
INTERVAL=5
ELAPSED=0

log() { echo "[$(date '+%H:%M:%S')] $*"; }

log "Watching rollout: $DEPLOYMENT in $NAMESPACE"

while true; do
    DESIRED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
        -o jsonpath='{.spec.replicas}')
    READY=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
    UPDATED=$(kubectl get deployment "$DEPLOYMENT" -n "$NAMESPACE" \
        -o jsonpath='{.status.updatedReplicas}' 2>/dev/null || echo 0)

    log "Replicas — desired: $DESIRED | updated: $UPDATED | ready: $READY"

    if [[ "$READY" == "$DESIRED" && "$UPDATED" == "$DESIRED" ]]; then
        log "Rollout complete!"
        exit 0
    fi

    if [[ $ELAPSED -ge $TIMEOUT ]]; then
        log "ERROR: Rollout timed out after ${TIMEOUT}s" >&2
        kubectl rollout history deployment/"$DEPLOYMENT" -n "$NAMESPACE"
        exit 1
    fi

    sleep "$INTERVAL"
    ((ELAPSED += INTERVAL))
done
```

### Multi-server command runner

```bash
#!/usr/bin/env bash
set -euo pipefail

SERVERS=("web1.prod" "web2.prod" "web3.prod")
COMMAND="$*"
FAILED=()

run_on_server() {
    local server="$1"
    echo "=== $server ==="
    if ssh -o ConnectTimeout=5 "$server" "$COMMAND"; then
        echo "=== $server: SUCCESS ==="
    else
        echo "=== $server: FAILED ===" >&2
        return 1
    fi
}

for server in "${SERVERS[@]}"; do
    run_on_server "$server" || FAILED+=("$server")
done

if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo "FAILED on: ${FAILED[*]}" >&2
    exit 1
fi

echo "All servers completed successfully"
```

---

## 12. Debugging Scripts

```bash
# Run script in debug mode — prints every command before executing
bash -x script.sh
./script.sh  # with #!/usr/bin/env bash -x in shebang

# Enable/disable debug mode within script
set -x        # enable debug mode
# ... commands to debug ...
set +x        # disable debug mode

# Dry run — trace without executing
bash -n script.sh     # syntax check only (no execution)

# Print line number on error
set -E
trap 'echo "Error on line $LINENO"' ERR

# Print call stack on error
trap 'echo "Error: exit code $? on line $LINENO in function ${FUNCNAME[*]}"' ERR

# Check a script with shellcheck (install: apt install shellcheck)
shellcheck script.sh
shellcheck -S warning script.sh   # only show warnings and above

# Step through a script manually (add read to pause)
set -x
command1
read -p "Press enter to continue..."
command2

# Debug specific section
set -x
problematic_function
set +x

# Verbose curl for HTTP debugging
curl -v https://example.com 2>&1 | tee curl-debug.log
```

---

## Cheatsheet

```bash
# Script header
#!/usr/bin/env bash
set -euo pipefail

# Variables
NAME="value"
RESULT=$(command)
DEFAULT="${VAR:-fallback}"
REQUIRED="${VAR:?VAR must be set}"

# Conditions
[[ -f "$FILE" ]]          # file exists
[[ -d "$DIR" ]]           # directory exists
[[ -z "$STR" ]]           # string is empty
[[ -n "$STR" ]]           # string is non-empty
[[ "$A" == "$B" ]]        # strings equal
[[ $A -eq $B ]]           # numbers equal
[[ $A -gt $B ]]           # number greater than

# Loops
for item in "${ARRAY[@]}"; do echo "$item"; done
while IFS= read -r line; do echo "$line"; done < file.txt

# Functions
my_func() {
    local arg="$1"
    echo "$arg"
}

# Error handling
trap 'cleanup' EXIT
error() { echo "ERROR: $*" >&2; exit 1; }
command -v tool &>/dev/null || error "tool not found"

# String ops
${#VAR}              # length
${VAR:0:5}           # substring
${VAR/old/new}       # replace first
${VAR//old/new}      # replace all
${VAR#prefix}        # remove prefix
${VAR%suffix}        # remove suffix
${VAR^^}             # uppercase
${VAR,,}             # lowercase

# Useful patterns
TMPFILE=$(mktemp); trap "rm -f $TMPFILE" EXIT
retry 3 5 some_command
[[ $# -lt 2 ]] && { echo "Usage: $0 <arg1> <arg2>"; exit 1; }

# Debug
bash -x script.sh    # trace execution
shellcheck script.sh # static analysis
bash -n script.sh    # syntax check
```

---

*Next: [Users, Permissions & Security →](./07-linux-security.md) — hardening, SSH security, sudo, and access control.*
