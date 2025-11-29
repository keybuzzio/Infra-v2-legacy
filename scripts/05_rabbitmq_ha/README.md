# Module 5 - RabbitMQ HA (Quorum Cluster)

**Version** : 1.0  
**Date** : 19 novembre 2025  
**Statut** : ⏳ À implémenter

## 🎯 Objectif

Mettre en place un cluster RabbitMQ HA avec Quorum Queues, composé de :
- **3 nœuds RabbitMQ** : queue-01, queue-02, queue-03
- **HAProxy** : haproxy-01, haproxy-02
- **LB Hetzner** : 10.0.0.10:5672 (point d'entrée unique)
- **Quorum Queues** : Réplication RAFT pour HA réelle

## 📋 Topologie

### Nœuds RabbitMQ
- **queue-01** : 10.0.0.126
- **queue-02** : 10.0.0.127
- **queue-03** : 10.0.0.128

### Load Balancers
- **haproxy-01** : 10.0.0.11
- **haproxy-02** : 10.0.0.12
- **LB Hetzner** : 10.0.0.10

## 🔌 Ports

- **5672/tcp** : AMQP (protocole RabbitMQ)
- **15672/tcp** : Management UI (interne uniquement)
- **25672/tcp** : Clustering inter-nœuds
- **4369/tcp** : EPMD (Erlang port mapper)

## 📦 Scripts (à créer)

1. **`05_rmq_00_setup_credentials.sh`** : Configuration des credentials
2. **`05_rmq_01_prepare_nodes.sh`** : Préparation des nœuds RabbitMQ
3. **`05_rmq_02_deploy_cluster.sh`** : Déploiement du cluster RabbitMQ
4. **`05_rmq_03_configure_haproxy.sh`** : Configuration HAProxy pour RabbitMQ
5. **`05_rmq_04_tests.sh`** : Tests et diagnostics
6. **`05_rmq_apply_all.sh`** : Script master

## 🔧 Prérequis

- Module 2 appliqué sur tous les serveurs
- Docker CE opérationnel
- UFW configuré pour les ports RabbitMQ
- Credentials configurés (`rabbitmq.env`)

## 📝 Notes Importantes

- **Quorum Queues** : Utilisation de Quorum Queues (RAFT) au lieu de classic mirrored queues
- **Erlang Cookie** : Doit être identique sur tous les nœuds
- **Network Host** : Tous les conteneurs utilisent `--network host`
- **Bind IP** : Bind sur IP privée pour la sécurité

## 🔗 Références

- Documentation complète : `Context.txt` (section Module 5 - RabbitMQ HA)
- Anciens scripts fonctionnels : `keybuzz-installer/scripts/` (si disponibles)

---

**Dernière mise à jour** : 19 novembre 2025  
**Statut** : ⏳ Structure créée, scripts à développer

