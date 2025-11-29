# Module 9 - K3s HA Complet

**Version** : 1.0  
**Date** : 20 novembre 2025  
**Statut** : ⏳ À implémenter

## 🎯 Objectif

Déployer un cluster K3s hautement disponible, capable de :
- Gérer des milliers de pods/tickets
- Supporter des pics Q4 / fortes charges
- Tourner même si un master ou plusieurs workers tombent
- Se mettre à jour sans downtime
- Recevoir des workloads IA
- Être la fondation multi-tenant de KeyBuzz

## 📋 Architecture HA

### Nœuds Master (Control-plane)
- **k3s-master-01** : 10.0.0.100 (bootstrap)
- **k3s-master-02** : 10.0.0.101
- **k3s-master-03** : 10.0.0.102

### Nœuds Worker
- **k3s-worker-01** : 10.0.0.110 (workloads généraux)
- **k3s-worker-02** : 10.0.0.111 (workloads généraux)
- **k3s-worker-03** : 10.0.0.112 (workloads lourds - IA)
- **k3s-worker-04** : 10.0.0.113 (observabilité, monitoring, jobs)
- **k3s-worker-05** : 10.0.0.114 (réserve/scalabilité)

### Load Balancers Hetzner
- **lb-keybuzz-1** : 10.0.0.5 (LB public HTTP/HTTPS)
- **lb-keybuzz-2** : 10.0.0.6 (LB public HTTP/HTTPS)
- **lb-haproxy** : 10.0.0.10 (LB interne - Postgres/Redis/RabbitMQ)

## 🔌 Ports

### Masters
- **6443/tcp** : Kubernetes API Server
- **10250/tcp** : Kubelet API
- **8472/udp** : Flannel VXLAN

### Workers
- **10250/tcp** : Kubelet API
- **8472/udp** : Flannel VXLAN

## 🔧 Prérequis

### Module 2 appliqué
- Swap OFF
- Docker CE installé (pour autres services, K3s utilise containerd)
- UFW configuré strictement

### Résolution DNS
- Fix systemd en place :
  ```
  nameserver 1.1.1.1
  nameserver 8.8.8.8
  chattr +i /etc/resolv.conf
  ```

### servers.tsv
- ROLE=k3s
- SUBROLE=master / worker
- DOCKER_STACK=k3s-control-plane / k3s-node

## 📦 Scripts

1. **`09_k3s_01_prepare.sh`** : Préparation des nœuds K3s
2. **`09_k3s_02_install_control_plane.sh`** : Installation control-plane HA
3. **`09_k3s_03_join_workers.sh`** : Join des workers
4. **`09_k3s_04_bootstrap_addons.sh`** : Bootstrap addons (DNS, metrics-server, storage)
5. **`09_k3s_05_ingress_daemonset.sh`** : Ingress NGINX DaemonSet (CRITIQUE)
6. **`09_k3s_06_deploy_core_apps.sh`** : Déploiement KeyBuzz Core
7. **`09_k3s_07_install_monitoring.sh`** : Installation monitoring K3s
8. **`09_k3s_08_install_vault_agent.sh`** : Vault Agent + secrets
9. **`09_k3s_09_final_validation.sh`** : Validation finale
10. **`09_k3s_test_healthcheck.sh`** : Test des healthchecks Ingress pour LB Hetzner
11. **`09_k3s_apply_all.sh`** : Script master

## 🏗️ Composants

### Control-plane HA
- 3 masters avec etcd intégré
- API Server load balanced
- Consensus RAFT pour etcd

### Addons Bootstrap
- **CoreDNS** : DNS interne K3s
- **metrics-server** : Métriques de base
- **local-path-provisioner** : StorageClass local

### Ingress NGINX DaemonSet
- **CRITIQUE** : Mode DaemonSet (pas Deployment)
- **hostNetwork=true** : Pour LB Hetzner L4
- Un Pod Ingress par node

### KeyBuzz Core Apps
- KeyBuzz API
- KeyBuzz Front
- Chatwoot rebrandé
- n8n Workflows
- Superset (optionnel)

### Monitoring K3s
- Prometheus stack
- Grafana
- Exporters (node, postgres, redis, etc.)

### Vault Agent
- Secrets management
- Injection automatique dans pods
- Rotation dynamique

## ⚠️ Notes Importantes

### Ingress DaemonSet (OBLIGATOIRE)
- **NE PAS** utiliser Deployment pour Ingress
- **OBLIGATOIRE** : DaemonSet avec hostNetwork=true
- Permet l'exploitation du Load Balancing L4 Hetzner
- Un Pod Ingress par node garantit la disponibilité

### Docker vs Containerd
- **Docker** : Installé sur les nodes (pour autres services)
- **K3s** : Utilise containerd (intégré)
- Pas de conflit

### Stateful Services
- **NE PAS** mettre Postgres/Redis/RabbitMQ/MinIO dans K3s
- Ces services sont déployés en Docker sur nœuds dédiés
- K3s gère uniquement les applications stateless

## 🔗 Intégration avec autres modules

✅ **Module 2** : Base OS appliquée sur tous les nœuds  
✅ **Module 3** : PostgreSQL HA accessible depuis K3s  
✅ **Module 4** : Redis HA accessible depuis K3s  
✅ **Module 5** : RabbitMQ HA accessible depuis K3s  
✅ **Module 6** : MinIO S3 accessible depuis K3s  
✅ **Module 7** : MariaDB Galera accessible depuis K3s  
✅ **Module 8** : ProxySQL optimisé pour ERPNext  

## 📚 Documentation

- **Context.txt** : Section "Module 9 — K3s HA Complet"
- **Architecture** : 3 masters + 5 workers
- **Ingress** : DaemonSet obligatoire

---

**Dernière mise à jour** : 20 novembre 2025  
**Auteur** : Infrastructure KeyBuzz

