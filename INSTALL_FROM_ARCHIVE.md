# Installation KeyBuzz depuis Archive - Guide Complet

Ce guide décrit le processus d'installation complète de KeyBuzz depuis une archive décompressée sur `install-01`.

## 📦 Prérequis

### Sur install-01

- ✅ Ubuntu 24.04 LTS
- ✅ Accès root
- ✅ Connexion SSH fonctionnelle vers tous les serveurs
- ✅ Clé SSH configurée pour accès sans mot de passe
- ✅ Réseau privé 10.0.0.0/16 fonctionnel

### Fichiers nécessaires

- ✅ Archive `keybuzz-installer-YYYYMMDD.tar.gz`
- ✅ Passphrase SSH (si nécessaire) : `C:\Users\ludov\Mon Drive\keybuzzio\SSH\passphrase.txt`

## 🚀 Étape 1 : Transfert de l'archive

### Depuis Windows (local)

```powershell
# Se placer dans le dossier Infra
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra"

# Transférer l'archive vers install-01
pscp.exe -i "..\SSH\keybuzz_infra" keybuzz-installer-YYYYMMDD.tar.gz root@91.98.128.153:/tmp/
```

### Vérification

```bash
# Se connecter sur install-01
ssh root@91.98.128.153

# Vérifier que l'archive est présente
ls -lh /tmp/keybuzz-installer-*.tar.gz
```

## 🔓 Étape 2 : Décompression et préparation

### Sur install-01

```bash
# Se placer dans /tmp
cd /tmp

# Décompresser l'archive
tar -xzf keybuzz-installer-YYYYMMDD.tar.gz

# Vérifier la structure
ls -la keybuzz-installer/

# Structure attendue :
# keybuzz-installer/
#   ├── scripts/
#   ├── docs/
#   ├── servers.tsv
#   ├── README.md
#   ├── INSTALLATION_PROCESS.md
#   ├── INSTALLATION_FROM_SCRATCH.md
#   ├── INSTALLATION_CHECKPOINT.md
#   └── INSTALL_FROM_ARCHIVE.md
```

## 📁 Étape 3 : Installation dans /opt

### Sur install-01

```bash
# Créer le répertoire de destination
mkdir -p /opt/keybuzz-installer

# Copier tous les fichiers
cp -r /tmp/keybuzz-installer/* /opt/keybuzz-installer/

# Aller dans le répertoire d'installation
cd /opt/keybuzz-installer

# Rendre les scripts exécutables
find scripts/ -type f -name "*.sh" -exec chmod +x {} \;

# Vérifier les permissions
ls -la scripts/
```

## ✅ Étape 4 : Vérification des prérequis

### Lancer le script de vérification

```bash
cd /opt/keybuzz-installer

# Rendre les scripts exécutables (si nécessaire)
chmod +x scripts/*.sh scripts/*/*.sh

# Lancer la vérification
./scripts/00_check_prerequisites.sh
```

### Vérifications manuelles

```bash
# Vérifier servers.tsv
cat servers.tsv | head -5

# Vérifier l'accès SSH vers les serveurs DB
ssh -o BatchMode=yes root@10.0.0.120 "echo 'OK'"
ssh -o BatchMode=yes root@10.0.0.121 "echo 'OK'"
ssh -o BatchMode=yes root@10.0.0.122 "echo 'OK'"

# Vérifier Docker sur install-01
docker --version
```

## 🎯 Étape 5 : Configuration initiale

### 1. Vérifier servers.tsv

```bash
# Éditer si nécessaire
nano /opt/keybuzz-installer/servers.tsv

# Vérifier les IPs, hostnames, rôles
```

### 2. Configurer ADMIN_IP dans base_os.sh

```bash
# Vérifier/corriger ADMIN_IP
grep ADMIN_IP scripts/02_base_os_and_security/base_os.sh

# Doit afficher : ADMIN_IP="91.98.128.153"
# Si différent, corriger :
nano scripts/02_base_os_and_security/base_os.sh
```

### 3. Préparer les credentials (si nécessaire)

```bash
# Créer le répertoire credentials
mkdir -p /opt/keybuzz-installer/credentials

# Pour Module 3 (PostgreSQL), créer postgres.env
# (sera fait lors du Module 3)
```

## 📊 Étape 6 : Suivi des checkpoints

### Ouvrir le fichier de checkpoints

```bash
# Éditer le fichier de checkpoints
nano /opt/keybuzz-installer/INSTALLATION_CHECKPOINT.md

# Cocher les cases au fur et à mesure
# Noter les dates et problèmes rencontrés
```

## 🚀 Étape 7 : Lancement de l'installation

### Option A : Installation complète automatique

```bash
cd /opt/keybuzz-installer/scripts

# Lancer le script maître
./00_master_install.sh
```

Le script va :
1. ✅ Lancer le Module 2 (Base OS & Sécurité)
2. ✅ Valider automatiquement le Module 2
3. ⏳ Continuer avec les modules suivants (quand implémentés)

### Option B : Installation manuelle étape par étape

```bash
# Module 2 uniquement
cd /opt/keybuzz-installer/scripts/02_base_os_and_security
./apply_base_os_to_all.sh ../../servers.tsv

# Validation Module 2
./validate_module2.sh ../../servers.tsv

# Vérifier le rapport
cat module2_validation_report_*.txt

# Cocher le Checkpoint 2 dans INSTALLATION_CHECKPOINT.md
```

## 📝 Étape 8 : Validation et checkpoint

### Après chaque module

1. **Vérifier les logs** :
   ```bash
   # Logs Module 2
   tail -100 /tmp/module2_final_complet.log
   
   # Rapport de validation
   cat scripts/02_base_os_and_security/module2_validation_report_*.txt
   ```

2. **Cocher le checkpoint** :
   ```bash
   nano /opt/keybuzz-installer/INSTALLATION_CHECKPOINT.md
   # Cocher toutes les cases du checkpoint correspondant
   # Noter la date et les problèmes éventuels
   ```

3. **Créer une sauvegarde** :
   ```bash
   # Créer une archive du checkpoint
   cd /opt/keybuzz-installer
   tar -czf /tmp/keybuzz-checkpoint-2-$(date +%Y%m%d).tar.gz \
       scripts/ docs/ servers.tsv INSTALLATION_CHECKPOINT.md
   ```

## 🔄 Réinstallation depuis un checkpoint

Si vous devez repartir depuis un checkpoint :

```bash
# 1. Restaurer l'archive complète
cd /tmp
tar -xzf keybuzz-installer-YYYYMMDD.tar.gz

# 2. Copier vers /opt
cp -r keybuzz-installer/* /opt/keybuzz-installer/

# 3. Vérifier le checkpoint précédent
cat /opt/keybuzz-installer/INSTALLATION_CHECKPOINT.md

# 4. Continuer depuis le module suivant
```

## 🆘 Dépannage

### Problème : Archive corrompue

```bash
# Vérifier l'intégrité
tar -tzf /tmp/keybuzz-installer-YYYYMMDD.tar.gz > /dev/null
echo $?  # Doit retourner 0
```

### Problème : Permissions incorrectes

```bash
# Corriger les permissions
cd /opt/keybuzz-installer
find scripts/ -type f -name "*.sh" -exec chmod +x {} \;
chown -R root:root /opt/keybuzz-installer
```

### Problème : Serveurs inaccessibles

```bash
# Tester la connectivité
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
  ssh -o BatchMode=yes -o ConnectTimeout=5 root@$ip "echo OK" || echo "FAIL: $ip"
done
```

## 📚 Documentation

- **Processus d'installation** : `INSTALLATION_PROCESS.md`
- **Installation depuis zéro** : `INSTALLATION_FROM_SCRATCH.md`
- **Checkpoints** : `INSTALLATION_CHECKPOINT.md`
- **Ce guide** : `INSTALL_FROM_ARCHIVE.md`

## ✅ Checklist finale

Avant de commencer l'installation :

- [ ] Archive transférée sur install-01
- [ ] Archive décompressée dans `/tmp`
- [ ] Fichiers copiés vers `/opt/keybuzz-installer`
- [ ] Permissions configurées
- [ ] `servers.tsv` vérifié
- [ ] `ADMIN_IP` configuré dans `base_os.sh`
- [ ] Prérequis vérifiés
- [ ] Fichier de checkpoints ouvert

---

**Dernière mise à jour** : 18 novembre 2025

