# 🔧 Troubleshooting

Diagnosing and fixing the most common Kubernetes failures — with exact commands and decision trees.

---

## 📚 Table of Contents

- [1. General Debug Workflow](#1-general-debug-workflow)
- [2. Pod Issues](#2-pod-issues)
- [3. Deployment Issues](#3-deployment-issues)
- [4. Service & Networking Issues](#4-service--networking-issues)
- [5. Storage Issues](#5-storage-issues)
- [6. Node Issues](#6-node-issues)
- [7. Resource Issues](#7-resource-issues)
- [8. Debug Tools & Techniques](#8-debug-tools--techniques)
- [Cheatsheet](#cheatsheet)

---

## 1. General Debug Workflow

```
Something is broken
        │
        ▼
kubectl get <resource>         ← What is the current state?
        │
        ▼
kubectl describe <resource>    ← What events/conditions explain the state?
        │
        ▼
kubectl logs <pod>             ← What is the app reporting?
        │
        ▼
kubectl exec -it <pod> -- sh   ← Can I investigate from inside?
        │
        ▼
kubectl get events             ← What happened recently?
```

---

## 2. Pod Issues

### CrashLoopBackOff

Pod keeps crashing and restarting. Kubernetes applies exponential backoff between restarts.

```bash
# Step 1 — See how many times it's restarted
kubectl get pod my-pod
# Look at RESTARTS column

# Step 2 — Check current logs
kubectl logs my-pod

# Step 3 — Check logs from the PREVIOUS crash (most important)
kubectl logs my-pod --previous
kubectl logs my-pod -p           # short form

# Step 4 — Check events
kubectl describe pod my-pod
# Look at Events section at the bottom

# Step 5 — Common causes and fixes:

# OOMKilled — not enough memory
kubectl describe pod my-pod | grep -i oom
# Fix: increase memory limit or fix memory leak

# Liveness probe failing too early
kubectl describe pod my-pod | grep -i "Liveness"
# Fix: increase initialDelaySeconds on livenessProbe

# App exits with error
kubectl logs my-pod --previous | tail -50
# Fix: debug the application error

# Wrong command or entrypoint
kubectl describe pod my-pod | grep -A5 "Command:"
# Fix: check the CMD/ENTRYPOINT in the image
```

### ImagePullBackOff / ErrImagePull

```bash
kubectl describe pod my-pod
# Look for events like:
# "Failed to pull image": unauthorized: authentication required
# "Failed to pull image": not found

# Causes and fixes:

# 1. Wrong image name or tag
kubectl describe pod my-pod | grep "Image:"
# Fix: correct the image name/tag in deployment

# 2. Private registry — missing imagePullSecret
kubectl get secret -n production | grep registry
# Fix: create secret and add to pod spec
kubectl create secret docker-registry registry-creds \
  --docker-server=registry.example.com \
  --docker-username=user \
  --docker-password=password
# Add to deployment:
# spec:
#   imagePullSecrets:
#     - name: registry-creds

# 3. Registry unreachable (network/firewall issue)
kubectl exec -it debug-pod -- curl https://registry.example.com
```

### Pending — pod not scheduling

```bash
kubectl describe pod my-pod
# Look at Events for FailedScheduling

# Common causes:

# 1. Insufficient resources on nodes
kubectl describe pod my-pod | grep -A5 "Insufficient"
# Shows: "0/3 nodes are available: 3 Insufficient cpu"
# Fix: reduce resource requests, add nodes, or check LimitRange

# 2. Node selector doesn't match any node
kubectl describe pod my-pod | grep nodeSelector
kubectl get nodes --show-labels
# Fix: correct the nodeSelector or add the label to a node

# 3. Taint not tolerated
kubectl describe pod my-pod | grep -i taint
kubectl describe nodes | grep Taints
# Fix: add toleration to pod spec

# 4. PVC not bound
kubectl get pvc -n production
kubectl describe pvc my-pvc
# Fix: see Storage troubleshooting section

# 5. Affinity/anti-affinity rules can't be satisfied
kubectl describe pod my-pod | grep -A10 "Warnings"
```

### OOMKilled — out of memory

```bash
# Identify OOMKilled pods
kubectl get pods -A | grep OOMKilled
kubectl describe pod my-pod | grep -i oom

# Check memory usage trends
kubectl top pods -n production

# See memory limit
kubectl describe pod my-pod | grep -A2 "Limits:"

# Fix options:
# 1. Increase memory limit
kubectl edit deployment my-app
# or patch:
kubectl patch deployment my-app -p \
  '{"spec":{"template":{"spec":{"containers":[{"name":"app","resources":{"limits":{"memory":"512Mi"}}}]}}}}'

# 2. Find memory leak in the application
# Check if usage grows over time with kubectl top pods -w
```

### Terminating — pod stuck

```bash
# Pod stuck in Terminating state
kubectl get pod my-pod
# STATUS = Terminating, for a long time

# Check why it won't terminate
kubectl describe pod my-pod
# Look for: finalizers, preStop hooks

# Check if there's a finalizer blocking deletion
kubectl get pod my-pod -o yaml | grep finalizer

# Force delete (last resort — can cause data issues)
kubectl delete pod my-pod --force --grace-period=0

# Remove a finalizer manually
kubectl patch pod my-pod -p '{"metadata":{"finalizers":[]}}' --type=merge
```

---

## 3. Deployment Issues

### Deployment stuck during rollout

```bash
# Check rollout status
kubectl rollout status deployment/my-app
# If stuck: "Waiting for deployment "my-app" rollout to finish..."

# See what's happening
kubectl describe deployment my-app
kubectl get pods -l app=my-app

# Check if new pods are failing
kubectl get pods -l app=my-app
# New pods in CrashLoopBackOff? Fix the application issue first.

# Rollback if rollout is broken
kubectl rollout undo deployment/my-app
kubectl rollout undo deployment/my-app --to-revision=2

# Common causes:
# 1. New image fails health checks → rollback
# 2. maxUnavailable: 0 and pods won't become ready → fix probe
# 3. Resource limits too low → pods OOMKill before becoming ready
```

### Deployment not updating pods

```bash
# Check if image tag is latest/wrong
kubectl describe deployment my-app | grep Image
# If using "latest" tag and imagePullPolicy: IfNotPresent
# → Pod uses cached old image

# Force re-pull and restart
kubectl rollout restart deployment/my-app

# Check if rollout happened
kubectl rollout history deployment/my-app
```

---

## 4. Service & Networking Issues

### Service not routing traffic

```bash
# Step 1 — Check if Service exists
kubectl get svc -n production

# Step 2 — Check endpoints (which pods are selected)
kubectl get endpoints my-service -n production
# If ENDPOINTS column is <none> — selector doesn't match any pod

# Step 3 — Check selector matches pod labels
kubectl describe svc my-service | grep Selector
kubectl get pods -l app=my-app --show-labels
# Compare: Service selector must match pod labels exactly

# Step 4 — Check target port
kubectl describe svc my-service | grep "TargetPort"
kubectl describe pod my-pod | grep "Ports"
# Port in Service must match container's listening port

# Step 5 — Test from inside the cluster
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash
# Inside:
curl http://my-service.production.svc.cluster.local
curl http://my-service.production
```

### DNS not resolving

```bash
# Test DNS from inside a pod
kubectl exec -it my-pod -- nslookup kubernetes.default
kubectl exec -it my-pod -- nslookup my-service.production

# If DNS fails, check CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl logs -n kube-system -l k8s-app=kube-dns

# Check DNS config inside pod
kubectl exec -it my-pod -- cat /etc/resolv.conf
# Should show: nameserver 10.96.0.10 (or cluster DNS IP)

# Check CoreDNS ConfigMap
kubectl get configmap coredns -n kube-system -o yaml
```

### Ingress not working

```bash
# Check Ingress controller pods
kubectl get pods -n ingress-nginx

# Check Ingress resource
kubectl describe ingress my-ingress -n production

# Check if backend service exists
kubectl get svc my-service -n production

# Check Ingress controller logs
kubectl logs -n ingress-nginx -l app.kubernetes.io/name=ingress-nginx

# Common issues:
# 1. ingressClassName doesn't match controller (check annotations vs spec.ingressClassName)
# 2. Backend service name or port wrong
# 3. TLS secret missing or wrong namespace
# 4. Host header not matching rules
```

---

## 5. Storage Issues

### PVC stuck in Pending

```bash
kubectl describe pvc my-pvc -n production
# Look at Events section

# Common causes:
# 1. No matching StorageClass
kubectl get storageclass
kubectl describe pvc | grep StorageClass

# 2. No available PV (manual provisioning)
kubectl get pv    # check STATUS and CLAIM columns

# 3. CSI driver not installed
kubectl get csidrivers
kubectl get pods -n kube-system | grep csi

# 4. volumeBindingMode: WaitForFirstConsumer (normal, not a problem)
# PVC won't bind until a pod using it is scheduled
kubectl get pod -l app=my-app   # check if pod is also Pending
```

### Pod stuck in ContainerCreating with volume error

```bash
kubectl describe pod my-pod
# Common volume errors:

# "Unable to attach or mount volumes"
# → PVC not yet bound, or EBS volume in wrong AZ
kubectl get pvc

# "Multi-Attach error: volume is already used by another pod"
# → RWO volume attached to a pod on different node
# Fix: delete old pod, ensure only one pod uses the volume at a time

# "no volume plugin matched"
# → CSI driver not installed
kubectl get csidrivers
```

---

## 6. Node Issues

### Node NotReady

```bash
# Check node status
kubectl get nodes
kubectl describe node worker-1

# Common conditions to look for
kubectl describe node worker-1 | grep -A30 "Conditions:"
# DiskPressure: True → disk full on node
# MemoryPressure: True → low memory
# PIDPressure: True → too many processes
# Ready: False → kubelet not reporting

# Check kubelet on the node (SSH to node)
systemctl status kubelet
journalctl -u kubelet -n 100

# Check node resource usage
kubectl top node worker-1
```

### Node disk pressure

```bash
# From node:
df -h
du -sh /var/lib/docker    # or /var/lib/containerd
du -sh /var/log/pods/

# Clean up unused container images
crictl rmi --prune
# or with docker:
docker system prune

# Check image garbage collection settings
# kubelet has configurable GC thresholds
```

### Cordoning and draining nodes

```bash
# Cordon — prevent new pods from being scheduled (node stays running)
kubectl cordon worker-1

# Drain — evict all pods from node (for maintenance)
kubectl drain worker-1 \
  --ignore-daemonsets \   # daemonsets are excluded
  --delete-emptydir-data  # ok to delete emptyDir volumes

# After maintenance — uncordon
kubectl uncordon worker-1

# Check which nodes are cordoned
kubectl get nodes
# SchedulingDisabled in STATUS column = cordoned
```

---

## 7. Resource Issues

### Pod can't be scheduled — FailedScheduling

```bash
kubectl describe pod my-pod | grep -A20 "Events:"
# "0/3 nodes are available: 3 Insufficient cpu"

# Check node capacity vs requests
kubectl describe nodes | grep -A8 "Allocated resources:"

# Check if there's a LimitRange causing issues
kubectl describe limitrange -n production
```

### ResourceQuota exceeded

```bash
# Error: "exceeded quota: production-quota, requested: cpu=500m, used: 9500m, limited: 10"
kubectl describe resourcequota -n production
# Shows used vs limit for each resource
```

---

## 8. Debug Tools & Techniques

### kubectl debug — ephemeral debug containers

```bash
# Add a debug container to a running pod (Kubernetes 1.23+)
kubectl debug -it my-pod --image=nicolaka/netshoot --target=my-container

# Create a copy of a pod with debug image
kubectl debug my-pod -it --copy-to=debug-pod --image=ubuntu

# Debug a node (runs privileged pod on the node)
kubectl debug node/worker-1 -it --image=ubuntu
```

### Useful debug images

```bash
# netshoot — networking tools (curl, dig, tcpdump, netstat, etc.)
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash

# busybox — minimal, has wget and sh
kubectl run debug --image=busybox -it --rm -- sh

# ubuntu — full shell
kubectl run debug --image=ubuntu -it --rm -- bash

# alpine — lightweight
kubectl run debug --image=alpine -it --rm -- sh
```

### Debug a specific pod's network

```bash
# From inside the pod's namespace
kubectl exec -it my-pod -- sh

# Test DNS
nslookup my-service
nslookup kubernetes.default.svc.cluster.local

# Test HTTP
curl http://my-service:80/health
curl -v https://external-api.example.com

# Check listening ports
ss -tulnp
netstat -tulnp

# Check routes
ip route
ip addr
```

### View resource YAML

```bash
# See the full spec of any resource
kubectl get pod my-pod -o yaml
kubectl get deployment my-app -o yaml
kubectl get svc my-service -o yaml

# Extract specific fields with jsonpath
kubectl get pod my-pod -o jsonpath='{.status.phase}'
kubectl get pods -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.status.phase}{"\n"}{end}'

# Extract with custom columns
kubectl get pods -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,NODE:.spec.nodeName"
```

### Check RBAC issues

```bash
# "Error from server (Forbidden)"
kubectl auth can-i get pods -n production
kubectl auth can-i get pods -n production --as=system:serviceaccount:production:my-app

# List what a ServiceAccount can do
kubectl auth can-i --list -n production --as=system:serviceaccount:production:my-app
```

### Decode Kubernetes events with stern

```bash
# Install stern for multi-pod log streaming
brew install stern

# Stream logs from all pods with label
stern -l app=my-app

# Stream from specific namespace
stern . -n production

# Stream with time and specific container
stern my-pod -c app --since 1h
```

---

## Cheatsheet

```bash
# Pod status
kubectl get pods -A
kubectl describe pod my-pod            # events + conditions
kubectl logs my-pod --previous         # crashed container logs
kubectl logs -l app=my-app -f          # follow all pods

# Debug
kubectl exec -it my-pod -- sh
kubectl run debug --image=nicolaka/netshoot -it --rm -- bash
kubectl debug -it my-pod --image=nicolaka/netshoot --target=app

# Events
kubectl get events --sort-by='.lastTimestamp' -n production
kubectl get events -A -w

# Service debugging
kubectl get endpoints my-svc           # which pods are selected
kubectl port-forward svc/my-svc 8080:80

# Node debugging
kubectl describe node worker-1
kubectl drain worker-1 --ignore-daemonsets --delete-emptydir-data
kubectl cordon/uncordon worker-1

# Resource usage
kubectl top nodes
kubectl top pods -A --sort-by=cpu

# Common fix commands
kubectl rollout restart deployment/my-app      # rolling restart
kubectl rollout undo deployment/my-app         # rollback
kubectl delete pod my-pod --force              # force delete stuck pod
kubectl scale deployment my-app --replicas=0   # kill all pods (then set back)
```

### Decision tree for common failures

```
Pod not running?
├── Pending
│   ├── FailedScheduling → check resources, nodeSelector, taints
│   └── PVC Pending → check StorageClass, CSI driver
├── CrashLoopBackOff
│   ├── OOMKilled → increase memory limit
│   ├── App crash → check logs with --previous
│   └── Probe failing → check initialDelaySeconds
├── ImagePullBackOff → check image name, registry credentials
├── ContainerCreating → check volume mounts, secrets, configmaps
└── Terminating (stuck) → force delete with --grace-period=0

Service not working?
├── No endpoints → check selector matches pod labels
├── Wrong port → check targetPort vs container port
└── DNS failure → check CoreDNS pods, pod /etc/resolv.conf
```

---

*Next: [Interview Q&A →](./10-interview-qa.md) — core, scenario-based, and advanced Kubernetes interview questions.*
