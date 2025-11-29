# Configuration Load Balancer Hetzner pour support.keybuzz.io

## Problème actuel
- **Erreur 504 Gateway Timeout** pour `https://support.keybuzz.io`
- Chatwoot répond correctement (200 OK) en interne
- Le problème vient de la configuration du Load Balancer Hetzner

## Architecture

### Load Balancers Hetzner (IPs publiques)
- **LB 1** : `49.13.42.76` (IP publique)
- **LB 2** : `138.199.132.240` (IP publique)

### Backends Kubernetes (IPs privées)
Les Load Balancers Hetzner doivent pointer vers **tous les nœuds Kubernetes** (masters + workers) :

**Masters** :
- `k8s-master-01` : `10.0.0.100`
- `k8s-master-02` : `10.0.0.101`
- `k8s-master-03` : `10.0.0.102`

**Workers** :
- `k8s-worker-01` : `10.0.0.110`
- `k8s-worker-02` : `10.0.0.111`
- `k8s-worker-03` : `10.0.0.112`
- `k8s-worker-04` : `10.0.0.113`
- `k8s-worker-05` : `10.0.0.114`

## Configuration requise dans Hetzner Console

### Service HTTP (Port 80)

**Targets** (Backends) :
- `10.0.0.100:80` (k8s-master-01)
- `10.0.0.101:80` (k8s-master-02)
- `10.0.0.102:80` (k8s-master-03)
- `10.0.0.110:80` (k8s-worker-01)
- `10.0.0.111:80` (k8s-worker-02)
- `10.0.0.112:80` (k8s-worker-03)
- `10.0.0.113:80` (k8s-worker-04)
- `10.0.0.114:80` (k8s-worker-05)

**Health Check** :
- Type : `HTTP`
- Path : `/healthz`
- Port : `80`
- Interval : `10s`
- Timeout : `5s`
- Retries : `3`

### Service HTTPS (Port 443)

**Targets** (Backends) :
- `10.0.0.100:443` (k8s-master-01)
- `10.0.0.101:443` (k8s-master-02)
- `10.0.0.102:443` (k8s-master-03)
- `10.0.0.110:443` (k8s-worker-01)
- `10.0.0.111:443` (k8s-worker-02)
- `10.0.0.112:443` (k8s-worker-03)
- `10.0.0.113:443` (k8s-worker-04)
- `10.0.0.114:443` (k8s-worker-05)

**Health Check** :
- Type : `HTTPS` (ou `HTTP` si le LB supporte HTTPS health check)
- Path : `/healthz`
- Port : `443` (ou `80` si le health check se fait en HTTP)
- Interval : `10s`
- Timeout : `5s`
- Retries : `3`

**Note** : Certains Load Balancers Hetzner permettent de faire un health check HTTP sur le port 443, ou HTTPS sur le port 443. Vérifiez les options disponibles.

## Configuration DNS

Le DNS `support.keybuzz.io` doit pointer vers l'**IP publique du Load Balancer Hetzner** :
- `49.13.42.76` (LB 1) OU
- `138.199.132.240` (LB 2)

**Important** : Ne pointez JAMAIS le DNS directement vers un nœud Kubernetes. Toujours vers le Load Balancer Hetzner.

## Vérification

### 1. Vérifier que les nœuds répondent sur /healthz

```bash
# Depuis install-01
for node in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  echo "Testing $node..."
  ssh root@$node "curl -sS -m 3 http://localhost/healthz || echo 'FAIL'"
done
```

### 2. Vérifier la connectivité depuis le Load Balancer

Dans Hetzner Console → Load Balancer → Health Checks, vérifiez que tous les backends sont **healthy** (vert).

### 3. Tester depuis l'extérieur

```bash
curl -v https://support.keybuzz.io
```

## Notes importantes

1. **Les IPs 49.13.42.76 et 138.199.132.240 sont les IPs PUBLIQUES des Load Balancers Hetzner**, pas des backends.
2. **Les backends sont les IPs PRIVÉES des nœuds Kubernetes** (10.0.0.100-102, 10.0.0.110-114).
3. **NGINX Ingress Controller écoute directement sur les ports 80 et 443** de chaque nœud (via `hostPort`).
4. **Le health check `/healthz` est l'endpoint par défaut de NGINX Ingress Controller**.

## Si le 504 persiste

1. Vérifier les logs NGINX Ingress :
   ```bash
   kubectl logs -n ingress-nginx --selector=app=ingress-nginx --tail=50
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

