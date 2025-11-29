#!/usr/bin/env bash
#
# build_and_push_images.sh - Build et push les images placeholder dans GHCR
#
# Usage:
#   export GITHUB_TOKEN=ghp_xxxxx
#   ./build_and_push_images.sh

set -euo pipefail

GITHUB_TOKEN="${GITHUB_TOKEN:-}"

if [ -z "$GITHUB_TOKEN" ]; then
    echo "❌ GITHUB_TOKEN non défini"
    echo "Usage: export GITHUB_TOKEN=ghp_xxxxx && ./build_and_push_images.sh"
    exit 1
fi

BASE_DIR="/opt/keybuzz-installer-v2/platform-images"

echo "=============================================================="
echo " [KeyBuzz] Build et Push des images placeholder dans GHCR"
echo "=============================================================="
echo ""

# 1. Connexion à GHCR
echo "🔐 Connexion à GHCR..."
echo "$GITHUB_TOKEN" | docker login ghcr.io -u keybuzzio --password-stdin
echo "✅ Connecté à GHCR"
echo ""

# 2. Build et push API
echo "📦 Building API..."
cd "${BASE_DIR}/api"
docker build -t ghcr.io/keybuzzio/platform-api:0.1.0 .
docker push ghcr.io/keybuzzio/platform-api:0.1.0
echo "✅ API pushed: ghcr.io/keybuzzio/platform-api:0.1.0"
echo ""

# 3. Build et push UI
echo "📦 Building UI..."
cd "${BASE_DIR}/ui"
docker build -t ghcr.io/keybuzzio/platform-ui:0.1.0 .
docker push ghcr.io/keybuzzio/platform-ui:0.1.0
echo "✅ UI pushed: ghcr.io/keybuzzio/platform-ui:0.1.0"
echo ""

# 4. Build et push My
echo "📦 Building My..."
cd "${BASE_DIR}/my"
docker build -t ghcr.io/keybuzzio/platform-my:0.1.0 .
docker push ghcr.io/keybuzzio/platform-my:0.1.0
echo "✅ My pushed: ghcr.io/keybuzzio/platform-my:0.1.0"
echo ""

echo "=============================================================="
echo "✅ Toutes les images ont été poussées dans GHCR"
echo "=============================================================="
echo ""
echo "Images disponibles:"
echo "  - ghcr.io/keybuzzio/platform-api:0.1.0"
echo "  - ghcr.io/keybuzzio/platform-ui:0.1.0"
echo "  - ghcr.io/keybuzzio/platform-my:0.1.0"
echo ""

