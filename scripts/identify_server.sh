#!/usr/bin/env bash
#
# identify_server.sh - Identifie et affiche les informations du serveur
#
# Usage:
#   ./identify_server.sh
#
# Affiche toutes les informations pertinentes pour identifier le serveur

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Identification du serveur"
echo "=============================================================="
echo ""

# Informations de base
echo "📋 Informations système :"
echo "------------------------"
echo "Hostname        : $(hostname)"
echo "FQDN            : $(hostname -f 2>/dev/null || echo 'N/A')"
echo "Utilisateur     : $(whoami)"
echo "UID             : $(id -u)"
echo "GID             : $(id -g)"
echo ""

# Informations réseau
echo "🌐 Informations réseau :"
echo "------------------------"
echo "IP publique     : $(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null || echo 'N/A')"
echo "IP privée       : $(ip addr show | grep 'inet 10.0.0' | awk '{print $2}' | cut -d/ -f1 | head -1 || echo 'N/A')"
echo "Toutes les IPs  :"
ip addr show | grep 'inet ' | awk '{print "  - " $2}' || echo "  N/A"
echo ""

# Informations OS
echo "💻 Informations OS :"
echo "------------------------"
if command -v lsb_release >/dev/null 2>&1; then
    echo "Distribution    : $(lsb_release -d | cut -f2)"
    echo "Version         : $(lsb_release -r | cut -f2)"
    echo "Code name       : $(lsb_release -c | cut -f2)"
elif [[ -f /etc/os-release ]]; then
    echo "Distribution    : $(grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
    echo "Version         : $(grep VERSION_ID /etc/os-release | cut -d'"' -f2)"
fi
echo "Kernel          : $(uname -r)"
echo "Architecture    : $(uname -m)"
echo "Uptime          : $(uptime -p 2>/dev/null || uptime | awk -F'up ' '{print $2}' | awk -F',' '{print $1}')"
echo "Date système    : $(date)"
echo "Timezone        : $(timedatectl show -p Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo 'N/A')"
echo ""

# Informations matérielles
echo "🖥️  Informations matérielles :"
echo "------------------------"
echo "CPU             : $(nproc) cores"
if command -v lscpu >/dev/null 2>&1; then
    echo "CPU Model       : $(lscpu | grep 'Model name' | cut -d':' -f2 | xargs)"
fi
echo "RAM totale      : $(free -h | grep Mem | awk '{print $2}')"
echo "RAM utilisée    : $(free -h | grep Mem | awk '{print $3}')"
echo "RAM disponible  : $(free -h | grep Mem | awk '{print $7}')"
echo "Swap            : $(free -h | grep Swap | awk '{print $2}')"
if swapon --summary 2>/dev/null | grep -q .; then
    echo "  ⚠️  SWAP ACTIVÉ (doit être désactivé pour KeyBuzz)"
else
    echo "  ✅ Swap désactivé"
fi
echo "Disque /        : $(df -h / | tail -1 | awk '{print $4 " libre sur " $2}')"
echo ""

# Informations logiciels
echo "🔧 Logiciels installés :"
echo "------------------------"
if command -v docker >/dev/null 2>&1; then
    echo "Docker          : ✅ $(docker --version | cut -d' ' -f3 | tr -d ',')"
    echo "  Containers   : $(docker ps -q | wc -l) running"
else
    echo "Docker          : ❌ Non installé"
fi

if command -v git >/dev/null 2>&1; then
    echo "Git             : ✅ $(git --version | cut -d' ' -f3)"
else
    echo "Git             : ❌ Non installé"
fi

if command -v curl >/dev/null 2>&1; then
    echo "cURL            : ✅ $(curl --version | head -1 | cut -d' ' -f2)"
else
    echo "cURL            : ❌ Non installé"
fi

if command -v ufw >/dev/null 2>&1; then
    UFW_STATUS=$(ufw status | head -1 | awk '{print $2}')
    echo "UFW             : ✅ $UFW_STATUS"
else
    echo "UFW             : ❌ Non installé"
fi
echo ""

# Vérifications KeyBuzz
echo "✅ Vérifications KeyBuzz :"
echo "------------------------"
echo -n "Swap désactivé  : "
if swapon --summary 2>/dev/null | grep -q .; then
    echo "❌ NON (doit être désactivé)"
else
    echo "✅ OUI"
fi

echo -n "Docker installé  : "
if command -v docker >/dev/null 2>&1; then
    echo "✅ OUI"
else
    echo "❌ NON"
fi

echo -n "Git installé     : "
if command -v git >/dev/null 2>&1; then
    echo "✅ OUI"
else
    echo "❌ NON"
fi

echo -n "Réseau privé     : "
if ip addr show | grep -q 'inet 10.0.0'; then
    echo "✅ OUI ($(ip addr show | grep 'inet 10.0.0' | awk '{print $2}' | cut -d/ -f1 | head -1))"
else
    echo "❌ NON"
fi

echo -n "DNS configuré     : "
if grep -q "1.1.1.1\|8.8.8.8" /etc/resolv.conf 2>/dev/null; then
    echo "✅ OUI"
else
    echo "⚠️  À vérifier"
fi
echo ""

# Répertoires KeyBuzz
echo "📁 Répertoires KeyBuzz :"
echo "------------------------"
if [[ -d "/opt/keybuzz-installer" ]]; then
    echo "/opt/keybuzz-installer : ✅ Existe"
    echo "  Contenu :"
    ls -la /opt/keybuzz-installer 2>/dev/null | head -10 || echo "  (vide ou inaccessible)"
else
    echo "/opt/keybuzz-installer : ❌ N'existe pas"
fi
echo ""

# Dernière vérification
echo "🎯 Identification finale :"
echo "------------------------"
EXPECTED_HOSTNAME="install-01"
CURRENT_HOSTNAME=$(hostname)

if [[ "${CURRENT_HOSTNAME}" == "${EXPECTED_HOSTNAME}" ]] || [[ "${CURRENT_HOSTNAME}" == "${EXPECTED_HOSTNAME}.keybuzz.io" ]]; then
    echo "✅ Serveur identifié : ${CURRENT_HOSTNAME}"
    echo "   C'est bien install-01 (serveur d'orchestration KeyBuzz)"
elif [[ "${CURRENT_HOSTNAME}" == *"install"* ]]; then
    echo "⚠️  Serveur probable : ${CURRENT_HOSTNAME}"
    echo "   Semble être install-01 mais le hostname ne correspond pas exactement"
else
    echo "❌ Attention : ${CURRENT_HOSTNAME}"
    echo "   Ce serveur ne semble pas être install-01"
fi
echo ""

echo "=============================================================="
echo "✅ Identification terminée"
echo "=============================================================="


