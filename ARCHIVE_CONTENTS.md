# Contenu de l'Archive KeyBuzz - Liste Complète

Ce document liste tous les fichiers qui DOIVENT être inclus dans l'archive pour une installation complète depuis zéro.

## 📁 Structure Complète

```
keybuzz-installer/
├── scripts/
│   ├── 00_check_prerequisites.sh          ✅ Vérification prérequis
│   ├── 00_prepare_install.sh               ✅ Préparation installation
│   ├── 00_master_install.sh                ✅ Script maître d'installation
│   ├── 01_inventory/
│   │   └── parse_servers_tsv.sh            ✅ Parsing inventaire
│   ├── 02_base_os_and_security/
│   │   ├── base_os.sh                      ✅ Script base OS (appliqué sur chaque serveur)
│   │   ├── apply_base_os_to_all.sh         ✅ Script maître Module 2
│   │   └── validate_module2.sh             ✅ Validation Module 2
│   ├── 03_postgresql_ha/                  ⏳ Module 3 (à venir)
│   ├── 04_redis_ha/                        ⏳ Module 4 (à venir)
│   └── ...
├── docs/
│   ├── 02_base_os_and_security.md         ✅ Documentation Module 2
│   ├── RECAP_MODULE_2.md                   ✅ Récapitulatif Module 2
│   ├── TEMPLATE_RECAP_MODULE.md           ✅ Template récapitulatifs
│   └── ...
├── servers.tsv                             ✅ Inventaire serveurs (OBLIGATOIRE)
├── README.md                               ✅ Documentation principale
├── INSTALLATION_PROCESS.md                 ✅ Processus d'installation
├── INSTALLATION_FROM_SCRATCH.md            ✅ Guide installation depuis zéro
├── INSTALLATION_CHECKPOINT.md              ✅ Système de checkpoints
├── INSTALL_FROM_ARCHIVE.md                 ✅ Guide installation depuis archive
├── CREATE_ARCHIVE.md                       ✅ Instructions création archive
└── ARCHIVE_CONTENTS.md                     ✅ Ce fichier
```

## ✅ Fichiers Critiques (DOIVENT être présents)

### 1. Inventaire
- **`servers.tsv`** : Obligatoire - Liste tous les serveurs avec IPs, rôles, etc.

### 2. Scripts Module 2 (OBLIGATOIRE)
- **`scripts/02_base_os_and_security/base_os.sh`** : Script appliqué sur chaque serveur
- **`scripts/02_base_os_and_security/apply_base_os_to_all.sh`** : Script maître Module 2
- **`scripts/02_base_os_and_security/validate_module2.sh`** : Validation Module 2

### 3. Scripts Utilitaires
- **`scripts/00_check_prerequisites.sh`** : Vérification prérequis
- **`scripts/00_prepare_install.sh`** : Préparation installation
- **`scripts/00_master_install.sh`** : Script maître

### 4. Documentation
- **`INSTALL_FROM_ARCHIVE.md`** : Guide principal pour installation depuis archive
- **`INSTALLATION_CHECKPOINT.md`** : Suivi des checkpoints
- **`docs/RECAP_MODULE_2.md`** : Récapitulatif Module 2

## 🔍 Vérification Avant Création Archive

Avant de créer l'archive, vérifier :

```bash
# Vérifier que servers.tsv existe
test -f servers.tsv && echo "✓ servers.tsv" || echo "✗ servers.tsv MANQUANT"

# Vérifier les scripts Module 2
test -f scripts/02_base_os_and_security/base_os.sh && echo "✓ base_os.sh" || echo "✗ base_os.sh MANQUANT"
test -f scripts/02_base_os_and_security/apply_base_os_to_all.sh && echo "✓ apply_base_os_to_all.sh" || echo "✗ apply_base_os_to_all.sh MANQUANT"
test -f scripts/02_base_os_and_security/validate_module2.sh && echo "✓ validate_module2.sh" || echo "✗ validate_module2.sh MANQUANT"

# Vérifier les scripts utilitaires
test -f scripts/00_check_prerequisites.sh && echo "✓ 00_check_prerequisites.sh" || echo "✗ 00_check_prerequisites.sh MANQUANT"
test -f scripts/00_prepare_install.sh && echo "✓ 00_prepare_install.sh" || echo "✗ 00_prepare_install.sh MANQUANT"
test -f scripts/00_master_install.sh && echo "✓ 00_master_install.sh" || echo "✗ 00_master_install.sh MANQUANT"

# Vérifier la documentation
test -f INSTALL_FROM_ARCHIVE.md && echo "✓ INSTALL_FROM_ARCHIVE.md" || echo "✗ INSTALL_FROM_ARCHIVE.md MANQUANT"
test -f INSTALLATION_CHECKPOINT.md && echo "✓ INSTALLATION_CHECKPOINT.md" || echo "✗ INSTALLATION_CHECKPOINT.md MANQUANT"
```

## 📦 Commande de Création Archive

```bash
cd /chemin/vers/Infra

tar -czf keybuzz-installer-$(date +%Y%m%d).tar.gz \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='*.tar.gz' \
    --exclude='*.log' \
    --exclude='keybuzz-installer/' \
    scripts/ \
    docs/ \
    servers.tsv \
    README.md \
    INSTALLATION_PROCESS.md \
    INSTALLATION_FROM_SCRATCH.md \
    INSTALLATION_CHECKPOINT.md \
    INSTALL_FROM_ARCHIVE.md \
    CREATE_ARCHIVE.md \
    ARCHIVE_CONTENTS.md
```

## ✅ Vérification Post-Création

Après création de l'archive, vérifier le contenu :

```bash
# Lister le contenu
tar -tzf keybuzz-installer-YYYYMMDD.tar.gz | grep -E "(servers\.tsv|base_os\.sh|apply_base_os|validate_module2|00_check|00_prepare|00_master|INSTALL_FROM)" | head -20

# Vérifier l'intégrité
tar -tzf keybuzz-installer-YYYYMMDD.tar.gz > /dev/null && echo "✓ Archive OK" || echo "✗ Archive corrompue"
```

## 🚨 Fichiers à NE PAS Inclure

- `.git/` (répertoire Git)
- `*.log` (fichiers de logs)
- `*.tar.gz` (autres archives)
- `__pycache__/` (cache Python)
- `*.pyc` (bytecode Python)
- `keybuzz-installer/` (ancien répertoire si présent)

## 📝 Notes

- Tous les scripts doivent avoir les permissions d'exécution (`chmod +x`)
- Le fichier `servers.tsv` doit être à jour avec les bonnes IPs
- `ADMIN_IP` dans `base_os.sh` doit être configuré (91.98.128.153)

---

**Dernière mise à jour** : 18 novembre 2025


