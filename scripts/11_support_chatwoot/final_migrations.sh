#!/bin/bash
export KUBECONFIG=/root/.kube/config

echo "=== Suppression Job existante ==="
kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true
sleep 3

echo ""
echo "=== Récupération image ==="
IMAGE=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Image: $IMAGE"

echo ""
echo "=== Création Job migrations ==="
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
echo "=== Attente Job (10 minutes max) ==="
if kubectl wait --for=condition=complete job/chatwoot-migrations -n chatwoot --timeout=600s 2>/dev/null; then
    echo "✅ Job terminée avec succès"
    echo ""
    echo "=== Logs ==="
    kubectl logs -n chatwoot job/chatwoot-migrations --tail=50
    kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true
else
    echo "❌ Job échouée ou timeout"
    echo ""
    echo "=== Logs ==="
    kubectl logs -n chatwoot job/chatwoot-migrations --tail=50
    exit 1
fi

