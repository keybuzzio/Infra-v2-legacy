# 📋 Guide - Étapes Suivantes Module 10

## ✅ Étape 1 — Remplacer les images nginx:alpine par les vraies images Platform

### Images actuelles (de test)
- **API** : `nginx:alpine` (port 8080, pas d'endpoint /health)
- **UI** : `nginx:alpine` (port 80, fonctionne)
- **My** : `nginx:alpine` (port 80, fonctionne)

### Mise à jour des images

**Option 1 : Utiliser le script automatique**

```bash
cd /opt/keybuzz-installer-v2/scripts/10_platform
./update_platform_images.sh \
  ghcr.io/keybuzz/platform-api:latest \
  ghcr.io/keybuzz/platform-ui:latest \
  ghcr.io/keybuzz/platform-my:latest
```

**Option 2 : Mise à jour manuelle**

```bash
export KUBECONFIG=/root/.kube/config

# API
kubectl set image deployment/keybuzz-api -n keybuzz \
  api=ghcr.io/keybuzz/platform-api:latest

# UI
kubectl set image deployment/keybuzz-ui -n keybuzz \
  ui=ghcr.io/keybuzz/platform-ui:latest

# My
kubectl set image deployment/keybuzz-my-ui -n keybuzz \
  my-ui=ghcr.io/keybuzz/platform-my:latest
```

### Vérification

```bash
# Vérifier les nouvelles images
kubectl get deployments -n keybuzz -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'

# Vérifier l'état des pods
kubectl get pods -n keybuzz -w

# Vérifier les health checks
kubectl logs -n keybuzz deployment/keybuzz-api | grep -i health
```

### Health Checks requis

L'API doit exposer :
- **Readiness** : `/health` ou `/healthz` (port 8080)
- **Liveness** : `/health` ou `/live` (port 8080)

Les Deployments sont déjà configurés avec :
```yaml
readinessProbe:
  httpGet:
    path: /health
    port: 8080
livenessProbe:
  httpGet:
    path: /health
    port: 8080
```

---

## ✅ Étape 2 — Configurer le DNS

### Enregistrements DNS requis

Dans votre fournisseur DNS (Cloudflare, etc.) :

| Hostname | Type | Valeur | TTL |
|----------|------|--------|-----|
| `platform.keybuzz.io` | A | IP publique du LB Hetzner | 300 |
| `platform-api.keybuzz.io` | A | IP publique du LB Hetzner | 300 |
| `my.keybuzz.io` | A | IP publique du LB Hetzner | 300 |

**⚠️ IMPORTANT** : Ne pointez JAMAIS un DNS directement vers un worker/master. Toujours → Hetzner LB ONLY.

### Vérification DNS

```bash
# Vérifier la résolution DNS
dig platform.keybuzz.io +short
dig platform-api.keybuzz.io +short
dig my.keybuzz.io +short

# Tous doivent retourner la même IP (celle du LB Hetzner)
```

---

## ✅ Étape 3 — Vérifier les certificats TLS

### Dans Hetzner Cloud Console

1. Aller dans **Load Balancers** → Votre LB
2. Section **Services** → **HTTPS**
3. Vérifier que les domaines sont configurés :
   - `platform.keybuzz.io` → Let's Encrypt VALID ✅
   - `platform-api.keybuzz.io` → Let's Encrypt VALID ✅
   - `my.keybuzz.io` → Let's Encrypt VALID ✅

### Si les certificats ne sont pas générés

1. Dans **HTTPS** → **Domains**
2. Ajouter les 3 domaines :
   - `platform.keybuzz.io`
   - `platform-api.keybuzz.io`
   - `my.keybuzz.io`
3. Le LB va générer les certificats automatiquement (Let's Encrypt)

### Vérification des certificats

```bash
# Vérifier les certificats
openssl s_client -connect platform.keybuzz.io:443 -servername platform.keybuzz.io < /dev/null 2>/dev/null | openssl x509 -noout -dates

# Les URLs doivent afficher un cadenas 🔒 vert dans le navigateur
```

---

## ✅ Étape 4 — (Optionnel) Ajouter un healthcheck Ingress dédié

### Créer un service de healthcheck interne

```bash
export KUBECONFIG=/root/.kube/config

# Créer un Deployment minimaliste
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: healthcheck
  namespace: keybuzz
spec:
  replicas: 1
  selector:
    matchLabels:
      app: healthcheck
  template:
    metadata:
      labels:
        app: healthcheck
    spec:
      containers:
      - name: healthcheck
        image: nginx:alpine
        ports:
        - containerPort: 80
        volumeMounts:
        - name: config
          mountPath: /etc/nginx/conf.d
      volumes:
      - name: config
        configMap:
          name: healthcheck-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: healthcheck-config
  namespace: keybuzz
data:
  default.conf: |
    server {
        listen 80;
        location /healthz {
            return 200 "OK\n";
            add_header Content-Type text/plain;
        }
    }
---
apiVersion: v1
kind: Service
metadata:
  name: healthcheck
  namespace: keybuzz
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
  selector:
    app: healthcheck
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: healthcheck-ingress
  namespace: keybuzz
spec:
  ingressClassName: nginx
  rules:
  - host: health.keybuzz.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: healthcheck
            port:
              number: 80
EOF
```

### Configurer le healthcheck dans Hetzner LB

1. Dans **Load Balancers** → Votre LB
2. Section **Health Checks**
3. Ajouter un health check :
   - **Type** : HTTP
   - **Path** : `/healthz`
   - **Domain** : `health.keybuzz.io`
   - **Port** : 443 (HTTPS)
   - **Interval** : 10s

---

## 📊 Checklist de Validation Finale

- [ ] Images Platform remplacées (pas nginx:alpine)
- [ ] Tous les pods sont Ready (3/3 pour chaque Deployment)
- [ ] Health checks fonctionnent (`/health` ou `/healthz`)
- [ ] DNS configurés (platform.*, platform-api.*, my.*)
- [ ] Certificats TLS valides (Let's Encrypt)
- [ ] URLs accessibles en HTTPS avec cadenas vert 🔒
- [ ] Healthcheck interne configuré (optionnel)

---

## 🚀 Commandes Utiles

### Vérifier l'état complet

```bash
export KUBECONFIG=/root/.kube/config

# Deployments
kubectl get deployments -n keybuzz

# Services
kubectl get services -n keybuzz

# Ingress
kubectl get ingress -n keybuzz

# Pods
kubectl get pods -n keybuzz

# Logs API
kubectl logs -n keybuzz deployment/keybuzz-api --tail=50

# Logs UI
kubectl logs -n keybuzz deployment/keybuzz-ui --tail=50
```

### Tester les endpoints

```bash
# Depuis un pod de test
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- \
  sh -c "curl -k https://platform-api.keybuzz.io/health"

# Depuis install-01
curl -k https://platform.keybuzz.io
curl -k https://platform-api.keybuzz.io/health
curl -k https://my.keybuzz.io
```

---

*Guide généré le $(date '+%Y-%m-%d %H:%M:%S')*

