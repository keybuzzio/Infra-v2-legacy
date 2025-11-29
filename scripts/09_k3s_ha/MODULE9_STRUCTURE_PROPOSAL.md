# Proposition de Structure Modulaire pour Applications KeyBuzz

**Date** : 20 novembre 2025  
**Auteur** : Infrastructure KeyBuzz

## 🎯 Objectif

Séparer les installations applicatives en modules distincts pour :
- ✅ Meilleur contrôle de chaque installation
- ✅ Validation individuelle avant passage à la suivante
- ✅ Facilité de maintenance et debugging
- ✅ Installation sélective selon les besoins
- ✅ Isolation des problèmes

## 📋 Structure Proposée

### Module 9 : K3s HA Core (✅ Créé)
**Contenu** :
- Control-plane HA (3 masters)
- Workers
- Addons bootstrap (CoreDNS, metrics-server, StorageClass)
- Ingress NGINX DaemonSet
- Namespaces de base
- ConfigMap avec endpoints services backend
- Monitoring K3s (Prometheus Stack)

**Statut** : ✅ Scripts créés

---

### Module 10 : KeyBuzz API & Front
**Contenu** :
- KeyBuzz API (Deployment + HPA)
- KeyBuzz Front/UI (Deployment + HPA)
- Secrets et ConfigMaps
- Ingress pour API et Front
- Tests de connectivité
- Validation

**Scripts à créer** :
- `10_keybuzz_00_setup_credentials.sh`
- `10_keybuzz_01_deploy_api.sh`
- `10_keybuzz_02_deploy_front.sh`
- `10_keybuzz_03_configure_ingress.sh`
- `10_keybuzz_04_tests.sh`
- `10_keybuzz_apply_all.sh`

---

### Module 11 : Chatwoot
**Contenu** :
- Chatwoot rebrandé (StatefulSet ou Deployment)
- Configuration Redis/PostgreSQL
- Ingress pour Chatwoot
- Tests de connectivité
- Validation

**Scripts à créer** :
- `11_chatwoot_00_setup_credentials.sh`
- `11_chatwoot_01_deploy.sh`
- `11_chatwoot_02_configure_ingress.sh`
- `11_chatwoot_03_tests.sh`
- `11_chatwoot_apply_all.sh`

---

### Module 12 : n8n Workflows
**Contenu** :
- n8n (Deployment, pas StatefulSet)
- Configuration base de données
- Ingress pour n8n
- Tests de connectivité
- Validation

**Scripts à créer** :
- `12_n8n_00_setup_credentials.sh`
- `12_n8n_01_deploy.sh`
- `12_n8n_02_configure_ingress.sh`
- `12_n8n_03_tests.sh`
- `12_n8n_apply_all.sh`

---

### Module 13 : Superset
**Contenu** :
- Superset (Deployment)
- Configuration base de données
- Ingress pour Superset
- Tests de connectivité
- Validation

**Scripts à créer** :
- `13_superset_00_setup_credentials.sh`
- `13_superset_01_deploy.sh`
- `13_superset_02_configure_ingress.sh`
- `13_superset_03_tests.sh`
- `13_superset_apply_all.sh`

---

### Module 14 : Vault Agent
**Contenu** :
- Vault Agent (DaemonSet ou Deployment)
- Configuration secrets management
- Injection automatique dans pods
- Tests de fonctionnement
- Validation

**Scripts à créer** :
- `14_vault_00_setup_credentials.sh`
- `14_vault_01_deploy.sh`
- `14_vault_02_configure_injection.sh`
- `14_vault_03_tests.sh`
- `14_vault_apply_all.sh`

---

### Module 15 : LiteLLM & Services IA
**Contenu** :
- LiteLLM Proxy (Deployment)
- Services IA (Deployment)
- Configuration API keys
- Ingress pour services IA
- Tests de connectivité
- Validation

**Scripts à créer** :
- `15_llm_00_setup_credentials.sh`
- `15_llm_01_deploy_litellm.sh`
- `15_llm_02_deploy_services.sh`
- `15_llm_03_configure_ingress.sh`
- `15_llm_04_tests.sh`
- `15_llm_apply_all.sh`

---

## ✅ Avantages de cette Structure

### 1. Contrôle Granulaire
- Chaque application peut être installée indépendamment
- Validation avant passage à la suivante
- Rollback facile si problème

### 2. Maintenance Simplifiée
- Mise à jour d'une application sans impacter les autres
- Debugging isolé par application
- Tests ciblés par module

### 3. Installation Sélective
- Installer uniquement les applications nécessaires
- Développement progressif
- Environnements différents (dev/staging/prod)

### 4. Documentation Claire
- Un fichier de validation par module
- README spécifique à chaque application
- Troubleshooting ciblé

## 📊 Ordre d'Installation Recommandé

1. **Module 9** : K3s HA Core (✅ Prêt)
2. **Module 10** : KeyBuzz API & Front (priorité 1)
3. **Module 11** : Chatwoot (priorité 2)
4. **Module 12** : n8n (priorité 3)
5. **Module 13** : Superset (optionnel)
6. **Module 14** : Vault Agent (recommandé)
7. **Module 15** : LiteLLM & Services IA (optionnel)

## 🔄 Intégration avec Master Script

Le `00_master_install.sh` peut appeler chaque module individuellement :

```bash
# Installation complète
./00_master_install.sh

# Installation sélective
./00_master_install.sh --module 9   # K3s Core
./00_master_install.sh --module 10  # KeyBuzz API/Front
./00_master_install.sh --module 11  # Chatwoot
# etc.
```

## 📝 Fichiers de Validation

Chaque module applicatif aura son propre fichier de validation :
- `MODULE10_VALIDATION.md` (KeyBuzz API & Front)
- `MODULE11_VALIDATION.md` (Chatwoot)
- `MODULE12_VALIDATION.md` (n8n)
- `MODULE13_VALIDATION.md` (Superset)
- `MODULE14_VALIDATION.md` (Vault Agent)
- `MODULE15_VALIDATION.md` (LiteLLM & Services IA)

---

**Recommandation** : ✅ Adopter cette structure modulaire pour un meilleur contrôle et une maintenance facilitée.

