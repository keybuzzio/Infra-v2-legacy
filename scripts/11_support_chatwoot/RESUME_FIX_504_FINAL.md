# Fix 504 Gateway Timeout - Résumé Final

## Diagnostic effectué

### ✅ Configurations vérifiées et correctes

1. **Service chatwoot-web** : ✅ 3000 → 3000
2. **Ingress** : ✅ chatwoot-web:3000
3. **containerPort** : ✅ 3000
4. **Endpoints** : ✅ 2 pods avec port 3000
5. **Pods** : ✅ Running (1/1 Ready)
6. **Command Rails** : ✅ `bundle exec rails s -p 3000 -b 0.0.0.0`

### ⚠️ Problème identifié

Les logs NGINX Ingress montrent des **timeouts de connexion upstream** (50 secondes) :
- `upstream timed out (110: Operation timed out) while connecting to upstream`
- Les requêtes vers `support.keybuzz.io` timeout après 50 secondes

### 🔧 Corrections appliquées

1. **Annotations upstream ajoutées à l'Ingress** :
   ```yaml
   nginx.ingress.kubernetes.io/upstream-connect-timeout: "60"
   nginx.ingress.kubernetes.io/upstream-send-timeout: "60"
   nginx.ingress.kubernetes.io/upstream-read-timeout: "60"
   ```

2. **Annotations proxy existantes** :
   ```yaml
   nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"
   nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
   nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
   ```

3. **Redémarrage NGINX Ingress** : Pour appliquer les nouvelles annotations

## Tests effectués

- ✅ Port-forward vers service : **Fonctionne** (retourne HTML Chatwoot)
- ✅ Pods répondent : **200 OK** dans les logs
- ✅ Endpoints corrects : **2 pods** avec port 3000
- ⚠️ Test depuis NGINX Ingress : **Timeout** (problème de connectivité réseau)

## Prochaines étapes

1. **Attendre 2-3 minutes** après le redémarrage de NGINX Ingress
2. **Tester** : `curl -v https://support.keybuzz.io`
3. **Si le 504 persiste** :
   - Vérifier les logs NGINX Ingress en temps réel
   - Vérifier la connectivité réseau Calico entre pods NGINX et Chatwoot
   - Vérifier les règles de firewall sur les nœuds Kubernetes

## Configuration finale

### Service
```yaml
spec:
  ports:
  - port: 3000
    targetPort: 3000
```

### Ingress
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
  annotations:
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
    nginx.ingress.kubernetes.io/upstream-connect-timeout: "60"
    nginx.ingress.kubernetes.io/upstream-send-timeout: "60"
    nginx.ingress.kubernetes.io/upstream-read-timeout: "60"
```

### Deployment
```yaml
command: ["bundle", "exec", "rails", "s", "-p", "3000", "-b", "0.0.0.0"]
ports:
- containerPort: 3000
```

---

**Date** : 2025-11-27  
**Statut** : Corrections appliquées, en attente de test final

