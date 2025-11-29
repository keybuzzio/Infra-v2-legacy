# Introduction à l'Infrastructure KeyBuzz

## Vue d'ensemble

KeyBuzz est une plateforme SaaS de support client, d'automatisation métier et d'intégration back-office pour les e-commerçants et les prestataires de support.

## Architecture globale

L'infrastructure KeyBuzz est composée de :

### Services Stateful (hors K3s)

- **PostgreSQL HA** : Cluster Patroni RAFT (3 nœuds) - Base principale KeyBuzz
- **MariaDB Galera** : Cluster Galera (3 nœuds) - Base ERPNext
- **Redis HA** : Cluster Redis avec Sentinel (3 nœuds)
- **RabbitMQ HA** : Cluster Quorum (3 nœuds)
- **MinIO** : Cluster S3 (3-4 nœuds)
- **Vector DB** : Qdrant pour les embeddings

### Services Stateless (dans K3s)

- **KeyBuzz API/Front** : Application principale
- **Chatwoot** : Support client
- **n8n** : Automatisation
- **ERPNext** : ERP (optionnel dans K3s)
- **Observabilité** : Prometheus, Grafana, Loki

### Load Balancers

- **LB 10.0.0.10** : LB interne Hetzner (Postgres, Redis, RabbitMQ)
- **LB 10.0.0.5 & 10.0.0.6** : LB publics Hetzner (Ingress K3s)

## Ordre d'installation

1. **Module 2** : Base OS & Sécurité (⚠️ OBLIGATOIRE EN PREMIER)
2. **Module 3** : PostgreSQL HA
3. **Module 4** : Redis HA
4. **Module 5** : RabbitMQ HA
5. **Module 6** : MinIO
6. **Module 7** : MariaDB Galera
7. **Module 8** : ProxySQL
8. **Module 9** : K3s HA
9. **Module 10** : Load Balancers

## Prérequis

- Ubuntu Server 24.04 LTS sur tous les serveurs
- Accès SSH root avec clés
- Réseau privé 10.0.0.0/16 fonctionnel
- Fichier `servers.tsv` correctement rempli

## Documentation

Consulter les modules dans l'ordre pour une installation complète.


