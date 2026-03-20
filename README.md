# k3s-production-cluster

> Production-grade self-hosted Kubernetes cluster on VPS using k3s — with Traefik Ingress, MetalLB load balancing, cert-manager TLS, and multi-namespace architecture.

Built as part of a cost-optimisation migration from AWS ECS — **reduced monthly infrastructure costs by ~30%** while sustaining **99%+ uptime**.

## Architecture

```
┌─────────────────────────────────────────────┐
│              Hostinger VPS                  │
│                                             │
│  ┌──────────┐   ┌──────────┐   ┌─────────┐ │
│  │ k3s      │   │ Traefik  │   │MetalLB  │ │
│  │ Master   │──▶│ Ingress  │◀──│LoadBal  │ │
│  └──────────┘   └──────────┘   └─────────┘ │
│       │                                     │
│  ┌────▼─────────────────────────────────┐   │
│  │  Namespaces                          │   │
│  │  ┌──────────┐  ┌──────────────────┐  │   │
│  │  │production│  │staging           │  │   │
│  │  └──────────┘  └──────────────────┘  │   │
│  └──────────────────────────────────────┘   │
│                                             │
│  cert-manager (Let's Encrypt TLS)           │
└─────────────────────────────────────────────┘
```

## Stack

![k3s](https://img.shields.io/badge/k3s-FFC61C?style=flat&logo=k3s&logoColor=black)
![Helm](https://img.shields.io/badge/Helm-0F1689?style=flat&logo=helm&logoColor=white)
![Traefik](https://img.shields.io/badge/Traefik-24A1C1?style=flat&logo=traefikproxy&logoColor=white)
![Kubernetes](https://img.shields.io/badge/Kubernetes-326CE5?style=flat&logo=kubernetes&logoColor=white)

## Repo Structure

```
k3s-production-cluster/
├── install/
│   └── k3s-install.sh          # k3s single-node install script
├── namespaces/
│   ├── production.yaml
│   └── staging.yaml
├── traefik/
│   ├── values.yaml             # Helm values for Traefik
│   └── ingress-example.yaml
├── metallb/
│   ├── metallb-config.yaml
│   └── ipaddresspool.yaml
├── cert-manager/
│   ├── clusterissuer-prod.yaml
│   └── clusterissuer-staging.yaml
├── resource-quotas/
│   ├── production-quota.yaml
│   └── staging-quota.yaml
└── README.md
```

## Quick Start

```bash
# 1. Install k3s (without default Traefik — we install our own)
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik" sh -

# 2. Get kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# 3. Install MetalLB
kubectl apply -f metallb/metallb-config.yaml

# 4. Install Traefik via Helm
helm repo add traefik https://traefik.github.io/charts
helm install traefik traefik/traefik -f traefik/values.yaml -n traefik --create-namespace

# 5. Install cert-manager
helm repo add jetstack https://charts.jetstack.io
helm install cert-manager jetstack/cert-manager --namespace cert-manager \
  --create-namespace --set installCRDs=true

# 6. Apply ClusterIssuers
kubectl apply -f cert-manager/clusterissuer-prod.yaml

# 7. Create namespaces with resource quotas
kubectl apply -f namespaces/
kubectl apply -f resource-quotas/
```

## Key Features

- **Zero-downtime deployments** via rolling update strategies
- **Automatic TLS** with cert-manager + Let's Encrypt
- **Multi-namespace isolation** — production and staging fully separated
- **Resource quotas** — CPU/memory limits enforced per namespace
- **PersistentVolumeClaims** for stateful workloads

## Related

- [jenkins-k8s-pipeline](https://github.com/Vishal-B142/jenkins-k8s-pipeline) — CI/CD that deploys into this cluster
- [observability-stack](https://github.com/Vishal-B142/observability-stack) — Monitoring for this cluster
