# Infrastructure KeyBuzz

Ce dépôt contient toute l'infrastructure d'installation et de configuration pour la plateforme KeyBuzz.

## Structure

```
Infra/
├── docs/                    # Documentation complète de l'infrastructure
│   ├── 01_intro.md
│   ├── 02_base_os_and_security.md
│   ├── 03_postgresql_ha.md
│   ├── 04_redis_ha.md
│   ├── 05_rabbitmq_ha.md
│   ├── 06_k3s_ha.md
│   ├── 07_load_balancers.md
│   └── ...
├── scripts/                  # Scripts d'installation et de configuration
│   ├── 01_inventory/
│   ├── 02_base_os_and_security/
│   ├── 03_postgresql/
│   ├── 04_redis/
│   ├── 05_rabbitmq/
│   ├── 06_minio/
│   ├── 07_mariadb_galera/
│   ├── 08_proxysql/
│   ├── 09_k3s/
│   └── 10_lb/
├── servers.tsv              # Inventaire complet des serveurs
└── README.md                # Ce fichier
```

## Installation

### Prérequis

- Accès SSH root vers le serveur `install-01` (10.0.0.20)
- Clés SSH configurées pour tous les serveurs
- Fichier `servers.tsv` correctement rempli

### Configuration SSH

Avant de commencer, configurez l'accès SSH :
- **Guide complet** : Voir `SETUP_SSH_ACCESS.md`
- **Clé PuTTY** : Voir `SETUP_PUTTY_KEY.md` si vous utilisez PuTTY
- **Test de connexion** : `./scripts/test_ssh_connection.sh`

### Démarrage rapide

1. **Se connecter sur install-01** :
```bash
ssh root@<IP_PUBLIQUE_INSTALL_01>
```

2. **Cloner le dépôt GitHub sur install-01** :
```bash
cd /opt
git clone https://github.com/keybuzzio/Infra.git keybuzz-installer
cd keybuzz-installer
```

3. **Appliquer le Module 2 (Base OS & Sécurité) sur tous les serveurs** :
```bash
cd /opt/keybuzz-installer/scripts/02_base_os_and_security
# Éditer base_os.sh pour mettre votre ADMIN_IP
nano base_os.sh
# Lancer l'installation
./apply_base_os_to_all.sh /opt/keybuzz-installer/servers.tsv
```

## Modules d'installation

### Module 1 : Inventaire
- Parsing et validation du fichier `servers.tsv`

### Module 2 : Base OS & Sécurité ⚠️ OBLIGATOIRE EN PREMIER
- Standardisation Ubuntu 24.04
- Durcissement SSH
- Configuration UFW
- Installation Docker
- Optimisations kernel

### Module 3 : PostgreSQL HA
- Cluster Patroni RAFT (3 nœuds)
- Load Balancer Hetzner 10.0.0.10
- PgBouncer

### Module 4 : Redis HA
- Cluster Redis avec Sentinel
- Exposé via LB 10.0.0.10:6379

### Module 5 : RabbitMQ HA
- Cluster Quorum (3 nœuds)
- Exposé via LB 10.0.0.10:5672

### Module 6 : MinIO
- Cluster S3 (3-4 nœuds)

### Module 7 : MariaDB Galera (ERPNext)
- Cluster Galera (3 nœuds)
- ProxySQL (2 nœuds)
- LB interne 10.0.0.20

### Module 8 : ProxySQL
- Configuration pour MariaDB

### Module 9 : K3s HA
- Control plane (3 masters)
- Workers
- Applications (KeyBuzz, Chatwoot, n8n, etc.)

### Module 10 : Load Balancers
- Configuration Hetzner LB
- Health checks

## Ordre d'installation recommandé

1. ✅ Module 2 : Base OS & Sécurité (sur TOUS les serveurs)
2. ✅ Module 3 : PostgreSQL HA
3. ✅ Module 4 : Redis HA
4. ✅ Module 5 : RabbitMQ HA
5. ✅ Module 6 : MinIO
6. ✅ Module 7 : MariaDB Galera
7. ✅ Module 8 : ProxySQL
8. ✅ Module 9 : K3s HA
9. ✅ Module 10 : Load Balancers

## Notes importantes

- ⚠️ **JAMAIS** installer un module rôle avant d'avoir appliqué le Module 2
- ⚠️ Le swap DOIT être désactivé (obligatoire pour Patroni, RabbitMQ, K3s)
- ⚠️ Le DNS DOIT être fixé (1.1.1.1, 8.8.8.8) avant K3s
- ⚠️ UFW doit autoriser 10.0.0.0/16 avant toute installation

## Support

Pour toute question ou problème, consulter la documentation dans `docs/`.

