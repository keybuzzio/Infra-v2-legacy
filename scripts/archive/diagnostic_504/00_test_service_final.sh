#!/usr/bin/env bash
# Test final Service ClusterIP

set -euo pipefail

echo "=============================================================="
echo " [KeyBuzz] Test Final Service ClusterIP"
echo "=============================================================="
echo ""

SVC_IP="10.43.38.57"

echo "Test Pod -> Service ClusterIP ($SVC_IP:80):"
kubectl run test-curl-final --image=curlimages/curl:latest --rm -i --restart=Never -- sh <<EOF
timeout 10 curl -v http://$SVC_IP/ 2>&1 | head -20
EOF

echo ""
echo "=============================================================="

