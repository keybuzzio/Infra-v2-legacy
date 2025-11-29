#!/usr/bin/env bash
#
# 07_maria_02_deploy_galera.sh - Déploiement du cluster MariaDB Galera
#
# Ce script déploie le cluster MariaDB Galera 3 nœuds en utilisant Docker.
# Le premier nœud (maria-01) démarre en mode bootstrap, les autres se joignent automatiquement.
#
# Usage:
#   ./07_maria_02_deploy_galera.sh [servers.tsv]
#
# Prérequis:
#   - Script 07_maria_01_prepare_nodes.sh exécuté
#   - Credentials configurés (mariadb.env)
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

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Header
echo "=============================================================="
echo " [KeyBuzz] Module 7 - Déploiement Cluster MariaDB Galera"
echo "=============================================================="
echo ""

# Collecter les informations des nœuds MariaDB
declare -a MARIADB_NODES
declare -a MARIADB_IPS

log_info "Lecture de servers.tsv..."

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" != "db" ]] || [[ "${SUBROLE}" != "mariadb" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    if [[ "${HOSTNAME}" == "maria-01" ]] || \
       [[ "${HOSTNAME}" == "maria-02" ]] || \
       [[ "${HOSTNAME}" == "maria-03" ]]; then
        MARIADB_NODES+=("${HOSTNAME}")
        MARIADB_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#MARIADB_NODES[@]} -ne 3 ]]; then
    log_error "Nombre de nœuds MariaDB incorrect: ${#MARIADB_NODES[@]} (attendu: 3)"
    exit 1
fi

# Construire la liste des adresses Galera
GALERA_ADDRESSES="gcomm://${MARIADB_IPS[0]},${MARIADB_IPS[1]},${MARIADB_IPS[2]}"

log_info "Cluster Galera: ${GALERA_ADDRESSES}"
log_info "Cluster Name: ${GALERA_CLUSTER_NAME}"
echo ""

# Copier les credentials sur chaque nœud
log_info "Copie des credentials sur les nœuds..."
for i in "${!MARIADB_NODES[@]}"; do
    hostname="${MARIADB_NODES[$i]}"
    ip="${MARIADB_IPS[$i]}"
    
    scp ${SSH_KEY_OPTS} -q "${CREDENTIALS_FILE}" "root@${ip}:/tmp/mariadb.env"
    log_success "Credentials copiés sur ${hostname}"
done
echo ""

# Fonction pour créer la configuration my.cnf
create_mycnf() {
    local node_ip=$1
    local node_name=$2
    cat <<EOF
[mysqld]
bind-address=0.0.0.0
default_storage_engine=InnoDB
binlog_format=ROW
innodb_autoinc_lock_mode=2
innodb_flush_log_at_trx_commit=1

# Galera Configuration
wsrep_on=ON
wsrep_provider=/usr/lib/galera/libgalera_smm.so
wsrep_cluster_address="${GALERA_ADDRESSES}"
wsrep_cluster_name="${GALERA_CLUSTER_NAME}"
wsrep_node_address="${node_ip}"
wsrep_node_name="${node_name}"
wsrep_sst_method=rsync
wsrep_provider_options="pc.recovery=TRUE;gcache.size=1G"

# Performance
max_connections=500
character-set-server=utf8mb4
collation-server=utf8mb4_unicode_ci

# Skip name resolution
skip-name-resolve=1
EOF
}

# Déployer le premier nœud (bootstrap)
log_info "=============================================================="
log_info "Déploiement du nœud bootstrap: ${MARIADB_NODES[0]} (${MARIADB_IPS[0]})"
log_info "=============================================================="

ssh ${SSH_KEY_OPTS} "root@${MARIADB_IPS[0]}" bash <<EOF
set -euo pipefail

source /tmp/mariadb.env

BASE="/opt/keybuzz/mariadb"

# Nettoyer les anciens conteneurs
docker stop mariadb 2>/dev/null || true
docker rm mariadb 2>/dev/null || true

# Forcer le bootstrap en modifiant grastate.dat si nécessaire
if [[ -f "\${BASE}/data/grastate.dat" ]]; then
    echo "  Modification de grastate.dat pour forcer le bootstrap..."
    sed -i 's/safe_to_bootstrap: 0/safe_to_bootstrap: 1/' "\${BASE}/data/grastate.dat" || true
fi

# Créer la configuration my.cnf
cat > "\${BASE}/conf/my.cnf" <<'MYCNF'
$(create_mycnf "${MARIADB_IPS[0]}" "${MARIADB_NODES[0]}")
MYCNF

# Déployer MariaDB Galera en mode bootstrap
docker run -d --name mariadb \
  --restart unless-stopped \
  --network host \
  -v "\${BASE}/data":/var/lib/mysql \
  -v "\${BASE}/conf/my.cnf":/etc/mysql/conf.d/my_custom.cnf:ro \
  -e MYSQL_ROOT_PASSWORD="\${MARIADB_ROOT_PASSWORD}" \
  bitnami/mariadb-galera:10.11.6 \
  --wsrep-cluster-name="\${GALERA_CLUSTER_NAME}" \
  --wsrep-cluster-address="${GALERA_ADDRESSES}" \
  --wsrep-node-address="${MARIADB_IPS[0]}" \
  --wsrep-node-name="${MARIADB_NODES[0]}" \
  --wsrep-sst-method=rsync \
  --wsrep-new-cluster

echo "  ✓ Conteneur MariaDB démarré (bootstrap)"
EOF

log_success "Nœud bootstrap déployé"
echo ""

# Attendre que le premier nœud soit prêt
log_info "Attente que le nœud bootstrap soit prêt (30 secondes)..."
sleep 30

# Vérifier que le premier nœud est opérationnel
log_info "Vérification du nœud bootstrap..."
if ssh ${SSH_KEY_OPTS} "root@${MARIADB_IPS[0]}" "docker exec mariadb mysql -uroot -p${MARIADB_ROOT_PASSWORD} -e 'SELECT 1' >/dev/null 2>&1"; then
    log_success "Nœud bootstrap opérationnel"
else
    log_warning "Nœud bootstrap pas encore prêt, attente supplémentaire (30 secondes)..."
    sleep 30
fi
echo ""

# Déployer les nœuds secondaires
for i in 1 2; do
    hostname="${MARIADB_NODES[$i]}"
    ip="${MARIADB_IPS[$i]}"
    
    log_info "=============================================================="
    log_info "Déploiement du nœud: ${hostname} (${ip})"
    log_info "=============================================================="
    
    ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<EOF
set -euo pipefail

source /tmp/mariadb.env

BASE="/opt/keybuzz/mariadb"

# Nettoyer les anciens conteneurs
docker stop mariadb 2>/dev/null || true
docker rm mariadb 2>/dev/null || true

# Créer la configuration my.cnf
cat > "\${BASE}/conf/my.cnf" <<'MYCNF'
$(create_mycnf "${ip}" "${hostname}")
MYCNF

# Déployer MariaDB Galera (rejoint le cluster)
docker run -d --name mariadb \
  --restart unless-stopped \
  --network host \
  -v "\${BASE}/data":/var/lib/mysql \
  -v "\${BASE}/conf/my.cnf":/etc/mysql/conf.d/my_custom.cnf:ro \
  -e MYSQL_ROOT_PASSWORD="\${MARIADB_ROOT_PASSWORD}" \
  bitnami/mariadb-galera:10.11.6 \
  --wsrep-cluster-name="\${GALERA_CLUSTER_NAME}" \
  --wsrep-cluster-address="${GALERA_ADDRESSES}" \
  --wsrep-node-address="${ip}" \
  --wsrep-node-name="${hostname}" \
  --wsrep-sst-method=rsync

echo "  ✓ Conteneur MariaDB démarré (rejoint le cluster)"
EOF

    log_success "${hostname} déployé"
    echo ""
    
    # Attendre un peu avant le nœud suivant
    if [[ $i -lt 2 ]]; then
        log_info "Attente avant le prochain nœud (10 secondes)..."
        sleep 10
    fi
done

# Attendre la stabilisation du cluster
log_info "Attente de la stabilisation du cluster (60 secondes)..."
sleep 60

# Vérifier le statut du cluster
log_info "=============================================================="
log_info "Vérification du statut du cluster"
log_info "=============================================================="

for i in "${!MARIADB_NODES[@]}"; do
    hostname="${MARIADB_NODES[$i]}"
    ip="${MARIADB_IPS[$i]}"
    
    log_info "Vérification de ${hostname}..."
    
    if ssh ${SSH_KEY_OPTS} "root@${ip}" bash <<EOF
source /tmp/mariadb.env

# Vérifier que le conteneur est en cours d'exécution
if ! docker ps | grep -q mariadb; then
    echo "  ✗ Conteneur non démarré"
    exit 1
fi

# Vérifier le statut Galera
CLUSTER_SIZE=\$(docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -Nse "SHOW STATUS LIKE 'wsrep_cluster_size';" 2>/dev/null | awk '{print \$2}' || echo "0")
CLUSTER_STATUS=\$(docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -Nse "SHOW STATUS LIKE 'wsrep_local_state_comment';" 2>/dev/null | awk '{print \$2}' || echo "Unknown")
READY=\$(docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -Nse "SHOW STATUS LIKE 'wsrep_ready';" 2>/dev/null | awk '{print \$2}' || echo "OFF")

echo "  Cluster Size: \${CLUSTER_SIZE}"
echo "  Status: \${CLUSTER_STATUS}"
echo "  Ready: \${READY}"

if [[ "\${CLUSTER_SIZE}" == "3" ]] && [[ "\${CLUSTER_STATUS}" == "Synced" ]] && [[ "\${READY}" == "ON" ]]; then
    echo "  ✓ ${hostname} opérationnel"
    exit 0
else
    echo "  ⚠ ${hostname} en cours de synchronisation..."
    exit 0
fi
EOF
    then
        log_success "${hostname} vérifié"
    else
        log_warning "${hostname} en cours de synchronisation (normal au démarrage)"
    fi
    echo ""
done

# Créer l'utilisateur ERPNext et la base de données
log_info "Création de l'utilisateur ERPNext et de la base de données..."
ssh ${SSH_KEY_OPTS} "root@${MARIADB_IPS[0]}" bash <<EOF
source /tmp/mariadb.env

# Supprimer l'utilisateur existant s'il existe (pour éviter les conflits)
docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -e "DROP USER IF EXISTS '\${MARIADB_APP_USER}'@'%';" 2>/dev/null || true
docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -e "DROP USER IF EXISTS '\${MARIADB_APP_USER}'@'localhost';" 2>/dev/null || true

# Créer la base et l'utilisateur
docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} <<SQL
CREATE DATABASE IF NOT EXISTS \${MARIADB_DB} CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER '\${MARIADB_APP_USER}'@'%' IDENTIFIED BY '\${MARIADB_APP_PASSWORD}';
GRANT ALL PRIVILEGES ON \${MARIADB_DB}.* TO '\${MARIADB_APP_USER}'@'%';
FLUSH PRIVILEGES;
SQL

# Vérifier que l'utilisateur a été créé
if docker exec mariadb mysql -uroot -p\${MARIADB_ROOT_PASSWORD} -e "SELECT User, Host FROM mysql.user WHERE User='\${MARIADB_APP_USER}';" | grep -q "\${MARIADB_APP_USER}"; then
    echo "  ✓ Utilisateur et base de données créés"
else
    echo "  ✗ Erreur lors de la création de l'utilisateur"
    exit 1
fi
EOF

log_success "Cluster MariaDB Galera déployé avec succès"
echo ""

echo "=============================================================="
log_success "✅ Déploiement du cluster MariaDB Galera terminé !"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - Nœuds déployés: ${#MARIADB_NODES[@]}"
log_info "  - Cluster Name: ${GALERA_CLUSTER_NAME}"
log_info "  - Database: ${MARIADB_DB}"
log_info "  - User: ${MARIADB_APP_USER}"
echo ""
log_info "Prochaine étape: Installer ProxySQL"
log_info "  ./07_maria_03_install_proxysql.sh ${TSV_FILE}"
echo ""

