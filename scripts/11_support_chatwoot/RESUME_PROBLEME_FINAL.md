# Résumé Problème Final - 504 Gateway Timeout

## 🔍 Problème identifié

**NGINX Ingress ne peut pas joindre les pods Chatwoot** (10.233.x.x) depuis les nœuds (10.0.0.x).

### Tests effectués

1. ❌ **IP Service (10.233.21.46:3000)** : timeout
2. ❌ **IP Pod (10.233.111.25:3000)** : timeout
3. ❌ **DNS (chatwoot-web.chatwoot.svc.cluster.local)** : connection timed out; no servers could be reached
4. ✅ **CoreDNS** : 2 pods Running
5. ⚠️ **/etc/resolv.conf dans NGINX** : pointe vers `169.254.25.10` (IP magique Kubernetes), mais timeout

## 📊 État actuel

- ✅ **DNS systemd-resolved configuré** sur tous les nœuds
- ✅ **NGINX Ingress** : 8 pods Running
- ✅ **Pods Chatwoot** : 2/2 Running
- ✅ **CoreDNS** : 2 pods Running
- ✅ **kube-proxy** : 4 pods Running
- ❌ **Connectivité NGINX → Pods Calico** : timeout

## 🔧 Cause probable

**Routage Calico bloqué** : NGINX Ingress avec `hostNetwork: true` ne peut pas joindre les IPs pods Calico (10.233.x.x) depuis les nœuds (10.0.0.x).

Même si UFW est inactive, il peut y avoir :
1. Des règles iptables qui bloquent le trafic
2. Des routes Calico manquantes ou incorrectes
3. Un problème de routage réseau entre 10.0.0.x et 10.233.x.x

## 💡 Solutions à tester

### Solution 1 : Vérifier les routes Calico
```bash
# Sur un nœud K8s
ip route | grep 10.233
calicoctl node status
```

### Solution 2 : Vérifier iptables
```bash
# Sur un nœud K8s
iptables -L -n | grep 10.233
iptables -t nat -L -n | grep 10.233
```

### Solution 3 : Vérifier Calico IPIP
```bash
# Vérifier que Calico IPIP est activé
calicoctl get ippool -o yaml
```

### Solution 4 : Tester depuis un pod normal (sans hostNetwork)
```bash
# Créer un pod de test
kubectl run test-pod --image=curlimages/curl --rm -it --restart=Never -- \
  wget -O- -T 5 http://chatwoot-web.chatwoot.svc.cluster.local:3000
```

## 📝 Prochaines étapes

1. Vérifier les routes Calico sur les nœuds
2. Vérifier les règles iptables
3. Vérifier la configuration Calico IPIP
4. Tester depuis un pod normal (sans hostNetwork) pour confirmer que le problème est spécifique à hostNetwork

---

**Date** : 2025-11-27  
**Statut** : Problème de routage Calico identifié - Investigation en cours

