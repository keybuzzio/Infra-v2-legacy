# Module 10 Platform - KeyBuzz API & Front - Validation

**Date de validation :** $(date '+%Y-%m-%d')  
**Statut :** ⏳ **EN ATTENTE DE DÉPLOIEMENT**

## Résumé

Le Module 10 Platform (KeyBuzz API, UI et My Portal) est prêt à être déployé sur le cluster K3s avec l'architecture **Deployment + Service ClusterIP + Ingress**.

## URLs

- **Platform API :** https://platform-api.keybuzz.io
- **Platform UI :** https://platform.keybuzz.io
- **My Portal :** https://my.keybuzz.io

## Architecture

### Approche choisie

- **Deployment** : 3 replicas minimum pour chaque application
- **Service ClusterIP** : Communication interne au cluster
- **Ingress** : Point d'entrée externe via NGINX Ingress Controller
- **HPA** : Autoscaling pour l'API (min: 3, max: 20)

### Pourquoi pas DaemonSet/hostNetwork ?

Contrairement à l'ancienne approche, nous utilisons maintenant les Services ClusterIP standard de Kubernetes, car :
- Les Services ClusterIP fonctionnent correctement dans notre environnement
- Meilleure isolation et sécurité réseau
- Gestion automatique de la répartition de charge
- Compatibilité avec les fonctionnalités Kubernetes standard

## Composants déployés

### 1. Platform API (platform-api.keybuzz.io)

- **Namespace :** `keybuzz`
- **Deployment :** `keybuzz-api` (3 réplicas minimum)
- **Service :** `keybuzz-api` (ClusterIP, port 8080)
- **HPA :** `keybuzz-api-hpa` (min: 3, max: 20)
- **Ingress :** `platform-api-ingress` (platform-api.keybuzz.io)
- **Image Docker :** `nginx:alpine` (placeholder - à remplacer par l'image Platform API réelle)
- **Port container :** 8080
- **Probes :**
  - `readinessProbe`: HTTP GET /health
  - `livenessProbe`: HTTP GET /health

**Variables d'environnement :**
- `DATABASE_URL`: postgresql://kb_app:<pass>@10.0.0.10:6432/keybuzz (PgBouncer)
- `REDIS_URL`: redis://10.0.0.10:6379
- `RABBITMQ_URL`: amqp://kb_rmq:<pass>@10.0.0.10:5672/
- `MINIO_ENDPOINT`: http://10.0.0.134:9000
- `MARIADB_HOST`: 10.0.0.20

### 2. Platform UI (platform.keybuzz.io)

- **Namespace :** `keybuzz`
- **Deployment :** `keybuzz-ui` (3 réplicas)
- **Service :** `keybuzz-ui` (ClusterIP, port 80)
- **Ingress :** `platform-ui-ingress` (platform.keybuzz.io)
- **Image Docker :** `nginx:alpine` (placeholder - à remplacer par l'image Platform UI réelle)
- **Port container :** 80
- **Probes :**
  - `readinessProbe`: HTTP GET /
  - `livenessProbe`: HTTP GET /

**Variables d'environnement :**
- `API_URL`: https://platform-api.keybuzz.io

### 3. My Portal (my.keybuzz.io)

- **Namespace :** `keybuzz`
- **Deployment :** `keybuzz-my-ui` (3 réplicas)
- **Service :** `keybuzz-my-ui` (ClusterIP, port 80)
- **Ingress :** `platform-my-ingress` (my.keybuzz.io)
- **Image Docker :** `nginx:alpine` (placeholder - à remplacer par l'image My Portal réelle)
- **Port container :** 80
- **Probes :**
  - `readinessProbe`: HTTP GET /
  - `livenessProbe`: HTTP GET /

**Variables d'environnement :**
- `API_URL`: https://platform-api.keybuzz.io

## Configuration Ingress

### IngressClass

- **Nom :** `nginx`
- **Controller :** `k8s.io/ingress-nginx`
- **Statut :** ✅ Créée automatiquement si nécessaire

### Ingress Rules

- **platform-api.keybuzz.io** → `keybuzz-api:8080`
- **platform.keybuzz.io** → `keybuzz-ui:80`
- **my.keybuzz.io** → `keybuzz-my-ui:80`

### Annotations

- `nginx.ingress.kubernetes.io/proxy-body-size: "50m"`
- `nginx.ingress.kubernetes.io/proxy-read-timeout: "300"` (API uniquement)
- `nginx.ingress.kubernetes.io/proxy-send-timeout: "300"` (API uniquement)

## Configuration Load Balancer Hetzner

### LB 1 (lb-keybuzz-1)
- **IP Publique :** 49.13.42.76
- **IP Privée :** 10.0.0.5
- **Service HTTPS :** 443 → 31695
- **Certificats :** platform.keybuzz.io, platform-api.keybuzz.io, my.keybuzz.io
- **Healthcheck :** `/healthz` (HTTP, port 31695, status 200)
- **Targets :** 8 nodes K3s (3 masters + 5 workers)

### LB 2 (lb-keybuzz-2)
- **IP Publique :** 138.199.132.240
- **IP Privée :** 10.0.0.6
- **Service HTTPS :** 443 → 31695
- **Certificats :** platform.keybuzz.io, platform-api.keybuzz.io, my.keybuzz.io
- **Healthcheck :** `/healthz` (HTTP, port 31695, status 200)
- **Targets :** 8 nodes K3s (3 masters + 5 workers)

## DNS Configuration

### Enregistrements A

- `platform.keybuzz.io` → 49.13.42.76, 138.199.132.240
- `platform-api.keybuzz.io` → 49.13.42.76, 138.199.132.240
- `my.keybuzz.io` → 49.13.42.76, 138.199.132.240
- **TTL :** 60 secondes

## Scripts créés

1. **`10_platform_00_setup_credentials.sh`** - Génération des credentials avec PgBouncer
2. **`10_platform_01_deploy_api.sh`** - Déploiement Platform API
3. **`10_platform_02_deploy_ui.sh`** - Déploiement Platform UI
4. **`10_platform_03_deploy_my.sh`** - Déploiement My Portal
5. **`10_platform_04_configure_ingress.sh`** - Configuration Ingress
6. **`10_platform_apply_all.sh`** - Script maître orchestration
7. **`validate_module10_platform.sh`** - Script de validation

## Tests de validation

### ✅ Tests à effectuer

1. **Deployments :**
   ```bash
   kubectl get deployment -n keybuzz
   # Doit afficher: keybuzz-api, keybuzz-ui, keybuzz-my-ui
   # Status: Available=True, Replicas >= 3
   ```

2. **Services :**
   ```bash
   kubectl get svc -n keybuzz
   # Doit afficher: keybuzz-api, keybuzz-ui, keybuzz-my-ui
   # Type: ClusterIP
   ```

3. **Ingress :**
   ```bash
   kubectl get ingress -n keybuzz
   # Doit afficher les 3 Ingress avec les hosts corrects
   ```

4. **Connectivité :**
   ```bash
   curl -k https://platform.keybuzz.io
   curl -k https://platform-api.keybuzz.io/health
   curl -k https://my.keybuzz.io
   ```

5. **Pods :**
   ```bash
   kubectl get pods -n keybuzz
   # Doit afficher au moins 9 pods Running (3 de chaque)
   ```

## ⚠️ Actions requises

1. **Images Docker :**
   - Remplacer `nginx:alpine` par les images Platform réelles :
     - `ghcr.io/keybuzz/platform-api:latest` (ou votre registry)
     - `ghcr.io/keybuzz/platform-ui:latest` (ou votre registry)
     - `ghcr.io/keybuzz/platform-my:latest` (ou votre registry)

2. **Healthchecks :**
   - Vérifier que les endpoints `/health` existent dans l'API
   - Ajuster les paths des probes si nécessaire

3. **Variables d'environnement :**
   - Vérifier que toutes les variables d'environnement dans les Secrets/ConfigMaps sont correctes
   - S'assurer que les URLs des services backend sont accessibles depuis les pods

4. **DNS :**
   - Configurer les enregistrements A pour les 3 domaines
   - Vérifier la propagation DNS

5. **Certificats TLS :**
   - Configurer les certificats SSL sur les Load Balancers Hetzner
   - Vérifier que les certificats couvrent les 3 domaines

## Prochaines étapes

1. ⏳ **Déployer le Module 10 Platform** : Exécuter `10_platform_apply_all.sh`
2. ⏳ **Valider le déploiement** : Exécuter `validate_module10_platform.sh`
3. ⏳ **Configurer les DNS** : Pointer les domaines vers les LB Hetzner
4. ⏳ **Tester les URLs publiques** : Vérifier l'accès via HTTPS
5. ⏭️ **Module 11** : n8n (Workflow Automation)

## Notes importantes

- Les images Docker actuelles sont des placeholders (`nginx:alpine`)
- Les healthchecks sont configurés mais peuvent nécessiter des ajustements selon les applications réelles
- Le SSL est géré par les Load Balancers Hetzner (SSL termination)
- Les Ingress n'ont pas d'annotations SSL redirect (géré par les LB)
- L'architecture utilise les Services ClusterIP standard (pas de hostNetwork)

---

**✅ Module 10 Platform prêt pour le déploiement !**

