#!/bin/bash
echo "============================================================"
echo " [KeyBuzz] RESUME FINAL MODULE 3"
echo "============================================================"
echo ""
echo "ETAPE 1: Credentials"
if [ -f /opt/keybuzz-installer/credentials/postgres.env ]; then
  echo "  ✓ Credentials crees"
else
  echo "  ✗ Credentials manquants"
fi
echo ""
echo "ETAPE 2: Patroni Cluster (3 noeuds)"
echo "  Services:"
for ip in 10.0.0.120 10.0.0.121 10.0.0.122; do
  status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@${ip} 'systemctl is-active patroni-docker.service 2>/dev/null || echo inactive' 2>/dev/null)
  echo "    ${ip}: ${status}"
done
echo ""
echo "ETAPE 3: HAProxy (2 noeuds)"
echo "  Services:"
for ip in 10.0.0.11 10.0.0.12; do
  status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@${ip} 'systemctl is-active haproxy-docker.service 2>/dev/null || echo inactive' 2>/dev/null)
  echo "    ${ip}: ${status}"
done
echo ""
echo "ETAPE 4: PgBouncer (2 noeuds)"
echo "  Services:"
for ip in 10.0.0.11 10.0.0.12; do
  status=$(ssh -o BatchMode=yes -o ConnectTimeout=5 root@${ip} 'systemctl is-active pgbouncer-docker.service 2>/dev/null || echo inactive' 2>/dev/null)
  echo "    ${ip}: ${status}"
done
echo ""
echo "ETAPE 5: pgvector"
echo "  ⚠️  Installation differee (necessite cluster actif)"
echo ""
echo "ETAPE 6: Diagnostics"
echo "  ✓ Scripts de diagnostic disponibles"
echo ""
echo "Logs disponibles:"
ls -lh /tmp/module3_*.log 2>/dev/null | tail -5


