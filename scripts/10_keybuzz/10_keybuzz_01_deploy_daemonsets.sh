#!/usr/bin/env bash
#
# 10_keybuzz_01_deploy_daemonsets.sh - Déploiement KeyBuzz en DaemonSets hostNetwork
#
# Ce script déploie KeyBuzz API et Front en DaemonSets avec hostNetwork
# pour contourner le problème VXLAN bloqué sur Hetzner Cloud.
#
# Usage:
#   ./10_keybuzz_01_deploy_daemonsets.sh [servers.tsv]
#
# Prérequis:
#   - Module 9 installé (K3s HA avec Ingress NGINX DaemonSet)
#   - Module 10 script 00 exécuté (credentials)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

# Chercher les credentials
CREDENTIALS_FILE=""
for path in \
    "/opt/keybuzz-installer/credentials/keybuzz.env" \
    "${INSTALL_DIR}/credentials/keybuzz.env" \
    "/root/credentials/keybuzz.env" \
    "${HOME}/credentials/keybuzz.env"; do
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
    log_warning "Fichier credentials introuvable, utilisation des valeurs par défaut"
    log_warning "Les variables d'environnement devront être définies dans les Secrets Kubernetes"
else
    log_info "Chargement des credentials depuis: ${CREDENTIALS_FILE}"
    source "${CREDENTIALS_FILE}"
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
echo " [KeyBuzz] Module 10 - Déploiement DaemonSets hostNetwork"
echo "=============================================================="
echo ""
log_info "Architecture: DaemonSets avec hostNetwork (contourne VXLAN)"
log_info "Ports: 8080 (API), 3000 (Front)"
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

# Créer le Secret Kubernetes avec les credentials
log_info "Création du Secret Kubernetes pour KeyBuzz API..."

SECRET_YAML=$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: keybuzz-api-secrets
  namespace: keybuzz
type: Opaque
stringData:
  DATABASE_URL: "${DATABASE_URL:-}"
  REDIS_URL: "${REDIS_URL:-}"
  RABBITMQ_URL: "${RABBITMQ_URL:-}"
  MINIO_URL: "${MINIO_URL:-}"
  VECTOR_URL: "${VECTOR_URL:-}"
  LLM_URL: "${LLM_URL:-}"
EOF
)

echo "${SECRET_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Secret keybuzz-api-secrets créé"

# Image Docker pour KeyBuzz
KEYBUZZ_API_IMAGE="${KEYBUZZ_API_IMAGE:-nginx:alpine}"
KEYBUZZ_FRONT_IMAGE="${KEYBUZZ_FRONT_IMAGE:-nginx:alpine}"

log_warning "⚠️  Image Docker: ${KEYBUZZ_API_IMAGE} / ${KEYBUZZ_FRONT_IMAGE}"
log_warning "⚠️  NOTE: Utilisez des images placeholder pour tester la configuration"
log_warning "⚠️  Remplacez par vos images KeyBuzz une fois construites"
echo ""

# Créer le DaemonSet KeyBuzz API
log_info "Création du DaemonSet KeyBuzz API avec hostNetwork..."

DAEMONSET_API_YAML=$(cat <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: keybuzz-api
  namespace: keybuzz
  labels:
    app: keybuzz-api
spec:
  selector:
    matchLabels:
      app: keybuzz-api
  template:
    metadata:
      labels:
        app: keybuzz-api
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
      - name: keybuzz-api
        image: ${KEYBUZZ_API_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 8080
          hostPort: 8080
          name: http
          protocol: TCP
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo 'server { listen 8080; root /usr/share/nginx/html; index index.html; location / { try_files \$uri \$uri/ /index.html; } }' > /etc/nginx/conf.d/default.conf
          echo '<!DOCTYPE html><html><head><title>KeyBuzz API</title></head><body><h1>KeyBuzz API</h1><p>API deployee avec succes</p></body></html>' > /usr/share/nginx/html/index.html
          nginx -g 'daemon off;'
        env:
        - name: DATABASE_URL
          valueFrom:
            secretKeyRef:
              name: keybuzz-api-secrets
              key: DATABASE_URL
        - name: REDIS_URL
          valueFrom:
            secretKeyRef:
              name: keybuzz-api-secrets
              key: REDIS_URL
        - name: RABBITMQ_URL
          valueFrom:
            secretKeyRef:
              name: keybuzz-api-secrets
              key: RABBITMQ_URL
        - name: MINIO_URL
          valueFrom:
            secretKeyRef:
              name: keybuzz-api-secrets
              key: MINIO_URL
        - name: VECTOR_URL
          valueFrom:
            secretKeyRef:
              name: keybuzz-api-secrets
              key: VECTOR_URL
        - name: LLM_URL
          valueFrom:
            secretKeyRef:
              name: keybuzz-api-secrets
              key: LLM_URL
        resources:
          requests:
            cpu: "200m"
            memory: "512Mi"
          limits:
            cpu: "1000m"
            memory: "2Gi"
EOF
)

echo "${DAEMONSET_API_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "DaemonSet keybuzz-api créé"

# Créer le DaemonSet KeyBuzz Front
log_info "Création du DaemonSet KeyBuzz Front avec hostNetwork..."

DAEMONSET_FRONT_YAML=$(cat <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: keybuzz-front
  namespace: keybuzz
  labels:
    app: keybuzz-front
spec:
  selector:
    matchLabels:
      app: keybuzz-front
  template:
    metadata:
      labels:
        app: keybuzz-front
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
      - name: keybuzz-front
        image: ${KEYBUZZ_FRONT_IMAGE}
        imagePullPolicy: IfNotPresent
        ports:
        - containerPort: 3000
          hostPort: 3000
          name: http
          protocol: TCP
        command: ["/bin/sh", "-c"]
        args:
        - |
          echo 'server { listen 3000; root /usr/share/nginx/html; index index.html; location / { try_files \$uri \$uri/ /index.html; } }' > /etc/nginx/conf.d/default.conf
          echo '<!DOCTYPE html><html><head><title>KeyBuzz Platform</title></head><body><h1>KeyBuzz Platform</h1><p>Frontend deploye avec succes</p></body></html>' > /usr/share/nginx/html/index.html
          nginx -g 'daemon off;'
        env:
        - name: API_URL
          value: "http://keybuzz-api.keybuzz.svc.cluster.local"
        resources:
          requests:
            cpu: "100m"
            memory: "128Mi"
          limits:
            cpu: "500m"
            memory: "512Mi"
EOF
)

echo "${DAEMONSET_FRONT_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "DaemonSet keybuzz-front créé"

# Créer les Services NodePort
log_info "Création des Services NodePort..."

SERVICE_API_YAML=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keybuzz-api
  namespace: keybuzz
  labels:
    app: keybuzz-api
spec:
  type: NodePort
  selector:
    app: keybuzz-api
  ports:
  - port: 80
    targetPort: 8080
    nodePort: 30080
    protocol: TCP
    name: http
EOF
)

echo "${SERVICE_API_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Service keybuzz-api créé (NodePort 30080)"

SERVICE_FRONT_YAML=$(cat <<EOF
apiVersion: v1
kind: Service
metadata:
  name: keybuzz-front
  namespace: keybuzz
  labels:
    app: keybuzz-front
spec:
  type: NodePort
  selector:
    app: keybuzz-front
  ports:
  - port: 80
    targetPort: 3000
    nodePort: 30000
    protocol: TCP
    name: http
EOF
)

echo "${SERVICE_FRONT_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Service keybuzz-front créé (NodePort 30000)"

# Attendre que les pods démarrent
log_info "Attente du démarrage des pods (30 secondes)..."
sleep 30

# Vérifier le statut
log_info "Vérification du statut..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get daemonset -n keybuzz"
echo ""
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -o wide"
echo ""
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc -n keybuzz"

echo ""
echo "=============================================================="
log_success "✅ KeyBuzz déployé en DaemonSets hostNetwork"
echo "=============================================================="
echo ""
log_info "Configuration:"
log_info "  - DaemonSet keybuzz-api (hostNetwork, port 8080)"
log_info "  - DaemonSet keybuzz-front (hostNetwork, port 3000)"
log_info "  - Service keybuzz-api (NodePort 30080)"
log_info "  - Service keybuzz-front (NodePort 30000)"
echo ""
log_info "Prochaine étape: ./10_keybuzz_02_configure_ingress.sh"
echo ""

