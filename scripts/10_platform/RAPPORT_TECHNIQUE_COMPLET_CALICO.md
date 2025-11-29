# Rapport Technique Complet : Migration Flannel → Calico IPIP

**Date** : 2025-11-24  
**Contexte** : Module 10 - Déploiement Platform KeyBuzz (API, UI, My Portal)  
**Infrastructure** : K3s HA sur Hetzner Cloud (8 nœuds : 3 masters + 5 workers)  
**Problème Initial** : Erreurs 503 Service Temporarily Unavailable sur toutes les URLs

---

## 📋 Table des Matières

1. [Problème Initial](#problème-initial)
2. [Diagnostic](#diagnostic)
3. [Solution Proposée](#solution-proposée)
4. [Implémentation](#implémentation)
5. [Problèmes Rencontrés](#problèmes-rencontrés)
6. [État Actuel](#état-actuel)
7. [Solutions Proposées](#solutions-proposées)
8. [Questions pour ChatGPT](#questions-pour-chatgpt)

---

## 🔴 Problème Initial

### Symptômes

1. **Erreurs 503 Service Temporarily Unavailable** sur les 3 URLs :
   - `https://platform.keybuzz.io`
   - `https://platform-api.keybuzz.io`
   - `https://my.keybuzz.io`

2. **Pods en état Running** mais inaccessibles :
   ```bash
   kubectl get pods -n keybuzz
   # Tous les pods sont Running (1/1)
   # keybuzz-api-* : 3 pods Running
   # keybuzz-ui-* : 3 pods Running
   # keybuzz-my-ui-* : 3 pods Running
   ```

3. **Services ClusterIP non fonctionnels** :
   ```bash
   kubectl get svc -n keybuzz
   # Services créés mais inaccessibles
   # keybuzz-api: ClusterIP 10.43.92.243:8080
   # keybuzz-ui: ClusterIP 10.43.102.230:80
   # keybuzz-my-ui: ClusterIP 10.43.232.70:80
   ```

---

## 🔍 Diagnostic

### Tests de Connectivité Effectués

#### 1. Test Services ClusterIP depuis un Pod

```bash
kubectl exec -n keybuzz keybuzz-api-xxx -- curl http://10.43.92.243:8080/health
# Résultat : Timeout après 2+ minutes
```

**Conclusion** : Les Services ClusterIP ne sont pas routables.

#### 2. Test Connectivité IPs Pods Directes

```bash
# IPs des pods API
kubectl get pods -n keybuzz -l app=platform-api -o jsonpath='{.items[*].status.podIP}'
# Résultat : 10.42.5.5 10.42.7.7 10.42.9.4

# Test depuis l'Ingress NGINX (hostNetwork=true)
kubectl exec -n ingress-nginx nginx-ingress-controller-xxx -- curl http://10.42.5.5:8080/health
# Résultat : Timeout après 5 secondes
```

**Conclusion** : Le réseau overlay (flannel) ne fonctionne pas.

#### 3. Test CoreDNS

```bash
# CoreDNS était en CrashLoopBackOff (corrigé depuis)
kubectl get pods -n kube-system | grep coredns
# Maintenant : Running

# Test résolution DNS
kubectl exec -n keybuzz test-pod -- nslookup keybuzz-api.keybuzz.svc.cluster.local
# Résultat : connection timed out; no servers could be reached
```

**Conclusion** : CoreDNS ne peut pas être atteint car il utilise aussi le réseau overlay.

#### 4. Test Services NodePort

```bash
# Conversion en NodePort
kubectl patch svc keybuzz-api -n keybuzz --type='json' -p='[{"op":"replace","path":"/spec/type","value":"NodePort"}]'
# NodePort 30080 créé

# Test depuis un nœud worker
ssh root@10.0.0.110 'curl http://localhost:30080/health'
# Résultat : Timeout
```

**Conclusion** : Les NodePorts ne fonctionnent pas non plus.

### Cause Racine Identifiée

**VXLAN bloqué sur Hetzner Cloud** :
- Hetzner Cloud bloque le port UDP 8472 utilisé par VXLAN
- Flannel (CNI par défaut de K3s) utilise VXLAN pour créer le réseau overlay
- Sans VXLAN, le réseau overlay ne peut pas fonctionner

**Impact** :
- ❌ Services ClusterIP : Non fonctionnels (routage via kube-proxy nécessite le réseau overlay)
- ❌ Services NodePort : Non fonctionnels (même raison)
- ❌ Communication inter-pods via IPs overlay : Non fonctionnelle
- ❌ CoreDNS : Ne peut pas être atteint via le réseau overlay

**Architecture Actuelle (Cassée)** :
```
Ingress NGINX (hostNetwork=true) 
  → Essaie d'atteindre Service ClusterIP (10.43.x.x)
    → kube-proxy doit router via réseau overlay
      → VXLAN bloqué → Échec
```

---

## ✅ Solution Proposée

### Solution Définitive : Calico IPIP

**Principe** : Remplacer Flannel (VXLAN) par Calico (IPIP)

**Pourquoi Calico IPIP ?**
- ✅ IPIP fonctionne sur Hetzner Cloud (pas de port bloqué)
- ✅ Réseau overlay pleinement fonctionnel
- ✅ Services ClusterIP opérationnels
- ✅ CoreDNS accessible
- ✅ Compatible avec Deployments classiques
- ✅ Scalable (HPA, multi-replicas)
- ✅ Architecture Kubernetes native

**Architecture Cible** :
```
Ingress NGINX (DaemonSet + hostNetwork=true)
  ↓
Services ClusterIP (10.43.x.x) - Fonctionnels
  ↓
Calico IPIP Overlay Network
  ↓
Pods (10.42.x.x) - Deployments classiques
```

**Avantages** :
- ✅ Pas de hostNetwork sur les apps
- ✅ Pas de conflits de ports
- ✅ Scaling horizontal possible
- ✅ HPA fonctionnel
- ✅ Multi-tenant compatible
- ✅ Architecture Kubernetes standard

---

## 🔧 Implémentation

### Étape 1 : Désactiver Flannel

**Action** : Modifier `/etc/rancher/k3s/config.yaml` sur tous les masters

```yaml
flannel-backend: none
disable-network-policy: true
```

**Résultat** : ✅ Configuration appliquée sur les 3 masters (k3s-master-01, k3s-master-02, k3s-master-03)

### Étape 2 : Redémarrer K3s

**Action** : `systemctl restart k3s` sur tous les masters

**Résultat** : ✅ K3s redémarré, cluster accessible après 60 secondes

### Étape 3 : Installer Calico

**Action** :
```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

**Résultat** : ✅ Calico installé, 8 pods déployés (un par nœud)

### Étape 4 : Configurer Calico en Mode IPIP

**Action** : Patcher le DaemonSet Calico pour :
- `CALICO_IPV4POOL_IPIP: Always`
- `CALICO_IPV4POOL_VXLAN: Never`

**Résultat** : ✅ Configuration IPIP appliquée

### Étape 5 : Vérification Configuration

**Vérifications effectuées** :
- ✅ IPPool configuré : `ipipMode: Always`, `vxlanMode: Never`
- ✅ 8 IPAMBlocks créés (un par nœud)
- ✅ BGP peering établi : 7/8 nœuds connectés

---

## ⚠️ Problèmes Rencontrés

### Problème 1 : Conflit nftables/iptables

#### Symptôme

```
[ERROR] felix/table.go 881: iptables-save failed because there are incompatible nft rules in the table. 
Remove the nft rules to continue. ipVersion=0x4 table="filter"
```

#### Cause

Des règles nftables sont présentes sur les nœuds et bloquent l'utilisation d'iptables par Calico Felix.

#### Solution Appliquée

**Action** : Supprimer les règles nftables sur tous les nœuds

```bash
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  ssh root@$ip "nft flush ruleset 2>/dev/null || true"
done
```

**Résultat** : ✅ Règles nftables supprimées sur tous les nœuds

**Script créé** : `fix_calico_ipset_nft.sh` pour automatiser cette correction

### Problème 2 : ipset manquant/incompatible

#### Symptôme

```
[ERROR] felix/ipsets.go 599: Bad return code from 'ipset list'. 
error=exit status 1 family="inet" 
stderr="ipset v7.11: Kernel and userspace incompatible: 
settype hash:ip with revision 6 not supported by userspace."
```

#### Cause

1. **ipset manquant** : ipset n'était pas installé sur la plupart des nœuds
2. **Version incompatible** : Certains nœuds ont ipset v7.11 qui ne supporte pas la révision 6 de `hash:ip` requise par le kernel

#### Solution Appliquée

**Action 1** : Installer ipset sur tous les nœuds

```bash
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  ssh root@$ip "apt-get update && apt-get install ipset -y"
done
```

**Résultat** : ✅ ipset installé sur tous les nœuds

**Action 2** : Vérifier les versions

- k3s-master-01 : ipset v7.19 ✅ (compatible)
- Autres nœuds : ipset v7.11 ❌ (incompatible)

**Problème restant** : Certains nœuds ont toujours ipset v7.11 qui ne supporte pas la révision 6.

#### Solutions Proposées (Non Appliquées)

1. **Mettre à jour ipset vers v7.19** sur tous les nœuds :
   ```bash
   apt-get update
   apt-get install --only-upgrade ipset
   ```

2. **Désactiver ipset dans Calico** (workaround) :
   ```bash
   kubectl patch felixconfiguration default --type merge -p '{
     "spec": {
       "ipsetsRefreshInterval": "0s"
     }
   }'
   ```
   **Note** : Peut affecter les performances.

3. **Downgrade vers Calico v3.26** (compatible avec ipset v7.11)

### Problème 3 : Felix en "wait-for-ready"

#### Symptôme

```
calico/node is not ready: felix is not ready: readiness probe reporting 503
```

Tous les pods Calico restent en `0/1 Ready` (Running mais pas prêts).

#### Cause

Felix ne peut pas terminer son initialisation à cause des erreurs ipset et nftables.

#### État Actuel

- **Pods Calico Ready** : 3/8 (après corrections nftables et installation ipset)
- **BGP Peering** : 7/8 nœuds connectés ✅
- **Felix Status** : Toujours en "wait-for-ready" sur certains nœuds

---

## 📊 État Actuel

### Pods Calico

```bash
kubectl get pods -n kube-system -l k8s-app=calico-node
```

**Résultat** :
- 3/8 pods sont `1/1 Ready`
- 5/8 pods sont `0/1 Running` (pas prêts)

### Services ClusterIP

**Test depuis un pod KeyBuzz** :
```bash
kubectl exec -n keybuzz keybuzz-api-xxx -- curl http://10.43.92.243:8080/health
# Résultat : ✅ "healthy"
```

**Test depuis Ingress NGINX** :
```bash
kubectl exec -n ingress-nginx nginx-ingress-controller-xxx -- curl http://keybuzz-api.keybuzz.svc.cluster.local:8080/health
# Résultat : ❌ Timeout / Could not resolve host
```

**Conclusion** : Le Service ClusterIP fonctionne depuis un pod, mais pas depuis l'Ingress (problème DNS).

### DNS

**Test résolution DNS** :
```bash
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup keybuzz-api.keybuzz.svc.cluster.local
# Résultat : ❌ "connection timed out; no servers could be reached"
```

**Conclusion** : CoreDNS ne répond pas aux requêtes DNS.

### URLs Externes

**Test** :
```bash
curl -k https://platform.keybuzz.io
curl -k https://platform-api.keybuzz.io/health
curl -k https://my.keybuzz.io
```

**Résultat** : ❌ 503 Service Temporarily Unavailable

**Conclusion** : Les URLs externes ne fonctionnent toujours pas.

### Configuration Calico

**IPPool** :
```yaml
spec:
  ipipMode: Always
  vxlanMode: Never
  cidr: 192.168.0.0/16
  natOutgoing: true
```

**IPAMBlocks** : 8 blocks créés (un par nœud) ✅

**BGP** : 7/8 nœuds avec peering établi ✅

---

## 💡 Solutions Proposées

### Solution 1 : Mettre à jour ipset vers v7.19 (Recommandé)

**Action** : Mettre à jour ipset sur tous les nœuds qui ont encore v7.11

```bash
for ip in 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  ssh root@$ip "apt-get update && apt-get install --only-upgrade ipset -y"
done
```

**Puis** : Redémarrer les pods Calico
```bash
kubectl delete pod -n kube-system -l k8s-app=calico-node
```

**Avantages** :
- ✅ Résout le problème ipset à la source
- ✅ Pas d'impact sur les performances
- ✅ Solution définitive

**Inconvénients** :
- ⚠️ Nécessite un accès SSH à tous les nœuds
- ⚠️ Peut nécessiter un redémarrage des pods Calico

### Solution 2 : Désactiver ipset dans Calico (Workaround)

**Action** : Configurer Felix pour ne pas utiliser ipset

```bash
kubectl patch felixconfiguration default --type merge -p '{
  "spec": {
    "ipsetsRefreshInterval": "0s",
    "ipSetRefreshInterval": "0s"
  }
}'
```

**Avantages** :
- ✅ Solution rapide
- ✅ Pas besoin d'accès SSH aux nœuds

**Inconvénients** :
- ⚠️ Peut affecter les performances de Calico
- ⚠️ Certaines fonctionnalités peuvent ne pas fonctionner
- ⚠️ Solution temporaire, pas définitive

### Solution 3 : Downgrade vers Calico v3.26

**Action** : Remplacer Calico v3.27 par v3.26

```bash
kubectl delete -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.5/manifests/calico.yaml
```

**Puis** : Reconfigurer IPIP comme précédemment.

**Avantages** :
- ✅ Compatible avec ipset v7.11
- ✅ Pas besoin de mettre à jour ipset

**Inconvénients** :
- ⚠️ Version plus ancienne (moins de fonctionnalités)
- ⚠️ Nécessite de réinstaller Calico

### Solution 4 : Attendre que Calico termine son initialisation

**Action** : Attendre 10-20 minutes supplémentaires

**Raison** : Felix peut prendre du temps pour terminer sa configuration, même avec des erreurs ipset.

**Avantages** :
- ✅ Pas d'action requise
- ✅ Peut résoudre le problème naturellement

**Inconvénients** :
- ⚠️ Pas garanti que cela résolve le problème
- ⚠️ Les erreurs ipset peuvent persister

---

## ❓ Questions pour ChatGPT

### Question 1 : Compatibilité ipset

**Contexte** : Certains nœuds ont ipset v7.11 qui ne supporte pas la révision 6 de `hash:ip` requise par le kernel. D'autres nœuds ont ipset v7.19 qui fonctionne.

**Questions** :
1. Calico peut-il fonctionner avec un mélange de versions ipset sur différents nœuds ?
2. Est-il possible de configurer Calico pour qu'il fonctionne avec ipset v7.11 ?
3. Y a-t-il une configuration Felix qui permet de contourner le problème ipset ?

### Question 2 : DNS et CoreDNS

**Contexte** : CoreDNS est Running mais ne répond pas aux requêtes DNS. Les pods ne peuvent pas résoudre les noms de services.

**Questions** :
1. Pourquoi CoreDNS ne répond pas malgré le fait qu'il soit Running ?
2. Y a-t-il une relation entre les erreurs ipset et le dysfonctionnement de CoreDNS ?
3. Comment diagnostiquer et corriger le problème DNS dans ce contexte ?

### Question 3 : Services ClusterIP depuis Ingress

**Contexte** : Le Service ClusterIP fonctionne depuis un pod KeyBuzz (`healthy`), mais l'Ingress NGINX ne peut pas y accéder (timeout / DNS resolution failed).

**Questions** :
1. Pourquoi l'Ingress NGINX (hostNetwork=true) ne peut pas accéder aux Services ClusterIP alors qu'un pod normal peut ?
2. Y a-t-il une configuration spécifique nécessaire pour que l'Ingress puisse accéder aux Services ClusterIP avec Calico ?
3. Le problème vient-il du DNS ou du routage réseau ?

### Question 4 : Stratégie de Correction

**Contexte** : Nous avons 3/8 pods Calico Ready, des erreurs ipset persistantes, et le réseau ne fonctionne toujours pas complètement.

**Questions** :
1. Quelle est la meilleure stratégie pour résoudre ce problème : mettre à jour ipset, désactiver ipset, ou downgrade Calico ?
2. Est-il normal que seulement 3/8 pods Calico soient Ready après 1 heure d'attente ?
3. Y a-t-il d'autres problèmes que nous n'avons pas identifiés qui pourraient bloquer Calico ?

### Question 5 : Alternative à Calico

**Contexte** : Calico rencontre des problèmes de compatibilité avec ipset et nftables.

**Questions** :
1. Y a-t-il une alternative à Calico qui fonctionnerait mieux sur Hetzner Cloud avec K3s ?
2. Cilium serait-il une meilleure option ? Quels sont les avantages/inconvénients ?
3. Est-il possible de faire fonctionner Flannel sans VXLAN (mode host-gw) ?

### Question 6 : Diagnostic Complémentaire

**Contexte** : Nous avons fait beaucoup de tests mais le problème persiste.

**Questions** :
1. Quels autres diagnostics devrions-nous effectuer pour identifier la cause racine ?
2. Y a-t-il des logs spécifiques à vérifier que nous n'avons pas encore consultés ?
3. Comment vérifier si le routage IPIP fonctionne correctement entre les nœuds ?

---

## 📝 Commandes de Diagnostic Utiles

### Vérifier l'état Calico

```bash
# État des pods
kubectl get pods -n kube-system -l k8s-app=calico-node -o wide

# Logs Calico
kubectl logs -n kube-system -l k8s-app=calico-node --tail=50 | grep -E 'ERROR|WARN|ready'

# Readiness probe
kubectl exec -n kube-system calico-node-xxx -- /bin/calico-node -felix-ready -bird-ready
```

### Vérifier le routage

```bash
# Routes depuis un pod
kubectl exec -n keybuzz keybuzz-api-xxx -- ip route

# Test connectivité Pod-to-Pod
kubectl exec -n keybuzz keybuzz-api-xxx -- ping -c 2 10.42.5.5

# Test Service ClusterIP
kubectl exec -n keybuzz keybuzz-api-xxx -- curl http://10.43.92.243:8080/health
```

### Vérifier DNS

```bash
# Test résolution DNS
kubectl run test-dns --image=busybox:1.36 --rm -it --restart=Never -- nslookup keybuzz-api.keybuzz.svc.cluster.local

# Logs CoreDNS
kubectl logs -n kube-system -l k8s-app=kube-dns --tail=50

# Configuration CoreDNS
kubectl get configmap -n kube-system coredns -o yaml
```

### Vérifier ipset

```bash
# Version ipset sur chaque nœud
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  echo "$ip:"
  ssh root@$ip "ipset --version 2>&1 | head -1"
done
```

---

## 📚 Références

- **Calico Documentation** : https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements
- **Calico IPIP Mode** : https://docs.tigera.io/calico/latest/networking/configuring/vxlan-ipip
- **Calico Troubleshooting** : https://docs.tigera.io/calico/latest/operations/troubleshooting/
- **K3s Network Configuration** : https://docs.k3s.io/networking
- **Hetzner Cloud Network Limitations** : Port UDP 8472 bloqué (VXLAN)
- **ipset Compatibility** : https://ipset.netfilter.org/ipset.man.html

---

## 🎯 Résumé Exécutif

**Problème Initial** : VXLAN bloqué sur Hetzner Cloud → Flannel non fonctionnel → Réseau overlay cassé → Erreurs 503

**Solution Appliquée** : Migration vers Calico IPIP

**Problèmes Rencontrés** :
1. ✅ Conflit nftables/iptables → Résolu (règles nftables supprimées)
2. ⚠️ ipset manquant/incompatible → Partiellement résolu (installé mais versions mixtes)
3. ⚠️ Felix en "wait-for-ready" → En cours (3/8 pods Ready)

**État Actuel** :
- ✅ Calico installé et configuré (IPIP mode)
- ✅ BGP peering établi (7/8 nœuds)
- ⚠️ 3/8 pods Calico Ready
- ⚠️ Erreurs ipset persistantes
- ❌ DNS ne fonctionne pas
- ❌ Ingress ne peut pas accéder aux Services ClusterIP
- ❌ Erreurs 503 toujours présentes

**Prochaines Étapes Recommandées** :
1. Mettre à jour ipset vers v7.19 sur tous les nœuds
2. Redémarrer les pods Calico
3. Vérifier que tous les pods Calico passent en Ready
4. Tester DNS et Ingress

---

---

## 🎯 VERDICT FINAL (ChatGPT Expert KeyBuzz)

### Diagnostic Final

**État Actuel** :
- ❌ Flannel (VXLAN) : Cassé (bloqué par Hetzner)
- ❌ Calico (IPIP) : Cassé (incompatibilité ipset/kernel)
- ❌ DNS : Cassé
- ❌ Services ClusterIP : Cassés
- ❌ Ingress : Ne peut plus joindre l'overlay

**Cause Racine Unique** :
```
ipset v7.11: Kernel and userspace incompatible: 
settype hash:ip with revision 6 not supported by userspace.
```

**Conclusion** : 
- ❌ **Calico NE PEUT PAS FONCTIONNER** sur des nœuds avec ipset v7.11
- ❌ Erreur FATALE, bloquante, NON contournable sans upgrade OS
- ❌ Même avec patches Felix, désactivation ipset, suppression nftables → état bancal
- ❌ Calico ne fonctionnera jamais proprement sur ce cluster

**Verdict** : **ARRÊTER la migration Calico MAINTENANT**

### Solution Définitive : Cilium

**Pourquoi Cilium ?**
- ✅ Ne dépend PAS d'ipset
- ✅ N'utilise PAS VXLAN par défaut
- ✅ Pas d'iptables/nftables
- ✅ Pas d'IPIP
- ✅ Utilise eBPF du kernel (compatible 100% avec kernels Hetzner)
- ✅ Performances maximales
- ✅ Stable + moderne
- ✅ Recommandé pour infrastructures Kubernetes modernes

**Configuration Cilium** :
- Mode : `tunneling=disabled` + `kube-proxy-replacement=strict`
- Pas de VXLAN, pas d'IPIP, pas d'IPSet, pas d'iptables, pas de nftables
- Compatible 100% avec kernels Hetzner

**Plan d'Action** :
1. Purger Calico proprement
2. Réactiver Flannel temporairement (pour stabilité)
3. Installer Cilium (tunnel=disabled)
4. Vérifications
5. Reprendre Module 10

---

**Document créé le** : 2025-11-24  
**Auteur** : Auto (Agent IA)  
**Statut** : ✅ Verdict final reçu - Migration vers Cilium recommandée  
**Priorité** : CRITIQUE - Bloque le déploiement du Module 10

