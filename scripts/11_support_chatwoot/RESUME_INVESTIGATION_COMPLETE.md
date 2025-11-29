# Résumé Investigation Complète - 504 Gateway Timeout

## ✅ Actions effectuées

1. **DNS systemd-resolved configuré** sur tous les nœuds K8s ✅
2. **NGINX Ingress redémarré** : 8 pods Running ✅
3. **Pods Chatwoot** : 2/2 Running ✅
4. **kube-proxy** : 4 pods Running ✅

## 🔍 Tests effectués

### Test depuis nœud (10.0.0.100)
- ✅ DNS résout `support.keybuzz.io` → IPs LB (138.199.132.240, 49.13.42.76)
- ⚠️ Connexion à `127.0.0.1:80` → Connection refused
- ⚠️ Connexion à LB → 400 Bad Request (normal sans Host header correct)

### Observations

1. **NGINX Ingress avec hostNetwork** :
   - Utilise `hostPort: 80` et `hostPort: 443`
   - Devrait écouter sur l'IP du nœud (10.0.0.100), pas sur 127.0.0.1

2. **Le problème pourrait être** :
   - NGINX Ingress n'écoute pas correctement sur les ports host
   - Le Load Balancer Hetzner ne route pas correctement vers les nœuds
   - NGINX Ingress ne peut pas joindre les pods Chatwoot (10.233.x.x) depuis les nœuds (10.0.0.x)

## 🧪 Tests à effectuer

1. **Vérifier que NGINX écoute sur l'IP du nœud** :
   ```bash
   ssh root@10.0.0.100 'netstat -tlnp | grep :80'
   ssh root@10.0.0.100 'curl -H "Host: support.keybuzz.io" http://10.0.0.100/ -v'
   ```

2. **Vérifier les logs NGINX en temps réel** pendant une requête

3. **Vérifier la configuration du Load Balancer Hetzner** :
   - Health checks pointent vers `/healthz` sur port 80
   - Backends pointent vers les IPs privées des nœuds (10.0.0.100-114)

## 📝 Prochaines étapes

1. Vérifier que NGINX Ingress écoute bien sur les ports host (80, 443)
2. Tester la connectivité depuis NGINX pod vers pods Chatwoot
3. Vérifier les logs NGINX en temps réel pendant une requête
4. Vérifier la configuration du Load Balancer Hetzner

---

**Date** : 2025-11-27  
**Statut** : Investigation en cours

