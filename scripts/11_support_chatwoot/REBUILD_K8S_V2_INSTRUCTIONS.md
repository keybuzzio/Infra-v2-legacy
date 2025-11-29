# Instructions Rebuild Kubernetes V2

## ✅ Étapes 0-1 terminées

### Sauvegarde documentation
- Backup créé dans `backup_before_k8s_rebuild_YYYYMMDD_HHMMSS`

### Inventaire Kubespray V2
- ✅ `inventory/keybuzz-v2/hosts.yaml` : 3 masters + 5 workers
- ✅ `group_vars/k8s_cluster/k8s-cluster.yml` : CIDR corrigés
- ✅ `group_vars/k8s_cluster/calico.yml` : IPIP Always
- ✅ `group_vars/all/all.yml` : DNS CoreDNS

### CIDR configurés
- **Pod CIDR** : `10.233.0.0/16` (Calico)
- **Service CIDR** : `10.96.0.0/12` (standard Kubernetes)

## ⏳ Prochaines étapes

### Étape 2 : Reset cluster K8s existant
```bash
cd /opt/keybuzz-installer-v2/kubespray
ansible-playbook -i inventory/keybuzz-v2/hosts.yaml --become --become-user=root reset.yml
```

⚠️ **Attention** : Ne touche PAS aux serveurs stateful (db, redis, rabbit, minio, maria, proxysql, haproxy)

### Étape 3 : Réinstaller Kubernetes HA
```bash
ansible-playbook -i inventory/keybuzz-v2/hosts.yaml --become --become-user=root cluster.yml
```

Après installation :
```bash
mkdir -p /root/.kube
cp inventory/keybuzz-v2/artifacts/admin.conf /root/.kube/config
export KUBECONFIG=/root/.kube/config
kubectl get nodes -o wide
```

### Étape 4 : Installer ingress-nginx
```bash
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.9.5/deploy/static/provider/baremetal/deploy.yaml
```

Puis patch en DaemonSet + hostNetwork (comme avant).

### Étape 5 : Valider réseau
- Pod → Pod
- Pod → Service
- DNS
- Node → Service

### Étape 6 : Réinstaller Module 10
```bash
cd /opt/keybuzz-installer-v2/scripts/10_platform
./deploy_module10_kubernetes.sh
./update_platform_images.sh ghcr.io/keybuzzio/platform-api:0.1.1 ghcr.io/keybuzzio/platform-ui:0.1.1 ghcr.io/keybuzzio/platform-ui:0.1.1
./validate_module10_kubernetes.sh
```

### Étape 7 : Réinstaller Module 11
```bash
cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot
./11_ct_apply_all.sh
./validate_module11.sh
```

---

**Date** : 2025-11-27  
**Statut** : Prêt pour reset et réinstallation

