#!/bin/bash
# =============================================================================
# k3s install script
# Disables built-in Traefik and servicelb — we use our own Traefik + MetalLB
# Run as root on the VPS
# =============================================================================
set -e

echo "Installing k3s (disabling built-in traefik and servicelb)..."
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--disable traefik --disable servicelb" sh -

echo "Waiting for k3s to be ready..."
sleep 10
kubectl get nodes

echo ""
echo "k3s installed. Kubeconfig at: /etc/rancher/k3s/k3s.yaml"
echo ""
echo "Next steps:"
echo "  1. Install MetalLB:    kubectl apply -f metallb/metallb-config.yaml"
echo "  2. Install Traefik:    helm install traefik traefik/traefik -f traefik/values.yaml -n kube-system"
echo "  3. Install cert-manager and apply ClusterIssuers"
echo "  4. Apply namespaces + resource quotas"
