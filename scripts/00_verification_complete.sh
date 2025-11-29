#!/usr/bin/env bash
#
# 00_verification_complete.sh - Vérification complète avant réinstallation
#
# Ce script effectue toutes les vérifications nécessaires avant de relancer
# l'installation complète de l'infrastructure KeyBuzz.
#
# Usage:
#   ./00_verification_complete.sh [servers.tsv]
#
# Prérequis:
#   - Exécuter depuis install-01
#   - Accès SSH root vers tous les serveurs

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_step() { echo -e "${CYAN}[→]${NC} $1"; }

# Compteurs
TOTAL_CHECKS=0
PASSED_CHECKS=0
FAILED_CHECKS=0
WARNING_CHECKS=0

check() {
    local name="$1"
    local result="$2"
    ((TOTAL_CHECKS++))
    
    if [[ "${result}" == "OK" ]]; then
        log_success "${name}"
        ((PASSED_CHECKS++))
        return 0
    elif [[ "${result}" == "WARN" ]]; then
        log_warning "${name}"
        ((WARNING_CHECKS++))
        return 1
    else
        log_error "${name}"
        ((FAILED_CHECKS++))
        return 1
    fi
}

# Header
echo "=============================================================="
echo " [KeyBuzz] Vérification Complète - Pré-Installation"
echo "=============================================================="
echo ""
echo "Date: $(date)"
echo "Répertoire: ${INSTALL_DIR}"
echo ""

# ============================================================
# PHASE 1 : VÉRIFICATION DE L'ENVIRONNEMENT LOCAL (install-01)
# ============================================================
log_step "PHASE 1/4 : Vérification de l'environnement local (install-01)"
echo ""

# Vérifier qu'on est root
if [[ "$(id -u)" -ne 0 ]]; then
    check "Exécution en root" "FAIL"
    log_error "Ce script doit être exécuté en root"
    exit 1
else
    check "Exécution en root" "OK"
fi

# Vérifier servers.tsv
if [[ ! -f "${TSV_FILE}" ]]; then
    check "Fichier servers.tsv présent" "FAIL"
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
else
    check "Fichier servers.tsv présent" "OK"
    SERVER_COUNT=$(grep -c "^prod" "${TSV_FILE}" 2>/dev/null || echo "0")
    log_info "  ${SERVER_COUNT} serveurs trouvés dans servers.tsv"
fi

# Vérifier la structure des scripts
log_info "Vérification de la structure des scripts..."
REQUIRED_SCRIPTS=(
    "00_master_install.sh"
    "00_check_prerequisites.sh"
    "02_base_os_and_security/apply_base_os_to_all.sh"
    "03_postgresql_ha/03_pg_apply_all.sh"
    "04_redis_ha/04_redis_apply_all.sh"
    "05_rabbitmq_ha/05_rmq_apply_all.sh"
    "06_minio/06_minio_apply_all.sh"
    "07_mariadb_galera/07_maria_apply_all.sh"
    "08_proxysql_advanced/08_proxysql_apply_all.sh"
    "09_k3s_ha/09_k3s_apply_all.sh"
    "10_keybuzz/10_keybuzz_apply_all.sh"
    "11_n8n/11_n8n_apply_all.sh"
)

MISSING_SCRIPTS=0
for script in "${REQUIRED_SCRIPTS[@]}"; do
    if [[ ! -f "${SCRIPT_DIR}/${script}" ]]; then
        log_warning "  Script manquant: ${script}"
        ((MISSING_SCRIPTS++))
    fi
done

if [[ ${MISSING_SCRIPTS} -eq 0 ]]; then
    check "Structure des scripts complète" "OK"
else
    check "Structure des scripts complète" "WARN"
    log_warning "  ${MISSING_SCRIPTS} scripts manquants"
fi

# Vérifier les outils nécessaires
log_info "Vérification des outils installés..."
TOOLS=("ssh" "jq" "curl" "hcloud")
MISSING_TOOLS=0

for tool in "${TOOLS[@]}"; do
    if ! command -v "${tool}" &>/dev/null; then
        log_warning "  ${tool} non installé"
        ((MISSING_TOOLS++))
    fi
done

if [[ ${MISSING_TOOLS} -eq 0 ]]; then
    check "Outils nécessaires installés" "OK"
else
    check "Outils nécessaires installés" "WARN"
    log_warning "  ${MISSING_TOOLS} outils manquants"
fi

# Vérifier la clé SSH
SSH_KEY=""
if [[ -f "/root/.ssh/keybuzz_infra" ]]; then
    SSH_KEY="/root/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY="${HOME}/.ssh/keybuzz_infra"
elif [[ -f "/root/.ssh/id_ed25519" ]]; then
    SSH_KEY="/root/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY="${HOME}/.ssh/id_ed25519"
fi

if [[ -n "${SSH_KEY}" ]] && [[ -f "${SSH_KEY}" ]]; then
    check "Clé SSH configurée" "OK"
    log_info "  Clé: ${SSH_KEY}"
else
    check "Clé SSH configurée" "FAIL"
    log_error "Aucune clé SSH trouvée"
fi

# Vérifier HCLOUD_TOKEN
if [[ -n "${HCLOUD_TOKEN:-}" ]]; then
    check "HCLOUD_TOKEN configuré" "OK"
    # Tester la connexion API
    if hcloud server list &>/dev/null; then
        check "Connexion API Hetzner" "OK"
    else
        check "Connexion API Hetzner" "FAIL"
    fi
else
    check "HCLOUD_TOKEN configuré" "WARN"
    log_warning "HCLOUD_TOKEN non configuré (nécessaire pour certaines opérations)"
fi

echo ""

# ============================================================
# PHASE 2 : VÉRIFICATION DES SERVEURS
# ============================================================
log_step "PHASE 2/4 : Vérification des serveurs"
echo ""

# Détecter la clé SSH pour les connexions
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5"
if [[ -n "${SSH_KEY}" ]]; then
    SSH_OPTS="${SSH_OPTS} -i ${SSH_KEY}"
fi

# Lire servers.tsv et vérifier chaque serveur
declare -a SERVER_LIST=()
declare -a SERVER_IPS=()
declare -a SERVER_HOSTNAMES=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ -z "${ENV}" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    HOSTNAME=$(echo "${HOSTNAME}" | tr -d '\r\n' | xargs)
    
    # Ignorer install-01
    [[ "${HOSTNAME}" == "install-01" ]] && continue
    
    SERVER_LIST+=("${HOSTNAME}")
    SERVER_IPS+=("${IP_PRIVEE}")
    SERVER_HOSTNAMES+=("${HOSTNAME}")
done
exec 3<&-

log_info "Vérification de ${#SERVER_LIST[@]} serveurs..."
echo ""

SSH_ACCESSIBLE=0
SSH_FAILED=0

for i in "${!SERVER_LIST[@]}"; do
    hostname="${SERVER_LIST[$i]}"
    ip="${SERVER_IPS[$i]}"
    
    if [[ -z "${ip}" ]]; then
        check "  ${hostname} - IP privée configurée" "FAIL"
        ((SSH_FAILED++))
        continue
    fi
    
    # Test SSH
    if timeout 5 ssh ${SSH_OPTS} "root@${ip}" "echo 1" &>/dev/null; then
        check "  ${hostname} (${ip}) - Accessible via SSH" "OK"
        ((SSH_ACCESSIBLE++))
    else
        check "  ${hostname} (${ip}) - Accessible via SSH" "FAIL"
        ((SSH_FAILED++))
    fi
done

echo ""
if [[ ${SSH_ACCESSIBLE} -eq ${#SERVER_LIST[@]} ]]; then
    check "Tous les serveurs accessibles via SSH" "OK"
elif [[ ${SSH_ACCESSIBLE} -gt 0 ]]; then
    check "Tous les serveurs accessibles via SSH" "WARN"
    log_warning "  ${SSH_ACCESSIBLE}/${#SERVER_LIST[@]} serveurs accessibles"
else
    check "Tous les serveurs accessibles via SSH" "FAIL"
fi

echo ""

# ============================================================
# PHASE 3 : VÉRIFICATION DES VOLUMES
# ============================================================
log_step "PHASE 3/4 : Vérification des volumes"
echo ""

if [[ -n "${HCLOUD_TOKEN:-}" ]] && command -v hcloud &>/dev/null; then
    VOLUME_COUNT=$(hcloud volume list -o json 2>/dev/null | jq -r '.[] | select(.name | startswith("vol-")) | .name' | wc -l || echo "0")
    log_info "Volumes Hetzner trouvés: ${VOLUME_COUNT}"
    
    # Vérifier quelques volumes spécifiques
    TEST_VOLUMES=("vol-db-master-01" "vol-redis-01" "vol-k3s-worker-01")
    VOLUMES_FOUND=0
    
    for vol in "${TEST_VOLUMES[@]}"; do
        if hcloud volume describe "${vol}" &>/dev/null; then
            ((VOLUMES_FOUND++))
        fi
    done
    
    if [[ ${VOLUMES_FOUND} -eq ${#TEST_VOLUMES[@]} ]]; then
        check "Volumes Hetzner présents" "OK"
    elif [[ ${VOLUME_COUNT} -gt 0 ]]; then
        check "Volumes Hetzner présents" "WARN"
        log_warning "  ${VOLUME_COUNT} volumes trouvés, mais certains volumes de test manquants"
    else
        check "Volumes Hetzner présents" "WARN"
        log_warning "  Aucun volume trouvé (normal si première installation)"
    fi
else
    check "Volumes Hetzner présents" "WARN"
    log_warning "  Impossible de vérifier (hcloud non disponible ou HCLOUD_TOKEN non configuré)"
fi

# Vérifier le montage des volumes sur quelques serveurs de test
log_info "Vérification du montage des volumes (échantillon)..."
TEST_SERVERS=("db-master-01" "redis-01" "k3s-worker-01")
MOUNTED_COUNT=0

for hostname in "${TEST_SERVERS[@]}"; do
    # Trouver l'IP du serveur
    ip=$(grep -E "^prod" "${TSV_FILE}" | grep -E "\t${hostname}\t" | cut -f4)
    
    if [[ -z "${ip}" ]]; then
        continue
    fi
    
    # Vérifier si un volume est monté
    if timeout 5 ssh ${SSH_OPTS} "root@${ip}" "mount | grep -q '/opt/keybuzz\|/var/lib/containerd'" &>/dev/null; then
        ((MOUNTED_COUNT++))
    fi
done

if [[ ${MOUNTED_COUNT} -eq ${#TEST_SERVERS[@]} ]]; then
    check "Volumes montés sur les serveurs de test" "OK"
elif [[ ${MOUNTED_COUNT} -gt 0 ]]; then
    check "Volumes montés sur les serveurs de test" "WARN"
    log_warning "  ${MOUNTED_COUNT}/${#TEST_SERVERS[@]} serveurs de test ont des volumes montés"
else
    check "Volumes montés sur les serveurs de test" "WARN"
    log_warning "  Aucun volume monté détecté (normal si première installation)"
fi

echo ""

# ============================================================
# PHASE 4 : VÉRIFICATION DES CONFIGURATIONS SPÉCIFIQUES
# ============================================================
log_step "PHASE 4/4 : Vérification des configurations spécifiques"
echo ""

# Vérifier que les scripts utilisent bien DaemonSet + hostNetwork
log_info "Vérification de la solution validée (DaemonSet + hostNetwork)..."

# Vérifier Ingress NGINX
if grep -q "hostNetwork: true" "${SCRIPT_DIR}/09_k3s_ha/09_k3s_05_ingress_daemonset.sh" 2>/dev/null && \
   grep -q "kind: DaemonSet" "${SCRIPT_DIR}/09_k3s_ha/09_k3s_05_ingress_daemonset.sh" 2>/dev/null; then
    check "Ingress NGINX: DaemonSet + hostNetwork" "OK"
else
    check "Ingress NGINX: DaemonSet + hostNetwork" "FAIL"
fi

# Vérifier KeyBuzz (chercher dans tous les scripts de déploiement)
KEYBUZZ_SCRIPT=""
for script in "10_keybuzz_01_deploy_daemonsets.sh" "10_keybuzz_01_deploy_api.sh" "10_keybuzz_02_deploy_front.sh"; do
    if [[ -f "${SCRIPT_DIR}/10_keybuzz/${script}" ]]; then
        KEYBUZZ_SCRIPT="${SCRIPT_DIR}/10_keybuzz/${script}"
        break
    fi
done

if [[ -n "${KEYBUZZ_SCRIPT}" ]]; then
    if grep -q "hostNetwork: true" "${KEYBUZZ_SCRIPT}" 2>/dev/null && \
       grep -q "kind: DaemonSet" "${KEYBUZZ_SCRIPT}" 2>/dev/null; then
        check "KeyBuzz: DaemonSet + hostNetwork" "OK"
    else
        check "KeyBuzz: DaemonSet + hostNetwork" "WARN"
        log_warning "  Fichier trouvé mais configuration incomplète: $(basename ${KEYBUZZ_SCRIPT})"
    fi
else
    check "KeyBuzz: DaemonSet + hostNetwork" "WARN"
    log_warning "  Script KeyBuzz introuvable (cherché: 10_keybuzz_01_deploy_daemonsets.sh, 10_keybuzz_01_deploy_api.sh)"
fi

# Vérifier n8n
if [[ -f "${SCRIPT_DIR}/11_n8n/11_n8n_01_deploy.sh" ]]; then
    if grep -q "hostNetwork: true" "${SCRIPT_DIR}/11_n8n/11_n8n_01_deploy.sh" 2>/dev/null && \
       grep -q "kind: DaemonSet" "${SCRIPT_DIR}/11_n8n/11_n8n_01_deploy.sh" 2>/dev/null; then
        check "n8n: DaemonSet + hostNetwork" "OK"
    else
        check "n8n: DaemonSet + hostNetwork" "FAIL"
        log_error "  Fichier: ${SCRIPT_DIR}/11_n8n/11_n8n_01_deploy.sh"
        # Afficher les lignes trouvées pour debug
        log_info "  Lignes hostNetwork trouvées:"
        grep -n "hostNetwork" "${SCRIPT_DIR}/11_n8n/11_n8n_01_deploy.sh" 2>/dev/null | head -3 || true
        log_info "  Lignes DaemonSet trouvées:"
        grep -n "DaemonSet" "${SCRIPT_DIR}/11_n8n/11_n8n_01_deploy.sh" 2>/dev/null | head -3 || true
    fi
else
    check "n8n: DaemonSet + hostNetwork" "WARN"
    log_warning "  Script n8n introuvable"
fi

echo ""

# ============================================================
# RÉSUMÉ FINAL
# ============================================================
echo "=============================================================="
echo " RÉSUMÉ DE LA VÉRIFICATION"
echo "=============================================================="
echo ""
log_info "Total des vérifications: ${TOTAL_CHECKS}"
log_success "Réussies: ${PASSED_CHECKS}"
log_warning "Avertissements: ${WARNING_CHECKS}"
log_error "Échecs: ${FAILED_CHECKS}"
echo ""

# Calcul du score
SCORE=$(( (PASSED_CHECKS * 100) / TOTAL_CHECKS ))
echo "Score: ${SCORE}%"
echo ""

if [[ ${FAILED_CHECKS} -eq 0 ]]; then
    if [[ ${WARNING_CHECKS} -eq 0 ]]; then
        log_success "✅ Toutes les vérifications sont OK !"
        log_success "✅ Prêt pour l'installation complète"
        echo ""
        echo "Prochaine étape:"
        echo "  ./00_master_install.sh"
        exit 0
    else
        log_warning "⚠️  Vérifications OK avec avertissements"
        log_warning "⚠️  Installation possible, mais vérifiez les avertissements"
        echo ""
        echo "Prochaine étape:"
        echo "  ./00_master_install.sh"
        exit 0
    fi
else
    log_error "❌ Des vérifications ont échoué"
    log_error "❌ Corrigez les erreurs avant de continuer"
    echo ""
    echo "Actions recommandées:"
    echo "  1. Corriger les erreurs listées ci-dessus"
    echo "  2. Relancer ce script: ./00_verification_complete.sh"
    echo "  3. Une fois toutes les vérifications OK, lancer: ./00_master_install.sh"
    exit 1
fi

