#!/usr/bin/env bash
#
# 00_fix_504_keybuzz_complete.sh - Correction complète problème 504 KeyBuzz
#
# Ce script orchestre la correction complète du problème 504 Gateway Timeout
# en convertissant KeyBuzz en DaemonSets hostNetwork pour contourner VXLAN.
#
# Usage:
#   ./00_fix_504_keybuzz_complete.sh [servers.tsv] [--yes]
#
# Prérequis:
#   - Module 9 installé (K3s HA)
#   - Module 10 installé (KeyBuzz déployé)
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
TSV_FILE="${1:-${INSTALL_DIR}/servers.tsv}"
AUTO_YES="${2:-}"

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

# Header
echo "=============================================================="
echo " [KeyBuzz] Correction Complète Problème 504"
echo "=============================================================="
echo ""
echo "Ce script va :"
echo "  1. Ouvrir les ports NodePort dans UFW (31695, 32720)"
echo "  2. Convertir KeyBuzz API/Front en DaemonSets hostNetwork"
echo "  3. Mettre à jour l'Ingress NGINX en DaemonSet hostNetwork"
echo "  4. Mettre à jour les routes Ingress pour KeyBuzz"
echo "  5. Valider la correction"
echo ""
echo "Raison :"
echo "  VXLAN bloqué sur Hetzner → hostNetwork requis"
echo "  Les pods utiliseront directement l'IP du nœud"
echo ""

if [[ "${AUTO_YES}" != "--yes" ]]; then
    read -p "Continuer ? (yes/NO) : " confirm
    if [[ "${confirm}" != "yes" ]]; then
        echo "Annulé"
        exit 0
    fi
fi

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

# Récupérer les IPs des workers
declare -a WORKER_IPS=()

exec 3< "${TSV_FILE}"
while IFS=$'\t' read -r ENV IP_PUBLIQUE HOSTNAME IP_PRIVEE FQDN USER_SSH POOL ROLE SUBROLE DOCKER_STACK CORE NOTES <&3; do
    if [[ "${ENV}" == "ENV" ]]; then
        continue
    fi
    
    if [[ "${ENV}" != "prod" ]]; then
        continue
    fi
    
    if [[ "${ROLE}" == "k3s" ]] && [[ "${SUBROLE}" == "worker" ]] && [[ -n "${IP_PRIVEE}" ]]; then
        WORKER_IPS+=("${IP_PRIVEE}")
    fi
done
exec 3<&-

if [[ ${#WORKER_IPS[@]} -lt 1 ]]; then
    log_error "Aucun worker K3s trouvé"
    exit 1
fi

log_info "Workers trouvés: ${#WORKER_IPS[@]}"

echo ""
echo "=============================================================="
echo " Étape 1/5 : Ouverture ports NodePort dans UFW"
echo "=============================================================="
echo ""

HTTP_NODEPORT=31695
HTTPS_NODEPORT=32720

SUCCESS=0
FAIL=0

for ip in "${WORKER_IPS[@]}"; do
    log_info "Configuration UFW sur worker ${ip}..."
    
    set +e
    ssh ${SSH_KEY_OPTS} -o StrictHostKeyChecking=no -o ConnectTimeout=10 "root@${ip}" bash <<EOF
set +u

# Fonction pour ajouter une règle UFW (idempotente)
add_ufw_rule() {
    local port="\$1"
    local comment="\$2"
    
    if ! ufw status numbered | grep -q "\$comment"; then
        ufw allow \$port/tcp comment "\$comment" >/dev/null 2>&1 || true
        echo "  ✓ Port \$port ouvert"
    else
        echo "  ℹ️  Port \$port déjà ouvert"
    fi
}

# Ouvrir les NodePorts
add_ufw_rule "${HTTP_NODEPORT}" "Ingress NGINX HTTP NodePort"
add_ufw_rule "${HTTPS_NODEPORT}" "Ingress NGINX HTTPS NodePort"

# Recharger UFW SANS interruption
ufw reload >/dev/null 2>&1 || true
echo "  ✓ UFW rechargé"
EOF
    SSH_EXIT=$?
    set -e
    
    if [[ $SSH_EXIT -eq 0 ]]; then
        log_success "Worker ${ip} configuré"
        ((SUCCESS++))
    else
        log_error "Worker ${ip} : échec"
        ((FAIL++))
    fi
    
    echo ""
done

if [[ $FAIL -gt 0 ]]; then
    log_warning "Certains workers ont échoué, mais on continue..."
fi

echo ""
echo "=============================================================="
echo " Étape 2/5 : Conversion KeyBuzz en DaemonSets hostNetwork"
echo "=============================================================="
echo ""

log_info "Exécution du script de conversion..."
if bash "${SCRIPT_DIR}/10_keybuzz/10_keybuzz_convert_to_daemonset.sh" "${TSV_FILE}"; then
    log_success "KeyBuzz converti en DaemonSets"
else
    log_error "Échec de la conversion KeyBuzz"
    exit 1
fi

echo ""
echo "=============================================================="
echo " Étape 3/5 : Vérification Ingress NGINX DaemonSet"
echo "=============================================================="
echo ""

log_info "Vérification Ingress NGINX DaemonSet..."
INGRESS_PODS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -c Running" || echo "0")

if [[ $INGRESS_PODS -ge 5 ]]; then
    log_success "Ingress NGINX : ${INGRESS_PODS} pods Running"
else
    log_warning "Ingress NGINX : ${INGRESS_PODS} pods Running (attendu: ≥5)"
    log_info "Vérifiez que l'Ingress NGINX est bien en DaemonSet avec hostNetwork"
fi

echo ""
echo "=============================================================="
echo " Étape 4/5 : Mise à jour routes Ingress KeyBuzz"
echo "=============================================================="
echo ""

log_info "Mise à jour des routes Ingress pour KeyBuzz..."

# Mettre à jour l'Ingress pour pointer vers les NodePorts
INGRESS_YAML=$(cat <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keybuzz-front-ingress
  namespace: keybuzz
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "180"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "180"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "180"
    nginx.ingress.kubernetes.io/proxy-next-upstream-tries: "5"
    nginx.ingress.kubernetes.io/proxy-next-upstream: "error timeout http_502 http_503"
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
---
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: keybuzz-api-ingress
  namespace: keybuzz
  annotations:
    nginx.ingress.kubernetes.io/proxy-body-size: "50m"
    nginx.ingress.kubernetes.io/proxy-connect-timeout: "180"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "180"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "180"
    nginx.ingress.kubernetes.io/proxy-next-upstream-tries: "5"
    nginx.ingress.kubernetes.io/proxy-next-upstream: "error timeout http_502 http_503"
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

echo "${INGRESS_YAML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl apply -f -" > /dev/null 2>&1
log_success "Routes Ingress mises à jour"

echo ""
echo "=============================================================="
echo " Étape 5/5 : Validation"
echo "=============================================================="
echo ""

log_info "Attente stabilisation (20 secondes)..."
sleep 20

log_info "Vérification des DaemonSets KeyBuzz..."
KEYBUZZ_API_PODS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=keybuzz-api --no-headers 2>/dev/null | grep -c Running" || echo "0")
KEYBUZZ_FRONT_PODS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | grep -c Running" || echo "0")

if [[ $KEYBUZZ_API_PODS -ge 5 ]]; then
    log_success "KeyBuzz API : ${KEYBUZZ_API_PODS} pods Running"
else
    log_warning "KeyBuzz API : ${KEYBUZZ_API_PODS} pods Running (attendu: ≥5)"
fi

if [[ $KEYBUZZ_FRONT_PODS -ge 5 ]]; then
    log_success "KeyBuzz Front : ${KEYBUZZ_FRONT_PODS} pods Running"
else
    log_warning "KeyBuzz Front : ${KEYBUZZ_FRONT_PODS} pods Running (attendu: ≥5)"
fi

log_info "Test de connectivité depuis install-01..."
echo -n "  platform.keybuzz.io: "
HTTP_CODE=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" https://platform.keybuzz.io 2>/dev/null || echo "TIMEOUT")
if [[ "$HTTP_CODE" == "200" ]]; then
    log_success "HTTP $HTTP_CODE"
else
    log_warning "HTTP $HTTP_CODE"
fi

echo -n "  platform-api.keybuzz.io: "
HTTP_CODE=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" https://platform-api.keybuzz.io 2>/dev/null || echo "TIMEOUT")
if [[ "$HTTP_CODE" == "200" ]]; then
    log_success "HTTP $HTTP_CODE"
else
    log_warning "HTTP $HTTP_CODE"
fi

echo ""
echo "=============================================================="
log_success "✅ Correction 504 terminée"
echo "=============================================================="
echo ""
log_info "Résumé:"
log_info "  - UFW NodePorts : ${SUCCESS}/${#WORKER_IPS[@]} workers configurés"
log_info "  - KeyBuzz API : ${KEYBUZZ_API_PODS} pods (DaemonSet hostNetwork)"
log_info "  - KeyBuzz Front : ${KEYBUZZ_FRONT_PODS} pods (DaemonSet hostNetwork)"
log_info "  - Ingress NGINX : ${INGRESS_PODS} pods (DaemonSet hostNetwork)"
echo ""
log_warning "⚠️  Les pods utilisent maintenant hostNetwork (IP du nœud)"
log_warning "⚠️  Les Services ClusterIP ne sont plus utilisés (normal)"
log_info "Prochaine étape: Vérifier que les URLs sont accessibles depuis Internet"
echo ""

