# Module 11 - n8n (Workflow Automation)

## 🎯 Objectif

Déployer n8n sur le cluster K3s HA pour l'automatisation des workflows, la synchronisation ERPNext ↔ KeyBuzz, et les connecteurs marketplaces.

## 📋 Architecture

### Composants
- **n8n** : Deployment (stateless, 3+ réplicas)
- **HPA** : Horizontal Pod Autoscaler (min: 3, max: 20)
- **Namespace** : `n8n`
- **Ingress** : `n8n.keybuzz.io`
- **Base de données** : PostgreSQL HA (via PgBouncer port 4632 ou direct 5432)
- **Queue** : Redis HA (Bull queue pour executions)

### Configuration

#### Variables d'environnement principales
- `DB_TYPE=postgresdb`
- `DB_POSTGRESDB_HOST=10.0.0.10` (LB PostgreSQL)
- `DB_POSTGRESDB_PORT=4632` (PgBouncer) ou `5432` (direct)
- `DB_POSTGRESDB_DATABASE=n8n`
- `DB_POSTGRESDB_USER=n8n`
- `DB_POSTGRESDB_PASSWORD=<pass>`
- `QUEUE_BULL_REDIS_HOST=10.0.0.10` (LB Redis)
- `QUEUE_BULL_REDIS_PORT=6379`
- `QUEUE_BULL_REDIS_PASSWORD=<pass>`
- `EXECUTIONS_MODE=queue` (utilise Redis Bull)
- `WEBHOOK_URL=https://n8n.keybuzz.io/`
- `N8N_ENCRYPTION_KEY=<32 bytes hex>`
- `N8N_LOG_LEVEL=info`
- `TZ=Europe/Paris`

### Ports
- **Container** : 5678 (n8n par défaut)
- **Service** : 80 (ClusterIP)
- **Ingress** : HTTPS via LB Hetzner

## 📝 Scripts

1. **`11_n8n_00_setup_credentials.sh`**
   - Génère ou charge les credentials n8n
   - Crée l'utilisateur PostgreSQL `n8n` et la base `n8n`
   - Génère `N8N_ENCRYPTION_KEY`
   - Génère le fichier `n8n.env`

2. **`11_n8n_01_deploy.sh`**
   - Crée le namespace `n8n`
   - Crée le Secret Kubernetes avec les credentials
   - Déploie le Deployment n8n (3 réplicas)
   - Crée le Service ClusterIP
   - Configure le HPA (min: 3, max: 20)

3. **`11_n8n_02_configure_ingress.sh`**
   - Configure l'Ingress pour `n8n.keybuzz.io`
   - Point vers le service n8n

4. **`11_n8n_03_tests.sh`**
   - Tests de connectivité
   - Tests de base de données
   - Tests Redis queue
   - Tests Ingress
   - Validation complète

5. **`11_n8n_apply_all.sh`**
   - Script master qui orchestre tous les scripts

## 🔗 Intégrations

### PostgreSQL HA
- **Utilisation** : Base de données principale n8n
- **Accès** : Via PgBouncer (port 4632) ou direct (port 5432)
- **Base** : `n8n`
- **User** : `n8n`

### Redis HA
- **Utilisation** : Queue Bull pour les executions
- **Accès** : Via LB Redis (10.0.0.10:6379)
- **Mode** : `EXECUTIONS_MODE=queue`

## 🌐 URLs

- **n8n** : https://n8n.keybuzz.io

## ⚠️ Notes Importantes

### Base de données
- La base `n8n` et l'utilisateur `n8n` doivent être créés dans PostgreSQL HA
- Utiliser PgBouncer (port 4632) pour le pooling de connexions
- Ou utiliser le port direct 5432 si préféré

### Queue Redis
- **Critique** : `EXECUTIONS_MODE=queue` doit être configuré
- Sinon, les executions s'exécutent en mode "main process" (non scalable)

### Encryption Key
- `N8N_ENCRYPTION_KEY` doit être unique et sécurisé (32 bytes hex)
- Ne jamais régénérer après déploiement (perte de données encryptées)

### HPA
- HPA configuré pour CPU (70%) et Memory (80%)
- Min: 3 réplicas (haute disponibilité)
- Max: 20 réplicas (scalabilité)

## 📚 Documentation

- **Context.txt** : Section 4.4 (n8n orchestration workflows)
- **Validation** : `MODULE11_VALIDATION.md` (à créer après installation)

## ✅ Prérequis

- ✅ Module 3 : PostgreSQL HA installé
- ✅ Module 4 : Redis HA installé
- ✅ Module 9 : K3s HA installé
- ✅ Module 10 : KeyBuzz API & Front (optionnel, pour intégrations)

---

**Statut** : 📝 Scripts à créer

