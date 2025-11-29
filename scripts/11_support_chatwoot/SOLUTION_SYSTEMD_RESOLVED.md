# Solution - Configuration systemd-resolved pour NGINX Ingress

## 🎯 Problème identifié

`/etc/resolv.conf` est géré par systemd-resolved (symlink vers `/run/systemd/resolve/stub-resolv.conf`). Il faut configurer systemd-resolved plutôt que de modifier directement resolv.conf.

## ✅ Solution appliquée

### Configuration systemd-resolved sur tous les nœuds K8s

Création de `/etc/systemd/resolved.conf.d/dns_servers.conf` sur tous les nœuds :

```ini
[Resolve]
DNS=8.8.8.8 1.1.1.1 10.233.0.3
FallbackDNS=8.8.4.4 1.0.0.1
```

**DNS configurés** :
- `8.8.8.8` : Google DNS (primaire)
- `1.1.1.1` : Cloudflare DNS (primaire)
- `10.233.0.3` : CoreDNS Kubernetes (pour résoudre les Services)
- `8.8.4.4` : Google DNS (fallback)
- `1.0.0.1` : Cloudflare DNS (fallback)

### Commandes exécutées

```bash
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  ssh root@$ip 'mkdir -p /etc/systemd/resolved.conf.d && cat > /etc/systemd/resolved.conf.d/dns_servers.conf << EOF
[Resolve]
DNS=8.8.8.8 1.1.1.1 10.233.0.3
FallbackDNS=8.8.4.4 1.0.0.1
EOF
systemctl restart systemd-resolved'
done
```

### Redémarrage NGINX Ingress

```bash
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller
kubectl -n ingress-nginx rollout status daemonset ingress-nginx-controller --timeout=120s
```

## 🧪 Vérification

```bash
# Vérifier configuration systemd-resolved
ssh root@10.0.0.100 'resolvectl status'

# Tester résolution DNS
ssh root@10.0.0.100 'nslookup chatwoot-web.chatwoot.svc.cluster.local'

# Tester support.keybuzz.io
curl -v https://support.keybuzz.io
```

## 📝 Avantages de cette solution

1. ✅ Respecte systemd-resolved (pas de modification directe de resolv.conf)
2. ✅ Inclut CoreDNS (10.233.0.3) pour résoudre les Services Kubernetes
3. ✅ DNS publics en fallback pour Internet
4. ✅ Persistant (survit aux redémarrages)

---

**Date** : 2025-11-27  
**Statut** : Solution appliquée - À tester

