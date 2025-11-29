#!/bin/bash
set -e
export KUBECONFIG=/root/.kube/config

echo "=============================================================="
echo " [KeyBuzz] Module 11 - Finalisation"
echo "=============================================================="
echo ""

# Étape 1 : Migrations
echo "=== ÉTAPE 1 : MIGRATIONS ==="
kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true
sleep 3

IMAGE=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Image: $IMAGE"

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: chatwoot-migrations
  namespace: chatwoot
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: chatwoot-migrations
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
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
EOF

echo "Job créée, attente 600 secondes..."
if kubectl wait --for=condition=complete job/chatwoot-migrations -n chatwoot --timeout=600s 2>&1; then
    echo "✅ Migrations OK"
    kubectl logs -n chatwoot job/chatwoot-migrations --tail=30
    kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true
else
    echo "❌ Migrations échouées"
    kubectl logs -n chatwoot job/chatwoot-migrations --tail=50
    exit 1
fi

echo ""
echo "=== ÉTAPE 2 : SEED ==="
kubectl delete job chatwoot-seed -n chatwoot --ignore-not-found=true
sleep 2

kubectl apply -f - <<EOF
apiVersion: batch/v1
kind: Job
metadata:
  name: chatwoot-seed
  namespace: chatwoot
spec:
  backoffLimit: 0
  template:
    metadata:
      labels:
        app: chatwoot-seed
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
        resources:
          requests:
            memory: "512Mi"
            cpu: "250m"
          limits:
            memory: "2Gi"
            cpu: "1000m"
EOF

echo "Attente 300 secondes..."
if kubectl wait --for=condition=complete job/chatwoot-seed -n chatwoot --timeout=300s 2>&1; then
    echo "✅ Seed OK"
    kubectl delete job chatwoot-seed -n chatwoot --ignore-not-found=true
else
    echo "⚠️ Seed échoué (peut être normal si déjà exécuté)"
fi

echo ""
echo "=== ÉTAPE 3 : REDÉMARRAGE ==="
kubectl rollout restart deployment/chatwoot-web -n chatwoot
kubectl rollout restart deployment/chatwoot-worker -n chatwoot
echo "Attente 90 secondes..."
sleep 90
kubectl get pods -n chatwoot
kubectl get deployments -n chatwoot

echo ""
echo "=== ÉTAPE 4 : VALIDATION ==="
cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot
bash validate_module11.sh
bash generate_reports.sh

echo ""
echo "✅ Module 11 finalisé !"

