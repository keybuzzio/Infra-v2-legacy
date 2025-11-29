# Installation Module 9 V2 - Serveurs Vierges

## 🎯 Objectif
Installer Kubernetes HA V2 sur des serveurs K8s vierges (Module 2 déjà installé, volumes montés).

## ✅ Prérequis vérifiés

### 1. Serveurs K8s
- ✅ 3 Masters : k8s-master-01, k8s-master-02, k8s-master-03
- ✅ 5 Workers : k8s-worker-01 à k8s-worker-05
- ✅ Accès SSH fonctionnel

### 2. Module 2 installé
- ✅ Docker installé et actif
- ✅ Configuration base OS appliquée

### 3. Volumes
- ✅ Volumes montés et configurés

## 📋 Étapes d'installation

### Étape 1 : Préparation inventaire Kubespray V2
- ✅ Inventaire `keybuzz-v2` créé
- ✅ CIDR configurés :
  - Pod CIDR : `10.233.0.0/16`
  - Service CIDR : `10.96.0.0/12`
- ✅ Configuration Calico : IPIP Always

### Étape 2 : Installation Kubernetes HA V2
- ⏳ Installation en cours via `ansible-playbook cluster.yml`
- ⏳ Durée estimée : 30-60 minutes

### Étape 3 : Post-installation
- ⏳ Copie kubeconfig
- ⏳ Vérification nodes Ready
- ⏳ Installation ingress-nginx
- ⏳ Validation réseau

### Étape 4 : Réinstallation Modules 10 & 11
- ⏳ Module 10 (Plateforme KeyBuzz)
- ⏳ Module 11 (Chatwoot / Support KeyBuzz)

---

**Date** : 2025-11-28  
**Statut** : ⏳ Installation Kubernetes en cours

