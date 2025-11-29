# Plan de réinstallation Module 3 - PostgreSQL HA

## ✅ Confirmation

**C'est OK pour moi !** Je suis prêt pour le rebuild des 5 serveurs.

## Serveurs concernés

1. **db-master-01** (10.0.0.120)
2. **db-slave-01** (10.0.0.121)
3. **db-slave-02** (10.0.0.122)
4. **haproxy-01** (10.0.0.11)
5. **haproxy-02** (10.0.0.12)

## Ordre d'installation

### 1. Module 1 & 2 (Base OS & Sécurité)
- Appliquer `base_os.sh` sur les 5 serveurs
- Vérifier volumes XFS montés sur `/opt/keybuzz/postgres/data` (DB nodes)
- Vérifier volumes XFS montés sur `/opt/keybuzz/haproxy/data` (HAProxy nodes)

### 2. Module 3 - PostgreSQL HA (dans l'ordre)

#### Étape 1 : Credentials
- `03_pg_00_setup_credentials.sh` - Génération des credentials PostgreSQL

#### Étape 2 : Patroni Cluster
- `04_postgres16_patroni_raft_FIXED.sh` - Installation Patroni RAFT
  - Construit l'image Docker personnalisée (PostgreSQL 16 + Patroni + pgvector)
  - Configure les 3 nœuds DB
  - Démarre en parallèle pour le quorum RAFT
  - Crée les bases et utilisateurs

#### Étape 3 : HAProxy
- `05_haproxy_patroni_FIXED_V2.sh` - Configuration HAProxy
  - Utilise l'API Patroni pour détecter le leader
  - Configure les 2 nœuds HAProxy

#### Étape 4 : PgBouncer
- `06_pgbouncer_scram_CORRECTED_V5.sh` - Installation PgBouncer
  - Récupère les hash SCRAM depuis PostgreSQL
  - Configure sur les 2 nœuds HAProxy

#### Étape 5 : Normalisation systemd
- `normalize_patroni_systemd.sh` - Normalisation services systemd
  - Désactive postgresql.service
  - Active patroni.service

#### Étape 6 : pgvector
- `install_pgvector_ha.sh` - Installation pgvector
  - Installe sur tous les nœuds
  - Crée l'extension sur le cluster

## Scripts adaptés

Tous les scripts ont été adaptés pour :
- ✅ Détecter automatiquement le chemin de `servers.tsv`
- ✅ Utiliser les bonnes colonnes (HOSTNAME=$3, IP_PRIVEE=$4)
- ✅ Lire depuis `../../servers.tsv` ou `../../inventory/servers.tsv`

## Après le rebuild

Une fois les serveurs rebuild et les volumes remontés :

1. **Vérifier Module 1 & 2** :
   ```bash
   cd /opt/keybuzz-installer/scripts/02_base_os_and_security
   ./apply_base_os_to_all.sh ../../servers.tsv
   ```

2. **Lancer Module 3** :
   ```bash
   cd /opt/keybuzz-installer/scripts/03_postgresql_ha
   ./03_pg_apply_all.sh ../../servers.tsv
   ```

## Notes importantes

- Les volumes XFS doivent être montés AVANT de lancer Patroni
- Le quorum RAFT nécessite que les 3 nœuds démarrent en parallèle
- Les credentials sont générés automatiquement si absents
- Tous les scripts utilisent `servers.tsv` pour la détection automatique


