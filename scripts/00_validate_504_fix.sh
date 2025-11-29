#!/usr/bin/env bash
#
# 00_validate_504_fix.sh - Validation de la correction 504
#
# Ce script valide que la correction du problème 504 a bien fonctionné
# en vérifiant les DaemonSets, les pods, et l'accessibilité des URLs.
#
# Usage:
#   ./00_validate_504_fix.sh [servers.tsv]
#
# Prérequis:
#   - Script 00_fix_504_keybuzz_complete.sh exécuté
#   - Exécuter depuis install-01

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
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

# Header
echo "=============================================================="
echo " [KeyBuzz] Validation Correction 504"
echo "=============================================================="
echo ""

SCORE=0
TOTAL=0

# 1. Vérifier les DaemonSets
echo "1. Vérification DaemonSets KeyBuzz:"
echo "=============================================================="
TOTAL=$((TOTAL + 1))

KEYBUZZ_API_DS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get daemonset keybuzz-api -n keybuzz --no-headers 2>/dev/null | wc -l" || echo "0")
KEYBUZZ_FRONT_DS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get daemonset keybuzz-front -n keybuzz --no-headers 2>/dev/null | wc -l" || echo "0")

if [[ $KEYBUZZ_API_DS -eq 1 ]] && [[ $KEYBUZZ_FRONT_DS -eq 1 ]]; then
    log_success "DaemonSets KeyBuzz présents"
    SCORE=$((SCORE + 1))
else
    log_error "DaemonSets KeyBuzz manquants"
fi

echo ""

# 2. Vérifier les pods
echo "2. Vérification Pods KeyBuzz:"
echo "=============================================================="
TOTAL=$((TOTAL + 1))

KEYBUZZ_API_PODS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=keybuzz-api --no-headers 2>/dev/null | grep -c Running" || echo "0")
KEYBUZZ_FRONT_PODS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | grep -c Running" || echo "0")

log_info "KeyBuzz API : ${KEYBUZZ_API_PODS} pods Running"
log_info "KeyBuzz Front : ${KEYBUZZ_FRONT_PODS} pods Running"

if [[ $KEYBUZZ_API_PODS -ge 5 ]] && [[ $KEYBUZZ_FRONT_PODS -ge 5 ]]; then
    log_success "Pods KeyBuzz opérationnels (≥5 chacun)"
    SCORE=$((SCORE + 1))
else
    log_warning "Pods KeyBuzz partiels (attendu: ≥5 chacun)"
fi

echo ""

# 3. Vérifier hostNetwork
echo "3. Vérification hostNetwork:"
echo "=============================================================="
TOTAL=$((TOTAL + 1))

API_HOSTNETWORK=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get daemonset keybuzz-api -n keybuzz -o jsonpath='{.spec.template.spec.hostNetwork}' 2>/dev/null" || echo "false")
FRONT_HOSTNETWORK=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get daemonset keybuzz-front -n keybuzz -o jsonpath='{.spec.template.spec.hostNetwork}' 2>/dev/null" || echo "false")

if [[ "$API_HOSTNETWORK" == "true" ]] && [[ "$FRONT_HOSTNETWORK" == "true" ]]; then
    log_success "hostNetwork activé sur les DaemonSets"
    SCORE=$((SCORE + 1))
else
    log_error "hostNetwork non activé"
fi

echo ""

# 4. Vérifier Ingress NGINX
echo "4. Vérification Ingress NGINX:"
echo "=============================================================="
TOTAL=$((TOTAL + 1))

INGRESS_PODS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n ingress-nginx --no-headers 2>/dev/null | grep -c Running" || echo "0")
INGRESS_HOSTNETWORK=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get daemonset -n ingress-nginx -o jsonpath='{.items[0].spec.template.spec.hostNetwork}' 2>/dev/null" || echo "false")

log_info "Ingress NGINX : ${INGRESS_PODS} pods Running"

if [[ $INGRESS_PODS -ge 5 ]] && [[ "$INGRESS_HOSTNETWORK" == "true" ]]; then
    log_success "Ingress NGINX opérationnel (DaemonSet hostNetwork)"
    SCORE=$((SCORE + 1))
else
    log_warning "Ingress NGINX partiel ou non en hostNetwork"
fi

echo ""

# 5. Vérifier les Services NodePort
echo "5. Vérification Services NodePort:"
echo "=============================================================="
TOTAL=$((TOTAL + 1))

API_SVC_TYPE=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc keybuzz-api -n keybuzz -o jsonpath='{.spec.type}' 2>/dev/null" || echo "ClusterIP")
FRONT_SVC_TYPE=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get svc keybuzz-front -n keybuzz -o jsonpath='{.spec.type}' 2>/dev/null" || echo "ClusterIP")

if [[ "$API_SVC_TYPE" == "NodePort" ]] && [[ "$FRONT_SVC_TYPE" == "NodePort" ]]; then
    log_success "Services en NodePort"
    SCORE=$((SCORE + 1))
else
    log_warning "Services en ${API_SVC_TYPE}/${FRONT_SVC_TYPE} (attendu: NodePort)"
fi

echo ""

# 6. Vérifier les Ingress
echo "6. Vérification Ingress KeyBuzz:"
echo "=============================================================="
TOTAL=$((TOTAL + 1))

INGRESS_COUNT=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress -n keybuzz --no-headers 2>/dev/null | wc -l" || echo "0")

if [[ $INGRESS_COUNT -ge 2 ]]; then
    log_success "Ingress KeyBuzz configurés (${INGRESS_COUNT})"
    SCORE=$((SCORE + 1))
    ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get ingress -n keybuzz"
else
    log_error "Ingress KeyBuzz manquants"
fi

echo ""

# 7. Test de connectivité
echo "7. Test de connectivité URLs:"
echo "=============================================================="
TOTAL=$((TOTAL + 1))

SUCCESS_URLS=0

echo -n "  platform.keybuzz.io: "
HTTP_CODE=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" https://platform.keybuzz.io 2>/dev/null || echo "TIMEOUT")
if [[ "$HTTP_CODE" == "200" ]]; then
    log_success "HTTP $HTTP_CODE"
    SUCCESS_URLS=$((SUCCESS_URLS + 1))
else
    log_warning "HTTP $HTTP_CODE"
fi

echo -n "  platform-api.keybuzz.io: "
HTTP_CODE=$(timeout 10 curl -s -o /dev/null -w "%{http_code}" https://platform-api.keybuzz.io 2>/dev/null || echo "TIMEOUT")
if [[ "$HTTP_CODE" == "200" ]]; then
    log_success "HTTP $HTTP_CODE"
    SUCCESS_URLS=$((SUCCESS_URLS + 1))
else
    log_warning "HTTP $HTTP_CODE"
fi

if [[ $SUCCESS_URLS -eq 2 ]]; then
    SCORE=$((SCORE + 1))
fi

echo ""

# Résumé final
echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
PERCENTAGE=$((SCORE * 100 / TOTAL))
log_info "Score : ${SCORE}/${TOTAL} (${PERCENTAGE}%)"
echo ""

if [[ $SCORE -eq $TOTAL ]]; then
    log_success "✅ Correction 504 validée avec succès !"
    echo ""
    log_info "Tous les composants sont opérationnels :"
    log_info "  - DaemonSets KeyBuzz avec hostNetwork"
    log_info "  - Ingress NGINX avec hostNetwork"
    log_info "  - Services NodePort"
    log_info "  - URLs accessibles"
    echo ""
    exit 0
elif [[ $PERCENTAGE -ge 80 ]]; then
    log_warning "⚠️  Correction partiellement validée"
    echo ""
    log_info "La plupart des composants sont opérationnels."
    log_info "Vérifiez les points en échec ci-dessus."
    echo ""
    exit 0
else
    log_error "❌ Correction non validée"
    echo ""
    log_info "Plusieurs composants nécessitent une attention."
    log_info "Relancez 00_fix_504_keybuzz_complete.sh"
    echo ""
    exit 1
fi

