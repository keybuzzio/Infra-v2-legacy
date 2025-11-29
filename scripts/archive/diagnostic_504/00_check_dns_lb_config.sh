#!/usr/bin/env bash
set -e

echo "=============================================================="
echo " [KeyBuzz] Vérification Configuration DNS et LB"
echo "=============================================================="
echo ""

echo "1. Résolution DNS pour platform.keybuzz.io:"
echo "   (Depuis install-01)"
nslookup platform.keybuzz.io 2>&1 | grep -A 5 "Name:" || echo "   ⚠️  nslookup non disponible, test avec dig..."
dig +short platform.keybuzz.io A 2>&1 || echo "   ⚠️  dig non disponible"
echo ""

echo "2. Test de connectivité vers chaque IP:"
IPS=$(dig +short platform.keybuzz.io A 2>&1 || nslookup platform.keybuzz.io 2>&1 | grep "Address:" | awk '{print $2}' || echo "")

if [[ -z "$IPS" ]]; then
    echo "   ⚠️  Impossible de récupérer les IPs"
else
    echo "   IPs trouvées:"
    echo "$IPS" | while read -r ip; do
        if [[ -n "$ip" ]]; then
            echo "   - $ip"
            # Test de connectivité
            if timeout 3 nc -zv "$ip" 443 2>&1 | grep -q "open"; then
                echo "     ✅ Port 443 accessible"
            else
                echo "     ❌ Port 443 non accessible"
            fi
            if timeout 3 nc -zv "$ip" 80 2>&1 | grep -q "open"; then
                echo "     ✅ Port 80 accessible"
            else
                echo "     ❌ Port 80 non accessible"
            fi
        fi
    done
fi
echo ""

echo "3. Test HTTP vers chaque IP (avec Host header):"
if [[ -n "$IPS" ]]; then
    echo "$IPS" | while read -r ip; do
        if [[ -n "$ip" ]]; then
            echo "   Test vers $ip:"
            HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -H "Host: platform.keybuzz.io" --max-time 5 "http://$ip/" 2>&1 || echo "000")
            if [[ "$HTTP_CODE" == "200" ]]; then
                echo "     ✅ HTTP 200 OK"
            elif [[ "$HTTP_CODE" == "000" ]]; then
                echo "     ❌ Timeout ou erreur de connexion"
            else
                echo "     ⚠️  HTTP $HTTP_CODE"
            fi
        fi
    done
fi
echo ""

echo "4. Recommandations:"
echo ""
echo "   ⚠️  PROBLÈME IDENTIFIÉ:"
echo "   Si vous avez 2 LBs avec 2 IPs différentes dans votre DNS,"
echo "   cela peut causer des problèmes intermittents car:"
echo ""
echo "   - Le DNS fait du round-robin entre les 2 IPs"
echo "   - Si un LB a des problèmes, 50% des requêtes échouent"
echo "   - Les timeouts peuvent varier entre les 2 LBs"
echo ""
echo "   ✅ SOLUTION RECOMMANDÉE:"
echo "   1. Utiliser UN SEUL LB avec une seule IP dans le DNS"
echo "   2. OU configurer les 2 LBs en actif/passif (pas round-robin)"
echo "   3. OU utiliser un DNS avec healthcheck qui retire les IPs down"
echo ""

echo "=============================================================="

