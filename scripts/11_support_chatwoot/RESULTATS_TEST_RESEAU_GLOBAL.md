# Résultats Test Réseau Kubernetes Global

## 📊 État du déploiement

- ✅ **Deployment net-test** : 1 pod Running
  - Pod IP : `10.233.115.174`
  - Node : `k8s-worker-04`
- ✅ **Service net-test** : ClusterIP créé
  - ClusterIP : `10.233.39.40`
  - Port : `80`
- ✅ **Endpoints** : `10.233.115.174:80`
- ✅ **kube-proxy** : 4 pods Running

## 🧪 Tests effectués

### Test 1 : DNS Service
- Commande : `getent hosts net-test.default.svc.cluster.local`
- **Résultat** : ❌ DNS FAIL
- **Conclusion** : DNS ne résout pas les Services Kubernetes

### Test 2 : Service DNS (curl)
- Commande : `curl http://net-test.default.svc.cluster.local:80`
- **Résultat** : ❌ Resolving timed out after 5001 milliseconds
- **Conclusion** : DNS timeout

### Test 3 : Service ClusterIP (curl)
- Commande : `curl http://10.233.39.40:80`
- **Résultat** : En cours

### Test 4 : Pod IP direct (curl)
- Commande : `curl http://10.233.115.174:80`
- **Résultat** : En cours

### Test 5 : Node → Service
- Commande : `curl http://10.233.39.40:80` depuis nœud master
- **Résultat** : En cours

## 📝 Observations

1. **DNS ne fonctionne pas** : Les pods ne peuvent pas résoudre les Services Kubernetes
2. **CoreDNS** : À vérifier
3. **kube-proxy** : 4 pods Running

## 💡 Interprétation

### Si tous les tests échouent
- **Conclusion** : Réseau K8s globalement cassé (Calico ou kube-proxy)

### Si Service IP fonctionne mais pas Pod IP
- **Conclusion** : kube-proxy OK, mais routage pod CIDR partiel

### Si Node → Service fonctionne mais pas Pod → Service
- **Conclusion** : Problème spécifique aux pods

---

**Date** : 2025-11-27  
**Statut** : Tests en cours

