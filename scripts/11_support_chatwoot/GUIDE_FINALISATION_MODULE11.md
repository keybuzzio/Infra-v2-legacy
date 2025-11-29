# 🚀 Guide de Finalisation - Module 11 : Support KeyBuzz (Chatwoot)

## 📋 État Actuel

✅ **Terminé** :
- Base de données `chatwoot` créée
- Extension `pg_stat_statements` créée
- Utilisateur `chatwoot` avec droits superuser
- Migration buggy marquée comme exécutée
- Scripts créés et déployés
- ConfigMap et Secret créés
- Deployments déployés

⏳ **À finaliser** :
- Exécution des migrations Rails
- Exécution de db:seed
- Redémarrage des pods
- Validation complète
- Génération des rapports

---

## 🔧 Commandes à Exécuter

### Étape 1 : Exécuter les Migrations

```bash
export KUBECONFIG=/root/.kube/config
cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot

# Supprimer l'ancienne Job si elle existe
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

### Étape 2 : Exécuter db:seed

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

### Étape 3 : Redémarrer les Pods

```bash
# Redémarrer les Deployments
kubectl rollout restart deployment/chatwoot-web -n chatwoot
kubectl rollout restart deployment/chatwoot-worker -n chatwoot

# Attendre le démarrage (60 secondes)
echo "Attente du démarrage des pods..."
sleep 60

# Vérifier l'état
kubectl get pods -n chatwoot -w
# Appuyer sur Ctrl+C quand tous les pods sont Running

# Vérifier les Deployments
kubectl get deployments -n chatwoot
```

### Étape 4 : Validation Complète

```bash
cd /opt/keybuzz-installer-v2/scripts/11_support_chatwoot

# Exécuter la validation
bash validate_module11.sh

# Générer les rapports
bash generate_reports.sh
```

### Étape 5 : Vérifier l'Accès

```bash
# Test interne
kubectl run curl-test --image=curlimages/curl --rm -i --restart=Never --namespace=chatwoot -- \
  curl -sS http://chatwoot-web.chatwoot.svc.cluster.local:3000

# Test externe (si DNS configuré)
curl -k https://support.keybuzz.io
```

---

## 📊 Vérifications Finales

### 1. État des Pods
```bash
kubectl get pods -n chatwoot
```
**Attendu** : Tous les pods en `Running`

### 2. État des Deployments
```bash
kubectl get deployments -n chatwoot
```
**Attendu** : `chatwoot-web` et `chatwoot-worker` avec tous les replicas Ready

### 3. Service
```bash
kubectl get service chatwoot-web -n chatwoot
```
**Attendu** : Service ClusterIP sur le port 3000

### 4. Ingress
```bash
kubectl get ingress chatwoot-ingress -n chatwoot
```
**Attendu** : Ingress configuré pour `support.keybuzz.io`

### 5. Logs
```bash
# Logs web
kubectl logs -n chatwoot -l component=web --tail=50

# Logs worker
kubectl logs -n chatwoot -l component=worker --tail=50
```
**Attendu** : Pas d'erreurs critiques

---

## 🐛 Dépannage

### Problème : Pods en CrashLoopBackOff

**Cause** : Migrations non exécutées ou erreur de configuration

**Solution** :
1. Vérifier les logs : `kubectl logs -n chatwoot <pod-name>`
2. Réexécuter les migrations (Étape 1)
3. Vérifier les variables d'environnement : `kubectl describe pod -n chatwoot <pod-name>`

### Problème : Job de migrations échoue

**Cause** : Extension PostgreSQL manquante ou permissions insuffisantes

**Solution** :
```bash
source /opt/keybuzz-installer-v2/credentials/postgres.env
export PGPASSWORD="${POSTGRES_SUPERPASS}"
psql -h 10.0.0.10 -p 5432 -U kb_admin -d chatwoot -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"
psql -h 10.0.0.10 -p 5432 -U kb_admin -d postgres -c "ALTER USER chatwoot WITH SUPERUSER;"
```

### Problème : Service non accessible

**Cause** : Pods non démarrés ou erreur de configuration

**Solution** :
1. Vérifier l'état des pods
2. Vérifier les logs
3. Vérifier le Service : `kubectl describe service chatwoot-web -n chatwoot`

---

## ✅ Checklist Finale

- [ ] Migrations exécutées avec succès
- [ ] db:seed exécuté avec succès
- [ ] Tous les pods en Running
- [ ] Service ClusterIP fonctionnel
- [ ] Ingress configuré pour support.keybuzz.io
- [ ] Test de connectivité interne OK
- [ ] Validation complète exécutée
- [ ] Rapports générés

---

## 📝 Rapports Générés

Une fois la validation terminée, les rapports suivants seront disponibles :

- `/opt/keybuzz-installer-v2/reports/RAPPORT_VALIDATION_MODULE11_SUPPORT.md`
- `/opt/keybuzz-installer-v2/reports/RECAP_CHATGPT_MODULE11.md`

---

**Module 11 - Support KeyBuzz (Chatwoot) - Guide de Finalisation** ✅

