# Problème Réseau Module 10 - API

## 🔴 Problème identifié

### Symptômes
- ✅ **platform.keybuzz.io** : Fonctionne
- ❌ **platform-api.keybuzz.io** : 503/504 (timeout)

### Tests de connectivité

#### Node → Pod UI (fonctionne)
```bash
curl http://10.233.36.196:80  # ✅ OK
```

#### Node → Pod API (timeout)
```bash
curl http://10.233.118.73:8080/health  # ❌ Timeout
```

#### Node → Service ClusterIP API (timeout)
```bash
curl http://10.110.76.162:8080/health  # ❌ Timeout
```

### Hypothèses
1. **Problème de routage Calico** : Les nodes ne peuvent pas atteindre les pods API sur le port 8080
2. **Problème de port** : Le port 8080 pourrait être bloqué ou mal configuré
3. **Problème de firewall** : UFW ou iptables pourrait bloquer le port 8080

### Différence avec UI
- UI fonctionne sur port 80
- API ne fonctionne pas sur port 8080
- Même réseau Calico (10.233.x.x)

### Actions à faire
1. Vérifier que les pods API écoutent bien sur 8080
2. Vérifier les routes Calico depuis les nodes
3. Vérifier les règles iptables/UFW pour le port 8080
4. Comparer la configuration réseau entre UI et API

---

**Date** : 2025-11-28  
**Statut** : ⚠️ Diagnostic en cours

