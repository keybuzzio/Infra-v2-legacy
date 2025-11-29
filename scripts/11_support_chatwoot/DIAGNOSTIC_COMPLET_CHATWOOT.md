# Diagnostic Complet - Chatwoot Port 3000

## 🧪 Tests effectués

### Test 1 : Pod curl-test vers Service et Pods
- Test vers Service ClusterIP : `chatwoot-web.chatwoot.svc.cluster.local:3000`
- Test vers IP Pod 1 : `10.233.111.25:3000`
- Test vers IP Pod 2 : `10.233.119.219:3000`
- Résolution DNS : `getent hosts chatwoot-web.chatwoot.svc.cluster.local`

### Test 2 : Ports en écoute dans le pod Chatwoot
- Commande : `netstat -tlnp` ou `ss -tlnp`
- Vérification : Process écoutant sur `0.0.0.0:3000`

### Test 3 : Curl depuis pod Chatwoot vers localhost:3000
- Commande : `curl -v -m 5 http://127.0.0.1:3000`
- Vérification : Le pod répond-il sur localhost:3000 ?

### Test 4 : Commande/Args du conteneur
- Commande : `kubectl get pod -o jsonpath='{.spec.containers[0].command}'`
- Args : `kubectl get pod -o jsonpath='{.spec.containers[0].args}'`
- Vérification : La commande lance-t-elle bien le serveur web sur 3000 ?

### Test 5 : Image utilisée
- Vérification : Quelle image est utilisée (chatwoot/chatwoot ou ghcr.io/keybuzzio/chatwoot-keybuzz) ?

### Test 6 : Logs du pod Chatwoot
- Vérification : Y a-t-il des erreurs dans les logs ?

## 📊 Résultats attendus

### Scénario A : Pod Chatwoot n'écoute pas sur 3000
- `netstat/ss` ne montre pas de process sur `0.0.0.0:3000`
- `curl http://127.0.0.1:3000` échoue
- **Solution** : Corriger le Deployment/Dockerfile

### Scénario B : Service/Endpoints route mal
- `curl http://127.0.0.1:3000` fonctionne
- `curl http://chatwoot-web.chatwoot.svc.cluster.local:3000` échoue
- **Solution** : Vérifier la configuration du Service

### Scénario C : Problème exotique
- Tous les tests internes fonctionnent
- NGINX Ingress ne peut toujours pas joindre
- **Solution** : Investiguer le routage Calico/network

---

**Date** : 2025-11-27  
**Statut** : Diagnostic en cours

