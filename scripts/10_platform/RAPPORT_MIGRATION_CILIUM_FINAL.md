# Rapport Final : Migration vers Cilium

**Date** : 2025-11-24  
**Statut** : ❌ ÉCHEC - Migration bloquée, cluster inaccessible

---

## 🔴 État Final

### Problème Principal

La migration vers Cilium a échoué après plusieurs tentatives. Le cluster est actuellement **inaccessible** (`dial tcp 10.0.0.100:6443: i/o timeout`).

### Causes Identifiées

1. **Cilium ne peut pas démarrer** avec la configuration `tunnel=disabled` :
   - Erreur : `auto-direct-node-routes cannot be used with tunneling`
   - Cilium détecte toujours `tunnel-protocol='vxlan'` malgré `tunnel=disabled`
   - Le ConfigMap ne contient pas la clé `tunnel` après installation

2. **Flannel n'est pas fonctionnel** :
   - VXLAN bloqué sur Hetzner Cloud
   - Le cluster dépend de Flannel pour le réseau overlay
   - Après désinstallation de Cilium, le cluster perd la connectivité

3. **Incompatibilité de configuration** :
   - `tunnelProtocol=disabled` n'est pas une valeur valide
   - `tunnel=disabled` ne désactive pas réellement le tunneling
   - Cilium détecte automatiquement le tunneling basé sur la configuration réseau

---

## 📋 Actions Tentées

1. ✅ Installation Cilium avec `--set tunnel=disabled`
2. ✅ Patch manuel du ConfigMap (échoué - syntaxe)
3. ✅ Nettoyage des interfaces réseau (vxlan, flannel)
4. ✅ Désinstallation/réinstallation complète
5. ✅ Tentative avec `tunnelProtocol=disabled` (erreur : invalid protocol)
6. ✅ Tentative sans `autoDirectNodeRoutes` (même erreur)
7. ❌ **Résultat** : Cluster inaccessible

---

## 🔧 Diagnostic Technique

### Logs Cilium

```
level=info msg="  --tunnel-port='0'" subsys=daemon
level=info msg="  --tunnel-protocol='vxlan'" subsys=daemon
level=fatal msg="auto-direct-node-routes cannot be used with tunneling. 
Packets must be routed through the tunnel device." subsys=daemon
```

**Conclusion** : Cilium utilise toujours VXLAN malgré `tunnel=disabled`.

### Configuration ConfigMap

```bash
kubectl -n kube-system get configmap cilium-config -o yaml | grep tunnel
# Résultat : tunnel non présent dans le ConfigMap
```

**Conclusion** : La configuration `tunnel=disabled` n'est pas appliquée au ConfigMap.

---

## 💡 Solutions à Explorer

### Solution 1 : Désactiver complètement Flannel AVANT Cilium

**Action** :
```bash
# Sur tous les masters
cat > /etc/rancher/k3s/config.yaml <<EOF
flannel-backend: none
disable-network-policy: true
EOF
systemctl restart k3s

# Attendre stabilisation
sleep 60

# Puis installer Cilium
cilium install --version 1.15.3 --set tunnel=disabled ...
```

### Solution 2 : Utiliser Helm au lieu du CLI

**Action** :
```bash
helm repo add cilium https://helm.cilium.io/
helm install cilium cilium/cilium \
  --namespace kube-system \
  --set tunnel=disabled \
  --set autoDirectNodeRoutes=false \
  --set enableBPFMasquerade=true \
  --set kubeProxyReplacement=strict
```

### Solution 3 : Utiliser une version différente de Cilium

**Action** :
```bash
cilium install --version 1.14.9 --set tunnel=disabled ...
```

### Solution 4 : Revenir à Flannel et utiliser NodePort

**Action** :
- Réactiver Flannel
- Utiliser NodePort pour les Services au lieu de ClusterIP
- Accepter que VXLAN ne fonctionne pas (mais NodePort fonctionne)

---

## ⚠️ État Actuel du Cluster

- ❌ **Cluster inaccessible** : `dial tcp 10.0.0.100:6443: i/o timeout`
- ❌ **Cilium** : Désinstallé
- ❌ **Flannel** : Non fonctionnel (VXLAN bloqué)
- ❌ **Réseau overlay** : Cassé

---

## 🚨 Actions Immédiates Requises

1. **Restaurer l'accès au cluster** :
   - Vérifier l'état des masters K3s
   - Redémarrer K3s si nécessaire
   - Réactiver Flannel temporairement

2. **Investigation avec ChatGPT** :
   - Pourquoi Cilium détecte-t-il toujours VXLAN ?
   - Comment forcer Cilium en mode direct-routing ?
   - Y a-t-il une incompatibilité K3s/Cilium ?

3. **Alternative** :
   - Considérer une autre solution CNI
   - Ou accepter NodePort au lieu de ClusterIP

---

## 📝 Questions pour ChatGPT

1. **Pourquoi `tunnel=disabled` ne désactive-t-il pas le tunneling dans Cilium ?**
   - Est-ce que Flannel doit être complètement désinstallé avant ?
   - Y a-t-il une configuration K3s qui force le tunneling ?

2. **Comment installer Cilium en mode direct-routing sur K3s ?**
   - Y a-t-il une méthode spécifique pour K3s ?
   - Faut-il utiliser Helm au lieu du CLI ?

3. **Y a-t-il une alternative à Cilium pour Hetzner Cloud ?**
   - Autre CNI compatible avec K3s et Hetzner ?
   - Ou solution de contournement avec Flannel/NodePort ?

---

**Document créé le** : 2025-11-24  
**Statut** : ❌ ÉCHEC - Cluster inaccessible, migration bloquée  
**Action Requise** : Restauration du cluster + Investigation avec ChatGPT

