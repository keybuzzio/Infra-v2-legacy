#!/usr/bin/env bash
#
# 11_n8n_01_deploy.sh - Déploiement n8n
#
# Ce script déploie n8n sur le cluster K3s avec :
# - DaemonSet avec hostNetwork (Solution validée pour contourner VXLAN)
# - Service NodePort (port 30567)
# - Secrets Kubernetes pour les credentials
# - Un pod par worker node (pas de HPA avec DaemonSet)
#
# Usage:
#   ./11_n8n_01_deploy.sh [servers.tsv]
#
# Prérequis:
#   - Module 9 installé (K3s HA)
#   - Module 11 script 00 exécuté (credentials)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
CREDENTIALS_DIR="${INSTALL_DIR}/credentials"
CREDENTIALS_FILE="${CREDENTIALS_DIR}/n8n.env"

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

if [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable: ${CREDENTIALS_FILE}"
    log_error "Exécutez d'abord: ./11_n8n_00_setup_credentials.sh"
    exit 1
fi

# Charger les credentials
source "${CREDENTIALS_FILE}"

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
echo " [KeyBuzz] Module 11 - Déploiement n8n"
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

# Vérifier la connectivité au cluster
log_info "Vérification de la connectivité au cluster K3s..."
if ! ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get nodes" > /dev/null 2>&1; then
    log_error "Impossible de se connecter au cluster K3s"
    exit 1
fi
log_success "Cluster K3s accessible"

# Créer le namespace si nécessaire
log_info "Création du namespace n8n..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl create namespace n8n --dry-run=client -o yaml | kubectl apply -f -" > /dev/null 2>&1
log_success "Namespace n8n prêt"

# Créer le Secret Kubernetes avec les credentials
log_info "Création du Secret Kubernetes pour n8n..."

# Charger les variables depuis le fichier credentials
source "${CREDENTIALS_FILE}"

SECRET_YAML=$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: n8n-config
  namespace: n8n
type: Opaque
stringData:
  DB_TYPE: "${DB_TYPE}"
  DB_POSTGRESDB_HOST: "${DB_POSTGRESDB_HOST}"
  DB_POSTGRESDB_PORT: "${DB_POSTGRESDB_PORT}"
  DB_POSTGRESDB_DATABASE: "${DB_POSTGRESDB_DATABASE}"
  DB_POSTGRESDB_USER: "${DB_POSTGRESDB_USER}"
  DB_POSTGRESDB_PASSWORD: "${DB_POSTGRESDB_PASSWORD}"
  DB_POSTGRESDB_SCHEMA: "${DB_POSTGRESDB_SCHEMA}"
  QUEUE_BULL_REDIS_HOST: "${QUEUE_BULL_REDIS_HOST}"
  QUEUE_BULL_REDIS_PORT: "${QUEUE_BULL_REDIS_PORT}"
  QUEUE_BULL_REDIS_PASSWORD: "${QUEUE_BULL_REDIS_PASSWORD}"
  QUEUE_BULL_REDIS_DB: "${QUEUE_BULL_REDIS_DB}"
  EXECUTIONS_MODE: "${EXECUTIONS_MODE}"
  WEBHOOK_URL: "${WEBHOOK_URL}"
  N8N_PROTOCOL: "${N8N_PROTOCOL}"
  N8N_HOST: "${N8N_HOST}"
  N8N_PORT: "${N8N_PORT}"
  N8N_ENCRYPTION_KEY: "${N8N_ENCRYPTION_KEY}"
  GENERIC_TIMEZONE: "${GENERIC_TIMEZONE}"
  TZ: "${TZ}"
  N8N_LOG_LEVEL: "${N8N_LOG_LEVEL}"
  N8N_LOG_OUTPUT: "${N8N_LOG_OUTPUT}"
EOF
)

echo "${SECRET_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Secret n8n-config créé"

# Image Docker pour n8n
N8N_IMAGE="${N8N_IMAGE:-n8nio/n8n:latest}"
N8N_PORT="${N8N_PORT:-5678}"

log_info "Image Docker: ${N8N_IMAGE}"
log_info "Port: ${N8N_PORT}"

# Créer le DaemonSet n8n avec hostNetwork (Solution validée)
log_info "Création du DaemonSet n8n avec hostNetwork (Solution validée)..."
log_warning "⚠️  Utilisation de DaemonSet + hostNetwork pour contourner VXLAN"

DAEMONSET_YAML=$(cat <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: n8n
  namespace: n8n
  labels:
    app: n8n
spec:
  selector:
    matchLabels:
      app: n8n
  template:
    metadata:
      labels:
        app: n8n
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: node-role.kubernetes.io/control-plane
                operator: DoesNotExist
      tolerations:
      - operator: Exists
      containers:
      - name: n8n
        image: ${N8N_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: ${N8N_PORT}
          hostPort: ${N8N_PORT}
          name: http
          protocol: TCP
        envFrom:
        - secretRef:
            name: n8n-config
        livenessProbe:
          httpGet:
            path: /healthz
            port: ${N8N_PORT}
          initialDelaySeconds: 60
          periodSeconds: 30
          timeoutSeconds: 10
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /healthz
            port: ${N8N_PORT}
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        resources:
          requests:
            cpu: "200m"
            memory: "512Mi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
EOF
)

echo "${DAEMONSET_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "DaemonSet n8n créé avec hostNetwork"

# Créer le Service NodePort (pour hostNetwork)
log_info "Création du Service NodePort n8n (pour hostNetwork)..."

SERVICE_YAML=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: n8n
  namespace: n8n
  labels:
    app: n8n
spec:
  type: NodePort
  selector:
    app: n8n
  ports:
  - port: 80
    targetPort: ${N8N_PORT}
    nodePort: 30567
    protocol: TCP
    name: http
EOF
)

echo "${SERVICE_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Service NodePort n8n créé (port 30567)"

# Note: Pas de HPA avec DaemonSet (un pod par node)
log_info "Note: DaemonSet déploie automatiquement un pod par worker node"
log_info "Pas de HPA nécessaire (DaemonSet gère la répartition)"

# Attendre que les pods soient prêts
log_info "Attente du démarrage des pods (60 secondes)..."
sleep 60

# Vérifier le statut
log_info "Vérification du statut du DaemonSet..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get daemonset n8n -n n8n"
echo ""
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n n8n -l app=n8n"
echo ""
echo ""
echo "=============================================================="
log_success "✅ n8n déployé"
echo "=============================================================="
echo ""
log_info "Configuration:"
log_info "  - Namespace: n8n"
log_info "  - DaemonSet: n8n (hostNetwork: true)"
log_info "  - Service: n8n (NodePort: 30567)"
log_info "  - Image: ${N8N_IMAGE}"
log_info "  - Port: ${N8N_PORT}"
echo ""
log_info "Prochaine étape: ./11_n8n_02_configure_ingress.sh"
echo ""

