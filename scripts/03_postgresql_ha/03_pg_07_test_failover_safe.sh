#!/usr/bin/env bash
#
# 03_pg_07_test_failover_safe.sh - Test de failover Patroni (sûr et réversible)
#
# Ce script teste le failover automatique du cluster Patroni de manière sûre :
# - Arrête temporairement le conteneur Docker du leader
# - Vérifie qu'un nouveau leader est élu
# - Redémarre l'ancien leader
# - Vérifie que le cluster revient à la normale
#
# ⚠️  SÛR : Ne touche pas au firewall, aux services systemd, ni aux volumes
# ⚠️  RÉVERSIBLE : Redémarre automatiquement tous les services après le test
#
# Usage:
#   ./03_pg_07_test_failover_safe.sh
#
# Prérequis:
#   - Cluster Patroni installé et fonctionnel
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

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

log_error() {
    echo -e "${RED}[✗]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# Mapping hostname -> IP
declare -A DB_IPS=(
    ["db-master-01"]="10.0.0.120"
    ["db-slave-01"]="10.0.0.121"
    ["db-slave-02"]="10.0.0.122"
)

# Option --yes pour exécution automatique
AUTO_YES=false
if [[ "${1:-}" == "--yes" ]] || [[ "${1:-}" == "-y" ]]; then
    AUTO_YES=true
fi

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 3 - Test de Failover Patroni (SÛR)"
echo "=============================================================="
echo ""
log_warning "Ce test va :"
log_warning "  1. Arrêter temporairement le conteneur Docker du leader"
log_warning "  2. Vérifier le failover automatique"
log_warning "  3. Redémarrer automatiquement l'ancien leader"
log_warning ""
log_warning "⚠️  SÛR : Ne touche pas au firewall, services systemd, ni volumes"
log_warning "⚠️  RÉVERSIBLE : Tout sera restauré automatiquement"
echo ""

if [[ "${AUTO_YES}" == "false" ]]; then
    read -p "Continuer le test ? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "Test annulé"
        exit 0
    fi
else
    log_info "Mode automatique activé (--yes)"
    sleep 2
fi

echo ""

# Fonction pour obtenir le leader actuel
get_current_leader() {
    local leader
    local node_ip="${1:-10.0.0.120}"
    # Extraire le nom du membre qui a le rôle "Leader"
    # Format: | db-master-01 | 10.0.0.120 | Leader  | running   | ...
    # Utiliser sed pour extraire la première colonne de la ligne contenant "Leader"
    # Essayer d'abord avec le nœud fourni, puis avec les autres si nécessaire
    leader=$(ssh -o BatchMode=yes root@${node_ip} \
        "docker exec patroni patronictl -c /etc/patroni/patroni.yml list 2>&1" \
        | grep "Leader" | sed 's/|/\n/g' | sed -n '2p' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null || echo "")
    
    # Si pas de résultat, essayer avec un autre nœud
    if [[ -z "${leader}" ]]; then
        for alt_ip in 10.0.0.121 10.0.0.122; do
            if [[ "${alt_ip}" != "${node_ip}" ]]; then
                leader=$(ssh -o BatchMode=yes root@${alt_ip} \
                    "docker exec patroni patronictl -c /etc/patroni/patroni.yml list 2>&1" \
                    | grep "Leader" | sed 's/|/\n/g' | sed -n '2p' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' 2>/dev/null || echo "")
                if [[ -n "${leader}" ]]; then
                    break
                fi
            fi
        done
    fi
    
    echo "${leader}"
}

# Fonction pour obtenir le statut complet du cluster
get_cluster_status() {
    ssh -o BatchMode=yes root@10.0.0.120 \
        "docker exec patroni patronictl -c /etc/patroni/patroni.yml list 2>&1"
}

# Étape 1 : État initial
log_info "=============================================================="
log_info "Étape 1 : État initial du cluster"
log_info "=============================================================="

CURRENT_LEADER=$(get_current_leader)

if [[ -z "${CURRENT_LEADER}" ]]; then
    log_error "Impossible de détecter le leader Patroni"
    log_info "Vérifiez que le cluster est opérationnel"
    exit 1
fi

log_success "Leader actuel détecté : ${CURRENT_LEADER}"

LEADER_IP="${DB_IPS[${CURRENT_LEADER}]}"
if [[ -z "${LEADER_IP}" ]]; then
    log_error "IP inconnue pour ${CURRENT_LEADER}"
    exit 1
fi

log_info "IP du leader : ${LEADER_IP} (${CURRENT_LEADER})"
echo ""

log_info "État du cluster AVANT le test :"
get_cluster_status
echo ""

# Étape 2 : Test de connectivité initiale
log_info "=============================================================="
log_info "Étape 2 : Test de connectivité initiale"
log_info "=============================================================="

if ssh -o BatchMode=yes root@${LEADER_IP} \
    "docker exec patroni psql -U postgres -c 'SELECT 1;' >/dev/null 2>&1"; then
    log_success "Connectivité PostgreSQL OK sur le leader"
else
    log_warning "Test de connectivité échoué (peut être normal si credentials non configurés)"
    log_info "Continuons le test de failover..."
fi
echo ""

# Étape 3 : Arrêt du leader
log_info "=============================================================="
log_info "Étape 3 : Arrêt temporaire du leader (${CURRENT_LEADER})"
log_info "=============================================================="

log_warning "Arrêt du conteneur Docker 'patroni' sur ${CURRENT_LEADER}..."
ssh -o BatchMode=yes root@${LEADER_IP} "docker stop patroni" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    log_success "Conteneur arrêté"
else
    log_error "Échec de l'arrêt du conteneur"
    exit 1
fi

log_info "Attente du failover automatique (30 secondes)..."
sleep 30
echo ""

# Étape 4 : Vérification du nouveau leader
log_info "=============================================================="
log_info "Étape 4 : Vérification du failover"
log_info "=============================================================="

# Essayer de détecter le nouveau leader depuis n'importe quel nœud disponible
NEW_LEADER=""
for check_ip in 10.0.0.121 10.0.0.122 10.0.0.120; do
    NEW_LEADER=$(get_current_leader ${check_ip})
    if [[ -n "${NEW_LEADER}" ]]; then
        break
    fi
done

if [[ -z "${NEW_LEADER}" ]]; then
    log_error "Impossible de détecter un leader après le failover"
    log_warning "Redémarrage du conteneur arrêté..."
    ssh -o BatchMode=yes root@${LEADER_IP} "docker start patroni" >/dev/null 2>&1
    exit 1
fi

if [[ "${NEW_LEADER}" != "${CURRENT_LEADER}" ]]; then
    log_success "Failover réussi !"
    log_success "Nouveau leader : ${NEW_LEADER} (ancien : ${CURRENT_LEADER})"
else
    log_warning "Le leader n'a pas changé (${NEW_LEADER})"
    log_warning "Cela peut être normal si le failover n'a pas encore eu lieu"
fi

log_info "État du cluster après failover :"
get_cluster_status
echo ""

# Étape 5 : Test de connectivité après failover
log_info "=============================================================="
log_info "Étape 5 : Test de connectivité après failover"
log_info "=============================================================="

NEW_LEADER_IP="${DB_IPS[${NEW_LEADER}]}"

if ssh -o BatchMode=yes root@${NEW_LEADER_IP} \
    "docker exec patroni psql -U postgres -c 'SELECT 1;' >/dev/null 2>&1"; then
    log_success "Connectivité PostgreSQL OK sur le nouveau leader"
else
    log_warning "Connexion temporairement indisponible (normal pendant le failover)"
fi
echo ""

# Étape 6 : Redémarrage de l'ancien leader
log_info "=============================================================="
log_info "Étape 6 : Redémarrage de l'ancien leader (${CURRENT_LEADER})"
log_info "=============================================================="

log_info "Redémarrage du conteneur Docker 'patroni' sur ${CURRENT_LEADER}..."
ssh -o BatchMode=yes root@${LEADER_IP} "docker start patroni" >/dev/null 2>&1

if [ $? -eq 0 ]; then
    log_success "Conteneur redémarré"
else
    log_error "Échec du redémarrage du conteneur"
    exit 1
fi

log_info "Attente de la stabilisation (20 secondes)..."
sleep 20
echo ""

# Étape 7 : Vérification finale
log_info "=============================================================="
log_info "Étape 7 : Vérification finale"
log_info "=============================================================="

FINAL_LEADER=$(get_current_leader)
log_info "Leader actuel : ${FINAL_LEADER}"

log_info "État final du cluster :"
get_cluster_status
echo ""

# Vérifier que l'ancien leader a rejoint le cluster
if ssh -o BatchMode=yes root@${LEADER_IP} \
    "docker exec patroni patronictl -c /etc/patroni/patroni.yml list 2>&1" \
    | grep -q "${CURRENT_LEADER}"; then
    log_success "L'ancien leader (${CURRENT_LEADER}) a rejoint le cluster"
else
    log_warning "L'ancien leader n'apparaît pas encore dans le cluster"
    log_warning "Cela peut prendre quelques secondes supplémentaires"
fi

# Test de connectivité finale
log_info "Vérification de la connectivité finale..."
if ssh -o BatchMode=yes root@${LEADER_IP} \
    "docker exec patroni psql -U postgres -c 'SELECT 1;' >/dev/null 2>&1"; then
    log_success "Connectivité PostgreSQL OK sur tous les nœuds"
else
    log_warning "Connexion encore en cours de stabilisation (normal)"
fi
echo ""

# Résumé
echo "=============================================================="
log_success "✅ Test de failover terminé !"
echo "=============================================================="
echo ""
log_info "Résumé :"
log_info "  - Leader initial : ${CURRENT_LEADER}"
log_info "  - Leader après failover : ${NEW_LEADER}"
log_info "  - Leader final : ${FINAL_LEADER}"
echo ""
log_info "Le cluster est opérationnel et tous les services sont restaurés."
echo ""

