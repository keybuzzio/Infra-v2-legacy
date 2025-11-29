# Images Docker pour KeyBuzz API & Front

**Date** : 20 novembre 2025  
**Statut** : ⚠️ Images à construire

---

## 🎯 Images Requises

### KeyBuzz API
- **Image** : `ghcr.io/keybuzz/api:latest` (ou votre registry)
- **Type** : Backend API (Python/FastAPI ou Node.js)
- **Port** : 8080
- **Healthcheck** : `/health`

### KeyBuzz Front
- **Image** : `ghcr.io/keybuzz/front:latest` (ou votre registry)
- **Type** : Frontend static (Vue/React) servi via NGINX
- **Port** : 80
- **Healthcheck** : `/`

---

## 🔧 Configuration Actuelle

Les scripts utilisent actuellement des **images placeholder** (`nginx:alpine`) pour tester la configuration Kubernetes.

### Pour utiliser vos images réelles

**Option 1 : Variable d'environnement**
```bash
export KEYBUZZ_API_IMAGE="ghcr.io/keybuzz/api:v1.0.0"
export KEYBUZZ_FRONT_IMAGE="ghcr.io/keybuzz/front:v1.0.0"
./10_keybuzz_apply_all.sh
```

**Option 2 : Modifier les scripts**
Éditez `10_keybuzz_01_deploy_api.sh` et `10_keybuzz_02_deploy_front.sh` :
```bash
KEYBUZZ_API_IMAGE="${KEYBUZZ_API_IMAGE:-ghcr.io/keybuzz/api:latest}"
KEYBUZZ_FRONT_IMAGE="${KEYBUZZ_FRONT_IMAGE:-ghcr.io/keybuzz/front:latest}"
```

---

## 🏗️ Construction des Images

### KeyBuzz API

**Dockerfile exemple** :
```dockerfile
FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir \
    fastapi==0.104.1 \
    uvicorn[standard]==0.24.0 \
    psycopg2-binary==2.9.9 \
    redis==5.0.1 \
    pika==1.3.2

# Copy application
COPY . /app

# Expose port
EXPOSE 8080

# Healthcheck
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:8080/health || exit 1

# Run
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
```

**Build** :
```bash
docker build -t ghcr.io/keybuzz/api:v1.0.0 .
docker push ghcr.io/keybuzz/api:v1.0.0
```

### KeyBuzz Front

**Dockerfile exemple** :
```dockerfile
# Stage 1: Build
FROM node:18-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Stage 2: Serve
FROM nginx:alpine
COPY --from=builder /app/dist /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

**Build** :
```bash
docker build -t ghcr.io/keybuzz/front:v1.0.0 .
docker push ghcr.io/keybuzz/front:v1.0.0
```

---

## 📝 Variables d'Environnement Requises

### KeyBuzz API
- `DATABASE_URL` : PostgreSQL connection string
- `REDIS_URL` : Redis connection string
- `RABBITMQ_URL` : RabbitMQ connection string
- `MINIO_URL` : MinIO endpoint
- `VECTOR_URL` : Qdrant endpoint (optionnel)
- `LLM_URL` : LiteLLM endpoint (optionnel)
- `PORT` : Port d'écoute (défaut: 8080)

### KeyBuzz Front
- `API_URL` : URL de l'API KeyBuzz (défaut: `http://keybuzz-api.keybuzz.svc.cluster.local`)

---

## ✅ Checklist

- [ ] Images Docker construites
- [ ] Images poussées vers le registry (GHCR ou autre)
- [ ] Variables d'environnement configurées dans les scripts
- [ ] Healthchecks activés dans les Deployments
- [ ] Tests de validation passés

---

**Note** : Les scripts actuels utilisent `nginx:alpine` comme placeholder pour valider la configuration Kubernetes. Remplacez par vos images réelles une fois construites.

