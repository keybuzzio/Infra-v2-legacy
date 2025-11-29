# Problème Calico : Incompatibilité ipset

**Date** : 2025-11-24  
**Contexte** : Après installation de Calico IPIP pour remplacer Flannel  
**Symptôme** : Pods Calico restent en 0/1 Ready, Felix en "wait-for-ready"

---

## 🔴 Problème Identifié

### Erreur dans les Logs Calico

```
[ERROR] felix/ipsets.go 599: Bad return code from 'ipset list'. 
error=exit status 1 family="inet" 
stderr="ipset v7.11: Kernel and userspace incompatible: 
settype hash:ip with revision 6 not supported by userspace."
```

### Cause

**Incompatibilité entre le kernel et ipset userspace** :
- Le kernel supporte `hash:ip` révision 6
- L'utilisateur ipset (v7.11) ne supporte que les révisions précédentes
- Felix ne peut pas créer/gérer les IP sets nécessaires au routage

### Impact

- ❌ Felix reste bloqué en "wait-for-ready"
- ❌ Readiness probes échouent (503)
- ❌ Réseau overlay non fonctionnel
- ❌ Services ClusterIP non accessibles depuis l'Ingress
- ❌ DNS ne fonctionne pas
- ❌ Erreurs 503 sur toutes les URLs

---

## ✅ Solutions Possibles

### Solution 1 : Mettre à jour ipset (Recommandé)

**Sur tous les nœuds** :

```bash
# Vérifier la version actuelle
ipset --version

# Mettre à jour ipset
apt-get update
apt-get install --only-upgrade ipset

# Vérifier la nouvelle version
ipset --version
```

**Puis redémarrer les pods Calico** :
```bash
kubectl delete pod -n kube-system -l k8s-app=calico-node
```

### Solution 2 : Désactiver ipset dans Calico (Workaround)

**Configurer Felix pour ne pas utiliser ipset** :

```bash
kubectl patch felixconfiguration default --type merge -p '{
  "spec": {
    "ipsetsRefreshInterval": "0s",
    "ipSetRefreshInterval": "0s"
  }
}'
```

**Note** : Cela peut affecter les performances et certaines fonctionnalités de Calico.

### Solution 3 : Utiliser une version de Calico compatible

**Downgrade vers Calico v3.26** qui peut être compatible avec ipset v7.11 :

```bash
kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.5/manifests/calico.yaml
```

**Puis reconfigurer IPIP** comme précédemment.

### Solution 4 : Mettre à jour le kernel (Solution Long Terme)

**Sur tous les nœuds** :

```bash
# Vérifier la version du kernel
uname -r

# Mettre à jour le kernel (si nécessaire)
apt-get update
apt-get install linux-generic-hwe-24.04

# Redémarrer les nœuds
reboot
```

**Note** : Nécessite un redémarrage de tous les nœuds, donc downtime planifié.

---

## 🔧 Solution Immédiate Recommandée

### Étape 1 : Vérifier ipset sur un nœud

```bash
ssh root@10.0.0.100 "ipset --version"
```

### Étape 2 : Mettre à jour ipset sur tous les nœuds

```bash
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  echo "Mise à jour ipset sur $ip..."
  ssh root@$ip "apt-get update && apt-get install --only-upgrade ipset -y"
done
```

### Étape 3 : Redémarrer les pods Calico

```bash
kubectl delete pod -n kube-system -l k8s-app=calico-node
```

### Étape 4 : Vérifier que les erreurs ipset disparaissent

```bash
kubectl logs -n kube-system -l k8s-app=calico-node --tail=20 | grep -i ipset
```

### Étape 5 : Attendre que tous les pods Calico passent en Ready

```bash
kubectl get pods -n kube-system -l k8s-app=calico-node
# Attendre que tous soient 1/1 Ready
```

### Étape 6 : Tester la connectivité

```bash
# Test DNS
kubectl run test-dns --image=busybox:1.36 -n default --rm -it --restart=Never -- nslookup keybuzz-api.keybuzz.svc.cluster.local

# Test Service ClusterIP depuis Ingress
kubectl exec -n ingress-nginx nginx-ingress-controller-xxx -- curl http://keybuzz-api.keybuzz.svc.cluster.local:8080/health

# Test URLs externes
curl -k https://platform.keybuzz.io
curl -k https://platform-api.keybuzz.io/health
```

---

## 📋 Checklist de Validation

Après correction :

- [ ] Tous les pods Calico sont 1/1 Ready
- [ ] Plus d'erreurs ipset dans les logs
- [ ] Felix est prêt (readiness probe OK)
- [ ] DNS fonctionne (résolution des noms de services)
- [ ] Services ClusterIP accessibles depuis l'Ingress
- [ ] Connectivité Pod-to-Pod fonctionnelle
- [ ] URLs externes répondent HTTP 200 (plus de 503)

---

## 🔍 Diagnostic Complémentaire

### Vérifier la version ipset

```bash
# Sur chaque nœud
ipset --version
```

### Vérifier les modules kernel ipset

```bash
# Sur chaque nœud
lsmod | grep ip_set
modinfo ip_set_hash_ip
```

### Vérifier les logs Felix détaillés

```bash
kubectl logs -n kube-system -l k8s-app=calico-node --tail=100 | grep -E 'ipset|ERROR|FATAL'
```

---

## 📚 Références

- **Calico Troubleshooting** : https://docs.tigera.io/calico/latest/operations/troubleshooting/
- **ipset Compatibility** : https://ipset.netfilter.org/ipset.man.html
- **Ubuntu Kernel Updates** : https://wiki.ubuntu.com/Kernel/LTSEnablementStack

---

**Document créé le** : 2025-11-24  
**Statut** : Problème identifié, solutions proposées  
**Priorité** : CRITIQUE - Bloque le fonctionnement du réseau

