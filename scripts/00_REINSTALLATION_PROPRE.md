# 🔄 Stratégie de Réinstallation Propre

## 📋 Objectif

Réinstaller l'infrastructure KeyBuzz depuis zéro avec les scripts corrigés et la solution hostNetwork dès le départ.

## ✅ Avantages d'une Réinstallation Propre

1. **Scripts propres** : Pas de scripts temporaires/de diagnostic
2. **Solution validée** : hostNetwork dès le départ
3. **Documentation à jour** : Tous les scripts documentés
4. **Tests complets** : Validation de bout en bout
5. **Base solide** : Infrastructure propre pour la suite

## 📦 Modules à Réinstaller

### Ordre d'Installation

1. **Module 2** : Base OS & Security
2. **Module 3** : PostgreSQL HA
3. **Module 4** : Redis HA
4. **Module 5** : RabbitMQ HA
5. **Module 6** : MinIO S3
6. **Module 7** : MariaDB Galera
7. **Module 8** : ProxySQL Advanced
8. **Module 9** : K3s HA (avec Ingress NGINX DaemonSet hostNetwork)
9. **Module 10** : KeyBuzz API & Front (DaemonSets hostNetwork) ⭐ **NOUVEAU**

## 🚀 Séquence de Réinstallation

### Étape 1 : Préparation

```bash
# Sur install-01
cd /root/Infra/scripts

# Nettoyer les scripts temporaires (optionnel)
# Voir 00_CLEANUP_SCRIPTS.md

# Vérifier les prérequis
./00_check_prerequisites.sh
```

### Étape 2 : Installation des Modules

```bash
# Installation complète
./00_master_install.sh /opt/keybuzz-installer/servers.tsv --yes

# Ou module par module
./02_base_os_and_security/apply_base_os_to_all.sh
./03_postgresql_ha/03_pg_apply_all.sh
./04_redis_ha/04_redis_apply_all.sh
./05_rabbitmq_ha/05_rmq_apply_all.sh
./06_minio/06_minio_apply_all.sh
./07_mariadb_galera/07_maria_apply_all.sh
./08_proxysql_advanced/08_proxysql_apply_all.sh
./09_k3s_ha/09_k3s_apply_all.sh
./10_keybuzz/10_keybuzz_apply_all.sh  # ⭐ NOUVEAU : hostNetwork dès le départ
```

### Étape 3 : Configuration Load Balancer

1. **Ingress NGINX** :
   - Port HTTP : 31695
   - Port HTTPS : 31695 (⚠️ IMPORTANT : même port)
   - Healthcheck : HTTP sur port 31695, path `/healthz`
   - Targets : Tous les workers K3s (5 workers)

2. **DNS** :
   - `platform.keybuzz.io` → IP LB Hetzner
   - `platform-api.keybuzz.io` → IP LB Hetzner

### Étape 4 : Validation

```bash
# Validation Module 10
cd /root/Infra/scripts/10_keybuzz
./10_keybuzz_03_tests.sh

# Tests manuels
curl https://platform.keybuzz.io
curl https://platform-api.keybuzz.io
```

## 📝 Checklist de Réinstallation

### Avant de Commencer

- [ ] Sauvegarder les données importantes (bases de données, volumes)
- [ ] Documenter la configuration actuelle (IPs, ports, etc.)
- [ ] Vérifier que tous les scripts sont à jour
- [ ] Nettoyer les scripts temporaires (optionnel)

### Pendant l'Installation

- [ ] Module 2 : Base OS ✅
- [ ] Module 3 : PostgreSQL HA ✅
- [ ] Module 4 : Redis HA ✅
- [ ] Module 5 : RabbitMQ HA ✅
- [ ] Module 6 : MinIO ✅
- [ ] Module 7 : MariaDB Galera ✅
- [ ] Module 8 : ProxySQL Advanced ✅
- [ ] Module 9 : K3s HA ✅
- [ ] Module 10 : KeyBuzz (hostNetwork) ✅

### Après l'Installation

- [ ] Vérifier tous les pods Running
- [ ] Tester tous les services
- [ ] Vérifier les Load Balancers
- [ ] Tester les URLs publiques
- [ ] Documenter la configuration finale

## ⚠️ Points d'Attention

### 1. Sauvegarde des Données

Avant de réinstaller, sauvegarder :
- Bases de données (PostgreSQL, MariaDB)
- Volumes Hetzner (si nécessaire)
- Configuration actuelle

### 2. Scripts à Utiliser

**Module 10** : Utiliser `10_keybuzz_01_deploy_daemonsets.sh` (nouveau script avec hostNetwork)

**Ne PAS utiliser** :
- `10_keybuzz_01_deploy_api.sh.old` (ancien, ne fonctionne pas)
- `10_keybuzz_02_deploy_front.sh.old` (ancien, ne fonctionne pas)

### 3. Load Balancer

**⚠️ CRITIQUE** : Le port HTTPS doit être **31695** (même que HTTP).

### 4. Ports Utilisés

| Service | Port | Usage |
|---------|------|-------|
| KeyBuzz API | 8080 | hostNetwork |
| KeyBuzz Front | 3000 | hostNetwork |
| Ingress NGINX | 31695 | NodePort (HTTP/HTTPS) |

## 🎯 Résultat Attendu

Après réinstallation propre :

```
✅ Tous les modules installés
✅ KeyBuzz en DaemonSets hostNetwork
✅ 10 pods KeyBuzz Running (5 API + 5 Front)
✅ Services NodePort fonctionnels
✅ URLs accessibles (HTTP 200)
✅ Infrastructure propre et documentée
```

## 📚 Documentation

- **`SOLUTION_HOSTNETWORK.md`** : Solution hostNetwork
- **`LESSONS_LEARNED.md`** : Leçons apprises
- **`README.md`** : Documentation Module 10

---

## 🤔 Faut-il Réinstaller ?

### Arguments POUR

- ✅ Scripts propres et documentés
- ✅ Solution validée dès le départ
- ✅ Base solide pour la suite
- ✅ Tests complets de bout en bout

### Arguments CONTRE

- ❌ Temps nécessaire (plusieurs heures)
- ❌ Risque de perte de données (si sauvegarde manquante)
- ❌ Infrastructure actuelle fonctionne

### Recommandation

**Si l'infrastructure actuelle fonctionne** : Pas besoin de réinstaller immédiatement.

**Réinstaller si** :
- Vous voulez une base propre pour la suite
- Vous avez le temps et les sauvegardes
- Vous voulez valider tous les scripts de bout en bout

**Alternative** : Continuer avec l'infrastructure actuelle et réinstaller plus tard si nécessaire.

---

**Date** : 2025-11-20

