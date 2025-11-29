# Installation KeyBuzz depuis Zéro - Guide Complet

Ce guide décrit le processus d'installation complète de l'infrastructure KeyBuzz en partant de zéro.

## 📋 Prérequis

### Infrastructure

- ✅ 49 serveurs Ubuntu 24.04 LTS provisionnés
- ✅ Réseau privé 10.0.0.0/16 fonctionnel
- ✅ Serveur `install-01` (10.0.0.20) accessible via SSH
- ✅ Fichier `servers.tsv` correctement rempli

### Accès

- ✅ Clé SSH configurée pour accès root sans mot de passe
- ✅ Clé SSH déposée sur tous les serveurs
- ✅ Passphrase disponible si nécessaire

## 🚀 Installation Complète

### Étape 1 : Préparation install-01

```bash
# Se connecter sur install-01
ssh root@91.98.128.153

# Cloner le dépôt GitHub
cd /opt
git clone https://github.com/keybuzzio/Infra.git keybuzz-installer
cd keybuzz-installer

# Vérifier la configuration
./scripts/01_inventory/parse_servers_tsv.sh servers.tsv
```

### Étape 2 : Configuration ADMIN_IP

```bash
# Éditer base_os.sh pour configurer ADMIN_IP
cd /opt/keybuzz-installer/scripts/02_base_os_and_security
nano base_os.sh

# Vérifier que ADMIN_IP est configuré (ligne 19)
grep ADMIN_IP base_os.sh
# Doit afficher : ADMIN_IP="91.98.128.153"
```

### Étape 3 : Installation via Script Maître

**Option A : Installation complète automatique**

```bash
cd /opt/keybuzz-installer/scripts
./00_master_install.sh
```

Le script maître va :
1. ✅ Lancer le Module 2 (Base OS & Sécurité)
2. ✅ Valider automatiquement le Module 2
3. ⏳ Lancer les modules suivants (quand implémentés)

**Option B : Installation manuelle étape par étape**

```bash
# Module 2 uniquement
cd /opt/keybuzz-installer/scripts/02_base_os_and_security
./apply_base_os_to_all.sh ../../servers.tsv

# Validation du Module 2
./validate_module2.sh ../../servers.tsv

# Modules suivants (quand implémentés)
# Module 3, 4, 5, etc.
```

## 📊 Validation du Module 2

Le script de validation vérifie **15 points** sur chaque serveur :

1. ✅ OS Ubuntu 24.04
2. ✅ Docker installé
3. ✅ Docker actif
4. ✅ Swap désactivé
5. ✅ Swap retiré de fstab
6. ✅ UFW activé
7. ✅ Réseau privé autorisé dans UFW
8. ✅ SSH durci
9. ✅ PasswordAuthentication désactivé
10. ✅ DNS configuré (1.1.1.1 ou 8.8.8.8)
11. ✅ Optimisations sysctl présentes
12. ✅ Timezone Europe/Paris
13. ✅ NTP activé
14. ✅ Configuration journald présente
15. ✅ Paquets de base installés

**Lancer la validation** :
```bash
cd /opt/keybuzz-installer/scripts/02_base_os_and_security
./validate_module2.sh ../../servers.tsv
```

**Rapport généré** : `module2_validation_report_YYYYMMDD_HHMMSS.txt`

## 📝 Compte Rendu Module 2

Un compte rendu complet est disponible dans :
- **Documentation** : `docs/RECAP_MODULE_2.md`
- **Logs** : `/tmp/module2_final_complet.log`
- **Rapport de validation** : `scripts/02_base_os_and_security/module2_validation_report_*.txt`

## 🔄 Réinstallation depuis Zéro

Pour réinstaller depuis zéro :

```bash
# Sur install-01
cd /opt/keybuzz-installer

# Option 1 : Script maître (recommandé)
./scripts/00_master_install.sh

# Option 2 : Module 2 uniquement
cd scripts/02_base_os_and_security
./apply_base_os_to_all.sh ../../servers.tsv
```

**Note** : Les scripts sont **idempotents**, vous pouvez les relancer sans risque.

## ✅ Checklist Post-Installation

Après le Module 2, vérifier :

- [ ] Tous les serveurs accessibles via SSH
- [ ] Docker fonctionne sur tous les serveurs
- [ ] Swap désactivé partout
- [ ] UFW activé et configuré
- [ ] DNS fonctionne (test : `dig google.com`)
- [ ] Validation complète réussie

## 📚 Documentation

- **Processus d'installation** : `INSTALLATION_PROCESS.md`
- **Récapitulatif Module 2** : `docs/RECAP_MODULE_2.md`
- **Documentation Module 2** : `docs/02_base_os_and_security.md`
- **Script maître** : `scripts/00_master_install.sh`

## 🆘 Dépannage

### Serveur inaccessible

```bash
# Vérifier la connectivité
ping <IP_SERVEUR>
ssh root@<IP_SERVEUR> "echo OK"

# Vérifier les clés SSH
ls -la ~/.ssh/
```

### Validation échoue

```bash
# Consulter le rapport
cat scripts/02_base_os_and_security/module2_validation_report_*.txt

# Relancer le Module 2 sur un serveur spécifique
ssh root@<IP_SERVEUR> "bash -s" < scripts/02_base_os_and_security/base_os.sh <ROLE> <SUBROLE>
```

### Logs

- **Module 2** : `/tmp/module2_final_complet.log`
- **Script maître** : `logs/module_*_*.log`
- **Validation** : `scripts/02_base_os_and_security/module2_validation_report_*.txt`

## 🎯 Prochaines Étapes

Une fois le Module 2 validé :

1. ✅ Module 3 : PostgreSQL HA
2. ✅ Module 4 : Redis HA
3. ✅ Module 5 : RabbitMQ HA
4. ✅ Module 6 : MinIO
5. ✅ Module 7 : MariaDB Galera
6. ✅ Module 8 : ProxySQL
7. ✅ Module 9 : K3s HA
8. ✅ Module 10 : Load Balancers

---

**Dernière mise à jour** : 18 novembre 2024  
**Statut Module 2** : ✅ TERMINÉ ET VALIDÉ


