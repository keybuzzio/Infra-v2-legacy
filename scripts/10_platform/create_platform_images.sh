#!/usr/bin/env bash
#
# create_platform_images.sh - Crée les fichiers des images placeholder
#

set -euo pipefail

BASE_DIR="/opt/keybuzz-installer-v2/platform-images"

mkdir -p "${BASE_DIR}/api" "${BASE_DIR}/ui" "${BASE_DIR}/my"

# API - app.py
cat > "${BASE_DIR}/api/app.py" <<'EOF'
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/health", methods=["GET"])
def health():
    return jsonify(status="ok", service="keybuzz-api"), 200

@app.route("/", methods=["GET"])
def root():
    return "KeyBuzz API placeholder", 200

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8080)
EOF

# API - requirements.txt
cat > "${BASE_DIR}/api/requirements.txt" <<'EOF'
flask==3.0.0
EOF

# API - Dockerfile
cat > "${BASE_DIR}/api/Dockerfile" <<'EOF'
FROM python:3.12-slim

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

ENV PORT=8080
EXPOSE 8080

CMD ["python", "app.py"]
EOF

# UI - index.html
cat > "${BASE_DIR}/ui/index.html" <<'EOF'
<!DOCTYPE html>
<html>
  <head>
    <title>KeyBuzz Platform UI</title>
  </head>
  <body>
    <h1>KeyBuzz Platform UI - Placeholder</h1>
    <p>Infra OK, on branchera le vrai front plus tard.</p>
  </body>
</html>
EOF

# UI - Dockerfile
cat > "${BASE_DIR}/ui/Dockerfile" <<'EOF'
FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
EOF

# My - index.html
cat > "${BASE_DIR}/my/index.html" <<'EOF'
<!DOCTYPE html>
<html>
  <head>
    <title>KeyBuzz My Portal</title>
  </head>
  <body>
    <h1>KeyBuzz My Portal - Placeholder</h1>
    <p>Portail client, infra validée.</p>
  </body>
</html>
EOF

# My - Dockerfile
cat > "${BASE_DIR}/my/Dockerfile" <<'EOF'
FROM nginx:alpine

COPY index.html /usr/share/nginx/html/index.html
EXPOSE 80
EOF

echo "✅ Tous les fichiers ont été créés dans ${BASE_DIR}"
find "${BASE_DIR}" -type f | sort

