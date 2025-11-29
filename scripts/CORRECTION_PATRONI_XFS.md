# Correction Script Patroni - Vérification Filesystem XFS

**Date** : 2025-11-23  
**Problème** : Script d'installation Patroni s'arrête si filesystem n'est pas XFS  
**Solution** : Accepter automatiquement en mode non-interactif ou si volume monté

---

## 🔍 Problème Identifié

Le script `03_pg_02_install_patroni_cluster.sh` vérifie que le filesystem de `/opt/keybuzz/postgres/data` est XFS et s'arrête avec une demande de confirmation si ce n'est pas le cas.

**Constat** :
- Les serveurs ont le filesystem racine en **ext4** (normal)
- Seuls les **volumes montés** doivent être en **XFS** (recommandé pour PostgreSQL)
- Le script doit vérifier si c'est un **volume monté**, pas uniquement le filesystem

---

## ✅ Corrections Appliquées

### 1. Script `03_pg_02_install_patroni_cluster.sh`

**Lignes 163-176** : Vérification filesystem améliorée

**Avant** :
```bash
if [[ "${fs_type}" != "xfs" ]] && [[ "${fs_type}" != "unknown" ]]; then
    log_warning "Filesystem sur ${hostname} n'est pas XFS (${fs_type})"
    log_warning "Continuez quand même ? (y/N)"
    read -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_error "Installation annulée"
        return 1
    fi
fi
```

**Après** :
```bash
if [[ "${fs_type}" != "xfs" ]] && [[ "${fs_type}" != "unknown" ]]; then
    log_warning "Filesystem sur ${hostname} n'est pas XFS (${fs_type})"
    # Vérifier si c'est un mountpoint (volume monté)
    local is_mountpoint=$(ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" \
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
```

**Améliorations** :
1. ✅ Vérifie si `/opt/keybuzz/postgres/data` est un mountpoint (volume monté)
2. ✅ Accepte automatiquement en mode non-interactif (`SKIP_FS_CHECK=true`)
3. ✅ Accepte automatiquement si un volume est monté (même si pas XFS)
4. ✅ Affiche un message de succès si XFS est détecté

### 2. Script `03_pg_apply_all.sh`

**Lignes 107-117** : Passage de la variable `SKIP_FS_CHECK` en mode `--yes`

**Ajout** :
```bash
# Activer le mode non-interactif pour la vérification filesystem si --yes est passé
if [[ "${NON_INTERACTIVE}" == "true" ]]; then
    export SKIP_FS_CHECK="true"
fi
if "${SCRIPT_DIR}/03_pg_02_install_patroni_cluster.sh" "${TSV_FILE}"; then
    log_success "Cluster Patroni installé"
else
    log_error "Échec de l'installation du cluster Patroni"
    exit 1
fi
unset SKIP_FS_CHECK
```

---

## 🚀 Utilisation

### Installation avec `--yes` (non-interactif)

```bash
cd /opt/keybuzz-installer/scripts/03_postgresql_ha
./03_pg_apply_all.sh ../../servers.tsv --yes
```

Le script acceptera automatiquement même si le filesystem n'est pas XFS, mais affichera un avertissement.

### Installation Interactive

```bash
./03_pg_apply_all.sh ../../servers.tsv
```

Le script demandera confirmation si le filesystem n'est pas XFS, sauf si un volume est monté (acceptation automatique).

---

## 📝 Notes

- **XFS recommandé** : Pour PostgreSQL, XFS est recommandé sur les volumes montés pour de meilleures performances
- **ext4 acceptable** : Si le volume est monté en ext4, cela fonctionnera mais avec des performances moindres
- **Mode non-interactif** : Avec `--yes`, le script ne demande jamais confirmation

---

## ✅ Validation

Après correction, le script doit :
1. ✅ Continuer automatiquement en mode `--yes` même si filesystem != XFS
2. ✅ Détecter si un volume est monté et accepter automatiquement
3. ✅ Afficher un avertissement clair sur les performances
4. ✅ Fonctionner correctement si XFS est présent

---

**Statut** : ✅ Corrections appliquées localement, à copier sur install-01













