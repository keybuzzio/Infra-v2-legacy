# Résumé : Comment Lancer les Tests sur install-01

## 📋 Situation Actuelle

- **Pageant est ACTIF** sur votre système (PID: 27868)
- Vous utilisez **PuTTY** sous Windows
- Clé SSH : `SSH/keybuzz_infra`

---

## 🎯 Option Recommandée : Utiliser Pageant

### Avantages
- ✅ Passphrase demandé **UNE SEULE FOIS**
- ✅ Toutes les connexions suivantes automatiques
- ✅ Plus rapide et pratique

### Étapes

1. **Charger la clé dans Pageant** (une seule fois) :
   - Cliquez sur l'icône **Pageant** dans la barre des tâches (en bas à droite, près de l'horloge)
   - **Clic droit** sur l'icône
   - Sélectionnez **"Add Key"** ou **"Ajouter une clé"**
   - Naviguez vers : `C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra`
   - Entrez votre **passphrase UNE FOIS**
   - La clé est maintenant chargée !

2. **Lancer les tests** :
   ```powershell
   .\lancer_tests_final.ps1
   ```
   Plus besoin de passphrase ! 🎉

---

## 🔄 Option Alternative : plink avec fenêtre PuTTY

Si vous préférez ne pas utiliser Pageant :

```powershell
.\lancer_tests_avec_plink.ps1
```

**Avantage** : Ouvre une fenêtre PuTTY interactive pour entrer le passphrase

**Inconvénient** : Devra entrer le passphrase à chaque fois

---

## 📝 Scripts Disponibles

1. **`lancer_tests_final.ps1`** ⭐ RECOMMANDÉ
   - Utilise Pageant si disponible
   - Fallback sur plink ou ssh si besoin

2. **`lancer_tests_avec_plink.ps1`**
   - Utilise plink (PuTTY)
   - Ouvre une fenêtre pour le passphrase

3. **`lancer_tests_simple.ps1`**
   - Utilise ssh standard
   - Demande le passphrase dans le terminal

4. **`00_test_complet_infrastructure_haproxy01.sh`**
   - Script de test complet (doit être sur install-01)
   - Teste tous les modules de l'infrastructure

---

## 🔍 Vérification Rapide

Pour vérifier si votre clé est chargée dans Pageant :

```powershell
# Clic droit sur l'icône Pageant dans la barre des tâches
# Vous devriez voir votre clé dans la liste
```

---

## 📚 Documentation Complète

- **GUIDE_PAGEANT.md** - Guide détaillé pour Pageant
- **GUIDE_CONFIGURATION_SSH.md** - Configuration SSH complète
- **COMMENT_LANCER_LES_TESTS.md** - Instructions détaillées

