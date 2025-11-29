# Diagnostic Complet Problème 504 - KeyBuzz

## Résumé du Problème

**Symptôme** : Erreurs 504 Gateway Time-out intermittentes sur :
- https://platform.keybuzz.io
- https://platform-api.keybuzz.io

## Diagnostic Effectué

### ✅ Ce qui fonctionne :
1. **Connectivité pod-to-pod directe** : Les pods peuvent communiquer entre eux via leurs IPs directes (10.42.x.x)
2. **Connectivité depuis les nœuds** : Les nœuds peuvent accéder aux pods directement
3. **UFW configuré** : Toutes les règles UFW sont en place sur les 8 nœuds K3s
4. **Règles iptables FORWARD** : Les règles sont présentes et correctement ordonnées
5. **Règles iptables NAT** : Les règles KUBE-SERVICES sont présentes pour les Services ClusterIP

### ❌ Ce qui ne fonctionne pas :
1. **Services ClusterIP (10.43.x.x)** : Les pods ne peuvent PAS accéder aux services via leur ClusterIP
2. **Ingress Controller -> Service** : L'Ingress Controller ne peut pas accéder au Service keybuzz-front
3. **DNS CoreDNS** : Les pods ne peuvent pas résoudre les noms DNS (timeout)

## Corrections Appliquées

### 1. UFW sur tous les nœuds K3s
- ✅ 10.42.0.0/16 (pods) autorisé
- ✅ 10.43.0.0/16 (services) autorisé
- ✅ Interfaces Flannel (flannel.1, cni0) autorisées
- ✅ Ports K3s (8472/udp, 10250/tcp) autorisés

### 2. iptables FORWARD
- ✅ Règles ACCEPT pour 10.42.0.0/16 et 10.43.0.0/16 ajoutées
- ✅ Règles pour interfaces Flannel ajoutées
- ✅ Règles placées AVANT KUBE-FORWARD

### 3. iptables NAT
- ✅ Règles KUBE-SERVICES présentes pour les Services ClusterIP

## Problème Identifié

Le problème semble être que **K3s n'utilise pas kube-proxy de la même manière que Kubernetes standard**. K3s intègre kube-proxy dans le processus k3s lui-même, et les Services ClusterIP ne fonctionnent pas correctement depuis les pods.

## Solutions Possibles

### Solution 1 : Utiliser les IPs des Pods Directement (CONTournement)
Modifier l'Ingress pour pointer directement vers les IPs des pods au lieu du Service.
**⚠️ Non recommandé** car les IPs changent lors des redéploiements.

### Solution 2 : Redémarrer K3s sur tous les nœuds
Forcer K3s à recréer toutes les règles réseau.

### Solution 3 : Vérifier la Configuration K3s
Vérifier `/etc/rancher/k3s/config.yaml` et les paramètres de réseau.

### Solution 4 : Utiliser un Service NodePort
Créer un Service de type NodePort au lieu de ClusterIP pour exposer l'application.

## Prochaines Étapes Recommandées

1. Vérifier les logs K3s sur tous les nœuds
2. Vérifier la configuration réseau K3s
3. Tester avec un Service NodePort
4. Si nécessaire, redémarrer K3s sur tous les nœuds

