# Module 6 - MinIO S3 HA (Hors K3s)

**Version** : 1.0  
**Date** : 19 novembre 2025  
**Statut** : ⏳ À implémenter

## 🎯 Objectif

Déployer un système S3-compatible robuste et scalable pour KeyBuzz :
- Stockage des backups PostgreSQL/Redis/RabbitMQ/K3s
- Stockage des assets applicatifs (Chatwoot, KeyBuzz Front/Back)
- Stockage des exports (CSV, JSON, snapshots)
- Stockage des pièces jointes (upload clients)
- Stockage des exports d'ERPNext (PDF, factures)
- Haute disponibilité via MinIO Distributed

## 📋 Topologie

### Mode Actuel : Mono-nœud
- **minio-01** : 10.0.0.134 (S3 principal)

### Mode Futur : Cluster HA (3-4 nœuds)
- **minio-01** : 10.0.0.134
- **minio-02** : (à définir)
- **minio-03** : (à définir)
- **minio-04** : (à définir)

## 🔌 Ports

- **9000/tcp** : S3 API (protocole S3)
- **9001/tcp** : Console MinIO (interface web)

## 📦 Scripts (à créer)

1. **`06_minio_00_setup_credentials.sh`** : Configuration des credentials
2. **`06_minio_01_prepare_nodes.sh`** : Préparation des nœuds MinIO
3. **`06_minio_02_install_single.sh`** : Installation mono-nœud
4. **`06_minio_03_configure_client.sh`** : Configuration client mc
5. **`06_minio_04_tests.sh`** : Tests et diagnostics
6. **`06_minio_apply_all.sh`** : Script master

## 🔧 Prérequis

- Module 2 appliqué sur tous les serveurs MinIO
- Docker CE opérationnel
- UFW configuré pour les ports 9000/9001 (réseau privé uniquement)
- Credentials configurés (`minio.env`)
- Volume XFS recommandé pour `/opt/keybuzz/minio/data`

## 📝 Notes Importantes

- **Hors K3s** : MinIO doit être déployé hors Kubernetes pour éviter la dépendance circulaire
- **Bucket par défaut** : `keybuzz-backups`
- **Réseau privé uniquement** : Jamais d'exposition publique
- **Scalabilité** : Mode mono-nœud pour commencer, évolutif en cluster 3-4 nœuds

## 🔗 Références

- Documentation complète : `Context.txt` (section Module 6 - MinIO HA)
- Anciens scripts fonctionnels : `keybuzz-installer/scripts/07-MinIO/` (si disponibles)

---

**Dernière mise à jour** : 19 novembre 2025  
**Statut** : ⏳ Structure créée, scripts à développer

