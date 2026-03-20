# k3s-dev-staging

> Self-hosted Kubernetes cluster on VPS using k3s for **development and staging** environments — Traefik Ingress, MetalLB, cert-manager TLS, and multi-namespace architecture.

Part of a two-tier Kubernetes strategy:

| Repo | Environment | Platform | Status |
|---|---|---|---|
| **k3s-dev-staging** (this repo) | Dev & Staging | k3s on Hostinger VPS | ✅ Live |
| [eks-production](https://github.com/Vishal-B142/eks-production) | Production | AWS EKS | 🔄 In Progress |

Migrating from AWS ECS to k3s for dev/staging **reduced monthly infrastructure costs by ~30%** while sustaining **99%+ uptime** — freeing budget for a managed EKS production cluster.

---

## Architecture

```
┌─────────────────────────────────────────────────┐
│                Hostinger VPS                    │
│                                                 │
│  ┌──────────┐   ┌──────────┐   ┌─────────────┐ │
│  │ k3s      │   │ Traefik  │   │   MetalLB   │ │
│  │ Master   │──▶│ Ingress  │◀──│ LoadBalancer│ │
│  └──────────┘   └──────────┘   └─────────────┘ │
│       │                                         │
│  ┌────▼───────────────────────────────────────┐ │
│  │  Namespaces                                │ │
│  │  ┌─────────────┐     ┌──────────────────┐  │ │
│  │  │     dev     │     │    staging       │  │ │
│  │  │             │     │                  │  │ │
│  │  │ light quotas│     │ prod-like config │  │ │
│  │  └─────────────┘     └──────────────────┘  │ │
│  └────────────────────────────────────────────┘ │
│                                                 │
│  cert-manager — Let's Encrypt TLS (auto-renew)  │
└─────────────────────────────────────────────────┘
```

---

## Stack

![k3s](https://img.shields.io/badge/k3s-FFC61C?style=flat&logo=k3s&logoColor=black)
![Helm](https://img.shields.io/badge/Helm-0F1689?style=flat&logo=helm&logoColor=white)
![Traefik](https://img.shields.io/badge/Traefik-24A1C1?style=flat&logo=traefikproxy&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)
![cert-manager](https://img.shields.io/badge/cert--manager-003F8C?style=flat&logo=letsencrypt&logoColor=white)

---

## Repo Structure

```
k3s-dev-staging/
├── install/
│   └── k3s-install.sh          # k3s install script (Traefik + servicelb disabled)
├── namespaces/
│   ├── dev.yaml
│   └── staging.yaml
├── traefik/
│   ├── values.yaml             # Helm values for Traefik
│   └── ingress-example.yaml   # Sample IngressRoute
├── metallb/
│   ├── metallb-config.yaml
│   └── ipaddresspool.yaml
├── cert-manager/
│   ├── clusterissuer-staging.yaml   # Let's Encrypt staging (testing)
│   └── clusterissuer-prod.yaml      # Let's Encrypt prod (real certs)
├── resource-quotas/
│   ├── dev-quota.yaml          # Lighter limits for dev
│   └── staging-quota.yaml      # Closer to prod limits
├── deployments/
│   └── example-deployment.yaml # Rolling update deployment example
└── README.md
```

---

## Quick Start

```bash
# 1. Install k3s — disable built-in Traefik and servicelb (we use our own)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -

# 2. Set kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 3. Install MetalLB
kubectl apply -f metallb/metallb-config.yaml
kubectl apply -f metallb/ipaddresspool.yaml

# 4. Install Traefik via Helm
helm repo add traefik https://traefik.github.io/charts
helm repo update
helm install traefik traefik/traefik \
  -f traefik/values.yaml \
  -n traefik --create-namespace

# 5. Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm repo update
helm install cert-manager jetstack/cert-manager \
  --namespace cert-manager \
  --create-namespace \
  --set installCRDs=true

# 6. Apply ClusterIssuers (start with staging to test)
kubectl apply -f cert-manager/clusterissuer-staging.yaml
kubectl apply -f cert-manager/clusterissuer-prod.yaml

# 7. Create namespaces and resource quotas
kubectl apply -f namespaces/
kubectl apply -f resource-quotas/
```

---

## Namespace Config

### dev — light resource limits, fast iteration
```yaml
# resource-quotas/dev-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: dev-quota
  namespace: dev
spec:
  hard:
    requests.cpu: "2"
    requests.memory: 2Gi
    limits.cpu: "4"
    limits.memory: 4Gi
    pods: "20"
```

### staging — mirrors production constraints
```yaml
# resource-quotas/staging-quota.yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: staging-quota
  namespace: staging
spec:
  hard:
    requests.cpu: "4"
    requests.memory: 4Gi
    limits.cpu: "8"
    limits.memory: 8Gi
    pods: "40"
```

---

## Key Features

- **Zero-downtime deployments** — rolling update strategy on all workloads
- **Automatic TLS** — cert-manager + Let's Encrypt, auto-renewed
- **Namespace isolation** — dev and staging fully separated with independent quotas
- **MetalLB** — bare-metal load balancing on VPS (no cloud LB needed)
- **Traefik** — single Ingress controller handling routing for both namespaces
- **Cost-efficient** — entire dev+staging stack runs on a single VPS

---

## Why k3s for Dev/Staging?

| Factor | k3s (Dev/Staging) | EKS (Production) |
|---|---|---|
| Cost | ~$10–20/month VPS | Higher (managed nodes) |
| Setup | Minutes | Hours (Terraform) |
| Control | Full | Shared with AWS |
| HA | Single node | Multi-AZ |
| Best for | Fast iteration, cost saving | Reliability, scale |

---

## Related

- [eks-production](https://github.com/Vishal-B142/eks-production) — production cluster on AWS EKS
- [jenkins-k8s-pipeline](https://github.com/Vishal-B142/jenkins-k8s-pipeline) — CI/CD deploying to both clusters
- [observability-stack](https://github.com/Vishal-B142/observability-stack) — monitoring for both environments
