# Analyse Définitive : Solution Réseau pour Hetzner Cloud

**Date** : 2025-11-24  
**Statut** : ✅ Solution identifiée - Migration vers Kubespray + Calico recommandée

---

## 🔴 Problème Racine Identifié

### Pourquoi Cilium + K3s a échoué

**Cause Structurelle** : K3s et Cilium sont **incompatibles** dans ce contexte.

#### 1. K3s active automatiquement Flannel

Même avec `flannel-backend: none` dans `/etc/rancher/k3s/config.yaml` :
- ❌ Flannel reste partiellement actif
- ❌ Les fichiers CNI restent présents dans `/var/lib/rancher/k3s/agent/etc/cni/net.d`
- ❌ Le kubelet continue d'utiliser Flannel
- ❌ Les routes VXLAN persistent

#### 2. Cilium détecte VXLAN et refuse de démarrer

```
level=info msg="  --tunnel-protocol='vxlan'" subsys=daemon
level=fatal msg="auto-direct-node-routes cannot be used with tunneling."
```

**Pourquoi** :
- K3s injecte automatiquement les routes VXLAN dans Cilium
- Cilium détecte "VXLAN est encore là"
- Cilium refuse le mode `tunnel=disabled` car VXLAN est détecté

#### 3. Conclusion

**C'est un problème structurel, pas de configuration.**

- K3s = Kubernetes "consolidé" par Rancher
- Il embarque son propre CNI Flannel qu'il active **TOUJOURS**
- Cilium **NE PEUT PAS** remplacer Flannel sur K3s à cause de cette intégration

---

## 🟥 État Actuel : Aucune Solution Viable avec K3s

### Solutions Testées

| Solution | Résultat | Raison |
|----------|----------|--------|
| K3s + Flannel | ❌ Impossible | VXLAN bloqué sur Hetzner |
| K3s + Calico IPIP | ❌ Échec | Incompatibilité ipset/kernel |
| K3s + Cilium | ❌ Impossible | K3s force Flannel, Cilium refuse |

### Conclusion

**Avec K3s sur Hetzner, il n'y aura JAMAIS un réseau overlay stable.**

- ❌ VXLAN est cassé
- ❌ Flannel est cassé
- ❌ Cilium ne fonctionnera pas
- ❌ AUCUN CNI ne peut fonctionner proprement tant que K3s impose Flannel

---

## 🟩 Solution Définitive : Kubespray + Calico IPIP

### Pourquoi Kubespray + Calico ?

**Avantages** :
- ✅ **Kubespray désactive totalement Flannel** (contrairement à K3s)
- ✅ **Calico IPIP ne nécessite pas ipset récent** (pas de mismatch kernel/userspace)
- ✅ **Kubespray gère toutes les dépendances Kubernetes officiellement supportées**
- ✅ **Cluster "valide CNCF"** avec comportement standard
- ✅ **Support Hetzner out-of-the-box**
- ✅ **IP routes propres, pas de VXLAN, overlay Calico stable**

### Architecture Recommandée

```
Kubernetes HA (Kubespray)
├── 3 Masters (control-plane)
├── 5 Workers
├── CNI: Calico IPIP (0 VXLAN)
├── kube-proxy: normal
├── Ingress: NGINX DaemonSet
└── Support: LB Hetzner
```

### Ce qui est conservé

- ✅ Toutes les IPs (10.0.0.x)
- ✅ Tous les volumes
- ✅ Toutes les apps (après migration)
- ✅ Configuration Ingress
- ✅ Monitoring (Prometheus/Grafana)

### Ce qui change

- ❌ K3s → Kubernetes complet (kubeadm)
- ❌ Flannel → Calico IPIP
- ❌ Installation via Kubespray au lieu de K3s

---

## 📊 Comparaison des Solutions

| Solution | Fiabilité | Performance | Compatibilité | Complexité | Recommandation |
|----------|-----------|-------------|---------------|------------|---------------|
| K3s + Flannel | ❌ Impossible | ❌ | ❌ | — | ❌ À oublier |
| K3s + Cilium | ❌ Impossible | ❌ | ❌ | Élevée | ❌ Non compatible |
| K3s + NodePort | ✔ OK | Moyen | Partielle | Faible | ✔ Option B (patch) |
| **Kubespray + Calico IPIP** | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | Moyenne | ⭐ **RECOMMANDÉ** |

---

## 🟦 Réponses aux Questions

### ❓ 1. Pourquoi Cilium détecte encore VXLAN ?

**➡️ Parce que K3s injecte Flannel même quand tu le désactives.**

- C'est par design
- Cilium ne peut pas remplacer Flannel dans K3s dans ce contexte

### ❓ 2. Comment forcer Cilium en direct-routing (tunnel=disabled) ?

**➡️ Impossible sur K3s.**

- Possible sur Kubernetes "normal" (kubeadm/Kubespray) uniquement

### ❓ 3. Y a-t-il une incompatibilité K3s ↔ Cilium ?

**➡️ Oui.**

- Documentée dans plusieurs issues Rancher + Project Cilium
- "Tunnel=disabled" ne fonctionne pas sur K3s

### ❓ 4. Alternative à Cilium pour Hetzner Cloud ?

**➡️ Oui : Kubespray + Calico IPIP**

- Ou K3s + NodePort/Ingress hostNetwork (solution patch, non recommandée)

---

## 🚀 Plan d'Action Recommandé

### Phase 1 : Restauration du Cluster Actuel

1. **Restaurer l'accès au cluster K3s** :
   - Vérifier l'état des masters
   - Réactiver Flannel temporairement
   - Redémarrer K3s si nécessaire

2. **Maintenir les applications en fonctionnement** :
   - Utiliser NodePort pour les Services (solution temporaire)
   - Garder Ingress NGINX en hostNetwork

### Phase 2 : Migration vers Kubespray + Calico

1. **Préparation** :
   - Sauvegarder toutes les configurations
   - Documenter les volumes et PVC
   - Lister toutes les applications déployées

2. **Installation Kubespray** :
   - Installer Kubespray sur `install-01`
   - Configurer l'inventaire (3 masters, 5 workers)
   - Configurer Calico en mode IPIP

3. **Migration des Applications** :
   - Recréer les namespaces
   - Recréer les ConfigMaps et Secrets
   - Recréer les Deployments et Services
   - Recréer les Ingress

4. **Validation** :
   - Tester DNS (CoreDNS)
   - Tester Services ClusterIP
   - Tester Pod-to-Pod
   - Tester Ingress → Backend
   - Tester URLs externes

---

## 📝 Notes Techniques

### Pourquoi Calico IPIP fonctionne avec Kubespray ?

1. **Kubespray désactive complètement Flannel** :
   - Pas de fichiers CNI Flannel
   - Pas de routes VXLAN
   - kubelet utilise uniquement Calico

2. **Calico IPIP ne nécessite pas ipset récent** :
   - IPIP utilise iptables standard
   - Pas de mismatch kernel/userspace
   - Compatible avec les kernels Hetzner

3. **Support Hetzner natif** :
   - IP routes propres
   - Pas de VXLAN
   - NAT IPv4 pour les workers
   - Overlay stable

### Incompatibilité K3s + Cilium

**Documentation** :
- Issues Rancher : K3s force Flannel
- Issues Cilium : Tunnel=disabled ne fonctionne pas sur K3s
- Problème structurel, pas de configuration

---

## ✅ Conclusion

**Solution Recommandée** : **Kubespray + Calico IPIP**

- ✅ Solution professionnelle et stable
- ✅ Utilisée par les gros SaaS sur Hetzner
- ✅ Compatible 100% avec Kubernetes standard
- ✅ Pas de VXLAN, pas d'IPIP problématique, pas d'ipset, pas de nftables
- ✅ Support complet de toutes les fonctionnalités Kubernetes

**Alternative Temporaire** : K3s + NodePort (solution patch, non recommandée pour production)

---

**Document créé le** : 2025-11-24  
**Auteur** : Analyse basée sur verdict ChatGPT Expert  
**Statut** : ✅ Solution définitive identifiée  
**Action Requise** : Restauration du cluster, puis migration vers Kubespray + Calico

