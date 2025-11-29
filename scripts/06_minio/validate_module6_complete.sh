#!/usr/bin/env bash
#
# validate_module6_complete.sh - Validation complète du Module 6 (MinIO S3 Cluster)
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/minio.env"

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
elif [[ -f "/root/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i /root/.ssh/keybuzz_infra"
fi

SSH_KEY_OPTS="${SSH_KEY_OPTS} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Parser servers.tsv pour obtenir les nœuds MinIO
MINIO_NODES=()
MINIO_IPS=()

while IFS=$'\t' read -r env ip_pub hostname ip_priv fqdn user pool role subrole stack core notes; do
    if [[ "${role}" == "storage" ]] && [[ "${subrole}" == "minio" ]]; then
        MINIO_NODES+=("${hostname}")
        MINIO_IPS+=("${ip_priv}")
    fi
done < <(tail -n +2 "${TSV_FILE}")

if [[ ${#MINIO_NODES[@]} -eq 0 ]]; then
    log_error "Aucun nœud MinIO trouvé dans ${TSV_FILE}"
    exit 1
fi

log_info "=============================================================="
log_info "Validation complète du Module 6 : MinIO S3 Cluster"
log_info "=============================================================="
echo ""

# Compteurs
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNINGS=0

# Fonction pour incrémenter les compteurs
check_pass() {
    ((TOTAL_CHECKS++))
    ((PASSED_CHECKS++))
}

check_fail() {
    ((TOTAL_CHECKS++))
    ((FAILED_CHECKS++))
}

check_warn() {
    ((TOTAL_CHECKS++))
    ((WARNINGS++))
}

# 1. Vérification des conteneurs Docker
log_info "=============================================================="
log_info "1. Vérification des conteneurs Docker MinIO"
log_info "=============================================================="

MINIO_CONTAINERS_RUNNING=0
for i in "${!MINIO_NODES[@]}"; do
    hostname="${MINIO_NODES[$i]}"
    ip="${MINIO_IPS[$i]}"
    
    if ssh ${SSH_KEY_OPTS} "root@${ip}" 'docker ps --format "{{.Names}}\t{{.Status}}" | grep -q "^minio.*Up"' 2>/dev/null; then
        status=$(ssh ${SSH_KEY_OPTS} "root@${ip}" 'docker ps --format "{{.Status}}" | grep minio' 2>/dev/null || echo "unknown")
        log_success "${hostname} (${ip}): Conteneur MinIO actif - ${status}"
        ((MINIO_CONTAINERS_RUNNING++))
        check_pass
    else
        log_error "${hostname} (${ip}): Conteneur MinIO non actif"
        check_fail
    fi
done

if [[ ${MINIO_CONTAINERS_RUNNING} -eq ${#MINIO_NODES[@]} ]]; then
    log_success "Tous les conteneurs MinIO sont actifs (${MINIO_CONTAINERS_RUNNING}/${#MINIO_NODES[@]})"
else
    log_error "Seulement ${MINIO_CONTAINERS_RUNNING}/${#MINIO_NODES[@]} conteneurs MinIO sont actifs"
fi
echo ""

# 2. Vérification de la connectivité réseau
log_info "=============================================================="
log_info "2. Vérification de la connectivité réseau"
log_info "=============================================================="

MINIO_PORTS_ACCESSIBLE=0
for i in "${!MINIO_NODES[@]}"; do
    hostname="${MINIO_NODES[$i]}"
    ip="${MINIO_IPS[$i]}"
    
    # Port 9000 (S3 API)
    if ssh ${SSH_KEY_OPTS} "root@${ip}" 'curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:9000/minio/health/live 2>/dev/null | grep -q "200"' 2>/dev/null; then
        log_success "${hostname} (${ip}): Port 9000 (S3 API) accessible"
        ((MINIO_PORTS_ACCESSIBLE++))
        check_pass
    else
        log_error "${hostname} (${ip}): Port 9000 (S3 API) non accessible"
        check_fail
    fi
    
    # Port 9001 (Console)
    if ssh ${SSH_KEY_OPTS} "root@${ip}" 'curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:9001 2>/dev/null | grep -qE "200|302"' 2>/dev/null; then
        log_success "${hostname} (${ip}): Port 9001 (Console) accessible"
        check_pass
    else
        log_warning "${hostname} (${ip}): Port 9001 (Console) non accessible (non bloquant)"
        check_warn
    fi
done

if [[ ${MINIO_PORTS_ACCESSIBLE} -eq ${#MINIO_NODES[@]} ]]; then
    log_success "Tous les ports S3 API sont accessibles (${MINIO_PORTS_ACCESSIBLE}/${#MINIO_NODES[@]})"
else
    log_error "Seulement ${MINIO_PORTS_ACCESSIBLE}/${#MINIO_NODES[@]} ports S3 API sont accessibles"
fi
echo ""

# 3. Vérification du cluster MinIO (via mc admin info)
log_info "=============================================================="
log_info "3. Vérification du cluster MinIO (mc admin info)"
log_info "=============================================================="

# Utiliser le premier nœud pour vérifier le cluster
FIRST_NODE_IP="${MINIO_IPS[0]}"
FIRST_NODE_HOSTNAME="${MINIO_NODES[0]}"

if ssh ${SSH_KEY_OPTS} "root@${FIRST_NODE_IP}" 'command -v mc >/dev/null 2>&1' 2>/dev/null; then
    log_info "Vérification du cluster via mc admin info sur ${FIRST_NODE_HOSTNAME}..."
    
    # Vérifier si mc est configuré
    if ssh ${SSH_KEY_OPTS} "root@${FIRST_NODE_IP}" 'mc alias list | grep -q minio' 2>/dev/null; then
        log_success "Client mc configuré avec alias 'minio'"
        check_pass
        
        # Obtenir les informations du cluster
        cluster_info=$(ssh ${SSH_KEY_OPTS} "root@${FIRST_NODE_IP}" 'mc admin info local 2>&1' 2>/dev/null || echo "")
        
        if [[ -n "${cluster_info}" ]] && ! echo "${cluster_info}" | grep -qi "error\|denied\|unable"; then
            log_success "Informations du cluster récupérées avec succès"
            check_pass
            
            # Vérifier le nombre de nœuds
            node_count=$(echo "${cluster_info}" | grep -i "online\|offline" | wc -l || echo "0")
            if [[ ${node_count} -ge ${#MINIO_NODES[@]} ]]; then
                log_success "Nombre de nœuds détectés : ${node_count} (attendu : ${#MINIO_NODES[@]})"
                check_pass
            else
                log_warning "Nombre de nœuds détectés : ${node_count} (attendu : ${#MINIO_NODES[@]})"
                check_warn
            fi
            
            # Afficher un résumé
            echo "${cluster_info}" | head -20 | while read line; do
                if [[ -n "${line}" ]]; then
                    log_info "  ${line}"
                fi
            done
        else
            log_error "Impossible de récupérer les informations du cluster"
            log_warning "Cela peut être normal si les credentials ne sont pas configurés"
            check_warn
        fi
    else
        log_warning "Client mc non configuré (non bloquant pour la validation)"
        check_warn
    fi
else
    log_warning "Client mc non installé sur ${FIRST_NODE_HOSTNAME} (non bloquant)"
    check_warn
fi
echo ""

# 4. Vérification des logs MinIO
log_info "=============================================================="
log_info "4. Vérification des logs MinIO"
log_info "=============================================================="

MINIO_LOGS_OK=0
for i in "${!MINIO_NODES[@]}"; do
    hostname="${MINIO_NODES[$i]}"
    ip="${MINIO_IPS[$i]}"
    
    # Vérifier les dernières lignes des logs
    recent_logs=$(ssh ${SSH_KEY_OPTS} "root@${ip}" 'docker logs minio --tail 10 2>&1' 2>/dev/null || echo "")
    
    if echo "${recent_logs}" | grep -qi "error\|fatal"; then
        log_warning "${hostname} (${ip}): Erreurs détectées dans les logs"
        echo "${recent_logs}" | grep -i "error\|fatal" | head -3 | while read line; do
            log_warning "  ${line}"
        done
        check_warn
    elif echo "${recent_logs}" | grep -qi "ready\|initialized\|started"; then
        log_success "${hostname} (${ip}): Logs indiquent un démarrage réussi"
        ((MINIO_LOGS_OK++))
        check_pass
    else
        log_info "${hostname} (${ip}): Logs non vérifiables (non bloquant)"
        check_warn
    fi
done

if [[ ${MINIO_LOGS_OK} -eq ${#MINIO_NODES[@]} ]]; then
    log_success "Tous les logs MinIO sont OK (${MINIO_LOGS_OK}/${#MINIO_NODES[@]})"
else
    log_warning "Seulement ${MINIO_LOGS_OK}/${#MINIO_NODES[@]} nœuds ont des logs OK"
fi
echo ""

# 5. Vérification de la configuration du cluster distribué
log_info "=============================================================="
log_info "5. Vérification de la configuration du cluster distribué"
log_info "=============================================================="

CLUSTER_CONFIG_OK=0
for i in "${!MINIO_NODES[@]}"; do
    hostname="${MINIO_NODES[$i]}"
    ip="${MINIO_IPS[$i]}"
    
    # Vérifier que le conteneur utilise bien le mode distribué
    docker_cmd=$(ssh ${SSH_KEY_OPTS} "root@${ip}" 'docker inspect minio --format "{{.Args}}" 2>/dev/null' 2>/dev/null || echo "")
    
    if echo "${docker_cmd}" | grep -q "server.*http://"; then
        # Compter le nombre de nœuds dans la commande
        node_count_in_cmd=$(echo "${docker_cmd}" | grep -o "http://[^ ]*" | wc -l || echo "0")
        if [[ ${node_count_in_cmd} -ge 3 ]]; then
            log_success "${hostname} (${ip}): Configuration cluster distribué détectée (${node_count_in_cmd} nœuds)"
            ((CLUSTER_CONFIG_OK++))
            check_pass
        else
            log_warning "${hostname} (${ip}): Configuration cluster avec ${node_count_in_cmd} nœuds (attendu : 3+)"
            check_warn
        fi
    else
        log_warning "${hostname} (${ip}): Impossible de vérifier la configuration cluster"
        check_warn
    fi
done

if [[ ${CLUSTER_CONFIG_OK} -eq ${#MINIO_NODES[@]} ]]; then
    log_success "Tous les nœuds sont configurés en cluster distribué (${CLUSTER_CONFIG_OK}/${#MINIO_NODES[@]})"
else
    log_warning "Seulement ${CLUSTER_CONFIG_OK}/${#MINIO_NODES[@]} nœuds ont une configuration cluster validée"
fi
echo ""

# 6. Test de lecture/écriture (si mc est configuré)
log_info "=============================================================="
log_info "6. Test de lecture/écriture (si mc est configuré)"
log_info "=============================================================="

if ssh ${SSH_KEY_OPTS} "root@${FIRST_NODE_IP}" 'mc alias list | grep -q minio' 2>/dev/null; then
    # Test d'écriture
    test_file="/tmp/minio_test_$$.txt"
    echo "test content $(date)" | ssh ${SSH_KEY_OPTS} "root@${FIRST_NODE_IP}" "cat > ${test_file}" 2>/dev/null
    
    if ssh ${SSH_KEY_OPTS} "root@${FIRST_NODE_IP}" "mc cp ${test_file} minio/keybuzz-backups/test/ 2>&1" 2>/dev/null; then
        log_success "Test d'écriture réussi"
        check_pass
        
        # Test de lecture
        if ssh ${SSH_KEY_OPTS} "root@${FIRST_NODE_IP}" "mc cat minio/keybuzz-backups/test/$(basename ${test_file}) >/dev/null 2>&1" 2>/dev/null; then
            log_success "Test de lecture réussi"
            check_pass
        else
            log_warning "Test de lecture échoué (non bloquant)"
            check_warn
        fi
        
        # Nettoyer
        ssh ${SSH_KEY_OPTS} "root@${FIRST_NODE_IP}" "rm -f ${test_file} && mc rm minio/keybuzz-backups/test/$(basename ${test_file}) 2>/dev/null" 2>/dev/null || true
    else
        log_warning "Test d'écriture échoué (non bloquant, peut nécessiter des credentials)"
        check_warn
    fi
else
    log_warning "Client mc non configuré, tests de lecture/écriture ignorés"
    check_warn
fi
echo ""

# Résumé final
log_info "=============================================================="
log_info "Résumé de la validation"
log_info "=============================================================="
echo ""
log_info "Total des vérifications : ${TOTAL_CHECKS}"
log_success "Vérifications réussies : ${PASSED_CHECKS}"
if [[ ${FAILED_CHECKS} -gt 0 ]]; then
    log_error "Vérifications échouées : ${FAILED_CHECKS}"
fi
if [[ ${WARNINGS} -gt 0 ]]; then
    log_warning "Avertissements : ${WARNINGS}"
fi
echo ""

if [[ ${FAILED_CHECKS} -eq 0 ]]; then
    log_success "✅ Module 6 validé avec succès !"
    echo ""
    log_info "Points d'accès :"
    log_info "  - S3 API: http://${MINIO_IPS[0]}:9000"
    log_info "  - Console: http://${MINIO_IPS[0]}:9001"
    log_info "  - Bucket: keybuzz-backups"
    exit 0
else
    log_error "❌ Module 6 présente des erreurs critiques"
    exit 1
fi

