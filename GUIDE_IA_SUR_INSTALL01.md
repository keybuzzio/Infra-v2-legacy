# Guide : Utiliser l'IA sur install-01

## 🎯 Problème

Code-Server (VS Code Server) est un IDE web, mais il n'inclut **pas** l'IA Cursor par défaut.

## ✅ Solutions disponibles

---

## 🚀 Solution 1 : VS Code Remote SSH depuis Windows (Recommandé)

### Avantages
- ✅ **IA Cursor complète** disponible sur Windows
- ✅ **Accès direct aux fichiers** sur install-01
- ✅ **Terminal intégré** vers install-01
- ✅ **Extensions VS Code** fonctionnent
- ✅ **Meilleure expérience** que Code-Server

### Configuration

#### Étape 1 : Installer VS Code sur Windows

1. Télécharger VS Code : https://code.visualstudio.com/
2. Installer VS Code

#### Étape 2 : Installer l'extension Remote SSH

1. Ouvrir VS Code
2. Extensions (Ctrl+Shift+X)
3. Chercher "Remote - SSH"
4. Installer "Remote - SSH" (par Microsoft)

#### Étape 3 : Configurer la connexion SSH

1. Dans VS Code, appuyer sur `F1`
2. Taper "Remote-SSH: Connect to Host"
3. Sélectionner "Configure SSH Hosts..."
4. Choisir votre fichier de config SSH (ex: `C:\Users\ludov\.ssh\config`)

5. Ajouter la configuration pour install-01 :

```
Host install-01
    HostName 91.98.128.153
    User root
    IdentityFile C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra
    StrictHostKeyChecking accept-new
```

6. Sauvegarder

#### Étape 4 : Se connecter

1. `F1` → "Remote-SSH: Connect to Host"
2. Sélectionner "install-01"
3. Entrer la passphrase SSH si demandée
4. VS Code se connecte à install-01 !

#### Étape 5 : Ouvrir le dossier

1. File → Open Folder
2. Naviguer vers : `/opt/keybuzz-installer`
3. Vous avez maintenant accès à tous vos fichiers avec l'IA Cursor !

### Utiliser Cursor avec Remote SSH

**Cursor** supporte aussi Remote SSH ! 

1. Installer Cursor (si pas déjà fait)
2. Installer l'extension "Remote - SSH" dans Cursor
3. Se connecter à install-01 de la même manière
4. **Vous avez l'IA Cursor directement sur install-01 !**

---

## 🚀 Solution 2 : Extensions IA dans Code-Server

### GitHub Copilot dans Code-Server

Code-Server supporte GitHub Copilot !

#### Configuration

1. **Ouvrir Code-Server** : `http://91.98.128.153:8080`

2. **Installer GitHub Copilot** :
   - Extensions (Ctrl+Shift+X)
   - Chercher "GitHub Copilot"
   - Installer

3. **Authentifier** :
   - Vous devrez vous connecter avec votre compte GitHub
   - Autoriser GitHub Copilot

4. **Utiliser** :
   - Commencer à taper du code
   - Copilot suggère automatiquement
   - `Tab` pour accepter, `Esc` pour refuser

### Autres extensions IA pour Code-Server

- **Codeium** : IA gratuite (alternative à Copilot)
- **Tabnine** : IA pour autocomplétion
- **GitHub Copilot Chat** : Chat avec l'IA

---

## 🚀 Solution 3 : Cursor directement sur install-01 (Non disponible)

**Note** : Cursor n'est pas disponible pour Linux en mode serveur/headless. Cursor est un éditeur de bureau qui nécessite une interface graphique.

**Alternatives** :
- Utiliser Cursor sur Windows avec Remote SSH (Solution 1) ✅
- Utiliser Code-Server avec GitHub Copilot (Solution 2) ✅

---

## 📊 Comparaison des solutions

| Solution | IA Cursor | Facilité | Performance | Recommandation |
|----------|-----------|----------|------------|----------------|
| **VS Code/Cursor Remote SSH** | ✅ Complète | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ **MEILLEURE** |
| **Code-Server + Copilot** | ⚠️ Copilot (différent) | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ Bonne alternative |
| **Code-Server + Codeium** | ⚠️ Codeium (différent) | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ Alternative gratuite |

---

## 🎯 Recommandation

### Pour vous : **Cursor avec Remote SSH**

1. **Installer Cursor** sur Windows (si pas déjà fait)
2. **Installer l'extension Remote SSH** dans Cursor
3. **Se connecter à install-01** via SSH
4. **Ouvrir `/opt/keybuzz-installer`**
5. **Vous avez l'IA Cursor complète** directement sur les fichiers du serveur !

### Avantages de cette approche

- ✅ **IA Cursor native** (pas Copilot)
- ✅ **Tous les fichiers** sur install-01 accessibles
- ✅ **Terminal intégré** vers install-01
- ✅ **Exécution de scripts** directement depuis Cursor
- ✅ **Meilleure expérience** que Code-Server

---

## 🔧 Configuration détaillée : Cursor Remote SSH

### Étape 1 : Vérifier que Cursor est installé

Cursor devrait déjà être installé sur votre Windows.

### Étape 2 : Installer Remote SSH dans Cursor

1. Ouvrir Cursor
2. Extensions (Ctrl+Shift+X)
3. Chercher "Remote - SSH"
4. Installer "Remote - SSH" (par Microsoft)

### Étape 3 : Configurer SSH

1. Créer/modifier `C:\Users\ludov\.ssh\config` :

```
Host install-01
    HostName 91.98.128.153
    User root
    IdentityFile C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra
    StrictHostKeyChecking accept-new
    ServerAliveInterval 60
    ServerAliveCountMax 3
```

### Étape 4 : Se connecter

1. Dans Cursor : `F1` → "Remote-SSH: Connect to Host"
2. Sélectionner "install-01"
3. Entrer la passphrase SSH
4. Cursor se connecte !

### Étape 5 : Ouvrir le dossier

1. File → Open Folder
2. `/opt/keybuzz-installer`
3. **C'est tout ! Vous avez l'IA Cursor sur install-01 !**

---

## 💡 Astuce : Utiliser les deux

Vous pouvez utiliser **les deux** :

- **Code-Server** : Pour accès rapide depuis n'importe quel navigateur
- **Cursor Remote SSH** : Pour développement avec IA complète

Ils travaillent sur les **mêmes fichiers** sur install-01 !

---

## 🚨 Dépannage

### Erreur : "Could not establish connection"

**Solution** :
- Vérifier que SSH fonctionne : `ssh root@91.98.128.153`
- Vérifier le chemin de la clé SSH dans la config
- Vérifier que la passphrase est correcte

### Erreur : "Permission denied"

**Solution** :
- Vérifier les permissions de la clé SSH : `chmod 600` sur la clé
- Vérifier que la clé est dans `authorized_keys` sur install-01

### Lenteur de connexion

**Solution** :
- Utiliser `ServerAliveInterval` dans la config SSH
- Vérifier la connexion réseau
- Code-Server peut être plus rapide pour les petits changements

---

## ✅ Résumé

**Pour avoir l'IA Cursor sur install-01** :

1. ✅ **Meilleure solution** : Cursor avec Remote SSH
   - Installer Remote SSH dans Cursor
   - Se connecter à install-01
   - Ouvrir `/opt/keybuzz-installer`
   - **IA Cursor complète disponible !**

2. ✅ **Alternative** : Code-Server avec GitHub Copilot
   - Installer Copilot dans Code-Server
   - Fonctionne mais différent de Cursor

3. ❌ **Non disponible** : Cursor directement sur install-01 (pas de version serveur)

---

## 🎯 Prochaines étapes

1. **Installer Remote SSH dans Cursor**
2. **Configurer la connexion SSH**
3. **Se connecter à install-01**
4. **Ouvrir `/opt/keybuzz-installer`**
5. **Profiter de l'IA Cursor sur install-01 !**








