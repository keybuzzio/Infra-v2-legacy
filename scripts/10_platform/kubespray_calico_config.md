# Configuration Calico IPIP pour Kubespray

**Date** : 2025-11-24  
**Objectif** : Configurer Calico en mode IPIP (sans VXLAN) pour Hetzner Cloud

---

## 📋 Fichiers à Modifier

### 1. `group_vars/k8s_cluster/k8s-cluster.yml`

Ajouter/modifier les paramètres suivants :

```yaml
# Network Plugin
network_plugin: calico
kube_network_plugin: calico

# Calico Configuration
calico_ipip_mode: Always
calico_vxlan_mode: Never
calico_nat_outgoing: Enabled

# kube-proxy
kube_proxy_mode: iptables
```

### 2. `group_vars/k8s_cluster/addons.yml`

Vérifier que les addons sont configurés :

```yaml
# CoreDNS
dns_mode: coredns
coredns_min_replicas: 2

# Metrics Server
metrics_server_enabled: true
```

---

## 🔧 Configuration Complète Recommandée

### `group_vars/k8s_cluster/k8s-cluster.yml`

```yaml
# ============================================================
# Network Plugin: Calico
# ============================================================
network_plugin: calico
kube_network_plugin: calico

# ============================================================
# Calico IPIP Configuration
# ============================================================
calico_ipip_mode: Always
calico_vxlan_mode: Never
calico_nat_outgoing: Enabled

# ============================================================
# kube-proxy
# ============================================================
kube_proxy_mode: iptables

# ============================================================
# Pod Network CIDR
# ============================================================
kube_pods_subnet: 10.233.0.0/16
kube_service_addresses: 10.233.0.0/18

# ============================================================
# Kubernetes Version
# ============================================================
kube_version: v1.28.0

# ============================================================
# Container Runtime
# ============================================================
container_manager: containerd
containerd_version: 1.7.0
```

### `group_vars/all/all.yml`

```yaml
# ============================================================
# System Configuration
# ============================================================
# Désactiver swap
disable_swap: true

# ============================================================
# Firewall (si UFW est utilisé)
# ============================================================
# ufw_enabled: false
```

---

## ✅ Vérifications Post-Installation

Après le déploiement, vérifier :

```bash
# 1. Vérifier les nodes
kubectl get nodes

# 2. Vérifier Calico
kubectl get pods -n kube-system -l k8s-app=calico-node

# 3. Vérifier CoreDNS
kubectl get pods -n kube-system -l k8s-app=kube-dns

# 4. Vérifier la configuration Calico
kubectl get ippool default-ipv4-ippool -o yaml

# 5. Tester DNS
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup kubernetes.default

# 6. Tester Services ClusterIP
kubectl run test-curl --image=curlimages/curl --rm -it --restart=Never -- curl http://kubernetes.default
```

---

## 🎯 Résultat Attendu

Après configuration et déploiement :

- ✅ Calico en mode IPIP (pas de VXLAN)
- ✅ DNS fonctionnel (CoreDNS)
- ✅ Services ClusterIP accessibles
- ✅ Pod-to-Pod communication fonctionnelle
- ✅ Ingress → Backend fonctionnel
- ✅ Pas d'erreurs ipset/nftables
- ✅ Réseau overlay stable

---

**Document créé le** : 2025-11-24  
**Statut** : ✅ Configuration prête  
**Action Requise** : Appliquer la configuration avant `ansible-playbook cluster.yml`

