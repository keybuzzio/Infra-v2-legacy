# Script Fix DNS - Exécuté

## 📋 Script créé

**Fichier** : `/opt/keybuzz-installer-v2/scripts/11_support_chatwoot/fix_systemd_resolved_dns.sh`

## ✅ Actions effectuées

1. **Configuration systemd-resolved** sur tous les nœuds K8s :
   - Création de `/etc/systemd/resolved.conf.d/dns_servers.conf`
   - DNS : 8.8.8.8, 1.1.1.1, 10.233.0.3 (CoreDNS)
   - FallbackDNS : 8.8.4.4, 1.0.0.1
   - Redémarrage de systemd-resolved

2. **Redémarrage NGINX Ingress** :
   - `kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller`
   - Attente de stabilisation (90s)

## 🧪 Test final

```bash
# Tester support.keybuzz.io
curl -v https://support.keybuzz.io
```

**Attendu** : HTTP 200/302 (page Chatwoot)

## 📝 Nœuds configurés

- k8s-master-01 (10.0.0.100)
- k8s-master-02 (10.0.0.101)
- k8s-master-03 (10.0.0.102)
- k8s-worker-01 (10.0.0.110)
- k8s-worker-02 (10.0.0.111)
- k8s-worker-03 (10.0.0.112)
- k8s-worker-04 (10.0.0.113)
- k8s-worker-05 (10.0.0.114)

## 🔄 Réexécution du script

Si nécessaire, le script peut être réexécuté :

```bash
/opt/keybuzz-installer-v2/scripts/11_support_chatwoot/fix_systemd_resolved_dns.sh
```

---

**Date** : 2025-11-27  
**Statut** : Script créé et exécuté

