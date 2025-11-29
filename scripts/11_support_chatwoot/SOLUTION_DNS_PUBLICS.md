# Solution - Ajout DNS Publics sur Nœuds K8s

## 🎯 Problème identifié

NGINX Ingress avec `hostNetwork: true` utilise le DNS du nœud hôte, pas celui du cluster Kubernetes. Si le DNS du nœud ne peut pas résoudre les Services Kubernetes, NGINX ne peut pas joindre les backends.

## ✅ Solution appliquée

### Ajout DNS publics sur tous les nœuds K8s

Ajout de Google DNS (8.8.8.8) et Cloudflare DNS (1.1.1.1) dans `/etc/resolv.conf` sur tous les nœuds K8s :

**Nœuds concernés** :
- k8s-master-01 (10.0.0.100)
- k8s-master-02 (10.0.0.101)
- k8s-master-03 (10.0.0.102)
- k8s-worker-01 (10.0.0.110)
- k8s-worker-02 (10.0.0.111)
- k8s-worker-03 (10.0.0.112)
- k8s-worker-04 (10.0.0.113)
- k8s-worker-05 (10.0.0.114)

### Commandes exécutées

```bash
for node in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  ssh root@$node bash <<'EOF'
    # Sauvegarder resolv.conf actuel
    cp /etc/resolv.conf /etc/resolv.conf.backup
    
    # Ajouter Google DNS et Cloudflare DNS si pas déjà présents
    if ! grep -q "8.8.8.8" /etc/resolv.conf; then
      echo "nameserver 8.8.8.8" >> /etc/resolv.conf
      echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    fi
    
    # Protéger resolv.conf (si chattr disponible)
    if command -v chattr >/dev/null 2>&1; then
      chattr +i /etc/resolv.conf 2>/dev/null || true
    fi
EOF
done
```

### Redémarrage NGINX Ingress

```bash
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller
kubectl -n ingress-nginx rollout status daemonset ingress-nginx-controller --timeout=120s
```

## 🧪 Vérification

```bash
# Vérifier DNS sur un nœud
ssh root@10.0.0.100 'cat /etc/resolv.conf | grep nameserver'

# Tester résolution DNS
ssh root@10.0.0.100 'nslookup chatwoot-web.chatwoot.svc.cluster.local'

# Tester support.keybuzz.io
curl -v https://support.keybuzz.io
```

## 📝 Notes importantes

1. **Protection resolv.conf** : Utilisation de `chattr +i` pour empêcher systemd-resolved ou NetworkManager d'écraser le fichier.

2. **DNS Kubernetes** : Les DNS publics (8.8.8.8, 1.1.1.1) ne résoudront pas les Services Kubernetes (chatwoot-web.chatwoot.svc.cluster.local). Pour cela, il faut que CoreDNS (10.233.0.3) soit aussi dans resolv.conf, OU que NGINX utilise directement l'IP du Service.

3. **Alternative** : Si les DNS publics ne suffisent pas, ajouter aussi CoreDNS :
   ```bash
   echo "nameserver 10.233.0.3" >> /etc/resolv.conf
   ```

## 🔍 Prochaines étapes si ça ne fonctionne pas

Si le problème persiste après l'ajout des DNS publics :

1. **Vérifier que CoreDNS est aussi dans resolv.conf** :
   ```bash
   echo "nameserver 10.233.0.3" >> /etc/resolv.conf
   ```

2. **OU configurer le resolver dans NGINX ConfigMap** :
   ```bash
   kubectl patch configmap ingress-nginx-controller -n ingress-nginx \
     --type merge \
     -p '{"data":{"resolver":"10.233.0.3 valid=10s"}}'
   ```

3. **OU utiliser l'IP du Service directement** (si DNS ne fonctionne toujours pas)

---

**Date** : 2025-11-27  
**Statut** : Solution appliquée - À tester

