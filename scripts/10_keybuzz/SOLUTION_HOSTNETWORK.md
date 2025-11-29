# 🎯 Solution Finale - KeyBuzz avec hostNetwork

## 📋 Problème Résolu

**Symptôme initial** : `504 Gateway Timeout` sur `platform.keybuzz.io` et `platform-api.keybuzz.io`

**Cause racine** : Infrastructure Hetzner Cloud bloque VXLAN (port 8472/UDP), rendant les Services ClusterIP inutilisables.

**Solution validée** : DaemonSets avec `hostNetwork: true` pour contourner VXLAN.

---

## ✅ Architecture Finale

### Principe

Au lieu d'utiliser le réseau overlay Flannel (qui nécessite VXLAN), on utilise **hostNetwork** :

1. **hostNetwork: true** → Les pods utilisent directement l'IP du nœud hôte
2. **DaemonSet** → Un pod par nœud automatiquement (5 workers = 5 pods)
3. **Communication locale** → Pas besoin de VXLAN
4. **NodePort** → Le Load Balancer route vers les workers qui répondent localement

### Configuration

```
KeyBuzz API:
  - DaemonSet avec hostNetwork: true
  - Port: 8080 (containerPort = hostPort)
  - Service NodePort: 30080
  - 5 pods (un par worker)

KeyBuzz Front:
  - DaemonSet avec hostNetwork: true
  - Port: 3000 (containerPort = hostPort)
  - Service NodePort: 30000
  - 5 pods (un par worker)
```

### Ports Utilisés

| Service | Container Port | Host Port | NodePort | Usage |
|---------|---------------|-----------|----------|-------|
| KeyBuzz API | 8080 | 8080 | 30080 | API KeyBuzz |
| KeyBuzz Front | 3000 | 3000 | 30000 | Frontend KeyBuzz |
| Ingress NGINX | 80/443 | 80/443 | 31695/32720 | Ingress Controller |

**IMPORTANT** : Avec `hostNetwork: true`, `containerPort` et `hostPort` doivent être **identiques**.

---

## 📦 Scripts d'Installation

### Script Principal

**`10_keybuzz_01_deploy_daemonsets.sh`** : Déploie KeyBuzz API et Front en DaemonSets hostNetwork

**Fonctionnalités** :
- Crée les DaemonSets avec hostNetwork
- Configure les Services NodePort
- Configure NGINX dans les pods pour écouter sur les bons ports
- Crée les Secrets Kubernetes pour les credentials

### Prérequis

1. Module 9 installé (K3s HA avec Ingress NGINX DaemonSet)
2. Credentials KeyBuzz générés (`10_keybuzz_00_setup_credentials.sh`)
3. Load Balancer Hetzner configuré :
   - Port HTTP : 31695
   - Port HTTPS : 31695 (SSL termination sur LB)
   - Targets : Tous les workers K3s (10.0.0.110-114)

---

## 🔧 Configuration Load Balancer Hetzner

### Ports à Configurer

- **HTTP** : Port 31695 (NodePort Ingress NGINX)
- **HTTPS** : Port 31695 (même port, SSL termination sur LB)

**IMPORTANT** : Le port HTTPS du LB doit être **31695**, pas un autre port !

### Healthchecks

- **Protocol** : HTTP
- **Port** : 31695
- **Path** : `/healthz`
- **Targets** : Tous les workers K3s (5 workers)

---

## 📝 Leçons Apprises

### ✅ Ce qui fonctionne

1. **DaemonSets hostNetwork** : Solution robuste pour contourner VXLAN
2. **NodePort** : Fonctionne correctement avec hostNetwork
3. **Ingress NGINX** : Peut router vers les Services NodePort
4. **Load Balancer Hetzner** : Route correctement vers les NodePorts

### ❌ Ce qui ne fonctionne PAS

1. **Services ClusterIP** : Ne fonctionnent pas (VXLAN bloqué)
2. **DNS CoreDNS** : Timeout (utilise ClusterIP)
3. **Communication inter-pods via Services** : Échoue

### ⚠️ Points d'Attention

1. **Ports hostNetwork** : `containerPort` et `hostPort` doivent être identiques
2. **Conflits de ports** : Vérifier qu'aucun autre service n'utilise les ports choisis
3. **Load Balancer** : Le port HTTPS doit être identique au port HTTP (31695)
4. **UFW** : Les ports NodePort doivent être ouverts sur tous les workers

---

## 🚀 Installation Propre

### Séquence d'Installation

1. **Module 9** : K3s HA avec Ingress NGINX DaemonSet
2. **Module 10** : KeyBuzz API & Front en DaemonSets hostNetwork
3. **Configuration LB** : Ports HTTP/HTTPS sur 31695
4. **DNS** : A records vers les IPs du Load Balancer

### Scripts à Exécuter

```bash
# 1. Générer les credentials
./10_keybuzz_00_setup_credentials.sh

# 2. Déployer en DaemonSets hostNetwork
./10_keybuzz_01_deploy_daemonsets.sh

# 3. Configurer l'Ingress
./10_keybuzz_02_configure_ingress.sh

# 4. Valider
./10_keybuzz_03_tests.sh
```

---

## ✅ Validation

### Tests à Effectuer

1. **Pods** : `kubectl get pods -n keybuzz` → 10 pods Running (5 API + 5 Front)
2. **Services** : `kubectl get svc -n keybuzz` → NodePort 30080 et 30000
3. **Endpoints** : `kubectl get endpoints -n keybuzz` → IPs des workers avec ports
4. **URLs** : 
   - `https://platform.keybuzz.io` → HTTP 200
   - `https://platform-api.keybuzz.io` → HTTP 200

### Résultat Attendu

```
✅ DaemonSets : 2 (keybuzz-api, keybuzz-front)
✅ Pods : 10 Running (5 de chaque)
✅ Services : 2 NodePort
✅ Endpoints : Correctement découverts
✅ URLs : HTTP 200
```

---

## 📚 Références

- **Solution validée** : DaemonSet + hostNetwork
- **Date** : 2025-11-20
- **Statut** : ✅ Production Ready

---

**Cette solution a été testée et validée en production. Tous les composants fonctionnent correctement avec hostNetwork.**

