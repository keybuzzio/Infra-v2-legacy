# Module 6 - MinIO S3 HA - Validation

**Date** : 19 novembre 2025  
**Statut** : ✅ Opérationnel

## Résumé

Le Module 6 (MinIO S3 HA) a été installé et validé avec succès. MinIO est opérationnel en mode mono-nœud, le bucket `keybuzz-backups` est créé avec versioning activé, et le client `mc` est configuré.

## Composants installés

### MinIO
- **1 nœud MinIO** : minio-01 (10.0.0.134)
- **Version** : MinIO latest
- **Mode** : Mono-nœud (évolutif vers cluster 3-4 nœuds)
- **Network** : --network host
- **Bucket** : keybuzz-backups (avec versioning)

### Client mc
- **Installé sur** : install-01
- **Alias** : minio → http://10.0.0.134:9000
- **Statut** : Configuré et opérationnel

## Points d'accès

- **S3 API** : http://10.0.0.134:9000
- **Console** : http://10.0.0.134:9001
- **Bucket** : keybuzz-backups

## Credentials

- **User** : admin-<random> (généré automatiquement)
- **Password** : Généré automatiquement (stocké dans `/opt/keybuzz-installer/credentials/minio.env`)
- **Bucket** : keybuzz-backups

## Tests effectués

✅ **Connectivité** : Port 9000 (S3 API) accessible  
✅ **Client mc** : Installé et configuré  
✅ **Bucket** : Créé et accessible  
✅ **Versioning** : Activé sur le bucket  
✅ **Upload/Download** : Tests réussis  
✅ **Docker** : Conteneur en cours d'exécution  

## Scripts disponibles

1. `06_minio_00_setup_credentials.sh` - Configuration des credentials
2. `06_minio_01_prepare_nodes.sh` - Préparation des nœuds
3. `06_minio_02_install_single.sh` - Installation mono-nœud
4. `06_minio_03_configure_client.sh` - Configuration client mc
5. `06_minio_04_tests.sh` - Tests et diagnostics
6. `06_minio_apply_all.sh` - Script master

## Commandes utiles

### Lister les buckets
```bash
mc ls minio
```

### Lister le contenu d'un bucket
```bash
mc ls minio/keybuzz-backups/
```

### Upload un fichier
```bash
mc cp <file> minio/keybuzz-backups/
```

### Download un fichier
```bash
mc cp minio/keybuzz-backups/<file> <destination>
```

### Informations admin
```bash
mc admin info minio
```

### Health check
```bash
curl http://10.0.0.134:9000/minio/health/live
```

## Notes importantes

- MinIO est déployé **hors K3s** pour éviter la dépendance circulaire
- Le bucket `keybuzz-backups` est utilisé pour stocker les backups de PostgreSQL, Redis, RabbitMQ, etc.
- Le versioning est activé pour permettre la récupération de versions précédentes
- MinIO est accessible uniquement sur le réseau privé (10.0.0.0/16)
- Évolutif vers un cluster 3-4 nœuds pour HA complète

## Migration future vers cluster HA

Pour migrer vers un cluster HA (3-4 nœuds), utiliser le script :
- `06_minio_03_install_cluster.sh` (à créer si nécessaire)

## Intégration avec autres modules

✅ **Module 3 (PostgreSQL)** : MinIO peut stocker les backups PostgreSQL  
✅ **Module 4 (Redis)** : MinIO peut stocker les snapshots Redis  
✅ **Module 5 (RabbitMQ)** : MinIO peut stocker les exports RabbitMQ  

---

**Dernière mise à jour** : 19 novembre 2025  
**Validé par** : Scripts automatisés et tests manuels

