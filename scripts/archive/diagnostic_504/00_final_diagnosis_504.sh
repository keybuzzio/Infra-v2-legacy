#!/usr/bin/env bash
# Diagnostic final du problème 504

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Diagnostic Final Problème 504"
echo "=============================================================="
echo ""

# 1. Vérifier kube-proxy
echo "1. Vérification kube-proxy:"
echo "=============================================================="
kubectl get pods -n kube-system | grep -E "kube-proxy|NAME" || echo "kube-proxy non trouvé (K3s utilise klipper-lb)"
echo ""

# 2. Vérifier le service
echo "2. Configuration Service keybuzz-front:"
echo "=============================================================="
kubectl get svc -n keybuzz keybuzz-front -o yaml | grep -A 5 "spec:" | head -10
echo ""

# 3. Vérifier les endpoints
echo "3. Endpoints keybuzz-front:"
echo "=============================================================="
kubectl get endpoints -n keybuzz keybuzz-front -o yaml | grep -A 15 "subsets:" | head -20
echo ""

# 4. Test depuis Ingress Controller vers Pod direct
echo "4. Test depuis Ingress Controller vers Pod direct (10.42.5.5:80):"
echo "=============================================================="
INGRESS_POD=$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk '{print $1}')
POD_IP="10.42.5.5"

if [[ -n "$INGRESS_POD" ]]; then
  SUCCESS=0
  for i in {1..5}; do
    echo -n "Tentative $i: "
    RESULT=$(kubectl exec -n ingress-nginx "$INGRESS_POD" -- sh -c "timeout 5 curl -s http://$POD_IP/ 2>&1" | head -1 || echo "FAIL")
    if echo "$RESULT" | grep -q "KeyBuzz\|html"; then
      echo "✅ OK"
      SUCCESS=$((SUCCESS + 1))
    else
      echo "❌ ÉCHEC"
    fi
    sleep 1
  done
  echo "Résultat: $SUCCESS/5 succès"
else
  echo "Ingress Controller pod non trouvé"
fi
echo ""

# 5. Solution: Modifier l'Ingress pour utiliser les IPs des pods directement
echo "5. SOLUTION PROPOSÉE:"
echo "=============================================================="
echo ""
echo "Le problème est que les Services ClusterIP (10.43.x.x) ne fonctionnent pas"
echo "depuis les pods, mais la connectivité pod-to-pod directe fonctionne."
echo ""
echo "Options:"
echo "1. Utiliser les IPs des pods directement dans l'Ingress (non recommandé)"
echo "2. Corriger la configuration kube-proxy/klipper-lb"
echo "3. Utiliser un Service de type NodePort au lieu de ClusterIP"
echo ""
echo "Vérifions d'abord si klipper-lb fonctionne..."
echo ""

# 6. Vérifier klipper-lb (service load balancer de K3s)
echo "6. Vérification klipper-lb:"
echo "=============================================================="
kubectl get pods -n kube-system | grep -E "svclb|NAME" || echo "svclb non trouvé"
echo ""

# 7. Vérifier les iptables pour les services
echo "7. Vérification iptables KUBE-SERVICES sur master-01:"
echo "=============================================================="
ssh -o StrictHostKeyChecking=no root@10.0.0.100 "iptables -t nat -L KUBE-SERVICES -n | grep '10.43.38.57' | head -5" || echo "Règle non trouvée"
echo ""

echo "=============================================================="
echo " ✅ Diagnostic terminé"
echo "=============================================================="
echo ""
echo "RECOMMANDATION:"
echo "Le problème vient des Services ClusterIP qui ne fonctionnent pas."
echo "La solution la plus simple est de modifier l'Ingress pour pointer"
echo "directement vers les pods, ou de corriger la configuration réseau K3s."
echo ""

