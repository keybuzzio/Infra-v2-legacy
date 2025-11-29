# Rebuild Kubernetes V2 - En cours

## ✅ Étapes terminées

### Étape 0 : Sauvegarde
- ✅ Backup créé : `backup_before_k8s_rebuild_20251128`

### Étape 1 : Préparation inventaire
- ✅ Inventaire Kubespray V2 créé
- ✅ CIDR configurés :
  - Pod CIDR : `10.233.0.0/16`
  - Service CIDR : `10.96.0.0/12`
- ✅ Configuration Calico : IPIP Always

### Étape 2 : Reset cluster K8s
- ✅ Pool Calico supprimé (default-pool avec CIDR 10.233.64.0/18)
- ✅ Reset exécuté avec succès (skip-tags calico)
- ✅ Logs : `/opt/keybuzz-installer-v2/logs/rebuild_k8s_v2_reset.log`

## ⏳ En cours

### Étape 3 : Réinstallation Kubernetes HA V2
- ⏳ Installation en cours via `ansible-playbook cluster.yml`
- ⏳ Logs : `/opt/keybuzz-installer-v2/logs/rebuild_k8s_v2_install.log`
- ⏳ Durée estimée : 30-60 minutes

**Commandes de vérification** :
```bash
# Vérifier l'état de l'installation
tail -f /opt/keybuzz-installer-v2/logs/rebuild_k8s_v2_install.log

# Vérifier les nodes (après installation)
export KUBECONFIG=/root/.kube/config
kubectl get nodes -o wide
```

## 📋 Prochaines étapes

### Étape 4 : Installer ingress-nginx
- DaemonSet + hostNetwork
- Ports 80/443

### Étape 5 : Valider le réseau K8s
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

**Date début** : 2025-11-28 10:03  
**Statut** : ⏳ Installation Kubernetes en cours

