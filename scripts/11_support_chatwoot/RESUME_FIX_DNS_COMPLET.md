# Résumé Complet - Fix DNS systemd-resolved

## ✅ Solution appliquée

### Configuration systemd-resolved sur tous les nœuds K8s

**Fichier créé** : `/etc/systemd/resolved.conf.d/dns_servers.conf`

**Contenu** :
```ini
[Resolve]
DNS=8.8.8.8 1.1.1.1 10.233.0.3
FallbackDNS=8.8.4.4 1.0.0.1
```

**Nœuds configurés** :
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
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  ssh root@$ip 'mkdir -p /etc/systemd/resolved.conf.d && \
    echo "[Resolve]" > /etc/systemd/resolved.conf.d/dns_servers.conf && \
    echo "DNS=8.8.8.8 1.1.1.1 10.233.0.3" >> /etc/systemd/resolved.conf.d/dns_servers.conf && \
    echo "FallbackDNS=8.8.4.4 1.0.0.1" >> /etc/systemd/resolved.conf.d/dns_servers.conf && \
    systemctl restart systemd-resolved'
done

# Redémarrage NGINX Ingress
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller
```

## 📊 État final

- ✅ **systemd-resolved configuré** sur tous les nœuds
- ✅ **NGINX Ingress redémarré** (8 pods Running)
- ✅ **Pods Chatwoot** : 2/2 Running

## 🧪 Test final

```bash
# Vérifier configuration
ssh root@10.0.0.100 'cat /etc/systemd/resolved.conf.d/dns_servers.conf'
ssh root@10.0.0.100 'resolvectl status'

# Tester support.keybuzz.io
curl -v https://support.keybuzz.io
```

**Attendu** : HTTP 200/302 (page Chatwoot)

## 📝 Notes

1. **DNS configurés** :
   - `8.8.8.8` : Google DNS (primaire)
   - `1.1.1.1` : Cloudflare DNS (primaire)
   - `10.233.0.3` : CoreDNS Kubernetes (pour Services K8s)
   - `8.8.4.4` : Google DNS (fallback)
   - `1.0.0.1` : Cloudflare DNS (fallback)

2. **Persistance** : La configuration survit aux redémarrages car elle est dans `/etc/systemd/resolved.conf.d/`

3. **NGINX Ingress** : Avec `hostNetwork: true`, NGINX utilise le DNS du nœud hôte, donc cette configuration devrait résoudre le problème.

---

**Date** : 2025-11-27  
**Statut** : ✅ Configuration appliquée - À tester

