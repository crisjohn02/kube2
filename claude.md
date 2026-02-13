# Kubernetes Learning Plan

> Learning Kubernetes from Docker Swarm, using your deployments folder as reference.
> Focused on: **1 Laravel app, 1 Node.js app, 1 Python app, Neo4j, and clustered MariaDB/Redis/MongoDB.**

---

## What You Already Know (Swarm) vs What You'll Learn (K8s)

| Swarm concept you use | Kubernetes equivalent | Key difference |
|---|---|---|
| `docker stack deploy -c stack.yaml` | `kubectl apply -f .` | Same idea, different CLI |
| One service = container + networking + routing | **3 resources**: Deployment + Service + Ingress | K8s splits "what runs" from "how to reach it" |
| `replicas: 8` | `spec.replicas: 8` | Identical concept |
| Stack name (app1) | **Namespace** | Logical grouping, same idea |
| External network `web2` | Flat networking (all pods talk by default) | No explicit network attachment needed |
| Traefik labels on services | **Ingress** resource | Declarative YAML instead of labels |
| Docker Swarm secrets (external) | **Kubernetes Secrets** | Can mount as files OR env vars |
| `.env` files | **ConfigMaps** | Same purpose |
| `deploy.placement.constraints` | `nodeSelector` / `nodeAffinity` | Same purpose |
| `deploy.resources.limits.memory: 2.5G` | `resources.limits.memory: "2560Mi"` | Different unit format |
| `deploy.update_config` (order: start-first) | `strategy.rollingUpdate` (maxSurge/maxUnavailable) | More granular in K8s |
| `healthcheck` | `livenessProbe` + `readinessProbe` + `startupProbe` | K8s has 3 types vs Swarm's 1 |
| Bind mounts `/mnt/data/*` | **PersistentVolumeClaim (PVC)** | Declarative storage requests |
| Named volumes | PVC with **StorageClass** | Auto-provisioned |
| `mode: global` | **DaemonSet** | Runs on every node |
| Docker socket for Traefik | **Kubernetes API + RBAC** | No socket mounting |
| Single-instance databases | **StatefulSets** with clustering | This is where K8s shines |

### The One Big Mental Shift

In Swarm, you write one service block and it handles everything. In Kubernetes, you write:

```
Deployment  →  "what container to run, how many replicas, resource limits"
Service     →  "how other pods find this internally" (like DNS within Swarm network)
Ingress     →  "how the outside world reaches this" (replaces Traefik labels)
```

Your `app1` service in `deployments/fluent-stack/stack.yaml` becomes 3 separate YAML resources.

---

## Phase 1: Setup

### 1.1 Install Tools

```bash
brew install kubectl           # The CLI (like docker/docker-compose)
brew install minikube           # Local cluster (single-node K8s on your Mac)
brew install helm               # Package manager (used for Traefik, databases, monitoring)
brew install k9s                # Terminal UI - makes K8s visual and fast

# To install in WSL2 - Windows
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

curl -LO https://github.com/kubernetes/minikube/releases/latest/download/minikube-linux-amd64
sudo install minikube-linux-amd64 /usr/local/bin/minikube && rm minikube-linux-amd64

wget https://github.com/derailed/k9s/releases/latest/download/k9s_linux_amd64.deb && sudo apt install ./k9s_linux_amd64.deb && rm k9s_linux_amd64.deb

curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-4 | bash
```

### 1.2 Start a Local Cluster

```bash
minikube start --cpus=4 --memory=8192 --driver=docker
minikube addons enable metrics-server
minikube dashboard
```

### 1.3 Verify

```bash
kubectl get nodes               # Should show one node "Ready"
kubectl cluster-info            # Shows API server URL
```

**Swarm equivalent**: `docker swarm init` + `docker node ls`

---

## Phase 2: Ingress Controller (Traefik)

**Why Traefik**: You already use it. Same tool, different integration. In Swarm it reads Docker socket labels. In K8s it watches Ingress resources via the Kubernetes API.

### 2.1 Install Traefik via Helm

```bash
helm repo add traefik https://traefik.github.io/charts
helm repo update

helm install -f infrastructure/traefik/values.yaml traefik traefik/traefik
```

#### 2.1.1 Upgrade / Update helm based on values.yaml changes
```bash
helm upgrade -f infrastructure/traefik/values.yaml traefik traefik/traefik
```

### 2.2 What Changed from Swarm Traefik

- No Docker socket needed - Traefik uses **Kubernetes API** instead
- Config is via Helm values (`infrastructure/traefik/values.yaml`) instead of a mounted `traefik.yaml`
- TLS will be handled by **cert-manager** (installed next) instead of Traefik's built-in ACME

### 2.3 Install cert-manager (Replaces Traefik ACME)

In your Swarm config (`traefik-stack/config/traefik.yaml`), you have certificate resolvers for Let's Encrypt. In K8s, **cert-manager** is the standard way:

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager -f infrastructure/cert-manager/values.yaml jetstack/cert-manager --namespace cert-manager --create-namespace
```

Then create the ClusterIssuer (see `infrastructure/cert-manager/cluster-issuer.yaml`):

```bash
kubectl apply -f infrastructure/cert-manager/cluster-issuer.yaml
```

Now any Ingress with `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation gets automatic TLS.

### 2.4 Security Headers (Translating Your headers.yaml)

Your `traefik-stack/config/headers.yaml` becomes a Traefik **Middleware CRD** (`traefik.io/v1alpha1` kind `Middleware`).
Reference it in any Ingress with: `traefik.ingress.kubernetes.io/router.middlewares: traefik-security-headers@kubernetescrd`

---

## Phase 3: Secrets, ConfigMaps, and Registry

### 3.1 Secrets (Replacing Docker Swarm External Secrets)

Swarm uses `docker secret create` + `external: true` in stack files.

**Kubernetes equivalent** - see `apps/app1/secrets.yaml` (Secret named `app1-secrets` in namespace `app1`):

```bash
kubectl apply -f apps/app1/secrets.yaml
```

Secrets can be injected as **env vars** (`envFrom.secretRef`) or **mounted as files** at `/run/secrets/` (identical to Swarm). We use env vars.

### 3.2 ConfigMaps (Replacing .env Files)

Swarm uses `env_file`. **Kubernetes** - see `apps/app1/configmap.yaml` (ConfigMap named `laravel-app-config` in namespace `app1`).
Contains the full Laravel .env equivalent (DB connections, Redis, MongoDB, mail, cache drivers, etc.).

```bash
kubectl apply -f apps/app1/configmap.yaml
```

### 3.3 Private Registry Auth

Your images come from `hub.connoisseur-suite.co.uk`. Registry credentials are in `registry/namespace.yaml` and `registry/credentials.yaml`.

```bash
kubectl apply -f registry/namespace.yaml
kubectl apply -f registry/credentials.yaml
```

You also need a `regcred` pull secret in each app namespace (referenced via `imagePullSecrets` in Deployments).

---

## Phase 4: Deploy a Laravel App (app1)

This is your most representative app. Translating `deployments/fluent-stack/stack.yaml`.

The app uses **PHP Swoole (Octane)** listening on **port 9000** (see `app_images/laravel-app/Dockerfile`).

### 4.1 File Structure

All app1 manifests live in `apps/app1/`:
```
apps/app1/
├── namespace.yaml        # Creates the app1 namespace
├── secrets.yaml          # Sensitive env vars (APP_KEY, DB_PASSWORD, etc.)
├── configmap.yaml        # Full Laravel .env equivalent (DB hosts, Redis, etc.)
└── deployment.yaml       # Deployment + Service (port 9000)
```

### 4.2 Kubernetes Deployment

See `apps/app1/deployment.yaml` for the full Deployment + Service definition.

Key points:
- Deployment named `app1` in namespace `app1`, port **9000** (Swoole/Octane)
- Uses `laravel-app-config` ConfigMap + `app1-secrets` Secret via `envFrom`
- RollingUpdate strategy (maxSurge: 1, maxUnavailable: 0)
- Startup, readiness, and liveness probes on port 9000
- `imagePullSecrets: regcred` for private registry
- Service exposes port 9000 internally as `app1.app1.svc`

### 4.4 Deploy It

```bash
# 1. Namespace, secrets, configmap, registry (already applied)
kubectl apply -f apps/app1/namespace.yaml
kubectl apply -f apps/app1/secrets.yaml
kubectl apply -f apps/app1/configmap.yaml
# Registry credentials also already applied

# 2. Deploy the app
kubectl apply -f apps/app1/deployment.yaml

# Watch pods come up
kubectl get pods -n app1 -w

# Check logs
kubectl logs -n app1 -l app=app1 --tail=50 -f

# Exec into a pod (like docker exec)
kubectl exec -it deploy/app1 -n app1 -- bash
```

---

## Phase 5: Deploy a Node.js App

Same pattern as app1: Deployment + Service + Ingress. Will live in `apps/<app-name>/`.
Port 3000, healthcheck at `/healthcheck`.

### Health Check Deep Dive (3 Probes vs Swarm's 1)

| Swarm healthcheck field | K8s probe | What it does |
|---|---|---|
| `start_period: 30s` | `startupProbe` | Don't kill the pod while it's booting |
| `test: curl /healthcheck` | `livenessProbe` | Kill and restart if this fails |
| *(no equivalent)* | `readinessProbe` | Remove from load balancer if failing, but don't kill |
| `interval: 1m30s` | `periodSeconds: 90` | How often to check |
| `timeout: 30s` | `timeoutSeconds: 30` | Max wait per check |
| `retries: 5` | `failureThreshold: 5` | Failures before action |

The **readinessProbe** is the big win over Swarm. During a deploy, new pods only receive traffic after readiness passes. In Swarm, traffic hits containers immediately.

---

## Phase 6: Deploy a Python/Flask App

Same pattern: Deployment + Service + Ingress. Will live in `apps/<app-name>/`.
Port 5001, healthcheck at `/healthcheck`.

Every app follows the same 3-resource structure: **Deployment + Service + Ingress**.

---

## Phase 7: Clustered Databases

This is where Kubernetes truly surpasses Swarm. Your current Swarm databases are all single-instance. Kubernetes makes clustering practical with **StatefulSets** and **Helm operators**.

### Key Concept: StatefulSet vs Deployment

| | Deployment (for apps) | StatefulSet (for databases) |
|---|---|---|
| Pod names | Random: `app1-7d8f9-xk2lp` | Ordered: `mongodb-0`, `mongodb-1`, `mongodb-2` |
| Storage | Shared PVC | **Unique PVC per replica** (each gets its own disk) |
| Scaling | Start/stop in any order | Ordered: 0 first, then 1, then 2 |
| DNS | Only via Service | Each pod gets a **stable DNS name**: `mongodb-0.mongodb.databases.svc` |
| Use case | Stateless web apps | Databases, queues, anything with persistent identity |

---

### 7.1 Clustered MongoDB (3-Node ReplicaSet)

Your Swarm runs a single MongoDB. **Kubernetes** runs a 3-node ReplicaSet with Bitnami Helm chart:

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update

helm install mongodb bitnami/mongodb \
  --namespace databases \
  --create-namespace \
  --set architecture=replicaset \
  --set replicaCount=3 \
  --set auth.rootUser=mongo-rocks \
  --set auth.rootPassword=YOUR_SECURE_PASSWORD \
  --set persistence.size=20Gi \
  --set resources.limits.memory=1Gi \
  --set resources.requests.memory=512Mi
```

This creates:
- `mongodb-0`, `mongodb-1`, `mongodb-2` (StatefulSet pods)
- Each with its own 20Gi PVC (no shared storage)
- Automatic primary election
- Headless Service for internal DNS: `mongodb-0.mongodb-headless.databases.svc`

**Connection for your apps** (from `apps/app1/configmap.yaml`):
```env
MONGODB_HOST=mongodb-cluster.databases.svc
MONGODB_PORT=27017
MONGODB_DATABASE=app1
# MONGODB_USERNAME and MONGODB_PASSWORD are in apps/app1/secrets.yaml
```

**What you gain over Swarm**:
- Automatic failover (primary dies → secondary promoted in seconds)
- Read replicas (offload reads to secondaries)
- Per-node storage (no single disk bottleneck)

**Backup**: Use a K8s CronJob with `mongodump` (replaces your `CRON_SCHEDULE: 0 3 * * *` service). Will be created in `databases/mongodb/backup-cronjob.yaml` when needed.

---

### 7.2 Clustered Redis (3-Node Sentinel)

Your Swarm runs a single Redis. **Kubernetes** runs Redis with Sentinel (automatic failover).
Values file: `databases/redis/helm-values.yaml`

```bash
# Using values file (databases/redis/helm-values.yaml):
kubectl apply -f databases/redis/secrets.yaml
helm install redis-cluster oci://registry-1.docker.io/cloudpirates/redis \
  -f databases/redis/helm-values.yaml -n databases
```

This creates:
- 1 master + 2 replicas (3 pods total)
- 3 Sentinel processes monitoring the master
- If master dies, Sentinel promotes a replica within seconds
- `redis-master.databases.svc` always points to current master
- `redis-replicas.databases.svc` load-balances reads across replicas

**Connection for your Laravel apps** (from `apps/app1/configmap.yaml`):
```env
REDIS_HOST=redis-cluster.databases.svc
REDIS_PORT=6379
# REDIS_PASSWORD is in apps/app1/secrets.yaml
```

**What you gain over Swarm**:
- Automatic failover (master dies → replica promoted, no downtime)
- Read scaling (point cache reads to replicas)
- Persistent storage per node

---

### 7.3 Clustered MariaDB (Galera Cluster - 3 Nodes)

**Galera Cluster** = multi-master MySQL/MariaDB. Every node accepts reads AND writes. Data synchronously replicated across all nodes.

Install via Helm (or values file in `databases/mariadb/` when created). This creates:
- `mariadb-galera-0`, `mariadb-galera-1`, `mariadb-galera-2`
- Each with its own 20Gi PVC
- **Multi-master**: write to ANY node (unlike Redis/Mongo which have a single primary)
- Synchronous replication (no data loss on failover)
- `mariadb-galera.databases.svc` load-balances across all nodes

**Connection for your Laravel apps** (from `apps/app1/configmap.yaml`):
```env
DB_CONNECTION=mariadb
DB_HOST=mariadb-cluster.databases.svc
DB_PORT=3306
DB_DATABASE=app1
DB_USERNAME=root
# DB_PASSWORD is in apps/app1/secrets.yaml
```

**What you gain**:
- Zero-downtime database maintenance (take down one node, other two keep serving)
- Multi-master writes (any node accepts writes, no single point of failure)
- Automatic resync when a node recovers

**Backup**: Use a K8s CronJob with `mariadb-dump`. Will be created in `databases/mariadb/backup-cronjob.yaml` when needed.

---

### 7.4 Neo4j

Uses a **StatefulSet** (not Deployment) for stable storage. Will be created in `databases/neo4j/` when needed.

Key points:
- StatefulSet with `volumeClaimTemplates` for data, logs, plugins, import
- Ports: 7474 (HTTP browser UI) + 7687 (Bolt protocol)
- Auth via Secret, APOC plugin enabled
- Bolt TCP routing via Traefik `IngressRouteTCP` CRD with `HostSNI` matching

---

## Phase 8: Putting It All Together

### 8.1 Namespace Layout

```
databases/        ← MariaDB Galera, MongoDB ReplicaSet, Redis Sentinel, Neo4j
app1/             ← app1 (Laravel/Swoole on port 9000)
registry/         ← Private Docker registry credentials
traefik/          ← Ingress controller
cert-manager/     ← TLS automation
```

### 8.2 How Services Find Each Other

In Swarm, everything on `web2` network can talk. In K8s, every Service gets a DNS name:

```
<service-name>.<namespace>.svc.cluster.local
```

So your Laravel app connects to databases like (from `apps/app1/configmap.yaml`):
```env
DB_HOST=mariadb-cluster.databases.svc
REDIS_HOST=redis-cluster.databases.svc
MONGODB_HOST=mongodb-cluster.databases.svc
NEO4J_HOST=neo4j.databases.svc
```

Cross-namespace communication works by default. No explicit network attachment needed.

### 8.3 Complete Deploy Order

```bash
# 1. Infrastructure
kubectl apply -f registry/namespace.yaml
kubectl apply -f registry/credentials.yaml
helm install traefik traefik/traefik -n traefik --create-namespace ...
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace ...
kubectl apply -f infrastructure/cert-manager/cluster-issuer.yaml

# 2. Databases (clustered)
kubectl create namespace databases
helm install mariadb bitnami/mariadb-galera -n databases ...
helm install mongodb bitnami/mongodb -n databases ...
helm install redis-cluster oci://registry-1.docker.io/cloudpirates/redis -f databases/redis/helm-values.yaml -n databases
kubectl apply -f neo4j/

# 3. App namespace, secrets, config, and registry creds
kubectl apply -f apps/app1/namespace.yaml
kubectl apply -f apps/app1/secrets.yaml
kubectl apply -f apps/app1/configmap.yaml
# Create regcred in app1 namespace for private image pulls

# 4. Deploy the app
kubectl apply -f apps/app1/deployment.yaml

# 5. Verify everything
kubectl get pods -A                   # All pods should be Running
kubectl get ingress -A                # All domains listed
kubectl get pvc -A                    # All storage bound
```

### 8.4 Day-to-Day Operations Translation

| Task | Docker Swarm | Kubernetes |
|---|---|---|
| Deploy / update | `docker stack deploy -c stack.yaml fluent` | `kubectl apply -f apps/app1/` |
| Update image | Edit compose, redeploy | `kubectl set image deploy/app1 app1=new:tag -n app1` |
| Scale | `docker service scale fluent=10` | `kubectl scale deploy app1 --replicas=10 -n app1` |
| Rollback | `docker service rollback fluent` | `kubectl rollout undo deploy/app1 -n app1` |
| View rollout status | `docker service ps fluent` | `kubectl rollout status deploy/app1 -n app1` |
| Logs | `docker service logs fluent -f` | `kubectl logs -n app1 -l app=app1 -f` |
| Exec into container | `docker exec -it <id> bash` | `kubectl exec -it deploy/app1 -n app1 -- bash` |
| View all running | `docker service ls` | `kubectl get pods -A` |
| Restart a service | `docker service update --force fluent` | `kubectl rollout restart deploy/app1 -n app1` |
| Check resource usage | `docker stats` | `kubectl top pods -A` (needs metrics-server) |
| Remove everything | `docker stack rm fluent` | `kubectl delete namespace app1` |

---

## Phase 9: Multi-Environment (Prod vs Stage)

Your Swarm uses separate files (`prod/express.yml` vs `stage.yaml`). Kubernetes uses **Kustomize** (built into kubectl).

```
apps/app1/
├── base/                          # Shared definition
│   ├── kustomization.yaml
│   ├── deployment.yaml
│   ├── service.yaml
│   └── ingress.yaml
└── overlays/
    ├── production/                # Overrides for prod
    │   ├── kustomization.yaml
    │   └── patch.yaml             # Different image, replicas, memory
    └── staging/                   # Overrides for staging
        ├── kustomization.yaml
        └── patch.yaml             # Staging registry, fewer replicas
```

```bash
# Deploy production
kubectl apply -k apps/app1/overlays/production/

# Deploy staging
kubectl apply -k apps/app1/overlays/staging/
```

This directly replaces your pattern of having `deployments/fluent-stack/stack.yaml` (base) + `deployments/fluent-stack/prod/` (overrides) + `deployments/fluent-stack/stage.yaml` (staging).

---

## Quick Reference

### Concept Glossary

| Swarm | K8s | One-liner |
|---|---|---|
| Stack | Namespace | Group of related resources |
| Service | Deployment | Runs and manages containers |
| *(routing via labels)* | Service | Internal DNS/load balancing |
| *(routing via labels)* | Ingress | External HTTP routing |
| Task | Pod | One running container instance |
| Manager node | Control Plane | Cluster brain |
| Worker node | Worker Node | Runs workloads |
| `web2` overlay network | CNI (flat network) | All pods can talk by default |
| `docker secret` | Secret | Sensitive config |
| `.env` file | ConfigMap | Non-sensitive config |
| Bind mount | PersistentVolumeClaim | Storage request |
| Named volume | PVC + StorageClass | Auto-provisioned storage |
| `mode: global` | DaemonSet | One pod per node |
| Compose file | Manifest YAML | Declarative config |
| Docker socket | Kubernetes API + RBAC | Control plane access |

### Useful Commands for Learning

```bash
# Explain any resource (built-in docs)
kubectl explain deployment.spec.strategy
kubectl explain statefulset.spec.volumeClaimTemplates

# Visual cluster navigation
k9s

# Watch everything happen in real-time
kubectl get events -A --watch

# See what Helm installed
helm list -A
helm get values mongodb -n databases
```
