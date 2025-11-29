# Rebuild Kubernetes V2 - Prêt

## ✅ Préparation terminée

### Sauvegarde
- ✅ Backup créé : `backup_before_k8s_rebuild_20251128`
- ✅ Documentation Modules 9, 10, 11 archivée

### Inventaire Kubespray V2
- ✅ `inventory/keybuzz-v2/hosts.yaml` : 3 masters + 5 workers
- ✅ `group_vars/k8s_cluster/k8s-cluster.yml` : CIDR corrigés
  - Pod CIDR : `10.233.0.0/16`
  - Service CIDR : `10.96.0.0/12`
- ✅ `group_vars/k8s_cluster/calico.yml` : IPIP Always
- ✅ `group_vars/all/all.yml` : CoreDNS

## 🎯 Prochaines étapes

### Étape 2 : Reset cluster K8s existant
```bash
cd /opt/keybuzz-installer-v2/kubespray
ansible-playbook -i inventory/keybuzz-v2/hosts.yaml --become --become-user=root reset.yml
```

### Étape 3 : Réinstaller Kubernetes HA
```bash
ansible-playbook -i inventory/keybuzz-v2/hosts.yaml --become --become-user=root cluster.yml
```

### Étape 4 : Installer ingress-nginx
- DaemonSet + hostNetwork

### Étape 5 : Valider réseau K8s
- Pod → Pod
- Pod → Service
- DNS
- Node → Service

### Étape 6 : Réinstaller Module 10
- Plateforme KeyBuzz

### Étape 7 : Réinstaller Module 11
- Chatwoot / Support KeyBuzz

### Étape 8 : Mettre à jour documentation

---

**Date** : 2025-11-27  
**Statut** : ✅ **PRÊT POUR REBUILD**

