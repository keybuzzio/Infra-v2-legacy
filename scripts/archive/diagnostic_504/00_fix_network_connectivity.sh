#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Correction Connectivité Réseau Interne"
echo "=============================================================="
echo ""

# Récupérer les informations
INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')
INGRESS_NODE=$(kubectl get pod -n ingress-nginx "$INGRESS_POD" -o jsonpath='{.spec.nodeName}')
POD=$(kubectl get pod -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | head -1 | awk '{print $1}')
POD_NODE=$(kubectl get pod -n keybuzz "$POD" -o jsonpath='{.spec.nodeName}')
POD_IP=$(kubectl get pod -n keybuzz "$POD" -o jsonpath='{.status.podIP}')

echo "Ingress Pod: $INGRESS_POD (Node: $INGRESS_NODE)"
echo "KeyBuzz Pod: $POD (Node: $POD_NODE, IP: $POD_IP)"
echo ""

# Test 1: Vérifier si les pods sont sur le même nœud
if [[ "$INGRESS_NODE" == "$POD_NODE" ]]; then
    echo "⚠️  Les pods sont sur le même nœud, testons la connectivité locale..."
else
    echo "ℹ️  Les pods sont sur des nœuds différents ($INGRESS_NODE -> $POD_NODE)"
fi
echo ""

# Test 2: Test depuis le nœud Ingress vers le pod
echo "1. Test depuis le nœud Ingress vers le pod KeyBuzz:"
echo "   Test depuis $INGRESS_NODE vers $POD_IP:80"
ssh -o StrictHostKeyChecking=no root@"$INGRESS_NODE" "timeout 5 nc -zv $POD_IP 80 2>&1" || echo "   ❌ Non accessible depuis le nœud"
echo ""

# Test 3: Vérifier les règles UFW sur le nœud Ingress
echo "2. Vérification UFW sur le nœud Ingress ($INGRESS_NODE):"
ssh -o StrictHostKeyChecking=no root@"$INGRESS_NODE" "ufw status | grep -E '10\.42\.|10\.43\.|K3s|k3s' || echo 'Aucune règle K3s trouvée'" || echo "   ⚠️  Impossible de vérifier UFW"
echo ""

# Test 4: Vérifier les règles UFW sur le nœud KeyBuzz
echo "3. Vérification UFW sur le nœud KeyBuzz ($POD_NODE):"
ssh -o StrictHostKeyChecking=no root@"$POD_NODE" "ufw status | grep -E '10\.42\.|10\.43\.|K3s|k3s' || echo 'Aucune règle K3s trouvée'" || echo "   ⚠️  Impossible de vérifier UFW"
echo ""

# Test 5: Test direct depuis le pod KeyBuzz
echo "4. Test direct depuis le pod KeyBuzz (localhost):"
kubectl exec -n keybuzz "$POD" -- sh -c "timeout 3 wget -qO- http://127.0.0.1/ 2>&1" | head -3 || echo "   ❌ Pod ne répond pas"
echo ""

# Test 6: Vérifier la configuration réseau K3s
echo "5. Configuration réseau K3s:"
echo "   Flannel backend:"
kubectl get daemonset -n kube-system kube-flannel -o yaml 2>/dev/null | grep -A 5 "FLANNEL_BACKEND" | head -5 || echo "   ⚠️  Flannel non trouvé"
echo ""

# Test 7: Vérifier les routes réseau
echo "6. Routes réseau sur le nœud Ingress:"
ssh -o StrictHostKeyChecking=no root@"$INGRESS_NODE" "ip route | grep -E '10\.42\.|10\.43\.|flannel' | head -5" || echo "   ⚠️  Impossible de vérifier les routes"
echo ""

# Test 8: Vérifier iptables
echo "7. Vérification iptables (règles qui bloquent):"
ssh -o StrictHostKeyChecking=no root@"$INGRESS_NODE" "iptables -L -n | grep -E 'REJECT|DROP' | grep -E '10\.42\.|10\.43\.' | head -5" || echo "   Aucune règle bloquante trouvée"
echo ""

# Correction: Ajouter les règles UFW nécessaires
echo "8. Correction: Ajout des règles UFW si nécessaire..."
echo "   Sur le nœud Ingress ($INGRESS_NODE):"
ssh -o StrictHostKeyChecking=no root@"$INGRESS_NODE" "ufw allow from 10.42.0.0/16 to any comment 'K3s pods network' 2>/dev/null || true"
ssh -o StrictHostKeyChecking=no root@"$INGRESS_NODE" "ufw allow from 10.43.0.0/16 to any comment 'K3s services network' 2>/dev/null || true"
echo "   ✅ Règles UFW ajoutées sur $INGRESS_NODE"
echo ""

echo "   Sur le nœud KeyBuzz ($POD_NODE):"
ssh -o StrictHostKeyChecking=no root@"$POD_NODE" "ufw allow from 10.42.0.0/16 to any comment 'K3s pods network' 2>/dev/null || true"
ssh -o StrictHostKeyChecking=no root@"$POD_NODE" "ufw allow from 10.43.0.0/16 to any comment 'K3s services network' 2>/dev/null || true"
echo "   ✅ Règles UFW ajoutées sur $POD_NODE"
echo ""

# Test final
echo "9. Test final après correction:"
sleep 2
RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 5 wget -qO- http://$POD_IP/ 2>&1" | head -1 || echo "FAIL")
if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
    echo "   ✅ Connectivité restaurée !"
else
    echo "   ❌ Toujours en échec"
fi
echo ""

echo "=============================================================="
echo " ✅ Correction terminée"
echo "=============================================================="

