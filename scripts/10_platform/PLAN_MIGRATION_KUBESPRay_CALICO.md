# Plan de Migration : K3s → Kubespray + Calico IPIP

**Date** : 2025-11-24  
**Statut** : ✅ Plan définitif approuvé  
**Objectif** : Migrer vers Kubernetes complet pour résoudre définitivement les problèmes réseau

---

## 🎯 Objectif Final

**Remplacer K3s par Kubernetes complet (Kubespray) avec Calico IPIP**

**Résultat attendu** :
- ✅ Réseau overlay stable et fonctionnel
- ✅ DNS opérationnel
- ✅ Services ClusterIP fonctionnels
- ✅ Pod-to-Pod communication
- ✅ Ingress → Backend fonctionnel
- ✅ Compatibilité 100% avec tous les modules KeyBuzz (10-16)

---

## 📋 Plan d'Action en 4 Phases

### 🟦 Phase 1 : Restauration Temporaire du Cluster K3s

**Objectif** : Restaurer l'accès au cluster pour exporter les configurations

**Actions** :
1. Réactiver Flannel dans `/etc/rancher/k3s/config.yaml`
2. Redémarrer K3s sur tous les masters
3. Nettoyer les interfaces Cilium résiduelles
4. Vérifier l'accès au cluster

**Résultat** :
- ✅ Cluster accessible via `kubectl`
- ⚠️ Réseau overlay cassé (normal, temporaire)
- ✅ Possibilité d'exporter manifests, ConfigMaps, Secrets

**Durée estimée** : 15-30 minutes

---

### 🟪 Phase 2 : Installation de Kubespray

**Objectif** : Préparer l'environnement Kubespray sur `install-01`

**Actions** :
1. Installer Kubespray (v2.23 ou master)
2. Installer les dépendances Python
3. Créer l'inventaire `inventory/keybuzz`
4. Configurer `hosts.yaml` avec :
   - 3 masters (10.0.0.100, 10.0.0.101, 10.0.0.102)
   - 5 workers (10.0.0.110, 10.0.0.111, 10.0.0.112, 10.0.0.113, 10.0.0.114)
   - Configuration Calico IPIP
   - kube-proxy en mode iptables

**Résultat** :
- ✅ Kubespray installé et configuré
- ✅ Inventaire prêt
- ✅ Configuration Calico IPIP validée

**Durée estimée** : 30-45 minutes

---

### 🟧 Phase 3 : Déploiement Kubernetes Complet + Calico IPIP

**Objectif** : Installer Kubernetes HA avec Calico IPIP

**Actions** :
1. Exécuter `ansible-playbook cluster.yml`
2. Attendre le déploiement complet
3. Vérifier :
   - Nodes Ready
   - CoreDNS Running
   - Calico pods Ready
   - Services ClusterIP accessibles
   - DNS fonctionnel
   - Pod-to-Pod communication

**Résultat** :
- ✅ Kubernetes complet opérationnel
- ✅ Calico IPIP fonctionnel
- ✅ Réseau overlay stable
- ✅ Tous les composants système OK

**Durée estimée** : 60-90 minutes

---

### 🟩 Phase 4 : Réinstallation des Modules 10 à 16

**Objectif** : Redéployer toutes les applications KeyBuzz

**Actions** :
1. Recréer les namespaces
2. Recréer les ConfigMaps et Secrets
3. Redéployer les Deployments
4. Recréer les Services ClusterIP
5. Recréer les Ingress
6. Valider chaque module

**Modules à redéployer** :
- Module 10 : Platform (platform.keybuzz.io, platform-api.keybuzz.io, my.keybuzz.io)
- Module 11 : Support (support.keybuzz.io)
- Module 12 : n8n (n8n.keybuzz.io)
- Module 13 : ERPNext (erp.keybuzz.io)
- Module 14 : Analytics (superset.keybuzz.io, analytics.keybuzz.io)
- Module 15 : IA/LLM (llm.keybuzz.io, qdrant.keybuzz.io)
- Module 16 : Connect & ETL (connect.keybuzz.io, etl.keybuzz.io)

**Résultat** :
- ✅ Toutes les applications KeyBuzz opérationnelles
- ✅ Réseau fonctionnel pour tous les modules
- ✅ Scaling et monitoring opérationnels

**Durée estimée** : 2-4 heures

---

## 🔧 Configuration Technique

### Calico IPIP

```yaml
calico_ipip_mode: Always
calico_vxlan_mode: Never
calico_nat_outgoing: Enabled
```

### kube-proxy

```yaml
kube_proxy_mode: iptables
```

### Network Plugin

```yaml
network_plugin: calico
kube_network_plugin: calico
```

---

## 📊 Comparaison Avant/Après

| Aspect | K3s (Avant) | Kubespray + Calico (Après) |
|--------|-------------|----------------------------|
| **CNI** | Flannel (VXLAN) | Calico IPIP |
| **VXLAN** | ❌ Bloqué sur Hetzner | ✅ Non utilisé |
| **DNS** | ❌ Cassé | ✅ Fonctionnel |
| **Services ClusterIP** | ❌ Inaccessibles | ✅ Fonctionnels |
| **Pod-to-Pod** | ❌ Cassé | ✅ Fonctionnel |
| **Ingress → Backend** | ❌ Timeout | ✅ Fonctionnel |
| **Stabilité** | ❌ Instable | ✅ Stable |
| **Compatibilité** | ⚠️ Partielle | ✅ 100% Kubernetes |

---

## ⚠️ Points d'Attention

### Pendant la Migration

1. **Downtime prévu** : 2-4 heures pendant Phase 3 et Phase 4
2. **Sauvegarde** : Exporter tous les manifests avant Phase 3
3. **Volumes** : Les volumes persistants seront conservés (même stockage)
4. **IPs** : Les IPs des nœuds restent identiques

### Après la Migration

1. **Ingress NGINX** : Doit être réinstallé (DaemonSet hostNetwork)
2. **Monitoring** : Prometheus/Grafana à réinstaller
3. **Certificats** : Cert-manager à reconfigurer
4. **Secrets** : Tous les secrets à recréer

---

## ✅ Checklist de Migration

### Phase 1 : Restauration K3s
- [ ] Réactiver Flannel
- [ ] Redémarrer K3s
- [ ] Nettoyer interfaces Cilium
- [ ] Vérifier accès cluster
- [ ] Exporter manifests
- [ ] Exporter ConfigMaps/Secrets

### Phase 2 : Installation Kubespray
- [ ] Installer Kubespray
- [ ] Installer dépendances Python
- [ ] Créer inventaire
- [ ] Configurer hosts.yaml
- [ ] Valider configuration

### Phase 3 : Déploiement Kubernetes
- [ ] Exécuter ansible-playbook
- [ ] Vérifier nodes Ready
- [ ] Vérifier CoreDNS
- [ ] Vérifier Calico
- [ ] Tester DNS
- [ ] Tester Services ClusterIP
- [ ] Tester Pod-to-Pod

### Phase 4 : Réinstallation Applications
- [ ] Recréer namespaces
- [ ] Recréer ConfigMaps/Secrets
- [ ] Redéployer Module 10
- [ ] Redéployer Module 11
- [ ] Redéployer Module 12
- [ ] Redéployer Module 13
- [ ] Redéployer Module 14
- [ ] Redéployer Module 15
- [ ] Redéployer Module 16
- [ ] Valider toutes les URLs

---

## 📝 Notes Importantes

1. **K3s ne sera plus utilisé** après Phase 3
2. **Tous les pods seront recréés** (nouveau cluster)
3. **Les volumes persistants seront conservés** (même stockage)
4. **Les IPs des nœuds restent identiques**
5. **Le LB Hetzner reste inchangé**

---

**Document créé le** : 2025-11-24  
**Auteur** : Plan basé sur analyse définitive  
**Statut** : ✅ Prêt à exécuter  
**Action Requise** : Commencer Phase 1 (Restauration K3s)

