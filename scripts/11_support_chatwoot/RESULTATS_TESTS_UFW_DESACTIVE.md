# Résultats Tests - UFW Désactivé

## ✅ UFW désactivé sur tous les nœuds K8s

- ✅ k8s-master-01 (10.0.0.100) : Status: inactive
- ✅ k8s-master-02 (10.0.0.101) : Status: inactive
- ✅ k8s-master-03 (10.0.0.102) : Status: inactive
- ✅ k8s-worker-01 (10.0.0.110) : Status: inactive
- ✅ k8s-worker-02 (10.0.0.111) : Status: inactive
- ✅ k8s-worker-03 (10.0.0.112) : Status: inactive
- ✅ k8s-worker-04 (10.0.0.113) : Status: inactive
- ✅ k8s-worker-05 (10.0.0.114) : Status: inactive

## 📊 Tests effectués

### Test 1 : Connectivité locale (depuis master)
```bash
curl -H "Host: support.keybuzz.io" http://127.0.0.1/ -v --max-time 5
```

**Résultat** : HTTP 400 Bad Request
- ✅ NGINX répond (pas de timeout)
- ⚠️ 400 Bad Request (requête incorrecte ou configuration NGINX)

### Test 2 : Connectivité externe
```bash
curl -v https://support.keybuzz.io --max-time 10
```

**Résultat** : Operation timed out after 10003 milliseconds
- ❌ Timeout après 10 secondes
- ✅ TLS handshake réussi
- ✅ Certificat Let's Encrypt valide
- ❌ Pas de réponse HTTP

### Test 3 : Connectivité NGINX → Service
```bash
kubectl exec -n ingress-nginx <pod> -- wget -O- -T 5 http://10.233.21.46:3000
```

**À tester** : En cours

## 🔍 Observations

1. **UFW désactivé** : ✅ Tous les nœuds
2. **NGINX Ingress** : ✅ 8 pods Running
3. **Pods Chatwoot** : ✅ 2/2 Running
4. **Test local** : ✅ NGINX répond (400 Bad Request)
5. **Test externe** : ❌ Timeout (10s)

## 💡 Prochaines étapes

1. Vérifier la connectivité NGINX → Service (IP 10.233.21.46:3000)
2. Vérifier la connectivité NGINX → Pod (IP 10.233.111.25:3000)
3. Vérifier les logs NGINX pour les erreurs upstream
4. Tester depuis un pod normal (sans hostNetwork) pour confirmer que le problème est spécifique à hostNetwork

---

**Date** : 2025-11-27  
**Statut** : UFW désactivé - Tests en cours

