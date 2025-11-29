#!/usr/bin/env bash
#
# 10_platform_02_deploy_ui.sh - Déploiement Platform UI (platform.keybuzz.io)
#
# Ce script déploie l'UI principale KeyBuzz avec Deployment + Service ClusterIP
#
# Usage:
#   ./10_platform_02_deploy_ui.sh [servers.tsv]
#
# Prérequis:
#   - Module 9 installé (K3s HA)
#   - Module 10 script 01 exécuté (API déployée)
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
echo " [KeyBuzz] Module 10 Platform - Déploiement UI"
echo "=============================================================="
echo ""
log_info "Architecture: Deployment + Service ClusterIP + Ingress"
log_info "Namespace: keybuzz"
log_info "Host: platform.keybuzz.io"
log_info "API URL: https://platform-api.keybuzz.io"
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

# Image Docker pour Platform UI
PLATFORM_UI_IMAGE="${PLATFORM_UI_IMAGE:-nginx:alpine}"
log_warning "⚠️  Image Docker: ${PLATFORM_UI_IMAGE}"
log_warning "⚠️  NOTE: Remplacez par votre image Platform UI réelle"

# Créer le ConfigMap pour la configuration de l'UI
log_info "Création du ConfigMap platform-ui-config..."

CONFIGMAP_YAML=$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: platform-ui-config
  namespace: keybuzz
  labels:
    app: platform
    component: frontend
data:
  API_URL: "https://platform-api.keybuzz.io"
EOF
)

echo "${CONFIGMAP_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "ConfigMap platform-ui-config créé"

# Créer le Deployment
log_info "Création du Deployment keybuzz-ui..."

DEPLOYMENT_YAML=$(cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keybuzz-ui
  namespace: keybuzz
  labels:
    app: platform
    component: frontend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: platform
      component: frontend
  template:
    metadata:
      labels:
        app: platform
        component: frontend
    spec:
      containers:
      - name: ui
        image: ${PLATFORM_UI_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 80
          name: http
          protocol: TCP
        env:
        - name: API_URL
          valueFrom:
            configMapKeyRef:
              name: platform-ui-config
              key: API_URL
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        resources:
          requests:
            memory: "128Mi"
            cpu: "50m"
          limits:
            memory: "256Mi"
            cpu: "200m"
EOF
)

echo "${DEPLOYMENT_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Deployment keybuzz-ui créé"

# Créer le Service ClusterIP
log_info "Création du Service ClusterIP keybuzz-ui..."

SERVICE_YAML=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keybuzz-ui
  namespace: keybuzz
  labels:
    app: platform
    component: frontend
spec:
  type: ClusterIP
  ports:
  - port: 80
    targetPort: 80
    protocol: TCP
    name: http
  selector:
    app: platform
    component: frontend
EOF
)

echo "${SERVICE_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Service keybuzz-ui créé"

# Attendre que les pods soient prêts
log_info "Attente du déploiement des pods..."
sleep 5

# Vérifier le statut
log_info "Vérification du statut du déploiement..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get deployment keybuzz-ui -n keybuzz"
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=platform"
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc keybuzz-ui -n keybuzz"

echo ""
echo "=============================================================="
log_success "✅ Platform UI déployé avec succès"
echo "=============================================================="
echo ""
log_info "Composants créés:"
log_info "  - Deployment: keybuzz-ui (3 replicas)"
log_info "  - Service: keybuzz-ui (ClusterIP, port 80)"
log_info "  - ConfigMap: platform-ui-config (API_URL)"
echo ""
log_info "Prochaine étape: ./10_platform_03_deploy_my.sh"
echo ""

