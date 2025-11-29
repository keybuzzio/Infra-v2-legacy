#!/usr/bin/env bash
#
# redis-update-master.sh - Script de mise à jour automatique du master Redis dans HAProxy
#
# Ce script interroge Sentinel pour détecter le master Redis actuel,
# puis met à jour la configuration HAProxy pour pointer vers ce master.
#
# Usage:
#   ./redis-update-master.sh [redis-sentinel-ip] [haproxy-config-file]
#
# Prérequis:
#   - Redis Sentinel accessible
#   - HAProxy configuré avec backend be_redis_master
#   - Exécuter depuis haproxy-01 ou haproxy-02
#
# Ce script doit être exécuté :
#   - Au boot (via systemd service)
#   - À intervalles réguliers (cron toutes les 15s/30s)
#   - Ou via hook Sentinel (notif script)

set -euo pipefail

# Configuration par défaut
SENTINEL_IP="${1:-10.0.0.123}"
SENTINEL_PORT="${SENTINEL_PORT:-26379}"
MASTER_NAME="${MASTER_NAME:-keybuzz-master}"
HAPROXY_CONFIG="${2:-/opt/keybuzz/haproxy/haproxy.cfg}"
HAPROXY_TEMP_CONFIG="${HAPROXY_CONFIG}.tmp"
REDIS_PASSWORD="${REDIS_PASSWORD:-}"

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

# Vérifier que HAProxy config existe
if [[ ! -f "${HAPROXY_CONFIG}" ]]; then
    log_error "Fichier HAProxy config introuvable: ${HAPROXY_CONFIG}"
    exit 1
fi

# Interroger Sentinel pour obtenir l'IP du master
log_info "Interrogation de Sentinel (${SENTINEL_IP}:${SENTINEL_PORT}) pour le master '${MASTER_NAME}'..."

if [[ -n "${REDIS_PASSWORD}" ]]; then
    MASTER_ADDR=$(redis-cli -h "${SENTINEL_IP}" -p "${SENTINEL_PORT}" -a "${REDIS_PASSWORD}" SENTINEL get-master-addr-by-name "${MASTER_NAME}" 2>/dev/null | head -1)
else
    MASTER_ADDR=$(redis-cli -h "${SENTINEL_IP}" -p "${SENTINEL_PORT}" SENTINEL get-master-addr-by-name "${MASTER_NAME}" 2>/dev/null | head -1)
fi

if [[ -z "${MASTER_ADDR}" ]] || [[ "${MASTER_ADDR}" == "null" ]]; then
    log_error "Impossible de récupérer l'adresse du master depuis Sentinel"
    exit 1
fi

# Extraire IP et PORT
MASTER_IP=$(echo "${MASTER_ADDR}" | cut -d' ' -f1)
MASTER_PORT=$(echo "${MASTER_ADDR}" | cut -d' ' -f2)

if [[ -z "${MASTER_IP}" ]] || [[ -z "${MASTER_PORT}" ]]; then
    log_error "Format d'adresse master invalide: ${MASTER_ADDR}"
    exit 1
fi

log_info "Master Redis détecté: ${MASTER_IP}:${MASTER_PORT}"

# Vérifier que le master est accessible
if ! timeout 2 redis-cli -h "${MASTER_IP}" -p "${MASTER_PORT}" ${REDIS_PASSWORD:+-a "${REDIS_PASSWORD}"} PING >/dev/null 2>&1; then
    log_warning "Le master ${MASTER_IP}:${MASTER_PORT} n'est pas accessible, on garde la config actuelle"
    exit 0
fi

# Lire la config HAProxy actuelle
log_info "Lecture de la configuration HAProxy..."

# Créer une copie temporaire
cp "${HAPROXY_CONFIG}" "${HAPROXY_TEMP_CONFIG}"

# Mettre à jour la ligne server redis-master dans le backend be_redis_master
# Format attendu: server redis-master <IP>:<PORT> check
sed -i "s|^[[:space:]]*server[[:space:]]*redis-master[[:space:]]*[0-9.]*:[0-9]*|    server redis-master ${MASTER_IP}:${MASTER_PORT}|g" "${HAPROXY_TEMP_CONFIG}"

# Vérifier que la modification a été effectuée
if ! grep -q "server redis-master ${MASTER_IP}:${MASTER_PORT}" "${HAPROXY_TEMP_CONFIG}"; then
    log_error "Échec de la mise à jour de la configuration HAProxy"
    rm -f "${HAPROXY_TEMP_CONFIG}"
    exit 1
fi

# Valider la configuration HAProxy
log_info "Validation de la configuration HAProxy..."
if ! haproxy -c -f "${HAPROXY_TEMP_CONFIG}" >/dev/null 2>&1; then
    log_error "Configuration HAProxy invalide après modification"
    rm -f "${HAPROXY_TEMP_CONFIG}"
    exit 1
fi

# Remplacer l'ancienne config par la nouvelle
mv "${HAPROXY_TEMP_CONFIG}" "${HAPROXY_CONFIG}"

# Recharger HAProxy sans downtime
log_info "Rechargement de HAProxy (sans downtime)..."
if systemctl is-active --quiet haproxy; then
    systemctl reload haproxy
    log_success "HAProxy rechargé avec succès"
else
    log_warning "HAProxy n'est pas actif, démarrage..."
    systemctl start haproxy
    log_success "HAProxy démarré avec succès"
fi

log_success "Master Redis mis à jour: ${MASTER_IP}:${MASTER_PORT}"

