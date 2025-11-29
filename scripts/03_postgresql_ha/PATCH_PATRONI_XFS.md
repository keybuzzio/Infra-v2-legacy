# Patch pour corriger la vérification XFS dans les scripts Patroni

**Date** : 2025-11-23  
**Problème** : Script s'arrête si filesystem n'est pas XFS même avec `--yes`  
**Solution** : Appliquer ce patch sur install-01

---

## 📋 Instructions

### Option 1 : Script de patch automatique (RECOMMANDÉ)

Se connecter à install-01 et exécuter :

```bash
cd /opt/keybuzz-installer/scripts/03_postgresql_ha

# Créer et exécuter le script de patch
cat > fix_xfs_patroni.sh << 'EOF'
#!/bin/bash
cd /opt/keybuzz-installer/scripts/03_postgresql_ha

# Backup
cp 03_pg_02_install_patroni_cluster.sh 03_pg_02_install_patroni_cluster.sh.backup
cp 03_pg_apply_all.sh 03_pg_apply_all.sh.backup

# Correction avec Python
python3 << 'PY'
import re

# Corriger 03_pg_02_install_patroni_cluster.sh
with open('03_pg_02_install_patroni_cluster.sh', 'r') as f:
    content = f.read()

new_section = '''    # Vérifier le filesystem XFS
    local fs_type=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \\
        "df -T /opt/keybuzz/postgres/data 2>/dev/null | tail -1 | awk '{print \\$2}' || echo 'unknown'")
    
    if [[ "${fs_type}" != "xfs" ]] && [[ "${fs_type}" != "unknown" ]]; then
        log_warning "Filesystem sur ${hostname} n'est pas XFS (${fs_type})"
        local is_mountpoint=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \\
            "mountpoint -q /opt/keybuzz/postgres/data 2>/dev/null && echo 'yes' || echo 'no'")
        if [[ "${is_mountpoint}" == "yes" ]]; then
            log_warning "Volume monté mais filesystem ${fs_type} (XFS recommandé)"
        fi
        if [[ "${SKIP_FS_CHECK:-false}" == "true" ]] || [[ "${is_mountpoint}" == "yes" ]]; then
            log_warning "Continuation automatique (mode non-interactif ou volume monté)"
        else
            log_warning "Continuez quand même ? (y/N)"
            read -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                log_error "Installation annulée"
                return 1
            fi
        fi
    elif [[ "${fs_type}" == "xfs" ]]; then
        log_success "Filesystem XFS détecté sur ${hostname}"
    fi
    '''

pattern = r'    # Vérifier le filesystem XFS.*?    fi\n'
content = re.sub(pattern, new_section, content, flags=re.DOTALL)

with open('03_pg_02_install_patroni_cluster.sh', 'w') as f:
    f.write(content)

print("✅ 03_pg_02_install_patroni_cluster.sh corrigé")
PY

# Corriger 03_pg_apply_all.sh
python3 << 'PY2'
with open('03_pg_apply_all.sh', 'r') as f:
    lines = f.readlines()

new_lines = []
added = False
for i, line in enumerate(lines):
    new_lines.append(line)
    if 'if [[ -f "${SCRIPT_DIR}/03_pg_02_install_patroni_cluster.sh" ]]; then' in line and not added:
        new_lines.append('    if [[ "${NON_INTERACTIVE}" == "true" ]]; then\n')
        new_lines.append('        export SKIP_FS_CHECK="true"\n')
        new_lines.append('    fi\n')
        added = True
    if 'log_success "Cluster Patroni installé"' in line and 'unset SKIP_FS_CHECK' not in ''.join(new_lines[-5:]):
        new_lines.append('    unset SKIP_FS_CHECK\n')

with open('03_pg_apply_all.sh', 'w') as f:
    f.writelines(new_lines)

print("✅ 03_pg_apply_all.sh corrigé")
PY2

echo "✅ Patch appliqué avec succès !"
EOF

chmod +x fix_xfs_patroni.sh
bash fix_xfs_patroni.sh
```

### Option 2 : Modification manuelle

Éditer directement les fichiers sur install-01 :

1. **Éditer `03_pg_02_install_patroni_cluster.sh`** ligne ~167-176 :
   - Remplacer la section `if [[ "${fs_type}" != "xfs" ]]...` par la version corrigée avec `SKIP_FS_CHECK`

2. **Éditer `03_pg_apply_all.sh`** ligne ~107 :
   - Ajouter après `if [[ -f "${SCRIPT_DIR}/03_pg_02_install_patroni_cluster.sh" ]]; then` :
     ```bash
     if [[ "${NON_INTERACTIVE}" == "true" ]]; then
         export SKIP_FS_CHECK="true"
     fi
     ```
   - Ajouter après `log_success "Cluster Patroni installé"` :
     ```bash
     unset SKIP_FS_CHECK
     ```

---

## ✅ Après le patch

Relancer l'installation :

```bash
cd /opt/keybuzz-installer/scripts/03_postgresql_ha
./03_pg_apply_all.sh ../../servers.tsv --yes
```

Le script continuera automatiquement même si le filesystem n'est pas XFS (en mode `--yes`).













