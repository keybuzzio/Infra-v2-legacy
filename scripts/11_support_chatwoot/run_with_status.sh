#!/bin/bash
#
# run_with_status.sh - Exécute la finalisation avec suivi de statut
#

set -euo pipefail

export KUBECONFIG=/root/.kube/config
STATUS_FILE="/tmp/module11_status.txt"
LOG_FILE="/tmp/module11_finalisation.log"

# Fonction pour écrire le statut
write_status() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$STATUS_FILE"
}

# Initialiser les fichiers
echo "=== Module 11 Finalisation - $(date) ===" > "$STATUS_FILE"
echo "" > "$LOG_FILE"

write_status "Démarrage de la finalisation"

# Étape 1 : Migrations
write_status "ÉTAPE 1/4 : Exécution des migrations"
kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true >> "$LOG_FILE" 2>&1
sleep 3

IMAGE=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.template.spec.containers[0].image}')
write_status "Image: $IMAGE"

kubectl apply -f - <<EOF >> "$LOG_FILE" 2>&1
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

write_status "Attente de la fin des migrations (max 10 minutes)..."
if kubectl wait --for=condition=complete job/chatwoot-migrations -n chatwoot --timeout=600s >> "$LOG_FILE" 2>&1; then
    write_status "✅ Migrations terminées avec succès"
    kubectl logs -n chatwoot job/chatwoot-migrations --tail=30 >> "$LOG_FILE" 2>&1
    kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true >> "$LOG_FILE" 2>&1
else
    write_status "❌ Migrations échouées"
    kubectl logs -n chatwoot job/chatwoot-migrations --tail=50 >> "$LOG_FILE" 2>&1
    write_status "ERREUR: Migrations échouées"
    exit 1
fi

# Étape 2 : Seed
write_status "ÉTAPE 2/4 : Exécution db:seed"
kubectl delete job chatwoot-seed -n chatwoot --ignore-not-found=true >> "$LOG_FILE" 2>&1
sleep 2

kubectl apply -f - <<EOF >> "$LOG_FILE" 2>&1
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

write_status "Attente de la fin du seed (max 5 minutes)..."
if kubectl wait --for=condition=complete job/chatwoot-seed -n chatwoot --timeout=300s >> "$LOG_FILE" 2>&1; then
    write_status "✅ Seed terminé avec succès"
    kubectl logs -n chatwoot job/chatwoot-seed --tail=30 >> "$LOG_FILE" 2>&1
    kubectl delete job chatwoot-seed -n chatwoot --ignore-not-found=true >> "$LOG_FILE" 2>&1
else
    write_status "⚠️ Seed échoué (peut être normal si déjà exécuté)"
    kubectl logs -n chatwoot job/chatwoot-seed --tail=50 >> "$LOG_FILE" 2>&1
fi

# Étape 3 : Redémarrage
write_status "ÉTAPE 3/4 : Redémarrage des pods"
kubectl rollout restart deployment/chatwoot-web -n chatwoot >> "$LOG_FILE" 2>&1
kubectl rollout restart deployment/chatwoot-worker -n chatwoot >> "$LOG_FILE" 2>&1
write_status "Attente du démarrage (90 secondes)..."
sleep 90

kubectl get pods -n chatwoot >> "$LOG_FILE" 2>&1
kubectl get deployments -n chatwoot >> "$LOG_FILE" 2>&1
write_status "✅ Pods redémarrés"

# Étape 4 : Validation
write_status "ÉTAPE 4/4 : Validation et rapports"
cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot

if bash validate_module11.sh >> "$LOG_FILE" 2>&1; then
    write_status "✅ Validation terminée"
else
    write_status "⚠️ Validation avec erreurs"
fi

bash generate_reports.sh >> "$LOG_FILE" 2>&1
write_status "✅ Rapports générés"

write_status "✅ FINALISATION TERMINÉE"
write_status "Logs: $LOG_FILE"
write_status "Rapports: /opt/keybuzz-installer-v2/reports/"


