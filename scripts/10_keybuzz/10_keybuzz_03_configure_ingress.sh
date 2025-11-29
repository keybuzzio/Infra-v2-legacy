#!/usr/bin/env bash
#
# 10_keybuzz_03_configure_ingress.sh - Configuration Ingress KeyBuzz
#
# Ce script configure les Ingress pour KeyBuzz API et Front selon Context.txt :
# - app.keybuzz.io → KeyBuzz Front
# - api.keybuzz.io → KeyBuzz API
#
# Usage:
#   ./10_keybuzz_03_configure_ingress.sh [servers.tsv]
#
# Prérequis:
#   - Module 9 installé (Ingress NGINX DaemonSet)
#   - Module 10 scripts 01-02 exécutés (API et Front déployés)
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
echo " [KeyBuzz] Module 10 - Configuration Ingress KeyBuzz"
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

# Vérifier que les services existent
log_info "Vérification des services KeyBuzz..."
if ! ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc keybuzz-api -n keybuzz" > /dev/null 2>&1; then
    log_error "Service keybuzz-api introuvable"
    log_error "Exécutez d'abord: ./10_keybuzz_01_deploy_daemonsets.sh"
    exit 1
fi

if ! ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc keybuzz-front -n keybuzz" > /dev/null 2>&1; then
    log_error "Service keybuzz-front introuvable"
    log_error "Exécutez d'abord: ./10_keybuzz_01_deploy_daemonsets.sh"
    exit 1
fi
log_success "Services KeyBuzz trouvés"

# Créer l'Ingress pour KeyBuzz Front (platform.keybuzz.io)
log_info "Création de l'Ingress pour KeyBuzz Front (platform.keybuzz.io)..."

INGRESS_FRONT_YAML=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keybuzz-front-ingress
  namespace: keybuzz
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  rules:
  - host: platform.keybuzz.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keybuzz-front
            port:
              number: 80
EOF
)

echo "${INGRESS_FRONT_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Ingress keybuzz-front-ingress créé (platform.keybuzz.io)"

# Créer l'Ingress pour KeyBuzz API (platform-api.keybuzz.io)
log_info "Création de l'Ingress pour KeyBuzz API (platform-api.keybuzz.io)..."

INGRESS_API_YAML=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keybuzz-api-ingress
  namespace: keybuzz
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  rules:
  - host: platform-api.keybuzz.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keybuzz-api
            port:
              number: 80
EOF
)

echo "${INGRESS_API_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Ingress keybuzz-api-ingress créé (platform-api.keybuzz.io)"

# Vérifier le statut
log_info "Vérification du statut des Ingress..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress -n keybuzz"

echo ""
echo "=============================================================="
log_success "✅ Ingress KeyBuzz configurés"
echo "=============================================================="
echo ""
log_info "Configuration:"
log_info "  - Frontend: platform.keybuzz.io → keybuzz-front"
log_info "  - API: platform-api.keybuzz.io → keybuzz-api"
log_info "  - TLS: Géré par LB Hetzner (SSL termination)"
echo ""
log_warning "⚠️  IMPORTANT: Configurer les DNS pour pointer vers les LB Hetzner:"
log_info "  - platform.keybuzz.io → IP LB Hetzner (10.0.0.5 ou 10.0.0.6)"
log_info "  - platform-api.keybuzz.io → IP LB Hetzner (10.0.0.5 ou 10.0.0.6)"
echo ""
log_info "Prochaine étape: ./10_keybuzz_03_tests.sh"
echo ""

