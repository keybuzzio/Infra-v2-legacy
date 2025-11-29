# Résumé Final - Fix DNS systemd-resolved

## ✅ Script créé et exécuté

**Fichier** : `/opt/keybuzz-installer-v2/scripts/11_support_chatwoot/fix_dns_systemd_resolved.sh`

### Actions effectuées

1. **Configuration systemd-resolved** sur tous les nœuds K8s (depuis install-01) :
   - Création de `/etc/systemd/resolved.conf.d/dns_servers.conf`
   - DNS : 8.8.8.8, 1.1.1.1, 10.233.0.3 (CoreDNS)
   - FallbackDNS : 8.8.4.4, 1.0.0.1
   - Redémarrage de systemd-resolved

2. **Redémarrage NGINX Ingress** :
   - `kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller`
   - Attente de stabilisation (90s)

### Nœuds configurés

- k8s-master-01 (10.0.0.100)
- k8s-master-02 (10.0.0.101)
- k8s-master-03 (10.0.0.102)
- k8s-worker-01 (10.0.0.110)
- k8s-worker-02 (10.0.0.111)
- k8s-worker-03 (10.0.0.112)
- k8s-worker-04 (10.0.0.113)
- k8s-worker-05 (10.0.0.114)

## 📝 Fichier créé sur chaque nœud

`/etc/systemd/resolved.conf.d/dns_servers.conf` :
```ini
[Resolve]
DNS=8.8.8.8 1.1.1.1 10.233.0.3
FallbackDNS=8.8.4.4 1.0.0.1
```

## 🧪 Test final

```bash
# Vérifier configuration
ssh root@10.0.0.100 'cat /etc/systemd/resolved.conf.d/dns_servers.conf'

# Vérifier status systemd-resolved
ssh root@10.0.0.100 'resolvectl status'

# Tester support.keybuzz.io
curl -v https://support.keybuzz.io
```

**Attendu** : HTTP 200/302 (page Chatwoot)

## 🔄 Réexécution du script

Si nécessaire, le script peut être réexécuté depuis install-01 :

```bash
/opt/keybuzz-installer-v2/scripts/11_support_chatwoot/fix_dns_systemd_resolved.sh
```

---

**Date** : 2025-11-27  
**Statut** : ✅ Script créé et exécuté depuis install-01
