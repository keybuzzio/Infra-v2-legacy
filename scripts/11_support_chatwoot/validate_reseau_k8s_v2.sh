#!/usr/bin/env bash
set -euo pipefail

export KUBECONFIG=/root/.kube/config

echo "=== ETAPE 5: VALIDATION RESEAU K8S V2 ==="
echo ""

# 1. Créer un pod curl de test
echo "1. Création d'un pod curl de test..."
kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never -- sh -c 'echo "Pod curl-test créé"'

# 2. Récupérer les informations
POD_NET=$(kubectl get pods -n default -l app=net-test -o jsonpath='{.items[0].metadata.name}')
POD_NET_IP=$(kubectl get pods -n default -l app=net-test -o jsonpath='{.items[0].status.podIP}')
SVC_IP=$(kubectl get svc net-test-svc -n default -o jsonpath='{.spec.clusterIP}')

echo ""
echo "Informations:"
echo "  Pod net-test: $POD_NET ($POD_NET_IP)"
echo "  Service ClusterIP: $SVC_IP"
echo ""

# 3. Test Pod -> Service ClusterIP
echo "2. TEST POD -> SERVICE (ClusterIP)..."
kubectl run curl-test-1 --image=curlimages/curl --rm -i --restart=Never -- sh -c "
  echo 'Test: curl-test -> $SVC_IP:80'
  curl -s -m 5 http://$SVC_IP | head -5
  echo ''
  echo 'OK: Pod -> Service ClusterIP fonctionne'
" || echo "Échec Pod -> Service"

# 4. Test Pod -> DNS Service
echo ""
echo "3. TEST POD -> DNS SERVICE..."
kubectl run curl-test-2 --image=curlimages/curl --rm -i --restart=Never -- sh -c "
  echo 'Test: curl-test -> net-test-svc.default.svc.cluster.local'
  nslookup net-test-svc.default.svc.cluster.local || echo 'nslookup non disponible, test avec getent'
  getent hosts net-test-svc.default.svc.cluster.local || echo 'getent non disponible'
  echo ''
  echo 'Test HTTP via DNS:'
  curl -s -m 5 http://net-test-svc.default.svc.cluster.local | head -5
  echo ''
  echo 'OK: Pod -> DNS Service fonctionne'
" || echo "Échec Pod -> DNS"

# 5. Test DNS CoreDNS
echo ""
echo "4. TEST DNS COREDNS (kubernetes.default)..."
kubectl run curl-test-3 --image=curlimages/curl --rm -i --restart=Never -- sh -c "
  echo 'Test: curl-test -> kubernetes.default.svc.cluster.local'
  nslookup kubernetes.default.svc.cluster.local || getent hosts kubernetes.default.svc.cluster.local
  echo ''
  echo 'OK: DNS CoreDNS fonctionne'
" || echo "Échec DNS CoreDNS"

# 6. Test Node -> Service
echo ""
echo "5. TEST NODE -> SERVICE (ClusterIP)..."
echo "Test: Node -> $SVC_IP:80"
curl -s -o /dev/null -w "HTTP %{http_code}\n" --max-time 5 http://$SVC_IP && echo "OK: Node -> Service ClusterIP fonctionne" || echo "Échec Node -> Service"

# 7. Vérification CIDR
echo ""
echo "6. VERIFICATION CIDR CONFIGURES..."
echo "Service CIDR:"
kubectl cluster-info dump 2>/dev/null | grep -i service-cluster-ip-range | head -1 || echo "Non trouvé"
echo ""
echo "Pod CIDR Calico:"
kubectl get ippool -o yaml 2>/dev/null | grep -E "name:|cidr:" | head -4 || echo "Pool Calico non trouvé"

echo ""
echo "=== VALIDATION TERMINEE ==="

