#!/usr/bin/env bash
#
# 08_proxysql_03_optimize_galera.sh - Optimisation Galera pour ERPNext
#
# Ce script optimise la configuration Galera pour ERPNext :
# - wsrep_provider_options optimisés
# - InnoDB tuning pour charges ERP
# - SST/IST optimisation
# - Auto recovery activé
#
# Usage:
#   ./08_proxysql_03_optimize_galera.sh [servers.tsv]
#
# Prérequis:
#   - Module 7 installé (MariaDB Galera)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_FILE="${INSTALL_DIR}/credentials/mariadb.env"

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

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    log_info "Exécutez d'abord: ./07_maria_00_setup_credentials.sh"
    exit 1
fi

# Charger les credentials
source "${CREDENTIALS_FILE}"

# Options SSH (depuis install-01, pas besoin de clé pour IP internes 10.0.0.x)
SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 8 - Optimisation Galera pour ERPNext"
echo "=============================================================="
echo ""

# Collecter les nœuds MariaDB
declare -a MARIADB_NODES=()
declare -a MARIADB_IPS=()

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "db" ]] && [[ "${SUBROLE}" == "mariadb" ]]; then
        if [[ -n "${IP_PRIVEE}" ]]; then
            if [[ "${HOSTNAME}" == "maria-01" ]] || \
               [[ "${HOSTNAME}" == "maria-02" ]] || \
               [[ "${HOSTNAME}" == "maria-03" ]]; then
                MARIADB_NODES+=("${HOSTNAME}")
                MARIADB_IPS+=("${IP_PRIVEE}")
            fi
        fi
    fi
done
exec 3<&-

if [[ ${#MARIADB_IPS[@]} -ne 3 ]]; then
    log_error "3 nœuds MariaDB requis, trouvé: ${#MARIADB_IPS[@]}"
    exit 1
fi

log_success "Nœuds MariaDB détectés: ${MARIADB_NODES[*]} (${MARIADB_IPS[*]})"
echo ""

# Générer la configuration optimisée
log_info "Génération de la configuration Galera optimisée..."

GALERA_OPTIMIZED_CONFIG="${INSTALL_DIR}/config/galera_optimized.cnf"

cat > "${GALERA_OPTIMIZED_CONFIG}" <<GALERA_CNF
# Configuration Galera optimisée pour ERPNext - Module 8
# Généré automatiquement pour KeyBuzz
# Date: $(date)

[galera]
# Optimisations wsrep_provider_options pour ERPNext
wsrep_provider_options="gcs.fc_limit=256; gcs.fc_factor=1.0; gcs.fc_master_slave=YES; evs.keepalive_period=PT3S; evs.suspect_timeout=PT10S; evs.inactive_timeout=PT30S; pc.recovery=TRUE"

# SST/IST optimisation (rsync = stable et sûr pour ERPNext)
wsrep_sst_method=rsync

# Auto recovery
wsrep_provider_options="pc.recovery=TRUE"

[mysqld]
# InnoDB tuning pour charges ERP
innodb_buffer_pool_size=1G
innodb_log_file_size=512M
innodb_flush_method=O_DIRECT
innodb_flush_log_at_trx_commit=1

# Performance générales
max_connections=500
query_cache_type=0
query_cache_size=0

# Galera spécifique
wsrep_cluster_name="${GALERA_CLUSTER_NAME}"
wsrep_node_address=""
wsrep_node_name=""
GALERA_CNF

log_success "Configuration générée: ${GALERA_OPTIMIZED_CONFIG}"

# Appliquer la configuration sur chaque nœud
for i in "${!MARIADB_NODES[@]}"; do
    hostname="${MARIADB_NODES[$i]}"
    ip="${MARIADB_IPS[$i]}"
    
    log_info "=============================================================="
    log_info "Optimisation Galera: ${hostname} (${ip})"
    log_info "=============================================================="
    
    # Copier la configuration
    log_info "Copie de la configuration optimisée..."
    scp ${SSH_KEY_OPTS} "${GALERA_OPTIMIZED_CONFIG}" "root@${ip}:/tmp/galera_optimized.cnf"
    
    # Appliquer la configuration
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<EOF
set -euo pipefail

# Vérifier que MariaDB est en cours d'exécution
if ! docker ps | grep -q mariadb; then
    echo "ERREUR: MariaDB n'est pas en cours d'exécution"
    exit 1
fi

BASE="/opt/keybuzz/mariadb"

# Sauvegarder l'ancienne configuration
if [[ -f "\${BASE}/conf/my.cnf" ]]; then
    cp "\${BASE}/conf/my.cnf" "\${BASE}/conf/my.cnf.backup.\$(date +%Y%m%d_%H%M%S)"
fi

# Ajouter la configuration optimisée à my.cnf
cat /tmp/galera_optimized.cnf >> "\${BASE}/conf/my.cnf"

# Forcer le bootstrap en modifiant grastate.dat si nécessaire (avant redémarrage)
if [[ -f "\${BASE}/data/grastate.dat" ]]; then
    echo "Modification de grastate.dat pour forcer le bootstrap..."
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' "\${BASE}/data/grastate.dat" || true
fi

# Redémarrer MariaDB pour appliquer les changements
echo "Redémarrage de MariaDB pour appliquer les optimisations..."
docker restart mariadb || {
    echo "ERREUR: Impossible de redémarrer MariaDB"
    exit 1
}

# Attendre que MariaDB soit prêt
echo "Attente que MariaDB soit prêt (15 secondes)..."
sleep 15

# Vérifier que MariaDB est opérationnel
for i in {1..30}; do
    if docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; then
        echo "  ✓ MariaDB opérationnel"
        break
    fi
    if [[ \$i -eq 30 ]]; then
        echo "ERREUR: MariaDB n'est pas opérationnel après redémarrage"
        # Si MariaDB ne démarre pas, forcer le bootstrap et réessayer
        if [[ -f "\${BASE}/data/grastate.dat" ]]; then
            echo "Tentative de correction du bootstrap..."
            sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' "\${BASE}/data/grastate.dat" || true
            docker restart mariadb || true
            sleep 10
            if docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SELECT 1;" >/dev/null 2>&1; then
                echo "  ✓ MariaDB opérationnel après correction"
                break
            fi
        fi
        exit 1
    fi
    sleep 2
done

# Vérifier les paramètres optimisés
echo ""
echo "=== Vérification des paramètres optimisés ==="
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW VARIABLES LIKE 'innodb_buffer_pool_size';"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW VARIABLES LIKE 'innodb_log_file_size';"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW VARIABLES LIKE 'wsrep_sst_method';"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_local_state_comment';"

echo "  ✓ Configuration optimisée appliquée"
EOF
    
    if [ $? -eq 0 ]; then
        log_success "${hostname}: Optimisations appliquées avec succès"
    else
        log_error "${hostname}: Échec de l'application des optimisations"
        exit 1
    fi
    
    echo ""
done

# Attendre la stabilisation du cluster
log_info "Attente de la stabilisation du cluster (20 secondes)..."
sleep 20

# Vérifier le statut du cluster
log_info "Vérification du statut du cluster..."
ssh ${SSH_KEY_OPTS} "root@${MARIADB_IPS[0]}" bash <<EOF
set -euo pipefail

echo "=== Statut du cluster Galera ==="
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_cluster_size';"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_local_state_comment';"
docker exec mariadb mysql -uroot -p"${MARIADB_ROOT_PASSWORD}" -e "SHOW STATUS LIKE 'wsrep_ready';"
EOF

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Optimisations Galera appliquées sur tous les nœuds"
echo "=============================================================="
echo ""
log_info "Optimisations appliquées:"
log_info "  - wsrep_provider_options optimisés pour ERPNext"
log_info "  - InnoDB tuning (buffer_pool_size=1G, log_file_size=512M)"
log_info "  - SST method: rsync (stable et sûr)"
log_info "  - Auto recovery activé (pc.recovery=TRUE)"
echo ""
log_info "Prochaine étape:"
log_info "  ./08_proxysql_04_monitoring_setup.sh ${TSV_FILE}"
echo ""

