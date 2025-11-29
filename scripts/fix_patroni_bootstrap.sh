#!/usr/bin/env bash
#
# fix_patroni_bootstrap.sh - Script pour forcer le bootstrap du cluster Patroni
#
# Ce script force le bootstrap du cluster Patroni RAFT en :
# 1. Arrêtant tous les nœuds
# 2. Nettoyant complètement les répertoires RAFT et PostgreSQL
# 3. Redémarrant tous les nœuds simultanément
#
# Usage:
#   ./fix_patroni_bootstrap.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Tous les nœuds DB accessibles via SSH

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

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

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Collecter les IPs des nœuds DB
declare -a DB_IPS
DB_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    [[ "${ENV}" == "ENV" ]] && continue
    [[ "${ENV}" != "prod" ]] && continue
    [[ "${ROLE}" != "db" ]] && continue
    [[ "${SUBROLE}" != "postgres" ]] && continue
    [[ -z "${IP_PRIVEE}" ]] && continue
    
    DB_IPS+=("${IP_PRIVEE}")
done
exec 3<&-

if [[ ${#DB_IPS[@]} -eq 0 ]]; then
    log_error "Aucun nœud PostgreSQL trouvé dans ${TSV_FILE}"
    exit 1
fi

log_info "Nœuds PostgreSQL trouvés: ${DB_IPS[*]}"
echo ""

log_warning "Ce script va :"
log_warning "  1. Arrêter tous les containers Patroni"
log_warning "  2. Nettoyer les répertoires RAFT sur tous les nœuds"
log_warning "  3. Nettoyer les données PostgreSQL sur tous les nœuds"
log_warning "  4. Redémarrer tous les nœuds simultanément pour bootstrap"
echo ""
read -p "Continuer ? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Annulé"
    exit 0
fi

echo ""
log_section "Étape 1: Arrêt de tous les containers Patroni"

for ip in "${DB_IPS[@]}"; do
    log_info "Arrêt du container Patroni sur ${ip}..."
    if ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=no root@"${ip}" \
        "docker stop patroni 2>&1" >/dev/null 2>&1; then
        log_success "Container arrêté sur ${ip}"
    else
        log_warning "Container déjà arrêté ou inexistant sur ${ip}"
    fi
done

echo ""
log_section "Étape 2: Nettoyage des répertoires RAFT"

for ip in "${DB_IPS[@]}"; do
    log_info "Nettoyage RAFT sur ${ip}..."
    if ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=no root@"${ip}" \
        "rm -rf /opt/keybuzz/postgres/raft/* 2>&1" >/dev/null 2>&1; then
        log_success "RAFT nettoyé sur ${ip}"
    else
        log_warning "Nettoyage RAFT échoué sur ${ip}"
    fi
done

echo ""
log_section "Étape 3: Nettoyage des données PostgreSQL"

for ip in "${DB_IPS[@]}"; do
    log_info "Nettoyage données PostgreSQL sur ${ip}..."
    if ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=no root@"${ip}" \
        "rm -rf /opt/keybuzz/postgres/data/* 2>&1" >/dev/null 2>&1; then
        log_success "Données PostgreSQL nettoyées sur ${ip}"
    else
        log_warning "Nettoyage données échoué sur ${ip}"
    fi
done

echo ""
log_section "Étape 4: Redémarrage simultané de tous les nœuds"

log_info "Redémarrage de tous les containers Patroni..."
for ip in "${DB_IPS[@]}"; do
    ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=no root@"${ip}" \
        "docker start patroni 2>&1" >/dev/null 2>&1 &
done

wait

log_success "Tous les containers redémarrés"
echo ""

log_info "Attente 30 secondes pour le bootstrap RAFT..."
sleep 30

echo ""
log_section "Étape 5: Vérification du bootstrap"

FIRST_IP="${DB_IPS[0]}"
log_info "Vérification du statut du cluster sur ${FIRST_IP}..."

CLUSTER_STATUS=$(ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=no root@"${FIRST_IP}" \
    "docker exec patroni patronictl -c /etc/patroni/patroni.yml list 2>&1" || echo "")

if echo "${CLUSTER_STATUS}" | grep -q "Leader"; then
    log_success "Cluster bootstrappé avec succès !"
    echo ""
    echo "${CLUSTER_STATUS}"
    echo ""
    log_success "Le cluster Patroni est maintenant opérationnel"
    exit 0
else
    log_error "Le cluster n'a pas bootstrappé correctement"
    echo ""
    echo "${CLUSTER_STATUS}"
    echo ""
    log_warning "Vérifiez les logs sur chaque nœud: docker logs patroni"
    exit 1
fi

