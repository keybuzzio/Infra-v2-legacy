# Installation Modules 10 et 11 - En cours

## ⏳ Module 10 : Plateforme KeyBuzz

### Installation en cours
- ⏳ Script `deploy_module10_v2.sh` lancé
- ⏳ Étapes :
  1. Vérification credentials
  2. Déploiement Module 10 de base
  3. Déploiement applications Platform
  4. Mise à jour images (GHCR)
  5. Création Secret GHCR
  6. Validation Module 10

### Images attendues
- `ghcr.io/keybuzzio/platform-api:0.1.1`
- `ghcr.io/keybuzzio/platform-ui:0.1.1`
- `ghcr.io/keybuzzio/platform-ui:0.1.1` (pour platform-my)

## ⏳ Module 11 : Chatwoot / Support KeyBuzz

### À faire après Module 10
- ⏳ Script `deploy_module11_from_install01.sh` ou `11_ct_apply_all.sh`
- ⏳ Étapes :
  1. Setup credentials (DB chatwoot)
  2. Préparation config (ConfigMap + Secrets)
  3. Déploiement Chatwoot (web + worker)
  4. Migrations
  5. Tests et validation

---

**Date** : 2025-11-28  
**Statut** : ⏳ Module 10 en cours d'installation

