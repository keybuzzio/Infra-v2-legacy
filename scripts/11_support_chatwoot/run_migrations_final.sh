#!/bin/bash
set -e
export KUBECONFIG=/root/.kube/config

echo "=== ÉTAPE 1 : RELANCE MIGRATIONS ==="
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

echo ""
echo "Job créée, attente 300 secondes..."
sleep 300

echo ""
echo "=== ÉTAT JOB ==="
kubectl get job chatwoot-migrations -n chatwoot

echo ""
echo "=== LOGS (dernières 50 lignes) ==="
kubectl logs -n chatwoot job/chatwoot-migrations --tail=50 2>&1 | tail -50

JOB_STATUS=$(kubectl get job chatwoot-migrations -n chatwoot -o jsonpath='{.status.conditions[0].type}' 2>/dev/null || echo "Unknown")
if [ "$JOB_STATUS" = "Complete" ]; then
    echo ""
    echo "✅ Migrations terminées avec succès"
    exit 0
else
    echo ""
    echo "⚠️ Job status: $JOB_STATUS"
    exit 1
fi

