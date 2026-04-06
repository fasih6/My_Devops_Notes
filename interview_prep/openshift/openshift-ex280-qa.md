# OpenShift EX280 Exam Prep & Interview Q&A — All Levels

> **Coverage**: Beginner → Intermediate → Advanced → EX280 Exam-Style  
> **Format**: Mix of concise answers, bullet points, tables, and code snippets  
> **Total**: 120+ questions across 10 topic sections  
> **Relevance**: Red Hat EX280 certification, OpenShift engineer interviews, DACH DevOps roles

---

## Table of Contents

1. [OpenShift Fundamentals](#1-openshift-fundamentals)
2. [OpenShift Architecture & Components](#2-openshift-architecture--components)
3. [Projects, Users & Authentication](#3-projects-users--authentication)
4. [Deployments, Builds & ImageStreams](#4-deployments-builds--imagestreams)
5. [Networking — Routes, Services & Policies](#5-networking--routes-services--policies)
6. [Storage in OpenShift](#6-storage-in-openshift)
7. [Security — SCC, RBAC & Quotas](#7-security--scc-rbac--quotas)
8. [OpenShift CLI (`oc`) Mastery](#8-openshift-cli-oc-mastery)
9. [Cluster Configuration & Operators](#9-cluster-configuration--operators)
10. [EX280 Exam-Style Scenarios](#10-ex280-exam-style-scenarios)

---

## 1. OpenShift Fundamentals

---

**Q1. What is OpenShift?**

Red Hat OpenShift is an **enterprise Kubernetes platform** built on top of Kubernetes. It adds:
- Developer-focused workflows (Source-to-Image, built-in CI/CD)
- Enhanced security (SCCs, default non-root enforcement)
- Integrated container registry
- Web console and developer UI
- Operator-based cluster management
- Built-in monitoring (Prometheus + Grafana stack)
- Enterprise support from Red Hat

OpenShift is available as:
- **OCP** (OpenShift Container Platform) — on-premises
- **ROSA** — managed on AWS
- **ARO** — managed on Azure
- **OpenShift on GCP** — managed on GCP
- **OSD** (OpenShift Dedicated) — fully managed

---

**Q2. What is the difference between OpenShift and Kubernetes?**

| Feature | Kubernetes | OpenShift |
|---|---|---|
| Base | Open source | Kubernetes + Red Hat additions |
| Security defaults | Permissive | Strict (no root by default) |
| SCCs | No | Yes (replaces PSP) |
| Projects | Namespaces | Projects (enhanced Namespaces) |
| Routes | No | Yes (built-in Ingress) |
| ImageStreams | No | Yes |
| Source-to-Image (S2I) | No | Yes |
| Operators | Manual | OLM (Operator Lifecycle Manager) |
| Registry | External | Built-in internal registry |
| CLI | kubectl | oc (superset of kubectl) |
| Web console | Dashboard | Full-featured developer + admin console |
| Cluster upgrade | Manual | Automated via CVO |

---

**Q3. What is the EX280 exam?**

The **Red Hat Certified Specialist in OpenShift Administration (EX280)** is a performance-based exam:

| Attribute | Detail |
|---|---|
| Duration | 4 hours |
| Format | 100% hands-on (no multiple choice) |
| Environment | Live OpenShift cluster via browser |
| Passing score | 70% |
| Version | Based on OpenShift 4.x |
| Open book | No — closed book |
| Certification | RHCS in OpenShift Administration |

**EX280 exam domains:**

| Domain | Weight |
|---|---|
| Manage OpenShift Container Platform | Core |
| Deploy Applications | Core |
| Manage Storage | Core |
| Configure Cluster Authentication | Core |
| Manage Projects and Users | Core |
| Network Configuration | Core |
| Configure Pod Scheduling | Core |
| Limit Resource Usage | Core |
| Manage Application Updates | Core |

---

**Q4. What is a Project in OpenShift?**

A Project is OpenShift's enhanced version of a Kubernetes Namespace. In addition to namespace functionality, a Project:
- Has a display name and description
- Automatically creates RBAC roles (`admin`, `edit`, `view`) for project members
- Can have resource quotas and limit ranges applied
- Appears in the web console's project selector

```bash
# Create project
oc new-project my-project \
  --display-name="My Application" \
  --description="Production environment for my-app"

# List projects
oc get projects
oc projects    # Shows all projects and current context

# Switch project
oc project my-project
```

---

**Q5. What is the `oc` CLI and how does it relate to `kubectl`?**

`oc` is the **OpenShift CLI** — a superset of `kubectl`. It includes all `kubectl` commands plus OpenShift-specific ones:

```bash
# These work identically in both
oc get pods
kubectl get pods

# OpenShift-specific oc commands
oc new-project
oc new-app
oc start-build
oc rollout
oc expose
oc adm                # Cluster administration commands
oc debug              # Debug running pods
oc rsh                # Remote shell into pod (like kubectl exec)
oc port-forward       # Same as kubectl port-forward
oc whoami             # Show current user
oc login              # Login to cluster
```

---

**Q6. What is Source-to-Image (S2I)?**

S2I is an OpenShift build strategy that takes **application source code and automatically builds a container image** without writing a Dockerfile. It:
1. Downloads source code from Git
2. Injects it into a **builder image** (e.g., `python:3.9-ubi8`)
3. Runs the build inside the container
4. Produces a new container image ready to deploy

```bash
# Deploy app directly from Git using S2I
oc new-app python~https://github.com/myorg/my-python-app.git \
  --name=my-app

# Format: <builder-image>~<git-url>
oc new-app nodejs~https://github.com/myorg/node-app.git
oc new-app java~https://github.com/myorg/spring-app.git
```

---

**Q7. What is the OpenShift Web Console?**

The web console provides two perspectives:
- **Developer perspective** — deploy apps, view topology, manage builds, pipelines
- **Administrator perspective** — manage cluster, users, operators, storage, networking

Access:
```bash
# Get web console URL
oc whoami --show-console

# Get API server URL
oc whoami --show-server
```

---

**Q8. What is the Operator Lifecycle Manager (OLM)?**

OLM is OpenShift's framework for **installing, managing, and upgrading Operators**. It provides:
- A catalog of available operators (OperatorHub)
- Dependency management between operators
- Automatic operator upgrades
- Namespace or cluster-wide operator installation

```bash
# List installed operators
oc get operators -A

# List available operator catalogs
oc get catalogsource -n openshift-marketplace

# List installable operators
oc get packagemanifests -n openshift-marketplace
```

---

**Q9. What is a ClusterVersion and how does OpenShift manage upgrades?**

OpenShift uses the **Cluster Version Operator (CVO)** to manage the entire platform lifecycle:

```bash
# Check current cluster version
oc get clusterversion

# Check available updates
oc adm upgrade

# Trigger upgrade (cluster admin only)
oc adm upgrade --to=4.14.5

# Check upgrade status
oc get clusterversion
oc get clusteroperators    # Monitor operator upgrade status
```

---

**Q10. What is CRI-O in OpenShift?**

OpenShift uses **CRI-O** as its container runtime (not Docker). CRI-O is a lightweight container runtime that implements the Kubernetes CRI (Container Runtime Interface) and uses runc to run containers. It is optimized for Kubernetes workloads and has a smaller attack surface than Docker.

---

## 2. OpenShift Architecture & Components

---

**Q11. What are the node types in an OpenShift cluster?**

| Node Type | Role |
|---|---|
| **Control Plane (Master)** | Runs API server, etcd, scheduler, controllers |
| **Worker** | Runs application workloads |
| **Infra** | Runs cluster infrastructure (registry, monitoring, router) |
| **Storage** | Runs storage components (ODF/Ceph) |
| **Edge** | Remote edge locations (single-node OpenShift) |

```bash
# View nodes and their roles
oc get nodes
oc get nodes -l node-role.kubernetes.io/worker

# Label a node as infra
oc label node node1 node-role.kubernetes.io/infra=
```

---

**Q12. What are Cluster Operators?**

Cluster Operators are OpenShift's built-in operators that manage core platform components. They are managed by CVO and cannot be uninstalled:

```bash
# List all cluster operators and their status
oc get clusteroperators

# KEY COLUMNS:
# NAME                    VERSION   AVAILABLE   PROGRESSING   DEGRADED
# authentication          4.14.5    True        False         False
# console                 4.14.5    True        False         False
# dns                     4.14.5    True        False         False
# etcd                    4.14.5    True        False         False
# ingress                 4.14.5    True        False         False
# monitoring              4.14.5    True        False         False
# network                 4.14.5    True        False         False
# storage                 4.14.5    True        False         False
```

---

**Q13. What is the OpenShift Router and how does it differ from a Kubernetes Ingress Controller?**

The **OpenShift Router** (based on HAProxy by default) is OpenShift's Ingress controller. It:
- Handles HTTP/HTTPS traffic routing via **Routes** (OpenShift's native resource)
- Automatically gets a wildcard DNS entry (e.g., `*.apps.cluster.example.com`)
- Supports edge, passthrough, and re-encrypt TLS termination

```bash
# Get router info
oc get ingresscontroller -n openshift-ingress-operator

# Get router pods
oc get pods -n openshift-ingress

# Get default ingress domain
oc get ingresses.config.openshift.io cluster \
  -o jsonpath='{.spec.domain}'
```

---

**Q14. What is the OpenShift internal image registry?**

OpenShift includes a **built-in container image registry** (`image-registry.openshift-image-registry.svc:5000`) that:
- Stores images built by BuildConfigs (S2I, Docker builds)
- Integrates with ImageStreams
- Exposed externally via a Route for pushing/pulling

```bash
# Check registry status
oc get configs.imageregistry.operator.openshift.io cluster

# Get external registry hostname
oc get route default-route -n openshift-image-registry

# Login to internal registry
podman login -u $(oc whoami) \
  -p $(oc whoami -t) \
  default-route-openshift-image-registry.apps.cluster.example.com
```

---

**Q15. What is etcd's role in OpenShift?**

etcd stores all cluster state in OpenShift, same as in Kubernetes. In OpenShift 4.x:
- etcd runs as static Pods on control plane nodes
- Managed by the **etcd Cluster Operator**
- Automatically backed up by the operator

```bash
# Check etcd cluster health
oc get etcd -o=jsonpath='{range .items[0].status.conditions[?(@.type=="EtcdMembersAvailable")]}{.message}{"\n"}'

# Manual etcd backup (cluster-admin)
oc debug node/<master-node> -- \
  chroot /host /usr/local/bin/cluster-backup.sh /home/core/backup
```

---

**Q16. What is Machine Config and MCO?**

The **Machine Config Operator (MCO)** manages OS-level configuration on OpenShift nodes using `MachineConfig` objects:
- Manages file contents, systemd units, kernel arguments
- Applies changes by draining the node and rebooting (rolling update)

```bash
# List machine configs
oc get machineconfig

# List machine config pools (group of nodes)
oc get machineconfigpool

# MachineConfigPool: master, worker, custom pools
# Pool shows DEGRADED if a node can't apply config
```

---

**Q17. What is the difference between the `openshift-*` namespaces and user namespaces?**

| `openshift-*` namespaces | User/Project namespaces |
|---|---|
| Reserved for cluster infrastructure | User workloads |
| Managed by Cluster Operators | Managed by users/admins |
| e.g., `openshift-ingress`, `openshift-monitoring` | e.g., `production`, `dev` |
| Cannot be deleted by users | Can be deleted by project admins |
| Run with elevated privileges | Restricted by default |

---

## 3. Projects, Users & Authentication

---

**Q18. How does authentication work in OpenShift?**

OpenShift supports multiple **identity providers (IdP)** configured in the OAuth server:

| Identity Provider | Description |
|---|---|
| `HTPasswd` | Username/password file (good for testing/small setups) |
| `LDAP` | Active Directory, OpenLDAP |
| `GitHub` | GitHub OAuth |
| `GitLab` | GitLab OAuth |
| `Google` | Google OAuth |
| `OpenID Connect` | Generic OIDC (Okta, Azure AD, Keycloak) |
| `Keystone` | OpenStack identity service |
| `RequestHeader` | Proxy-based auth |

---

**Q19. How do you configure HTPasswd authentication?**

```bash
# Step 1: Create htpasswd file
htpasswd -c -B -b /tmp/htpasswd admin SecurePass123
htpasswd -B -b /tmp/htpasswd developer DevPass456

# Step 2: Create Secret from htpasswd file
oc create secret generic htpasswd-secret \
  --from-file=htpasswd=/tmp/htpasswd \
  -n openshift-config

# Step 3: Configure OAuth to use HTPasswd
cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: htpasswd-provider
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpasswd-secret
EOF

# Step 4: Verify login
oc login -u admin -p SecurePass123

# Add/update user in existing htpasswd
oc get secret htpasswd-secret -n openshift-config \
  -o jsonpath='{.data.htpasswd}' | base64 -d > /tmp/htpasswd
htpasswd -B -b /tmp/htpasswd newuser NewPass789
oc create secret generic htpasswd-secret \
  --from-file=htpasswd=/tmp/htpasswd \
  -n openshift-config --dry-run=client -o yaml | oc replace -f -
```

---

**Q20. How do you manage users and groups in OpenShift?**

```bash
# List users
oc get users
oc get identity

# Delete a user completely
oc delete user developer
oc delete identity htpasswd-provider:developer

# Create a group
oc adm groups new dev-team

# Add users to group
oc adm groups add-users dev-team alice bob charlie

# List groups
oc get groups

# Remove user from group
oc adm groups remove-users dev-team bob

# Grant cluster role to user
oc adm policy add-cluster-role-to-user cluster-admin alice
oc adm policy remove-cluster-role-from-user cluster-admin alice
```

---

**Q21. How do you grant roles to users in a project?**

```bash
# Grant project-level roles
oc adm policy add-role-to-user admin alice -n my-project
oc adm policy add-role-to-user edit bob -n my-project
oc adm policy add-role-to-user view charlie -n my-project

# Grant to group
oc adm policy add-role-to-group edit dev-team -n my-project

# Remove role
oc adm policy remove-role-from-user edit bob -n my-project

# View role bindings in project
oc get rolebindings -n my-project
oc describe rolebinding admin -n my-project
```

---

**Q22. What are the default project roles in OpenShift?**

| Role | Permissions |
|---|---|
| `admin` | Full control within the project; can manage RBAC |
| `edit` | Create, update, delete most resources; cannot manage RBAC |
| `view` | Read-only access to project resources |
| `basic-user` | Can view basic project info; cannot see resources |
| `self-provisioner` | Can create new projects |

---

**Q23. How do you prevent users from creating new projects?**

```bash
# Remove self-provisioner cluster role from authenticated users
oc adm policy remove-cluster-role-from-group \
  self-provisioner \
  system:authenticated:oauth

# Verify
oc describe clusterrolebinding self-provisioners

# Re-enable project creation for authenticated users
oc adm policy add-cluster-role-to-group \
  self-provisioner \
  system:authenticated:oauth
```

---

**Q24. What is a ServiceAccount in OpenShift?**

Same as Kubernetes, but with OpenShift extensions:

```bash
# Create service account
oc create serviceaccount my-sa -n my-project

# Grant SCC to service account (OpenShift-specific)
oc adm policy add-scc-to-user anyuid -z my-sa -n my-project

# Create token for service account
oc create token my-sa -n my-project

# Use SA in deployment
oc set serviceaccount deployment my-app my-sa -n my-project
```

---

**Q25. How do you log in to OpenShift and check who you are?**

```bash
# Login with username/password
oc login https://api.cluster.example.com:6443 \
  -u admin \
  -p SecurePass123

# Login with token
oc login --token=sha256~abc123... \
  --server=https://api.cluster.example.com:6443

# Check current user
oc whoami

# Get current token
oc whoami -t

# Get API server URL
oc whoami --show-server

# Get console URL
oc whoami --show-console

# Logout
oc logout
```

---

## 4. Deployments, Builds & ImageStreams

---

**Q26. What is `oc new-app` and what does it create?**

`oc new-app` is a convenience command that **creates all resources needed to deploy an application**:

```bash
# From Git (S2I auto-detection)
oc new-app https://github.com/myorg/my-python-app.git --name=my-app

# Explicitly specify builder image
oc new-app python~https://github.com/myorg/my-app.git --name=my-app

# From existing container image
oc new-app nginx:1.25 --name=web-server

# From a Dockerfile in Git
oc new-app https://github.com/myorg/my-app.git \
  --strategy=docker --name=my-app

# What it creates:
# - BuildConfig (for Git sources)
# - ImageStream
# - Deployment
# - Service
```

---

**Q27. What is a BuildConfig?**

A `BuildConfig` (BC) is an OpenShift CRD that defines **how to build a container image**:

```yaml
apiVersion: build.openshift.io/v1
kind: BuildConfig
metadata:
  name: my-app
spec:
  source:
    type: Git
    git:
      uri: https://github.com/myorg/my-app.git
      ref: main
  strategy:
    type: Source          # S2I strategy
    sourceStrategy:
      from:
        kind: ImageStreamTag
        name: python:3.9-ubi8
        namespace: openshift
  output:
    to:
      kind: ImageStreamTag
      name: my-app:latest
  triggers:
  - type: ConfigChange
  - type: ImageChange
```

---

**Q28. What are the build strategies in OpenShift?**

| Strategy | Description |
|---|---|
| **Source (S2I)** | Uses a builder image + source code to produce an app image |
| **Docker** | Uses a `Dockerfile` from the source repository |
| **Custom** | Uses a custom builder image that defines the entire build process |
| **Pipeline** | Triggers a Tekton/Jenkins pipeline (deprecated) |

```bash
# Start a build manually
oc start-build my-app

# Follow build logs
oc logs -f buildconfig/my-app
oc logs -f build/my-app-1

# Get build status
oc get builds
oc describe build my-app-1
```

---

**Q29. What is an ImageStream?**

An ImageStream is an OpenShift resource that provides an **abstraction layer** over container images. It:
- Tracks image tags and their underlying digests
- Triggers automatic redeployments when a new image is pushed
- Prevents the need to update all configs when an image changes location

```bash
# List imagestreams
oc get imagestreams
oc get is    # Short form

# Get imagestream tags
oc get imagestreamtags
oc get istag

# Describe an imagestream
oc describe imagestream my-app

# Import an external image into an imagestream
oc import-image my-nginx:latest \
  --from=docker.io/nginx:latest \
  --confirm

# Tag an imagestream
oc tag my-app:latest my-app:production
```

---

**Q30. What is a DeploymentConfig vs a Deployment in OpenShift?**

| DeploymentConfig (DC) | Deployment |
|---|---|
| OpenShift-specific (older) | Kubernetes-native |
| Managed by OpenShift DC controller | Managed by K8s Deployment controller |
| Supports ImageStream triggers | No ImageStream triggers |
| Has lifecycle hooks | Uses init containers / Jobs |
| `oc rollout` | `oc rollout` or `kubectl rollout` |
| Being deprecated | Preferred going forward |

```bash
# DeploymentConfig (legacy)
oc get dc
oc rollout status dc/my-app
oc rollout history dc/my-app
oc rollout undo dc/my-app

# Modern Deployment
oc get deployment
oc rollout status deployment/my-app
```

Red Hat recommends migrating from DeploymentConfig to Deployment.

---

**Q31. How do you deploy an application from a container image in OpenShift?**

```bash
# Method 1: oc new-app
oc new-app --image=nginx:1.25 --name=web-server -n my-project

# Method 2: oc create deployment (Kubernetes-style)
oc create deployment web-server \
  --image=nginx:1.25 \
  --replicas=3 \
  -n my-project

# Method 3: YAML manifest
oc apply -f deployment.yaml

# Expose as service and route
oc expose deployment web-server --port=80
oc expose svc/web-server
```

---

**Q32. How do you update an application (rolling update) in OpenShift?**

```bash
# Update image tag
oc set image deployment/my-app my-app=nginx:1.26

# Check rollout
oc rollout status deployment/my-app

# View history
oc rollout history deployment/my-app

# Rollback
oc rollout undo deployment/my-app
oc rollout undo deployment/my-app --to-revision=2

# Restart all pods (rolling restart)
oc rollout restart deployment/my-app

# Pause/resume rollout
oc rollout pause deployment/my-app
oc rollout resume deployment/my-app
```

---

**Q33. How do you scale an application in OpenShift?**

```bash
# Scale deployment
oc scale deployment my-app --replicas=5

# Scale DeploymentConfig (legacy)
oc scale dc/my-app --replicas=3

# Autoscale (HPA)
oc autoscale deployment my-app \
  --min=2 \
  --max=10 \
  --cpu-percent=70

# Check HPA
oc get hpa
```

---

**Q34. What are build triggers in OpenShift?**

Build triggers automatically start a new build when certain conditions are met:

| Trigger | Description |
|---|---|
| `ConfigChange` | Build triggered when BuildConfig is created/updated |
| `ImageChange` | Build triggered when source builder image updates |
| `Generic webhook` | External webhook (any HTTP POST) |
| `GitHub webhook` | GitHub-specific webhook on push events |
| `GitLab webhook` | GitLab-specific webhook |

```bash
# Get webhook URLs
oc describe bc/my-app | grep -A 5 "Webhook"

# Trigger build via generic webhook
curl -X POST \
  "https://api.cluster.example.com:6443/apis/build.openshift.io/v1/namespaces/my-project/buildconfigs/my-app/webhooks/<secret>/generic"

# Manually start build
oc start-build my-app
oc start-build my-app --from-dir=.    # Build from local directory
```

---

## 5. Networking — Routes, Services & Policies

---

**Q35. What is an OpenShift Route?**

A Route is OpenShift's mechanism for **exposing Services to external traffic** via the Router (HAProxy). It provides:
- HTTP/HTTPS routing
- Host-based routing (hostname → Service)
- TLS termination options
- Path-based routing

```bash
# Create route from existing service
oc expose svc/my-app

# Create route with specific hostname
oc expose svc/my-app --hostname=myapp.apps.cluster.example.com

# Create secure route (edge TLS)
oc create route edge my-app-secure \
  --service=my-app \
  --hostname=myapp.apps.cluster.example.com \
  --cert=tls.crt \
  --key=tls.key

# List routes
oc get routes
oc get route my-app -o jsonpath='{.spec.host}'
```

---

**Q36. What are the TLS termination types for Routes?**

| Type | Description | Traffic to Pod |
|---|---|---|
| **Edge** | TLS terminated at Router | HTTP (unencrypted) |
| **Passthrough** | TLS passed through to Pod | HTTPS (encrypted, Router doesn't decrypt) |
| **Re-encrypt** | TLS terminated at Router, re-encrypted to Pod | HTTPS (new certificate) |

```bash
# Edge termination
oc create route edge my-route \
  --service=my-svc \
  --cert=tls.crt \
  --key=tls.key \
  --ca-cert=ca.crt

# Passthrough termination (app handles TLS)
oc create route passthrough my-route \
  --service=my-svc

# Re-encrypt
oc create route reencrypt my-route \
  --service=my-svc \
  --cert=tls.crt \
  --key=tls.key \
  --dest-ca-cert=dest-ca.crt
```

---

**Q37. How does DNS work in OpenShift?**

OpenShift uses **CoreDNS** (same as Kubernetes) for cluster-internal DNS. Routes get external DNS via:
- A wildcard DNS entry: `*.apps.<cluster-domain>` → Router IP
- All Routes under `apps.<cluster-domain>` resolve to the Router

```bash
# Internal service DNS
http://my-svc.my-project.svc.cluster.local
http://my-svc          # Within same namespace

# External Route
http://my-app.apps.cluster.example.com   # Wildcard DNS

# Get cluster base domain
oc get dns.config.openshift.io cluster \
  -o jsonpath='{.spec.baseDomain}'
```

---

**Q38. What is a NetworkPolicy in OpenShift?**

Same as Kubernetes NetworkPolicy — controls Pod-to-Pod traffic. OpenShift's default CNI (OVN-Kubernetes or OpenShift SDN) supports NetworkPolicies:

```bash
# By default, OpenShift uses namespace isolation mode:
# Pods in different projects CAN'T communicate without policy

# Allow specific ingress traffic
cat <<EOF | oc apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend
  namespace: backend-project
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: frontend-project
      podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 8080
EOF
```

---

**Q39. What is the difference between OpenShift SDN and OVN-Kubernetes?**

| Feature | OpenShift SDN (legacy) | OVN-Kubernetes (current) |
|---|---|---|
| Technology | OVS (Open vSwitch) | OVN + OVS |
| Networkpolicy | Basic | Full + Egress |
| Egress IPs | Via EgressNetworkPolicy | Via EgressIP CRD |
| Multicast | Supported | Supported |
| Status | Deprecated in OCP 4.14 | Default in OCP 4.12+ |

```bash
# Check current network type
oc get network.config.openshift.io cluster \
  -o jsonpath='{.spec.networkType}'
```

---

**Q40. What is an EgressIP in OpenShift?**

An EgressIP assigns a **stable outbound IP** to a namespace — all Pods in the namespace appear to external systems as coming from that IP:

```yaml
apiVersion: k8s.ovn.org/v1
kind: EgressIP
metadata:
  name: production-egress
spec:
  egressIPs:
  - 192.168.1.100
  namespaceSelector:
    matchLabels:
      environment: production
  podSelector:
    matchLabels:
      app: my-app
```

Useful for whitelisting OpenShift applications in external firewalls.

---

## 6. Storage in OpenShift

---

**Q41. How does storage work in OpenShift?**

OpenShift uses standard Kubernetes storage primitives plus additional operators:
- **PersistentVolumes (PV)** and **PersistentVolumeClaims (PVC)** — same as Kubernetes
- **StorageClasses** — define dynamic provisioners
- **OpenShift Data Foundation (ODF)** — Red Hat's storage solution (Ceph-based)
- **CSI Drivers** — AWS EBS, Azure Disk, NFS, etc.

```bash
# List storage classes
oc get storageclass

# List PVs
oc get pv

# List PVCs in current project
oc get pvc

# Create PVC
cat <<EOF | oc apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: my-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
  storageClassName: standard
EOF
```

---

**Q42. How do you add storage to a running Deployment in OpenShift?**

```bash
# Add persistent storage to a deployment
oc set volume deployment/my-app \
  --add \
  --name=data-vol \
  --type=pvc \
  --claim-name=my-data \
  --mount-path=/data

# Add a ConfigMap as a volume
oc set volume deployment/my-app \
  --add \
  --name=config-vol \
  --configmap-name=app-config \
  --mount-path=/etc/config

# Add a Secret as a volume
oc set volume deployment/my-app \
  --add \
  --name=secret-vol \
  --secret-name=my-secret \
  --mount-path=/etc/secrets

# Create and attach PVC in one command
oc set volume deployment/my-app \
  --add \
  --name=data-vol \
  --type=pvc \
  --claim-size=5Gi \
  --mount-path=/data
```

---

**Q43. What is OpenShift Data Foundation (ODF)?**

ODF is Red Hat's container-native storage solution based on **Ceph**. It provides:
- Block storage (RBD)
- File storage (CephFS) — ReadWriteMany supported
- Object storage (Ceph RADOS Gateway / S3-compatible)

```bash
# Check ODF status (if installed)
oc get storagecluster -n openshift-storage
oc get cephcluster -n openshift-storage

# Storage classes created by ODF:
# ocs-storagecluster-ceph-rbd    (block, RWO)
# ocs-storagecluster-cephfs      (file, RWX)
# openshift-storage.noobaa.io    (object)
```

---

**Q44. How do you configure the default StorageClass?**

```bash
# View storage classes
oc get storageclass

# Set default storage class
oc patch storageclass <name> \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'

# Remove default annotation from old default
oc patch storageclass <old-default> \
  -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}'
```

---

**Q45. How do you resize a PVC in OpenShift?**

```bash
# StorageClass must have allowVolumeExpansion: true

# Resize PVC
oc patch pvc my-data \
  -p '{"spec":{"resources":{"requests":{"storage":"10Gi"}}}}'

# Monitor resize
oc describe pvc my-data
# Look for: "Resizing" condition

# Note: For file systems, Pod restart may be required to see new size
```

---

## 7. Security — SCC, RBAC & Quotas

---

**Q46. What is a Security Context Constraint (SCC)?**

SCC is OpenShift's **Pod admission mechanism** (more powerful than Kubernetes PodSecurityPolicy/PSA). It controls:
- Which user IDs a container can run as
- Which Linux capabilities can be used
- Whether a container can run as privileged
- SELinux context
- Volume types allowed

```bash
# List SCCs (cluster-admin only)
oc get scc

# View SCC details
oc describe scc restricted-v2

# Key SCCs:
# restricted-v2   — default; no root, random UID
# anyuid          — run as any UID (including root)
# privileged      — full privileges
# hostnetwork     — use host network namespace
# hostpath        — use hostPath volumes
# nonroot         — non-root user, but can specify UID
```

---

**Q47. What is the default SCC and what does it restrict?**

The default SCC for all new Pods is `restricted-v2`:
- **No root** — containers cannot run as UID 0
- **Random UID** — OpenShift assigns a random UID from the namespace's UID range
- **No privileged containers**
- **No host namespace** (network, PID, IPC)
- **No hostPath volumes**
- **SELinux enforced**

This is why third-party images that need root fail by default in OpenShift.

---

**Q48. How do you grant an SCC to a ServiceAccount?**

```bash
# Grant anyuid SCC to a service account
oc adm policy add-scc-to-user anyuid \
  -z my-sa \
  -n my-project

# Grant privileged SCC
oc adm policy add-scc-to-user privileged \
  -z my-sa \
  -n my-project

# Grant to a group
oc adm policy add-scc-to-group anyuid my-group

# Remove SCC
oc adm policy remove-scc-from-user anyuid \
  -z my-sa \
  -n my-project

# Check which SCC a pod is using
oc get pod my-pod \
  -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
```

---

**Q49. How do you determine which SCC a Pod needs?**

```bash
# Check what SCC would be needed
oc adm policy scc-subject-review \
  -f deployment.yaml

# Check which SCC a running pod uses
oc get pod my-pod \
  -o jsonpath='{.metadata.annotations.openshift\.io/scc}'

# Review SCC for existing deployment
oc adm policy scc-review \
  -z my-sa \
  --as=system:serviceaccount:my-project:my-sa

# Common fix for third-party images that need root:
# 1. Create SA
oc create sa anyuid-sa -n my-project
# 2. Grant anyuid SCC
oc adm policy add-scc-to-user anyuid -z anyuid-sa -n my-project
# 3. Assign SA to deployment
oc set serviceaccount deployment/my-app anyuid-sa
```

---

**Q50. What is a ResourceQuota in OpenShift?**

Same as Kubernetes ResourceQuota — limits total resources in a namespace/project:

```bash
# Create a quota
cat <<EOF | oc apply -f - -n my-project
apiVersion: v1
kind: ResourceQuota
metadata:
  name: project-quota
spec:
  hard:
    pods: "20"
    requests.cpu: "4"
    requests.memory: 8Gi
    limits.cpu: "8"
    limits.memory: 16Gi
    persistentvolumeclaims: "10"
    requests.storage: 50Gi
    services: "10"
    secrets: "20"
    configmaps: "20"
EOF

# Check quota usage
oc describe quota -n my-project
oc get resourcequota -n my-project
```

---

**Q51. What is a LimitRange in OpenShift?**

LimitRange sets default and min/max resource constraints per container/Pod in a project:

```bash
cat <<EOF | oc apply -f - -n my-project
apiVersion: v1
kind: LimitRange
metadata:
  name: project-limits
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    default:
      cpu: "500m"
      memory: "256Mi"
    max:
      cpu: "2"
      memory: "2Gi"
    min:
      cpu: "50m"
      memory: "64Mi"
  - type: Pod
    max:
      cpu: "4"
      memory: "4Gi"
EOF

# View limit ranges
oc get limitrange -n my-project
oc describe limitrange project-limits -n my-project
```

---

**Q52. How do you apply cluster-wide RBAC in OpenShift?**

```bash
# Grant cluster admin to user
oc adm policy add-cluster-role-to-user cluster-admin alice

# Grant cluster role to group
oc adm policy add-cluster-role-to-group cluster-reader ops-team

# Remove cluster admin
oc adm policy remove-cluster-role-from-user cluster-admin alice

# List cluster role bindings
oc get clusterrolebindings | grep alice

# Create custom cluster role
oc create clusterrole node-reader \
  --verb=get,list,watch \
  --resource=nodes

# Bind custom cluster role
oc adm policy add-cluster-role-to-user node-reader alice
```

---

**Q53. How do you check and audit permissions in OpenShift?**

```bash
# Check what current user can do
oc auth can-i create pods
oc auth can-i --list -n my-project

# Check as another user
oc auth can-i create pods --as=alice
oc auth can-i list pods --as=system:serviceaccount:my-project:my-sa

# View all role bindings in a project
oc get rolebindings -n my-project -o wide

# Who can do what in a project
oc adm policy who-can create pods -n my-project
oc adm policy who-can delete deployments -n my-project
```

---

**Q54. What is the `cluster-admin` role vs `admin` role?**

| Role | Scope | Capabilities |
|---|---|---|
| `cluster-admin` | Cluster-wide | Full control of everything |
| `admin` | Namespace/Project | Full control within the project; can manage RBAC in project |
| `edit` | Namespace/Project | Create/delete most resources; no RBAC management |
| `view` | Namespace/Project | Read-only |
| `cluster-reader` | Cluster-wide | Read-only across all projects |

---

## 8. OpenShift CLI (`oc`) Mastery

---

**Q55. What are the most important `oc adm` commands?**

```bash
# User and RBAC management
oc adm policy add-role-to-user <role> <user> -n <project>
oc adm policy remove-role-from-user <role> <user> -n <project>
oc adm policy add-cluster-role-to-user <role> <user>
oc adm policy add-scc-to-user <scc> -z <sa> -n <project>
oc adm groups new <group>
oc adm groups add-users <group> <user>

# Node management
oc adm cordon <node>
oc adm uncordon <node>
oc adm drain <node> --ignore-daemonsets --delete-emptydir-data

# Cluster info
oc adm top nodes
oc adm top pods --all-namespaces
oc adm certificate approve <csr>
oc adm upgrade

# Project management
oc adm new-project <project> --admin=alice

# Inspect
oc adm inspect clusteroperator/authentication
oc adm must-gather    # Collect diagnostics
```

---

**Q56. How do you debug in OpenShift?**

```bash
# Open shell in running pod (like kubectl exec)
oc rsh my-pod
oc rsh deployment/my-app    # Selects one pod from deployment

# Debug a failing pod with a different command
oc debug pod/my-pod

# Debug with a different image
oc debug pod/my-pod --image=busybox

# Debug a node (opens privileged pod on the node)
oc debug node/worker-1

# Copy files
oc cp my-pod:/var/log/app.log ./app.log
oc cp ./config.yaml my-pod:/etc/config/

# Port forward
oc port-forward pod/my-pod 8080:8080
oc port-forward svc/my-svc 9090:80
```

---

**Q57. How do you view and manage logs in OpenShift?**

```bash
# Pod logs
oc logs my-pod
oc logs my-pod --previous
oc logs my-pod -f               # Follow
oc logs my-pod -c my-container  # Specific container
oc logs my-pod --tail=100

# Build logs
oc logs -f buildconfig/my-app
oc logs -f build/my-app-3

# Deployment logs (all pods)
oc logs deployment/my-app --all-containers

# Cluster-level logs
oc adm must-gather    # Collect all cluster diagnostics
```

---

**Q58. How do you use `oc explain` in OpenShift?**

```bash
# Get OpenShift-specific resource documentation
oc explain route
oc explain route.spec
oc explain buildconfig
oc explain deploymentconfig
oc explain imagestream

# Works for K8s resources too
oc explain pod.spec.containers
oc explain networkpolicy.spec
```

---

**Q59. How do you set environment variables in OpenShift?**

```bash
# Set env var on deployment
oc set env deployment/my-app \
  APP_ENV=production \
  LOG_LEVEL=info

# Set from ConfigMap
oc set env deployment/my-app \
  --from=configmap/app-config

# Set from Secret
oc set env deployment/my-app \
  --from=secret/db-credentials

# View current env vars
oc set env deployment/my-app --list

# Remove an env var (append -)
oc set env deployment/my-app LOG_LEVEL-
```

---

**Q60. How do you use `oc process` and templates?**

OpenShift Templates allow **parameterized multi-resource applications**:

```bash
# List available templates
oc get templates -n openshift

# Process a template (preview)
oc process -f template.yaml \
  -p APP_NAME=my-app \
  -p IMAGE_TAG=v1.0 \
  | oc apply -f -

# Process and apply in one step
oc new-app --template=postgresql-persistent \
  -p POSTGRESQL_USER=admin \
  -p POSTGRESQL_PASSWORD=secret \
  -p POSTGRESQL_DATABASE=mydb

# Export parameters of a template
oc process --parameters -f template.yaml
```

---

**Q61. What is `oc get events` and when is it used?**

```bash
# Get events in current project
oc get events
oc get events -n my-project

# Sort by time
oc get events --sort-by='.lastTimestamp'

# Watch live events
oc get events -w

# Filter for warnings only
oc get events --field-selector type=Warning

# Critical for debugging:
# - Pod scheduling failures
# - Image pull errors
# - Volume mount failures
# - SCC denied errors
```

---

**Q62. How do you use `oc patch` in OpenShift?**

```bash
# Patch a deployment replica count
oc patch deployment my-app \
  -p '{"spec":{"replicas":5}}'

# Patch using JSON patch
oc patch deployment my-app \
  --type=json \
  -p '[{"op":"replace","path":"/spec/replicas","value":3}]'

# Add annotation
oc patch deployment my-app \
  -p '{"metadata":{"annotations":{"description":"My web app"}}}'

# Patch a route to add annotation
oc patch route my-route \
  -p '{"metadata":{"annotations":{"haproxy.router.openshift.io/timeout":"5m"}}}'
```

---

## 9. Cluster Configuration & Operators

---

**Q63. What is the OpenShift Monitoring Stack?**

OpenShift ships with a **pre-configured monitoring stack** based on the kube-prometheus project:

| Component | Role |
|---|---|
| Prometheus | Metrics collection and storage |
| Alertmanager | Alert routing and notifications |
| Thanos | Multi-cluster metrics query |
| Grafana | Visualization (deprecated in 4.11+ — use console) |
| Node Exporter | Node-level metrics |
| kube-state-metrics | Cluster object metrics |

```bash
# Check monitoring stack
oc get pods -n openshift-monitoring

# Access Prometheus UI
oc get route prometheus-k8s -n openshift-monitoring

# Access Alertmanager
oc get route alertmanager-main -n openshift-monitoring
```

---

**Q64. How do you configure user workload monitoring in OpenShift?**

By default, OpenShift monitoring only monitors cluster components. To enable monitoring for user workloads:

```bash
# Enable user workload monitoring
cat <<EOF | oc apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: cluster-monitoring-config
  namespace: openshift-monitoring
data:
  config.yaml: |
    enableUserWorkload: true
EOF

# User workload monitoring components appear in:
oc get pods -n openshift-user-workload-monitoring

# Users can then create ServiceMonitors and PrometheusRules in their namespaces
cat <<EOF | oc apply -f - -n my-project
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: my-app-monitor
spec:
  selector:
    matchLabels:
      app: my-app
  endpoints:
  - port: metrics
    interval: 30s
EOF
```

---

**Q65. What is the Cluster Autoscaler in OpenShift?**

OpenShift supports cluster autoscaling via `ClusterAutoscaler` and `MachineAutoscaler` resources:

```yaml
# ClusterAutoscaler - cluster-wide settings
apiVersion: autoscaling.openshift.io/v1
kind: ClusterAutoscaler
metadata:
  name: default
spec:
  resourceLimits:
    maxNodesTotal: 20
  scaleDown:
    enabled: true
    delayAfterAdd: 10m

---
# MachineAutoscaler - per machine set
apiVersion: autoscaling.openshift.io/v1beta1
kind: MachineAutoscaler
metadata:
  name: worker-eu-central-1a
  namespace: openshift-machine-api
spec:
  minReplicas: 1
  maxReplicas: 5
  scaleTargetRef:
    kind: MachineSet
    name: cluster-worker-eu-central-1a
```

---

**Q66. What is a MachineSet in OpenShift?**

A MachineSet manages a group of **Machine** objects (like a ReplicaSet for worker nodes). It defines the desired number and configuration of nodes:

```bash
# List machine sets
oc get machineset -n openshift-machine-api

# Scale a machine set (add nodes)
oc scale machineset <name> \
  --replicas=3 \
  -n openshift-machine-api

# Get machines
oc get machines -n openshift-machine-api
```

---

**Q67. How do you manage certificates in OpenShift?**

```bash
# List certificate signing requests
oc get csr

# Approve a CSR
oc adm certificate approve <csr-name>

# Approve all pending CSRs
oc get csr -o name | xargs oc adm certificate approve

# Configure custom API server certificates
oc patch apiserver cluster \
  --type=merge \
  -p '{"spec":{"servingCerts":{"namedCertificates":[{"names":["api.example.com"],"servingCertificate":{"name":"api-cert"}}]}}}'
```

---

**Q68. What is the OpenShift Alertmanager configuration?**

```bash
# Edit Alertmanager configuration
oc edit secret alertmanager-main -n openshift-monitoring

# Config is base64-encoded — decode, edit, re-encode
oc get secret alertmanager-main \
  -n openshift-monitoring \
  -o jsonpath='{.data.alertmanager\.yaml}' | base64 -d > alertmanager.yaml

# Edit alertmanager.yaml, then update secret
oc create secret generic alertmanager-main \
  --from-file=alertmanager.yaml \
  -n openshift-monitoring \
  --dry-run=client -o yaml | oc replace -f -
```

---

**Q69. What is an OperatorGroup?**

An `OperatorGroup` defines the **target namespaces** an Operator manages:

```yaml
# AllNamespaces — operator manages all namespaces
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: global-operators
  namespace: operators
spec: {}   # Empty spec = all namespaces

---
# OwnNamespace — operator only manages its own namespace
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: my-project-operators
  namespace: my-project
spec:
  targetNamespaces:
  - my-project
```

---

**Q70. How do you install an Operator via the CLI?**

```bash
# Step 1: Find the operator package
oc get packagemanifests -n openshift-marketplace | grep cert-manager

# Step 2: Get available channels
oc describe packagemanifest cert-manager-operator \
  -n openshift-marketplace

# Step 3: Create OperatorGroup (if needed)
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cert-manager-og
  namespace: cert-manager
spec:
  targetNamespaces:
  - cert-manager
EOF

# Step 4: Create Subscription
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cert-manager-operator
  namespace: cert-manager
spec:
  channel: stable-v1
  name: cert-manager-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
  installPlanApproval: Automatic
EOF

# Step 5: Verify installation
oc get csv -n cert-manager
oc get installplan -n cert-manager
```

---

## 10. EX280 Exam-Style Scenarios

---

**Q71. EX280 TASK: Configure HTPasswd identity provider with two users.**

```bash
# Step 1: Create htpasswd file
htpasswd -c -B -b /tmp/htpasswd admin Admin1234!
htpasswd -B -b /tmp/htpasswd developer Dev1234!

# Step 2: Create secret
oc create secret generic htpasswd-secret \
  --from-file=htpasswd=/tmp/htpasswd \
  -n openshift-config

# Step 3: Configure OAuth
cat <<EOF | oc apply -f -
apiVersion: config.openshift.io/v1
kind: OAuth
metadata:
  name: cluster
spec:
  identityProviders:
  - name: htpasswd
    mappingMethod: claim
    type: HTPasswd
    htpasswd:
      fileData:
        name: htpasswd-secret
EOF

# Step 4: Verify
sleep 30
oc login -u developer -p Dev1234! \
  --server=https://api.cluster.example.com:6443
oc whoami
```

---

**Q72. EX280 TASK: Create a project with resource quotas and limit ranges.**

```bash
# Step 1: Create project as admin
oc adm new-project quota-project \
  --display-name="Quota Test Project" \
  --admin=developer

# Step 2: Apply ResourceQuota
cat <<EOF | oc apply -f - -n quota-project
apiVersion: v1
kind: ResourceQuota
metadata:
  name: quota-project-quota
spec:
  hard:
    pods: "10"
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    persistentvolumeclaims: "5"
    requests.storage: 20Gi
EOF

# Step 3: Apply LimitRange
cat <<EOF | oc apply -f - -n quota-project
apiVersion: v1
kind: LimitRange
metadata:
  name: quota-project-limits
spec:
  limits:
  - type: Container
    defaultRequest:
      cpu: "100m"
      memory: "128Mi"
    default:
      cpu: "500m"
      memory: "256Mi"
    max:
      cpu: "1"
      memory: "1Gi"
EOF

# Step 4: Verify
oc describe quota -n quota-project
oc describe limitrange -n quota-project
```

---

**Q73. EX280 TASK: Deploy an application that requires root (anyuid SCC).**

```bash
# Scenario: Third-party image runs as root, fails with default SCC

# Step 1: Create project and service account
oc new-project legacy-app
oc create serviceaccount legacy-sa

# Step 2: Grant anyuid SCC
oc adm policy add-scc-to-user anyuid \
  -z legacy-sa \
  -n legacy-app

# Step 3: Deploy with service account
oc create deployment legacy-web \
  --image=legacy-nginx:1.0 \
  -n legacy-app

oc set serviceaccount deployment/legacy-web \
  legacy-sa \
  -n legacy-app

# Step 4: Verify pod runs
oc get pods -n legacy-app
oc get pod <pod-name> \
  -o jsonpath='{.metadata.annotations.openshift\.io/scc}'
# Should show: anyuid
```

---

**Q74. EX280 TASK: Create a Route with TLS edge termination.**

```bash
# Step 1: Deploy app and service
oc new-project tls-test
oc create deployment web --image=nginx:latest
oc expose deployment web --port=80

# Step 2: Create edge TLS route (using cluster default cert)
oc create route edge web-secure \
  --service=web \
  --hostname=web.apps.cluster.example.com

# Step 3: Create edge TLS route with custom cert
oc create route edge web-custom-tls \
  --service=web \
  --hostname=custom.apps.cluster.example.com \
  --cert=tls.crt \
  --key=tls.key

# Step 4: Verify
oc get routes
curl -k https://web.apps.cluster.example.com

# Step 5: Test re-encrypt (app serves HTTPS internally)
oc create route reencrypt web-reencrypt \
  --service=web-https \
  --hostname=secure.apps.cluster.example.com \
  --cert=tls.crt \
  --key=tls.key \
  --dest-ca-cert=dest-ca.crt
```

---

**Q75. EX280 TASK: Configure project network isolation.**

```bash
# By default in OpenShift, projects are isolated (OVN-Kubernetes)
# Allow communication from monitoring project to app project

cat <<EOF | oc apply -f - -n production
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-from-monitoring
spec:
  podSelector: {}
  ingress:
  - from:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: openshift-monitoring
EOF

# Allow all traffic within same namespace
cat <<EOF | oc apply -f - -n production
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-same-namespace
spec:
  podSelector: {}
  ingress:
  - from:
    - podSelector: {}
EOF

# Deny all ingress (default deny)
cat <<EOF | oc apply -f - -n production
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: deny-all
spec:
  podSelector: {}
  policyTypes:
  - Ingress
EOF
```

---

**Q76. EX280 TASK: Scale an application and configure HPA.**

```bash
# Step 1: Deploy app with resource requests (required for HPA)
oc create deployment web-app \
  --image=nginx:latest \
  -n my-project

oc set resources deployment/web-app \
  --requests=cpu=100m,memory=128Mi \
  --limits=cpu=500m,memory=256Mi

# Step 2: Scale manually
oc scale deployment/web-app --replicas=3

# Step 3: Create HPA
oc autoscale deployment/web-app \
  --min=2 \
  --max=10 \
  --cpu-percent=70

# Step 4: Verify
oc get hpa
oc describe hpa web-app
```

---

**Q77. EX280 TASK: Configure persistent storage for a deployment.**

```bash
# Step 1: Create PVC
cat <<EOF | oc apply -f - -n my-project
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: app-data
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 5Gi
EOF

# Step 2: Wait for PVC to bind
oc get pvc app-data -w

# Step 3: Mount PVC to deployment
oc set volume deployment/my-app \
  --add \
  --name=data-storage \
  --type=pvc \
  --claim-name=app-data \
  --mount-path=/var/data

# Step 4: Verify
oc get pods    # New pod should be created
oc rsh deployment/my-app ls /var/data
```

---

**Q78. EX280 TASK: Perform a rolling update and rollback.**

```bash
# Step 1: Check current image
oc get deployment web-app \
  -o jsonpath='{.spec.template.spec.containers[0].image}'

# Step 2: Update image (rolling update)
oc set image deployment/web-app \
  web-app=nginx:1.26

# Step 3: Monitor rollout
oc rollout status deployment/web-app

# Step 4: View history
oc rollout history deployment/web-app

# Step 5: Rollback if needed
oc rollout undo deployment/web-app

# Step 6: Verify rollback
oc rollout status deployment/web-app
oc get deployment web-app \
  -o jsonpath='{.spec.template.spec.containers[0].image}'
```

---

**Q79. EX280 TASK: Grant a user admin access to a project.**

```bash
# Grant alice admin role in my-project
oc adm policy add-role-to-user admin alice -n my-project

# Grant bob edit role
oc adm policy add-role-to-user edit bob -n my-project

# Grant charlie view role
oc adm policy add-role-to-user view charlie -n my-project

# Grant dev-team group edit access
oc adm policy add-role-to-group edit dev-team -n my-project

# Verify
oc get rolebindings -n my-project
oc auth can-i create pods --as=alice -n my-project   # yes
oc auth can-i create pods --as=charlie -n my-project  # no
```

---

**Q80. EX280 TASK: Configure a ConfigMap and Secret and use in deployment.**

```bash
# Create ConfigMap
oc create configmap app-config \
  --from-literal=APP_ENV=production \
  --from-literal=LOG_LEVEL=info \
  -n my-project

# Create Secret
oc create secret generic db-secret \
  --from-literal=username=dbadmin \
  --from-literal=password=S3cr3tPass! \
  -n my-project

# Inject ConfigMap as env vars
oc set env deployment/my-app \
  --from=configmap/app-config

# Inject Secret as env vars
oc set env deployment/my-app \
  --from=secret/db-secret

# Mount ConfigMap as volume
oc set volume deployment/my-app \
  --add \
  --name=config-vol \
  --configmap-name=app-config \
  --mount-path=/etc/config

# Verify
oc rsh deployment/my-app env | grep APP_ENV
oc rsh deployment/my-app ls /etc/config
```

---

**Q81. EX280 TASK: Remove the cluster-admin role from a user.**

```bash
# Check current cluster role bindings for user
oc get clusterrolebindings \
  -o jsonpath='{range .items[?(@.subjects[0].name=="alice")]}{.metadata.name}{"\n"}'

# Remove cluster-admin
oc adm policy remove-cluster-role-from-user cluster-admin alice

# Verify
oc auth can-i create nodes --as=alice    # no
oc auth can-i list pods --as=alice       # no (depending on other roles)
```

---

**Q82. EX280 TASK: Trigger a build and deploy the result.**

```bash
# Start a new build
oc start-build my-app -n my-project

# Follow the build log
oc logs -f buildconfig/my-app -n my-project

# Wait for build to complete
oc get builds -n my-project

# The build outputs to ImageStream
oc get imagestream my-app -n my-project

# ImageChange trigger automatically redeploys
# Or manually trigger
oc rollout restart deployment/my-app -n my-project

# Verify new pod is running
oc get pods -n my-project
```

---

**Q83. EX280 TASK: Configure an application to use node selectors for scheduling.**

```bash
# Label a node
oc label node worker-1 app-type=high-memory
oc label node worker-2 app-type=high-memory

# Set node selector on deployment
oc patch deployment my-app \
  -p '{"spec":{"template":{"spec":{"nodeSelector":{"app-type":"high-memory"}}}}}'

# Or using oc adm on a project (affects all new pods)
oc adm policy add-scc-to-user anyuid -z default -n my-project

# Annotate project with default node selector
oc annotate namespace my-project \
  openshift.io/node-selector="env=production" \
  --overwrite

# Verify pod placement
oc get pods -o wide -n my-project
```

---

**Q84. EX280 TASK: Use `oc adm must-gather` for diagnostics.**

```bash
# Collect full cluster diagnostics
oc adm must-gather

# Collect to specific directory
oc adm must-gather --dest-dir=/tmp/cluster-state

# Collect for specific operator
oc adm must-gather \
  --image=registry.redhat.io/openshift4/ose-must-gather:latest

# Collect for ODF storage
oc adm must-gather \
  --image=registry.redhat.io/ocs4/ocs-must-gather-rhel8:latest

# Result: tar.gz file with:
# - Cluster operator states
# - Pod logs from all namespaces
# - Events
# - Resource definitions
```

---

**Q85. EX280 TASK: Configure pod disruption budget.**

```bash
cat <<EOF | oc apply -f - -n production
apiVersion: policy/v1
kind: PodDisruptionBudget
metadata:
  name: web-app-pdb
spec:
  minAvailable: 2
  selector:
    matchLabels:
      app: web-app
EOF

# Verify
oc get pdb -n production
oc describe pdb web-app-pdb -n production
```

---

**Q86. EX280 TASK: Create and use a Template.**

```bash
# Create a template
cat <<EOF | oc apply -f - -n openshift
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  name: my-app-template
  namespace: openshift
parameters:
- name: APP_NAME
  required: true
- name: IMAGE_TAG
  value: latest
- name: REPLICA_COUNT
  value: "2"
objects:
- apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: \${APP_NAME}
  spec:
    replicas: \${{REPLICA_COUNT}}
    selector:
      matchLabels:
        app: \${APP_NAME}
    template:
      metadata:
        labels:
          app: \${APP_NAME}
      spec:
        containers:
        - name: \${APP_NAME}
          image: nginx:\${IMAGE_TAG}
- apiVersion: v1
  kind: Service
  metadata:
    name: \${APP_NAME}
  spec:
    selector:
      app: \${APP_NAME}
    ports:
    - port: 80
EOF

# Instantiate template
oc process my-app-template \
  -p APP_NAME=web-frontend \
  -p IMAGE_TAG=1.25 \
  -p REPLICA_COUNT=3 \
  | oc apply -f -
```

---

**Q87. EX280 TASK: Manage cluster upgrade.**

```bash
# Check current version
oc get clusterversion

# Check available updates
oc adm upgrade

# Example output:
# Recommended updates:
#   VERSION     IMAGE
#   4.14.6      quay.io/openshift-release-dev/...

# Start upgrade
oc adm upgrade --to-latest=true
# Or specific version:
oc adm upgrade --to=4.14.6

# Monitor upgrade progress
watch oc get clusterversion
oc get clusteroperators | grep -v "True.*False.*False"
# Healthy operators: AVAILABLE=True, PROGRESSING=False, DEGRADED=False

# Check individual operator status
oc describe clusteroperator authentication
```

---

**Q88. EX280 TASK: Configure image pruning.**

```bash
# Configure automatic image pruning
cat <<EOF | oc apply -f -
apiVersion: imageregistry.operator.openshift.io/v1
kind: Config
metadata:
  name: cluster
spec:
  pruning:
    suspend: false
EOF

# Manual image pruning
oc adm prune images \
  --keep-tag-revisions=3 \
  --keep-younger-than=60m \
  --confirm

# Prune builds
oc adm prune builds \
  --keep-complete=5 \
  --keep-failed=1 \
  --keep-younger-than=10m \
  --confirm

# Prune deployments
oc adm prune deployments \
  --keep-complete=5 \
  --keep-failed=1 \
  --confirm
```

---

**Q89. EX280 TASK: Enable the internal registry and expose it externally.**

```bash
# Enable the registry
oc patch configs.imageregistry.operator.openshift.io cluster \
  --type merge \
  --patch '{"spec":{"managementState":"Managed"}}'

# Configure storage (for non-cloud environments, use empty dir for testing)
oc patch configs.imageregistry.operator.openshift.io cluster \
  --type merge \
  --patch '{"spec":{"storage":{"emptyDir":{}}}}'

# Expose registry externally
oc patch configs.imageregistry.operator.openshift.io cluster \
  --type merge \
  --patch '{"spec":{"defaultRoute":true}}'

# Get registry route
oc get route default-route -n openshift-image-registry

# Login to registry
REGISTRY=$(oc get route default-route \
  -n openshift-image-registry \
  -o jsonpath='{.spec.host}')
podman login -u $(oc whoami) -p $(oc whoami -t) $REGISTRY
```

---

**Q90. EX280 TASK: Configure cluster-wide proxy.**

```bash
# Configure HTTP proxy for the entire cluster
oc edit proxy.config.openshift.io cluster

# Or patch it
oc patch proxy.config.openshift.io cluster \
  --type=merge \
  --patch='{
    "spec": {
      "httpProxy": "http://proxy.example.com:3128",
      "httpsProxy": "http://proxy.example.com:3128",
      "noProxy": "localhost,127.0.0.1,.cluster.local,.svc,10.128.0.0/14"
    }
  }'

# Verify
oc get proxy.config.openshift.io cluster -o yaml
```

---

## EX280 Quick Reference Card

---

**Q91. What are the must-know `oc adm policy` commands for EX280?**

```bash
# Add role to user in namespace
oc adm policy add-role-to-user <role> <user> -n <ns>
oc adm policy remove-role-from-user <role> <user> -n <ns>

# Add cluster role to user
oc adm policy add-cluster-role-to-user <role> <user>
oc adm policy remove-cluster-role-from-user <role> <user>

# Add role to group
oc adm policy add-role-to-group <role> <group> -n <ns>
oc adm policy add-cluster-role-to-group <role> <group>

# SCC management
oc adm policy add-scc-to-user <scc> -z <sa> -n <ns>
oc adm policy remove-scc-from-user <scc> -z <sa> -n <ns>
oc adm policy add-scc-to-group <scc> <group>

# Check permissions
oc adm policy who-can <verb> <resource> -n <ns>
oc auth can-i <verb> <resource> --as=<user> -n <ns>
```

---

**Q92. What is the self-provisioner role and how do you manage it?**

```bash
# self-provisioner allows users to create new projects
# By default, all authenticated OAuth users can create projects

# Check current binding
oc describe clusterrolebinding self-provisioners

# Remove ability for all OAuth users to create projects
oc adm policy remove-cluster-role-from-group \
  self-provisioner \
  system:authenticated:oauth

# Allow specific group to create projects
oc adm policy add-cluster-role-to-group \
  self-provisioner \
  project-creators
```

---

**Q93. What are the most important OpenShift-specific resources for EX280?**

```bash
# OpenShift-specific resources
oc get routes                    # Ingress (OpenShift-native)
oc get buildconfigs / bc         # Build definitions
oc get builds                    # Build instances
oc get imagestreams / is         # Image abstractions
oc get imagestreamtags / istag   # Image tags
oc get deploymentconfigs / dc    # Legacy deployment (OCP 3.x style)
oc get templates                 # Parameterized app templates
oc get clusteroperators / co     # Platform component operators
oc get clusterversion / cv       # Cluster version + upgrade status
oc get oauth                     # Authentication configuration
oc get user                      # OpenShift users
oc get identity                  # User identity mappings
oc get group                     # OpenShift groups
oc get scc                       # Security context constraints
oc get machineset -n openshift-machine-api
oc get machines -n openshift-machine-api
oc get machineconfigpool
oc get machineconfig
```

---

**Q94. What are common EX280 failure scenarios and how to avoid them?**

| Mistake | Prevention |
|---|---|
| Forgot to switch project | Always run `oc project <n>` at task start |
| Wrong namespace in YAML | Double-check `namespace:` field |
| SCC not granted — pod stuck Pending | `oc adm policy add-scc-to-user anyuid -z <sa>` |
| Route hostname wrong domain | Use `oc get ingresses.config cluster -o jsonpath='{.spec.domain}'` |
| User not in htpasswd — auth fails | Re-check htpasswd file and secret update |
| PVC pending — no storageclass | `oc get storageclass` first |
| Forgot to verify work | Always `oc get` + `oc describe` after each task |
| Used kubectl instead of oc | Use `oc` — identical but includes OpenShift objects |
| Quota blocks pod creation | Check `oc describe quota -n <ns>` |

---

**Q95. What are the EX280 exam strategy tips?**

- **Time management** — 4 hours for ~20 tasks; ~12 min per task
- **Read carefully** — tasks are very specific about project names, usernames, values
- **Verify every task** — always confirm with `oc get` / `oc describe` / `oc auth can-i`
- **Use `oc explain`** — built-in docs for all resource fields
- **Use `oc adm` subcommands** — many admin tasks have dedicated oc adm commands
- **Check cluster operator health** — if something seems broken, check `oc get co`
- **Don't modify what you don't need to** — OpenShift is complex; targeted changes only
- **Use `oc whoami` frequently** — confirm you're logged in as the right user
- **Switch projects** — `oc project <n>` before working on project tasks
- **Web console is allowed** — use it for discovery; CLI for task execution

---

**Q96. How do you check cluster health quickly in OpenShift?**

```bash
# Quick health check commands
oc get nodes                         # All nodes Ready?
oc get clusteroperators              # All operators Available?
oc get clusterversion                # Cluster version and status

# More detailed checks
oc get co | grep -v "True.*False.*False"   # Show non-healthy operators
oc get nodes | grep -v Ready              # Show non-Ready nodes
oc get pods --all-namespaces | grep -v "Running\|Completed"  # Failing pods

# Resource usage
oc adm top nodes
oc adm top pods --all-namespaces --sort-by=cpu | head -10
```

---

**Q97. What are the key differences between `oc new-app` output resources for Git vs. image sources?**

```bash
# From Git source (creates build pipeline):
oc new-app python~https://github.com/myorg/app.git
# Creates: BuildConfig, ImageStream, Deployment, Service

# From container image (no build):
oc new-app nginx:1.25 --name=web
# Creates: Deployment, Service (no BuildConfig, no ImageStream)

# From existing imagestream:
oc new-app my-imagestream:latest
# Creates: Deployment, Service

# List what would be created (dry run)
oc new-app python~https://github.com/myorg/app.git \
  --dry-run=true
```

---

**Q98. How do you work with OpenShift secrets securely?**

```bash
# Create generic secret
oc create secret generic my-secret \
  --from-literal=key=value \
  --from-file=config.properties

# Create TLS secret
oc create secret tls my-tls \
  --cert=tls.crt \
  --key=tls.key

# Create docker registry secret
oc create secret docker-registry registry-creds \
  --docker-server=registry.example.com \
  --docker-username=myuser \
  --docker-password=mypass

# Link registry secret to service account (for pulling private images)
oc secrets link default registry-creds --for=pull

# Decode a secret value
oc get secret my-secret \
  -o jsonpath='{.data.key}' | base64 -d

# Update existing secret
oc create secret generic my-secret \
  --from-literal=key=newvalue \
  --dry-run=client -o yaml | oc replace -f -
```

---

**Q99. How is OpenShift different for typical DevOps interview questions in Germany?**

German enterprises heavily use OpenShift (Deutsche Telekom, SAP, many automotive/industrial companies). Common questions:

1. **"What is the difference between Kubernetes and OpenShift?"** — SCCs, Projects, Routes, OLM
2. **"How does SCC work and when do you need anyuid?"** — Third-party images, root requirement
3. **"Explain OpenShift Routes vs Kubernetes Ingress"** — Router, TLS types, wildcard DNS
4. **"How do you deploy an application from source code?"** — S2I, BuildConfig, ImageStreams
5. **"How do you manage users in OpenShift?"** — HTPasswd/LDAP, oc adm policy, groups
6. **"How do you configure monitoring for user workloads?"** — cluster-monitoring-config ConfigMap
7. **"What is OLM and how do you install operators?"** — Subscription, OperatorGroup, CatalogSource
8. **"How do you perform a cluster upgrade?"** — oc adm upgrade, CVO, ClusterOperators
9. **"How do you troubleshoot a pod that won't start?"** — SCCs, quotas, image pull, oc describe
10. **"What is MachineConfig and why is it used?"** — Node OS config, MCO, rolling node updates

---

**Q100. What is the complete EX280 task checklist?**

For each task in the exam:

```bash
# 1. Read task completely before starting

# 2. Switch to correct context/user if specified
oc login -u <user> -p <pass>
oc whoami   # Confirm

# 3. Switch to correct project
oc project <project-name>

# 4. Execute the task

# 5. Verify your work
oc get <resource>
oc describe <resource> <name>
oc auth can-i <verb> <resource> --as=<user> -n <project>

# 6. Test the functional outcome
# (e.g., curl a route, check app is accessible, verify login works)
```

---

**Q101. How do you troubleshoot a Pod stuck in `Pending` in OpenShift?**

```bash
# Step 1: Describe the pod
oc describe pod <pod-name> -n <project>
# Check Events section

# Common OpenShift-specific causes:
# "unable to validate against any security context constraint"
oc adm policy add-scc-to-user anyuid -z default -n <project>

# "0/3 nodes available: 3 node(s) didn't match Pod's node affinity"
oc get nodes --show-labels
oc label node worker-1 <required-label>=<value>

# "exceeded quota"
oc describe quota -n <project>
# Reduce resource requests or increase quota

# "PVC not bound"
oc get pvc -n <project>
oc get storageclass
```

---

**Q102. How does OpenShift handle image security scanning?**

OpenShift includes **Red Hat Quay** integration and can use the **Container Security Operator** for image vulnerability scanning:

```bash
# Check if Container Security Operator is installed
oc get csv -A | grep container-security

# View vulnerability reports
oc get imagemanifestvulns -A

# OpenShift also uses:
# - Red Hat UBI (Universal Base Images) — hardened, scanned base images
# - Clair scanner (in Quay)
# - ImageContentSourcePolicy for mirror registries
```

---

**Q103. What is the ImageContentSourcePolicy?**

Allows mirroring container images from external registries to an internal registry — essential for disconnected/air-gapped OpenShift installations:

```yaml
apiVersion: operator.openshift.io/v1alpha1
kind: ImageContentSourcePolicy
metadata:
  name: mirror-config
spec:
  repositoryDigestMirrors:
  - mirrors:
    - mirror-registry.example.com/openshift4
    source: quay.io/openshift-release-dev/ocp-release
  - mirrors:
    - mirror-registry.example.com/library
    source: docker.io/library
```

---

**Q104. What is the difference between `oc rollout` and `oc deploy`?**

```bash
# oc rollout — Kubernetes-native (works with Deployments)
oc rollout status deployment/my-app
oc rollout history deployment/my-app
oc rollout undo deployment/my-app
oc rollout restart deployment/my-app

# oc deploy — OpenShift-specific (works with DeploymentConfigs - legacy)
oc deploy dc/my-app --latest
oc deploy dc/my-app --cancel

# DeploymentConfig-specific rollback
oc rollout undo dc/my-app
oc rollout history dc/my-app
```

---

**Q105. How do you configure OpenShift to use a custom certificate for the API server?**

```bash
# Step 1: Create TLS secret with custom certificate
oc create secret tls api-server-cert \
  --cert=api.crt \
  --key=api.key \
  -n openshift-config

# Step 2: Configure API server to use the custom cert
oc patch apiserver cluster \
  --type=merge \
  -p '{
    "spec": {
      "servingCerts": {
        "namedCertificates": [{
          "names": ["api.cluster.example.com"],
          "servingCertificate": {
            "name": "api-server-cert"
          }
        }]
      }
    }
  }'

# Step 3: Monitor rollout of API server pods
oc get pods -n openshift-kube-apiserver -w
```

---

**Q106. How do you configure OpenShift to use a custom certificate for the default router (Ingress)?**

```bash
# Step 1: Create TLS secret
oc create secret tls router-certs \
  --cert=wildcard.crt \
  --key=wildcard.key \
  -n openshift-ingress

# Step 2: Update IngressController
oc patch ingresscontroller default \
  --type=merge \
  -p '{
    "spec": {
      "defaultCertificate": {
        "name": "router-certs"
      }
    }
  }' \
  -n openshift-ingress-operator

# Step 3: Verify
oc get ingresscontroller default \
  -n openshift-ingress-operator \
  -o jsonpath='{.spec.defaultCertificate}'

# Test
curl -v https://my-app.apps.cluster.example.com
```

---

**Q107. What is the `oc debug` command and how is it used?**

```bash
# Debug a failing pod (creates copy of pod with shell overriding command)
oc debug pod/my-failing-pod

# Debug with different image
oc debug pod/my-pod --image=registry.access.redhat.com/ubi8/ubi

# Debug a node (opens privileged pod on the node)
oc debug node/worker-1
# Inside node debug pod:
chroot /host
systemctl status kubelet
journalctl -u crio -n 50

# Debug a deployment (picks a pod)
oc debug deployment/my-app

# Keep the pod alive after command
oc debug pod/my-pod -- sleep 3600
```

---

**Q108. How do you manage OpenShift cluster certificates rotation?**

```bash
# Check certificate expiry
oc get csr
oc adm ocp-certificates monitor-certificates

# Rotate kubelet serving certificates
oc adm certificates renew-api-cert-signer

# For worker kubelet certificates
# Nodes periodically auto-rotate via TLS bootstrapping

# Force certificate approval for pending CSRs
oc get csr -o name | xargs oc adm certificate approve

# Check certificate expiry across cluster
oc -n openshift-kube-apiserver-operator \
  get secret kube-apiserver-to-kubelet-signer \
  -o jsonpath='{.metadata.annotations.auth\.openshift\.io/certificate-not-after}'
```

---

**Q109. What is the OpenShift console developer perspective used for?**

The Developer Perspective provides:
- **Topology view** — visual map of all app components and their connections
- **+Add** menu — deploy from Git, container image, Helm chart, Operator catalog
- **Pipelines** — view and manage Tekton pipelines
- **Builds** — view BuildConfigs and build history
- **Monitoring** — app-level metrics and alerts
- **Helm** — manage Helm releases

```bash
# Switch perspective via URL:
# Administrator: /k8s/cluster/projects
# Developer: /topology/ns/<project>

# Or via oc:
oc whoami --show-console
```

---

**Q110. What are the key OpenShift concepts that differ most from vanilla Kubernetes?**

| OpenShift Concept | Kubernetes Equivalent | Key Difference |
|---|---|---|
| Project | Namespace | Adds display name, description, default RBAC |
| Route | Ingress | TLS types (edge/passthrough/reencrypt), wildcard DNS |
| SCC | PSA/PSP | More granular, UID ranges, SELinux |
| DeploymentConfig | Deployment | ImageStream triggers, lifecycle hooks (legacy) |
| ImageStream | None | Abstraction layer for images, triggers |
| BuildConfig | None | S2I builds, webhook triggers |
| Template | Helm (sort of) | Parameterized multi-resource YAML |
| oc adm | kubectl with plugins | Integrated admin operations |
| OLM | Helm (for operators) | Full operator lifecycle management |
| Machine/MachineSet | Node (manual) | Declarative node provisioning |

---

**Q111. How do you configure OpenShift logging (cluster logging)?**

```bash
# Install Cluster Logging Operator via OLM
# Install Loki Operator via OLM (or Elasticsearch Operator)

# Create ClusterLogging instance
cat <<EOF | oc apply -f -
apiVersion: logging.openshift.io/v1
kind: ClusterLogging
metadata:
  name: instance
  namespace: openshift-logging
spec:
  managementState: Managed
  logStore:
    type: lokistack
    lokiStack:
      name: logging-loki
  collection:
    type: vector
EOF

# Check logging pods
oc get pods -n openshift-logging
```

---

**Q112. What is a tekton pipeline and how does OpenShift use it?**

OpenShift Pipelines is based on **Tekton** — a cloud-native CI/CD framework:

```bash
# Check if OpenShift Pipelines is installed
oc get csv -n openshift-operators | grep pipeline

# Key Tekton resources:
oc get tasks -n my-project          # Reusable steps
oc get pipelines -n my-project      # Pipeline definitions
oc get pipelineruns -n my-project   # Pipeline instances

# Trigger a pipeline run
oc create -f pipeline-run.yaml
tkn pipeline start my-pipeline \
  -p IMAGE_URL=registry.example.com/my-app:latest
```

---

**Q113. How do you handle pod anti-affinity in OpenShift for HA?**

```yaml
# Spread replicas across nodes
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchLabels:
                app: my-web-app
            topologyKey: kubernetes.io/hostname
```

```bash
# Apply to existing deployment
oc patch deployment my-app \
  --type=json \
  -p '[{
    "op": "add",
    "path": "/spec/template/spec/affinity",
    "value": {
      "podAntiAffinity": {
        "requiredDuringSchedulingIgnoredDuringExecution": [{
          "labelSelector": {
            "matchLabels": {"app": "my-app"}
          },
          "topologyKey": "kubernetes.io/hostname"
        }]
      }
    }
  }]'
```

---

**Q114. What is the `oc adm cordon/drain/uncordon` workflow in OpenShift?**

```bash
# Cordon node (mark as unschedulable)
oc adm cordon worker-1

# Drain node (evict all pods for maintenance)
oc adm drain worker-1 \
  --ignore-daemonsets \
  --delete-emptydir-data \
  --grace-period=60

# Verify node is drained
oc get pods -o wide --all-namespaces | grep worker-1

# Perform maintenance on worker-1...

# Re-enable scheduling
oc adm uncordon worker-1

# Verify
oc get nodes   # worker-1 should show Ready (not SchedulingDisabled)
```

---

**Q115. How do you check the health of etcd in OpenShift 4?**

```bash
# Check etcd pods
oc get pods -n openshift-etcd

# Check etcd cluster status
oc rsh -n openshift-etcd etcd-master-0 \
  etcdctl endpoint health \
  --cluster \
  --cacert /etc/kubernetes/static-pod-certs/configmaps/etcd-serving-ca/ca-bundle.crt \
  --cert /etc/kubernetes/static-pod-certs/secrets/etcd-all-certs/etcd-peer-master-0.crt \
  --key /etc/kubernetes/static-pod-certs/secrets/etcd-all-certs/etcd-peer-master-0.key

# Check etcd operator status
oc get clusteroperator etcd

# Check etcd member list
oc rsh -n openshift-etcd etcd-master-0 \
  etcdctl member list --write-out=table ...
```

---

**Q116. What is the difference between `oc rsh` and `oc exec`?**

```bash
# oc rsh — opens interactive shell (simpler syntax)
oc rsh my-pod
oc rsh deployment/my-app    # Selects a pod from the deployment

# oc exec — run specific command (same as kubectl exec)
oc exec my-pod -- /bin/bash
oc exec -it my-pod -- /bin/bash
oc exec my-pod -- env

# oc rsh is more convenient for interactive sessions
# oc exec is better for scripting/automation
```

---

**Q117. How do you manage OpenShift node taints?**

```bash
# Add taint to node
oc adm taint nodes worker-gpu dedicated=gpu:NoSchedule

# Remove taint
oc adm taint nodes worker-gpu dedicated=gpu:NoSchedule-

# View node taints
oc describe node worker-gpu | grep Taint

# Pod toleration (same as Kubernetes)
spec:
  tolerations:
  - key: "dedicated"
    operator: "Equal"
    value: "gpu"
    effect: "NoSchedule"
```

---

**Q118. What is the OpenShift Local (CRC) and how is it used for learning?**

**OpenShift Local** (formerly CodeReady Containers/CRC) is a **local OpenShift cluster** running in a VM on your laptop:

```bash
# Install and start
crc setup
crc start

# Login credentials (printed during start):
# Web Console: https://console-openshift-console.apps-crc.testing
# Admin: kubeadmin / <generated password>
# Developer: developer / developer

# Get cluster info
crc console --credentials
crc status

# Configure oc for CRC
eval $(crc oc-env)
oc login -u developer -p developer https://api.crc.testing:6443

# Stop cluster
crc stop
```

Minimum requirements: 4 CPUs, 16 GB RAM, 35 GB disk.

---

**Q119. What OpenShift version management commands should you know for EX280?**

```bash
# Cluster version
oc get clusterversion
oc describe clusterversion version

# Check upgrade channel
oc get clusterversion version \
  -o jsonpath='{.spec.channel}'

# Change upgrade channel
oc patch clusterversion version \
  --type=merge \
  -p '{"spec":{"channel":"stable-4.14"}}'

# List available updates
oc adm upgrade

# Upgrade to specific version
oc adm upgrade --to=4.14.6

# Pause automatic upgrades
oc patch clusterversion version \
  --type=merge \
  -p '{"spec":{"desiredUpdate":null}}'

# Monitor upgrade
oc get clusteroperators -w
```

---

**Q120. Summarize the complete EX280 workflow and what to practice.**

```
EX280 EXAM DAY WORKFLOW:
========================

For each question:
1. Read carefully — note project, username, resource names, values
2. Switch user if needed:   oc login -u <user> -p <pass>
3. Switch project:          oc project <project>
4. Execute task
5. Verify:                  oc get/describe/auth can-i
6. Move on — don't get stuck

KEY AREAS TO PRACTICE:
=======================
✅ HTPasswd identity provider setup
✅ User/group creation and RBAC (add-role-to-user, add-cluster-role-to-user)
✅ SCC management (anyuid for legacy apps)
✅ ResourceQuota + LimitRange creation
✅ Route creation (simple, edge TLS, passthrough)
✅ NetworkPolicy for project isolation
✅ Deployment, scaling, rolling updates, rollbacks
✅ ConfigMap and Secret creation + injection
✅ Persistent storage (PVC creation + mounting)
✅ S2I builds and BuildConfig management
✅ Project creation with admin assignment
✅ Preventing self-provisioning
✅ Node management (cordon, drain, uncordon, taint)
✅ HPA configuration
✅ Cluster upgrade workflow
✅ oc adm must-gather for diagnostics
✅ Image pruning
✅ Monitoring configuration

PRACTICE ENVIRONMENT:
=====================
- OpenShift Local (CRC) — free, runs locally
- Red Hat Developer Sandbox — free cloud OpenShift
- RHPDS (for Red Hat partners/employees)
```

---

*End of OpenShift EX280 Exam Prep & Interview Q&A — 120 Questions (All Levels)*

---

## Complete Interview Preparation Series — FINAL SUMMARY

| Tool | File | Questions |
|---|---|---|
| Kubernetes Beginner | `interview-beginner-qa.md` | 120 |
| Kubernetes Intermediate | `interview-intermediate-qa.md` | 120 |
| Kubernetes Advanced | `interview-advanced-qa.md` | 120 |
| Kubernetes CKA/CKAD | `interview-cka-ckad-qa.md` | 120 |
| ArgoCD | `argocd-interview-qa.md` | 120 |
| Terraform | `terraform-interview-qa.md` | 120 |
| Helm | `helm-interview-qa.md` | 120 |
| OpenShift EX280 | `openshift-ex280-qa.md` | 120 |
| **Total** | | **960 questions** |

**🎉 Complete series done! Nearly 1,000 questions covering the full DevOps stack for German/DACH market roles.**
