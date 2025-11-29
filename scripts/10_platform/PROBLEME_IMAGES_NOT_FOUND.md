# ⚠️ Problème : Images non trouvées dans GHCR

## ✅ Bonne nouvelle

L'authentification GHCR fonctionne ! Plus d'erreur `403 Forbidden`.

## ❌ Problème actuel

Les images ne sont **pas trouvées** dans GHCR :

- `ghcr.io/keybuzz/platform-api:latest: not found`
- `ghcr.io/keybuzz/platform-ui:latest: not found`
- `ghcr.io/keybuzz/platform-my:latest: not found`

## 🔍 Causes possibles

1. **Les images n'ont pas encore été publiées** dans GHCR
2. **Le nom de l'organisation/package est incorrect** :
   - Peut-être `ghcr.io/keybuzzio/platform-api` au lieu de `ghcr.io/keybuzz/platform-api` ?
   - Peut-être un autre nom de package ?
3. **Les images existent mais avec un tag différent** (pas `latest`)

## ✅ Solutions

### Option 1 : Vérifier les images dans GHCR

1. Aller sur https://github.com/keybuzz?tab=packages
2. Vérifier les noms exacts des packages
3. Vérifier les tags disponibles

### Option 2 : Publier les images

Si les images n'existent pas encore, il faut les builder et les publier :

```bash
# Exemple de build et push
docker build -t ghcr.io/keybuzz/platform-api:latest ./api
docker push ghcr.io/keybuzz/platform-api:latest
```

### Option 3 : Utiliser des images temporaires

En attendant les vraies images, vous pouvez utiliser des images de test publiques :

```bash
export KUBECONFIG=/root/.kube/config

# Utiliser des images de test temporaires
kubectl set image deployment/keybuzz-api -n keybuzz \
  api=nginx:alpine

kubectl set image deployment/keybuzz-ui -n keybuzz \
  ui=nginx:alpine

kubectl set image deployment/keybuzz-my-ui -n keybuzz \
  my-ui=nginx:alpine
```

### Option 4 : Mettre à jour les noms d'images

Si les noms sont incorrects, mettre à jour les Deployments :

```bash
export KUBECONFIG=/root/.kube/config

# Exemple si les images sont dans keybuzzio au lieu de keybuzz
kubectl set image deployment/keybuzz-api -n keybuzz \
  api=ghcr.io/keybuzzio/platform-api:latest

kubectl set image deployment/keybuzz-ui -n keybuzz \
  ui=ghcr.io/keybuzzio/platform-ui:latest

kubectl set image deployment/keybuzz-my-ui -n keybuzz \
  my-ui=ghcr.io/keybuzzio/platform-my:latest
```

## 📋 Checklist

- [ ] Vérifier que les images existent dans GHCR
- [ ] Vérifier les noms exacts des packages
- [ ] Vérifier les tags disponibles
- [ ] Mettre à jour les Deployments avec les bons noms
- [ ] Vérifier que les pods peuvent pull les images

## 🔍 Commandes de diagnostic

```bash
export KUBECONFIG=/root/.kube/config

# Vérifier les images configurées
kubectl get deployments -n keybuzz -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.template.spec.containers[0].image}{"\n"}{end}'

# Vérifier les événements
kubectl get events -n keybuzz --sort-by='.lastTimestamp' | grep -i 'image\|pull' | tail -10

# Tester le pull manuel (depuis un node)
# (nécessite d'être connecté au node et authentifié)
```

