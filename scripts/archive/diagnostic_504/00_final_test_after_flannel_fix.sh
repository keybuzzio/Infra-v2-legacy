#!/usr/bin/env bash
# Script final de test après correction UFW Flannel

set +e

echo "=============================================================="
echo " [KeyBuzz] Test Final après Correction UFW Flannel"
echo "=============================================================="
echo ""

MASTER_IP="10.0.0.100"

# Exécuter les tests depuis master-01
ssh -o StrictHostKeyChecking=no root@"$MASTER_IP" "bash -c '
# Récupérer les informations
INGRESS_POD=\$(kubectl get pod -n ingress-nginx --no-headers 2>/dev/null | grep nginx-ingress-controller | head -1 | awk \"{print \\\$1}\")
SVC_IP=\$(kubectl get svc -n keybuzz keybuzz-front -o jsonpath=\"{.spec.clusterIP}\" 2>/dev/null || echo \"\")
POD_IP=\$(kubectl get pod -n keybuzz -l app=keybuzz-front --no-headers 2>/dev/null | head -1 | awk \"{print \\\$1}\" | xargs kubectl get pod -n keybuzz -o jsonpath=\"{.status.podIP}\" 2>/dev/null || echo \"\")

echo \"Ingress Pod: \$INGRESS_POD\"
echo \"Service IP: \$SVC_IP\"
echo \"Pod IP: \$POD_IP\"
echo \"\"

# Test 1: Depuis master-01 vers pod direct
echo \"1. Test depuis master-01 vers Pod (\$POD_IP:80) - 5 tentatives:\"
SUCCESS1=0
for i in {1..5}; do
    RESULT=\$(timeout 5 curl -s http://\$POD_IP/ 2>&1 | head -1 || echo \"FAIL\")
    if echo \"\$RESULT\" | grep -q \"KeyBuzz\|html\"; then
        echo -n \"✅\"
        SUCCESS1=\$((SUCCESS1 + 1))
    else
        echo -n \"❌\"
    fi
    sleep 1
done
echo \"\"
echo \"   Résultat: \$SUCCESS1/5\"
echo \"\"

# Test 2: Depuis Ingress Controller vers Service
if [[ -n \"\$INGRESS_POD\" ]] && [[ -n \"\$SVC_IP\" ]]; then
    echo \"2. Test Ingress Controller -> Service (\$SVC_IP:80) - 5 tentatives:\"
    SUCCESS2=0
    for i in {1..5}; do
        RESULT=\$(kubectl exec -n ingress-nginx \"\$INGRESS_POD\" -- sh -c \"timeout 10 wget -qO- http://\$SVC_IP/ 2>&1\" | head -1 || echo \"FAIL\")
        if echo \"\$RESULT\" | grep -q \"KeyBuzz\|html\"; then
            echo -n \"✅\"
            SUCCESS2=\$((SUCCESS2 + 1))
        else
            echo -n \"❌\"
        fi
        sleep 1
    done
    echo \"\"
    echo \"   Résultat: \$SUCCESS2/5\"
    echo \"\"
fi

# Test 3: Depuis Ingress Controller vers Pod direct
if [[ -n \"\$INGRESS_POD\" ]] && [[ -n \"\$POD_IP\" ]]; then
    echo \"3. Test Ingress Controller -> Pod direct (\$POD_IP:80) - 5 tentatives:\"
    SUCCESS3=0
    for i in {1..5}; do
        RESULT=\$(kubectl exec -n ingress-nginx \"\$INGRESS_POD\" -- sh -c \"timeout 10 wget -qO- http://\$POD_IP/ 2>&1\" | head -1 || echo \"FAIL\")
        if echo \"\$RESULT\" | grep -q \"KeyBuzz\|html\"; then
            echo -n \"✅\"
            SUCCESS3=\$((SUCCESS3 + 1))
        else
            echo -n \"❌\"
        fi
        sleep 1
    done
    echo \"\"
    echo \"   Résultat: \$SUCCESS3/5\"
    echo \"\"
fi

# Résumé
echo \"==============================================================\"
echo \" Résumé\"
echo \"==============================================================\"
echo \"\"
echo \"Test 1 (master -> pod): \$SUCCESS1/5\"
echo \"Test 2 (Ingress -> Service): \$SUCCESS2/5\"
echo \"Test 3 (Ingress -> Pod): \$SUCCESS3/5\"
echo \"\"

if [[ \$SUCCESS2 -ge 4 ]] || [[ \$SUCCESS3 -ge 4 ]]; then
    echo \"✅ Le problème semble résolu !\"
    echo \"   Testez maintenant depuis votre navigateur:\"
    echo \"   - https://platform.keybuzz.io\"
    echo \"   - https://platform-api.keybuzz.io\"
else
    echo \"❌ Le problème persiste. Investigation supplémentaire nécessaire.\"
fi
echo \"\"
'" 2>&1

echo ""
echo "=============================================================="

