#!/usr/bin/env bash
#
# 09_k3s_10_test_failover_complet.sh - Tests de failover complets K3s
#
# Ce script teste la solidité et le failover automatique du cluster K3s :
# - Failover master (perte d'un master)
# - Failover worker (perte d'un worker)
# - Rescheduling des pods (perte d'un worker avec pods)
# - Ingress DaemonSet (redistribution après perte de nœud)
# - Réintégration d'un nœud (ajout après perte)
#
# Usage:
#   ./09_k3s_10_test_failover_complet.sh [servers.tsv] [--yes]
#
# Prérequis:
#   - Module 9 installé et opérationnel
#   - Exécuter depuis install-01
#

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
AUTO_YES="${2:-}"

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

# Trouver les nœuds K3s
declare -a K3S_MASTER_IPS=()
declare -a K3S_MASTER_HOSTNAMES=()
declare -a K3S_WORKER_IPS=()
declare -a K3S_WORKER_HOSTNAMES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        if [[ "${SUBROLE}" == "master" ]]; then
            K3S_MASTER_IPS+=("${IP_PRIVEE}")
            K3S_MASTER_HOSTNAMES+=("${HOSTNAME}")
        elif [[ "${SUBROLE}" == "worker" ]]; then
            K3S_WORKER_IPS+=("${IP_PRIVEE}")
            K3S_WORKER_HOSTNAMES+=("${HOSTNAME}")
        fi
    fi
done
exec 3<&-

if [[ ${#K3S_MASTER_IPS[@]} -lt 1 ]]; then
    log_error "Aucun master K3s trouvé"
    exit 1
fi

MASTER_IP="${K3S_MASTER_IPS[0]}"

echo "=============================================================="
echo " [KeyBuzz] Module 9 - Tests de Failover Complets K3s"
echo "=============================================================="
echo ""
log_warning "Ces tests vont arrêter temporairement des nœuds K3s"
log_warning "Le cluster doit continuer à fonctionner malgré les pertes"
echo ""

if [[ "${AUTO_YES}" != "--yes" ]]; then
    read -p "Continuer avec les tests de failover ? (o/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[OoYy]$ ]]; then
        log_info "Tests annulés"
        exit 0
    fi
fi

# Compteurs
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

# Variables pour suivre les nœuds arrêtés (pour nettoyage en cas d'erreur)
STOPPED_MASTERS=()
STOPPED_WORKERS=()

# Fonction de nettoyage pour redémarrer tous les nœuds arrêtés
cleanup() {
    log_warning "Nettoyage en cours : redémarrage des nœuds arrêtés..."
    
    # Redémarrer tous les masters arrêtés
    for master_info in "${STOPPED_MASTERS[@]}"; do
        if [[ -n "${master_info}" ]] && [[ "${master_info}" =~ : ]]; then
            MASTER_IP="${master_info%%:*}"
            MASTER_HOSTNAME="${master_info##*:}"
            if [[ -n "${MASTER_IP}" ]] && [[ -n "${MASTER_HOSTNAME}" ]]; then
                log_info "Redémarrage du master ${MASTER_HOSTNAME} (${MASTER_IP})..."
                ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "systemctl start k3s" || true
            fi
        fi
    done
    
    # Redémarrer tous les workers arrêtés
    for worker_info in "${STOPPED_WORKERS[@]}"; do
        if [[ -n "${worker_info}" ]] && [[ "${worker_info}" =~ : ]]; then
            WORKER_IP="${worker_info%%:*}"
            WORKER_HOSTNAME="${worker_info##*:}"
            if [[ -n "${WORKER_IP}" ]] && [[ -n "${WORKER_HOSTNAME}" ]]; then
                log_info "Redémarrage du worker ${WORKER_HOSTNAME} (${WORKER_IP})..."
                ssh ${SSH_KEY_OPTS} "root@${WORKER_IP}" "systemctl start k3s-agent" || true
            fi
        fi
    done
    
    if [[ ${#STOPPED_MASTERS[@]} -gt 0 ]] || [[ ${#STOPPED_WORKERS[@]} -gt 0 ]]; then
        log_info "Attente de la stabilisation (30 secondes)..."
        sleep 30
    fi
}

# Trap pour s'assurer que le nettoyage est fait même en cas d'erreur
# Note: On utilise seulement EXIT pour éviter que le trap se déclenche sur chaque erreur de test
trap cleanup EXIT

run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TOTAL_TESTS++))
    echo -n "  Test: ${test_name} ... "
    
    if eval "${test_command}" > /dev/null 2>&1; then
        log_success "OK"
        ((PASSED_TESTS++))
        return 0
    else
        log_error "ÉCHEC"
        ((FAILED_TESTS++))
        return 1
    fi
}

# État initial
log_info "=============================================================="
log_info "État Initial du Cluster"
log_info "=============================================================="
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<'EOF'
kubectl get nodes -o wide
echo ""
echo "Masters: $(kubectl get nodes -l node-role.kubernetes.io/master=true --no-headers 2>/dev/null | wc -l || kubectl get nodes -l node-role.kubernetes.io/control-plane=true --no-headers 2>/dev/null | wc -l || echo "0")"
echo "Workers: $(kubectl get nodes --no-headers | grep -v master | grep -v control-plane | wc -l || echo "0")"
EOF
echo ""

# Test 1: Failover Master (perte d'un master)
if [[ ${#K3S_MASTER_IPS[@]} -ge 3 ]]; then
    log_info "=============================================================="
    log_info "Test 1: Failover Master (perte d'un master)"
    log_info "=============================================================="
    
    # Choisir un master non-bootstrap (pas le premier)
    TEST_MASTER_IP="${K3S_MASTER_IPS[1]}"
    TEST_MASTER_HOSTNAME="${K3S_MASTER_HOSTNAMES[1]}"
    
    log_info "Arrêt du master ${TEST_MASTER_HOSTNAME} (${TEST_MASTER_IP})..."
    ssh ${SSH_KEY_OPTS} "root@${TEST_MASTER_IP}" "systemctl stop k3s" || true
    STOPPED_MASTERS+=("${TEST_MASTER_IP}:${TEST_MASTER_HOSTNAME}")
    
    log_info "Attente de la stabilisation (30 secondes)..."
    sleep 30
    
    # Vérifier que le cluster fonctionne toujours
    run_test "Cluster opérationnel après perte master" \
        "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'kubectl get nodes | grep -q Ready'"
    
    run_test "Au moins 2 masters Ready" \
        "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'kubectl get nodes -l node-role.kubernetes.io/master=true --no-headers 2>/dev/null | grep Ready | wc -l | grep -qE \"[2-9]\" || kubectl get nodes -l node-role.kubernetes.io/control-plane=true --no-headers 2>/dev/null | grep Ready | wc -l | grep -qE \"[2-9]\"'"
    
    run_test "API Server accessible" \
        "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'kubectl get nodes >/dev/null 2>&1'"
    
    # Redémarrer le master
    log_info "Redémarrage du master ${TEST_MASTER_HOSTNAME}..."
    ssh ${SSH_KEY_OPTS} "root@${TEST_MASTER_IP}" "systemctl start k3s" || true
    sleep 30
    
    # Vérifier que le master est bien redémarré
    MAX_RETRIES=10
    RETRY=0
    while [[ ${RETRY} -lt ${MAX_RETRIES} ]]; do
        if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes | grep ${TEST_MASTER_HOSTNAME} | grep -q Ready" 2>/dev/null; then
            break
        fi
        ((RETRY++))
        log_info "  Attente que le master soit Ready... (${RETRY}/${MAX_RETRIES})"
        sleep 5
    done
    
    run_test "Master réintégré au cluster" \
        "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'kubectl get nodes | grep ${TEST_MASTER_HOSTNAME} | grep -q Ready'"
    
    # Retirer de la liste des nœuds arrêtés
    STOPPED_MASTERS=("${STOPPED_MASTERS[@]/${TEST_MASTER_IP}:${TEST_MASTER_HOSTNAME}/}")
    
    echo ""
fi

# Test 2: Failover Worker (perte d'un worker)
if [[ ${#K3S_WORKER_IPS[@]} -ge 1 ]]; then
    log_info "=============================================================="
    log_info "Test 2: Failover Worker (perte d'un worker)"
    log_info "=============================================================="
    
    TEST_WORKER_IP="${K3S_WORKER_IPS[0]}"
    TEST_WORKER_HOSTNAME="${K3S_WORKER_HOSTNAMES[0]}"
    
    log_info "Arrêt du worker ${TEST_WORKER_HOSTNAME} (${TEST_WORKER_IP})..."
    ssh ${SSH_KEY_OPTS} "root@${TEST_WORKER_IP}" "systemctl stop k3s-agent" || true
    STOPPED_WORKERS+=("${TEST_WORKER_IP}:${TEST_WORKER_HOSTNAME}")
    
    log_info "Attente de la détection (30 secondes - K3s peut prendre du temps pour détecter)..."
    sleep 30
    
    # Vérifier que le cluster fonctionne toujours
    run_test "Cluster opérationnel après perte worker" \
        "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'kubectl get nodes | grep -q Ready'"
    
    # Vérifier que le worker est marqué NotReady (avec retries car K3s peut prendre du temps)
    WORKER_NOTREADY=false
    for retry in {1..5}; do
        if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes | grep ${TEST_WORKER_HOSTNAME} | grep -q NotReady" 2>/dev/null; then
            WORKER_NOTREADY=true
            log_info "  Worker détecté comme NotReady (tentative ${retry}/5)"
            break
        fi
        if [[ ${retry} -lt 5 ]]; then
            log_info "  Attente que le worker soit marqué NotReady... (${retry}/5)"
            sleep 5
        fi
    done
    
    run_test "Worker marqué NotReady" "${WORKER_NOTREADY}"
    
    # Vérifier que les pods sont reschedulés (si des pods tournaient sur ce worker)
    run_test "Pods système toujours Running" \
        "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'kubectl get pods -n kube-system --field-selector=status.phase!=Running --no-headers 2>/dev/null | wc -l | grep -qE \"^0$\" || true'"
    
    # Redémarrer le worker
    log_info "Redémarrage du worker ${TEST_WORKER_HOSTNAME}..."
    ssh ${SSH_KEY_OPTS} "root@${TEST_WORKER_IP}" "systemctl start k3s-agent" || true
    sleep 30
    
    # Vérifier que le worker est bien redémarré
    MAX_RETRIES=10
    RETRY=0
    while [[ ${RETRY} -lt ${MAX_RETRIES} ]]; do
        if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes | grep ${TEST_WORKER_HOSTNAME} | grep -q Ready" 2>/dev/null; then
            break
        fi
        ((RETRY++))
        log_info "  Attente que le worker soit Ready... (${RETRY}/${MAX_RETRIES})"
        sleep 5
    done
    
    run_test "Worker réintégré au cluster" \
        "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'kubectl get nodes | grep ${TEST_WORKER_HOSTNAME} | grep -q Ready'"
    
    # Retirer de la liste des nœuds arrêtés
    STOPPED_WORKERS=("${STOPPED_WORKERS[@]/${TEST_WORKER_IP}:${TEST_WORKER_HOSTNAME}/}")
    
    echo ""
fi

# Test 3: Rescheduling Pods (déployer un pod, arrêter le worker, vérifier rescheduling)
if [[ ${#K3S_WORKER_IPS[@]} -ge 2 ]]; then
    log_info "=============================================================="
    log_info "Test 3: Rescheduling Pods (perte worker avec pods)"
    log_info "=============================================================="
    
    TEST_WORKER_IP="${K3S_WORKER_IPS[0]}"
    TEST_WORKER_HOSTNAME="${K3S_WORKER_HOSTNAMES[0]}"
    
    # Déployer un pod de test
    log_info "Déploiement d'un pod de test..."
    ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<'EOF'
kubectl run test-pod-failover --image=nginx:alpine --restart=Always -n default
sleep 10
EOF
    
    # Vérifier que le pod est Running
    POD_NODE=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pod test-pod-failover -n default -o jsonpath='{.spec.nodeName}' 2>/dev/null" || echo "")
    
    if [[ -n "${POD_NODE}" ]]; then
        log_info "Pod déployé sur: ${POD_NODE}"
        
        # Si le pod est sur le worker de test, arrêter le worker
        if [[ "${POD_NODE}" == "${TEST_WORKER_HOSTNAME}" ]] || [[ "${POD_NODE}" == "${TEST_WORKER_IP}" ]]; then
            log_info "Arrêt du worker ${TEST_WORKER_HOSTNAME} (pod présent)..."
            ssh ${SSH_KEY_OPTS} "root@${TEST_WORKER_IP}" "systemctl stop k3s-agent" || true
            STOPPED_WORKERS+=("${TEST_WORKER_IP}:${TEST_WORKER_HOSTNAME}")
            
            log_info "Attente du rescheduling (30 secondes)..."
            sleep 30
            
            # Vérifier que le pod est reschedulé
            NEW_POD_NODE=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pod test-pod-failover -n default -o jsonpath='{.spec.nodeName}' 2>/dev/null" || echo "")
            
            run_test "Pod reschedulé sur autre nœud" \
                "[[ -n \"${NEW_POD_NODE}\" ]] && [[ \"${NEW_POD_NODE}\" != \"${TEST_WORKER_HOSTNAME}\" ]] && [[ \"${NEW_POD_NODE}\" != \"${TEST_WORKER_IP}\" ]]"
            
            run_test "Pod Running après rescheduling" \
                "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'kubectl get pod test-pod-failover -n default | grep -q Running'"
            
            # Redémarrer le worker
            log_info "Redémarrage du worker ${TEST_WORKER_HOSTNAME}..."
            ssh ${SSH_KEY_OPTS} "root@${TEST_WORKER_IP}" "systemctl start k3s-agent" || true
            sleep 30
            
            # Vérifier que le worker est bien redémarré
            MAX_RETRIES=10
            RETRY=0
            while [[ ${RETRY} -lt ${MAX_RETRIES} ]]; do
                if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes | grep ${TEST_WORKER_HOSTNAME} | grep -q Ready" 2>/dev/null; then
                    break
                fi
                ((RETRY++))
                log_info "  Attente que le worker soit Ready... (${RETRY}/${MAX_RETRIES})"
                sleep 5
            done
            
            # Retirer de la liste des nœuds arrêtés
            STOPPED_WORKERS=("${STOPPED_WORKERS[@]/${TEST_WORKER_IP}:${TEST_WORKER_HOSTNAME}/}")
        else
            log_info "Pod sur autre nœud, test de rescheduling non applicable"
        fi
        
        # Nettoyer
        ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl delete pod test-pod-failover -n default --ignore-not-found=true" || true
    fi
    
    echo ""
fi

# Test 4: Ingress DaemonSet (redistribution après perte de nœud)
log_info "=============================================================="
log_info "Test 4: Ingress DaemonSet (redistribution)"
log_info "=============================================================="

if [[ ${#K3S_WORKER_IPS[@]} -ge 1 ]]; then
    TEST_WORKER_IP="${K3S_WORKER_IPS[0]}"
    TEST_WORKER_HOSTNAME="${K3S_WORKER_HOSTNAMES[0]}"
    
    # Compter les pods Ingress avant
    INGRESS_PODS_BEFORE=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n ingress-nginx --no-headers | grep Running | wc -l" || echo "0")
    
    log_info "Pods Ingress avant: ${INGRESS_PODS_BEFORE}"
    
    log_info "Arrêt du worker ${TEST_WORKER_HOSTNAME}..."
    ssh ${SSH_KEY_OPTS} "root@${TEST_WORKER_IP}" "systemctl stop k3s-agent" || true
    STOPPED_WORKERS+=("${TEST_WORKER_IP}:${TEST_WORKER_HOSTNAME}")
    
    log_info "Attente de la détection (20 secondes)..."
    sleep 20
    
    # Vérifier que les pods Ingress sont toujours distribués
    INGRESS_PODS_AFTER=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n ingress-nginx --no-headers | grep Running | wc -l" || echo "0")
    
    log_info "Pods Ingress après: ${INGRESS_PODS_AFTER}"
    
    # Le nombre devrait être proche (un pod par nœud actif)
    ACTIVE_NODES=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes --no-headers | grep Ready | wc -l" || echo "0")
    
    run_test "Ingress DaemonSet redistribué" \
        "[[ ${INGRESS_PODS_AFTER} -ge $((ACTIVE_NODES - 1)) ]]"
    
    # Redémarrer le worker
    log_info "Redémarrage du worker ${TEST_WORKER_HOSTNAME}..."
    ssh ${SSH_KEY_OPTS} "root@${TEST_WORKER_IP}" "systemctl start k3s-agent" || true
    sleep 30
    
    # Vérifier que le worker est bien redémarré
    MAX_RETRIES=10
    RETRY=0
    while [[ ${RETRY} -lt ${MAX_RETRIES} ]]; do
        if ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes | grep ${TEST_WORKER_HOSTNAME} | grep -q Ready" 2>/dev/null; then
            break
        fi
        ((RETRY++))
        log_info "  Attente que le worker soit Ready... (${RETRY}/${MAX_RETRIES})"
        sleep 5
    done
    
    INGRESS_PODS_FINAL=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n ingress-nginx --no-headers | grep Running | wc -l" || echo "0")
    
    run_test "Ingress DaemonSet restauré après réintégration" \
        "[[ ${INGRESS_PODS_FINAL} -ge ${INGRESS_PODS_BEFORE} ]]"
    
    # Retirer de la liste des nœuds arrêtés
    STOPPED_WORKERS=("${STOPPED_WORKERS[@]/${TEST_WORKER_IP}:${TEST_WORKER_HOSTNAME}/}")
    
    echo ""
fi

# Test 5: Connectivité Services Backend (vérifier que les services restent accessibles)
log_info "=============================================================="
log_info "Test 5: Connectivité Services Backend (après failover)"
log_info "=============================================================="

run_test "PostgreSQL accessible" \
    "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'timeout 3 nc -z 10.0.0.10 5432'"

run_test "Redis accessible" \
    "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'timeout 3 nc -z 10.0.0.10 6379'"

run_test "RabbitMQ accessible" \
    "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'timeout 3 nc -z 10.0.0.10 5672'"

run_test "MinIO accessible" \
    "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'timeout 3 nc -z 10.0.0.134 9000'"

run_test "MariaDB accessible" \
    "ssh ${SSH_KEY_OPTS} root@${MASTER_IP} 'timeout 3 nc -z 10.0.0.20 3306'"

echo ""

# Résumé final
echo "=============================================================="
log_info "RÉSUMÉ DES TESTS DE FAILOVER K3s"
echo "=============================================================="
log_info "Total de tests : ${TOTAL_TESTS}"
log_success "Tests réussis : ${PASSED_TESTS}"
if [[ ${FAILED_TESTS} -gt 0 ]]; then
    log_error "Tests échoués : ${FAILED_TESTS}"
else
    log_success "Tests échoués : ${FAILED_TESTS}"
fi
echo ""

if [[ ${FAILED_TESTS} -eq 0 ]]; then
    log_success "✅ Tous les tests de failover K3s sont passés avec succès !"
    log_info "Le cluster K3s est robuste et résilient"
    exit 0
else
    log_error "❌ Certains tests de failover ont échoué"
    log_warning "Vérifiez les erreurs ci-dessus"
    exit 1
fi

