#!/usr/bin/env bash
# Script à exécuter sur CHAQUE nœud K3s pour ajouter les règles UFW nécessaires

echo "=============================================================="
echo " [KeyBuzz] Ajout règles UFW pour K3s"
echo "=============================================================="
echo ""

# Autoriser le réseau des pods K3s (10.42.0.0/16)
echo "Ajout règle: 10.42.0.0/16 (pods K3s)..."
ufw allow from 10.42.0.0/16 to any comment "K3s pods network" 2>/dev/null && echo "✅ Ajouté" || echo "⚠️  Déjà présent ou erreur"

# Autoriser le réseau des services K3s (10.43.0.0/16)
echo "Ajout règle: 10.43.0.0/16 (services K3s)..."
ufw allow from 10.43.0.0/16 to any comment "K3s services network" 2>/dev/null && echo "✅ Ajouté" || echo "⚠️  Déjà présent ou erreur"

# Autoriser Flannel VXLAN (port 8472/udp)
echo "Ajout règle: 8472/udp (Flannel VXLAN)..."
ufw allow 8472/udp comment "K3s flannel VXLAN" 2>/dev/null && echo "✅ Ajouté" || echo "⚠️  Déjà présent ou erreur"

# Autoriser Kubelet (port 10250/tcp)
echo "Ajout règle: 10250/tcp (Kubelet)..."
ufw allow 10250/tcp comment "K3s kubelet" 2>/dev/null && echo "✅ Ajouté" || echo "⚠️  Déjà présent ou erreur"

echo ""
echo "Vérification des règles ajoutées:"
ufw status | grep -E "10\.42\.|10\.43\.|K3s|k3s" || echo "Aucune règle K3s trouvée"

echo ""
echo "=============================================================="
echo " ✅ Terminé"
echo "=============================================================="

