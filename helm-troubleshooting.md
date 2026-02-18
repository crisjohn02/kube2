# Helm Troubleshooting Playbook

---

## Step 1 — Before Installing: Understand What the Chart Creates

```bash
# See all default values
helm show values oci://...

# See the actual manifests the chart will generate — without installing anything
helm template my-release oci://... -f my-values.yaml

# Pipe it through grep to find specific resource types
helm template my-release oci://... -f my-values.yaml | grep "^kind:"
```

`helm template` is the most underused command. It renders everything locally so you
can see exactly what Kubernetes will receive — every Deployment, Service, ConfigMap,
Job, PVC — before a single thing is applied.

---

## Step 2 — After Installing: See Everything the Chart Created

```bash
# See all resources helm created, grouped by type
helm get manifest my-release -n namespace

# Quick overview of every resource type in the namespace
kubectl get all -n metrics

# kubectl get all misses some things (PVCs, Ingresses, CRDs) — always follow up with:
kubectl get ingress,pvc,configmap,secret,servicemonitor -n metrics
```

---

## Step 3 — Something is Failing: Triage Order

```bash
# 1. Start here — what's the overall picture?
kubectl get pods -n metrics

# 2. Zoom into the broken pod
kubectl describe pod <pod-name> -n metrics
# Read the Events section at the bottom — that's always the most useful part

# 3. Get the actual logs
kubectl logs <pod-name> -n metrics
kubectl logs <pod-name> -n metrics --previous   # logs from before the last crash

# 4. If it has multiple containers (like Grafana's 3/3)
kubectl logs <pod-name> -n metrics -c <container-name>

# 5. See all recent events in the namespace — best birds-eye view of what's wrong
kubectl get events -n metrics --sort-by='.lastTimestamp'
```

> The **Events section in `describe`** and **`get events`** will tell you 80% of
> what's wrong — image pull failures, volume mount errors, OOMKilled, etc.

---

## Step 4 — Operators Specifically: Understand the CRDs They Own

Operators are harder because they add custom resource types that `kubectl get all`
won't show.

```bash
# See what CRDs the operator registered
kubectl get crd | grep monitoring   # prometheus operator
kubectl get crd | grep traefik      # traefik

# Then query those custom resources
kubectl get prometheusrule -A
kubectl get servicemonitor -A
kubectl get alertmanagerconfig -A
```

> If Prometheus isn't scraping something, 9/10 times it's a `ServiceMonitor` issue —
> either it doesn't exist, has wrong labels, or wrong namespace selector.

---

## Step 5 — Values Not Taking Effect?

```bash
# See what values are actually live on the running release
helm get values my-release -n namespace

# See computed values (your overrides merged with chart defaults)
helm get values my-release -n namespace --all
```

This tells you if your values file was actually applied or if you're looking at stale
config from a previous install.

---

## The Mental Model

| Command | Question it answers | When to use |
|---|---|---|
| `helm template` | What will be created? | Before installing |
| `kubectl get all` | What exists? | After installing |
| `kubectl describe` | Why is this pod unhappy? | Triage |
| `kubectl logs` | What did the app say? | Deep dive |
| `kubectl get events` | What did Kubernetes say? | Deep dive |
| `helm get values` | Are my values applied? | Config check |

Work top to bottom. Most issues are caught at `describe` before you even need logs.

---

## Real Example — kube-prometheus-stack

```bash
# See every resource type the chart will create before installing
helm template kube-prometheus-stack oci://ghcr.io/prometheus-community/charts/kube-prometheus-stack \
  -n metrics \
  -f metrics/kube-prometheus-stack/helm-values.yaml | grep "^kind:"
```

This gives you a complete map of what to look for when things break.

---

## Common Failures and Where to Look

| Symptom | First place to check |
|---|---|
| Pod stuck in `Pending` | `kubectl describe pod` → Events (usually resource limits or PVC not bound) |
| Pod stuck in `Init:Error` | `kubectl logs <pod> -c <init-container-name>` |
| Pod in `ImagePullBackOff` | `kubectl describe pod` → Events (bad image name, registry unreachable, auth) |
| Pod in `CrashLoopBackOff` | `kubectl logs <pod> --previous` (logs from before the crash) |
| Pod in `ContainerCreating` | `kubectl describe pod` → usually a missing Secret or ConfigMap |
| Chart installed but nothing works | `helm get values` → check your overrides actually applied |
| Operator not picking up your CRD | Check labels — ServiceMonitor labels must match the operator's selector |
