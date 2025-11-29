# Résumé Fix kube-proxy - Complet

## ✅ État actuel

### kube-proxy
- ✅ **Mode** : iptables (configuré)
- ✅ **Règles iptables** : Présentes et correctes
  - `KUBE-SVC-WH67X75RIZJ5M7LP` : Pointe vers 2 endpoints
  - `KUBE-SEP-GC6753WHRTBYHHNO` : 10.233.111.25:3000
  - `KUBE-SEP-UREL7UUQFZ76F6NC` : 10.233.119.219:3000
- ✅ **Endpoints** : 2 endpoints valides
- ✅ **Service** : ClusterIP 10.233.21.46:3000

### Tests
- ❌ **Node → Service** : Connection timed out
- ❌ **Node → Pod direct** : Connection timed out
- ❌ **Externe → Chatwoot** : Operation timed out

## 🔍 Problème identifié

**Les règles iptables sont correctes, mais le routage réseau ne fonctionne pas**

Causes possibles :
1. **Routage Calico** : Les nœuds ne peuvent pas joindre les pods (10.233.x.x)
2. **Règles iptables DNAT** : Les chaînes KUBE-SEP ne font pas le DNAT correctement
3. **Routage réseau** : Problème de routage entre nœuds (10.0.0.x) et pods (10.233.x.x)

## 💡 Conclusion

**kube-proxy est correctement configuré**, mais le **routage réseau Calico est bloqué** entre les nœuds et les pods.

Même avec UFW désactivé et kube-proxy fonctionnel, les nœuds ne peuvent pas joindre les pods directement.

---

**Date** : 2025-11-27  
**Statut** : kube-proxy OK - Routage Calico bloqué

