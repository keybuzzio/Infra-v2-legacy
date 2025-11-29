#!/usr/bin/env bash
#
# 10_keybuzz_create_test_pages.sh - Création de pages de test pour KeyBuzz
#
# Ce script crée des pages HTML simples dans les pods nginx:alpine
# pour remplacer le placeholder par défaut
#
# Usage:
#   ./10_keybuzz_create_test_pages.sh [servers.tsv]
#

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

# Page HTML pour le Front
FRONT_HTML=$(cat <<'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>KeyBuzz Platform - Frontend</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            margin: 0;
            padding: 0;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
        }
        .container {
            text-align: center;
            padding: 2rem;
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
        }
        p {
            font-size: 1.2rem;
            opacity: 0.9;
        }
        .status {
            background: rgba(255, 255, 255, 0.2);
            padding: 1rem 2rem;
            border-radius: 10px;
            margin-top: 2rem;
            display: inline-block;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🚀 KeyBuzz Platform</h1>
        <p>Frontend déployé avec succès</p>
        <div class="status">
            ✅ Service opérationnel
        </div>
    </div>
</body>
</html>
EOF
)

# Page HTML pour l'API
API_HTML=$(cat <<'EOF'
<!DOCTYPE html>
<html lang="fr">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>KeyBuzz API - Backend</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, Cantarell, sans-serif;
            margin: 0;
            padding: 0;
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
            color: white;
            display: flex;
            justify-content: center;
            align-items: center;
            min-height: 100vh;
        }
        .container {
            text-align: center;
            padding: 2rem;
        }
        h1 {
            font-size: 3rem;
            margin-bottom: 1rem;
        }
        p {
            font-size: 1.2rem;
            opacity: 0.9;
        }
        .status {
            background: rgba(255, 255, 255, 0.2);
            padding: 1rem 2rem;
            border-radius: 10px;
            margin-top: 2rem;
            display: inline-block;
        }
        .endpoint {
            background: rgba(255, 255, 255, 0.1);
            padding: 0.5rem 1rem;
            border-radius: 5px;
            margin-top: 1rem;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔌 KeyBuzz API</h1>
        <p>Backend déployé avec succès</p>
        <div class="status">
            ✅ Service opérationnel
        </div>
        <div class="endpoint">
            GET /health → Status OK
        </div>
    </div>
</body>
</html>
EOF
)

log_info "Création des pages de test dans les pods Front..."
FRONT_PODS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[*].metadata.name}'")

for POD in ${FRONT_PODS}; do
    echo "${FRONT_HTML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n keybuzz ${POD} -- sh -c 'cat > /usr/share/nginx/html/index.html'" > /dev/null 2>&1
    log_success "Page de test créée dans ${POD}"
done

log_info "Création des pages de test dans les pods API..."
API_PODS=$(ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl get pods -n keybuzz -l app=keybuzz-api -o jsonpath='{.items[*].metadata.name}'")

for POD in ${API_PODS}; do
    # Pour l'API, on crée un serveur HTTP simple car nginx:alpine écoute sur 80, pas 8080
    # On va créer un fichier index.html et configurer nginx pour servir sur 8080
    echo "${API_HTML}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n keybuzz ${POD} -- sh -c 'mkdir -p /usr/share/nginx/html && cat > /usr/share/nginx/html/index.html'" > /dev/null 2>&1
    
    # Créer une config nginx pour écouter sur 8080
    NGINX_CONF=$(cat <<'EOF'
events {
    worker_connections 1024;
}
http {
    server {
        listen 8080;
        root /usr/share/nginx/html;
        index index.html;
        location / {
            try_files $uri $uri/ /index.html;
        }
    }
}
EOF
)
    echo "${NGINX_CONF}" | ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n keybuzz ${POD} -- sh -c 'cat > /etc/nginx/nginx.conf'" > /dev/null 2>&1
    
    # Redémarrer nginx dans le pod
    ssh ${SSH_KEY_OPTS} "root@${MASTER_IP}" "kubectl exec -n keybuzz ${POD} -- nginx -s reload" > /dev/null 2>&1 || true
    log_success "Page de test créée dans ${POD}"
done

echo ""
log_success "✅ Pages de test créées"
echo ""
log_info "Les URLs devraient maintenant afficher des pages au lieu de 404"
echo ""

