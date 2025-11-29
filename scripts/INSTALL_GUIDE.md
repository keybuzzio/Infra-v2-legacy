# Guide d'exécution des scripts sur install-01

## Contexte

Vous êtes connecté à install-01 via Cursor Remote SSH. Tous les scripts que je crée peuvent être exécutés directement dans le terminal Cursor.

## Workflow recommandé

### 1. Création des scripts (par moi)

Je crée les scripts dans `Infra/scripts/`

### 2. Transfert vers install-01

**Option A : Via Git (Recommandé)**
```bash
# Sur install-01, cloner le dépôt
cd /opt
git clone https://github.com/keybuzzio/Infra.git keybuzz-installer
cd keybuzz-installer
```

**Option B : Via SCP depuis Windows**
```powershell
# Depuis PowerShell
scp -r Infra\* root@91.98.128.153:/opt/keybuzz-installer/
```

**Option C : Copier-coller dans Cursor**
- Ouvrir le fichier dans Cursor
- Copier le contenu
- Créer le fichier sur install-01 via le terminal Cursor

### 3. Exécution des scripts

Dans le terminal Cursor (déjà connecté à install-01) :

```bash
cd /opt/keybuzz-installer
chmod +x scripts/**/*.sh
./scripts/identify_server.sh
```

## Commandes que je peux exécuter pour vous

Quand je dis "je vais exécuter", je vais vous donner les commandes à copier-coller dans le terminal Cursor, ou créer des scripts que vous pourrez exécuter.

## Exemple : Script d'identification

Je crée le script → Vous le copiez dans Cursor → Vous l'exécutez

Ou je vous donne directement la commande à exécuter dans le terminal Cursor.


