#!/bin/bash
# deploy_ssh_worker_04_05.sh
# Script pour déployer la clé SSH d'install-01 sur worker-04 et worker-05
#
# Usage:
#   bash 00_deploy_ssh_worker_04_05.sh
#

set -uo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Fonctions d'affichage
log() { echo -e "${CYAN}[INFO]${NC} $1"; }
ok() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
ko() { echo -e "${RED}[FAIL]${NC} $1"; }
section() { echo -e "\n${BLUE}════════════════════════════════════════════════════════════════════${NC}"; echo -e "${BLUE}$1${NC}"; echo -e "${BLUE}════════════════════════════════════════════════════════════════════${NC}\n"; }

# Configuration
INSTALL_01_IP="91.98.128.153"
WORKER_04_IP="91.98.200.38"
WORKER_05_IP="188.245.45.242"
SSH_PORT=22

section "Déploiement SSH sur worker-04 et worker-05"

log "Ce script va déployer la clé SSH d'install-01 sur :"
log "  - k8s-worker-04 ($WORKER_04_IP)"
log "  - k8s-worker-05 ($WORKER_05_IP)"
echo ""
warn "IMPORTANT: Ces serveurs viennent d'être rebuildés"
warn "Vous devrez peut-être entrer le mot de passe root temporaire"
echo ""

# Récupérer la clé publique d'install-01
log "Récupération de la clé SSH d'install-01..."
INSTALL_KEY=$(ssh root@$INSTALL_01_IP "cat /root/.ssh/id_ed25519.pub" 2>/dev/null)

if [ -z "$INSTALL_KEY" ]; then
    ko "Impossible de récupérer la clé SSH d'install-01"
    exit 1
fi

ok "Clé SSH récupérée"
log "Fingerprint: $(echo "$INSTALL_KEY" | awk '{print $2}' | cut -c1-20)..."
echo ""

# Fonction pour déployer la clé sur un serveur
deploy_key() {
    local server_ip=$1
    local server_name=$2
    
    log "Déploiement sur $server_name ($server_ip)..."
    
    # Créer le répertoire .ssh
    ssh -o StrictHostKeyChecking=no root@"$server_ip" "mkdir -p /root/.ssh && chmod 700 /root/.ssh" 2>/dev/null || {
        warn "Connexion SSH échouée, tentative avec mot de passe..."
        echo ""
        warn "Vous devrez entrer le mot de passe root pour $server_name"
        echo "Le mot de passe temporaire a été envoyé par Hetzner lors du rebuild"
        echo ""
        read -p "Appuyez sur Entrée pour continuer..."
        
        # Essayer avec sshpass si disponible, sinon demander manuellement
        if command -v sshpass &> /dev/null; then
            read -sp "Mot de passe root pour $server_name: " PASSWORD
            echo ""
            sshpass -p "$PASSWORD" ssh -o StrictHostKeyChecking=no root@"$server_ip" "mkdir -p /root/.ssh && chmod 700 /root/.ssh" 2>/dev/null || {
                ko "Échec connexion avec mot de passe"
                return 1
            }
        else
            ssh -o StrictHostKeyChecking=no root@"$server_ip" "mkdir -p /root/.ssh && chmod 700 /root/.ssh" || {
                ko "Échec connexion. Installez sshpass ou configurez la clé SSH manuellement."
                return 1
            }
        fi
    }
    
    # Vérifier si la clé existe déjà
    if ssh -o StrictHostKeyChecking=no root@"$server_ip" "grep -q '$(echo "$INSTALL_KEY" | awk '{print $2}')' /root/.ssh/authorized_keys 2>/dev/null"; then
        warn "Clé déjà présente sur $server_name"
        return 0
    fi
    
    # Ajouter la clé
    echo "$INSTALL_KEY" | ssh -o StrictHostKeyChecking=no root@"$server_ip" "cat >> /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys && echo OK" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        ok "Clé SSH déployée sur $server_name"
        
        # Tester la connexion
        if ssh -o StrictHostKeyChecking=no -o BatchMode=yes root@"$server_ip" "echo 'Connexion OK'" &>/dev/null; then
            ok "Connexion testée avec succès sur $server_name"
            return 0
        else
            warn "Clé déployée mais connexion test échoué (peut être normal)"
            return 0
        fi
    else
        ko "Échec déploiement de la clé sur $server_name"
        return 1
    fi
}

# Déployer sur worker-04
deploy_key "$WORKER_04_IP" "k8s-worker-04"
WORKER_04_RESULT=$?

echo ""

# Déployer sur worker-05
deploy_key "$WORKER_05_IP" "k8s-worker-05"
WORKER_05_RESULT=$?

echo ""
section "Résumé"

if [ $WORKER_04_RESULT -eq 0 ]; then
    ok "k8s-worker-04 : Clé SSH déployée"
else
    ko "k8s-worker-04 : Échec"
fi

if [ $WORKER_05_RESULT -eq 0 ]; then
    ok "k8s-worker-05 : Clé SSH déployée"
else
    ko "k8s-worker-05 : Échec"
fi

echo ""

if [ $WORKER_04_RESULT -eq 0 ] && [ $WORKER_05_RESULT -eq 0 ]; then
    ok "Toutes les clés SSH ont été déployées avec succès"
    log "Vous pouvez maintenant relancer le script de déploiement SSH complet"
else
    warn "Certaines clés n'ont pas pu être déployées"
    log "Vérifiez les mots de passe root ou configurez manuellement"
fi

