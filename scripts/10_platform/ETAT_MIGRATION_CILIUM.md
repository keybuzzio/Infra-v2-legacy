# État de la Migration vers Cilium

**Date** : 2025-11-24  
**Statut** : ⚠️ En cours - Problème de configuration détecté

---

## 🔴 Problème Actuel

### Symptôme

Tous les pods Cilium sont en `CrashLoopBackOff` avec l'erreur :

```
level=fatal msg="auto-direct-node-routes cannot be used with tunneling. 
Packets must be routed through the tunnel device." subsys=daemon
```

### Diagnostic

1. **Configuration appliquée** :
   - `tunnel=disabled` via CLI Cilium
   - `autoDirectNodeRoutes=true`
   - `enableBPFMasquerade=true`
   - `kubeProxyReplacement=strict`
   - `ipv4NativeRoutingCIDR=10.42.0.0/16`

2. **Vérification ConfigMap** :
   ```bash
   kubectl -n kube-system get configmap cilium-config -o yaml | grep tunnel
   # Résultat : tunnel non présent dans le ConfigMap
   ```

3. **Comportement observé** :
   - Cilium CLI indique `tunnel=disabled` lors de l'installation
   - Mais Cilium détecte toujours un tunneling activé
   - L'erreur persiste même après nettoyage des interfaces

### Hypothèses

1. **Cilium détecte automatiquement le tunneling** basé sur la configuration réseau existante (Flannel)
2. **Le ConfigMap n'est pas correctement mis à jour** par le CLI
3. **Cilium nécessite une désactivation complète de Flannel** avant installation
4. **Version Cilium 1.15.3** peut avoir un bug ou nécessiter une configuration différente

---

## 🔧 Actions Tentées

1. ✅ Installation Cilium avec `--set tunnel=disabled`
2. ✅ Patch manuel du ConfigMap (échoué - syntaxe)
3. ✅ Nettoyage des interfaces réseau (vxlan, flannel)
4. ✅ Désinstallation/réinstallation complète
5. ❌ Configuration tunnel=disabled ne prend pas effet

---

## 💡 Solutions à Essayer

### Solution 1 : Désactiver complètement Flannel avant Cilium

**Action** :
```bash
# Sur tous les masters
cat > /etc/rancher/k3s/config.yaml <<EOF
flannel-backend: none
disable-network-policy: true
EOF
systemctl restart k3s

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
  --set autoDirectNodeRoutes=true \
  --set enableBPFMasquerade=true \
  --set kubeProxyReplacement=strict
```

### Solution 3 : Utiliser une version différente de Cilium

**Action** :
```bash
cilium install --version 1.14.9 --set tunnel=disabled ...
```

### Solution 4 : Vérifier la configuration réseau K3s

**Action** :
- Vérifier si K3s a une configuration réseau qui force le tunneling
- Vérifier les routes réseau sur les nœuds
- Vérifier si Flannel est vraiment désactivé

---

## 📋 État Actuel du Cluster

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
# Résultat : 0/8 pods Ready (tous en CrashLoopBackOff)

kubectl get nodes
# Résultat : 8/8 nœuds Ready

kubectl get pods -n keybuzz
# Résultat : 9/9 pods Running (mais non accessibles)
```

---

## ❓ Questions pour ChatGPT

1. **Pourquoi Cilium détecte-t-il un tunneling alors que tunnel=disabled est configuré ?**
   - Est-ce que Flannel doit être complètement désinstallé avant Cilium ?
   - Y a-t-il une configuration K3s qui force le tunneling ?

2. **Comment forcer Cilium à utiliser le mode direct-routing sans tunneling ?**
   - Y a-t-il une autre méthode de configuration ?
   - Faut-il utiliser Helm au lieu du CLI ?

3. **Y a-t-il une incompatibilité entre K3s et Cilium en mode direct-routing ?**
   - K3s a-t-il des exigences spécifiques pour le CNI ?
   - Faut-il configurer K3s différemment ?

4. **Alternative : Utiliser Cilium en mode VXLAN (au lieu de disabled) ?**
   - Mais VXLAN est bloqué sur Hetzner...
   - Ou utiliser un autre mode de tunneling compatible ?

---

**Document créé le** : 2025-11-24  
**Statut** : ⚠️ Migration bloquée - Configuration tunnel=disabled ne prend pas effet  
**Action Requise** : Investigation avec ChatGPT

