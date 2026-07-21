# CKA Simulator B — killer.sh (Kubernetes 1.35)

> Source: https://killer.sh
> Personal study notes — completed and reviewed

---

## Table of Contents

1. [Question 1 | DNS / FQDN / Headless Service](#question-1--dns--fqdn--headless-service)
2. [Question 2 | Create a Static Pod and Service](#question-2--create-a-static-pod-and-service)
3. [Question 3 | Kubelet client/server cert info](#question-3--kubelet-clientserver-cert-info)
4. [Question 4 | Pod Ready if Service is reachable](#question-4--pod-ready-if-service-is-reachable)
5. [Question 5 | Kubectl sorting](#question-5--kubectl-sorting)
6. [Question 6 | Fix Kubelet](#question-6--fix-kubelet)
7. [Question 7 | Etcd Operations](#question-7--etcd-operations)
8. [Question 8 | Get Controlplane Information](#question-8--get-controlplane-information)
9. [Question 9 | Kill Scheduler, Manual Scheduling](#question-9--kill-scheduler-manual-scheduling)
10. [Question 10 | PV PVC Dynamic Provisioning](#question-10--pv-pvc-dynamic-provisioning)
11. [Question 11 | Create Secret and mount into Pod](#question-11--create-secret-and-mount-into-pod)
12. [Question 12 | Schedule Pod on Controlplane Nodes](#question-12--schedule-pod-on-controlplane-nodes)
13. [Question 13 | Multi Containers and Pod shared Volume](#question-13--multi-containers-and-pod-shared-volume)
14. [Question 14 | Find out Cluster Information](#question-14--find-out-cluster-information)
15. [Question 15 | Cluster Event Logging](#question-15--cluster-event-logging)
16. [Question 16 | Namespaces and Api Resources](#question-16--namespaces-and-api-resources)
17. [Question 17 | Operator, CRDs, RBAC, Kustomize](#question-17--operator-crds-rbac-kustomize)

---

## General Notes

- Each question is solved on a **specific instance** other than the main `candidate@terminal`. Connect via `ssh <instance>`.
- Always `exit` back to the main terminal before switching to a different instance.
- In the real exam, each question uses a **different** instance; in the simulator, several questions may share one.
- Use `sudo -i` to become root on any node when required.

---

## Question 1 | DNS / FQDN / Headless Service

**Solve on:** `ssh cka6016`

**Task:** Update the ConfigMap used by a Deployment in `lima-control` with correct FQDN values:
- `DNS_1`: Service `kubernetes` in `default`
- `DNS_2`: Headless Service `department` in `lima-workload`
- `DNS_3`: Pod `section100` in `lima-workload`, resilient to IP changes
- `DNS_4`: A Pod with IP `1.2.3.4` in `kube-system`

### Concept

Standard cluster-internal DNS pattern: `SERVICE.NAMESPACE.svc.cluster.local`. Since the task asks for **FQDNs**, short forms like `SERVICE.NAMESPACE` are not acceptable even though they'd resolve.

### Investigate via nslookup

```bash
k -n lima-control exec -it controller-586d6657-gdmch -- sh
```

```sh
nslookup google.com                        # sanity check, external DNS works
nslookup kubernetes.default.svc.cluster.local
# → 10.96.0.1
```

### DNS_1 — standard Service

```
kubernetes.default.svc.cluster.local
```

### DNS_2 — Headless Service

```sh
nslookup department.lima-workload.svc.cluster.local
# → returns multiple Pod IPs directly (no ClusterIP)
```

```bash
k -n lima-workload get svc               # department: TYPE ClusterIP, CLUSTER-IP None
k -n lima-workload get endpointslice
```

> A headless Service (`clusterIP: None`) has no virtual IP; DNS resolves directly to the backing Pod IPs, letting the querying application choose which endpoint to use.

```
department.lima-workload.svc.cluster.local
```

### DNS_3 — Pod-specific FQDN via hostname/subdomain

```sh
nslookup section100.section.lima-workload.svc.cluster.local
# → 10.32.0.10 (specific Pod IP, resolves correctly even if IP changes)
```

This only works because the Pod defines `hostname` and `subdomain`:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: section100
  namespace: lima-workload
spec:
  hostname: section100   # matches requested Pod-level name
  subdomain: section     # matches the (headless) Service name
```

```
section100.section.lima-workload.svc.cluster.local
```

### DNS_4 — Pod IP FQDN (no Pod needs to actually exist)

```sh
nslookup 1-2-3-4.kube-system.pod.cluster.local
# → 1.2.3.4
```

Pattern: `IP-WITH-DASHES.NAMESPACE.pod.cluster.local`

```
1-2-3-4.kube-system.pod.cluster.local
```

### Apply the fix

```bash
k -n lima-control edit cm control-config
```

```yaml
data:
  DNS_1: kubernetes.default.svc.cluster.local
  DNS_2: department.lima-workload.svc.cluster.local
  DNS_3: section100.section.lima-workload.svc.cluster.local
  DNS_4: 1-2-3-4.kube-system.pod.cluster.local
```

```bash
k -n lima-control rollout restart deploy controller
k -n lima-control logs -f controller-<new-hash>   # confirm all 4 nslookups succeed
```

> ✅ **Key takeaway:** Four distinct DNS FQDN patterns exist in Kubernetes: `svc.cluster.local` (normal + headless Services), `hostname.subdomain.namespace.svc.cluster.local` (individually addressable Pods behind a headless Service), and `ip-with-dashes.namespace.pod.cluster.local` (any arbitrary Pod IP, even a non-existent one).

---

## Question 2 | Create a Static Pod and Service

**Solve on:** `ssh cka2560`

**Task:**
- Static Pod `my-static-pod` on the control-plane node, `default` namespace, image `nginx:1-alpine`, requests `10m` CPU / `20Mi` memory
- NodePort Service `static-pod-service` exposing it on port 80
- Verify: Service has 1 Endpoint, reachable via `curl <node-internal-ip>:<node-port>`

### Step 1 — Create the static Pod manifest

```bash
sudo -i
cd /etc/kubernetes/manifests/
k run my-static-pod --image=nginx:1-alpine -o yaml --dry-run=client > my-static-pod.yaml
```

```yaml
# /etc/kubernetes/manifests/my-static-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: my-static-pod
  name: my-static-pod
spec:
  containers:
  - image: nginx:1-alpine
    name: my-static-pod
    resources:
      requests:
        cpu: 10m
        memory: 20Mi
```

```bash
k get pod -A | grep my-static
# → default   my-static-pod-cka2560   1/1   Running
```

> 💡 The kubelet appends the node's hostname as suffix to static Pod names automatically (`my-static-pod-cka2560`).

### Step 2 — Expose it

```bash
k expose pod my-static-pod-cka2560 --name static-pod-service --type=NodePort --port 80
```

```bash
k get svc,endpointslice -l run=my-static-pod
```

### Step 3 — Verify connectivity

```bash
k get node -owide     # find INTERNAL-IP
curl 192.168.100.31:<NODE_PORT>
# → nginx welcome page HTML
```

---

## Question 3 | Kubelet client/server cert info

**Solve on:** `ssh cka5248` (worker: `ssh cka5248-node1`)

**Task:** Find Issuer and Extended Key Usage for the kubelet **client** cert (outgoing to API server) and kubelet **server** cert (incoming from API server) on `cka5248-node1`. Write to `/opt/course/3/certificate-info.txt`.

```bash
ssh cka5248-node1
sudo -i
find /var/lib/kubelet/pki
```

### Client certificate

```bash
openssl x509 -noout -text -in /var/lib/kubelet/pki/kubelet-client-current.pem | grep Issuer
# Issuer: CN = kubernetes

openssl x509 -noout -text -in /var/lib/kubelet/pki/kubelet-client-current.pem | grep "Extended Key Usage" -A1
# TLS Web Client Authentication
```

### Server certificate

```bash
openssl x509 -noout -text -in /var/lib/kubelet/pki/kubelet.crt | grep Issuer
# Issuer: CN = cka5248-node1-ca@1730211854

openssl x509 -noout -text -in /var/lib/kubelet/pki/kubelet.crt | grep "Extended Key Usage" -A1
# TLS Web Server Authentication
```

### Result

```
# /opt/course/3/certificate-info.txt
Issuer: CN = kubernetes
X509v3 Extended Key Usage: TLS Web Client Authentication
Issuer: CN = cka5248-node1-ca@1730211854
X509v3 Extended Key Usage: TLS Web Server Authentication
```

> ✅ **Key takeaway:** The kubelet **client** cert is signed by the cluster CA (`CN = kubernetes`) since it's issued through the TLS bootstrap process and used to authenticate *to* the API server. The kubelet **server** cert is typically self-signed locally on the node (`CN = <node>-ca@<timestamp>`) since it's used to authenticate the kubelet *to* incoming API server connections.

---

## Question 4 | Pod Ready if Service is reachable

**Solve on:** `ssh cka3200`

**Task:** In `default`:
- Pod `ready-if-service-ready` (nginx:1-alpine): LivenessProbe = `true`; ReadinessProbe = check `http://service-am-i-ready:80` reachable
- Confirm it starts **not ready**
- Create Pod `am-i-ready` (label `id: cross-server-ready`) so the existing Service `service-am-i-ready` gains an endpoint
- Confirm the first Pod becomes ready

> ⚠️ This is an anti-pattern (Pods shouldn't health-check other Pods this way), but it demonstrates probe + Service DNS mechanics.

### Step 1 — Create the first Pod

```bash
k run ready-if-service-ready --image=nginx:1-alpine --dry-run=client -o yaml > 4_pod1.yaml
```

```yaml
spec:
  containers:
  - image: nginx:1-alpine
    name: ready-if-service-ready
    livenessProbe:
      exec:
        command:
        - 'true'
    readinessProbe:
      exec:
        command:
        - sh
        - -c
        - 'wget -T2 -O- http://service-am-i-ready:80'
```

```bash
k -f 4_pod1.yaml create
k get pod ready-if-service-ready
# READY 0/1 — as expected

k describe pod ready-if-service-ready
# Warning  Unhealthy  Readiness probe failed: command timed out ...
```

### Step 2 — Create the second Pod to give the Service an endpoint

```bash
k run am-i-ready --image=nginx:1-alpine --labels="id=cross-server-ready"
k describe svc service-am-i-ready       # Endpoints now populated
```

```bash
k get pod ready-if-service-ready
# READY 1/1 (after the next probe interval)
```

> ✅ **Key takeaway:** `readinessProbe.httpGet` cannot target an arbitrary remote URL directly — using `exec` + `wget`/`curl` is the workaround for cross-service readiness checks.

---

## Question 5 | Kubectl sorting

**Solve on:** `ssh cka8448`

**Task:** Write two scripts:
- `/opt/course/5/find_pods.sh` — all Pods, all Namespaces, sorted by AGE
- `/opt/course/5/find_pods_uid.sh` — sorted by `metadata.uid`

```bash
# /opt/course/5/find_pods.sh
kubectl get pod -A --sort-by=.metadata.creationTimestamp
```

```bash
# /opt/course/5/find_pods_uid.sh
kubectl get pod -A --sort-by=.metadata.uid
```

> 💡 The `kubectl` cheat sheet (searchable in the K8s docs) is a great reference for sorting, output formatting, and other one-liners under exam time pressure.

---

## Question 6 | Fix Kubelet

**Solve on:** `ssh cka1024`

**Task:** kubelet on control-plane node `cka1024` isn't running. Fix it, confirm `Ready` state, then create Pod `success` (nginx:1-alpine) in `default`.

### Step 1 — Confirm the API server is unreachable

```bash
k get node
# dial tcp 192.168.100.41:6443: connect: connection refused
```

### Step 2 — Check if the kubelet process is running

```bash
sudo -i
ps aux | grep kubelet     # nothing running
service kubelet status    # Active: inactive (dead)
```

### Step 3 — Attempt to start it

```bash
service kubelet start
service kubelet status
# Process: ExecStart=/usr/local/bin/kubelet ... status=203/EXEC
```

`203/EXEC` means the binary path in the ExecStart line couldn't be executed.

### Step 4 — Diagnose the binary path

```bash
/usr/local/bin/kubelet
# -bash: No such file or directory

whereis kubelet
# kubelet: /usr/bin/kubelet
```

Cross-check with `journalctl`/syslog for confirmation:

```bash
cat /var/log/syslog | grep kubelet
# Main process exited, code=exited, status=203/EXEC
```

### Step 5 — Fix the service unit and restart

```bash
vim /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
```

```
ExecStart=
ExecStart=/usr/bin/kubelet $KUBELET_KUBECONFIG_ARGS $KUBELET_CONFIG_ARGS $KUBELET_KUBEADM_ARGS $KUBELET_EXTRA_ARGS
```

```bash
systemctl daemon-reload
service kubelet restart
service kubelet status     # Active: active (running)
ps aux | grep kubelet      # confirm process
```

### Step 6 — Confirm cluster health & create the Pod

```bash
watch crictl ps      # wait for controlplane containers to appear
k get node           # STATUS: Ready (may take a moment)
k run success --image nginx:1-alpine
k get pod success -o wide
```

> ✅ **Key takeaway:** `code=exited, status=203/EXEC` from `systemctl status` is a strong signal of a bad/missing binary path in the unit file — always try running the `ExecStart` binary manually to reproduce and confirm the exact failure.

---

## Question 7 | Etcd Operations

**Solve on:** `ssh cka2560`

**Task:**
- Write `etcd --version` output → `/opt/course/7/etcd-version`
- Snapshot etcd → `/opt/course/7/etcd-snapshot.db`

### Step 1 — Version (etcd runs as a static Pod, not a host binary)

```bash
sudo -i
etcd --version
# Command 'etcd' not found

k -n kube-system get pod | grep etcd
k -n kube-system exec etcd-cka2560 -- etcd --version > /opt/course/7/etcd-version
```

### Step 2 — Snapshot (requires client certs for authentication)

```bash
ETCDCTL_API=3 etcdctl snapshot save /opt/course/7/etcd-snapshot.db
# hangs/fails — no auth provided
```

Find the correct cert paths from the etcd or kube-apiserver static Pod manifest:

```bash
cat /etc/kubernetes/manifests/etcd.yaml
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep etcd
```

```bash
ETCDCTL_API=3 etcdctl snapshot save /opt/course/7/etcd-snapshot.db \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  --cert /etc/kubernetes/pki/etcd/server.crt \
  --key /etc/kubernetes/pki/etcd/server.key
# saved at /opt/course/7/etcd-snapshot.db
```

### (Optional, high-risk) Etcd Restore Walkthrough

> ⚠️ Doing this incorrectly can break the cluster. Only practice this in a disposable environment.

```bash
kubectl run test --image=nginx
kubectl get pod -l run=test

cd /etc/kubernetes/manifests/
mv * ..                    # stop all controlplane static pods
watch crictl ps             # wait for all containers to disappear
```

Since etcd 3.6, use **`etcdutl`** (not `etcdctl`) for restore — this is an **offline** operation, so no certs are needed:

```bash
etcdutl snapshot restore /opt/course/7/etcd-snapshot.db --data-dir /var/lib/etcd-snapshot
```

Point etcd at the restored data directory:

```bash
vim /etc/kubernetes/etcd.yaml
```

```yaml
volumes:
  - hostPath:
      path: /var/lib/etcd-snapshot   # changed from /var/lib/etcd
      type: DirectoryOrCreate
    name: etcd-data
```

```bash
mv ../*.yaml .              # restart controlplane
watch crictl ps
kubectl get pod -l run=test
# No resources found — confirms restore worked (test Pod created after snapshot is gone)
```

> ✅ **Key takeaway:** `etcdctl` (online, needs certs) is for backup/snapshot **save**; `etcdutl` (offline, no certs) is for snapshot **restore** since etcd 3.6 split these tools. Always locate cert paths from the etcd/kube-apiserver static Pod manifests rather than guessing.

---

## Question 8 | Get Controlplane Information

**Solve on:** `ssh cka8448`

**Task:** Determine how `kubelet`, `kube-apiserver`, `kube-scheduler`, `kube-controller-manager`, `etcd`, and DNS are installed/started. Write to `/opt/course/8/controlplane-components.txt` using types: `not-installed`, `process`, `static-pod`, `pod`.

```bash
sudo -i
ps aux | grep kubelet
find /usr/lib/systemd | grep kube      # kubelet.service found
service kubelet status                 # Active: running → process

find /usr/lib/systemd | grep etcd      # nothing → not systemd-managed

find /etc/kubernetes/manifests/
# kube-controller-manager.yaml, etcd.yaml, kube-apiserver.yaml, kube-scheduler.yaml
# → all static Pods

k -n kube-system get pod -o wide       # confirm all 4 + coredns + kube-proxy + weave-net

k -n kube-system get ds                # kube-proxy, weave-net → DaemonSets
k -n kube-system get deploy            # coredns → Deployment
```

### Result

```
# /opt/course/8/controlplane-components.txt
kubelet: process
kube-apiserver: static-pod
kube-scheduler: static-pod
kube-controller-manager: static-pod
etcd: static-pod
dns: pod coredns
```

> ✅ **Key takeaway:** kubeadm-installed clusters run kubelet as a systemd-managed host **process**, while the core control-plane components (`etcd`, `kube-apiserver`, `kube-scheduler`, `kube-controller-manager`) run as **static Pods** defined in `/etc/kubernetes/manifests/`. CoreDNS is a normal cluster-scheduled **Pod** managed by a Deployment.

---

## Question 9 | Kill Scheduler, Manual Scheduling

**Solve on:** `ssh cka5248`

**Task:**
- Temporarily stop `kube-scheduler` (recoverably)
- Create Pod `manual-schedule` (httpd:2-alpine), confirm it's unscheduled
- Manually set its `nodeName` to `cka5248` and get it running
- Restart the scheduler, then confirm normal operation with a second Pod `manual-schedule2` landing on `cka5248-node1`

### Step 1 — Stop the scheduler

```bash
sudo -i
kubectl -n kube-system get pod | grep schedule
cd /etc/kubernetes/manifests/
mv kube-scheduler.yaml ..
watch crictl ps                            # wait for it to disappear
kubectl -n kube-system get pod | grep schedule   # empty
```

### Step 2 — Create the Pod and confirm it's Pending/unscheduled

```bash
k run manual-schedule --image=httpd:2-alpine
k get pod manual-schedule -o wide
# STATUS Pending, NODE <none>
```

### Step 3 — Manually schedule it

```bash
k get pod manual-schedule -o yaml > 9.yaml
```

```yaml
spec:
  nodeName: cka5248     # add this manually
  containers:
  - image: httpd:2-alpine
    ...
```

```bash
k -f 9.yaml replace --force
k get pod manual-schedule -o wide
# STATUS Running, NODE cka5248
```

> 💡 Since a Pod's `nodeName` field is immutable and cannot be patched or edited in place, you must `replace --force` (delete + recreate) rather than `apply`/`edit`.

> ⚠️ Notice: no toleration was needed even though this landed on the control-plane node — because **taints/tolerations are only evaluated by the scheduler**, not by the kubelet. Bypassing the scheduler bypasses that enforcement entirely.

### Step 4 — Restart the scheduler and verify normal operation

```bash
cd /etc/kubernetes/manifests/
mv ../kube-scheduler.yaml .
kubectl -n kube-system get pod | grep schedule    # Running again

k run manual-schedule2 --image=httpd:2-alpine
k get pod -o wide | grep schedule
# manual-schedule2 lands on cka5248-node1 as expected
```

---

## Question 10 | PV PVC Dynamic Provisioning

**Solve on:** `ssh cka6016`

**Task:**
- StorageClass `local-backup`: provisioner `rancher.io/local-path`, `volumeBindingMode: WaitForFirstConsumer`, retains PVs even after PVC deletion
- Adjust Job at `/opt/course/10/backup.yaml` to use a PVC (50Mi) with the new StorageClass
- Verify Job completes and PVC binds to a new PV

### Step 1 — Create the StorageClass

```bash
k get sc
# local-path: rancher.io/local-path, RECLAIMPOLICY Delete
```

```yaml
# sc.yaml
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: local-backup
provisioner: rancher.io/local-path
reclaimPolicy: Retain
volumeBindingMode: WaitForFirstConsumer
```

```bash
k -f sc.yaml apply
```

> 🎯 `reclaimPolicy: Retain` is the key requirement here — it prevents the underlying PV (and its data) from being deleted just because someone deletes the PVC, protecting backup data from accidental loss.

### Step 2 — Update the Job to use a PVC

```bash
cp backup.yaml backup.yaml_ori     # always back up before editing
```

```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: backup-pvc
  namespace: project-bern
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 50Mi
  storageClassName: local-backup
---
apiVersion: batch/v1
kind: Job
metadata:
  name: backup
  namespace: project-bern
spec:
  backoffLimit: 0
  template:
    spec:
      volumes:
        - name: backup
          persistentVolumeClaim:
            claimName: backup-pvc
      containers:
        - name: bash
          image: bash:5
          command:
            - bash
            - -c
            - |
              set -x
              touch /backup/backup-$(date +%Y-%m-%d-%H-%M-%S).tar.gz
              sleep 15
          volumeMounts:
            - name: backup
              mountPath: /backup
      restartPolicy: Never
```

### Step 3 — Deploy and verify

```bash
k delete -f backup.yaml    # remove prior emptyDir-based run
k apply -f backup.yaml

k -n project-bern get job,pod,pvc,pv
```

> 💡 With `volumeBindingMode: WaitForFirstConsumer`, the PV isn't actually provisioned until a Pod that uses the PVC is scheduled — this avoids binding to a node that later turns out to be unsuitable.

### Optional — verify Retain behavior

```bash
k -n project-bern delete pvc backup-pvc
k get pv,pvc -A
# PV STATUS: Released (not deleted) — data preserved on disk
```

> ✅ **Key takeaway:** `rancher.io/local-path` (Local Path Provisioner) backs PVs with local node storage under `/opt/local-path-provisioner`, not real cloud volumes — useful for single-node or dev/test clusters. Always check `reclaimPolicy` before trusting a StorageClass with important data.

---

## Question 11 | Create Secret and mount into Pod

**Solve on:** `ssh cka2560`

**Task:** In new Namespace `secret`:
- Pod `secret-pod` (busybox:1, `sleep 1d`)
- Mount existing Secret `/opt/course/11/secret1.yaml` read-only at `/tmp/secret1`
- Create Secret `secret2` (`user=user1`, `pass=1234`), expose as env vars `APP_USER` / `APP_PASS`

```bash
k create ns secret
```

### Secret 1 — apply existing file (namespace corrected)

```bash
cp /opt/course/11/secret1.yaml 11_secret1.yaml
```

```yaml
metadata:
  name: secret1
  namespace: secret     # updated
```

```bash
k -f 11_secret1.yaml create
```

### Secret 2 — create from literals

```bash
k -n secret create secret generic secret2 --from-literal=user=user1 --from-literal=pass=1234
```

### Pod

```bash
k -n secret run secret-pod --image=busybox:1 --dry-run=client -o yaml -- sh -c "sleep 1d" > 11.yaml
```

```yaml
spec:
  containers:
  - args: ["sh", "-c", "sleep 1d"]
    image: busybox:1
    name: secret-pod
    env:
    - name: APP_USER
      valueFrom:
        secretKeyRef:
          name: secret2
          key: user
    - name: APP_PASS
      valueFrom:
        secretKeyRef:
          name: secret2
          key: pass
    volumeMounts:
    - name: secret1
      mountPath: /tmp/secret1
      readOnly: true
  volumes:
  - name: secret1
    secret:
      secretName: secret1
```

```bash
k -f 11.yaml create
```

### Verify

```bash
k -n secret exec secret-pod -- env | grep APP
# APP_PASS=1234
# APP_USER=user1

k -n secret exec secret-pod -- find /tmp/secret1
k -n secret exec secret-pod -- cat /tmp/secret1/halt
```

> ✅ **Key takeaway:** Two distinct patterns for consuming Secrets — `secretKeyRef` for individual env vars vs. `volumes.secret` for full file mounts — often combined in the same Pod as shown here.

---

## Question 12 | Schedule Pod on Controlplane Nodes

**Solve on:** `ssh cka5248`

**Task:** Pod `pod1` (container `pod1-container`, image httpd:2-alpine) in `default`, must only schedule on control-plane nodes. **Do not label any nodes.**

```bash
k get node
k describe node cka5248 | grep Taint -A1
# Taints: node-role.kubernetes.io/control-plane:NoSchedule

k get node cka5248 --show-labels
# node-role.kubernetes.io/control-plane= (key-only label already present)
```

```bash
k run pod1 --image=httpd:2-alpine --dry-run=client -o yaml > 12.yaml
```

### Solution using nodeSelector (recommended)

```yaml
spec:
  containers:
  - image: httpd:2-alpine
    name: pod1-container
  tolerations:
  - effect: NoSchedule
    key: node-role.kubernetes.io/control-plane
  nodeSelector:
    node-role.kubernetes.io/control-plane: ""
```

> The `nodeSelector` value is an empty string because `node-role.kubernetes.io/control-plane` is a **key-only** label with no meaningful value — matching just needs the key present.

### Solution using nodeAffinity (alternative)

```yaml
  affinity:
    nodeAffinity:
      requiredDuringSchedulingIgnoredDuringExecution:
        nodeSelectorTerms:
        - matchExpressions:
          - key: node-role.kubernetes.io/control-plane
            operator: Exists
```

> ⚠️ **Both toleration AND selector/affinity are required.** A toleration alone only allows scheduling on the control-plane; it doesn't *restrict* to it — the Pod could still land on a worker node. You need the selector/affinity to enforce the restriction.

```bash
k -f 12.yaml create
k get pod pod1 -o wide     # confirm NODE = cka5248
```

---

## Question 13 | Multi Containers and Pod shared Volume

**Solve on:** `ssh cka3200`

**Task:** Pod `multi-container-playground` in `default` with a shared (non-persistent, non-shared-across-Pods) volume:
- `c1` (nginx:1-alpine): env var `MY_NODE_NAME` = the Pod's node name
- `c2` (busybox:1): appends `date` output to `date.log` in the shared volume every second
- `c3` (busybox:1): tails `date.log` to stdout continuously

```bash
k run multi-container-playground --image=nginx:1-alpine --dry-run=client -o yaml > 13.yaml
```

```yaml
spec:
  containers:
  - image: nginx:1-alpine
    name: c1
    env:
    - name: MY_NODE_NAME
      valueFrom:
        fieldRef:
          fieldPath: spec.nodeName
    volumeMounts:
    - name: vol
      mountPath: /vol
  - image: busybox:1
    name: c2
    command: ["sh", "-c", "while true; do date >> /vol/date.log; sleep 1; done"]
    volumeMounts:
    - name: vol
      mountPath: /vol
  - image: busybox:1
    name: c3
    command: ["sh", "-c", "tail -f /vol/date.log"]
    volumeMounts:
    - name: vol
      mountPath: /vol
  volumes:
    - name: vol
      emptyDir: {}
```

```bash
k -f 13.yaml create
k get pod multi-container-playground     # 3/3 Running
```

### Verify

```bash
k exec multi-container-playground -c c1 -- env | grep MY
# MY_NODE_NAME=cka3200

k logs multi-container-playground -c c3
# Streaming date output confirms c2 writes and c3 reads correctly
```

> ✅ **Key takeaway:** `spec.nodeName` via `fieldRef` is the Downward API pattern for exposing Pod/node metadata as env vars. `emptyDir` is the standard non-persistent, Pod-scoped shared volume for inter-container communication within a single Pod.

---

## Question 14 | Find out Cluster Information

**Solve on:** `ssh cka8448`

**Task:** Determine: control-plane node count, worker node count, Service CIDR, CNI plugin + config path, static Pod naming suffix. Write to `/opt/course/14/cluster-info`.

```bash
k get node
# 1 control-plane, 0 workers
```

```bash
sudo -i
cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep range
# --service-cluster-ip-range=10.96.0.0/12
```

```bash
find /etc/cni/net.d/
cat /etc/cni/net.d/10-weave.conflist
# CNI = Weave, config at /etc/cni/net.d/10-weave.conflist
```

Static Pod suffix = the node's hostname with a leading hyphen.

### Result

```
# /opt/course/14/cluster-info
1: 1
2: 0
3: 10.96.0.0/12
4: Weave, /etc/cni/net.d/10-weave.conflist
5: -cka8448
```

> 💡 The kubelet discovers CNI plugins by default from `/etc/cni/net.d/` — this path is consistent across control-plane and worker nodes regardless of which CNI is installed.

---

## Question 15 | Cluster Event Logging

**Solve on:** `ssh cka6016`

**Task:**
- Script `/opt/course/15/cluster_events.sh`: latest cluster-wide events sorted by time
- Delete the `kube-proxy` Pod → capture resulting events → `/opt/course/15/pod_kill.log`
- Manually kill the `kube-proxy` container (via `crictl`) → capture resulting events → `/opt/course/15/container_kill.log`

### Step 1 — The events script

```bash
# /opt/course/15/cluster_events.sh
kubectl get events -A --sort-by=.metadata.creationTimestamp
```

### Step 2 — Delete the Pod, observe events

```bash
k -n kube-system get pod -l k8s-app=kube-proxy -owide
k -n kube-system delete pod kube-proxy-lf2fs
sh /opt/course/15/cluster_events.sh
```

```
# /opt/course/15/pod_kill.log
kube-system   Killing             pod/kube-proxy-lf2fs         Stopping container kube-proxy
kube-system   SuccessfulCreate    daemonset/kube-proxy         Created pod: kube-proxy-wb4tb
kube-system   Scheduled           pod/kube-proxy-wb4tb         Successfully assigned ...
kube-system   Pulled              pod/kube-proxy-wb4tb         Container image already present
kube-system   Created             pod/kube-proxy-wb4tb         Created container kube-proxy
kube-system   Started             pod/kube-proxy-wb4tb         Started container kube-proxy
default       Starting            node/cka6016
```

### Step 3 — Kill just the container, observe events

```bash
sudo -i
crictl ps | grep kube-proxy
crictl rm --force <container-id>
crictl ps | grep kube-proxy      # new container ID appears automatically
sh /opt/course/15/cluster_events.sh
```

```
# /opt/course/15/container_kill.log
kube-system   Created             pod/kube-proxy-wb4tb   Created container kube-proxy
kube-system   Started             pod/kube-proxy-wb4tb   Started container kube-proxy
default       Starting            node/cka6016
default       Starting            node/cka6016
```

> ✅ **Key takeaway:** Deleting the whole **Pod** triggers a full DaemonSet reconciliation cycle (scheduling + pulling + creating), generating more events. Killing just the **container** (kubelet notices and restarts it in place) generates a smaller event footprint since the Pod object itself never changed.

---

## Question 16 | Namespaces and Api Resources

**Solve on:** `ssh cka3200`

**Task:**
- List all namespaced resource kinds → `/opt/course/16/resources.txt`
- Find the `project-*` Namespace with the most Roles → `/opt/course/16/crowded-namespace.txt`

```bash
k api-resources --namespaced -o name > /opt/course/16/resources.txt
```

```bash
k -n project-jinan get role --no-headers | wc -l       # 0
k -n project-miami get role --no-headers | wc -l       # 300
k -n project-melbourne get role --no-headers | wc -l   # 2
k -n project-seoul get role --no-headers | wc -l       # 10
k -n project-toronto get role --no-headers | wc -l     # 0
```

```
# /opt/course/16/crowded-namespace.txt
project-miami with 300 roles
```

> 💡 `kubectl api-resources -h` and `--namespaced` (true/false filter) are easy to forget under time pressure — worth memorizing for quickly enumerating resource scopes.

---

## Question 17 | Operator, CRDs, RBAC, Kustomize

**Solve on:** `ssh cka6016`

**Task:** Kustomize config at `/opt/course/17/operator` (base + prod overlay) deploys an operator working with CRDs.
- Check operator logs → find missing CRD permissions → fix Role `operator-role`
- Add new `Student` resource `student4`
- Deploy changes to `prod`

### Investigate base & prod

```bash
cd /opt/course/17/operator
k kustomize base     # shows CRDs, ServiceAccount, etc. with NAMESPACE_REPLACE placeholder
k kustomize prod     # namespace = operator-prod, label project_id added
```

### Locate the permissions issue

```bash
k -n operator-prod get pod
k -n operator-prod logs operator-<hash>
```

```
Error from server (Forbidden): students.education.killer.sh is forbidden: ... cannot list resource "students"
Error from server (Forbidden): classes.education.killer.sh is forbidden: ... cannot list resource "classes"
```

The operator Deployment simply loops `kubectl get students` / `kubectl get classes` — confirmed via:

```bash
k -n operator-prod edit deploy operator
```

### Fix the Role

Generate the correct rule via dry-run, then copy into the Kustomize base file:

```bash
k -n operator-prod create role operator-role --verb list --resource student --resource class -oyaml --dry-run=client
```

```yaml
# base/rbac.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: Role
metadata:
  name: operator-role
  namespace: default
rules:
- apiGroups:
  - education.killer.sh
  resources:
  - students
  - classes
  verbs:
  - list
```

```bash
kubectl kustomize /opt/course/17/operator/prod | kubectl apply -f -
```

```bash
k -n operator-prod logs operator-<hash>
# kubectl get students / classes now succeed
```

### Add the new Student resource

```yaml
# base/students.yaml (appended)
---
apiVersion: education.killer.sh/v1
kind: Student
metadata:
  name: student4
spec:
  name: Some Name
  description: Some Description
```

```bash
kubectl kustomize /opt/course/17/operator/prod | kubectl apply -f -
k -n operator-prod get student
# student4 created; everything else unchanged
```

> ✅ **Key takeaway:** When debugging CRD/operator RBAC issues, always check the **operator's own logs** first — they usually surface the exact `Forbidden` error naming the missing resource and verb. Use `kubectl create role ... --dry-run=client -oyaml` to generate correct RBAC YAML instead of hand-writing `apiGroups`/`resources`/`verbs` from memory.

---

## Summary — Recurring Themes & Personal Gap Log

| Area | Gap / Thing to Remember |
|---|---|
| DNS | 4 FQDN patterns: normal/headless Service, per-Pod hostname.subdomain, and arbitrary Pod-IP FQDN (`ip-with-dashes.ns.pod.cluster.local`) |
| Static Pods | Named `<pod>-<node-hostname>`; live in `/etc/kubernetes/manifests/`; moving the manifest out/in is the "stop/start" trick |
| Scheduler bypass | Manual `nodeName` assignment skips taint/toleration enforcement entirely — only the scheduler checks those |
| etcd tooling | `etcdctl` = online ops needing certs (snapshot save); `etcdutl` = offline ops, no certs (snapshot restore) since etcd 3.6 |
| kubelet troubleshooting | `status=203/EXEC` in systemd = bad/missing binary path; manually run the `ExecStart` binary to confirm |
| StorageClass | `reclaimPolicy: Retain` protects data after PVC deletion; `WaitForFirstConsumer` delays PV binding until a consuming Pod is scheduled |
| Node restriction | Toleration ≠ restriction — always pair with `nodeSelector`/`nodeAffinity` to force scheduling onto specific (e.g. control-plane) nodes |
| Events | Pod deletion → full DaemonSet/Deployment reconciliation events; container-only kill → minimal kubelet-level events |
| RBAC + Operators | Check operator/application logs for exact `Forbidden` messages before writing RBAC rules; use `--dry-run=client -oyaml` to generate accurate Role YAML |

---

*End of document.*
