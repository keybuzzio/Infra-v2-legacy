#!/bin/bash
#
# check_module2_recap.sh - Récapitulatif complet de l'état du Module 2
#
# Usage: ./check_module2_recap.sh

export HCLOUD_TOKEN='PvaKOohQayiL8MpTsPpkzDMdWqRLauDErV4NTCwUKF333VeZ5wDDqFbKZb1q7HrE'

TSV_FILE="/opt/keybuzz-installer/servers.tsv"
LOG_FILE="/tmp/module2_installation_.log"

echo "=============================================================="
echo " Récapitulatif Module 2 - État par serveur"
echo "=============================================================="
echo ""

# Détecter la clé SSH
SSH_KEY_OPTS=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY_OPTS="-i ${HOME}/.ssh/id_rsa"
fi

# Fonction pour vérifier si Module 2 est appliqué
check_module2() {
    local HOSTNAME="$1"
    local IP="$2"
    
    # Vérifier dans le log
    if grep -q "✅ Serveur ${HOSTNAME}" "${LOG_FILE}" 2>/dev/null; then
        echo "✅"
        return 0
    fi
    
    # Vérifier sur le serveur (Docker installé = Module 2 appliqué)
    if ssh ${SSH_KEY_OPTS} -o ConnectTimeout=5 -o BatchMode=yes -o StrictHostKeyChecking=accept-new root@"${IP}" "command -v docker >/dev/null 2>&1" 2>/dev/null; then
        echo "✅"
        return 0
    else
        echo "❌"
        return 1
    fi
}

# Lister tous les serveurs Hetzner
HETZNER_SERVERS=$(hcloud server list -o columns=name,ipv4,private_net | tail -n +2)

# Traiter chaque serveur du TSV
echo "📋 Serveurs dans servers.tsv (prod):"
echo ""
printf "%-25s %-15s %-10s %-30s\n" "HOSTNAME" "IP PRIVÉE" "STATUS" "ROLE/SUBROLE"
echo "---------------------------------------------------------------------------------------------------"

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]] || [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ -z "${IP_PRIVEE}" ]]; then
        continue
    fi
    
    STATUS=$(check_module2 "${HOSTNAME}" "${IP_PRIVEE}")
    printf "%-25s %-15s %-10s %-30s\n" "${HOSTNAME}" "${IP_PRIVEE}" "${STATUS}" "${ROLE}/${SUBROLE}"
done
exec 3<&-

echo ""
echo "=============================================================="
echo "📊 Serveurs chez Hetzner mais absents de servers.tsv:"
echo "=============================================================="

# Trouver les serveurs Hetzner non dans TSV
HETZNER_NAMES=$(echo "${HETZNER_SERVERS}" | awk '{print $1}' | sort)
TSV_NAMES=$(grep '^prod' "${TSV_FILE}" | cut -f3 | sort)

for server in ${HETZNER_NAMES}; do
    if ! echo "${TSV_NAMES}" | grep -q "^${server}$"; then
        IP_LINE=$(echo "${HETZNER_SERVERS}" | grep "^${server}")
        PRIVATE_IP=$(echo "${IP_LINE}" | awk '{print $3}' | sed 's/(keybuzz)//' | tr -d ' ' | cut -d'/' -f1)
        if [[ -n "${PRIVATE_IP}" ]] && [[ "${PRIVATE_IP}" != "-" ]]; then
            STATUS=$(check_module2 "${server}" "${PRIVATE_IP}" 2>/dev/null || echo "❌")
            printf "%-25s %-15s %-10s %-30s\n" "${server}" "${PRIVATE_IP}" "${STATUS}" "(absent de servers.tsv)"
        else
            printf "%-25s %-15s %-10s %-30s\n" "${server}" "N/A" "❌" "(absent de servers.tsv, pas d'IP privée)"
        fi
    fi
done

echo ""
echo "=============================================================="
echo "✅ = Module 2 appliqué | ❌ = Module 2 non appliqué"
echo "=============================================================="

