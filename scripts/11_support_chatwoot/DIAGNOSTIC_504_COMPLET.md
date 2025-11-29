# Diagnostic Complet - 504 Gateway Timeout

**Date** : 2025-11-27  
**Problème** : 504 Gateway Timeout persistant sur `https://support.keybuzz.io`

## 📊 Résultats de l'investigation

### ✅ Ce qui fonctionne

1. **Pods Chatwoot** : ✅ Running (2/2 web, 2/2 worker)
   - IPs : 10.233.111.25, 10.233.119.219
   - Logs montrent des requêtes HTTP 200 OK réussies
   - Répondent correctement aux requêtes directes

2. **Port-forward** : ✅ Fonctionne
   - `kubectl port-forward` → HTTP 200 OK
   - Chatwoot répond correctement

3. **Service** : ✅ Configuré correctement
   - ClusterIP : 10.233.21.46
   - Port : 3000 → targetPort : 3000
   - Endpoints : 10.233.111.25:3000, 10.233.119.219:3000

4. **Ingress** : ✅ Configuré correctement
   - Host : support.keybuzz.io
   - Backend : chatwoot-web:3000
   - Annotations timeout présentes

### ❌ Problèmes identifiés

1. **DNS CoreDNS** : ❌ Échec de résolution
   - Test depuis pod test : `Could not resolve host: chatwoot-web.chatwoot.svc.cluster.local`
   - NGINX Ingress (hostNetwork) peut avoir des problèmes de DNS

2. **UFW** : ⚠️ Inactive
   - UFW est inactive sur les nœuds (pas le problème actuel)
   - Mais peut-être que les règles Calico ne sont pas appliquées

3. **NGINX Ingress hostNetwork** : ⚠️ Utilise hostNetwork
   - Pods NGINX ont des IPs en 10.0.0.x (IPs des nœuds)
   - Peuvent avoir des problèmes pour joindre les pods en 10.233.x.x

## 🔍 Hypothèses

### Hypothèse 1 : Problème DNS CoreDNS
NGINX Ingress (hostNetwork) ne peut pas résoudre `chatwoot-web.chatwoot.svc.cluster.local`

**Solution** : Utiliser l'IP du Service directement (10.233.21.46) ou vérifier CoreDNS

### Hypothèse 2 : Problème routage Calico
Les nœuds (10.0.0.x) ne peuvent pas joindre les pods (10.233.x.x) même si UFW est inactive

**Solution** : Vérifier les routes IP et la configuration Calico

### Hypothèse 3 : Problème de configuration NGINX Ingress
NGINX Ingress ne peut pas joindre le Service ClusterIP

**Solution** : Vérifier la configuration NGINX et les logs détaillés

## 🧪 Tests à effectuer

1. **Test DNS depuis NGINX pod** :
   ```bash
   kubectl exec -n ingress-nginx <nginx-pod> -- nslookup chatwoot-web.chatwoot.svc.cluster.local
   ```

2. **Test connectivité directe IP** :
   ```bash
   kubectl exec -n ingress-nginx <nginx-pod> -- wget -O- http://10.233.111.25:3000
   ```

3. **Test depuis nœud directement** :
   ```bash
   curl -H "Host: support.keybuzz.io" http://127.0.0.1/ -v
   ```

4. **Vérifier CoreDNS** :
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50
   ```

5. **Vérifier routes IP** :
   ```bash
   ip route | grep 10.233
   ```

## 📝 Prochaines étapes

1. Vérifier les logs NGINX Ingress en temps réel pendant une requête
2. Tester la connectivité directe depuis un pod NGINX vers les pods Chatwoot
3. Vérifier CoreDNS
4. Vérifier les routes IP sur les nœuds
5. Vérifier la configuration Calico

---

**Statut** : Investigation en cours

