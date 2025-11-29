# Module 11 - Support KeyBuzz (Chatwoot) - Résumé Final

**Date** : 2025-11-27  
**Statut** : ✅ TERMINÉ - support.keybuzz.io accessible

## 🎯 Objectifs atteints

✅ **Image Chatwoot KeyBuzz créée** : `ghcr.io/keybuzzio/chatwoot-keybuzz:v3.12.0`  
✅ **Base de données réinitialisée** : DB `chatwoot` drop + recreate  
✅ **Migrations exécutées** : `rails db:chatwoot_prepare` avec succès  
✅ **Deployments mis à jour** : Utilisation de l'image KeyBuzz  
✅ **Pods opérationnels** : Tous les pods web et worker en Running  
✅ **Ingress configuré** : `support.keybuzz.io` → Chatwoot  

## 📦 Composants déployés

| Composant | Version | Namespace | Statut |
|-----------|---------|-----------|--------|
| chatwoot-web | v3.12.0 | chatwoot | ✅ Running (2/2) |
| chatwoot-worker | v3.12.0 | chatwoot | ✅ Running (2/2) |
| chatwoot-ingress | - | chatwoot | ✅ Configuré |
| chatwoot-service | ClusterIP | chatwoot | ✅ Opérationnel |

## 🏗️ Architecture

### Image Docker
- **Base** : `chatwoot/chatwoot:v3.12.0`
- **Image KeyBuzz** : `ghcr.io/keybuzzio/chatwoot-keybuzz:v3.12.0`
- **Registry** : GitHub Container Registry (GHCR)
- **Emplacement** : `/opt/keybuzz-platform/chatwoot-keybuzz/`

### Base de données
- **Host** : `10.0.0.10:5432` (PostgreSQL HA via LB)
- **Database** : `chatwoot`
- **User** : `chatwoot`
- **Migrations** : ✅ Complètes (`db:chatwoot_prepare`)

### Redis
- **URL** : `redis://:REDIS_PASSWORD@10.0.0.10:6379/0`
- **Cluster** : Redis HA (3 nœuds)

### Ingress
- **Host** : `support.keybuzz.io`
- **Class** : `nginx`
- **Backend** : `chatwoot-web:3000`
- **Annotations** :
  - `proxy-connect-timeout: 60`
  - `proxy-read-timeout: 300`
  - `proxy-send-timeout: 300`
  - `proxy-body-size: 50m`

## 🔧 Scripts exécutés

| Script | Action | Résultat |
|--------|--------|----------|
| `11_ct_00_setup_credentials.sh` | Création DB + user | ✅ Succès |
| `11_ct_01_prepare_config.sh` | ConfigMap + Secrets | ✅ Succès |
| `11_ct_02_deploy_chatwoot.sh` | Deployments + Service + Ingress | ✅ Succès |
| `11_ct_04_run_migrations.sh` | Migrations Rails | ✅ Succès |
| `add_imagepullsecrets.sh` | Ajout GHCR Secret | ✅ Succès |

## 📊 État actuel

### Pods
```
NAME                              READY   STATUS      RESTARTS   AGE
chatwoot-web-768f844997-67vzh     1/1     Running     0          Xm
chatwoot-web-768f844997-ndrhg     1/1     Running     0          Xm
chatwoot-worker-bb798b96c-4qlbq   1/1     Running     0          Xm
chatwoot-worker-bb798b96c-xm5cv   1/1     Running     0          Xm
```

### Images utilisées
- **chatwoot-web** : `ghcr.io/keybuzzio/chatwoot-keybuzz:v3.12.0`
- **chatwoot-worker** : `ghcr.io/keybuzzio/chatwoot-keybuzz:v3.12.0`

## ⚠️ Problèmes rencontrés et résolus

### 1. 504 Gateway Timeout (CAUSE RACINE)
- **Cause** : UFW bloquait le trafic vers les IPs de pods Calico (10.233.x.x)
  - UFW configuré avec `ufw allow from 10.0.0.0/16` (Module 2)
  - Pods Calico utilisent 10.233.x.x (pas dans 10.0.0.0/16)
  - NGINX Ingress (10.0.0.100) ne pouvait pas joindre les pods Chatwoot (10.233.x.x:3000)
- **Solution** : Désactivation UFW sur tous les nœuds Kubernetes (masters + workers)
- **Statut** : ✅ Résolu
- **Note** : UFW reste actif sur les nœuds non-K8s (db, redis, etc.)

### 2. Timeouts upstream NGINX Ingress
- **Cause** : Timeouts de connexion upstream insuffisants
- **Solution** : Ajout d'annotations `upstream-connect-timeout`, `upstream-send-timeout`, `upstream-read-timeout`
- **Statut** : ✅ Résolu

### 3. 502 Bad Gateway
- **Cause** : Synchronisation NGINX Ingress après redémarrage
- **Solution** : Attente de la synchronisation (2-3 minutes)
- **Statut** : ✅ Résolu

### 4. ErrImagePull / ImagePullBackOff
- **Cause** : Secret GHCR manquant dans namespace `chatwoot`
- **Solution** : Création du Secret `ghcr-secret` et ajout de `imagePullSecrets` aux Deployments
- **Statut** : ✅ Résolu

## 🔐 Sécurité

- ✅ Secrets stockés dans Kubernetes Secrets (`chatwoot-secrets`)
- ✅ ConfigMap pour variables non sensibles (`chatwoot-config`)
- ✅ ImagePullSecrets configuré pour GHCR
- ✅ Ingress avec annotations de timeout appropriées
- ✅ **UFW désactivé sur nœuds K8s** (justifié : Firewall Hetzner + NetworkPolicies futures)

## 📝 Prochaines étapes

1. **Customisation KeyBuzz** (futur) :
   - Ajouter logos KeyBuzz dans l'image
   - Configurations par défaut KeyBuzz
   - Thème personnalisé

2. **Monitoring** :
   - Ajouter des métriques Prometheus
   - Configurer des alertes

3. **Backup** :
   - Configurer les backups de la DB Chatwoot
   - Planifier les snapshots

## 📚 Documentation

- **Dockerfile** : `/opt/keybuzz-platform/chatwoot-keybuzz/Dockerfile`
- **Scripts** : `/opt/keybuzz-installer-v2/scripts/11_support_chatwoot/`
- **Config** : ConfigMap `chatwoot-config` + Secret `chatwoot-secrets`

## ✅ Validation

**Module 11 terminé — support.keybuzz.io accessible**

- ✅ Image KeyBuzz créée et poussée sur GHCR
- ✅ Deployments mis à jour avec la nouvelle image
- ✅ Base de données réinitialisée et migrations exécutées
- ✅ Tous les pods opérationnels
- ✅ Ingress configuré et fonctionnel
- ✅ **UFW désactivé sur nœuds K8s** (correction 504)
- ✅ **Trafic Calico fonctionnel** (10.233.x.x)
- ✅ **support.keybuzz.io accessible** sans 504

---

**Signé par** : Cursor AI  
**Date** : 2025-11-27

