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
| Stack name (fluent-stack) | **Namespace** | Logical grouping, same idea |
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

Your `fluent` service in `deployments/fluent-stack/stack.yaml` becomes 3 separate YAML resources.

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

### 2.2 What Just Happened (vs Your Swarm Traefik)

Your Swarm `traefik-stack/stack.yaml` does this:
```yaml
# SWARM - what you have now
services:
  traefik:
    image: traefik:v3.6
    ports:
      - target: 80
        published: 80
        mode: host
      - target: 443
        published: 443
        mode: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro    # <-- reads Docker API
      - ./config/traefik.yaml:/etc/traefik/traefik.yaml:ro
```

The Helm chart does the same thing, but:
- No Docker socket needed - Traefik uses **Kubernetes API** instead
- Config is via Helm values instead of a mounted `traefik.yaml`
- TLS will be handled by **cert-manager** (installed next) instead of Traefik's built-in ACME

### 2.3 Install cert-manager (Replaces Traefik ACME)

In your Swarm config (`traefik-stack/config/traefik.yaml`), you have certificate resolvers for Let's Encrypt. In K8s, **cert-manager** is the standard way:

```bash
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set crds.enabled=true
```

Then create issuers:

```yaml
# cert-issuer.yaml
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@domain.com
    privateKeySecretRef:
      name: letsencrypt-prod-key
    solvers:
      - http01:
          ingress:
            class: traefik
```

```bash
kubectl apply -f cert-issuer.yaml
```

Now any Ingress with `cert-manager.io/cluster-issuer: letsencrypt-prod` annotation gets automatic TLS.

### 2.4 Security Headers (Translating Your headers.yaml)

Your `traefik-stack/config/headers.yaml` defines HSTS, CSP, XSS protection etc. In K8s with Traefik, use a **Middleware CRD**:

```yaml
# security-headers.yaml
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: security-headers
  namespace: traefik
spec:
  headers:
    stsSeconds: 31536000
    stsIncludeSubdomains: true
    stsPreload: true
    frameDeny: true
    contentTypeNosniff: true
    browserXssFilter: true
    referrerPolicy: strict-origin-when-cross-origin
    permissionsPolicy: "camera=(), microphone=(), geolocation=()"
```

Reference it in any Ingress with an annotation:
```yaml
annotations:
  traefik.ingress.kubernetes.io/router.middlewares: traefik-security-headers@kubernetescrd
```

---

## Phase 3: Secrets and ConfigMaps

### 3.1 Secrets (Replacing Docker Swarm External Secrets)

Your Swarm stacks declare secrets like this (`fluent-stack/stack.yaml`):
```yaml
# SWARM
secrets:
  fluent_app_key:
    external: true
  fluent_db_password:
    external: true
```

And you created them with `docker secret create fluent_app_key ./secret-file`.

**Kubernetes equivalent**:

```bash
# Create from command line (like docker secret create)
kubectl create secret generic fluent-secrets \
  --namespace=fluent \
  --from-literal=APP_KEY='base64:yourkey' \
  --from-literal=DB_PASSWORD='yourpassword' \
  --from-literal=MONGODB_PASSWORD='mongopass'
```

Or as YAML (for version control - values auto base64-encoded with `stringData`):
```yaml
# fluent-secrets.yaml
apiVersion: v1
kind: Secret
metadata:
  name: fluent-secrets
  namespace: fluent
type: Opaque
stringData:
  APP_KEY: "base64:yourkey"
  DB_PASSWORD: "yourpassword"
  DB_PASSWORD_ACT: "actpassword"
  POSTMARK_TOKEN: "yourtoken"
  PUSHER_APP_SECRET: "yoursecret"
  GOOGLE_CLIENT_SECRET: "googlesecret"
  MONGODB_PASSWORD: "mongopass"
```

**Using secrets in a Pod** - two options:

```yaml
# Option A: As env vars (most common in K8s)
containers:
  - name: fluent
    envFrom:
      - secretRef:
          name: fluent-secrets     # All keys injected as env vars

# Option B: As files at /run/secrets/ (identical to your Swarm behavior)
containers:
  - name: fluent
    volumeMounts:
      - name: secrets
        mountPath: /run/secrets
        readOnly: true
volumes:
  - name: secrets
    secret:
      secretName: fluent-secrets
```

### 3.2 ConfigMaps (Replacing .env Files)

Your Swarm stacks use `env_file` (`fluent-stack/stack.yaml`):
```yaml
# SWARM
env_file:
  - ${HOME}/config/env/fluent.env
```

**Kubernetes**:
```bash
# Create ConfigMap directly from your .env file
kubectl create configmap fluent-config \
  --namespace=fluent \
  --from-env-file=./fluent.env
```

Use it:
```yaml
containers:
  - name: fluent
    envFrom:
      - configMapRef:
          name: fluent-config      # Non-secret env vars
      - secretRef:
          name: fluent-secrets     # Secret env vars
```

### 3.3 Private Registry Auth

Your images come from `hub.connoisseur-suite.co.uk`. K8s needs credentials to pull:

```bash
kubectl create secret docker-registry regcred \
  --namespace=fluent \
  --docker-server=hub.connoisseur-suite.co.uk \
  --docker-username=youruser \
  --docker-password=yourpass
```

Referenced in Deployments:
```yaml
spec:
  imagePullSecrets:
    - name: regcred
```

---

## Phase 4: Deploy a Laravel App (fluent)

This is your most representative app. Translating `deployments/fluent-stack/stack.yaml`.

### 4.1 Swarm vs Kubernetes Side-by-Side

**Your Swarm definition**:
```yaml
# SWARM - deployments/fluent-stack/stack.yaml
services:
  fluent:
    image: hub.connoisseur-suite.co.uk/production/v1.3.52
    networks: [web2]
    deploy:
      replicas: 8
      update_config:
        parallelism: 0
        order: start-first
        failure_action: rollback
        monitor: 45s
      resources:
        limits:
          memory: 2.5G
      placement:
        constraints: [node.role == manager]
    env_file: [${HOME}/config/env/fluent.env]
    secrets: [fluent_app_key, fluent_db_password, ...]
    volumes: [/mnt/data/fluent/data:/app/storage]
```

**Kubernetes equivalent** (3 resources):

```yaml
# fluent-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fluent
  namespace: fluent
spec:
  replicas: 8
  selector:
    matchLabels:
      app: fluent
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxSurge: 1           # order: start-first → start new before killing old
      maxUnavailable: 0     # parallelism: 0 → never have fewer than current
  minReadySeconds: 45       # monitor: 45s → wait 45s before considering "ready"
  template:
    metadata:
      labels:
        app: fluent
    spec:
      containers:
        - name: fluent
          image: hub.connoisseur-suite.co.uk/production/v1.3.52
          ports:
            - containerPort: 80
          envFrom:
            - configMapRef:
                name: fluent-config
            - secretRef:
                name: fluent-secrets
          volumeMounts:
            - name: storage
              mountPath: /app/storage
          resources:
            limits:
              memory: "2560Mi"     # 2.5G
            requests:
              memory: "512Mi"      # Guaranteed minimum (new concept - Swarm doesn't have this)
              cpu: "250m"          # 0.25 CPU guaranteed
          readinessProbe:          # NEW - Swarm doesn't have this
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 10
            periodSeconds: 5
          livenessProbe:
            httpGet:
              path: /
              port: 80
            initialDelaySeconds: 30
            periodSeconds: 30
      volumes:
        - name: storage
          persistentVolumeClaim:
            claimName: fluent-storage
      imagePullSecrets:
        - name: regcred
---
# fluent-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: fluent
  namespace: fluent
spec:
  selector:
    app: fluent
  ports:
    - port: 80
      targetPort: 80
---
# fluent-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fluent
  namespace: fluent
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
    traefik.ingress.kubernetes.io/router.middlewares: traefik-security-headers@kubernetescrd
spec:
  ingressClassName: traefik
  tls:
    - hosts: [connoisseur-suite.com]
      secretName: fluent-tls
  rules:
    - host: connoisseur-suite.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: fluent
                port:
                  number: 80
```

### 4.2 Storage (PVC)

Your Swarm bind mount `/mnt/data/fluent/data:/app/storage` becomes:

```yaml
# fluent-pvc.yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: fluent-storage
  namespace: fluent
spec:
  accessModes: [ReadWriteOnce]
  resources:
    requests:
      storage: 50Gi
```

On a cloud provider (GKE/EKS), this auto-provisions a disk. On bare metal, you'd pre-create a PersistentVolume pointing to `/mnt/data/fluent/data`.

### 4.3 The Queue Worker (fluent-worker)

Your Swarm `fluent-worker` uses a custom entrypoint. Same pattern, just a separate Deployment with no Service/Ingress:

```yaml
# fluent-worker-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fluent-worker
  namespace: fluent
spec:
  replicas: 2
  selector:
    matchLabels:
      app: fluent-worker
  template:
    metadata:
      labels:
        app: fluent-worker
    spec:
      containers:
        - name: worker
          image: hub.connoisseur-suite.co.uk/production/fluent-worker:v1.3.52
          command: ["php", "artisan", "queue:work"]
          envFrom:
            - configMapRef:
                name: fluent-config
            - secretRef:
                name: fluent-secrets
          resources:
            limits:
              memory: "500Mi"
      imagePullSecrets:
        - name: regcred
      # No Service or Ingress - workers don't receive HTTP traffic
```

### 4.4 Deploy It

```bash
kubectl create namespace fluent
kubectl apply -f fluent-secrets.yaml
kubectl apply -f fluent-config.yaml        # from your .env
kubectl apply -f fluent-pvc.yaml
kubectl apply -f fluent-deployment.yaml
kubectl apply -f fluent-worker-deployment.yaml

# Watch pods come up
kubectl get pods -n fluent -w

# Check logs
kubectl logs -n fluent -l app=fluent --tail=50 -f

# Exec into a pod (like docker exec)
kubectl exec -it deploy/fluent -n fluent -- bash
```

---

## Phase 5: Deploy a Node.js App (fluent-widget)

Translating from `deployments/fluent-stack/stack.yaml` - the `fluent-widget` service.

### 5.1 Swarm Original

```yaml
# SWARM
fluent-widget:
  image: hub.connoisseur-suite.co.uk/production/fluent-widget:v1.0.23
  networks: [web2]
  deploy:
    replicas: 3
    resources:
      limits:
        memory: 2G
    update_config:
      parallelism: 0
      order: start-first
  healthcheck:
    test: ["CMD", "curl", "-f", "http://0.0.0.0:3000/healthcheck"]
    interval: 1m30s
    timeout: 30s
    retries: 5
    start_period: 30s
```

### 5.2 Kubernetes Translation

```yaml
# widget-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fluent-widget
  namespace: fluent
spec:
  replicas: 3
  selector:
    matchLabels:
      app: fluent-widget
  strategy:
    rollingUpdate:
      maxSurge: 1
      maxUnavailable: 0
  template:
    metadata:
      labels:
        app: fluent-widget
    spec:
      containers:
        - name: widget
          image: hub.connoisseur-suite.co.uk/production/fluent-widget:v1.0.23
          ports:
            - containerPort: 3000
          envFrom:
            - configMapRef:
                name: fluent-widget-config
          resources:
            limits:
              memory: "2Gi"
            requests:
              memory: "512Mi"
              cpu: "250m"
          # Your Swarm healthcheck becomes 3 probes:
          startupProbe:                    # Replaces start_period: 30s
            httpGet:
              path: /healthcheck
              port: 3000
            periodSeconds: 5
            failureThreshold: 6            # 6 x 5s = 30s startup window
          readinessProbe:                  # NEW: controls load balancer routing
            httpGet:
              path: /healthcheck
              port: 3000
            periodSeconds: 10
            failureThreshold: 3
          livenessProbe:                   # Replaces healthcheck test
            httpGet:
              path: /healthcheck
              port: 3000
            periodSeconds: 90              # interval: 1m30s
            timeoutSeconds: 30             # timeout: 30s
            failureThreshold: 5            # retries: 5
      imagePullSecrets:
        - name: regcred
---
apiVersion: v1
kind: Service
metadata:
  name: fluent-widget
  namespace: fluent
spec:
  selector:
    app: fluent-widget
  ports:
    - port: 3000
      targetPort: 3000
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fluent-widget
  namespace: fluent
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts: [widget.connoisseur-suite.com]
      secretName: widget-tls
  rules:
    - host: widget.connoisseur-suite.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: fluent-widget
                port:
                  number: 3000
```

### 5.3 Health Check Deep Dive (3 Probes vs Swarm's 1)

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

## Phase 6: Deploy a Python/Flask App (fluent-flask)

Translating from `deployments/fluent-stack/stack.yaml`.

### 6.1 Swarm Original

```yaml
# SWARM
fluent-flask:
  image: hub.connoisseur-suite.co.uk/production/fluent-flask:v1.0.2
  networks: [web2]
  deploy:
    replicas: 3
    resources:
      limits:
        memory: 1G
  env_file: [${HOME}/config/env/fluent-flask.env]
  volumes: [/mnt/data/fluent/flask/data:/app/logs]
  healthcheck:
    test: ["CMD", "curl", "-f", "http://0.0.0.0:5001/healthcheck"]
    interval: 1m30s
    retries: 5
    start_period: 30s
```

### 6.2 Kubernetes Translation

```yaml
# flask-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fluent-flask
  namespace: fluent
spec:
  replicas: 3
  selector:
    matchLabels:
      app: fluent-flask
  template:
    metadata:
      labels:
        app: fluent-flask
    spec:
      containers:
        - name: flask
          image: hub.connoisseur-suite.co.uk/production/fluent-flask:v1.0.2
          ports:
            - containerPort: 5001
          envFrom:
            - configMapRef:
                name: fluent-flask-config
          volumeMounts:
            - name: logs
              mountPath: /app/logs
          resources:
            limits:
              memory: "1Gi"
            requests:
              memory: "256Mi"
              cpu: "100m"
          startupProbe:
            httpGet:
              path: /healthcheck
              port: 5001
            periodSeconds: 5
            failureThreshold: 6
          readinessProbe:
            httpGet:
              path: /healthcheck
              port: 5001
            periodSeconds: 10
          livenessProbe:
            httpGet:
              path: /healthcheck
              port: 5001
            periodSeconds: 90
            failureThreshold: 5
      volumes:
        - name: logs
          persistentVolumeClaim:
            claimName: fluent-flask-logs
      imagePullSecrets:
        - name: regcred
---
apiVersion: v1
kind: Service
metadata:
  name: fluent-flask
  namespace: fluent
spec:
  selector:
    app: fluent-flask
  ports:
    - port: 5001
      targetPort: 5001
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: fluent-flask
  namespace: fluent
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts: [flask.connoisseur-suite.com]
      secretName: flask-tls
  rules:
    - host: flask.connoisseur-suite.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: fluent-flask
                port:
                  number: 5001
```

By now you see the pattern. Every app follows the same 3-resource structure: **Deployment + Service + Ingress**.

---

## Phase 7: Clustered Databases

This is where Kubernetes truly surpasses Swarm. Your current Swarm databases are all single-instance. Kubernetes makes clustering practical with **StatefulSets** and **Helm operators**.

### Key Concept: StatefulSet vs Deployment

| | Deployment (for apps) | StatefulSet (for databases) |
|---|---|---|
| Pod names | Random: `fluent-7d8f9-xk2lp` | Ordered: `mongodb-0`, `mongodb-1`, `mongodb-2` |
| Storage | Shared PVC | **Unique PVC per replica** (each gets its own disk) |
| Scaling | Start/stop in any order | Ordered: 0 first, then 1, then 2 |
| DNS | Only via Service | Each pod gets a **stable DNS name**: `mongodb-0.mongodb.databases.svc` |
| Use case | Stateless web apps | Databases, queues, anything with persistent identity |

---

### 7.1 Clustered MongoDB (3-Node ReplicaSet)

Your Swarm runs a single MongoDB (`deployments/mongo-stack/stack.yaml`):
```yaml
# SWARM - single instance
services:
  mongodb:
    image: mongo:8.2.3
    volumes: [mongodb_data:/data/db]
    deploy:
      placement:
        constraints: [node.role == manager]
```

**Kubernetes - 3-node ReplicaSet with Bitnami Helm chart**:

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

**Connection string for your apps**:
```
mongodb://mongo-rocks:PASSWORD@mongodb-0.mongodb-headless.databases.svc:27017,mongodb-1.mongodb-headless.databases.svc:27017,mongodb-2.mongodb-headless.databases.svc:27017/fluent?replicaSet=rs0&authSource=admin
```

**What you gain over Swarm**:
- Automatic failover (primary dies → secondary promoted in seconds)
- Read replicas (offload reads to secondaries)
- Per-node storage (no single disk bottleneck)

**Backup CronJob** (replaces your `mongodump` service with `CRON_SCHEDULE: 0 3 * * *`):
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mongodb-backup
  namespace: databases
spec:
  schedule: "0 3 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: mongodump
              image: mongo:8.2.3
              command:
                - /bin/sh
                - -c
                - >
                  mongodump
                  --uri="mongodb://mongo-rocks:$(MONGO_PASSWORD)@mongodb-0.mongodb-headless:27017/admin?replicaSet=rs0"
                  --out=/backup/$(date +%Y%m%d-%H%M%S)
              env:
                - name: MONGO_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: mongodb
                      key: mongodb-root-password
              volumeMounts:
                - name: backup
                  mountPath: /backup
          restartPolicy: OnFailure
          volumes:
            - name: backup
              persistentVolumeClaim:
                claimName: mongodb-backup
```

---

### 7.2 Clustered Redis (3-Node Sentinel)

Your Swarm runs a single Redis (`deployments/redis-stack/prod/redis.yml`):
```yaml
# SWARM - single instance
services:
  redis:
    image: redis:8.4-alpine
    command: redis-server --appendonly yes
    deploy:
      resources:
        limits:
          memory: 1G
    healthcheck:
      test: ["CMD", "redis-cli", "ping"]
```

**Kubernetes - Redis with Sentinel (automatic failover)**:

```bash
helm install redis bitnami/redis \
  --namespace databases \
  --set architecture=replication \
  --set replica.replicaCount=2 \
  --set sentinel.enabled=true \
  --set sentinel.quorum=2 \
  --set master.persistence.size=8Gi \
  --set replica.persistence.size=8Gi \
  --set master.resources.limits.memory=1Gi \
  --set replica.resources.limits.memory=1Gi \
  --set auth.password=YOUR_REDIS_PASSWORD
```

This creates:
- 1 master + 2 replicas (3 pods total)
- 3 Sentinel processes monitoring the master
- If master dies, Sentinel promotes a replica within seconds
- `redis-master.databases.svc` always points to current master
- `redis-replicas.databases.svc` load-balances reads across replicas

**Connection for your Laravel apps**:
```env
REDIS_HOST=redis-master.databases.svc
REDIS_PASSWORD=YOUR_REDIS_PASSWORD
REDIS_PORT=6379
```

**What you gain over Swarm**:
- Automatic failover (master dies → replica promoted, no downtime)
- Read scaling (point cache reads to replicas)
- Persistent storage per node

---

### 7.3 Clustered MariaDB (Galera Cluster - 3 Nodes)

Your Swarm doesn't have MariaDB clustering. This is new and powerful.

**Galera Cluster** = multi-master MySQL/MariaDB. Every node accepts reads AND writes. Data synchronously replicated across all nodes.

```bash
helm install mariadb bitnami/mariadb-galera \
  --namespace databases \
  --set replicaCount=3 \
  --set rootUser.password=YOUR_ROOT_PASSWORD \
  --set db.name=fluent \
  --set db.user=fluent \
  --set db.password=YOUR_DB_PASSWORD \
  --set persistence.size=20Gi \
  --set resources.limits.memory=1Gi \
  --set resources.requests.memory=512Mi \
  --set galera.mariabackup.password=YOUR_BACKUP_PASSWORD
```

This creates:
- `mariadb-galera-0`, `mariadb-galera-1`, `mariadb-galera-2`
- Each with its own 20Gi PVC
- **Multi-master**: write to ANY node (unlike Redis/Mongo which have a single primary)
- Synchronous replication (no data loss on failover)
- `mariadb-galera.databases.svc` load-balances across all nodes

**Connection for your Laravel apps**:
```env
DB_CONNECTION=mysql
DB_HOST=mariadb-galera.databases.svc
DB_PORT=3306
DB_DATABASE=fluent
DB_USERNAME=fluent
DB_PASSWORD=YOUR_DB_PASSWORD
```

**What you gain**:
- Zero-downtime database maintenance (take down one node, other two keep serving)
- Multi-master writes (any node accepts writes, no single point of failure)
- Automatic resync when a node recovers

**MariaDB Backup CronJob**:
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: mariadb-backup
  namespace: databases
spec:
  schedule: "0 2 * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
            - name: mariadb-backup
              image: mariadb:11
              command:
                - /bin/sh
                - -c
                - >
                  mariadb-dump -h mariadb-galera.databases.svc
                  -u root -p"$(MYSQL_ROOT_PASSWORD)"
                  --all-databases --single-transaction
                  > /backup/all-databases-$(date +%Y%m%d-%H%M%S).sql
              env:
                - name: MYSQL_ROOT_PASSWORD
                  valueFrom:
                    secretKeyRef:
                      name: mariadb-galera
                      key: mariadb-root-password
              volumeMounts:
                - name: backup
                  mountPath: /backup
          restartPolicy: OnFailure
          volumes:
            - name: backup
              persistentVolumeClaim:
                claimName: mariadb-backup
```

---

### 7.4 Neo4j

Your Swarm Neo4j (`deployments/neo4j/stack.yml`):
```yaml
# SWARM
services:
  neo4j:
    image: neo4j:2025.07.1
    deploy:
      resources:
        limits:
          memory: 1G
    secrets: [neo4j_auth_file]
    environment:
      - NEO4J_PLUGINS=["apoc"]
      - NEO4J_AUTH_FILE=/run/secrets/neo4j_auth_file
    volumes:
      - /mnt/data/neo4j/data:/data
      - /mnt/data/neo4j/logs:/logs
      - /mnt/data/neo4j/plugin:/plugins
      - /mnt/data/neo4j/import:/var/lib/neo4j/import
```

**Kubernetes** (StatefulSet for stable storage):

```yaml
# neo4j-secret.yaml
apiVersion: v1
kind: Secret
metadata:
  name: neo4j-auth
  namespace: databases
stringData:
  NEO4J_AUTH: "neo4j/YOUR_PASSWORD"
---
# neo4j-statefulset.yaml
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: neo4j
  namespace: databases
spec:
  serviceName: neo4j
  replicas: 1
  selector:
    matchLabels:
      app: neo4j
  template:
    metadata:
      labels:
        app: neo4j
    spec:
      containers:
        - name: neo4j
          image: neo4j:2025.07.1
          ports:
            - containerPort: 7474
              name: http
            - containerPort: 7687
              name: bolt
          env:
            - name: NEO4J_AUTH
              valueFrom:
                secretKeyRef:
                  name: neo4j-auth
                  key: NEO4J_AUTH
            - name: NEO4J_PLUGINS
              value: '["apoc"]'
            - name: NEO4J_dbms_security_procedures_unrestricted
              value: "apoc.import.csv"
            - name: NEO4J_apoc_import_file_enabled
              value: "true"
            - name: NEO4J_apoc_export_file_enabled
              value: "true"
          volumeMounts:
            - name: data
              mountPath: /data
            - name: logs
              mountPath: /logs
            - name: plugins
              mountPath: /plugins
            - name: import
              mountPath: /var/lib/neo4j/import
          resources:
            limits:
              memory: "1Gi"
            requests:
              memory: "512Mi"
          readinessProbe:
            httpGet:
              path: /
              port: 7474
            initialDelaySeconds: 30
            periodSeconds: 10
  volumeClaimTemplates:
    - metadata:
        name: data
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 20Gi
    - metadata:
        name: logs
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 5Gi
    - metadata:
        name: plugins
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 1Gi
    - metadata:
        name: import
      spec:
        accessModes: [ReadWriteOnce]
        resources:
          requests:
            storage: 10Gi
---
# neo4j-service.yaml (internal access)
apiVersion: v1
kind: Service
metadata:
  name: neo4j
  namespace: databases
spec:
  selector:
    app: neo4j
  ports:
    - name: http
      port: 7474
      targetPort: 7474
    - name: bolt
      port: 7687
      targetPort: 7687
---
# neo4j-ingress.yaml (browser UI)
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: neo4j
  namespace: databases
  annotations:
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: traefik
  tls:
    - hosts: [neo4j.connoisseur-suite.com]
      secretName: neo4j-tls
  rules:
    - host: neo4j.connoisseur-suite.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: neo4j
                port:
                  number: 7474
```

**Bolt TCP routing** (your Swarm exposes port 7687 via Traefik TCP). In K8s with Traefik CRD:

```yaml
# neo4j-bolt-route.yaml
apiVersion: traefik.io/v1alpha1
kind: IngressRouteTCP
metadata:
  name: neo4j-bolt
  namespace: databases
spec:
  entryPoints: [websecure]
  routes:
    - match: HostSNI(`bolt.neo4j.connoisseur-suite.com`)
      services:
        - name: neo4j
          port: 7687
  tls:
    passthrough: true
```

---

## Phase 8: Putting It All Together

### 8.1 Namespace Layout

```
databases/        ← MariaDB Galera, MongoDB ReplicaSet, Redis Sentinel, Neo4j
fluent/           ← fluent (Laravel), fluent-worker, fluent-widget (Node), fluent-flask (Python)
traefik/          ← Ingress controller
cert-manager/     ← TLS automation
```

### 8.2 How Services Find Each Other

In Swarm, everything on `web2` network can talk. In K8s, every Service gets a DNS name:

```
<service-name>.<namespace>.svc.cluster.local
```

So your Laravel app connects to databases like:
```env
# fluent.env → fluent-config ConfigMap
DB_HOST=mariadb-galera.databases.svc
REDIS_HOST=redis-master.databases.svc
MONGO_HOST=mongodb-headless.databases.svc
NEO4J_HOST=neo4j.databases.svc
```

Cross-namespace communication works by default. No explicit network attachment needed.

### 8.3 Complete Deploy Order

```bash
# 1. Infrastructure
kubectl create namespace databases
kubectl create namespace fluent
helm install traefik traefik/traefik -n traefik --create-namespace ...
helm install cert-manager jetstack/cert-manager -n cert-manager --create-namespace ...
kubectl apply -f cert-issuer.yaml

# 2. Databases (clustered)
helm install mariadb bitnami/mariadb-galera -n databases ...
helm install mongodb bitnami/mongodb -n databases ...
helm install redis bitnami/redis -n databases ...
kubectl apply -f neo4j/

# 3. Secrets and config
kubectl apply -f fluent-secrets.yaml
kubectl apply -f fluent-config.yaml

# 4. Apps
kubectl apply -f fluent/              # Laravel
kubectl apply -f fluent-worker/       # Queue worker
kubectl apply -f fluent-widget/       # Node.js
kubectl apply -f fluent-flask/        # Python

# 5. Verify everything
kubectl get pods -A                   # All pods should be Running
kubectl get ingress -A                # All domains listed
kubectl get pvc -A                    # All storage bound
```

### 8.4 Day-to-Day Operations Translation

| Task | Docker Swarm | Kubernetes |
|---|---|---|
| Deploy / update | `docker stack deploy -c stack.yaml fluent` | `kubectl apply -f fluent/` |
| Update image | Edit compose, redeploy | `kubectl set image deploy/fluent fluent=new:tag -n fluent` |
| Scale | `docker service scale fluent=10` | `kubectl scale deploy fluent --replicas=10 -n fluent` |
| Rollback | `docker service rollback fluent` | `kubectl rollout undo deploy/fluent -n fluent` |
| View rollout status | `docker service ps fluent` | `kubectl rollout status deploy/fluent -n fluent` |
| Logs | `docker service logs fluent -f` | `kubectl logs -n fluent -l app=fluent -f` |
| Exec into container | `docker exec -it <id> bash` | `kubectl exec -it deploy/fluent -n fluent -- bash` |
| View all running | `docker service ls` | `kubectl get pods -A` |
| Restart a service | `docker service update --force fluent` | `kubectl rollout restart deploy/fluent -n fluent` |
| Check resource usage | `docker stats` | `kubectl top pods -A` (needs metrics-server) |
| Remove everything | `docker stack rm fluent` | `kubectl delete namespace fluent` |

---

## Phase 9: Multi-Environment (Prod vs Stage)

Your Swarm uses separate files (`prod/express.yml` vs `stage.yaml`). Kubernetes uses **Kustomize** (built into kubectl).

```
fluent/
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
kubectl apply -k fluent/overlays/production/

# Deploy staging
kubectl apply -k fluent/overlays/staging/
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
