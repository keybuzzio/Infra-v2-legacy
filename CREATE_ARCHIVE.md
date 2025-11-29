# Création de l'Archive KeyBuzz - Instructions

## Méthode 1 : Depuis Linux (install-01)

Si vous avez accès à un environnement Linux, créez l'archive ainsi :

```bash
cd /chemin/vers/Infra
tar -czf keybuzz-installer-$(date +%Y%m%d).tar.gz \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='*.tar.gz' \
    --exclude='*.log' \
    scripts/ \
    docs/ \
    servers.tsv \
    README.md \
    INSTALLATION_PROCESS.md \
    INSTALLATION_FROM_SCRATCH.md \
    INSTALLATION_CHECKPOINT.md \
    INSTALL_FROM_ARCHIVE.md
```

## Méthode 2 : Depuis Windows avec WSL

```bash
# Dans WSL
cd /mnt/c/Users/ludov/Mon\ Drive/keybuzzio/Infra
tar -czf keybuzz-installer-$(date +%Y%m%d).tar.gz \
    --exclude='.git' \
    --exclude='__pycache__' \
    --exclude='*.pyc' \
    --exclude='*.tar.gz' \
    --exclude='*.log' \
    scripts/ \
    docs/ \
    servers.tsv \
    README.md \
    INSTALLATION_PROCESS.md \
    INSTALLATION_FROM_SCRATCH.md \
    INSTALLATION_CHECKPOINT.md \
    INSTALL_FROM_ARCHIVE.md
```

## Méthode 3 : Depuis Windows avec 7-Zip

Si vous avez 7-Zip installé :

```powershell
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra"
$date = Get-Date -Format "yyyyMMdd"
7z a -ttar "keybuzz-installer-${date}.tar" scripts docs servers.tsv README.md INSTALLATION_PROCESS.md INSTALLATION_FROM_SCRATCH.md INSTALLATION_CHECKPOINT.md INSTALL_FROM_ARCHIVE.md
7z a -tgzip "keybuzz-installer-${date}.tar.gz" "keybuzz-installer-${date}.tar"
Remove-Item "keybuzz-installer-${date}.tar"
```

## Méthode 4 : Création manuelle sur install-01

Si vous ne pouvez pas créer l'archive localement, vous pouvez :

1. Transférer tous les fichiers sur install-01
2. Créer l'archive directement sur install-01

```bash
# Sur install-01
cd /tmp
mkdir -p keybuzz-installer
# Transférer tous les fichiers dans /tmp/keybuzz-installer
# Puis créer l'archive :
cd /tmp
tar -czf keybuzz-installer-$(date +%Y%m%d).tar.gz keybuzz-installer/
```

## Contenu de l'archive

L'archive doit contenir :

```
keybuzz-installer/
├── scripts/
│   ├── 00_check_prerequisites.sh
│   ├── 00_prepare_install.sh
│   ├── 00_master_install.sh
│   ├── 01_inventory/
│   ├── 02_base_os_and_security/
│   └── ...
├── docs/
│   ├── 02_base_os_and_security.md
│   ├── RECAP_MODULE_2.md
│   └── ...
├── servers.tsv
├── README.md
├── INSTALLATION_PROCESS.md
├── INSTALLATION_FROM_SCRATCH.md
├── INSTALLATION_CHECKPOINT.md
└── INSTALL_FROM_ARCHIVE.md
```

## Vérification de l'archive

Après création, vérifiez le contenu :

```bash
# Lister le contenu
tar -tzf keybuzz-installer-YYYYMMDD.tar.gz | head -20

# Vérifier l'intégrité
tar -tzf keybuzz-installer-YYYYMMDD.tar.gz > /dev/null && echo "Archive OK" || echo "Archive corrompue"
```

## Transfert vers install-01

```powershell
# Depuis Windows
cd "C:\Users\ludov\Mon Drive\keybuzzio\Infra"
pscp.exe -i "..\SSH\keybuzz_infra" keybuzz-installer-YYYYMMDD.tar.gz root@91.98.128.153:/tmp/
```

## Utilisation

Une fois l'archive transférée sur install-01, suivez le guide `INSTALL_FROM_ARCHIVE.md`.


