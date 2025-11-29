# Configuration DNS pour KeyBuzz

**Date** : 20 novembre 2025  
**Statut** : Configuration progressive par module

---

## 🎯 Principe : Configuration Progressive

**Vous ne devez créer QUE les enregistrements DNS pour les modules que vous déployez.**

Les autres URLs seront créées quand leurs modules respectifs seront installés.

---

## ✅ Module 10 - KeyBuzz API & Front (À CRÉER MAINTENANT)

### Enregistrements DNS à créer

Créez ces 2 enregistrements DNS dans votre zone DNS `keybuzz.io` :

| Type | Nom | Valeur | TTL | Notes |
|------|-----|--------|-----|-------|
| A | `platform` | IP LB Hetzner (10.0.0.5 ou 10.0.0.6) | 300 | Frontend KeyBuzz |
| A | `platform-api` | IP LB Hetzner (10.0.0.5 ou 10.0.0.6) | 300 | API KeyBuzz |

**Résultat** :
- `platform.keybuzz.io` → IP LB Hetzner
- `platform-api.keybuzz.io` → IP LB Hetzner

### Configuration LB Hetzner

Sur vos 2 LB Hetzner (10.0.0.5 et 10.0.0.6), ajoutez les certificats TLS pour :
- `platform.keybuzz.io`
- `platform-api.keybuzz.io`

Les certificats peuvent être :
- Let's Encrypt (via Hetzner)
- Certificats personnalisés

---

## 📋 URLs Futures (À CRÉER PLUS TARD)

### Module 11 - Chatwoot
- `support.keybuzz.io` → À créer lors du Module 11

### Module 12 - n8n
- `n8n.keybuzz.io` → À créer lors du Module 12

### Module 13 - Superset
- `analytics.keybuzz.io` → À créer lors du Module 13

### Module 15 - LiteLLM
- `llm.keybuzz.io` → À créer lors du Module 15

### Module 14 - Vault
- `vault.keybuzz.io` → À créer lors du Module 14

### Autres services
- `s3.keybuzz.io` → MinIO (déjà configuré si Module 6 installé)
- `mail.keybuzz.io` → Mail (Module 23, futur)
- `erp.keybuzz.io` → ERPNext (si exposé publiquement)
- Etc.

---

## 🔍 Vérification DNS

Après création des enregistrements, vérifiez avec :

```bash
# Vérifier la résolution DNS
dig platform.keybuzz.io
dig platform-api.keybuzz.io

# Ou avec nslookup
nslookup platform.keybuzz.io
nslookup platform-api.keybuzz.io
```

Les deux doivent pointer vers l'IP de vos LB Hetzner.

---

## ⚠️ Important

1. **Ne créez QUE les DNS pour les modules déployés**
2. **Les autres URLs seront créées au fur et à mesure**
3. **Vérifiez que les certificats TLS sont configurés sur les LB Hetzner**
4. **Les DNS peuvent prendre quelques minutes à se propager**

---

## 📝 Checklist Module 10

- [ ] Créer l'enregistrement DNS `platform.keybuzz.io` → IP LB Hetzner
- [ ] Créer l'enregistrement DNS `platform-api.keybuzz.io` → IP LB Hetzner
- [ ] Configurer les certificats TLS sur les LB Hetzner
- [ ] Vérifier la résolution DNS
- [ ] Tester l'accès HTTPS : `https://platform.keybuzz.io`
- [ ] Tester l'accès API : `https://platform-api.keybuzz.io/health`

---

**Dernière mise à jour** : 20 novembre 2025

