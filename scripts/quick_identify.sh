#!/bin/bash
# Script d'identification rapide pour install-01

echo "=============================================================="
echo " [KeyBuzz] Identification du serveur"
echo "=============================================================="
echo ""
echo "Hostname        : $(hostname)"
echo "Utilisateur     : $(whoami)"
echo "IP privée       : $(ip addr show | grep 'inet 10.0.0' | awk '{print $2}' | cut -d/ -f1 | head -1)"
echo "OS              : $(lsb_release -d 2>/dev/null | cut -f2 || grep PRETTY_NAME /etc/os-release | cut -d'"' -f2)"
echo "Kernel          : $(uname -r)"
echo "Uptime          : $(uptime -p 2>/dev/null || uptime)"
echo ""
echo "Docker          : $(docker --version 2>/dev/null || echo 'Non installé')"
echo "Git             : $(git --version 2>/dev/null || echo 'Non installé')"
echo ""
echo "Swap            : $(swapon --summary 2>/dev/null | grep -q . && echo '⚠️ ACTIVÉ' || echo '✅ Désactivé')"
echo ""
echo "Répertoire KeyBuzz : $(test -d /opt/keybuzz-installer && echo '✅ /opt/keybuzz-installer existe' || echo '❌ N\'existe pas')"
echo ""
echo "=============================================================="


