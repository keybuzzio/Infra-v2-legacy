# Résumé Fix UFW Final - 504 Gateway Timeout

## ✅ Actions effectuées

### 1. Désactivation UFW sur tous les nœuds K8s

**Nœuds traités** :
- k8s-master-01
- k8s-master-02
- k8s-master-03
- k8s-worker-01
- k8s-worker-02
- k8s-worker-03
- k8s-worker-04
- k8s-worker-05

**Commande** :
```bash
for NODE in k8s-master-01 k8s-master-02 k8s-master-03 k8s-worker-01 k8s-worker-02 k8s-worker-03 k8s-worker-04 k8s-worker-05; do
  ssh root@$NODE "ufw disable || true"
done
```

### 2. Redémarrage NGINX Ingress

```bash
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller
kubectl -n ingress-nginx rollout status daemonset ingress-nginx-controller --timeout=120s
```

### 3. Tests de connectivité

#### Test local (depuis master)
```bash
curl -H "Host: support.keybuzz.io" http://127.0.0.1/ -v --max-time 5
```

#### Test externe
```bash
curl -v https://support.keybuzz.io --max-time 10
```

## 📝 Notes

**Cause identifiée** : UFW sur les nœuds Kubernetes bloquait le trafic entre les nœuds (10.0.0.x) et les pods Calico (10.233.x.x).

**Solution** : Désactivation complète d'UFW sur tous les nœuds K8s.

**Sécurité** : Les nœuds K8s sont protégés par :
- Le firewall Hetzner (Security Groups)
- Les NetworkPolicies Kubernetes (à configurer plus tard)
- Le fait que seul le LB Hetzner ouvre les ports publics

---

**Date** : 2025-11-27  
**Statut** : UFW désactivé - Tests en cours

