#!/usr/bin/env bash
#
# 00_restore_services.sh - Restauration des services backend sans perte de données
#
# Ce script restaure PostgreSQL HA et Redis HA en préservant les données existantes.
#
# Usage:
#   ./00_restore_services.sh [--force]
#
# Options:
#   --force : Force la réinstallation même si les services semblent fonctionner
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Les volumes de données doivent être présents

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Trouver servers.tsv
TSV_FILE="${INSTALL_DIR}/servers.tsv"
if [[ ! -f "${TSV_FILE}" ]]; then
    TSV_FILE="/root/install-01/servers.tsv"
fi
if [[ ! -f "${TSV_FILE}" ]]; then
    TSV_FILE="${INSTALL_DIR}/inventory/servers.tsv"
fi
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable"
    exit 1
fi

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

# Header
echo "=============================================================="
echo " [KeyBuzz] Restauration des Services Backend"
echo "=============================================================="
echo ""
echo "Ce script va :"
echo "  1. Diagnostiquer l'état actuel des services"
echo "  2. Redémarrer PostgreSQL HA (Patroni, HAProxy, PgBouncer)"
echo "  3. Redémarrer Redis HA"
echo "  4. Vérifier la connectivité"
echo ""
echo "⚠️  IMPORTANT: Les données existantes seront préservées"
echo ""
read -p "Continuer ? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log_info "Restauration annulée"
    exit 0
fi

echo ""

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# ============================================================
# ÉTAPE 1 : Diagnostic
# ============================================================
log_info "=============================================================="
log_info "Étape 1/4 : Diagnostic de l'état actuel"
log_info "=============================================================="
echo ""

# Vérifier PostgreSQL
log_info "Vérification PostgreSQL..."
PG_NODES=0
PG_RUNNING=0

declare -a PG_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "postgres" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        PG_IPS+=("${IP_PRIVEE}")
        ((PG_NODES++))
        
        if ssh ${SSH_KEY_OPTS} "root@${IP_PRIVEE}" "docker ps | grep -q patroni" 2>/dev/null; then
            ((PG_RUNNING++))
            log_success "PostgreSQL ${HOSTNAME} (${IP_PRIVEE}): Running"
        else
            log_error "PostgreSQL ${HOSTNAME} (${IP_PRIVEE}): Stopped"
        fi
    fi
done
exec 3<&-

echo "  PostgreSQL: ${PG_RUNNING}/${PG_NODES} nœuds actifs"
echo ""

# Vérifier Redis
log_info "Vérification Redis..."
REDIS_NODES=0
REDIS_RUNNING=0

declare -a REDIS_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "redis" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        REDIS_IPS+=("${IP_PRIVEE}")
        ((REDIS_NODES++))
        
        if ssh ${SSH_KEY_OPTS} "root@${IP_PRIVEE}" "docker ps | grep -q redis" 2>/dev/null; then
            ((REDIS_RUNNING++))
            log_success "Redis ${HOSTNAME} (${IP_PRIVEE}): Running"
        else
            log_error "Redis ${HOSTNAME} (${IP_PRIVEE}): Stopped"
        fi
    fi
done
exec 3<&-

echo "  Redis: ${REDIS_RUNNING}/${REDIS_NODES} nœuds actifs"
echo ""

# ============================================================
# ÉTAPE 2 : Redémarrage PostgreSQL
# ============================================================
if [[ ${PG_RUNNING} -lt ${PG_NODES} ]]; then
    log_info "=============================================================="
    log_info "Étape 2/4 : Redémarrage PostgreSQL HA"
    log_info "=============================================================="
    echo ""
    
    log_warning "Redémarrage des containers Patroni..."
    for ip in "${PG_IPS[@]}"; do
        log_info "Redémarrage Patroni sur ${ip}..."
        ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<'EOF'
# Redémarrer le container Patroni s'il existe
if docker ps -a | grep -q patroni; then
    docker restart patroni 2>/dev/null || docker start patroni 2>/dev/null || true
    echo "  Container Patroni redémarré"
else
    echo "  Container Patroni introuvable - nécessite réinstallation complète"
fi
EOF
    done
    
    log_info "Attente du démarrage du cluster (30 secondes)..."
    sleep 30
    
    # Vérifier le statut
    PG_RUNNING_AFTER=0
    for ip in "${PG_IPS[@]}"; do
        if ssh ${SSH_KEY_OPTS} "root@${ip}" "docker ps | grep -q patroni" 2>/dev/null; then
            ((PG_RUNNING_AFTER++))
        fi
    done
    
    if [[ ${PG_RUNNING_AFTER} -eq ${PG_NODES} ]]; then
        log_success "Tous les nœuds PostgreSQL sont démarrés"
    else
        log_warning "Certains nœuds PostgreSQL ne sont pas démarrés (${PG_RUNNING_AFTER}/${PG_NODES})"
        log_warning "Une réinstallation complète peut être nécessaire"
    fi
    echo ""
fi

# Redémarrer HAProxy et PgBouncer
log_info "Redémarrage HAProxy et PgBouncer..."
declare -a HAPROXY_IPS=()
exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    if [[ "${ROLE}" == "lb" ]] && [[ "${SUBROLE}" == "internal-haproxy" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        HAPROXY_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

for ip in "${HAPROXY_IPS[@]}"; do
    log_info "Redémarrage HAProxy/PgBouncer sur ${ip}..."
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<'EOF'
# Redémarrer HAProxy
if docker ps -a | grep -q haproxy; then
    docker restart haproxy 2>/dev/null || docker start haproxy 2>/dev/null || true
    echo "  HAProxy redémarré"
fi

# Redémarrer PgBouncer
if docker ps -a | grep -q pgbouncer; then
    docker restart pgbouncer 2>/dev/null || docker start pgbouncer 2>/dev/null || true
    echo "  PgBouncer redémarré"
fi
EOF
done
echo ""

# ============================================================
# ÉTAPE 3 : Redémarrage Redis
# ============================================================
if [[ ${REDIS_RUNNING} -lt ${REDIS_NODES} ]]; then
    log_info "=============================================================="
    log_info "Étape 3/4 : Redémarrage Redis HA"
    log_info "=============================================================="
    echo ""
    
    log_warning "Redémarrage des containers Redis..."
    for ip in "${REDIS_IPS[@]}"; do
        log_info "Redémarrage Redis sur ${ip}..."
        ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<'EOF'
# Redémarrer les containers Redis
for container in $(docker ps -a --format "{{.Names}}" | grep -E "redis|sentinel"); do
    docker restart "${container}" 2>/dev/null || docker start "${container}" 2>/dev/null || true
    echo "  ${container} redémarré"
done
EOF
    done
    
    log_info "Attente du démarrage du cluster (20 secondes)..."
    sleep 20
    echo ""
fi

# ============================================================
# ÉTAPE 4 : Vérification finale
# ============================================================
log_info "=============================================================="
log_info "Étape 4/4 : Vérification finale"
log_info "=============================================================="
echo ""

# Test PostgreSQL
log_info "Test de connectivité PostgreSQL..."
if [[ ${#HAPROXY_IPS[@]} -gt 0 ]]; then
    HAPROXY_IP="${HAPROXY_IPS[0]}"
    if ssh ${SSH_KEY_OPTS} "root@${HAPROXY_IP}" "nc -z localhost 5432" 2>/dev/null; then
        log_success "PostgreSQL accessible via HAProxy (port 5432)"
    else
        log_error "PostgreSQL non accessible via HAProxy (port 5432)"
    fi
    
    if ssh ${SSH_KEY_OPTS} "root@${HAPROXY_IP}" "nc -z localhost 4632" 2>/dev/null; then
        log_success "PgBouncer accessible (port 4632)"
    else
        log_error "PgBouncer non accessible (port 4632)"
    fi
fi
echo ""

# Test Redis
log_info "Test de connectivité Redis..."
if [[ ${#REDIS_IPS[@]} -gt 0 ]]; then
    REDIS_IP="${REDIS_IPS[0]}"
    if ssh ${SSH_KEY_OPTS} "root@${REDIS_IP}" "docker exec redis-master redis-cli PING 2>/dev/null | grep -q PONG" 2>/dev/null; then
        log_success "Redis accessible"
    else
        log_error "Redis non accessible"
    fi
fi
echo ""

# Résumé
echo "=============================================================="
log_success "✅ Restauration terminée"
echo "=============================================================="
echo ""
log_info "Si les services ne fonctionnent toujours pas, vous pouvez :"
log_info "  1. Relancer ce script avec --force"
log_info "  2. Réinstaller complètement avec les scripts du Module 3 et 4"
log_info "     (les données seront préservées si les volumes sont intacts)"
echo ""

