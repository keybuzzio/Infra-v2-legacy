#!/usr/bin/env bash
#
# 09_k3s_05_ingress_daemonset.sh - Installation Ingress NGINX DaemonSet
#
# Ce script installe Ingress NGINX en mode DaemonSet (CRITIQUE pour LB Hetzner).
# Un Pod Ingress par node garantit la disponibilité avec le Load Balancing L4.
#
# Usage:
#   ./09_k3s_05_ingress_daemonset.sh [servers.tsv]
#
# Prérequis:
#   - Script 09_k3s_04_bootstrap_addons.sh exécuté
#   - Cluster K3s opérationnel
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
echo " [KeyBuzz] Module 9 - Installation Ingress NGINX DaemonSet"
echo "=============================================================="
echo ""
log_warning "CRITIQUE: Ingress doit être en DaemonSet (pas Deployment)"
log_warning "Cela garantit un Pod Ingress par node pour LB Hetzner L4"
echo ""

# Trouver le premier master
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
echo ""

# Créer le manifeste Ingress DaemonSet
log_info "Création du manifeste Ingress NGINX DaemonSet..."

INGRESS_MANIFEST="${INSTALL_DIR}/config/k3s/ingress-nginx-daemonset.yaml"

mkdir -p "$(dirname "${INGRESS_MANIFEST}")"

cat > "${INGRESS_MANIFEST}" <<'INGRESS_YAML'
apiVersion: v1
kind: Namespace
metadata:
  name: ingress-nginx
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nginx-ingress-controller
  namespace: ingress-nginx
  labels:
    app: ingress-nginx
spec:
  selector:
    matchLabels:
      app: ingress-nginx
  template:
    metadata:
      labels:
        app: ingress-nginx
    spec:
      hostNetwork: true
      dnsPolicy: ClusterFirstWithHostNet
      serviceAccountName: ingress-nginx
      containers:
      - name: controller
        image: registry.k8s.io/ingress-nginx/controller:v1.11.0
        args:
        - /nginx-ingress-controller
        - --configmap=$(POD_NAMESPACE)/nginx-configuration
        - --tcp-services-configmap=$(POD_NAMESPACE)/tcp-services
        - --udp-services-configmap=$(POD_NAMESPACE)/udp-services
        - --annotations-prefix=nginx.ingress.kubernetes.io
        - --publish-service=$(POD_NAMESPACE)/ingress-nginx-controller
        env:
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: POD_NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        ports:
        - name: http
          containerPort: 80
          protocol: TCP
        - name: https
          containerPort: 443
          protocol: TCP
        livenessProbe:
          httpGet:
            path: /healthz
            port: 10254
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 1
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /healthz
            port: 10254
            scheme: HTTP
          initialDelaySeconds: 10
          periodSeconds: 10
          timeoutSeconds: 1
          successThreshold: 1
          failureThreshold: 3
        resources:
          limits:
            cpu: 1000m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 128Mi
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: ingress-nginx
  namespace: ingress-nginx
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ingress-nginx
rules:
- apiGroups:
  - ""
  resources:
  - configmaps
  - endpoints
  - nodes
  - pods
  - secrets
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - nodes
  verbs:
  - get
- apiGroups:
  - ""
  resources:
  - services
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - networking.k8s.io
  resources:
  - ingresses
  verbs:
  - get
  - list
  - watch
- apiGroups:
  - ""
  resources:
  - events
  verbs:
  - create
  - patch
- apiGroups:
  - networking.k8s.io
  resources:
  - ingresses/status
  verbs:
  - update
- apiGroups:
  - networking.k8s.io
  resources:
  - ingressclasses
  verbs:
  - get
  - list
  - watch
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ingress-nginx
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ingress-nginx
subjects:
- kind: ServiceAccount
  name: ingress-nginx
  namespace: ingress-nginx
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: nginx-configuration
  namespace: ingress-nginx
data:
  use-forwarded-headers: "true"
  compute-full-forwarded-for: "true"
  use-proxy-protocol: "false"
---
apiVersion: v1
kind: Service
metadata:
  name: ingress-nginx-controller
  namespace: ingress-nginx
  labels:
    app: ingress-nginx
spec:
  type: NodePort
  ports:
  - name: http
    port: 80
    protocol: TCP
    targetPort: 80
    nodePort: 31695
  selector:
    app: ingress-nginx
INGRESS_YAML

log_success "Manifeste créé: ${INGRESS_MANIFEST}"

# Copier et appliquer le manifeste
log_info "Application du manifeste Ingress NGINX DaemonSet..."

scp ${SSH_KEY_OPTS} "${INGRESS_MANIFEST}" "root@${MASTER_IP}:/tmp/ingress-nginx-daemonset.yaml"

ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

# Supprimer l'ancien ingress si existe (Traefik ou autre)
echo "Nettoyage des anciens ingress..."
kubectl delete deployment traefik -n kube-system 2>/dev/null || true
kubectl delete daemonset nginx-ingress-controller -n ingress-nginx 2>/dev/null || true
sleep 5

# Appliquer le manifeste
echo "Application du manifeste Ingress NGINX DaemonSet..."
kubectl apply -f /tmp/ingress-nginx-daemonset.yaml

# Attendre que les pods soient prêts
echo "Attente que les pods Ingress soient prêts (30 secondes)..."
sleep 30

# Vérifier l'installation
echo "=== DaemonSet Ingress ==="
kubectl get daemonset -n ingress-nginx

echo ""
echo "=== Pods Ingress (devrait être un par node) ==="
kubectl get pods -n ingress-nginx -o wide

echo ""
echo "=== Vérification hostNetwork ==="
kubectl get pods -n ingress-nginx -o jsonpath='{.items[0].spec.hostNetwork}' && echo ""
EOF

if [ $? -eq 0 ]; then
    log_success "Ingress NGINX DaemonSet installé"
else
    log_error "Échec de l'installation Ingress NGINX"
    exit 1
fi

# Vérifier que chaque node a un pod
log_info "Vérification de la distribution des pods..."
ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

NODE_COUNT=\$(kubectl get nodes --no-headers | wc -l)
POD_COUNT=\$(kubectl get pods -n ingress-nginx --no-headers | grep Running | wc -l)

echo "Nœuds: \${NODE_COUNT}"
echo "Pods Ingress Running: \${POD_COUNT}"

if [[ \${POD_COUNT} -ge \${NODE_COUNT} ]]; then
    echo "✓ Tous les nœuds ont un Pod Ingress"
else
    echo "⚠ Certains nœuds n'ont pas encore de Pod Ingress"
fi
EOF

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Ingress NGINX DaemonSet installé"
echo "=============================================================="
echo ""
log_info "Configuration:"
log_info "  - Mode: DaemonSet (un Pod par node)"
log_info "  - hostNetwork: true (pour LB Hetzner L4)"
log_info "  - Ports: 80 (HTTP), 443 (HTTPS)"
echo ""
log_warning "IMPORTANT: Configurer le LB Hetzner pour pointer vers tous les nœuds K3s"
log_warning "  - Port 80 → tous les nœuds"
log_warning "  - Port 443 → tous les nœuds"
echo ""
log_info "Prochaine étape:"
log_info "  ./09_k3s_06_deploy_core_apps.sh ${TSV_FILE}"
echo ""

