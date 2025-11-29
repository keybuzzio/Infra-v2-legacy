#!/usr/bin/env bash
#
# 00_cleanup_complete_installation.sh - Nettoyage complet pour réinstallation depuis zéro
#
# Ce script nettoie TOUTES les données pour permettre une réinstallation propre :
# - Arrête et supprime tous les conteneurs Docker
# - Formate les volumes XFS (supprime toutes les données)
# - Nettoie les fichiers de configuration
# - Conserve uniquement les credentials (fichiers .env)
#
# Usage:
#   ./00_cleanup_complete_installation.sh [servers.tsv]
#
# ATTENTION: Ce script supprime TOUTES les données. Utiliser uniquement pour réinstallation complète.

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

# Vérifier les prérequis
if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier servers.tsv introuvable: ${TSV_FILE}"
    exit 1
fi

# Détecter la clé SSH (depuis install-01)
SSH_KEY="${HOME}/.ssh/keybuzz_infra"
if [[ ! -f "${SSH_KEY}" ]]; then
    SSH_KEY="/root/.ssh/keybuzz_infra"
fi

if [[ ! -f "${SSH_KEY}" ]]; then
    log_warning "Clé SSH introuvable, utilisation de l'authentification par défaut"
    SSH_KEY_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
else
    SSH_KEY_OPTS="-i ${SSH_KEY} -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
fi

# Fonction pour obtenir la configuration des volumes
get_volume_config() {
    local hostname="$1"
    local size=""
    local mount_path=""
    
    case "${hostname}" in
        postgres-*|pg-*|db-*)
            size="100"
            mount_path="/opt/keybuzz/postgres"
            ;;
        redis-*)
            size="50"
            mount_path="/opt/keybuzz/redis"
            ;;
        rabbitmq-*|rmq-*)
            size="50"
            mount_path="/opt/keybuzz/rabbitmq"
            ;;
        mariadb-*|maria-*)
            size="100"
            mount_path="/opt/keybuzz/mariadb"
            ;;
        minio-*)
            size="500"
            mount_path="/opt/keybuzz/minio"
            ;;
        *)
            return 1
            ;;
    esac
    
    echo "${size}:${mount_path}"
}

echo "=============================================================="
echo " [KeyBuzz] Nettoyage Complet - Réinstallation depuis Zéro"
echo "=============================================================="
echo ""
log_warning "ATTENTION: Ce script va supprimer TOUTES les données !"
log_warning "Les volumes XFS seront formatés (toutes les données perdues)"
log_warning "Tous les conteneurs Docker seront arrêtés et supprimés"
log_warning "Les fichiers de configuration seront nettoyés"
log_warning "Les credentials (.env) seront CONSERVÉS"
echo ""
read -p "Continuer ? (tapez 'OUI' pour confirmer) : " CONFIRM
if [[ "${CONFIRM}" != "OUI" ]]; then
    log_info "Nettoyage annulé"
    exit 0
fi

echo ""
log_info "Lecture de servers.tsv..."

# Collecter tous les serveurs (sauf install-01 et backn8n)
declare -a ALL_SERVERS
declare -a ALL_IPS
declare -a ALL_NOTES

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    # Exclure install-01 et backn8n
    if [[ "${HOSTNAME}" == "install-01" ]] || [[ "${HOSTNAME}" == "backn8n.keybuzz.io" ]]; then
        continue
    fi
    
    ALL_SERVERS+=("${HOSTNAME}")
    ALL_IPS+=("${IP_PRIVEE}")
    # Stocker aussi NOTES pour la configuration des volumes
    ALL_NOTES+=("${NOTES:-}")
done
exec 3<&-

if [[ ${#ALL_SERVERS[@]} -eq 0 ]]; then
    log_error "Aucun serveur trouvé dans servers.tsv"
    exit 1
fi

log_info "Serveurs à nettoyer: ${#ALL_SERVERS[@]}"
echo ""

# Nettoyer chaque serveur
for i in "${!ALL_SERVERS[@]}"; do
    hostname="${ALL_SERVERS[$i]}"
    ip="${ALL_IPS[$i]}"
    notes="${ALL_NOTES[$i]:-}"
    
    log_info "--------------------------------------------------------------"
    log_info "Nettoyage de ${hostname} (${ip})"
    log_info "--------------------------------------------------------------"
    
    # Vérifier l'accessibilité SSH
    if ! ssh ${SSH_KEY_OPTS} -o BatchMode=yes -o ConnectTimeout=5 "root@${ip}" "echo 'OK'" >/dev/null 2>&1; then
        log_warning "  ⚠ Serveur ${hostname} inaccessible, skip"
        continue
    fi
    
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${ip}" bash <<EOF
set -euo pipefail

NOTES="${notes}"

echo "  → Arrêt de tous les conteneurs Docker..."
docker stop \$(docker ps -q) 2>/dev/null || true
sleep 2

echo "  → Suppression de tous les conteneurs Docker..."
docker rm \$(docker ps -aq) 2>/dev/null || true

echo "  → Suppression de toutes les images Docker (sauf système)..."
docker images --format "{{.Repository}}:{{.Tag}}" | grep -vE "^<none>|^REPOSITORY" | xargs -r docker rmi -f 2>/dev/null || true

echo "  → Nettoyage des volumes Docker..."
docker volume prune -f >/dev/null 2>&1 || true

echo "  → Nettoyage des réseaux Docker..."
docker network prune -f >/dev/null 2>&1 || true

    # Obtenir la configuration du volume depuis servers.tsv ou par hostname
    VOLUME_CONFIG=""
    
    # Essayer de lire depuis servers.tsv (colonne NOTES)
    if [[ -n "\${NOTES}" ]] && echo "\${NOTES}" | grep -qE "volume:[0-9]+:[^[:space:]]+"; then
        VOLUME_SIZE=\$(echo "\${NOTES}" | sed -n 's/.*volume:\([0-9]\+\):.*/\1/p')
        VOLUME_MOUNT=\$(echo "\${NOTES}" | sed -n 's/.*volume:[0-9]\+:\([^[:space:]]\+\).*/\1/p')
        if [[ -n "\${VOLUME_SIZE}" ]] && [[ -n "\${VOLUME_MOUNT}" ]]; then
            VOLUME_CONFIG="\${VOLUME_SIZE}:\${VOLUME_MOUNT}"
        fi
    fi
    
    # Fallback sur hostname si NOTES ne contient pas la config
    if [[ -z "\${VOLUME_CONFIG}" ]]; then
        case "${hostname}" in
            postgres-*|pg-*|db-*)
                VOLUME_CONFIG="100:/opt/keybuzz/postgres"
                ;;
            redis-*)
                VOLUME_CONFIG="50:/opt/keybuzz/redis"
                ;;
            rabbitmq-*|rmq-*)
                VOLUME_CONFIG="50:/opt/keybuzz/rabbitmq"
                ;;
            mariadb-*|maria-*)
                VOLUME_CONFIG="100:/opt/keybuzz/mariadb"
                ;;
            minio-*)
                VOLUME_CONFIG="500:/opt/keybuzz/minio"
                ;;
        esac
    fi

if [[ -n "\${VOLUME_CONFIG}" ]]; then
    MOUNT_PATH="\$(echo \${VOLUME_CONFIG} | cut -d: -f2)"
    
    echo "  → Démontage du volume (si monté)..."
    umount "\${MOUNT_PATH}" 2>/dev/null || true
    sleep 1
    
    echo "  → Suppression de l'entrée fstab..."
    sed -i "\#\${MOUNT_PATH}#d" /etc/fstab 2>/dev/null || true
    
    echo "  → Détection du périphérique du volume..."
    # Chercher le périphérique attaché (généralement /dev/sdb, /dev/sdc, etc.)
    DEVICE=""
    for dev in /dev/sd[b-z] /dev/vd[b-z]; do
        if [[ -b "\${dev}" ]] && ! mountpoint -q "\${dev}" 2>/dev/null; then
            # Vérifier que ce n'est pas le disque système
            if ! lsblk -n -o MOUNTPOINT "\${dev}" 2>/dev/null | grep -q "^/$"; then
                DEVICE="\${dev}"
                break
            fi
        fi
    done
    
    if [[ -n "\${DEVICE}" ]]; then
        echo "  → Formatage du volume \${DEVICE} en XFS..."
        mkfs.xfs -f "\${DEVICE}" >/dev/null 2>&1 || true
        echo "  → Volume formaté: \${DEVICE}"
    else
        echo "  ⚠ Aucun volume détecté pour ${hostname}"
    fi
fi

# Nettoyer les répertoires de configuration (sauf credentials)
echo "  → Nettoyage des répertoires de configuration..."
rm -rf /opt/keybuzz/* 2>/dev/null || true
rm -rf /etc/patroni 2>/dev/null || true
rm -rf /etc/redis 2>/dev/null || true
rm -rf /etc/rabbitmq 2>/dev/null || true
rm -rf /etc/mariadb 2>/dev/null || true
rm -rf /etc/minio 2>/dev/null || true
rm -rf /etc/haproxy 2>/dev/null || true
rm -rf /etc/pgbouncer 2>/dev/null || true
rm -rf /etc/proxysql 2>/dev/null || true

# Nettoyer les services systemd
echo "  → Désactivation des services systemd..."
systemctl stop patroni-docker 2>/dev/null || true
systemctl stop redis-docker 2>/dev/null || true
systemctl stop rabbitmq-docker 2>/dev/null || true
systemctl stop mariadb-docker 2>/dev/null || true
systemctl stop haproxy-redis 2>/dev/null || true
systemctl stop haproxy-rabbitmq 2>/dev/null || true
systemctl stop pgbouncer 2>/dev/null || true
systemctl stop proxysql 2>/dev/null || true

systemctl disable patroni-docker 2>/dev/null || true
systemctl disable redis-docker 2>/dev/null || true
systemctl disable rabbitmq-docker 2>/dev/null || true
systemctl disable mariadb-docker 2>/dev/null || true
systemctl disable haproxy-redis 2>/dev/null || true
systemctl disable haproxy-rabbitmq 2>/dev/null || true
systemctl disable pgbouncer 2>/dev/null || true
systemctl disable proxysql 2>/dev/null || true

rm -f /etc/systemd/system/*patroni*.service 2>/dev/null || true
rm -f /etc/systemd/system/*redis*.service 2>/dev/null || true
rm -f /etc/systemd/system/*rabbitmq*.service 2>/dev/null || true
rm -f /etc/systemd/system/*mariadb*.service 2>/dev/null || true
rm -f /etc/systemd/system/*haproxy*.service 2>/dev/null || true
rm -f /etc/systemd/system/*pgbouncer*.service 2>/dev/null || true
rm -f /etc/systemd/system/*proxysql*.service 2>/dev/null || true

systemctl daemon-reload

# CONSERVER les credentials
echo "  → Conservation des credentials (.env)..."
# Les credentials sont dans /opt/keybuzz-installer/credentials/ et ne sont pas supprimés

echo "  ✓ Nettoyage terminé pour ${hostname}"
EOF
    
    if [[ $? -eq 0 ]]; then
        log_success "  ✓ ${hostname} nettoyé"
    else
        log_error "  ✗ Erreur lors du nettoyage de ${hostname}"
    fi
    echo ""
done

# Nettoyer install-01 (sans formater de volumes)
log_info "--------------------------------------------------------------"
log_info "Nettoyage de install-01 (sans volumes)"
log_info "--------------------------------------------------------------"

INSTALL01_IP=$(grep -E "^prod" "${TSV_FILE}" | grep -E "\tinstall-01\t" | cut -f4 | head -1)

if [[ -n "${INSTALL01_IP}" ]]; then
    ssh ${SSH_KEY_OPTS} -o BatchMode=yes "root@${INSTALL01_IP}" bash <<EOF
set -euo pipefail

echo "  → Nettoyage des logs et fichiers temporaires..."
rm -rf /tmp/keybuzz-* 2>/dev/null || true
rm -rf /var/log/keybuzz-* 2>/dev/null || true

echo "  → Nettoyage des anciens scripts (garder la structure)..."
# Ne pas supprimer les scripts, juste nettoyer les logs

echo "  ✓ Nettoyage terminé pour install-01"
EOF
    
    log_success "  ✓ install-01 nettoyé"
else
    log_warning "  ⚠ install-01 non trouvé dans servers.tsv"
fi

echo ""
log_success "=============================================================="
log_success "✅ Nettoyage complet terminé !"
log_success "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - Tous les conteneurs Docker arrêtés et supprimés"
log_info "  - Tous les volumes XFS formatés (données supprimées)"
log_info "  - Tous les fichiers de configuration nettoyés"
log_info "  - Tous les services systemd désactivés"
log_info "  - Credentials (.env) CONSERVÉS"
echo ""
log_info "Vous pouvez maintenant relancer l'installation depuis le début."
echo ""

