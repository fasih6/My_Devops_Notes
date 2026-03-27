# 🧩 Templating Deep Dive

Sprig functions, helpers, control structures, and advanced Go templating patterns.

---

## 📚 Table of Contents

- [1. Go Template Basics](#1-go-template-basics)
- [2. Sprig Functions](#2-sprig-functions)
- [3. _helpers.tpl Patterns](#3-_helperstpl-patterns)
- [4. Control Structures](#4-control-structures)
- [5. Whitespace Control](#5-whitespace-control)
- [6. Variables in Templates](#6-variables-in-templates)
- [7. Template Composition](#7-template-composition)
- [8. Advanced Patterns](#8-advanced-patterns)
- [Cheatsheet](#cheatsheet)

---

## 1. Go Template Basics

Helm uses Go's `text/template` package, extended with Sprig functions.

```
{{ }}   — action block (output a value or call a function)
{{- }}  — trim whitespace BEFORE the block
{{ -}}  — trim whitespace AFTER the block
{{- -}} — trim both sides

{{ . }}          — current context (the dot)
{{ .Values }}    — values from values.yaml
{{ .Release }}   — release info
{{ .Chart }}     — chart metadata
{{ .Files }}     — access non-template files
{{ .Capabilities }} — Kubernetes/Helm capabilities
```

### The dot (.) — context

```yaml
# At the top level, . = root context
{{ .Values.replicaCount }}
{{ .Release.Name }}
{{ .Chart.Name }}

# Inside range, . becomes each item
{{- range .Values.servers }}
- host: {{ .host }}
  port: {{ .port }}
{{- end }}

# Inside with, . becomes the matching value
{{- with .Values.ingress }}
enabled: {{ .enabled }}
host: {{ .host }}
{{- end }}

# Pass root context into range/with using $
{{- range .Values.servers }}
  release: {{ $.Release.Name }}   # $ = root context, always accessible
  host: {{ .host }}               # . = current item
{{- end }}
```

---

## 2. Sprig Functions

Sprig adds 70+ functions to Go templates. These are the ones you'll use constantly.

### String functions

```yaml
{{ "hello world" | upper }}           # HELLO WORLD
{{ "HELLO" | lower }}                 # hello
{{ "hello world" | title }}           # Hello World
{{ "  hello  " | trim }}              # hello
{{ "  hello  " | trimAll " " }}       # hello
{{ "hello" | repeat 3 }}             # hellohellohello
{{ "hello world" | replace " " "-" }} # hello-world
{{ "hello" | trunc 3 }}              # hel
{{ "hello world" | contains "world" }} # true
{{ "hello" | hasPrefix "hel" }}      # true
{{ "hello" | hasSuffix "llo" }}      # true
{{ "hello world" | splitList " " }}  # [hello world]
{{ list "a" "b" "c" | join "-" }}    # a-b-c
{{ "hello\nworld" | splitLines }}    # [hello world]

# Indent and nindent — essential for YAML
{{ "key: value" | indent 4 }}        # "    key: value"
{{ "key: value" | nindent 4 }}       # "\n    key: value"

# Quote — very important for YAML string safety
{{ .Values.someString | quote }}     # "value" (with quotes)
{{ .Values.someString | squote }}    # 'value' (single quotes)

# b64 encode/decode
{{ "hello" | b64enc }}               # aGVsbG8=
{{ "aGVsbG8=" | b64dec }}           # hello

# SHA256 hash
{{ "password" | sha256sum }}
```

### Numeric functions

```yaml
{{ 42 | toString }}          # "42"
{{ "42" | toInt }}           # 42
{{ "3.14" | toFloat64 }}     # 3.14
{{ max 1 2 3 }}              # 3
{{ min 1 2 3 }}              # 1
{{ add 1 2 3 }}              # 6
{{ mul 2 3 }}                # 6
{{ div 10 3 }}               # 3
{{ mod 10 3 }}               # 1
{{ ceil 1.5 }}               # 2
{{ floor 1.5 }}              # 1
{{ round 1.5 }}              # 2
```

### List functions

```yaml
{{ list "a" "b" "c" }}                    # [a b c]
{{ list "a" "b" "c" | first }}            # a
{{ list "a" "b" "c" | last }}             # c
{{ list "a" "b" "c" | rest }}             # [b c]
{{ list "a" "b" "c" | len }}              # 3
{{ list "a" "b" "c" | has "b" }}          # true
{{ list "a" "b" "c" | without "b" }}      # [a c]
{{ list "a" "b" "c" | uniq }}             # [a b c] (deduplicate)
{{ list "c" "a" "b" | sortAlpha }}        # [a b c]
{{ list "a" "b" | append "c" }}           # [a b c]
{{ list "a" "b" | prepend "z" }}          # [z a b]
{{ concat (list "a" "b") (list "c") }}    # [a b c]
{{ list "a" "b" "c" | reverse }}          # [c b a]

# slice — sublist
{{ list "a" "b" "c" "d" | slice 1 3 }}   # [b c]

# compact — remove empty/nil
{{ list "a" "" "c" nil | compact }}       # [a c]
```

### Dict functions

```yaml
{{ dict "key" "value" "key2" "value2" }}  # map[key:value key2:value2]
{{ .Values.config | keys | sortAlpha }}   # sorted list of keys
{{ .Values.config | values }}             # list of values
{{ .Values.config | hasKey "database" }}  # true/false
{{ .Values.config | get "database" }}     # value for key

# merge — combine dicts (first dict wins on conflicts)
{{ merge .Values.extra .Values.defaults }}

# omit — dict without certain keys
{{ .Values.config | omit "password" "secret" }}

# pick — dict with only certain keys
{{ .Values.config | pick "host" "port" }}

# set — add/update a key
{{- $d := dict "key" "value" }}
{{- $_ := set $d "newkey" "newvalue" }}

# unset — remove a key
{{- $_ := unset $d "key" }}

# toYaml — convert to YAML string
{{ .Values.resources | toYaml }}

# toJson — convert to JSON string
{{ .Values.config | toJson }}

# fromYaml / fromJson — parse strings
{{- $parsed := "key: value" | fromYaml }}
```

### Type conversion & testing

```yaml
{{ .Values.enabled | toString }}     # convert to string
{{ "true" | toBool }}               # true (bool)
{{ .Values.count | toInt64 }}       # int64

# Type checking
{{ kindOf .Values.count }}          # "float64", "string", "bool", etc.
{{ kindIs "string" .Values.name }}  # true/false
{{ typeOf .Values.count }}          # "float64"
{{ typeIs "float64" .Values.count }}

# Empty check
{{ empty "" }}     # true
{{ empty 0 }}      # true
{{ empty nil }}    # true
{{ empty "x" }}    # false
```

### Date functions

```yaml
{{ now | date "2006-01-02" }}           # 2024-01-15
{{ now | date "2006-01-02T15:04:05Z" }} # ISO 8601
{{ now | unixEpoch }}                   # Unix timestamp
{{ now | dateInZone "2006-01-02" "UTC" }}
{{ now | htmlDate }}                    # 2024-01-15
{{ now | dateModify "-24h" | date "2006-01-02" }}  # yesterday

# Note: Go's reference date is Mon Jan 2 15:04:05 MST 2006
# 2006 = year, 01 = month, 02 = day, 15 = hour, 04 = min, 05 = sec
```

### URL functions

```yaml
{{ "https://user:pass@example.com:8080/path?q=1#frag" | urlParse | toJson }}
# {"fragment":"frag","host":"example.com:8080","hostname":"example.com",
#  "path":"/path","query":"q=1","scheme":"https","userinfo":"user:pass"}

{{ urlJoin (dict "scheme" "https" "host" "example.com" "path" "/api") }}
# https://example.com/api
```

---

## 3. _helpers.tpl Patterns

`_helpers.tpl` defines named templates used across all chart templates.

```
{{/* Template name */}}
{{- define "chart.name" -}}
...
{{- end }}
```

### Standard helpers (what `helm create` generates)

```
{{/*
Expand the name of the chart — truncated at 63 chars.
*/}}
{{- define "my-app.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited.
*/}}
{{- define "my-app.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart name and version as used by the chart label.
*/}}
{{- define "my-app.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels — applied to all resources.
*/}}
{{- define "my-app.labels" -}}
helm.sh/chart: {{ include "my-app.chart" . }}
{{ include "my-app.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels — used in matchLabels (must be stable across upgrades!).
*/}}
{{- define "my-app.selectorLabels" -}}
app.kubernetes.io/name: {{ include "my-app.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
ServiceAccount name.
*/}}
{{- define "my-app.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "my-app.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}
```

### Custom helpers

```
{{/*
Database connection string.
*/}}
{{- define "my-app.databaseURL" -}}
{{- $db := .Values.config.database -}}
{{- printf "postgresql://%s:%s@%s:%d/%s" $db.user $db.password $db.host (int $db.port) $db.name }}
{{- end }}

{{/*
Generate image reference with optional digest.
*/}}
{{- define "my-app.image" -}}
{{- if .Values.image.digest }}
{{- printf "%s@%s" .Values.image.repository .Values.image.digest }}
{{- else }}
{{- printf "%s:%s" .Values.image.repository (.Values.image.tag | default .Chart.AppVersion) }}
{{- end }}
{{- end }}

{{/*
Render environment variables from a list.
*/}}
{{- define "my-app.env" -}}
{{- range .Values.extraEnv }}
- name: {{ .name | quote }}
  value: {{ .value | quote }}
{{- end }}
{{- end }}

{{/*
Check if monitoring is available (CRD exists).
*/}}
{{- define "my-app.monitoringEnabled" -}}
{{- if and .Values.metrics.serviceMonitor.enabled
          (.Capabilities.APIVersions.Has "monitoring.coreos.com/v1/ServiceMonitor") -}}
true
{{- end }}
{{- end }}
```

---

## 4. Control Structures

### if / else / else if

```yaml
{{- if .Values.ingress.enabled }}
apiVersion: networking.k8s.io/v1
kind: Ingress
...
{{- end }}

{{- if eq .Values.service.type "LoadBalancer" }}
  loadBalancerIP: {{ .Values.service.loadBalancerIP }}
{{- else if eq .Values.service.type "NodePort" }}
  nodePort: {{ .Values.service.nodePort }}
{{- else }}
  {{/* ClusterIP — nothing extra needed */}}
{{- end }}
```

### Truthy values in Helm

```yaml
# False: false, 0, "", nil, empty list/map
# True: everything else

{{- if .Values.enabled }}        # true if enabled is true/non-zero/non-empty
{{- if not .Values.enabled }}    # negation
{{- if and .Values.a .Values.b }} # both must be truthy
{{- if or .Values.a .Values.b }}  # either must be truthy
```

### range — iteration

```yaml
# Loop over a list
{{- range .Values.servers }}
- host: {{ .host }}
  port: {{ .port | default 8080 }}
{{- end }}

# Loop with index
{{- range $index, $server := .Values.servers }}
server-{{ $index }}: {{ $server.host }}
{{- end }}

# Loop over a dict
{{- range $key, $value := .Values.config }}
{{ $key }}: {{ $value | quote }}
{{- end }}

# Loop over range of numbers
{{- range $i := until 5 }}      # 0, 1, 2, 3, 4
replica-{{ $i }}: active
{{- end }}

{{- range $i := untilStep 1 6 1 }}  # 1, 2, 3, 4, 5
{{- end }}

# Conditional within range
{{- range .Values.servers }}
{{- if .enabled }}
- {{ .host }}
{{- end }}
{{- end }}
```

### with — contextual block

```yaml
# Only renders block if value is truthy, and . becomes the value
{{- with .Values.podAnnotations }}
annotations:
  {{- toYaml . | nindent 4 }}
{{- end }}

# Multiple fields with $
{{- with .Values.ingress }}
host: {{ .host }}
path: {{ .path | default "/" }}
release: {{ $.Release.Name }}  # $ accesses root context
{{- end }}
```

---

## 5. Whitespace Control

Getting whitespace right in YAML is critical — wrong indentation breaks everything.

```yaml
# {{- trims preceding whitespace/newlines
# -}} trims following whitespace/newlines

# Without trimming:
key:
{{ "value" }}
# Produces: key:\nvalue (extra newline before value)

# With trimming:
key:
{{- "value" }}
# Produces: key:value (no newline — too aggressive)

# Correct — nindent adds its own newline
key:
{{- " value" }}
# Produces: key: value

# toYaml + nindent pattern (most common)
resources:
  {{- toYaml .Values.resources | nindent 2 }}
# nindent 2 adds \n + 2 spaces of indent

# The {{- and -}} rules:
# {{- removes all whitespace (spaces, tabs, newlines) BEFORE the tag
# -}} removes all whitespace AFTER the tag

# Common pattern — range with trimming
{{- range .Values.items }}
- item: {{ . }}
{{- end }}
```

---

## 6. Variables in Templates

```yaml
# Assign a variable
{{- $name := include "my-app.fullname" . }}
{{- $replicas := .Values.replicaCount | int }}

# Use variable
name: {{ $name }}
replicas: {{ $replicas }}

# Variable in range (escape the dot)
{{- $release := .Release.Name }}
{{- range .Values.servers }}
  release: {{ $release }}    # can't use .Release.Name here — . is the server
  host: {{ .host }}
{{- end }}

# Dict variable
{{- $labels := dict "app" "my-app" "env" "prod" }}
{{- range $k, $v := $labels }}
{{ $k }}: {{ $v }}
{{- end }}

# Conditional assignment
{{- $port := .Values.service.port | default 80 }}
{{- if eq .Values.service.type "LoadBalancer" }}
  {{- $port = 443 }}
{{- end }}
port: {{ $port }}
```

---

## 7. Template Composition

### include vs template

```yaml
# include — returns string, can be piped to functions
labels:
  {{- include "my-app.labels" . | nindent 4 }}

# template — renders in place, cannot be piped
{{- template "my-app.labels" . }}
```

### Passing context to templates

```yaml
# Pass root context
{{- include "my-app.labels" . }}

# Pass a dict with multiple values
{{- include "my-app.render-something" (dict "root" . "extra" "value") }}

# In the template, access with .root and .extra
{{- define "my-app.render-something" -}}
release: {{ .root.Release.Name }}
extra: {{ .extra }}
{{- end }}

# Pass a list as context
{{- include "my-app.render-list" (list . "arg1" "arg2") }}
# Access: index . 0 = root context, index . 1 = "arg1"
```

### tpl — render a string as a template

```yaml
# values.yaml
name: "{{ .Release.Name }}-app"

# template
name: {{ tpl .Values.name . }}
# Output: my-release-app (variables are expanded)
```

---

## 8. Advanced Patterns

### Generating multiple resources from a list

```yaml
{{- range .Values.ingresses }}
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: {{ include "my-app.fullname" $ }}-{{ .name }}
  namespace: {{ $.Release.Namespace }}
spec:
  rules:
    - host: {{ .host }}
      http:
        paths:
          - path: {{ .path | default "/" }}
            pathType: Prefix
            backend:
              service:
                name: {{ include "my-app.fullname" $ }}
                port:
                  number: {{ $.Values.service.port }}
{{- end }}
```

### Capability checks — write backwards-compatible templates

```yaml
# Check Kubernetes version
{{- if semverCompare ">=1.24-0" .Capabilities.KubeVersion.GitVersion }}
# Use new API
{{- else }}
# Use old API
{{- end }}

# Check if a CRD/API exists
{{- if .Capabilities.APIVersions.Has "monitoring.coreos.com/v1/ServiceMonitor" }}
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
...
{{- end }}

# Check Helm version
{{- if semverCompare ">=3.0.0" .Capabilities.HelmVersion.Version }}
{{- end }}
```

### Files — embed non-template content

```yaml
# Access a file in the chart (not in templates/)
# Place file at: my-chart/files/config.yaml

# In template:
data:
  config.yaml: |
    {{- .Files.Get "files/config.yaml" | nindent 4 }}

# Glob multiple files
{{- range $path, $content := .Files.Glob "files/*.yaml" }}
  {{ $path | base }}: |
    {{- $content | nindent 4 }}
{{- end }}

# As ConfigMap data (base64 encoded)
binaryData:
  {{- range $path, $content := .Files.Glob "files/*.bin" }}
  {{ $path | base }}: {{ $content | b64enc | quote }}
  {{- end }}
```

### required and fail

```yaml
# required — fail with message if value is empty
host: {{ .Values.database.host | required "database.host is required" }}

# fail — unconditionally fail with message
{{- if and .Values.hpa.enabled (not .Values.resources) }}
{{ fail "resources must be set when autoscaling is enabled" }}
{{- end }}
```

---

## Cheatsheet

```yaml
# Core syntax
{{ .Values.key }}                    # output value
{{- .Values.key -}}                  # output, trim whitespace both sides
{{ .Values.key | default "val" }}    # with default
{{ .Values.key | quote }}            # with quotes
{{ .Values.key | required "msg" }}   # fail if empty

# Essential functions
{{ include "chart.name" . }}         # call named template
{{ toYaml .Values.obj | nindent 4 }} # YAML encode + indent
{{ printf "%s-%s" .Release.Name .Chart.Name }} # string format

# Control flow
{{- if .Values.enabled }}...{{- end }}
{{- with .Values.optional }}...{{- end }}
{{- range .Values.list }}{{ . }}{{- end }}
{{- range $k, $v := .Values.dict }}{{ $k }}: {{ $v }}{{- end }}

# Variables
{{- $var := .Values.key }}
{{- $root := . }}

# Capability checks
{{- if semverCompare ">=1.24-0" .Capabilities.KubeVersion.GitVersion }}
{{- if .Capabilities.APIVersions.Has "monitoring.coreos.com/v1/ServiceMonitor" }}

# Useful Sprig
| upper | lower | title | trim | replace " " "-"
| trunc 63 | trimSuffix "-"
| b64enc | b64dec | sha256sum
| toJson | fromJson | toYaml | fromYaml
| list "a" "b" | join "," | has "a" | without "b"
| dict "k" "v" | keys | values | hasKey "k"
| now | date "2006-01-02"
| semverCompare ">=1.24" .Capabilities.KubeVersion.GitVersion
```

---

*Next: [Dependencies & Subcharts →](./04-dependencies-subcharts.md)*
