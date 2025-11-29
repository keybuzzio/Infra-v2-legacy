# Guide : Utiliser Pageant pour automatiser les connexions SSH

## Étape 1 : Charger votre clé dans Pageant (UNE SEULE FOIS)

Pageant est déjà actif sur votre système. Maintenant, chargez votre clé :

### Méthode A : Via l'interface Pageant

1. **Trouvez l'icône Pageant** dans la barre des tâches Windows (en bas à droite, près de l'horloge)
2. **Cliquez avec le bouton droit** sur l'icône Pageant
3. **Sélectionnez "Add Key"** (ou "Ajouter une clé")
4. **Naviguez vers votre clé SSH** : `C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra`
5. **Entrez votre passphrase UNE FOIS**
6. La clé est maintenant chargée dans Pageant

### Méthode B : Via la ligne de commande

Si vous avez un fichier `.ppk` :

```powershell
# Convertir la clé OpenSSH en .ppk si nécessaire
# Ou utiliser directement le .ppk si vous en avez un

# Charger dans Pageant via ligne de commande
pageant.exe "C:\Users\ludov\Mon Drive\keybuzzio\SSH\keybuzz_infra"
```

**Note** : Si vous avez seulement une clé OpenSSH (pas .ppk), vous devez d'abord la convertir ou utiliser l'interface graphique.

## Étape 2 : Vérifier que la clé est chargée

```powershell
# Cliquez avec le bouton droit sur l'icône Pageant
# Vous devriez voir votre clé dans la liste
```

## Étape 3 : Lancer les tests

Une fois la clé chargée dans Pageant :

```powershell
.\lancer_tests_final.ps1
```

**Plus besoin d'entrer le passphrase !** Pageant le gère automatiquement.

## Avantages de Pageant

- ✅ Passphrase demandé UNE SEULE FOIS (au chargement de la clé)
- ✅ Toutes les connexions SSH suivantes utilisent automatiquement la clé
- ✅ Compatible avec PuTTY, plink, et autres outils SSH
- ✅ La clé reste chargée jusqu'à la fermeture de Pageant ou redémarrage Windows

