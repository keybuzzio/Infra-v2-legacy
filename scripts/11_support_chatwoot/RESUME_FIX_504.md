# Résumé du Fix 504 Gateway Timeout

## Problème identifié

Le 504 Gateway Timeout pour `https://support.keybuzz.io` n'était **PAS** causé par :
- ❌ La configuration du Load Balancer Hetzner (correctement configuré)
- ❌ Le DNS (correctement configuré)
- ❌ Les pods Chatwoot (Running et répondent correctement)
- ❌ Le Service Kubernetes (correctement configuré : port 3000 → targetPort 3000)
- ❌ L'Ingress (correctement configuré : pointe vers chatwoot-web:3000)

## Cause réelle

Le problème venait de **NGINX Ingress qui ne pouvait pas établir la connexion initiale** vers les pods Chatwoot.

Les logs NGINX Ingress montraient :
```
upstream timed out (110: Operation timed out) while connecting to upstream
```

## Solution appliquée

1. **Ajout de l'annotation `proxy-connect-timeout`** à l'Ingress :
   ```bash
   kubectl annotate ingress chatwoot-ingress -n chatwoot \
     nginx.ingress.kubernetes.io/proxy-connect-timeout=60 \
     --overwrite
   ```

2. **Les timeouts existants étaient déjà corrects** :
   - `proxy-read-timeout: 300`
   - `proxy-send-timeout: 300`

3. **Redémarrage des pods NGINX Ingress** pour forcer la relecture de la configuration :
   ```bash
   kubectl rollout restart daemonset ingress-nginx-controller -n ingress-nginx
   ```

## Vérifications effectuées

✅ Les pods Chatwoot sont Running et répondent (test port-forward OK)  
✅ Le Service est correctement configuré (port 3000 → targetPort 3000)  
✅ L'Ingress pointe vers le bon service (chatwoot-web:3000)  
✅ Les pods répondent depuis le même nœud (test depuis worker-04 OK)  
✅ Calico est opérationnel (pods Running)  
✅ Pas de NetworkPolicies bloquantes  

## Configuration finale de l'Ingress

```yaml
annotations:
  nginx.ingress.kubernetes.io/proxy-body-size: "50m"
  nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
  nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
  nginx.ingress.kubernetes.io/proxy-connect-timeout: "60"  # ← Ajouté
```

## Test final

Après le redémarrage des pods NGINX Ingress, tester :
```bash
curl -v https://support.keybuzz.io
```

Le 504 devrait être résolu.

## Notes

- Le timeout de connexion par défaut de NGINX Ingress est de 5 secondes, ce qui peut être insuffisant dans certains cas de charge réseau ou de latence.
- L'augmentation du `proxy-connect-timeout` à 60 secondes permet à NGINX Ingress d'avoir plus de temps pour établir la connexion initiale vers les pods Chatwoot.
- Si le problème persiste, vérifier :
  1. Les logs NGINX Ingress : `kubectl logs -n ingress-nginx --selector=app=ingress-nginx --tail=50`
  2. La connectivité réseau entre les pods : `kubectl exec -n ingress-nginx <pod> -- wget -qO- --timeout=5 http://chatwoot-web.chatwoot.svc.cluster.local:3000`
  3. Les règles de firewall sur les nœuds Kubernetes

