#!/usr/bin/env bash
#
# 09_k3s_07_install_monitoring.sh - Installation Monitoring K3s (Prometheus Stack)
#
# Ce script installe le monitoring K3s avec Prometheus Stack :
# - Prometheus (collecte métriques)
# - Grafana (visualisation)
# - kube-state-metrics (métriques K8s)
# - node-exporter (métriques nodes)
#
# Usage:
#   ./09_k3s_07_install_monitoring.sh [servers.tsv]
#
# Prérequis:
#   - Script 09_k3s_06_deploy_core_apps.sh exécuté
#   - Cluster K3s opérationnel
#   - Helm installé (optionnel, sinon installation manuelle)
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
echo " [KeyBuzz] Module 9 - Installation Monitoring K3s"
echo "=============================================================="
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

# Vérifier si Helm est disponible
log_info "Vérification de Helm..."

HELM_AVAILABLE=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "command -v helm >/dev/null 2>&1 && echo 'yes' || echo 'no'")

if [[ "${HELM_AVAILABLE}" == "no" ]]; then
    log_warning "Helm non installé, installation..."
    ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

# Installer Helm
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Ajouter le repo Prometheus
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update
EOF
    
    if [ $? -eq 0 ]; then
        log_success "Helm installé"
    else
        log_warning "Helm non installé, installation manuelle requise"
        log_info "Le monitoring sera installé manuellement plus tard"
        exit 0
    fi
else
    log_success "Helm déjà installé"
fi

echo ""

# Installer Prometheus Stack
log_info "Installation Prometheus Stack..."

ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

# Exporter le kubeconfig
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml

# Créer le namespace monitoring
kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -

# Installer kube-prometheus-stack
echo "Installation kube-prometheus-stack..."
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --set grafana.adminPassword=KeyBuzz2025! \
  --set prometheus.prometheusSpec.retention=30d \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.storageClassName=local-path \
  --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=50Gi \
  --wait \
  --timeout 10m

# Attendre que les pods soient prêts
echo "Attente que les pods soient prêts (60 secondes)..."
sleep 60

# Vérifier l'installation
echo "=== Pods monitoring ==="
kubectl get pods -n monitoring

echo ""
echo "=== Services monitoring ==="
kubectl get svc -n monitoring
EOF

if [ $? -eq 0 ]; then
    log_success "Prometheus Stack installé"
else
    log_warning "Installation Prometheus Stack échouée ou en cours"
    log_warning "Vérifiez manuellement: kubectl get pods -n monitoring"
fi

echo ""

# Exposer Grafana via Ingress (optionnel)
log_info "Création de l'Ingress pour Grafana..."

ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" bash <<EOF
set -euo pipefail

cat <<INGRESS | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana
  namespace: monitoring
  annotations:
    nginx.ingress.kubernetes.io/ssl-redirect: "false"
spec:
  ingressClassName: nginx
  rules:
  - host: grafana.keybuzz.local
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: kube-prometheus-stack-grafana
            port:
              number: 80
INGRESS

echo "✓ Ingress Grafana créé"
EOF

log_success "Ingress Grafana créé"
echo ""

# Résumé
echo ""
echo "=============================================================="
log_success "✅ Monitoring K3s installé"
echo "=============================================================="
echo ""
log_info "Composants installés:"
log_info "  - Prometheus: Collecte métriques"
log_info "  - Grafana: Visualisation (admin/KeyBuzz2025!)"
log_info "  - kube-state-metrics: Métriques K8s"
log_info "  - node-exporter: Métriques nodes"
echo ""
log_info "Accès Grafana:"
log_info "  - Via Ingress: http://grafana.keybuzz.local (après configuration DNS)"
log_info "  - Port-forward: kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80"
echo ""
log_info "Prochaine étape:"
log_info "  ./09_k3s_08_install_vault_agent.sh ${TSV_FILE}"
echo ""

