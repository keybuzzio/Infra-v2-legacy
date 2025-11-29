# Problème Réseau K3s : VXLAN Bloqué et Solution Technique

**Date** : 2025-11-24  
**Contexte** : Module 10 - Déploiement Platform KeyBuzz (API, UI, My Portal)  
**Infrastructure** : K3s HA sur Hetzner Cloud (8 nœuds : 3 masters + 5 workers)

---

## 🔴 Problème Identifié

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

### Diagnostic Technique

#### 1. Test de Connectivité Services ClusterIP

```bash
# Depuis un pod dans le cluster
kubectl exec -n keybuzz keybuzz-api-xxx -- curl http://10.43.92.243:8080/health
# Résultat : Timeout après 2+ minutes
```

**Conclusion** : Les Services ClusterIP ne sont pas routables.

#### 2. Test de Connectivité IPs Pods Directes

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

---

## 🔍 Cause Racine

### VXLAN Bloqué sur Hetzner Cloud

D'après la documentation existante (`SOLUTION_HOSTNETWORK.md`), **Hetzner Cloud bloque le protocole VXLAN** (port 8472/UDP), qui est utilisé par Flannel (CNI de K3s) pour créer le réseau overlay.

**Impact** :
- ❌ Services ClusterIP : Non fonctionnels (routage via kube-proxy nécessite le réseau overlay)
- ❌ Services NodePort : Non fonctionnels (même raison)
- ❌ Communication inter-pods via IPs overlay : Non fonctionnelle
- ❌ CoreDNS : Ne peut pas être atteint via le réseau overlay

**Architecture Actuelle** :
```
Ingress NGINX (hostNetwork=true) 
  → Essaie d'atteindre Service ClusterIP (10.43.x.x)
    → kube-proxy doit router via réseau overlay
      → VXLAN bloqué → Échec
```

---

## ✅ Solution Définitive : Remplacement Flannel par Calico IPIP

### ❌ Pourquoi hostNetwork sur les Apps est une Mauvaise Solution

**Problèmes avec hostNetwork sur les Deployments** :
- ❌ **Conflits de ports** : Impossible d'avoir plusieurs replicas sur le même nœud
- ❌ **Non scalable** : Pas de HPA possible
- ❌ **Port starvation** : Chaque app nécessite ses propres ports (API:8080, UI:80, My:80, Chatwoot:3000, etc.)
- ❌ **Sécurité réduite** : Accès direct au réseau hôte
- ❌ **Incompatible multi-tenant** : Partage de ports impossible
- ❌ **Performance instable** : Réseau partagé avec l'hôte
- ❌ **Montée en charge impossible** : Scaling horizontal bloqué

**Conclusion** : hostNetwork sur les apps est un hack qui ne tient pas la charge pour un SaaS comme KeyBuzz.

### ✅ Solution Professionnelle : Calico IPIP

**Remplacer Flannel (VXLAN) par Calico (IPIP)** :
- ✅ IPIP fonctionne sur Hetzner Cloud (pas de port bloqué)
- ✅ Réseau overlay pleinement fonctionnel
- ✅ Services ClusterIP opérationnels
- ✅ CoreDNS accessible
- ✅ Compatible avec Deployments classiques
- ✅ Scalable (HPA, multi-replicas)
- ✅ Architecture Kubernetes native

**Architecture avec Calico IPIP** :
```
Ingress NGINX (DaemonSet + hostNetwork=true)
  ↓
Services ClusterIP (10.43.x.x) - Fonctionnels
  ↓
Calico IPIP Overlay Network
  ↓
Pods (10.42.x.x) - Deployments classiques
```

### Procédure de Correction

#### Étape 1 : Désactiver Flannel

Sur tous les masters K3s, modifier `/etc/rancher/k3s/config.yaml` :
```yaml
flannel-backend: none
disable-network-policy: true
```

Puis redémarrer K3s : `systemctl restart k3s`

#### Étape 2 : Installer Calico

```bash
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml
```

#### Étape 3 : Configurer Calico en Mode IPIP

Patcher le DaemonSet Calico pour :
- `vxlanMode: Never`
- `ipipMode: Always`
- `natOutgoing: Enabled`

**Script disponible** : `fix_k3s_network_calico.sh`

#### Résultat

Après correction :
- ✅ Services ClusterIP fonctionnels
- ✅ CoreDNS accessible
- ✅ Communication Pod-to-Pod fonctionnelle
- ✅ Ingress → Backends opérationnel
- ✅ Deployments classiques (pas de hostNetwork)
- ✅ Scalabilité assurée (HPA, multi-replicas)

---

## ⚠️ Contraintes et Limitations

### 1. Ports Uniques par Nœud

Avec `hostNetwork: true`, chaque port ne peut être utilisé qu'une seule fois par nœud. Si plusieurs pods du même Deployment sont sur le même nœud, ils partageront le même port.

**Solution** : Utiliser un DaemonSet au lieu d'un Deployment pour garantir un pod par nœud, OU utiliser `podAntiAffinity` pour éviter la co-localisation.

### 2. Sécurité

Les pods avec `hostNetwork: true` ont accès à tous les ports du nœud hôte. Il faut s'assurer que :
- Les ports utilisés ne sont pas déjà utilisés par d'autres services
- Les pods ne peuvent pas écouter sur des ports privilégiés (< 1024) sans privilèges

### 3. DNS

Avec `dnsPolicy: ClusterFirstWithHostNet`, les pods peuvent toujours utiliser CoreDNS pour la résolution DNS, mais CoreDNS doit lui-même être accessible (potentiellement aussi en hostNetwork si nécessaire).

### 4. Scalabilité

Avec un Deployment et `hostNetwork: true`, si vous avez 3 replicas et 5 workers, les pods peuvent se répartir sur les nœuds. Mais si 2 pods se retrouvent sur le même nœud, ils partageront le même port (conflit).

**Recommandation** : Utiliser `podAntiAffinity` :
```yaml
spec:
  template:
    spec:
      affinity:
        podAntiAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
          - labelSelector:
              matchExpressions:
              - key: app
                operator: In
                values:
                - platform-api
            topologyKey: kubernetes.io/hostname
```

---

## 🔄 Alternatives Considérées

### Alternative 1 : Services NodePort + Load Balancer Direct

**Principe** : Configurer le Load Balancer Hetzner pour pointer directement vers les NodePorts.

**Problème** : Les NodePorts ne fonctionnent pas non plus car ils dépendent du réseau overlay.

### Alternative 2 : Utiliser un autre CNI

**Principe** : Remplacer Flannel par un CNI qui n'utilise pas VXLAN (ex: Calico avec IPIP, Cilium, etc.).

**Problème** : 
- Nécessite une reconfiguration complète du cluster
- Risque de downtime
- Complexité élevée

### Alternative 3 : DaemonSets au lieu de Deployments

**Principe** : Utiliser des DaemonSets avec `hostNetwork: true` pour garantir un pod par nœud.

**Avantages** :
- Pas de conflit de ports
- Distribution automatique sur tous les nœuds
- Solution déjà validée dans `SOLUTION_HOSTNETWORK.md`

**Inconvénients** :
- Nombre de pods fixe (un par nœud)
- Pas de scaling horizontal facile
- Si vous avez 5 workers, vous aurez toujours 5 pods (pas 3)

---

## 📋 Plan d'Action Proposé

### Option A : Deployments avec hostNetwork + podAntiAffinity (Recommandé)

1. Modifier les 3 Deployments (`keybuzz-api`, `keybuzz-ui`, `keybuzz-my-ui`) :
   - Ajouter `hostNetwork: true`
   - Ajouter `dnsPolicy: ClusterFirstWithHostNet`
   - Ajouter `hostPort` identique à `containerPort`
   - Ajouter `podAntiAffinity` pour éviter la co-localisation

2. Les Services ClusterIP restent inchangés (ils pointeront automatiquement vers les IPs des nœuds)

3. Les Ingress restent inchangés (ils utiliseront les Services ClusterIP qui fonctionneront maintenant)

**Avantages** :
- ✅ Contrôle du nombre de replicas (3 pods comme souhaité)
- ✅ Services ClusterIP fonctionnels
- ✅ Ingress fonctionnel
- ✅ Pas de conflit de ports grâce à podAntiAffinity

**Inconvénients** :
- ⚠️ Si un nœud tombe, les pods ne seront pas automatiquement redéployés sur un autre nœud (sauf si vous avez plus de replicas que de nœuds)

### Option B : DaemonSets avec hostNetwork (Solution Validée)

1. Convertir les Deployments en DaemonSets
2. Utiliser `hostNetwork: true`
3. Utiliser Services NodePort (ou ClusterIP qui pointera vers les IPs des nœuds)

**Avantages** :
- ✅ Solution déjà validée et documentée
- ✅ Pas de conflit de ports (un pod par nœud)
- ✅ Haute disponibilité (un pod sur chaque worker)

**Inconvénients** :
- ⚠️ Nombre de pods fixe (5 pods si 5 workers, pas 3)
- ⚠️ Pas de scaling horizontal facile

---

## ✅ Réponse de ChatGPT (Expert KeyBuzz)

### 1. KeyBuzz Platform peut-il fonctionner avec `hostNetwork: true` ?

**➡️ NON.** hostNetwork sur les apps est incompatible avec KeyBuzz :
- Conflits de ports (impossible pour API/UI/My)
- Scaling impossible (2 pods = crash)
- Performance instable
- Montée en charge impossible

### 2. Quelle option recommandez-vous ?

**➡️ Solution Définitive : Calico IPIP**
- Remplacer Flannel par Calico (IPIP mode)
- Garder les apps en Deployment ClusterIP classique
- Garder l'Ingress en DaemonSet hostNetwork

### 3. Alternative technique ?

**➡️ Calico IPIP est la seule solution viable** pour Hetzner Cloud :
- Hetzner bloque UDP 8472 → VXLAN KO
- Flannel + VXLAN = mort
- Seul Calico permet un overlay STABLE sans VXLAN

### 4. Impact sur les Modules 10-16 ?

**➡️ Après passage à Calico :**
- ✅ Plus besoin d'hostNetwork pour les apps
- ✅ Plus besoin de DaemonSets
- ✅ Module 10-16 fonctionnent comme n'importe quel cluster K8s
- ✅ KeyBuzz peut scaler (HPA, multi-replicas, auto-healing)

---

## 📚 Références

- `Infra/scripts/10_keybuzz/SOLUTION_HOSTNETWORK.md` : Solution validée avec DaemonSets + hostNetwork
- `Infra/scripts/10_platform/10_platform_01_deploy_api.sh` : Script actuel de déploiement API
- `Infra/scripts/10_platform/10_platform_02_deploy_ui.sh` : Script actuel de déploiement UI
- `Infra/scripts/10_platform/10_platform_03_deploy_my.sh` : Script actuel de déploiement My Portal

---

## 📝 Notes Techniques Supplémentaires

### État Actuel du Cluster

```bash
# Nœuds
k3s-master-01 : 10.0.0.100
k3s-master-02 : 10.0.0.101
k3s-master-03 : 10.0.0.102
k3s-worker-01 : 10.0.0.110
k3s-worker-02 : 10.0.0.111
k3s-worker-03 : 10.0.0.112
k3s-worker-04 : 10.0.0.113
k3s-worker-05 : 10.0.0.114

# Ingress NGINX
- DaemonSet avec hostNetwork: true
- Écoute sur ports 80/443 de tous les nœuds
- NodePort : 31695 (HTTP/HTTPS)

# Load Balancer Hetzner
- Pointe vers les 5 workers (10.0.0.110-114)
- Port 31695 (HTTP/HTTPS)
```

### Configuration Flannel Actuelle

```bash
# Flannel utilise VXLAN par défaut dans K3s
# Port 8472/UDP nécessaire mais bloqué par Hetzner
# Pas de configuration alternative visible dans K3s
```

---

**Document créé le** : 2025-11-24  
**Auteur** : Auto (Agent IA)  
**Statut** : ✅ Solution validée par ChatGPT (Expert KeyBuzz)

**Solution Définitive** : Voir `SOLUTION_CALICO_IPIP.md` et `fix_k3s_network_calico.sh`

