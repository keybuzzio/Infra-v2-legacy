#!/usr/bin/env bash
# Script complet de diagnostic

set +e

echo "=============================================================="
echo " [KeyBuzz] Diagnostic Complet"
echo "=============================================================="
echo ""

MASTER_IP="10.0.0.100"
WORKER03_IP="10.0.0.112"
POD_IP="10.42.5.5"

# Test 1: Depuis master-01 vers worker-03 (IP privée)
echo "1. Test depuis master-01 vers worker-03 (10.0.0.112):"
ssh -o StrictHostKeyChecking=no root@"$MASTER_IP" "ping -c 2 10.0.0.112 2>&1 | tail -2" || echo "   ❌ Ping échoué"
echo ""

# Test 2: Depuis master-01 vers pod (via Flannel)
echo "2. Test depuis master-01 vers pod ($POD_IP) via Flannel:"
ssh -o StrictHostKeyChecking=no root@"$MASTER_IP" "timeout 5 nc -zv $POD_IP 80 2>&1" || echo "   ❌ Connexion échouée"
echo ""

# Test 3: Depuis worker-03 vers pod (devrait fonctionner)
echo "3. Test depuis worker-03 vers pod ($POD_IP) - devrait fonctionner:"
ssh -o StrictHostKeyChecking=no root@"$WORKER03_IP" "timeout 5 curl -s http://$POD_IP/ 2>&1 | head -1" && echo "   ✅ Fonctionne" || echo "   ❌ Échoué"
echo ""

# Test 4: Vérifier UFW sur master-01
echo "4. Vérification UFW sur master-01:"
ssh -o StrictHostKeyChecking=no root@"$MASTER_IP" "ufw status | grep -E '10.42|10.43|flannel|cni0' | head -15" || echo "   ⚠️  Impossible de vérifier"
echo ""

# Test 5: Vérifier iptables FORWARD sur master-01
echo "5. Vérification iptables FORWARD sur master-01:"
ssh -o StrictHostKeyChecking=no root@"$MASTER_IP" "iptables -L FORWARD -n -v | head -10" || echo "   ⚠️  Impossible de vérifier"
echo ""

# Test 6: Vérifier le routage
echo "6. Vérification routage sur master-01:"
ssh -o StrictHostKeyChecking=no root@"$MASTER_IP" "ip route get $POD_IP 2>&1" || echo "   ⚠️  Impossible de vérifier"
echo ""

# Test 7: Test avec traceroute
echo "7. Traceroute depuis master-01 vers pod:"
ssh -o StrictHostKeyChecking=no root@"$MASTER_IP" "timeout 10 traceroute -n -m 5 $POD_IP 2>&1 | head -10" || echo "   ⚠️  Traceroute non disponible"
echo ""

echo "=============================================================="
echo " ✅ Diagnostic terminé"
echo "=============================================================="

