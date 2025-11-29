#!/usr/bin/env bash
#
# 09_k3s_check_test_results.sh - Vérifier les résultats des tests K3s
#

LOG_DIR="/opt/keybuzz-installer/logs"
LATEST_LOG=$(ls -t ${LOG_DIR}/test_failover_k3s_final_*.log 2>/dev/null | head -1)

if [[ -z "${LATEST_LOG}" ]]; then
    echo "Aucun log de test trouvé"
    exit 1
fi

echo "=== Résultats Tests K3s Failover ==="
echo "Log: ${LATEST_LOG}"
echo ""

# Vérifier si les tests sont terminés
if grep -q "RÉSUMÉ FINAL" "${LATEST_LOG}" 2>/dev/null; then
    echo "✅ Tests terminés"
    echo ""
    
    # Afficher le résumé
    echo "=== Résumé ==="
    grep -A 10 "RÉSUMÉ FINAL" "${LATEST_LOG}" | head -15
    
    # Compter les tests
    TOTAL=$(grep -c "Test:" "${LATEST_LOG}" 2>/dev/null || echo "0")
    SUCCESS=$(grep -c "Test:.*OK" "${LATEST_LOG}" 2>/dev/null || echo "0")
    FAILED=$(grep -c "Test:.*ÉCHEC" "${LATEST_LOG}" 2>/dev/null || echo "0")
    
    echo ""
    echo "Total de tests: ${TOTAL}"
    echo "Tests réussis: ${SUCCESS}"
    echo "Tests échoués: ${FAILED}"
    
    if [[ ${FAILED} -eq 0 ]]; then
        echo ""
        echo "✅ TOUS LES TESTS RÉUSSIS (100%)"
    else
        echo ""
        echo "⚠️ ${FAILED} test(s) échoué(s)"
        echo ""
        echo "Tests échoués:"
        grep "Test:.*ÉCHEC" "${LATEST_LOG}" | head -5
    fi
else
    echo "⏳ Tests en cours..."
    echo ""
    echo "Dernières lignes du log:"
    tail -20 "${LATEST_LOG}"
fi

