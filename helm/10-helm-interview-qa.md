# 🎯 Helm Interview Q&A

Real Helm questions asked in DevOps interviews — with complete answers.

---

## 📚 Table of Contents

- [🔥 Core Concepts](#-core-concepts)
- [🏗️ Chart Development](#️-chart-development)
- [🧩 Templating](#-templating)
- [🔐 Security & Secrets](#-security--secrets)
- [🚀 CI/CD & Operations](#-cicd--operations)
- [🔥 Scenario-Based Questions](#-scenario-based-questions)
- [🧠 Advanced Questions](#-advanced-questions)
- [💬 Questions to Ask the Interviewer](#-questions-to-ask-the-interviewer)

---

## 🔥 Core Concepts

---

**Q: What is Helm and what problem does it solve?**

Helm is the package manager for Kubernetes. A Kubernetes application typically requires many resources — Deployment, Service, Ingress, ConfigMap, HPA, ServiceAccount, RBAC rules. Managing dozens of YAML files separately is complex, error-prone, and hard to version.

Helm packages these resources into a **chart** — a versioned, configurable bundle. You install a chart as a **release**, upgrade it, roll it back, and track exactly what's deployed. This is comparable to how `apt` packages software for Ubuntu or `npm` packages JavaScript libraries.

---

**Q: What is the difference between a chart, a release, and a revision?**

A **chart** is the package — the collection of templates, default values, and metadata. It's reusable and versioned.

A **release** is a running instance of a chart in a cluster. You can have multiple releases of the same chart (e.g., `my-app-staging` and `my-app-production`).

A **revision** is a version of a release. Every install creates revision 1. Every upgrade increments the revision. This is what enables rollbacks — each revision is stored and can be restored.

---

**Q: Where does Helm store release information?**

Helm 3 stores release metadata as Kubernetes Secrets in the release namespace. Each revision gets its own Secret named `sh.helm.release.v1.<release-name>.v<revision>`. These secrets contain the chart templates, values, and rendered manifests — everything needed to track and rollback.

This is why you need RBAC access to Secrets in a namespace to manage Helm releases there, and why release history survives even if you reinstall the Helm client.

---

**Q: What is the difference between `helm install` and `helm upgrade --install`?**

`helm install` fails if the release already exists. `helm upgrade --install` is idempotent — it installs if the release doesn't exist, and upgrades if it does.

In CI/CD pipelines, always use `helm upgrade --install` — it works for both first-time deploys and subsequent updates without needing to check if the release exists.

---

**Q: What does `--atomic` do?**

`--atomic` makes a Helm install or upgrade automatically rollback if it fails. Without it, a failed upgrade leaves the release in a `failed` state and you need to manually intervene.

Combined with `--wait`, it's the safest production deployment pattern:
```bash
helm upgrade --install my-app ./chart --atomic --wait --timeout 10m
```

If deployment fails (pods crash, health checks fail, timeout), Helm automatically rolls back to the previous revision.

---

**Q: What is 3-way strategic merge in Helm 3?**

When Helm upgrades a release, it compares three states:
1. The old chart (previous desired state)
2. Live cluster state (including any manual kubectl edits)
3. The new chart (new desired state)

Helm merges these intelligently — manual changes to fields that the new chart doesn't touch are preserved. Helm 2 used a 2-way merge and would clobber manual changes. This 3-way merge makes Helm 3 safer in environments where operators occasionally make manual adjustments.

---

## 🏗️ Chart Development

---

**Q: What is the difference between `defaults/` and `vars/` in a chart?**

There's no `defaults/` and `vars/` in Helm — that's Ansible. In Helm, you have:

- `values.yaml` — default values. Low priority. Users override these with `-f` or `--set`.
- Template variables in `_helpers.tpl` — internal computed values, not user-facing.

The closest analogy: `values.yaml` defaults can be overridden by anything. Internal template variables computed in `_helpers.tpl` are private to the chart.

---

**Q: What is `_helpers.tpl` and why does the filename start with underscore?**

`_helpers.tpl` defines named templates (reusable template snippets) using `{{- define "name" }}`. The underscore prefix is a convention that tells Helm this file contains no renderable output — only template definitions. Helm skips rendering files starting with `_` directly.

Without it, every template file produces a separate Kubernetes manifest. `_helpers.tpl` is just for defining reusable `{{- define }}` blocks used across other templates.

---

**Q: How do you make a chart value required?**

Use the `required` function in the template:

```yaml
host: {{ .Values.database.host | required "database.host is required" }}
```

If `database.host` is empty or not set, `helm install` fails with the message `"database.host is required"`. This is much better than deploying with an empty value and getting a cryptic runtime error.

---

**Q: What is `values.schema.json` and why would you use it?**

A JSON Schema file placed in the chart root that validates user-provided values before rendering templates. It catches type errors and missing required fields at `helm install` time rather than at runtime.

For example: `service.port` must be an integer between 1 and 65535, `image.pullPolicy` must be one of "Always", "IfNotPresent", "Never". Without schema validation, a user setting `service.port: "80"` (string instead of int) might cause a cryptic Kubernetes error.

---

## 🧩 Templating

---

**Q: What is the difference between `include` and `template` in Helm?**

Both call a named template, but `include` returns a string (which can be piped to other functions), while `template` renders directly in place (cannot be piped).

```yaml
# include — returns string, can pipe to nindent
labels:
  {{- include "my-chart.labels" . | nindent 4 }}

# template — renders in place, cannot pipe
{{- template "my-chart.labels" . }}
```

Always use `include` — it's more flexible and is the standard in modern Helm charts.

---

**Q: What does `nindent` do and why is it so common?**

`nindent N` adds a newline followed by N spaces of indentation to a string. It's essential for embedding YAML blocks correctly in templates.

```yaml
# Without nindent — wrong indentation
resources:
{{ toYaml .Values.resources }}

# With nindent 2 — correct
resources:
  {{- toYaml .Values.resources | nindent 2 }}
```

`nindent` (newline-indent) is preferred over `indent` because YAML is sensitive to leading newlines, and `nindent` handles the newline automatically.

---

**Q: How do you access the root context inside a `range` loop?**

Use `$` — it always refers to the root context, regardless of the current scope:

```yaml
{{- range .Values.servers }}
  release: {{ $.Release.Name }}   # $ = root context
  host: {{ .host }}               # . = current server item
{{- end }}
```

Inside `range` and `with`, `.` becomes the current item. `$` escapes back to the root, giving you access to `.Release`, `.Values`, `.Chart`, etc.

---

**Q: What is the `tpl` function and when would you use it?**

`tpl` renders a string as a Go template. It's useful when you want users to be able to use template variables inside values:

```yaml
# values.yaml
name: "{{ .Release.Name }}-my-suffix"

# template
name: {{ tpl .Values.name . }}
# Output: my-release-my-suffix (variables expanded)
```

Use `tpl` when values need to be dynamic based on release context. Be careful — it introduces template injection risk if users can set arbitrary values.

---

## 🔐 Security & Secrets

---

**Q: How do you handle secrets in Helm?**

Helm values files are plain text, so you shouldn't put raw secrets in them. The main approaches:

1. **helm-secrets + SOPS** — encrypt values files with age/KMS keys before committing to Git. Helm-secrets decrypts them before passing to Helm.

2. **External Secrets Operator** — secrets live in AWS Secrets Manager/Vault, synced automatically to K8s Secrets. Chart references the K8s Secret name, not the value.

3. **Vault** — Vault Agent Injector sidecar decrypts and mounts secrets into pods at runtime.

For most teams, helm-secrets + SOPS is the simplest starting point. For cloud-native environments, External Secrets Operator integrates better with IAM.

---

**Q: What is SOPS and how does it work with Helm?**

SOPS (Secrets OPerationS) encrypts YAML files so sensitive values become opaque ciphertext — but the structure remains readable. The encrypted file is safe to commit to Git.

```yaml
# Encrypted with SOPS (safe to commit)
database:
  password: ENC[AES256_GCM,data:abc123...,iv:...,tag:...,type:str]
```

The `helm-secrets` plugin decrypts SOPS-encrypted files before passing them to Helm:
```bash
helm secrets upgrade --install my-app ./chart -f secrets.enc.yaml
```

SOPS supports age keys, PGP, AWS KMS, GCP KMS, and Azure Key Vault as backends.

---

## 🚀 CI/CD & Operations

---

**Q: What flags do you always use in CI/CD Helm deployments?**

```bash
helm upgrade --install my-app ./chart \
  --atomic           # rollback automatically on failure
  --wait             # wait for all resources to be ready
  --timeout 10m      # don't wait forever
  --cleanup-on-fail  # delete new resources if upgrade fails
```

Additionally:
- `--namespace` and `--create-namespace` — ensure correct namespace
- `helm diff` before applying — shows changes for review
- `helm test` after deploying — validates the deployment

---

**Q: How do you do a rollback with Helm?**

```bash
# Rollback to previous revision
helm rollback my-app

# Rollback to specific revision
helm rollback my-app 3

# View history first
helm history my-app
```

Helm doesn't re-run hooks on rollback by default. Each revision's rendered manifests are stored in the release Secrets, so rollback restores the exact previous state.

---

## 🔥 Scenario-Based Questions

---

**Scenario 1: A Helm upgrade failed. The release is in a "failed" state. What do you do?**

```
1. Check what went wrong
   helm status my-app
   kubectl get pods -n production
   kubectl describe pod <failing-pod>

2. Check the diff to understand what changed
   helm history my-app                    # see revisions
   helm get manifest my-app --revision 5  # what's currently deployed

3. Options:
   a) Fix the chart/values and upgrade again
      helm upgrade my-app ./chart --values values.yaml --atomic

   b) Rollback to last working revision
      helm rollback my-app              # to previous
      helm rollback my-app 4            # to specific revision

4. If --atomic was used, rollback already happened automatically

5. Reset failed state if needed
   helm upgrade my-app ./chart --force  # forces upgrade even if failed
```

---

**Scenario 2: Your chart works in staging but fails in production with a different error. What do you check?**

```
1. Compare the rendered templates between environments
   helm template my-app ./chart -f values-staging.yaml > staging-rendered.yaml
   helm template my-app ./chart -f values-production.yaml > prod-rendered.yaml
   diff staging-rendered.yaml prod-rendered.yaml

2. Check the values difference
   helm get values my-app --namespace staging > staging-values.yaml
   diff staging-values.yaml production-values.yaml

3. Common environment-specific issues:
   - Different resource limits (OOMKilled in prod with smaller limits)
   - Different nodeSelectors or tolerations
   - Missing secrets in production namespace
   - Different StorageClass names
   - Image pull secret not configured

4. Check the error carefully:
   kubectl describe pod <failing-pod> -n production
   kubectl logs <failing-pod> -n production --previous
```

---

**Scenario 3: You need to deploy the same chart to 50 namespaces (one per customer). How do you manage this?**

```
Options:

1. Helmfile with a loop
   {{- range .Values.customers }}
   - name: app-{{ .name }}
     namespace: customer-{{ .name }}
     chart: ./charts/my-app
     values:
       - values/my-app.yaml
       - "values/customers/{{ .name }}.yaml"
   {{- end }}

2. ArgoCD ApplicationSet (if using GitOps)
   - Generates one ArgoCD Application per customer
   - Reads customer list from Git or external source

3. Custom script wrapping helm upgrade --install
   for customer in customers.txt; do
     helm upgrade --install my-app-$customer ./chart \
       --namespace customer-$customer \
       --values customers/$customer.yaml
   done

Helmfile + ArgoCD ApplicationSet is the cleanest production approach.
```

---

**Scenario 4: A Helm hook (database migration) is failing. How do you debug it?**

```
1. Find the hook job
   kubectl get jobs -n production | grep migrate

2. Check job status
   kubectl describe job my-app-db-migrate -n production

3. Check pod logs
   kubectl get pods -n production -l job-name=my-app-db-migrate
   kubectl logs -n production <job-pod-name>
   kubectl logs -n production <job-pod-name> --previous  # if crashed

4. If hook-delete-policy deletes it too fast:
   Remove "helm.sh/hook-delete-policy" annotation temporarily
   Re-run the upgrade to keep the job for inspection

5. Temporarily disable the hook to deploy without it:
   Comment out the hook annotation in the template
   Deploy, then re-enable

6. Common causes:
   - Database not reachable (wrong hostname, missing network policy)
   - Wrong credentials (secret key name mismatch)
   - Migration already ran (check for idempotency)
   - Timeout too short
```

---

## 🧠 Advanced Questions

---

**Q: What is the difference between Helmfile and ArgoCD?**

**Helmfile** is a CLI tool for managing multiple Helm releases — you run it manually or in CI. It's pull-based from your workstation or CI pipeline.

**ArgoCD** is a GitOps controller running in the cluster. It continuously watches a Git repository and automatically syncs the cluster to match what's in Git — self-healing. If someone manually changes a resource, ArgoCD reverts it.

They can work together: Helmfile manages infrastructure (cert-manager, ingress, monitoring), while ArgoCD manages applications in a GitOps model. Or you use Helmfile for everything in a CI/CD model, or ArgoCD for everything in a pure GitOps model.

---

**Q: What are library charts and when would you use them?**

A library chart (`type: library` in Chart.yaml) contains only named template definitions — no renderable manifests. Other charts depend on it to share reusable templates.

Use cases:
- Standardize labels, annotations, and helper functions across all your organization's charts
- Share common security context templates
- Enforce naming conventions across teams

```yaml
# Library chart _helpers.tpl defines:
{{- define "myorg.labels" -}}...{{- end }}
{{- define "myorg.securityContext" -}}...{{- end }}

# Application charts depend on the library and use:
labels:
  {{- include "myorg.labels" . | nindent 4 }}
```

---

**Q: How do you handle Kubernetes API version deprecations in your Helm charts?**

API versions change across Kubernetes versions (e.g., `extensions/v1beta1` Ingress deprecated in 1.22). Use capability checks in templates:

```yaml
{{- if semverCompare ">=1.19-0" .Capabilities.KubeVersion.GitVersion }}
apiVersion: networking.k8s.io/v1
{{- else }}
apiVersion: networking.k8s.io/v1beta1
{{- end }}
```

The `helm-mapkubeapis` plugin can automatically fix deprecated API versions in existing releases:
```bash
helm plugin install https://github.com/helm/helm-mapkubeapis
helm mapkubeapis my-release -n production
```

---

## 💬 Questions to Ask the Interviewer

**On their Helm usage:**
- "Do you use Helm with GitOps (ArgoCD/Flux) or a push-based CI/CD model?"
- "Do you maintain your own charts or primarily use community charts?"
- "How do you handle secrets in your Helm deployments — helm-secrets, External Secrets, or Vault?"

**On their practices:**
- "Do you use Helmfile to manage multiple releases, or individual helm commands?"
- "How do you test chart changes before they hit production — staging environment, helm test, or both?"
- "Do you publish charts to an OCI registry or a traditional HTTP repo?"

**On their challenges:**
- "What's been your biggest pain point with Helm at scale?"
- "How do you handle the situation where multiple teams share a cluster and each needs their own release?"

---

*Good luck — you've built a comprehensive Helm knowledge base. 🚀*
