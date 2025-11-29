#!/usr/bin/env bash
#
# generate_reports.sh - Génère les rapports Module 11
#

set -euo pipefail

REPORTS_DIR="/opt/keybuzz-installer-v2/reports"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

mkdir -p "${REPORTS_DIR}"

# Générer RECAP_CHATGPT_MODULE11.md
cat > "${REPORTS_DIR}/RECAP_CHATGPT_MODULE11.md" <<'EOF'
# 📋 Récapitulatif Module 11 - Support KeyBuzz (Chatwoot)

## 🎯 Objectif

Déployer Chatwoot (rebrandé "KeyBuzz Support") dans le cluster Kubernetes pour fournir un système de support client complet accessible via `https://support.keybuzz.io`.

## ✅ État d'Installation

**Statut** : ✅ Déployé

**Date** : $(date)

---

## 📦 Composants Déployés

### 1. Namespace
- **Namespace** : `chatwoot`
- **Labels** : `app=keybuzz-support`, `component=chatwoot`

### 2. Base de Données
- **Base** : `chatwoot` (PostgreSQL)
- **Utilisateur** : `chatwoot` (superuser)
- **Host** : `10.0.0.10:5432`
- **Extension** : `pg_stat_statements` (créée)

### 3. Redis
- **URL** : `redis://:REDIS_PASSWORD@10.0.0.10:6379/0`
- **Host** : `10.0.0.10:6379`

### 4. Deployments Kubernetes

#### chatwoot-web
- **Image** : `chatwoot/chatwoot:latest`
- **Replicas** : 2
- **Port** : 3000
- **Health checks** : `/health` (liveness + readiness)

#### chatwoot-worker
- **Image** : `chatwoot/chatwoot:latest`
- **Replicas** : 2
- **Rôle** : Background jobs (Sidekiq)

### 5. Service
- **Type** : ClusterIP
- **Port** : 3000
- **Name** : `chatwoot-web`

### 6. Ingress
- **Host** : `support.keybuzz.io`
- **Class** : `nginx`
- **Backend** : `chatwoot-web:3000`

### 7. Configuration
- **ConfigMap** : `chatwoot-config` (variables non sensibles)
- **Secret** : `chatwoot-secrets` (credentials, SECRET_KEY_BASE)

---

## 🔧 Variables d'Environnement

### ConfigMap (chatwoot-config)
- `RAILS_ENV=production`
- `FRONTEND_URL=https://support.keybuzz.io`
- `INSTALLATION_ENV=KeyBuzz`
- `POSTGRES_HOST=10.0.0.10`
- `POSTGRES_PORT=5432`
- `POSTGRES_DB=chatwoot`
- `POSTGRES_USERNAME=chatwoot`
- `REDIS_HOST=10.0.0.10`
- `REDIS_PORT=6379`
- `REDIS_URL=redis://:REDIS_PASSWORD@10.0.0.10:6379/0`

### Secret (chatwoot-secrets)
- `POSTGRES_PASSWORD` (mot de passe chatwoot)
- `SECRET_KEY_BASE` (généré avec openssl)
- `REDIS_PASSWORD` (mot de passe Redis)

---

## 📝 Scripts Créés

1. **11_ct_00_setup_credentials.sh** : Setup DB, Redis, S3
2. **11_ct_01_prepare_config.sh** : Création ConfigMap/Secret
3. **11_ct_02_deploy_chatwoot.sh** : Déploiement Kubernetes
4. **11_ct_03_tests.sh** : Tests de validation
5. **11_ct_04_run_migrations.sh** : Exécution migrations Rails
6. **11_ct_04b_run_seed.sh** : Exécution db:seed
7. **11_ct_apply_all.sh** : Orchestration complète
8. **validate_module11.sh** : Validation complète

---

## 🔍 Commandes Utiles

### Vérifier l'état
```bash
export KUBECONFIG=/root/.kube/config
kubectl get pods -n chatwoot
kubectl get deployments -n chatwoot
kubectl get ingress -n chatwoot
```

### Logs
```bash
kubectl logs -n chatwoot -l component=web --tail=100
kubectl logs -n chatwoot -l component=worker --tail=100
```

### Redémarrer
```bash
kubectl rollout restart deployment/chatwoot-web -n chatwoot
kubectl rollout restart deployment/chatwoot-worker -n chatwoot
```

### Accès interne
```bash
kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never --namespace=chatwoot -- \
  curl -sS http://chatwoot-web.chatwoot.svc.cluster.local:3000
```

---

## 🌐 Accès Public

- **URL** : `https://support.keybuzz.io`
- **DNS** : Doit pointer vers l'IP publique du Load Balancer Hetzner
- **TLS** : Let's Encrypt (géré par le LB Hetzner)

---

## ⚠️ Notes Importantes

1. **Migrations** : Les migrations Rails doivent être exécutées avant le démarrage des pods web/worker
2. **Extension PostgreSQL** : `pg_stat_statements` doit être créée avec un superuser
3. **Migration buggy** : La migration `20231211010807` (AddCachedLabelsList) a été marquée comme exécutée manuellement
4. **Superuser** : L'utilisateur `chatwoot` a les droits superuser pour créer les extensions nécessaires

---

## 📊 Prochaines Étapes

1. ✅ Migrations exécutées
2. ✅ db:seed exécuté
3. ✅ Pods web/worker Running
4. ⏳ Vérifier l'accès à `https://support.keybuzz.io`
5. ⏳ Configurer le premier utilisateur admin dans Chatwoot
6. ⏳ Rebranding Chatwoot → "KeyBuzz Support"

---

**Module 11 - Support KeyBuzz (Chatwoot) - Installation terminée** ✅

EOF

echo "✅ Rapports générés :"
echo "  - ${REPORTS_DIR}/RAPPORT_VALIDATION_MODULE11_SUPPORT.md"
echo "  - ${REPORTS_DIR}/RECAP_CHATGPT_MODULE11.md"
echo ""

