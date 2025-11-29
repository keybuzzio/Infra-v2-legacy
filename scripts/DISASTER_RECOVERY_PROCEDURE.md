# Procedure de Disaster Recovery - haproxy-01

## Contexte

Le serveur **haproxy-01** (10.0.0.11) est critique pour l'infrastructure KeyBuzz car il fait office de Load Balancer interne pour :
- PostgreSQL (5432)
- PgBouncer (6432)
- Redis (6379)
- RabbitMQ (5672)

En cas de panne hardware ou de rebuild, le serveur doit pouvoir reprendre son role automatiquement.

## Script de Disaster Recovery Automatique

### Script Principal

**Fichier** : `00_disaster_recovery_haproxy_01.sh`

**Fonctionnalites** :
1. **Detection automatique** : Detecte si le serveur est "vide" (apres rebuild)
2. **Reinstallation automatique** : Reinstalle tous les services necessaires
3. **Verification** : Verifie que tous les services sont operationnels

### Utilisation

```bash
# Depuis install-01
cd /opt/keybuzz-installer/scripts

# Mode automatique (detection + reinstallation si necessaire)
bash 00_disaster_recovery_haproxy_01.sh /opt/keybuzz-installer/servers.tsv

# Mode force (reinstallation forcee meme si services detectes)
bash 00_disaster_recovery_haproxy_01.sh /opt/keybuzz-installer/servers.tsv --force
```

### Critères de Detection "Serveur Vide"

Le script considere le serveur comme "vide" si :
- Docker n'est pas installe
- OU le conteneur HAProxy n'existe pas
- OU le repertoire /opt/keybuzz n'existe pas

### Services Reinstalles

1. **Module 1 & 2 : Base OS + Securite**
   - Installation Docker
   - Configuration firewall
   - Configuration reseau
   - Volumes montes (si necessaire)

2. **Module 3 : HAProxy (PostgreSQL + PgBouncer)**
   - Conteneur HAProxy
   - Configuration backends PostgreSQL
   - Configuration backend PgBouncer
   - Ports 5432 et 6432

3. **Module 3 : PgBouncer**
   - Conteneur PgBouncer
   - Configuration SCRAM
   - Integration avec HAProxy

4. **Module 4 : HAProxy Redis**
   - Configuration backend Redis dans HAProxy
   - Script redis-update-master.sh
   - Port 6379

## Prevention Future

### 1. Monitoring Automatique

Creer un script de monitoring qui verifie regulierement l'etat de haproxy-01 :

```bash
#!/usr/bin/env bash
# check_haproxy_01_health.sh

HAPROXY_01_IP="10.0.0.11"

# Verifier SSH
if ! ssh -o ConnectTimeout=5 root@${HAPROXY_01_IP} "echo OK" 2>/dev/null | grep -q "OK"; then
    echo "ALERT: haproxy-01 SSH inaccessible"
    # Declencher disaster recovery automatique
    /opt/keybuzz-installer/scripts/00_disaster_recovery_haproxy_01.sh --force
    exit 1
fi

# Verifier conteneurs
if ! ssh root@${HAPROXY_01_IP} "docker ps | grep -q haproxy" 2>/dev/null; then
    echo "ALERT: haproxy-01 conteneur HAProxy non actif"
    # Declencher disaster recovery automatique
    /opt/keybuzz-installer/scripts/00_disaster_recovery_haproxy_01.sh --force
    exit 1
fi

# Verifier ports
for port in 5432 6432 6379 5672; do
    if ! timeout 3 bash -c "echo > /dev/tcp/${HAPROXY_01_IP}/${port}" 2>/dev/null; then
        echo "ALERT: haproxy-01 port ${port} inaccessible"
        # Declencher disaster recovery automatique
        /opt/keybuzz-installer/scripts/00_disaster_recovery_haproxy_01.sh --force
        exit 1
    fi
done

echo "OK: haproxy-01 operationnel"
```

### 2. Cron Job Automatique

Ajouter un cron job sur install-01 pour verifier toutes les 5 minutes :

```bash
# Crontab sur install-01
*/5 * * * * /opt/keybuzz-installer/scripts/check_haproxy_01_health.sh >> /var/log/haproxy01_health.log 2>&1
```

### 3. Systemd Service (Optionnel)

Creer un service systemd pour le monitoring automatique :

```ini
[Unit]
Description=KeyBuzz HAProxy-01 Health Check
After=network.target

[Service]
Type=oneshot
ExecStart=/opt/keybuzz-installer/scripts/check_haproxy_01_health.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
```

Avec un timer systemd :

```ini
[Unit]
Description=KeyBuzz HAProxy-01 Health Check Timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min

[Install]
WantedBy=timers.target
```

### 4. Backup de Configuration

Sauvegarder regulierement la configuration de haproxy-01 :

```bash
#!/usr/bin/env bash
# backup_haproxy_01_config.sh

HAPROXY_01_IP="10.0.0.11"
BACKUP_DIR="/opt/keybuzz-installer/backups/haproxy-01"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p "${BACKUP_DIR}"

# Backup configuration HAProxy
ssh root@${HAPROXY_01_IP} "docker exec haproxy cat /usr/local/etc/haproxy/haproxy.cfg" > "${BACKUP_DIR}/haproxy_${DATE}.cfg"

# Backup configuration PgBouncer
ssh root@${HAPROXY_01_IP} "docker exec pgbouncer cat /etc/pgbouncer/pgbouncer.ini" > "${BACKUP_DIR}/pgbouncer_${DATE}.ini" 2>/dev/null || true

# Garder seulement les 10 derniers backups
ls -t "${BACKUP_DIR}"/*.cfg 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
ls -t "${BACKUP_DIR}"/*.ini 2>/dev/null | tail -n +11 | xargs rm -f 2>/dev/null || true
```

## Procedure Manuelle (Si le script automatique echoue)

### 1. Verification Prealable

```bash
# Verifier SSH
ssh root@10.0.0.11 "hostname && docker ps"

# Verifier etat
cd /opt/keybuzz-installer/scripts
bash 00_disaster_recovery_haproxy_01.sh /opt/keybuzz-installer/servers.tsv
```

### 2. Reinstallation Manuelle

Si le script automatique echoue, executer manuellement :

```bash
# 1. Base OS
cd /opt/keybuzz-installer/scripts/01_base_os
bash 01_base_os_install.sh /opt/keybuzz-installer/servers.tsv

# 2. HAProxy
cd /opt/keybuzz-installer/scripts/03_postgresql_ha
bash 05_haproxy_patroni_FIXED_V2.sh /opt/keybuzz-installer/servers.tsv

# 3. PgBouncer
cd /opt/keybuzz-installer/scripts/03_postgresql_ha
bash 06_pgbouncer_scram_CORRECTED_V5.sh /opt/keybuzz-installer/servers.tsv

# 4. HAProxy Redis
cd /opt/keybuzz-installer/scripts/04_redis_ha
bash 04_redis_04_configure_haproxy_redis.sh /opt/keybuzz-installer/servers.tsv
```

### 3. Verification Finale

```bash
cd /opt/keybuzz-installer/scripts
bash 00_verification_complete_apres_redemarrage.sh /opt/keybuzz-installer/servers.tsv
```

## Notes Importantes

1. **Load Balancer Hetzner** : Apres reinstallation, verifier que le LB 10.0.0.10 pointe toujours vers haproxy-01 (10.0.0.11) et haproxy-02 (10.0.0.12).

2. **Credentials** : Les credentials doivent etre deja configures sur install-01 dans `/opt/keybuzz-installer/credentials/`.

3. **Dependances** : haproxy-01 depend de :
   - PostgreSQL Patroni cluster (db-master-01, db-slave-01, db-slave-02)
   - Redis cluster (redis-01, redis-02, redis-03)
   - RabbitMQ cluster (queue-01, queue-02, queue-03)

4. **Temps de reinstallation** : Compte environ 10-15 minutes pour une reinstallation complete.

5. **Downtime** : Pendant la reinstallation, haproxy-02 continue de fonctionner, donc pas de downtime complet.

## Ameliorations Futures

1. **Auto-healing automatique** : Integrer le script de disaster recovery dans un systeme de monitoring (Prometheus + Alertmanager)

2. **Backup automatique** : Sauvegarder la configuration avant chaque changement

3. **Tests automatiques** : Apres reinstallation, executer automatiquement les tests de validation

4. **Notification** : Envoyer une alerte (email, Slack, etc.) en cas de disaster recovery declenche

5. **Documentation automatique** : Generer un rapport de disaster recovery avec timestamp et actions effectuees

