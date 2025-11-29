# Problème DNS NGINX Ingress Identifié

## 🔍 Problème identifié

**NGINX Ingress ne peut pas résoudre les Services Kubernetes** :
```
wget: bad address 'chatwoot-web.chatwoot.svc.cluster.local:3000'
```

## 📊 État actuel

- ✅ **Endpoints Chatwoot** : 2 endpoints (10.233.111.25:3000, 10.233.119.219:3000)
- ✅ **Service ClusterIP** : 10.233.21.46:3000
- ✅ **NGINX Ingress** : 8 pods Running
- ❌ **Résolution DNS** : NGINX ne peut pas résoudre `chatwoot-web.chatwoot.svc.cluster.local`

## 🔧 Cause probable

NGINX Ingress utilise `hostNetwork: true` et `dnsPolicy: ClusterFirstWithHostNet`, ce qui signifie qu'il devrait utiliser CoreDNS. Cependant, la résolution DNS ne fonctionne pas.

## 🧪 Tests à effectuer

1. **Test avec IP Service directement** :
   ```bash
   kubectl exec -n ingress-nginx ingress-nginx-controller-drmb7 -- wget -O- -T 5 http://10.233.21.46:3000
   ```

2. **Test avec IP Pod directement** :
   ```bash
   kubectl exec -n ingress-nginx ingress-nginx-controller-drmb7 -- wget -O- -T 5 http://10.233.111.25:3000
   ```

3. **Vérifier CoreDNS** :
   ```bash
   kubectl get pods -n kube-system -l k8s-app=kube-dns
   ```

4. **Vérifier /etc/resolv.conf dans NGINX pod** :
   ```bash
   kubectl exec -n ingress-nginx ingress-nginx-controller-drmb7 -- cat /etc/resolv.conf
   ```

5. **Test nslookup depuis NGINX pod** :
   ```bash
   kubectl exec -n ingress-nginx ingress-nginx-controller-drmb7 -- nslookup chatwoot-web.chatwoot.svc.cluster.local
   ```

## 💡 Solutions possibles

1. **Si l'IP Service fonctionne** : Le problème est uniquement DNS. NGINX devrait quand même pouvoir joindre le Service via kube-proxy, même sans DNS.

2. **Si l'IP Service ne fonctionne pas** : Le problème est plus profond (routage Calico, kube-proxy, etc.).

3. **Configuration CoreDNS** : Vérifier que CoreDNS est accessible depuis les nœuds (10.0.0.x) et que NGINX peut le joindre.

---

**Date** : 2025-11-27  
**Statut** : Problème DNS identifié - Tests en cours

