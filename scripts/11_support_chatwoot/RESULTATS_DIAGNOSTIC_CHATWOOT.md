# Résultats Diagnostic Complet - Chatwoot

## 🧪 Tests effectués

### Test 1 : Pod curl-test vers Service
- Service : `chatwoot-web.chatwoot.svc.cluster.local:3000`
- **Résultat** : En cours

### Test 1B : Pod curl-test vers IP Pod 1
- IP Pod 1 : `10.233.111.25:3000`
- **Résultat** : En cours

### Test 1C : Pod curl-test vers IP Pod 2
- IP Pod 2 : `10.233.119.219:3000`
- **Résultat** : En cours

### Test 2 : Ports en écoute dans le pod Chatwoot
- Commande : `netstat -tlnp` ou `ss -tlnp`
- **Résultat** : En cours

### Test 3 : Curl depuis pod Chatwoot vers localhost:3000
- Commande : `curl -v -m 5 http://127.0.0.1:3000`
- **Résultat** : En cours

### Test 4 : Commande/Args du conteneur
- **Résultat** : En cours

### Test 5 : Image utilisée
- **Résultat** : En cours

### Test 6 : Logs du pod Chatwoot
- **Résultat** : En cours

## 📊 État actuel

- ✅ **Endpoints** : 2 endpoints (10.233.111.25:3000, 10.233.119.219:3000)
- ✅ **Service** : ClusterIP 10.233.21.46:3000
- ✅ **Pod testé** : chatwoot-web-768f844997-67vzh

---

**Date** : 2025-11-27  
**Statut** : Diagnostic en cours

