#!/bin/bash
# ============================================================
# Script: Attachement, formatage XFS et montage des volumes
# ============================================================
# Ce script attache les volumes existants aux serveurs,
# les formate en XFS et les monte avec fstab
# ============================================================

set -uo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Fonctions de logging
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✓]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
log_error() { echo -e "${RED}[✗]${NC} $1"; }
log_step() { echo -e "${CYAN}[→]${NC} $1"; }

# ============================================================
# CONFIGURATION
# ============================================================

TSV_FILE="/opt/keybuzz-installer/servers.tsv"

if [[ ! -f "${TSV_FILE}" ]]; then
    log_error "Fichier ${TSV_FILE} introuvable"
    exit 1
fi

# Détecter la clé SSH
SSH_KEY=""
if [[ -f "/root/.ssh/keybuzz_infra" ]]; then
    SSH_KEY="/root/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY="${HOME}/.ssh/keybuzz_infra"
elif [[ -f "/root/.ssh/id_ed25519" ]]; then
    SSH_KEY="/root/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY="${HOME}/.ssh/id_ed25519"
elif [[ -f "/root/.ssh/id_rsa" ]]; then
    SSH_KEY="/root/.ssh/id_rsa"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY="${HOME}/.ssh/id_rsa"
fi

if [[ -z "${SSH_KEY}" ]] || [[ ! -f "${SSH_KEY}" ]]; then
    log_error "Aucune clé SSH trouvée"
    exit 1
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes"

# ============================================================
# PHASE 1 : ANALYSE DES VOLUMES
# ============================================================
log_step "PHASE 1/3 : Analyse des volumes et serveurs"
echo ""

declare -A SERVER_VOLUMES=()
SERVER_LIST=()

# Lire servers.tsv (format: ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES)
while IFS=$'\t' read -r env ip_pub hostname ip_priv fqdn user_ssh pool role subrole docker_stack core notes; do
    # Ignorer les lignes vides ou commentaires
    [[ -z "${env}" ]] || [[ "${env}" == "#"* ]] || [[ "${env}" == "ENV"* ]] && continue
    
    # Nettoyer les variables
    env=$(echo "${env}" | tr -d '\r\n' | xargs)
    hostname=$(echo "${hostname}" | tr -d '\r\n' | xargs)
    
    # Ignorer install-01 et backn8n
    [[ "${hostname}" == "install-01" ]] && continue
    [[ "${hostname}" == "backn8n"* ]] && continue
    
    HOSTNAME="${hostname}"
    
    # Déterminer la taille et le point de montage selon le hostname
    size=""
    mount_path=""
    
    case "${HOSTNAME}" in
        # Database
        db-master-*)
            size=100
            mount_path="/opt/keybuzz/postgres/data"
            ;;
        db-slave-*)
            size=50
            mount_path="/opt/keybuzz/postgres/data"
            ;;
        # HAProxy
        haproxy-*)
            size=10
            mount_path="/opt/keybuzz/haproxy/data"
            ;;
        # Redis
        redis-*)
            size=20
            mount_path="/opt/keybuzz/redis/data"
            ;;
        # Queue
        queue-*)
            size=40
            mount_path="/opt/keybuzz/rabbitmq/data"
            ;;
        # Storage
        minio-*)
            size=100
            mount_path="/opt/keybuzz/minio/data"
            ;;
        backup-*)
            size=200
            mount_path="/opt/keybuzz/backup/data"
            ;;
        # K3s Workers
        k3s-worker-*)
            size=50
            mount_path="/var/lib/containerd"
            ;;
        # Monitoring & Security
        monitor-*)
            size=100
            mount_path="/opt/keybuzz/monitor/data"
            ;;
        vault-*)
            size=20
            mount_path="/opt/keybuzz/vault/data"
            ;;
        siem-*)
            size=200
            mount_path="/opt/keybuzz/siem/data"
            ;;
        # Services
        vector-db-*)
            size=50
            mount_path="/opt/keybuzz/qdrant/data"
            ;;
        temporal-db-*)
            size=50
            mount_path="/opt/keybuzz/temporal-db/data"
            ;;
        temporal-*)
            size=20
            mount_path="/opt/keybuzz/temporal/data"
            ;;
        analytics-db-*)
            size=100
            mount_path="/opt/keybuzz/analytics-db/data"
            ;;
        analytics-*)
            size=20
            mount_path="/opt/keybuzz/analytics/data"
            ;;
        mail-core-*)
            size=50
            mount_path="/opt/keybuzz/mail/data"
            ;;
        # Apps
        python-api-*)
            size=20
            mount_path="/opt/keybuzz/api/data"
            ;;
        billing-*)
            size=20
            mount_path="/opt/keybuzz/billing/data"
            ;;
        api-gateway-*)
            size=10
            mount_path="/opt/keybuzz/gateway/data"
            ;;
        litellm-*)
            size=20
            mount_path="/opt/keybuzz/litellm/data"
            ;;
        etl-*)
            size=50
            mount_path="/opt/keybuzz/airbyte/data"
            ;;
        baserow-*)
            size=20
            mount_path="/opt/keybuzz/baserow/data"
            ;;
        nocodb-*)
            size=20
            mount_path="/opt/keybuzz/nocodb/data"
            ;;
        ml-platform-*)
            size=50
            mount_path="/opt/keybuzz/mlflow/data"
            ;;
        n8n-*)
            size=20
            mount_path="/opt/keybuzz/n8n/data"
            ;;
        # MariaDB
        mariadb-*|maria-*)
            size=50
            mount_path="/opt/keybuzz/mariadb/data"
            ;;
        # ProxySQL
        proxysql-*)
            size=10
            mount_path="/opt/keybuzz/proxysql/data"
            ;;
        # Pas de volume pour ces serveurs
        k3s-master-*|mail-mx-*|dev-aio-*|install-*|backn8n*|connect-*|crm-*|builder-*)
            # Skip
            ;;
        *)
            # Serveur inconnu ou pas de volume
            ;;
    esac
    
    if [[ -n "${size}" ]] && [[ -n "${mount_path}" ]]; then
        SERVER_VOLUMES["${HOSTNAME}"]="${size}|${mount_path}"
    fi
done < "${TSV_FILE}"

log_success "${#SERVER_VOLUMES[@]} serveurs avec volumes configurés"
echo ""

# ============================================================
# PHASE 2 : ATTACHEMENT DES VOLUMES
# ============================================================
log_step "PHASE 2/3 : Attachement des volumes aux serveurs"
echo ""

ATTACHED=0
ALREADY_ATTACHED=0
FAILED_ATTACH=0

for hostname in "${!SERVER_VOLUMES[@]}"; do
    IFS='|' read -r size mount_path <<< "${SERVER_VOLUMES[${hostname}]}"
    vol_name="vol-${hostname}"
    
    log_info "Traitement de ${hostname} (${vol_name})..."
    
    # Vérifier si le volume existe
    if ! hcloud volume describe "${vol_name}" &>/dev/null; then
        log_warning "  ${vol_name} n'existe pas, skip"
        continue
    fi
    
    # Vérifier si déjà attaché
    current_server=$(hcloud volume describe "${vol_name}" -o json 2>/dev/null | jq -r '.server // empty')
    
    if [[ -n "${current_server}" ]] && [[ "${current_server}" != "null" ]]; then
        if [[ "${current_server}" == "${hostname}" ]]; then
            log_info "  ${vol_name} déjà attaché à ${hostname}"
            ((ALREADY_ATTACHED++))
        else
            log_warning "  ${vol_name} attaché à ${current_server} au lieu de ${hostname}"
            # Détacher puis réattacher
            hcloud volume detach "${vol_name}" &>/dev/null || true
            sleep 2
        fi
    fi
    
    # Attacher le volume
    if [[ "${current_server}" != "${hostname}" ]]; then
        log_info "  Attachement de ${vol_name} à ${hostname}..."
        attach_output=$(hcloud volume attach "${vol_name}" "${hostname}" 2>&1)
        attach_rc=$?
        
        if [[ ${attach_rc} -eq 0 ]]; then
            log_success "  Volume attaché"
            ((ATTACHED++))
            sleep 3  # Attendre que le volume soit visible
        else
            log_error "  Échec attachement: ${attach_output}"
            ((FAILED_ATTACH++))
            # Continuer quand même pour les autres volumes
        fi
    fi
done

log_success "${ATTACHED} volumes attachés"
log_info "${ALREADY_ATTACHED} volumes déjà attachés"
[[ ${FAILED_ATTACH} -gt 0 ]] && log_warning "${FAILED_ATTACH} échecs d'attachement"
echo ""

# ============================================================
# PHASE 3 : FORMATAGE ET MONTAGE
# ============================================================
log_step "PHASE 3/3 : Formatage XFS et montage"
echo ""

FORMATTED=0
MOUNTED=0
ALREADY_MOUNTED=0
FAILED_MOUNT=0

for hostname in "${!SERVER_VOLUMES[@]}"; do
    IFS='|' read -r size mount_path <<< "${SERVER_VOLUMES[${hostname}]}"
    vol_name="vol-${hostname}"
    
    # Obtenir l'IP privée du serveur depuis servers.tsv
    server_ip=$(grep -E "^prod" "${TSV_FILE}" | grep -E "\t${hostname}\t" | cut -f4)
    
    if [[ -z "${server_ip}" ]]; then
        log_warning "${hostname} : IP privée introuvable dans servers.tsv"
        continue
    fi
    
    log_info "Traitement de ${hostname} (${vol_name})..."
    
    # Vérifier si le volume est attaché
    current_server=$(hcloud volume describe "${vol_name}" -o json 2>/dev/null | jq -r '.server // empty')
    if [[ -z "${current_server}" ]] || [[ "${current_server}" != "${hostname}" ]]; then
        log_warning "  ${vol_name} n'est pas attaché à ${hostname}, skip"
        continue
    fi
    
    # Attendre que le serveur soit accessible via SSH
    log_info "  Vérification de l'accessibilité SSH..."
    ssh_ok=false
    for i in {1..30}; do
        if ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" "echo 1" &>/dev/null; then
            ssh_ok=true
            break
        fi
        sleep 2
    done
    
    if [[ "${ssh_ok}" == "false" ]]; then
        log_error "  Serveur ${hostname} non accessible via SSH"
        ((FAILED_MOUNT++))
        continue
    fi
    
    # Détecter le device
    log_info "  Détection du device..."
    
    device=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
        "TARGET_SIZE=\$((${size} * 1000000000)); TOLERANCE=\$((TARGET_SIZE / 10)); \
        for dev in /dev/sd{b..z} /dev/vd{b..z}; do \
            [ -b \"\$dev\" ] || continue; \
            DEV_SIZE=\$(lsblk -b -n -o SIZE \"\$dev\" 2>/dev/null | head -1); \
            [ -z \"\$DEV_SIZE\" ] && continue; \
            if [ \$DEV_SIZE -gt \$((TARGET_SIZE - TOLERANCE)) ] && [ \$DEV_SIZE -lt \$((TARGET_SIZE + TOLERANCE)) ]; then \
                mount | grep -q \"\$dev\" || { echo \"\$dev\"; break; }; \
            fi; \
        done" 2>/dev/null || echo "")
    
    # Méthode 2: Chercher le dernier device non monté
    if [[ -z "${device}" ]]; then
        device=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
            "for dev in \$(lsblk -d -n -o NAME | grep -E '^[sv]d[b-z]$' | sort -r); do \
                dev_path=\"/dev/\$dev\"; \
                if mount | grep -q \"\$dev_path\"; then continue; fi; \
                if [ -b \"\$dev_path\" ]; then echo \"\$dev_path\"; break; fi; \
            done" 2>/dev/null || echo "")
    fi
    
    # Méthode 3: Chercher via /dev/disk/by-id (Hetzner volumes)
    if [[ -z "${device}" ]]; then
        device=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
            "ls -1 /dev/disk/by-id/scsi-* 2>/dev/null | grep -v part | head -1 | xargs readlink -f 2>/dev/null" || echo "")
    fi
    
    if [[ -z "${device}" ]]; then
        log_error "  Device non trouvé pour ${vol_name}"
        ((FAILED_MOUNT++))
        continue
    fi
    
    log_success "  Device détecté: ${device}"
    
    # Vérifier si déjà monté
    is_mounted=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
        "mountpoint -q '${mount_path}' && echo 1 || echo 0" 2>/dev/null || echo "0")
    
    if [[ "${is_mounted}" == "1" ]]; then
        log_info "  ${mount_path} déjà monté"
        ((ALREADY_MOUNTED++))
    else
        # Formater en XFS (si pas déjà formaté)
        log_info "  Formatage XFS de ${device}..."
        format_needed=true
        
        # Vérifier si déjà formaté en XFS
        if ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
            "blkid ${device} | grep -q 'TYPE=\"xfs\"'" &>/dev/null; then
            log_info "  ${device} déjà formaté en XFS"
            format_needed=false
        fi
        
        if [[ "${format_needed}" == "true" ]]; then
            # Installer xfsprogs si nécessaire
            ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
                "apt-get update -qq && apt-get install -y -qq xfsprogs" &>/dev/null || true
            
            # Formater
            if ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
                "mkfs.xfs -f ${device}" &>/dev/null; then
                log_success "  ${device} formaté en XFS"
                ((FORMATTED++))
            else
                log_error "  Échec formatage"
                ((FAILED_MOUNT++))
                continue
            fi
        fi
        
        # Créer le point de montage
        log_info "  Création du point de montage ${mount_path}..."
        ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
            "mkdir -p ${mount_path}" &>/dev/null || true
        
        # Monter le volume
        log_info "  Montage de ${device} sur ${mount_path}..."
        if ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
            "mount ${device} ${mount_path}" &>/dev/null; then
            log_success "  Volume monté"
            ((MOUNTED++))
            
            # Ajouter au fstab
            log_info "  Ajout au fstab..."
            uuid=$(ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
                "blkid -s UUID -o value ${device}" 2>/dev/null || echo "")
            
            if [[ -n "${uuid}" ]]; then
                # Vérifier si déjà dans fstab
                if ! ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
                    "grep -q '${mount_path}' /etc/fstab" &>/dev/null; then
                    ssh ${SSH_OPTS} -i "${SSH_KEY}" "root@${server_ip}" \
                        "echo 'UUID=${uuid} ${mount_path} xfs defaults,noatime 0 2' >> /etc/fstab" &>/dev/null
                    log_success "  Ajouté au fstab"
                else
                    log_info "  Déjà dans fstab"
                fi
            fi
        else
            log_error "  Échec montage"
            ((FAILED_MOUNT++))
        fi
    fi
    
    echo ""
done

# ============================================================
# RÉSUMÉ FINAL
# ============================================================
echo "=============================================================="
echo " RÉSUMÉ"
echo "=============================================================="
echo ""
log_info "Volumes attachés: ${ATTACHED}"
log_info "Volumes déjà attachés: ${ALREADY_ATTACHED}"
log_info "Volumes formatés: ${FORMATTED}"
log_info "Volumes montés: ${MOUNTED}"
log_info "Volumes déjà montés: ${ALREADY_MOUNTED}"
[[ ${FAILED_ATTACH} -gt 0 ]] && log_warning "Échecs d'attachement: ${FAILED_ATTACH}"
[[ ${FAILED_MOUNT} -gt 0 ]] && log_warning "Échecs de montage: ${FAILED_MOUNT}"
echo ""

if [[ ${FAILED_ATTACH} -eq 0 ]] && [[ ${FAILED_MOUNT} -eq 0 ]]; then
    log_success "Tous les volumes ont été traités avec succès !"
    exit 0
else
    log_warning "Certains volumes ont échoué"
    exit 1
fi

