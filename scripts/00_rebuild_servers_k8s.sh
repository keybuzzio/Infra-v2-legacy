#!/bin/bash
# rebuild_servers_k8s.sh
# Script pour rebuild les serveurs K8s avec Ubuntu 24.04
#
# Usage:
#   bash 00_rebuild_servers_k8s.sh
#

set -uo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fonctions d'affichage
log() { echo -e "${CYAN}[INFO]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
ko() { echo -e "${RED}[FAIL]${NC} $1"; }
section() { echo -e "\n${BLUE}════════════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}\n"; }

# Token Hetzner Cloud
export HCLOUD_TOKEN='PvaKOohQayiL8MpTsPpkzDMdWqRLauDErV4NTCwUKF333VeZ5wDDqFbKZb1q7HrE'

# Liste des serveurs K8s à rebuild
declare -a K8S_SERVERS=(
    "k8s-master-01"
    "k8s-master-02"
    "k8s-master-03"
    "k8s-worker-01"
    "k8s-worker-02"
    "k8s-worker-03"
    "k8s-worker-04"
    "k8s-worker-05"
)

# Vérifier que hcloud est installé
check_dependencies() {
    section "Vérification des dépendances"
    
    if ! command -v hcloud &> /dev/null; then
        ko "hcloud CLI n'est pas installé"
        exit 1
    fi
    
    # Vérifier le token
    if ! hcloud server list &> /dev/null; then
        ko "Impossible de se connecter à Hetzner Cloud. Vérifiez le token."
        exit 1
    fi
    ok "Connexion Hetzner Cloud OK"
}

# Rebuild un serveur
rebuild_server() {
    local server_name=$1
    local image="ubuntu-24.04"
    
    log "Rebuild de $server_name avec $image..."
    
    # Lancer le rebuild
    if ! hcloud server rebuild --image "$image" "$server_name" &>/dev/null; then
        return 1
    fi
    
    ok "$server_name en cours de rebuild"
    return 0
}

# Main
main() {
    section "Rebuild des serveurs K8s avec Ubuntu 24.04"
    
    log "Ce script va rebuild ${#K8S_SERVERS[@]} serveurs K8s avec Ubuntu 24.04"
    log "Les serveurs seront rebuildés en parallèle"
    echo ""
    log "Démarrage automatique..."
    echo ""
    
    check_dependencies
    
    section "Lancement des rebuilds en parallèle"
    
    local pids=()
    local server_names=()
    local rebuilt=0
    local failed=0
    
    # Lancer tous les rebuilds en arrière-plan
    for server_name in "${K8S_SERVERS[@]}"; do
        (
            if rebuild_server "$server_name"; then
                echo "SUCCESS:$server_name" > /tmp/rebuild_${server_name}.result
            else
                echo "FAILED:$server_name" > /tmp/rebuild_${server_name}.result
            fi
        ) &
        
        local pid=$!
        pids+=($pid)
        server_names+=("$server_name")
        log "  PID: $pid pour $server_name"
    done
    
    echo ""
    log "Attente de la fin de tous les rebuilds (${#pids[@]} serveurs)..."
    log "Cela peut prendre 3-5 minutes..."
    
    # Attendre tous les processus
    for pid in "${pids[@]}"; do
        wait $pid 2>/dev/null
    done
    
    # Récupérer les résultats
    echo ""
    for server_name in "${server_names[@]}"; do
        if [ -f "/tmp/rebuild_${server_name}.result" ]; then
            local result
            result=$(cat "/tmp/rebuild_${server_name}.result" 2>/dev/null || echo "")
            if [[ "$result" == "SUCCESS:"* ]]; then
                ok "$server_name : rebuild lancé avec succès"
                ((rebuilt++))
            else
                ko "$server_name : rebuild échoué"
                ((failed++))
            fi
            rm -f "/tmp/rebuild_${server_name}.result"
        else
            warn "$server_name : résultat non trouvé"
            ((failed++))
        fi
    done
    
    echo ""
    section "Résumé"
    echo "Rebuilds lancés: $rebuilt"
    echo "Échecs: $failed"
    echo ""
    
    if [ $failed -eq 0 ]; then
        ok "Tous les rebuilds ont été lancés avec succès"
        log "Attendez 3-5 minutes que les serveurs soient prêts avant de relancer le déploiement SSH"
    else
        warn "Certains rebuilds ont échoué ($failed échecs)"
    fi
}

main "$@"

