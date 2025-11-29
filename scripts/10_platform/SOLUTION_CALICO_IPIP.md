# Solution Définitive : Remplacement Flannel par Calico IPIP

**Date** : 2025-11-24  
**Contexte** : Correction du réseau K3s sur Hetzner Cloud  
**Problème** : VXLAN bloqué (port 8472/UDP) → Flannel non fonctionnel  
**Solution** : Calico CNI en mode IPIP (sans VXLAN)

---

## 🔴 Problème Identifié

### Cause Racine

**Hetzner Cloud bloque le port UDP 8472** utilisé par VXLAN (Flannel).

**Impact** :
- ❌ Services ClusterIP : Non routables
- ❌ Services NodePort : Non fonctionnels
- ❌ CoreDNS : Non accessible via réseau overlay
- ❌ Communication Pod-to-Pod : Échoue
- ❌ Ingress → Backends : 503 Service Temporarily Unavailable

### Pourquoi hostNetwork sur les Apps est une Mauvaise Solution

❌ **Conflits de ports** : Impossible d'avoir plusieurs replicas sur le même nœud  
❌ **Non scalable** : Pas de HPA possible  
❌ **Port starvation** : Chaque app nécessite ses propres ports (API:8080, UI:80, My:80, Chatwoot:3000, etc.)  
❌ **Sécurité réduite** : Accès direct au réseau hôte  
❌ **Incompatible multi-tenant** : Partage de ports impossible  
❌ **Performance instable** : Réseau partagé avec l'hôte  

**Conclusion** : hostNetwork sur les apps est un hack qui ne tient pas la charge pour un SaaS comme KeyBuzz.

---

## ✅ Solution Définitive : Calico IPIP

### Principe

**Remplacer Flannel (VXLAN) par Calico (IPIP)** :
- ✅ IPIP fonctionne sur Hetzner Cloud (pas de port bloqué)
- ✅ Réseau overlay pleinement fonctionnel
- ✅ Services ClusterIP opérationnels
- ✅ CoreDNS accessible
- ✅ Compatible avec Deployments classiques
- ✅ Scalable (HPA, multi-replicas)
- ✅ Architecture Kubernetes native

### Architecture Finale

```
Ingress NGINX (DaemonSet + hostNetwork=true)
  ↓
Services ClusterIP (10.43.x.x)
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

## 🔧 Procédure de Correction

### Étape 1 : Désactiver Flannel

**Sur tous les masters K3s** (k3s-master-01, k3s-master-02, k3s-master-03) :

```bash
# Modifier /etc/rancher/k3s/config.yaml
cat >> /etc/rancher/k3s/config.yaml <<EOF
flannel-backend: none
disable-network-policy: true
EOF

# Redémarrer K3s
systemctl restart k3s
```

**Attendre** que tous les masters soient prêts (environ 30-60 secondes).

### Étape 2 : Installer Calico

**Depuis install-01** :

```bash
# Installer Calico
kubectl apply -f https://raw.githubusercontent.com/projectcalico/calico/v3.27.0/manifests/calico.yaml

# Attendre que Calico soit déployé
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n kube-system --timeout=300s
```

### Étape 3 : Configurer Calico en Mode IPIP

**Créer le fichier de configuration Calico** :

```bash
cat > /tmp/calico-ipip-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: calico-config
  namespace: kube-system
data:
  calico_backend: "none"
  ipipMode: "Always"
  vxlanMode: "Never"
  natOutgoing: "Enabled"
EOF

kubectl apply -f /tmp/calico-ipip-config.yaml
```

**Patcher le DaemonSet Calico** :

```bash
# Mettre à jour la configuration IPIP
kubectl patch daemonset calico-node -n kube-system --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "CALICO_IPV4POOL_IPIP",
      "value": "Always"
    }
  },
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/env/-",
    "value": {
      "name": "CALICO_IPV4POOL_VXLAN",
      "value": "Never"
    }
  }
]'

# Redémarrer les pods Calico
kubectl rollout restart daemonset calico-node -n kube-system
```

### Étape 4 : Vérifications Post-Installation

#### 4.1 Vérifier Calico

```bash
kubectl get pods -n kube-system | grep calico
# Doit afficher : calico-node-xxx Running (1/1) sur chaque nœud
```

#### 4.2 Vérifier CoreDNS

```bash
kubectl get pods -n kube-system | grep coredns
# Doit afficher : coredns-xxx Running (1/1)

# Test résolution DNS
kubectl run test-dns --image=busybox:1.36 -n default --rm -it --restart=Never -- nslookup kubernetes.default.svc.cluster.local
# Doit réussir
```

#### 4.3 Vérifier Services ClusterIP

```bash
# Tester depuis un pod
kubectl run test-curl --image=curlimages/curl -n keybuzz --rm -it --restart=Never -- curl http://keybuzz-api.keybuzz.svc.cluster.local:8080/health
# Doit retourner : healthy
```

#### 4.4 Vérifier Communication Pod-to-Pod

```bash
# Récupérer une IP de pod
POD_IP=$(kubectl get pods -n keybuzz -l app=platform-api -o jsonpath='{.items[0].status.podIP}')

# Tester depuis un autre pod
kubectl run test-pod --image=curlimages/curl -n keybuzz --rm -it --restart=Never -- curl http://${POD_IP}:8080/health
# Doit réussir
```

#### 4.5 Vérifier Ingress → Backends

```bash
# Tester depuis l'Ingress NGINX
kubectl exec -n ingress-nginx nginx-ingress-controller-xxx -- curl http://keybuzz-api.keybuzz.svc.cluster.local:8080/health
# Doit retourner : healthy
```

#### 4.6 Vérifier URLs Externes

```bash
# Depuis un pod test
kubectl run test-urls --image=curlimages/curl -n keybuzz --rm -it --restart=Never -- sh -c "
  curl -k https://platform.keybuzz.io && echo ''
  curl -k https://platform-api.keybuzz.io/health && echo ''
  curl -k https://my.keybuzz.io && echo ''
"
# Doit retourner HTTP 200
```

---

## 📋 Checklist de Validation

- [ ] Calico déployé sur tous les nœuds
- [ ] CoreDNS Running et répond aux requêtes DNS
- [ ] Services ClusterIP routables
- [ ] Communication Pod-to-Pod fonctionnelle
- [ ] Ingress NGINX peut atteindre les Services ClusterIP
- [ ] URLs externes (platform.*, platform-api.*, my.*) répondent HTTP 200
- [ ] Pas d'erreurs 503
- [ ] Pas de hostNetwork sur les apps
- [ ] Deployments fonctionnent normalement

---

## 🚫 Interdictions Strictes

Après correction avec Calico, **NE JAMAIS** :

❌ Utiliser `hostNetwork: true` sur les Deployments  
❌ Transformer les apps en DaemonSet  
❌ Utiliser `hostPort` dans les Deployments  
❌ Exposer les Services en NodePort (sauf cas spécifiques)  
❌ Utiliser des IPs hardcodées dans les apps  

**Toujours utiliser** :
✅ Deployments classiques  
✅ Services ClusterIP  
✅ Ingress NGINX (déjà en DaemonSet hostNetwork)  
✅ Variables d'environnement pour les URLs de services  

---

## 🔄 Impact sur les Modules 10-16

### Avant Correction (Flannel/VXLAN)

- ❌ Module 10 : Platform KeyBuzz → 503
- ❌ Module 11 : Support KeyBuzz → Non déployable
- ❌ Module 12 : n8n → Non déployable
- ❌ Module 13 : ERPNext → Non déployable
- ❌ Module 14 : Superset → Non déployable
- ❌ Module 15 : LLM/Qdrant → Non déployable
- ❌ Module 16 : Connect/ETL → Non déployable

### Après Correction (Calico IPIP)

- ✅ Module 10 : Platform KeyBuzz → Fonctionnel
- ✅ Module 11 : Support KeyBuzz → Déployable
- ✅ Module 12 : n8n → Déployable
- ✅ Module 13 : ERPNext → Déployable
- ✅ Module 14 : Superset → Déployable
- ✅ Module 15 : LLM/Qdrant → Déployable
- ✅ Module 16 : Connect/ETL → Déployable

**Tous les modules fonctionnent avec l'architecture Kubernetes standard** :
- Deployments
- Services ClusterIP
- Ingress
- HPA
- Multi-replicas
- Auto-scaling

---

## 📚 Références

- **Calico Documentation** : https://docs.tigera.io/calico/latest/getting-started/kubernetes/requirements
- **Calico IPIP Mode** : https://docs.tigera.io/calico/latest/networking/configuring/vxlan-ipip
- **K3s Network Configuration** : https://docs.k3s.io/networking
- **Hetzner Cloud Network Limitations** : Port UDP 8472 bloqué (VXLAN)

---

## 🎯 Résumé Exécutif

**Problème** : Flannel/VXLAN bloqué sur Hetzner Cloud → Réseau overlay non fonctionnel

**Solution** : Remplacer Flannel par Calico en mode IPIP

**Résultat** :
- ✅ Réseau overlay pleinement fonctionnel
- ✅ Architecture Kubernetes standard
- ✅ Scalabilité assurée
- ✅ Compatibilité avec tous les modules KeyBuzz
- ✅ Pas de hacks (hostNetwork sur apps)

**Action Requise** : Exécuter le script de correction (`fix_k3s_network_calico.sh`)

---

**Document créé le** : 2025-11-24  
**Statut** : Solution validée par ChatGPT (Expert KeyBuzz)  
**Priorité** : CRITIQUE - À appliquer immédiatement

