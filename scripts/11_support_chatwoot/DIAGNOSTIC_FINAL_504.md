# Diagnostic Final - 504 Gateway Timeout

## ✅ Actions effectuées

1. **DNS systemd-resolved configuré** sur tous les nœuds K8s
   - Fichier : `/etc/systemd/resolved.conf.d/dns_servers.conf`
   - DNS : 8.8.8.8, 1.1.1.1, 10.233.0.3 (CoreDNS)
   - ✅ Tous les nœuds configurés

2. **NGINX Ingress redémarré** : 8 pods Running

3. **Pods Chatwoot** : 2/2 Running

## 🔍 Tests à effectuer

### Test 1 : Connectivité directe depuis pod NGINX vers pod Chatwoot
```bash
kubectl exec -n ingress-nginx <nginx-pod> -- wget -O- -T 5 http://10.233.111.25:3000
```

### Test 2 : Connectivité via Service ClusterIP
```bash
kubectl exec -n ingress-nginx <nginx-pod> -- wget -O- -T 5 http://10.233.21.46:3000
```

### Test 3 : Test depuis nœud directement
```bash
ssh root@10.0.0.100 'curl -H "Host: support.keybuzz.io" http://127.0.0.1/ -v'
```

### Test 4 : Vérifier kube-proxy
```bash
kubectl get pods -n kube-system -l k8s-app=kube-proxy
```

## 📝 Notes importantes

1. **NGINX Ingress ne devrait PAS avoir besoin de DNS** pour joindre un Service ClusterIP. Il utilise kube-proxy qui route directement vers les endpoints.

2. **Le problème pourrait être** :
   - kube-proxy ne fonctionne pas correctement
   - Routes Calico bloquées (même si UFW est inactive)
   - NGINX Ingress ne peut pas joindre les IPs 10.233.x.x depuis les nœuds 10.0.0.x

3. **Solution alternative** : Si kube-proxy ne fonctionne pas, utiliser l'IP du Service directement dans la configuration NGINX (mais ce n'est pas recommandé).

---

**Date** : 2025-11-27  
**Statut** : Diagnostic en cours

