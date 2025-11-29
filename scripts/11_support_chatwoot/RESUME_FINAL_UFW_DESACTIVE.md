# Résumé Final - UFW Désactivé

## ✅ Actions effectuées

### 1. UFW désactivé sur tous les nœuds K8s
- ✅ 8 nœuds (3 masters + 5 workers) : Status: inactive

### 2. NGINX Ingress redémarré
- ✅ 8 pods Running

## 📊 Résultats des tests

### Test local (depuis master)
```bash
curl -H "Host: support.keybuzz.io" http://127.0.0.1/ -v --max-time 5
```
**Résultat** : HTTP 400 Bad Request
- ✅ NGINX répond (pas de timeout)

### Test externe
```bash
curl -v https://support.keybuzz.io --max-time 15
```
**Résultat** : Operation timed out after 15001 milliseconds
- ❌ Timeout après 15 secondes
- ✅ TLS handshake réussi
- ✅ Certificat Let's Encrypt valide

### Test connectivité NGINX → Service
```bash
kubectl exec -n ingress-nginx ingress-nginx-controller-2dxgc -- wget -O- -T 5 http://10.233.21.46:3000
```
**Résultat** : wget: download timed out
- ❌ Timeout

### Test connectivité NGINX → Pod
```bash
kubectl exec -n ingress-nginx ingress-nginx-controller-2dxgc -- wget -O- -T 5 http://10.233.111.25:3000
```
**Résultat** : wget: download timed out
- ❌ Timeout

## 🔍 Logs NGINX

```
10.0.0.6 - - [27/Nov/2025:20:43:23 +0000] "GET / HTTP/1.1" 499 0 "-" "curl/8.5.0" 162 50.001 [chatwoot-chatwoot-web-3000] [] 10.233.119.219:3000 0 50.001 - 899286148eadc3f3c656823e06f6895c
```

**Analyse** :
- Code 499 : Client fermé la connexion avant réponse
- Timeout 50.001s : NGINX a attendu 50 secondes pour une réponse du backend (10.233.119.219:3000)
- Backend : `chatwoot-chatwoot-web-3000` → `10.233.119.219:3000`

## 📝 Conclusion

**UFW désactivé** mais le problème persiste :
- ❌ NGINX ne peut pas joindre les pods Calico (10.233.x.x)
- ❌ Timeout sur Service (10.233.21.46:3000)
- ❌ Timeout sur Pod (10.233.111.25:3000)

**Cause probable** : Problème de routage Calico ou configuration réseau, pas UFW.

## 💡 Prochaines étapes

1. Vérifier les routes Calico sur les nœuds
2. Vérifier la configuration Calico IPIP
3. Vérifier les règles iptables (même avec UFW désactivé)
4. Tester depuis un pod normal (sans hostNetwork)

---

**Date** : 2025-11-27  
**Statut** : UFW désactivé - Problème de connectivité persiste

