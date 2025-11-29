# Résumé Préparation Rebuild Kubernetes V2

## ✅ Étapes 0-1 terminées

### 0. Sauvegarde documentation
- ✅ Backup créé : `backup_before_k8s_rebuild_20251128`
- ✅ Modules 9, 10, 11 archivés
- ✅ Rapports de validation archivés

### 1. Préparation inventaire Kubespray V2

#### Fichiers créés
- ✅ `inventory/keybuzz-v2/hosts.yaml` : 3 masters + 5 workers
- ✅ `group_vars/k8s_cluster/k8s-cluster.yml` : CIDR corrigés
- ✅ `group_vars/k8s_cluster/calico.yml` : IPIP Always
- ✅ `group_vars/all/all.yml` : DNS CoreDNS

#### CIDR configurés
- **Pod CIDR Calico** : `10.233.0.0/16` (englobe tous les pods)
- **Service CIDR** : `10.96.0.0/12` (séparé des pods, standard Kubernetes)
- **kube-proxy mode** : `iptables`
- **Calico IPIP** : `Always`
- **Calico VXLAN** : `Never`

## 📋 Prochaines étapes

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
- Ports 80/443

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
**Statut** : ✅ Préparation terminée - Prêt pour reset et réinstallation

