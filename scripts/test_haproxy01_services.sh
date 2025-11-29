#!/usr/bin/env bash
#
# test_haproxy01_services.sh - Tests spécifiques des services haproxy-01
#
# Ce script vérifie tous les services, ports et connectivités sur haproxy-01
# après la réinstallation.
#
# Usage:
#   ./test_haproxy01_services.sh [haproxy-01-ip]
#

set -uo pipefail

HAPROXY_01_IP="${1:-10.0.0.11}"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

log_section() {
    echo ""
    echo -e "${CYAN}=============================================================="
    echo -e "${CYAN} $1"
    echo -e "${CYAN}=============================================================="
    echo ""
}

# Compteurs
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

test_port() {
    local service_name="$1"
    local port="$2"
    local description="${3:-}"
    
    ((TOTAL_TESTS++))
    echo -n "  Test port ${port} (${service_name})"
    [[ -n "${description}" ]] && echo " - ${description}" || echo ""
    
    if ssh ${SSH_OPTS} root@${HAPROXY_01_IP} "nc -z localhost ${port} 2>&1" >/dev/null 2>&1; then
        log_success "  Port ${port} accessible"
        ((PASSED_TESTS++))
        return 0
    else
        log_error "  Port ${port} NON accessible"
        ((FAILED_TESTS++))
        return 1
    fi
}

test_http_check() {
    local service_name="$1"
    local url="$2"
    
    ((TOTAL_TESTS++))
    echo -n "  Test HTTP: ${service_name} (${url}) ... "
    
    HTTP_CODE=$(ssh ${SSH_OPTS} root@${HAPROXY_01_IP} "curl -s -o /dev/null -w '%{http_code}' --max-time 3 ${url} 2>&1" || echo "000")
    
    if [[ "${HTTP_CODE}" =~ ^(200|301|302)$ ]]; then
        log_success "OK (HTTP ${HTTP_CODE})"
        ((PASSED_TESTS++))
        return 0
    else
        log_error "ÉCHEC (HTTP ${HTTP_CODE})"
        ((FAILED_TESTS++))
        return 1
    fi
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Tests Services haproxy-01"
echo " IP: ${HAPROXY_01_IP}"
echo " Date: $(date)"
echo "=============================================================="
echo ""

# ============================================================
# 1. Vérification Containers Docker
# ============================================================
log_section "1. Containers Docker"

log_info "Liste des containers actifs:"
CONTAINERS=$(ssh ${SSH_OPTS} root@${HAPROXY_01_IP} "docker ps --format '{{.Names}}|{{.Status}}|{{.Image}}'" 2>&1)
if [[ -n "${CONTAINERS}" ]]; then
    echo "${CONTAINERS}" | while IFS='|' read -r name status image; do
        log_success "  ${name}: ${status} (${image})"
    done
else
    log_error "  Aucun container trouvé"
fi

# Vérifier chaque container attendu
log_info "Vérification des containers attendus:"
for container in haproxy pgbouncer haproxy-redis redis-sentinel-watcher; do
    if echo "${CONTAINERS}" | grep -q "^${container}"; then
        log_success "  Container ${container} présent"
        ((PASSED_TESTS++))
    else
        log_error "  Container ${container} absent"
        ((FAILED_TESTS++))
    fi
    ((TOTAL_TESTS++))
done

# ============================================================
# 2. Vérification Services Systemd
# ============================================================
log_section "2. Services Systemd"

log_info "Services systemd actifs:"
SERVICES=$(ssh ${SSH_OPTS} root@${HAPROXY_01_IP} "systemctl list-units --type=service --state=running 2>/dev/null | grep -E 'haproxy|pgbouncer' || true" 2>&1)
if [[ -n "${SERVICES}" ]]; then
    echo "${SERVICES}" | while read -r service; do
        log_success "  ${service}"
    done
else
    log_warning "  Aucun service systemd haproxy/pgbouncer trouvé (normal si containers Docker)"
fi

# ============================================================
# 3. Tests des Ports
# ============================================================
log_section "3. Tests des Ports"

log_info "Vérification des ports ouverts:"

# HAProxy PostgreSQL
test_port "HAProxy PostgreSQL (write)" "5432" "Backend PostgreSQL primary"
test_port "HAProxy PostgreSQL (read)" "5433" "Backend PostgreSQL replicas (si configuré)"

# PgBouncer
test_port "PgBouncer" "6432" "Pooling de connexions PostgreSQL"

# HAProxy Stats
test_port "HAProxy Stats" "8404" "Page de statistiques HAProxy"

# HAProxy Redis
test_port "HAProxy Redis" "6379" "Backend Redis"

# HAProxy RabbitMQ (si installé)
test_port "HAProxy RabbitMQ" "5672" "Backend RabbitMQ"

# Ports additionnels
test_port "HAProxy Redis Health" "26379" "Port Sentinel (si configuré)"

# ============================================================
# 4. Tests de Connectivité Backend
# ============================================================
log_section "4. Tests de Connectivité Backend"

log_info "Test HAProxy PostgreSQL (port 5432):"
if ssh ${SSH_OPTS} root@${HAPROXY_01_IP} "timeout 3 bash -c '</dev/tcp/localhost/5432' 2>&1" >/dev/null 2>&1; then
    log_success "  Port 5432: Connexion TCP réussie"
    ((PASSED_TESTS++))
else
    log_error "  Port 5432: Connexion TCP échouée"
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

log_info "Test PgBouncer (port 6432):"
if ssh ${SSH_OPTS} root@${HAPROXY_01_IP} "timeout 3 bash -c '</dev/tcp/localhost/6432' 2>&1" >/dev/null 2>&1; then
    log_success "  Port 6432: Connexion TCP réussie"
    ((PASSED_TESTS++))
else
    log_error "  Port 6432: Connexion TCP échouée"
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

log_info "Test HAProxy Redis (port 6379):"
if ssh ${SSH_OPTS} root@${HAPROXY_01_IP} "timeout 3 bash -c '</dev/tcp/localhost/6379' 2>&1" >/dev/null 2>&1; then
    log_success "  Port 6379: Connexion TCP réussie"
    ((PASSED_TESTS++))
else
    log_error "  Port 6379: Connexion TCP échouée"
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

# ============================================================
# 5. Tests HAProxy Stats (HTTP)
# ============================================================
log_section "5. Tests HAProxy Stats Page"

test_http_check "HAProxy Stats" "http://localhost:8404/stats"

# ============================================================
# 6. Configuration HAProxy
# ============================================================
log_section "6. Configuration HAProxy"

log_info "Vérification du fichier de configuration HAProxy:"
if ssh ${SSH_OPTS} root@${HAPROXY_01_IP} "test -f /etc/haproxy/haproxy.cfg" 2>/dev/null; then
    log_success "  /etc/haproxy/haproxy.cfg existe"
    log_info "  Contenu du fichier (aperçu):"
    ssh ${SSH_OPTS} root@${HAPROXY_01_IP} "head -30 /etc/haproxy/haproxy.cfg 2>/dev/null" | sed 's/^/    /'
    ((PASSED_TESTS++))
else
    log_error "  /etc/haproxy/haproxy.cfg introuvable"
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

# Vérifier la syntaxe HAProxy
log_info "Vérification de la syntaxe HAProxy:"
if ssh ${SSH_OPTS} root@${HAPROXY_01_IP} "docker exec haproxy haproxy -c -f /usr/local/etc/haproxy/haproxy.cfg 2>&1" | grep -q "valid\|Configuration file is valid"; then
    log_success "  Syntaxe HAProxy valide"
    ((PASSED_TESTS++))
else
    log_warning "  Vérification syntaxe HAProxy échouée (peut être normal si container non accessible)"
    ((FAILED_TESTS++))
fi
((TOTAL_TESTS++))

# ============================================================
# 7. Logs des Containers
# ============================================================
log_section "7. Logs des Containers (dernières lignes)"

for container in haproxy pgbouncer haproxy-redis; do
    if echo "${CONTAINERS}" | grep -q "^${container}"; then
        log_info "Logs ${container} (5 dernières lignes):"
        ssh ${SSH_OPTS} root@${HAPROXY_01_IP} "docker logs --tail 5 ${container} 2>&1" | sed 's/^/    /' || log_warning "  Impossible de lire les logs"
    fi
done

# ============================================================
# Résumé
# ============================================================
log_section "RÉSUMÉ DES TESTS"

echo "Total tests: ${TOTAL_TESTS}"
echo "✓ Réussis: ${PASSED_TESTS}"
echo "✗ Échoués: ${FAILED_TESTS}"

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    log_success "Tous les tests ont réussi !"
    exit 0
else
    log_warning "Certains tests ont échoué. Vérification manuelle recommandée."
    exit 1
fi

