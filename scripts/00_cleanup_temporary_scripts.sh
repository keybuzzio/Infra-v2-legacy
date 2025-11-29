#!/usr/bin/env bash
#
# 00_cleanup_temporary_scripts.sh - Nettoyage des scripts temporaires
#
# Ce script archive les scripts temporaires créés pendant le diagnostic 504/503
# dans un dossier archive/ pour référence future.
#
# Usage:
#   ./00_cleanup_temporary_scripts.sh [--dry-run]
#
# Options:
#   --dry-run : Affiche ce qui sera fait sans le faire

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_DIR="${SCRIPT_DIR}/archive/diagnostic_504"
DRY_RUN="${1:-}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

# Header
echo "=============================================================="
echo " Nettoyage des Scripts Temporaires"
echo "=============================================================="
echo ""

if [[ "${DRY_RUN}" == "--dry-run" ]]; then
    log_warning "Mode DRY-RUN : Aucun fichier ne sera déplacé"
    echo ""
fi

# Créer le dossier archive
if [[ "${DRY_RUN}" != "--dry-run" ]]; then
    mkdir -p "${ARCHIVE_DIR}"
    log_success "Dossier archive créé: ${ARCHIVE_DIR}"
else
    log_info "Créerait: ${ARCHIVE_DIR}"
fi
echo ""

# Liste des scripts à archiver
declare -a SCRIPTS_TO_ARCHIVE=(
    # Diagnostic 504
    "00_diagnose_504.sh"
    "00_diagnose_504_complete.sh"
    "00_diagnose_504_from_install01.sh"
    "00_diagnose_504_intermittent.sh"
    "00_diagnose_internal_504.sh"
    "00_diagnose_503.sh"
    "00_final_diagnosis_504.sh"
    
    # Tests 504
    "00_test_504_from_master.sh"
    "00_test_after_ufw_fix.sh"
    "00_test_connectivity_workers.sh"
    "00_test_from_workers.sh"
    "00_test_ingress_connectivity.sh"
    "00_test_pod_network.sh"
    "00_test_service_final.sh"
    "00_test_stability.sh"
    "00_test_stability_120s.sh"
    "00_final_test_504.sh"
    "00_final_test_after_flannel_fix.sh"
    
    # Corrections 504 (tentatives échouées)
    "00_fix_504_complete.sh"
    "00_fix_504_definitive.sh"
    "00_fix_504_final_summary.sh"
    "00_fix_ingress_504.sh"
    "00_fix_network_connectivity.sh"
    "00_fix_dns_resolution.sh"
    
    # UFW (tentatives multiples)
    "00_add_ufw_all_workers.sh"
    "00_add_ufw_rules_k3s.sh"
    "00_add_ufw_workers_simple.sh"
    "00_apply_ufw_direct.sh"
    "00_apply_ufw_private_ips.sh"
    "00_apply_ufw_rules_all_nodes.sh"
    "00_apply_ufw_workers.sh"
    "00_fix_ufw_all_k3s_nodes.sh"
    "00_fix_ufw_flannel_interface.sh"
    "00_fix_ufw_k3s_direct.sh"
    "00_fix_ufw_k3s_network.sh"
    "00_fix_ufw_k3s_networks_complete.sh"
    "00_fix_ufw_k3s_simple.sh"
    
    # iptables/Flannel
    "00_fix_iptables_forward.sh"
    "00_fix_iptables_kube_forward.sh"
    "00_fix_flannel_routing.sh"
    "00_fix_missing_flannel_route.sh"
    
    # K3s Services
    "00_fix_k3s_services_clusterip.sh"
    
    # Restauration Services
    "00_restore_services.sh"
    "00_restore_services_simple.sh"
    
    # DNS/LB
    "00_check_dns_lb_config.sh"
    
    # Script temporaire KeyBuzz (remplacé)
    "00_create_keybuzz_daemonsets.sh"
)

# Scripts à garder (utiles)
declare -a SCRIPTS_TO_KEEP=(
    "00_fix_504_keybuzz_complete.sh"  # Solution finale (peut être utile)
    "00_fix_ufw_nodeports_keybuzz.sh"  # Utile pour ouvrir ports NodePort
    "00_validate_504_fix.sh"            # Utile pour validation
)

# Archiver les scripts
ARCHIVED=0
NOT_FOUND=0

log_info "Archivage des scripts temporaires..."
echo ""

for script in "${SCRIPTS_TO_ARCHIVE[@]}"; do
    script_path="${SCRIPT_DIR}/${script}"
    
    if [[ -f "${script_path}" ]]; then
        if [[ "${DRY_RUN}" == "--dry-run" ]]; then
            log_info "  → Archiverait: ${script}"
        else
            mv "${script_path}" "${ARCHIVE_DIR}/"
            log_success "  ✓ Archivé: ${script}"
        fi
        ((ARCHIVED++))
    else
        if [[ "${DRY_RUN}" != "--dry-run" ]]; then
            log_warning "  ⚠ Introuvable: ${script}"
        fi
        ((NOT_FOUND++))
    fi
done

echo ""
log_info "Scripts archivés: ${ARCHIVED}"
if [[ ${NOT_FOUND} -gt 0 ]]; then
    log_warning "Scripts introuvables: ${NOT_FOUND}"
fi
echo ""

# Afficher les scripts gardés
log_info "Scripts conservés (utiles):"
for script in "${SCRIPTS_TO_KEEP[@]}"; do
    if [[ -f "${SCRIPT_DIR}/${script}" ]]; then
        log_success "  ✓ ${script}"
    fi
done
echo ""

# Créer un README dans l'archive
if [[ "${DRY_RUN}" != "--dry-run" ]]; then
    cat > "${ARCHIVE_DIR}/README.md" <<EOF
# Archive - Scripts de Diagnostic 504/503

Ce dossier contient les scripts temporaires créés pendant le diagnostic et la résolution du problème 504 Gateway Timeout.

## 📋 Contenu

Ces scripts ont été créés pour diagnostiquer et tenter de résoudre le problème 504, qui s'est finalement révélé être causé par le blocage VXLAN sur Hetzner Cloud.

## ✅ Solution Finale

La solution validée est documentée dans :
- \`10_keybuzz/SOLUTION_HOSTNETWORK.md\`
- \`10_keybuzz/LESSONS_LEARNED.md\`

## 📝 Scripts Conservés

Les scripts suivants ont été conservés car ils peuvent être utiles :
- \`00_fix_504_keybuzz_complete.sh\` : Solution finale (peut être utile)
- \`00_fix_ufw_nodeports_keybuzz.sh\` : Ouverture ports NodePort
- \`00_validate_504_fix.sh\` : Validation de la correction

## 🗓️ Date d'Archivage

$(date)

---

**Note** : Ces scripts sont conservés uniquement pour référence historique. Ne pas utiliser pour de nouvelles installations.
EOF
    log_success "README créé dans l'archive"
fi

echo ""
echo "=============================================================="
if [[ "${DRY_RUN}" == "--dry-run" ]]; then
    log_info "✅ Nettoyage simulé terminé"
    log_info "Relancez sans --dry-run pour effectuer le nettoyage"
else
    log_success "✅ Nettoyage terminé"
    log_info "Scripts archivés dans: ${ARCHIVE_DIR}"
fi
echo "=============================================================="
echo ""

