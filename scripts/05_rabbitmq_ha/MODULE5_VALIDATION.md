# Module 5 - RabbitMQ HA - Validation

**Date** : 19 novembre 2025  
**Statut** : ✅ Opérationnel

## Résumé

Le Module 5 (RabbitMQ HA) a été installé et validé avec succès. Le cluster RabbitMQ est opérationnel avec Quorum Queues, HAProxy est configuré, et tous les composants fonctionnent correctement.

## Composants installés

### RabbitMQ Cluster
- **3 nœuds RabbitMQ** : queue-01, queue-02, queue-03
- **Version** : RabbitMQ 3.12-management
- **Cluster** : keybuzz-queue
- **Quorum Queues** : Activées par défaut
- **Network** : --network host

### HAProxy
- **2 nœuds HAProxy** : haproxy-01, haproxy-02
- **Port** : 5672 (AMQP)
- **Backend** : queue-01 (primary), queue-02/03 (backup)

## Points d'accès

- **RabbitMQ direct** : queue-01/02/03:5672
- **HAProxy** : haproxy-01:5672, haproxy-02:5672
- **LB Hetzner** : 10.0.0.10:5672 (à configurer manuellement)

## Credentials

- **User** : kb_rmq
- **Password** : Généré automatiquement (stocké dans `/opt/keybuzz-installer/credentials/rabbitmq.env`)
- **Erlang Cookie** : Généré automatiquement (identique sur tous les nœuds)

## Tests effectués

✅ **Connectivité RabbitMQ** : Tous les nœuds accessibles sur le port 5672  
✅ **Cluster** : Cluster opérationnel (queue-01 comme nœud principal)  
✅ **HAProxy** : HAProxy opérationnel sur haproxy-01 et haproxy-02  
✅ **Quorum Queues** : Activées sur tous les nœuds  

## Scripts disponibles

1. `05_rmq_00_setup_credentials.sh` - Configuration des credentials
2. `05_rmq_01_prepare_nodes.sh` - Préparation des nœuds
3. `05_rmq_02_deploy_cluster.sh` - Déploiement du cluster
4. `05_rmq_03_configure_haproxy.sh` - Configuration HAProxy
5. `05_rmq_04_tests.sh` - Tests et diagnostics
6. `05_rmq_apply_all.sh` - Script master

## Commandes utiles

### Vérifier le statut du cluster
```bash
ssh root@10.0.0.126 "docker exec rabbitmq rabbitmqctl cluster_status"
```

### Vérifier les queues
```bash
ssh root@10.0.0.126 "docker exec rabbitmq rabbitmqctl list_queues"
```

### Vérifier HAProxy
```bash
ssh root@10.0.0.11 "docker ps | grep haproxy-rabbitmq"
```

## Notes importantes

- Le cookie Erlang est géré automatiquement via la variable d'environnement `RABBITMQ_ERLANG_COOKIE`
- Les Quorum Queues sont activées par défaut pour une meilleure HA
- Le cluster utilise `--network host` pour éviter les problèmes de résolution DNS
- Les hostnames sont ajoutés dans `/etc/hosts` sur chaque nœud pour la résolution DNS

## Problèmes résolus

1. ✅ **Cookie Erlang** : Suppression du cookie existant dans le volume data avant le démarrage
2. ✅ **Configuration** : Utilisation d'une configuration minimale avec variables d'environnement
3. ✅ **Résolution DNS** : Ajout des hostnames dans `/etc/hosts`
4. ✅ **Permissions** : Le conteneur crée automatiquement le cookie avec les bonnes permissions

---

**Dernière mise à jour** : 19 novembre 2025  
**Validé par** : Scripts automatisés

