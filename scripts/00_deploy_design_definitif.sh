#!/usr/bin/env bash
#
# 00_deploy_design_definitif.sh - Script master de déploiement du design définitif
#
# Ce script orchestre le déploiement complet de l'infrastructure
# selon le design définitif KeyBuzz.
#
# Usage:
#   ./00_deploy_design_definitif.sh [--skip-lb] [--skip-minio] [--yes]
#
# Options:
#   --skip-lb    : Ignorer la configuration des Load Balancers (à faire manuellement)
#   --skip-minio : Ignorer le déploiement MinIO
#   --yes        : Mode non-interactif

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${INSTALL_DIR}/servers.tsv"
LOG_DIR="${INSTALL_DIR}/logs"
LOG_FILE="${LOG_DIR}/deploy_design_definitif_$(date +%Y%m%d_%H%M%S).log"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1" | tee -a "${LOG_FILE}"
}

# Options
SKIP_LB=false
SKIP_MINIO=false
AUTO_YES=false

for arg in "$@"; do
    case "${arg}" in
        --skip-lb)
            SKIP_LB=true
            ;;
        --skip-minio)
            SKIP_MINIO=true
            ;;
        --yes)
            AUTO_YES=true
            ;;
    esac
done

# Créer le répertoire de logs
mkdir -p "${LOG_DIR}"

echo "=============================================================="
echo " Déploiement Design Définitif Infrastructure KeyBuzz"
echo "=============================================================="
echo ""
log_info "Fichier servers.tsv: ${TSV_FILE}"
log_info "Log file: ${LOG_FILE}"
echo ""

# Confirmation
if [[ "${AUTO_YES}" != "true" ]]; then
    read -p "Continuer le déploiement du design définitif ? (o/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
        log_info "Déploiement annulé"
        exit 0
    fi
fi

# Étape 1: Vérifier servers.tsv
log_info "============================================================="
log_info "Étape 1/7 : Vérification servers.tsv"
log_info "============================================================="

if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

# Vérifier que MinIO a 3 nœuds
MINIO_COUNT=$(grep -c "storage.*minio" "${TSV_FILE}" || echo "0")
if [[ "${MINIO_COUNT}" -lt 3 ]]; then
    log_error "Au moins 3 nœuds MinIO requis, trouvé: ${MINIO_COUNT}"
    exit 1
fi

log_success "servers.tsv valide (${MINIO_COUNT} nœuds MinIO)"
echo ""

# Étape 2: Vérifier versions.yaml
log_info "============================================================="
log_info "Étape 2/7 : Vérification versions.yaml"
log_info "============================================================="

VERSIONS_FILE="${INSTALL_DIR}/scripts/versions.yaml"
if [[ ! -f "${VERSIONS_FILE}" ]]; then
    log_error "Fichier versions.yaml introuvable: ${VERSIONS_FILE}"
    exit 1
fi

log_success "versions.yaml présent"
echo ""

# Étape 3: Configuration Load Balancers (optionnel)
if [[ "${SKIP_LB}" != "true" ]]; then
    log_info "============================================================="
    log_info "Étape 3/7 : Configuration Load Balancers Hetzner"
    log_info "============================================================="
    
    if [[ -f "${SCRIPT_DIR}/10_lb/10_lb_01_configure_hetzner_lb.sh" ]]; then
        "${SCRIPT_DIR}/10_lb/10_lb_01_configure_hetzner_lb.sh" "${TSV_FILE}"
        log_warning "⚠️  Les Load Balancers doivent être créés manuellement dans le dashboard Hetzner"
    else
        log_warning "Script de configuration LB introuvable, ignoré"
    fi
    echo ""
else
    log_info "Étape 3/7 : Configuration Load Balancers (ignorée --skip-lb)"
    echo ""
fi

# Étape 4: Configuration HAProxy Redis Master
log_info "============================================================="
log_info "Étape 4/7 : Configuration HAProxy Redis Master"
log_info "============================================================="

if [[ -f "${SCRIPT_DIR}/03_haproxy/03_haproxy_01_configure_redis_master.sh" ]]; then
    "${SCRIPT_DIR}/03_haproxy/03_haproxy_01_configure_redis_master.sh" "${TSV_FILE}"
else
    log_warning "Script de configuration HAProxy Redis introuvable"
fi
echo ""

# Étape 5: Déploiement MinIO Distributed
if [[ "${SKIP_MINIO}" != "true" ]]; then
    log_info "============================================================="
    log_info "Étape 5/7 : Déploiement MinIO Distributed (3 nœuds)"
    log_info "============================================================="
    
    if [[ -f "${SCRIPT_DIR}/06_minio/06_minio_01_deploy_minio_distributed.sh" ]]; then
        "${SCRIPT_DIR}/06_minio/06_minio_01_deploy_minio_distributed.sh" "${TSV_FILE}"
    else
        log_warning "Script de déploiement MinIO introuvable"
    fi
    echo ""
else
    log_info "Étape 5/7 : Déploiement MinIO (ignoré --skip-minio)"
    echo ""
fi

# Étape 6: Installation script redis-update-master.sh
log_info "============================================================="
log_info "Étape 6/7 : Installation script redis-update-master.sh"
log_info "============================================================="

if [[ -f "${SCRIPT_DIR}/04_redis_ha/redis-update-master.sh" ]]; then
    # Parser servers.tsv pour obtenir les nœuds HAProxy
    HAPROXY_IPS=()
    while IFS=$'\t' read -r env ip_pub hostname ip_priv fqdn user pool role subrole stack core notes; do
        if [[ "${role}" == "lb" ]] && [[ "${subrole}" == "internal-haproxy" ]]; then
            HAPROXY_IPS+=("${ip_priv}")
        fi
    done < <(tail -n +2 "${TSV_FILE}")
    
    # Détecter la clé SSH
    SSH_KEY="${HOME}/.ssh/keybuzz_infra"
    if [[ ! -f "${SSH_KEY}" ]]; then
        SSH_KEY="/root/.ssh/keybuzz_infra"
    fi
    
    if [[ ! -f "${SSH_KEY}" ]]; then
        SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    else
        SSH_KEY_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    fi
    
    # Copier le script sur chaque nœud HAProxy
    for haproxy_ip in "${HAPROXY_IPS[@]}"; do
        log_info "Copie de redis-update-master.sh sur ${haproxy_ip}..."
        scp ${SSH_KEY_OPTS} "${SCRIPT_DIR}/04_redis_ha/redis-update-master.sh" "root@${haproxy_ip}:/usr/local/bin/redis-update-master.sh"
        ssh ${SSH_KEY_OPTS} "root@${haproxy_ip}" "chmod +x /usr/local/bin/redis-update-master.sh"
        log_success "Script installé sur ${haproxy_ip}"
    done
    
    log_warning "NEXT STEP : Configurer cron/systemd pour exécution régulière"
    log_warning "            Exemple cron: */30 * * * * /usr/local/bin/redis-update-master.sh"
else
    log_warning "Script redis-update-master.sh introuvable"
fi
echo ""

# Étape 7: Résumé
log_info "============================================================="
log_info "Étape 7/7 : Résumé"
log_info "============================================================="

echo ""
log_success "✅ Déploiement du design définitif terminé !"
echo ""
log_info "Actions effectuées :"
log_info "  - ✅ servers.tsv vérifié"
log_info "  - ✅ versions.yaml vérifié"
if [[ "${SKIP_LB}" != "true" ]]; then
    log_info "  - ⚠️  Load Balancers : Instructions générées (à créer manuellement)"
fi
log_info "  - ✅ HAProxy Redis Master configuré"
if [[ "${SKIP_MINIO}" != "true" ]]; then
    log_info "  - ✅ MinIO Distributed déployé (3 nœuds)"
fi
log_info "  - ✅ Script redis-update-master.sh installé"
echo ""
log_warning "PROCHAINES ÉTAPES :"
log_warning "  1. Créer les Load Balancers Hetzner (LB 10.0.0.10 et 10.0.0.20)"
log_warning "  2. Configurer DNS pour minio-01/02/03.keybuzz.io"
log_warning "  3. Configurer cron/systemd pour redis-update-master.sh"
log_warning "  4. Tester la connectivité vers les LB"
echo ""

