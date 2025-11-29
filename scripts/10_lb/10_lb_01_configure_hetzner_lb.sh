#!/usr/bin/env bash
#
# 10_lb_01_configure_hetzner_lb.sh - Guide de configuration des Load Balancers Hetzner
#
# Ce script guide la configuration des Load Balancers Hetzner internes
# selon le design définitif de l'infrastructure KeyBuzz.
#
# Usage:
#   ./10_lb_01_configure_hetzner_lb.sh [servers.tsv]
#
# Note: Ce script ne peut pas créer les LB automatiquement via API,
# mais il génère les instructions et vérifie la configuration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
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

# Parser servers.tsv
HAPROXY_IPS=()
PROXYSQL_IPS=()

while IFS=$'\t' read -r env ip_pub hostname ip_priv fqdn user pool role subrole stack core notes; do
    if [[ "${role}" == "lb" ]] && [[ "${subrole}" == "internal-haproxy" ]]; then
        HAPROXY_IPS+=("${ip_priv}")
    fi
    if [[ "${role}" == "db_proxy" ]] && [[ "${subrole}" == "proxysql" ]]; then
        PROXYSQL_IPS+=("${ip_priv}")
    fi
done < <(tail -n +2 "${TSV_FILE}")

echo "=============================================================="
echo " Configuration Load Balancers Hetzner - Design Définitif"
echo "=============================================================="
echo ""

log_info "HAProxy nodes: ${HAPROXY_IPS[*]}"
log_info "ProxySQL nodes: ${PROXYSQL_IPS[*]}"
echo ""

# Instructions pour LB 10.0.0.10
echo "=============================================================="
log_info "LB 10.0.0.10 - Configuration"
echo "=============================================================="
echo ""
log_warning "⚠️  ACTION REQUISE : Créer/configurer le LB Hetzner dans le dashboard"
echo ""
echo "Configuration requise pour LB 10.0.0.10 :"
echo ""
echo "1. Type : Load Balancer privé (sans IP publique)"
echo "2. IP privée : 10.0.0.10"
echo "3. Réseau : Réseau privé KeyBuzz (10.0.0.0/16)"
echo ""
echo "Services à configurer :"
echo ""
echo "  Service PostgreSQL (Write) :"
echo "    - Port LB : 5432"
echo "    - Protocole : TCP"
echo "    - Health check : TCP sur port 5432"
echo "    - Targets :"
for ip in "${HAPROXY_IPS[@]}"; do
    echo "      - ${ip}:5432"
done
echo ""
echo "  Service PostgreSQL (Read) :"
echo "    - Port LB : 5433"
echo "    - Protocole : TCP"
echo "    - Health check : TCP sur port 5433"
echo "    - Targets :"
for ip in "${HAPROXY_IPS[@]}"; do
    echo "      - ${ip}:5433"
done
echo ""
echo "  Service PgBouncer (si utilisé) :"
echo "    - Port LB : 6432"
echo "    - Protocole : TCP"
echo "    - Health check : TCP sur port 6432"
echo "    - Targets :"
for ip in "${HAPROXY_IPS[@]}"; do
    echo "      - ${ip}:6432"
done
echo ""
echo "  Service Redis :"
echo "    - Port LB : 6379"
echo "    - Protocole : TCP"
echo "    - Health check : TCP sur port 6379"
echo "    - Targets :"
for ip in "${HAPROXY_IPS[@]}"; do
    echo "      - ${ip}:6379"
done
echo ""
echo "  Service RabbitMQ :"
echo "    - Port LB : 5672"
echo "    - Protocole : TCP"
echo "    - Health check : TCP sur port 5672"
echo "    - Targets :"
for ip in "${HAPROXY_IPS[@]}"; do
    echo "      - ${ip}:5672"
done
echo ""

# Instructions pour LB 10.0.0.20
echo "=============================================================="
log_info "LB 10.0.0.20 - Configuration"
echo "=============================================================="
echo ""
log_warning "⚠️  ACTION REQUISE : Créer/configurer le LB Hetzner dans le dashboard"
echo ""
echo "Configuration requise pour LB 10.0.0.20 :"
echo ""
echo "1. Type : Load Balancer privé (sans IP publique)"
echo "2. IP privée : 10.0.0.20"
echo "3. Réseau : Réseau privé KeyBuzz (10.0.0.0/16)"
echo ""
echo "Services à configurer :"
echo ""
echo "  Service MariaDB (via ProxySQL) :"
echo "    - Port LB : 3306"
echo "    - Protocole : TCP"
echo "    - Health check : TCP sur port 3306"
echo "    - Targets :"
for ip in "${PROXYSQL_IPS[@]}"; do
    echo "      - ${ip}:3306"
done
echo ""

# Vérification de la connectivité
echo "=============================================================="
log_info "Vérification de la connectivité"
echo "=============================================================="
echo ""

log_info "Test de connectivité vers LB 10.0.0.10..."
if timeout 2 nc -z 10.0.0.10 5432 2>/dev/null; then
    log_success "LB 10.0.0.10:5432 accessible"
else
    log_warning "LB 10.0.0.10:5432 non accessible (peut être normal si LB pas encore créé)"
fi

if timeout 2 nc -z 10.0.0.10 6379 2>/dev/null; then
    log_success "LB 10.0.0.10:6379 accessible"
else
    log_warning "LB 10.0.0.10:6379 non accessible (peut être normal si LB pas encore créé)"
fi

log_info "Test de connectivité vers LB 10.0.0.20..."
if timeout 2 nc -z 10.0.0.20 3306 2>/dev/null; then
    log_success "LB 10.0.0.20:3306 accessible"
else
    log_warning "LB 10.0.0.20:3306 non accessible (peut être normal si LB pas encore créé)"
fi

echo ""
log_warning "NOTE : Les Load Balancers Hetzner doivent être créés manuellement"
log_warning "       dans le dashboard Hetzner Cloud avant de continuer."
echo ""

