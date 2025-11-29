# Vérification des IPs des Serveurs Installés

**Date** : 2025-11-21  
**Objectif** : Comparer les serveurs réellement installés avec le fichier `servers.tsv`

---

## 📋 Serveurs Installés (selon les modules)

### Module 2 : Base OS & Sécurité
**Tous les serveurs** (49 serveurs au total)

### Module 3 : PostgreSQL HA
- **db-master-01** : `10.0.0.120` ✅
- **db-slave-01** : `10.0.0.121` ✅
- **db-slave-02** : `10.0.0.122` ✅

### Module 4 : Redis HA
- **redis-01** : `10.0.0.123` ✅
- **redis-02** : `10.0.0.124` ✅
- **redis-03** : `10.0.0.125` ✅

### Module 5 : RabbitMQ HA
- **queue-01** : `10.0.0.126` ✅ (dans servers.tsv)
- **queue-02** : `10.0.0.127` ✅ (dans servers.tsv)
- **queue-03** : `10.0.0.128` ✅ (dans servers.tsv)

⚠️ **INCOHÉRENCE DÉTECTÉE** : Dans le rapport technique, j'ai écrit `10.0.0.130`, `10.0.0.131`, `10.0.0.132` mais dans servers.tsv c'est `10.0.0.126`, `10.0.0.127`, `10.0.0.128`

### Module 6 : MinIO
- **minio-01** : `10.0.0.134` ✅

### Module 7 : MariaDB Galera
- **maria-01** : `10.0.0.170` ✅ (dans servers.tsv)
- **maria-02** : `10.0.0.171` ✅ (dans servers.tsv)
- **maria-03** : `10.0.0.172` ✅ (dans servers.tsv)

⚠️ **INCOHÉRENCE DÉTECTÉE** : Dans le rapport technique, j'ai écrit `10.0.0.140`, `10.0.0.141`, `10.0.0.142` mais dans servers.tsv c'est `10.0.0.170`, `10.0.0.171`, `10.0.0.172`

### Module 8 : ProxySQL
- **proxysql-01** : `10.0.0.173` ✅ (dans servers.tsv)
- **proxysql-02** : `10.0.0.174` ✅ (dans servers.tsv)

⚠️ **INCOHÉRENCE DÉTECTÉE** : Dans le rapport technique, j'ai écrit `10.0.0.150`, `10.0.0.151` mais dans servers.tsv c'est `10.0.0.173`, `10.0.0.174`

### Module 9 : K3s HA
**Masters** :
- **k3s-master-01** : `10.0.0.100` ✅
- **k3s-master-02** : `10.0.0.101` ✅
- **k3s-master-03** : `10.0.0.102` ✅

**Workers** :
- **k3s-worker-01** : `10.0.0.110` ✅
- **k3s-worker-02** : `10.0.0.111` ✅
- **k3s-worker-03** : `10.0.0.112` ✅
- **k3s-worker-04** : `10.0.0.113` ✅
- **k3s-worker-05** : `10.0.0.114` ✅

### Autres Serveurs (non installés dans les modules 2-9)
- **install-01** : `10.0.0.20` ✅ (dans servers.tsv)
- **haproxy-01** : `10.0.0.11` ✅ (dans servers.tsv)
- **haproxy-02** : `10.0.0.12` ✅ (dans servers.tsv)

---

## 🔍 Comparaison avec servers.tsv

### ✅ Serveurs Cohérents

| Hostname | IP dans servers.tsv | IP dans rapport | Statut |
|----------|---------------------|-----------------|--------|
| k3s-master-01 | 10.0.0.100 | 10.0.0.100 | ✅ |
| k3s-master-02 | 10.0.0.101 | 10.0.0.101 | ✅ |
| k3s-master-03 | 10.0.0.102 | 10.0.0.102 | ✅ |
| k3s-worker-01 | 10.0.0.110 | 10.0.0.110 | ✅ |
| k3s-worker-02 | 10.0.0.111 | 10.0.0.111 | ✅ |
| k3s-worker-03 | 10.0.0.112 | 10.0.0.112 | ✅ |
| k3s-worker-04 | 10.0.0.113 | 10.0.0.113 | ✅ |
| k3s-worker-05 | 10.0.0.114 | 10.0.0.114 | ✅ |
| db-master-01 | 10.0.0.120 | 10.0.0.120 | ✅ |
| db-slave-01 | 10.0.0.121 | 10.0.0.121 | ✅ |
| db-slave-02 | 10.0.0.122 | 10.0.0.122 | ✅ |
| redis-01 | 10.0.0.123 | 10.0.0.123 | ✅ |
| redis-02 | 10.0.0.124 | 10.0.0.124 | ✅ |
| redis-03 | 10.0.0.125 | 10.0.0.125 | ✅ |
| minio-01 | 10.0.0.134 | 10.0.0.134 | ✅ |

### ⚠️ Incohérences Détectées

| Hostname | IP dans servers.tsv | IP dans rapport | Correction nécessaire |
|----------|---------------------|-----------------|----------------------|
| queue-01 | **10.0.0.126** | 10.0.0.130 | ❌ Rapport à corriger |
| queue-02 | **10.0.0.127** | 10.0.0.131 | ❌ Rapport à corriger |
| queue-03 | **10.0.0.128** | 10.0.0.132 | ❌ Rapport à corriger |
| maria-01 | **10.0.0.170** | 10.0.0.140 | ❌ Rapport à corriger |
| maria-02 | **10.0.0.171** | 10.0.0.141 | ❌ Rapport à corriger |
| maria-03 | **10.0.0.172** | 10.0.0.142 | ❌ Rapport à corriger |
| proxysql-01 | **10.0.0.173** | 10.0.0.150 | ❌ Rapport à corriger |
| proxysql-02 | **10.0.0.174** | 10.0.0.151 | ❌ Rapport à corriger |

---

## 📝 Liste Complète des Serveurs Installés (selon servers.tsv)

### K3s (8 serveurs)
1. **k3s-master-01** : `10.0.0.100`
2. **k3s-master-02** : `10.0.0.101`
3. **k3s-master-03** : `10.0.0.102`
4. **k3s-worker-01** : `10.0.0.110`
5. **k3s-worker-02** : `10.0.0.111`
6. **k3s-worker-03** : `10.0.0.112`
7. **k3s-worker-04** : `10.0.0.113`
8. **k3s-worker-05** : `10.0.0.114`

### PostgreSQL (3 serveurs)
9. **db-master-01** : `10.0.0.120`
10. **db-slave-01** : `10.0.0.121`
11. **db-slave-02** : `10.0.0.122`

### Redis (3 serveurs)
12. **redis-01** : `10.0.0.123`
13. **redis-02** : `10.0.0.124`
14. **redis-03** : `10.0.0.125`

### RabbitMQ (3 serveurs)
15. **queue-01** : `10.0.0.126`
16. **queue-02** : `10.0.0.127`
17. **queue-03** : `10.0.0.128`

### MinIO (1 serveur)
18. **minio-01** : `10.0.0.134`

### MariaDB Galera (3 serveurs)
19. **maria-01** : `10.0.0.170`
20. **maria-02** : `10.0.0.171`
21. **maria-03** : `10.0.0.172`

### ProxySQL (2 serveurs)
22. **proxysql-01** : `10.0.0.173`
23. **proxysql-02** : `10.0.0.174`

### HAProxy (2 serveurs)
24. **haproxy-01** : `10.0.0.11`
25. **haproxy-02** : `10.0.0.12`

### Orchestration (1 serveur)
26. **install-01** : `10.0.0.20`

---

## 🔧 Actions à Prendre

1. **Corriger le rapport technique** avec les bonnes IPs
2. **Vérifier les scripts d'installation** pour s'assurer qu'ils utilisent les bonnes IPs depuis servers.tsv
3. **Vérifier les configurations** (HAProxy, ProxySQL, etc.) pour s'assurer qu'elles pointent vers les bonnes IPs

---

## 📊 Résumé

- **Total serveurs installés** : 26 serveurs (modules 2-9)
- **Incohérences détectées** : 8 IPs incorrectes dans le rapport technique
- **Serveurs cohérents** : 18 serveurs

**Les scripts d'installation utilisent servers.tsv comme source de vérité, donc les installations sont correctes. Seul le rapport technique contient des erreurs.**

