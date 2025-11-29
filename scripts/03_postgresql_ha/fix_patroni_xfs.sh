#!/bin/bash
# Script pour corriger la vérification XFS dans les scripts Patroni
# À exécuter sur install-01 dans /opt/keybuzz-installer/scripts/03_postgresql_ha

cd /opt/keybuzz-installer/scripts/03_postgresql_ha || exit 1

echo "=== Correction Scripts Patroni XFS ==="
echo ""

# Backup
cp 03_pg_02_install_patroni_cluster.sh 03_pg_02_install_patroni_cluster.sh.backup_$(date +%Y%m%d_%H%M%S)
cp 03_pg_apply_all.sh 03_pg_apply_all.sh.backup_$(date +%Y%m%d_%H%M%S)

echo "✅ Backups créés"
echo ""

# Correction 03_pg_02_install_patroni_cluster.sh
python3 << 'PYFIX'
import re

# Lire le fichier
with open('03_pg_02_install_patroni_cluster.sh', 'r') as f:
    content = f.read()

# Nouvelle section complète
new_section = '''    # Vérifier le filesystem XFS
    local fs_type=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \\
        "df -T /opt/keybuzz/postgres/data 2>/dev/null | tail -1 | awk '{print \\$2}' || echo 'unknown'")
    
    if [[ "${fs_type}" != "xfs" ]] && [[ "${fs_type}" != "unknown" ]]; then
        log_warning "Filesystem sur ${hostname} n'est pas XFS (${fs_type})"
        # Vérifier si c'est un mountpoint (volume monté)
        local is_mountpoint=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \\
            "mountpoint -q /opt/keybuzz/postgres/data 2>/dev/null && echo 'yes' || echo 'no'")
        
        if [[ "${is_mountpoint}" == "yes" ]]; then
            log_warning "Volume monté mais filesystem ${fs_type} (XFS recommandé pour PostgreSQL)"
            log_warning "Le volume devrait être en XFS pour de meilleures performances"
        else
            log_warning "Répertoire non monté, utilisation du filesystem système (${fs_type})"
        fi
        
        # En mode non-interactif ou si volume monté, continuer automatiquement
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

# Pattern pour trouver et remplacer
pattern = r'    # Vérifier le filesystem XFS.*?    fi\n'
new_content = re.sub(pattern, new_section, content, flags=re.DOTALL)

# Écrire
with open('03_pg_02_install_patroni_cluster.sh', 'w') as f:
    f.write(new_content)

print("✅ 03_pg_02_install_patroni_cluster.sh corrigé")
PYFIX

# Correction 03_pg_apply_all.sh
python3 << 'PYFIX2'
with open('03_pg_apply_all.sh', 'r') as f:
    lines = f.readlines()

new_lines = []
added_export = False
added_unset = False

for i, line in enumerate(lines):
    new_lines.append(line)
    
    # Ajouter SKIP_FS_CHECK après le if du script patroni
    if 'if [[ -f "${SCRIPT_DIR}/03_pg_02_install_patroni_cluster.sh" ]]; then' in line and not added_export:
        new_lines.append('    # Activer le mode non-interactif pour la vérification filesystem si --yes est passé\n')
        new_lines.append('    if [[ "${NON_INTERACTIVE}" == "true" ]]; then\n')
        new_lines.append('        export SKIP_FS_CHECK="true"\n')
        new_lines.append('    fi\n')
        added_export = True
    
    # Ajouter unset après le log_success
    if 'log_success "Cluster Patroni installé"' in line and not added_unset:
        new_lines.append('    unset SKIP_FS_CHECK\n')
        added_unset = True

with open('03_pg_apply_all.sh', 'w') as f:
    f.writelines(new_lines)

if added_export or added_unset:
    print("✅ 03_pg_apply_all.sh corrigé")
else:
    print("ℹ️  03_pg_apply_all.sh déjà corrigé")
PYFIX2

echo ""
echo "✅ Corrections appliquées !"
echo ""
echo "Vérification:"
grep -c "SKIP_FS_CHECK" 03_pg_02_install_patroni_cluster.sh 2>/dev/null && echo "  - 03_pg_02_install_patroni_cluster.sh contient SKIP_FS_CHECK" || echo "  - Non trouvé"
grep -c "SKIP_FS_CHECK" 03_pg_apply_all.sh 2>/dev/null && echo "  - 03_pg_apply_all.sh contient SKIP_FS_CHECK" || echo "  - Non trouvé"













