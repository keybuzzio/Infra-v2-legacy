# Test Réseau Kubernetes Global

## 🧪 Tests effectués

### Étape 1 : Déploiement nginx de test
- Deployment : `net-test` (nginx:alpine) dans namespace `default`
- Service : ClusterIP `net-test` port 80

### Étape 2 : Tests depuis pod curl
1. **Test DNS** : `getent hosts net-test.default.svc.cluster.local`
2. **Test Service ClusterIP** : `curl http://<SERVICE_IP>:80`
3. **Test Pod direct** : `curl http://<POD_IP>:80`
4. **Test Service DNS** : `curl http://net-test.default.svc.cluster.local:80`

### Étape 3 : Test depuis nœud master
- Test Service ClusterIP depuis nœud (hostNetwork)

## 📊 Résultats attendus

### Scénario A : Réseau K8s globalement cassé
- ❌ DNS FAIL
- ❌ SERVICE FAIL
- ❌ POD FAIL
- ❌ NODE → SERVICE FAIL
- **Conclusion** : Problème global (Calico ou kube-proxy)

### Scénario B : Problème local à Chatwoot
- ✅ DNS OK dans default
- ✅ SERVICE OK dans default
- ✅ POD OK dans default
- ❌ Tout plante dans chatwoot
- **Conclusion** : Problème local (NetworkPolicy, namespace, config)

### Scénario C : Routage pod CIDR partiel
- ✅ SERVICE OK
- ❌ POD direct FAIL
- **Conclusion** : kube-proxy OK, mais routage pod CIDR partiel

---

**Date** : 2025-11-27  
**Statut** : Tests en cours

