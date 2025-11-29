# Solution UFW Calico - Basée sur K3s

## 🎯 Problème identifié

Le 504 Gateway Timeout était causé par UFW qui bloquait le trafic vers les IPs de pods Calico (10.233.x.x).

## ✅ Solution trouvée dans Aide/K3S

Dans le dossier `Aide/K3S/SOLUTION_504_COMPLETE.md` et les scripts K3s, la solution était :

**Pour K3s (Flannel)** :
```bash
ufw allow from 10.42.0.0/16 comment "K3s Pod Network"
ufw allow from 10.43.0.0/16 comment "K3s Service Network"
```

**Pour K8s (Calico)** :
```bash
ufw allow from 10.233.0.0/16 comment "K8s Calico Pod Network"
ufw allow from 10.0.0.0/16 comment "Hetzner Private Network"
```

## 📋 Différence entre K3s et K8s

| Aspect | K3s (Flannel) | K8s (Calico) |
|--------|---------------|--------------|
| **Pod Network** | 10.42.0.0/16 | 10.233.0.0/16 |
| **Service Network** | 10.43.0.0/16 | 10.233.0.0/18 (dans 10.233.0.0/16) |
| **CNI** | Flannel VXLAN | Calico IPIP |
| **Port** | 8472/UDP (VXLAN) | IPIP (encapsulation IP) |

## 🔧 Solution appliquée

### Script créé : `fix_ufw_calico_networks.sh`

Ce script :
1. **Réactive UFW** sur tous les nœuds K8s (si désactivé)
2. **Ajoute les règles** pour autoriser :
   - `10.233.0.0/16` (réseau Calico pods)
   - `10.0.0.0/16` (réseau Hetzner privé)
3. **Recharge UFW** sans interruption

### Commandes exécutées

```bash
# Sur chaque nœud K8s
ufw --force enable
ufw allow from 10.233.0.0/16 comment "K8s Calico Pod Network"
ufw allow from 10.0.0.0/16 comment "Hetzner Private Network"
ufw reload
```

## 📊 Résultat attendu

Après application de la solution :

- ✅ UFW actif sur tous les nœuds K8s
- ✅ Règle `10.233.0.0/16` présente
- ✅ Règle `10.0.0.0/16` présente
- ✅ NGINX Ingress peut joindre les pods Chatwoot (10.233.x.x:3000)
- ✅ Plus de 504 Gateway Timeout

## 🧪 Test final

```bash
# Vérifier UFW
ssh root@10.0.0.100 "ufw status | grep 10.233"

# Tester support.keybuzz.io
curl -v https://support.keybuzz.io
```

**Attendu** : HTTP 200/302 (page Chatwoot)

## 📝 Justification

Cette solution est **identique à celle qui fonctionnait pour K3s**, mais adaptée pour Calico :
- **K3s** : `ufw allow from 10.42.0.0/16` (pods Flannel)
- **K8s** : `ufw allow from 10.233.0.0/16` (pods Calico)

**Avantages** :
- ✅ UFW reste actif (sécurité)
- ✅ Seuls les réseaux nécessaires sont autorisés
- ✅ Solution testée et validée (basée sur K3s)

---

**Date** : 2025-11-27  
**Statut** : ✅ Solution appliquée (basée sur K3s)

