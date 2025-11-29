#!/usr/bin/env bash
#
# build_and_push_platform.sh - Build et push les vraies images Platform
#
# Usage:
#   export GITHUB_TOKEN=ghp_xxxxx
#   ./build_and_push_platform.sh

set -euo pipefail

GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ GITHUB_TOKEN non défini"
    echo "Usage: export GITHUB_TOKEN=ghp_xxxxx && ./build_and_push_platform.sh"
    exit 1
fi

BASE_DIR="/opt/keybuzz-platform"

echo "=============================================================="
echo " [KeyBuzz] Build et Push des vraies images Platform"
echo "=============================================================="
echo ""

# 1. Connexion à GHCR
echo "🔐 Connexion à GHCR..."
echo "$GITHUB_TOKEN" | docker login ghcr.io -u keybuzzio --password-stdin
echo "✅ Connecté à GHCR"
echo ""

# 2. Build et push API
echo "📦 Building Platform API..."
cd "${BASE_DIR}/platform-api"
docker build -t ghcr.io/keybuzzio/platform-api:0.1.1 .
docker push ghcr.io/keybuzzio/platform-api:0.1.1
echo "✅ API pushed: ghcr.io/keybuzzio/platform-api:0.1.1"
echo ""

# 3. Build et push UI
echo "📦 Building Platform UI..."
cd "${BASE_DIR}/platform-ui"
docker build -t ghcr.io/keybuzzio/platform-ui:0.1.1 .
docker push ghcr.io/keybuzzio/platform-ui:0.1.1
echo "✅ UI pushed: ghcr.io/keybuzzio/platform-ui:0.1.1"
echo ""

echo "=============================================================="
echo "✅ Toutes les images ont été poussées dans GHCR"
echo "=============================================================="
echo ""
echo "Images disponibles:"
echo "  - ghcr.io/keybuzzio/platform-api:0.1.1"
echo "  - ghcr.io/keybuzzio/platform-ui:0.1.1"
echo ""
echo "Note: platform-my utilisera la même image que platform-ui (0.1.1)"
echo ""

