# 🚀 Commandes de Finalisation - Module 11

## 📋 Commandes à Exécuter sur install-01

Connectez-vous à install-01 et exécutez ces commandes dans l'ordre :

### 1. Exécuter les Migrations

```bash
export KUBECONFIG=/root/.kube/config

# Supprimer l'ancienne Job
kubectl delete job chatwoot-migrations -n chatwoot --ignore-not-found=true
sleep 3

# Récupérer l'image
IMAGE=$(kubectl get deployment chatwoot-web -n chatwoot -o jsonpath='{.spec.template.spec.containers[0].image}')
echo "Image: $IMAGE"

# Créer la Job de migrations
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

# Attendre la fin (peut prendre 5-10 minutes)
echo "Attente de la fin de la Job..."
kubectl wait --for=condition=complete job/chatwoot-migrations -n chatwoot --timeout=600s

# Vérifier les logs
kubectl logs -n chatwoot job/chatwoot-migrations --tail=50

# Si succès, supprimer la Job
kubectl delete job chatwoot-migrations -n chatwoot
```

### 2. Exécuter db:seed

```bash
# Créer la Job de seed
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

# Attendre la fin
kubectl wait --for=condition=complete job/chatwoot-seed -n chatwoot --timeout=300s

# Vérifier les logs
kubectl logs -n chatwoot job/chatwoot-seed --tail=50

# Supprimer la Job
kubectl delete job chatwoot-seed -n chatwoot
```

### 3. Redémarrer les Pods

```bash
# Redémarrer les Deployments
kubectl rollout restart deployment/chatwoot-web -n chatwoot
kubectl rollout restart deployment/chatwoot-worker -n chatwoot

# Attendre le démarrage
echo "Attente du démarrage des pods (90 secondes)..."
sleep 90

# Vérifier l'état
kubectl get pods -n chatwoot
kubectl get deployments -n chatwoot
```

### 4. Validation et Rapports

```bash
cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot

# Exécuter la validation
bash validate_module11.sh

# Générer les rapports
bash generate_reports.sh
```

### 5. Vérifier l'Accès

```bash
# Test interne
kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never --namespace=chatwoot -- \
  curl -sS http://chatwoot-web.chatwoot.svc.cluster.local:3000

# Test externe (si DNS configuré)
curl -k https://support.keybuzz.io
```

---

## 🔄 Script Automatique

Vous pouvez aussi exécuter le script automatique :

```bash
cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot
bash finaliser_module11.sh
```

Ou utiliser le script complet :

```bash
cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot
bash execute_finalisation.sh
```

---

## 📊 Vérifications Finales

```bash
# État des pods
kubectl get pods -n chatwoot

# État des Deployments
kubectl get deployments -n chatwoot

# Service
kubectl get service chatwoot-web -n chatwoot

# Ingress
kubectl get ingress chatwoot-ingress -n chatwoot

# Logs
kubectl logs -n chatwoot -l component=web --tail=50
kubectl logs -n chatwoot -l component=worker --tail=50
```

---

## 📝 Rapports

Une fois la validation terminée, les rapports seront disponibles dans :

- `/opt/keybuzz-installer-v2/reports/RAPPORT_VALIDATION_MODULE11_SUPPORT.md`
- `/opt/keybuzz-installer-v2/reports/RECAP_CHATGPT_MODULE11.md`

---

**Toutes les commandes sont prêtes à être exécutées !** ✅

