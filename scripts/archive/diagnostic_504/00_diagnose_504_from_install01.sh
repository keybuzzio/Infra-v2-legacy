#!/usr/bin/env bash
# Script de diagnostic 504 depuis install-01

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Diagnostic 504 depuis install-01"
echo "=============================================================="
echo ""

# 1. Vérifier les pods KeyBuzz
echo "1. État des pods KeyBuzz:"
echo "=============================================================="
kubectl get pods -n keybuzz -o wide
echo ""

# 2. Vérifier les services
echo "2. Services KeyBuzz:"
echo "=============================================================="
kubectl get svc -n keybuzz -o wide
echo ""

# 3. Vérifier les endpoints
echo "3. Endpoints KeyBuzz:"
echo "=============================================================="
kubectl get endpoints -n keybuzz
echo ""

# 4. Vérifier l'Ingress
echo "4. Ingress KeyBuzz:"
echo "=============================================================="
kubectl get ingress -n keybuzz -o wide
echo ""

# 5. Vérifier l'Ingress Controller
echo "5. Ingress Controller pods:"
echo "=============================================================="
kubectl get pods -n ingress-nginx -o wide | grep nginx-ingress-controller
echo ""

# 6. Récupérer les IPs
SVC_IP=$(kubectl get svc -n keybuzz keybuzz-front -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")
POD_IPS=$(kubectl get pods -n keybuzz -l app=keybuzz-front -o jsonpath='{.items[*].status.podIP}' 2>/dev/null || echo "")
INGRESS_POD=$(kubectl get pod -n ingress-nginx -l app.kubernetes.io/component=controller --no-headers 2>/dev/null | head -1 | awk '{print $1}' || kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}' || echo "")

echo "6. Informations réseau:"
echo "=============================================================="
echo "Service IP (keybuzz-front): $SVC_IP"
echo "Pod IPs: $POD_IPS"
echo "Ingress Pod: $INGRESS_POD"
echo ""

# 7. Test depuis Ingress Controller vers Service
if [[ -n "$INGRESS_POD" ]] && [[ -n "$SVC_IP" ]]; then
  echo "7. Test depuis Ingress Controller vers Service ($SVC_IP:80):"
  echo "=============================================================="
  for i in {1..5}; do
    echo -n "Tentative $i: "
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- http://$SVC_IP/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
      echo "✅ OK"
    else
      echo "❌ ÉCHEC: $RESULT"
    fi
    sleep 1
  done
  echo ""
fi

# 8. Test depuis Ingress Controller vers Pod direct
if [[ -n "$INGRESS_POD" ]] && [[ -n "$POD_IPS" ]]; then
  FIRST_POD_IP=$(echo $POD_IPS | awk '{print $1}')
  echo "8. Test depuis Ingress Controller vers Pod direct ($FIRST_POD_IP:80):"
  echo "=============================================================="
  for i in {1..5}; do
    echo -n "Tentative $i: "
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 10 wget -qO- http://$FIRST_POD_IP/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
      echo "✅ OK"
    else
      echo "❌ ÉCHEC: $RESULT"
    fi
    sleep 1
  done
  echo ""
fi

# 9. Vérifier les logs Ingress Controller
if [[ -n "$INGRESS_POD" ]]; then
  echo "9. Derniers logs Ingress Controller (erreurs):"
  echo "=============================================================="
  kubectl logs -n ingress-nginx "$INGRESS_POD" --tail=50 2>&1 | grep -i -E "504|502|503|timeout|upstream|error|keybuzz" | tail -10 || echo "Aucune erreur récente"
  echo ""
fi

# 10. Vérifier la configuration NGINX dans l'Ingress Controller
if [[ -n "$INGRESS_POD" ]]; then
  echo "10. Configuration NGINX (recherche keybuzz):"
  echo "=============================================================="
  kubectl exec -n ingress-nginx "$INGRESS_POD" -- cat /etc/nginx/nginx.conf 2>/dev/null | grep -A 10 -B 5 "keybuzz\|platform" | head -30 || echo "Aucune configuration keybuzz trouvée"
  echo ""
fi

# 11. Vérifier les routes réseau sur les nœuds
echo "11. Vérification routes réseau (exemple: master-01):"
echo "=============================================================="
MASTER01_IP="10.0.0.100"
FIRST_POD_IP=$(echo $POD_IPS | awk '{print $1}')
if [[ -n "$FIRST_POD_IP" ]]; then
  ssh -o StrictHostKeyChecking=no root@"$MASTER01_IP" "ip route get $FIRST_POD_IP 2>&1" || echo "Impossible de vérifier"
else
  echo "Aucun pod IP trouvé"
fi
echo ""

# 12. Test depuis master-01 vers pod
if [[ -n "$FIRST_POD_IP" ]]; then
  echo "12. Test depuis master-01 vers pod ($FIRST_POD_IP:80):"
  echo "=============================================================="
  ssh -o StrictHostKeyChecking=no root@"$MASTER01_IP" "timeout 5 curl -s http://$FIRST_POD_IP/ 2>&1 | head -1" && echo "✅ OK" || echo "❌ ÉCHEC"
  echo ""
fi

echo "=============================================================="
echo " ✅ Diagnostic terminé"
echo "=============================================================="

