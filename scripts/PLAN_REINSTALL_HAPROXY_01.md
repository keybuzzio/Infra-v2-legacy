# Plan de Reinstallation haproxy-01 apres Rebuild

## Situation

Le serveur **haproxy-01** (10.0.0.11) est HS apres le redemarrage. Erreur de boot "No bootable device". Un rebuild complet est necessaire via Hetzner.

## Serveur concerne

- **haproxy-01** (10.0.0.11)
- **Role** : Load Balancer interne (HAProxy)
- **Services** :
  - HAProxy pour PostgreSQL (5432)
  - HAProxy pour PgBouncer (6432)
  - HAProxy pour Redis (6379)
  - HAProxy pour RabbitMQ (5672)

## Ordre de Reinstallation

### 1. Module 1 & 2 : Base OS + Securite

**Script** : `01_base_os/01_base_os_install.sh`

**Commande** :
```bash
cd /opt/keybuzz-installer/scripts/01_base_os
bash 01_base_os_install.sh /opt/keybuzz-installer/servers.tsv haproxy-01
```

**Verifications** :
- SSH accessible
- Volumes montes (si necessaire)
- Firewall configure
- Docker installe

### 2. Module 3 : HAProxy (PostgreSQL + PgBouncer)

**Script** : `03_postgresql_ha/05_haproxy_patroni_FIXED_V2.sh`

**Commande** :
```bash
cd /opt/keybuzz-installer/scripts/03_postgresql_ha
bash 05_haproxy_patroni_FIXED_V2.sh /opt/keybuzz-installer/servers.tsv haproxy-01
```

**Verifications** :
- Conteneur HAProxy demarre
- Ports 5432 et 6432 accessibles
- Backend PostgreSQL configure
- Backend PgBouncer configure

### 3. Module 3 : PgBouncer

**Script** : `03_postgresql_ha/06_pgbouncer_scram_CORRECTED_V5.sh`

**Commande** :
```bash
cd /opt/keybuzz-installer/scripts/03_postgresql_ha
bash 06_pgbouncer_scram_CORRECTED_V5.sh /opt/keybuzz-installer/servers.tsv haproxy-01
```

**Verifications** :
- Conteneur PgBouncer demarre
- Port 6432 accessible via HAProxy
- Configuration SCRAM correcte

### 4. Module 4 : HAProxy Redis

**Script** : `04_redis_ha/04_redis_04_configure_haproxy_redis.sh`

**Commande** :
```bash
cd /opt/keybuzz-installer/scripts/04_redis_ha
bash 04_redis_04_configure_haproxy_redis.sh /opt/keybuzz-installer/servers.tsv haproxy-01
```

**Verifications** :
- Backend Redis configure dans HAProxy
- Port 6379 accessible via HAProxy (10.0.0.10:6379)
- Script redis-update-master.sh configure

### 5. Verification Complete

**Script** : `00_verification_complete_apres_redemarrage.sh`

**Commande** :
```bash
cd /opt/keybuzz-installer/scripts
bash 00_verification_complete_apres_redemarrage.sh /opt/keybuzz-installer/servers.tsv
```

**Resultat attendu** :
- HAProxy container on haproxy-01 : [OK]
- HAProxy PostgreSQL port 5432 : [OK]
- HAProxy PgBouncer port 6432 : [OK]
- HAProxy Redis port 6379 : [OK]

## Notes Importantes

1. **Scripts a adapter** : Les scripts d'installation peuvent etre configures pour traiter tous les serveurs ou un serveur specifique. Verifier que les scripts acceptent un parametre de serveur cible.

2. **Load Balancer Hetzner** : Le LB 10.0.0.10 doit pointer vers haproxy-01 (10.0.0.11) et haproxy-02 (10.0.0.12). Verifier la configuration apres reinstallation.

3. **Credentials** : Les credentials doivent etre deja configures sur install-01 dans `/opt/keybuzz-installer/credentials/`.

4. **Dependances** : haproxy-01 depend de :
   - PostgreSQL Patroni cluster (db-master-01, db-slave-01, db-slave-02)
   - Redis cluster (redis-01, redis-02, redis-03)
   - RabbitMQ cluster (queue-01, queue-02, queue-03)

## Apres Reinstallation

Une fois haproxy-01 reinstalle, les problemes restants a corriger sont :

1. **Patroni cluster** : Forcer le bootstrap du leader
2. **Redis Sentinel** : Reconfigurer pour detecter le master

Ensuite, relancer la verification complete pour atteindre 100% de succes.

