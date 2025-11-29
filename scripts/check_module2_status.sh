#!/usr/bin/env bash
#
# check_module2_status.sh - Vérifie le statut du Module 2
#
# Usage:
#   ./check_module2_status.sh [--watch] [--interval SECONDS]
#
# Options:
#   --watch           : Surveille en continu (Ctrl+C pour arrêter)
#   --interval N      : Intervalle en secondes (défaut: 30)

set -uo pipefail

LOG_FILE="/tmp/module2_final_complet.log"
WATCH_MODE=false
INTERVAL=30

while [[ $# -gt 0 ]]; do
    case $1 in
        --watch)
            WATCH_MODE=true
            shift
            ;;
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "Usage: $0 [--watch] [--interval SECONDS]"
            exit 1
            ;;
    esac
done

check_status() {
    local total_servers=49
    local success_count=0
    local error_count=0
    local is_running=false
    
    if [[ ! -f "${LOG_FILE}" ]]; then
        echo "❌ Fichier de log introuvable: ${LOG_FILE}"
        return 1
    fi
    
    success_count=$(grep -c "Serveur.*traité avec succès" "${LOG_FILE}" 2>/dev/null || echo "0")
    error_count=$(grep -c "Erreur" "${LOG_FILE}" 2>/dev/null || echo "0")
    is_running=$(ps aux | grep -q "[a]pply_base_os_to_all" && echo "true" || echo "false")
    
    echo "=============================================================="
    echo " [KeyBuzz] Statut Module 2 - Base OS & Sécurité"
    echo "=============================================================="
    echo ""
    echo "Date: $(date)"
    echo ""
    echo "Progression:"
    echo "  Serveurs traités avec succès: ${success_count}/${total_servers}"
    echo "  Erreurs: ${error_count}"
    echo "  Restants: $((total_servers - success_count))"
    echo ""
    
    if [[ "${is_running}" == "true" ]]; then
        echo "Status: 🟢 EN COURS"
        echo ""
        echo "Dernières lignes du log:"
        tail -5 "${LOG_FILE}" | sed 's/^/  /'
    else
        echo "Status: 🔴 TERMINÉ"
        echo ""
        if [[ "${success_count}" -eq "${total_servers}" ]]; then
            echo "✅ Tous les serveurs ont été traités avec succès !"
        else
            echo "⚠️  Installation terminée mais certains serveurs n'ont pas été traités"
        fi
    fi
    
    echo ""
    echo "=============================================================="
}

if [[ "${WATCH_MODE}" == "true" ]]; then
    echo "Surveillance du Module 2 (Ctrl+C pour arrêter)..."
    echo ""
    while true; do
        clear
        check_status
        sleep "${INTERVAL}"
    done
else
    check_status
fi


