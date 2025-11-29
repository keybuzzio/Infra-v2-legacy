#!/usr/bin/env bash
#
# 00_check_servers_status.sh - Vérifier l'état des serveurs avant Module 2
#
# Usage:
#   ./00_check_servers_status.sh [servers.tsv]

set -euo pipefail

TSV_FILE="${1:-/opt/keybuzz-installer/servers.tsv}"

if [[ ! -f "${TSV_FILE}" ]]; then
    echo "❌ Fichier TSV introuvable: ${TSV_FILE}"
    exit 1
fi

echo "=============================================================="
echo " [KeyBuzz] Vérification de l'état des serveurs"
echo "=============================================================="
echo ""

# Détecter la clé SSH
SSH_KEY=""
if [[ -f "${HOME}/.ssh/keybuzz_infra" ]]; then
    SSH_KEY="${HOME}/.ssh/keybuzz_infra"
elif [[ -f "${HOME}/.ssh/id_ed25519" ]]; then
    SSH_KEY="${HOME}/.ssh/id_ed25519"
elif [[ -f "${HOME}/.ssh/id_rsa" ]]; then
    SSH_KEY="${HOME}/.ssh/id_rsa"
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=5 -o ConnectionAttempts=2"
if [[ -n "${SSH_KEY}" ]]; then
    SSH_OPTS="${SSH_OPTS} -i ${SSH_KEY}"
fi

# Compter les serveurs
TOTAL=0
ACCESSIBLE=0
MODULE2_OK=0
MODULE2_PARTIAL=0
MODULE2_MISSING=0

echo "Vérification des serveurs..."
echo ""

# Lire le fichier TSV (ignorer les lignes de commentaire et header)
while IFS=$'\t' read -r env ip_pub hostname ip_priv fqdn user_ssh pool role subrole docker_stack core notes; do
    # Ignorer les lignes vides, commentaires et header
    [[ -z "${hostname}" ]] && continue
    [[ "${hostname}" == "HOSTNAME" ]] && continue
    [[ "${hostname}" =~ ^#.* ]] && continue
    
    # Ignorer install-01
    [[ "${hostname}" == "install-01" ]] && continue
    
    ((TOTAL++))
    
    # Vérifier l'accessibilité SSH
    if ssh ${SSH_OPTS} root@"${ip_priv}" "echo 'OK'" &>/dev/null; then
        ((ACCESSIBLE++))
        
        # Vérifier l'état du Module 2
        MODULE2_STATUS=$(ssh ${SSH_OPTS} root@"${ip_priv}" "
            # Vérifier plusieurs indicateurs du Module 2
            SWAP_DISABLED=\$(swapon --summary 2>/dev/null | wc -l)
            DOCKER_INSTALLED=\$(command -v docker &>/dev/null && echo 1 || echo 0)
            UFW_ACTIVE=\$(ufw status | grep -q 'Status: active' && echo 1 || echo 0)
            DNS_CONFIGURED=\$(grep -q 'nameserver 1.1.1.1' /etc/resolv.conf 2>/dev/null && echo 1 || echo 0)
            
            # Compter les points
            POINTS=0
            [[ \$SWAP_DISABLED -eq 0 ]] && ((POINTS++))
            [[ \$DOCKER_INSTALLED -eq 1 ]] && ((POINTS++))
            [[ \$UFW_ACTIVE -eq 1 ]] && ((POINTS++))
            [[ \$DNS_CONFIGURED -eq 1 ]] && ((POINTS++))
            
            echo \$POINTS
        " 2>/dev/null || echo "0")
        
        if [[ "${MODULE2_STATUS}" == "4" ]]; then
            ((MODULE2_OK++))
            STATUS="✅ Module 2 OK"
        elif [[ "${MODULE2_STATUS}" -ge "2" ]]; then
            ((MODULE2_PARTIAL++))
            STATUS="⚠️  Module 2 partiel (${MODULE2_STATUS}/4)"
        else
            ((MODULE2_MISSING++))
            STATUS="❌ Module 2 manquant"
        fi
        
        printf "%-20s %-15s %s\n" "${hostname}" "${ip_priv}" "${STATUS}"
    else
        printf "%-20s %-15s %s\n" "${hostname}" "${ip_priv}" "❌ Inaccessible SSH"
    fi
done < <(grep -v '^#' "${TSV_FILE}" | grep -v '^$' | tail -n +2)

echo ""
echo "=============================================================="
echo "Résumé :"
echo "  Total serveurs vérifiés : ${TOTAL}"
echo "  Accessibles SSH         : ${ACCESSIBLE}"
echo "  Module 2 complet        : ${MODULE2_OK}"
echo "  Module 2 partiel        : ${MODULE2_PARTIAL}"
echo "  Module 2 manquant       : ${MODULE2_MISSING}"
echo "=============================================================="
echo ""

if [[ ${MODULE2_MISSING} -gt 0 ]] || [[ ${MODULE2_PARTIAL} -gt 0 ]]; then
    echo "⚠️  Action recommandée : Relancer le Module 2"
    echo ""
    echo "   cd /opt/keybuzz-installer/scripts/02_base_os_and_security"
    echo "   ./apply_base_os_to_all.sh ../../servers.tsv"
    echo ""
else
    echo "✅ Tous les serveurs ont le Module 2 appliqué"
    echo ""
fi

