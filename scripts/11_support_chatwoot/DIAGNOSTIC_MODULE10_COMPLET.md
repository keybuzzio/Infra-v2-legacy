# Diagnostic Complet Module 10 - Problème Réseau

## ✅ Découvertes importantes

### Tests de connectivité

#### Depuis le node où se trouve le pod API (worker-03, 10.0.0.112)
- ✅ **Ping vers pod API (10.233.7.136)** : OK (0% packet loss)
- ✅ **Curl vers pod API (10.233.7.136:8080)** : OK (`{"status":"ok","service":"keybuzz-platform-api"}`)
- ✅ **Route Calico** : `10.233.7.136 dev cali45f8f5f4b01 scope link`

#### Depuis un autre node (worker-01, 10.0.0.110)
- ❌ **Ping vers pod API (10.233.7.136)** : 100% packet loss
- ❌ **Curl vers pod API (10.233.7.136:8080)** : Timeout
- ❌ **Curl vers Service ClusterIP (10.110.76.162:8080)** : Timeout
- ❌ **Pas de route Calico** vers 10.233.7.136

### Configuration actuelle

#### Calico
- **CIDR** : `10.233.0.0/16`
- **IPIP Mode** : Always
- **natOutgoing** : true
- **Routes** : Chaque node a seulement les routes vers ses propres pods (scope link)

#### Ingress-nginx
- **Mode** : DaemonSet avec hostNetwork
- **Pods** : 5 pods sur tous les workers (10.0.0.110-114)
- **Backend** : Pointe vers Service `keybuzz-api:8080`

#### Service keybuzz-api
- **Type** : ClusterIP
- **Port** : 8080
- **Endpoints** : 3 pods API (10.233.118.73, 10.233.55.200, 10.233.7.136)

## 🔴 Problème identifié

### Cause racine
**Calico en mode IPIP ne permet pas aux nodes de joindre directement les pods sur d'autres nodes via leur IP pod.**

Les routes Calico sont **locales** (scope link) :
- Chaque node a seulement les routes vers ses propres pods
- Les pods communiquent entre eux via IPIP tunnels
- Mais les nodes (hostNetwork) ne peuvent pas joindre les pods sur d'autres nodes directement

### Pourquoi UI fonctionne mais pas API ?
**Hypothèse** : Les pods UI sont peut-être sur le même node que certains pods ingress-nginx, ou il y a une différence de configuration.

### Pourquoi le Service ClusterIP ne fonctionne pas ?
**Ingress-nginx en hostNetwork ne peut pas utiliser kube-proxy** pour joindre les Services ClusterIP depuis les nodes.

## 💡 Solutions possibles

### Solution 1 : Service NodePort
Exposer l'API via NodePort au lieu de ClusterIP, puis ingress pointe vers NodeIP:NodePort.

### Solution 2 : Configurer Calico pour routage inter-node
Modifier la configuration Calico pour permettre aux nodes de joindre les pods sur d'autres nodes.

### Solution 3 : Changer ingress-nginx
Ne pas utiliser hostNetwork, utiliser un Service LoadBalancer ou NodePort.

### Solution 4 : Utiliser les IPs des pods directement
Configurer ingress-nginx pour utiliser les IPs des pods directement (nécessite que les pods soient sur le même node).

---

**Date** : 2025-11-28  
**Statut** : ⚠️ Diagnostic complet - Solutions à tester

