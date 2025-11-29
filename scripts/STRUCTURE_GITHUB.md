# 📂 Structure pour GitHub - Infrastructure KeyBuzz

**Objectif** : Créer un dépôt GitHub propre, sans secrets, contenant uniquement les éléments nécessaires pour l'installation et la documentation de l'infrastructure KeyBuzz.

---

## 🎯 Principe

**Ce qui va sur GitHub** :
- ✅ Scripts d'installation (sans secrets)
- ✅ Documentation technique
- ✅ Templates et exemples
- ✅ Inventaire (sans credentials)
- ✅ Guides d'installation

**Ce qui NE va PAS sur GitHub** :
- ❌ Credentials et secrets
- ❌ Fichiers `.env` avec mots de passe
- ❌ Clés SSH privées
- ❌ Tokens et API keys
- ❌ Données sensibles

---

## 📂 Structure Proposée

```
keybuzz-infra/
├── README.md                          # Documentation principale
├── LICENSE                            # Licence
├── .gitignore                         # Fichiers à ignorer
├── inventory/
│   ├── servers.tsv.example            # Exemple d'inventaire (sans IPs réelles)
│   └── README.md                      # Documentation inventaire
├── scripts/
│   ├── 00_master_install.sh           # Script maître
│   ├── 02_base_os_and_security/
│   │   ├── base_os.sh
│   │   ├── apply_base_os_to_all.sh
│   │   └── README.md
│   ├── 03_postgresql_ha/
│   │   ├── 03_pg_apply_all.sh
│   │   ├── 03_pg_01_prepare_volumes.sh
│   │   ├── 03_pg_02_install_patroni_cluster.sh
│   │   └── README.md
│   ├── 04_redis_ha/
│   │   └── ...
│   ├── 05_rabbitmq_ha/
│   │   └── ...
│   ├── 06_minio/
│   │   └── ...
│   ├── 07_mariadb_galera/
│   │   └── ...
│   ├── 08_proxysql_advanced/
│   │   └── ...
│   └── 09_k8s_ha/                     # ⚠️ K8s, pas K3s
│       ├── 09_k8s_apply_all.sh
│       ├── 09_k8s_01_prepare.sh
│       ├── 09_k8s_02_install_kubespray.sh
│       ├── 09_k8s_03_configure_inventory.sh
│       ├── 09_k8s_04_deploy_cluster.sh
│       ├── 09_k8s_05_configure_calico_ipip.sh
│       └── README.md
├── docs/
│   ├── MODULE_02_BASE_OS.md
│   ├── MODULE_03_POSTGRESQL.md
│   ├── MODULE_04_REDIS.md
│   ├── MODULE_05_RABBITMQ.md
│   ├── MODULE_06_MINIO.md
│   ├── MODULE_07_MARIADB.md
│   ├── MODULE_08_PROXYSQL.md
│   ├── MODULE_09_K8S.md                # ⚠️ K8s, pas K3s
│   └── ARCHITECTURE.md                 # Architecture globale
├── templates/
│   ├── credentials/
│   │   ├── postgres.env.example
│   │   ├── redis.env.example
│   │   ├── rabbitmq.env.example
│   │   ├── minio.env.example
│   │   ├── mariadb.env.example
│   │   └── proxysql.env.example
│   └── kubespray/
│       └── hosts.yaml.example
├── guides/
│   ├── INSTALLATION_COMPLETE.md        # Guide installation complète
│   ├── INSTALLATION_MODULE_BY_MODULE.md
│   └── TROUBLESHOOTING.md
└── .github/
    └── workflows/
        └── lint.yml                    # CI/CD (optionnel)

```

---

## 📝 Fichiers Clés

### `.gitignore`

```gitignore
# Credentials et secrets
credentials/*.env
credentials/*.txt
credentials/*.key
credentials/*.pem
*.env
*.key
*.pem

# Clés SSH
*.pub
id_rsa
id_ed25519
keybuzz_infra

# Logs
logs/*.log
*.log

# Inventaire réel (garder seulement l'exemple)
inventory/servers.tsv
!inventory/servers.tsv.example

# Fichiers temporaires
*.tmp
*.bak
*.swp
*~

# OS
.DS_Store
Thumbs.db

# IDE
.vscode/
.idea/
*.sublime-*

# Python
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
venv/
env/

# Ansible
*.retry
.ansible/

# Kubernetes
kubeconfig
*.kubeconfig
```

### `README.md` (Principal)

```markdown
# Infrastructure KeyBuzz

Infrastructure complète pour la plateforme KeyBuzz, installable depuis zéro.

## 📋 Modules

- Module 2 : Base OS & Sécurité
- Module 3 : PostgreSQL HA (Patroni RAFT)
- Module 4 : Redis HA (Sentinel)
- Module 5 : RabbitMQ HA (Quorum)
- Module 6 : MinIO S3 (Cluster 3 nœuds)
- Module 7 : MariaDB Galera HA
- Module 8 : ProxySQL Advanced
- Module 9 : Kubernetes HA (K8s) - Calico IPIP

## 🚀 Installation

Voir `guides/INSTALLATION_COMPLETE.md`

## 📚 Documentation

Voir `docs/` pour la documentation technique de chaque module.

## ⚠️ Important

- Ne jamais commiter de credentials ou secrets
- Utiliser les fichiers `.example` comme templates
- Suivre l'ordre d'installation des modules
```

---

## 🔒 Sécurité

### Fichiers à Vérifier Avant Commit

1. **Aucun secret dans les scripts** :
   ```bash
   grep -r "password\|secret\|token\|key" scripts/ --exclude="*.example"
   ```

2. **Aucun credential dans l'inventaire** :
   ```bash
   # Vérifier que servers.tsv n'est pas commité
   git check-ignore inventory/servers.tsv
   ```

3. **Aucune clé SSH** :
   ```bash
   find . -name "*.pub" -o -name "*_rsa" -o -name "*_ed25519"
   ```

### Template pour Credentials

**Fichier** : `templates/credentials/postgres.env.example`

```bash
# PostgreSQL Credentials
# Copier ce fichier vers credentials/postgres.env et remplir les valeurs

POSTGRES_SUPERUSER_PASSWORD=CHANGE_ME
POSTGRES_REPLICATION_PASSWORD=CHANGE_ME
POSTGRES_APP_PASSWORD=CHANGE_ME
```

---

## 📦 Préparation pour GitHub

### Étape 1 : Créer la Structure

```bash
mkdir -p keybuzz-infra/{inventory,scripts,docs,templates,guides}
```

### Étape 2 : Copier les Scripts (Sans Secrets)

```bash
# Copier les scripts en excluant les credentials
rsync -av --exclude='*.env' --exclude='credentials' \
  /opt/keybuzz-installer-v2/scripts/ \
  keybuzz-infra/scripts/
```

### Étape 3 : Créer les Templates

```bash
# Créer les fichiers .example depuis les vrais fichiers
for file in credentials/*.env; do
  cp "$file" "templates/credentials/$(basename $file).example"
  # Remplacer les valeurs par CHANGE_ME
  sed -i 's/=.*/=CHANGE_ME/g' "templates/credentials/$(basename $file).example"
done
```

### Étape 4 : Créer l'Inventaire Exemple

```bash
# Créer servers.tsv.example sans IPs réelles
sed 's/[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}/X.X.X.X/g' \
  inventory/servers.tsv > inventory/servers.tsv.example
```

### Étape 5 : Vérifier Avant Commit

```bash
# Vérifier qu'aucun secret n'est présent
./scripts/check_secrets.sh
```

---

## 📚 Documentation à Inclure

### Obligatoire

- ✅ `README.md` - Documentation principale
- ✅ `guides/INSTALLATION_COMPLETE.md` - Guide complet
- ✅ `docs/ARCHITECTURE.md` - Architecture globale
- ✅ `docs/MODULE_XX_*.md` - Documentation de chaque module

### Optionnel

- `guides/TROUBLESHOOTING.md` - Dépannage
- `guides/BEST_PRACTICES.md` - Bonnes pratiques
- `CHANGELOG.md` - Historique des changements

---

## 🔄 Workflow de Publication

### 1. Préparation Locale

```bash
cd /opt/keybuzz-installer-v2
./scripts/prepare_for_github.sh
```

### 2. Vérification

```bash
./scripts/check_secrets.sh
./scripts/validate_structure.sh
```

### 3. Commit et Push

```bash
cd keybuzz-infra
git add .
git commit -m "feat: Infrastructure KeyBuzz - Installation complète"
git push origin main
```

---

## ✅ Checklist Avant Publication

- [ ] Aucun secret dans les scripts
- [ ] Aucun credential dans l'inventaire
- [ ] Tous les fichiers `.example` créés
- [ ] `.gitignore` configuré correctement
- [ ] Documentation complète
- [ ] README.md à jour
- [ ] Structure validée
- [ ] Tests de vérification passés

---

**Cette structure permet de publier l'infrastructure sur GitHub de manière sécurisée, sans exposer de secrets.**

