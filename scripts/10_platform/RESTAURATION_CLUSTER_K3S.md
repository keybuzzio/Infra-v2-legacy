# Restauration du Cluster K3s

**Date** : 2025-11-24  
**Objectif** : Restaurer l'accès au cluster K3s après échec migration Cilium

---

## 🔴 État Actuel

- ❌ Cluster inaccessible : `dial tcp 10.0.0.100:6443: i/o timeout`
- ❌ Cilium désinstallé
- ❌ Flannel non fonctionnel (VXLAN bloqué)
- ❌ Réseau overlay cassé

---

## 🔧 Procédure de Restauration

### Étape 1 : Vérifier l'état des Masters

```bash
# Vérifier l'état du service K3s sur chaque master
for ip in 10.0.0.100 10.0.0.101 10.0.0.102; do
  echo "=== Master $ip ==="
  ssh root@$ip "systemctl status k3s | head -10"
done
```

### Étape 2 : Réactiver Flannel

```bash
# Sur tous les masters
for ip in 10.0.0.100 10.0.0.101 10.0.0.102; do
  ssh root@$ip "cat > /etc/rancher/k3s/config.yaml <<EOF
flannel-backend: vxlan
disable-network-policy: false
EOF
"
done
```

### Étape 3 : Redémarrer K3s

```bash
# Sur tous les masters
for ip in 10.0.0.100 10.0.0.101 10.0.0.102; do
  ssh root@$ip "systemctl restart k3s"
done
```

### Étape 4 : Attendre la Stabilisation

```bash
# Attendre 60-90 secondes
sleep 90
```

### Étape 5 : Vérifier l'Accès

```bash
# Depuis install-01
kubectl get nodes
kubectl get pods -n kube-system
```

### Étape 6 : Nettoyer les Interfaces Cilium

```bash
# Sur tous les nœuds
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  ssh root@$ip "ip link delete cilium_vxlan 2>/dev/null || true; echo OK $ip"
done
```

---

## ⚠️ Limitations Après Restauration

- ❌ **Flannel ne fonctionnera toujours pas** (VXLAN bloqué sur Hetzner)
- ❌ **Services ClusterIP ne fonctionneront pas**
- ❌ **DNS ne fonctionnera pas**
- ✅ **Cluster sera accessible** (API Kubernetes)
- ✅ **Pods pourront être créés** (mais non accessibles entre eux)

---

## 🔄 Solution Temporaire : Utiliser NodePort

Pour maintenir les applications fonctionnelles en attendant la migration vers Kubespray :

1. **Convertir les Services ClusterIP en NodePort** :
   ```bash
   kubectl patch svc keybuzz-api -n keybuzz -p '{"spec":{"type":"NodePort"}}'
   ```

2. **Mettre à jour les Ingress** pour pointer vers les NodePorts

3. **Accepter les limitations** :
   - Pas de DNS interne
   - Pas de Pod-to-Pod direct
   - Accès via NodePort uniquement

---

## 📋 Checklist de Restauration

- [ ] Vérifier l'état des masters
- [ ] Réactiver Flannel dans config.yaml
- [ ] Redémarrer K3s sur tous les masters
- [ ] Attendre stabilisation (90 secondes)
- [ ] Vérifier l'accès au cluster (`kubectl get nodes`)
- [ ] Nettoyer les interfaces Cilium
- [ ] Vérifier l'état des pods système
- [ ] Documenter l'état final

---

**Document créé le** : 2025-11-24  
**Statut** : ⚠️ À exécuter pour restaurer l'accès au cluster  
**Action Requise** : Exécuter la procédure de restauration

