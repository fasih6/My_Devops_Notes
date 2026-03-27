# ⛵ Helm

A complete Helm knowledge base — from core concepts to production-grade chart development and CI/CD integration.

> Helm is the standard way to package and deploy Kubernetes applications. Every company running Kubernetes uses it. This folder goes deep — beyond basic install/upgrade into chart authoring, templating, secrets, and automation.

---

## 🗺️ Learning Path

```
01 → 02 → 03 → 04 → 05 → 06 → 07 → 08 → 09 → 10
 │     │     │     │     │     │     │     │     │     │
 │     │     │     │     │     │     │     │     │     └── Interview prep
 │     │     │     │     │     │     │     │     └──────── Manage multiple releases
 │     │     │     │     │     │     │     └────────────── Modern chart distribution
 │     │     │     │     │     │     └──────────────────── Automate deployments
 │     │     │     │     │     └────────────────────────── Keep secrets safe
 │     │     │     │     └──────────────────────────────── Lifecycle hooks & testing
 │     │     │     └────────────────────────────────────── Multi-chart applications
 │     │     └──────────────────────────────────────────── Template engine mastery
 │     └────────────────────────────────────────────────── Write real charts
 └──────────────────────────────────────────────────────── How Helm works internally
```

---

## 📚 Contents

| # | File | What you'll learn |
|---|------|------------------|
| 01 | [Core Concepts](./01-helm-core-concepts.md) | Internal mechanics, release lifecycle, storage, repos, value merging |
| 02 | [Chart Development](./02-helm-chart-development.md) | Scaffold, Chart.yaml, values.yaml design, templates, linting |
| 03 | [Templating Deep Dive](./03-helm-templating.md) | Sprig functions, _helpers.tpl, control structures, advanced patterns |
| 04 | [Dependencies & Subcharts](./04-helm-dependencies.md) | Subchart values, conditions, tags, global values, library charts |
| 05 | [Hooks & Tests](./05-helm-hooks-tests.md) | Pre/post hooks, migrations, helm test, debugging |
| 06 | [Secrets Management](./06-helm-secrets.md) | helm-secrets, SOPS, age/KMS, Vault, External Secrets |
| 07 | [CI/CD Integration](./07-helm-cicd.md) | GitHub Actions, GitLab CI, chart-releaser, ArgoCD |
| 08 | [OCI Registries](./08-helm-oci.md) | Push/pull charts from ECR, GHCR, GCR, Harbor |
| 09 | [Helmfile](./09-helmfile.md) | Declarative multi-release management, environments, selectors |
| 10 | [Interview Q&A](./10-helm-interview-qa.md) | Core, scenario-based, and advanced interview questions |

---

## ⚡ Quick Reference

### Essential Helm commands

```bash
# Repos
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
helm search repo nginx --versions
helm show values bitnami/nginx > nginx-defaults.yaml

# Install / upgrade
helm upgrade --install my-app ./my-chart \
  --namespace production \
  --create-namespace \
  --values values.yaml \
  --values values-production.yaml \
  --set image.tag=v1.2.3 \
  --atomic \
  --wait \
  --timeout 10m

# Manage releases
helm list -A
helm status my-app -n production
helm history my-app -n production
helm rollback my-app               # to previous revision
helm rollback my-app 3             # to specific revision
helm uninstall my-app -n production

# Inspect
helm get values my-app             # user-supplied values
helm get values my-app --all       # all values including defaults
helm get manifest my-app           # rendered Kubernetes YAML

# Debug
helm template my-app ./chart --values values.yaml   # render locally
helm install my-app ./chart --dry-run --debug        # dry run
helm lint ./chart                                    # validate chart
helm diff upgrade my-app ./chart --values values.yaml # show diff

# Test
helm test my-app -n production --logs

# OCI
helm push my-chart-1.0.0.tgz oci://ghcr.io/myorg/charts
helm install my-app oci://ghcr.io/myorg/charts/my-chart --version 1.0.0
```

### Helmfile commands

```bash
helmfile apply                          # apply all releases
helmfile diff                           # show what would change
helmfile -e production apply            # target environment
helmfile apply --selector layer=infra   # target by label
helmfile test                           # run helm tests
```

### Template quick reference

```yaml
# Access built-in objects
{{ .Release.Name }}
{{ .Release.Namespace }}
{{ .Chart.Name }}
{{ .Chart.AppVersion }}
{{ .Values.myKey }}

# Common patterns
{{ include "chart.fullname" . }}
{{ .Values.key | default "fallback" }}
{{ .Values.key | required "key is required" }}
{{ .Values.key | quote }}
{{ toYaml .Values.resources | nindent 2 }}

# Conditional
{{- if .Values.ingress.enabled }}...{{- end }}
{{- with .Values.optional }}...{{- end }}

# Loop
{{- range .Values.list }}{{ . }}{{- end }}
{{- range $k, $v := .Values.dict }}{{ $k }}: {{ $v }}{{- end }}

# Root context in range
{{- range .Values.items }}
  release: {{ $.Release.Name }}    # $ = root
  name: {{ .name }}               # . = current item
{{- end }}
```

---

## 🧠 Key Concepts at a Glance

| Concept | One-line summary |
|---------|-----------------|
| **Chart** | Versioned package of K8s templates + default values |
| **Release** | A running instance of a chart in the cluster |
| **Revision** | Immutable snapshot of a release — enables rollback |
| **values.yaml** | Default configuration — overridden by users |
| **_helpers.tpl** | Reusable named templates — not rendered directly |
| **`include`** | Call a named template and return string (pipeable) |
| **`nindent`** | Add newline + N spaces — essential for YAML embedding |
| **`required`** | Fail with clear message if value is empty |
| **Hook** | K8s resource run at specific release lifecycle point |
| **`--atomic`** | Auto-rollback if install/upgrade fails |
| **`--wait`** | Wait for all resources to be ready before returning |
| **helm-secrets** | Plugin that decrypts SOPS files before passing to Helm |
| **SOPS** | Encrypts YAML files (values safe to commit to Git) |
| **Helmfile** | Declarative multi-release manager — like Helm for Helm |
| **OCI registry** | Store charts in container registry (ECR, GHCR, Harbor) |
| **Library chart** | Chart with only templates, no deployable resources |
| **Subchart** | Chart dependency installed with the parent chart |
| **Global values** | Values accessible in parent AND all subcharts |
| **3-way merge** | Helm 3 preserves manual kubectl changes during upgrade |
| **`helm diff`** | Plugin showing what would change before upgrading |

---

## 🗂️ Folder Structure

```
helm/
├── 00-helm-index.md              ← You are here
├── 01-helm-core-concepts.md
├── 02-helm-chart-development.md
├── 03-helm-templating.md
├── 04-helm-dependencies.md
├── 05-helm-hooks-tests.md
├── 06-helm-secrets.md
├── 07-helm-cicd.md
├── 08-helm-oci.md
├── 09-helmfile.md
└── 10-helm-interview-qa.md
```

---

## 🔗 How Helm Connects to the Rest of Your Notes

| Topic | Connection |
|-------|-----------|
| **Kubernetes** | Helm deploys K8s resources — same YAML, just templated |
| **Observability** | kube-prometheus-stack, Loki installed via Helm |
| **CI/CD** | Helm upgrade commands in GitHub Actions / GitLab CI |
| **Secrets** | helm-secrets integrates with SOPS and Vault |
| **GitOps** | ArgoCD natively syncs Helm charts from Git |
| **Ansible** | Some teams use Ansible to run Helm commands (ansible k8s module) |

---

*Notes are living documents — updated as I learn and build.*
