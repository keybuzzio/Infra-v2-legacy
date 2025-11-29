# Module 10 - KeyBuzz API & Front

## 📋 Objectifs

Déployer KeyBuzz API et Frontend sur le cluster K3s en utilisant **DaemonSets avec hostNetwork** pour contourner le problème VXLAN bloqué sur Hetzner Cloud.

## 🏗️ Architecture

### Solution hostNetwork

- **DaemonSets** : Un pod par worker (5 pods pour API, 5 pods pour Front)
- **hostNetwork: true** : Les pods utilisent directement l'IP du nœud
- **Ports** : 8080 (API), 3000 (Front)
- **Services NodePort** : 30080 (API), 30000 (Front)

### Pourquoi hostNetwork ?

L'infrastructure Hetzner Cloud bloque VXLAN (port 8472/UDP), rendant les Services ClusterIP inutilisables. La solution hostNetwork contourne ce problème en utilisant directement l'IP du nœud.

## 📦 Scripts

### Scripts Principaux

1. **`10_keybuzz_00_setup_credentials.sh`**
   - Génère les credentials KeyBuzz
   - Crée le fichier `keybuzz.env`
   - Crée les utilisateurs/bases de données nécessaires

2. **`10_keybuzz_01_deploy_daemonsets.sh`** ⭐ **NOUVEAU**
   - Déploie KeyBuzz API et Front en DaemonSets hostNetwork
   - Crée les Services NodePort
   - Configure NGINX dans les pods

3. **`10_keybuzz_02_configure_ingress.sh`**
   - Configure les Ingress pour `platform.keybuzz.io` et `platform-api.keybuzz.io`
   - Pointent vers les Services NodePort

4. **`10_keybuzz_03_tests.sh`**
   - Valide le déploiement
   - Teste la connectivité
   - Vérifie les pods, services, ingress

5. **`10_keybuzz_apply_all.sh`**
   - Script maître qui orchestre tous les scripts ci-dessus

### Scripts Obsolètes (conservés en référence)

- `10_keybuzz_01_deploy_api.sh.old` : Ancien script avec Deployment (ne fonctionne pas)
- `10_keybuzz_02_deploy_front.sh.old` : Ancien script avec Deployment (ne fonctionne pas)

## 🔧 Configuration Load Balancer Hetzner

### Ports à Configurer

- **HTTP** : Port 31695 (NodePort Ingress NGINX)
- **HTTPS** : Port 31695 (même port, SSL termination sur LB)

**⚠️ IMPORTANT** : Le port HTTPS du LB doit être **31695**, pas un autre port !

### Healthchecks

- **Protocol** : HTTP
- **Port** : 31695
- **Path** : `/healthz`
- **Targets** : Tous les workers K3s (5 workers)

## 📝 Prérequis

1. **Module 9** : K3s HA avec Ingress NGINX DaemonSet installé
2. **Modules 3-6** : Services backend (PostgreSQL, Redis, RabbitMQ, MinIO)
3. **DNS** : A records pour `platform.keybuzz.io` et `platform-api.keybuzz.io`
4. **Load Balancer Hetzner** : Configuré avec ports HTTP/HTTPS sur 31695

## 🚀 Installation

### Installation Complète

```bash
cd /root/Infra/scripts/10_keybuzz
./10_keybuzz_apply_all.sh /opt/keybuzz-installer/servers.tsv --yes
```

### Installation Étape par Étape

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

## ✅ Validation

### Résultat Attendu

```
✅ DaemonSets : 2 (keybuzz-api, keybuzz-front)
✅ Pods : 10 Running (5 de chaque)
✅ Services : 2 NodePort (30080, 30000)
✅ Endpoints : Correctement découverts
✅ URLs : HTTP 200
```

### Tests

```bash
# Vérifier les pods
kubectl get pods -n keybuzz

# Vérifier les services
kubectl get svc -n keybuzz

# Vérifier les ingress
kubectl get ingress -n keybuzz

# Tester les URLs
curl https://platform.keybuzz.io
curl https://platform-api.keybuzz.io
```

## 📚 Documentation

- **`SOLUTION_HOSTNETWORK.md`** : Documentation complète de la solution hostNetwork
- **`DNS_CONFIGURATION.md`** : Configuration DNS requise
- **`IMAGES_DOCKER.md`** : Informations sur les images Docker

## 🎓 Leçons Apprises

### ✅ Ce qui fonctionne

- DaemonSets hostNetwork
- Services NodePort
- Ingress NGINX avec hostNetwork
- Load Balancer Hetzner avec NodePorts

### ❌ Ce qui ne fonctionne PAS

- Services ClusterIP (VXLAN bloqué)
- DNS CoreDNS (utilise ClusterIP)
- Communication inter-pods via Services

### ⚠️ Points d'Attention

- `containerPort` et `hostPort` doivent être identiques avec hostNetwork
- Vérifier les conflits de ports
- Load Balancer : port HTTPS = port HTTP (31695)
- UFW : ports NodePort doivent être ouverts

---

**Date de création** : 2025-11-20  
**Statut** : ✅ Production Ready
