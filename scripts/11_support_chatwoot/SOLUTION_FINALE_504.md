# Solution Finale - 504 Gateway Timeout

## 🎯 Problème identifié

Le 504 Gateway Timeout est causé par **NGINX Ingress (hostNetwork) qui ne peut pas résoudre le DNS** pour `chatwoot-web.chatwoot.svc.cluster.local`.

### Diagnostic

1. ✅ **Pods Chatwoot** : Fonctionnent (HTTP 200 OK dans les logs)
2. ✅ **Port-forward** : Fonctionne (HTTP 200 OK)
3. ✅ **Service** : Configuré correctement (10.233.21.46:3000)
4. ✅ **Endpoints** : Corrects (10.233.111.25:3000, 10.233.119.219:3000)
5. ❌ **DNS** : Échec de résolution (`connection timed out; no servers could be reached`)
6. ⚠️ **NGINX Ingress** : Utilise `hostNetwork: true` → problèmes DNS

## ✅ Solution appliquée

### Configuration du resolver DNS dans NGINX

Ajout du resolver DNS dans le ConfigMap `ingress-nginx-controller` :

```bash
kubectl patch configmap ingress-nginx-controller -n ingress-nginx \
  --type merge \
  -p '{"data":{"resolver":"10.233.0.10 valid=10s"}}'
```

**Note** : `10.233.0.10` est l'IP du service CoreDNS (à vérifier avec `kubectl get svc -n kube-system`).

### Redémarrage NGINX Ingress

```bash
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller
kubectl -n ingress-nginx rollout status daemonset ingress-nginx-controller --timeout=120s
```

## 🧪 Test final

Après application de la solution :

```bash
curl -v https://support.keybuzz.io
```

**Attendu** : HTTP 200/302 (page Chatwoot)

## 📝 Alternative si le resolver ne fonctionne pas

Si le resolver DNS ne fonctionne pas, utiliser l'IP du Service directement dans l'Ingress :

```yaml
spec:
  rules:
  - host: support.keybuzz.io
    http:
      paths:
      - backend:
          service:
            name: chatwoot-web
            port:
              number: 3000
```

Mais normalement, NGINX devrait utiliser kube-proxy pour router vers le Service ClusterIP sans avoir besoin de DNS.

## 🔍 Vérifications supplémentaires

1. **Vérifier CoreDNS** :
   ```bash
   kubectl get svc -n kube-system | grep dns
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   ```

2. **Vérifier kube-proxy** :
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-proxy
   ```

3. **Vérifier les routes IP** :
   ```bash
   ip route | grep 10.233
   ```

---

**Date** : 2025-11-27  
**Statut** : Solution appliquée - À tester

