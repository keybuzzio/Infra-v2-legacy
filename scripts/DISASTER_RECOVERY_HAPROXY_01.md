# Disaster Recovery - haproxy-01

## Contexte

Le serveur **haproxy-01** (10.0.0.11) est critique pour l'infrastructure KeyBuzz. En cas de panne hardware ou de rebuild, il doit pouvoir reprendre son role automatiquement.

**IMPORTANT** : Conforme au Context.txt, **tous les scripts doivent etre executes depuis install-01 uniquement**, jamais depuis Windows.

## Script de Disaster Recovery

### Fichier

`00_disaster_recovery_haproxy_01_SIMPLE.sh`

### Execution

**Depuis install-01 uniquement** :

```bash
# Se connecter a install-01
ssh root@91.98.128.153

# Aller dans le repertoire des scripts
cd /opt/keybuzz-installer/scripts

# Executer le script de disaster recovery
bash 00_disaster_recovery_haproxy_01_SIMPLE.sh
```

### Ce que fait le script

1. **Verification SSH** : Verifie l'acces SSH a haproxy-01
2. **Detection** : Detecte si le serveur est vide (pas de Docker, pas de conteneurs)
3. **Reinstallation automatique** :
   - **Base OS** : Installation Docker, firewall, configuration reseau
   - **HAProxy PostgreSQL** : Configuration HAProxy pour PostgreSQL (port 5432)
   - **HAProxy Redis** : Configuration HAProxy pour Redis (port 6379)
4. **Verification finale** : Verifie que tous les conteneurs sont actifs

### Services reinstalles

- **Base OS** : Module 2 (Docker, UFW, configuration reseau)
- **HAProxy PostgreSQL** : Module 3 (port 5432, backend Patroni)
- **HAProxy Redis** : Module 4 (port 6379, backend Redis master)

### Verification apres execution

```bash
# Depuis install-01
cd /opt/keybuzz-installer/scripts

# Verifier l'etat de haproxy-01
ssh root@10.0.0.11 "docker ps"

# Verifier les ports
timeout 3 bash -c "echo > /dev/tcp/10.0.0.11/5432" && echo "Port 5432 OK"
timeout 3 bash -c "echo > /dev/tcp/10.0.0.11/6379" && echo "Port 6379 OK"

# Verification complete de l'infrastructure
bash 00_verification_complete_apres_redemarrage.sh /opt/keybuzz-installer/servers.tsv
```

## Prevention Future

### Monitoring automatique (a implementer)

Creer un script de monitoring qui verifie regulierement l'etat de haproxy-01 :

```bash
#!/usr/bin/env bash
# check_haproxy_01_health.sh

HAPROXY_01_IP="10.0.0.11"

# Verifier SSH
if ! ssh -o ConnectTimeout=5 root@${HAPROXY_01_IP} "echo OK" 2>/dev/null | grep -q "OK"; then
    echo "ALERT: haproxy-01 SSH inaccessible"
    /opt/keybuzz-installer/scripts/00_disaster_recovery_haproxy_01_SIMPLE.sh
    exit 1
fi

# Verifier conteneurs
if ! ssh root@${HAPROXY_01_IP} "docker ps | grep -q haproxy" 2>/dev/null; then
    echo "ALERT: haproxy-01 conteneur HAProxy non actif"
    /opt/keybuzz-installer/scripts/00_disaster_recovery_haproxy_01_SIMPLE.sh
    exit 1
fi

# Verifier ports
for port in 5432 6379; do
    if ! timeout 3 bash -c "echo > /dev/tcp/${HAPROXY_01_IP}/${port}" 2>/dev/null; then
        echo "ALERT: haproxy-01 port ${port} inaccessible"
        /opt/keybuzz-installer/scripts/00_disaster_recovery_haproxy_01_SIMPLE.sh
        exit 1
    fi
done

echo "OK: haproxy-01 operationnel"
```

### Cron job (a implementer)

Ajouter sur install-01 :

```bash
# Crontab sur install-01
*/5 * * * * /opt/keybuzz-installer/scripts/check_haproxy_01_health.sh >> /var/log/haproxy01_health.log 2>&1
```

## Notes Importantes

1. **Execution depuis install-01 uniquement** : Conforme au Context.txt
2. **Load Balancer Hetzner** : Apres reinstallation, verifier que le LB 10.0.0.10 pointe vers haproxy-01 (10.0.0.11) et haproxy-02 (10.0.0.12)
3. **Credentials** : Les credentials doivent etre deja configures sur install-01 dans `/opt/keybuzz-installer/credentials/`
4. **Dependances** : haproxy-01 depend de :
   - PostgreSQL Patroni cluster (db-master-01, db-slave-01, db-slave-02)
   - Redis cluster (redis-01, redis-02, redis-03)
   - RabbitMQ cluster (queue-01, queue-02, queue-03)

## Temps d'execution

- Base OS : ~5-10 minutes
- HAProxy PostgreSQL : ~2-3 minutes
- HAProxy Redis : ~2-3 minutes
- **Total** : ~10-15 minutes

