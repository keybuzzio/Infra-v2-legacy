#!/usr/bin/env bash
#
# 10_platform_01_deploy_api.sh - Déploiement Platform API (platform-api.keybuzz.io)
#
# Ce script déploie l'API KeyBuzz avec Deployment + Service ClusterIP + Ingress
#
# Usage:
#   ./10_platform_01_deploy_api.sh [servers.tsv]
#
# Prérequis:
#   - Module 9 installé (K3s HA)
#   - Module 10 script 00 exécuté (credentials)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

# Chercher les credentials
CREDENTIALS_FILE=""
for path in \
    "/opt/keybuzz-installer/credentials/platform.env" \
    "${INSTALL_DIR}/credentials/platform.env" \
    "/root/credentials/platform.env" \
    "${HOME}/credentials/platform.env"; do
    if [[ -f "${path}" ]]; then
        CREDENTIALS_FILE="${path}"
        break
    fi
done

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

if [[ -z "${CREDENTIALS_FILE}" ]] || [[ ! -f "${CREDENTIALS_FILE}" ]]; then
    log_error "Fichier credentials introuvable"
    log_error "Exécutez d'abord: ./10_platform_00_setup_credentials.sh"
    exit 1
fi

log_info "Chargement des credentials depuis: ${CREDENTIALS_FILE}"
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
echo " [KeyBuzz] Module 10 Platform - Déploiement API"
echo "=============================================================="
echo ""
log_info "Architecture: Deployment + Service ClusterIP + Ingress"
log_info "Namespace: keybuzz"
log_info "Host: platform-api.keybuzz.io"
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
log_info "Création du namespace keybuzz..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl create namespace keybuzz --dry-run=client -o yaml | kubectl apply -f -" > /dev/null 2>&1
log_success "Namespace keybuzz prêt"

# Image Docker pour Platform API
PLATFORM_API_IMAGE="${PLATFORM_API_IMAGE:-nginx:alpine}"
log_warning "⚠️  Image Docker: ${PLATFORM_API_IMAGE}"
log_warning "⚠️  NOTE: Remplacez par votre image Platform API réelle"

# Créer le ConfigMap pour les variables non sensibles
log_info "Création du ConfigMap platform-api-config..."

CONFIGMAP_YAML=$(cat <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: platform-api-config
  namespace: keybuzz
  labels:
    app: platform-api
    component: backend
data:
  MINIO_ENDPOINT: "${MINIO_ENDPOINT:-http://10.0.0.134:9000}"
  MARIADB_HOST: "${MARIADB_HOST:-10.0.0.20}"
EOF
)

echo "${CONFIGMAP_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "ConfigMap platform-api-config créé"

# Créer le Secret pour les credentials sensibles
log_info "Création du Secret platform-api-secrets..."

SECRET_YAML=$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: platform-api-secrets
  namespace: keybuzz
  labels:
    app: platform-api
    component: backend
type: Opaque
stringData:
  DATABASE_URL: "${DATABASE_URL:-}"
  REDIS_URL: "${REDIS_URL:-}"
  RABBITMQ_URL: "${RABBITMQ_URL:-}"
EOF
)

echo "${SECRET_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Secret platform-api-secrets créé"

# Créer le Deployment
log_info "Création du Deployment keybuzz-api..."

DEPLOYMENT_YAML=$(cat <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keybuzz-api
  namespace: keybuzz
  labels:
    app: platform-api
    component: backend
spec:
  replicas: 3
  selector:
    matchLabels:
      app: platform-api
      component: backend
  template:
    metadata:
      labels:
        app: platform-api
        component: backend
    spec:
      containers:
      - name: api
        image: ${PLATFORM_API_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: platform-api-secrets
              key: DATABASE_URL
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: platform-api-secrets
              key: REDIS_URL
        - name: RABBITMQ_URL
          valueFrom:
            secretKeyRef:
              name: platform-api-secrets
              key: RABBITMQ_URL
        - name: MINIO_ENDPOINT
          valueFrom:
            configMapKeyRef:
              name: platform-api-config
              key: MINIO_ENDPOINT
        - name: MARIADB_HOST
          valueFrom:
            configMapKeyRef:
              name: platform-api-config
              key: MARIADB_HOST
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 30
          timeoutSeconds: 5
          failureThreshold: 3
        resources:
          requests:
            memory: "256Mi"
            cpu: "100m"
          limits:
            memory: "512Mi"
            cpu: "500m"
EOF
)

echo "${DEPLOYMENT_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Deployment keybuzz-api créé"

# Créer le Service ClusterIP
log_info "Création du Service ClusterIP keybuzz-api..."

SERVICE_YAML=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keybuzz-api
  namespace: keybuzz
  labels:
    app: platform-api
    component: backend
spec:
  type: ClusterIP
  ports:
  - port: 8080
    targetPort: 8080
    protocol: TCP
    name: http
  selector:
    app: platform-api
    component: backend
EOF
)

echo "${SERVICE_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Service keybuzz-api créé"

# Créer le HPA (Horizontal Pod Autoscaler)
log_info "Création du HPA keybuzz-api-hpa..."

HPA_YAML=$(cat <<EOF
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: keybuzz-api-hpa
  namespace: keybuzz
  labels:
    app: platform-api
    component: backend
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: keybuzz-api
  minReplicas: 3
  maxReplicas: 20
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
EOF
)

echo "${HPA_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "HPA keybuzz-api-hpa créé"

# Attendre que les pods soient prêts
log_info "Attente du déploiement des pods..."
sleep 5

# Vérifier le statut
log_info "Vérification du statut du déploiement..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get deployment keybuzz-api -n keybuzz"
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=platform-api"
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc keybuzz-api -n keybuzz"

echo ""
echo "=============================================================="
log_success "✅ Platform API déployé avec succès"
echo "=============================================================="
echo ""
log_info "Composants créés:"
log_info "  - Deployment: keybuzz-api (3 replicas min)"
log_info "  - Service: keybuzz-api (ClusterIP, port 8080)"
log_info "  - HPA: keybuzz-api-hpa (min: 3, max: 20)"
log_info "  - ConfigMap: platform-api-config"
log_info "  - Secret: platform-api-secrets"
echo ""
log_info "Prochaine étape: ./10_platform_02_deploy_ui.sh"
echo ""

