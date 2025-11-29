# Instructions pour désactiver UFW sur les nœuds K8s

## Problème

UFW bloque le trafic vers les IPs de pods Calico (10.233.x.x), causant des 504 Gateway Timeout.

## Solution

Désactiver UFW sur tous les nœuds Kubernetes (masters + workers).

## Commandes à exécuter sur install-01

```bash
export KUBECONFIG=/root/.kube/config

# Désactiver UFW sur tous les nœuds K8s
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  echo "Désactivation UFW sur $ip..."
  ssh -o StrictHostKeyChecking=no root@$ip "ufw disable"
done

# Vérification
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  echo -n "$ip: "
  ssh -o StrictHostKeyChecking=no root@$ip "ufw status | head -1"
done

# Redémarrer Ingress NGINX
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller
kubectl -n ingress-nginx rollout status daemonset ingress-nginx-controller --timeout=120s

# Attendre 2-3 minutes puis tester
sleep 120
curl -v https://support.keybuzz.io
```

## Nœuds concernés

- k8s-master-01 (10.0.0.100)
- k8s-master-02 (10.0.0.101)
- k8s-master-03 (10.0.0.102)
- k8s-worker-01 (10.0.0.110)
- k8s-worker-02 (10.0.0.111)
- k8s-worker-03 (10.0.0.112)
- k8s-worker-04 (10.0.0.113)
- k8s-worker-05 (10.0.0.114)

## Nœuds NON concernés (UFW reste actif)

- db-master-01, db-slave-01, db-slave-02
- redis-01, redis-02, redis-03
- queue-01, queue-02, queue-03
- minio-01, minio-02, minio-03
- Tous les autres nœuds non-K8s

## Justification

Dans un cluster Kubernetes cloud HA :
- ✅ Firewall Hetzner protège les ports publics
- ✅ NetworkPolicies Kubernetes contrôleront le trafic inter-pods (à ajouter)
- ✅ Load Balancer Hetzner est le seul point d'entrée public
- ❌ UFW sur nœuds K8s bloque le trafic Calico nécessaire (10.233.x.x)

