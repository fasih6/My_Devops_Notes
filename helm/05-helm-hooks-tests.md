# 🪝 Hooks & Tests

Run tasks at specific points in the release lifecycle — migrations, validations, and automated testing.

---

## 📚 Table of Contents

- [1. What are Hooks?](#1-what-are-hooks)
- [2. Hook Types & Execution Order](#2-hook-types--execution-order)
- [3. Hook Annotations](#3-hook-annotations)
- [4. Common Hook Patterns](#4-common-hook-patterns)
- [5. Helm Tests](#5-helm-tests)
- [6. Hook Debugging](#6-hook-debugging)
- [Cheatsheet](#cheatsheet)

---

## 1. What are Hooks?

Hooks are Kubernetes resources (usually Jobs) that Helm runs at specific points in a release lifecycle — before or after install, upgrade, rollback, or uninstall.

```
helm install my-app ./chart
        │
        ▼
  pre-install hook runs  ← database migration, config validation
        │
        ▼
  Main resources deployed
        │
        ▼
  post-install hook runs ← smoke test, seed data, send notification
        │
        ▼
  Release = deployed
```

Any Kubernetes resource can be a hook — Jobs are most common because they run to completion.

---

## 2. Hook Types & Execution Order

```
helm install:
  pre-install → [resources created] → post-install

helm upgrade:
  pre-upgrade → [resources updated] → post-upgrade

helm rollback:
  pre-rollback → [resources reverted] → post-rollback

helm uninstall:
  pre-delete → [resources deleted] → post-delete

helm test:
  test (only when explicitly running helm test)
```

### Hook weights — order within the same lifecycle

```yaml
annotations:
  "helm.sh/hook-weight": "-10"    # runs first (lower = earlier)
  "helm.sh/hook-weight": "0"      # default
  "helm.sh/hook-weight": "10"     # runs last (higher = later)
```

Within the same hook type and weight, hooks run in alphabetical order by resource name.

---

## 3. Hook Annotations

```yaml
metadata:
  annotations:
    # What hook phase to run in
    "helm.sh/hook": pre-upgrade,pre-install

    # Execution order (lower = runs first)
    "helm.sh/hook-weight": "0"

    # What to do with the hook resource after it runs
    "helm.sh/hook-delete-policy": hook-succeeded
```

### Hook delete policies

| Policy | When the resource is deleted |
|--------|------------------------------|
| `hook-succeeded` | After the hook succeeds |
| `hook-failed` | After the hook fails |
| `before-hook-creation` | Before next hook run (default) |

```yaml
# Common production pattern — delete on success, keep on failure for debugging
"helm.sh/hook-delete-policy": hook-succeeded

# Delete before next run (keeps one copy for inspection)
"helm.sh/hook-delete-policy": before-hook-creation

# Never delete (accumulates) — useful for audit trail
# (no delete policy annotation)
```

---

## 4. Common Hook Patterns

### Database migration (pre-upgrade, pre-install)

```yaml
# templates/hooks/db-migrate.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "my-app.fullname" . }}-db-migrate-{{ .Release.Revision }}
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install
    "helm.sh/hook-weight": "0"
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  ttlSecondsAfterFinished: 300    # auto-delete after 5 min
  backoffLimit: 2                 # retry twice
  activeDeadlineSeconds: 600      # fail if not done in 10 min
  template:
    metadata:
      labels:
        {{- include "my-app.selectorLabels" . | nindent 8 }}
        job-type: db-migrate
    spec:
      restartPolicy: OnFailure
      serviceAccountName: {{ include "my-app.serviceAccountName" . }}
      containers:
        - name: migrate
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          imagePullPolicy: {{ .Values.image.pullPolicy }}
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo "Running database migration..."
              /app/migrate --timeout 300
              echo "Migration complete."
          env:
            - name: DB_HOST
              value: {{ .Values.config.database.host | quote }}
            - name: DB_PASSWORD
              valueFrom:
                secretKeyRef:
                  name: {{ .Values.config.database.existingSecret | default (printf "%s-db" (include "my-app.fullname" .)) }}
                  key: password
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 500m
              memory: 256Mi
```

### Pre-install validation

```yaml
# templates/hooks/validate-config.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "my-app.fullname" . }}-validate
  annotations:
    "helm.sh/hook": pre-install,pre-upgrade
    "helm.sh/hook-weight": "-5"       # run before migration
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: validate
          image: curlimages/curl:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo "Checking database connectivity..."
              until nc -z {{ .Values.config.database.host }} {{ .Values.config.database.port }}; do
                echo "Waiting for database..."
                sleep 2
              done
              echo "Database is reachable."

              echo "Checking external API..."
              curl -sf {{ .Values.config.externalApiUrl }}/health || {
                echo "External API is unreachable!"
                exit 1
              }
              echo "All checks passed."
```

### Post-install notification

```yaml
# templates/hooks/notify-deploy.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "my-app.fullname" . }}-notify-{{ .Release.Revision }}
  annotations:
    "helm.sh/hook": post-install,post-upgrade
    "helm.sh/hook-weight": "10"
    "helm.sh/hook-delete-policy": hook-succeeded,hook-failed
spec:
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: notify
          image: curlimages/curl:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              curl -X POST {{ .Values.notifications.slackWebhook | quote }} \
                -H "Content-Type: application/json" \
                -d '{
                  "text": "✅ Deployed {{ .Chart.Name }} {{ .Chart.AppVersion }} to {{ .Release.Namespace }}"
                }'
          env:
            - name: SLACK_WEBHOOK
              valueFrom:
                secretKeyRef:
                  name: notifications-secret
                  key: slackWebhook
```

### Pre-delete backup

```yaml
# templates/hooks/pre-delete-backup.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "my-app.fullname" . }}-backup-before-delete
  annotations:
    "helm.sh/hook": pre-delete
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: backup
          image: myregistry/backup-tool:latest
          command: ["/bin/sh", "-c"]
          args:
            - |
              echo "Taking backup before uninstall..."
              /app/backup --destination s3://my-bucket/backups/pre-delete
              echo "Backup complete."
```

---

## 5. Helm Tests

Tests are hook resources with `"helm.sh/hook": test`. Run with `helm test <release>`.

### Connection test (the most common)

```yaml
# templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "my-app.fullname" . }}-test-connection
  namespace: {{ .Release.Namespace }}
  labels:
    {{- include "my-app.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  restartPolicy: Never
  containers:
    - name: test
      image: curlimages/curl:latest
      command: ["/bin/sh", "-c"]
      args:
        - |
          echo "Testing HTTP connection..."
          curl -sf http://{{ include "my-app.fullname" . }}:{{ .Values.service.port }}/health
          echo "Test passed!"
```

### Comprehensive test suite

```yaml
# templates/tests/test-suite.yaml
apiVersion: batch/v1
kind: Job
metadata:
  name: {{ include "my-app.fullname" . }}-test-suite
  annotations:
    "helm.sh/hook": test
    "helm.sh/hook-delete-policy": hook-succeeded
spec:
  backoffLimit: 0   # don't retry — fail fast
  template:
    spec:
      restartPolicy: Never
      containers:
        - name: tests
          image: "{{ .Values.image.repository }}:{{ .Values.image.tag | default .Chart.AppVersion }}"
          command: ["/bin/sh", "-c"]
          args:
            - |
              set -e

              echo "=== Test 1: Health check ==="
              curl -sf http://{{ include "my-app.fullname" . }}/health

              echo "=== Test 2: Metrics endpoint ==="
              {{- if .Values.metrics.enabled }}
              curl -sf http://{{ include "my-app.fullname" . }}:{{ .Values.metrics.port }}/metrics
              {{- else }}
              echo "Metrics disabled — skipping"
              {{- end }}

              echo "=== Test 3: Database connectivity ==="
              /app/test-db-connection

              echo "=== All tests passed! ==="
```

### Running tests

```bash
# Run helm tests for a release
helm test my-app

# Run tests with verbose output
helm test my-app --logs

# Run tests in specific namespace
helm test my-app -n production

# Example output:
# NAME: my-app
# LAST DEPLOYED: Mon Jan 15 10:00:00 2024
# NAMESPACE: production
# STATUS: deployed
#
# TEST SUITE:     my-app-test-connection
# Last Started:   Mon Jan 15 10:01:00 2024
# Last Completed: Mon Jan 15 10:01:05 2024
# Phase:          Succeeded
```

---

## 6. Hook Debugging

### Why is my hook failing?

```bash
# Check hook job status
kubectl get jobs -n production | grep my-app

# Get hook pod logs
kubectl logs -n production -l job-name=my-app-db-migrate

# Describe the job
kubectl describe job my-app-db-migrate -n production

# If hook-delete-policy deletes it too fast, temporarily disable deletion:
# Remove "helm.sh/hook-delete-policy" annotation from the hook template
# Then re-install/upgrade to keep the job for inspection
```

### Hook stuck or timed out

```bash
# Check if hook job is still running
kubectl get pods -n production -l job-type=db-migrate

# If stuck, check what the container is doing
kubectl exec -it my-app-db-migrate-xxx -n production -- sh

# Force delete stuck hook job
kubectl delete job my-app-db-migrate -n production

# Then try the release again
helm upgrade my-app ./my-chart
```

### Atomic flag and hooks

```bash
# With --atomic: if any hook fails, Helm rolls back the release
helm upgrade my-app ./my-chart --atomic --timeout 10m

# The hook failure causes rollback — but hooks' own resources
# are still cleaned up based on hook-delete-policy
```

---

## Cheatsheet

```bash
# Run tests
helm test my-app
helm test my-app --logs
helm test my-app -n production

# Debug hooks
kubectl get jobs -n production
kubectl logs -n production -l job-type=db-migrate
kubectl describe job my-app-db-migrate -n production

# Force re-run hook (hook's job exists from previous run)
# With before-hook-creation policy — just upgrade again
helm upgrade my-app ./my-chart
```

```yaml
# Hook template skeleton
metadata:
  annotations:
    "helm.sh/hook": pre-upgrade,pre-install     # when to run
    "helm.sh/hook-weight": "0"                  # order (lower = first)
    "helm.sh/hook-delete-policy": hook-succeeded # cleanup

# Hook types: pre-install, post-install, pre-upgrade, post-upgrade,
#             pre-rollback, post-rollback, pre-delete, post-delete, test

# Delete policies: hook-succeeded, hook-failed, before-hook-creation

# Common patterns:
# -5  → validation/connectivity check
#  0  → database migration
# +5  → cache warmup
# +10 → deployment notification
```

---

*Next: [Secrets Management →](./06-secrets-management.md)*
