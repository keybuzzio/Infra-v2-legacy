# Instructions Manuelles - Configuration DNS systemd-resolved

## 🎯 Problème

Les connexions SSH directes depuis Windows vers les IPs privées (10.0.0.x) ne fonctionnent pas. Il faut exécuter les commandes depuis install-01.

## ✅ Solution - Script à exécuter sur install-01

**Script créé** : `/tmp/fix_dns_all.sh`

### Exécution manuelle

Connectez-vous à install-01 et exécutez :

```bash
export KUBECONFIG=/root/.kube/config

# Configuration systemd-resolved sur tous les nœuds
for ip in 10.0.0.100 10.0.0.101 10.0.0.102 10.0.0.110 10.0.0.111 10.0.0.112 10.0.0.113 10.0.0.114; do
  echo "Configuration $ip..."
  ssh root@$ip bash <<'EOF'
    mkdir -p /etc/systemd/resolved.conf.d
    echo '[Resolve]' > /etc/systemd/resolved.conf.d/dns_servers.conf
    echo 'DNS=8.8.8.8 1.1.1.1 10.233.0.3' >> /etc/systemd/resolved.conf.d/dns_servers.conf
    echo 'FallbackDNS=8.8.4.4 1.0.0.1' >> /etc/systemd/resolved.conf.d/dns_servers.conf
    systemctl restart systemd-resolved
    echo "OK"
EOF
done

# Vérification
ssh root@10.0.0.100 'cat /etc/systemd/resolved.conf.d/dns_servers.conf'

# Redémarrage NGINX Ingress
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller
kubectl -n ingress-nginx rollout status daemonset ingress-nginx-controller --timeout=120s

# Test final
curl -v https://support.keybuzz.io
```

## 📝 Fichier créé sur chaque nœud

`/etc/systemd/resolved.conf.d/dns_servers.conf` :
```ini
[Resolve]
DNS=8.8.8.8 1.1.1.1 10.233.0.3
FallbackDNS=8.8.4.4 1.0.0.1
```

## 🧪 Vérification

```bash
# Vérifier configuration
ssh root@10.0.0.100 'cat /etc/systemd/resolved.conf.d/dns_servers.conf'

# Vérifier status systemd-resolved
ssh root@10.0.0.100 'resolvectl status'

# Tester support.keybuzz.io
curl -v https://support.keybuzz.io
```

---

**Date** : 2025-11-27  
**Statut** : Script créé sur install-01 - À exécuter manuellement

