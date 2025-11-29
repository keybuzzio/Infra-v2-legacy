# Commandes manuelles pour désactiver UFW

## Exécuter ces commandes sur install-01

```bash
export KUBECONFIG=/root/.kube/config

# Désactiver UFW sur chaque nœud K8s
ssh root@10.0.0.100 "ufw disable"
ssh root@10.0.0.101 "ufw disable"
ssh root@10.0.0.102 "ufw disable"
ssh root@10.0.0.110 "ufw disable"
ssh root@10.0.0.111 "ufw disable"
ssh root@10.0.0.112 "ufw disable"
ssh root@10.0.0.113 "ufw disable"
ssh root@10.0.0.114 "ufw disable"

# Vérification
ssh root@10.0.0.100 "ufw status"
ssh root@10.0.0.101 "ufw status"
ssh root@10.0.0.102 "ufw status"
ssh root@10.0.0.110 "ufw status"
ssh root@10.0.0.111 "ufw status"
ssh root@10.0.0.112 "ufw status"
ssh root@10.0.0.113 "ufw status"
ssh root@10.0.0.114 "ufw status"

# Redémarrer Ingress NGINX
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller

# Attendre 2-3 minutes
sleep 180

# Tester
curl -v https://support.keybuzz.io
```

## Script bash complet

Créer `/opt/keybuzz-installer-v2/scripts/11_support_chatwoot/disable_ufw_all.sh` :

```bash
#!/bin/bash
set -e
export KUBECONFIG=/root/.kube/config

echo "=== Désactivation UFW sur nœuds K8s ==="
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  echo "Désactivation UFW sur $ip..."
  ssh -o StrictHostKeyChecking=no root@$ip "ufw disable" || echo "Erreur"
done

echo ""
echo "=== Vérification ==="
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  echo -n "$ip: "
  ssh -o StrictHostKeyChecking=no root@$ip "ufw status | head -1" || echo "Non accessible"
done

echo ""
echo "=== Redémarrage Ingress NGINX ==="
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller
echo "Attendre 2-3 minutes puis tester : curl -v https://support.keybuzz.io"
```

