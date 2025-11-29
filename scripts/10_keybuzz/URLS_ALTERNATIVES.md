# URLs Alternatives pour KeyBuzz API & Front

## 📋 URLs Originales (Context.txt)

Selon Context.txt, les URLs prévues sont :
- **UI KeyBuzz** : `app.keybuzz.io` ⚠️ **DÉJÀ UTILISÉ (Go High Level)**
- **API KeyBuzz** : `api.keybuzz.io` ⚠️ **DÉJÀ UTILISÉ (Go High Level)**

## 🔄 Alternatives Proposées

### Option 1 : URLs avec préfixe "platform"
- **UI KeyBuzz** : `platform.keybuzz.io`
- **API KeyBuzz** : `platform-api.keybuzz.io`

### Option 2 : URLs avec préfixe "dashboard"
- **UI KeyBuzz** : `dashboard.keybuzz.io`
- **API KeyBuzz** : `api-dashboard.keybuzz.io` ou `dashboard-api.keybuzz.io`

### Option 3 : URLs avec préfixe "core"
- **UI KeyBuzz** : `core.keybuzz.io`
- **API KeyBuzz** : `core-api.keybuzz.io`

### Option 4 : URLs avec préfixe "saas"
- **UI KeyBuzz** : `saas.keybuzz.io`
- **API KeyBuzz** : `saas-api.keybuzz.io`

### Option 5 : URLs courtes
- **UI KeyBuzz** : `kb.keybuzz.io`
- **API KeyBuzz** : `kb-api.keybuzz.io`

### Option 6 : URLs avec préfixe "console"
- **UI KeyBuzz** : `console.keybuzz.io`
- **API KeyBuzz** : `console-api.keybuzz.io`

## 📝 Liste Complète des URLs KeyBuzz (selon Context.txt)

### ✅ Core KeyBuzz SaaS
- `app.keybuzz.io` → UI KeyBuzz (Frontend) ⚠️ **DÉJÀ UTILISÉ**
- `api.keybuzz.io` → API Backend KeyBuzz ⚠️ **DÉJÀ UTILISÉ**
- `support.keybuzz.io` → Chatwoot rebrandé
- `ai.keybuzz.io` → Front IA / Console IA (optionnel)

### ✅ Automations & Workflows
- `n8n.keybuzz.io` → Orchestration Workflows n8n
- `hooks.keybuzz.io` → Endpoints webhooks entrants
- `events.keybuzz.io` → Future gateway RabbitMQ HTTP-in

### ✅ Analytics & Dashboard
- `analytics.keybuzz.io` → Superset (BI, dashboards)
- `monitoring.keybuzz.io` → Grafana
- `prometheus.keybuzz.io` → Prometheus (optionnel)

### ✅ IA / LLM / Vector / RAG
- `llm.keybuzz.io` → LiteLLM Proxy (multi-LLM)
- `rag.keybuzz.io` → API RAG interne (optionnel)
- `vector.keybuzz.io` → Qdrant / Vector DB UI (optionnel)
- `embeddings.keybuzz.io` → Service embeddings dédié (optionnel)

### ✅ Workplace KeyBuzz
- `workplace.keybuzz.io` → Workplace interne
- `chat.keybuzz.io` → Chat interne (WebSocket)
- `docs.keybuzz.io` → Zone documentation
- `academy.keybuzz.io` → KeyBuzz Academy

### ✅ Sécurité, Secrets & Administration
- `vault.keybuzz.io` → HashiCorp Vault
- `siem.keybuzz.io` → SIEM interne / Wazuh
- `admin.keybuzz.io` → Backoffice KeyBuzz
- `status.keybuzz.io` → Page statut publique

### ✅ Stockage, S3 et MinIO
- `s3.keybuzz.io` → MinIO Console
- `storage.keybuzz.io` → Alias S3 public (optionnel)

### ✅ ERPNext
- `erp.keybuzz.io` → ERPNext (Web)
- `erp-api.keybuzz.io` → API REST ERPNext (optionnel)

### ✅ Mails KeyBuzz
- `mail.keybuzz.io` → MTA / IMAP
- `mx1.keybuzz.io` → MX primaire
- `mx2.keybuzz.io` → MX secondaire
- `smtp.keybuzz.io` → SMTP sortant

## 🎯 Recommandation

Pour KeyBuzz API & Front, je recommande **Option 1** :
- **UI KeyBuzz** : `platform.keybuzz.io`
- **API KeyBuzz** : `platform-api.keybuzz.io`

**Avantages** :
- ✅ Clair et professionnel
- ✅ Indique que c'est la plateforme principale
- ✅ Facile à retenir
- ✅ Pas de conflit avec Go High Level

## ⚙️ Modification des Scripts

Une fois que vous avez choisi les URLs, je mettrai à jour :
1. `10_keybuzz_03_configure_ingress.sh` (Ingress)
2. `README.md` (Documentation)
3. Tous les scripts qui référencent ces URLs

