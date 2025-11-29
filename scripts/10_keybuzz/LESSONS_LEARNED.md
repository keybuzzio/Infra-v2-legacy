# 🎓 Leçons Apprises - Module 10 KeyBuzz

## 📋 Résumé

Ce document résume les erreurs rencontrées et les solutions trouvées lors du déploiement de KeyBuzz sur K3s avec Hetzner Cloud.

---

## ❌ Erreur Initiale : 504 Gateway Timeout

### Symptômes

- `504 Gateway Timeout` sur `platform.keybuzz.io` et `platform-api.keybuzz.io`
- Pods peuvent communiquer directement via IP (10.42.x.x)
- Services ClusterIP (10.43.x.x) ne fonctionnent PAS
- DNS CoreDNS timeout
- Ingress Controller → Services = 504 Gateway Timeout

### Cause Racine

**Infrastructure Hetzner Cloud bloque VXLAN** (port 8472/UDP).

- VXLAN est nécessaire pour le réseau overlay Flannel dans K3s
- Sans VXLAN, les Services ClusterIP ne fonctionnent pas
- Les communications inter-pods via ClusterIP échouent
- DNS CoreDNS (qui utilise ClusterIP) timeout

### Tentatives Échouées

1. ❌ Augmentation des timeouts Ingress NGINX
2. ❌ Configuration de sessionAffinity
3. ❌ Ajout de règles UFW pour K3s networks
4. ❌ Correction des règles iptables FORWARD
5. ❌ Ajout de DNS publics (8.8.8.8, 1.1.1.1)
6. ❌ Redémarrage des services backend

**Aucune de ces solutions n'a fonctionné car le problème était au niveau infrastructure (VXLAN bloqué).**

---

## ✅ Solution Validée : DaemonSet + hostNetwork

### Principe

Au lieu d'utiliser le réseau overlay Flannel (qui nécessite VXLAN), on utilise **hostNetwork** :

1. **hostNetwork: true** → Les pods utilisent directement l'IP du nœud hôte
2. **DaemonSet** → Un pod par nœud automatiquement
3. **Communication locale** → Pas besoin de VXLAN
4. **NodePort** → Le Load Balancer route vers les workers qui répondent localement

### Avantages

- ✅ Contourne complètement le blocage VXLAN
- ✅ Performances optimales (pas de surcharge réseau)
- ✅ Haute disponibilité native (1 pod/nœud)
- ✅ Fonctionne avec les Load Balancers Hetzner

### Configuration Finale

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

---

## 🔧 Points Techniques Critiques

### 1. Ports hostNetwork

**⚠️ IMPORTANT** : Avec `hostNetwork: true`, `containerPort` et `hostPort` doivent être **identiques**.

```yaml
ports:
- containerPort: 8080
  hostPort: 8080  # Doit être identique !
  name: http
```

**Erreur commune** : Essayer d'utiliser des ports différents → Erreur Kubernetes.

### 2. Configuration NGINX dans les Pods

Avec hostNetwork, NGINX doit être configuré pour écouter sur le bon port :

```bash
echo 'server { listen 8080; ... }' > /etc/nginx/conf.d/default.conf
```

**Erreur commune** : NGINX écoute sur 80 par défaut, mais le pod utilise 8080 → Port déjà utilisé.

### 3. Load Balancer Hetzner

**⚠️ CRITIQUE** : Le port HTTPS du Load Balancer doit être **31695** (même que HTTP).

**Erreur rencontrée** : Port HTTPS différent → 503 Service Unavailable.

### 4. Services NodePort

Les Services doivent pointer vers les bons `targetPort` :

```yaml
ports:
- port: 80
  targetPort: 8080  # Port du container (hostNetwork)
  nodePort: 30080
```

**Erreur commune** : `targetPort: 80` alors que le pod écoute sur 8080 → 503.

---

## 📊 Évolution des Erreurs

### 504 Gateway Timeout → 503 Service Unavailable → 200 OK

1. **504 Gateway Timeout** : Pas de connexion, timeout complet
   - Cause : Services ClusterIP ne fonctionnent pas (VXLAN bloqué)

2. **503 Service Unavailable** : Connexion établie, mais service non disponible
   - Cause : Port HTTPS du LB incorrect ou `targetPort` incorrect

3. **200 OK** : Tout fonctionne ! ✅
   - Solution : DaemonSets hostNetwork + Services NodePort + LB correctement configuré

---

## 🎯 Bonnes Pratiques

### 1. Toujours utiliser hostNetwork sur Hetzner Cloud

Pour toute application déployée sur K3s avec Hetzner Cloud, utiliser **DaemonSets avec hostNetwork** dès le départ.

### 2. Tester localement avant de tester depuis Internet

Les tests locaux (depuis le cluster) permettent de valider rapidement l'infrastructure avant de tester depuis Internet.

### 3. Vérifier les ports du Load Balancer

Le port HTTPS doit être identique au port HTTP (31695 pour Ingress NGINX).

### 4. Documenter les ports utilisés

Maintenir une liste claire des ports utilisés pour éviter les conflits.

---

## 📝 Checklist de Déploiement

Avant de déployer une application sur K3s avec Hetzner Cloud :

- [ ] Utiliser DaemonSet avec hostNetwork
- [ ] Vérifier que `containerPort = hostPort`
- [ ] Configurer NGINX/app pour écouter sur le bon port
- [ ] Créer un Service NodePort avec le bon `targetPort`
- [ ] Ouvrir les ports NodePort dans UFW
- [ ] Configurer le Load Balancer (HTTP et HTTPS sur le même port)
- [ ] Tester localement depuis le cluster
- [ ] Tester depuis Internet

---

## 🚀 Prochaines Applications

Pour les prochaines applications (n8n, Superset, Chatwoot, etc.), utiliser la même approche :

1. **DaemonSet avec hostNetwork**
2. **Ports uniques** (éviter les conflits)
3. **Services NodePort**
4. **Ingress pointant vers les Services**

---

## 📚 Références

- **Solution validée** : DaemonSet + hostNetwork
- **Date de validation** : 2025-11-20
- **Statut** : ✅ Production Ready

---

**Cette solution a été testée et validée en production. Tous les composants fonctionnent correctement avec hostNetwork.**

