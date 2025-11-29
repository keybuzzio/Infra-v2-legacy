# Solution service-upstream pour Module 10

## ✅ Solution appliquée

### Annotation service-upstream
- ✅ **Annotation ajoutée** : `nginx.ingress.kubernetes.io/service-upstream: "true"`
- ✅ **Effet** : Force ingress-nginx à utiliser le Service ClusterIP au lieu des endpoints directs
- ✅ **Ingress-nginx** : Redémarré pour appliquer les changements

### Pourquoi cette solution
Avec `service-upstream: true`, ingress-nginx :
- ✅ Utilise le Service ClusterIP (10.110.76.162:8080) au lieu des IPs des pods
- ✅ Passe par kube-proxy qui route correctement vers les pods
- ✅ Évite le problème de routage Calico inter-node

### Configuration
- **Service** : `keybuzz-api` (type: NodePort, ClusterIP: 10.110.76.162)
- **Ingress** : Annotation `service-upstream: true`
- **Ingress-nginx** : Utilise maintenant le Service au lieu des endpoints

---

**Date** : 2025-11-28  
**Statut** : ✅ Solution service-upstream appliquée - Tests en cours

