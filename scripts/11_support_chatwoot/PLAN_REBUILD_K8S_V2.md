# Plan Rebuild Kubernetes V2 - KeyBuzz

## 🎯 Objectif

Reconstruire le cluster Kubernetes avec des CIDR compatibles pour résoudre les problèmes de routage réseau.

## 🔍 Problème identifié

**CIDR incompatibles** :
- Service CIDR : `10.233.0.0/18`
- Pod CIDR Calico : `10.233.64.0/18`
- **Résultat** : Routage réseau cassé (Pod→Service, Node→Service, DNS, Ingress)

## ✅ Solution

**CIDR corrigés** :
- Pod CIDR Calico : `10.233.0.0/16` (englobe tous les pods)
- Service CIDR : `10.96.0.0/12` (séparé des pods, standard Kubernetes)

## 📋 Étapes

### 0. Sauvegarde documentation
- ✅ Créer backup_before_k8s_rebuild_YYYYMMDD_HHMMSS
- ✅ Archiver docs et rapports Modules 9, 10, 11

### 1. Préparer inventaire Kubespray V2
- ✅ Créer inventory/keybuzz-v2
- ✅ Créer hosts.yaml avec 3 masters + 5 workers
- ✅ Configurer k8s-cluster.yml avec CIDR corrects
- ✅ Configurer calico.yml avec IPIP Always

### 2. Reset cluster K8s existant
- ⏳ Exécuter `ansible-playbook reset.yml`
- ⚠️ Ne touche PAS aux serveurs stateful (db, redis, rabbit, minio, etc.)

### 3. Réinstaller Kubernetes HA
- ⏳ Exécuter `ansible-playbook cluster.yml`
- ⏳ Copier kubeconfig
- ⏳ Vérifier nodes Ready

### 4. Installer ingress-nginx
- ⏳ DaemonSet + hostNetwork
- ⏳ Ports 80/443 exposés

### 5. Valider réseau K8s
- ⏳ Pod → Pod
- ⏳ Pod → Service
- ⏳ DNS CoreDNS
- ⏳ Node → Service

### 6. Réinstaller Module 10
- ⏳ Plateforme KeyBuzz
- ⏳ platform.keybuzz.io, platform-api.keybuzz.io, my.keybuzz.io

### 7. Réinstaller Module 11
- ⏳ Chatwoot / Support KeyBuzz
- ⏳ support.keybuzz.io

### 8. Mettre à jour documentation
- ⏳ Modules 9, 10, 11
- ⏳ Rapports de validation

---

**Date** : 2025-11-27  
**Statut** : En cours - Étape 0 et 1 terminées

