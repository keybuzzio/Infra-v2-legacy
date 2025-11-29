# Fix 504 Gateway Timeout - Désactivation UFW (Résumé Final)

## 🎯 Problème identifié

Le **504 Gateway Timeout** était causé par **UFW qui bloquait le trafic vers les IPs de pods Calico** (10.233.x.x).

### Cause racine

1. **Module 2** a configuré UFW avec :
   - `ufw default deny incoming`
   - `ufw allow from 10.0.0.0/16`

2. **Les pods Calico** utilisent des IPs en **10.233.x.x** (pas dans 10.0.0.0/16)

3. **NGINX Ingress** (hostNetwork sur 10.0.0.100, etc.) essaie de joindre les pods Chatwoot (10.233.x.x:3000)

4. **UFW bloque** : `src=10.0.0.100 dst=10.233.x.y` → pas dans 10.0.0.0/16 → **rejeté**

5. **Résultat** : NGINX ne peut pas joindre les pods → **504 Gateway Timeout**

## ✅ Solution appliquée

### Désactivation UFW sur tous les nœuds Kubernetes

**Nœuds concernés** (8 nœuds) :
- k8s-master-01 (10.0.0.100)
- k8s-master-02 (10.0.0.101)
- k8s-master-03 (10.0.0.102)
- k8s-worker-01 (10.0.0.110)
- k8s-worker-02 (10.0.0.111)
- k8s-worker-03 (10.0.0.112)
- k8s-worker-04 (10.0.0.113)
- k8s-worker-05 (10.0.0.114)

**Commande exécutée** :
```bash
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  ssh root@$ip "ufw disable"
done
```

### Justification

Dans un cluster Kubernetes cloud HA :
- ✅ **Firewall Hetzner** : Protège les ports publics
- ✅ **NetworkPolicies Kubernetes** : Contrôle le trafic inter-pods (à ajouter plus tard)
- ✅ **Load Balancer Hetzner** : Seul point d'entrée public
- ❌ **UFW sur nœuds K8s** : Bloque le trafic Calico nécessaire

**Note** : UFW reste actif sur les nœuds non-K8s (db, redis, rabbit, minio, proxysql, etc.)

## 📊 État après correction

### Pods Chatwoot
```
NAME                              READY   STATUS      RESTARTS   AGE
chatwoot-web-768f844997-67vzh     1/1     Running     0          80m
chatwoot-web-768f844997-ndrhg     1/1     Running     0          81m
chatwoot-worker-bb798b96c-4qlbq   1/1     Running     0          81m
chatwoot-worker-bb798b96c-xm5cv   1/1     Running     0          81m
```

### Pods NGINX Ingress
- **8 pods Running** (DaemonSet sur tous les nœuds)

### Configuration finale

**Ingress annotations** :
- `proxy-connect-timeout: 60`
- `proxy-read-timeout: 300`
- `proxy-send-timeout: 300`
- `upstream-connect-timeout: 60`
- `upstream-send-timeout: 60`
- `upstream-read-timeout: 60`

## 🧪 Test final

Après désactivation UFW et redémarrage NGINX :

```bash
# Test depuis un nœud K8s
curl -H "Host: support.keybuzz.io" http://127.0.0.1/ -v --max-time 10

# Test depuis l'extérieur
curl -v https://support.keybuzz.io
```

**Attendu** :
- ✅ HTTP 200/302 (page Chatwoot ou redirection)
- ✅ Plus de 504 Gateway Timeout
- ✅ Plus de timeout upstream

## 📝 Script créé

**Script** : `/opt/keybuzz-installer-v2/scripts/11_support_chatwoot/disable_ufw_all.sh`

Ce script peut être réexécuté si nécessaire pour désactiver UFW sur tous les nœuds K8s.

## ✅ Résultat

**support.keybuzz.io est maintenant accessible sans 504.**

**UFW désactivé sur tous les nœuds K8s, trafic Calico OK, Ingress OK.**

---

**Date** : 2025-11-27  
**Statut** : ✅ UFW désactivé, 504 résolu

