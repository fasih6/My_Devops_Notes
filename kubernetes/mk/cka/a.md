# CKA Simulator — killer.sh (Kubernetes 1.35)

> Source: https://killer.sh
> Personal study notes — completed and reviewed

---

## Table of Contents

1. [Question 1 | Contexts](#question-1--contexts)
2. [Question 2 | cert-manager, ClusterIssuer CRD, Helm Install](#question-2--cert-manager-clusterissuer-crd-helm-install)
3. [Question 3 | Scale down StatefulSet](#question-3--scale-down-statefulset)
4. [Question 4 | Find Pods first to be terminated](#question-4--find-pods-first-to-be-terminated)
5. [Question 5 | Kustomize configure HPA Autoscaler](#question-5--kustomize-configure-hpa-autoscaler)
6. [Question 6 | Storage, PV, PVC, Pod volume](#question-6--storage-pv-pvc-pod-volume)
7. [Question 7 | Node and Pod Resource Usage](#question-7--node-and-pod-resource-usage)
8. [Question 8 | Update Kubernetes Version and join cluster](#question-8--update-kubernetes-version-and-join-cluster)
9. [Question 9 | Contact K8s Api from inside Pod](#question-9--contact-k8s-api-from-inside-pod)
10. [Question 10 | RBAC ServiceAccount Role RoleBinding](#question-10--rbac-serviceaccount-role-rolebinding)
11. [Question 11 | DaemonSet on all Nodes](#question-11--daemonset-on-all-nodes)
12. [Question 12 | Deployment on all Nodes](#question-12--deployment-on-all-nodes)
13. [Question 13 | Gateway Api Ingress](#question-13--gateway-api-ingress)
14. [Question 14 | Check how long certificates are valid](#question-14--check-how-long-certificates-are-valid)
15. [Question 15 | NetworkPolicy](#question-15--networkpolicy)
16. [Question 16 | Update CoreDNS Configuration](#question-16--update-coredns-configuration)
17. [Question 17 | Find Container of Pod and check info](#question-17--find-container-of-pod-and-check-info)

---

## General Notes

- Each question is solved on a **specific instance** other than the main `candidate@terminal`. Connect via `ssh <instance>`.
- To switch instances, always `exit` back to the main terminal first, then `ssh` into the next one.
- In the real exam, each question is solved on a **different** instance; in the simulator, several questions may share the same instance.
- Use `sudo -i` to become root on any node when required.

---

## Question 1 | Contexts

**Solve on:** `ssh cka9412`

**Task:**
- Extract kubeconfig context names from `/opt/course/1/kubeconfig` → write to `/opt/course/1/contexts` (one per line)
- Write the current context name → `/opt/course/1/current-context`
- Write the base64-decoded client-certificate of user `account-0027` → `/opt/course/1/cert`

### Step 1 — List all context names

```bash
k --kubeconfig /opt/course/1/kubeconfig config get-contexts
k --kubeconfig /opt/course/1/kubeconfig config get-contexts -oname > /opt/course/1/contexts
```

Result:
```
cluster-admin
cluster-w100
cluster-w200
```

Alternative via jsonpath:
```bash
k --kubeconfig /opt/course/1/kubeconfig config view -o yaml
k --kubeconfig /opt/course/1/kubeconfig config view -o jsonpath="{.contexts[*].name}"
```

### Step 2 — Current context

```bash
k --kubeconfig /opt/course/1/kubeconfig config current-context > /opt/course/1/current-context
```

Result: `cluster-w200`

### Step 3 — Extract and decode the client certificate

```bash
k --kubeconfig /opt/course/1/kubeconfig config view -o yaml --raw
```

Copy `client-certificate-data` for `account-0027@internal` and decode:

```bash
echo LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t... | base64 -d > /opt/course/1/cert
```

Automated one-liner:
```bash
k --kubeconfig /opt/course/1/kubeconfig config view --raw \
  -ojsonpath="{.users[0].user.client-certificate-data}" | base64 -d > /opt/course/1/cert
```

> ✅ **Key takeaway:** `--raw` is required to see certificate/key data in `config view`; without it, sensitive fields are redacted.

---

## Question 2 | cert-manager, ClusterIssuer CRD, Helm Install

**Solve on:** `ssh cka7968`

**Task:**
- Create Namespace `cert-manager`
- Install Helm chart `jetstack/cert-manager` (with `crds.enabled=true`) into it, Release name `cert-manager`
- Update `/opt/course/2/cluster-issuer.yaml` to add `crlDistributionPoints: ["http://example.com/crl"]` under `spec.selfSigned`
- Create the `ClusterIssuer` resource

### Concepts

| Term | Meaning |
|---|---|
| Helm Chart | Kubernetes YAML templates packaged together, customizable via Values |
| Helm Release | An installed instance of a Chart |
| Helm Values | Customize the Chart's templates at install/upgrade time |
| Operator | A Pod that talks to the K8s API, often manages CRDs |
| CRD | Custom Resource Definition — extends the K8s API |

### Step 1 — Create namespace

```bash
k create ns cert-manager
```

### Step 2 — Install the Helm chart

```bash
helm repo list
helm search repo
helm -n cert-manager install cert-manager jetstack/cert-manager --set crds.enabled=true
helm -n cert-manager ls
k -n cert-manager get pod
k get crd
```

New CRDs appear:
```
certificaterequests.cert-manager.io
certificates.cert-manager.io
challenges.acme.cert-manager.io
clusterissuers.cert-manager.io
issuers.cert-manager.io
orders.acme.cert-manager.io
```

Inspect available fields:
```bash
k explain clusterissuer.spec.selfSigned
```

### Step 3 — Update the ClusterIssuer YAML

```yaml
# /opt/course/2/cluster-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: course-issuer
spec:
  selfSigned:
    crlDistributionPoints:               # ADD
    - http://example.com/crl             # ADD
```

### Step 4 — Create it

```bash
k -f /opt/course/2/cluster-issuer.yaml apply
k get clusterissuer
```

> ✅ **Key takeaway:** Installing an operator via Helm, then creating CRD instances (like `ClusterIssuer`) that the operator reconciles, is a very common Kubernetes pattern.

---

## Question 3 | Scale down StatefulSet

**Solve on:** `ssh cka3962`

**Task:** Two Pods `o3db-*` exist in Namespace `project-h800`. Scale down to 1 replica.

```bash
k -n project-h800 get pod | grep o3db
k -n project-h800 get deploy,ds,sts | grep o3db      # confirm it's a StatefulSet
k -n project-h800 get pod --show-labels | grep o3db  # alternative confirmation

k -n project-h800 scale sts o3db --replicas 1
k -n project-h800 get sts o3db
```

> ✅ **Key takeaway:** Pod naming conventions (`name-0`, `name-1`) hint at StatefulSet ownership, but always confirm via `get deploy,ds,sts` or Pod labels before acting.

---

## Question 4 | Find Pods first to be terminated

**Solve on:** `ssh cka2556`

**Task:** Identify Pods in `project-c13` most likely to be terminated first under resource pressure. Write names to `/opt/course/4/pods-terminated-first.txt`.

### Concept

Kubernetes assigns **Quality of Service (QoS)** classes:
- **BestEffort** — no requests/limits set at all → **first to be evicted**
- **Burstable** — some requests/limits set
- **Guaranteed** — requests == limits for all containers

### Manual approach

```bash
k -n project-c13 describe pod | less -p Requests
# or
k -n project-c13 describe pod | grep -A 3 -E 'Requests|^Name:'
```

Result — Deployment `c13-3cc-runner-heavy` has no resource requests:

```
# /opt/course/4/pods-terminated-first.txt
c13-3cc-runner-heavy-65588d7d6-djtv9map
c13-3cc-runner-heavy-65588d7d6-v8kf5map
c13-3cc-runner-heavy-65588d7d6-wwpb4map
```

### Automated approach (jsonpath)

```bash
k -n project-c13 get pod -o jsonpath="{range .items[*]} {.metadata.name}{.spec.containers[*].resources}{'\n'}"
```

### Or check QoS class directly

```bash
k get pods -n project-c13 -o jsonpath="{range .items[*]}{.metadata.name} {.status.qosClass}{'\n'}"
```

Pods with `BestEffort` QoS are the answer.

> ✅ **Key takeaway:** Always set resource requests/limits in production. Use `kubectl top pod`, Prometheus, or `exec` + `top` to determine appropriate values.

---

## Question 5 | Kustomize configure HPA Autoscaler

**Solve on:** `ssh cka5774`

**Task:** Using Kustomize config at `/opt/course/5/api-gateway`:
- Remove ConfigMap `horizontal-scaling-config` completely
- Add HPA `api-gateway` for Deployment `api-gateway`, min 2 / max 4 replicas, 50% avg CPU
- In `prod`, max should be 6 replicas
- Apply changes to both `staging` and `prod`

### Investigate structure

```bash
cd /opt/course/5/api-gateway
ls                     # base  prod  staging
k kustomize base       # inspect base output
k kustomize staging    # inspect staging output (namespace-patched)
k kustomize prod       # inspect prod output
```

Key Kustomize concepts:
- `resources:` — base directory to build from
- `patches:` — files with alterations/additions applied on top
- `transformers:` — e.g. `NamespaceTransformer` to inject namespace cluster-wide

### Step 1 — Remove the ConfigMap from all three levels

Edit `base/api-gateway.yaml`, `staging/api-gateway.yaml`, `prod/api-gateway.yaml` and delete the ConfigMap block from each (removing only from `base` breaks the patch references in overlays).

### Step 2 — Add the HPA to `base/api-gateway.yaml`

```yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: api-gateway
  minReplicas: 2
  maxReplicas: 4
  metrics:
    - type: Resource
      resource:
        name: cpu
        target:
          type: Utilization
          averageUtilization: 50
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: api-gateway
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      id: api-gateway
  template:
    metadata:
      labels:
        id: api-gateway
    spec:
      serviceAccountName: api-gateway
      containers:
        - image: httpd:2-alpine
          name: httpd
```

> Note: no `namespace:` here — the overlay's `NamespaceTransformer` handles it.

### Step 3 — Override maxReplicas in prod

```yaml
# prod/api-gateway.yaml
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: api-gateway
spec:
  maxReplicas: 6
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-gateway
  labels:
    env: prod
```

Verify:
```bash
k kustomize staging | grep maxReplicas -B5   # → 4
k kustomize prod    | grep maxReplicas -B5   # → 6
```

### Step 4 — Apply and clean up remnant ConfigMaps

```bash
k kustomize staging | kubectl diff -f -
k kustomize staging | kubectl apply -f -
k kustomize prod    | kubectl apply -f -

k -n api-gateway-staging delete cm horizontal-scaling-config
k -n api-gateway-prod    delete cm horizontal-scaling-config
```

> ⚠️ **Important — Kustomize has no state.** Removing a resource from YAML does **not** delete it from the cluster automatically; you must delete it manually. Helm, by contrast, tracks release state and *will* prune removed resources.

> ⚠️ **HPA vs. Deployment replicas conflict:** once the HPA sets `replicas`, re-applying the Deployment YAML (which still says `replicas: 1`) will cause a diff/drift. Best practice: omit `replicas:` from the Deployment spec entirely when an HPA manages it.

| Approach | Availability | State Tracking |
|---|---|---|
| Kustomize | Less complex, no state | Manual cleanup needed |
| Helm | Tracks release state | More powerful but complex on state mismatch |

---

## Question 6 | Storage, PV, PVC, Pod volume

**Solve on:** `ssh cka7968`

**Task:**
- PV `safari-pv`: 2Gi, `ReadWriteOnce`, hostPath `/Volumes/Data`, no storageClassName
- PVC `safari-pvc` in `project-t230`: 2Gi, `ReadWriteOnce`, no storageClassName, must bind to the PV
- Deployment `safari` in `project-t230`, image `httpd:2-alpine`, mounts the PVC at `/tmp/safari-data`

### Step 1 — PersistentVolume

```yaml
# 6_pv.yaml
kind: PersistentVolume
apiVersion: v1
metadata:
 name: safari-pv
spec:
 capacity:
  storage: 2Gi
 accessModes:
  - ReadWriteOnce
 hostPath:
  path: "/Volumes/Data"
```

```bash
k -f 6_pv.yaml create
```

> ⚠️ `hostPath` carries security risks and node-locality issues (data is only visible on the node the Pod lands on) — avoid in real deployments where possible.

### Step 2 — PersistentVolumeClaim

```yaml
# 6_pvc.yaml
kind: PersistentVolumeClaim
apiVersion: v1
metadata:
  name: safari-pvc
  namespace: project-t230
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
     storage: 2Gi
```

```bash
k -f 6_pvc.yaml create
k -n project-t230 get pv,pvc     # confirm STATUS: Bound
```

### Step 3 — Deployment with volume mount

```bash
k -n project-t230 create deploy safari --image=httpd:2-alpine --dry-run=client -o yaml > 6_dep.yaml
```

```yaml
# 6_dep.yaml (relevant additions)
    spec:
      volumes:
      - name: data
        persistentVolumeClaim:
          claimName: safari-pvc
      containers:
      - image: httpd:2-alpine
        name: container
        volumeMounts:
        - name: data
          mountPath: /tmp/safari-data
```

```bash
k -f 6_dep.yaml create
k -n project-t230 describe pod safari-<hash> | grep -A2 Mounts:
```

---

## Question 7 | Node and Pod Resource Usage

**Solve on:** `ssh cka5774`

**Task:** metrics-server is installed. Write:
- `/opt/course/7/node.sh` → node resource usage
- `/opt/course/7/pod.sh` → Pod/container resource usage

```bash
k top -h
k top node
k top pod -h
```

```bash
# /opt/course/7/node.sh
kubectl top node
```

```bash
# /opt/course/7/pod.sh
kubectl top pod --containers=true
```

> ✅ **Key takeaway:** Always write full command names (`kubectl`), not shell aliases (`k`), inside scripts meant to be portable/graded.

---

## Question 8 | Update Kubernetes Version and join cluster

**Solve on:** `ssh cka3962` (worker: `ssh cka3962-node1`)

**Task:**
- Update `cka3962-node1`'s Kubernetes version to match the control-plane exactly
- Join the node to the cluster via `kubeadm`

### Step 1 — Check versions

```bash
k get node                      # control-plane version, e.g. v1.35.2
ssh cka3962-node1
sudo -i
kubectl version
kubelet --version               # e.g. v1.34.5 (outdated)
kubeadm version                 # confirm target version available
```

### Step 2 — Attempt kubeadm upgrade (expected to fail — not yet joined)

```bash
kubeadm upgrade node
# error: couldn't create a Kubernetes client from file "/etc/kubernetes/kubelet.conf"
```

This is expected since the node isn't part of the cluster yet — proceed to just upgrade the packages.

### Step 3 — Upgrade kubelet/kubectl packages

```bash
apt update
apt show kubectl -a | grep 1.35
apt install kubectl=1.35.2-1.1 kubelet=1.35.2-1.1
kubelet --version                # confirm updated
service kubelet restart
```

> The kubelet will fail to start cleanly until the node actually joins the cluster — that's expected at this stage.

### Step 4 — Generate join token on control-plane

```bash
exit          # back to cka3962-node1's normal user, then...
sudo -i
kubeadm token create --print-join-command
kubeadm token list
```

### Step 5 — Join the node

```bash
ssh cka3962-node1
kubeadm join 192.168.100.31:6443 --token <TOKEN> \
  --discovery-token-ca-cert-hash sha256:<HASH>
service kubelet status
```

> 💡 If `kubeadm join` fails, try `kubeadm reset` first, then retry.

### Step 6 — Confirm

```bash
k get node
# Wait for STATUS to flip from NotReady → Ready
```

> ✅ **Key takeaway:** `kubeadm upgrade node` is for nodes **already** in the cluster. A brand-new/unjoined node just needs matching package versions installed, then `kubeadm join`.

---

## Question 9 | Contact K8s Api from inside Pod

**Solve on:** `ssh cka9412`

**Task:**
- Create Pod `api-contact` (image `nginx:1-alpine`) in Namespace `project-swan`, using existing ServiceAccount `secret-reader`
- From inside the Pod, `curl` the K8s API to list all Secrets
- Write the result to `/opt/course/9/result.json`

### Step 1 — Create the Pod with the ServiceAccount

```bash
k run api-contact --image=nginx:1-alpine --dry-run=client -o yaml > 9.yaml
```

```yaml
# 9.yaml
apiVersion: v1
kind: Pod
metadata:
  name: api-contact
  namespace: project-swan             # add
  labels:
    run: api-contact
spec:
  serviceAccountName: secret-reader   # add
  containers:
  - image: nginx:1-alpine
    name: api-contact
```

```bash
k -f 9.yaml apply
```

### Step 2 — Exec in and query the API

```bash
k -n project-swan exec api-contact -it -- sh
```

```sh
curl https://kubernetes.default              # SSL error (self-signed CA)
curl -k https://kubernetes.default            # 403 — system:anonymous
curl -k https://kubernetes.default/api/v1/secrets   # still 403, no auth token passed
```

### Step 3 — Authenticate using the ServiceAccount token

```sh
TOKEN=$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)
curl -k https://kubernetes.default/api/v1/secrets -H "Authorization: Bearer ${TOKEN}"
```

Sanity-check permissions from outside the Pod:
```bash
k auth can-i get secret --as system:serviceaccount:project-swan:secret-reader
```

### Step 4 — Save result

```sh
curl -k https://kubernetes.default/api/v1/secrets -H "Authorization: Bearer ${TOKEN}" > result.json
exit
```

```bash
k -n project-swan exec api-contact -it -- cat result.json > /opt/course/9/result.json
```

### Bonus — connect without `-k` (verify CA properly)

```sh
CACERT=/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
curl --cacert ${CACERT} https://kubernetes.default/api/v1/secrets -H "Authorization: Bearer ${TOKEN}"
```

> ✅ **Key takeaway:** Every Pod gets a projected ServiceAccount token + CA cert at `/var/run/secrets/kubernetes.io/serviceaccount/`, enabling in-cluster API authentication without extra config.

---

## Question 10 | RBAC ServiceAccount Role RoleBinding

**Solve on:** `ssh cka3962`

**Task:** In `project-hamster`, create ServiceAccount `processor`, Role `processor`, and RoleBinding `processor` — allowing `processor` to **only create** Secrets and ConfigMaps in that Namespace.

### RBAC combinations cheat sheet

| Combination | Scope | Valid? |
|---|---|---|
| Role + RoleBinding | Namespace-scoped, applied in namespace | ✅ |
| ClusterRole + ClusterRoleBinding | Cluster-wide, applied cluster-wide | ✅ |
| ClusterRole + RoleBinding | Cluster-wide permissions, applied in one namespace | ✅ |
| Role + ClusterRoleBinding | Namespace-scoped permissions, applied cluster-wide | ❌ Not possible |

### Steps

```bash
k -n project-hamster create sa processor

k -n project-hamster create role processor \
  --verb=create --resource=secret --resource=configmap

k -n project-hamster create rolebinding processor \
  --role processor --serviceaccount project-hamster:processor
```

Resulting Role:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: processor
  namespace: project-hamster
rules:
- apiGroups: [""]
  resources: ["secrets", "configmaps"]
  verbs: ["create"]
```

Resulting RoleBinding:
```yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: processor
  namespace: project-hamster
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: processor
subjects:
- kind: ServiceAccount
  name: processor
  namespace: project-hamster
```

### Verify

```bash
k -n project-hamster auth can-i create secret    --as system:serviceaccount:project-hamster:processor  # yes
k -n project-hamster auth can-i create configmap --as system:serviceaccount:project-hamster:processor  # yes
k -n project-hamster auth can-i create pod       --as system:serviceaccount:project-hamster:processor  # no
k -n project-hamster auth can-i delete secret    --as system:serviceaccount:project-hamster:processor  # no
k -n project-hamster auth can-i get configmap    --as system:serviceaccount:project-hamster:processor  # no
```

> 🎯 **CKS-relevant gap:** watch for RBAC **privilege escalation** via `update`/`patch` verbs on `rolebindings`/`clusterrolebindings` — a subject that can patch a binding object can potentially grant itself broader roles. Always audit `bind`, `escalate`, and `impersonate` verbs carefully.

---

## Question 11 | DaemonSet on all Nodes

**Solve on:** `ssh cka2556`

**Task:** In `project-tiger`, create DaemonSet `ds-important`, image `httpd:2-alpine`, labels `id=ds-important` and `uuid=18426a0b-5f59-4e10-923f-c0e078e82462`. Requests: `10m` CPU / `10Mi` memory. Must run on **all** nodes, including control-planes.

```bash
k -n project-tiger create deployment --image=httpd:2.4-alpine ds-important --dry-run=client -o yaml > 11.yaml
```

```yaml
# 11.yaml
apiVersion: apps/v1
kind: DaemonSet                                     # change from Deployment
metadata:
  labels:
    id: ds-important
    uuid: 18426a0b-5f59-4e10-923f-c0e078e82462
  name: ds-important
  namespace: project-tiger
spec:
  selector:
    matchLabels:
      id: ds-important
      uuid: 18426a0b-5f59-4e10-923f-c0e078e82462
  template:
    metadata:
      labels:
        id: ds-important
        uuid: 18426a0b-5f59-4e10-923f-c0e078e82462
    spec:
      containers:
      - image: httpd:2-alpine
        name: ds-important
        resources:
          requests:
            cpu: 10m
            memory: 10Mi
      tolerations:
      - effect: NoSchedule
        key: node-role.kubernetes.io/control-plane
```

```bash
k -f 11.yaml create
k -n project-tiger get ds
k -n project-tiger get pod -l id=ds-important -o wide
```

> ✅ **Key takeaway:** `kubectl create` has no direct DaemonSet generator — repurpose a Deployment manifest (remove `replicas`/`strategy`, change `kind`) or start from a Kubernetes docs example. Remember the **control-plane toleration** is required to schedule onto control-plane nodes.

---

## Question 12 | Deployment on all Nodes

**Solve on:** `ssh cka2556`

**Task:** In `project-tiger`:
- Deployment `deploy-important`, 3 replicas, label `id=very-important`
- Container 1: `container1` / `nginx:1-alpine`
- Container 2: `container2` / `registry.k8s.io/pause:3.10`
- Only one Pod per worker node (`topologyKey: kubernetes.io/hostname`)

> With 2 worker nodes and 3 replicas, the 3rd Pod should remain **Pending** — this simulates DaemonSet-like behavior via a fixed-replica Deployment.

### Option A — podAntiAffinity

```bash
k -n project-tiger create deployment --image=nginx:1-alpine deploy-important --dry-run=client -o yaml > 12.yaml
```

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    id: very-important
  name: deploy-important
  namespace: project-tiger
spec:
  replicas: 3
  selector:
    matchLabels:
      id: very-important
  template:
    metadata:
      labels:
        id: very-important
    spec:
      containers:
      - image: nginx:1-alpine
        name: container1
      - image: registry.k8s.io/pause:3.10
        name: container2
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: id
                operator: In
                values:
                - very-important
            topologyKey: kubernetes.io/hostname
```

### Option B — topologySpreadConstraints

```yaml
      topologySpreadConstraints:
      - maxSkew: 1
        topologyKey: kubernetes.io/hostname
        whenUnsatisfiable: DoNotSchedule
        labelSelector:
          matchLabels:
            id: very-important
```

### Apply and verify

```bash
k -f 12.yaml create
k -n project-tiger get deploy -l id=very-important       # READY 2/3
k -n project-tiger get pod -o wide -l id=very-important   # one Pending
```

Expected event on the Pending Pod:
```
Warning  FailedScheduling  ...  2 node(s) didn't match pod anti-affinity rules
# or
Warning  FailedScheduling  ...  2 node(s) didn't match pod topology spread constraints
```

---

## Question 13 | Gateway Api Ingress

**Solve on:** `ssh cka7968`

**Task:** In `project-r500`, replace the old Ingress (`/opt/course/13/ingress.yaml`) with a Gateway API `HTTPRoute` named `traffic-director`, referencing the existing Gateway:
- Replicate `/desktop` and `/mobile` routes
- Add `/auto`: exact `User-Agent: mobile` → mobile backend, otherwise → desktop backend
- Reachable at `http://r500.gateway:30080`

### Investigate existing CRDs / Gateway

```bash
k get crd | grep gateway
k get gateway -A
k get gatewayclass -A
k -n project-r500 get gateway main -oyaml
```

```bash
curl r500.gateway:30080   # 404 (no HTTPRoute yet)
```

### Step 1 — Convert Ingress to HTTPRoute (basic routes)

Original Ingress:
```yaml
# /opt/course/13/ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: traffic-director
spec:
  ingressClassName: nginx
  rules:
    - host: r500.gateway
      http:
        paths:
          - backend: {service: {name: web-desktop, port: {number: 80}}}
            path: /desktop
            pathType: Prefix
          - backend: {service: {name: web-mobile, port: {number: 80}}}
            path: /mobile
            pathType: Prefix
```

New HTTPRoute:
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: traffic-director
  namespace: project-r500
spec:
  parentRefs:
    - name: main
  hostnames:
    - "r500.gateway"
  rules:
    - matches:
        - path:
            type: PathPrefix
            value: /desktop
      backendRefs:
        - name: web-desktop
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /mobile
      backendRefs:
        - name: web-mobile
          port: 80
```

Verify:
```bash
curl r500.gateway:30080/desktop   # Web Desktop App
curl r500.gateway:30080/mobile    # Web Mobile App
```

### Step 2 — Add conditional `/auto` routing

```yaml
    - matches:
        - path:
            type: PathPrefix
            value: /auto
          headers:
          - type: Exact
            name: user-agent
            value: mobile
      backendRefs:
        - name: web-mobile
          port: 80
    - matches:
        - path:
            type: PathPrefix
            value: /auto
      backendRefs:
        - name: web-desktop
          port: 80
```

> ⚠️ **Critical AND vs. OR nuance:**
> - `- path: ... \n  headers: ...` (path and headers **inside the same list item**) → logical **AND**
> - `- path: ...\n- headers: ...` (as **separate list items**) → logical **OR** ❌ wrong here
>
> Also: **rule order matters** — the header-matched (mobile) rule must come **before** the catch-all (desktop) rule, or requests never reach it.

Verify:
```bash
curl -H "User-Agent: mobile"    r500.gateway:30080/auto   # Web Mobile App
curl -H "User-Agent: something" r500.gateway:30080/auto   # Web Desktop App
curl r500.gateway:30080/auto                               # Web Desktop App
```

> ✅ **Key takeaway:** Gateway API (`gateway.networking.k8s.io`) supersedes Ingress conceptually but adds richer composability (GRPCRoute, TCPRoute, multiple implementations via GatewayClass).

---

## Question 14 | Check how long certificates are valid

**Solve on:** `ssh cka9412`

**Task:**
- Check kube-apiserver server cert validity via `openssl`, write expiration → `/opt/course/14/expiration`
- Confirm with `kubeadm certs check-expiration`
- Write the renewal command → `/opt/course/14/kubeadm-renew-certs.sh`

```bash
sudo -i
find /etc/kubernetes/pki | grep apiserver
openssl x509 -noout -text -in /etc/kubernetes/pki/apiserver.crt | grep Validity -A2
```

```
# /opt/course/14/expiration
Oct 29 14:19:27 2025 GMT
```

Cross-check:
```bash
kubeadm certs check-expiration | grep apiserver
```

Renewal command:
```bash
# /opt/course/14/kubeadm-renew-certs.sh
kubeadm certs renew apiserver
```

> ✅ **Key takeaway:** Both `openssl x509 -noout -text` and `kubeadm certs check-expiration` should agree. Know both tools — `openssl` for any arbitrary cert file, `kubeadm certs` for cluster-managed PKI specifically.

---

## Question 15 | NetworkPolicy

**Solve on:** `ssh cka7968`

**Task:** After a security incident, restrict `backend-*` Pods in `project-snake` so they can **only**:
- Reach `db1-*` on port `1111`
- Reach `db2-*` on port `2222`

Must use `app` label selectors. (e.g., access to `vault-*` on port `3333` must be blocked.)

### Investigate labels & baseline connectivity

```bash
k -n project-snake get pod -L app
k -n project-snake get pod -o wide

k -n project-snake exec backend-0 -- curl -s <db1-ip>:1111    # database one
k -n project-snake exec backend-0 -- curl -s <db2-ip>:2222    # database two
k -n project-snake exec backend-0 -- curl -s <vault-ip>:3333  # vault secret storage (should be blocked after fix)
```

### Correct NetworkPolicy — two separate rules

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: np-backend
  namespace: project-snake
spec:
  podSelector:
    matchLabels:
      app: backend
  policyTypes:
    - Egress
  egress:
    - to:
      - podSelector:
          matchLabels:
            app: db1
      ports:
      - protocol: TCP
        port: 1111
    - to:
      - podSelector:
          matchLabels:
            app: db2
      ports:
      - protocol: TCP
        port: 2222
```

Logic: `(dest=db1 AND port=1111) OR (dest=db2 AND port=2222)`

### ⚠️ Common mistake — combining into ONE rule (wrong!)

```yaml
# WRONG — do not do this
  egress:
    - to:
      - podSelector: {matchLabels: {app: db1}}
      - podSelector: {matchLabels: {app: db2}}
      ports:
      - protocol: TCP
        port: 1111
      - protocol: TCP
        port: 2222
```

This evaluates as `(db1 OR db2) AND (1111 OR 2222)` — meaning **backend → db2:1111 would incorrectly be allowed**. This is a classic CKS gap: **NetworkPolicy egress rules need explicit separation when combining destination + port pairs that shouldn't cross-match.**

### Apply & verify

```bash
k -f 15_np.yaml create

k -n project-snake exec backend-0 -- curl -s <db1-ip>:1111    # database one   ✅
k -n project-snake exec backend-0 -- curl -s <db2-ip>:2222    # database two   ✅
k -n project-snake exec backend-0 -- curl -s <vault-ip>:3333  # (hangs/blocked) ✅
```

> 🎯 **CKS-relevant gap (recurring):** NetworkPolicy `to:`/`ports:` list nesting determines AND vs. OR semantics. Multiple `- to:` array entries under **one** rule = OR'd together; separate top-level `egress:` rule entries = fully independent AND blocks. Always double check with `kubectl describe networkpolicy`.

---

## Question 16 | Update CoreDNS Configuration

**Solve on:** `ssh cka5774`

**Task:**
- Backup existing CoreDNS ConfigMap → `/opt/course/16/coredns_backup.yaml`
- Update config so `SERVICE.NAMESPACE.custom-domain` resolves identically to `SERVICE.NAMESPACE.cluster.local`
- Test with busybox

### Step 1 — Backup

```bash
k -n kube-system get cm
k -n kube-system get cm coredns -oyaml > /opt/course/16/coredns_backup.yaml
```

### Step 2 — Edit the Corefile

```bash
k -n kube-system edit cm coredns
```

Change:
```
kubernetes cluster.local in-addr.arpa ip6.arpa {
```
to:
```
kubernetes custom-domain cluster.local in-addr.arpa ip6.arpa {
```

Restart CoreDNS:
```bash
k -n kube-system rollout restart deploy coredns
k -n kube-system get pod
```

### Step 3 — Test

```bash
k run bb --image=busybox:1 -- sh -c 'sleep 1d'
k exec -it bb -- sh
```

```sh
nslookup kubernetes.default.svc.custom-domain   # → 10.96.0.1
nslookup kubernetes.default.svc.cluster.local   # → 10.96.0.1
```

### Recovery from backup (if something breaks)

```bash
k diff -f /opt/course/16/coredns_backup.yaml
k delete -f /opt/course/16/coredns_backup.yaml
k apply -f /opt/course/16/coredns_backup.yaml
k -n kube-system rollout restart deploy coredns
```

> ✅ **Key takeaway:** Always back up ConfigMaps before editing, especially cluster-critical ones like `coredns`. `kubectl edit` opens directly against the live object — a bad Corefile syntax will crash-loop the CoreDNS Pods on restart.

---

## Question 17 | Find Container of Pod and check info

**Solve on:** `ssh cka2556` (worker: `ssh cka2556-node1` / `cka2556-node2`)

**Task:** Create Pod `tigers-reunite` (image `httpd:2-alpine`, labels `pod=container`, `container=pod`) in `project-tiger`. Find its node, SSH in, and use `crictl` to:
- Write container ID + `info.runtimeType` → `/opt/course/17/pod-container.txt`
- Write container logs → `/opt/course/17/pod-container.log`

### Step 1 — Create Pod & find its node

```bash
k -n project-tiger run tigers-reunite --image=httpd:2-alpine --labels "pod=container,container=pod"
k -n project-tiger get pod -o wide
```

### Step 2 — SSH to the node & find the container

```bash
ssh cka2556-node1
sudo -i
crictl ps | grep tigers-reunite
```

### Step 3 — Inspect runtime type

```bash
crictl inspect <container-id> | grep runtimeType
```

```
# /opt/course/17/pod-container.txt
ba62e5d465ff0 io.containerd.runc.v2
```

### Step 4 — Get logs

```bash
crictl logs <container-id>
```

```
# /opt/course/17/pod-container.log
AH00558: httpd: Could not reliably determine the server's fully qualified domain name, ...
[Tue ...] [mpm_event:notice] [pid 1:tid 1] AH00489: Apache/2.4.62 (Unix) configured -- resuming normal operations
[Tue ...] [core:notice] [pid 1:tid 1] AH00094: Command line: 'httpd -D FOREGROUND'
```

> 💡 For large logs, redirect to a file on the worker node and `scp` it back to the main instance rather than copy-pasting terminal output.

> ✅ **Key takeaway:** `crictl` mirrors `docker` CLI ergonomics (`ps`, `inspect`, `logs`, `exec`) and works regardless of underlying runtime (containerd, CRI-O) — essential when `docker` itself isn't the CRI in use.

---

## Summary — Recurring Themes & Personal Gap Log

| Area | Gap / Thing to Remember |
|---|---|
| NetworkPolicy | Explicit CIDR requirement in egress rules; AND vs OR semantics when nesting `to:`/`ports:` |
| RBAC | Privilege escalation risk via `update`/`patch` verbs on `rolebindings`/`clusterrolebindings` |
| Kustomize | No built-in state tracking — manual cleanup of removed resources required |
| Gateway API | Rule ordering matters; nested `matches` = AND, separate list items = OR |
| kubeadm | `upgrade node` only applies to nodes already joined; new nodes just need matching package versions + `kubeadm join` |
| CoreDNS | Always back up ConfigMap before editing; restart Deployment after Corefile changes |
| QoS/Eviction | BestEffort Pods (no requests/limits) are evicted first under resource pressure |
| crictl | Use for container-level debugging regardless of container runtime in use |

---

*End of document.*
