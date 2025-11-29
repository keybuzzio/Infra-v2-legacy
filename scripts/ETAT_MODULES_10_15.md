# État des Modules 10-15 - Applications KeyBuzz

**Date de création** : 24 novembre 2024  
**Statut** : 🔄 **Installation en cours**

---

## 📋 Modules d'Applications KeyBuzz

### Module 10 : KeyBuzz API & Front
**Statut** : 🔄 **INSTALLATION EN COURS**  
**Date de début** : 2025-11-24 16:34 UTC

**Composants** :
- KeyBuzz API (DaemonSet hostNetwork, port 8080)
- KeyBuzz Front (DaemonSet hostNetwork, port 3000)
- Services NodePort (30080 pour API, 30000 pour Front)
- Ingress (platform.keybuzz.io, platform-api.keybuzz.io)

**Scripts** :
- `10_keybuzz_00_setup_credentials.sh` - Configuration credentials
- `10_keybuzz_01_deploy_daemonsets.sh` - Déploiement DaemonSets
- `10_keybuzz_02_configure_ingress.sh` - Configuration Ingress
- `10_keybuzz_03_tests.sh` - Tests de validation
- `10_keybuzz_apply_all.sh` - Script master

**Logs** : `/tmp/module10_installation_*.log`

---

### Module 11 : n8n Workflows
**Statut** : ⏳ **EN ATTENTE** (Module 10 en cours)

**Composants** :
- n8n (Deployment dans namespace n8n)
- Configuration Ingress
- Connexion PostgreSQL et Redis

**Scripts** :
- `11_n8n_00_setup_credentials.sh` - Configuration credentials
- `11_n8n_01_deploy.sh` - Déploiement n8n
- `11_n8n_02_configure_ingress.sh` - Configuration Ingress
- `11_n8n_03_tests.sh` - Tests de validation
- `11_n8n_apply_all.sh` - Script master

---

### Module 12 : Chatwoot KeyBuzzifié
**Statut** : ⏳ **EN ATTENTE** (Modules précédents)

**Composants** :
- Chatwoot rebrandé (Deployment dans namespace chatwoot)
- Configuration Ingress
- Connexion PostgreSQL et Redis

**Namespace** : `chatwoot` (déjà créé dans Module 9)

---

### Module 13 : LiteLLM / Services IA
**Statut** : ⏳ **EN ATTENTE** (Modules précédents)

**Composants** :
- LiteLLM (Deployment dans namespace ai)
- Services IA (Deployment dans namespace ai)
- Configuration Ingress

**Namespace** : `ai` (déjà créé dans Module 9)

---

### Module 14 : Analytics (Superset)
**Statut** : ⏳ **EN ATTENTE** (Modules précédents)

**Composants** :
- Superset (Deployment dans namespace analytics)
- Configuration Ingress
- Connexion PostgreSQL

**Namespace** : `analytics` (déjà créé dans Module 9)

---

### Module 15 : Workplace & Backoffice Admin
**Statut** : ⏳ **EN ATTENTE** (Modules précédents)

**Composants** :
- Workplace (Deployment dans namespace keybuzz)
- Backoffice Admin (Deployment dans namespace keybuzz)
- Configuration Ingress

**Namespace** : `keybuzz` (déjà créé dans Module 9)

---

## 🔒 Règles Définitives - Infrastructure

**⚠️ IMPORTANT** : L'infrastructure (Modules 2-9) est **DÉFINITIVEMENT TERMINÉE** et ne doit **PAS** être modifiée :

- ✅ **Module 2-9** : Infrastructure stable, ne plus modifier
- ✅ **K3s** : Cluster HA opérationnel (8 nœuds)
- ✅ **Ingress NGINX** : DaemonSet hostNetwork (obligatoire)
- ✅ **Services backend** : Endpoints fixes (10.0.0.10, 10.0.0.20, 10.0.0.134)
- ✅ **Load Balancers** : LB Hetzner 10.0.0.5/10.0.0.6 pour HTTPS publics

---

## 📝 Notes d'Installation

### Endpoints Backend (Obligatoires)
Tous les services doivent utiliser ces endpoints :
- **PostgreSQL** : `10.0.0.10:5432`
- **PgBouncer** : `10.0.0.10:6432`
- **Redis** : `10.0.0.10:6379`
- **RabbitMQ** : `10.0.0.10:5672`
- **MariaDB** : `10.0.0.20:3306`
- **MinIO** : `10.0.0.134:9000`

### Namespaces Disponibles
- `keybuzz` : Applications KeyBuzz principales
- `chatwoot` : Chatwoot rebrandé
- `n8n` : n8n Workflows
- `analytics` : Analytics et reporting
- `ai` : Services IA
- `vault` : Vault Agent
- `monitoring` : Prometheus Stack

---

**Dernière mise à jour** : 24 novembre 2024 16:35 UTC

