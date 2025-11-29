#!/bin/bash
# Script simple pour exécuter rapidement les étapes critiques

export KUBECONFIG=/root/.kube/config

echo "=== Module 11 - Exécution Rapide ==="

# Migrations
echo "1. Migrations..."
kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true
IMAGE=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.template.spec.containers[0].image}')

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: chatwoot-migrations
  namespace: chatwoot
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: chatwoot-migrations
        image: ${IMAGE}
        envFrom:
        - secretRef:
            name: chatwoot-secrets
        - configMapRef:
            name: chatwoot-config
        command: ["bundle", "exec", "rails", "db:migrate"]
EOF

echo "Attente migrations (600s)..."
kubectl wait --for=condition=complete job/chatwoot-migrations -n chatwoot --timeout=600s && \
  kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true && \
  echo "✅ Migrations OK" || echo "❌ Migrations échouées"

# Seed
echo "2. Seed..."
kubectl delete job chatwoot-seed -n chatwoot --ignore-not-found=true

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: chatwoot-seed
  namespace: chatwoot
spec:
  backoffLimit: 0
  template:
    spec:
      restartPolicy: Never
      containers:
      - name: chatwoot-seed
        image: ${IMAGE}
        envFrom:
        - secretRef:
            name: chatwoot-secrets
        - configMapRef:
            name: chatwoot-config
        command: ["bundle", "exec", "rails", "db:seed"]
EOF

kubectl wait --for=condition=complete job/chatwoot-seed -n chatwoot --timeout=300s && \
  kubectl delete job chatwoot-seed -n chatwoot --ignore-not-found=true && \
  echo "✅ Seed OK" || echo "⚠️ Seed échoué"

# Redémarrage
echo "3. Redémarrage..."
kubectl rollout restart deployment/chatwoot-web -n chatwoot
kubectl rollout restart deployment/chatwoot-worker -n chatwoot
sleep 90
echo "✅ Redémarrage OK"

# Validation
echo "4. Validation..."
cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot
bash validate_module11.sh && bash generate_reports.sh
echo "✅ Terminé"


