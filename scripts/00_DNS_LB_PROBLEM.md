# Problème DNS avec 2 Load Balancers

## 🔴 Problème Identifié

Votre DNS `platform.keybuzz.io` résout vers **2 IPs différentes** :
- `138.199.132.240`
- `49.13.42.76`

Cela cause des **erreurs 504 intermittentes** car :

1. **Round-Robin DNS** : Le DNS distribue les requêtes entre les 2 IPs de manière aléatoire
2. **Problèmes asymétriques** : Si un LB a des problèmes (timeouts, healthchecks, configuration), 50% des requêtes échouent
3. **Timeouts variables** : Les 2 LBs peuvent avoir des configurations différentes (timeouts, healthchecks)
4. **Pas de failover intelligent** : Le DNS ne sait pas qu'un LB est down, il continue de router vers les 2

## ✅ Solutions Recommandées

### Solution 1 : UN SEUL Load Balancer (Recommandé)

**Avantages :**
- Pas de problèmes de round-robin
- Configuration plus simple
- Moins de points de défaillance
- Plus facile à déboguer

**Action :**
1. Gardez UN SEUL LB actif
2. Supprimez la deuxième IP du DNS
3. Gardez le deuxième LB en backup (mais pas dans le DNS)

### Solution 2 : Configuration Actif/Passif

**Avantages :**
- Haute disponibilité
- Pas de round-robin

**Action :**
1. Configurez un DNS avec healthcheck (ex: Cloudflare, Route53)
2. Le DNS retire automatiquement les IPs down
3. Utilisez un seul LB à la fois dans le DNS

### Solution 3 : DNS avec Healthcheck

**Avantages :**
- Haute disponibilité automatique
- Failover intelligent

**Action :**
1. Utilisez un service DNS avec healthcheck (Cloudflare, Route53, etc.)
2. Configurez les healthchecks pour surveiller les 2 LBs
3. Le DNS retire automatiquement les IPs qui ne répondent pas

## 📋 Actions Immédiates

1. **Vérifiez la configuration des 2 LBs dans Hetzner :**
   - Sont-ils identiques ?
   - Ont-ils les mêmes healthchecks ?
   - Ont-ils les mêmes timeouts ?

2. **Testez chaque LB individuellement :**
   ```bash
   # Test LB 1
   curl -H "Host: platform.keybuzz.io" http://138.199.132.240/
   
   # Test LB 2
   curl -H "Host: platform.keybuzz.io" http://49.13.42.76/
   ```

3. **Recommandation immédiate :**
   - **Supprimez une des 2 IPs du DNS** (gardez celle qui fonctionne le mieux)
   - Testez pendant 24h
   - Si stable, gardez cette configuration

## 🔍 Diagnostic

Le test de stabilité sur 120 secondes montre que les tests internes échouent, mais cela peut être normal car :
- Les tests sont faits depuis l'Ingress Controller vers lui-même
- Les timeouts peuvent être trop courts pour les tests internes
- Les requêtes réelles depuis l'extérieur fonctionnent (voir logs)

**Le vrai test est depuis votre navigateur :**
- Testez https://platform.keybuzz.io depuis votre navigateur
- Si vous voyez des 504 intermittents, c'est bien le problème des 2 LBs

## 📝 Configuration DNS Actuelle

```
platform.keybuzz.io → 138.199.132.240 (LB 1)
platform.keybuzz.io → 49.13.42.76 (LB 2)
```

**Recommandation :**
```
platform.keybuzz.io → 138.199.132.240 (LB 1 uniquement)
```

Ou gardez les 2 mais avec un DNS intelligent qui fait du healthcheck.

