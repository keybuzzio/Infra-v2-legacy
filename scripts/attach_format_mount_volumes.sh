#!/usr/bin/env bash
set -uo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SERVERS_TSV="${SERVERS_TSV:-/opt/keybuzz-installer/servers.tsv}"
LOG_DIR="/tmp/volumes_format_$(date +%Y%m%d_%H%M%S)"

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[OK]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if ! command -v hcloud >/dev/null 2>&1; then
    log_error "hcloud CLI not found"
    exit 1
fi

if [[ -z "${HCLOUD_TOKEN:-}" ]]; then
    log_error "HCLOUD_TOKEN not set"
    exit 1
fi

if [[ ! -f "$SERVERS_TSV" ]]; then
    log_error "servers.tsv not found"
    exit 1
fi

mkdir -p "$LOG_DIR"

clear
echo -e "${CYAN}╔═══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║   Attachement, Formatage XFS et Montage des Volumes  ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════╝${NC}"
echo

log_info "Récupération de la liste des volumes..."
VOLUMES_JSON=$(hcloud volume list --output json)

declare -A VOLUME_TO_SERVER
declare -A VOLUME_TO_SIZE
declare -A SERVER_TO_IP

while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES || [[ -n "$ENV" ]]; do
    if [[ "$ENV" =~ ^#.*$ ]] || [[ "$ENV" == "ENV" ]] || [[ -z "$ENV" ]] || [[ -z "$HOSTNAME" ]]; then
        continue
    fi
    SERVER_TO_IP["$HOSTNAME"]="$IP_PRIVEE"
done < "$SERVERS_TSV"

VOLUME_COUNT=0
while IFS='|' read -r vol_id vol_name vol_size; do
    server_name="${vol_name#vol-}"
    if [[ -n "${SERVER_TO_IP[$server_name]:-}" ]]; then
        VOLUME_TO_SERVER["$vol_id"]="$server_name"
        VOLUME_TO_SIZE["$vol_id"]="$vol_size"
        ((VOLUME_COUNT++))
        log_info "Volume $vol_name -> Serveur $server_name"
    fi
done < <(echo "$VOLUMES_JSON" | jq -r '.[] | "\(.id)|\(.name)|\(.size)"')

echo
log_success "$VOLUME_COUNT volumes à traiter"
echo

process_volume() {
    local vol_id="$1"
    local vol_name="$2"
    local server_name="$3"
    local server_ip="$4"
    local vol_size="$5"
    local log_file="$LOG_DIR/${server_name}_${vol_name}.log"
    
    echo "[$(date +%H:%M:%S)] Début: $vol_name sur $server_name" > "$log_file"
    
    if ! hcloud volume attach "$vol_id" --server "$server_name" >> "$log_file" 2>&1; then
        echo "ERROR: Échec attachement" >> "$log_file"
        return 1
    fi
    
    sleep 3
    
    mount_path="/opt/keybuzz/${server_name#*-}/data"
    if [[ "$server_name" =~ ^db- ]]; then
        mount_path="/opt/keybuzz/postgres/data"
    elif [[ "$server_name" =~ ^redis- ]]; then
        mount_path="/opt/keybuzz/redis/data"
    elif [[ "$server_name" =~ ^queue- ]]; then
        mount_path="/opt/keybuzz/rabbitmq/data"
    elif [[ "$server_name" =~ ^minio- ]]; then
        mount_path="/opt/keybuzz/minio/data"
    elif [[ "$server_name" =~ ^haproxy- ]]; then
        mount_path="/opt/keybuzz/haproxy/data"
    fi
    
    if ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "root@${server_ip}" bash -s "$vol_size" "$mount_path" <<'FORMAT_SCRIPT' >> "$log_file" 2>&1; then
        VOL_SIZE="$1"
        MOUNT_PATH="$2"
        
        if ! command -v mkfs.xfs >/dev/null 2>&1; then
            apt-get update -qq && apt-get install -y -qq xfsprogs
        fi
        
        mkdir -p "$MOUNT_PATH"
        sleep 2
        
        DEVICE=""
        TARGET_SIZE=$((VOL_SIZE * 1000000000))
        TOLERANCE=$((TARGET_SIZE / 10))
        
        for dev in /dev/disk/by-id/scsi-* /dev/sd{b..z} /dev/vd{b..z}; do
            [ -b "$dev" ] || continue
            DEV_SIZE=$(lsblk -b -n -o SIZE "$dev" 2>/dev/null | head -1)
            [ -z "$DEV_SIZE" ] && continue
            if ! mount | grep -q "$dev"; then
                if [ $DEV_SIZE -gt $((TARGET_SIZE - TOLERANCE)) ] && [ $DEV_SIZE -lt $((TARGET_SIZE + TOLERANCE)) ]; then
                    DEVICE=$(readlink -f "$dev" 2>/dev/null || echo "$dev")
                    break
                fi
            fi
        done
        
        if [[ -z "$DEVICE" ]]; then
            echo "ERROR: Device non trouvé"
            exit 1
        fi
        
        echo "Device: $DEVICE"
        wipefs -af "$DEVICE" 2>/dev/null
        mkfs.xfs -f -m crc=1,finobt=1 "$DEVICE" || { echo "ERROR: mkfs.xfs failed"; exit 1; }
        
        mount -t xfs -o noatime,nodiratime,logbufs=8,logbsize=256k "$DEVICE" "$MOUNT_PATH" || { echo "ERROR: mount failed"; exit 1; }
        
        UUID=$(blkid -s UUID -o value "$DEVICE")
        if ! grep -q "$UUID" /etc/fstab; then
            echo "UUID=$UUID $MOUNT_PATH xfs defaults,noatime,nodiratime,logbufs=8,logbsize=256k,nofail 0 2" >> /etc/fstab
        fi
        
        chown -R 999:999 "$MOUNT_PATH" 2>/dev/null || true
        chmod 700 "$MOUNT_PATH" 2>/dev/null || true
FORMAT_SCRIPT
        return 0
    else
        echo "ERROR: Échec formatage/montage" >> "$log_file"
        return 1
    fi
}

export -f process_volume
export LOG_DIR SERVER_TO_IP VOLUME_TO_SERVER VOLUME_TO_SIZE

log_info "Traitement en parallèle..."
echo

PIDS=()
FAILED=()
SUCCESS=0

for vol_id in "${!VOLUME_TO_SERVER[@]}"; do
    server_name="${VOLUME_TO_SERVER[$vol_id]}"
    server_ip="${SERVER_TO_IP[$server_name]}"
    vol_size="${VOLUME_TO_SIZE[$vol_id]}"
    vol_name="vol-${server_name}"
    
    echo -n "  $vol_name -> $server_name... "
    process_volume "$vol_id" "$vol_name" "$server_name" "$server_ip" "$vol_size" &
    pid=$!
    PIDS+=($pid)
    echo -e "${GREEN}[PID: $pid]${NC}"
    sleep 0.3
done

echo
log_info "Attente de la fin..."
wait

for i in "${!PIDS[@]}"; do
    pid="${PIDS[$i]}"
    if wait "$pid" 2>/dev/null; then
        ((SUCCESS++))
    else
        FAILED+=("PID $pid")
    fi
done

echo
echo -e "${CYAN}════════════════════════════════════════${NC}"
echo "  Succès: $SUCCESS / $VOLUME_COUNT"
echo "  Échecs: ${#FAILED[@]}"
echo "  Logs: $LOG_DIR"
echo

[[ ${#FAILED[@]} -eq 0 ]] && exit 0 || exit 1

