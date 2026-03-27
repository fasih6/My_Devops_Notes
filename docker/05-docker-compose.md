# 🐙 Docker Compose

Define and run multi-container applications — services, networks, volumes, dependencies, and profiles.

---

## 📚 Table of Contents

- [1. What is Docker Compose?](#1-what-is-docker-compose)
- [2. compose.yaml Structure](#2-composeyaml-structure)
- [3. Services Deep Dive](#3-services-deep-dive)
- [4. Networks in Compose](#4-networks-in-compose)
- [5. Volumes in Compose](#5-volumes-in-compose)
- [6. Environment Variables](#6-environment-variables)
- [7. Dependencies & Health Checks](#7-dependencies--health-checks)
- [8. Profiles](#8-profiles)
- [9. Multiple Compose Files](#9-multiple-compose-files)
- [10. Real-World Examples](#10-real-world-examples)
- [Cheatsheet](#cheatsheet)

---

## 1. What is Docker Compose?

Docker Compose defines and runs multi-container applications from a single YAML file. Instead of running multiple `docker run` commands, you declare your entire application stack.

```bash
# One command to start everything
docker compose up -d

# One command to stop everything
docker compose down
```

### Compose v1 vs v2

```bash
# Compose v1 (deprecated) — separate binary
docker-compose up

# Compose v2 (current) — built into Docker CLI
docker compose up   # note: no hyphen
```

---

## 2. compose.yaml Structure

```yaml
# compose.yaml (or docker-compose.yaml)
name: my-app                    # project name (default: directory name)

services:                        # containers to run
  web:
    image: nginx:1.24
    ports: ["80:80"]

  api:
    build: ./api
    depends_on: [db]

  db:
    image: postgres:15
    volumes: [postgres-data:/var/lib/postgresql/data]

volumes:                         # named volumes
  postgres-data:

networks:                        # custom networks
  backend:
```

---

## 3. Services Deep Dive

### Complete service configuration

```yaml
services:
  api:
    # Image or build
    image: myregistry/my-api:v1.2.3
    # OR build from Dockerfile
    build:
      context: ./api             # build context directory
      dockerfile: Dockerfile.prod
      args:
        VERSION: v1.2.3
        NODE_ENV: production
      target: production          # multi-stage build target
      cache_from:
        - myregistry/my-api:latest
      labels:
        - "com.example.env=prod"

    # Container settings
    container_name: my-api         # fixed name (avoids auto-naming)
    hostname: api
    restart: unless-stopped        # no, always, on-failure, unless-stopped

    # Ports
    ports:
      - "8080:8080"                # host:container
      - "127.0.0.1:9090:9090"     # bind to localhost only
      - "8443:8443/tcp"

    # Expose (internal only, no host mapping)
    expose:
      - "8080"

    # Environment
    environment:
      APP_ENV: production
      DB_HOST: db
      LOG_LEVEL: info
    env_file:
      - .env
      - .env.production

    # Volumes
    volumes:
      - ./logs:/app/logs           # bind mount
      - app-data:/data             # named volume
      - type: tmpfs
        target: /tmp
        tmpfs:
          size: 100m

    # Networks
    networks:
      - frontend
      - backend

    # Dependencies
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_started

    # Health check
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 15s

    # Resource limits
    deploy:
      resources:
        limits:
          cpus: "0.5"
          memory: 256M
        reservations:
          cpus: "0.1"
          memory: 128M

    # Security
    user: "1000:1000"
    read_only: true
    cap_drop:
      - ALL
    cap_add:
      - NET_BIND_SERVICE
    security_opt:
      - no-new-privileges:true

    # Extra config
    working_dir: /app
    entrypoint: ["./docker-entrypoint.sh"]
    command: ["node", "server.js"]
    stdin_open: true               # docker run -i
    tty: true                      # docker run -t
    privileged: false
    extra_hosts:
      - "host.docker.internal:host-gateway"

    # Labels
    labels:
      com.example.version: "1.2.3"
      traefik.enable: "true"

    # Logging
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
```

---

## 4. Networks in Compose

```yaml
services:
  web:
    networks:
      - frontend                  # only frontend access
  api:
    networks:
      - frontend
      - backend                   # access both
  db:
    networks:
      - backend                   # only backend access

networks:
  frontend:
    driver: bridge
  backend:
    driver: bridge
    internal: true                # no external access

  # Use existing external network
  existing-net:
    external: true
    name: my-existing-network

  # Custom subnet
  custom:
    driver: bridge
    ipam:
      config:
        - subnet: 172.20.0.0/16
          gateway: 172.20.0.1
```

**Default network:** Compose automatically creates one network for the project. All services join it and can find each other by service name.

---

## 5. Volumes in Compose

```yaml
services:
  db:
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql:ro
      - type: tmpfs
        target: /tmp

volumes:
  postgres-data:                  # named volume managed by Docker
    driver: local

  # External (pre-existing) volume
  existing-volume:
    external: true
    name: my-existing-volume

  # NFS volume
  nfs-data:
    driver: local
    driver_opts:
      type: nfs
      o: addr=nfs-server,rw
      device: ":/exports/data"
```

---

## 6. Environment Variables

```yaml
services:
  api:
    # Inline environment variables
    environment:
      APP_ENV: production
      DB_HOST: db

    # From .env file (default: .env in same directory as compose.yaml)
    env_file:
      - .env
      - .env.local           # loaded after .env, can override
      - path: .env.secret    # optional file (won't error if missing)
        required: false
```

### .env file

```bash
# .env — loaded automatically by Compose
POSTGRES_PASSWORD=secret123
POSTGRES_DB=myapp
APP_VERSION=v1.2.3
IMAGE_TAG=latest
```

### Variable substitution in compose.yaml

```yaml
services:
  api:
    image: myregistry/my-app:${APP_VERSION:-latest}  # default if not set
    environment:
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      APP_VERSION: ${APP_VERSION:?APP_VERSION must be set}  # required

# Use env vars in compose.yaml itself
# docker compose --env-file .env.prod up
```

---

## 7. Dependencies & Health Checks

### depends_on with conditions

```yaml
services:
  api:
    depends_on:
      db:
        condition: service_healthy    # wait until db is healthy
        restart: true                 # restart api if db restarts
      redis:
        condition: service_started    # just wait for container to start
      migrations:
        condition: service_completed_successfully  # wait for job to finish

  db:
    image: postgres:15
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5
      start_period: 10s

  redis:
    image: redis:7
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5

  migrations:
    image: my-app:latest
    command: ["python", "manage.py", "migrate"]
    depends_on:
      db:
        condition: service_healthy
    restart: "no"             # don't restart — it's a one-time job
```

---

## 8. Profiles

Profiles allow you to enable/disable services for different scenarios.

```yaml
services:
  # Always started
  api:
    image: my-api
    networks: [default]

  db:
    image: postgres:15

  # Only in "monitoring" profile
  prometheus:
    image: prom/prometheus
    profiles: [monitoring]

  grafana:
    image: grafana/grafana
    profiles: [monitoring]

  # Only in "debug" profile
  adminer:
    image: adminer
    profiles: [debug]
    ports: ["8080:8080"]
```

```bash
# Start without profiles (only api + db)
docker compose up -d

# Start with monitoring profile
docker compose --profile monitoring up -d

# Start with multiple profiles
docker compose --profile monitoring --profile debug up -d
```

---

## 9. Multiple Compose Files

Override compose.yaml with additional files:

```bash
# Default: reads compose.yaml
docker compose up

# Override with additional file
docker compose -f compose.yaml -f compose.prod.yaml up

# Later files override earlier ones (like Helm values)
```

```yaml
# compose.yaml — base
services:
  api:
    image: my-api:latest
    environment:
      APP_ENV: development

# compose.prod.yaml — production overrides
services:
  api:
    image: my-api:${VERSION}     # pinned version
    environment:
      APP_ENV: production
    deploy:
      resources:
        limits:
          memory: 512M
    restart: unless-stopped
```

### Common pattern: dev + prod

```
compose.yaml         → base configuration
compose.override.yaml → development overrides (auto-loaded by Docker Compose)
compose.prod.yaml    → production overrides (specified explicitly)
```

```yaml
# compose.override.yaml — auto-loaded in development
services:
  api:
    build: .              # build locally in dev
    volumes:
      - .:/app            # live code reload
    environment:
      APP_ENV: development
      DEBUG: "true"
```

```bash
# Development (loads compose.yaml + compose.override.yaml automatically)
docker compose up

# Production (explicit files)
docker compose -f compose.yaml -f compose.prod.yaml up -d
```

---

## 10. Real-World Examples

### Full web application stack

```yaml
# compose.yaml
name: my-app

services:
  nginx:
    image: nginx:1.24-alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./nginx/certs:/etc/nginx/certs:ro
    depends_on:
      api:
        condition: service_healthy
    networks: [frontend]
    restart: unless-stopped

  api:
    build:
      context: .
      target: production
    environment:
      APP_ENV: production
      DB_HOST: db
      DB_NAME: ${POSTGRES_DB}
      DB_PASSWORD: ${POSTGRES_PASSWORD}
      REDIS_URL: redis://redis:6379
    depends_on:
      db:
        condition: service_healthy
      redis:
        condition: service_healthy
    networks: [frontend, backend]
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8080/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 20s
    restart: unless-stopped
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "5"

  db:
    image: postgres:15-alpine
    environment:
      POSTGRES_USER: ${POSTGRES_USER:-myapp}
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: ${POSTGRES_DB:-myapp}
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./db/init:/docker-entrypoint-initdb.d:ro
    networks: [backend]
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U ${POSTGRES_USER:-myapp}"]
      interval: 5s
      timeout: 5s
      retries: 10
    restart: unless-stopped

  redis:
    image: redis:7-alpine
    command: redis-server --save 60 1 --loglevel warning
    volumes:
      - redis-data:/data
    networks: [backend]
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
      interval: 5s
      timeout: 3s
      retries: 5
    restart: unless-stopped

networks:
  frontend:
  backend:
    internal: true

volumes:
  postgres-data:
  redis-data:
```

---

## Cheatsheet

```bash
# Lifecycle
docker compose up               # start all services (foreground)
docker compose up -d            # start detached
docker compose up --build       # rebuild images first
docker compose down             # stop and remove containers
docker compose down -v          # also remove volumes
docker compose restart          # restart all services

# Status
docker compose ps               # list services and status
docker compose logs             # all logs
docker compose logs -f api      # follow specific service logs
docker compose top              # running processes

# Scale
docker compose up -d --scale api=3   # run 3 api instances

# Execute
docker compose exec api bash    # shell into running service
docker compose run --rm api python manage.py migrate  # one-off command

# Build
docker compose build            # build all services
docker compose build api        # build specific service
docker compose pull             # pull all images

# Config
docker compose config           # validate and show merged config
docker compose --env-file .env.prod config  # with specific env file

# Profiles
docker compose --profile monitoring up -d
docker compose --profile debug run --rm debug-tools bash
```

---

*Next: [Security →](./06-security.md)*
