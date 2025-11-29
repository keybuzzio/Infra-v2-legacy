#!/bin/bash
set -e
export KUBECONFIG=/root/.kube/config

echo "=== Configuration systemd-resolved sur noeuds K8s ==="
echo ""

for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  echo "Configuration $ip..."
  ssh -o StrictHostKeyChecking=no root@$ip bash <<'NODESCRIPT'
    mkdir -p /etc/systemd/resolved.conf.d
    echo '[Resolve]' > /etc/systemd/resolved.conf.d/dns_servers.conf
    echo 'DNS=8.8.8.8 1.1.1.1 10.233.0.3' >> /etc/systemd/resolved.conf.d/dns_servers.conf
    echo 'FallbackDNS=8.8.4.4 1.0.0.1' >> /etc/systemd/resolved.conf.d/dns_servers.conf
    systemctl restart systemd-resolved
    echo "OK"
NODESCRIPT
  echo ""
done

echo "=== Verification ==="
ssh root@10.0.0.100 'cat /etc/systemd/resolved.conf.d/dns_servers.conf'
echo ""

echo "=== Redemarrage NGINX Ingress ==="
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller
echo "Attente 90s..."
sleep 90

echo ""
echo "=== Etat final ==="
kubectl get pods -n ingress-nginx | grep Running | wc -l | xargs echo "pods NGINX Running:"
kubectl get pods -n chatwoot -l app=chatwoot,component=web

echo ""
echo "Configuration terminee. Testez: curl -v https://support.keybuzz.io"

