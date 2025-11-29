#!/usr/bin/env bash
# Script de test de connectivité depuis Ingress Controller

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Test Connectivité Ingress Controller"
echo "=============================================================="
echo ""

# Récupérer les informations
INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')
SVC_IP=$(kubectl get svc -n keybuzz keybuzz-front -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
POD_IP="10.42.5.5"  # Pod sur worker-03

echo "Ingress Pod: $INGRESS_POD"
echo "Service IP: $SVC_IP"
echo "Pod IP: $POD_IP"
echo ""

# Test 1: Ingress -> Service
if [[ -n "$INGRESS_POD" ]] && [[ -n "$SVC_IP" ]]; then
  echo "Test 1: Ingress Controller -> Service ($SVC_IP:80) - 10 tentatives:"
  echo "=============================================================="
  SUCCESS1=0
  FAIL1=0
  for i in {1..10}; do
    echo -n "Tentative $i: "
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- http://$SVC_IP/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
      echo "✅ OK"
      SUCCESS1=$((SUCCESS1 + 1))
    else
      echo "❌ ÉCHEC: $RESULT"
      FAIL1=$((FAIL1 + 1))
    fi
    sleep 1
  done
  echo ""
  echo "Résultat: $SUCCESS1 succès, $FAIL1 échecs"
  echo ""
fi

# Test 2: Ingress -> Pod direct
if [[ -n "$INGRESS_POD" ]] && [[ -n "$POD_IP" ]]; then
  echo "Test 2: Ingress Controller -> Pod direct ($POD_IP:80) - 10 tentatives:"
  echo "=============================================================="
  SUCCESS2=0
  FAIL2=0
  for i in {1..10}; do
    echo -n "Tentative $i: "
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- http://$POD_IP/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
      echo "✅ OK"
      SUCCESS2=$((SUCCESS2 + 1))
    else
      echo "❌ ÉCHEC: $RESULT"
      FAIL2=$((FAIL2 + 1))
    fi
    sleep 1
  done
  echo ""
  echo "Résultat: $SUCCESS2 succès, $FAIL2 échecs"
  echo ""
fi

# Test 3: Vérifier sur quel nœud est l'Ingress Controller
if [[ -n "$INGRESS_POD" ]]; then
  INGRESS_NODE=$(kubectl get pod -n ingress-nginx "$INGRESS_POD" -o jsonpath='{.spec.nodeName}' 2>/dev/null || echo "")
  echo "Ingress Controller pod est sur: $INGRESS_NODE"
  echo "Pod KeyBuzz est sur: k3s-worker-03"
  echo ""
  
  # Si l'Ingress est sur un autre nœud, tester la connectivité réseau
  if [[ "$INGRESS_NODE" != "k3s-worker-03" ]]; then
    echo "⚠️  L'Ingress Controller et le pod KeyBuzz sont sur des nœuds différents"
    echo "   Test de connectivité réseau entre les nœuds..."
    
    # Récupérer l'IP du nœud Ingress
    INGRESS_NODE_IP=$(kubectl get node "$INGRESS_NODE" -o jsonpath='{.status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")
    if [[ -n "$INGRESS_NODE_IP" ]]; then
      echo "   Test depuis $INGRESS_NODE ($INGRESS_NODE_IP) vers pod ($POD_IP):"
      ssh -o StrictHostKeyChecking=no root@"$INGRESS_NODE_IP" "timeout 5 curl -s http://$POD_IP/ 2>&1 | head -1" && echo "   ✅ OK" || echo "   ❌ ÉCHEC"
    fi
  else
    echo "✅ L'Ingress Controller et le pod KeyBuzz sont sur le même nœud (devrait fonctionner)"
  fi
  echo ""
fi

# Résumé
echo "=============================================================="
echo " Résumé"
echo "=============================================================="
echo ""
echo "Test 1 (Ingress -> Service): $SUCCESS1/10"
echo "Test 2 (Ingress -> Pod): $SUCCESS2/10"
echo ""

if [[ $SUCCESS2 -ge 8 ]]; then
  echo "✅ La connectivité fonctionne ! Le problème 504 pourrait venir d'ailleurs."
elif [[ $SUCCESS2 -ge 5 ]]; then
  echo "⚠️  Connectivité intermittente - problème réseau probable"
else
  echo "❌ La connectivité échoue - problème réseau confirmé"
fi

echo ""
echo "=============================================================="

