# Configuration Load Balancer Hetzner - Correction 504 Gateway Timeout

## ❌ Configuration INCORRECTE (actuelle)

Vous avez mentionné :
- HTTPS 443 → HTTP 80 des LB (49.13.42.76 et 138.199.132.240) avec /healthz
- HTTP 80 → HTTP 80 des LB (49.13.42.76 et 138.199.132.240) avec /healthz

**Problème** : Les IPs `49.13.42.76` et `138.199.132.240` sont les **IPs PUBLIQUES** des Load Balancers Hetzner, pas des backends.

## ✅ Configuration CORRECTE

### Load Balancers Hetzner (IPs publiques)
- **LB 1** : `49.13.42.76` (IP publique)
- **LB 2** : `138.199.132.240` (IP publique)

### Backends Kubernetes (IPs privées)

Les Load Balancers Hetzner doivent pointer vers les **IPs PRIVÉES** des nœuds Kubernetes :

**Masters** :
- `10.0.0.100:80` et `10.0.0.100:443` (k8s-master-01)
- `10.0.0.101:80` et `10.0.0.101:443` (k8s-master-02)
- `10.0.0.102:80` et `10.0.0.102:443` (k8s-master-03)

**Workers** :
- `10.0.0.110:80` et `10.0.0.110:443` (k8s-worker-01)
- `10.0.0.111:80` et `10.0.0.111:443` (k8s-worker-02)
- `10.0.0.112:80` et `10.0.0.112:443` (k8s-worker-03)
- `10.0.0.113:80` et `10.0.0.113:443` (k8s-worker-04)
- `10.0.0.114:80` et `10.0.0.114:443` (k8s-worker-05)

## 📋 Configuration dans Hetzner Console

### Service HTTP (Port 80)

1. **Targets** (Backends) :
   ```
   10.0.0.100:80
   10.0.0.101:80
   10.0.0.102:80
   10.0.0.110:80
   10.0.0.111:80
   10.0.0.112:80
   10.0.0.113:80
   10.0.0.114:80
   ```

2. **Health Check** :
   - Type : `HTTP`
   - Path : `/healthz`
   - Port : `80`
   - Interval : `10s`
   - Timeout : `5s`
   - Retries : `3`

### Service HTTPS (Port 443)

1. **Targets** (Backends) :
   ```
   10.0.0.100:443
   10.0.0.101:443
   10.0.0.102:443
   10.0.0.110:443
   10.0.0.111:443
   10.0.0.112:443
   10.0.0.113:443
   10.0.0.114:443
   ```

2. **Health Check** :
   - Type : `HTTP` (ou `HTTPS` si supporté)
   - Path : `/healthz`
   - Port : `80` (pour un health check HTTP, même si le service est HTTPS 443)
   - **OU** Port : `443` (si le LB supporte un health check HTTPS)
   - Interval : `10s`
   - Timeout : `5s`
   - Retries : `3`

   **Note** : Certains Load Balancers Hetzner permettent de faire un health check HTTP sur le port 80 même pour le service HTTPS 443. C'est une configuration courante et recommandée.

## 🔍 Vérification

### 1. Vérifier que les nœuds répondent sur /healthz

Depuis `install-01` :
```bash
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  echo "Testing $ip..."
  ssh root@$ip "curl -sS -m 3 http://localhost/healthz || echo 'FAIL'"
done
```

### 2. Vérifier dans Hetzner Console

Dans **Hetzner Console → Load Balancer → Health Checks** :
- Tous les backends doivent être **healthy** (vert)
- Si un backend est **unhealthy** (rouge), vérifiez :
  - Que le nœud est accessible depuis le réseau privé Hetzner
  - Que NGINX Ingress Controller est bien déployé sur ce nœud
  - Que le port 80/443 est bien ouvert

### 3. Tester depuis l'extérieur

```bash
curl -v https://support.keybuzz.io
```

## ⚠️ Points importants

1. **Les IPs 49.13.42.76 et 138.199.132.240 sont les IPs PUBLIQUES des Load Balancers**, pas des backends.
2. **Les backends sont les IPs PRIVÉES des nœuds Kubernetes** (10.0.0.100-102, 10.0.0.110-114).
3. **NGINX Ingress Controller écoute directement sur les ports 80 et 443** de chaque nœud (via `hostPort`).
4. **Le health check `/healthz` est l'endpoint par défaut de NGINX Ingress Controller**.
5. **Le DNS `support.keybuzz.io` doit pointer vers l'IP PUBLIQUE du Load Balancer** (49.13.42.76 ou 138.199.132.240), **JAMAIS** vers un nœud directement.

## 🐛 Si le 504 persiste après cette configuration

1. Vérifier les logs NGINX Ingress :
   ```bash
   kubectl logs -n ingress-nginx --selector=app=ingress-nginx --tail=50 | grep -i "support\|chatwoot\|504\|timeout"
   ```

2. Vérifier que les pods Chatwoot sont bien Running :
   ```bash
   kubectl get pods -n chatwoot
   ```

3. Vérifier que l'Ingress est bien configuré :
   ```bash
   kubectl get ingress -n chatwoot -o yaml
   ```

4. Tester directement depuis un nœud :
   ```bash
   curl -H "Host: support.keybuzz.io" http://localhost/
   ```

