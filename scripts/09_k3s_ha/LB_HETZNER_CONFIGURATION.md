# Configuration Load Balancers Hetzner pour K3s

**Date** : 20 novembre 2025  
**Statut** : ✅ Configuration validée

---

## 🎯 Configuration Recommandée

### ⚠️ IMPORTANT : SSL Termination sur LB Hetzner

Les certificats HTTPS sont gérés par les **Load Balancers Hetzner**, pas par Ingress NGINX. Le trafic vers les nœuds K3s est en **HTTP** uniquement.

---

## 📋 Configuration des Services LB

### Service 1 : Kubernetes API (Port 6443)

**Configuration** :
- **Type** : TCP
- **Listen Port** : 6443
- **Destination Port** : 6443
- **Health Check** : TCP sur 6443
- **Targets** : **UNIQUEMENT les 3 masters**
  - k3s-master-01 (10.0.0.100:6443)
  - k3s-master-02 (10.0.0.101:6443)
  - k3s-master-03 (10.0.0.102:6443)

**⚠️ Ne PAS ajouter les workers** : Ils ne servent pas l'API Kubernetes.

---

### Service 2 : HTTP (Port 80)

**Configuration** :
- **Type** : HTTP
- **Listen Port** : 80
- **Destination Port** : **31695**
- **Health Check** :
  - **Protocol** : HTTP
  - **Port** : 31695
  - **Path** : `/healthz`
  - **Interval** : 10-15 secondes
  - **Timeout** : 5-10 secondes
  - **Retries** : 3
  - **Status codes** : 200, 2??, 3??
- **Targets** : **TOUS les 8 nœuds** (masters + workers)
  - k3s-master-01 (10.0.0.100:31695)
  - k3s-master-02 (10.0.0.101:31695)
  - k3s-master-03 (10.0.0.102:31695)
  - k3s-worker-01 (10.0.0.110:31695)
  - k3s-worker-02 (10.0.0.111:31695)
  - k3s-worker-03 (10.0.0.112:31695)
  - k3s-worker-04 (10.0.0.113:31695)
  - k3s-worker-05 (10.0.0.114:31695)

---

### Service 3 : HTTPS (Port 443)

**Configuration** :
- **Type** : HTTPS
- **Listen Port** : 443
- **Destination Port** : **31695** (⚠️ MÊME PORT que HTTP)
- **Certificats** : Gérés par les LB Hetzner (SSL termination)
- **Health Check** :
  - **Protocol** : **HTTP** (⚠️ PAS HTTPS - CRITIQUE)
  - **Port** : **31695** (⚠️ MÊME PORT que HTTP)
  - **Path** : `/healthz`
  - **Interval** : 10-15 secondes
  - **Timeout** : 5-10 secondes
  - **Retries** : 3
  - **Status codes** : `200` (ou `2??, 3??`)
- **Targets** : **TOUS les 8 nœuds** (masters + workers)
  - k3s-master-01 (10.0.0.100:31695)
  - k3s-master-02 (10.0.0.101:31695)
  - k3s-master-03 (10.0.0.102:31695)
  - k3s-worker-01 (10.0.0.110:31695)
  - k3s-worker-02 (10.0.0.111:31695)
  - k3s-worker-03 (10.0.0.112:31695)
  - k3s-worker-04 (10.0.0.113:31695)
  - k3s-worker-05 (10.0.0.114:31695)

**⚠️ CRITIQUE** : Le healthcheck HTTPS doit utiliser **HTTP** (pas HTTPS) car :
- Les certificats sont sur les LB, pas sur les nœuds
- Le trafic vers les nœuds est en HTTP après SSL termination
- Le healthcheck vérifie que le service répond en HTTP

---

## ⚠️ Points Critiques

### 1. SSL Termination sur LB Hetzner

- ✅ Les certificats HTTPS sont sur les **LB Hetzner**
- ✅ Le trafic vers les nœuds K3s est en **HTTP** (port 31695)
- ✅ Les LB font le SSL termination et envoient du HTTP vers les nœuds

### 2. Health Check HTTPS

- ✅ **Protocol** : HTTP (pas HTTPS)
- ✅ **Port** : 31695 (même que HTTP)
- ✅ **Path** : `/healthz`

**Pourquoi HTTP pour le healthcheck HTTPS ?**
- Les certificats sont sur les LB, pas sur les nœuds
- Le healthcheck doit vérifier que le service répond en HTTP
- Les LB gèrent le SSL, donc le healthcheck utilise HTTP

### 3. Même Port pour HTTP et HTTPS

- ✅ **HTTP (80)** → **31695**
- ✅ **HTTPS (443)** → **31695** (même port)

**Pourquoi le même port ?**
- Les LB font le SSL termination
- Le trafic vers les nœuds est toujours en HTTP
- Ingress NGINX écoute sur le port 80 (HTTP) via hostNetwork
- Le port 31695 mappe vers le port 80 du pod Ingress

---

## 🔧 Correction à Appliquer dans Hetzner Console

### Pour le Service HTTPS (443)

1. **Ouvrir** : Hetzner Console → Load Balancers → lb-keybuzz-1 → Services → HTTPS (443)
2. **Modifier** :
   - **Destination Port** : `31695` (au lieu de 31696)
3. **Health Check** :
   - **Protocol** : `HTTP` (⚠️ PAS HTTPS)
   - **Port** : `31695`
   - **Path** : `/healthz`
   - **Interval** : 10-15 secondes
   - **Timeout** : 5-10 secondes
   - **Retries** : 3
   - **Status codes** : `200` ou `2??, 3??`

### Vérification

Après modification, tous les targets devraient passer en **"Healthy"** (vert).

---

## 📊 Résumé Configuration

| Service | Listen Port | Destination Port | Health Check | Targets |
|---------|-------------|------------------|--------------|---------|
| Kubernetes API | 6443 | 6443 | TCP | 3 masters uniquement |
| HTTP | 80 | 31695 | HTTP /healthz | 8 nœuds (masters + workers) |
| HTTPS | 443 | 31695 | HTTP /healthz | 8 nœuds (masters + workers) |

---

## ✅ Validation

Après configuration, vérifier :

1. **Service HTTP (80)** : Tous les targets "Healthy" ✅
2. **Service HTTPS (443)** : Tous les targets "Healthy" ✅
3. **Service API (6443)** : 3 masters "Healthy" ✅

---

**Note** : Cette configuration est optimale car :
- Les certificats sont centralisés sur les LB
- Le trafic interne est en HTTP (plus performant)
- Le healthcheck fonctionne correctement
- La configuration est simple et maintenable

