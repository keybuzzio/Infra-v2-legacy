# Instructions pour Finaliser la Correction UFW

## ✅ État Actuel

Les règles UFW ont été ajoutées avec succès sur :
- ✅ k3s-master-01 (91.98.124.228)
- ✅ k3s-master-02 (91.98.117.26)
- ✅ k3s-master-03 (91.98.165.238)

Les règles UFW n'ont **PAS** été ajoutées sur les workers (accès SSH échoué) :
- ❌ k3s-worker-01 (116.203.135.192)
- ❌ k3s-worker-02 (91.99.164.62)
- ❌ k3s-worker-03 (157.90.119.183) ← **POD KEYBUZZ EST ICI**
- ❌ k3s-worker-04 (91.98.200.38)
- ❌ k3s-worker-05 (188.245.45.242)

## 🔧 Solution : Ajouter les Règles UFW sur les Workers

### Option 1 : Via SSH depuis install-01 (si accès configuré)

Exécutez ces commandes pour chaque worker :

```bash
# Worker 01
ssh root@116.203.135.192 'ufw allow from 10.42.0.0/16 to any comment "K3s pods network" && ufw allow from 10.43.0.0/16 to any comment "K3s services network" && ufw allow 8472/udp comment "K3s flannel VXLAN" && ufw allow 10250/tcp comment "K3s kubelet"'

# Worker 02
ssh root@91.99.164.62 'ufw allow from 10.42.0.0/16 to any comment "K3s pods network" && ufw allow from 10.43.0.0/16 to any comment "K3s services network" && ufw allow 8472/udp comment "K3s flannel VXLAN" && ufw allow 10250/tcp comment "K3s kubelet"'

# Worker 03 (IMPORTANT - pod KeyBuzz ici)
ssh root@157.90.119.183 'ufw allow from 10.42.0.0/16 to any comment "K3s pods network" && ufw allow from 10.43.0.0/16 to any comment "K3s services network" && ufw allow 8472/udp comment "K3s flannel VXLAN" && ufw allow 10250/tcp comment "K3s kubelet"'

# Worker 04
ssh root@91.98.200.38 'ufw allow from 10.42.0.0/16 to any comment "K3s pods network" && ufw allow from 10.43.0.0/16 to any comment "K3s services network" && ufw allow 8472/udp comment "K3s flannel VXLAN" && ufw allow 10250/tcp comment "K3s kubelet"'

# Worker 05
ssh root@188.245.45.242 'ufw allow from 10.42.0.0/16 to any comment "K3s pods network" && ufw allow from 10.43.0.0/16 to any comment "K3s services network" && ufw allow 8472/udp comment "K3s flannel VXLAN" && ufw allow 10250/tcp comment "K3s kubelet"'
```

### Option 2 : Connexion directe sur chaque worker

Connectez-vous directement sur chaque worker et exécutez :

```bash
ufw allow from 10.42.0.0/16 to any comment "K3s pods network"
ufw allow from 10.43.0.0/16 to any comment "K3s services network"
ufw allow 8472/udp comment "K3s flannel VXLAN"
ufw allow 10250/tcp comment "K3s kubelet"
```

### Option 3 : Utiliser le script 00_add_ufw_rules_k3s.sh

Copiez le script `00_add_ufw_rules_k3s.sh` sur chaque worker et exécutez-le :

```bash
# Sur chaque worker
scp 00_add_ufw_rules_k3s.sh root@<IP_WORKER>:/root/
ssh root@<IP_WORKER> "chmod +x /root/00_add_ufw_rules_k3s.sh && bash /root/00_add_ufw_rules_k3s.sh"
```

## ✅ Vérification

Après avoir ajouté les règles sur tous les workers, vérifiez :

```bash
# Depuis install-01
bash /root/00_test_after_ufw_fix.sh
```

Ou testez manuellement depuis votre navigateur :
- https://platform.keybuzz.io
- https://platform-api.keybuzz.io

## 📋 Règles UFW à Ajouter

Les 4 règles suivantes doivent être présentes sur **TOUS** les nœuds K3s :

1. `ufw allow from 10.42.0.0/16 to any comment "K3s pods network"`
2. `ufw allow from 10.43.0.0/16 to any comment "K3s services network"`
3. `ufw allow 8472/udp comment "K3s flannel VXLAN"`
4. `ufw allow 10250/tcp comment "K3s kubelet"`

## 🔍 Vérification des Règles

Pour vérifier que les règles sont présentes :

```bash
ufw status | grep -E "10\.42\.|10\.43\.|K3s|k3s"
```

Vous devriez voir les 4 règles listées ci-dessus.

