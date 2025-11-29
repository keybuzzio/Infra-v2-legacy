# Troubleshooting - Déploiement MinIO Distributed

## Problème initial
Erreur `docker: invalid reference format` lors du déploiement de MinIO en mode distribué.

## Problèmes identifiés

### 1. Image MinIO inexistante
- **Problème** : L'image `minio/minio:RELEASE.2024-10-02T10-00Z` n'existe pas dans Docker Hub
- **Solution** : Utiliser `minio/minio:latest` (corrigé dans `versions.yaml`)

### 2. Interpolation SSH complexe
- **Problème** : Les heredocs SSH avec interpolation de variables complexes causent des erreurs
- **Tentatives** :
  - Heredoc avec interpolation directe → Variables corrompues
  - Heredoc avec placeholders + `sed` → Script temporaire corrompu (`"INIO_IMAGE_ARG=` au lieu de `MINIO_IMAGE_ARG=`)
  - `printf` pour construire le script → Problèmes avec caractères spéciaux

### 3. Format de commande Docker
- **Problème** : La commande Docker avec tableau d'arguments mal formée
- **Tests validés** : Tous les formats fonctionnent en test direct :
  - Commande directe
  - Tableau avec guillemets : `"${MINIO_CMD_ARGS[@]}"`
  - Tableau sans guillemets : `${MINIO_CMD_ARGS[@]}`
  - Chaîne avec eval

## Solution actuelle

### Approche : Script temporaire créé localement puis copié
1. Créer le script temporaire sur `install-01` avec toutes les valeurs intégrées
2. Copier le script sur le serveur MinIO via `scp`
3. Exécuter le script sur le serveur distant
4. Nettoyer le script temporaire

### Format utilisé
- Utilisation de `printf` pour les variables (échappement automatique)
- Heredoc avec quotes simples pour le reste du script
- Tableau d'arguments avec guillemets : `"${MINIO_CMD_ARGS[@]}"`

## Problème persistant

L'erreur `docker: invalid reference format` persiste, indiquant que :
- Soit le script temporaire est toujours corrompu lors de la création
- Soit la commande Docker est mal formée dans le script temporaire

## Problème persistant identifié

Le diagnostic montre que le script temporaire est **toujours corrompu** même avec `printf` :
- `"INIO_IMAGE_ARG=` au lieu de `MINIO_IMAGE_ARG=`
- Le premier caractère `M` est manquant

Cela suggère que :
1. Le problème vient de la création/copie du script (fin de ligne Windows vs Linux ?)
2. Ou d'un problème d'encodage/échappement lors de la copie via `scp`

## Solution finale recommandée

### Option 1 : Créer le script directement sur le serveur distant
Au lieu de créer le script localement puis le copier, créer le script directement sur le serveur distant via SSH heredoc, mais avec une approche plus simple.

### Option 2 : Utiliser une commande Docker directe sans tableau
Simplifier la commande Docker pour éviter les problèmes d'expansion de tableau :
```bash
docker run -d --name minio \
  --restart always \
  --network host \
  -v /opt/keybuzz/minio/data:/data \
  -e MINIO_ROOT_USER="${MINIO_ROOT_USER_ARG}" \
  -e MINIO_ROOT_PASSWORD="${MINIO_ROOT_PASSWORD_ARG}" \
  "${MINIO_IMAGE_ARG}" \
  server ${MINIO_VOLUMES_STR} --console-address :9001
```

### Option 3 : Utiliser `envsubst` ou template
Créer un template de script et utiliser `envsubst` pour remplacer les variables de manière sûre.

## Prochaines étapes recommandées

1. **Tester Option 2** : Simplifier la commande Docker pour éviter les tableaux
2. **Vérifier les fins de ligne** : S'assurer que le script utilise des fins de ligne Unix (`\n`)
3. **Tester avec une commande minimale** : Créer un script de test minimal pour valider l'approche

## Solution finale implémentée

### Approche : Heredoc SSH direct
Au lieu de créer un script temporaire localement puis le copier, le script est maintenant exécuté directement sur le serveur distant via SSH heredoc.

**Avantages** :
- Pas de problème de création/copie de fichier
- Pas de problème de fin de ligne Windows vs Linux
- Variables interpolées directement dans le heredoc
- Plus simple et plus fiable

**Format utilisé** :
- Heredoc SSH avec interpolation des variables locales
- Tableau d'arguments construit dans le heredoc
- Expansion du tableau sans guillemets : `${MINIO_CMD_ARGS[@]}` (validé par les tests)

## Notes techniques

- Le script est exécuté directement sur le serveur distant via SSH heredoc
- Les variables locales sont interpolées dans le heredoc
- Le tableau d'arguments est construit dans le heredoc pour éviter les problèmes d'espaces
- Expansion du tableau sans guillemets pour permettre l'expansion correcte de chaque élément

