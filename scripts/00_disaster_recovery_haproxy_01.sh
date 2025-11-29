#!/usr/bin/env bash
#
# 00_disaster_recovery_haproxy_01.sh - Disaster Recovery Automatique pour haproxy-01
#
# Ce script detecte si haproxy-01 est dans un etat "vide" (apres rebuild)
# et reinstallera automatiquement tous les services necessaires :
# - Module 1 & 2 : Base OS + Securite
# - Module 3 : HAProxy (PostgreSQL + PgBouncer)
# - Module 3 : PgBouncer
# - Module 4 : HAProxy Redis
#
# Usage:
#   ./00_disaster_recovery_haproxy_01.sh [servers.tsv] [--force]
#
# Options:
#   --force : Force la reinstallation meme si des services sont detectes
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
FORCE="${2:-}"

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

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
    echo -e "${GREEN}[OK]${NC} $1"
}

log_error() {
    echo -e "${RED}[FAIL]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

get_ip() {
    local hostname="$1"
    awk -F'\t' -v h="${hostname}" 'NR>1 && $3==h {print $4}' "${TSV_FILE}" | head -1
}

HAPROXY_01_IP=$(get_ip "haproxy-01")

if [[ -z "${HAPROXY_01_IP}" ]]; then
    log_error "IP de haproxy-01 non trouvee dans servers.tsv"
    exit 1
fi

echo "=============================================================="
echo " [KeyBuzz] Disaster Recovery - haproxy-01"
echo " IP: ${HAPROXY_01_IP}"
echo "=============================================================="
echo ""

# Phase 1: Verification acces SSH
log_info "Phase 1: Verification acces SSH..."
if ! ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "echo OK" 2>/dev/null | grep -q "OK"; then
    log_error "SSH inaccessible sur haproxy-01 (${HAPROXY_01_IP})"
    log_error "Verifiez que le serveur est rebuild et que la cle SSH est configuree"
    exit 1
fi
log_success "SSH accessible"
echo ""

# Phase 2: Detection de l'etat du serveur
log_info "Phase 2: Detection de l'etat du serveur..."

# Verifier si Docker est installe
DOCKER_INSTALLED=$(ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "command -v docker >/dev/null 2>&1 && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")

# Verifier si les conteneurs existent
HAPROXY_CONTAINER=$(ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "docker ps -a | grep -q haproxy && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
PGBOUNCER_CONTAINER=$(ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "docker ps -a | grep -q pgbouncer && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")

# Verifier si les repertoires existent
KEYBUZZ_DIR=$(ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "test -d /opt/keybuzz && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")

# Determiner si le serveur est "vide"
IS_EMPTY="no"
if [[ "${DOCKER_INSTALLED}" == "no" ]] || [[ "${HAPROXY_CONTAINER}" == "no" ]] || [[ "${KEYBUZZ_DIR}" == "no" ]]; then
    IS_EMPTY="yes"
fi

log_info "  Docker installe: ${DOCKER_INSTALLED}"
log_info "  Conteneur HAProxy: ${HAPROXY_CONTAINER}"
log_info "  Conteneur PgBouncer: ${PGBOUNCER_CONTAINER}"
log_info "  Repertoire /opt/keybuzz: ${KEYBUZZ_DIR}"
log_info "  Serveur vide: ${IS_EMPTY}"
echo ""

# Phase 3: Decision de reinstallation
if [[ "${IS_EMPTY}" == "yes" ]] || [[ "${FORCE}" == "--force" ]]; then
    if [[ "${FORCE}" == "--force" ]]; then
        log_warning "Mode FORCE active - Reinstallation forcee"
    else
        log_warning "Serveur detecte comme vide - Reinstallation necessaire"
    fi
    echo ""
    
    # Confirmation (sauf si --force)
    if [[ "${FORCE}" != "--force" ]]; then
        read -p "Continuer avec la reinstallation automatique ? (o/N) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Oo]$ ]]; then
            log_info "Operation annulee"
            exit 0
        fi
    fi
    
    # Phase 4: Reinstallation Base OS
    log_info "Phase 4: Reinstallation Base OS..."
    log_info "  Execution via SSH direct sur haproxy-01..."
    
    # Copier et executer base_os.sh directement sur haproxy-01
    if [[ -f "${SCRIPT_DIR}/02_base_os_and_security/base_os.sh" ]]; then
        # Copier le script
        scp ${SSH_OPTS} "${SCRIPT_DIR}/02_base_os_and_security/base_os.sh" root@"${HAPROXY_01_IP}":/tmp/base_os.sh 2>/dev/null || true
        
        # Executer sur haproxy-01 (role=lb, subrole=internal-haproxy)
        if ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "chmod +x /tmp/base_os.sh && bash /tmp/base_os.sh lb internal-haproxy" 2>&1 | tee /tmp/haproxy01_baseos.log; then
            log_success "Base OS installe"
        else
            log_error "Echec installation Base OS"
            exit 1
        fi
    else
        log_warning "Script Base OS non trouve - Ignore"
    fi
    echo ""
    
    # Phase 5: Reinstallation HAProxy (PostgreSQL)
    log_info "Phase 5: Reinstallation HAProxy (PostgreSQL)..."
    if [[ -f "${SCRIPT_DIR}/03_postgresql_ha/03_pg_03_install_haproxy_db_lb.sh" ]]; then
        log_info "  Execution: 03_postgresql_ha/03_pg_03_install_haproxy_db_lb.sh"
        # Ce script installe HAProxy pour PostgreSQL sur tous les haproxy-*
        # Il faut filtrer pour haproxy-01 uniquement, mais le script devrait gerer cela
        if bash "${SCRIPT_DIR}/03_postgresql_ha/03_pg_03_install_haproxy_db_lb.sh" "${TSV_FILE}" 2>&1 | tee /tmp/haproxy01_haproxy.log; then
            log_success "HAProxy PostgreSQL installe"
        else
            log_error "Echec installation HAProxy PostgreSQL"
            exit 1
        fi
    else
        log_warning "Script HAProxy PostgreSQL non trouve - Ignore"
    fi
    echo ""
    
    # Phase 6: Reinstallation HAProxy Redis
    log_info "Phase 6: Reinstallation HAProxy Redis..."
    if [[ -f "${SCRIPT_DIR}/04_redis_ha/04_redis_04_configure_haproxy_redis.sh" ]]; then
        log_info "  Execution: 04_redis_ha/04_redis_04_configure_haproxy_redis.sh"
        if bash "${SCRIPT_DIR}/04_redis_ha/04_redis_04_configure_haproxy_redis.sh" "${TSV_FILE}" 2>&1 | tee /tmp/haproxy01_redis.log; then
            log_success "HAProxy Redis installe"
        else
            log_error "Echec installation HAProxy Redis"
            exit 1
        fi
    else
        log_warning "Script HAProxy Redis non trouve - Ignore"
    fi
    echo ""
    
    # Phase 8: Verification finale
    log_info "Phase 8: Verification finale..."
    sleep 5
    
    # Verifier les conteneurs
    HAPROXY_RUNNING=$(ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "docker ps | grep -q haproxy && echo 'yes' || echo 'no'" 2>/dev/null || echo "no")
    
    if [[ "${HAPROXY_RUNNING}" == "yes" ]]; then
        log_success "HAProxy container actif"
    else
        log_error "HAProxy container non actif"
    fi
    
    # Verifier les ports
    if timeout 3 bash -c "echo > /dev/tcp/${HAPROXY_01_IP}/5432" 2>/dev/null; then
        log_success "Port 5432 (PostgreSQL) accessible"
    else
        log_warning "Port 5432 (PostgreSQL) non accessible"
    fi
    
    if timeout 3 bash -c "echo > /dev/tcp/${HAPROXY_01_IP}/6432" 2>/dev/null; then
        log_success "Port 6432 (PgBouncer) accessible"
    else
        log_warning "Port 6432 (PgBouncer) non accessible"
    fi
    
    if timeout 3 bash -c "echo > /dev/tcp/${HAPROXY_01_IP}/6379" 2>/dev/null; then
        log_success "Port 6379 (Redis) accessible"
    else
        log_warning "Port 6379 (Redis) non accessible"
    fi
    
    echo ""
    log_success "Disaster Recovery termine pour haproxy-01"
    log_info "Relancer 00_verification_complete_apres_redemarrage.sh pour verification complete"
    
else
    log_success "Serveur haproxy-01 semble deja configure"
    log_info "Utilisez --force pour forcer la reinstallation"
    
    # Afficher l'etat actuel
    log_info "Etat actuel des services:"
    ssh ${SSH_OPTS} root@"${HAPROXY_01_IP}" "docker ps --format 'table {{.Names}}\t{{.Status}}' 2>/dev/null | head -10" 2>/dev/null || log_warning "Impossible de recuperer l'etat"
fi

echo ""
echo "=============================================================="

