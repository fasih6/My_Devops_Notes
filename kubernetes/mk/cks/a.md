# CKS Simulator A — Kubernetes 1.35
### Source: [killer.sh](https://killer.sh)

> Each question needs to be solved on a specific instance other than your main `candidate@terminal`. Connect via the provided `ssh` command. To connect to a different instance, always return first to your main terminal with `exit`.
>
> In the real exam, each question is solved on a **different** instance, whereas in the simulator multiple questions may share the same instance.
>
> Use `sudo -i` to become root on any node when necessary.

---

## Table of Contents

### Exam Questions
1. [Question 1 — Contexts: Configure Access to Multiple Clusters](#question-1--contexts-configure-access-to-multiple-clusters)
2. [Question 2 — Image Vulnerability Scanning](#question-2--image-vulnerability-scanning)
3. [Question 3 — Apiserver Security: Controlling Access to the Kubernetes API](#question-3--apiserver-security-controlling-access-to-the-kubernetes-api)
4. [Question 4 — ServiceAccount Token Expiration](#question-4--serviceaccount-token-expiration)
5. [Question 5 — CIS Benchmark: Securing a Cluster](#question-5--cis-benchmark-securing-a-cluster)
6. [Question 6 — Immutable Root FileSystem](#question-6--immutable-root-filesystem)
7. [Question 7 — Pod Security Standard and Admission](#question-7--pod-security-standard-and-admission)
8. [Question 8 — Docker Configuration and Usage](#question-8--docker-configuration-and-usage)
9. [Question 9 — AppArmor Profile](#question-9--apparmor-profile)
10. [Question 10 — Container Runtime Sandbox (gVisor)](#question-10--container-runtime-sandbox-gvisor)
11. [Question 11 — Secret Management](#question-11--secret-management)
12. [Question 12 — ImagePolicyWebhook](#question-12--imagepolicywebhook)
13. [Question 13 — CiliumNetworkPolicy: Metadata Server](#question-13--ciliumnetworkpolicy-metadata-server)
14. [Question 14 — ETCD Secret Encryption](#question-14--etcd-secret-encryption)
15. [Question 15 — Configure TLS on Ingress](#question-15--configure-tls-on-ingress)
16. [Question 16 — Runtime Security with Falco](#question-16--runtime-security-with-falco)
17. [Question 17 — Audit Log Policy](#question-17--audit-log-policy)

### Preview Questions (Additional)
18. [Preview Question 1 — Using RBAC Authorization](#preview-question-1--using-rbac-authorization)
19. [Preview Question 2 — Auditing: Managing Secrets using kubectl](#preview-question-2--auditing-managing-secrets-using-kubectl)
20. [Preview Question 3 — Unknown Miner Process Investigation](#preview-question-3--unknown-miner-process-investigation)

### Reference
21. [CKS Tips — Kubernetes 1.35](#cks-tips--kubernetes-135)
22. [CKS Exam Info](#cks-exam-info)
23. [Kubernetes Documentation (Allowed Resources)](#kubernetes-documentation-allowed-resources)
24. [CKS Clusters](#cks-clusters)
25. [The Exam UI / Remote Desktop](#the-exam-ui--remote-desktop)
26. [PSI Bridge](#psi-bridge)
27. [Terminal Handling](#terminal-handling)

---

## Question 1 | Contexts: Configure Access to Multiple Clusters

**Topic:** Cluster Access with kubeconfig
**Solve on:** `ssh cks3477`

### Task
- You have access to multiple clusters from your main terminal through kubectl contexts. Write all context names into `/opt/course/1/contexts` on `cks3477`, one per line.
- From the kubeconfig, extract the certificate of user `restricted@infra-prod` and write it decoded to `/opt/course/1/cert`.

### Answer

```bash
ssh cks3477

k config get-contexts # copy by hand

k config get-contexts -o name > /opt/course/1/contexts
```

Or using jsonpath:
```bash
k config view -o jsonpath="{.contexts[*].name}"
k config view -o jsonpath="{.contexts[*].name}" | tr " " "\n" # new lines
k config view -o jsonpath="{.contexts[*].name}" | tr " " "\n" > /opt/course/1/contexts
```

Resulting content:
```text
# cks3477:/opt/course/1/contexts
gianna@infra-prod
kubernetes-admin@kubernetes
restricted@infra-prod
```

For the certificate, view the raw config manually, or extract programmatically:
```bash
k config view --raw -ojsonpath="{@.users[2].user.client-certificate-data}" | base64 -d > /opt/course/1/cert

# Or by name match:
k config view --raw -ojsonpath="{@.users[?(.name == 'restricted@infra-prod')].user.client-certificate-data}" | base64 -d > /opt/course/1/cert
```

```text
# cks3477:/opt/course/1/cert
-----BEGIN CERTIFICATE-----
MIIDHzCCAgegAwIBAgIQN5Qe/Rj/PhaqckEI23LPnjANBgkqhkiG9w0BAQsFADAV
...
-----END CERTIFICATE-----
```

Completed.

[⬆ Back to top](#table-of-contents)

---

## Question 2 | Image Vulnerability Scanning

**Solve on:** `ssh cks8930`

### Task
The vulnerability scanner `trivy` is installed on your main terminal. Use it to scan:
- `nginx:1.16.1-alpine`
- `k8s.gcr.io/kube-apiserver:v1.18.0`
- `k8s.gcr.io/kube-controller-manager:v1.18.0`
- `docker.io/weaveworks/weave-kube:2.7.0`

Write all image names (with tags) that **don't** contain `CVE-2020-10878` or `CVE-2020-1967` into `/opt/course/2/good-images` on `cks8930`.

### Answer

```bash
ssh cks8930

trivy image nginx:1.16.1-alpine | grep -E 'CVE-2020-10878|CVE-2020-1967'
# libcrypto1.1 / libssl1.1 → CVE-2020-1967 (HIGH)

trivy image k8s.gcr.io/kube-apiserver:v1.18.0 | grep -E 'CVE-2020-10878|CVE-2020-1967'
# → CVE-2020-10878

trivy image k8s.gcr.io/kube-controller-manager:v1.18.0 | grep -E 'CVE-2020-10878|CVE-2020-1967'
# → CVE-2020-10878

trivy image docker.io/weaveworks/weave-kube:2.7.0 | grep -E 'CVE-2020-10878|CVE-2020-1967'
# (no output — clean)
```

Only `docker.io/weaveworks/weave-kube:2.7.0` is free of both CVEs:

```text
# cks8930:/opt/course/2/good-images
docker.io/weaveworks/weave-kube:2.7.0
```

[⬆ Back to top](#table-of-contents)

---

## Question 3 | Apiserver Security: Controlling Access to the Kubernetes API

**Solve on:** `ssh cks8930`
**Note:** `sudo -i` may be required.

### Task
The apiserver is currently accessible through a **NodePort** Service. Change the setup so it's only accessible through a **ClusterIP** Service.

### Answer

```bash
ssh cks8930
sudo -i

ps aux | grep kube-apiserver
# notice: --kubernetes-service-node-port=31000

k get svc
# kubernetes   NodePort   10.96.0.1   <none>   443:31000/TCP
```

Back up and edit the static Pod manifest:
```bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml ~/3_kube-apiserver.yaml
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```

Comment out / remove the insecure flag:
```yaml
#    - --kubernetes-service-node-port=31000   # delete or set to 0
```

Wait for the apiserver to restart:
```bash
watch crictl ps
k -n kube-system get pod | grep apiserver
ps aux | grep kube-apiserver | grep node-port   # should return nothing
```

The `kubernetes` Service still shows `NodePort` — delete it so it gets recreated correctly:
```bash
k delete svc kubernetes
k get svc
# kubernetes   ClusterIP   10.96.0.1   <none>   443/TCP
```

[⬆ Back to top](#table-of-contents)

---

## Question 4 | ServiceAccount Token Expiration

**Topic:** Configure Service Accounts for Pods → Managing Service Accounts
**Solve on:** `ssh cks5608`

### Task
Update `/opt/course/4/stream-multiplex.yaml`:
- Pods get annotation `token-lifetime: "1200"`
- Use ServiceAccount `stream-multiplex`
- Disable automounting of ServiceAccount tokens
- Mount the SA token at `/var/run/secrets/custom/` with an expiration of `1200s`

Create the Deployment and ensure it runs without errors.

### Answer

Starting Deployment:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stream-multiplex
  namespace: team-coral
spec:
  replicas: 2
  selector:
    matchLabels:
      id: stream-multiplex
  template:
    metadata:
      labels:
        id: stream-multiplex
    spec:
      containers:
        - image: httpd:2-alpine
          name: httpd
          resources:
            requests:
              cpu: 20m
              memory: 20Mi
```

Final result:
```yaml
# cks5608:/opt/course/4/stream-multiplex.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: stream-multiplex
  namespace: team-coral
spec:
  replicas: 2
  selector:
    matchLabels:
      id: stream-multiplex
  template:
    metadata:
      labels:
        id: stream-multiplex
      annotations:
        token-lifetime: "1200"
    spec:
      serviceAccountName: stream-multiplex
      automountServiceAccountToken: false
      containers:
        - image: httpd:2-alpine
          name: httpd
          resources:
            requests:
              cpu: 20m
              memory: 20Mi
          volumeMounts:
            - name: token-volume
              mountPath: /var/run/secrets/custom
              readOnly: true
      volumes:
        - name: token-volume
          projected:
            sources:
              - serviceAccountToken:
                  path: token
                  expirationSeconds: 1200
```

Verify:
```bash
k apply -f /opt/course/4/stream-multiplex.yaml
k -n team-coral get deploy
k -n team-coral get pod
k -n team-coral get pod <pod-name> -oyaml   # confirm volume/mount/expiration
```

> 💡 Tip: temporarily set `automountServiceAccountToken: true`, create the Deployment, and copy the generated `projected` volume yaml from a running Pod as a starting template.

[⬆ Back to top](#table-of-contents)

---

## Question 5 | CIS Benchmark: Securing a Cluster

**Solve on:** `ssh cks7262`
**Note:** `sudo -i` may be required.

### Task
Use `kube-bench` (pre-installed) to evaluate and correct:

**Controlplane node** (`ssh cks7262`):
- `--profiling` argument of `kube-controller-manager`
- Ownership of `/var/lib/etcd`

**Worker node** (`ssh cks7262-node1` from `cks7262`):
- Permissions of `/var/lib/kubelet/config.yaml`
- `--client-ca-file` argument of the kubelet

### Answer

**Step 1 — controller-manager profiling**
```bash
ssh cks7262
sudo -i
kube-bench run --targets=master
kube-bench run --targets=master --check='1.3.2'
# [FAIL] 1.3.2 Ensure that the --profiling argument is set to false
```
Edit `/etc/kubernetes/manifests/kube-controller-manager.yaml`, add:
```yaml
    - --profiling=false
```
Recheck:
```bash
kube-bench run --targets=master | grep 1.3.2
# [PASS]
```

**Step 2 — etcd data directory ownership**
```bash
stat -c %U:%G /var/lib/etcd     # root:root
kube-bench run --targets=master | grep 1.1.12
# [FAIL] Ensure that the etcd data directory ownership is set to etcd:etcd

chown etcd:etcd /var/lib/etcd
kube-bench run --targets=master | grep 1.1.12
# [PASS]
```

**Step 3 — kubelet config permissions**
```bash
ssh cks7262-node1
kube-bench run --targets=node
stat -c %a /var/lib/kubelet/config.yaml   # 777
kube-bench run --targets=node | grep 4.1.9
# [FAIL] permissions set to 600 or more restrictive

chmod 600 /var/lib/kubelet/config.yaml
kube-bench run --targets=node | grep 4.1.9
# [PASS]
```

**Step 4 — kubelet `--client-ca-file`**
```bash
kube-bench run --targets=node | grep client-ca-file
# [PASS] 4.2.3 already set

ps -ef | grep kubelet
vim /var/lib/kubelet/config.yaml
# authentication.x509.clientCAFile: /etc/kubernetes/pki/ca.crt   → already correct
```

[⬆ Back to top](#table-of-contents)

---

## Question 6 | Immutable Root FileSystem

**Topic:** Configure a Security Context
**Solve on:** `ssh cks2546`

### Task
Deployment `immutable-deployment` in Namespace `team-purple` should run immutable: no process may write to the filesystem except `/tmp`. Don't modify the Docker image. Save updated YAML to `/opt/course/6/immutable-deployment-new.yaml` and update the running Deployment.

### Answer

Original manifest has no `securityContext` restrictions:
```yaml
containers:
- image: busybox:1
  command: ['sh', '-c', 'tail -f /dev/null']
  imagePullPolicy: IfNotPresent
  name: busybox
```

Updated manifest:
```yaml
# cks2546:/opt/course/6/immutable-deployment-new.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  namespace: team-purple
  name: immutable-deployment
  labels:
    app: immutable-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: immutable-deployment
  template:
    metadata:
      labels:
        app: immutable-deployment
    spec:
      containers:
      - image: busybox:1
        command: ['sh', '-c', 'tail -f /dev/null']
        imagePullPolicy: IfNotPresent
        name: busybox
        securityContext:
          readOnlyRootFilesystem: true
        volumeMounts:
        - mountPath: /tmp
          name: temp-vol
      volumes:
      - name: temp-vol
        emptyDir: {}
      restartPolicy: Always
```

Apply:
```bash
k delete -f /opt/course/6/immutable-deployment-new.yaml
k create -f /opt/course/6/immutable-deployment-new.yaml
```

Verify:
```bash
k -n team-purple exec <pod> -- touch /abc.txt        # Read-only file system
k -n team-purple exec <pod> -- touch /var/abc.txt    # Read-only file system
k -n team-purple exec <pod> -- touch /etc/abc.txt    # Read-only file system
k -n team-purple exec <pod> -- touch /tmp/abc.txt    # OK
k -n team-purple exec <pod> -- ls /tmp               # abc.txt
```

[⬆ Back to top](#table-of-contents)

---

## Question 7 | Pod Security Standard and Admission

**Topic:** Pod Security Standards / Pod Security Admission
**Solve on:** `ssh cks5608`

### Task
In Namespace `team-sepia`:
- Configure Pod Security Admission in mode **audit** for level **baseline**
- Configure Pod Security Admission in mode **warn** for level **restricted**
- Create the Pod from `/opt/course/7/bad-pod.yaml` and write warnings/errors into `/opt/course/7/bad-pod.log`

### Background: Pod Security Standards Levels
| Level | Description |
|---|---|
| `privileged` | Unrestricted |
| `baseline` | Minimally restrictive |
| `restricted` | Heavily restricted |

### Background: Admission Modes
| Mode | Effect |
|---|---|
| `enforce` | Violating Pod creation is **rejected** |
| `audit` | Violation is logged to the audit log, but **allowed** |
| `warn` | User-facing warning shown, but **allowed** |

### Answer

Configure via Namespace labels:
```bash
ssh cks5608

k label ns team-sepia pod-security.kubernetes.io/audit=baseline
k label ns team-sepia pod-security.kubernetes.io/warn=restricted
```

Or edit directly:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: team-sepia
    pod-security.kubernetes.io/audit: baseline
    pod-security.kubernetes.io/warn: restricted
  name: team-sepia
```

Create the Pod and capture warnings:
```bash
k -f /opt/course/7/bad-pod.yaml apply 2> /opt/course/7/bad-pod.log
# Warning: would violate PodSecurity "restricted:latest": allowPrivilegeEscalation != false, ...
```

### (Optional) Testing `enforce` mode
```bash
k label ns team-sepia pod-security.kubernetes.io/enforce=restricted
# Warning: existing pods violate the new enforce level (no effect on running Pods)

k -f /opt/course/7/bad-pod.yaml delete
k -f /opt/course/7/bad-pod.yaml apply
# Error from server (Forbidden): pods "bad-pod" is forbidden: violates PodSecurity "restricted:latest"
```
Clean up afterward:
```bash
k label ns team-sepia pod-security.kubernetes.io/enforce-
```

[⬆ Back to top](#table-of-contents)

---

## Question 8 | Docker Configuration and Usage

**Solve on:** `ssh cks4024`
**Note:** Run all Docker commands as root (`sudo -i`).

### Task
- Disable inter-container communication: add `"icc": false` to Docker config, restart the daemon.
- Create containers `container1` and `container2`:
  - image `nginx:1-alpine`
  - `restart always`
  - running in background (`-d`)
- Result: the containers must **not** be able to ping each other by IP.

### Answer

```bash
ssh cks4024
sudo -i

service docker status
ps aux | grep kubelet | grep runtime      # confirms Kubelet uses containerd, not Docker
service containerd status
find /etc/ | grep docker                  # /etc/docker/daemon.json
```

Edit config:
```json
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "storage-driver": "overlay2",
  "registry-mirrors": ["https://mirror.gcr.io","https://docker-mirror.killer.sh"],
  "icc": false,
  "mtu": 1454
}
```

Restart Docker:
```bash
service docker restart
service docker status
```

Create containers:
```bash
docker run -d --name container1 --restart always nginx:1-alpine
docker run -d --name container2 --restart always nginx:1-alpine
docker ps
```

### (Optional) Verify ICC
```bash
docker inspect container1 | grep IPAddress
docker exec container2 ping <container1-ip>     # fails after icc:false + restart
docker exec container1 ping <container2-ip>     # fails
docker exec container1 ping <container2-ip-same-container-loop>  # own IP still reachable
docker exec container1 ping 8.8.8.8              # internet still reachable
```

[⬆ Back to top](#table-of-contents)

---

## Question 9 | AppArmor Profile

**Solve on:** `ssh cks7262`

### Task
Install AppArmor profile `/opt/course/9/profile` on node `cks7262-node1`.
- Add label `security=apparmor` to the node
- Create Deployment `apparmor` in `default` Namespace:
  - 1 replica, image `nginx:1-alpine`
  - `nodeSelector: security=apparmor`
  - single container `c1` with the AppArmor profile enabled **only** for this container
- Write Pod logs to `/opt/course/9/logs` (Pod may not run properly — that's expected).

### Answer

**Step 1 — install the profile**
```bash
ssh cks7262
scp /opt/course/9/profile cks7262-node1:~/
ssh cks7262-node1
sudo apparmor_parser -q ./profile
sudo apparmor_status     # confirms "very-secure" profile in enforce mode
```

**Step 2 — label the node**
```bash
k label node cks7262-node1 security=apparmor
```

**Step 3 — create the Deployment**
```bash
k create deploy apparmor --image=nginx:1-alpine --dry-run=client -o yaml > 9_deploy.yaml
```
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  labels:
    app: apparmor
  name: apparmor
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: apparmor
  template:
    metadata:
      labels:
        app: apparmor
    spec:
      nodeSelector:
        security: apparmor
      containers:
      - image: nginx:1-alpine
        name: c1
        securityContext:
          appArmorProfile:
            type: Localhost
            localhostProfile: very-secure
```
```bash
k -f 9_deploy.yaml create
```

**Step 4 — check and capture logs**
```bash
k get pod -owide | grep apparmor
# CrashLoopBackOff — nginx needs write access the profile denies

k logs <pod-name> > /opt/course/9/logs
```

Confirm on the node:
```bash
crictl pods | grep apparmor
crictl ps -a | grep <pod-id>
crictl inspect <container-id> | grep -i profile
# "apparmor_profile": "localhost/very-secure"
```

[⬆ Back to top](#table-of-contents)

---

## Question 10 | Container Runtime Sandbox (gVisor)

**Topic:** RuntimeClass
**Solve on:** `ssh cks7262`

### Task
Node `cks7262-node1` already supports the `runsc`/gVisor runtime via containerd.
- Create RuntimeClass `gvisor` with handler `runsc`
- Create Pod `gvisor-test` in Namespace `team-purple`, image `nginx:1-alpine`, using this RuntimeClass
- Force it onto `cks7262-node1`
- Write `dmesg` output into `/opt/course/10/gvisor-test-dmesg`

### Answer

```bash
ssh cks7262
k get node -owide     # confirm containerd runtime

ssh cks7262-node1
runsc --version
cat /etc/containerd/config.toml | grep runsc
```

RuntimeClass:
```yaml
# 10_rtc.yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  name: gvisor
handler: runsc
```
```bash
k -f 10_rtc.yaml create
```

Pod:
```yaml
# 10_pod.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: gvisor-test
  name: gvisor-test
  namespace: team-purple
spec:
  nodeName: cks7262-node1
  runtimeClassName: gvisor
  containers:
  - image: nginx:1-alpine
    name: gvisor-test
  dnsPolicy: ClusterFirst
  restartPolicy: Always
```
```bash
k -f 10_pod.yaml create
k -n team-purple get pod gvisor-test
k -n team-purple exec gvisor-test -- dmesg    # "Starting gVisor..."
k -n team-purple exec gvisor-test > /opt/course/10/gvisor-test-dmesg -- dmesg
```

[⬆ Back to top](#table-of-contents)

---

## Question 11 | Secret Management

**Topic:** Secrets → Managing Secrets using kubectl
**Solve on:** `ssh cks2546`

### Task
1. Update password of Secret `db-con` in `team-khaki-us-east-ad1` to `4c!29f_Ee2e`; ensure Pods using it keep working.
2. Move Secret `user-data` from `team-khaki-us-east-ad1` to `team-khaki-us-east-ad2`.
3. Convert ConfigMap `app-data` (same Namespace) to a Secret, delete the ConfigMap, ensure dependent Pods continue working with the new Secret.

### Answer

**Step 1 — update immutable Secret**
```bash
ssh cks2546
echo -n '4c!29f_Ee2e' | base64
# NGMhMjlmX0VlMmU=
```
Direct `edit` fails because `immutable: true`:
```text
# secrets "db-con" was not valid:
# * data: Forbidden: field is immutable when `immutable` is set
```
Export, edit, delete + recreate:
```bash
k -n team-khaki-us-east-ad1 get secret db-con -oyaml > 11_db-con.yaml
vim 11_db-con.yaml     # update password: NGMhMjlmX0VlMmU=

k delete -f 11_db-con.yaml
k apply -f 11_db-con.yaml
```
Restart dependent Deployments (scale down/up, not just rollout restart):
```bash
k -n team-khaki-us-east-ad1 get deploy,pod
k -n team-khaki-us-east-ad1 get deploy app-green-sky -oyaml | grep db-con

k -n team-khaki-us-east-ad1 scale deploy app-green-sky --replicas 0
sleep 5
k -n team-khaki-us-east-ad1 scale deploy app-green-sky --replicas 2

k -n team-khaki-us-east-ad1 exec <pod> -- env | grep DB_PASSWORD
```

**Step 2 — move a Secret between Namespaces**
```bash
k -n team-khaki-us-east-ad1 get secret user-data -oyaml > 11_user-data.yaml
vim 11_user-data.yaml    # change metadata.namespace to team-khaki-us-east-ad2

k apply -f 11_user-data.yaml
k -n team-khaki-us-east-ad1 delete secret user-data
```

**Step 3 — convert ConfigMap to Secret**
```bash
k -n team-khaki-us-east-ad1 get cm app-data -oyaml > 11_app-data.yaml
vim 11_app-data.yaml
```
Change `data:` → `stringData:` (auto base64-encoded), `kind: ConfigMap` → `kind: Secret`, strip immutable metadata fields:
```yaml
apiVersion: v1
stringData:
  app.interface.properties: |
    load=lazy3
    loader=lazy3.v3.loader
    allow.renew=true
    allow.pass=c395e8d2
  interface_file_name: app.interface.properties
  token: c395e8d2-2525-4621-a99e-9bf111f4caeb
kind: Secret
metadata:
  name: app-data
  namespace: team-khaki-us-east-ad1
```
```bash
k apply -f 11_app-data.yaml
```
Update the consuming Deployment's volume:
```bash
k -n team-khaki-us-east-ad1 edit deploy app-purple-sunrise
```
```yaml
volumes:
- secret:
    defaultMode: 420
    secretName: app-data
  name: app-config
```
Verify and clean up:
```bash
k -n team-khaki-us-east-ad1 get pod
k -n team-khaki-us-east-ad1 exec <pod> -- cat /app/config/token
k -n team-khaki-us-east-ad1 delete cm app-data
```

[⬆ Back to top](#table-of-contents)

---

## Question 12 | ImagePolicyWebhook

**Topic:** Admission Control in Kubernetes
**Solve on:** `ssh cks4024`
**Note:** `sudo -i` may be required. Back up `kube-apiserver.yaml` **outside** `/etc/kubernetes/manifests`.

### Task
Team White created an ImagePolicyWebhook backend at `/opt/course/12/webhook`, with a working `webhook-backend` Service in Namespace `team-white`.

- Create AdmissionConfiguration at `/opt/course/12/webhook/admission-config.yaml`:
  ```yaml
  imagePolicy:
    kubeConfigFile: /etc/kubernetes/webhook/webhook.yaml
    allowTTL: 10
    denyTTL: 10
    retryBackoff: 20
    defaultAllow: true
  ```
- Configure apiserver to:
  - Mount `/opt/course/12/webhook` at `/etc/kubernetes/webhook`
  - Use the AdmissionConfiguration at `/etc/kubernetes/webhook/admission-config.yaml`
  - Enable the `ImagePolicyWebhook` admission plugin
- Result: images containing `danger-danger` must be denied; other images still work.

### Answer

Inspect the backend:
```bash
ssh cks4024
k -n team-white get pod,svc,secret
```
Existing `webhook.yaml` kubeconfig points to the backend Service IP with a CA cert.

**Step 1 — AdmissionConfiguration**
```bash
sudo -i
vim /opt/course/12/webhook/admission-config.yaml
```
```yaml
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: ImagePolicyWebhook
    configuration:
      imagePolicy:
        kubeConfigFile: /etc/kubernetes/webhook/webhook.yaml
        allowTTL: 10
        denyTTL: 10
        retryBackoff: 20
        defaultAllow: true
```

**Step 2 — register with the apiserver**
```bash
cp /etc/kubernetes/manifests/kube-apiserver.yaml ~/s12_kube-apiserver.yaml
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```
```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --enable-admission-plugins=NodeRestriction,ImagePolicyWebhook
    - --admission-control-config-file=/etc/kubernetes/webhook/admission-config.yaml
    ...
    volumeMounts:
    - mountPath: /etc/kubernetes/webhook
      name: webhook
      readOnly: true
    ...
  volumes:
  - hostPath:
      path: /opt/course/12/webhook
      type: DirectoryOrCreate
    name: webhook
```
```bash
watch crictl ps    # wait for apiserver to restart
```

> If it fails to restart: check `/var/log/pods/`, `journalctl -u kubelet`, or `/var/log/syslog`.
> Because `defaultAllow: true`, a broken webhook connection **silently allows all Pods** — check apiserver logs / `kubectl get events -A`.

**Result / verification**
```bash
k run test1 --image=something/danger-danger
# Error: image policy webhook backend denied one or more images

k run test2 --image=nginx:alpine
# pod/test2 created

k -n team-white logs deploy/webhook-backend
```

[⬆ Back to top](#table-of-contents)

---

## Question 13 | CiliumNetworkPolicy: Metadata Server

**Solve on:** `ssh cks8930`
**Reference:** [Cilium Documentation](https://docs.cilium.io)

### Task
A metadata service at `http://192.168.100.21:9055` must be blocked from Pod access.

In Namespace `metadata-access`, create a `CiliumNetworkPolicy` named `default` that:
- Allows egress to `0.0.0.0/0`
- Allows egress to Endpoints in the same Namespace
- Allows egress to Endpoints in `kube-system`
- Denies egress to `192.168.100.21` on port `9055`

> Existing Nginx Pods (port 80) are provided for testing — do not modify them.

### Answer

**Check connectivity first**
```bash
ssh cks8930
k -n metadata-access get pods -owide

k exec -it -n metadata-access <pod1> -- curl http://192.168.100.21:9055   # reachable

k exec -it -n metadata-access <pod1> -- nslookup kubernetes.default.svc.cluster.local
k exec -it -n metadata-access <pod1> -- curl google.com
k exec -it -n metadata-access <pod1> -- curl <pod2-ip>
```

**Create the policy**
```yaml
# 13_cnp.yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: default
  namespace: metadata-access
spec:
  endpointSelector:
    matchLabels: {}

  egress:
  # 1. Allow egress to 0.0.0.0/0
  - toCIDR:
      - 0.0.0.0/0

  # 2. Allow egress to Endpoints in the same Namespace
  - toEndpoints:
      - {}

  # 3. Allow egress to Endpoints in kube-system Namespace
  - toEndpoints:
      - matchLabels:
          io.kubernetes.pod.namespace: kube-system

  egressDeny:
  # 4. Deny egress to 192.168.100.21 on port 9055
  - toCIDR:
      - 192.168.100.21/32
    toPorts:
      - ports:
          - port: "9055"
            protocol: TCP
```
```bash
k -f 13_cnp.yaml apply
```

### How rule logic combines
- Rules under `egress:` / `egressDeny:` are combined with **OR**.
- Selectors **within a single rule** are combined with **AND**.
- `egressDeny` takes precedence over `egress` allow rules.

Read as:
```text
Deny if:  CIDR == 192.168.100.21/32 AND port == 9055/tcp
Allow if: CIDR == 0.0.0.0/0
       OR endpoint in same namespace
       OR endpoint in kube-system namespace
```

> ⚠️ **Common mistake:** combining two selectors into a single rule (e.g. `toEndpoints:` twice under one list item, or two `egressDeny` selectors merged) changes the semantics from OR to AND. Each new array entry under `egress:`/`egressDeny:` starts a **new rule**.

**Test**
```bash
k exec -it -n metadata-access <pod1> -- curl http://192.168.100.21:9055    # blocked (timeout)
k exec -it -n metadata-access <pod1> -- curl http://192.168.100.21:9099    # still allowed (other port)
k exec -it -n metadata-access <pod1> -- nslookup kubernetes.default.svc.cluster.local  # still works
k exec -it -n metadata-access <pod1> -- curl google.com                    # still works
k exec -it -n metadata-access <pod1> -- curl <pod2-ip>                     # still works
```

[⬆ Back to top](#table-of-contents)

---

## Question 14 | ETCD Secret Encryption

**Topic:** Encrypting Confidential Data at Rest
**Solve on:** `ssh cks7262`

### Task
An `EncryptionConfiguration` already exists at `/etc/kubernetes/etcd/ec.yaml`.
- Write the non-encoded `aesgcm` password into `/opt/course/14/password.txt`
- Apiserver mounts `/etc/kubernetes/etcd` → `/etc/kubernetes/etcd` inside the container
- Apiserver uses the EncryptionConfiguration from `/etc/kubernetes/etcd/ec.yaml`
- All Secrets in Namespace `team-magenta` must be stored encrypted in etcd

### Answer

Inspect the provided config:
```yaml
# /etc/kubernetes/etcd/ec.yaml
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aesgcm:
          keys:
            - name: key1
              secret: d0hhVGFTZUN1UmVQYVNzIQ==
      - identity: {}
```

**Step 1 — decode the password**
```bash
echo d0hhVGFTZUN1UmVQYVNzIQ== | base64 -d
# wHaTaSeCuRePaSs!
echo d0hhVGFTZUN1UmVQYVNzIQ== | base64 -d > /opt/course/14/password.txt
```

**Step 2+3 — configure the apiserver**
```bash
sudo -i
cp /etc/kubernetes/manifests/kube-apiserver.yaml ~/14_kube-apiserver.yaml
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```
```yaml
spec:
  containers:
  - command:
    - kube-apiserver
    - --encryption-provider-config=/etc/kubernetes/etcd/ec.yaml
    ...
    volumeMounts:
    - mountPath: /etc/kubernetes/etcd
      name: etcd
      readOnly: true
  volumes:
  - hostPath:
      path: /etc/kubernetes/etcd
      type: DirectoryOrCreate
    name: etcd
```
```bash
watch crictl ps    # wait for apiserver to restart
```

**Step 4 — re-encrypt existing Secrets**

Simply recreating Secrets causes them to be re-stored using the new EncryptionConfiguration:
```bash
k -n team-magenta get secrets -o json | kubectl replace -f -
```

### (Optional) Verify with etcdctl
```bash
ETCDCTL_API=3 etcdctl \
  --cert /etc/kubernetes/pki/apiserver-etcd-client.crt \
  --key /etc/kubernetes/pki/apiserver-etcd-client.key \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  get /registry/secrets/team-magenta/proxy-01
```
Before encryption: plaintext JSON visible.
After encryption: prefixed with `k8s:enc:aesgcm:` and shows binary/garbled data — while `kubectl get secret` still works normally.

[⬆ Back to top](#table-of-contents)

---

## Question 15 | Configure TLS on Ingress

**Topic:** Ingress
**Solve on:** `ssh cks2546`

### Task
Namespace `team-pink` has an Nginx Ingress `secure` with paths `/app` and `/api`, currently using the Ingress Controller's default fake certificate. Replace it with the key/cert provided at `/opt/course/15/tls.key` and `/opt/course/15/tls.crt`.

Test:
```bash
curl -v http://secure-ingress.test:31080/app
curl -kv https://secure-ingress.test:31443/app
```

### Answer

**Investigate current state**
```bash
ssh cks2546
k -n team-pink get ing secure
ping secure-ingress.test

curl http://secure-ingress.test:31080/app     # This is the backend APP!
curl http://secure-ingress.test:31080/api     # This is the API Server!
curl -k https://secure-ingress.test:31443/api # works with -k (self-signed default cert)
curl -kv https://secure-ingress.test:31443/api
# subject: O=Acme Co; CN=Kubernetes Ingress Controller Fake Certificate
```

**Create TLS Secret**
```bash
cd /opt/course/15
k -n team-pink create secret tls tls-secret --key tls.key --cert tls.crt
```

**Update the Ingress**
```bash
k -n team-pink get ing secure -oyaml > 15_ing_bak.yaml
k -n team-pink edit ing secure
```
```yaml
spec:
  tls:
    - hosts:
      - secure-ingress.test
      secretName: tls-secret
  rules:
  - host: secure-ingress.test
    http:
      paths:
      - backend:
          service:
            name: secure-app
            port: 80
        path: /app
        pathType: ImplementationSpecific
      - backend:
          service:
            name: secure-api
            port: 80
        path: /api
        pathType: ImplementationSpecific
```

**Verify**
```bash
k -n team-pink get ing
# secure   nginx   secure-ingress.test   192.168.100.51   80, 443

curl -k https://secure-ingress.test:31443/api
curl -kv https://secure-ingress.test:31443/api
# subject: CN=secure-ingress.test; O=secure-ingress.test
```

[⬆ Back to top](#table-of-contents)

---

## Question 16 | Runtime Security with Falco

**Reference:** [Falco Documentation](https://falco.org/docs)
**Solve on:** `ssh cks5608`
**Related tools to know:** `sysdig`, `tracee`

### Task
Add two rules to `/etc/falco/falco_rules.local.yaml`:

**Custom Rule 1** — priority `WARNING`: find all containers accessing files with prefix `/etc/kubernetes`.
```text
custom_rule_1 file={{FILEPATH}} container={{CONTAINER_ID}}
```

**Custom Rule 2** — priority `INFO`: find all processes performing `kill` syscalls.
```text
custom_rule_2 event_signal=%evt.arg.sig event_pid=%evt.arg.pid container={{CONTAINER_ID}}
```

Only create the new rules — no additional macros/lists. Run Falco for ≥30 seconds and write logs to `/opt/course/16/logs`.

### Answer

**Locate config**
```bash
ssh cks5608
sudo -i
cd /etc/falco
ls -lh
cat falco.yaml | grep -A5 rules_files
```
`rules_files` includes `falco_rules.yaml`, `falco_rules.local.yaml`, `rules.d/` — override in `falco_rules.local.yaml`.

Reference: [Falco supported fields](https://falco.org/docs/rules/supported-fields)

**Rule 1**
```yaml
# /etc/falco/falco_rules.local.yaml
- rule: Custom Rule 1
  desc: Custom Rule 1
  condition: container and evt.type in (open, openat) and fd.name startswith /etc/kubernetes
  output: custom_rule_1 file=%fd.name container=%container.id
  priority: WARNING
```
> Restricting `evt.type` to `(open, openat)` avoids the `LOAD_NO_EVTTYPE` performance warning that occurs when `fd.name` is used unrestricted.

**Rule 2**
```yaml
- rule: Custom Rule 2
  desc: Custom Rule 2
  condition: syscall.type = kill
  output: custom_rule_2 event_signal=%evt.arg.sig event_pid=%evt.arg.pid container=%container.id
  priority: INFO
```

**Test**
```bash
falco
# custom_rule_1 file=/etc/kubernetes/pki/etcd/server.key container=<id> ...
# custom_rule_2 event_signal=SIGTERM event_pid=666 container=<id> ...
```

**Capture logs for ≥30s**
```bash
falco > /opt/course/16/logs
# let it run 30+ seconds, then Ctrl+C

grep custom_rule_1 /opt/course/16/logs | wc -l
grep custom_rule_2 /opt/course/16/logs | wc -l
```

[⬆ Back to top](#table-of-contents)

---

## Question 17 | Audit Log Policy

**Topic:** Auditing
**Solve on:** `ssh cks3477`
**Note:** `sudo -i` may be required. Use `yq` for readable JSON: `cat data.json | yq -p json -o json`.

### Task
Audit Logging is enabled with a policy at `/etc/kubernetes/audit/policy.yaml`.
- Change config so only **one** backup of logs is stored.
- Alter the policy to only log:
  - **Secret** resources → level `Metadata`
  - `system:nodes` userGroups → level `RequestResponse`
- Empty the log file after changes: `echo > /etc/kubernetes/audit/logs/audit.log`

### Answer

**Step 1 — apiserver flags**
```bash
ssh cks3477
sudo -i
cp /etc/kubernetes/manifests/kube-apiserver.yaml ~/17_kube-apiserver.yaml   # backup OUTSIDE manifests dir
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```
```yaml
    - --audit-policy-file=/etc/kubernetes/audit/policy.yaml
    - --audit-log-path=/etc/kubernetes/audit/logs/audit.log
    - --audit-log-maxsize=5
    - --audit-log-maxbackup=1
```
```bash
watch crictl ps
```

**Step 2 — update the policy**

Existing policy logs everything at `Metadata`:
```yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
- level: Metadata
```

New policy:
```yaml
# /etc/kubernetes/audit/policy.yaml
apiVersion: audit.k8s.io/v1
kind: Policy
rules:

# log Secret resources, level Metadata
- level: Metadata
  resources:
  - group: ""
    resources: ["secrets"]

# log system:nodes activity, level RequestResponse
- level: RequestResponse
  userGroups: ["system:nodes"]

# don't log anything else
- level: None
```

**Apply and reset logs**
```bash
cd /etc/kubernetes/manifests/
mv kube-apiserver.yaml ..
watch crictl ps           # wait for apiserver to go away

echo > /etc/kubernetes/audit/logs/audit.log

mv ../kube-apiserver.yaml .
watch crictl ps           # wait for apiserver to come back
```

**Verify**
```bash
cat /etc/kubernetes/audit/logs/audit.log | tail | yq -p json -o json

# validation one-liners:
cat audit.log | grep '"resource":"secrets"' | wc -l
cat audit.log | grep '"resource":"secrets"' | grep -v '"level":"Metadata"' | wc -l   # should be 0
cat audit.log | grep -v '"level":"RequestResponse"' | wc -l
cat audit.log | grep '"level":"RequestResponse"' | grep -v "system:nodes" | wc -l    # should be 0
```

[⬆ Back to top](#table-of-contents)

---

# Preview Questions (Additional)

> These are bonus questions beyond the 17 core questions above. The full CKS Simulator (Version A & B) contains 17+ questions each; these previews are extra practice available in the interactive environment.

## Preview Question 1 | Using RBAC Authorization

**Solve on:** `ssh cks3477`

### Task
For user `gianna`:
1. Existing cluster-level RBAC should ensure `gianna` can **never** read Secret contents cluster-wide. Confirm or fix this.
2. Create RBAC to let `gianna` create Pods and Deployments in Namespaces `security`, `restricted`, and `internal` — she'll likely get the same permissions in future Namespaces too.

Test with:
```bash
k config use-context gianna@infra-prod
k config use-context kubernetes-admin@kubernetes   # switch back
```

### Answer

**Part 1 — audit existing RBAC**
```bash
ssh cks3477
k get clusterrolebinding -oyaml | grep gianna -A10 -B20
k edit clusterrolebinding gianna     # bound to ClusterRole "gianna"
k edit clusterrole gianna
```
```yaml
rules:
- apiGroups: [""]
  resources: [secrets, configmaps, pods, namespaces]
  verbs: [list]
```
`list` alone looks safe:
```bash
k auth can-i list secrets --as gianna   # yes
k auth can-i get secrets --as gianna    # no
```
But `list -oyaml` **does** leak Secret data:
```bash
k config use-context gianna@infra-prod
k -n security get secrets -oyaml | grep password   # data IS visible!
```
Fix: remove `secrets` from the list resource:
```bash
k config use-context kubernetes-admin@kubernetes
k edit clusterrole gianna
```
```yaml
rules:
- apiGroups: [""]
  resources:
  #- secrets     # REMOVE
  - configmaps
  - pods
  - namespaces
  verbs: [list]
```
Verify:
```bash
k auth can-i list secrets --as gianna    # no
```

**Part 2 — grant Pod/Deployment create access**

### RBAC combination reference
| Combination | Scope of permissions | Scope of application | Valid? |
|---|---|---|---|
| Role + RoleBinding | Single Namespace | Single Namespace | ✅ |
| ClusterRole + ClusterRoleBinding | Cluster-wide | Cluster-wide | ✅ |
| ClusterRole + RoleBinding | Cluster-wide | Single Namespace | ✅ |
| Role + ClusterRoleBinding | Single Namespace | Cluster-wide | ❌ Not possible |

Since permissions will likely be reused for future Namespaces, use **one ClusterRole + multiple RoleBindings**:
```bash
k create clusterrole gianna-additional --verb=create --resource=pods --resource=deployments

k -n security create rolebinding gianna-additional --clusterrole=gianna-additional --user=gianna
k -n restricted create rolebinding gianna-additional --clusterrole=gianna-additional --user=gianna
k -n internal create rolebinding gianna-additional --clusterrole=gianna-additional --user=gianna
```

**Verify**
```bash
k -n default auth can-i create pods --as gianna       # no
k -n security auth can-i create pods --as gianna      # yes
k -n restricted auth can-i create pods --as gianna     # yes
k -n internal auth can-i create pods --as gianna       # yes
```

[⬆ Back to top](#table-of-contents)

---

## Preview Question 2 | Auditing: Managing Secrets using kubectl

**Solve on:** `ssh cks3477`

### Task
Namespace `security` has 5 `Opaque` Secrets considered highly confidential. An incident investigation revealed ServiceAccount `p.auster` had excessive access for a period and **should never** have accessed any Secrets there. Find out — using Audit Logs at `/opt/course/p2/audit.log` — which Secrets were accessed, and change the passwords of those (and only those).

> Tip: `cat data.json | jq` for readable JSON.

### Answer

```bash
ssh cks3477
k -n security get secret | grep Opaque
# kubeadmin-token, mysql-admin, postgres001, postgres002, vault-token

cd /opt/course/p2
cat audit.log | wc -l                              # 4448 lines total
cat audit.log | grep "p.auster" | wc -l             # 28
cat audit.log | grep "p.auster" | grep Secret | wc -l         # 2
cat audit.log | grep "p.auster" | grep Secret | grep list | wc -l   # 0 (no list actions — good)
cat audit.log | grep "p.auster" | grep Secret | grep get | wc -l    # 2

cat audit.log | grep "p.auster" | grep Secret | grep get | jq
```
Results show `get` requests to Secrets `vault-token` and `mysql-admin`.

**Rotate the affected passwords**
```bash
echo -n new-vault-pass | base64
k -n security edit secret vault-token

echo -n new-mysql-pass | base64
k -n security edit secret mysql-admin
```

> ⚠️ Note: Audit Logs at `RequestResponse` level store the **full Secret content**, including plaintext passwords (`cat audit.log | grep "p.auster" | grep Secret | grep password`). Consider limiting Secret auditing to `Metadata` level via an Audit Policy to avoid leaking sensitive data into logs.

[⬆ Back to top](#table-of-contents)

---

## Preview Question 3 | Unknown Miner Process Investigation

**Solve on:** `ssh cks8930`

### Task
A security scan found an unknown miner process listening on port `6666` on one of the nodes. Kill the process and delete the binary.

### Answer

```bash
ssh cks8930
k get node
sudo -i

ss -plnt | grep 6666        # nothing on the controlplane

ssh cks8930-node1
ss -plnt | grep 6666
# LISTEN ... *:6666 ... users:(("system-atm",pid=9321,fd=3))
```
Alternative:
```bash
lsof -i :6666
```
Find the full binary path:
```bash
ls -lh /proc/9321/exe
# -> /usr/bin/system-atm
```
Kill and remove:
```bash
kill -9 9321
rm /usr/bin/system-atm
ss -plnt | grep 6666    # confirm gone
```

> `ss` (from `iproute2`) is the modern replacement for `netstat` — better performance and IPv6 support.

[⬆ Back to top](#table-of-contents)

---

# CKS Tips — Kubernetes 1.35

## Knowledge

### Pre-Knowledge
- Ensure your CKA knowledge is current and you're proficient with `kubectl`.
- Study scenarios: [killercoda.com/killer-shell-cka](https://killercoda.com/killer-shell-cka)

### Core Knowledge
- Study all curriculum topics until comfortable.
- Study scenarios: [killercoda.com/killer-shell-cks](https://killercoda.com/killer-shell-cks)
- Read the [Cloud Native Security Whitepaper](https://github.com/cncf/tag-security)
- Reference repo of tips/resources by Walid Shaari

### Approach
- Do both test sessions of the CKS Simulator; understand solutions and explore alternate approaches.
- Be fast — "breathe kubectl."

### Content to Master
- Modifying the `kube-apiserver` in a kubeadm setup
- Working with AdmissionControllers
- Creating and using the `ImagePolicyWebhook`
- Open-source tools: **Falco**, **Sysdig**, **Tracee**, **Trivy**

[⬆ Back to top](#table-of-contents)

---

# CKS Exam Info

| Resource | Link |
|---|---|
| Curriculum | https://github.com/cncf/curriculum |
| Handbook | https://docs.linuxfoundation.org/tc-docs/certification/lf-handbook2 |
| Important Instructions | https://docs.linuxfoundation.org/tc-docs/certification/important-instructions-cks |
| FAQ | https://docs.linuxfoundation.org/tc-docs/certification/faq-cka-ckad-cks |

[⬆ Back to top](#table-of-contents)

---

# Kubernetes Documentation (Allowed Resources)

During the exam, only these documentation sources are permitted (verify current list before the exam):

- https://kubernetes.io/docs
- https://kubernetes.io/blog
- https://falco.org/docs
- https://kubernetes-sigs.github.io/bom/cli-reference
- https://etcd.io/docs
- https://kubernetes.github.io/ingress-nginx/user-guide/nginx-configuration
- https://docs.cilium.io/en/stable
- https://istio.io/latest/docs

[⬆ Back to top](#table-of-contents)

---

# CKS Clusters

In the real exam you get one cluster per question (each solved independently — breaking one cluster won't affect others). Each cluster has one controlplane node and possibly additional worker nodes.

[⬆ Back to top](#table-of-contents)

---

# The Exam UI / Remote Desktop

The exam (and simulator) provides a Remote Desktop (XFCE) on Ubuntu/Debian.

- Reference: [ExamUI: Performance Based Exams](https://docs.linuxfoundation.org/tc-docs/certification/certification-resources-all-exams)
- **Lagging:** use a good internet connection — webcam + screen are streaming continuously.
- **Pre-installed:** `kubectl` with `k` alias + Bash autocompletion, `yq`, `curl`/`wget`, `man` pages. You may install additional tools (`tmux`, `jq`, etc).
- **Copy & Paste:**
  - Always works: right-click context menu
  - Terminal: `Ctrl+Shift+C` / `Ctrl+Shift+V`
  - Other apps (e.g. Firefox): `Ctrl+C` / `Ctrl+V`
- **Score:** 15–20 questions, automatically graded per the handbook. Disagreements go through Linux Foundation Support.
- **Notepad & Flagging:** flag questions to revisit (self-marker only, doesn't affect scoring); a browser notepad is available for notes. Mousepad or Vim inside the Remote Desktop are alternatives.
- **VSCodium:** available for editing + terminal use; extensions cannot be installed.
- **Servers:** each question is solved on a specific instance reached via the provided `ssh` command.

[⬆ Back to top](#table-of-contents)

---

# PSI Bridge

Changes starting with PSI Bridge:

- Exam taken via **PSI Secure Browser** (latest Edge, Safari, Chrome, or Firefox)
- **Multiple monitors no longer permitted**
- **Personal bookmarks no longer permitted**
- New ExamUI features:
  - Remote desktop pre-configured with required tools
  - Timer showing actual minutes remaining, with alerts at 30/15/5 minutes
  - Content panel remains on the left-hand side

More info: [PSI Bridge announcement](https://docs.linuxfoundation.org/tc-docs/certification)

[⬆ Back to top](#table-of-contents)

---

# Terminal Handling

## Bash Aliases
Each question is solved on a different SSH instance — **don't rely on custom bash aliases**, they won't carry over.

## Be Fast
- Use `history` / `Ctrl+R` to reuse commands.
- Background long-running commands with `Ctrl+Z`, resume with `fg`.
- Fast pod deletion:
  ```bash
  k delete pod x --grace-period 0 --force
  ```

## Vim

### Settings
If paste/indentation misbehaves, configure `~/.vimrc` or set manually:
```vim
set tabstop=2
set expandtab
set shiftwidth=2
```
> `~/.vimrc` changes do **not** carry over to other SSH instances.

### Line Numbers
Toggle with `Esc` then `:set number` / `:set nonumber`. Jump to a line: `Esc :22` + Enter.

### Copy & Paste in Vim
| Action | Keys |
|---|---|
| Mark lines | `Esc` + `Shift+V` (then arrow keys) |
| Copy marked lines | `y` |
| Cut marked lines | `d` |
| Paste | `p` or `P` |

### Indent Multiple Lines
```vim
:set shiftwidth=2
```
Mark lines with `Shift+V` + arrows, then `>` or `<` to indent/outdent; repeat with `.`.

[⬆ Back to top](#table-of-contents)
