# Module 10 — Configuration des Load Balancers Hetzner

## Vue d'ensemble

L'infrastructure KeyBuzz utilise 3 Load Balancers Hetzner :

### LB 10.0.0.10 — Load Balancer interne KeyBuzz

**Rôle** : Router les flux internes critiques vers les services stateful

**Services exposés** :
- TCP/5432 → PostgreSQL (via haproxy-01 / haproxy-02)
- TCP/6379 → Redis HA
- TCP/5672 → RabbitMQ quorum cluster
- TCP/6432 → PgBouncer

**Backends** :
- haproxy-01 (10.0.0.11)
- haproxy-02 (10.0.0.12)

### LB 10.0.0.5 & 10.0.0.6 — Load Balancers publics

**Rôle** : Router le trafic HTTP/HTTPS public vers K3s

**Services exposés** :
- HTTPS/443 → Ingress K3s (NodePort 31695)
- HTTP/80 → Redirection vers HTTPS

**Backends** :
- k3s-master-01 → 03
- k3s-worker-01 → 05

## Configuration requise

### LB interne (10.0.0.10)

**PostgreSQL (5432)** :
- Health check : TCP sur 5432
- Backends : haproxy-01:5432, haproxy-02:5432

**Redis (6379)** :
- Health check : TCP sur 6379
- Backends : redis-01:6379, redis-02:6379, redis-03:6379

**RabbitMQ (5672)** :
- Health check : TCP sur 5672
- Backends : queue-01:5672, queue-02:5672, queue-03:5672

### LB publics (10.0.0.5 & 10.0.0.6)

**HTTPS (443)** :
- Health check : HTTP GET sur /healthz (NodePort 31695)
- Backends : Tous les nœuds K3s (masters + workers)

## Scripts de configuration

Les scripts de configuration des LB seront dans :
- `scripts/10_lb/configure_lb_internal.sh`
- `scripts/10_lb/configure_lb_public.sh`

## Notes importantes

- ⚠️ Les health checks doivent pointer vers HAProxy, pas directement vers les conteneurs
- ⚠️ Le LB interne doit être strict : uniquement les ports réellement utilisés
- ⚠️ Les ports non nécessaires doivent être supprimés


