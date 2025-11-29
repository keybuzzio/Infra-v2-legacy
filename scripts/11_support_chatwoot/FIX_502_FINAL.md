# Fix 502 Bad Gateway - support.keybuzz.io

## Situation actuelle

Après avoir corrigé le 504 Gateway Timeout en ajoutant `proxy-connect-timeout=60`, nous avons maintenant un **502 Bad Gateway**.

## Diagnostic

### ✅ Ce qui fonctionne :
- Les pods Chatwoot sont **Running** et **Ready**
- Les pods répondent correctement (test port-forward OK)
- Les healthchecks passent (Readiness: True, ContainersReady: True)
- Le Service est correctement configuré (port 3000 → targetPort 3000)
- L'Ingress est correctement configuré (pointe vers chatwoot-web:3000)

### ⚠️ Problème identifié :
Les pods NGINX Ingress viennent d'être redémarrés (certains ont moins de 2 minutes d'âge). Le 502 peut être **temporaire** pendant la synchronisation de la configuration NGINX.

## Solutions

### Solution 1 : Attendre la synchronisation (RECOMMANDÉ)

Attendez **2-3 minutes** après le redémarrage des pods NGINX Ingress, puis testez à nouveau :

```bash
curl -v https://support.keybuzz.io
```

Les pods NGINX Ingress doivent être tous **Running** depuis au moins 2-3 minutes pour que la configuration soit complètement synchronisée.

### Solution 2 : Vérifier la configuration NGINX

Si le 502 persiste après 3 minutes, vérifiez la configuration NGINX :

```bash
export KUBECONFIG=/root/.kube/config

# Obtenir un pod NGINX Ingress
INGRESS_POD=$(kubectl get pods -n ingress-nginx -l app=ingress-nginx --no-headers | head -1 | awk '{print $1}')

# Vérifier la configuration backend
kubectl exec -n ingress-nginx $INGRESS_POD -- cat /etc/nginx/nginx.conf | grep -A 10 "chatwoot"
```

### Solution 3 : Redémarrer les pods Chatwoot

Si le problème persiste, redémarrez les pods Chatwoot :

```bash
export KUBECONFIG=/root/.kube/config
kubectl rollout restart deployment/chatwoot-web -n chatwoot
kubectl rollout restart deployment/chatwoot-worker -n chatwoot

# Attendre que les pods soient Ready
kubectl wait --for=condition=ready pod -l app=chatwoot,component=web -n chatwoot --timeout=180s
```

### Solution 4 : Vérifier les logs en temps réel

Pendant une requête vers `https://support.keybuzz.io`, surveillez les logs :

```bash
# Terminal 1 : Logs NGINX Ingress
kubectl logs -n ingress-nginx --selector=app=ingress-nginx --tail=0 -f | grep -i "support\|chatwoot\|502\|error"

# Terminal 2 : Logs Chatwoot
kubectl logs -n chatwoot --selector=app=chatwoot,component=web --tail=0 -f | grep -i "error\|fatal\|exception"
```

## Configuration actuelle de l'Ingress

```yaml
annotations:
  nginx.ingress.kubernetes.io/proxy-body-size: "50m"
  nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
  nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
  nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"  # ← Ajouté pour fixer le 504
```

## Test de validation

Une fois que tous les pods NGINX Ingress sont Running depuis au moins 3 minutes :

```bash
# Test depuis install-01
curl -v https://support.keybuzz.io

# Vous devriez voir :
# - HTTP/2 200 (ou 302 redirect vers login)
# - Page HTML Chatwoot
```

## Si le 502 persiste

1. **Vérifier les endpoints** :
   ```bash
   kubectl get endpoints chatwoot-web -n chatwoot
   ```
   Doit montrer les IPs des pods Chatwoot (ex: `10.233.115.163:3000,10.233.71.161:3000`)

2. **Vérifier la connectivité réseau** :
   ```bash
   # Depuis un pod NGINX Ingress
   INGRESS_POD=$(kubectl get pods -n ingress-nginx -l app=ingress-nginx --no-headers | head -1 | awk '{print $1}')
   kubectl exec -n ingress-nginx $INGRESS_POD -- wget -qO- --timeout=5 http://chatwoot-web.chatwoot.svc.cluster.local:3000
   ```

3. **Vérifier les règles de firewall** sur les nœuds Kubernetes (UFW, iptables)

## Notes importantes

- Le 502 Bad Gateway signifie que NGINX Ingress **peut se connecter** aux pods Chatwoot (contrairement au 504), mais les pods renvoient une erreur ou ne répondent pas correctement.
- Si les pods Chatwoot sont Ready et répondent en port-forward, le problème est probablement lié à la synchronisation NGINX après le redémarrage.
- **Attendre 2-3 minutes** après le redémarrage des pods NGINX Ingress est souvent suffisant pour résoudre le problème.

