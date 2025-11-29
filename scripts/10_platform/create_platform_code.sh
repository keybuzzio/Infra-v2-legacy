#!/usr/bin/env bash
#
# create_platform_code.sh - Crée la structure de code Platform
#

set -euo pipefail

BASE_DIR="/opt/keybuzz-platform"

echo "=============================================================="
echo " [KeyBuzz] Création de la structure de code Platform"
echo "=============================================================="
echo ""

mkdir -p "${BASE_DIR}/platform-api/app"
mkdir -p "${BASE_DIR}/platform-ui"

# API - main.py
cat > "${BASE_DIR}/platform-api/app/main.py" <<'EOF'
from fastapi import FastAPI
from fastapi.responses import JSONResponse

app = FastAPI(title="KeyBuzz Platform API", version="0.1.1")

@app.get("/health")
async def health():
    return JSONResponse({"status": "ok", "service": "keybuzz-platform-api"}, status_code=200)

@app.get("/")
async def root():
    return {"message": "KeyBuzz Platform API - placeholder"}

# Endpoints futurs (auth, tenants, etc.) pourront être ajoutés ici plus tard
EOF

# API - requirements.txt
cat > "${BASE_DIR}/platform-api/requirements.txt" <<'EOF'
fastapi==0.115.0
uvicorn[standard]==0.30.0
EOF

# API - Dockerfile
cat > "${BASE_DIR}/platform-api/Dockerfile" <<'EOF'
FROM python:3.12-slim

WORKDIR /app

# Install deps
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy app
COPY app ./app

ENV PORT=8080
EXPOSE 8080

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8080"]
EOF

# UI - index.html
cat > "${BASE_DIR}/platform-ui/index.html" <<'EOF'
<!DOCTYPE html>
<html lang="fr">
  <head>
    <meta charset="UTF-8" />
    <title>KeyBuzz Platform UI</title>
  </head>
  <body>
    <h1>KeyBuzz Platform</h1>
    <p>Frontend KeyBuzz - placeholder (infra OK).</p>
    <p>API: <a href="https://platform-api.keybuzz.io/health" target="_blank">/health</a></p>
  </body>
</html>
EOF

# UI - Dockerfile
cat > "${BASE_DIR}/platform-ui/Dockerfile" <<'EOF'
FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
EOF

echo "✅ Structure créée dans ${BASE_DIR}"
echo ""
echo "Fichiers créés:"
find "${BASE_DIR}" -type f | sort
echo ""

