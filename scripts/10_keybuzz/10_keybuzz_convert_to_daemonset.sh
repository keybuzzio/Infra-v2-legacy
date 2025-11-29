#!/usr/bin/env bash
#
# 10_keybuzz_convert_to_daemonset.sh - Conversion KeyBuzz en DaemonSets hostNetwork
#
# Ce script convertit KeyBuzz API et Front de Deployments en DaemonSets avec hostNetwork
# pour contourner le problème VXLAN bloqué sur Hetzner Cloud.
#
# Usage:
#   ./10_keybuzz_convert_to_daemonset.sh [servers.tsv]
#
# Prérequis:
#   - KeyBuzz API et Front déjà déployés (Deployments)
#   - Module 9 installé (K3s HA)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"

# Chercher les credentials dans plusieurs emplacements possibles
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
    # On continue quand même, les secrets peuvent être créés manuellement
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
echo " [KeyBuzz] Conversion en DaemonSets hostNetwork"
echo "=============================================================="
echo ""
echo "IMPORTANT :"
echo "  ❌ Les Deployments actuels utilisent ClusterIP (ne fonctionne pas)"
echo "  ✅ Conversion en DaemonSets avec hostNetwork"
echo ""
echo "Raison :"
echo "  VXLAN bloqué sur Hetzner → hostNetwork requis"
echo "  Les pods utiliseront directement l'IP du nœud"
echo ""

read -p "Continuer la conversion ? (yes/NO) : " confirm
if [[ "${confirm}" != "yes" ]]; then
    echo "Annulé"
    exit 0
fi

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

# Image Docker pour KeyBuzz
KEYBUZZ_API_IMAGE="${KEYBUZZ_API_IMAGE:-nginx:alpine}"
KEYBUZZ_FRONT_IMAGE="${KEYBUZZ_FRONT_IMAGE:-nginx:alpine}"
KEYBUZZ_API_PORT="${KEYBUZZ_API_PORT:-8080}"
KEYBUZZ_FRONT_PORT="${KEYBUZZ_FRONT_PORT:-80}"

# Ports hostNetwork pour KeyBuzz (éviter conflits avec Ingress NGINX sur 80/443)
KEYBUZZ_API_HOSTPORT="${KEYBUZZ_API_HOSTPORT:-8080}"
KEYBUZZ_FRONT_HOSTPORT="${KEYBUZZ_FRONT_HOSTPORT:-3000}"

echo ""
echo "=============================================================="
echo " 1. Suppression des Deployments existants"
echo "=============================================================="
echo ""

log_info "Suppression des Deployments KeyBuzz..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl delete deployment keybuzz-api keybuzz-front -n keybuzz --ignore-not-found=true" > /dev/null 2>&1 || true
log_success "Deployments supprimés"

log_info "Suppression des HPA KeyBuzz..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl delete hpa keybuzz-api-hpa -n keybuzz --ignore-not-found=true" > /dev/null 2>&1 || true
log_success "HPA supprimé"

echo ""
echo "=============================================================="
echo " 2. Création DaemonSet KeyBuzz API"
echo "=============================================================="
echo ""

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
      # Ne pas déployer sur les masters (optionnel)
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
        - containerPort: 80
          hostPort: ${KEYBUZZ_API_HOSTPORT}
          name: http
          protocol: TCP
        # Configuration NGINX pour écouter sur le port 80 (containerPort)
        # Le hostPort (8080) sera mappé automatiquement
        command: ["/bin/sh"]
        args: ["-c", "echo '<!DOCTYPE html><html><head><title>KeyBuzz API</title></head><body><h1>KeyBuzz API</h1><p>API déployée avec succès</p><p>Port: ${KEYBUZZ_API_HOSTPORT}</p></body></html>' > /usr/share/nginx/html/index.html && nginx -g 'daemon off;'"]
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
        - name: PORT
          value: "80"
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

echo ""
echo "=============================================================="
echo " 3. Création DaemonSet KeyBuzz Front"
echo "=============================================================="
echo ""

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
      # Ne pas déployer sur les masters (optionnel)
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
        - containerPort: 80
          hostPort: ${KEYBUZZ_FRONT_HOSTPORT}
          name: http
          protocol: TCP
        # Configuration NGINX pour servir le frontend
        command: ["/bin/sh"]
        args: ["-c", "echo '<!DOCTYPE html><html><head><title>KeyBuzz Platform</title></head><body><h1>🚀 KeyBuzz Platform</h1><p>Frontend déployé avec succès</p><p>Port: ${KEYBUZZ_FRONT_HOSTPORT}</p></body></html>' > /usr/share/nginx/html/index.html && nginx -g 'daemon off;'"]
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

# Mettre à jour les Services pour pointer vers les NodePorts
echo ""
echo "=============================================================="
echo " 4. Mise à jour des Services (NodePort)"
echo "=============================================================="
echo ""

log_info "Mise à jour du Service keybuzz-api en NodePort..."

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
    targetPort: ${KEYBUZZ_API_HOSTPORT}
    nodePort: 30080
    protocol: TCP
    name: http
EOF
)

echo "${SERVICE_API_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Service keybuzz-api mis à jour (NodePort 30080)"

log_info "Mise à jour du Service keybuzz-front en NodePort..."

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
    targetPort: ${KEYBUZZ_FRONT_HOSTPORT}
    nodePort: 30000
    protocol: TCP
    name: http
EOF
)

echo "${SERVICE_FRONT_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Service keybuzz-front mis à jour (NodePort 30000)"

# Attendre que les pods démarrent
log_info "Attente du démarrage des pods (30 secondes)..."
sleep 30

# Vérifier le statut
log_info "Vérification du statut..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get daemonset -n keybuzz"
echo ""
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=keybuzz-api"
echo ""
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=keybuzz-front"
echo ""
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc -n keybuzz"

echo ""
echo "=============================================================="
log_success "✅ KeyBuzz converti en DaemonSets hostNetwork"
echo "=============================================================="
echo ""
log_info "Configuration:"
log_info "  - DaemonSet keybuzz-api (hostNetwork, port ${KEYBUZZ_API_HOSTPORT})"
log_info "  - DaemonSet keybuzz-front (hostNetwork, port ${KEYBUZZ_FRONT_HOSTPORT})"
log_info "  - Service keybuzz-api (NodePort 30080)"
log_info "  - Service keybuzz-front (NodePort 30000)"
echo ""
log_warning "⚠️  IMPORTANT: Les pods utilisent maintenant l'IP du nœud directement"
log_warning "⚠️  L'Ingress doit pointer vers les NodePorts ou les IPs des nœuds"
echo ""

