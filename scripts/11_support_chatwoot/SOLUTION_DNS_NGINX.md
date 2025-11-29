# Solution Problème DNS NGINX Ingress

## 🎯 Problème identifié

NGINX Ingress avec `hostNetwork: true` peut avoir des problèmes de résolution DNS pour les Services Kubernetes.

## ✅ Solution : Configurer le resolver DNS dans NGINX

NGINX Ingress doit être configuré pour utiliser CoreDNS (10.233.0.10) comme resolver.

### Configuration à ajouter

Ajouter dans le ConfigMap `ingress-nginx-controller` :

```yaml
data:
  use-forwarded-headers: "true"
  compute-full-forwarded-for: "true"
  use-proxy-protocol: "false"
  # Resolver DNS pour hostNetwork
  resolver: "10.233.0.10 valid=10s"
```

### Commandes à exécuter

```bash
export KUBECONFIG=/root/.kube/config

# Obtenir la configuration actuelle
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o yaml > /tmp/nginx-config.yaml

# Ajouter le resolver
kubectl patch configmap ingress-nginx-controller -n ingress-nginx --type merge -p '{"data":{"resolver":"10.233.0.10 valid=10s"}}'

# Redémarrer les pods NGINX
kubectl -n ingress-nginx rollout restart daemonset ingress-nginx-controller

# Attendre la stabilisation
kubectl -n ingress-nginx rollout status daemonset ingress-nginx-controller --timeout=120s
```

### Vérification

```bash
# Vérifier la configuration
kubectl get configmap ingress-nginx-controller -n ingress-nginx -o yaml | grep resolver

# Tester
curl -v https://support.keybuzz.io
```

---

**Date** : 2025-11-27  
**Statut** : Solution à tester

