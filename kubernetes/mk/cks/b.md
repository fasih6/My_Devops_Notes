# CKS Simulator B — Kubernetes 1.35
### Source: [killer.sh](https://killer.sh)

> Each question needs to be solved on a specific instance other than your main `candidate@terminal`. Connect via the provided `ssh` command. To connect to a different instance, always return first to your main terminal with `exit`.
>
> In the real exam, each question is solved on a **different** instance, whereas in the simulator multiple questions may share the same instance.
>
> Use `sudo -i` to become root on any node when necessary.

---

## Table of Contents

### Exam Questions
1. [Question 1 — SBOM (Software Bill of Materials)](#question-1--sbom-software-bill-of-materials)
2. [Question 2 — Runtime Security with Falco](#question-2--runtime-security-with-falco)
3. [Question 3 — Manual Static Security Analysis](#question-3--manual-static-security-analysis)
4. [Question 4 — Pod Security Standard](#question-4--pod-security-standard)
5. [Question 5 — Network Policy](#question-5--network-policy)
6. [Question 6 — Verify Platform Binaries](#question-6--verify-platform-binaries)
7. [Question 7 — KubeletConfiguration](#question-7--kubeletconfiguration)
8. [Question 8 — CiliumNetworkPolicy (Layer 3/4, Mutual Auth)](#question-8--ciliumnetworkpolicy-layer-34-mutual-auth)
9. [Question 9 — Certificates and Signing Requests](#question-9--certificates-and-signing-requests)
10. [Question 10 — Istio Security and mTLS](#question-10--istio-security-and-mtls)
11. [Question 11 — Secrets in ETCD](#question-11--secrets-in-etcd)
12. [Question 12 — Hack Secrets (RBAC Privilege Escape)](#question-12--hack-secrets-rbac-privilege-escape)
13. [Question 13 — RBAC Operator Troubleshooting](#question-13--rbac-operator-troubleshooting)
14. [Question 14 — Syscall Activity](#question-14--syscall-activity)
15. [Question 15 — Apiserver TLS Settings](#question-15--apiserver-tls-settings)
16. [Question 16 — Docker Image Attack Surface](#question-16--docker-image-attack-surface)
17. [Question 17 — Update Kubernetes (kubeadm)](#question-17--update-kubernetes-kubeadm)

### Reference
18. [CKS Tips — Kubernetes 1.35](#cks-tips--kubernetes-135)
19. [CKS Exam Info](#cks-exam-info)
20. [Kubernetes Documentation (Allowed Resources)](#kubernetes-documentation-allowed-resources)
21. [CKS Clusters](#cks-clusters)
22. [The Exam UI / Remote Desktop](#the-exam-ui--remote-desktop)
23. [PSI Bridge](#psi-bridge)
24. [Terminal Handling](#terminal-handling)

---

## Question 1 | SBOM (Software Bill of Materials)

**Reference:** [bom CLI Reference](https://kubernetes-sigs.github.io/bom/cli-reference)
**Solve on:** `ssh cks9640`

### Task
1. Using **bom**: generate a SPDX-JSON SBOM of `registry.k8s.io/kube-apiserver:v1.31.0` → store at `/opt/course/1/sbom1.json`
2. Using **trivy**: generate a CycloneDX SBOM of `registry.k8s.io/kube-controller-manager:v1.31.0` → store at `/opt/course/1/sbom2.json`
3. Using **trivy**: scan the existing SPDX-JSON SBOM at `/opt/course/1/sbom_check.json` for known vulnerabilities → save result in JSON at `/opt/course/1/sbom_check_result.json`

> 💡 SBOMs are like an ingredients list, but for software — a structured way to represent components/dependencies so security risks are easier to track.

### Answer

**Step 1 — generate SBOM with `bom`**
```bash
ssh cks9640
bom
# bom generate → Create SPDX SBOMs

bom generate --image registry.k8s.io/kube-apiserver:v1.31.0 --format json --output /opt/course/1/sbom1.json
```
```json
{
  "SPDXID": "SPDXRef-DOCUMENT",
  "name": "SBOM-SPDX-...",
  "spdxVersion": "SPDX-2.3",
  "creationInfo": { "creators": ["Tool: bom-v0.6.0"] },
  "dataLicense": "CC0-1.0",
  ...
}
```
> `bom document` can also visualize/query existing SBOMs.

**Step 2 — generate CycloneDX SBOM with `trivy`**
```bash
trivy image --help | grep format
# -f, --format string   (table,json,template,sarif,cyclonedx,spdx,spdx-json,github,cosign-vuln)

trivy image --format cyclonedx --output /opt/course/1/sbom2.json registry.k8s.io/kube-controller-manager:v1.31.0
```
> Note: `--format cyclonedx` disables security scanning by default — pass `--scanners vuln` explicitly if vulnerabilities need to be included.

**Step 3 — scan an existing SBOM with `trivy`**
```bash
trivy sbom /opt/course/1/sbom_check.json
# Detected SBOM format: spdx-json

trivy sbom --format json --output /opt/course/1/sbom_check_result.json /opt/course/1/sbom_check.json
```

[⬆ Back to top](#table-of-contents)

---

## Question 2 | Runtime Security with Falco

**Reference:** [Falco Documentation](https://falco.org/docs)
**Solve on:** `ssh cks5632` → then `ssh cks5632-node1`
**Note:** `sudo -i` may be required. Related tools: `sysdig`, `tracee`.

### Task
Falco runs on worker node `cks5632-node1` with custom rules at `/etc/falco/rules.d/falco_custom.yaml`.

1. Find a Pod (image `httpd`) modifying `/etc/passwd` → scale its Deployment to `0`.
2. Find a Pod (image `nginx`) triggering rule `Package management process launched`.
3. Change that rule's output format to only:
   ```text
   time-with-nanoseconds,container-id,container-name,user-name
   ```
4. Collect logs for ≥20 seconds → save to `/opt/course/2/falco.log`.
5. Scale that Deployment to `0`.

### Answer

**Investigate Falco config**
```bash
ssh cks5632
ssh cks5632-node1
sudo -i
cd /etc/falco
ls -lh
cat rules.d/falco_custom.yaml
```
`falco.yaml` → `rules_files` includes `falco_rules.yaml`, `falco_rules.local.yaml`, `rules.d/`.

**Step 1 — find the `httpd` offender**
```bash
falco -U | grep httpd
```
```text
Warning Sensitive file opened for reading by non-trusted program (file=/etc/passwd ...
process=sed proc_exepath=/bin/busybox parent=sh command=sed -i $d /etc/passwd
container_id=f86cd629e71c container_name=httpd)
```
```bash
crictl ps -id f86cd629e71c        # find POD ID
crictl pods -id <pod-id>          # find NAMESPACE + Pod NAME

k get pod -A | grep rating-service
k -n team-violet scale deploy rating-service --replicas 0
```

> The default `sensitive_file_names` list (in `falco_rules.local.yaml`) drives this rule — extend it to catch additional paths.

**Step 2 — find and fix `Package management process launched`**
```bash
falco -U | grep 'Package management process launched'
```
```text
Error Package management process launched (user=root ... command=apk container_id=65338e61dc48 container_name=nginx image=docker.io/library/nginx:1.19.2-alpine)
```
```bash
crictl ps -id 65338e61dc48       # find POD ID
crictl pods -id <pod-id>         # find NAMESPACE + Pod NAME (webapi, team-clover)
```
Don't scale down yet — the rule must be edited first.

**Edit the rule**
```bash
vim rules.d/falco_custom.yaml
```
```yaml
- rule: Launch Package Management Process in Container
  desc: Package management process ran inside container
  condition: >
    spawned_process
    and container
    and user.name != "_apt"
    and package_mgmt_procs
    and not package_mgmt_ancestor_procs
  output: >
    Package management process launched %evt.time,%container.id,%container.name,%user.name
  priority: ERROR
  tags: [process, mitre_persistence]
```
> Reference: [Falco supported fields](https://falco.org/docs/rules/supported-fields). Also try `falco --list | grep user`.

**Collect logs ≥20s**
```bash
falco -U | grep 'Package management process launched'
```
```text
11:32:21.364062550: Error Package management process launched 11:32:21.364062550,2e01e03f9d92,nginx,root ...
```
Save at least 20 seconds worth of matching lines to `/opt/course/2/falco.log` (exit back to `cks5632` main terminal first, since the file lives there):
```bash
exit    # back from sudo
exit    # back from cks5632-node1
vim /opt/course/2/falco.log
```

**Scale down the Deployment**
```bash
k get pod -A | grep webapi
k -n team-clover scale deploy webapi --replicas 0
```

[⬆ Back to top](#table-of-contents)

---

## Question 3 | Manual Static Security Analysis

**Reference:** [Secrets Good Practices](https://kubernetes.io/docs/concepts/security/secrets-good-practices) / Security Checklist
**Solve on:** `ssh cks9640`

### Task
Review Dockerfiles and YAML manifests at `/opt/course/3/files` for **unwanted credential exposure**. (Running as root is out of scope.) Write filenames with issues to `/opt/course/3/security-issues`.

> Assume referenced files/folders/secrets/mounts exist; ignore syntax/logic errors.

### Answer

```bash
ssh cks9640
ls -la /opt/course/3/files
```
3 Dockerfiles + 7 K8s manifests to review.

**Issue 1 — `Dockerfile-mysql`: secret persists in image layers**
```dockerfile
FROM ubuntu
...
COPY secret-token .                                # LAYER X
RUN /etc/register.sh ./secret-token                # LAYER Y
RUN rm ./secret-token # delete secret token again  # LAYER Z
```
Every `COPY`/`RUN`/`ADD` creates a persisted layer — deleting the file in a later layer does **not** remove it from the image history.
```bash
echo Dockerfile-mysql >> /opt/course/3/security-issues
```

**Issue 2 — `deployment-redis.yaml`: credentials echoed into logs**
```yaml
command: ["/bin/sh"]
args:
- "-c"
- "echo $SECRET_USERNAME && echo $SECRET_PASSWORD && docker-entrypoint.sh" # NOT GOOD
env:
- name: SECRET_USERNAME
  valueFrom: { secretKeyRef: { name: mysecret, key: username } }
- name: SECRET_PASSWORD
  valueFrom: { secretKeyRef: { name: mysecret, key: password } }
```
```bash
echo deployment-redis.yaml >> /opt/course/3/security-issues
```

**Issue 3 — `statefulset-nginx.yaml`: plaintext password in env**
```yaml
env:
- name: Username
  value: Administrator
- name: Password
  value: MyDiReCtP@sSw0rd    # NOT GOOD
```
```bash
echo statefulset-nginx.yaml >> /opt/course/3/security-issues
```

**Result**
```bash
cat /opt/course/3/security-issues
```
```text
Dockerfile-mysql
deployment-redis.yaml
statefulset-nginx.yaml
```

[⬆ Back to top](#table-of-contents)

---

## Question 4 | Pod Security Standard

**Topic:** Pod Security Standards / Pod Security Admission
**Solve on:** `ssh cks6032`

### Task
Deployment `container-host-hacker` in `team-rose` mounts `/run/containerd` as a `hostPath` volume — exposing other containers' data on the node.
- Enforce the **baseline** Pod Security Standard on Namespace `team-rose`.
- Delete the offending Pod.
- Check ReplicaSet events, write the reason the Pod isn't recreated into `/opt/course/4/logs`.

### Answer

```bash
ssh cks6032
k label ns team-rose pod-security.kubernetes.io/enforce=baseline
```
Or via edit:
```yaml
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: team-rose
    pod-security.kubernetes.io/enforce: baseline
  name: team-rose
```

**Delete the Pod and observe**
```bash
k -n team-rose get pod
k -n team-rose delete pod container-host-hacker-dbf989777-wm8fc --force --grace-period 0
k -n team-rose get pod
# No resources found — ReplicaSet fails to recreate it
```

**Check why**
```bash
k -n team-rose get rs
k -n team-rose describe rs container-host-hacker-dbf989777
```
```text
Warning  FailedCreate  ... replicaset-controller  (combined from similar events): Error creating: pods "..." is forbidden: violates PodSecurity "baseline:latest": hostPath volumes (volume "containerdata")
```
```bash
vim /opt/course/4/logs
```
```text
# cks6032:/opt/course/4/logs
Warning  FailedCreate  2m2s (x9 over 2m40s)  replicaset-controller  (combined from similar events): Error creating: pods "container-host-hacker-dbf989777-kjfpn" is forbidden: violates PodSecurity "baseline:latest": hostPath volumes (volume "containerdata")
```

> Pod Security Standards give a solid baseline, but for finer-grained control beyond `baseline`/`restricted`, look at 3rd-party solutions like OPA or Kyverno.

[⬆ Back to top](#table-of-contents)

---

## Question 5 | Network Policy

**Topic:** Network Policies → Declare Network Policy
**Solve on:** `ssh cks4933`

### Task
Namespace `team-ivy-private` has Deployment `api-private` protected by an existing NetworkPolicy — **do not change anything there**.

In Namespace `team-ivy-gateway`, satisfy that policy so:
- `gateway-v1` can access `api-private` only on **port 3000**
- `gateway-v2` can access `api-private` only on **ports 4000 and 5000**

Then create new NetworkPolicy/ies restricting `gateway-v1`/`gateway-v2` to **outgoing** connections into `team-ivy-private` only (no ingress control needed).

### Answer

**Part 1 — satisfy the existing policy via labels**

Check connectivity and inspect the policy:
```bash
ssh cks4933
k -n team-ivy-private get pod -owide
k -n team-ivy-gateway get pod

k -n team-ivy-gateway exec <gateway-v1-pod> -- curl -s <api-private-ip>:3000   # fails
k -n team-ivy-private get networkpolicy api-private-access -oyaml
```
Policy (read-only, for reference):
```yaml
spec:
  ingress:
  - from: [{namespaceSelector: {}, podSelector: {matchLabels: {api-access-cache: "true"}}}]
    ports: [{port: 2000, protocol: TCP}]
  - from: [{namespaceSelector: {}, podSelector: {matchLabels: {api-access-operation: "true"}}}]
    ports: [{port: 3000, protocol: TCP}]
  - from: [{namespaceSelector: {}, podSelector: {matchLabels: {api-access-status: "true"}}}]
    ports: [{port: 4000, protocol: TCP}]
  - from: [{namespaceSelector: {}, podSelector: {matchLabels: {api-access-report: "true"}}}]
    ports: [{port: 5000, protocol: TCP}]
  - from: [{namespaceSelector: {}, podSelector: {matchLabels: {api-access-reset: "true"}}}]
    ports: [{port: 6000, protocol: TCP}]
  podSelector: {matchLabels: {id: api-private}}
  policyTypes: [Ingress]
```
> Read as OR across rules: each destination port requires the matching source-Pod label.

Since labels must be **permanent** (not just on running Pods), edit the Deployments:
```bash
k -n team-ivy-gateway edit deploy gateway-v1
```
```yaml
template:
  metadata:
    labels:
      id: gateway-v1
      api-access-operation: "true"   # ADD → allows port 3000
```
```bash
k -n team-ivy-gateway edit deploy gateway-v2
```
```yaml
template:
  metadata:
    labels:
      id: gateway-v2
      api-access-status: "true"   # ADD → allows port 4000
      api-access-report: "true"   # ADD → allows port 5000
```

**Verify**
```bash
k -n team-ivy-gateway get pod
k -n team-ivy-gateway exec <gateway-v1-pod> -- curl -s <api-private-ip>:3000    # works
k -n team-ivy-gateway exec <gateway-v2-pod> -- curl -s <api-private-ip>:4000    # works
k -n team-ivy-gateway exec <gateway-v2-pod> -- curl -s <api-private-ip>:5000    # works
k -n team-ivy-gateway exec <gateway-v1-pod> -- curl -s <api-private-ip>:4000    # still blocked
```

**Part 2 — restrict gateway egress to only `team-ivy-private`**
```bash
k get ns team-ivy-private --show-labels
```
```yaml
# 5_np.yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gateway-v1
  namespace: team-ivy-gateway
spec:
  podSelector:
    matchLabels:
      id: gateway-v1
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: team-ivy-private
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: gateway-v2
  namespace: team-ivy-gateway
spec:
  podSelector:
    matchLabels:
      id: gateway-v2
  policyTypes:
  - Egress
  egress:
  - to:
    - namespaceSelector:
        matchLabels:
          kubernetes.io/metadata.name: team-ivy-private
```
```bash
k -f 5_np.yaml apply
```
> Alternative: one policy using `matchExpressions` with `In: [gateway-v1, gateway-v2]`, or a shared Pod label (`app: gateway`) selected by a single policy.

**Verify final state**
```bash
k -n team-ivy-gateway exec <gateway-v1-pod> -- curl -s <api-private-ip>:3000   # works
k -n team-ivy-gateway exec <gateway-v1-pod> -- curl -s google.com             # blocked
k -n team-ivy-gateway exec <gateway-v2-pod> -- curl -s <api-private-ip>:4000   # works
k -n team-ivy-gateway exec <gateway-v2-pod> -- curl -s google.com             # blocked
```

[⬆ Back to top](#table-of-contents)

---

## Question 6 | Verify Platform Binaries

**Solve on:** `ssh cks1428`

### Task
Four Kubernetes server binaries are at `/opt/course/6/binaries`. Given verified `sha512` hashes for `kube-apiserver`, `kube-controller-manager`, `kube-proxy`, `kubelet` — delete any binaries whose hash doesn't match.

### Answer

```bash
ssh cks1428
cd /opt/course/6/binaries
ls

sha512sum kube-apiserver             # matches ✅
sha512sum kube-controller-manager    # matches ✅ (verify carefully!)
sha512sum kube-proxy                 # matches ✅
sha512sum kubelet                    # MISMATCH ❌
```

> ⚠️ **Careful comparison matters.** A hash can look correct at a glance but differ by a single character (e.g., `b0` vs `bo`). Verify programmatically instead of eyeballing:
```bash
sha512sum kube-controller-manager > compare1
vim compare1   # remove filename, keep hash only

echo <provided-hash> > compare2
diff compare1 compare2
```
```text
1c1
< 60100cc725e91fe1a949e1b2d0474237844b5862556e25c2c655a33b0a8225855ec5ee22fa4927e6c46a60d43a7c4403a27268f96fbb726307d1608b44f38a60
---
> 60100cc725e91fe1a949e1b2d0474237844b5862556e25c2c655a33boa8225855ec5ee22fa4927e6c46a60d43a7c4403a27268f96fbb726307d1608b44f38a60
```

**Remove the invalid binaries**
```bash
rm kubelet kube-controller-manager
```

[⬆ Back to top](#table-of-contents)

---

## Question 7 | KubeletConfiguration

**Topic:** Configuring kubelets using kubeadm
**Solve on:** `ssh cks9640` → `ssh cks9640-node1`
**Note:** `sudo -i` may be required.

### Task
Update the cluster's `KubeletConfiguration` **the kubeadm way** so new nodes automatically receive it too:
- `containerLogMaxSize: 5Mi`
- `containerLogMaxFiles: 3`
- Apply on `cks9640` (controlplane)
- Apply on `cks9640-node1` (worker)

### Answer

**Step 1 — update the cluster-wide `kubelet-config` ConfigMap**
```bash
ssh cks9640
k -n kube-system edit cm kubelet-config
```
```yaml
data:
  kubelet: |
    apiVersion: kubelet.config.k8s.io/v1beta1
    kind: KubeletConfiguration
    ...
    containerLogMaxSize: 5Mi
    containerLogMaxFiles: 3
```
> New nodes added to the cluster (or upgraded via `kubeadm upgrade`) will pick up this KubeletConfiguration automatically.

**Step 2 — apply to the controlplane Kubelet**
```bash
sudo -i
ps aux | grep kubelet
# --config=/var/lib/kubelet/config.yaml

grep containerLog /var/lib/kubelet/config.yaml   # currently empty

kubeadm upgrade node phase kubelet-config --dry-run
kubeadm upgrade node phase kubelet-config

grep containerLog /var/lib/kubelet/config.yaml
# containerLogMaxFiles: 3
# containerLogMaxSize: 5Mi

service kubelet restart
```

**(Optional) verify via API**
```bash
kubectl get --raw "/api/v1/nodes/cks9640/proxy/configz" | yq -p json -o json
```

**Step 3 — apply to the worker node**
```bash
ssh cks9640-node1
grep containerLog /var/lib/kubelet/config.yaml   # still empty

kubeadm upgrade node phase kubelet-config
grep containerLog /var/lib/kubelet/config.yaml
# containerLogMaxFiles: 3
# containerLogMaxSize: 5Mi

service kubelet restart
```
```bash
kubectl get --raw "/api/v1/nodes/cks9640-node1/proxy/configz" | yq -p json -o json
```

[⬆ Back to top](#table-of-contents)

---

## Question 8 | CiliumNetworkPolicy (Layer 3/4, Mutual Auth)

**Reference:** [Cilium Documentation](https://docs.cilium.io)
**Solve on:** `ssh cks6032`

### Task
Namespace `team-iris` has a Default-Allow `CiliumNetworkPolicy` named `default-allow` (allows all intra-Namespace traffic + DNS) — **do not alter it**. Create 3 new policies:

1. **p1** (Layer 3): deny egress from `type=messenger` Pods to Pods behind Service `database`
2. **p2** (Layer 4): deny outgoing ICMP from Deployment `transmitter` to Pods behind Service `database`
3. **p3** (Layer 3): enable **Mutual Authentication** for egress from `type=database` Pods to `type=messenger` Pods

> All Pods run plain Nginx (port 80) for simple connectivity tests: `k -n team-iris exec POD -- curl database`

### Answer

**Overview**
```bash
ssh cks6032
k -n team-iris get pod --show-labels -owide
k -n team-iris get svc
```
Existing `default-allow` policy:
```yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: default-allow
  namespace: team-iris
spec:
  endpointSelector: {matchLabels: {}}
  egress:
  - toEndpoints: [{}]
  - toEndpoints:
    - matchLabels: {io.kubernetes.pod.namespace: kube-system, k8s-app: kube-dns}
    toPorts:
    - ports: [{port: "53", protocol: UDP}]
      rules: {dns: [{matchPattern: "*"}]}
  ingress:
  - fromEndpoints: [{}]
```
> CiliumNetworkPolicies follow default-deny semantics: once a direction has a rule, only what's explicitly allowed passes. `egressDeny`/`ingressDeny` take precedence over allow rules.

**Policy p1 — deny messenger → database (Layer 3)**
```bash
k -n team-iris exec <messenger-pod> -- curl -m 2 --head database    # works before policy
```
```yaml
# 8_p1.yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: p1
  namespace: team-iris
spec:
  endpointSelector:
    matchLabels:
      type: messenger
  egressDeny:
  - toEndpoints:
    - matchLabels:
        type: database
```
```bash
k -f 8_p1.yaml apply
```
**Verify**
```bash
k -n team-iris exec <messenger-pod> -- curl -m 2 --head database         # timeout
k -n team-iris exec <messenger-pod> -- curl -m 2 --head <database-ip>    # timeout
k -n team-iris exec <messenger-pod> -- curl -m 2 --head <transmitter-ip> # still works
```

**Policy p2 — deny ICMP transmitter → database (Layer 4)**
```bash
k -n team-iris exec <transmitter-pod> -- ping <database-ip>   # works before policy
```
```yaml
# 8_p2.yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: p2
  namespace: team-iris
spec:
  endpointSelector:
    matchLabels:
      type: transmitter
  egressDeny:
  - toEndpoints:
    - matchLabels:
        type: database
    icmps:
    - fields:
      - type: 8
        family: IPv4
      - type: EchoRequest
        family: IPv6
```
```bash
k -f 8_p2.yaml apply
```
**Verify**
```bash
k -n team-iris exec <transmitter-pod> -- ping -w 2 <database-ip>          # 100% packet loss
k -n team-iris exec <transmitter-pod> -- curl -m 2 --head database        # still works (not ICMP)
k -n team-iris exec <transmitter-pod> -- ping <messenger-ip>              # still works
```

**Policy p3 — Mutual Authentication database → messenger (Layer 3)**
```yaml
# 8_p3.yaml
apiVersion: "cilium.io/v2"
kind: CiliumNetworkPolicy
metadata:
  name: p3
  namespace: team-iris
spec:
  endpointSelector:
    matchLabels:
      type: database
  egress:
  - toEndpoints:
    - matchLabels:
        type: messenger
    authentication:
      mode: "required"
```
```bash
k -f 8_p3.yaml apply
k -n team-iris get cnp
```

[⬆ Back to top](#table-of-contents)

---

## Question 9 | Certificates and Signing Requests

**Reference:** [Certificates and CSRs](https://kubernetes.io/docs/tasks/tls/managing-tls-in-a-cluster) / Manage TLS Certificates in a Cluster
**Solve on:** `ssh cks7984`

### Task
1. Create + **approve** the CSR at `/opt/course/9/csr-app-6c63ce3f.yaml` → download decoded cert to `/opt/course/9/app-6c63ce3f.crt`
2. Create + **deny** the CSR at `/opt/course/9/csr-app-dc6fdc2d.yaml` → store `kubectl describe` output at `/opt/course/9/csr-app-dc6fdc2d.log`
3. Using a given template, create a CSR yaml at `/opt/course/9/new.csr.yaml` for the raw CSR file `/opt/course/9/new.csr` — the `NAME` must match the CN subject inside `new.csr`.

Template:
```yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: {{NAME}}
spec:
  groups:
  - system:authenticated
  request: {{REQUEST}}
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
```

### Answer

### Background
| Abbreviation | Meaning |
|---|---|
| CA | Certificate Authority |
| CSR | Certificate Signing Request |
| CRT | Certificate |
| KEY | Private Key |

Users are identified via the `CN` (Common Name) field in their client certificate. Signing can be done manually via `openssl`, or via a K8s `CertificateSigningRequest` resource (no direct CA access needed; approval controlled by RBAC).

**Step 1 — create and approve**
```bash
ssh cks7984
k -f /opt/course/9/csr-app-6c63ce3f.yaml create
k get csr
kubectl certificate approve app-6c63ce3f@users-pro
k get csr
# Approved,Issued
```
Download the decoded certificate:
```bash
k get csr app-6c63ce3f@users-pro -ojsonpath="{.status.certificate}" | base64 -d > /opt/course/9/app-6c63ce3f.crt
cat /opt/course/9/app-6c63ce3f.crt
```

**Step 2 — create and deny**
```bash
k -f /opt/course/9/csr-app-dc6fdc2d.yaml create
k get csr

k certificate deny app-dc6fdc2d@users-base
k get csr
# Denied

k describe csr app-dc6fdc2d@users-base > /opt/course/9/csr-app-dc6fdc2d.log
```

**Step 3 — build a new CSR yaml from a raw request**

Extract the CN subject:
```bash
openssl req -in /opt/course/9/new.csr -noout -text
```
```text
Subject: CN = app-c5a95f65@users-company   # ← NAME to use
```
Base64-encode the CSR content (single line, no newlines):
```bash
cat /opt/course/9/new.csr | base64 | tr -d "\n"
```
Fill the template:
```yaml
# cks7984:/opt/course/9/new.csr.yaml
apiVersion: certificates.k8s.io/v1
kind: CertificateSigningRequest
metadata:
  name: app-c5a95f65@users-company
spec:
  groups:
  - system:authenticated
  request: <base64-encoded-CSR-single-line>
  signerName: kubernetes.io/kube-apiserver-client
  usages:
  - client auth
```
**Validate without creating** (optional):
```bash
k -f /opt/course/9/new.csr.yaml diff
```
> If `request:` is missing/malformed you'll see errors like `PEM block type must be CERTIFICATE REQUEST` or `illegal base64 data at input byte N`.

[⬆ Back to top](#table-of-contents)

---

## Question 10 | Istio Security and mTLS

**Reference:** [Istio Documentation](https://istio.io/latest/docs)
**Solve on:** `ssh cks1428`

### Task
Namespace `team-sedum` has Deployment `one` calling Deployment `two` via its Service. Istio is installed. Enable **Istio sidecar injection for the whole Namespace** so current and future Pods run with the Istio proxy sidecar.

### Answer

### Background: Istio sidecar injection
Injecting the Istio proxy sidecar routes all container network traffic through it (shared Pod network namespace), enabling **mTLS**, traffic policies, and telemetry — without app changes. For features like mTLS to work, **both** source and destination Pods need the sidecar.

**Investigate**
```bash
ssh cks1428
k get ns
k -n istio-system get pod
k -n team-sedum logs one-<pod>
# Failed to connect to application two   (intermittent)

k -n team-sedum get deploy one -oyaml
# uses http://two.team-sedum.svc.cluster.local:8080 in a curl loop
```

**Enable injection via Namespace label**
```bash
k get ns --show-labels
k label ns team-sedum istio-injection=enabled
k get ns team-sedum --show-labels
```

**Restart Deployments to pick up the sidecar**
```bash
k -n team-sedum rollout restart deploy one
k -n team-sedum get pod
# READY 2/2 → sidecar injected
```
```bash
k -n team-sedum describe pod <one-pod>
```
```text
Labels: ... security.istio.io/tlsMode=istio ...
Annotations: sidecar.istio.io/status: {"initContainers":["istio-init"],"containers":["istio-proxy"],...}
Containers:
  istio-proxy:
    Image: docker.io/istio/proxyv2:1.26.2
```
```bash
k -n team-sedum rollout restart deploy two
k -n team-sedum get pod
# both Deployments now 2/2
```

**(Optional) Confirm via MutatingWebhookConfiguration**
```bash
k get MutatingWebhookConfiguration
k get MutatingWebhookConfiguration istio-sidecar-injector-1-26-2 -oyaml
```
```yaml
namespaceSelector:
  matchExpressions:
  - key: istio-injection
    operator: In
    values: [enabled]
objectSelector:
  matchExpressions:
  - key: sidecar.istio.io/inject
    operator: NotIn
    values: ["false"]
```

[⬆ Back to top](#table-of-contents)

---

## Question 11 | Secrets in ETCD

**Reference:** [etcd Documentation](https://etcd.io/docs) — Operating etcd clusters for Kubernetes
**Solve on:** `ssh cks4933`
**Note:** `sudo -i` may be required.

### Task
Secret `database-access` exists in Namespace `team-daisy`.
1. Read the **complete** Secret content directly from ETCD (via `etcdctl`) → save to `/opt/course/11/etcd-secret-content`
2. Write the plain, decoded value of key `pass` → `/opt/course/11/database-password`

### Answer

```bash
ssh cks4933
sudo -i
etcdctl
# WARNING: ETCDCTL_API not set; defaults to v2 — set ETCDCTL_API=3

cat /etc/kubernetes/manifests/kube-apiserver.yaml | grep etcd
```
```text
--etcd-cafile=/etc/kubernetes/pki/etcd/ca.crt
--etcd-certfile=/etc/kubernetes/pki/apiserver-etcd-client.crt
--etcd-keyfile=/etc/kubernetes/pki/apiserver-etcd-client.key
--etcd-servers=https://127.0.0.1:2379
```
Query ETCD directly (data path pattern: `/registry/{type}/{namespace}/{name}`):
```bash
ETCDCTL_API=3 etcdctl \
  --cert /etc/kubernetes/pki/apiserver-etcd-client.crt \
  --key /etc/kubernetes/pki/apiserver-etcd-client.key \
  --cacert /etc/kubernetes/pki/etcd/ca.crt \
  get /registry/secrets/team-daisy/database-access
```
Save the full raw output to `/opt/course/11/etcd-secret-content` (copy/paste is fine — it includes protobuf-ish binary framing plus the base64 `data.pass` value).

Decode the password:
```bash
echo -n Y29uZmlkZW50aWFs | base64 -d > /opt/course/11/database-password
cat /opt/course/11/database-password
# confidential
```

> ⚠️ This works because the Secret is **not encrypted at rest** — see Question 14 in [CKS Simulator A](#) for how to configure `EncryptionConfiguration`.

[⬆ Back to top](#table-of-contents)

---

## Question 12 | Hack Secrets (RBAC Privilege Escape)

**Topic:** Using RBAC Authorization
**Solve on:** `ssh cks1428`

### Task
Using context `restricted@workload-prod` (user `restricted`, limited permissions, **should not** read Secret values), attempt to find the `password` key values of Secrets `secret1`, `secret2`, `secret3` in Namespace `restricted`. Write decoded values to `/opt/course/12/secret1`, `/opt/course/12/secret2`, `/opt/course/12/secret3`. Switch back afterward.

```bash
k config use-context restricted@workload-prod
# ... investigate ...
k config use-context kubernetes-admin@kubernetes
```

### Answer

**Explore the boundaries**
```bash
ssh cks1428
k config use-context restricted@workload-prod

k -n restricted get role,rolebinding,clusterrole,clusterrolebinding   # Forbidden
k -n restricted get secret                                           # Forbidden (list)
k -n restricted get secret -o yaml                                   # Forbidden (list)
```

**Secret 1 — via Pod volume mount**
```bash
k -n restricted get all
# Pods: pod1, pod2, pod3 (RCs/Services forbidden)

k -n restricted get pod -o yaml | grep -i secret
k -n restricted exec pod1-fd5d64b9c-pcx6q -- cat /etc/secret-volume/password
# you-are

echo you-are > /opt/course/12/secret1
```

**Secret 2 — via Pod environment variable**
```bash
k -n restricted exec pod2-6494f7699b-4hks5 -- env | grep PASS
# PASSWORD=an-amazing

echo an-amazing > /opt/course/12/secret2
```

**Secret 3 — no Pod mounts it; escalate via ServiceAccount token**

No Pod mounts `secret3`, and creating new Pods is forbidden:
```bash
k -n restricted run test --image=nginx    # Forbidden
k -n restricted auth can-i create pods    # no
```
But one Pod (`pod3-*`) has its ServiceAccount token auto-mounted:
```bash
k -n restricted get pod -o yaml | grep automountServiceAccountToken

k -n restricted exec -it pod3-748b48594-24s76 -- sh
mount | grep serviceaccount
ls /run/secrets/kubernetes.io/serviceaccount
# ca.crt  namespace  token
```
Call the API directly with the SA token:
```bash
curl https://kubernetes.default/api/v1/namespaces/restricted/secrets \
  -H "Authorization: Bearer $(cat /run/secrets/kubernetes.io/serviceaccount/token)" -k
```
```json
{
  "metadata": { "name": "secret3", "namespace": "restricted" },
  "data": { "password": "cEVuRXRSYVRpT24tdEVzVGVSCg==" },
  "type": "Opaque"
}
```
```bash
exit    # back from the Pod shell

echo cEVuRXRSYVRpT24tdEVzVGVSCg== | base64 -d
# pEnEtRaTiOn-tEsTeR

echo cEVuRXRSYVRpT24tdEVzVGVSCg== | base64 -d > /opt/course/12/secret3
```

> ⚠️ **RBAC lesson:** granting the `list` verb on Secrets allows reading full Secret content via `kubectl get secrets -o yaml`, even without the `get` verb. And a Pod with an auto-mounted ServiceAccount token can be used to escalate access if the SA itself has broader permissions than the calling user.

**Switch back**
```bash
k config use-context kubernetes-admin@kubernetes
```

[⬆ Back to top](#table-of-contents)

---

## Question 13 | RBAC Operator Troubleshooting

**Topic:** Using RBAC Authorization
**Solve on:** `ssh cks4933`

### Task
Operator `cert-signer` (Namespace `team-lilac`) is crashing. Check logs, iteratively add the **minimal** missing RBAC permissions until it runs error-free with no restarts. Also grant its ServiceAccount permission to **approve** CertificateSigningRequests.

### RBAC combination reference
| Combination | Permission scope | Applied scope | Valid? |
|---|---|---|---|
| Role + RoleBinding | Namespace | Namespace | ✅ |
| ClusterRole + ClusterRoleBinding | Cluster | Cluster | ✅ |
| ClusterRole + RoleBinding | Cluster | Namespace | ✅ |
| Role + ClusterRoleBinding | Namespace | Cluster | ❌ Not possible |

### Answer

```bash
ssh cks4933
k -n team-lilac get sts,pod
# cert-signer-0   CrashLoopBackOff
```

**Round 1 — missing `list configmaps`**
```bash
k -n team-lilac logs cert-signer-0
# Error: cannot list resource "configmaps" in API group "" in namespace "team-lilac"
```
```bash
k -n team-lilac get sts cert-signer -oyaml | grep serviceAccount
# serviceAccountName: cert-signer

k -n team-lilac create role cert-signer --resource configmap --verb list
k -n team-lilac create rolebinding cert-signer --role cert-signer --serviceaccount team-lilac:cert-signer

k -n team-lilac auth can-i list configmap --as system:serviceaccount:team-lilac:cert-signer   # yes
k -n team-lilac delete pod cert-signer-0 --force --grace-period 0
k -n team-lilac logs cert-signer-0
```

**Round 2 — missing `get configmaps`**
```text
Error: cannot get resource "configmaps" "cert-signer-lock" in namespace "team-lilac"
```
```bash
k -n team-lilac edit role cert-signer
```
```yaml
rules:
- apiGroups: [""]
  resources: [configmaps]
  verbs: [list, get]   # ADD get
```
```bash
k -n team-lilac delete pod cert-signer-0 --force --grace-period 0
k -n team-lilac logs cert-signer-0
```

**Round 3 — missing `list csr` at cluster scope**
```text
Error: cannot list resource "certificatesigningrequests" in API group "certificates.k8s.io" at the cluster scope
```
```bash
k create clusterrole cert-signer --resource certificatesigningrequests --verb list
k create clusterrolebinding cert-signer --clusterrole cert-signer --serviceaccount team-lilac:cert-signer

k auth can-i list csr --as system:serviceaccount:team-lilac:cert-signer -A   # yes
k -n team-lilac delete pod cert-signer-0 --force --grace-period 0
k -n team-lilac logs cert-signer-0
# No resources found — no more permission errors, no more restarts
```

> `No resources found` is **not** a permission error — the loop is now clean.

**Grant CSR approval permission**
```bash
k edit clusterrole cert-signer
```
```yaml
rules:
- apiGroups: [certificates.k8s.io]
  resources: [certificatesigningrequests]
  verbs: [list]
- apiGroups: [certificates.k8s.io]      # ADD
  resources: [certificatesigningrequests/approval]
  verbs: [update]
```
> For real-world completeness you'd also grant `approve` on the specific `signers` resource (e.g. `kubernetes.io/kube-apiserver-client`) — but this extra scoping isn't checked by this question.

[⬆ Back to top](#table-of-contents)

---

## Question 14 | Syscall Activity

**Reference:** [Falco Documentation](https://falco.org/docs)
**Solve on:** `ssh cks5632` → `ssh cks5632-node1`

### Task
Pods in Namespace `team-tulip` may be using the forbidden `kill` syscall. Find the offending Pod(s) and scale the parent Deployment to `0`.

### Answer

Syscalls let Userspace processes talk to the Linux Kernel. Container runtimes restrict some by default (e.g. `reboot`); further restriction is possible via Seccomp/AppArmor.

**Locate the node**
```bash
ssh cks5632
k -n team-tulip get pod -owide
# all on cks5632-node1
```

**Find each Deployment's process and inspect syscalls**
```bash
ssh cks5632-node1
sudo -i

crictl pods --name collector1
crictl ps --pod <pod-id>
crictl inspect <container-id> | grep args -A1
# ./collector1-process

ps aux | grep collector1-process
strace -p <pid>
```
```text
kill(666, SIGTERM) = -1 ESRCH (No such process)   ← forbidden syscall found!
```

Check other Deployments (`collector2`, `collector3`) the same way — clean (no `kill` syscall).

**Scale down the offender**
```bash
k -n team-tulip scale deploy collector1 --replicas 0
```

[⬆ Back to top](#table-of-contents)

---

## Question 15 | Apiserver TLS Settings

**Reference:** [kube-apiserver](https://kubernetes.io/docs/reference/command-line-tools-reference/kube-apiserver)
**Solve on:** `ssh cks7984`

### Task
Set the apiserver's **TLS minimum version** to `1.3`. Then call it with `curl --tls-max 1.2 --tlsv1.2`, writing the full output (incl. errors) to `/opt/course/15/curl.log`.

### Answer

**Configure the apiserver**
```bash
ssh cks7984
sudo -i
cp /etc/kubernetes/manifests/kube-apiserver.yaml ./15_kube-apiserver.yaml
vim /etc/kubernetes/manifests/kube-apiserver.yaml
```
```yaml
    - --tls-cert-file=/etc/kubernetes/pki/apiserver.crt
    - --tls-private-key-file=/etc/kubernetes/pki/apiserver.key
    - --tls-min-version=VersionTLS13   # ADD
```
```bash
watch crictl ps   # wait for apiserver restart
```

> ⚠️ **Common typo:** `--tls-min-version VersionTLS13` (space) instead of `--tls-min-version=VersionTLS13` (equals) → `Error: unknown flag`. Check `/var/log/pods/kube-system_kube-apiserver-*/kube-apiserver/*.log` if the container doesn't come back.

**Test with curl**

The apiserver uses `hostNetwork: true`, so it's reachable at `https://127.0.0.1:6443` directly from the host:
```bash
curl --tls-max 1.2 --tlsv1.2 https://127.0.0.1:6443
# curl: (35) OpenSSL/3.0.13: error:0A00042E:SSL routines::tlsv1 alert protocol version

curl --tls-max 1.3 --tlsv1.3 https://127.0.0.1:6443 -k
# {"kind":"Status", ..., "message": "forbidden: User \"system:anonymous\" cannot get path \"/\""}
```
```bash
vim /opt/course/15/curl.log
```
```text
curl: (35) OpenSSL/3.0.13: error:0A00042E:SSL routines::tlsv1 alert protocol version
```

[⬆ Back to top](#table-of-contents)

---

## Question 16 | Docker Image Attack Surface

**Solve on:** `ssh cks5632`
**Note:** Run `podman` as user `candidate`, **not** root.

### Task
Deployment `image-verify` (Namespace `team-maple`) runs `registry.killer.sh:5000/image-verify:v1`. Update `/opt/course/16/image/Dockerfile` (edit existing lines only, no new lines) to:
- Base image → `alpine:3.22`
- **Don't** install `curl`
- `nginx` version constraint `>=1.18.0`
- Run main process as `myuser`

Build/tag as `v2`, push, and update the Deployment.

```bash
cd /opt/course/16/image
podman build -t registry.killer.sh:5000/image-verify:v2 .
podman run registry.killer.sh:5000/image-verify:v2   # test
podman push registry.killer.sh:5000/image-verify:v2
```

### Answer

**Inspect the current Dockerfile**
```bash
ssh cks5632
cd /opt/course/16/image
cp Dockerfile Dockerfile.bak
cat Dockerfile
```
```dockerfile
FROM alpine:3.4
RUN apk update && apk add vim curl nginx=1.10.3-r0
RUN addgroup -S myuser && adduser -S myuser -G myuser
COPY ./run.sh run.sh
RUN ["chmod", "+x", "./run.sh"]
USER root
ENTRYPOINT ["/bin/sh", "./run.sh"]
```
```bash
k -n team-maple logs -f -l id=image-verify
# uid=0(root) ... — confirms running as root currently
```

**Edit in place (no new lines)**
```dockerfile
FROM alpine:3.22
RUN apk update && apk add vim nginx>=1.18.0
RUN addgroup -S myuser && adduser -S myuser -G myuser
COPY ./run.sh run.sh
RUN ["chmod", "+x", "./run.sh"]
USER myuser
ENTRYPOINT ["/bin/sh", "./run.sh"]
```

**Build, test, push**
```bash
podman build -t registry.killer.sh:5000/image-verify:v2 .
podman run registry.killer.sh:5000/image-verify:v2
# uid=101(myuser) gid=102(myuser) groups=102(myuser)

podman push registry.killer.sh:5000/image-verify:v2
```

**Update the Deployment**
```bash
k -n team-maple edit deploy image-verify
```
```yaml
containers:
- image: registry.killer.sh:5000/image-verify:v2   # change
```

**Verify**
```bash
k -n team-maple logs -f -l id=image-verify
# uid=101(myuser) gid=102(myuser) groups=102(myuser)

k -n team-maple exec <pod> -- curl
# curl: executable file not found in $PATH   ← confirms curl not installed

k -n team-maple exec <pod> -- nginx -v
# nginx version: nginx/1.18.0
```

[⬆ Back to top](#table-of-contents)

---

## Question 17 | Update Kubernetes (kubeadm)

**Reference:** [Upgrading kubeadm clusters](https://kubernetes.io/docs/tasks/administer-cluster/kubeadm/kubeadm-upgrade)
**Solve on:** `ssh cks9640` → `ssh cks9640-node1`
**Note:** `sudo -i` may be required.

### Task
Upgrade the cluster from Kubernetes **1.34.5** → **1.35.2** using `apt` and `kubeadm`.

### Answer

```bash
ssh cks9640
k get node
# both nodes at v1.34.5
```

### Control Plane

**Drain the controlplane node**
```bash
k drain cks9640 --ignore-daemonsets
```

**Check / install kubeadm at target version**
```bash
sudo -i
kubelet --version      # v1.34.5
kubeadm version        # already v1.35.2 in this env
```
If not already at target version:
```bash
apt-mark unhold kubeadm
apt install kubeadm=1.35.2-1.1
apt-mark hold kubeadm
```

**Plan and apply the upgrade**
```bash
kubeadm upgrade plan
kubeadm upgrade apply v1.35.2
```
> Confirm with `y` when prompted. This upgrades etcd, kube-apiserver, kube-controller-manager, kube-scheduler, CoreDNS, kube-proxy on the controlplane.
```bash
kubeadm upgrade plan
# Cluster version: v1.35.2 ✅
```

**Upgrade kubelet + kubectl on the controlplane**
```bash
apt update
apt show kubelet | grep 1.35.2
apt install kubelet=1.35.2-1.1 kubectl=1.35.2-1.1
apt-mark hold kubelet kubectl

service kubelet restart
service kubelet status

k get node
# cks9640  Ready,SchedulingDisabled  v1.35.2
```

**Uncordon**
```bash
k uncordon cks9640
```

### Data Plane (worker node)

**Drain the worker**
```bash
k drain cks9640-node1 --ignore-daemonsets
```

**Upgrade kubeadm on the worker**
```bash
ssh cks9640-node1
apt update
kubeadm version   # v1.34.5

apt install kubeadm=1.35.2-1.1
kubeadm upgrade node
```

**Upgrade kubelet + kubectl on the worker**
```bash
apt-mark unhold kubectl kubelet
apt install kubelet=1.35.2-1.1 kubectl=1.35.2-1.1

service kubelet restart
service kubelet status
apt-mark hold kubelet kubectl
```

**Uncordon and verify**
```bash
k get node
# cks9640         Ready  v1.35.2
# cks9640-node1   Ready,SchedulingDisabled  v1.35.2

k uncordon cks9640-node1
k get node
# both nodes Ready v1.35.2
```

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
