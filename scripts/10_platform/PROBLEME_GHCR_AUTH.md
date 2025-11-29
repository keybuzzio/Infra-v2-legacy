# 🔐 Problème d'authentification GHCR

## ❌ Erreur identifiée

**Erreur** : `403 Forbidden` lors du pull des images depuis GHCR

**Cause** : Les images `ghcr.io/keybuzz/platform-*` sont privées dans GitHub Container Registry, et Kubernetes n'a pas les credentials pour y accéder.

## ✅ Solution

Créer un Secret Kubernetes avec un token GitHub pour permettre le pull des images privées.

## 📋 Étapes

### 1. Créer un token GitHub

1. Aller sur GitHub → **Settings** → **Developer settings**
2. **Personal access tokens** → **Tokens (classic)**
3. **Generate new token (classic)**
4. **Permissions** : Cocher `read:packages`
5. **Generate token**
6. **Copier le token** (commence par `ghp_`)

### 2. Créer le Secret Kubernetes

**Option 1 - Avec token en argument :**

```bash
cd /opt/keybuzz-installer-v2/scripts/10_platform
./create_ghcr_secret.sh ghp_votre_token_github
```

**Option 2 - Avec variable d'environnement :**

```bash
export GITHUB_TOKEN=ghp_votre_token_github
cd /opt/keybuzz-installer-v2/scripts/10_platform
./create_ghcr_secret.sh
```

### 3. Vérifier que les pods peuvent pull les images

```bash
export KUBECONFIG=/root/.kube/config

# Vérifier l'état des pods
kubectl get pods -n keybuzz -w

# Les pods devraient passer de ErrImagePull à Running
```

## 🔍 Vérification

Après avoir créé le Secret, les Deployments seront automatiquement mis à jour avec `imagePullSecrets`. Les pods vont redémarrer et pouvoir télécharger les images.

```bash
# Vérifier que le Secret existe
kubectl get secret ghcr-secret -n keybuzz

# Vérifier que les Deployments ont imagePullSecrets
kubectl get deployment keybuzz-api -n keybuzz -o yaml | grep -A 5 imagePullSecrets
```

## 📝 Note

Le script `create_ghcr_secret.sh` :
- Crée le Secret `ghcr-secret` dans le namespace `keybuzz`
- Ajoute `imagePullSecrets` aux 3 Deployments (api, ui, my-ui)
- Permet aux pods de pull les images privées depuis GHCR

