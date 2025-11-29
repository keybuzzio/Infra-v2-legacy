#!/usr/bin/env bash
#
# 11_n8n_02_configure_ingress.sh - Configuration Ingress n8n
#
# Ce script configure l'Ingress pour n8n selon Context.txt :
# - n8n.keybuzz.io → n8n Service
#
# Usage:
#   ./11_n8n_02_configure_ingress.sh [servers.tsv]
#
# Prérequis:
#   - Module 9 installé (Ingress NGINX DaemonSet)
#   - Module 11 script 01 exécuté (n8n déployé)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
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
echo " [KeyBuzz] Module 11 - Configuration Ingress n8n"
echo "=============================================================="
echo ""

# Trouver le premier master K3s
declare -a K3S_MASTER_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ "${SUBROLE}" == "master" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        K3S_MASTER_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#K3S_MASTER_IPS[@]} -lt 1 ]]; then
    log_error "Aucun master K3s trouvé"
    exit 1
fi

MASTER_IP="${K3S_MASTER_IPS[0]}"
log_info "Utilisation du master: ${MASTER_IP}"

# Vérifier que le service existe
log_info "Vérification du service n8n..."
if ! ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc n8n -n n8n" > /dev/null 2>&1; then
    log_error "Service n8n introuvable"
    log_error "Exécutez d'abord: ./11_n8n_01_deploy.sh"
    exit 1
fi
log_success "Service n8n trouvé"

# Créer l'Ingress pour n8n (n8n.keybuzz.io)
log_info "Création de l'Ingress pour n8n (n8n.keybuzz.io)..."

INGRESS_YAML=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: n8n-ingress
  namespace: n8n
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "600"
spec:
  ingressClassName: nginx
  rules:
  - host: n8n.keybuzz.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: n8n
            port:
              number: 80
EOF
)

echo "${INGRESS_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Ingress n8n-ingress créé (n8n.keybuzz.io)"

# Vérifier le statut
log_info "Vérification du statut de l'Ingress..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress -n n8n"

echo ""
echo "=============================================================="
log_success "✅ Ingress n8n configuré"
echo "=============================================================="
echo ""
log_info "Configuration:"
log_info "  - Frontend: n8n.keybuzz.io → n8n"
log_info "  - TLS: Géré par LB Hetzner (SSL termination)"
echo ""
log_warning "⚠️  IMPORTANT: Configurer les DNS pour pointer vers les LB Hetzner:"
log_info "  - n8n.keybuzz.io → IP LB Hetzner (10.0.0.5 ou 10.0.0.6)"
echo ""
log_info "Prochaine étape: ./11_n8n_03_tests.sh"
echo ""

