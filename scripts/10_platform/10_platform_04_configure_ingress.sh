#!/usr/bin/env bash
#
# 10_platform_04_configure_ingress.sh - Configuration Ingress Platform KeyBuzz
#
# Ce script configure les Ingress pour les 3 domaines :
# - platform.keybuzz.io → keybuzz-ui
# - platform-api.keybuzz.io → keybuzz-api
# - my.keybuzz.io → keybuzz-my-ui
#
# Usage:
#   ./10_platform_04_configure_ingress.sh [servers.tsv]
#
# Prérequis:
#   - Module 9 installé (Ingress NGINX DaemonSet)
#   - Module 10 scripts 01-03 exécutés (API, UI, My déployés)
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
echo " [KeyBuzz] Module 10 Platform - Configuration Ingress"
echo "=============================================================="
echo ""
log_info "Configuration des Ingress pour les 3 domaines"
log_info "Namespace: keybuzz"
log_info "IngressClass: nginx"
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

# Vérifier la connectivité au cluster
log_info "Vérification de la connectivité au cluster K3s..."
if ! ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes" > /dev/null 2>&1; then
    log_error "Impossible de se connecter au cluster K3s"
    exit 1
fi
log_success "Cluster K3s accessible"

# Vérifier que l'IngressClass nginx existe
log_info "Vérification de l'IngressClass nginx..."
if ! ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingressclass nginx" > /dev/null 2>&1; then
    log_warning "IngressClass nginx n'existe pas, création..."
    INGRESS_CLASS_YAML=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: nginx
spec:
  controller: k8s.io/ingress-nginx
EOF
)
    echo "${INGRESS_CLASS_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
    log_success "IngressClass nginx créé"
else
    log_success "IngressClass nginx existe"
fi

# Créer l'Ingress pour platform-api.keybuzz.io
log_info "Création de l'Ingress pour platform-api.keybuzz.io..."

INGRESS_API_YAML=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: platform-api-ingress
  namespace: keybuzz
  labels:
    app: platform-api
    component: backend
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "300"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "300"
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
              number: 8080
EOF
)

echo "${INGRESS_API_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Ingress platform-api-ingress créé"

# Créer l'Ingress pour platform.keybuzz.io
log_info "Création de l'Ingress pour platform.keybuzz.io..."

INGRESS_UI_YAML=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: platform-ui-ingress
  namespace: keybuzz
  labels:
    app: platform
    component: frontend
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
            name: keybuzz-ui
            port:
              number: 80
EOF
)

echo "${INGRESS_UI_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Ingress platform-ui-ingress créé"

# Créer l'Ingress pour my.keybuzz.io
log_info "Création de l'Ingress pour my.keybuzz.io..."

INGRESS_MY_YAML=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: platform-my-ingress
  namespace: keybuzz
  labels:
    app: my
    component: frontend
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
spec:
  ingressClassName: nginx
  rules:
  - host: my.keybuzz.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: keybuzz-my-ui
            port:
              number: 80
EOF
)

echo "${INGRESS_MY_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Ingress platform-my-ingress créé"

# Attendre un peu pour que les Ingress soient propagés
log_info "Attente de la propagation des Ingress..."
sleep 5

# Vérifier le statut
log_info "Vérification du statut des Ingress..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress -n keybuzz"

echo ""
echo "=============================================================="
log_success "✅ Ingress configurés avec succès"
echo "=============================================================="
echo ""
log_info "Ingress créés:"
log_info "  - platform-api.keybuzz.io → keybuzz-api:8080"
log_info "  - platform.keybuzz.io → keybuzz-ui:80"
log_info "  - my.keybuzz.io → keybuzz-my-ui:80"
echo ""
log_warning "⚠️  Actions requises:"
log_info "  1. Configurer les DNS pour pointer vers les Load Balancers Hetzner"
log_info "  2. Vérifier les certificats TLS sur les Load Balancers"
log_info "  3. Tester l'accès via les domaines configurés"
echo ""
log_info "Prochaine étape: ./validate_module10_platform.sh"
echo ""

