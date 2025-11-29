#!/bin/bash
echo "============================================================"
echo " [KeyBuzz] Verification Etat Module 3"
echo "============================================================"
echo ""

# Compteurs
patroni_actif=0
haproxy_actif=0
pgbouncer_actif=0

echo "1. SERVICES SYSTEMD:"
echo ""

echo "   Patroni Cluster:"
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
  status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@${ip} 'systemctl is-active patroni-docker.service 2>/dev/null || echo inactive' 2>/dev/null)
  if [ "${status}" = "active" ]; then
    patroni_actif=$((patroni_actif+1))
    echo "     ${ip}: ✓ active"
  else
    echo "     ${ip}: ✗ ${status}"
  fi
done

echo ""
echo "   HAProxy:"
for ip in 10.0.0.11 10.0.0.12; do
  status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@${ip} 'systemctl is-active haproxy-docker.service 2>/dev/null || echo inactive' 2>/dev/null)
  if [ "${status}" = "active" ]; then
    haproxy_actif=$((haproxy_actif+1))
    echo "     ${ip}: ✓ active"
  else
    echo "     ${ip}: ✗ ${status}"
  fi
done

echo ""
echo "   PgBouncer:"
for ip in 10.0.0.11 10.0.0.12; do
  status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@${ip} 'systemctl is-active pgbouncer-docker.service 2>/dev/null || echo inactive' 2>/dev/null)
  if [ "${status}" = "active" ]; then
    pgbouncer_actif=$((pgbouncer_actif+1))
    echo "     ${ip}: ✓ active"
  else
    echo "     ${ip}: ✗ ${status}"
  fi
done

echo ""
echo "2. CONTENEURS DOCKER:"
echo ""

echo "   Patroni:"
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
  containers=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@${ip} 'docker ps | grep -c patroni || echo 0' 2>/dev/null)
  echo "     ${ip}: ${containers} conteneur(s)"
done

echo ""
echo "   HAProxy:"
for ip in 10.0.0.11 10.0.0.12; do
  containers=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@${ip} 'docker ps | grep -c haproxy || echo 0' 2>/dev/null)
  echo "     ${ip}: ${containers} conteneur(s)"
done

echo ""
echo "3. RESUMÉ:"
echo "   Patroni:    ${patroni_actif}/3 actifs"
echo "   HAProxy:    ${haproxy_actif}/2 actifs"
echo "   PgBouncer: ${pgbouncer_actif}/2 actifs"
echo ""

if [ ${patroni_actif} -eq 3 ] && [ ${haproxy_actif} -eq 2 ] && [ ${pgbouncer_actif} -eq 2 ]; then
  echo "✓ TOUS LES SERVICES SONT ACTIFS - Module 3 prêt !"
  exit 0
else
  echo "⚠️  Certains services ne sont pas actifs."
  echo ""
  echo "4. DIAGNOSTIC:"
  echo ""
  echo "   Vérification des erreurs Patroni (db-master-01):"
  ssh -o BatchMode=yes -o ConnectTimeout=5 root@10.0.0.120 'journalctl -u patroni-docker.service --no-pager -n 10 2>/dev/null | tail -5' 2>/dev/null || echo "     Impossible de récupérer les logs"
  echo ""
  echo "   Vérification des erreurs HAProxy (haproxy-01):"
  ssh -o BatchMode=yes -o ConnectTimeout=5 root@10.0.0.11 'journalctl -u haproxy-docker.service --no-pager -n 10 2>/dev/null | tail -5' 2>/dev/null || echo "     Impossible de récupérer les logs"
  exit 1
fi


