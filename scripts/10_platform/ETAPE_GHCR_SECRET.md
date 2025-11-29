# 🔐 Étape unique : Créer le Secret GHCR et relancer les pods

## 📋 Instructions complètes

### 1. Créer un token GitHub

Sur GitHub (avec le compte qui possède `ghcr.io/keybuzz/...`) :

1. **Settings** → **Developer settings** → **Personal access tokens** → **Tokens (classic)**
2. **Generate new token (classic)**
3. **Scopes minimum** :
   - ✅ `read:packages`
   - (Si keybuzz est une organisation privée : cocher aussi `read:org`)
4. **Generate token**
5. **Copier le token** `ghp_xxxxxx…` (une seule fois, ne le perdez pas !)

### 2. Sur install-01, lancer le script

```bash
export GITHUB_TOKEN=ghp_ton_token_ici
cd /opt/keybuzz-installer-v2/scripts/10_platform
./create_ghcr_secret.sh
```

**Ou avec le token en argument :**

```bash
cd /opt/keybuzz-installer-v2/scripts/10_platform
./create_ghcr_secret.sh ghp_ton_token_ici
```

### 3. Ce que fait le script

Le script `create_ghcr_secret.sh` va :

1. ✅ Créer un Secret `ghcr-secret` dans le namespace `keybuzz`
2. ✅ Le configurer comme `imagePullSecrets` :
   - Sur le ServiceAccount `default` (et/ou spécifiques)
   - Sur les Deployments `keybuzz-api`, `keybuzz-ui`, `keybuzz-my-ui`
3. ✅ Supprimer les pods en erreur pour forcer le redémarrage

### 4. Surveiller les pods

```bash
export KUBECONFIG=/root/.kube/config
kubectl get pods -n keybuzz -w
```

**Évolution attendue :**
- `ErrImagePull` / `ImagePullBackOff` → `ContainerCreating` → `Running` ✅

### 5. Vérifier que tout est prêt

Quand les 3 Deployments sont en **3/3 Ready** :

```bash
# Vérifier l'état final
kubectl get deployments -n keybuzz
kubectl get pods -n keybuzz

# Tester les URLs (si DNS configuré)
curl -k https://platform.keybuzz.io
curl -k https://platform-api.keybuzz.io/health
curl -k https://my.keybuzz.io
```

## ✅ Checklist

- [ ] Token GitHub créé avec permission `read:packages`
- [ ] Secret GHCR créé sur install-01
- [ ] Tous les pods passent en `Running`
- [ ] Les 3 Deployments sont en `3/3 Ready`
- [ ] Les URLs sont accessibles (si DNS configuré)

## 🔍 Dépannage

### Si les pods restent en `ErrImagePull` :

1. Vérifier que le token est correct :
   ```bash
   kubectl get secret ghcr-secret -n keybuzz -o yaml
   ```

2. Vérifier que les Deployments ont `imagePullSecrets` :
   ```bash
   kubectl get deployment keybuzz-api -n keybuzz -o yaml | grep -A 5 imagePullSecrets
   ```

3. Tester le pull manuel :
   ```bash
   docker pull ghcr.io/keybuzz/platform-api:latest
   # (nécessite d'être authentifié avec le token)
   ```

### Si le token expire :

1. Créer un nouveau token GitHub
2. Mettre à jour le Secret :
   ```bash
   kubectl delete secret ghcr-secret -n keybuzz
   export GITHUB_TOKEN=ghp_nouveau_token
   cd /opt/keybuzz-installer-v2/scripts/10_platform
   ./create_ghcr_secret.sh
   ```

