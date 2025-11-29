# État actuel de l'infrastructure KeyBuzz

**Date** : 18 novembre 2024
**Serveur** : install-01 (91.98.128.153)

## ✅ Configuration terminée

### Sur install-01

- **Répertoire** : `/opt/keybuzz-installer`
- **servers.tsv** : 49 serveurs configurés
- **ADMIN_IP** : `91.98.128.153` (IP publique d'install-01)
- **Scripts Module 2** : Transférés et exécutables

### Répartition des serveurs

- **10** serveurs `app` (applications diverses)
- **8** serveurs `k3s` (3 masters + 5 workers)
- **8** serveurs `db` (PostgreSQL, MariaDB, etc.)
- **3** serveurs `redis` (cluster Redis HA)
- **3** serveurs `queue` (RabbitMQ quorum)
- **3** serveurs `mail` (infrastructure mail)
- **3** serveurs `lb` (HAProxy, ProxySQL)
- **2** serveurs `security` (Vault, SIEM)
- **2** serveurs `db_proxy` (ProxySQL)
- **1** serveur `vectordb` (Qdrant)
- **1** serveur `storage` (MinIO)
- **1** serveur `orchestrator` (install-01)
- **1** serveur `monitoring`

**Total : 49 serveurs**

## 📋 Prochaine étape : Module 2

Le Module 2 (Base OS & Sécurité) est prêt à être lancé.

### Commande à exécuter

```bash
cd /opt/keybuzz-installer/scripts/02_base_os_and_security
./apply_base_os_to_all.sh ../../servers.tsv
```

### Ce que fait le Module 2

Pour chaque serveur (49 serveurs) :
1. ✅ Mise à jour OS (Ubuntu 24.04)
2. ✅ Installation Docker
3. ✅ Désactivation du swap
4. ✅ Configuration UFW (firewall)
5. ✅ Durcissement SSH
6. ✅ Configuration DNS (1.1.1.1, 8.8.8.8)
7. ✅ Optimisations kernel/sysctl
8. ✅ Configuration journald
9. ✅ Ouverture des ports selon le rôle

**Durée estimée** : 10-15 minutes pour 49 serveurs

## ⚠️ Prérequis

Avant de lancer le Module 2, vérifier que :

- ✅ Les clés SSH sont déposées sur tous les serveurs
- ✅ La connectivité réseau 10.0.0.0/16 fonctionne
- ✅ Tous les serveurs sont accessibles depuis install-01

## 📊 Après le Module 2

Une fois le Module 2 terminé, vous pourrez :

1. ✅ Lancer le Module 3 : PostgreSQL HA
2. ✅ Lancer le Module 4 : Redis HA
3. ✅ Lancer le Module 5 : RabbitMQ HA
4. ✅ Et ainsi de suite...

## 🔍 Vérification

Pour vérifier l'état actuel :

```bash
cd /opt/keybuzz-installer
./scripts/01_inventory/parse_servers_tsv.sh servers.tsv
```


