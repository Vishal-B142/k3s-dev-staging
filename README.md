# k3s-dev-staging

> Self-hosted Kubernetes cluster on VPS using k3s — Traefik Ingress, MetalLB, Blue/Green deployments, Prometheus + Grafana + Loki observability, HPA autoscaling, and Headlamp dashboard. Built and operated in production.

Part of a two-tier Kubernetes strategy:

| Repo | Environment | Platform | Status |
|---|---|---|---|
| **k3s-dev-staging** (this repo) | Dev & Staging | k3s on VPS | ✅ Live |
| [eks-production](https://github.com/Vishal-B142/eks-production) | Production | AWS EKS | 🔄 In Progress |

---

## Infrastructure Overview

| Component | Technology | Status |
|---|---|---|
| Kubernetes | k3s v1.34 | Running |
| Container Registry | AWS ECR | Active |
| App CI/CD | Jenkins (Jenkinsfile) | Active — triggers on every git push |
| Infra CI/CD | Jenkins (Jenkinsfile.infra) | Active — manual trigger |
| Load Balancer | MetalLB v0.14.5 | Active |
| Ingress | Traefik v3.6.7 | Active — replaced nginx hostNetwork |
| SSL | Let's Encrypt (certbot) | Active |
| Deployments | Blue/Green slots | Active — zero downtime |
| Metrics | Prometheus | Active |
| Dashboards | Grafana | Active |
| Logs | Loki + Promtail | Active — connected to Grafana |
| K8s Dashboard | Headlamp | Active |
| Auto-scaling | HPA (CPU + Memory) | Active — all services |

---


## Architecture Diagram

```
                         Internet
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│  kube-system                                                     │
│                                                                  │
│  ┌─────────────────────┐   ┌─────────────────────┐              │
│  │      MetalLB        │──▶│    Traefik v3.6.7   │  CoreDNS     │
│  │  Assigns VPS IP     │   │  Ingress controller │  metrics-    │
│  │  to Traefik LB svc  │   │  HTTP → HTTPS redir │  server      │
│  └─────────────────────┘   └──────────┬──────────┘              │
└──────────────────────────────────────  │  ───────────────────────┘
                                         │  Host-header routing
                                         ▼
┌──────────────────────────────────────────────────────────────────┐
│  app namespace                                                   │
│                                                                  │
│          Blue / Green deployment pair (per service)             │
│  ┌───────────────────────┐       ┌───────────────────────┐      │
│  │   -blue  (active)     │  ──▶  │   -green  (idle)      │      │
│  │   replicas = 1        │       │   replicas = 0        │      │
│  │   serving traffic     │       │   ready to receive    │      │
│  └───────────────────────┘       └───────────────────────┘      │
│                                                                  │
│   Jenkins deploy sequence:                                       │
│   1. Scale up green  →  2. Wait readiness  →  3. Patch selector  │
│   4. Scale down blue     (auto-rollback if step 2 fails)        │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  HPA  (all services)                                      │  │
│  │  Public-facing: CPU > 60%, Mem > 75%  → scale up          │  │
│  │  Internal:      CPU > 70%, Mem > 80%  → scale up  max=5   │  │
│  └───────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
         ▲ Scrapes pod metrics every 15s
         │
┌────────┴──────────────────────────┐   ┌────────────────────────┐
│  monitoring namespace             │   │  headlamp namespace    │
│                                   │   │                        │
│  ┌──────────────┐  ┌────────────┐ │   │  Headlamp              │
│  │  Prometheus  │─▶│  Grafana   │ │   │  Web K8s dashboard     │
│  │  + Alertmgr  │  │  + Loki ds │ │   │  Pods / logs / shell   │
│  └──────────────┘  └────────────┘ │   └────────────────────────┘
│  ┌──────────────────────────────┐ │
│  │  Loki  +  Promtail           │ │   ┌────────────────────────┐
│  │  Promtail DaemonSet on node  │ │   │  cert-manager          │
│  │  Ships logs → Loki gateway   │ │   │  Let's Encrypt TLS     │
│  │  Grafana reads loki-gateway  │ │   │  Auto-renews all certs  │
│  └──────────────────────────────┘ │   └────────────────────────┘
└───────────────────────────────────┘
         ▲ Image pull (ECR token refreshed by Jenkins)
         │
┌────────┴─────────────┐
│   AWS ECR            │
│   ap-south-1         │
│   Container registry │
└──────────────────────┘
```

## Architecture (ASCII reference)

```
Internet
    |
    v
VPS Public IP (MetalLB assigns VPS IP to Traefik LoadBalancer)
    |
    v
Traefik Ingress (port 8000/HTTP and 8443/HTTPS)
    |
    +-- redirect-https Middleware: HTTP -> HTTPS 301 for all domains
    |
    v  (matches Ingress rule by Host header)
Kubernetes Service (e.g. gateway-service:8007)
    |
    v  (selector: app=gateway-service, slot=blue)
Active Blue Pod (green pod is idle at 0 replicas)
    |
    v  (HPA watches CPU/memory every 15 seconds)
Scale up if CPU > threshold -> new pod added to active slot
```

### Namespaces

| Namespace | Contains | Access |
|---|---|---|
| `app` | N services (blue/green), Ingress, HPA, Middleware | Public via Traefik |
| `monitoring` | Prometheus, Grafana, Loki, Promtail, Alertmanager | Internal dashboard URL |
| `headlamp` | Headlamp dashboard | Internal dashboard URL |
| `kube-system` | Traefik, MetalLB, metrics-server, CoreDNS | Internal only |

---

## Repo Structure

```
k3s-dev-staging/
├── Jenkinsfile                  # App pipeline — build + blue/green deploy
├── Jenkinsfile.infra            # Infra pipeline — monitoring + headlamp
├── k3s/
│   ├── deployments.yaml        # N services as blue/green Deployment pairs
│   ├── ingress.yaml            # Traefik Ingress + Middleware rules
│   └── hpa.yaml                # HorizontalPodAutoscaler for all services
└── monitoring/
    ├── monitoring-values.yaml  # Prometheus + Grafana Helm values
    ├── loki-values.yaml        # Loki Helm values
    ├── promtail-values.yaml    # Promtail Helm values
    ├── monitoring-ingress.yaml # Grafana Traefik ingress
    └── headlamp-ingress.yaml   # Headlamp Traefik ingress
```

---

## Key Design Decisions

### nginx → Traefik (Why We Switched)

The original setup used `nginx` with `hostNetwork: true`, binding ports 80/443 directly on the VPS. This was replaced with Traefik + MetalLB.

| nginx (old) | Traefik (new) | Reason |
|---|---|---|
| `hostNetwork: true` | MetalLB LoadBalancer service | Proper Kubernetes networking |
| Manual SSL config | cert-manager + Let's Encrypt | Auto-renewing TLS |
| No WebSocket support | Native WebSocket | No extra config needed |
| Config files | Kubernetes Ingress resources | Version-controlled in Git |

### Blue/Green Deployments

Every service has two Deployment slots — `-blue` (active, replicas=1) and `-green` (idle, replicas=0). Jenkins switches traffic between them with zero downtime.

**Deploy sequence:**
1. Read active slot annotation from Service
2. Set new image on the **inactive** slot
3. Scale inactive slot up → wait for readiness
4. Patch Service selector to point to new slot
5. Scale old slot down

If step 3 fails (pod unhealthy), steps 4 and 5 never run — old slot stays live automatically.

---


## Architecture Diagram

```
                         Internet
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────┐
│  kube-system                                                     │
│                                                                  │
│  ┌─────────────────────┐   ┌─────────────────────┐              │
│  │      MetalLB        │──▶│    Traefik v3.6.7   │  CoreDNS     │
│  │  Assigns VPS IP     │   │  Ingress controller │  metrics-    │
│  │  to Traefik LB svc  │   │  HTTP→HTTPS redir   │  server      │
│  └─────────────────────┘   └──────────┬──────────┘              │
└─────────────────────────────────────── │ ────────────────────────┘
                                         │  Host-header routing
                                         ▼
┌──────────────────────────────────────────────────────────────────┐
│  app namespace                                                   │
│                                                                  │
│          Blue / Green deployment pair (per service)             │
│  ┌───────────────────────┐       ┌───────────────────────┐      │
│  │   -blue  (active)     │  ──▶  │   -green  (idle)      │      │
│  │   replicas = 1        │       │   replicas = 0        │      │
│  │   serving traffic     │       │   ready to receive    │      │
│  └───────────────────────┘       └───────────────────────┘      │
│                                                                  │
│   Deploy: scale up green → wait readiness → patch selector       │
│           scale down blue  (auto-rollback if readiness fails)   │
│                                                                  │
│  ┌───────────────────────────────────────────────────────────┐  │
│  │  HPA  (all services)   max replicas = 5                   │  │
│  │  Public:  CPU > 60%, Memory > 75%  →  scale up            │  │
│  │  Internal: CPU > 70%, Memory > 80% →  scale up            │  │
│  └───────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
         ▲ Scrapes pod metrics
         │
┌────────┴──────────────────────────┐   ┌────────────────────────┐
│  monitoring namespace             │   │  headlamp namespace    │
│  ┌──────────────┐  ┌────────────┐ │   │  Web K8s dashboard     │
│  │  Prometheus  │─▶│  Grafana   │ │   │  Pods / logs / shell   │
│  │  + Alertmgr  │  │  + Loki ds │ │   └────────────────────────┘
│  └──────────────┘  └────────────┘ │
│  ┌──────────────────────────────┐ │   ┌────────────────────────┐
│  │  Loki  +  Promtail DaemonSet │ │   │  cert-manager          │
│  │  Ships pod logs → Loki gw    │ │   │  Let's Encrypt TLS     │
│  │  Grafana reads loki-gateway  │ │   │  Auto-renews all certs │
│  └──────────────────────────────┘ │   └────────────────────────┘
└───────────────────────────────────┘
         ▲ Image pull
         │
┌────────┴──────────┐
│   AWS ECR         │
│   Container imgs  │
└───────────────────┘
```

## Quick Start

```bash
# 1. Install k3s — disable built-in Traefik (we use our own)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -

# 2. Set kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 3. Install MetalLB
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.5/config/manifests/metallb-native.yaml
kubectl apply -f k3s/metallb-config.yaml

# 4. Install Traefik via Helm
helm repo add traefik https://traefik.github.io/charts && helm repo update
helm install traefik traefik/traefik -n kube-system

# 5. Install cert-manager
helm repo add jetstack https://charts.jetstack.io && helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager --create-namespace --set installCRDs=true

# 6. Apply app manifests
kubectl apply -f k3s/deployments.yaml
kubectl apply -f k3s/ingress.yaml
kubectl apply -f k3s/hpa.yaml

# 7. Install monitoring stack
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm upgrade --install monitoring prometheus-community/kube-prometheus-stack \
  -n monitoring --create-namespace \
  -f monitoring/monitoring-values.yaml --atomic=false

# 8. Install Loki + Promtail
helm repo add grafana https://grafana.github.io/helm-charts
helm upgrade --install loki grafana/loki -n monitoring -f monitoring/loki-values.yaml
helm upgrade --install promtail grafana/promtail -n monitoring -f monitoring/promtail-values.yaml
```

---

## HPA Configuration

| Service type | CPU threshold | Memory threshold | Max replicas |
|---|---|---|---|
| Public-facing (gateway, ai, portals) | 60% | 75% | 5 |
| Internal services | 70% | 80% | 5 |

Scale-up window: 30s (public), 60s (internal). Scale-down stabilization: 300s.

---

## Observability

### Grafana Dashboards
- **Kubernetes Pods** — CPU and memory per pod, filter by namespace
- **Node Exporter Full** — VPS host metrics (CPU, memory, disk, network)
- **HPA Replicas** — live replica counts and scaling events

### Useful LogQL Queries (Loki)

```logql
# All logs from a service
{namespace="app", app="gateway-service"}

# Error logs across all services
{namespace="app"} |= "ERROR"

# Logs from active slot only
{namespace="app", slot="blue"}

# Count errors per service in last 1 hour
sum by (app) (count_over_time({namespace="app"} |= "ERROR" [1h]))
```

### Useful PromQL Queries (Prometheus)

```promql
# Current replica count per service
kube_horizontalpodautoscaler_status_current_replicas{namespace="app"}

# Services currently scaled above 1 replica
kube_horizontalpodautoscaler_status_current_replicas{namespace="app"} > 1
```

---

## Jenkins Infra Pipeline Parameters

| Parameter | Default | Effect |
|---|---|---|
| `FORCE_REINSTALL` | false | Delete all Helm releases and reinstall from scratch |
| `SKIP_PROMETHEUS` | false | Skip Prometheus + Grafana |
| `SKIP_LOKI` | false | Skip Loki |
| `SKIP_PROMTAIL` | false | Skip Promtail |
| `SKIP_HEADLAMP` | false | Skip Headlamp |
| `REFRESH_TLS` | false | Recreate TLS secrets after cert renewal |

---

## Known Issues & Fixes

| Issue | Root Cause | Fix |
|---|---|---|
| `ingress.yaml` fails with `cannot unmarshal string` | Unicode arrow characters in YAML comments | YAML must use plain ASCII only — no unicode in any field |
| `kubectl apply` fails without `--validate=false` | Remote kubectl lacks Traefik CRD schemas | Apply with `--validate=false`; cluster validates correctly |
| Jenkinsfile shell errors | Unicode emoji in shell scripts | Rewrote with plain ASCII only — never use emoji in shell |
| `helm upgrade --install` timeout (15 min) | `--wait` flag blocks pipeline | Use `--atomic=false` — lets Kubernetes handle rollout independently |
| Grafana stuck in Pending | local-path PVC never bound | Set `persistence.enabled: false` — use emptyDir, provision dashboards as code |
| Grafana CrashLoopBackOff — duplicate default datasource | Chart v82+ auto-provisions Prometheus as default | Remove `isDefault: true` from all datasources in values.yaml |
| Loki CrashLoopBackOff — read-only filesystem | Loki writes to `/var/loki` even with persistence disabled | Add emptyDir volume mounted at `/var/loki` |
| Grafana shows Loki connection error | Loki chart v6+ deploys gateway proxy | Use `loki-gateway.monitoring.svc.cluster.local` not `loki:3100` |
| Headlamp Helm repo 404 | Helm chart URL changed | Deploy via direct `kubectl` manifest using `ghcr.io/headlamp-k8s/headlamp:latest` |

---

## Related

- [eks-production](https://github.com/Vishal-B142/eks-production) — production cluster on AWS EKS
- [jenkins-k8s-pipeline](https://github.com/Vishal-B142/jenkins-k8s-pipeline) — CI/CD pipeline for blue/green deploys
- [observability-stack](https://github.com/Vishal-B142/observability-stack) — standalone monitoring stack reference
- [terraform-aws-infra](https://github.com/Vishal-B142/terraform-aws-infra) — AWS infrastructure modules
